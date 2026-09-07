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
			Status = 'Inicial',
			PremiumAmount = 1000,
			PremiumFrequency = 'Mensual',
			PaymentDueDate = Date.today()
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
				Status = 'Vigente',
				PremiumAmount = 1000,
				PremiumFrequency = 'Mensual',
				PaymentDueDate = Date.today()
			),
			new InsurancePolicy(
				Name = 'POL-AMBIGUA-001',
				PolicyName = 'Test B',
				NameInsuredId = accountId,
				Status = 'Inicial',
				PremiumAmount = 1000,
				PremiumFrequency = 'Mensual',
				PaymentDueDate = Date.today()
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
	static void findsCancelledPolicy() {
		// Antes se ignoraba por estar cancelada y el pago moria en Sin Match, aunque
		// la poliza existiera. La aseguradora puede cobrar sobre una poliza cancelada.
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy cancelled = new InsurancePolicy(
			Name = 'POL-CANCELADA-001',
			PolicyName = 'Cancelled',
			NameInsuredId = accountId,
			Status = 'Cancelado'
		);
		insert cancelled;

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
			SELECT candidatePolicy__c, policyMatchReason__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual(
			cancelled.Id,
			inbound.candidatePolicy__c,
			'Una poliza cancelada sigue siendo esa poliza.'
		);
		Assert.areEqual('UNICO_GANADOR', inbound.policyMatchReason__c);
	}

	@IsTest
	static void findsExpiredPolicy() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy expired = new InsurancePolicy(
			Name = 'POL-VENCIDA-001',
			PolicyName = 'Expired',
			NameInsuredId = accountId,
			Status = 'Vencido'
		);
		insert expired;

		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-PC-010',
			'POL-VENCIDA-001',
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
		Assert.areEqual(
			expired.Id,
			inbound.candidatePolicy__c,
			'Un pago tardio sobre una poliza vencida es un cobro real.'
		);
	}

	@IsTest
	static void picksTheTermThatContainsTheReceiptDate() {
		// Renovaciones: cada vigencia es una poliza propia con el mismo numero. Gana la que
		// contiene la fecha del recibo, no la que tenga mejor estado.
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy firstTerm = new InsurancePolicy(
			Name = 'POL-RENOV-001',
			PolicyName = 'Vigencia 2025',
			NameInsuredId = accountId,
			Status = 'Vencido',
			EffectiveDate = Datetime.newInstance(2025, 1, 1, 0, 0, 0),
			ExpirationDate = Datetime.newInstance(2025, 12, 31, 0, 0, 0)
		);
		InsurancePolicy secondTerm = new InsurancePolicy(
			Name = 'POL-RENOV-001',
			PolicyName = 'Vigencia 2026',
			NameInsuredId = accountId,
			Status = 'Vigente',
			PremiumAmount = 1000,
			PremiumFrequency = 'Mensual',
			PaymentDueDate = Date.today(),
			EffectiveDate = Datetime.newInstance(2026, 1, 1, 0, 0, 0),
			ExpirationDate = Datetime.newInstance(2026, 12, 31, 0, 0, 0)
		);
		insert new List<InsurancePolicy>{ firstTerm, secondTerm };

		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-PC-011',
			'POL-RENOV-001',
			null,
			Date.newInstance(2025, 6, 15)
		);

		Test.startTest();
		System.enqueueJob(
			new InboundPolicyCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT candidatePolicy__c, policyMatchReason__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual(
			firstTerm.Id,
			inbound.candidatePolicy__c,
			'El recibo vence en 2025: pertenece a la primera vigencia aunque este vencida.'
		);
		Assert.areEqual('RESUELTO_POR_VIGENCIA', inbound.policyMatchReason__c);
	}

	@IsTest
	static void leavesNullWhenDateFallsOutsideEveryTerm() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		insert new List<InsurancePolicy>{
			new InsurancePolicy(
				Name = 'POL-RENOV-002',
				PolicyName = 'Vigencia 2025',
				NameInsuredId = accountId,
				Status = 'Vencido',
				EffectiveDate = Datetime.newInstance(2025, 1, 1, 0, 0, 0),
				ExpirationDate = Datetime.newInstance(2025, 12, 31, 0, 0, 0)
			),
			new InsurancePolicy(
				Name = 'POL-RENOV-002',
				PolicyName = 'Vigencia 2026',
				NameInsuredId = accountId,
				Status = 'Vigente',
				PremiumAmount = 1000,
				PremiumFrequency = 'Mensual',
				PaymentDueDate = Date.today(),
				EffectiveDate = Datetime.newInstance(2026, 1, 1, 0, 0, 0),
				ExpirationDate = Datetime.newInstance(2026, 12, 31, 0, 0, 0)
			)
		};

		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-PC-012',
			'POL-RENOV-002',
			null,
			Date.newInstance(2030, 6, 15)
		);

		Test.startTest();
		System.enqueueJob(
			new InboundPolicyCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT candidatePolicy__c, policyMatchReason__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.isNull(
			inbound.candidatePolicy__c,
			'No se elige por descarte: atribuir el cobro al ano equivocado es peor.'
		);
		Assert.areEqual(
			'VIGENCIA_AMBIGUA',
			inbound.policyMatchReason__c,
			'Tiene que distinguirse de un Sin Match: la poliza si existe.'
		);
	}

	@IsTest
	static void marksMissingPolicyAsNoPolicy() {
		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-PC-013',
			'POL-NO-EXISTE-999',
			null,
			null
		);

		Test.startTest();
		System.enqueueJob(
			new InboundPolicyCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT candidatePolicy__c, policyMatchReason__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.isNull(inbound.candidatePolicy__c);
		Assert.areEqual(
			'SIN_POLIZA',
			inbound.policyMatchReason__c,
			'Sin Match recupera su significado: el numero no existe.'
		);
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
			Status = 'Vigente',
			PremiumAmount = 1000,
			PremiumFrequency = 'Mensual',
			PaymentDueDate = Date.today()
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
