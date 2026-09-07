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

	// Un recibo sin fecha de pago es un COBRO PROGRAMADO: la aseguradora lo emitio y
	// todavia no lo cobro. Recorre la identificacion igual que un pago -para saber a que cuota
	// va y poder contrastar importe y fecha contra lo que emitio- pero se detiene aqui: no
	// avanza a las reglas, asi que no concilia ni genera cobro.
	private static final String STATUS_SCHEDULED = 'Pendiente de Pago';
	private static final Set<String> IDENTIFIABLE_STATUSES = new Set<String>{
		STATUS_NORMALIZED,
		STATUS_SCHEDULED
	};
	// El estado del plan deja de decidir si sus cuotas se miran. Un plan cancelado o
	// suspendido puede seguir recibiendo cobros, porque quien decide eso es la aseguradora.
	// El unico que se excluye es el reemplazado: sus cuotas se volvieron a crear en el plan
	// que lo sustituyo (cambio de frecuencia) y contarlas seria cobrar dos veces.
	private static final String PLAN_STATUS_REPLACED = 'Reemplazado';
	private static final Set<String> CONCILIABLE_INSTALLMENT_STATUSES = new Set<String>{
		'Pendiente',
		'Vencido'
	};

	// Una cuota cancelada puede volver a cobrarse, pero SOLO si la aseguradora da el
	// recibo por pagado: quien reabre la deuda es ella, no el motor. Se suma a las conciliables
	// unicamente en ese caso.
	private static final String INSTALLMENT_STATUS_CANCELLED = 'Cancelado';
	private static final String CARRIER_STATUS_PAID = 'Pagado';
	private static final Integer DATE_TOLERANCE_DAYS = 7;
	private static final Decimal AMOUNT_TOLERANCE_PCT = 0.05;
	private static final Integer SCORE_SEQUENCE_EXACT = 6;
	private static final Integer SCORE_DATE_EXACT = 3;
	private static final Integer SCORE_AMOUNT_EXACT = 2;
	private static final Integer SCORE_DATE_CLOSE = 1;
	private static final Integer SCORE_AMOUNT_CLOSE = 1;
	private static final Integer MINIMUM_CANDIDATE_SCORE = 3;

	private static final String REASON_SINGLE_WINNER = 'UNICO_GANADOR';
	private static final String REASON_LOW_SCORE = 'SCORE_BAJO';
	private static final String REASON_TIE = 'EMPATE';
	private static final String REASON_NO_INSTALLMENTS = 'SIN_CUOTAS';
	private static final String REASON_MULTIPLE_PLANS = 'PLANES_MULTIPLES';

	@TestVisible
	private static Boolean forceFailureForTest = false;

	private class InstallmentMatchException extends Exception {
	}

	private class InstallmentMatchResult {
		Id installmentId;
		String matchReason;

		InstallmentMatchResult(Id installmentId, String matchReason) {
			this.installmentId = installmentId;
			this.matchReason = matchReason;
		}
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
		AppLogger.setJobContext(context == null ? null : context.getJobId());
		System.attachFinalizer(
			CobranzaLog.finalizerFor(
				CobranzaLog.STAGE_CUOTA_CANDIDATA,
				inboundPaymentIds
			)
		);

		List<InboundInsurancePayment__c> payments = [
			SELECT
				Id,
				inboundStatus__c,
				carrierReceiptStatus__c,
				candidatePolicy__c,
				sourceInstallmentNumber__c,
				sourceDueDate__c,
				sourceAmount__c,
				sourceReceiptNumber__c
			FROM InboundInsurancePayment__c
			WHERE
				Id IN :inboundPaymentIds
				AND inboundStatus__c IN :IDENTIFIABLE_STATUSES
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
		// Las canceladas se cargan aparte: solo entran en juego para los pagos que la
		// aseguradora da por cobrados, asi que mezclarlas con las abiertas obligaria a
		// filtrarlas dentro del scoring, que corre una vez por cuota.
		Map<Id, List<PaymentPlanInstallment__c>> cancelledByPolicy = loadCancelledInstallmentsByPolicy(
			policyIds
		);

		List<InboundInsurancePayment__c> toUpdate = new List<InboundInsurancePayment__c>();

		for (InboundInsurancePayment__c p : payments) {
			InboundInsurancePayment__c rec = new InboundInsurancePayment__c(
				Id = p.Id
			);
			warnIfInstallmentNumberNotNumeric(p);
			try {
				if (forceFailureForTest) {
					throw new InstallmentMatchException('Forced failure for test');
				}
				InstallmentMatchResult result = bestInstallmentMatch(
					p,
					eligibleInstallmentsFor(p, installmentsByPolicy, cancelledByPolicy)
				);
				rec.candidateInstallment__c = result.installmentId;
				rec.installmentMatchReason__c = result.matchReason;
			} catch (Exception e) {
				rec.candidateInstallment__c = null;
				rec.installmentMatchReason__c = null;
				CobranzaLog.error(
						CobranzaLog.STAGE_CUOTA_CANDIDATA,
						CobranzaLog.EVENT_INSTALLMENT_CANDIDATE_FAILED,
						e
					)
					.onInbound(p.Id);
			}
			// La etapa del pipeline solo avanza para los pagos. Un cobro programado no esta
			// recorriendo el proceso sino aparcado a proposito, y sellarle una etapa lo haria
			// parecer en vuelo justo en el campo que sirve para encontrar pagos trabados.
			if (STATUS_NORMALIZED.equals(p.inboundStatus__c)) {
				rec.pipelineStage__c = CobranzaLog.STAGE_CUOTA_CANDIDATA;
			}
			toUpdate.add(rec);
		}

		update toUpdate;

		warnOnDuplicateScheduledCharges(payments, toUpdate);

		// Los cobros programados terminan su recorrido aqui: ya sabemos a que cuota apuntan,
		// que es todo lo que se puede afirmar mientras la aseguradora no los de por cobrados.
		// Avanzar a las reglas los conciliaria, que es justo lo que no debe pasar.
		Set<Id> allIds = new Set<Id>();
		for (InboundInsurancePayment__c p : payments) {
			if (STATUS_NORMALIZED.equals(p.inboundStatus__c)) {
				allIds.add(p.Id);
			}
		}
		if (allIds.isEmpty()) {
			AppLogger.flush();
			return;
		}
		try {
			System.enqueueJob(new InboundReconciliationRulesQueueable(allIds));
		} catch (System.AsyncException e) {
			CobranzaLog.chainBreak(
				CobranzaLog.STAGE_CUOTA_CANDIDATA,
				e,
				'InboundReconciliationRulesQueueable',
				allIds
			);
		}

		AppLogger.flush();
	}

	/**
	 * @creation date: 30/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Deja una advertencia cuando la aseguradora envio un numero de cuota que
	 *               no es numerico. No es un fallo del motor sino calidad de dato de origen,
	 *               pero importa: la secuencia exacta es la senal de mayor peso del scoring
	 *               (+6 puntos), asi que sin ella el pago tiene mucha mas chance de caer a
	 *               revision manual. Se evalua una vez por pago y no dentro del scoring,
	 *               que corre una vez por cada cuota candidata y generaria ruido.
	 * @param payment: Pago inbound a evaluar.
	 * @return
	 */
	/**
	 * @creation date: 01/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Avisa cuando dos cobros programados distintos apuntan a la misma cuota.
	 *               No es un fallo del motor y no bloquea nada: la cuota sigue libre
	 *               y cualquiera de los dos puede terminar cobrandose. Es una señal sobre los
	 *               datos -normalmente que la aseguradora emitio dos recibos para la misma
	 *               obligacion, o que nuestro plan tiene una cuota de menos- y sin registrarla
	 *               nadie se enteraria hasta el dia del cobro.
	 * @param payments: Pagos evaluados en este lote.
	 * @param updates: Registros ya actualizados con su cuota candidata.
	 * @return
	 */
	private static void warnOnDuplicateScheduledCharges(
		List<InboundInsurancePayment__c> payments,
		List<InboundInsurancePayment__c> updates
	) {
		Map<Id, String> statusById = new Map<Id, String>();
		for (InboundInsurancePayment__c p : payments) {
			statusById.put(p.Id, p.inboundStatus__c);
		}

		Set<Id> installmentIds = new Set<Id>();
		for (InboundInsurancePayment__c rec : updates) {
			if (
				rec.candidateInstallment__c != null &&
				STATUS_SCHEDULED.equals(statusById.get(rec.Id))
			) {
				installmentIds.add(rec.candidateInstallment__c);
			}
		}
		if (installmentIds.isEmpty()) {
			return;
		}

		Map<Id, List<Id>> scheduledByInstallment = new Map<Id, List<Id>>();
		for (InboundInsurancePayment__c other : [
			SELECT Id, candidateInstallment__c
			FROM InboundInsurancePayment__c
			WHERE
				candidateInstallment__c IN :installmentIds
				AND inboundStatus__c = :STATUS_SCHEDULED
		]) {
			if (!scheduledByInstallment.containsKey(other.candidateInstallment__c)) {
				scheduledByInstallment.put(
					other.candidateInstallment__c,
					new List<Id>()
				);
			}
			scheduledByInstallment.get(other.candidateInstallment__c).add(other.Id);
		}

		for (InboundInsurancePayment__c rec : updates) {
			if (
				rec.candidateInstallment__c == null ||
				!STATUS_SCHEDULED.equals(statusById.get(rec.Id))
			) {
				continue;
			}
			List<Id> competing = scheduledByInstallment.get(
				rec.candidateInstallment__c
			);
			if (competing == null || competing.size() < 2) {
				continue;
			}
			CobranzaLog.warn(
					CobranzaLog.STAGE_CUOTA_CANDIDATA,
					CobranzaLog.EVENT_DUPLICATE_SCHEDULED_CHARGE,
					'La aseguradora tiene ' +
						competing.size() +
						' recibos emitidos apuntando a la misma cuota. No bloquea nada, pero ' +
						'suele significar que emitio dos recibos para la misma obligacion o ' +
						'que a nuestro plan le falta una cuota.'
				)
				.onInbound(rec.Id);
		}
	}

	private static void warnIfInstallmentNumberNotNumeric(
		InboundInsurancePayment__c payment
	) {
		if (String.isBlank(payment.sourceInstallmentNumber__c)) {
			return;
		}
		try {
			Decimal.valueOf(payment.sourceInstallmentNumber__c.trim());
		} catch (Exception e) {
			CobranzaLog.warn(
					CobranzaLog.STAGE_CUOTA_CANDIDATA,
					CobranzaLog.EVENT_INSTALLMENT_NUMBER_NOT_NUMERIC,
					'El número de cuota recibido no es numérico ("' +
						payment.sourceInstallmentNumber__c +
						'"): el matching pierde la señal de secuencia exacta.'
				)
				.onInbound(payment.Id);
		}
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
	/**
	 * @creation date: 01/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Cuotas que este pago concreto puede tomar. A las abiertas se suman
	 *               las CANCELADAS, pero solo si la aseguradora da el recibo por cobrado: quien
	 *               decide reabrir una deuda cancelada es ella, no el motor.
	 * @param payment: Pago evaluado, con el estatus que reporta la aseguradora.
	 * @param openByPolicy: Cuotas abiertas por poliza.
	 * @param cancelledByPolicy: Cuotas canceladas reabribles por poliza.
	 * @return Lista de cuotas candidatas para este pago.
	 */
	private static List<PaymentPlanInstallment__c> eligibleInstallmentsFor(
		InboundInsurancePayment__c payment,
		Map<Id, List<PaymentPlanInstallment__c>> openByPolicy,
		Map<Id, List<PaymentPlanInstallment__c>> cancelledByPolicy
	) {
		List<PaymentPlanInstallment__c> eligible = new List<PaymentPlanInstallment__c>();
		List<PaymentPlanInstallment__c> open = openByPolicy.get(
			payment.candidatePolicy__c
		);
		if (open != null) {
			eligible.addAll(open);
		}
		if (!CARRIER_STATUS_PAID.equals(payment.carrierReceiptStatus__c)) {
			return eligible;
		}
		List<PaymentPlanInstallment__c> cancelled = cancelledByPolicy.get(
			payment.candidatePolicy__c
		);
		if (cancelled != null) {
			eligible.addAll(cancelled);
		}
		return eligible;
	}

	/**
	 * @creation date: 01/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Carga las cuotas CANCELADAS que podrian volver a cobrarse.
	 *               Excluye dos cosas a proposito:
	 *               - Las de planes REEMPLAZADOS. Una cuota queda cancelada por dos motivos muy
	 *                 distintos: porque la aseguradora la cancelo, o porque el cliente cambio la
	 *                 frecuencia de pago y su plan fue sustituido. En el segundo caso la deuda no
	 *                 desaparecio: se volvio a crear en el plan nuevo, asi que cobrarla aqui seria
	 *                 cobrarla dos veces. Ese filtro ya existe aguas arriba, pero la regla se
	 *                 repite aqui porque si alguien lo relaja, el doble cobro aparece sin aviso.
	 *               - Las CONDONADAS. Perdonar una deuda es una decision nuestra, y ningun mensaje
	 *                 de la aseguradora la revierte.
	 * @param policyIds: Polizas candidatas resueltas.
	 * @return Mapa de poliza a sus cuotas canceladas reabribles.
	 */
	private static Map<Id, List<PaymentPlanInstallment__c>> loadCancelledInstallmentsByPolicy(
		Set<Id> policyIds
	) {
		Map<Id, List<PaymentPlanInstallment__c>> result = new Map<Id, List<PaymentPlanInstallment__c>>();
		if (policyIds.isEmpty()) {
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
				paymentPlan__c,
				paymentPlan__r.insurancePolicy__c
			FROM PaymentPlanInstallment__c
			WHERE
				paymentPlan__r.insurancePolicy__c IN :policyIds
				AND installmentStatus__c = :INSTALLMENT_STATUS_CANCELLED
				AND paymentPlan__r.planStatus__c != :PLAN_STATUS_REPLACED
		]) {
			Id policyId = inst.paymentPlan__r.insurancePolicy__c;
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
				AND planStatus__c != :PLAN_STATUS_REPLACED
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
	private static InstallmentMatchResult bestInstallmentMatch(
		InboundInsurancePayment__c payment,
		List<PaymentPlanInstallment__c> installments
	) {
		if (payment.candidatePolicy__c == null) {
			return new InstallmentMatchResult(null, null);
		}
		if (installments == null || installments.isEmpty()) {
			return new InstallmentMatchResult(null, REASON_NO_INSTALLMENTS);
		}

		// Al dejar de exigir plan Activo, una poliza puede presentar cuotas abiertas de mas de
		// un plan a la vez. Puntuarlas juntas mezclaria dos calendarios distintos y podria
		// aplicar el cobro al plan equivocado, asi que no se elige: lo resuelve una persona.
		Set<Id> openPlans = new Set<Id>();
		for (PaymentPlanInstallment__c inst : installments) {
			if (inst.paymentPlan__c != null) {
				openPlans.add(inst.paymentPlan__c);
			}
		}
		if (openPlans.size() > 1) {
			CobranzaLog.warn(
					CobranzaLog.STAGE_CUOTA_CANDIDATA,
					CobranzaLog.EVENT_MULTIPLE_OPEN_PLANS,
					'La poliza tiene ' +
						openPlans.size() +
						' planes de pago con cuotas abiertas. No se elige cuota: aplicar el ' +
						'cobro al plan equivocado es peor que dejarlo para revision manual.'
				)
				.onInbound(payment.Id);
			return new InstallmentMatchResult(null, REASON_MULTIPLE_PLANS);
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

		if (topScore < MINIMUM_CANDIDATE_SCORE) {
			return new InstallmentMatchResult(null, REASON_LOW_SCORE);
		}
		if (topCount != 1) {
			return new InstallmentMatchResult(null, REASON_TIE);
		}
		return new InstallmentMatchResult(topId, REASON_SINGLE_WINNER);
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
				// Numero de cuota no numerico: condicion de dato esperada, no un fallo. Se
				// omiten los puntos de secuencia. La traza se emite una unica vez por pago
				// en warnIfInstallmentNumberNotNumeric; registrarla aca la repetiria por
				// cada cuota candidata evaluada.
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
