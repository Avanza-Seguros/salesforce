/**
 *   @name: PaymentInstallmentMatchQueueable
 *   @version: 1.0
 *   @creation date: 09/06/2026
 *   @author: Javier Torres - Volestra
 *   @description: Octavo eslabon del pipeline de normalizacion de pagos inbound.
 *                 Tras crear el recibo limpio (PolicyPaymentReceipt__c), refleja ese
 *                 resultado en la cuota esperada (PaymentPlanInstallment__c) que el
 *                 recibo satisface: vincula matchedReceipt__c, registra matchedOn__c
 *                 cuando la cuota queda totalmente cubierta y actualiza
 *                 installmentStatus__c a Conciliado en ese caso. Los importes
 *                 matchedAmount__c y outstandingAmount__c son formula y se derivan
 *                 solos al vincular el recibo, por lo que no se escriben aqui.
 *                 MVP de un recibo por cuota: una cuota que ya tiene matchedReceipt__c,
 *                 esta cancelada/condonada o ya conciliada no se modifica; un segundo
 *                 recibo sobre una cuota ya vinculada no la sobrescribe (queda para
 *                 revision manual). La acumulacion de pagos parciales esta fuera de
 *                 alcance.
 */
public with sharing class PaymentInstallmentMatchQueueable implements Queueable {
	private static final String STATUS_PENDING = 'Pendiente';
	private static final String STATUS_OVERDUE = 'Vencido';
	private static final String STATUS_RECONCILED = 'Conciliado';

	private static final Set<String> ELIGIBLE_STATUSES = new Set<String>{
		STATUS_PENDING,
		STATUS_OVERDUE
	};

	@TestVisible
	private static Boolean forceFailureForTest = false;

	private class InstallmentMatchException extends Exception {
	}

	private Set<Id> receiptIds;

	/**
	 * @creation date: 09/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Inicializa el job con los IDs de los recibos recien creados.
	 * @param receiptIds: Conjunto de IDs de PolicyPaymentReceipt__c a aplicar sobre sus cuotas.
	 * @return
	 */
	public PaymentInstallmentMatchQueueable(Set<Id> receiptIds) {
		this.receiptIds = receiptIds;
	}

	/**
	 * @creation date: 09/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Punto de entrada del job. Consulta los recibos con cuota vinculada,
	 *               carga las cuotas candidatas y, para cada cuota elegible (Pendiente o
	 *               Vencido y sin recibo previo), vincula matchedReceipt__c. Si el monto
	 *               del recibo cubre totalmente el importe esperado, marca la cuota como
	 *               Conciliado y sella matchedOn__c; si es parcial, deja el estado y la
	 *               fecha sin tocar (el saldo pendiente se refleja por formula). Si una
	 *               cuota falla, ese registro se omite sin afectar al resto del lote.
	 * @param context: Contexto de ejecucion del Queueable proporcionado por la plataforma.
	 * @return
	 */
	public void execute(QueueableContext context) {
		AppLogger.setJobContext(context == null ? null : context.getJobId());
		System.attachFinalizer(
			CobranzaLog.finalizerFor(CobranzaLog.STAGE_CUOTA, receiptIds)
		);

		List<PolicyPaymentReceipt__c> receipts = [
			SELECT
				Id,
				receiptAmount__c,
				paymentPlanInstallment__c,
				sourceInboundPayment__c
			FROM PolicyPaymentReceipt__c
			WHERE Id IN :receiptIds AND paymentPlanInstallment__c != NULL
		];

		if (receipts.isEmpty()) {
			return;
		}

		Set<Id> installmentIds = new Set<Id>();
		for (PolicyPaymentReceipt__c receipt : receipts) {
			installmentIds.add(receipt.paymentPlanInstallment__c);
		}

		Map<Id, PaymentPlanInstallment__c> installmentsById = new Map<Id, PaymentPlanInstallment__c>(
			[
				SELECT Id, installmentStatus__c, expectedAmount__c, matchedReceipt__c
				FROM PaymentPlanInstallment__c
				WHERE Id IN :installmentIds
			]
		);

		Datetime now = System.now();
		Map<Id, PaymentPlanInstallment__c> updatesById = new Map<Id, PaymentPlanInstallment__c>();
		Set<Id> claimedInstallments = new Set<Id>();

		for (PolicyPaymentReceipt__c receipt : receipts) {
			try {
				if (forceFailureForTest) {
					throw new InstallmentMatchException('Forced failure for test');
				}

				PaymentPlanInstallment__c inst = installmentsById.get(
					receipt.paymentPlanInstallment__c
				);
				if (inst == null) {
					continue;
				}

				if (!isEligible(inst, claimedInstallments)) {
					continue;
				}

				PaymentPlanInstallment__c upd = new PaymentPlanInstallment__c(
					Id = inst.Id,
					matchedReceipt__c = receipt.Id
				);

				if (coversFull(receipt, inst)) {
					upd.installmentStatus__c = STATUS_RECONCILED;
					upd.matchedOn__c = now;
				}

				updatesById.put(inst.Id, upd);
				claimedInstallments.add(inst.Id);
			} catch (Exception e) {
				CobranzaLog.error(
						CobranzaLog.STAGE_CUOTA,
						CobranzaLog.EVENT_INSTALLMENT_MATCH_FAILED,
						e
					)
					.onRecord(receipt.Id)
					.onInbound(receipt.sourceInboundPayment__c);
			}
		}

		Set<Id> stampedInboundIds = new Set<Id>();
		for (PolicyPaymentReceipt__c receipt : receipts) {
			if (receipt.sourceInboundPayment__c != null) {
				stampedInboundIds.add(receipt.sourceInboundPayment__c);
			}
		}
		CobranzaLog.markStage(stampedInboundIds, CobranzaLog.STAGE_CUOTA);

		if (updatesById.isEmpty()) {
			AppLogger.flush();
			return;
		}

		update updatesById.values();

		AppLogger.flush();
	}

	/**
	 * @creation date: 09/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Indica si la cuota puede recibir el recibo: debe estar en estado
	 *               Pendiente o Vencido, no tener un recibo previo vinculado y no haber
	 *               sido reclamada por otro recibo del mismo lote. Protege el MVP de un
	 *               recibo por cuota: las cuotas canceladas, condonadas o ya conciliadas
	 *               y las ya vinculadas quedan para revision manual.
	 * @param inst: Cuota candidata cargada.
	 * @param claimedInstallments: Cuotas ya reclamadas por un recibo en este lote.
	 * @return true si la cuota es elegible para vincular el recibo.
	 */
	private static Boolean isEligible(
		PaymentPlanInstallment__c inst,
		Set<Id> claimedInstallments
	) {
		return ELIGIBLE_STATUSES.contains(inst.installmentStatus__c) &&
			inst.matchedReceipt__c == null &&
			!claimedInstallments.contains(inst.Id);
	}

	/**
	 * @creation date: 09/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Determina si el monto del recibo cubre totalmente el importe
	 *               esperado de la cuota. Si falta alguno de los dos importes, se trata
	 *               como cobertura no total (parcial).
	 * @param receipt: Recibo a aplicar.
	 * @param inst: Cuota candidata.
	 * @return true si receiptAmount__c >= expectedAmount__c.
	 */
	private static Boolean coversFull(
		PolicyPaymentReceipt__c receipt,
		PaymentPlanInstallment__c inst
	) {
		return receipt.receiptAmount__c != null &&
			inst.expectedAmount__c != null &&
			receipt.receiptAmount__c >= inst.expectedAmount__c;
	}
}
