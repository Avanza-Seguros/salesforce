/**
 *   @name: InboundReconciliationRulesQueueableTest
 *   @version: 1.0
 *   @creation date: 19/05/2026
 *   @author: Javier Torres - Volestra
 *   @description: Valida el motor de reglas MVP de conciliacion automatica.
 *                 Cubre las seis reglas (NO_MATCH, AMBIGUOUS, EXACT_POLICY_AND_SEQUENCE,
 *                 POLICY_DATE_AMOUNT, POLICY_AMOUNT, POLICY_ONLY), trazabilidad
 *                 obligatoria de reconciledAt__c y aislamiento de errores por registro.
 */
@IsTest
private class InboundReconciliationRulesQueueableTest {
	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	@IsTest
	static void classifiesNoMatchWhenNoCandidatePolicy() {
		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-RR-001',
			null,
			null,
			null,
			null,
			Date.today(),
			500
		);

		Test.startTest();
		System.enqueueJob(
			new InboundReconciliationRulesQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = queryResult(inbound.Id);
		Assert.areEqual('NO_MATCH', inbound.reconciliationMethod__c);
		Assert.areEqual('Sin Match', inbound.reconciliationResult__c);
		Assert.isNotNull(inbound.reconciledAt__c);
	}

	@IsTest
	static void classifiesAmbiguousWhenInstallmentTie() {
		Id policyId = createPolicy('POL-RR-002');
		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-RR-002',
			policyId,
			null,
			'EMPATE',
			null,
			Date.today(),
			500
		);

		Test.startTest();
		System.enqueueJob(
			new InboundReconciliationRulesQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = queryResult(inbound.Id);
		Assert.areEqual('AMBIGUOUS', inbound.reconciliationMethod__c);
		Assert.areEqual('Revision Manual', inbound.reconciliationResult__c);
	}

	@IsTest
	static void classifiesExactPolicyAndSequenceWhenSequenceMatches() {
		Id policyId = createPolicy('POL-RR-003');
		PaymentPlanInstallment__c inst = createInstallmentForPolicy(
			policyId,
			1,
			Date.today().addDays(30),
			800
		);
		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-RR-003',
			policyId,
			inst.Id,
			'UNICO_GANADOR',
			'1',
			Date.today().addDays(10),
			999
		);

		Test.startTest();
		System.enqueueJob(
			new InboundReconciliationRulesQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = queryResult(inbound.Id);
		Assert.areEqual(
			'EXACT_POLICY_AND_SEQUENCE',
			inbound.reconciliationMethod__c
		);
		Assert.areEqual('Match Exacto', inbound.reconciliationResult__c);
	}

	@IsTest
	static void classifiesPolicyDateAmountWhenDateAndAmountMatch() {
		Id policyId = createPolicy('POL-RR-004');
		Date dueDate = Date.today().addDays(30);
		PaymentPlanInstallment__c inst = createInstallmentForPolicy(
			policyId,
			2,
			dueDate,
			1200
		);
		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-RR-004',
			policyId,
			inst.Id,
			'UNICO_GANADOR',
			null,
			dueDate,
			1200
		);

		Test.startTest();
		System.enqueueJob(
			new InboundReconciliationRulesQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = queryResult(inbound.Id);
		Assert.areEqual('POLICY_DATE_AMOUNT', inbound.reconciliationMethod__c);
		Assert.areEqual('Match Exacto', inbound.reconciliationResult__c);
	}

	@IsTest
	static void classifiesPolicyAmountWhenOnlyAmountMatches() {
		Id policyId = createPolicy('POL-RR-005');
		Date dueDate = Date.today().addDays(30);
		PaymentPlanInstallment__c inst = createInstallmentForPolicy(
			policyId,
			1,
			dueDate,
			750
		);
		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-RR-005',
			policyId,
			inst.Id,
			'UNICO_GANADOR',
			null,
			Date.today().addDays(60),
			750
		);

		Test.startTest();
		System.enqueueJob(
			new InboundReconciliationRulesQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = queryResult(inbound.Id);
		Assert.areEqual('POLICY_AMOUNT', inbound.reconciliationMethod__c);
		Assert.areEqual('Match Probable', inbound.reconciliationResult__c);
	}

	@IsTest
	static void classifiesPolicyOnlyWhenScoreBajo() {
		Id policyId = createPolicy('POL-RR-006');
		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-RR-006',
			policyId,
			null,
			'SCORE_BAJO',
			null,
			Date.today(),
			500
		);

