/**
 *   @name: PaymentInstallmentMatchQueueableTest
 *   @version: 1.0
 *   @creation date: 09/06/2026
 *   @author: Javier Torres - Volestra
 *   @description: Valida la actualizacion de la cuota esperada a partir del recibo
 *                 limpio: cobertura total (Conciliado + matchedOn), cobertura parcial
 *                 (queda Pendiente con saldo), elegibilidad (no toca cuotas canceladas
 *                 ni ya vinculadas), no sobrescritura del recibo previo, idempotencia,
 *                 recibos sin cuota y aislamiento de errores.
 */
@IsTest
private class PaymentInstallmentMatchQueueableTest {
	private static Integer seq = 0;

	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	@IsTest
	static void fullCoverageMarksReconciled() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-IM-001', accountId);
		PaymentPlanInstallment__c inst = createInstallment(
			policy.Id,
			400,
			'Pendiente'
		);
		PolicyPaymentReceipt__c receipt = createReceipt(policy.Id, inst.Id, 400);

		Test.startTest();
		System.enqueueJob(
			new PaymentInstallmentMatchQueueable(new Set<Id>{ receipt.Id })
		);
		Test.stopTest();

		PaymentPlanInstallment__c updated = queryInstallment(inst.Id);
		Assert.areEqual(receipt.Id, updated.matchedReceipt__c);
		Assert.areEqual('Conciliado', updated.installmentStatus__c);
		Assert.isNotNull(updated.matchedOn__c);
		Assert.areEqual(400, updated.matchedAmount__c);
		Assert.areEqual(0, updated.outstandingAmount__c);
	}

	@IsTest
	static void overpaymentMarksReconciled() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-IM-002', accountId);
		PaymentPlanInstallment__c inst = createInstallment(
			policy.Id,
			400,
			'Pendiente'
		);
		PolicyPaymentReceipt__c receipt = createReceipt(policy.Id, inst.Id, 500);

		Test.startTest();
		System.enqueueJob(
			new PaymentInstallmentMatchQueueable(new Set<Id>{ receipt.Id })
		);
		Test.stopTest();

		PaymentPlanInstallment__c updated = queryInstallment(inst.Id);
		Assert.areEqual('Conciliado', updated.installmentStatus__c);
		Assert.areEqual(500, updated.matchedAmount__c);
		Assert.areEqual(-100, updated.outstandingAmount__c);
	}

	@IsTest
	static void partialKeepsPendingWithOutstanding() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-IM-003', accountId);
		PaymentPlanInstallment__c inst = createInstallment(
			policy.Id,
			400,
			'Pendiente'
		);
		PolicyPaymentReceipt__c receipt = createReceipt(policy.Id, inst.Id, 250);

		Test.startTest();
		System.enqueueJob(
			new PaymentInstallmentMatchQueueable(new Set<Id>{ receipt.Id })
		);
		Test.stopTest();

		PaymentPlanInstallment__c updated = queryInstallment(inst.Id);
		Assert.areEqual(
			receipt.Id,
			updated.matchedReceipt__c,
			'El recibo parcial igual se vincula'
		);
		Assert.areEqual(
			'Pendiente',
			updated.installmentStatus__c,
			'Un parcial no cierra la cuota'
		);
		Assert.isNull(
			updated.matchedOn__c,
			'Un parcial no sella matchedOn porque la cuota no se cerro'
		);
		Assert.areEqual(250, updated.matchedAmount__c);
		Assert.areEqual(150, updated.outstandingAmount__c);
	}

	@IsTest
	static void ineligibleCancelledNotTouched() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-IM-004', accountId);
		PaymentPlanInstallment__c inst = createInstallment(
			policy.Id,
			400,
			'Cancelado'
		);
		PolicyPaymentReceipt__c receipt = createReceipt(policy.Id, inst.Id, 400);

		Test.startTest();
		System.enqueueJob(
			new PaymentInstallmentMatchQueueable(new Set<Id>{ receipt.Id })
		);
		Test.stopTest();

		PaymentPlanInstallment__c updated = queryInstallment(inst.Id);
		Assert.isNull(updated.matchedReceipt__c, 'No se toca una cuota cancelada');
		Assert.areEqual('Cancelado', updated.installmentStatus__c);
	}

	@IsTest
	static void doesNotOverwriteExistingMatch() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-IM-005', accountId);
		PaymentPlanInstallment__c inst = createInstallment(
			policy.Id,
			400,
			'Pendiente'
		);

		PolicyPaymentReceipt__c receiptA = createReceipt(policy.Id, inst.Id, 250);
		update new PaymentPlanInstallment__c(
			Id = inst.Id,
			matchedReceipt__c = receiptA.Id
		);

		PolicyPaymentReceipt__c receiptB = createReceipt(policy.Id, inst.Id, 400);

		Test.startTest();
		System.enqueueJob(
			new PaymentInstallmentMatchQueueable(new Set<Id>{ receiptB.Id })
		);
		Test.stopTest();

		PaymentPlanInstallment__c updated = queryInstallment(inst.Id);
		Assert.areEqual(
			receiptA.Id,
			updated.matchedReceipt__c,
			'Un segundo recibo no debe sobrescribir el recibo previo'
		);
		Assert.areEqual('Pendiente', updated.installmentStatus__c);
	}

	@IsTest
	static void idempotentReapplyIsNoOp() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-IM-006', accountId);
		PaymentPlanInstallment__c inst = createInstallment(
			policy.Id,
			400,
			'Pendiente'
		);
		PolicyPaymentReceipt__c receipt = createReceipt(policy.Id, inst.Id, 400);

		// La cuota ya quedo conciliada por este mismo recibo en una corrida previa.
		Datetime previousMatchOn = Datetime.newInstance(2026, 1, 1, 0, 0, 0);
		update new PaymentPlanInstallment__c(
			Id = inst.Id,
			matchedReceipt__c = receipt.Id,
			installmentStatus__c = 'Conciliado',
			matchedOn__c = previousMatchOn
		);

		Test.startTest();
		System.enqueueJob(
			new PaymentInstallmentMatchQueueable(new Set<Id>{ receipt.Id })
		);
		Test.stopTest();

		PaymentPlanInstallment__c updated = queryInstallment(inst.Id);
		Assert.areEqual(receipt.Id, updated.matchedReceipt__c);
		Assert.areEqual('Conciliado', updated.installmentStatus__c);
		Assert.areEqual(
			previousMatchOn,
			updated.matchedOn__c,
			'Reaplicar el mismo recibo no debe alterar la cuota'
		);
	}

	@IsTest
	static void receiptWithoutInstallmentIgnored() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-IM-007', accountId);
		PaymentPlanInstallment__c inst = createInstallment(
			policy.Id,
			400,
			'Pendiente'
		);
		PolicyPaymentReceipt__c validReceipt = createReceipt(
			policy.Id,
			inst.Id,
			400
		);
		PolicyPaymentReceipt__c orphanReceipt = createReceipt(policy.Id, null, 100);

		Test.startTest();
		System.enqueueJob(
			new PaymentInstallmentMatchQueueable(
				new Set<Id>{ validReceipt.Id, orphanReceipt.Id }
			)
		);
		Test.stopTest();

		PaymentPlanInstallment__c updated = queryInstallment(inst.Id);
		Assert.areEqual(
			'Conciliado',
			updated.installmentStatus__c,
			'El recibo sin cuota se ignora sin afectar al valido'
		);
		Assert.areEqual(validReceipt.Id, updated.matchedReceipt__c);
	}

	@IsTest
	static void skipsWhenForcedFailure() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-IM-008', accountId);
		PaymentPlanInstallment__c inst = createInstallment(
			policy.Id,
			400,
			'Pendiente'
		);
		PolicyPaymentReceipt__c receipt = createReceipt(policy.Id, inst.Id, 400);

		PaymentInstallmentMatchQueueable.forceFailureForTest = true;

		Test.startTest();
		System.enqueueJob(
			new PaymentInstallmentMatchQueueable(new Set<Id>{ receipt.Id })
		);
		Test.stopTest();

		PaymentPlanInstallment__c updated = queryInstallment(inst.Id);
		Assert.isNull(updated.matchedReceipt__c);
		Assert.areEqual('Pendiente', updated.installmentStatus__c);
	}

	private static InsurancePolicy createPolicy(String name, Id accountId) {
		InsurancePolicy policy = new InsurancePolicy(
			Name = name,
			PolicyName = name,
			NameInsuredId = accountId,
			Status = 'Inicial',
			PremiumAmount = 1200,
			PremiumFrequency = 'Mensual',
			PaymentDueDate = Date.today()
		);
		insert policy;
		return policy;
	}

	private static PaymentPlanInstallment__c createInstallment(
		Id policyId,
		Decimal expectedAmount,
		String status
	) {
		List<PaymentPlan__c> autoPlans = [
			SELECT Id
			FROM PaymentPlan__c
			WHERE insurancePolicy__c = :policyId
		];
		if (!autoPlans.isEmpty()) {
			Set<Id> planIds = new Map<Id, PaymentPlan__c>(autoPlans).keySet();
			delete [
				SELECT Id
				FROM PaymentPlanInstallment__c
				WHERE paymentPlan__c IN :planIds
			];
			delete autoPlans;
		}

		PaymentPlan__c plan = new PaymentPlan__c(
			insurancePolicy__c = policyId,
			planStatus__c = 'Activo',
			premiumFrequency__c = 'Mensual',
			expectedTotalAmount__c = 1200,
			firstDueDate__c = Date.today()
		);
		insert plan;

		PaymentPlanInstallment__c inst = new PaymentPlanInstallment__c(
			paymentPlan__c = plan.Id,
			sequenceNumber__c = 1,
			dueDate__c = Date.today().addDays(30),
			expectedAmount__c = expectedAmount,
			installmentStatus__c = status
		);
		insert inst;
		return inst;
	}

	private static PolicyPaymentReceipt__c createReceipt(
		Id policyId,
		Id installmentId,
		Decimal amount
	) {
		seq++;
		InboundInsurancePayment__c inbound = new InboundInsurancePayment__c(
			externalPaymentId__c = 'EXT-IM-' + seq,
			inboundStatus__c = 'Conciliado',
			candidatePolicy__c = policyId,
			sourceAmount__c = amount,
			sourcePaymentDate__c = Date.today(),
			sourcePolicyNumber__c = 'POL-TEST',
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now()
		);
		insert inbound;

		PaymentReconciliation__c recon = new PaymentReconciliation__c(
			inboundPayment__c = inbound.Id,
			insurancePolicy__c = policyId,
			reconciliationStatus__c = 'Conciliado',
			matchMethod__c = 'Cuota exacta',
			confidenceScore__c = 95,
			candidateCount__c = 1
		);
		insert recon;

		PolicyPaymentReceipt__c receipt = new PolicyPaymentReceipt__c(
			insurancePolicy__c = policyId,
			paymentReconciliation__c = recon.Id,
			paymentPlanInstallment__c = installmentId,
			receiptAmount__c = amount,
			receiptDate__c = Date.today(),
			receiptStatus__c = 'Reconocido'
		);
		insert receipt;
		return receipt;
	}

	private static PaymentPlanInstallment__c queryInstallment(Id installmentId) {
		return [
			SELECT
				Id,
				installmentStatus__c,
				matchedReceipt__c,
				matchedOn__c,
				matchedAmount__c,
				outstandingAmount__c,
				expectedAmount__c
			FROM PaymentPlanInstallment__c
			WHERE Id = :installmentId
		];
	}
}
