/**
 * @creation date: 23/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Correo al cliente cuando una solicitud de movimientos (altas, bajas y cambios) queda concluida, a mano o
 *               al cerrarse su último movimiento, con el resumen de lo realizado: cada registro con su movimiento, su
 *               fecha, su estado (Concluido, o Rechazado con el motivo) y su prima, y el total de la solicitud.
 *               Va a quien envió la solicitud desde el sitio de empresas o, si no vino del sitio, al contratante de la
 *               póliza. Se envía en segundo plano: una falla del correo no impide concluir. Cada envío queda como tarea
 *               en la póliza. Fuera de producción va a los destinatarios de prueba, nunca al cliente.
 *               Sin sharing: también se concluye desde el sitio y el resumen lee todos los registros de la solicitud.
 */
public without sharing class AvisoMovimientoConcluido implements Queueable {

	public static final String ASUNTO_TAREA = 'Resumen de movimiento concluido enviado';
	static final Integer MAX_FILAS = 300;
	// Solicitudes ya programadas en esta transacción.
	@TestVisible static Set<String> programadas = new Set<String>();

	private Id policyId;
	private String folio;

	public AvisoMovimientoConcluido(Id policyId, String folio) {
		this.policyId = policyId;
		this.folio = folio;
	}

	/**
	 * @creation date: 23/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Programa el correo de la solicitud concluida (una vez por transacción).
	 * @param policyId: póliza.
	 * @param folio: solicitud (SOL-0001...).
	 * @return aviso para la pantalla, o null si no hay nada que enviar.
	 */
	public static String programar(Id policyId, String folio) {
		if (policyId == null || String.isBlank(folio) || !programadas.add(policyId + '|' + folio)) { return null; }
		try {
			String correo = correoCliente(policyId, folio);
			Boolean produccion = AvisoRenovacionPoliza.esProduccion();
			if (produccion && correo == null) { return 'El cliente no tiene correo registrado: no se le envió el resumen.'; }
			if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) { return 'No se pudo enviar el resumen al cliente.'; }
			System.enqueueJob(new AvisoMovimientoConcluido(policyId, folio));
			return produccion ? 'Se envía el resumen al cliente (' + correo + ').'
				: 'Se envía el resumen a los correos de prueba (en producción, a ' + (correo == null ? 'nadie: el cliente no tiene correo' : correo) + ').';
		} catch (Exception e) {
			System.debug(LoggingLevel.ERROR, 'AvisoMovimientoConcluido: ' + e.getMessage());
			return 'No se pudo enviar el resumen al cliente.';
		}
	}

	public void execute(QueueableContext qc) {
		try {
			enviar(policyId, folio);
		} catch (Exception e) {
			System.debug(LoggingLevel.ERROR, 'AvisoMovimientoConcluido: ' + e.getMessage() + ' | ' + e.getStackTraceString());
		}
	}

	/**
	 * @return correo del usuario del sitio que envió la solicitud o, si no vino del sitio, el del contratante (nunca uno
	 *         de Avanza); null si no hay.
	 */
	@TestVisible
	static String correoCliente(Id policyId, String folio) {
		Id rt = EndosoPoliza.tipoCaso();
		if (rt != null) {
			for (Case c : [
				SELECT CreatedBy.Email, CreatedBy.ContactId FROM Case
				WHERE RecordTypeId = :rt AND InsurancePolicy__c = :policyId AND Solicitud__c = :folio ORDER BY CreatedDate LIMIT 1
			]) {
				if (c.CreatedBy.ContactId != null && deCliente(c.CreatedBy.Email)) { return c.CreatedBy.Email; }
			}
		}
		for (InsurancePolicy p : [
			SELECT NameInsured.PersonEmail, NameInsured.Correo_electronico__c FROM InsurancePolicy
			WHERE Id = :policyId AND NameInsuredId != null LIMIT 1
		]) {
			if (deCliente(p.NameInsured.PersonEmail)) { return p.NameInsured.PersonEmail; }
			if (deCliente(p.NameInsured.Correo_electronico__c)) { return p.NameInsured.Correo_electronico__c; }
		}
		return null;
	}

	private static Boolean deCliente(String correo) {
		return String.isNotBlank(correo) && !correo.trim().toLowerCase().endsWith('@avanzaseguro.com');
	}

	@TestVisible
	static void enviar(Id policyId, String folio) {
		Boolean produccion = AvisoRenovacionPoliza.esProduccion();
		String correo = correoCliente(policyId, folio);
		if (produccion && correo == null) { return; }
		InsurancePolicy p = [SELECT Id, Name, NameInsured.Name FROM InsurancePolicy WHERE Id = :policyId LIMIT 1];
		List<String> para = produccion ? new List<String>{ correo } : AvisoRenovacionPoliza.PRUEBA_PARA;
		List<String> copia = produccion ? new List<String>{ AvisoRenovacionPoliza.COPIA_PRODUCCION } : AvisoRenovacionPoliza.PRUEBA_COPIA;
		Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
		m.setToAddresses(para);
		m.setCcAddresses(copia);
		m.setSubject((produccion ? '' : '[PRUEBA] ') + 'Tu solicitud ' + numero(folio) + ' de la póliza ' + p.Name + ' quedó concluida');
		m.setHtmlBody(cuerpo(p, folio, produccion ? '' : AvisoRenovacionPoliza.filaPrueba(correo)));
		m.setSaveAsActivity(false);
		List<OrgWideEmailAddress> owe = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :AvisoRenovacionPoliza.CORREO_SERVICIO LIMIT 1];
		if (!owe.isEmpty()) { m.setOrgWideEmailAddressId(owe[0].Id); } else { m.setReplyTo(AvisoRenovacionPoliza.CORREO_SERVICIO); }
		String error;
		try {
			Messaging.SendEmailResult r = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ m }, false)[0];
			error = r.isSuccess() ? null : r.getErrors()[0].getMessage();
		} catch (Exception e) {
			// Entregabilidad del org apagada o sin capacidad de envío.
			error = e.getMessage();
		}
		// El envío (o por qué falló) queda como tarea en la póliza.
		Database.insert(new Task(WhatId = p.Id, Status = 'Completed', ActivityDate = Date.today(), TaskSubtype = 'Email', Priority = 'Normal',
			Subject = ((error == null ? ASUNTO_TAREA : 'No se envió el resumen del movimiento concluido') + ' · ' + numero(folio) + ' · ' + p.Name).left(255),
			Description = (error == null ? '' : error + '\n') + 'Para: ' + String.join(para, ', ') + '\nCC: ' + String.join(copia, ', ')
				+ (produccion ? '' : '\n(Prueba: el cliente es ' + (correo == null ? 'sin correo' : correo) + ')')), false);
	}

	// Resumen de la solicitud: qué se hizo con cada registro.
	@TestVisible
	static String cuerpo(InsurancePolicy p, String folio, String filaPrueba) {
		List<Movimiento_Poliza__c> movs = [
			SELECT Tipo__c, Asegurado__c, Certificado__c, Fecha_Movimiento__c, Fecha_Cierre__c, Seguimiento__c, Motivo_Rechazo__c,
				Numero_Endoso__c, Prima__c, Participante__c, Inciso__c, Inciso__r.Numero_Inciso__c, Inciso__r.Descripcion__c
			FROM Movimiento_Poliza__c WHERE Poliza__c = :p.Id AND Solicitud__c = :folio ORDER BY CreatedDate, Id LIMIT 5000
		];
		Map<String, Integer> conteo = new Map<String, Integer>();
		Integer rechazados = 0;
		Decimal prima;
		Datetime cierre;
		Set<String> endosos = new Set<String>();
		Boolean personas = false;
		for (Movimiento_Poliza__c m : movs) {
			if (m.Seguimiento__c == 'Rechazado') { rechazados++; }
			else { conteo.put(m.Tipo__c, (conteo.containsKey(m.Tipo__c) ? conteo.get(m.Tipo__c) : 0) + 1); }
			if (m.Prima__c != null) { prima = (prima == null ? 0 : prima) + m.Prima__c; }
			if (m.Fecha_Cierre__c != null && (cierre == null || cierre < m.Fecha_Cierre__c)) { cierre = m.Fecha_Cierre__c; }
			if (String.isNotBlank(m.Numero_Endoso__c)) { endosos.add(m.Numero_Endoso__c.trim()); }
			if (m.Participante__c != null) { personas = true; }
		}
		Boolean conPrima = prima != null;
		List<String> hechos = new List<String>();
		for (String t : new List<String>{ 'Alta', 'Baja', 'Cambio' }) {
			Integer n = conteo.get(t);
			if (n != null) { hechos.add(n + ' ' + t.toLowerCase() + (n == 1 ? '' : 's')); }
		}
		if (rechazados > 0) { hechos.add(rechazados + (rechazados == 1 ? ' rechazado' : ' rechazados')); }
		String tabla = '';
		if (!movs.isEmpty()) {
			String th = '<th align="left" style="padding:8px;background:#EEF3FB;color:#1F4E9C;border:1px solid #D5DEEE;font-size:12px;">';
			tabla = '<table cellspacing="0" style="width:100%;border-collapse:collapse;font-size:13px;margin-top:8px;"><tr>'
				+ th + (personas ? 'Certificado' : 'Inciso') + '</th>' + th + 'Nombre</th>' + th + 'Movimiento</th>' + th + 'Fecha</th>' + th + 'Estado</th>'
				+ (conPrima ? th + 'Prima</th>' : '') + '</tr>';
			Integer n = 0;
			for (Movimiento_Poliza__c m : movs) {
				if (++n > MAX_FILAS) { break; }
				Boolean rechazado = m.Seguimiento__c == 'Rechazado';
				String clave = m.Inciso__c != null && m.Inciso__r.Numero_Inciso__c != null ? String.valueOf(m.Inciso__r.Numero_Inciso__c.intValue())
					: CensoColectivoController.certificadoLimpio(m.Certificado__c);
				if (clave == null) { clave = personas ? 'POR ASIGNAR' : ''; }
				tabla += '<tr>' + td(clave) + td(String.isNotBlank(m.Asegurado__c) ? m.Asegurado__c : (m.Inciso__c == null ? '' : m.Inciso__r.Descripcion__c))
					+ td(m.Tipo__c) + td(fecha(m.Fecha_Movimiento__c))
					+ td(rechazado ? 'Rechazado' + (String.isBlank(m.Motivo_Rechazo__c) ? '' : ': ' + m.Motivo_Rechazo__c) : 'Concluido')
					+ (conPrima ? td(dinero(m.Prima__c)) : '') + '</tr>';
			}
			tabla += '</table>';
			if (movs.size() > MAX_FILAS) { tabla += '<p>Y ' + (movs.size() - MAX_FILAS) + ' registros más; los ves completos en el sitio de empresas.</p>'; }
		}
		String cliente = p.NameInsured == null ? null : p.NameInsured.Name;
		return '<table width="100%" cellspacing="0" style="max-width:720px;font-family:Arial,Helvetica,sans-serif;color:#1a1a1a;font-size:14px;">' + filaPrueba
			+ '<tr><td style="background:#1F4E9C;color:#ffffff;padding:18px;font-size:20px;font-weight:bold;">Tu solicitud quedó concluida</td></tr>'
			+ '<tr><td style="padding:18px 0;"><p>Estimado cliente' + (cliente == null ? '' : ' <b>' + esc(cliente) + '</b>') + ':</p>'
			+ '<p>Concluimos la solicitud de movimientos <b>' + esc(numero(folio)) + '</b> de tu póliza <b>' + esc(p.Name) + '</b>. Este es el resumen de lo realizado:</p>'
			+ '<table cellpadding="4" style="font-size:14px;">'
			+ dato('Número de movimiento', numero(folio)) + dato('Póliza', p.Name)
			+ dato('Fecha de cierre', fecha(cierre == null ? Date.today() : cierre.date()))
			+ dato('Realizado', String.join(hechos, ', ')) + dato('Endoso', String.join(new List<String>(endosos), ', '))
			+ dato('Prima del movimiento', conPrima ? dinero(prima) : null) + '</table>' + tabla
			+ '<p style="margin-top:18px;">Si tienes alguna duda, responde este correo o contacta a tu asesor.</p>'
			+ '<p>Avanza Seguro Consultores<br/>' + AvisoRenovacionPoliza.CORREO_SERVICIO + '</p></td></tr></table>';
	}

	// Número del movimiento como lo ve el cliente (SOL-0005 → 0005).
	private static String numero(String folio) { return folio == null ? '' : folio.replace('SOL-', ''); }
	private static String esc(String s) { return s == null ? '' : s.escapeHtml4(); }
	private static String td(String v) { return '<td style="padding:8px;border:1px solid #D5DEEE;">' + esc(v) + '</td>'; }
	private static String dato(String etiqueta, String v) {
		return String.isBlank(v) ? '' : '<tr><td style="color:#555555;"><b>' + etiqueta + '</b></td><td>' + esc(v) + '</td></tr>';
	}
	private static String fecha(Date d) {
		return d == null ? '' : String.valueOf(d.day()).leftPad(2, '0') + '/' + String.valueOf(d.month()).leftPad(2, '0') + '/' + d.year();
	}
	// Con separador de miles y dos decimales, sin depender del idioma del usuario.
	private static String dinero(Decimal n) {
		if (n == null) { return ''; }
		String s = n.abs().setScale(2).toPlainString();
		String entero = s.substringBefore('.');
		String miles = '';
		while (entero.length() > 3) {
			miles = ',' + entero.right(3) + miles;
			entero = entero.left(entero.length() - 3);
		}
		return (n < 0 ? '-$' : '$') + entero + miles + '.' + s.substringAfter('.');
	}
}
