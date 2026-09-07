/**
 *   @name: InboundConfidenceScoreQueueable
 *   @version: 1.0
 *   @creation date: 20/05/2026
 *   @author: Javier Torres - Volestra
 *   @description: Quinto eslabon del pipeline de normalizacion de pagos inbound.
 *                 Calcula confidenceScore__c y confidenceBand__c a partir de
 *                 reconciliationMethod__c. Determina inboundStatus__c (Conciliado,
 *                 Revision Manual o Sin Match) y manualReviewRequired__c segun la
 *                 banda y el reconciliationResult__c. Encadena a
 *                 PaymentReconciliationQueueable solo para registros que alcanzan
 *                 estado Conciliado.
 */
public with sharing class InboundConfidenceScoreQueueable implements Queueable {
	private static final String STATUS_NORMALIZED = 'Normalizado';
	private static final String STATUS_RECONCILED = 'Conciliado';
	private static final String STATUS_MANUAL_REVIEW = 'Revision Manual';
	private static final String STATUS_NO_MATCH = 'Sin Match';

	private static final String METHOD_EXACT_POLICY_AND_SEQUENCE = 'EXACT_POLICY_AND_SEQUENCE';
	private static final String METHOD_POLICY_DATE_AMOUNT = 'POLICY_DATE_AMOUNT';
	private static final String METHOD_POLICY_AMOUNT = 'POLICY_AMOUNT';
	private static final String METHOD_POLICY_ONLY = 'POLICY_ONLY';
	private static final String METHOD_AMBIGUOUS = 'AMBIGUOUS';
	private static final String METHOD_NO_MATCH = 'NO_MATCH';
	private static final String METHOD_ERROR = 'ERROR';

	private static final String REASON_NO_INSTALLMENTS = 'SIN_CUOTAS';

	private static final String RESULT_EXACT_MATCH = 'Match Exacto';
	private static final String RESULT_PROBABLE_MATCH = 'Match Probable';
	private static final String RESULT_NO_MATCH = 'Sin Match';

	private static final String BAND_HIGH = 'Alta';
	private static final String BAND_MEDIUM = 'Media';
	private static final String BAND_LOW = 'Baja';

	private static final Map<String, Integer> METHOD_SCORES = new Map<String, Integer>{
		METHOD_EXACT_POLICY_AND_SEQUENCE => 95,
		METHOD_POLICY_DATE_AMOUNT => 85,
		METHOD_POLICY_AMOUNT => 65,
		METHOD_POLICY_ONLY => 45,
		METHOD_AMBIGUOUS => 25,
		METHOD_NO_MATCH => 0,
		METHOD_ERROR => 0
	};

	@TestVisible
	private static Boolean forceFailureForTest = false;

	private class ConfidenceScoreException extends Exception {
	}

	private Set<Id> inboundPaymentIds;

	/**
	 * @creation date: 20/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Inicializa el job con los IDs de los registros a clasificar.
	 * @param inboundPaymentIds: Conjunto de IDs de InboundInsurancePayment__c en estado Normalizado.
	 * @return
	 */
	public InboundConfidenceScoreQueueable(Set<Id> inboundPaymentIds) {
		this.inboundPaymentIds = inboundPaymentIds;
	}

	/**
	 * @creation date: 20/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Punto de entrada del job. Consulta los registros en estado
	 *               Normalizado, calcula el score y la banda de confianza segun el
	 *               metodo de conciliacion, y determina inboundStatus__c y
	 *               manualReviewRequired__c. Si ocurre una excepcion en un registro
	 *               individual, ese registro queda con score 0, banda Baja,
	 *               manualReviewRequired__c=true y estado Revision Manual sin afectar
	 *               al resto del lote. Encadena a PaymentReconciliationQueueable con
	 *               los IDs de los registros que alcanzaron estado Conciliado.
	 * @param context: Contexto de ejecucion del Queueable proporcionado por la plataforma.
	 * @return
	 */
	public void execute(QueueableContext context) {
		AppLogger.setJobContext(context == null ? null : context.getJobId());
		System.attachFinalizer(
			CobranzaLog.finalizerFor(CobranzaLog.STAGE_SCORE, inboundPaymentIds)
		);

		List<InboundInsurancePayment__c> payments = [
			SELECT
				Id,
				reconciliationMethod__c,
				reconciliationResult__c,
				installmentMatchReason__c,
				candidateInstallment__c
			FROM InboundInsurancePayment__c
			WHERE Id IN :inboundPaymentIds AND inboundStatus__c = :STATUS_NORMALIZED
		];

		if (payments.isEmpty()) {
			return;
		}

		List<InboundInsurancePayment__c> toUpdate = new List<InboundInsurancePayment__c>();
		for (InboundInsurancePayment__c p : payments) {
			InboundInsurancePayment__c rec = new InboundInsurancePayment__c(
				Id = p.Id
			);
			try {
				if (forceFailureForTest) {
					throw new ConfidenceScoreException('Forced failure for test');
				}
				applyConfidenceScore(rec, p);
			} catch (Exception e) {
				rec.confidenceScore__c = 0;
				rec.confidenceBand__c = BAND_LOW;
				rec.candidateCount__c = 0;
				rec.manualReviewRequired__c = true;
				rec.inboundStatus__c = STATUS_MANUAL_REVIEW;
				CobranzaLog.error(
						CobranzaLog.STAGE_SCORE,
						CobranzaLog.EVENT_SCORE_FAILED,
						e
					)
					.onInbound(p.Id);
			}
			rec.pipelineStage__c = CobranzaLog.STAGE_SCORE;
			toUpdate.add(rec);
		}

		update toUpdate;

		Set<Id> allIds = new Set<Id>();
		for (InboundInsurancePayment__c rec : toUpdate) {
			allIds.add(rec.Id);
		}
		try {
			System.enqueueJob(new PaymentReconciliationQueueable(allIds));
		} catch (System.AsyncException e) {
			CobranzaLog.chainBreak(
				CobranzaLog.STAGE_SCORE,
				e,
				'PaymentReconciliationQueueable',
				allIds
			);
		}

		AppLogger.flush();
	}

	/**
	 * @creation date: 20/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Calcula el score de confianza, deriva la banda y determina el
	 *               estado final del registro. El score se obtiene del mapa de metodos
	 *               (95 para EXACT_POLICY_AND_SEQUENCE, 85 POLICY_DATE_AMOUNT, 65
	 *               POLICY_AMOUNT, 45 POLICY_ONLY, 25 AMBIGUOUS, 0 NO_MATCH/ERROR).
	 *               La banda es Alta para score>=80, Media para >=40, Baja para <40.
	 *               El estado final se determina por la combinacion de banda y
	 *               reconciliationResult__c.
	 * @param rec: Registro de salida a poblar (solo Id preestablecido).
	 * @param payment: Registro fuente con los campos evaluados.
	 * @return
	 */
	private static void applyConfidenceScore(
		InboundInsurancePayment__c rec,
		InboundInsurancePayment__c payment
	) {
		String method = payment.reconciliationMethod__c;
		Integer score = METHOD_SCORES.containsKey(method)
			? METHOD_SCORES.get(method)
			: 0;

		rec.confidenceScore__c = score;
		rec.candidateCount__c = deriveCandidateCount(
			method,
			payment.installmentMatchReason__c
		);

		String band;
		if (score >= 80) {
			band = BAND_HIGH;
		} else if (score >= 40) {
			band = BAND_MEDIUM;
		} else {
			band = BAND_LOW;
		}
		rec.confidenceBand__c = band;

		String result = payment.reconciliationResult__c;

		if (BAND_HIGH.equals(band) && RESULT_EXACT_MATCH.equals(result)) {
			rec.inboundStatus__c = STATUS_RECONCILED;
			rec.manualReviewRequired__c = false;
		} else if (
			BAND_MEDIUM.equals(band) && RESULT_PROBABLE_MATCH.equals(result)
		) {
			rec.inboundStatus__c = STATUS_MANUAL_REVIEW;
			rec.manualReviewRequired__c = true;
		} else if (BAND_LOW.equals(band) && RESULT_NO_MATCH.equals(result)) {
			rec.inboundStatus__c = STATUS_NO_MATCH;
			rec.manualReviewRequired__c = true;
		} else {
			rec.inboundStatus__c = STATUS_MANUAL_REVIEW;
			rec.manualReviewRequired__c = true;
		}
	}

	/**
	 * @creation date: 20/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Deriva candidateCount__c segun el metodo de conciliacion y la
	 *               razon de match de cuota. NO_MATCH y SIN_CUOTAS producen 0 (no hubo
	 *               candidatos evaluables). AMBIGUOUS produce 2 (empate entre cuotas).
	 *               Cualquier otro caso produce 1 (un unico candidato, ya sea ganador
	 *               confirmado o con score insuficiente).
	 * @param method: reconciliationMethod__c del pago.
	 * @param installmentMatchReason: installmentMatchReason__c del pago.
	 * @return Numero de candidatos relevantes.
	 */
	private static Integer deriveCandidateCount(
		String method,
		String installmentMatchReason
	) {
		if (METHOD_NO_MATCH.equals(method)) {
			return 0;
		}
		if (REASON_NO_INSTALLMENTS.equals(installmentMatchReason)) {
			return 0;
		}
		if (METHOD_AMBIGUOUS.equals(method)) {
			return 2;
		}
		return 1;
	}
}
