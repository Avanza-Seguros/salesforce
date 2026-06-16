/**
 *   @name: PolicyPaymentReceiptTriggerHandler
 *   @version: 1.0
 *   @creation date: 15/06/2026
 *   @author: Javier Torres - Volestra
 *   @description: Cierra la Opportunity vinculada a la poliza cuando se registra
 *                 un PolicyPaymentReceipt__c reconocido. Navega la cadena
 *                 PolicyPaymentReceipt__c -> InsurancePolicy.SourceOpportunityId -> Opportunity
 *                 y actualiza StageName a Closed Won si la oportunidad esta en
 *                 un estado elegible. La actualizacion es best-effort (allOrNone=false)
 *                 para no bloquear la creacion del recibo ante un fallo comercial.
 */
public with sharing class PolicyPaymentReceiptTriggerHandler {
	private static final String RECEIPT_STATUS_RECOGNIZED = 'Reconocido';
	private static final String STAGE_CLOSED_WON = 'Closed Won';
	private static final String STAGE_CLOSED_LOST = 'Closed Lost';

	/**
	 * @creation date: 15/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Procesa recibos recien insertados buscando los reconocidos
	 *               para cerrar la oportunidad vinculada.
	 * @param newReceipts: Recibos insertados en la transaccion actual.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	public static void handleAfterInsert(
		List<PolicyPaymentReceipt__c> newReceipts
	) {
		processRecognizedReceipts(newReceipts, null);
	}

	/**
	 * @creation date: 15/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Procesa recibos actualizados detectando transiciones hacia
	 *               estado Reconocido para cerrar la oportunidad vinculada.
	 * @param newReceipts: Valores actualizados de los recibos.
	 * @param oldMap: Valores anteriores de los recibos.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	public static void handleAfterUpdate(
		List<PolicyPaymentReceipt__c> newReceipts,
		Map<Id, PolicyPaymentReceipt__c> oldMap
	) {
		processRecognizedReceipts(newReceipts, oldMap);
	}

	/**
	 * @creation date: 15/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Filtra los recibos que acaban de adquirir estado Reconocido
	 *               y delega el cierre de las oportunidades correspondientes.
	 * @param receipts: Recibos de la transaccion actual.
	 * @param oldMap: Valores anteriores; null en contexto de insert.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	private static void processRecognizedReceipts(
		List<PolicyPaymentReceipt__c> receipts,
		Map<Id, PolicyPaymentReceipt__c> oldMap
	) {
		Set<Id> policyIds = new Set<Id>();

		for (PolicyPaymentReceipt__c receipt : receipts) {
			if (!isNewlyRecognized(receipt, oldMap)) {
				continue;
			}

			if (receipt.insurancePolicy__c == null) {
				continue;
			}

			policyIds.add(receipt.insurancePolicy__c);
		}

		if (policyIds.isEmpty()) {
			return;
		}

		closeOpportunitiesForPolicies(policyIds);
	}

	/**
	 * @creation date: 15/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Indica si el recibo acaba de pasar a estado Reconocido en
	 *               esta transaccion, tanto en insert como en update.
	 * @param receipt: Recibo actual.
	 * @param oldMap: Valores anteriores; null en contexto de insert.
	 * @return: Boolean true si el estado acaba de ser Reconocido.
	 * @exception:
	 * @throws:
	 */
	private static Boolean isNewlyRecognized(
		PolicyPaymentReceipt__c receipt,
		Map<Id, PolicyPaymentReceipt__c> oldMap
	) {
		if (receipt.receiptStatus__c != RECEIPT_STATUS_RECOGNIZED) {
			return false;
		}

		if (oldMap == null) {
			return true;
		}

		PolicyPaymentReceipt__c oldReceipt = oldMap.get(receipt.Id);
		return oldReceipt == null ||
			oldReceipt.receiptStatus__c != RECEIPT_STATUS_RECOGNIZED;
	}

	/**
	 * @creation date: 15/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Navega InsurancePolicy.SourceOpportunityId y actualiza a
	 *               Closed Won las oportunidades en estado elegible. Excluye
	 *               oportunidades ya en Closed Won (idempotencia) y Closed Lost
	 *               (no reabrir negocios perdidos). La actualizacion es best-effort.
	 * @param policyIds: IDs de polizas con recibo recien reconocido.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	private static void closeOpportunitiesForPolicies(Set<Id> policyIds) {
		Set<Id> opportunityIds = new Set<Id>();

		for (InsurancePolicy policy : [
			SELECT SourceOpportunityId
			FROM InsurancePolicy
			WHERE Id IN :policyIds AND SourceOpportunityId != NULL
		]) {
			opportunityIds.add(policy.SourceOpportunityId);
		}

		if (opportunityIds.isEmpty()) {
			return;
		}

		List<Opportunity> toUpdate = new List<Opportunity>();

		for (Opportunity opp : [
			SELECT Id, StageName
			FROM Opportunity
			WHERE
				Id IN :opportunityIds
				AND StageName != :STAGE_CLOSED_WON
				AND StageName != :STAGE_CLOSED_LOST
		]) {
			toUpdate.add(new Opportunity(Id = opp.Id, StageName = STAGE_CLOSED_WON));
		}

		if (!toUpdate.isEmpty()) {
			Database.update(toUpdate, false);
		}
	}
}
