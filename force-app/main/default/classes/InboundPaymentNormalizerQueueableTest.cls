/**
 *   @name: InboundPaymentNormalizerQueueableTest
 *   @version: 1.0
 *   @creation date: 02/05/2026
 *   @author: Javier Torres - Volestra
 *   @description: Valida el matching deterministico jerarquico de cuotas candidatas
 *                 sobre pagos inbound en estado Parseado, incluyendo match por
 *                 numero de cuota, por fecha de vencimiento, sin match y casos ambiguos.
 */
@IsTest
private class InboundPaymentNormalizerQueueableTest {
	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	@IsTest
	static void normalizesPaymentMatchingByInstallmentNumber() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = CollectionsTestDataFactory.createOperationalPolicy(
			accountId,
			'Mensual',
			1200,
			Date.today()
		);
		PaymentPlan__c plan = [
			SELECT Id
			FROM PaymentPlan__c
			WHERE insurancePolicy__c = :policy.Id
			LIMIT 1
		];
		PaymentPlanInstallment__c installment = [
			SELECT Id
			FROM PaymentPlanInstallment__c
			WHERE paymentPlan__c = :plan.Id AND sequenceNumber__c = 1
			LIMIT 1
		];

		InboundInsurancePayment__c inbound = createParsedInbound(
			'EXT-NORM-001',
			policy.Id,
			'1',
			null
		);

		Test.startTest();
		System.enqueueJob(
			new InboundPaymentNormalizerQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT inboundStatus__c, candidateInstallment__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual('Normalizado', inbound.inboundStatus__c);
		Assert.areEqual(installment.Id, inbound.candidateInstallment__c);
	}

	@IsTest
	static void normalizesPaymentMatchingByDueDate() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = CollectionsTestDataFactory.createOperationalPolicy(
			accountId,
			'Mensual',
			1200,
			Date.today()
		);
		PaymentPlan__c plan = CollectionsTestDataFactory.createPlan(
			policy.Id,
			'Activo',
			'Mensual',
			1200,
			Date.today(),
			3
		);
		Date targetDueDate = Date.today().addDays(30);
		PaymentPlanInstallment__c installment = createInstallment(
			plan.Id,
			1,
			targetDueDate
		);
		createInstallment(plan.Id, 2, Date.today().addDays(60));

		InboundInsurancePayment__c inbound = createParsedInbound(
			'EXT-NORM-002',
			policy.Id,
			null,
			targetDueDate
		);

		Test.startTest();
		System.enqueueJob(
			new InboundPaymentNormalizerQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT inboundStatus__c, candidateInstallment__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual('Normalizado', inbound.inboundStatus__c);
		Assert.areEqual(installment.Id, inbound.candidateInstallment__c);
	}

	@IsTest
	static void normalizesPaymentWithNullInstallmentWhenNoMatchFound() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = CollectionsTestDataFactory.createOperationalPolicy(
			accountId,
			'Mensual',
			1200,
			Date.today()
		);
		PaymentPlan__c plan = CollectionsTestDataFactory.createPlan(
			policy.Id,
			'Activo',
			'Mensual',
			1200,
			Date.today(),
			3
		);
		createInstallment(plan.Id, 1, Date.today().addDays(30));

		InboundInsurancePayment__c inbound = createParsedInbound(
			'EXT-NORM-003',
			policy.Id,
			'99',
			null
		);

		Test.startTest();
		System.enqueueJob(
			new InboundPaymentNormalizerQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT inboundStatus__c, candidateInstallment__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual('Normalizado', inbound.inboundStatus__c);
		Assert.isNull(inbound.candidateInstallment__c);
	}

	@IsTest
	static void normalizesPaymentWithNullInstallmentWhenMatchIsAmbiguous() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = CollectionsTestDataFactory.createOperationalPolicy(
			accountId,
			'Mensual',
			1200,
			Date.today()
		);
		PaymentPlan__c plan = CollectionsTestDataFactory.createPlan(
			policy.Id,
			'Activo',
			'Mensual',
			1200,
			Date.today(),
			3
		);
		Date sharedDueDate = Date.today().addDays(30);
		createInstallment(plan.Id, 1, sharedDueDate);
		createInstallment(plan.Id, 2, sharedDueDate);

		InboundInsurancePayment__c inbound = createParsedInbound(
			'EXT-NORM-004',
			policy.Id,
			null,
			sharedDueDate
		);

		Test.startTest();
		System.enqueueJob(
			new InboundPaymentNormalizerQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT inboundStatus__c, candidateInstallment__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual('Normalizado', inbound.inboundStatus__c);
		Assert.isNull(inbound.candidateInstallment__c);
	}

