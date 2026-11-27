/**
 * @creation date: 26/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Siniestros en Claims (FSC), que reemplazan a Control de Folios. Al guardar un siniestro (Claim) toma de
 *               su póliza el contratante, el producto y la aseguradora, y su nombre es su folio (SIN-00001); la fecha de
 *               cierre se pone al cerrarse y se quita al reabrirse. Cada solicitud de pago (PaymentRequest: el folio de un
 *               reembolso, inicial o complementario) toma la póliza del siniestro y un folio consecutivo (SIN-00001-01).
 *               Automatizaciones que antes hacía Control de Folios:
 *               - Fecha de acuse (InitiationDate): se pone al pasar a Bajo evaluación (ingresado a la aseguradora).
 *               - Avisos por correo (NotificacionesSiniestro): carta de programación y de ingreso hospitalario al pasar a
 *                 Concedido; aviso de reembolso al pasar a Pagado su solicitud de pago.
 *               - Encuesta: al cerrarse (Cerrado o Rechazado) se recuenta en el contacto del titular cuántos siniestros
 *                 tiene (Conteo_de_Folios__c: sus folios de siniestro de Control de Folios más sus siniestros de personas).
 */
public with sharing class Siniestros {

	// Estatus de Claim que cierran el siniestro (los mismos que FSC marca como cerrados).
	private static final Set<String> CERRADOS = new Set<String>{ 'Cerrado', 'Anulado', 'Rechazado' };
	// Cierres que cuentan para la encuesta (un anulado fue un error de captura).
	private static final Set<String> CIERRES_ENCUESTA = new Set<String>{ 'Cerrado', 'Rechazado' };
	private static final String BAJO_EVALUACION = 'Bajo evaluación';
	private static final String CONCEDIDO = 'Concedido';
	private static final String PAGADO = 'Pagado';
	// Aviso que se envía al conceder cada tipo de siniestro.
	private static final Map<String, String> AVISO_AL_CONCEDER = new Map<String, String>{
		'Programación de cirugía' => NotificacionesSiniestro.PROGRAMACION,
		'Pago directo hospitalario' => NotificacionesSiniestro.INGRESO
	};

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Antes de guardar el siniestro: datos de su póliza (si no los trae) y fecha de cierre.
	 * @param nuevos: Trigger.new
	 * @param anteriores: Trigger.oldMap (null al crear)
	 * @return void
	 */
	public static void antesDeGuardar(List<Claim> nuevos, Map<Id, Claim> anteriores) {
		Set<Id> polizas = new Set<Id>();
		for (Claim c : nuevos) {
			Claim ant = anteriores == null ? null : anteriores.get(c.Id);
			if (c.PolicyNumberId != null && (ant == null || ant.PolicyNumberId != c.PolicyNumberId)) { polizas.add(c.PolicyNumberId); }
			Boolean cerrado = CERRADOS.contains(c.Status);
			if (cerrado && c.FinalizedDate == null) { c.FinalizedDate = Datetime.now(); }
			// Reabierto: vuelve a estar en trámite.
			if (!cerrado && ant != null && CERRADOS.contains(ant.Status)) { c.FinalizedDate = null; }
			// Ingresado a la aseguradora: fecha de acuse (si no la capturaron).
			if (c.Status == BAJO_EVALUACION && c.InitiationDate == null && (ant == null || ant.Status != BAJO_EVALUACION)) {
				c.InitiationDate = Datetime.now();
			}
		}
		if (polizas.isEmpty()) { return; }
		Map<Id, InsurancePolicy> porId = new Map<Id, InsurancePolicy>([
			SELECT Id, NameInsuredId, ProductId, Aseguradora__r.Name, Product.Aseguradora__r.Name
			FROM InsurancePolicy WHERE Id IN :polizas
		]);
		for (Claim c : nuevos) {
			InsurancePolicy p = porId.get(c.PolicyNumberId);
			if (p == null) { continue; }
			if (c.AccountId == null) { c.AccountId = p.NameInsuredId; }
			if (c.ProductId == null) { c.ProductId = p.ProductId; }
			if (String.isBlank(c.SourceSystem)) { c.SourceSystem = aseguradora(p); }
		}
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Después de crear el siniestro: su nombre es su folio.
	 * @param nuevos: Trigger.new
	 * @return void
	 */
	public static void despuesDeCrear(List<Claim> nuevos) {
		List<Claim> cambios = new List<Claim>();
		for (Claim c : [SELECT Id, Name, Folio__c FROM Claim WHERE Id IN :nuevos]) {
			if (String.isNotBlank(c.Folio__c) && c.Name != c.Folio__c) { cambios.add(new Claim(Id = c.Id, Name = c.Folio__c)); }
		}
		if (!cambios.isEmpty()) { update cambios; }
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Solicitudes de pago nuevas: la póliza del siniestro y el folio consecutivo del siniestro.
	 * @param nuevas: Trigger.new
	 * @return void
	 */
	public static void antesDeCrearSolicitudes(List<PaymentRequest> nuevas) {
		Set<Id> ids = new Set<Id>();
		for (PaymentRequest r : nuevas) { if (r.ClaimId != null) { ids.add(r.ClaimId); } }
		if (ids.isEmpty()) { return; }
		Map<Id, Claim> siniestros = new Map<Id, Claim>([SELECT Id, Name, PolicyNumberId FROM Claim WHERE Id IN :ids]);
		Map<Id, Integer> cuenta = new Map<Id, Integer>();
		for (AggregateResult ar : [SELECT ClaimId c, COUNT(Id) n FROM PaymentRequest WHERE ClaimId IN :ids GROUP BY ClaimId]) {
			cuenta.put((Id) ar.get('c'), (Integer) ar.get('n'));
		}
		for (PaymentRequest r : nuevas) {
			Claim c = siniestros.get(r.ClaimId);
			if (c == null) { continue; }
			if (r.InsurancePolicyId == null) { r.InsurancePolicyId = c.PolicyNumberId; }
			Integer n = (cuenta.containsKey(c.Id) ? cuenta.get(c.Id) : 0) + 1;
			cuenta.put(c.Id, n);
			r.Name = (c.Name + '-' + String.valueOf(n).leftPad(2, '0')).left(80);
		}
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Después de actualizar siniestros: avisos al conceder (programación e ingreso hospitalario) y conteo
	 *               de la encuesta al cerrarse.
	 * @param nuevos: Trigger.new
	 * @param anteriores: Trigger.oldMap
	 * @return void
	 */
	public static void despuesDeActualizar(List<Claim> nuevos, Map<Id, Claim> anteriores) {
		List<NotificacionesSiniestro.Aviso> avisos = new List<NotificacionesSiniestro.Aviso>();
		Set<Id> titulares = new Set<Id>();
		for (Claim c : nuevos) {
			Claim ant = anteriores.get(c.Id);
			Boolean cambio = ant.Status != c.Status || ant.LossType != c.LossType;
			if (cambio && c.Status == CONCEDIDO && AVISO_AL_CONCEDER.containsKey(c.LossType)) {
				avisos.add(new NotificacionesSiniestro.Aviso(AVISO_AL_CONCEDER.get(c.LossType), c.Id, null));
			}
			if (c.Titular__c != null && ant.Status != c.Status && CIERRES_ENCUESTA.contains(c.Status)) { titulares.add(c.Titular__c); }
		}
		NotificacionesSiniestro.encolar(avisos);
		if (!titulares.isEmpty()) { new SinCompartir().contarSiniestros(titulares); }
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Después de actualizar solicitudes de pago: aviso de reembolso al pasar a Pagado una solicitud de un
	 *               siniestro de reembolso.
	 * @param nuevas: Trigger.new
	 * @param anteriores: Trigger.oldMap
	 * @return void
	 */
	public static void despuesDeActualizarSolicitudes(List<PaymentRequest> nuevas, Map<Id, PaymentRequest> anteriores) {
		Map<Id, Id> pagadas = new Map<Id, Id>();
		for (PaymentRequest r : nuevas) {
			if (r.ClaimId != null && r.Status == PAGADO && anteriores.get(r.Id).Status != PAGADO) { pagadas.put(r.Id, r.ClaimId); }
		}
		if (pagadas.isEmpty()) { return; }
		Map<Id, Claim> reembolsos = new Map<Id, Claim>([SELECT Id FROM Claim WHERE Id IN :pagadas.values() AND LossType = 'Reembolso']);
		List<NotificacionesSiniestro.Aviso> avisos = new List<NotificacionesSiniestro.Aviso>();
		for (Id r : pagadas.keySet()) {
			if (reembolsos.containsKey(pagadas.get(r))) { avisos.add(new NotificacionesSiniestro.Aviso(NotificacionesSiniestro.REEMBOLSO, pagadas.get(r), r)); }
		}
		NotificacionesSiniestro.encolar(avisos);
	}

	// El conteo de la encuesta se guarda en el contacto aunque el ejecutivo no pueda editarlo; un error no detiene el siniestro.
	private without sharing class SinCompartir {
		void contarSiniestros(Set<Id> contactos) {
			Map<Id, Integer> cuenta = new Map<Id, Integer>();
			for (Id i : contactos) { cuenta.put(i, 0); }
			Schema.RecordTypeInfo folios = Schema.SObjectType.Control_de_Folios__c.getRecordTypeInfosByDeveloperName().get('Siniestros');
			if (folios != null) {
				Id rt = folios.getRecordTypeId();
				for (AggregateResult ar : [
					SELECT Titular__c t, COUNT(Id) n FROM Control_de_Folios__c WHERE Titular__c IN :contactos AND RecordTypeId = :rt GROUP BY Titular__c
				]) { cuenta.put((Id) ar.get('t'), cuenta.get((Id) ar.get('t')) + (Integer) ar.get('n')); }
			}
			for (AggregateResult ar : [
				SELECT Titular__c t, COUNT(Id) n FROM Claim WHERE Titular__c IN :contactos AND RecordType.DeveloperName = 'Personas' GROUP BY Titular__c
			]) { cuenta.put((Id) ar.get('t'), cuenta.get((Id) ar.get('t')) + (Integer) ar.get('n')); }
			List<Contact> cambios = new List<Contact>();
			for (Id i : cuenta.keySet()) { cambios.add(new Contact(Id = i, Conteo_de_Folios__c = cuenta.get(i))); }
			for (Database.SaveResult r : Database.update(cambios, false)) {
				if (!r.isSuccess()) { System.debug(LoggingLevel.ERROR, 'Conteo de siniestros no guardado: ' + r.getErrors()[0].getMessage()); }
			}
		}
	}

	// Aseguradora de la póliza: la de la póliza o, si no la tiene, la de su producto.
	private static String aseguradora(InsurancePolicy p) {
		if (p.Aseguradora__r != null) { return p.Aseguradora__r.Name; }
		return p.Product != null && p.Product.Aseguradora__r != null ? p.Product.Aseguradora__r.Name : null;
	}
}
