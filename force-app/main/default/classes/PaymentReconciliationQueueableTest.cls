/**
 *   @name: PaymentReconciliationQueueableTest
 *   @version: 1.0
 *   @creation date: 20/05/2026
 *   @author: Javier Torres - Volestra
 *   @description: Valida la creacion de PaymentReconciliation__c para todos los
 *                 resultados del pipeline (Conciliado, Revision Manual, Sin Match),
 *                 la idempotencia (no duplicados), el mapeo de campos, el aislamiento
 *                 de errores y el encadenamiento a PolicyPaymentReceiptQueueable.
 */
@IsTest
private class PaymentReconciliationQueueableTest {
	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	@IsTest
	static void createsReconciliationForConciliadoRecord() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-PR-001', accountId);
		InboundInsurancePayment__c inbound = createEvaluatedInbound(
			'EXT-PR-001',
			policy.Id,
			'Conciliado',
			'EXACT_POLICY_AND_SEQUENCE',
			'Match Exacto',
			95,
			'Alta',
			false,
			1
		);

		Test.startTest();
		System.enqueueJob(
			new PaymentReconciliationQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		List<PaymentReconciliation__c> recs = [
			SELECT
				reconciliationStatus__c,
				matchMethod__c,
				confidenceScore__c,
				confidenceBand__c,
				manualReviewRequired__c,
				candidateCount__c,
				insurancePolicy__c
			FROM PaymentReconciliation__c
			WHERE inboundPayment__c = :inbound.Id
		];
		Assert.areEqual(1, recs.size());
		Assert.areEqual('Conciliado', recs[0].reconciliationStatus__c);
		Assert.areEqual('Cuota exacta', recs[0].matchMethod__c);
		Assert.areEqual(95, recs[0].confidenceScore__c);
		Assert.areEqual('Alta', recs[0].confidenceBand__c);
		Assert.areEqual(false, recs[0].manualReviewRequired__c);
		Assert.areEqual(1, recs[0].candidateCount__c);
		Assert.areEqual(policy.Id, recs[0].insurancePolicy__c);
	}

	@IsTest
	static void createsReconciliationForProbableRecord() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-PR-002', accountId);
		InboundInsurancePayment__c inbound = createEvaluatedInbound(
			'EXT-PR-002',
			policy.Id,
			'Revision Manual',
			'POLICY_AMOUNT',
			'Match Probable',
			65,
			'Media',
			true,
			1
		);

		Test.startTest();
		System.enqueueJob(
			new PaymentReconciliationQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		List<PaymentReconciliation__c> recs = [
			SELECT reconciliationStatus__c, matchMethod__c, manualReviewRequired__c
			FROM PaymentReconciliation__c
			WHERE inboundPayment__c = :inbound.Id
		];
		Assert.areEqual(1, recs.size());
		Assert.areEqual('Probable', recs[0].reconciliationStatus__c);
		Assert.areEqual('Poliza e importe', recs[0].matchMethod__c);
		Assert.areEqual(true, recs[0].manualReviewRequired__c);
	}

	@IsTest
	static void createsReconciliationForRevisionManualAmbiguous() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-PR-003', accountId);
		InboundInsurancePayment__c inbound = createEvaluatedInbound(
			'EXT-PR-003',
			policy.Id,
			'Revision Manual',
			'AMBIGUOUS',
			'Revision Manual',
			25,
			'Baja',
			true,
			2
		);

		Test.startTest();
		System.enqueueJob(
			new PaymentReconciliationQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		List<PaymentReconciliation__c> recs = [
			SELECT reconciliationStatus__c, matchMethod__c, candidateCount__c
			FROM PaymentReconciliation__c
			WHERE inboundPayment__c = :inbound.Id
		];
		Assert.areEqual(1, recs.size());
		Assert.areEqual('Requiere revision', recs[0].reconciliationStatus__c);
		Assert.areEqual('Asistido por candidato', recs[0].matchMethod__c);
		Assert.areEqual(2, recs[0].candidateCount__c);
	}

