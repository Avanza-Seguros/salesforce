/**
 *   @name: PaymentReconciliationQueueable
 *   @version: 1.0
 *   @creation date: 20/05/2026
 *   @author: Javier Torres - Volestra
 *   @description: Sexto eslabon del pipeline de normalizacion de pagos inbound.
 *                 Crea un registro PaymentReconciliation__c para cada inbound evaluado,
 *                 independientemente del resultado (Conciliado, Revision Manual, Sin Match).
 *                 Garantiza trazabilidad de auditoria para todos los casos. Solo para
 *                 registros con inboundStatus__c = Conciliado encadena a
 *                 PolicyPaymentReceiptQueueable.
 */
public with sharing class PaymentReconciliationQueueable implements Queueable {
	private static final String STATUS_RECONCILED = 'Conciliado';

	private static final String METHOD_EXACT_POLICY_AND_SEQUENCE = 'EXACT_POLICY_AND_SEQUENCE';
	private static final String METHOD_POLICY_DATE_AMOUNT = 'POLICY_DATE_AMOUNT';
	private static final String METHOD_POLICY_AMOUNT = 'POLICY_AMOUNT';
	private static final String METHOD_POLICY_ONLY = 'POLICY_ONLY';
	private static final String METHOD_AMBIGUOUS = 'AMBIGUOUS';

	private static final String MATCH_EXACT_INSTALLMENT = 'Cuota exacta';
	private static final String MATCH_POLICY_AMOUNT = 'Poliza e importe';
	private static final String MATCH_ASSISTED = 'Asistido por candidato';
	private static final String MATCH_MANUAL = 'Decision manual';

	private static final String RECON_STATUS_RECONCILED = 'Conciliado';
	private static final String RECON_STATUS_PROBABLE = 'Probable';
	private static final String RECON_STATUS_REVIEW = 'Requiere revision';
	private static final String RECON_STATUS_NO_MATCH = 'Sin Match';

	private static final String RESULT_PROBABLE_MATCH = 'Match Probable';

	private static final String INBOUND_STATUS_NO_MATCH = 'Sin Match';
	private static final String INBOUND_STATUS_MANUAL_REVIEW = 'Revision Manual';

	@TestVisible
	private static Boolean forceFailureForTest = false;

	private class ReconciliationException extends Exception {
	}

	private Set<Id> inboundPaymentIds;

	/**
	 * @creation date: 20/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Inicializa el job con los IDs de los inbounds evaluados.
	 * @param inboundPaymentIds: Conjunto de IDs de InboundInsurancePayment__c ya evaluados.
	 * @return
	 */
	public PaymentReconciliationQueueable(Set<Id> inboundPaymentIds) {
		this.inboundPaymentIds = inboundPaymentIds;
	}

	/**
	 * @creation date: 20/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Punto de entrada del job. Consulta los inbounds evaluados, verifica
	 *               idempotencia (omite los que ya tienen una conciliacion creada), carga
	 *               datos de cuota candidata, crea PaymentReconciliation__c para cada
	 *               registro sin conciliacion previa y encadena a
	 *               PolicyPaymentReceiptQueueable para los que alcanzaron Conciliado.
	 *               Si ocurre una excepcion en un registro individual ese registro se
	 *               omite sin afectar al resto.
	 * @param context: Contexto de ejecucion del Queueable proporcionado por la plataforma.
	 * @return
	 */
	public void execute(QueueableContext context) {
		List<InboundInsurancePayment__c> payments = [
			SELECT
				Id,
				candidatePolicy__c,
				candidateInstallment__c,
				reconciliationMethod__c,
				reconciliationResult__c,
				confidenceScore__c,
				confidenceBand__c,
				candidateCount__c,
				manualReviewRequired__c,
				inboundStatus__c,
				sourceReceiptNumber__c
			FROM InboundInsurancePayment__c
			WHERE Id IN :inboundPaymentIds
		];

		if (payments.isEmpty()) {
			return;
		}

		Set<Id> alreadyProcessed = new Set<Id>();
		for (PaymentReconciliation__c existing : [
			SELECT inboundPayment__c
			FROM PaymentReconciliation__c
			WHERE inboundPayment__c IN :inboundPaymentIds
		]) {
			alreadyProcessed.add(existing.inboundPayment__c);
		}

		Set<Id> installmentIds = new Set<Id>();
		for (InboundInsurancePayment__c p : payments) {
			if (p.candidateInstallment__c != null) {
				installmentIds.add(p.candidateInstallment__c);
			}
		}

		Map<Id, PaymentPlanInstallment__c> installmentsById = new Map<Id, PaymentPlanInstallment__c>();
		if (!installmentIds.isEmpty()) {
			for (PaymentPlanInstallment__c inst : [
				SELECT Id, paymentPlan__c
				FROM PaymentPlanInstallment__c
				WHERE Id IN :installmentIds
			]) {
				installmentsById.put(inst.Id, inst);
			}
		}

		List<PaymentReconciliation__c> toInsert = new List<PaymentReconciliation__c>();
		Set<Id> reconciledInboundIds = new Set<Id>();

		for (InboundInsurancePayment__c p : payments) {
			if (alreadyProcessed.contains(p.Id)) {
				continue;
			}
			try {
				if (forceFailureForTest) {
					throw new ReconciliationException('Forced failure for test');
				}
				PaymentPlanInstallment__c inst = p.candidateInstallment__c != null
					? installmentsById.get(p.candidateInstallment__c)
					: null;

				PaymentReconciliation__c rec = new PaymentReconciliation__c(
					inboundPayment__c = p.Id,
					insurancePolicy__c = p.candidatePolicy__c,
					paymentPlanInstallment__c = p.candidateInstallment__c,
					paymentPlan__c = inst != null ? inst.paymentPlan__c : null,
					reconciliationStatus__c = deriveReconciliationStatus(p),
					matchMethod__c = deriveMatchMethod(p.reconciliationMethod__c),
					confidenceScore__c = p.confidenceScore__c,
					candidateCount__c = p.candidateCount__c,
					decisionNotes__c = buildDecisionNotes(p)
				);

				toInsert.add(rec);

				if (STATUS_RECONCILED.equals(p.inboundStatus__c)) {
					reconciledInboundIds.add(p.Id);
				}
			} catch (Exception e) {
			}
		}

		if (toInsert.isEmpty()) {
			return;
		}

		insert toInsert;

		Set<Id> reconciledReconciliationIds = new Set<Id>();
		for (PaymentReconciliation__c rec : toInsert) {
			if (reconciledInboundIds.contains(rec.inboundPayment__c)) {
				reconciledReconciliationIds.add(rec.Id);
			}
		}

		if (!reconciledReconciliationIds.isEmpty()) {
			try {
				System.enqueueJob(
					new PolicyPaymentReceiptQueueable(reconciledReconciliationIds)
				);
			} catch (System.AsyncException e) {
			}
		}
	}

	/**
	 * @creation date: 20/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Deriva reconciliationStatus__c a partir del inboundStatus__c y
	 *               reconciliationResult__c. Conciliado -> Conciliado; Sin Match ->
	 *               Sin Match; Revision Manual con Match Probable -> Probable;
	 *               cualquier otro caso de Revision Manual -> Requiere revision.
	 * @param payment: Registro inbound evaluado.
	 * @return Valor del picklist reconciliationStatus__c.
	 */
	private static String deriveReconciliationStatus(
		InboundInsurancePayment__c payment
	) {
		if (STATUS_RECONCILED.equals(payment.inboundStatus__c)) {
			return RECON_STATUS_RECONCILED;
		}
		if (INBOUND_STATUS_NO_MATCH.equals(payment.inboundStatus__c)) {
			return RECON_STATUS_NO_MATCH;
		}
		if (RESULT_PROBABLE_MATCH.equals(payment.reconciliationResult__c)) {
			return RECON_STATUS_PROBABLE;
		}
		return RECON_STATUS_REVIEW;
	}

	/**
	 * @creation date: 20/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Mapea reconciliationMethod__c al picklist restringido matchMethod__c.
	 *               EXACT_POLICY_AND_SEQUENCE -> Cuota exacta;
	 *               POLICY_DATE_AMOUNT y POLICY_AMOUNT -> Poliza e importe;
	 *               POLICY_ONLY y AMBIGUOUS -> Asistido por candidato;
	 *               NO_MATCH y ERROR -> Decision manual.
	 * @param method: Valor de reconciliationMethod__c.
	 * @return Valor del picklist matchMethod__c.
	 */
	private static String deriveMatchMethod(String method) {
		if (METHOD_EXACT_POLICY_AND_SEQUENCE.equals(method)) {
			return MATCH_EXACT_INSTALLMENT;
		}
		if (
			METHOD_POLICY_DATE_AMOUNT.equals(method) ||
			METHOD_POLICY_AMOUNT.equals(method)
		) {
			return MATCH_POLICY_AMOUNT;
		}
		if (METHOD_POLICY_ONLY.equals(method) || METHOD_AMBIGUOUS.equals(method)) {
			return MATCH_ASSISTED;
		}
		return MATCH_MANUAL;
	}

	/**
	 * @creation date: 20/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Construye el texto de notas de decision que resume el resultado
	 *               del proceso de conciliacion para auditoria.
	 * @param payment: Registro inbound evaluado.
	 * @return Texto de notas de decision.
	 */
	private static String buildDecisionNotes(InboundInsurancePayment__c payment) {
		return 'Estado: ' +
			payment.inboundStatus__c +
			'. Metodo: ' +
			payment.reconciliationMethod__c +
			'. Resultado: ' +
			payment.reconciliationResult__c +
			'. Score: ' +
			payment.confidenceScore__c +
			'. Banda: ' +
			payment.confidenceBand__c +
			'.';
	}
}
