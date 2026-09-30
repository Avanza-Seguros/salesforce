/**
 *   @name: InboundPolicyReviewTest
 *   @version: 1.0
 *   @creation date: 30/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Una comunicacion de poliza que no se puede aplicar queda en revision
 *                 con un tipo de motivo fijo; el analista la reprocesa cuando resuelve lo que
 *                 faltaba, y si la aseguradora la vuelve a enviar se recupera sola.
 */
@IsTest
private class InboundPolicyReviewTest {
	private static final String POLICY_NUMBER = '0971452001';
	private static final Date TERM_START = Date.newInstance(2026, 1, 15);
	private static final String ROW =
		'[{"sourcePolicyNumber__c":"' +
		POLICY_NUMBER +
		'","sourceCarrierCode__c":"QUALITAS","sourcePolicyStartDate__c":"2026-01-15",' +
		'"sourceNetPremium__c":987,"sourceSynchronizedAt__c":"%SYNC%"}]';

	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	/**
	 * @description: Una poliza que no existe deja la comunicacion en revision con su
	 *               tipo de motivo y el mensaje que lo explica.
	 */
	@IsTest
	static void missingPolicyGoesToReviewWithItsReason() {
		Id updateId = insertCommunication();

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ updateId });
		Test.stopTest();

		InboundPolicyUpdate__c result = load(updateId);
		Assert.areEqual('Revision Manual', result.inboundStatus__c);
		Assert.areEqual('SIN_POLIZA', result.reviewReasonCode__c);
		Assert.isTrue(
			result.manualReviewReason__c.startsWith(
				'La poliza no existe en Salesforce'
			)
		);
		Assert.isTrue(result.manualReviewRequired__c);
	}

	/**
	 * @description: El analista crea la poliza que faltaba y reprocesa: se aplica como si
	 *               acabara de llegar, sin motivo de revision, y cuenta el reproceso.
	 */
	@IsTest
	static void reprocessAppliesOnceThePolicyExists() {
		Id updateId = insertCommunication();
		InboundPolicyApplyService.apply(new Set<Id>{ updateId });
		Id policyId = createPolicy();

		Test.startTest();
		String message = InboundPolicyApplyService.reprocess(updateId);
		Test.stopTest();

		Assert.isTrue(message.contains(POLICY_NUMBER), message);
		InboundPolicyUpdate__c result = load(updateId);
		Assert.areEqual('Aplicado', result.inboundStatus__c);
		Assert.isNull(result.reviewReasonCode__c);
		Assert.isFalse(result.manualReviewRequired__c);
		Assert.areEqual(1, result.reprocessCount__c);
		Assert.areEqual(policyId, result.candidatePolicy__c);
		Assert.areEqual(
			Decimal.valueOf('987.00'),
			[SELECT Subtotal__c FROM InsurancePolicy WHERE Id = :policyId].Subtotal__c
		);
	}

	/**
	 * @description: Si sigue sin poder aplicarse, vuelve a revision con un mensaje que lo
	 *               explica.
	 */
	@IsTest
	static void reprocessThatStillFailsReturnsToReview() {
		Id updateId = insertCommunication();
		InboundPolicyApplyService.apply(new Set<Id>{ updateId });

		Test.startTest();
		String message = InboundPolicyApplyService.reprocess(updateId);
		Test.stopTest();

		Assert.isTrue(message.startsWith('Sigue sin poder aplicarse'), message);
		InboundPolicyUpdate__c result = load(updateId);
		Assert.areEqual('Revision Manual', result.inboundStatus__c);
		Assert.areEqual('SIN_POLIZA', result.reviewReasonCode__c);
		Assert.areEqual(1, result.reprocessCount__c);
	}

	/**
	 * @description: Solo se reprocesa lo que esta en revision.
	 */
	@IsTest
	static void onlyCommunicationsInReviewCanBeReprocessed() {
		createPolicy();
		Id updateId = insertCommunication();
		InboundPolicyApplyService.apply(new Set<Id>{ updateId });
		Assert.areEqual('Aplicado', load(updateId).inboundStatus__c);

		Test.startTest();
		String error;
		try {
			InboundPolicyApplyService.reprocess(updateId);
		} catch (AuraHandledException e) {
			error = e.getMessage();
		}
		Test.stopTest();

		Assert.isNotNull(error);
		Assert.isTrue(error.contains('revisión manual'), error);
	}

	/**
	 * @description: Cuando la poliza ya existe y la aseguradora vuelve a enviar la misma
	 *               comunicacion, se aplica sola, sin que nadie la reprocese.
	 */
	@IsTest
	static void resendRecoversOnceThePolicyExists() {
		InboundPolicyService.applyDisabledForTest = true;
		InboundPolicyService.receive(ROW.replace('%SYNC%', '2026-09-01T10:00:00Z'));
		InboundPolicyService.applyDisabledForTest = false;
		Id updateId = [SELECT Id FROM InboundPolicyUpdate__c LIMIT 1].Id;
		InboundPolicyApplyService.apply(new Set<Id>{ updateId });
		Assert.areEqual('Revision Manual', load(updateId).inboundStatus__c);
		Id policyId = createPolicy();

		Test.startTest();
		InboundPolicyService.EndpointResult r = InboundPolicyService.receive(
			ROW.replace('%SYNC%', '2026-09-08T10:00:00Z')
		);
		Test.stopTest();

		Assert.areEqual('RESENT', r.body.results[0].code);
		InboundPolicyUpdate__c result = load(updateId);
		Assert.areEqual('Aplicado', result.inboundStatus__c);
		Assert.areEqual(policyId, result.candidatePolicy__c);
		Assert.areEqual(
			0,
			result.reprocessCount__c == null ? 0 : result.reprocessCount__c
		);
	}

	/**
	 * @description: La moneda distinta queda con su tipo de motivo.
	 */
	@IsTest
	static void currencyMismatchHasItsReasonCode() {
		Id policyId = createPolicy();
		update new InsurancePolicy(Id = policyId, Moneda__c = 'PESOS');
		Id updateId = insertCommunication();
		update new InboundPolicyUpdate__c(Id = updateId, sourceCurrency__c = 'USD');

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ updateId });
		Test.stopTest();

		InboundPolicyUpdate__c result = load(updateId);
		Assert.areEqual('Revision Manual', result.inboundStatus__c);
		Assert.areEqual('MONEDA_DISTINTA', result.reviewReasonCode__c);
	}

	private static Id createPolicy() {
		InsurancePolicy policy = CollectionsTestDataFactory.buildCompletePolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Vigente',
			'Semestral',
			1200,
			TERM_START
		);
		policy.Name = POLICY_NUMBER;
		policy.EffectiveDate = PolicyStatusService.mexicoMidnight(TERM_START);
		policy.ExpirationDate = PolicyStatusService.mexicoMidnight(
			TERM_START.addYears(1)
		);
		insert policy;
		return policy.Id;
	}

	private static Id insertCommunication() {
		InboundPolicyUpdate__c c = new InboundPolicyUpdate__c(
			sourcePolicyNumber__c = POLICY_NUMBER,
			sourcePolicyStartDate__c = TERM_START,
			sourceCarrierCode__c = 'QUALITAS',
			sourceNetPremium__c = 987,
			sourceSynchronizedAt__c = DateTime.newInstanceGmt(2026, 9, 1, 10, 0, 0),
			inboundStatus__c = 'Recibido',
			contentFingerprint__c = 'kan452-' + Crypto.getRandomInteger(),
			receivedAt__c = System.now()
		);
		insert c;
		return c.Id;
	}

	private static InboundPolicyUpdate__c load(Id updateId) {
		return [
			SELECT
				inboundStatus__c,
				reviewReasonCode__c,
				manualReviewReason__c,
				manualReviewRequired__c,
				reprocessCount__c,
				candidatePolicy__c
			FROM InboundPolicyUpdate__c
			WHERE Id = :updateId
		];
	}
}
