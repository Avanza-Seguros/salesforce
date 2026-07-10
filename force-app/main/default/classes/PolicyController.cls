/**
 *   @name: PolicyController
 *   @version: 1.0
 *   @creation date: 08/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Apoya al LWC policyCreator: localiza la InsurancePolicy generada por
 *                 el flow del org al pasar la oportunidad a Póliza. La póliza se ubica
 *                 por la cotización origen (SourceQuoteId) y, como respaldo, por las
 *                 cotizaciones de la oportunidad.
 */
public with sharing class PolicyController {

	/**
	 * @creation date: 08/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve el Id de la InsurancePolicy asociada a la cotización o a la
	 *               oportunidad indicadas. Primero busca por SourceQuoteId = quoteId; si no
	 *               la encuentra, busca por las cotizaciones de la oportunidad.
	 * @param quoteId: Id de la cotización aceptada (origen de la póliza). Puede ser null.
	 * @param opportunityId: Id de la oportunidad. Puede ser null.
	 * @return Id de la InsurancePolicy encontrada, o null si no existe.
	 */
	@AuraEnabled(cacheable=false)
	public static Id getPolicyIdByQuote(Id quoteId, Id opportunityId) {
		try {
			// 1) Por la cotización origen (SourceQuoteId).
			if (quoteId != null) {
				List<InsurancePolicy> ps = [
					SELECT Id FROM InsurancePolicy
					WHERE SourceQuoteId = :quoteId
					ORDER BY CreatedDate DESC
					LIMIT 1
				];
				if (!ps.isEmpty()) { return ps[0].Id; }
			}
			// 2) Respaldo: por cualquier cotización de la oportunidad.
			if (opportunityId != null) {
				Set<Id> quoteIds = new Set<Id>();
				for (Quote q : [SELECT Id FROM Quote WHERE OpportunityId = :opportunityId]) {
					quoteIds.add(q.Id);
				}
				if (!quoteIds.isEmpty()) {
					List<InsurancePolicy> ps = [
						SELECT Id FROM InsurancePolicy
						WHERE SourceQuoteId IN :quoteIds
						ORDER BY CreatedDate DESC
						LIMIT 1
					];
					if (!ps.isEmpty()) { return ps[0].Id; }
				}
			}
			return null;
		} catch (Exception e) {
			throw new AuraHandledException('Error al localizar la póliza: ' + e.getMessage());
		}
	}
}