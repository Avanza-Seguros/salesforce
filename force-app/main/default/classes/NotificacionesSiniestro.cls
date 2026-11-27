/**
 * @creation date: 26/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Avisos por correo de los siniestros (Claim), los mismos que enviaba Control de Folios y con sus mismas
 *               plantillas: carta de programación aceptada (Seguros Monterrey NYL o Allianz), carta de ingreso
 *               hospitalario y aviso de reembolso pagado. Se envían al correo para avisos del siniestro, desde
 *               info@avanzaseguro.com y con copia a correos@avanzaseguro.com, con los archivos marcados como carta de
 *               autorización (del siniestro y, en el reembolso, también de su solicitud de pago). Las plantillas
 *               combinan campos del folio ({!Control_de_Folios__c.Campo}); aquí se llenan con los datos del siniestro.
 *               Se envían en segundo plano (Queueable) para que un error de correo no impida guardar el siniestro.
 */
public without sharing class NotificacionesSiniestro implements Queueable {

	public static final String PROGRAMACION = 'programacion';
	public static final String INGRESO = 'ingreso';
	public static final String REEMBOLSO = 'reembolso';
	private static final String REMITENTE = 'info@avanzaseguro.com';
	private static final String COPIA = 'correos@avanzaseguro.com';
	// Plantilla de cada aviso (las de Control de Folios); la carta de programación depende de la aseguradora.
	@TestVisible
	private static Map<String, String> plantillas = new Map<String, String>{
		PROGRAMACION + ':smnyl' => 'Cartas_de_autorizacion',
		PROGRAMACION + ':allianz' => 'Carta_de_Autorizacion_Allianz',
		INGRESO => 'Env_o_de_cartas_de_autorizaci_n_ingreso_hospitalario_no_programado',
		REEMBOLSO => 'Reembolso'
	};
	// Correos armados en la última ejecución (para las pruebas).
	@TestVisible
	private static List<Messaging.SingleEmailMessage> armados = new List<Messaging.SingleEmailMessage>();

	/** Aviso por enviar: su tipo, el siniestro y, en el reembolso, la solicitud pagada. */
	public class Aviso {
		public String tipo;
		public Id claimId;
		public Id solicitudId;
		public Aviso(String tipo, Id claimId, Id solicitudId) {
			this.tipo = tipo;
			this.claimId = claimId;
			this.solicitudId = solicitudId;
		}
	}

	private List<Aviso> avisos;

	public NotificacionesSiniestro(List<Aviso> avisos) {
		this.avisos = avisos;
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Encola el envío de los avisos (si queda cupo de trabajos en la transacción).
	 * @param avisos: avisos por enviar.
	 * @return void
	 */
	public static void encolar(List<Aviso> avisos) {
		if (avisos == null || avisos.isEmpty()) { return; }
		if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
			System.enqueueJob(new NotificacionesSiniestro(avisos));
		} else {
			System.debug(LoggingLevel.WARN, 'Sin cupo para enviar los avisos de siniestro: ' + avisos.size());
		}
	}

	public void execute(QueueableContext contexto) {
		enviar(avisos);
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma y envía los avisos. Los que no tienen correo, plantilla o aseguradora con carta no se envían.
	 * @param avisos: avisos por enviar.
	 * @return número de correos enviados.
	 */
	public static Integer enviar(List<Aviso> avisos) {
		armados = armar(avisos);
		if (armados.isEmpty()) { return 0; }
		Integer enviados = 0;
		for (Messaging.SingleEmailMessage m : armados) {
			Integer adjuntos = m.getFileAttachments() == null ? 0 : m.getFileAttachments().size();
			System.debug(LoggingLevel.INFO, 'Aviso de siniestro: «' + m.getSubject() + '» a ' + m.getToAddresses() + ' con ' + adjuntos + ' adjunto(s)');
		}
		try {
			for (Messaging.SendEmailResult r : Messaging.sendEmail(armados, false)) {
				if (r.isSuccess()) { enviados++; } else { System.debug(LoggingLevel.ERROR, 'Aviso de siniestro no enviado: ' + r.getErrors()[0].getMessage()); }
			}
		} catch (Exception e) {
			System.debug(LoggingLevel.ERROR, 'No se enviaron los avisos de siniestro: ' + e.getMessage());
		}
		return enviados;
	}

	@TestVisible
	private static List<Messaging.SingleEmailMessage> armar(List<Aviso> avisos) {
		List<Messaging.SingleEmailMessage> res = new List<Messaging.SingleEmailMessage>();
		Set<Id> claimIds = new Set<Id>();
		Set<Id> solicitudIds = new Set<Id>();
		for (Aviso a : avisos) {
			if (a.claimId != null) { claimIds.add(a.claimId); }
			if (a.solicitudId != null) { solicitudIds.add(a.solicitudId); }
		}
		if (claimIds.isEmpty()) { return res; }
		Map<Id, Claim> siniestros = new Map<Id, Claim>([
			SELECT Id, Name, LossType, SourceSystem, SourceSystemIdentifier, InitiationDate, Correo_Avisos__c, Afectado__c,
				Titular__c, Titular__r.Name, PolicyNumber.Name,
				(SELECT Roles, InsurancePolicyParticipant.ParticipantName, ParticipantAccount.Name FROM ClaimParticipants ORDER BY CreatedDate)
			FROM Claim WHERE Id IN :claimIds
		]);
		Map<Id, PaymentRequest> solicitudes = new Map<Id, PaymentRequest>([SELECT Id, Name, ReferenceNumber FROM PaymentRequest WHERE Id IN :solicitudIds]);
		Map<String, EmailTemplate> porNombre = new Map<String, EmailTemplate>();
		for (EmailTemplate t : [SELECT Id, DeveloperName, Subject, HtmlValue, Body FROM EmailTemplate WHERE DeveloperName IN :plantillas.values()]) {
			porNombre.put(t.DeveloperName, t);
		}
		List<OrgWideEmailAddress> remitente = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :REMITENTE LIMIT 1];
		Set<Id> conArchivos = new Set<Id>(claimIds);
		conArchivos.addAll(solicitudIds);
		Map<Id, List<Messaging.EmailFileAttachment>> cartas = cartasDe(conArchivos);
		for (Aviso a : avisos) {
			Claim c = siniestros.get(a.claimId);
			if (c == null || String.isBlank(c.Correo_Avisos__c)) { continue; }
			String clave = a.tipo == PROGRAMACION ? PROGRAMACION + ':' + claveAseguradora(c.SourceSystem) : a.tipo;
			EmailTemplate t = porNombre.get(plantillas.get(clave));
			if (t == null) { continue; }
			PaymentRequest r = a.solicitudId == null ? null : solicitudes.get(a.solicitudId);
			Map<String, String> valores = valores(c, r);
			Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
			m.setToAddresses(new List<String>{ c.Correo_Avisos__c });
			m.setCcAddresses(new List<String>{ COPIA });
			if (!remitente.isEmpty()) { m.setOrgWideEmailAddressId(remitente[0].Id); }
			m.setSaveAsActivity(false);
			m.setUseSignature(true);
			m.setSubject(combinar(t.Subject, valores, false));
			String html = String.isNotBlank(t.HtmlValue) ? t.HtmlValue : (t.Body == null ? '' : t.Body.escapeHtml4().replace('\n', '<br/>'));
			m.setHtmlBody(combinar(html, valores, true));
			List<Messaging.EmailFileAttachment> adjuntos = new List<Messaging.EmailFileAttachment>();
			if (cartas.containsKey(c.Id)) { adjuntos.addAll(cartas.get(c.Id)); }
			if (r != null && cartas.containsKey(r.Id)) { adjuntos.addAll(cartas.get(r.Id)); }
			if (!adjuntos.isEmpty()) { m.setFileAttachments(adjuntos); }
			res.add(m);
		}
		return res;
	}

	// Datos del siniestro para los campos del folio que combinan las plantillas.
	private static Map<String, String> valores(Claim c, PaymentRequest r) {
		String titular = c.Titular__c != null ? c.Titular__r.Name : null;
		if (titular == null) {
			for (ClaimParticipant p : c.ClaimParticipants) {
				if (p.Roles != null && p.Roles.contains('Reclamante')) {
					titular = p.InsurancePolicyParticipantId != null ? p.InsurancePolicyParticipant.ParticipantName
						: (p.ParticipantAccountId != null ? p.ParticipantAccount.Name : null);
					break;
				}
			}
		}
		if (titular == null) { titular = c.Afectado__c; }
		// Folio: el de la aseguradora para el reembolso (o el de la solicitud) o para el siniestro (o el del siniestro).
		String folio = r != null ? (String.isNotBlank(r.ReferenceNumber) ? r.ReferenceNumber : r.Name)
			: (String.isNotBlank(c.SourceSystemIdentifier) ? c.SourceSystemIdentifier : c.Name);
		return new Map<String, String>{
			'Titular__c' => titular, 'Folio__c' => folio, 'Poliza__c' => c.PolicyNumber == null ? null : c.PolicyNumber.Name,
			'Fecha_de_Acuse__c' => c.InitiationDate == null ? null : c.InitiationDate.format('dd/MM/yyyy'),
			'Movimiento__c' => c.LossType, 'Asegurado_afectado__c' => c.Afectado__c, 'Siniestro__c' => c.SourceSystemIdentifier,
			'Name' => c.Name
		};
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Llena los campos del folio de una plantilla ({!Control_de_Folios__c.Campo} o {!Control_de_Folios__c:Campo})
	 *               con los datos del siniestro; un campo sin dato queda vacío.
	 * @param texto: asunto o cuerpo de la plantilla.
	 * @param valores: dato de cada campo.
	 * @param html: si el texto es HTML (los datos se escapan).
	 * @return el texto combinado.
	 */
	@TestVisible
	private static String combinar(String texto, Map<String, String> valores, Boolean html) {
		if (String.isBlank(texto)) { return texto; }
		Matcher m = Pattern.compile('\\{!Control_de_Folios__c[.:]([A-Za-z0-9_]+)\\}').matcher(texto);
		List<String> partes = new List<String>();
		Integer inicio = 0;
		while (m.find()) {
			partes.add(texto.substring(inicio, m.start()));
			String v = valores.get(m.group(1));
			partes.add(v == null ? '' : (html ? v.escapeHtml4() : v));
			inicio = m.end();
		}
		partes.add(texto.substring(inicio));
		return String.join(partes, '');
	}

	// Aseguradora con carta de programación: Seguros Monterrey New York Life o Allianz.
	@TestVisible
	private static String claveAseguradora(String aseguradora) {
		String a = aseguradora == null ? '' : aseguradora.toLowerCase();
		if (a.contains('monterrey') || a.contains('smnyl')) { return 'smnyl'; }
		if (a.contains('allianz')) { return 'allianz'; }
		return '';
	}

	// Archivos marcados como carta de autorización de cada registro, como adjuntos.
	private static Map<Id, List<Messaging.EmailFileAttachment>> cartasDe(Set<Id> registros) {
		Map<Id, List<Messaging.EmailFileAttachment>> res = new Map<Id, List<Messaging.EmailFileAttachment>>();
		Map<Id, Set<Id>> registrosDe = new Map<Id, Set<Id>>();
		for (ContentDocumentLink l : [SELECT ContentDocumentId, LinkedEntityId FROM ContentDocumentLink WHERE LinkedEntityId IN :registros]) {
			if (!registrosDe.containsKey(l.ContentDocumentId)) { registrosDe.put(l.ContentDocumentId, new Set<Id>()); }
			registrosDe.get(l.ContentDocumentId).add(l.LinkedEntityId);
		}
		if (registrosDe.isEmpty()) { return res; }
		for (ContentVersion v : [
			SELECT ContentDocumentId, PathOnClient, Title, FileExtension, VersionData FROM ContentVersion
			WHERE ContentDocumentId IN :registrosDe.keySet() AND IsLatest = true AND Carta_Autorizacion__c = true ORDER BY CreatedDate
		]) {
			Messaging.EmailFileAttachment a = new Messaging.EmailFileAttachment();
			a.setFileName(String.isNotBlank(v.PathOnClient) ? v.PathOnClient : v.Title + (String.isBlank(v.FileExtension) ? '' : '.' + v.FileExtension));
			a.setBody(v.VersionData);
			for (Id r : registrosDe.get(v.ContentDocumentId)) {
				if (!res.containsKey(r)) { res.put(r, new List<Messaging.EmailFileAttachment>()); }
				res.get(r).add(a);
			}
		}
		return res;
	}
}
