/**
 *   @name: InboundInstallmentCandidateQueueableTest
 *   @version: 1.0
 *   @creation date: 07/05/2026
 *   @author: Javier Torres - Volestra
 *   @description: Valida el algoritmo de scoring multi-senal para la identificacion
 *                 de cuota candidata en pagos inbound normalizados. Cubre asignacion
 *                 por secuencia exacta, fecha exacta, fecha proxima, monto exacto,
 *                 monto proximo, empate, puntaje bajo el minimo, sin poliza candidata,
 *                 exclusion de cuotas conciliadas y exclusion de planes cancelados.
 */
@IsTest
private class InboundInstallmentCandidateQueueableTest {
	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	@IsTest
	static void assignsInstallmentByExactDueDateAndAmount() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = new InsurancePolicy(
			Name = 'POL-IC-001',
			PolicyName = 'Test Policy',
			NameInsuredId = accountId,
			Status = 'Inicial',
			PremiumAmount = 1000,
			PremiumFrequency = 'Mensual',
			PaymentDueDate = Date.today()
		);
		insert policy;
		PaymentPlan__c plan = createActivePlan(policy.Id);
		Date dueDate = Date.today().addDays(30);
		PaymentPlanInstallment__c installment = createInstallment(
			plan.Id,
			1,
			dueDate,
			400,
			'Pendiente'
		);

		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-IC-001',
			policy.Id,
			null,
			dueDate,
			400
		);

		Test.startTest();
		System.enqueueJob(
			new InboundInstallmentCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT candidateInstallment__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual(installment.Id, inbound.candidateInstallment__c);
	}

	@IsTest
	static void assignsInstallmentBySequenceNumber() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = new InsurancePolicy(
			Name = 'POL-IC-002',
			PolicyName = 'Test Policy',
			NameInsuredId = accountId,
			Status = 'Inicial',
			PremiumAmount = 1000,
			PremiumFrequency = 'Mensual',
			PaymentDueDate = Date.today()
		);
		insert policy;
		PaymentPlan__c plan = createActivePlan(policy.Id);
		PaymentPlanInstallment__c installment = createInstallment(
			plan.Id,
			1,
			Date.today().addDays(30),
			400,
			'Pendiente'
		);

		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-IC-002',
			policy.Id,
			'1',
			Date.today().addDays(30),
			999
		);

		Test.startTest();
		System.enqueueJob(
			new InboundInstallmentCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT candidateInstallment__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual(installment.Id, inbound.candidateInstallment__c);
	}

	@IsTest
	static void assignsWhenAmountMatchesAndDateIsClose() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = new InsurancePolicy(
			Name = 'POL-IC-003',
			PolicyName = 'Test Policy',
			NameInsuredId = accountId,
			Status = 'Inicial',
			PremiumAmount = 1000,
			PremiumFrequency = 'Mensual',
			PaymentDueDate = Date.today()
		);
		insert policy;
		PaymentPlan__c plan = createActivePlan(policy.Id);
		createInstallment(plan.Id, 1, Date.today().addDays(30), 400, 'Pendiente');

		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-IC-003',
			policy.Id,
			null,
			Date.today().addDays(33),
			400
		);

		Test.startTest();
		System.enqueueJob(
			new InboundInstallmentCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT candidateInstallment__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.isNotNull(inbound.candidateInstallment__c);
	}

	@IsTest
	static void assignsWhenDateMatchesAndAmountDiffersSlightly() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = new InsurancePolicy(
			Name = 'POL-IC-004',
			PolicyName = 'Test Policy',
			NameInsuredId = accountId,
			Status = 'Inicial',
			PremiumAmount = 1000,
			PremiumFrequency = 'Mensual',
			PaymentDueDate = Date.today()
		);
		insert policy;
		PaymentPlan__c plan = createActivePlan(policy.Id);
		Date dueDate = Date.today().addDays(30);
		PaymentPlanInstallment__c installment = createInstallment(
			plan.Id,
			1,
			dueDate,
			400,
			'Pendiente'
		);

		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-IC-004',
			policy.Id,
			null,
			dueDate,
			412
		);

		Test.startTest();
		System.enqueueJob(
			new InboundInstallmentCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT candidateInstallment__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual(installment.Id, inbound.candidateInstallment__c);
	}

	@IsTest
	static void leavesNullWhenMultipleInstallmentsScoreEqually() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = new InsurancePolicy(
			Name = 'POL-IC-005',
			PolicyName = 'Test Policy',
			NameInsuredId = accountId,
			Status = 'Inicial',
			PremiumAmount = 1000,
			PremiumFrequency = 'Mensual',
			PaymentDueDate = Date.today()
		);
		insert policy;
		PaymentPlan__c plan = createActivePlan(policy.Id);
		Date sharedDueDate = Date.today().addDays(30);
		createInstallment(plan.Id, 1, sharedDueDate, 300, 'Pendiente');
		createInstallment(plan.Id, 2, sharedDueDate, 500, 'Pendiente');

		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-IC-005',
			policy.Id,
			null,
			sharedDueDate,
			null
		);

		Test.startTest();
		System.enqueueJob(
			new InboundInstallmentCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT candidateInstallment__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.isNull(inbound.candidateInstallment__c);
	}

	@IsTest
	static void leavesNullWhenScoreBelowThreshold() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = new InsurancePolicy(
			Name = 'POL-IC-006',
			PolicyName = 'Test Policy',
			NameInsuredId = accountId,
			Status = 'Inicial',
			PremiumAmount = 1000,
			PremiumFrequency = 'Mensual',
			PaymentDueDate = Date.today()
		);
		insert policy;
		PaymentPlan__c plan = createActivePlan(policy.Id);
		createInstallment(plan.Id, 1, Date.today().addDays(30), 400, 'Pendiente');

		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-IC-006',
			policy.Id,
			null,
			null,
			400
		);

		Test.startTest();
		System.enqueueJob(
			new InboundInstallmentCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT candidateInstallment__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.isNull(inbound.candidateInstallment__c);
	}

	@IsTest
	static void leavesNullWhenNoCandidatePolicy() {
		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-IC-007',
			null,
			null,
			Date.today().addDays(30),
			400
		);

		Test.startTest();
		System.enqueueJob(
			new InboundInstallmentCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT candidateInstallment__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.isNull(inbound.candidateInstallment__c);
	}

	@IsTest
	static void excludesConciliatedInstallments() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = new InsurancePolicy(
			Name = 'POL-IC-008',
			PolicyName = 'Test Policy',
			NameInsuredId = accountId,
			Status = 'Inicial',
			PremiumAmount = 1000,
			PremiumFrequency = 'Mensual',
			PaymentDueDate = Date.today()
		);
		insert policy;
		deleteAutoGeneratedPlans(policy.Id);
		PaymentPlan__c plan = createActivePlan(policy.Id);
		Date dueDate = Date.today().addDays(30);
		createInstallment(plan.Id, 1, dueDate, 400, 'Conciliado');

		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-IC-008',
			policy.Id,
			null,
			dueDate,
			400
		);

		Test.startTest();
		System.enqueueJob(
			new InboundInstallmentCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT candidateInstallment__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.isNull(inbound.candidateInstallment__c);
	}

	@IsTest
	static void excludesInstallmentsOfCancelledPlans() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = new InsurancePolicy(
			Name = 'POL-IC-009',
			PolicyName = 'Test Policy',
			NameInsuredId = accountId,
			Status = 'Inicial',
			PremiumAmount = 1000,
			PremiumFrequency = 'Mensual',
			PaymentDueDate = Date.today()
		);
		insert policy;
		deleteAutoGeneratedPlans(policy.Id);
		PaymentPlan__c plan = new PaymentPlan__c(
			insurancePolicy__c = policy.Id,
			planStatus__c = 'Cancelado',
			premiumFrequency__c = 'Mensual',
			expectedTotalAmount__c = 1200,
			installmentCount__c = 3,
			firstDueDate__c = Date.today()
		);
		insert plan;
		Date dueDate = Date.today().addDays(30);
		createInstallment(plan.Id, 1, dueDate, 400, 'Pendiente');

		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-IC-009',
			policy.Id,
			null,
			dueDate,
			400
		);

		Test.startTest();
		System.enqueueJob(
			new InboundInstallmentCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT candidateInstallment__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.isNull(inbound.candidateInstallment__c);
	}

	@IsTest
	static void skipsRecordsThatAreNotInNormalizedStatus() {
		InboundInsurancePayment__c inbound = new InboundInsurancePayment__c(
			externalPaymentId__c = 'EXT-IC-010',
			inboundStatus__c = 'Parseado',
			sourceAmount__c = 500,
			sourcePaymentDate__c = Date.today(),
			sourcePolicyNumber__c = 'POL-SKIP',
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now()
		);
		insert inbound;

		Test.startTest();
		System.enqueueJob(
			new InboundInstallmentCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT candidateInstallment__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.isNull(inbound.candidateInstallment__c);
	}

	private static InboundInsurancePayment__c createNormalizedInbound(
		String externalId,
		Id candidatePolicyId,
		String installmentNumber,
		Date dueDate,
		Decimal amount
	) {
		InboundInsurancePayment__c rec = new InboundInsurancePayment__c(
			externalPaymentId__c = externalId,
			inboundStatus__c = 'Normalizado',
			sourceAmount__c = amount,
			sourcePaymentDate__c = Date.today(),
			sourcePolicyNumber__c = 'POL-TEST',
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now(),
			parsedAt__c = System.now(),
			candidatePolicy__c = candidatePolicyId,
			sourceInstallmentNumber__c = installmentNumber,
			sourceDueDate__c = dueDate
		);
		insert rec;
		return rec;
	}

	private static PaymentPlan__c createActivePlan(Id policyId) {
		PaymentPlan__c plan = new PaymentPlan__c(
			insurancePolicy__c = policyId,
			planStatus__c = 'Activo',
			premiumFrequency__c = 'Mensual',
			expectedTotalAmount__c = 1200,
			firstDueDate__c = Date.today()
		);
		insert plan;
		return plan;
	}

	private static PaymentPlanInstallment__c createInstallment(
		Id planId,
		Integer seq,
		Date dueDate,
		Decimal amount,
		String status
	) {
		PaymentPlanInstallment__c inst = new PaymentPlanInstallment__c(
			paymentPlan__c = planId,
			sequenceNumber__c = seq,
			dueDate__c = dueDate,
			expectedAmount__c = amount,
			installmentStatus__c = status
		);
		insert inst;
		return inst;
	}

	private static void deleteAutoGeneratedPlans(Id policyId) {
		List<PaymentPlan__c> autoPlans = [
			SELECT Id
			FROM PaymentPlan__c
			WHERE insurancePolicy__c = :policyId
		];
		if (autoPlans.isEmpty()) {
			return;
		}
		Set<Id> planIds = new Map<Id, PaymentPlan__c>(autoPlans).keySet();
		delete [
			SELECT Id
			FROM PaymentPlanInstallment__c
			WHERE paymentPlan__c IN :planIds
		];
		delete autoPlans;
	}
}
