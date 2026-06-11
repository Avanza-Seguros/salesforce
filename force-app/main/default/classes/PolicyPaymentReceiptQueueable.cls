/**
 *   @name: PolicyPaymentReceiptQueueable
 *   @version: 1.0
 *   @creation date: 20/05/2026
 *   @author: Javier Torres - Volestra
 *   @description: Septimo eslabon del pipeline de normalizacion de pagos inbound.
 *                 Crea un registro PolicyPaymentReceipt__c para cada conciliacion
 *                 que alcanzo estado Conciliado. Solo se ejecuta para registros
 *                 conciliados automaticamente. Garantiza idempotencia verificando
 *                 resultingReceipt__c antes de crear. Actualiza
 *                 PaymentReconciliation__c.resultingReceipt__c con el ID del recibo
 *                 creado. Encadena a PaymentInstallmentMatchQueueable con los recibos
 *                 generados para reflejar el resultado en la cuota esperada.
 */
public with sharing class PolicyPaymentReceiptQueueable implements Queueable {
	private static final String RECEIPT_STATUS_RECOGNIZED = 'Reconocido';

	@TestVisible
	private static Boolean forceFailureForTest = false;

	private class ReceiptCreationException extends Exception {
	}

	private Set<Id> reconciliationIds;

	/**
	 * @creation date: 20/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Inicializa el job con los IDs de las conciliaciones aprobadas.
	 * @param reconciliationIds: Conjunto de IDs de PaymentReconciliation__c con resultado Conciliado.
	 * @return
	 */
	public PolicyPaymentReceiptQueueable(Set<Id> reconciliationIds) {
		this.reconciliationIds = reconciliationIds;
	}

	/**
	 * @creation date: 20/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Punto de entrada del job. Consulta las conciliaciones pendientes
	 *               de recibo (resultingReceipt__c = null), crea un
	 *               PolicyPaymentReceipt__c por cada una, y actualiza
	 *               PaymentReconciliation__c.resultingReceipt__c con el ID generado.
	 *               Si ocurre una excepcion en un registro individual ese registro se
	 *               omite sin afectar al resto.
	 * @param context: Contexto de ejecucion del Queueable proporcionado por la plataforma.
	 * @return
	 */
	public void execute(QueueableContext context) {
		List<PaymentReconciliation__c> reconciliations = [
			SELECT
				Id,
				insurancePolicy__c,
				paymentPlan__c,
				paymentPlanInstallment__c,
				resultingReceipt__c,
				inboundPayment__c,
				inboundPayment__r.sourceAmount__c,
				inboundPayment__r.sourcePaymentDate__c,
				inboundPayment__r.sourceReceiptNumber__c
			FROM PaymentReconciliation__c
			WHERE Id IN :reconciliationIds AND resultingReceipt__c = NULL
		];

		if (reconciliations.isEmpty()) {
			return;
		}

		List<PolicyPaymentReceipt__c> toInsert = new List<PolicyPaymentReceipt__c>();
		List<PaymentReconciliation__c> processedReconciliations = new List<PaymentReconciliation__c>();

		for (PaymentReconciliation__c recon : reconciliations) {
			try {
				if (forceFailureForTest) {
					throw new ReceiptCreationException('Forced failure for test');
				}

				PolicyPaymentReceipt__c receipt = new PolicyPaymentReceipt__c(
					insurancePolicy__c = recon.insurancePolicy__c,
					sourceInboundPayment__c = recon.inboundPayment__c,
					paymentReconciliation__c = recon.Id,
					paymentPlan__c = recon.paymentPlan__c,
					paymentPlanInstallment__c = recon.paymentPlanInstallment__c,
					receiptDate__c = recon.inboundPayment__r.sourcePaymentDate__c,
					receiptAmount__c = recon.inboundPayment__r.sourceAmount__c,
					receiptStatus__c = RECEIPT_STATUS_RECOGNIZED,
					receiptNumber__c = recon.inboundPayment__r.sourceReceiptNumber__c
				);

				toInsert.add(receipt);
				processedReconciliations.add(recon);
			} catch (Exception e) {
			}
		}

		if (toInsert.isEmpty()) {
			return;
		}

		insert toInsert;

		List<PaymentReconciliation__c> toUpdate = new List<PaymentReconciliation__c>();
		Set<Id> receiptIds = new Set<Id>();
		for (Integer i = 0; i < toInsert.size(); i++) {
			toUpdate.add(
				new PaymentReconciliation__c(
					Id = processedReconciliations[i].Id,
					resultingReceipt__c = toInsert[i].Id
				)
			);
			receiptIds.add(toInsert[i].Id);
		}

		update toUpdate;

		if (!receiptIds.isEmpty()) {
			try {
				System.enqueueJob(new PaymentInstallmentMatchQueueable(receiptIds));
			} catch (System.AsyncException e) {
			}
		}
	}
}
