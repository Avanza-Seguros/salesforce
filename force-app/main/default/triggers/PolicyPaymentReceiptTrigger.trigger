/**
 *   @name: PolicyPaymentReceiptTrigger
 *   @version: 1.1
 *   @creation date: 15/06/2026
 *   @author: Javier Torres - Volestra
 *   @description: Orquesta los procesos posteriores al insert y update de recibos
 *                 de pago, incluyendo el cierre comercial de la oportunidad vinculada
 *                 y la reversa de un cobro que dejo de ser valido (H201).
 *                 La reversa se engancha a la TRANSICION de estado y no a la accion del
 *                 analista: por eso vive aqui y no en el componente. Cualquier via que
 *                 lleve el recibo de Reconocido a Reversado produce los mismos efectos.
 */
trigger PolicyPaymentReceiptTrigger on PolicyPaymentReceipt__c(
	before update,
	after insert,
	after update
) {
	if (Trigger.isBefore) {
		// Sella autoria y fecha de la reversa antes de guardar, para no gastar un DML
		// adicional sobre los mismos registros.
		PolicyPaymentReceiptReversalService.stampReversalAudit(
			Trigger.new,
			Trigger.oldMap
		);
	} else if (Trigger.isInsert) {
		PolicyPaymentReceiptTriggerHandler.handleAfterInsert(Trigger.new);
		// Un cobro valido nuevo retira la señal comercial de la poliza (H203).
		PolicyPaymentReceiptReversalService.clearSignalOnRecognition(
			Trigger.new,
			null
		);
	} else {
		PolicyPaymentReceiptTriggerHandler.handleAfterUpdate(
			Trigger.new,
			Trigger.oldMap
		);
		PolicyPaymentReceiptReversalService.handleReversals(
			Trigger.new,
			Trigger.oldMap
		);
		PolicyPaymentReceiptReversalService.clearSignalOnRecognition(
			Trigger.new,
			Trigger.oldMap
		);
	}
}
