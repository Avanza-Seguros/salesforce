/**
 *   @name: InboundRefundService
 *   @version: 1.0
 *   @creation date: 15/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Trata los importes negativos de la aseguradora: devoluciones de dinero y
 *                 anulaciones contables. El signo manda: un negativo nunca es un cobro, aunque
 *                 la aseguradora lo reporte como pagado; su estatus solo dice si el movimiento
 *                 ya se aplico.
 *                 Un negativo nunca trae el folio del recibo que devuelve, asi que se relaciona
 *                 por poliza, vencimiento e importe, y SOLO se aplica solo lo que coincide
 *                 exactamente. Todo lo demas -casi coincidencias, ambiguedades, cobros
 *                 duplicados, polizas en estados dudosos- lo decide el analista: clasificar mal
 *                 una devolucion cambia lo que el sistema da por cobrado sin que nadie se entere.
 *                 La aplicacion reutiliza la reversa del recibo (motivo Devolucion), de modo que
 *                 una devolucion resuelta a mano y una resuelta sola dejan el sistema igual.
 */
public with sharing class InboundRefundService {
	private static final String STATUS_REFUND = 'Devolucion';
	private static final String STATUS_MANUAL_REVIEW = 'Revision Manual';

	private static final String CARRIER_PAID = 'Pagado';
	private static final String CARRIER_PENDING = 'Pendiente';
	private static final String CARRIER_OVERDUE = 'Vencido';
	private static final String CARRIER_CANCELLED = 'Cancelado';
	// Estatus con los que un negativo que nombra recibos de cuotas se decide por esos recibos.
	// Uno pagado es dinero que vuelve y sigue las reglas de siempre.
	private static final Set<String> RECEIPT_NAMING_STATUSES = new Set<String>{
		CARRIER_PENDING,
		CARRIER_OVERDUE,
		CARRIER_CANCELLED
	};

	public static final String OUTCOME_PENDING = 'Pendiente de aplicar';
	public static final String OUTCOME_NO_EFFECT = 'Sin efecto';
	public static final String OUTCOME_CANCELLATION = 'Anulacion contable';
	public static final String OUTCOME_INSTALLMENT = 'Devolucion de cuota';
	public static final String OUTCOME_WITHOUT_INSTALLMENT = 'Devolucion sin cuota';
	public static final String OUTCOME_REVIEW = 'Requiere revision';

	// Resultados que ya tuvieron efecto sobre cuotas o recibos. Una devolucion con uno de
	// estos resultados no se vuelve a aplicar nunca.
	public static final Set<String> APPLIED_OUTCOMES = new Set<String>{
		OUTCOME_CANCELLATION,
		OUTCOME_INSTALLMENT,
		OUTCOME_WITHOUT_INSTALLMENT
	};

	// Los que movieron dinero y por eso cuentan en el total devuelto de la poliza. La
	// anulacion contable no: esos recibos nunca se pagaron.
	private static final Set<String> MONEY_OUTCOMES = new Set<String>{
		OUTCOME_INSTALLMENT,
		OUTCOME_WITHOUT_INSTALLMENT
	};

	public static final String RESOLUTION_INSTALLMENT = 'CUOTA';
	public static final String RESOLUTION_WITHOUT_INSTALLMENT = 'SIN_CUOTA';
	public static final String RESOLUTION_NO_EFFECT = 'SIN_EFECTO';

	// Por ahora, viva es Vigente o Inicial. Cancelado deja la cuota cancelada. Cualquier otro
	// estado (Vencido, Suspendido...) no permite decidir si la cuota se vuelve a deber.
	private static final Set<String> LIVE_POLICY_STATUSES = new Set<String>{
		'Vigente',
		'Inicial'
	};
	private static final String POLICY_CANCELLED = 'Cancelado';

	private static final String INSTALLMENT_RECONCILED = 'Conciliado';
	private static final String INSTALLMENT_CANCELLED = 'Cancelado';
	private static final Set<String> OPEN_INSTALLMENT_STATUSES = new Set<String>{
		'Pendiente',
		'Vencido'
	};
	private static final String PLAN_REPLACED = 'Reemplazado';
	private static final String RECEIPT_RECOGNIZED = 'Reconocido';
	private static final String RECEIPT_REVERSED = 'Reversado';
	private static final String REVERSAL_REASON_REFUND = 'Devolucion';
	private static final String STATUS_REJECTED = 'Rechazado';
	private static final String REASON_AMBIGUOUS_TERM = 'VIGENCIA_AMBIGUA';

	@TestVisible
	private static Boolean forceFailureForTest = false;

	public class RefundValidationException extends Exception {
	}

	private class RefundException extends Exception {
	}

	private class Decision {
		InboundInsurancePayment__c refund;
		String outcome;
		String reviewReason;
		Id policyId;
		List<PaymentPlanInstallment__c> toCancel = new List<PaymentPlanInstallment__c>();
		PaymentPlanInstallment__c installment;
		Boolean policyCancelled = false;

		Decision(InboundInsurancePayment__c refund) {
			this.refund = refund;
		}

		Decision review(String reason) {
			this.outcome = OUTCOME_REVIEW;
			this.reviewReason = reason;
			return this;
		}
	}

	public class InstallmentOption {
		@AuraEnabled
		public String value;
		@AuraEnabled
		public String label;

		InstallmentOption(String value, String label) {
			this.value = value;
			this.label = label;
		}
	}

	/**
	 * @creation date: 15/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Clasifica y aplica las devoluciones indicadas. Solo toma las que estan en
	 *               estado Devolucion y todavia no tienen resultado: eso es lo que garantiza que
	 *               una devolucion repetida no se aplique dos veces.
	 *               Cada devolucion se aplica por separado y con punto de restauracion: si algo
	 *               falla a mitad, se deshace lo que hizo esa devolucion y queda para el analista,
	 *               sin afectar a las demas.
	 * @param refundIds: Pagos inbound con importe negativo.
	 * @return
	 */
	public static void process(Set<Id> refundIds) {
		if (refundIds == null || refundIds.isEmpty()) {
			return;
		}
		List<InboundInsurancePayment__c> refunds = [
			SELECT
				Id,
				externalPaymentId__c,
				sourceReceiptNumber__c,
				sourcePolicyNumber__c,
				sourceAmount__c,
				sourceDueDate__c,
				sourcePaymentDate__c,
				carrierReceiptStatus__c
			FROM InboundInsurancePayment__c
			WHERE
				Id IN :refundIds
				AND inboundStatus__c = :STATUS_REFUND
				AND refundOutcome__c = NULL
				AND sourceAmount__c < 0
		];
		if (refunds.isEmpty()) {
			return;
		}

		Map<Id, InboundPolicyCandidateQueueable.PolicyMatchResult> matchByRefund = InboundPolicyCandidateQueueable.resolveAll(
			refunds
		);
		Set<Id> policyIds = new Set<Id>();
		for (
			InboundPolicyCandidateQueueable.PolicyMatchResult match : matchByRefund.values()
		) {
			if (match != null && match.policyId != null) {
				policyIds.add(match.policyId);
			}
		}
		Map<Id, InsurancePolicy> policies = new Map<Id, InsurancePolicy>(
			[SELECT Id, Status FROM InsurancePolicy WHERE Id IN :policyIds]
		);
		Map<Id, List<PaymentPlanInstallment__c>> installmentsByPolicy = loadInstallments(
			policyIds
		);
		Map<String, List<InboundInsurancePayment__c>> chargesByPolicyNumber = loadPaidCharges(
			refunds
		);

		// Una cuota solo puede tomarla una devolucion por envio: si dos devoluciones del mismo
		// lote apuntan a la misma, la segunda la decide el analista.
		Set<Id> claimedInstallments = new Set<Id>();
		Set<Id> policiesWithMoney = new Set<Id>();
		for (InboundInsurancePayment__c refund : refunds) {
			Decision decision = decide(
				refund,
				matchByRefund.get(refund.Id),
				policies,
				installmentsByPolicy,
				chargesByPolicyNumber,
				claimedInstallments
			);
			applyDecision(decision);
			if (
				decision.policyId != null && MONEY_OUTCOMES.contains(decision.outcome)
			) {
				policiesWithMoney.add(decision.policyId);
			}
		}
		recalculateTotals(policiesWithMoney);
		// Se guarda aqui y no solo en el proceso asincrono: quien llame al servicio por otra via
		// perderia el registro de lo que se decidio.
		AppLogger.flush();
	}

	/**
	 * @creation date: 15/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Decide que es la devolucion sin tocar nada todavia. El orden importa: primero
	 *               el estatus (si la aseguradora aun no la aplico, no hay nada que hacer), luego
	 *               la poliza, y solo entonces las coincidencias exactas. Cualquier duda termina
	 *               en revision manual con el motivo, nunca en una eleccion por descarte.
	 * @return La decision tomada.
	 */
	private static Decision decide(
		InboundInsurancePayment__c refund,
		InboundPolicyCandidateQueueable.PolicyMatchResult match,
		Map<Id, InsurancePolicy> policies,
		Map<Id, List<PaymentPlanInstallment__c>> installmentsByPolicy,
		Map<String, List<InboundInsurancePayment__c>> chargesByPolicyNumber,
		Set<Id> claimedInstallments
	) {
		Decision d = new Decision(refund);
		String carrierStatus = refund.carrierReceiptStatus__c;

		// Un negativo sin cobrar que nombra el recibo de una cuota de la poliza se decide por sus
		// recibos, no por importe: no hay dinero que devolver de recibos que nunca se cobraron,
		// asi que solo puede dejarlos de exigir, aunque la aseguradora aun no lo haya asentado.
		if (
			RECEIPT_NAMING_STATUSES.contains(carrierStatus) &&
			match != null &&
			match.policyId != null
		) {
			List<PaymentPlanInstallment__c> named = installmentsNamedBy(
				refund,
				installmentsByPolicy.get(match.policyId),
				claimedInstallments
			);
			if (named != null) {
				d.policyId = match.policyId;
				if (!named.isEmpty()) {
					d.outcome = OUTCOME_CANCELLATION;
					d.toCancel = named;
					claim(named, claimedInstallments);
					return d;
				}
				if (CARRIER_CANCELLED.equals(carrierStatus)) {
					d.outcome = OUTCOME_NO_EFFECT;
					return d;
				}
			}
		}

		if (
			CARRIER_PENDING.equals(carrierStatus) ||
			CARRIER_OVERDUE.equals(carrierStatus)
		) {
			// La aseguradora todavia no la aplico. Se aplicara cuando llegue como pagada.
			d.outcome = OUTCOME_PENDING;
			d.policyId = match == null ? null : match.policyId;
			return d;
		}
		if (
			!CARRIER_PAID.equals(carrierStatus) &&
			!CARRIER_CANCELLED.equals(carrierStatus)
		) {
			return d.review(
				'La aseguradora informó un estatus que no corresponde a ninguno de los acordados.'
			);
		}
		if (match == null || match.policyId == null) {
			return d.review(
				match != null && REASON_AMBIGUOUS_TERM.equals(match.reason)
					? 'El número de póliza corresponde a varias vigencias y la fecha de la devolución no permite elegir una.'
					: 'No se encontró la póliza de la devolución.'
			);
		}
		d.policyId = match.policyId;

		Decimal amount = refund.sourceAmount__c.abs();
		List<PaymentPlanInstallment__c> installments = installmentsByPolicy.containsKey(
				d.policyId
			)
			? installmentsByPolicy.get(d.policyId)
			: new List<PaymentPlanInstallment__c>();
		List<PaymentPlanInstallment__c> cancellation = findCancellation(
			installments,
			amount,
			refund.sourceDueDate__c,
			claimedInstallments
		);

		if (CARRIER_CANCELLED.equals(carrierStatus)) {
			// Un negativo cancelado solo puede ser una anulacion contable: tratarlo como
			// devolucion anularia cobros que el cliente si pago.
			if (cancellation == null) {
				d.outcome = OUTCOME_NO_EFFECT;
				return d;
			}
			d.outcome = OUTCOME_CANCELLATION;
			d.toCancel = cancellation;
			claim(cancellation, claimedInstallments);
			return d;
		}

		List<PaymentPlanInstallment__c> paidMatches = findPaidInstallments(
			installments,
			amount,
			refund.sourceDueDate__c
		);
		Integer interpretations =
			paidMatches.size() + (cancellation == null ? 0 : 1);

		if (interpretations == 0) {
			return d.review(
				'No coincide exactamente con ninguna cuota pagada ni con la suma de las cuotas no pagadas de la póliza.'
			);
		}
		if (interpretations > 1) {
			return d.review(
				'Coincide con más de una opción (' +
					paidMatches.size() +
					' cuota(s) pagada(s)' +
					(cancellation == null ? '' : ' y la suma de las cuotas no pagadas') +
					'): no se elige por descarte.'
			);
		}
		if (cancellation != null) {
			d.outcome = OUTCOME_CANCELLATION;
			d.toCancel = cancellation;
			claim(cancellation, claimedInstallments);
			return d;
		}

		PaymentPlanInstallment__c installment = paidMatches[0];
		if (claimedInstallments.contains(installment.Id)) {
			return d.review(
				'Otra devolución del mismo envío ya tomó la cuota que coincide.'
			);
		}
		if (
			installment.matchedReceipt__c == null ||
			!RECEIPT_RECOGNIZED.equals(installment.matchedReceipt__r.receiptStatus__c)
		) {
			return d.review(
				'La cuota que coincide está conciliada pero no tiene un recibo reconocido que anular.'
			);
		}
		if (
			hasDuplicateCharge(installment, refund, amount, chargesByPolicyNumber)
		) {
			return d.review(
				'La cuota que coincide se cobró dos veces: la devolución corresponde al cobro de más y la cuota sigue pagada.'
			);
		}
		String policyStatus = policies.get(d.policyId).Status;
		Boolean cancelled = POLICY_CANCELLED.equals(policyStatus);
		if (!cancelled && !LIVE_POLICY_STATUSES.contains(policyStatus)) {
			return d.review(
				'La póliza está en estado ' +
					policyStatus +
					': no está claro si la cuota se vuelve a deber.'
			);
		}
		d.outcome = OUTCOME_INSTALLMENT;
		d.installment = installment;
		d.policyCancelled = cancelled;
		claimedInstallments.add(installment.Id);
		return d;
	}

	/**
	 * @creation date: 15/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Aplica la decision y deja el pago con su resultado. Todo lo de una misma
	 *               devolucion va junto: si algo falla, se deshace y la devolucion queda para el
	 *               analista con el motivo del fallo.
	 * @param d: Decision tomada para la devolucion.
	 * @return
	 */
	private static void applyDecision(Decision d) {
		Savepoint sp = Database.setSavepoint();
		try {
			if (forceFailureForTest && APPLIED_OUTCOMES.contains(d.outcome)) {
				throw new RefundException('Forced failure for test');
			}
			if (OUTCOME_CANCELLATION.equals(d.outcome)) {
				cancelInstallments(d.toCancel, d.refund.Id);
			} else if (OUTCOME_INSTALLMENT.equals(d.outcome)) {
				refundInstallment(d.refund, d.installment, d.policyCancelled);
			}
			update resultRecord(d);
			logDecision(d);
		} catch (Exception e) {
			Database.rollback(sp);
			CobranzaLog.error(
					CobranzaLog.STAGE_DEVOLUCION,
					CobranzaLog.EVENT_REFUND_FAILED,
					'No se pudo aplicar la devolución (' +
						d.outcome +
						'). No se cambió nada y queda para el analista. Motivo: ' +
						e.getMessage()
				)
				.onInbound(d.refund.Id);
			d.review('No se pudo aplicar: ' + e.getMessage().left(200));
			update resultRecord(d);
		}
	}

	/**
	 * @creation date: 15/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Anula el recibo de la cuota devuelta y deja la cuota segun la poliza. La
	 *               reversa (motivo Devolucion) reabre la cuota como Pendiente y NO devuelve a
	 *               revision el pago que la concilio. Si la poliza esta cancelada, la cuota queda
	 *               ademas en Cancelado: ya no se debe.
	 *               Comprueba despues que la cuota quedo libre: la cascada de la reversa tolera
	 *               fallos parciales, y una cuota Conciliado con su recibo anulado seria justo el
	 *               "verde falso" que esta historia existe para evitar.
	 * @param refund: Devolucion que se aplica.
	 * @param installment: Cuota devuelta, con su recibo.
	 * @param policyCancelled: Si la poliza esta cancelada.
	 * @return
	 */
	private static void refundInstallment(
		InboundInsurancePayment__c refund,
		PaymentPlanInstallment__c installment,
		Boolean policyCancelled
	) {
		update new PolicyPaymentReceipt__c(
			Id = installment.matchedReceipt__c,
			receiptStatus__c = RECEIPT_REVERSED,
			reversalReason__c = REVERSAL_REASON_REFUND,
			reversalNotes__c = 'Devolución de la aseguradora, folio ' +
				(String.isBlank(refund.sourceReceiptNumber__c)
					? refund.externalPaymentId__c
					: refund.sourceReceiptNumber__c) +
				', por ' +
				refund.sourceAmount__c.abs().setScale(2).format() +
				'.',
			refundInboundPayment__c = refund.Id
		);

		PaymentPlanInstallment__c after = [
			SELECT matchedReceipt__c
			FROM PaymentPlanInstallment__c
			WHERE Id = :installment.Id
		];
		if (after.matchedReceipt__c != null) {
			throw new RefundException(
				'La cuota no se pudo reabrir tras anular su recibo.'
			);
		}
		if (policyCancelled) {
			update new PaymentPlanInstallment__c(
				Id = installment.Id,
				installmentStatus__c = INSTALLMENT_CANCELLED,
				cancelledByRefund__c = refund.Id
			);
		}
	}

	/**
	 * @creation date: 15/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Deja en Cancelado las cuotas que la anulacion contable da de baja, con
	 *               constancia de que anulacion lo hizo. No toca ningun recibo: esas cuotas nunca
	 *               se pagaron.
	 * @param installments: Cuotas a cancelar.
	 * @param refundId: Anulacion que las cancela.
	 * @return
	 */
	private static void cancelInstallments(
		List<PaymentPlanInstallment__c> installments,
		Id refundId
	) {
		List<PaymentPlanInstallment__c> toUpdate = new List<PaymentPlanInstallment__c>();
		for (PaymentPlanInstallment__c inst : installments) {
			toUpdate.add(
				new PaymentPlanInstallment__c(
					Id = inst.Id,
					installmentStatus__c = INSTALLMENT_CANCELLED,
					cancelledByRefund__c = refundId
				)
			);
		}
		update toUpdate;
	}

	/**
	 * @creation date: 15/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Registro del pago con el resultado de la decision. Lo que va a revision
	 *               queda visible en la bandeja del analista (la marca manualReviewRequired__c),
	 *               con el motivo.
	 * @param d: Decision tomada.
	 * @return Registro listo para actualizar.
	 */
	private static InboundInsurancePayment__c resultRecord(Decision d) {
		Boolean review = OUTCOME_REVIEW.equals(d.outcome);
		InboundInsurancePayment__c rec = new InboundInsurancePayment__c(
			Id = d.refund.Id,
			refundOutcome__c = d.outcome,
			refundReviewReason__c = review ? d.reviewReason : null,
			inboundStatus__c = review ? STATUS_MANUAL_REVIEW : STATUS_REFUND,
			manualReviewRequired__c = review
		);
		if (d.policyId != null) {
			rec.candidatePolicy__c = d.policyId;
		}
		return rec;
	}

	private static void logDecision(Decision d) {
		if (OUTCOME_REVIEW.equals(d.outcome)) {
			CobranzaLog.warn(
					CobranzaLog.STAGE_DEVOLUCION,
					CobranzaLog.EVENT_REFUND_TO_REVIEW,
					'La devolución queda para el analista: ' + d.reviewReason
				)
				.onInbound(d.refund.Id);
			return;
		}
		if (OUTCOME_CANCELLATION.equals(d.outcome)) {
			CobranzaLog.info(
					CobranzaLog.STAGE_DEVOLUCION,
					CobranzaLog.EVENT_REFUND_APPLIED,
					'Anulación contable: ' +
						d.toCancel.size() +
						' cuota(s) no pagada(s) pasaron a Cancelado.'
				)
				.onInbound(d.refund.Id);
			return;
		}
		if (OUTCOME_INSTALLMENT.equals(d.outcome)) {
			CobranzaLog.info(
					CobranzaLog.STAGE_DEVOLUCION,
					CobranzaLog.EVENT_REFUND_APPLIED,
					'Devolución de una cuota pagada: se anuló su recibo y la cuota quedó ' +
						(d.policyCancelled ? 'Cancelado' : 'Pendiente') +
						'.'
				)
				.onInbound(d.refund.Id);
		}
	}

	/**
	 * @creation date: 15/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Cuotas no pagadas cuya suma es exactamente el importe de la anulacion. Se
	 *               prueba primero con las que vencen desde la fecha de la anulacion (es lo que
	 *               suele cancelar la aseguradora) y despues con todas. Sin coincidencia exacta
	 *               no hay anulacion.
	 * @return Cuotas a cancelar, o null si no hay coincidencia exacta.
	 */
	private static List<PaymentPlanInstallment__c> findCancellation(
		List<PaymentPlanInstallment__c> installments,
		Decimal amount,
		Date dueDate,
		Set<Id> claimedInstallments
	) {
		List<PaymentPlanInstallment__c> open = new List<PaymentPlanInstallment__c>();
		List<PaymentPlanInstallment__c> fromDueDate = new List<PaymentPlanInstallment__c>();
		for (PaymentPlanInstallment__c inst : installments) {
			if (
				!OPEN_INSTALLMENT_STATUSES.contains(inst.installmentStatus__c) ||
				claimedInstallments.contains(inst.Id)
			) {
				continue;
			}
			open.add(inst);
			if (
				dueDate != null &&
				inst.dueDate__c != null &&
				inst.dueDate__c >= dueDate
			) {
				fromDueDate.add(inst);
			}
		}
		if (
			!fromDueDate.isEmpty() && sameAmount(sumExpected(fromDueDate), amount)
		) {
			return fromDueDate;
		}
		if (!open.isEmpty() && sameAmount(sumExpected(open), amount)) {
			return open;
		}
		return null;
	}

	/**
	 * @creation date: 15/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Cuotas pagadas que coinciden exactamente con la devolucion: mismo
	 *               vencimiento y mismo importe, sea el esperado de la cuota o el de su recibo.
	 *               Sin vencimiento en la devolucion no hay coincidencia posible.
	 * @return Cuotas que coinciden.
	 */
	private static List<PaymentPlanInstallment__c> findPaidInstallments(
		List<PaymentPlanInstallment__c> installments,
		Decimal amount,
		Date dueDate
	) {
		List<PaymentPlanInstallment__c> result = new List<PaymentPlanInstallment__c>();
		if (dueDate == null) {
			return result;
		}
		for (PaymentPlanInstallment__c inst : installments) {
			if (
				!INSTALLMENT_RECONCILED.equals(inst.installmentStatus__c) ||
				inst.dueDate__c != dueDate
			) {
				continue;
			}
			Boolean receiptMatches =
				inst.matchedReceipt__c != null &&
				sameAmount(inst.matchedReceipt__r.receiptAmount__c, amount);
			if (sameAmount(inst.expectedAmount__c, amount) || receiptMatches) {
				result.add(inst);
			}
		}
		return result;
	}

	/**
	 * @creation date: 15/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Indica si la cuota se cobro dos veces: existe otro pago de la aseguradora,
	 *               ademas del que la concilio, por el mismo importe y con el mismo vencimiento.
	 *               En ese caso lo devuelto es el cobro de mas y la cuota sigue pagada.
	 * @return true si hay un cobro duplicado.
	 */
	private static Boolean hasDuplicateCharge(
		PaymentPlanInstallment__c installment,
		InboundInsurancePayment__c refund,
		Decimal amount,
		Map<String, List<InboundInsurancePayment__c>> chargesByPolicyNumber
	) {
		String key = refund.sourcePolicyNumber__c == null
			? null
			: refund.sourcePolicyNumber__c.trim().toUpperCase();
		if (key == null || !chargesByPolicyNumber.containsKey(key)) {
			return false;
		}
		Id reconciledCharge = installment.matchedReceipt__r.sourceInboundPayment__c;
		for (InboundInsurancePayment__c charge : chargesByPolicyNumber.get(key)) {
			if (
				charge.Id != reconciledCharge &&
				charge.sourceDueDate__c == installment.dueDate__c &&
				sameAmount(charge.sourceAmount__c, amount)
			) {
				return true;
			}
		}
		return false;
	}

	private static Map<Id, List<PaymentPlanInstallment__c>> loadInstallments(
		Set<Id> policyIds
	) {
		Map<Id, List<PaymentPlanInstallment__c>> result = new Map<Id, List<PaymentPlanInstallment__c>>();
		if (policyIds.isEmpty()) {
			return result;
		}
		for (PaymentPlanInstallment__c inst : [
			SELECT
				Id,
				paymentPlan__r.insurancePolicy__c,
				installmentStatus__c,
				dueDate__c,
				expectedAmount__c,
				sequenceNumber__c,
				carrierReceiptNumber__c,
				matchedReceipt__c,
				matchedReceipt__r.receiptAmount__c,
				matchedReceipt__r.receiptStatus__c,
				matchedReceipt__r.sourceInboundPayment__c
			FROM PaymentPlanInstallment__c
			WHERE
				paymentPlan__r.insurancePolicy__c IN :policyIds
				AND paymentPlan__r.planStatus__c != :PLAN_REPLACED
			ORDER BY dueDate__c
		]) {
			Id policyId = inst.paymentPlan__r.insurancePolicy__c;
			if (!result.containsKey(policyId)) {
				result.put(policyId, new List<PaymentPlanInstallment__c>());
			}
			result.get(policyId).add(inst);
		}
		return result;
	}

	/**
	 * @creation date: 15/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Cobros de la aseguradora (importes positivos pagados) de las mismas polizas
	 *               y vencimientos que las devoluciones, para detectar cobros duplicados. Un pago
	 *               migrado sin estatus pero con fecha de pago cuenta como pagado, igual que en la
	 *               recepcion.
	 * @param refunds: Devoluciones a evaluar.
	 * @return Cobros por numero de poliza normalizado.
	 */
	private static Map<String, List<InboundInsurancePayment__c>> loadPaidCharges(
		List<InboundInsurancePayment__c> refunds
	) {
		Map<String, List<InboundInsurancePayment__c>> result = new Map<String, List<InboundInsurancePayment__c>>();
		Set<String> policyNumbers = new Set<String>();
		Set<Date> dueDates = new Set<Date>();
		for (InboundInsurancePayment__c refund : refunds) {
			if (
				String.isNotBlank(refund.sourcePolicyNumber__c) &&
				refund.sourceDueDate__c != null
			) {
				policyNumbers.add(refund.sourcePolicyNumber__c.trim());
				dueDates.add(refund.sourceDueDate__c);
			}
		}
		if (policyNumbers.isEmpty()) {
			return result;
		}
		for (InboundInsurancePayment__c charge : [
			SELECT Id, sourcePolicyNumber__c, sourceDueDate__c, sourceAmount__c
			FROM InboundInsurancePayment__c
			WHERE
				sourcePolicyNumber__c IN :policyNumbers
				AND sourceDueDate__c IN :dueDates
				AND sourceAmount__c > 0
				AND inboundStatus__c != :STATUS_REJECTED
				AND (carrierReceiptStatus__c = :CARRIER_PAID
				OR (carrierReceiptStatus__c = NULL
				AND sourcePaymentDate__c != NULL))
		]) {
			String key = charge.sourcePolicyNumber__c.trim().toUpperCase();
			if (!result.containsKey(key)) {
				result.put(key, new List<InboundInsurancePayment__c>());
			}
			result.get(key).add(charge);
		}
		return result;
	}

	/**
	 * @creation date: 15/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Recalcula el total devuelto de las polizas a partir de sus devoluciones con
	 *               dinero, en vez de sumar a ciegas: asi el total siempre se puede explicar con
	 *               la lista de devoluciones de la poliza, y una devolucion que se procesa dos
	 *               veces no lo altera.
	 * @param policyIds: Polizas a recalcular.
	 * @return
	 */
	public static void recalculateTotals(Set<Id> policyIds) {
		if (policyIds == null || policyIds.isEmpty()) {
			return;
		}
		Map<Id, Decimal> totals = new Map<Id, Decimal>();
		for (Id policyId : policyIds) {
			totals.put(policyId, 0);
		}
		for (AggregateResult ar : [
			SELECT candidatePolicy__c policyId, SUM(sourceAmount__c) total
			FROM InboundInsurancePayment__c
			WHERE
				candidatePolicy__c IN :policyIds
				AND refundOutcome__c IN :MONEY_OUTCOMES
			GROUP BY candidatePolicy__c
		]) {
			Decimal total = (Decimal) ar.get('total');
			totals.put((Id) ar.get('policyId'), total == null ? 0 : total.abs());
		}
		List<InsurancePolicy> toUpdate = new List<InsurancePolicy>();
		for (Id policyId : totals.keySet()) {
			toUpdate.add(
				new InsurancePolicy(
					Id = policyId,
					totalRefundedAmount__c = totals.get(policyId)
				)
			);
		}
		List<Database.SaveResult> results = Database.update(toUpdate, false);
		for (Integer i = 0; i < results.size(); i++) {
			if (results[i].isSuccess()) {
				continue;
			}
			CobranzaLog.error(
					CobranzaLog.STAGE_DEVOLUCION,
					CobranzaLog.EVENT_REFUND_FAILED,
					'No se pudo actualizar el total devuelto de la póliza: ' +
					results[i].getErrors()[0].getMessage()
				)
				.onRecord(toUpdate[i].Id);
		}
	}

	/**
	 * @creation date: 15/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Cuotas pagadas de la poliza de la devolucion que el analista puede elegir
	 *               como "Devolucion de una cuota": conciliadas y con un recibo reconocido que
	 *               anular.
	 * @param refundId: Devolucion en revision.
	 * @return Opciones para la accion de resolucion.
	 */
	@AuraEnabled
	public static List<InstallmentOption> getInstallmentOptions(Id refundId) {
		List<InstallmentOption> options = new List<InstallmentOption>();
		List<InboundInsurancePayment__c> refunds = [
			SELECT candidatePolicy__c
			FROM InboundInsurancePayment__c
			WHERE Id = :refundId
		];
		if (refunds.isEmpty() || refunds[0].candidatePolicy__c == null) {
			return options;
		}
		for (PaymentPlanInstallment__c inst : [
			SELECT
				Id,
				sequenceNumber__c,
				dueDate__c,
				expectedAmount__c,
				matchedReceipt__r.receiptAmount__c
			FROM PaymentPlanInstallment__c
			WHERE
				paymentPlan__r.insurancePolicy__c = :refunds[0].candidatePolicy__c
				AND paymentPlan__r.planStatus__c != :PLAN_REPLACED
				AND installmentStatus__c = :INSTALLMENT_RECONCILED
				AND matchedReceipt__r.receiptStatus__c = :RECEIPT_RECOGNIZED
			ORDER BY dueDate__c
		]) {
			Decimal paid = inst.matchedReceipt__r.receiptAmount__c != null
				? inst.matchedReceipt__r.receiptAmount__c
				: inst.expectedAmount__c;
			options.add(
				new InstallmentOption(
					inst.Id,
					'Cuota ' +
						(inst.sequenceNumber__c == null
							? '-'
							: String.valueOf(inst.sequenceNumber__c.intValue())) +
						' · vence ' +
						(inst.dueDate__c == null ? '-' : inst.dueDate__c.format()) +
						' · ' +
						(paid == null ? '-' : paid.setScale(2).format())
				)
			);
		}
		return options;
	}

	/**
	 * @creation date: 15/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Punto de entrada de la accion «Resolver devolucion». Traduce las
	 *               validaciones de negocio a un mensaje para el componente.
	 * @param refundId: Devolucion en revision.
	 * @param resolution: CUOTA, SIN_CUOTA o SIN_EFECTO.
	 * @param installmentId: Cuota devuelta, solo con CUOTA.
	 * @param notes: Notas del analista, obligatorias.
	 * @return
	 */
	@AuraEnabled
	public static void resolve(
		Id refundId,
		String resolution,
		Id installmentId,
		String notes
	) {
		try {
			resolveRefund(refundId, resolution, installmentId, notes);
		} catch (RefundValidationException e) {
			throw new AuraHandledException(e.getMessage());
		}
	}

	/**
	 * @creation date: 15/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Resuelve a mano una devolucion en revision. «Devolucion de una cuota» aplica
	 *               exactamente lo mismo que el proceso automatico sobre la cuota elegida; «sin
	 *               cuota» la registra como devolucion de la poliza y suma al total devuelto; «sin
	 *               efecto» no cambia nada. En todos los casos queda quien, cuando y por que, y
	 *               el pago sale de la bandeja.
	 * @return
	 */
	@TestVisible
	private static void resolveRefund(
		Id refundId,
		String resolution,
		Id installmentId,
		String notes
	) {
		if (refundId == null) {
			throw new RefundValidationException('Falta la devolución a resolver.');
		}
		if (String.isBlank(notes)) {
			throw new RefundValidationException(
				'Debe escribir notas que expliquen la resolución.'
			);
		}
		List<InboundInsurancePayment__c> refunds = [
			SELECT
				Id,
				externalPaymentId__c,
				sourceReceiptNumber__c,
				sourceAmount__c,
				refundOutcome__c,
				candidatePolicy__c,
				candidatePolicy__r.Status
			FROM InboundInsurancePayment__c
			WHERE Id = :refundId
		];
		if (
			refunds.isEmpty() ||
			refunds[0].sourceAmount__c == null ||
			refunds[0].sourceAmount__c >= 0 ||
			!OUTCOME_REVIEW.equals(refunds[0].refundOutcome__c)
		) {
			throw new RefundValidationException(
				'Solo se puede resolver una devolución que está en revisión.'
			);
		}
		InboundInsurancePayment__c refund = refunds[0];

		String outcome;
		if (RESOLUTION_NO_EFFECT.equals(resolution)) {
			outcome = OUTCOME_NO_EFFECT;
		} else if (
			RESOLUTION_INSTALLMENT.equals(resolution) ||
			RESOLUTION_WITHOUT_INSTALLMENT.equals(resolution)
		) {
			if (refund.candidatePolicy__c == null) {
				throw new RefundValidationException(
					'La devolución no tiene póliza identificada: solo puede resolverse como «Sin efecto».'
				);
			}
			outcome = RESOLUTION_INSTALLMENT.equals(resolution)
				? OUTCOME_INSTALLMENT
				: OUTCOME_WITHOUT_INSTALLMENT;
		} else {
			throw new RefundValidationException('Debe elegir una resolución.');
		}

		PaymentPlanInstallment__c installment;
		if (OUTCOME_INSTALLMENT.equals(outcome)) {
			if (installmentId == null) {
				throw new RefundValidationException('Debe elegir la cuota devuelta.');
			}
			List<PaymentPlanInstallment__c> found = [
				SELECT
					Id,
					dueDate__c,
					installmentStatus__c,
					matchedReceipt__c,
					matchedReceipt__r.receiptStatus__c
				FROM PaymentPlanInstallment__c
				WHERE
					Id = :installmentId
					AND paymentPlan__r.insurancePolicy__c = :refund.candidatePolicy__c
			];
			if (
				found.isEmpty() ||
				!INSTALLMENT_RECONCILED.equals(found[0].installmentStatus__c) ||
				found[0].matchedReceipt__c == null ||
				!RECEIPT_RECOGNIZED.equals(found[0].matchedReceipt__r.receiptStatus__c)
			) {
				throw new RefundValidationException(
					'La cuota elegida no es de la póliza de la devolución o no tiene un recibo reconocido que anular.'
				);
			}
			installment = found[0];
		}

		Savepoint sp = Database.setSavepoint();
		try {
			if (installment != null) {
				refundInstallment(
					refund,
					installment,
					POLICY_CANCELLED.equals(refund.candidatePolicy__r.Status)
				);
			}
			update new InboundInsurancePayment__c(
				Id = refund.Id,
				refundOutcome__c = outcome,
				inboundStatus__c = STATUS_REFUND,
				manualReviewRequired__c = false,
				refundResolvedBy__c = UserInfo.getUserId(),
				refundResolvedAt__c = System.now(),
				refundResolutionNotes__c = notes
			);
			if (MONEY_OUTCOMES.contains(outcome)) {
				recalculateTotals(new Set<Id>{ refund.candidatePolicy__c });
			}
		} catch (Exception e) {
			Database.rollback(sp);
			throw new RefundValidationException(
				'No se pudo resolver la devolución: ' + e.getMessage()
			);
		}
		CobranzaLog.info(
				CobranzaLog.STAGE_DEVOLUCION,
				CobranzaLog.EVENT_REFUND_RESOLVED,
				'Devolución resuelta a mano como «' + outcome + '».'
			)
			.onInbound(refund.Id);
		AppLogger.flush();
	}

	/**
	 * @creation date: 18/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Cuotas que anula un negativo que nombra el recibo de una cuota de la poliza.
	 *               El negativo trae el recibo con el que empieza la serie que anula; los demas
	 *               son los siguientes numeros consecutivos (asi numera la aseguradora una serie),
	 *               hasta sumar su importe. Todas tienen que estar abiertas y sin reclamar.
	 * @param refund: Devolucion evaluada.
	 * @param installments: Cuotas de su poliza.
	 * @param claimedInstallments: Cuotas ya tomadas por otra devolucion del envio.
	 * @return null si el negativo no nombra el recibo de ninguna cuota; una lista vacia si lo
	 *         nombra pero no anula cuotas abiertas que sumen su importe; si no, las cuotas.
	 */
	private static List<PaymentPlanInstallment__c> installmentsNamedBy(
		InboundInsurancePayment__c refund,
		List<PaymentPlanInstallment__c> installments,
		Set<Id> claimedInstallments
	) {
		if (String.isBlank(refund.sourceReceiptNumber__c) || installments == null) {
			return null;
		}
		String receipt = refund.sourceReceiptNumber__c.trim();
		Map<String, PaymentPlanInstallment__c> byReceipt = new Map<String, PaymentPlanInstallment__c>();
		for (PaymentPlanInstallment__c inst : installments) {
			if (inst.carrierReceiptNumber__c != null) {
				byReceipt.put(inst.carrierReceiptNumber__c.trim(), inst);
			}
		}
		if (!byReceipt.containsKey(receipt)) {
			return null;
		}

		Long first = receipt.isNumeric() ? Long.valueOf(receipt) : null;
		Decimal amount = refund.sourceAmount__c.abs();
		Decimal total = 0;
		List<PaymentPlanInstallment__c> named = new List<PaymentPlanInstallment__c>();
		for (Integer i = 0; i < installments.size(); i++) {
			if (i > 0 && first == null) {
				break;
			}
			String current = i == 0
				? receipt
				: String.valueOf(first + i).leftPad(receipt.length(), '0');
			PaymentPlanInstallment__c inst = byReceipt.get(current);
			if (
				inst == null ||
				!OPEN_INSTALLMENT_STATUSES.contains(inst.installmentStatus__c) ||
				claimedInstallments.contains(inst.Id)
			) {
				break;
			}
			named.add(inst);
			total += inst.expectedAmount__c == null ? 0 : inst.expectedAmount__c;
			if (sameAmount(total, amount)) {
				return named;
			}
			if (total > amount) {
				break;
			}
		}
		return new List<PaymentPlanInstallment__c>();
	}

	private static void claim(
		List<PaymentPlanInstallment__c> installments,
		Set<Id> claimedInstallments
	) {
		for (PaymentPlanInstallment__c inst : installments) {
			claimedInstallments.add(inst.Id);
		}
	}

	private static Decimal sumExpected(
		List<PaymentPlanInstallment__c> installments
	) {
		Decimal total = 0;
		for (PaymentPlanInstallment__c inst : installments) {
			total += inst.expectedAmount__c == null ? 0 : inst.expectedAmount__c;
		}
		return total;
	}

	/**
	 * @creation date: 15/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Compara dos importes al centavo, sin que importe cuantos decimales traiga
	 *               cada uno.
	 * @return true si son el mismo importe.
	 */
	private static Boolean sameAmount(Decimal a, Decimal b) {
		if (a == null || b == null) {
			return false;
		}
		Decimal left = a.setScale(2);
		Decimal right = b.setScale(2);
		return !(left < right) && !(left > right);
	}
}