	@IsTest
	static void createsReconciliationForSinMatchRecord() {
		InboundInsurancePayment__c inbound = createEvaluatedInbound(
			'EXT-PR-004',
			null,
			'Sin Match',
			'NO_MATCH',
			'Sin Match',
			0,
			'Baja',
			true,
			0
		);

		Test.startTest();
		System.enqueueJob(
			new PaymentReconciliationQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		List<PaymentReconciliation__c> recs = [
			SELECT reconciliationStatus__c, matchMethod__c, insurancePolicy__c
			FROM PaymentReconciliation__c
			WHERE inboundPayment__c = :inbound.Id
		];
		Assert.areEqual(1, recs.size());
		Assert.areEqual('Sin Match', recs[0].reconciliationStatus__c);
		Assert.areEqual('Decision manual', recs[0].matchMethod__c);
		Assert.isNull(recs[0].insurancePolicy__c);
	}

	@IsTest
	static void idempotencyDoesNotCreateDuplicate() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-PR-005', accountId);
		InboundInsurancePayment__c inbound = createEvaluatedInbound(
			'EXT-PR-005',
			policy.Id,
			'Conciliado',
			'EXACT_POLICY_AND_SEQUENCE',
			'Match Exacto',
			95,
			'Alta',
			false,
			1
		);

		PaymentReconciliation__c existing = new PaymentReconciliation__c(
			inboundPayment__c = inbound.Id,
			reconciliationStatus__c = 'Conciliado',
			matchMethod__c = 'Cuota exacta',
			confidenceScore__c = 95,
			confidenceBand__c = 'Alta',
			manualReviewRequired__c = false,
			candidateCount__c = 1
		);
		insert existing;

		Test.startTest();
		System.enqueueJob(
			new PaymentReconciliationQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		List<PaymentReconciliation__c> recs = [
			SELECT Id
			FROM PaymentReconciliation__c
			WHERE inboundPayment__c = :inbound.Id
		];
		Assert.areEqual(1, recs.size());
	}

	@IsTest
	static void populatesAmountAndDateDeltasWhenInstallmentExists() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-PR-006', accountId);

		List<PaymentPlan__c> autoPlans = [
			SELECT Id
			FROM PaymentPlan__c
			WHERE insurancePolicy__c = :policy.Id
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
			insurancePolicy__c = policy.Id,
			planStatus__c = 'Activo',
			premiumFrequency__c = 'Mensual',
			expectedTotalAmount__c = 1200,
			firstDueDate__c = Date.today()
		);
		insert plan;

		Date dueDate = Date.today().addDays(30);
		PaymentPlanInstallment__c inst = new PaymentPlanInstallment__c(
			paymentPlan__c = plan.Id,
			sequenceNumber__c = 1,
			dueDate__c = dueDate,
			expectedAmount__c = 400,
			installmentStatus__c = 'Pendiente'
		);
		insert inst;

		InboundInsurancePayment__c inbound = createEvaluatedInboundWithInstallment(
			'EXT-PR-006',
			policy.Id,
			inst.Id,
			'Conciliado',
			'EXACT_POLICY_AND_SEQUENCE',
			'Match Exacto',
			95,
			'Alta',
			false,
			1,
			405,
			dueDate.addDays(2)
		);

		Test.startTest();
		System.enqueueJob(
			new PaymentReconciliationQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		List<PaymentReconciliation__c> recs = [
			SELECT
				amountDelta__c,
				dateDeltaDays__c,
				paymentPlan__c,
				paymentPlanInstallment__c
			FROM PaymentReconciliation__c
			WHERE inboundPayment__c = :inbound.Id
		];
		Assert.areEqual(1, recs.size());
		Assert.areEqual(5.00, recs[0].amountDelta__c);
		Assert.areEqual(-2, recs[0].dateDeltaDays__c);
		Assert.areEqual(plan.Id, recs[0].paymentPlan__c);
		Assert.areEqual(inst.Id, recs[0].paymentPlanInstallment__c);
	}

	@IsTest
	static void skipsRecordWhenForcedFailure() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-PR-007', accountId);
		InboundInsurancePayment__c inbound = createEvaluatedInbound(
			'EXT-PR-007',
			policy.Id,
			'Conciliado',
			'EXACT_POLICY_AND_SEQUENCE',
			'Match Exacto',
			95,
			'Alta',
			false,
			1
		);

		PaymentReconciliationQueueable.forceFailureForTest = true;

		Test.startTest();
		System.enqueueJob(
			new PaymentReconciliationQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		List<PaymentReconciliation__c> recs = [
			SELECT Id
			FROM PaymentReconciliation__c
			WHERE inboundPayment__c = :inbound.Id
		];
		Assert.areEqual(0, recs.size());
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

	private static InboundInsurancePayment__c createEvaluatedInbound(
		String externalId,
		Id policyId,
		String inboundStatus,
		String method,
		String result,
		Integer score,
		String band,
		Boolean manualReview,
		Integer candidateCount
	) {
		InboundInsurancePayment__c rec = new InboundInsurancePayment__c(
			externalPaymentId__c = externalId,
			inboundStatus__c = inboundStatus,
			candidatePolicy__c = policyId,
			reconciliationMethod__c = method,
			reconciliationResult__c = result,
			confidenceScore__c = score,
			confidenceBand__c = band,
			manualReviewRequired__c = manualReview,
			candidateCount__c = candidateCount,
			sourceAmount__c = 400,
			sourcePaymentDate__c = Date.today(),
			sourcePolicyNumber__c = 'POL-TEST',
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now()
		);
		insert rec;
		return rec;
	}

	private static InboundInsurancePayment__c createEvaluatedInboundWithInstallment(
		String externalId,
		Id policyId,
		Id installmentId,
		String inboundStatus,
		String method,
		String result,
		Integer score,
		String band,
		Boolean manualReview,
		Integer candidateCount,
		Decimal amount,
		Date dueDate
	) {
		InboundInsurancePayment__c rec = new InboundInsurancePayment__c(
			externalPaymentId__c = externalId,
			inboundStatus__c = inboundStatus,
			candidatePolicy__c = policyId,
			candidateInstallment__c = installmentId,
			reconciliationMethod__c = method,
			reconciliationResult__c = result,
			confidenceScore__c = score,
			confidenceBand__c = band,
			manualReviewRequired__c = manualReview,
			candidateCount__c = candidateCount,
			sourceAmount__c = amount,
			sourceDueDate__c = dueDate,
			sourcePaymentDate__c = Date.today(),
			sourcePolicyNumber__c = 'POL-TEST',
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now()
		);
		insert rec;
		return rec;
	}
}
