/**
 *   @name: EnvioCorreoPlantilla
 *   @version: 1.0
 *   @creation date: 12/11/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Acción para Flows que envía una plantilla de correo UNA sola vez a una dirección (sin mandarla
 *                 además al contacto/usuario de la plantilla, que duplicaba el correo) y, si se pide, con los archivos
 *                 del registro adjuntos.
 */
public with sharing class EnvioCorreoPlantilla {

	// Tamaño máximo de los adjuntos por correo (el límite de Salesforce es 25 MB con la codificación).
	@TestVisible
	// El contenido de los PDFs se carga en memoria: se limita para no pasar el límite de memoria de Apex (6 MB).
	private static final Integer MAX_ADJUNTOS_BYTES = Integer.valueOf(4.5 * 1024 * 1024);

	public class Solicitud {
		@InvocableVariable(label='Plantilla (nombre API)' required=true)
		public String plantilla;
		@InvocableVariable(label='Correo del destinatario' description='Si viene vacío se usa el correo del contacto o usuario.')
		public String correo;
		@InvocableVariable(label='Contacto o usuario (para los campos de la plantilla)')
		public Id destinatarioId;
		@InvocableVariable(label='Registro relacionado (póliza u oportunidad)')
		public Id registroId;
		@InvocableVariable(label='Adjuntar los archivos del registro')
		public Boolean adjuntarArchivos;
		@InvocableVariable(label='Remitente (dirección de toda la organización)')
		public String remitente;
		@InvocableVariable(label='Prompt de IA que redacta el correo (opcional)' description='Nombre API del prompt de Prompt Builder (por ejemplo Correo_Cotizacion_Cliente). Si la IA falla se usa la plantilla.')
		public String promptIA;
	}

	public class Resultado {
		@InvocableVariable(label='Enviado')
		public Boolean enviado;
		@InvocableVariable(label='Mensaje')
		public String mensaje;
	}

	/**
	 * @creation date: 12/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Envía cada solicitud como un solo correo a una sola dirección. Las direcciones repetidas en la misma
	 *               llamada (mismo registro y plantilla) se envían una vez.
	 * @param solicitudes: plantilla, destinatario, registro y si se adjuntan sus archivos.
	 * @return Un resultado por solicitud (enviado y mensaje).
	 */
	// Direcciones a las que ya se envió en esta transacción por registro: el agente y el cliente del flujo se envían en
	// dos acciones de la misma transacción, y la misma dirección no debe recibir dos correos.
	private static Set<String> enviados = new Set<String>();

	@InvocableMethod(label='Enviar correo con plantilla (una vez, con adjuntos)' category='Correo')
	public static List<Resultado> enviar(List<Solicitud> solicitudes) {
		List<Resultado> resultados = new List<Resultado>();
		for (Solicitud s : solicitudes) {
			Resultado r = new Resultado();
			r.enviado = false;
			try {
				String correo = correoDestino(s);
				if (String.isBlank(correo)) {
					r.mensaje = 'El destinatario no tiene correo.';
				} else {
					String llave = (correo + '|' + s.registroId).toLowerCase();
					if (enviados.contains(llave)) {
						r.enviado = true;
						r.mensaje = 'Ya se había enviado a ' + correo + '.';
					} else {
						r.mensaje = enviarUno(s, correo);
						r.enviado = true;
						enviados.add(llave);
					}
				}
			} catch (Exception e) {
				r.mensaje = 'No se pudo enviar el correo: ' + e.getMessage();
			}
			resultados.add(r);
		}
		return resultados;
	}

	// Dirección a la que se envía: la indicada o, si no hay, la del contacto/usuario.
	@TestVisible
	private static String correoDestino(Solicitud s) {
		if (String.isNotBlank(s.correo)) { return s.correo.trim(); }
		if (s.destinatarioId == null) { return null; }
		String tipo = s.destinatarioId.getSObjectType().getDescribe().getName();
		if (tipo == 'Contact') {
			List<Contact> c = [SELECT Email FROM Contact WHERE Id = :s.destinatarioId LIMIT 1];
			return c.isEmpty() ? null : c[0].Email;
		}
		if (tipo == 'User') {
			List<User> u = [SELECT Email FROM User WHERE Id = :s.destinatarioId LIMIT 1];
			return u.isEmpty() ? null : u[0].Email;
		}
		return null;
	}

	private static String enviarUno(Solicitud s, String correo) {
		List<EmailTemplate> tpls = [SELECT Id, HtmlValue FROM EmailTemplate WHERE DeveloperName = :s.plantilla LIMIT 1];
		if (tpls.isEmpty()) { throw new CorreoException('No existe la plantilla ' + s.plantilla + '.'); }
		String aviso = '';
		List<Messaging.EmailFileAttachment> adjuntos = new List<Messaging.EmailFileAttachment>();
		if (s.adjuntarArchivos == true && s.registroId != null) {
			List<Id> versiones = new List<Id>();
			Integer omitidos = archivosDe(s.registroId, versiones);
			adjuntos = adjuntosDe(versiones);
			if (omitidos > 0) { aviso = ', ' + omitidos + ' PDF(s) no se adjuntaron por tamaño'; }
		}
		Messaging.SingleEmailMessage m = null;
		String redaccion = '';
		// Cotización de Auto individual: lleva su propio diseño (el mismo para el cliente y el agente), sin IA.
		CorreoOportunidadIA.Correo deAuto = CorreoCotizacionAuto.armar(s.registroId);
		if (deAuto != null) {
			m = new Messaging.SingleEmailMessage();
			m.setSubject(deAuto.asunto);
			m.setHtmlBody(deAuto.html);
			m.setReplyTo(CorreoCotizacionAuto.RESPUESTA);
		} else if (String.isNotBlank(s.promptIA) && s.registroId != null) {
			try {
				List<String> nombres = new List<String>();
				for (Messaging.EmailFileAttachment a : adjuntos) { nombres.add(a.getFileName()); }
				CorreoOportunidadIA.Correo ia = CorreoOportunidadIA.generar(s.promptIA, s.registroId, s.destinatarioId, nombres);
				m = new Messaging.SingleEmailMessage();
				m.setSubject(ia.asunto);
				// El texto de la IA va dentro del diseño de la plantilla (banner, imágenes y pie de Avanza).
				String enPlantilla = enDisenoDePlantilla(tpls[0].HtmlValue, ia.cuerpo);
				m.setHtmlBody(enPlantilla != null ? enPlantilla : ia.html);
				redaccion = ' (redactado con IA)';
			} catch (Exception e) {
				// Sin la IA se manda la plantilla de siempre.
				redaccion = ' (con la plantilla porque la IA no respondió: ' + String.valueOf(e.getMessage()).left(150) + ')';
				m = null;
			}
		}
		if (m == null) {
			m = renderizar(tpls[0].Id, s.destinatarioId, s.registroId);
		}
		if (deAuto == null && m.getHtmlBody() != null) { m.setHtmlBody(conRamo(m.getHtmlBody(), ramoDe(s.registroId))); }
		// Solo a la dirección: sin setTargetObjectId, que lo mandaría otra vez al contacto/usuario.
		m.setToAddresses(new List<String>{ correo });
		m.setSaveAsActivity(false);
		if (String.isNotBlank(s.remitente)) {
			List<OrgWideEmailAddress> owe = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :s.remitente LIMIT 1];
			if (!owe.isEmpty()) { m.setOrgWideEmailAddressId(owe[0].Id); }
		}
		if (!adjuntos.isEmpty()) { m.setFileAttachments(adjuntos); }
		Integer adjuntados = adjuntos.size();
		Messaging.SendEmailResult res = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ m }, false)[0];
		if (!res.isSuccess()) { throw new CorreoException(res.getErrors()[0].getMessage()); }
		if (deAuto != null) { CorreoCotizacionAuto.seguimiento(s.registroId); }
		return 'Correo enviado a ' + correo + redaccion + ' con ' + adjuntados + ' PDF(s) adjunto(s)' + aviso + '.';
	}

	/**
	 * @creation date: 20/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Pone el cuerpo que redactó la IA dentro del diseño de la plantilla: el texto fijo de la plantilla
	 *   (el primer bloque justificado) se cambia por el de la IA y el saludo «Apreciable %%…%%» se quita, porque la
	 *   IA ya saluda. El banner, las imágenes, el cierre y el pie de la plantilla se conservan.
	 * @param plantilla: HTML de la plantilla (EmailTemplate.HtmlValue)
	 * @param cuerpo: Cuerpo HTML de la IA
	 * @return HTML del correo, o null si la plantilla no tiene ese bloque (entonces se usa el marco sencillo)
	 */
	@TestVisible
	private static String enDisenoDePlantilla(String plantilla, String cuerpo) {
		if (String.isBlank(plantilla) || String.isBlank(cuerpo)) { return null; }
		String abre = '<div style="text-align: justify;">';
		Integer ini = plantilla.indexOf(abre);
		if (ini < 0) { return null; }
		Integer fin = plantilla.indexOf('</div>', ini + abre.length());
		if (fin < 0) { return null; }
		String html = plantilla.left(ini)
			+ '<div style="text-align: left; font-family: Arial, Helvetica, sans-serif; font-size: 15px; line-height: 1.5; color: #444444;">'
			+ cuerpo + '</div>' + plantilla.substring(fin + '</div>'.length());
		// Saludo de la plantilla: su texto se quita (el bloque queda vacío).
		Integer saludo = html.indexOf('Apreciable');
		if (saludo >= 0 && saludo < html.indexOf(cuerpo)) {
			Integer divIni = html.lastIndexOf('<div', saludo);
			Integer divFin = html.indexOf('</div>', saludo);
			if (divIni >= 0 && divFin > saludo) {
				Integer cierreApertura = html.indexOf('>', divIni);
				html = html.left(cierreApertura + 1) + html.substring(divFin);
			}
		}
		return html;
	}

	// Texto fijo de las plantillas (texto alternativo del banner) que se cambia por el ramo del registro.
	private static final String TEXTO_RAMO_PLANTILLA = 'A tu seguro de gastos médicos mayores';

	/**
	 * @creation date: 20/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Ramo de la oportunidad o de la póliza, como se lee en el correo ("automóviles", "gastos médicos
	 *   mayores", "daños"...). Empresarial se escribe "paquete empresarial".
	 * @param registroId: Oportunidad o póliza (InsurancePolicy)
	 * @return Ramo en minúsculas, o null si el registro no tiene
	 */
	@TestVisible
	private static String ramoDe(Id registroId) {
		if (registroId == null) { return null; }
		String ramo = null;
		Schema.SObjectType tipo = registroId.getSobjectType();
		if (tipo == Opportunity.SObjectType) {
			for (Opportunity o : [SELECT toLabel(Ramo__c) FROM Opportunity WHERE Id = :registroId LIMIT 1]) { ramo = o.Ramo__c; }
		} else if (tipo == InsurancePolicy.SObjectType) {
			for (InsurancePolicy p : [SELECT toLabel(Ramo__c) FROM InsurancePolicy WHERE Id = :registroId LIMIT 1]) { ramo = p.Ramo__c; }
		}
		if (String.isBlank(ramo)) { return null; }
		return ramo.equalsIgnoreCase('Empresarial') ? 'paquete empresarial' : ramo.toLowerCase();
	}

	/**
	 * @creation date: 20/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Las plantillas traen fijo "A tu seguro de gastos médicos mayores" (texto del banner); se cambia
	 *   por el ramo del registro, o queda "A tu seguro" si no lo tiene.
	 * @param html: HTML del correo
	 * @param ramo: Ramo como se lee en el correo (puede ser null)
	 * @return HTML con el ramo
	 */
	@TestVisible
	private static String conRamo(String html, String ramo) {
		if (String.isBlank(html)) { return html; }
		return html.replace(TEXTO_RAMO_PLANTILLA, String.isBlank(ramo) ? 'A tu seguro' : 'A tu seguro de ' + ramo);
	}

	// Arma asunto y cuerpo de la plantilla con los campos del contacto/usuario y del registro. Si la plantilla no admite
	// el registro relacionado, se arma solo con el destinatario.
	private static Messaging.SingleEmailMessage renderizar(Id plantillaId, Id whoId, Id whatId) {
		Messaging.SingleEmailMessage r;
		try {
			r = Messaging.renderStoredEmailTemplate(plantillaId, whoId, whatId);
		} catch (Exception e) {
			r = Messaging.renderStoredEmailTemplate(plantillaId, whoId, null);
		}
		Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
		m.setSubject(r.getSubject());
		if (r.getHtmlBody() != null) { m.setHtmlBody(r.getHtmlBody()); }
		if (r.getPlainTextBody() != null) { m.setPlainTextBody(r.getPlainTextBody()); }
		return m;
	}

	// Contenido de cada PDF como adjunto del correo (se manda el archivo, no una referencia).
	private static List<Messaging.EmailFileAttachment> adjuntosDe(List<Id> versiones) {
		List<Messaging.EmailFileAttachment> adjuntos = new List<Messaging.EmailFileAttachment>();
		if (versiones.isEmpty()) { return adjuntos; }
		for (ContentVersion v : [SELECT Title, FileExtension, VersionData FROM ContentVersion WHERE Id IN :versiones]) {
			Messaging.EmailFileAttachment a = new Messaging.EmailFileAttachment();
			String nombre = String.isBlank(v.Title) ? 'archivo' : v.Title;
			if (!nombre.toLowerCase().endsWith('.pdf')) { nombre += '.pdf'; }
			a.setFileName(nombre);
			a.setContentType('application/pdf');
			a.setBody(v.VersionData);
			adjuntos.add(a);
		}
		return adjuntos;
	}

	// Última versión de cada PDF del registro, del más reciente al más antiguo, mientras quepan en el límite de
	// tamaño. Devuelve cuántos se omitieron por tamaño.
	@TestVisible
	private static Integer archivosDe(Id registroId, List<Id> versiones) {
		Set<Id> docIds = new Set<Id>();
		for (ContentDocumentLink l : [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :registroId]) {
			docIds.add(l.ContentDocumentId);
		}
		if (docIds.isEmpty()) { return 0; }
		Integer total = 0;
		Integer omitidos = 0;
		for (ContentVersion v : [
			SELECT Id, ContentSize FROM ContentVersion
			WHERE ContentDocumentId IN :docIds AND IsLatest = true AND FileExtension = 'pdf'
			ORDER BY CreatedDate DESC
		]) {
			Integer tam = v.ContentSize == null ? 0 : v.ContentSize;
			if (total + tam > MAX_ADJUNTOS_BYTES) { omitidos++; continue; }
			total += tam;
			versiones.add(v.Id);
		}
		return omitidos;
	}

	public class CorreoException extends Exception {}
}
