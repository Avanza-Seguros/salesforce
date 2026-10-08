/**
 *   @name: InboundPolicyRenewalTest
 *   @version: 2.0
 *   @creation date: 30/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: La renovacion de una aseguradora que conserva el numero no crea su vigencia: queda en
 *                 revision, sin tocar la vigencia anterior, hasta que alguien la da de alta; entonces el
 *                 siguiente reenvio la aplica solo. Una fecha anterior a las vigencias no es renovacion.
 */
@IsTest
private class InboundPolicyRenewalTest {
	private static final String POLICY_NUMBER = '0971453001';
	private static final String RENEWAL_ROW =
		'[{"sourcePolicyNumber__c":"' +
		POLICY_NUMBER +
		'","sourceCarrierCode__c":"QUALITAS","sourcePolicyStatusRaw__c":"Vigor",' +
		'"sourcePolicyStartDate__c":"2027-01-15","sourcePolicyEndDate__c":"2028-01-15",' +
		'"sourcePremiumFrequency__c":"Semestral","sourceTotalPremium__c":13000,' +
		'"sourceNetPremium__c":10400,"sourceSynchronizedAt__c":"%SYNC%"}]';

	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	/**
	 * @description: La renovacion queda en revision con su motivo y enlazada a la vigencia anterior;
	 *               no se crea ninguna poliza y la anterior conserva su prima, su estado de la
	 *               aseguradora y su fecha de sincronizacion.
	 */
	@IsTest
	static void renewalWaitsForItsTerm() {
		usarEquivalencias();
		InsurancePolicy prior = createPolicy(
			Date.newInstance(2026, 1, 15),
			Date.newInstance(2027, 1, 15)
		);
		InboundPolicyUpdate__c c = renewal(Date.newInstance(2027, 1, 15));

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ c.Id });
		Test.stopTest();

		Assert.areEqual(
			1,
			[SELECT COUNT() FROM InsurancePolicy WHERE Name = :POLICY_NUMBER],
			'No se crea nada'
		);
		InboundPolicyUpdate__c result = load(c.Id);
		Assert.areEqual('Revision Manual', result.inboundStatus__c);
		Assert.areEqual('RENOVACION_PENDIENTE', result.reviewReasonCode__c);
		Assert.areEqual(prior.Id, result.candidatePolicy__c);
		Assert.isTrue(
			result.manualReviewReason__c.contains('no existe en Salesforce')
		);

		InsurancePolicy after = [
			SELECT PremiumAmount, carrierPolicyStatusRaw__c, carrierDataSyncedAt__c
			FROM InsurancePolicy
			WHERE Id = :prior.Id
		];
		Assert.areEqual(
			Decimal.valueOf('1200.00'),
			after.PremiumAmount,
			'La anterior no se toca'
		);
		Assert.isNull(
			after.carrierPolicyStatusRaw__c,
			'El estado de la renovacion no se aplica a la anterior'
		);
		Assert.isNull(after.carrierDataSyncedAt__c);
	}

	/**
	 * @description: Cuando la vigencia nueva ya existe, el siguiente reenvio de la renovacion se aplica
	 *               a ella sin que nadie lo reprocese.
	 */
	@IsTest
	static void resendAppliesOnceTheTermExists() {
		InboundPolicyService.applyDisabledForTest = true;
		InboundPolicyService.receive(
			RENEWAL_ROW.replace('%SYNC%', '2026-12-20T10:00:00Z')
		);
		InboundPolicyService.applyDisabledForTest = false;
		createPolicy(Date.newInstance(2026, 1, 15), Date.newInstance(2027, 1, 15));
		Id updateId = [SELECT Id FROM InboundPolicyUpdate__c LIMIT 1].Id;
		InboundPolicyApplyService.apply(new Set<Id>{ updateId });
		Assert.areEqual('RENOVACION_PENDIENTE', load(updateId).reviewReasonCode__c);
		InsurancePolicy created = createPolicy(
			Date.newInstance(2027, 1, 15),
			Date.newInstance(2028, 1, 15)
		);

		Test.startTest();
		InboundPolicyService.receive(
			RENEWAL_ROW.replace('%SYNC%', '2026-12-21T10:00:00Z')
		);
		Test.stopTest();

		InboundPolicyUpdate__c result = load(updateId);
		Assert.areEqual('Aplicado', result.inboundStatus__c);
		Assert.areEqual(created.Id, result.candidatePolicy__c);
		Assert.isNull(result.reviewReasonCode__c);
		Assert.areEqual(
			Decimal.valueOf('10400.00'),
			[SELECT Subtotal__c FROM InsurancePolicy WHERE Id = :created.Id]
			.Subtotal__c
		);
	}

	/**
	 * @description: Un inicio anterior a las vigencias existentes no es una renovacion: va a revision
	 *               como vigencia no identificada.
	 */
	@IsTest
	static void anEarlierDateIsNotARenewal() {
		createPolicy(Date.newInstance(2026, 1, 15), Date.newInstance(2027, 1, 15));
		InboundPolicyUpdate__c c = renewal(Date.newInstance(2024, 1, 15));

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ c.Id });
		Test.stopTest();

		InboundPolicyUpdate__c result = load(c.Id);
		Assert.areEqual('Revision Manual', result.inboundStatus__c);
		Assert.areEqual('SIN_VIGENCIA', result.reviewReasonCode__c);
	}

	private static void usarEquivalencias() {
		PolicyCarrierStatusService.mappingsForTest = new Map<String, String>{
			PolicyCarrierStatusService.mappingKey('QUALITAS', 'Vigor') => 'Vigente'
		};
	}

	private static InsurancePolicy createPolicy(Date startDate, Date endDate) {
		InsurancePolicy policy = CollectionsTestDataFactory.buildCompletePolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Vigente',
			'Semestral',
			1200,
			startDate
		);
		policy.Name = POLICY_NUMBER;
		policy.EffectiveDate = PolicyStatusService.mexicoMidnight(startDate);
		policy.ExpirationDate = PolicyStatusService.mexicoMidnight(endDate);
		insert policy;
		return policy;
	}

	private static InboundPolicyUpdate__c renewal(Date startDate) {
		InboundPolicyUpdate__c c = new InboundPolicyUpdate__c(
			sourcePolicyNumber__c = POLICY_NUMBER,
			sourceCarrierCode__c = 'QUALITAS',
			sourcePolicyStatusRaw__c = 'Vigor',
			sourcePolicyStartDate__c = startDate,
			sourcePolicyEndDate__c = startDate.addYears(1),
			sourceTotalPremium__c = 13000,
			sourceNetPremium__c = 10400,
			sourcePremiumFrequency__c = 'Semestral',
			sourceSynchronizedAt__c = System.now(),
			inboundStatus__c = 'Recibido',
			contentFingerprint__c = 'kan453-' + startDate,
			receivedAt__c = System.now()
		);
		insert c;
		return c;
	}

	private static InboundPolicyUpdate__c load(Id updateId) {
		return [
			SELECT
				inboundStatus__c,
				policyMatchReason__c,
				reviewReasonCode__c,
				manualReviewReason__c,
				candidatePolicy__c
			FROM InboundPolicyUpdate__c
			WHERE Id = :updateId
		];
	}
}
