/**
 *   @name: PaymentPlanInstallmentTrigger
 *   @version: 1.0
 *   @creation date: 11/06/2026
 *   @author: Javier Torres - Volestra
 *   @description: Recalcula el estado del PaymentPlan__c padre cuando sus cuotas
 *                 cambian de estado (insert/update). Delega en
 *                 PaymentPlanInstallmentTriggerHandler.
 */
trigger PaymentPlanInstallmentTrigger on PaymentPlanInstallment__c(
	after insert,
	after update
) {
	if (Trigger.isAfter) {
		PaymentPlanInstallmentTriggerHandler.handleAfterTrigger(
			Trigger.new,
			Trigger.isInsert ? null : Trigger.oldMap
		);
	}
}
