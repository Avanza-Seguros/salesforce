/**
 *   @name: InboundPolicyCandidateQueueableTest
 *   @version: 1.0
 *   @creation date: 07/05/2026
 *   @author: Javier Torres - Volestra
 *   @description: Valida la identificacion de poliza candidata para pagos inbound
 *                 normalizados, incluyendo match unico activo, sin match, ambiguedad
 *                 por multiples polizas activas, exclusion de polizas canceladas
 *                 y manejo de errores.
 */
@IsTest
private class InboundPolicyCandidateQueueableTest {
	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	@IsTest
	static void assignsUniquePolicyMatchByPolicyNumber() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = new InsurancePolicy(
			Name = 'POL-CANDIDATE-001',
			PolicyName = 'Test Policy',
			NameInsuredId = accountId,
			Status = 'Inicial'
		);
		insert policy;

		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-PC-001',
			'POL-CANDIDATE-001',
			null,
			null
		);

		Test.startTest();
		System.enqueueJob(
			new InboundPolicyCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT candidatePolicy__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual(policy.Id, inbound.candidatePolicy__c);
	}

	@IsTest
	static void leavesNullWhenNoPolicyFound() {
		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-PC-002',
			'POL-INEXISTENTE-999',
			null,
			null
		);

		Test.startTest();
		System.enqueueJob(
			new InboundPolicyCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT candidatePolicy__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.isNull(inbound.candidatePolicy__c);
	}

	@IsTest
	static void leavesNullWhenMatchIsAmbiguous() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		insert new List<InsurancePolicy>{
			new InsurancePolicy(
				Name = 'POL-AMBIGUA-001',
				PolicyName = 'Test A',
				NameInsuredId = accountId,
				Status = 'Vigente'
			),
			new InsurancePolicy(
				Name = 'POL-AMBIGUA-001',
				PolicyName = 'Test B',
				NameInsuredId = accountId,
				Status = 'Inicial'
			)
		};

		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-PC-003',
			'POL-AMBIGUA-001',
			null,
			null
		);

		Test.startTest();
		System.enqueueJob(
			new InboundPolicyCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT candidatePolicy__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.isNull(inbound.candidatePolicy__c);
	}

	@IsTest
	static void ignoresCancelledPolicies() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		insert new InsurancePolicy(
			Name = 'POL-CANCELADA-001',
			PolicyName = 'Cancelled',
			NameInsuredId = accountId,
			Status = 'Cancelado'
		);

		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-PC-004',
			'POL-CANCELADA-001',
			null,
			null
		);

		Test.startTest();
		System.enqueueJob(
			new InboundPolicyCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT candidatePolicy__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.isNull(inbound.candidatePolicy__c);
	}

	@IsTest
	static void assignsActiveWhenCancelledAndActiveCoexist() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy activePolicy = new InsurancePolicy(
			Name = 'POL-MIXTA-001',
			PolicyName = 'Active',
			NameInsuredId = accountId,
			Status = 'Vigente'
		);
		insert activePolicy;
		insert new InsurancePolicy(
			Name = 'POL-MIXTA-001',
			PolicyName = 'Cancelled',
			NameInsuredId = accountId,
			Status = 'Cancelado'
		);

		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-PC-005',
			'POL-MIXTA-001',
			null,
			null
		);

		Test.startTest();
		System.enqueueJob(
			new InboundPolicyCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT candidatePolicy__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual(activePolicy.Id, inbound.candidatePolicy__c);
	}

	@IsTest
	static void leavesNullWhenNoPolicyNumber() {
		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-PC-006',
			null,
			null,
			null
		);

		Test.startTest();
		System.enqueueJob(
			new InboundPolicyCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT candidatePolicy__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.isNull(inbound.candidatePolicy__c);
	}

	@IsTest
	static void skipsRecordsThatAreNotInNormalizedStatus() {
		InboundInsurancePayment__c inbound = new InboundInsurancePayment__c(
			externalPaymentId__c = 'EXT-PC-008',
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
			new InboundPolicyCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT candidatePolicy__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.isNull(inbound.candidatePolicy__c);
	}

	@IsTest
	static void setsNullCandidatesOnException() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = new InsurancePolicy(
			Name = 'POL-EXCEPTION-001',
			PolicyName = 'Test',
			NameInsuredId = accountId,
			Status = 'Vigente'
		);
		insert policy;

		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-PC-009',
			'POL-EXCEPTION-001',
			null,
			null
		);

		InboundPolicyCandidateQueueable.forceFailureForTest = true;

		Test.startTest();
		System.enqueueJob(
			new InboundPolicyCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT inboundStatus__c, candidatePolicy__c, candidateInstallment__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual('Normalizado', inbound.inboundStatus__c);
		Assert.isNull(inbound.candidatePolicy__c);
		Assert.isNull(inbound.candidateInstallment__c);
	}

	private static InboundInsurancePayment__c createNormalizedInbound(
		String externalId,
		String policyNumber,
		String installmentNumber,
		Date dueDate
	) {
		InboundInsurancePayment__c rec = new InboundInsurancePayment__c(
			externalPaymentId__c = externalId,
			inboundStatus__c = 'Normalizado',
			sourceAmount__c = 500,
			sourcePaymentDate__c = Date.today(),
			sourcePolicyNumber__c = policyNumber,
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now(),
			parsedAt__c = System.now(),
			sourceInstallmentNumber__c = installmentNumber,
			sourceDueDate__c = dueDate
		);
		insert rec;
		return rec;
	}
}
