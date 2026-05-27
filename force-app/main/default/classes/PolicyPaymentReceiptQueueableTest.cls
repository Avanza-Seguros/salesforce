/**
 *   @name: PolicyPaymentReceiptQueueableTest
 *   @version: 1.0
 *   @creation date: 20/05/2026
 *   @author: Javier Torres - Volestra
 *   @description: Valida la creacion de PolicyPaymentReceipt__c para conciliaciones
 *                 aprobadas, la idempotencia (no duplicados por conciliacion), el
 *                 poblado de campos minimos, el vinculo de retorno en
 *                 PaymentReconciliation__c.resultingReceipt__c y el aislamiento de
 *                 errores por registro.
 */
@IsTest
private class PolicyPaymentReceiptQueueableTest {
	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	@IsTest
	static void createsReceiptAndLinksToReconciliation() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-REC-001', accountId);
		InboundInsurancePayment__c inbound = createInbound(
			'EXT-REC-001',
			policy.Id,
			500
		);
		PaymentReconciliation__c recon = createReconciliation(
			inbound.Id,
			policy.Id
		);

		Test.startTest();
		System.enqueueJob(
			new PolicyPaymentReceiptQueueable(new Set<Id>{ recon.Id })
		);
		Test.stopTest();

		List<PolicyPaymentReceipt__c> receipts = [
			SELECT
				insurancePolicy__c,
				sourceInboundPayment__c,
				paymentReconciliation__c,
				receiptAmount__c,
				receiptDate__c,
				receiptStatus__c
			FROM PolicyPaymentReceipt__c
			WHERE paymentReconciliation__c = :recon.Id
		];
		Assert.areEqual(1, receipts.size());
		Assert.areEqual(policy.Id, receipts[0].insurancePolicy__c);
		Assert.areEqual(inbound.Id, receipts[0].sourceInboundPayment__c);
		Assert.areEqual(recon.Id, receipts[0].paymentReconciliation__c);
		Assert.areEqual(500, receipts[0].receiptAmount__c);
		Assert.areEqual('Reconocido', receipts[0].receiptStatus__c);
		Assert.isNotNull(receipts[0].receiptDate__c);

		recon = [
			SELECT resultingReceipt__c
			FROM PaymentReconciliation__c
			WHERE Id = :recon.Id
		];
		Assert.areEqual(receipts[0].Id, recon.resultingReceipt__c);
	}

	@IsTest
	static void idempotencySkipsWhenReceiptAlreadyExists() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-REC-002', accountId);
		InboundInsurancePayment__c inbound = createInbound(
			'EXT-REC-002',
			policy.Id,
			300
		);
		PaymentReconciliation__c recon = createReconciliation(
			inbound.Id,
			policy.Id
		);

		PolicyPaymentReceipt__c existingReceipt = new PolicyPaymentReceipt__c(
			insurancePolicy__c = policy.Id,
			sourceInboundPayment__c = inbound.Id,
			paymentReconciliation__c = recon.Id,
			receiptAmount__c = 300,
			receiptDate__c = Date.today(),
			receiptStatus__c = 'Reconocido'
		);
		insert existingReceipt;

		recon.resultingReceipt__c = existingReceipt.Id;
		update recon;

		Test.startTest();
		System.enqueueJob(
			new PolicyPaymentReceiptQueueable(new Set<Id>{ recon.Id })
		);
		Test.stopTest();

		List<PolicyPaymentReceipt__c> receipts = [
			SELECT Id
			FROM PolicyPaymentReceipt__c
			WHERE paymentReconciliation__c = :recon.Id
		];
		Assert.areEqual(1, receipts.size());
	}

	@IsTest
	static void populatesInstallmentAndPlanWhenPresent() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-REC-003', accountId);

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

		PaymentPlanInstallment__c inst = new PaymentPlanInstallment__c(
			paymentPlan__c = plan.Id,
			sequenceNumber__c = 1,
			dueDate__c = Date.today().addDays(30),
			expectedAmount__c = 400,
			installmentStatus__c = 'Pendiente'
		);
		insert inst;

		InboundInsurancePayment__c inbound = createInbound(
			'EXT-REC-003',
			policy.Id,
			400
		);

		PaymentReconciliation__c recon = new PaymentReconciliation__c(
			inboundPayment__c = inbound.Id,
			insurancePolicy__c = policy.Id,
			paymentPlan__c = plan.Id,
			paymentPlanInstallment__c = inst.Id,
			reconciliationStatus__c = 'Conciliado',
			matchMethod__c = 'Cuota exacta',
			confidenceScore__c = 95,
			candidateCount__c = 1
		);
		insert recon;

		Test.startTest();
		System.enqueueJob(
			new PolicyPaymentReceiptQueueable(new Set<Id>{ recon.Id })
		);
		Test.stopTest();

		List<PolicyPaymentReceipt__c> receipts = [
			SELECT paymentPlan__c, paymentPlanInstallment__c
			FROM PolicyPaymentReceipt__c
			WHERE paymentReconciliation__c = :recon.Id
		];
		Assert.areEqual(1, receipts.size());
		Assert.areEqual(plan.Id, receipts[0].paymentPlan__c);
		Assert.areEqual(inst.Id, receipts[0].paymentPlanInstallment__c);
	}

	@IsTest
	static void skipsRecordWhenForcedFailure() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-REC-004', accountId);
		InboundInsurancePayment__c inbound = createInbound(
			'EXT-REC-004',
			policy.Id,
			200
		);
		PaymentReconciliation__c recon = createReconciliation(
			inbound.Id,
			policy.Id
		);

		PolicyPaymentReceiptQueueable.forceFailureForTest = true;

		Test.startTest();
		System.enqueueJob(
			new PolicyPaymentReceiptQueueable(new Set<Id>{ recon.Id })
		);
		Test.stopTest();

		List<PolicyPaymentReceipt__c> receipts = [
			SELECT Id
			FROM PolicyPaymentReceipt__c
			WHERE paymentReconciliation__c = :recon.Id
		];
		Assert.areEqual(0, receipts.size());
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

	private static InboundInsurancePayment__c createInbound(
		String externalId,
		Id policyId,
		Decimal amount
	) {
		InboundInsurancePayment__c rec = new InboundInsurancePayment__c(
			externalPaymentId__c = externalId,
			inboundStatus__c = 'Conciliado',
			candidatePolicy__c = policyId,
			sourceAmount__c = amount,
			sourcePaymentDate__c = Date.today(),
			sourcePolicyNumber__c = 'POL-TEST',
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now()
		);
		insert rec;
		return rec;
	}

	private static PaymentReconciliation__c createReconciliation(
		Id inboundId,
		Id policyId
	) {
		PaymentReconciliation__c recon = new PaymentReconciliation__c(
			inboundPayment__c = inboundId,
			insurancePolicy__c = policyId,
			reconciliationStatus__c = 'Conciliado',
			matchMethod__c = 'Cuota exacta',
			confidenceScore__c = 95,
			candidateCount__c = 1
		);
		insert recon;
		return recon;
	}
}
