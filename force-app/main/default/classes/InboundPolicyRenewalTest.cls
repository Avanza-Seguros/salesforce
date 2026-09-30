/**
 *   @name: InboundPolicyRenewalTest
 *   @version: 1.0
 *   @creation date: 30/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Cuando la aseguradora comunica una vigencia nueva y posterior de un
 *                 numero conocido, se crea la vigencia encadenada a la anterior, con su plan, y lo
 *                 que no viene se hereda. Una fecha anterior no es renovacion, la misma renovacion
 *                 no se duplica y una que no se puede crear no detiene a las demas.
 */
@IsTest
private class InboundPolicyRenewalTest {
	private static final String NUMBER_A = '0971453001';
	private static final String NUMBER_B = '0971453002';
	private static Integer sequence = 0;

	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	/**
	 * @description: La renovacion crea la vigencia nueva con los datos comunicados, la
	 *               encadena a la anterior y a la original de la cadena, hereda cliente,
	 *               aseguradora y moneda, nace con su plan, aplica el estado comunicado y la
	 *               anterior solo queda marcada como renovada.
	 */
	@IsTest
	static void renewalCreatesTheChainedTerm() {
		useMappings();
		InsurancePolicy first = createPolicy(
			NUMBER_A,
			Date.newInstance(2025, 1, 15),
			Date.newInstance(2026, 1, 15)
		);
		InsurancePolicy prior = createPolicy(
			NUMBER_A,
			Date.newInstance(2026, 1, 15),
			Date.newInstance(2027, 1, 15)
		);
		update new InsurancePolicy(
			Id = prior.Id,
			OriginalPolicyId = first.Id,
			Moneda__c = 'PESOS'
		);
		InboundPolicyUpdate__c c = renewal(
			NUMBER_A,
			Date.newInstance(2027, 1, 15),
			13000,
			'Semestral'
		);

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ c.Id });
		Test.stopTest();

		InsurancePolicy created = termStarting(
			NUMBER_A,
			Date.newInstance(2027, 1, 15)
		);
		Assert.isNotNull(created, 'Se creo la vigencia nueva');
		Assert.areEqual(
			PolicyStatusService.mexicoMidnight(Date.newInstance(2028, 1, 15)),
			created.ExpirationDate
		);
		Assert.areEqual(Decimal.valueOf('13000.00'), created.PremiumAmount);
		Assert.areEqual('Semestral', created.PremiumFrequency);
		Assert.areEqual(
			Decimal.valueOf('10400.00'),
			created.Subtotal__c,
			'Los demas datos comunicados tambien'
		);
		Assert.areEqual(prior.Id, created.PriorPolicyId);
		Assert.areEqual(prior.Id, created.RenewedFromPolicyId);
		Assert.areEqual(
			first.Id,
			created.OriginalPolicyId,
			'La original de la cadena'
		);
		Assert.areEqual(prior.NameInsuredId, created.NameInsuredId);
		Assert.areEqual('PESOS', created.Moneda__c);
		Assert.areEqual(
			'Vigente',
			created.Status,
			'El estado lo pone lo que comunico la aseguradora'
		);
		Assert.areEqual(
			2,
			[
				SELECT COUNT()
				FROM PaymentPlanInstallment__c
				WHERE
					paymentPlan__r.insurancePolicy__c = :created.Id
					AND paymentPlan__r.planStatus__c = 'Activo'
			],
			'Nace con su plan'
		);

		InsurancePolicy after = [
			SELECT PremiumAmount, ExpirationDate, IsRenewedPolicy, nextPolicy__c
			FROM InsurancePolicy
			WHERE Id = :prior.Id
		];
		Assert.isTrue(after.IsRenewedPolicy);
		Assert.areEqual(
			created.Id,
			after.nextPolicy__c,
			'La anterior enlaza a la siguiente'
		);
		Assert.areEqual(
			Decimal.valueOf('1200.00'),
			after.PremiumAmount,
			'La anterior no se toca'
		);
		Assert.areEqual(
			PolicyStatusService.mexicoMidnight(Date.newInstance(2027, 1, 15)),
			after.ExpirationDate
		);

		InboundPolicyUpdate__c result = load(c.Id);
		Assert.areEqual('Aplicado', result.inboundStatus__c);
		Assert.areEqual('RENOVACION_CREADA', result.policyMatchReason__c);
		Assert.areEqual(created.Id, result.candidatePolicy__c);
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM AppLog__c
				WHERE eventCode__c = 'POLICY_RENEWAL_CREATED'
			]
		);
	}

	/**
	 * @description: La misma renovacion, comunicada otra vez con un dato distinto, se aplica a
	 *               la vigencia ya creada: no se crea otra.
	 */
	@IsTest
	static void aRenewalIsNotDuplicated() {
		createPolicy(
			NUMBER_A,
			Date.newInstance(2026, 1, 15),
			Date.newInstance(2027, 1, 15)
		);
		InboundPolicyApplyService.apply(
			new Set<Id>{
				renewal(NUMBER_A, Date.newInstance(2027, 1, 15), 13000, 'Semestral').Id
			}
		);
		InboundPolicyUpdate__c again = renewal(
			NUMBER_A,
			Date.newInstance(2027, 1, 15),
			13000,
			'Semestral'
		);
		again.sourceNetPremium__c = 10500;
		again.sourceSynchronizedAt__c = System.now().addMinutes(5);
		update again;

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ again.Id });
		Test.stopTest();

		Assert.areEqual(
			2,
			[SELECT COUNT() FROM InsurancePolicy WHERE Name = :NUMBER_A]
		);
		Assert.areEqual(
			Decimal.valueOf('10500.00'),
			termStarting(NUMBER_A, Date.newInstance(2027, 1, 15)).Subtotal__c
		);
		Assert.areEqual('Aplicado', load(again.Id).inboundStatus__c);
	}

	/**
	 * @description: Dos comunicaciones de la misma renovacion en un envio crean una sola
	 *               vigencia; la mas antigua queda Superada.
	 */
	@IsTest
	static void twoCommunicationsOfTheSameRenewalCreateOneTerm() {
		createPolicy(
			NUMBER_A,
			Date.newInstance(2026, 1, 15),
			Date.newInstance(2027, 1, 15)
		);
		InboundPolicyUpdate__c older = renewal(
			NUMBER_A,
			Date.newInstance(2027, 1, 15),
			13000,
			'Semestral'
		);
		InboundPolicyUpdate__c newer = renewal(
			NUMBER_A,
			Date.newInstance(2027, 1, 15),
			13500,
			'Semestral'
		);
		newer.sourceSynchronizedAt__c = System.now().addMinutes(5);
		update newer;

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ older.Id, newer.Id });
		Test.stopTest();

		Assert.areEqual(
			2,
			[SELECT COUNT() FROM InsurancePolicy WHERE Name = :NUMBER_A]
		);
		Assert.areEqual(
			Decimal.valueOf('13500.00'),
			termStarting(NUMBER_A, Date.newInstance(2027, 1, 15)).PremiumAmount
		);
		Assert.areEqual('Superada', load(older.Id).inboundStatus__c);
		Assert.areEqual('Aplicado', load(newer.Id).inboundStatus__c);
	}

	/**
	 * @description: Un inicio anterior a las vigencias existentes no es una renovacion: va a
	 *               revision y no se crea nada.
	 */
	@IsTest
	static void anEarlierDateIsNotARenewal() {
		createPolicy(
			NUMBER_A,
			Date.newInstance(2026, 1, 15),
			Date.newInstance(2027, 1, 15)
		);
		InboundPolicyUpdate__c c = renewal(
			NUMBER_A,
			Date.newInstance(2024, 1, 15),
			13000,
			'Semestral'
		);

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ c.Id });
		Test.stopTest();

		Assert.areEqual(
			1,
			[SELECT COUNT() FROM InsurancePolicy WHERE Name = :NUMBER_A]
		);
		InboundPolicyUpdate__c result = load(c.Id);
		Assert.areEqual('Revision Manual', result.inboundStatus__c);
		Assert.areEqual('SIN_VIGENCIA', result.reviewReasonCode__c);
	}

	/**
	 * @description: Una renovacion sin forma de pago no se crea: va a revision con su tipo de motivo.
	 */
	@IsTest
	static void anIncompleteRenewalGoesToReview() {
		InsurancePolicy prior = createPolicy(
			NUMBER_A,
			Date.newInstance(2026, 1, 15),
			Date.newInstance(2027, 1, 15)
		);
		InboundPolicyUpdate__c c = renewal(
			NUMBER_A,
			Date.newInstance(2027, 1, 15),
			13000,
			null
		);

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ c.Id });
		Test.stopTest();

		Assert.areEqual(
			1,
			[SELECT COUNT() FROM InsurancePolicy WHERE Name = :NUMBER_A]
		);
		InboundPolicyUpdate__c result = load(c.Id);
		Assert.areEqual('Revision Manual', result.inboundStatus__c);
		Assert.areEqual('RENOVACION_INCOMPLETA', result.reviewReasonCode__c);
		Assert.areEqual(prior.Id, result.candidatePolicy__c);
		Assert.isNull(
			[
				SELECT carrierPolicyStatusRaw__c
				FROM InsurancePolicy
				WHERE Id = :prior.Id
			]
			.carrierPolicyStatusRaw__c,
			'El estado de la renovacion no se aplica a la vigencia anterior'
		);
	}

	/**
	 * @description: Una renovacion que no se puede crear no detiene a la otra del envio y el
	 *               fallo queda registrado.
	 */
	@IsTest
	static void aFailedRenewalDoesNotStopTheOthers() {
		createPolicy(
			NUMBER_A,
			Date.newInstance(2026, 1, 15),
			Date.newInstance(2027, 1, 15)
		);
		createPolicy(
			NUMBER_B,
			Date.newInstance(2026, 1, 15),
			Date.newInstance(2027, 1, 15)
		);
		InboundPolicyApplyService.failRenewalForTest.add(NUMBER_A);
		InboundPolicyUpdate__c failing = renewal(
			NUMBER_A,
			Date.newInstance(2027, 1, 15),
			13000,
			'Semestral'
		);
		InboundPolicyUpdate__c healthy = renewal(
			NUMBER_B,
			Date.newInstance(2027, 1, 15),
			13000,
			'Semestral'
		);

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ failing.Id, healthy.Id });
		Test.stopTest();

		Assert.areEqual(
			1,
			[SELECT COUNT() FROM InsurancePolicy WHERE Name = :NUMBER_A]
		);
		Assert.areEqual(
			2,
			[SELECT COUNT() FROM InsurancePolicy WHERE Name = :NUMBER_B]
		);
		InboundPolicyUpdate__c failed = load(failing.Id);
		Assert.areEqual('Revision Manual', failed.inboundStatus__c);
		Assert.areEqual('NO_SE_PUDO_GUARDAR', failed.reviewReasonCode__c);
		Assert.areEqual('Aplicado', load(healthy.Id).inboundStatus__c);
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM AppLog__c
				WHERE eventCode__c = 'POLICY_RENEWAL_FAILED'
			]
		);
	}

	private static void useMappings() {
		PolicyCarrierStatusService.mappingsForTest = new Map<String, String>{
			PolicyCarrierStatusService.mappingKey('QUALITAS', 'Vigor') => 'Vigente'
		};
	}

	private static InsurancePolicy createPolicy(
		String policyNumber,
		Date startDate,
		Date endDate
	) {
		InsurancePolicy policy = CollectionsTestDataFactory.buildCompletePolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Vigente',
			'Semestral',
			1200,
			startDate
		);
		policy.Name = policyNumber;
		policy.EffectiveDate = PolicyStatusService.mexicoMidnight(startDate);
		policy.ExpirationDate = PolicyStatusService.mexicoMidnight(endDate);
		insert policy;
		return [
			SELECT Id, NameInsuredId
			FROM InsurancePolicy
			WHERE Id = :policy.Id
		];
	}

	private static InboundPolicyUpdate__c renewal(
		String policyNumber,
		Date startDate,
		Decimal premium,
		String frequency
	) {
		sequence++;
		InboundPolicyUpdate__c c = new InboundPolicyUpdate__c(
			sourcePolicyNumber__c = policyNumber,
			sourceCarrierCode__c = 'QUALITAS',
			sourcePolicyStatusRaw__c = 'Vigor',
			sourcePolicyStartDate__c = startDate,
			sourcePolicyEndDate__c = startDate.addYears(1),
			sourceTotalPremium__c = premium,
			sourceNetPremium__c = 10400,
			sourcePremiumFrequency__c = frequency,
			sourceSynchronizedAt__c = System.now(),
			inboundStatus__c = 'Recibido',
			contentFingerprint__c = 'kan453-' + sequence,
			receivedAt__c = System.now()
		);
		insert c;
		return c;
	}

	private static InsurancePolicy termStarting(
		String policyNumber,
		Date startDate
	) {
		List<InsurancePolicy> found = [
			SELECT
				Id,
				Status,
				ExpirationDate,
				PremiumAmount,
				PremiumFrequency,
				Subtotal__c,
				PriorPolicyId,
				RenewedFromPolicyId,
				OriginalPolicyId,
				NameInsuredId,
				Moneda__c
			FROM InsurancePolicy
			WHERE
				Name = :policyNumber
				AND EffectiveDate = :PolicyStatusService.mexicoMidnight(startDate)
		];
		return found.isEmpty() ? null : found[0];
	}

	private static InboundPolicyUpdate__c load(Id updateId) {
		return [
			SELECT
				inboundStatus__c,
				policyMatchReason__c,
				reviewReasonCode__c,
				candidatePolicy__c
			FROM InboundPolicyUpdate__c
			WHERE Id = :updateId
		];
	}
}
