/**
 * @creation date: 26/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Siniestros en Claims (FSC), que reemplazan a Control de Folios. Al guardar un siniestro (Claim) toma de
 *               su póliza el contratante, el producto y la aseguradora, y su nombre es su folio (SIN-00001); la fecha de
 *               cierre se pone al cerrarse y se quita al reabrirse. Cada solicitud de pago (PaymentRequest: el folio de un
 *               reembolso, inicial o complementario) toma la póliza del siniestro y un folio consecutivo (SIN-00001-01).
 */
public with sharing class Siniestros {

	// Estatus de Claim que cierran el siniestro (los mismos que FSC marca como cerrados).
	private static final Set<String> CERRADOS = new Set<String>{ 'Cerrado', 'Anulado', 'Rechazado' };

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

	// Aseguradora de la póliza: la de la póliza o, si no la tiene, la de su producto.
	private static String aseguradora(InsurancePolicy p) {
		if (p.Aseguradora__r != null) { return p.Aseguradora__r.Name; }
		return p.Product != null && p.Product.Aseguradora__r != null ? p.Product.Aseguradora__r.Name : null;
	}
}
