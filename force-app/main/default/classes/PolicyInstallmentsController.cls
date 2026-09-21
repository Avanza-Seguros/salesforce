/**
 *   @name: PolicyInstallmentsController
 *   @version: 1.0
 *   @creation date: 20/07/2026
 *   @author: Javier Torres - Volestra
 *   @description: Controlador del componente que lista las cuotas de una poliza en la
 *                 pagina de InsurancePolicy. La relacion es de dos niveles
 *                 (InsurancePolicy -> PaymentPlan__c -> PaymentPlanInstallment__c), y
 *                 las listas relacionadas nativas solo muestran hijos directos, por eso
 *                 las cuotas se exponen con este controlador y un LWC en lugar de una
 *                 related list estandar.
 */
public with sharing class PolicyInstallmentsController {
	/**
	 * @creation date: 20/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Devuelve todas las cuotas de los planes de la poliza indicada,
	 *               ordenadas por vencimiento. Incluye de que recibo de la aseguradora viene
	 *               cada una y a cual reemplaza, que es lo que permite agruparlas.
	 * @param policyId: Id de la InsurancePolicy.
	 * @return Lista de PaymentPlanInstallment__c con los campos de cobranza.
	 */
	@AuraEnabled(cacheable=true)
	public static List<PaymentPlanInstallment__c> getInstallmentsByPolicy(
		Id policyId
	) {
		if (policyId == null) {
			return new List<PaymentPlanInstallment__c>();
		}
		return [
			SELECT
				Id,
				Name,
				sequenceNumber__c,
				dueDate__c,
				expectedAmount__c,
				matchedAmount__c,
				outstandingAmount__c,
				installmentStatus__c,
				daysOverdue__c,
				agingStatus__c,
				carrierReceiptNumber__c,
				carrierEndorsementNumber__c,
				carrierInstallmentNumber__c,
				replacesInstallment__c,
				matchedOn__c,
				matchedReceipt__c,
				matchedReceipt__r.Name,
				matchedReceipt__r.receiptDate__c,
				paymentPlan__c,
				paymentPlan__r.Name,
				paymentPlan__r.planStatus__c
			FROM PaymentPlanInstallment__c
			WHERE paymentPlan__r.insurancePolicy__c = :policyId
			ORDER BY dueDate__c ASC NULLS LAST, sequenceNumber__c ASC
		];
	}
}
