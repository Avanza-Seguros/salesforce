/**
 *   @name: PolicyPaymentReceiptTrigger
 *   @version: 1.0
 *   @creation date: 15/06/2026
 *   @author: Javier Torres - Volestra
 *   @description: Orquesta los procesos posteriores al insert y update de recibos
 *                 de pago, incluyendo el cierre comercial de la oportunidad vinculada.
 */
trigger PolicyPaymentReceiptTrigger on PolicyPaymentReceipt__c(
	after insert,
	after update
) {
	if (Trigger.isInsert) {
		PolicyPaymentReceiptTriggerHandler.handleAfterInsert(Trigger.new);
	} else if (Trigger.isUpdate) {
		PolicyPaymentReceiptTriggerHandler.handleAfterUpdate(
			Trigger.new,
			Trigger.oldMap
		);
	}
}
