/**
 *   @name: InboundReconciliationRulesQueueable
 *   @version: 1.0
 *   @creation date: 19/05/2026
 *   @author: Javier Torres - Volestra
 *   @description: Cuarto eslabon del pipeline de normalizacion de pagos inbound.
 *                 Aplica las reglas MVP de conciliacion sobre registros en estado
 *                 Normalizado que ya tienen candidatePolicy__c e installmentMatchReason__c
 *                 resueltos. Evalua las reglas en orden de mayor a menor confianza
 *                 y escribe reconciliationMethod__c, reconciliationResult__c y
 *                 reconciledAt__c. No modifica inboundStatus__c; eso es
 *                 responsabilidad de InboundConfidenceScoreQueueable. Encadena a
 *                 InboundConfidenceScoreQueueable al terminar.
 */
public with sharing class InboundReconciliationRulesQueueable implements Queueable {
	private static final String STATUS_NORMALIZED = 'Normalizado';

	private static final String REASON_LOW_SCORE = 'SCORE_BAJO';
	private static final String REASON_TIE = 'EMPATE';
	private static final String REASON_NO_INSTALLMENTS = 'SIN_CUOTAS';

	private static final String METHOD_EXACT_POLICY_AND_SEQUENCE = 'EXACT_POLICY_AND_SEQUENCE';
	private static final String METHOD_POLICY_DATE_AMOUNT = 'POLICY_DATE_AMOUNT';
	private static final String METHOD_POLICY_AMOUNT = 'POLICY_AMOUNT';
	private static final String METHOD_POLICY_ONLY = 'POLICY_ONLY';
	private static final String METHOD_AMBIGUOUS = 'AMBIGUOUS';
	private static final String METHOD_NO_MATCH = 'NO_MATCH';
	private static final String METHOD_ERROR = 'ERROR';

	private static final String RESULT_EXACT_MATCH = 'Match Exacto';
	private static final String RESULT_PROBABLE_MATCH = 'Match Probable';
	private static final String RESULT_NO_MATCH = 'Sin Match';
	private static final String RESULT_MANUAL_REVIEW = 'Revision Manual';

	@TestVisible
	private static Boolean forceFailureForTest = false;

	private class ReconciliationRulesException extends Exception {
	}

	private Set<Id> inboundPaymentIds;

	/**
	 * @creation date: 19/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Inicializa el job con los IDs de los registros a clasificar.
	 * @param inboundPaymentIds: Conjunto de IDs de InboundInsurancePayment__c en estado Normalizado.
	 * @return
	 */
	public InboundReconciliationRulesQueueable(Set<Id> inboundPaymentIds) {
		this.inboundPaymentIds = inboundPaymentIds;
	}

	/**
	 * @creation date: 19/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Punto de entrada del job. Consulta los registros en estado
	 *               Normalizado, carga los datos de las cuotas candidatas y aplica
	 *               las reglas MVP en orden de prioridad. Escribe reconciliationMethod__c,
	 *               reconciliationResult__c y reconciledAt__c. Si ocurre una excepcion
	 *               en un registro individual, ese registro queda con ERROR y Revision
	 *               Manual sin afectar al resto del lote. Encadena a
	 *               InboundConfidenceScoreQueueable con todos los IDs del lote.
	 * @param context: Contexto de ejecucion del Queueable proporcionado por la plataforma.
	 * @return
	 */
	public void execute(QueueableContext context) {
		AppLogger.setJobContext(context == null ? null : context.getJobId());
		System.attachFinalizer(
			CobranzaLog.finalizerFor(CobranzaLog.STAGE_REGLAS, inboundPaymentIds)
		);

		List<InboundInsurancePayment__c> payments = [
			SELECT
				Id,
				candidatePolicy__c,
				candidateInstallment__c,
				installmentMatchReason__c,
				sourceInstallmentNumber__c,
				sourceDueDate__c,
				sourceAmount__c
			FROM InboundInsurancePayment__c
			WHERE Id IN :inboundPaymentIds AND inboundStatus__c = :STATUS_NORMALIZED
		];

		if (payments.isEmpty()) {
			return;
		}

		Set<Id> installmentIds = new Set<Id>();
		for (InboundInsurancePayment__c p : payments) {
			if (p.candidateInstallment__c != null) {
				installmentIds.add(p.candidateInstallment__c);
			}
		}

		Map<Id, PaymentPlanInstallment__c> installmentsById = loadInstallments(
			installmentIds
		);

		List<InboundInsurancePayment__c> toUpdate = new List<InboundInsurancePayment__c>();
		Datetime now = System.now();

		for (InboundInsurancePayment__c p : payments) {
			InboundInsurancePayment__c rec = new InboundInsurancePayment__c(
				Id = p.Id
			);
			try {
				if (forceFailureForTest) {
					throw new ReconciliationRulesException('Forced failure for test');
				}
				applyRules(rec, p, installmentsById, now);
			} catch (Exception e) {
				rec.reconciliationMethod__c = METHOD_ERROR;
				rec.reconciliationResult__c = RESULT_MANUAL_REVIEW;
				rec.reconciledAt__c = now;
				CobranzaLog.error(
						CobranzaLog.STAGE_REGLAS,
						CobranzaLog.EVENT_RULES_EVALUATION_FAILED,
						e
					)
					.onInbound(p.Id);
			}
			rec.pipelineStage__c = CobranzaLog.STAGE_REGLAS;
			toUpdate.add(rec);
		}

		update toUpdate;

		Set<Id> allIds = new Set<Id>();
		for (InboundInsurancePayment__c rec : toUpdate) {
			allIds.add(rec.Id);
		}
		try {
			System.enqueueJob(new InboundConfidenceScoreQueueable(allIds));
		} catch (System.AsyncException e) {
			CobranzaLog.chainBreak(
				CobranzaLog.STAGE_REGLAS,
				e,
				'InboundConfidenceScoreQueueable',
				allIds
			);
		}

		AppLogger.flush();
	}

	/**
	 * @creation date: 19/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Evalua las reglas MVP en orden de prioridad y popula
	 *               reconciliationMethod__c, reconciliationResult__c y reconciledAt__c
	 *               en el registro de salida. La primera regla satisfecha termina
	 *               la evaluacion. Reglas: NO_MATCH, AMBIGUOUS,
	 *               EXACT_POLICY_AND_SEQUENCE, POLICY_DATE_AMOUNT, POLICY_AMOUNT,
	 *               POLICY_ONLY.
	 * @param rec: Registro de salida a poblar (solo Id preestablecido).
	 * @param payment: Registro fuente con los campos evaluados.
	 * @param installmentsById: Mapa de Id a PaymentPlanInstallment__c candidatas cargadas.
	 * @param now: Timestamp de ejecucion del lote.
	 * @return
	 */
	private static void applyRules(
		InboundInsurancePayment__c rec,
		InboundInsurancePayment__c payment,
		Map<Id, PaymentPlanInstallment__c> installmentsById,
		Datetime now
	) {
		rec.reconciledAt__c = now;

		if (payment.candidatePolicy__c == null) {
			rec.reconciliationMethod__c = METHOD_NO_MATCH;
			rec.reconciliationResult__c = RESULT_NO_MATCH;
			return;
		}

		if (REASON_TIE.equals(payment.installmentMatchReason__c)) {
			rec.reconciliationMethod__c = METHOD_AMBIGUOUS;
			rec.reconciliationResult__c = RESULT_MANUAL_REVIEW;
			return;
		}

		PaymentPlanInstallment__c inst = payment.candidateInstallment__c != null
			? installmentsById.get(payment.candidateInstallment__c)
			: null;

		if (inst != null && sequenceMatches(payment, inst)) {
			rec.reconciliationMethod__c = METHOD_EXACT_POLICY_AND_SEQUENCE;
			rec.reconciliationResult__c = RESULT_EXACT_MATCH;
			return;
		}

		if (
			inst != null &&
			dateMatches(payment, inst) &&
			amountMatches(payment, inst)
		) {
			rec.reconciliationMethod__c = METHOD_POLICY_DATE_AMOUNT;
			rec.reconciliationResult__c = RESULT_EXACT_MATCH;
			return;
		}

		if (inst != null && amountMatches(payment, inst)) {
			rec.reconciliationMethod__c = METHOD_POLICY_AMOUNT;
			rec.reconciliationResult__c = RESULT_PROBABLE_MATCH;
			return;
		}

		rec.reconciliationMethod__c = METHOD_POLICY_ONLY;
		rec.reconciliationResult__c = RESULT_PROBABLE_MATCH;
	}

	/**
	 * @creation date: 19/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Evalua si el numero de secuencia del inbound coincide exactamente
	 *               con el sequenceNumber__c de la cuota candidata. Convierte el
	 *               campo texto a Decimal para la comparacion. Retorna false ante
	 *               cualquier valor nulo o error de conversion.
	 * @param payment: Registro inbound con sourceInstallmentNumber__c a evaluar.
	 * @param inst: Cuota candidata con sequenceNumber__c a comparar.
	 * @return true si los numeros de secuencia coinciden exactamente.
	 */
	private static Boolean sequenceMatches(
		InboundInsurancePayment__c payment,
		PaymentPlanInstallment__c inst
	) {
		if (
			payment.sourceInstallmentNumber__c == null ||
			inst.sequenceNumber__c == null
		) {
			return false;
		}
		try {
			return Decimal.valueOf(payment.sourceInstallmentNumber__c.trim()) ==
				inst.sequenceNumber__c;
		} catch (Exception e) {
			// Numero de cuota no numerico: condicion de dato esperada, no un fallo. La
			// advertencia ya se emitio en el eslabon de cuota candidata, una vez por pago.
			return false;
		}
	}

	/**
	 * @creation date: 19/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Evalua si la fecha de vencimiento del inbound coincide
	 *               exactamente con el dueDate__c de la cuota candidata.
	 * @param payment: Registro inbound con sourceDueDate__c a evaluar.
	 * @param inst: Cuota candidata con dueDate__c a comparar.
	 * @return true si las fechas son identicas.
	 */
	private static Boolean dateMatches(
		InboundInsurancePayment__c payment,
		PaymentPlanInstallment__c inst
	) {
		return payment.sourceDueDate__c != null &&
			inst.dueDate__c != null &&
			payment.sourceDueDate__c == inst.dueDate__c;
	}

	/**
	 * @creation date: 19/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Evalua si el monto del inbound coincide exactamente con el
	 *               expectedAmount__c de la cuota candidata.
	 * @param payment: Registro inbound con sourceAmount__c a evaluar.
	 * @param inst: Cuota candidata con expectedAmount__c a comparar.
	 * @return true si los montos son identicos.
	 */
	private static Boolean amountMatches(
		InboundInsurancePayment__c payment,
		PaymentPlanInstallment__c inst
	) {
		return payment.sourceAmount__c != null &&
			inst.expectedAmount__c != null &&
			payment.sourceAmount__c == inst.expectedAmount__c;
	}

	/**
	 * @creation date: 19/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Carga los datos de las cuotas candidatas necesarios para
	 *               evaluar las reglas de conciliacion. Solo consulta las cuotas
	 *               cuyos IDs fueron resueltos como candidateInstallment__c.
	 * @param ids: Conjunto de IDs de PaymentPlanInstallment__c a cargar.
	 * @return Mapa de Id a PaymentPlanInstallment__c con los campos de evaluacion.
	 */
	private static Map<Id, PaymentPlanInstallment__c> loadInstallments(
		Set<Id> ids
	) {
		if (ids.isEmpty()) {
			return new Map<Id, PaymentPlanInstallment__c>();
		}
		return new Map<Id, PaymentPlanInstallment__c>(
			[
				SELECT Id, sequenceNumber__c, dueDate__c, expectedAmount__c
				FROM PaymentPlanInstallment__c
				WHERE Id IN :ids
			]
		);
	}
}
