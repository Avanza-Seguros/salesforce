/**
 * @creation date: 18/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Aviso de renovación de póliza (InsurancePolicy). Se envía con la plantilla «Aviso Renovación Póliza»
 *               (carpeta Empresas), cuyos marcadores {{...}} se llenan aquí:
 *               - Automático: cada día (Schedulable + Batch) a las pólizas Vigentes que vencen en 30 y en 15 días.
 *               - Manual: botón «Enviar aviso de renovación» de la póliza (acción avisoRenovacionPoliza).
 *               El texto se adapta a la póliza: días que faltan, y qué se le pedirá al cliente según sea individual o
 *               empresarial y el ramo (asegurados, vehículos o ubicaciones). Cada envío queda como tarea en la póliza.
 *               Fuera de producción el correo va a los destinatarios de prueba, nunca al cliente.
 */
public with sharing class AvisoRenovacionPoliza implements Database.Batchable<SObject>, Schedulable {

	public static final String PLANTILLA = 'Aviso_Renovacion_Poliza';
	public static final List<Integer> DIAS_AVISO = new List<Integer>{ 30, 15 };
	public static final String NOMBRE_JOB = 'Aviso de renovación de pólizas';
	public static final String ASUNTO_TAREA = 'Aviso de renovación enviado';
	public static final String CORREO_SERVICIO = 'info@avanzaseguro.com';
	public static final String COPIA_PRODUCCION = 'correos@avanzaseguro.com';
	static final String ORG_PRODUCCION = '00D8a000001KZ9w';
	public static final List<String> PRUEBA_PARA = new List<String>{ 'abraham.gonzalez@avanzaseguro.com' };
	public static final List<String> PRUEBA_COPIA = new List<String>{ 'sergio.uribe@volestra.com' };
	@TestVisible static Boolean produccionPrueba;

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Programa el envío diario (8:00). Si ya estaba programado, no hace nada.
	 * @return Id del job
	 */
	public static Id programar() {
		List<CronTrigger> ya = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :NOMBRE_JOB LIMIT 1];
		if (!ya.isEmpty()) { return ya[0].Id; }
		return System.schedule(NOMBRE_JOB, '0 0 8 * * ?', new AvisoRenovacionPoliza());
	}

	public void execute(SchedulableContext sc) {
		Database.executeBatch(new AvisoRenovacionPoliza(), 20);
	}

	/** Pólizas Vigentes cuyo vencimiento cae justo a 30 o 15 días de hoy. */
	public Database.QueryLocator start(Database.BatchableContext bc) {
		Date hoy = Date.today();
		Datetime a1 = inicioDia(hoy.addDays(DIAS_AVISO[0]));
		Datetime b1 = a1.addDays(1);
		Datetime a2 = inicioDia(hoy.addDays(DIAS_AVISO[1]));
		Datetime b2 = a2.addDays(1);
		String vigente = PolicyStatusService.STATUS_ACTIVE;
		return Database.getQueryLocator([
			SELECT Id FROM InsurancePolicy
			WHERE Status = :vigente
				AND ((ExpirationDate >= :a1 AND ExpirationDate < :b1) OR (ExpirationDate >= :a2 AND ExpirationDate < :b2))
		]);
	}

	public void execute(Database.BatchableContext bc, List<InsurancePolicy> scope) {
		Set<Id> ids = new Map<Id, InsurancePolicy>(scope).keySet();
		// Si el job corre dos veces el mismo día, no se repite el aviso.
		Set<Id> yaAvisadas = new Set<Id>();
		String asunto = ASUNTO_TAREA + '%';
		for (Task t : [SELECT WhatId FROM Task WHERE WhatId IN :ids AND Subject LIKE :asunto AND CreatedDate = TODAY]) {
			yaAvisadas.add(t.WhatId);
		}
		ids.removeAll(yaAvisadas);
		if (!ids.isEmpty()) { enviar(ids, false); }
	}

	public void finish(Database.BatchableContext bc) {}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Botón de la póliza: envía el aviso de renovación en ese momento.
	 * @param policyId: póliza
	 * @return a quién se envió
	 */
	@AuraEnabled
	public static String enviarAviso(Id policyId) {
		try {
			InsurancePolicy p = [SELECT Status FROM InsurancePolicy WHERE Id = :policyId LIMIT 1];
			if (p.Status == PolicyStatusService.STATUS_CANCELLED) {
				throw new AuraHandledException('La póliza está cancelada: no se envía aviso de renovación.');
			}
			Map<Id, String> res = enviar(new Set<Id>{ policyId }, true);
			String r = res.get(policyId);
			if (r == null || r.startsWith('ERROR:')) {
				throw new AuraHandledException(r == null ? 'No se pudo enviar el aviso.' : r.removeStart('ERROR:'));
			}
			return r;
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			AuraHandledException a = new AuraHandledException(e.getMessage());
			a.setMessage(e.getMessage());
			throw a;
		}
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma y envía el aviso de cada póliza y deja una tarea en ella.
	 * @param policyIds: pólizas
	 * @param manual: true si lo envió el ejecutivo con el botón
	 * @return por póliza, a quién se envió o «ERROR:motivo»
	 */
	public static Map<Id, String> enviar(Set<Id> policyIds, Boolean manual) {
		Map<Id, String> res = new Map<Id, String>();
		List<EmailTemplate> tpls = [SELECT Id, Name, Subject, HtmlValue, Body FROM EmailTemplate WHERE DeveloperName = :PLANTILLA AND IsActive = true LIMIT 1];
		if (tpls.isEmpty()) {
			for (Id i : policyIds) { res.put(i, 'ERROR:No existe la plantilla activa «' + PLANTILLA + '».'); }
			return res;
		}
		EmailTemplate tpl = tpls[0];
		Boolean produccion = esProduccion();
		List<OrgWideEmailAddress> owe = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :CORREO_SERVICIO LIMIT 1];

		List<Messaging.SingleEmailMessage> mensajes = new List<Messaging.SingleEmailMessage>();
		List<InsurancePolicy> enviadas = new List<InsurancePolicy>();
		List<String> descripciones = new List<String>();
		for (InsurancePolicy p : [
			SELECT Id, Name, toLabel(Ramo__c), EffectiveDate, ExpirationDate, PremiumAmount, OwnerId,
				Aseguradora__r.Name, Product.Aseguradora__r.Name, Producer.Name,
				SourceOpportunityId, SourceOpportunity.Tipo_Contratacion__c,
				NameInsuredId, NameInsured.Name, NameInsured.IsPersonAccount, NameInsured.PersonEmail, NameInsured.Correo_electronico__c
			FROM InsurancePolicy WHERE Id IN :policyIds
		]) {
			String correoCliente = p.NameInsuredId == null ? null
				: (String.isNotBlank(p.NameInsured.PersonEmail) ? p.NameInsured.PersonEmail : p.NameInsured.Correo_electronico__c);
			if (produccion && String.isBlank(correoCliente)) {
				res.put(p.Id, 'ERROR:El contratante no tiene correo registrado.');
				continue;
			}
			List<String> para = produccion ? new List<String>{ correoCliente } : PRUEBA_PARA;
			List<String> copia = produccion ? new List<String>{ COPIA_PRODUCCION } : PRUEBA_COPIA;
			Map<String, String> v = marcadores(p);
			v.put('HTML_AVISO_PRUEBA', produccion ? '' : filaPrueba(correoCliente));

			Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
			m.setSubject((produccion ? '' : '[PRUEBA] ') + llenar(tpl.Subject, v, false));
			if (tpl.HtmlValue != null) { m.setHtmlBody(llenar(tpl.HtmlValue, v, true)); }
			if (tpl.Body != null) { m.setPlainTextBody(llenar(tpl.Body, v, false)); }
			m.setToAddresses(para);
			m.setCcAddresses(copia);
			if (!owe.isEmpty()) { m.setOrgWideEmailAddressId(owe[0].Id); } else { m.setReplyTo(CORREO_SERVICIO); }
			m.setSaveAsActivity(false);
			mensajes.add(m);
			enviadas.add(p);
			descripciones.add((manual ? 'Envío manual' : 'Envío automático') + ' · ' + v.get('AVISO_DIAS')
				+ '\nPara: ' + String.join(para, ', ') + '\nCC: ' + String.join(copia, ', ')
				+ (produccion ? '' : '\n(Prueba: el contratante es ' + (String.isBlank(correoCliente) ? 'sin correo' : correoCliente) + ')'));
		}
		if (mensajes.isEmpty()) { return res; }

		List<Messaging.SendEmailResult> envio;
		try {
			envio = Messaging.sendEmail(mensajes, false);
		} catch (Exception e) {
			// Entregabilidad del org apagada o sin capacidad de envío.
			for (InsurancePolicy p : enviadas) { res.put(p.Id, 'ERROR:No se pudo enviar el correo: ' + e.getMessage()); }
			return res;
		}
		Set<Id> duenos = new Set<Id>();
		for (InsurancePolicy p : enviadas) { if (p.OwnerId != null && p.OwnerId.getSobjectType() == User.SObjectType) { duenos.add(p.OwnerId); } }
		Set<Id> activos = new Map<Id, User>([SELECT Id FROM User WHERE Id IN :duenos AND IsActive = true]).keySet();
		List<Task> tareas = new List<Task>();
		for (Integer i = 0; i < envio.size(); i++) {
			InsurancePolicy p = enviadas[i];
			if (envio[i].isSuccess()) {
				res.put(p.Id, String.join(mensajes[i].getToAddresses(), ', '));
				tareas.add(new Task(WhatId = p.Id, Subject = (ASUNTO_TAREA + ' · ' + p.Name).left(255), Status = 'Completed',
					ActivityDate = Date.today(), TaskSubtype = 'Email', Priority = 'Normal',
					Description = descripciones[i], OwnerId = activos.contains(p.OwnerId) ? p.OwnerId : UserInfo.getUserId()));
			} else {
				res.put(p.Id, 'ERROR:' + envio[i].getErrors()[0].getMessage());
			}
		}
		if (!tareas.isEmpty()) { Database.insert(tareas, false); }
		return res;
	}

	/** Valores de los marcadores de la plantilla para una póliza. */
	@TestVisible
	static Map<String, String> marcadores(InsurancePolicy p) {
		Date vence = p.ExpirationDate == null ? null : p.ExpirationDate.date();
		Integer dias = vence == null ? null : Date.today().daysBetween(vence);
		String avisoDias = vence == null ? 'está próxima a vencer'
			: dias < 0 ? 'venció el ' + vence.format()
			: dias == 0 ? 'vence hoy'
			: dias == 1 ? 'vence mañana'
			: 'vence en ' + dias + ' días';
		String aseguradora = p.Aseguradora__r != null ? p.Aseguradora__r.Name
			: (p.Product != null && p.Product.Aseguradora__r != null ? p.Product.Aseguradora__r.Name : '');
		Boolean empresarial = (p.SourceOpportunityId != null && p.SourceOpportunity.Tipo_Contratacion__c == 'Colectiva')
			|| (p.SourceOpportunityId == null && p.NameInsuredId != null && p.NameInsured.IsPersonAccount != true);
		return new Map<String, String>{
			'NOMBRE_CONTRATANTE' => p.NameInsuredId == null ? 'cliente' : p.NameInsured.Name,
			'POLIZA' => p.Name,
			'ASEGURADORA' => String.isBlank(aseguradora) ? 'tu aseguradora' : aseguradora,
			'RAMO' => String.isBlank(p.Ramo__c) ? 'Seguro' : p.Ramo__c,
			'VIGENCIA' => (p.EffectiveDate == null ? '' : p.EffectiveDate.date().format() + ' al ') + (vence == null ? '' : vence.format()),
			'FECHA_VENCIMIENTO' => vence == null ? '' : vence.format(),
			'AVISO_DIAS' => avisoDias,
			'PRIMA_ACTUAL' => p.PremiumAmount == null ? 'N/D' : '$' + p.PremiumAmount.setScale(2).format(),
			'AGENTE' => p.Producer == null ? 'Avanza Seguro Consultores' : p.Producer.Name,
			'TIPO_POLIZA' => empresarial ? 'Empresarial' : 'Individual',
			'MENSAJE_RENOVACION' => mensaje(empresarial, tipoRamo(p.Ramo__c)),
			'CORREO_SERVICIO' => CORREO_SERVICIO
		};
	}

	/** Qué se le pide al cliente para renovar, según sea empresarial o individual y el ramo. */
	@TestVisible
	static String mensaje(Boolean empresarial, String tipo) {
		if (empresarial) {
			if (tipo == 'vehiculos') {
				return 'Para cotizar la renovación de tu flotilla, compártenos el listado actualizado de vehículos: unidades que se dan de alta o de baja, cambios de uso, placas o conductores.';
			}
			if (tipo == 'ubicaciones') {
				return 'Para cotizar la renovación, confírmanos las ubicaciones aseguradas y sus sumas aseguradas: altas, bajas, cambios de giro o de valores (edificio, contenidos, inventarios).';
			}
			return 'Para cotizar la renovación, compártenos el listado actualizado de asegurados (altas y bajas de colaboradores y dependientes) y cualquier cambio en el plan que quieras evaluar.';
		}
		if (tipo == 'vehiculos') {
			return 'Revisaremos con las aseguradoras las mejores opciones para tu vehículo. Si cambió el uso, el conductor habitual o tu domicilio, avísanos para considerarlo en la propuesta.';
		}
		if (tipo == 'ubicaciones') {
			return 'Revisaremos con las aseguradoras las mejores opciones para tu inmueble. Si cambiaron los valores de tu casa o negocio, avísanos para mantener la suma asegurada correcta.';
		}
		return 'Revisaremos con las aseguradoras las mejores opciones de renovación para ti. Si cambió algún dato (domicilio, beneficiarios o asegurados), avísanos para considerarlo en la propuesta.';
	}

	/** personas | vehiculos | ubicaciones, con la misma regla que los movimientos de la póliza. */
	@TestVisible
	static String tipoRamo(String ramo) {
		String r = String.isBlank(ramo) ? null : CensoColectivoController.llave(ramo);
		if (r == null) { return 'personas'; }
		if (r.startsWith('auto')) { return 'vehiculos'; }
		if (r.startsWith('dano') || r.startsWith('empresarial')) { return 'ubicaciones'; }
		return 'personas';
	}

	/** Reemplaza {{MARCADOR}}. Los marcadores HTML_ se insertan tal cual; el resto se escapa en el HTML. */
	@TestVisible
	static String llenar(String texto, Map<String, String> valores, Boolean html) {
		if (String.isBlank(texto)) { return texto; }
		String r = texto;
		for (String k : valores.keySet()) {
			String v = valores.get(k) == null ? '' : valores.get(k);
			if (k.startsWith('HTML_')) {
				if (!html) { v = ''; }
			} else if (html) {
				v = v.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;');
			}
			r = r.replace('{{' + k + '}}', v);
		}
		return r.replaceAll('\\{\\{[A-Z_]+\\}\\}', '');
	}

	public static String filaPrueba(String correoCliente) {
		String c = String.isBlank(correoCliente) ? 'sin correo registrado'
			: correoCliente.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;');
		return '<tr><td style="background:#FFF4D6;color:#7A5B00;font-size:12px;text-align:center;padding:8px;">'
			+ 'CORREO DE PRUEBA – En producción se enviaría al contratante (' + c + ')</td></tr>';
	}

	static Datetime inicioDia(Date d) {
		return Datetime.newInstance(d, Time.newInstance(0, 0, 0, 0));
	}

	public static Boolean esProduccion() {
		if (produccionPrueba != null) { return produccionPrueba; }
		return String.valueOf(UserInfo.getOrganizationId()).startsWith(ORG_PRODUCCION)
			&& [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox == false;
	}
}