		Test.startTest();
		System.enqueueJob(
			new InboundReconciliationRulesQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = queryResult(inbound.Id);
		Assert.areEqual('POLICY_ONLY', inbound.reconciliationMethod__c);
		Assert.areEqual('Match Probable', inbound.reconciliationResult__c);
	}

	@IsTest
	static void classifiesPolicyOnlyWhenSinCuotas() {
		Id policyId = createPolicy('POL-RR-007');
		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-RR-007',
			policyId,
			null,
			'SIN_CUOTAS',
			null,
			Date.today(),
			500
		);

		Test.startTest();
		System.enqueueJob(
			new InboundReconciliationRulesQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = queryResult(inbound.Id);
		Assert.areEqual('POLICY_ONLY', inbound.reconciliationMethod__c);
		Assert.areEqual('Match Probable', inbound.reconciliationResult__c);
	}

	@IsTest
	static void populatesReconciledAtOnAllRecords() {
		Id policyId = createPolicy('POL-RR-008');
		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-RR-008',
			policyId,
			null,
			'SIN_CUOTAS',
			null,
			Date.today(),
			500
		);

		Test.startTest();
		System.enqueueJob(
			new InboundReconciliationRulesQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = queryResult(inbound.Id);
		Assert.isNotNull(inbound.reconciledAt__c);
		Assert.isNotNull(inbound.reconciliationMethod__c);
		Assert.isNotNull(inbound.reconciliationResult__c);
	}

	@IsTest
	static void classifiesErrorAndManualReviewOnException() {
		InboundReconciliationRulesQueueable.forceFailureForTest = true;
		Id policyId = createPolicy('POL-RR-009');
		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-RR-009',
			policyId,
			null,
			'SIN_CUOTAS',
			null,
			Date.today(),
			500
		);

		Test.startTest();
		System.enqueueJob(
			new InboundReconciliationRulesQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = queryResult(inbound.Id);
		Assert.areEqual('ERROR', inbound.reconciliationMethod__c);
		Assert.areEqual('Revision Manual', inbound.reconciliationResult__c);
		Assert.isNotNull(inbound.reconciledAt__c);
	}

	@IsTest
	static void skipsRecordsNotInNormalizedStatus() {
		InboundInsurancePayment__c inbound = new InboundInsurancePayment__c(
			externalPaymentId__c = 'EXT-RR-010',
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
			new InboundReconciliationRulesQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = queryResult(inbound.Id);
		Assert.isNull(inbound.reconciliationMethod__c);
		Assert.isNull(inbound.reconciliationResult__c);
	}

	private static Id createPolicy(String policyName) {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = new InsurancePolicy(
			Name = policyName,
			PolicyName = policyName,
			NameInsuredId = accountId,
			Status = 'Inicial',
			PremiumAmount = 1000,
			PremiumFrequency = 'Mensual',
			PaymentDueDate = Date.today()
		);
		insert policy;
		return policy.Id;
	}

	private static PaymentPlanInstallment__c createInstallmentForPolicy(
		Id policyId,
		Integer seq,
		Date dueDate,
		Decimal amount
	) {
		PaymentPlan__c plan = new PaymentPlan__c(
			insurancePolicy__c = policyId,
			planStatus__c = 'Activo',
			premiumFrequency__c = 'Mensual',
			expectedTotalAmount__c = amount,
			installmentCount__c = 1,
			firstDueDate__c = dueDate
		);
		insert plan;
		PaymentPlanInstallment__c inst = new PaymentPlanInstallment__c(
			paymentPlan__c = plan.Id,
			sequenceNumber__c = seq,
			dueDate__c = dueDate,
			expectedAmount__c = amount,
			installmentStatus__c = 'Pendiente'
		);
		insert inst;
		return inst;
	}

	private static InboundInsurancePayment__c createNormalizedInbound(
		String externalId,
		Id candidatePolicyId,
		Id candidateInstallmentId,
		String installmentMatchReason,
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
			candidateInstallment__c = candidateInstallmentId,
			installmentMatchReason__c = installmentMatchReason,
			sourceInstallmentNumber__c = installmentNumber,
			sourceDueDate__c = dueDate
		);
		insert rec;
		return rec;
	}

	private static InboundInsurancePayment__c queryResult(Id recordId) {
		return [
			SELECT reconciliationMethod__c, reconciliationResult__c, reconciledAt__c
			FROM InboundInsurancePayment__c
			WHERE Id = :recordId
		];
	}
}
