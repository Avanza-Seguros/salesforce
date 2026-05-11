/**
 *   @name: InboundInstallmentCandidateQueueable
 *   @version: 1.0
 *   @creation date: 07/05/2026
 *   @author: Javier Torres - Volestra
 *   @description: Tercer eslabon del pipeline de normalizacion de pagos inbound.
 *                 Identifica la cuota candidata (candidateInstallment__c) para
 *                 pagos en estado Normalizado que ya tienen candidatePolicy__c resuelto.
 *                 Aplica un algoritmo de scoring multi-senal sobre cuotas conciliables
 *                 (Pendiente, Vencido) de planes activos (Activo): secuencia exacta
 *                 (+6), fecha exacta (+3), monto exacto (+2), fecha proxima 7 dias (+1),
 *                 monto proximo 5% (+1). Asigna la cuota solo si tiene el puntaje mas
 *                 alto, supera el minimo de 3 puntos y no hay empate. No modifica
 *                 inboundStatus__c; solo actualiza candidateInstallment__c.
 */
public with sharing class InboundInstallmentCandidateQueueable implements Queueable {
	private static final String STATUS_NORMALIZED = 'Normalizado';
	private static final Set<String> ACTIVE_PLAN_STATUSES = new Set<String>{
		'Activo'
	};
	private static final Set<String> CONCILIABLE_INSTALLMENT_STATUSES = new Set<String>{
		'Pendiente',
		'Vencido'
	};
	private static final Integer DATE_TOLERANCE_DAYS = 7;
	private static final Decimal AMOUNT_TOLERANCE_PCT = 0.05;
	private static final Integer SCORE_SEQUENCE_EXACT = 6;
	private static final Integer SCORE_DATE_EXACT = 3;
	private static final Integer SCORE_AMOUNT_EXACT = 2;
	private static final Integer SCORE_DATE_CLOSE = 1;
	private static final Integer SCORE_AMOUNT_CLOSE = 1;
	private static final Integer MINIMUM_CANDIDATE_SCORE = 3;

	@TestVisible
	private static Boolean forceFailureForTest = false;

	private class InstallmentMatchException extends Exception {
	}

	private Set<Id> inboundPaymentIds;

	/**
	 * @creation date: 07/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Inicializa el job con los IDs de los registros a enriquecer.
	 * @param inboundPaymentIds: Conjunto de IDs de InboundInsurancePayment__c en estado Normalizado.
	 * @return
	 */
	public InboundInstallmentCandidateQueueable(Set<Id> inboundPaymentIds) {
		this.inboundPaymentIds = inboundPaymentIds;
	}

	/**
	 * @creation date: 07/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Punto de entrada del job. Consulta los registros en estado
	 *               Normalizado, carga las cuotas conciliables de los planes activos
	 *               vinculados a las polizas candidatas y aplica el algoritmo de
	 *               scoring para asignar candidateInstallment__c. Solo asigna si hay
	 *               un unico ganador con puntaje mayor o igual al minimo. Si ocurre
	 *               una excepcion en un registro individual, candidateInstallment__c
	 *               queda en null sin afectar al resto del lote ni cambiar el estado
	 *               del registro.
	 * @param context: Contexto de ejecucion del Queueable proporcionado por la plataforma.
	 * @return
	 */
	public void execute(QueueableContext context) {
		List<InboundInsurancePayment__c> payments = [
			SELECT
				Id,
				candidatePolicy__c,
				sourceInstallmentNumber__c,
				sourceDueDate__c,
				sourceAmount__c
			FROM InboundInsurancePayment__c
			WHERE Id IN :inboundPaymentIds AND inboundStatus__c = :STATUS_NORMALIZED
		];

		if (payments.isEmpty()) {
			return;
		}

		Set<Id> policyIds = new Set<Id>();
		for (InboundInsurancePayment__c p : payments) {
			if (p.candidatePolicy__c != null) {
				policyIds.add(p.candidatePolicy__c);
			}
		}

		Map<Id, List<PaymentPlanInstallment__c>> installmentsByPolicy = loadConciliableInstallmentsByPolicy(
			policyIds
		);

		List<InboundInsurancePayment__c> toUpdate = new List<InboundInsurancePayment__c>();

		for (InboundInsurancePayment__c p : payments) {
			InboundInsurancePayment__c rec = new InboundInsurancePayment__c(
				Id = p.Id
			);
			try {
				if (forceFailureForTest) {
					throw new InstallmentMatchException('Forced failure for test');
				}
				rec.candidateInstallment__c = bestInstallmentMatch(
					p,
					installmentsByPolicy
				);
			} catch (Exception e) {
				rec.candidateInstallment__c = null;
			}
			toUpdate.add(rec);
		}

		update toUpdate;
	}

	/**
	 * @creation date: 07/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Carga las cuotas conciliables de los planes activos vinculados a
	 *               las polizas indicadas, agrupadas por ID de poliza. Usa 2 consultas
	 *               separadas: primero obtiene los planes en estado Activo y luego las
	 *               cuotas en estados conciliables (Pendiente, Vencido).
	 * @param policyIds: Conjunto de IDs de InsurancePolicy candidatas resueltas.
	 * @return Mapa de policyId a lista de PaymentPlanInstallment__c conciliables de esa poliza.
	 */
	private static Map<Id, List<PaymentPlanInstallment__c>> loadConciliableInstallmentsByPolicy(
		Set<Id> policyIds
	) {
		Map<Id, List<PaymentPlanInstallment__c>> result = new Map<Id, List<PaymentPlanInstallment__c>>();
		if (policyIds.isEmpty()) {
			return result;
		}
		Map<Id, Id> policyByPlan = new Map<Id, Id>();
		for (PaymentPlan__c plan : [
			SELECT Id, insurancePolicy__c
			FROM PaymentPlan__c
			WHERE
				insurancePolicy__c IN :policyIds
				AND planStatus__c IN :ACTIVE_PLAN_STATUSES
		]) {
			policyByPlan.put(plan.Id, plan.insurancePolicy__c);
		}
		if (policyByPlan.isEmpty()) {
			return result;
		}
		for (PaymentPlanInstallment__c inst : [
			SELECT
				Id,
				sequenceNumber__c,
				dueDate__c,
				expectedAmount__c,
				installmentStatus__c,
				periodStartDate__c,
				periodEndDate__c,
				paymentPlan__c
			FROM PaymentPlanInstallment__c
			WHERE
				paymentPlan__c IN :policyByPlan.keySet()
				AND installmentStatus__c IN :CONCILIABLE_INSTALLMENT_STATUSES
		]) {
			Id policyId = policyByPlan.get(inst.paymentPlan__c);
			if (policyId == null) {
				continue;
			}
			if (!result.containsKey(policyId)) {
				result.put(policyId, new List<PaymentPlanInstallment__c>());
			}
			result.get(policyId).add(inst);
		}
		return result;
	}

	/**
	 * @creation date: 07/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Evalua todas las cuotas conciliables de la poliza candidata del
	 *               pago y retorna el ID de la mejor cuota si hay un unico ganador
	 *               con puntaje igual o superior al minimo requerido. Retorna null si
	 *               no hay poliza candidata, si no hay cuotas, si el mejor puntaje
	 *               es menor al minimo o si hay empate en el puntaje maximo.
	 * @param payment: Registro inbound a resolver.
	 * @param installmentsByPolicy: Cuotas conciliables agrupadas por poliza.
	 * @return ID de la cuota candidata con mayor puntaje univoco, o null.
	 */
	private static Id bestInstallmentMatch(
		InboundInsurancePayment__c payment,
		Map<Id, List<PaymentPlanInstallment__c>> installmentsByPolicy
	) {
		if (payment.candidatePolicy__c == null) {
			return null;
		}
		List<PaymentPlanInstallment__c> installments = installmentsByPolicy.get(
			payment.candidatePolicy__c
		);
		if (installments == null || installments.isEmpty()) {
			return null;
		}

		Integer topScore = 0;
		Id topId = null;
		Integer topCount = 0;

		for (PaymentPlanInstallment__c inst : installments) {
			Integer score = scoreInstallment(payment, inst);
			if (score > topScore) {
				topScore = score;
				topId = inst.Id;
				topCount = 1;
			} else if (score == topScore && score > 0) {
				topCount++;
			}
		}

		if (topScore < MINIMUM_CANDIDATE_SCORE || topCount != 1) {
			return null;
		}
		return topId;
	}

	/**
	 * @creation date: 07/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Calcula el puntaje de matching entre un pago inbound y una cuota.
	 *               Acumula puntos por coincidencia exacta de secuencia (+6), fecha
	 *               exacta (+3), monto exacto (+2), fecha proxima hasta 7 dias (+1)
	 *               y monto proximo hasta 5% de diferencia relativa (+1).
	 * @param payment: Registro inbound con los campos fuente a comparar.
	 * @param inst: Cuota a evaluar.
	 * @return Puntaje total acumulado para esta cuota.
	 */
	private static Integer scoreInstallment(
		InboundInsurancePayment__c payment,
		PaymentPlanInstallment__c inst
	) {
		Integer score = 0;

		if (
			payment.sourceInstallmentNumber__c != null &&
			inst.sequenceNumber__c != null
		) {
			try {
				if (
					Decimal.valueOf(payment.sourceInstallmentNumber__c.trim()) ==
					inst.sequenceNumber__c
				) {
					score += SCORE_SEQUENCE_EXACT;
				}
			} catch (Exception e) {
			}
		}

		if (payment.sourceDueDate__c != null && inst.dueDate__c != null) {
			Integer daysDiff = Math.abs(
				payment.sourceDueDate__c.daysBetween(inst.dueDate__c)
			);
			if (daysDiff == 0) {
				score += SCORE_DATE_EXACT;
			} else if (daysDiff <= DATE_TOLERANCE_DAYS) {
				score += SCORE_DATE_CLOSE;
			}
		}

		if (
			payment.sourceAmount__c != null &&
			inst.expectedAmount__c != null &&
			inst.expectedAmount__c > 0
		) {
			Decimal delta = (payment.sourceAmount__c - inst.expectedAmount__c).abs();
			if (delta == 0) {
				score += SCORE_AMOUNT_EXACT;
			} else if (delta / inst.expectedAmount__c <= AMOUNT_TOLERANCE_PCT) {
				score += SCORE_AMOUNT_CLOSE;
			}
		}

		return score;
	}
}