	@IsTest
	static void normalizesPaymentWithNullInstallmentWhenNoCandidatePolicy() {
		InboundInsurancePayment__c inbound = createParsedInbound(
			'EXT-NORM-005',
			null,
			'1',
			Date.today().addDays(30)
		);

		Test.startTest();
		System.enqueueJob(
			new InboundPaymentNormalizerQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT inboundStatus__c, candidateInstallment__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual('Normalizado', inbound.inboundStatus__c);
		Assert.isNull(inbound.candidateInstallment__c);
	}

	@IsTest
	static void skipsRecordsThatAreNotInParsedStatus() {
		InboundInsurancePayment__c inbound = new InboundInsurancePayment__c(
			externalPaymentId__c = 'EXT-NORM-006',
			inboundStatus__c = 'Rechazado',
			sourceAmount__c = 500,
			sourcePaymentDate__c = Date.today(),
			sourcePolicyNumber__c = 'POL-SKIP',
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now()
		);
		insert inbound;

		Test.startTest();
		System.enqueueJob(
			new InboundPaymentNormalizerQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT inboundStatus__c, candidateInstallment__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual('Rechazado', inbound.inboundStatus__c);
		Assert.isNull(inbound.candidateInstallment__c);
	}

	@IsTest
	static void normalizesStringFieldsWithTrimAndUppercase() {
		InboundInsurancePayment__c inbound = new InboundInsurancePayment__c(
			externalPaymentId__c = 'EXT-NORM-007',
			inboundStatus__c = 'Parseado',
			sourceAmount__c = 500,
			sourcePaymentDate__c = Date.today(),
			sourcePolicyNumber__c = '  pol-test  ',
			sourceReceiptNumber__c = '  rec-001  ',
			sourceInsuranceCarrier__c = '  carrier-xyz  ',
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now()
		);
		insert inbound;

		Test.startTest();
		System.enqueueJob(
			new InboundPaymentNormalizerQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT
				inboundStatus__c,
				sourcePolicyNumber__c,
				sourceReceiptNumber__c,
				sourceInsuranceCarrier__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual('Normalizado', inbound.inboundStatus__c);
		Assert.areEqual('POL-TEST', inbound.sourcePolicyNumber__c);
		Assert.areEqual('rec-001', inbound.sourceReceiptNumber__c);
		Assert.areEqual('CARRIER-XYZ', inbound.sourceInsuranceCarrier__c);
	}

	@IsTest
	static void normalizesAmountsToTwoDecimalPlaces() {
		InboundInsurancePayment__c inbound = new InboundInsurancePayment__c(
			externalPaymentId__c = 'EXT-NORM-008',
			inboundStatus__c = 'Parseado',
			sourceAmount__c = 1200.999,
			sourceGrossCommission__c = 120.1234,
			sourceVatCommission__c = 19.5678,
			sourcePaymentDate__c = Date.today(),
			sourcePolicyNumber__c = 'POL-TEST',
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now()
		);
		insert inbound;

		Test.startTest();
		System.enqueueJob(
			new InboundPaymentNormalizerQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT sourceAmount__c, sourceGrossCommission__c, sourceVatCommission__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual(1201.00, inbound.sourceAmount__c);
		Assert.areEqual(120.12, inbound.sourceGrossCommission__c);
		Assert.areEqual(19.57, inbound.sourceVatCommission__c);
	}

	@IsTest
	static void setsParsedAtOnSuccessfulNormalization() {
		InboundInsurancePayment__c inbound = createParsedInbound(
			'EXT-NORM-009',
			null,
			null,
			null
		);

		Test.startTest();
		System.enqueueJob(
			new InboundPaymentNormalizerQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT inboundStatus__c, parsedAt__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual('Normalizado', inbound.inboundStatus__c);
		Assert.isNotNull(inbound.parsedAt__c);
	}

	@IsTest
	static void setsRejectedStatusOnNormalizationError() {
		InboundInsurancePayment__c inbound = createParsedInbound(
			'EXT-NORM-010',
			null,
			null,
			null
		);

		InboundPaymentNormalizerQueueable.forceFailureForTest = true;

		Test.startTest();
		System.enqueueJob(
			new InboundPaymentNormalizerQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT inboundStatus__c, rejectionReason__c, parsedAt__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual('Rechazado', inbound.inboundStatus__c);
		Assert.areEqual('Error de normalizacion', inbound.rejectionReason__c);
		Assert.isNotNull(inbound.parsedAt__c);
	}

	private static PaymentPlanInstallment__c createInstallment(
		Id planId,
		Integer sequenceNumber,
		Date dueDate
	) {
		PaymentPlanInstallment__c inst = new PaymentPlanInstallment__c(
			paymentPlan__c = planId,
			sequenceNumber__c = sequenceNumber,
			dueDate__c = dueDate,
			expectedAmount__c = 400,
			installmentStatus__c = 'Pendiente'
		);
		insert inst;
		return inst;
	}

	private static InboundInsurancePayment__c createParsedInbound(
		String externalId,
		Id candidatePolicyId,
		String installmentNumber,
		Date dueDate
	) {
		InboundInsurancePayment__c rec = new InboundInsurancePayment__c(
			externalPaymentId__c = externalId,
			inboundStatus__c = 'Parseado',
			sourceAmount__c = 500,
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
}
