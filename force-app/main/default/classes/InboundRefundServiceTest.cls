/**
 *   @name: InboundRefundServiceTest
 *   @version: 1.0
 *   @creation date: 15/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Pruebas de las devoluciones y anulaciones de la aseguradora: que se aplica
 *                 solo lo que coincide exactamente, que lo demas queda para el analista sin
 *                 tocar nada, y que la resolucion manual deja el sistema igual que la
 *                 automatica.
 */
@IsTest
private class InboundRefundServiceTest {
	private static final Date DUE_1 = Date.newInstance(2026, 1, 15);
	private static final Date DUE_2 = Date.newInstance(2026, 2, 15);
	private static final Date DUE_3 = Date.newInstance(2026, 3, 15);
	private static Integer sequence = 0;

	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	// ================================================================
	// Datos de apoyo

	/**
	 * Una poliza Inicial o Vigente exige prima, frecuencia y fecha de pago, y al crearla el
	 * sistema le genera su plan inicial: esas polizas se crean con esos datos y la prueba reusa
	 * ese plan. Las de otros estados no los exigen ni generan plan.
	 */
	private static InsurancePolicy policy(String policyNumber, String status) {
		InsurancePolicy p = CollectionsTestDataFactory.buildPolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			status
		);
		p.Name = policyNumber;
		if (status == 'Inicial' || status == 'Vigente') {
			p.PremiumAmount = 1200;
			p.PremiumFrequency = 'Mensual';
			p.PaymentDueDate = DUE_1;
		}
		insert p;
		return p;
	}

	/**
	 * Deja una cuota Pendiente de 100 por cada vencimiento, sobre el plan que ya tenga la
	 * poliza o sobre uno nuevo.
	 */
	private static List<PaymentPlanInstallment__c> installments(
		InsurancePolicy p,
		List<Date> dueDates
	) {
		List<PaymentPlan__c> existingPlans = [
			SELECT Id
			FROM PaymentPlan__c
			WHERE insurancePolicy__c = :p.Id AND planStatus__c != 'Reemplazado'
			LIMIT 1
		];
		PaymentPlan__c plan = !existingPlans.isEmpty()
			? existingPlans[0]
			: CollectionsTestDataFactory.createPlan(
					p.Id,
					'Activo',
					'Mensual',
					100 * dueDates.size(),
					dueDates[0],
					dueDates.size()
			  );
		List<PaymentPlanInstallment__c> generated = CollectionsTestDataFactory.getInstallmentsByPlan(
			plan.Id
		);
		List<PaymentPlanInstallment__c> result = new List<PaymentPlanInstallment__c>();
		for (Integer i = 0; i < dueDates.size(); i++) {
			PaymentPlanInstallment__c inst = i < generated.size()
				? new PaymentPlanInstallment__c(Id = generated[i].Id)
				: new PaymentPlanInstallment__c(
						paymentPlan__c = plan.Id,
						sequenceNumber__c = i + 1
				  );
			inst.dueDate__c = dueDates[i];
			inst.expectedAmount__c = 100;
			inst.installmentStatus__c = 'Pendiente';
			result.add(inst);
		}
		upsert result;
		// El generador del plan puede crear mas cuotas de las que la prueba necesita: se dejan
		// condonadas para que no entren en ninguna suma ni coincidencia.
		List<PaymentPlanInstallment__c> extras = new List<PaymentPlanInstallment__c>();
		for (Integer i = dueDates.size(); i < generated.size(); i++) {
			extras.add(
				new PaymentPlanInstallment__c(
					Id = generated[i].Id,
					installmentStatus__c = 'Condonado'
				)
			);
		}
		update extras;
		return result;
	}

	private static InboundInsurancePayment__c charge(
		InsurancePolicy p,
		Date dueDate,
		Decimal amount,
		String status
	) {
		sequence++;
		InboundInsurancePayment__c inbound = new InboundInsurancePayment__c(
			externalPaymentId__c = 'EXT-432-C' + sequence,
			inboundStatus__c = status,
			sourceAmount__c = amount,
			sourceDueDate__c = dueDate,
			sourcePaymentDate__c = dueDate,
			sourcePolicyNumber__c = p.Name,
			carrierReceiptStatus__c = 'Pagado',
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now()
		);
		insert inbound;
		return inbound;
	}

	/**
	 * Deja la cuota conciliada: pago, conciliacion y recibo reconocido enlazado a la cuota.
	 */
	private static PolicyPaymentReceipt__c reconcile(
		InsurancePolicy p,
		PaymentPlanInstallment__c inst
	) {
		InboundInsurancePayment__c inbound = charge(
			p,
			inst.dueDate__c,
			100,
			'Conciliado'
		);
		PaymentReconciliation__c recon = new PaymentReconciliation__c(
			inboundPayment__c = inbound.Id,
			insurancePolicy__c = p.Id,
			reconciliationStatus__c = 'Conciliado'
		);
		insert recon;
		PolicyPaymentReceipt__c receipt = new PolicyPaymentReceipt__c(
			insurancePolicy__c = p.Id,
			sourceInboundPayment__c = inbound.Id,
			paymentReconciliation__c = recon.Id,
			paymentPlanInstallment__c = inst.Id,
			receiptDate__c = inst.dueDate__c,
			receiptAmount__c = 100,
			receiptStatus__c = 'Reconocido',
			receiptNumber__c = 'REC-432-' + sequence
		);
		insert receipt;
		update new PaymentReconciliation__c(
			Id = recon.Id,
			resultingReceipt__c = receipt.Id
		);
		update new PaymentPlanInstallment__c(
			Id = inst.Id,
			installmentStatus__c = 'Conciliado',
			matchedReceipt__c = receipt.Id,
			matchedOn__c = System.now()
		);
		return receipt;
	}

	private static InboundInsurancePayment__c refund(
		InsurancePolicy p,
		Decimal amount,
		Date dueDate,
		String carrierStatus
	) {
		sequence++;
		InboundInsurancePayment__c inbound = new InboundInsurancePayment__c(
			externalPaymentId__c = 'EXT-432-R' + sequence,
			sourceReceiptNumber__c = 'R' + sequence,
			inboundStatus__c = 'Devolucion',
			sourceAmount__c = amount,
			sourceDueDate__c = dueDate,
			sourcePolicyNumber__c = p.Name,
			carrierReceiptStatus__c = carrierStatus,
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now()
		);
		insert inbound;
		return inbound;
	}

	private static InboundInsurancePayment__c reload(Id refundId) {
		return [
			SELECT
				inboundStatus__c,
				refundOutcome__c,
				refundReviewReason__c,
				manualReviewRequired__c,
				candidatePolicy__c,
				refundResolvedBy__c,
				refundResolvedAt__c,
				refundResolutionNotes__c
			FROM InboundInsurancePayment__c
			WHERE Id = :refundId
		];
	}

	private static PaymentPlanInstallment__c installment(Id installmentId) {
		return [
			SELECT installmentStatus__c, matchedReceipt__c, cancelledByRefund__c
			FROM PaymentPlanInstallment__c
			WHERE Id = :installmentId
		];
	}

	private static PolicyPaymentReceipt__c receipt(Id receiptId) {
		return [
			SELECT receiptStatus__c, reversalReason__c, refundInboundPayment__c
			FROM PolicyPaymentReceipt__c
			WHERE Id = :receiptId
		];
	}

	private static Decimal totalRefunded(Id policyId) {
		return [
			SELECT totalRefundedAmount__c
			FROM InsurancePolicy
			WHERE Id = :policyId
		]
		.totalRefundedAmount__c;
	}

	private static void process(Id refundId) {
		InboundRefundService.process(new Set<Id>{ refundId });
	}

	// ================================================================
	// Devolucion de una cuota pagada

	@IsTest
	static void installmentRefundOnLivePolicyReopensTheInstallment() {
		InsurancePolicy p = policy('POL-432-01', 'Inicial');
		List<PaymentPlanInstallment__c> insts = installments(
			p,
			new List<Date>{ DUE_1, DUE_2, DUE_3 }
		);
		PolicyPaymentReceipt__c paid = reconcile(p, insts[0]);
		InboundInsurancePayment__c r = refund(p, -100, DUE_1, 'Pagado');

		Test.startTest();
		process(r.Id);
		Test.stopTest();

		PolicyPaymentReceipt__c reversed = receipt(paid.Id);
		Assert.areEqual('Reversado', reversed.receiptStatus__c);
		Assert.areEqual('Devolucion', reversed.reversalReason__c);
		Assert.areEqual(
			r.Id,
			reversed.refundInboundPayment__c,
			'Desde el recibo se ve que devolución lo anuló'
		);
		PaymentPlanInstallment__c inst = installment(insts[0].Id);
		Assert.areEqual(
			'Pendiente',
			inst.installmentStatus__c,
			'Póliza viva: se vuelve a deber'
		);
		Assert.isNull(inst.matchedReceipt__c);

		InboundInsurancePayment__c after = reload(r.Id);
		Assert.areEqual('Devolucion de cuota', after.refundOutcome__c);
		Assert.areEqual('Devolucion', after.inboundStatus__c);
		Assert.areEqual(p.Id, after.candidatePolicy__c);
		Assert.isFalse(after.manualReviewRequired__c);
		Assert.areEqual(100, totalRefunded(p.Id));

		Assert.areEqual(
			'Conciliado',
			[
				SELECT inboundStatus__c
				FROM InboundInsurancePayment__c
				WHERE
					Id = :[
						SELECT sourceInboundPayment__c
						FROM PolicyPaymentReceipt__c
						WHERE Id = :paid.Id
					]
					.sourceInboundPayment__c
			]
			.inboundStatus__c,
			'El pago que concilió la cuota fue real: no vuelve a la bandeja'
		);
		Assert.areEqual(
			'Conciliado',
			[
				SELECT reconciliationStatus__c
				FROM PaymentReconciliation__c
				WHERE
					Id = :[
						SELECT paymentReconciliation__c
						FROM PolicyPaymentReceipt__c
						WHERE Id = :paid.Id
					]
					.paymentReconciliation__c
			]
			.reconciliationStatus__c,
			'Ni su conciliación vuelve a revisión'
		);
	}

	@IsTest
	static void installmentRefundOnCancelledPolicyCancelsTheInstallment() {
		InsurancePolicy p = policy('POL-432-02', 'Cancelado');
		List<PaymentPlanInstallment__c> insts = installments(
			p,
			new List<Date>{ DUE_1, DUE_2, DUE_3 }
		);
		reconcile(p, insts[0]);
		InboundInsurancePayment__c r = refund(p, -100, DUE_1, 'Pagado');

		Test.startTest();
		process(r.Id);
		Test.stopTest();

		PaymentPlanInstallment__c inst = installment(insts[0].Id);
		Assert.areEqual(
			'Cancelado',
			inst.installmentStatus__c,
			'Póliza cancelada: la cuota ya no se debe'
		);
		Assert.areEqual(r.Id, inst.cancelledByRefund__c);
		Assert.areEqual('Devolucion de cuota', reload(r.Id).refundOutcome__c);
		Assert.areEqual(100, totalRefunded(p.Id));
	}

	@IsTest
	static void installmentRefundOnPolicyInAnotherStatusGoesToReview() {
		InsurancePolicy p = policy('POL-432-03', 'Suspendido');
		List<PaymentPlanInstallment__c> insts = installments(
			p,
			new List<Date>{ DUE_1, DUE_2, DUE_3 }
		);
		PolicyPaymentReceipt__c paid = reconcile(p, insts[0]);
		InboundInsurancePayment__c r = refund(p, -100, DUE_1, 'Pagado');

		Test.startTest();
		process(r.Id);
		Test.stopTest();

		InboundInsurancePayment__c after = reload(r.Id);
		Assert.areEqual('Requiere revision', after.refundOutcome__c);
		Assert.areEqual('Revision Manual', after.inboundStatus__c);
		Assert.isTrue(after.manualReviewRequired__c);
		Assert.isTrue(after.refundReviewReason__c.contains('Suspendido'));
		Assert.areEqual('Reconocido', receipt(paid.Id).receiptStatus__c);
	}

	// ================================================================
	// Anulacion contable y estatus

	@IsTest
	static void accountingCancellationCancelsTheUnpaidInstallments() {
		InsurancePolicy p = policy('POL-432-04', 'Inicial');
		List<PaymentPlanInstallment__c> insts = installments(
			p,
			new List<Date>{ DUE_1, DUE_2, DUE_3 }
		);
		PolicyPaymentReceipt__c paid = reconcile(p, insts[0]);
		InboundInsurancePayment__c r = refund(p, -200, DUE_2, 'Cancelado');

		Test.startTest();
		process(r.Id);
		Test.stopTest();

		Assert.areEqual('Anulacion contable', reload(r.Id).refundOutcome__c);
		for (Integer i = 1; i < 3; i++) {
			PaymentPlanInstallment__c inst = installment(insts[i].Id);
			Assert.areEqual('Cancelado', inst.installmentStatus__c);
			Assert.areEqual(r.Id, inst.cancelledByRefund__c);
		}
		Assert.areEqual(
			'Conciliado',
			installment(insts[0].Id).installmentStatus__c,
			'La cuota pagada no se toca'
		);
		Assert.areEqual('Reconocido', receipt(paid.Id).receiptStatus__c);
		Assert.areEqual(
			0,
			totalRefunded(p.Id) == null ? 0 : totalRefunded(p.Id),
			'Una anulación contable no mueve dinero'
		);
	}

	@IsTest
	static void cancelledNegativeMatchingAPaidInstallmentHasNoEffect() {
		InsurancePolicy p = policy('POL-432-05', 'Inicial');
		List<PaymentPlanInstallment__c> insts = installments(
			p,
			new List<Date>{ DUE_1, DUE_2, DUE_3 }
		);
		PolicyPaymentReceipt__c paid = reconcile(p, insts[0]);
		// Coincide con la cuota pagada, pero la aseguradora lo reporta cancelado.
		InboundInsurancePayment__c r = refund(p, -100, DUE_1, 'Cancelado');

		Test.startTest();
		process(r.Id);
		Test.stopTest();

		Assert.areEqual('Sin efecto', reload(r.Id).refundOutcome__c);
		Assert.areEqual(
			'Reconocido',
			receipt(paid.Id).receiptStatus__c,
			'Un negativo cancelado no anula un cobro bueno'
		);
	}

	@IsTest
	static void pendingOrOverdueRefundHasNoEffectYet() {
		InsurancePolicy p = policy('POL-432-06', 'Inicial');
		List<PaymentPlanInstallment__c> insts = installments(
			p,
			new List<Date>{ DUE_1, DUE_2 }
		);
		PolicyPaymentReceipt__c paid = reconcile(p, insts[0]);
		InboundInsurancePayment__c pending = refund(p, -100, DUE_1, 'Pendiente');
		InboundInsurancePayment__c overdue = refund(p, -100, DUE_1, 'Vencido');

		Test.startTest();
		InboundRefundService.process(new Set<Id>{ pending.Id, overdue.Id });
		Test.stopTest();

		Assert.areEqual(
			'Pendiente de aplicar',
			reload(pending.Id).refundOutcome__c
		);
		Assert.areEqual(
			'Pendiente de aplicar',
			reload(overdue.Id).refundOutcome__c
		);
		Assert.areEqual('Reconocido', receipt(paid.Id).receiptStatus__c);
	}

	// ================================================================
	// Lo que no es exacto lo decide el analista

	@IsTest
	static void aCentDifferenceGoesToReview() {
		InsurancePolicy p = policy('POL-432-07', 'Inicial');
		List<PaymentPlanInstallment__c> insts = installments(
			p,
			new List<Date>{ DUE_1, DUE_2 }
		);
		PolicyPaymentReceipt__c paid = reconcile(p, insts[0]);
		InboundInsurancePayment__c r = refund(p, -100.01, DUE_1, 'Pagado');

		Test.startTest();
		process(r.Id);
		Test.stopTest();

		InboundInsurancePayment__c after = reload(r.Id);
		Assert.areEqual('Requiere revision', after.refundOutcome__c);
		Assert.isTrue(after.refundReviewReason__c.contains('No coincide'));
		Assert.areEqual('Reconocido', receipt(paid.Id).receiptStatus__c);
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM AppLog__c
				WHERE eventCode__c = :CobranzaLog.EVENT_REFUND_TO_REVIEW
			]
		);
	}

	@IsTest
	static void matchingBothAPaidInstallmentAndTheUnpaidSumIsAmbiguous() {
		InsurancePolicy p = policy('POL-432-08', 'Inicial');
		List<PaymentPlanInstallment__c> insts = installments(
			p,
			new List<Date>{ DUE_1, DUE_2 }
		);
		PolicyPaymentReceipt__c paid = reconcile(p, insts[0]);
		// 100 es la cuota pagada del 15/01 y también la suma de las no pagadas desde esa fecha.
		InboundInsurancePayment__c r = refund(p, -100, DUE_1, 'Pagado');

		Test.startTest();
		process(r.Id);
		Test.stopTest();

		Assert.areEqual('Requiere revision', reload(r.Id).refundOutcome__c);
		Assert.areEqual('Reconocido', receipt(paid.Id).receiptStatus__c);
		Assert.areEqual('Pendiente', installment(insts[1].Id).installmentStatus__c);
	}

	@IsTest
	static void aDuplicateChargeKeepsTheInstallmentPaid() {
		InsurancePolicy p = policy('POL-432-09', 'Inicial');
		List<PaymentPlanInstallment__c> insts = installments(
			p,
			new List<Date>{ DUE_1, DUE_2, DUE_3 }
		);
		PolicyPaymentReceipt__c paid = reconcile(p, insts[0]);
		// Segundo cobro de la misma cuota: quedó sin cuota libre, en revisión manual.
		charge(p, DUE_1, 100, 'Revision Manual');
		InboundInsurancePayment__c r = refund(p, -100, DUE_1, 'Pagado');

		Test.startTest();
		process(r.Id);
		Test.stopTest();

		InboundInsurancePayment__c after = reload(r.Id);
		Assert.areEqual('Requiere revision', after.refundOutcome__c);
		Assert.isTrue(after.refundReviewReason__c.contains('dos veces'));
		Assert.areEqual(
			'Reconocido',
			receipt(paid.Id).receiptStatus__c,
			'La cuota sigue pagada con el cobro que queda'
		);
	}

	@IsTest
	static void aRefundWithoutPolicyGoesToReview() {
		InsurancePolicy p = new InsurancePolicy(Name = 'POL-432-NO-EXISTE');
		InboundInsurancePayment__c r = refund(p, -100, DUE_1, 'Pagado');

		Test.startTest();
		process(r.Id);
		Test.stopTest();

		InboundInsurancePayment__c after = reload(r.Id);
		Assert.areEqual('Requiere revision', after.refundOutcome__c);
		Assert.isNull(after.candidatePolicy__c);
	}

	// ================================================================
	// Idempotencia y fallos

	@IsTest
	static void aRefundIsNeverAppliedTwice() {
		InsurancePolicy p = policy('POL-432-10', 'Inicial');
		List<PaymentPlanInstallment__c> insts = installments(
			p,
			new List<Date>{ DUE_1, DUE_2, DUE_3 }
		);
		reconcile(p, insts[0]);
		InboundInsurancePayment__c r = refund(p, -100, DUE_1, 'Pagado');
		process(r.Id);

		Test.startTest();
		process(r.Id);
		Test.stopTest();

		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM PolicyPaymentReceipt__c
				WHERE refundInboundPayment__c = :r.Id
			]
		);
		Assert.areEqual(100, totalRefunded(p.Id), 'El total no cambia');
	}

	@IsTest
	static void aFailureUndoesEverythingAndLeavesItForReview() {
		InsurancePolicy p = policy('POL-432-11', 'Inicial');
		List<PaymentPlanInstallment__c> insts = installments(
			p,
			new List<Date>{ DUE_1, DUE_2, DUE_3 }
		);
		PolicyPaymentReceipt__c paid = reconcile(p, insts[0]);
		InboundInsurancePayment__c r = refund(p, -100, DUE_1, 'Pagado');
		InboundRefundService.forceFailureForTest = true;

		Test.startTest();
		process(r.Id);
		Test.stopTest();

		InboundRefundService.forceFailureForTest = false;
		Assert.areEqual('Requiere revision', reload(r.Id).refundOutcome__c);
		Assert.areEqual('Reconocido', receipt(paid.Id).receiptStatus__c);
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM AppLog__c
				WHERE eventCode__c = :CobranzaLog.EVENT_REFUND_FAILED
			]
		);
	}

	// ================================================================
	// Resolucion manual

	private static InboundInsurancePayment__c refundInReview(
		InsurancePolicy p,
		Decimal amount
	) {
		InboundInsurancePayment__c r = refund(p, amount, DUE_1, 'Pagado');
		process(r.Id);
		Assert.areEqual('Requiere revision', reload(r.Id).refundOutcome__c);
		return r;
	}

	@IsTest
	static void analystResolvesARefundWithoutInstallment() {
		InsurancePolicy p = policy('POL-432-12', 'Inicial');
		installments(p, new List<Date>{ DUE_1, DUE_2 });
		InboundInsurancePayment__c r = refundInReview(p, -345.67);

		Test.startTest();
		InboundRefundService.resolve(
			r.Id,
			InboundRefundService.RESOLUTION_WITHOUT_INSTALLMENT,
			null,
			'Devolución de prima al cancelar.'
		);
		Test.stopTest();

		InboundInsurancePayment__c after = reload(r.Id);
		Assert.areEqual('Devolucion sin cuota', after.refundOutcome__c);
		Assert.areEqual('Devolucion', after.inboundStatus__c);
		Assert.isFalse(after.manualReviewRequired__c, 'Sale de la bandeja');
		Assert.areEqual(UserInfo.getUserId(), after.refundResolvedBy__c);
		Assert.isNotNull(after.refundResolvedAt__c);
		Assert.areEqual(
			'Devolución de prima al cancelar.',
			after.refundResolutionNotes__c
		);
		Assert.areEqual(345.67, totalRefunded(p.Id));
	}

	@IsTest
	static void analystResolvesARefundOnAChosenInstallment() {
		InsurancePolicy p = policy('POL-432-13', 'Inicial');
		List<PaymentPlanInstallment__c> insts = installments(
			p,
			new List<Date>{ DUE_1, DUE_2 }
		);
		PolicyPaymentReceipt__c paid = reconcile(p, insts[0]);
		InboundInsurancePayment__c r = refundInReview(p, -100.01);

		List<InboundRefundService.InstallmentOption> options = InboundRefundService.getInstallmentOptions(
			r.Id
		);
		Assert.areEqual(1, options.size(), 'Solo la cuota pagada se puede elegir');
		Assert.areEqual(String.valueOf(insts[0].Id), options[0].value);

		Test.startTest();
		InboundRefundService.resolve(
			r.Id,
			InboundRefundService.RESOLUTION_INSTALLMENT,
			insts[0].Id,
			'Diferencia de un centavo: es la devolución de la cuota 1.'
		);
		Test.stopTest();

		Assert.areEqual('Reversado', receipt(paid.Id).receiptStatus__c);
		Assert.areEqual('Pendiente', installment(insts[0].Id).installmentStatus__c);
		Assert.areEqual('Devolucion de cuota', reload(r.Id).refundOutcome__c);
		Assert.areEqual(100.01, totalRefunded(p.Id));
	}

	@IsTest
	static void analystResolvesARefundWithNoEffect() {
		InsurancePolicy p = policy('POL-432-14', 'Inicial');
		List<PaymentPlanInstallment__c> insts = installments(
			p,
			new List<Date>{ DUE_1, DUE_2, DUE_3 }
		);
		PolicyPaymentReceipt__c paid = reconcile(p, insts[0]);
		charge(p, DUE_1, 100, 'Revision Manual');
		InboundInsurancePayment__c r = refundInReview(p, -100);

		Test.startTest();
		InboundRefundService.resolve(
			r.Id,
			InboundRefundService.RESOLUTION_NO_EFFECT,
			null,
			'Es la devolución del cobro duplicado.'
		);
		Test.stopTest();

		Assert.areEqual('Sin efecto', reload(r.Id).refundOutcome__c);
		Assert.areEqual('Reconocido', receipt(paid.Id).receiptStatus__c);
	}

	@IsTest
	static void manualResolutionIsValidated() {
		InsurancePolicy p = policy('POL-432-15', 'Inicial');
		installments(p, new List<Date>{ DUE_1, DUE_2 });
		InboundInsurancePayment__c r = refundInReview(p, -345.67);
		InboundInsurancePayment__c applied = refund(p, -50, DUE_1, 'Pendiente');
		process(applied.Id);

		Test.startTest();
		List<String> errors = new List<String>();
		for (
			List<Object> attempt : new List<List<Object>>{
				new List<Object>{ r.Id, 'SIN_CUOTA', null, '' },
				new List<Object>{ r.Id, 'CUOTA', null, 'Sin cuota elegida' },
				new List<Object>{ r.Id, null, null, 'Sin resolución' },
				new List<Object>{
					applied.Id,
					'SIN_EFECTO',
					null,
					'No está en revisión'
				}
			}
		) {
			try {
				InboundRefundService.resolve(
					(Id) attempt[0],
					(String) attempt[1],
					(Id) attempt[2],
					(String) attempt[3]
				);
			} catch (AuraHandledException e) {
				errors.add(e.getMessage());
			}
		}
		Test.stopTest();

		Assert.areEqual(4, errors.size(), 'Los cuatro intentos se rechazan');
		Assert.areEqual('Requiere revision', reload(r.Id).refundOutcome__c);
	}

	// ================================================================
	// Recepcion y proceso asincrono

	@IsTest
	static void theEndpointAcceptsNegativeAndZeroAmounts() {
		InsurancePolicy p = policy('POL-432-16', 'Inicial');
		installments(p, new List<Date>{ DUE_1, DUE_2 });

		RestRequest request = new RestRequest();
		request.requestUri = '/services/apexrest/collections/v1/inbound-payments';
		request.httpMethod = 'POST';
		request.requestBody = Blob.valueOf(
			'[' +
				'{"sourcePolicyNumber__c":"POL-432-16","sourceAmount__c":-345.67,' +
				'"sourceDueDate__c":"15/01/2026","sourcePaymentDate__c":"20/01/2026",' +
				'"sourcePaymentStatus__c":"Pagado","sourceCarrierCode__c":"QUALITAS",' +
				'"sourceReceiptNumber__c":"432-NEG"},' +
				'{"sourcePolicyNumber__c":"POL-432-16","sourceAmount__c":0,' +
				'"sourcePaymentStatus__c":"Cancelado","sourceCarrierCode__c":"QUALITAS",' +
				'"sourceReceiptNumber__c":"432-CERO"}' +
				']'
		);
		RestContext.request = request;
		RestContext.response = new RestResponse();

		Test.startTest();
		InboundInsurancePaymentRestResource.receive();
		Test.stopTest();

		Assert.areEqual(202, RestContext.response.statusCode);
		InboundInsurancePayment__c negative = [
			SELECT inboundStatus__c, refundOutcome__c, rejectionReason__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'QUALITAS_432-NEG'
		];
		Assert.isNull(negative.rejectionReason__c, 'Un negativo ya no se rechaza');
		Assert.areEqual(
			'Requiere revision',
			negative.refundOutcome__c,
			'El proceso de devoluciones corrió: no coincide con ninguna cuota pagada'
		);
		Assert.areEqual(
			'No Conciliable',
			[
				SELECT inboundStatus__c
				FROM InboundInsurancePayment__c
				WHERE externalPaymentId__c = 'QUALITAS_432-CERO'
			]
			.inboundStatus__c,
			'Un importe cero se guarda sin efecto'
		);
	}

	@IsTest
	static void theQueueableProcessesInBatches() {
		InsurancePolicy p = policy('POL-432-17', 'Inicial');
		installments(p, new List<Date>{ DUE_1, DUE_2 });
		InboundInsurancePayment__c first = refund(p, -1, DUE_1, 'Pendiente');
		InboundInsurancePayment__c second = refund(p, -2, DUE_1, 'Pendiente');
		InboundRefundQueueable.maxPerJob = 1;

		Test.startTest();
		System.enqueueJob(
			new InboundRefundQueueable(new Set<Id>{ first.Id, second.Id })
		);
		Test.stopTest();

		Integer processed = [
			SELECT COUNT()
			FROM InboundInsurancePayment__c
			WHERE
				Id IN :new Set<Id>{ first.Id, second.Id }
				AND refundOutcome__c = 'Pendiente de aplicar'
		];
		Assert.isTrue(processed >= 1, 'La primera tanda se procesa');
	}
}
