/**
 *   @name: InboundNoMatchReviewTest
 *   @version: 1.0
 *   @creation date: 05/10/2026
 *   @author: Javier Torres - Volestra
 *   @description: Un pago cuya poliza no existe (Sin Match) queda en la bandeja de revision con
 *                 su motivo, no la pierde cuando la aseguradora lo reenvia sin cambios y, si
 *                 la poliza ya existe cuando llega el reenvio, vuelve solo al circuito.
 */
@IsTest
private class InboundNoMatchReviewTest {
	private static final String EXTERNAL_ID = 'EXT-NOMATCH-01';
	private static final String POLICY_NUMBER = 'POL-NOMATCH-01';

	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	/**
	 * @description: Un reenvio identico de un pago Sin Match conserva la marca de revision y el
	 *               motivo; sin poliza, no se reintenta.
	 */
	@IsTest
	static void unchangedResendKeepsTheReviewFlag() {
		InboundInsurancePaymentService.receive(body());
		leaveAsNoMatch();

		Test.startTest();
		InboundInsurancePaymentService.receive(body());
		Test.stopTest();

		InboundInsurancePayment__c after = payment();
		Assert.areEqual('Sin Match', after.inboundStatus__c);
		Assert.isTrue(
			after.manualReviewRequired__c,
			'El reenvio no la saca de la bandeja'
		);
		Assert.isTrue(after.manualReviewReason__c.contains('no existe'));
		Assert.areEqual(1, after.resendCount__c);
		Assert.areEqual(0, retriedLogs());
	}

	/**
	 * @description: Si la poliza ya existe cuando llega el reenvio, el pago vuelve al circuito
	 *               con su poliza candidata y sale de la bandeja; queda constancia.
	 */
	@IsTest
	static void resendRetriesOnceThePolicyExists() {
		InboundInsurancePaymentService.receive(body());
		leaveAsNoMatch();
		InsurancePolicy policy = CollectionsTestDataFactory.buildCompletePolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Vigente',
			'Mensual',
			1000,
			Date.newInstance(2026, 1, 15)
		);
		policy.Name = POLICY_NUMBER;
		policy.EffectiveDate = PolicyStatusService.mexicoMidnight(
			Date.newInstance(2026, 1, 15)
		);
		policy.ExpirationDate = PolicyStatusService.mexicoMidnight(
			Date.newInstance(2027, 1, 15)
		);
		insert policy;

		Test.startTest();
		InboundInsurancePaymentService.receive(body());
		Test.stopTest();

		InboundInsurancePayment__c after = payment();
		Assert.areNotEqual(
			'Sin Match',
			after.inboundStatus__c,
			'Volvio al circuito'
		);
		Assert.areEqual(policy.Id, after.candidatePolicy__c);
		Assert.areEqual(1, retriedLogs());
	}

	/**
	 * @description: El circuito deja el motivo al marcar un Sin Match y lo limpia cuando el
	 *               pago termina con otro resultado.
	 */
	@IsTest
	static void scoreExplainsNoMatchAndClearsTheReasonOtherwise() {
		InboundInsurancePayment__c noMatch = normalized(
			'EXT-NOMATCH-02',
			'NO_MATCH',
			'Sin Match',
			null
		);
		InboundInsurancePayment__c reconciled = normalized(
			'EXT-NOMATCH-03',
			'EXACT_POLICY_AND_SEQUENCE',
			'Match Exacto',
			'UNICO_GANADOR'
		);
		update new InboundInsurancePayment__c(
			Id = reconciled.Id,
			manualReviewReason__c = 'motivo viejo'
		);

		Test.startTest();
		System.enqueueJob(
			new InboundConfidenceScoreQueueable(
				new Set<Id>{ noMatch.Id, reconciled.Id }
			)
		);
		Test.stopTest();

		InboundInsurancePayment__c noMatchAfter = [
			SELECT inboundStatus__c, manualReviewRequired__c, manualReviewReason__c
			FROM InboundInsurancePayment__c
			WHERE Id = :noMatch.Id
		];
		Assert.areEqual('Sin Match', noMatchAfter.inboundStatus__c);
		Assert.isTrue(noMatchAfter.manualReviewRequired__c);
		Assert.isTrue(
			noMatchAfter.manualReviewReason__c.startsWith(
				'La poliza no existe en Salesforce'
			)
		);
		Assert.isTrue(noMatchAfter.manualReviewReason__c.contains(POLICY_NUMBER));
		Assert.isNull(
			[
				SELECT manualReviewReason__c
				FROM InboundInsurancePayment__c
				WHERE Id = :reconciled.Id
			]
			.manualReviewReason__c
		);
	}

	private static String body() {
		return '[{' +
			'"externalPaymentId__c":"' +
			EXTERNAL_ID +
			'",' +
			'"sourcePolicyNumber__c":"' +
			POLICY_NUMBER +
			'",' +
			'"sourceAmount__c":1000.00,' +
			'"sourceDueDate__c":"15/09/2026",' +
			'"sourcePaymentDate__c":"15/09/2026",' +
			'"sourcePaymentStatus__c":"Pagado"' +
			'}]';
	}

	/**
	 * Deja el pago como lo deja el circuito cuando no encuentra la poliza. Se arma a mano porque
	 * el circuito es asincrono y en una prueba solo avanza un eslabon; al no estar Parseado, el
	 * normalizador que encolo la primera recepcion lo ignora.
	 */
	private static void leaveAsNoMatch() {
		update new InboundInsurancePayment__c(
			Id = payment().Id,
			inboundStatus__c = 'Sin Match',
			manualReviewRequired__c = true,
			manualReviewReason__c = 'La poliza no existe en Salesforce: no hay ninguna con el numero ' +
				POLICY_NUMBER +
				'.'
		);
	}

	private static InboundInsurancePayment__c payment() {
		return [
			SELECT
				Id,
				inboundStatus__c,
				manualReviewRequired__c,
				manualReviewReason__c,
				resendCount__c,
				candidatePolicy__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = :EXTERNAL_ID
			LIMIT 1
		];
	}

	private static Integer retriedLogs() {
		return [
			SELECT COUNT()
			FROM AppLog__c
			WHERE eventCode__c = 'NO_MATCH_RETRIED'
		];
	}

	private static InboundInsurancePayment__c normalized(
		String externalId,
		String method,
		String result,
		String installmentReason
	) {
		InboundInsurancePayment__c rec = new InboundInsurancePayment__c(
			externalPaymentId__c = externalId,
			inboundStatus__c = 'Normalizado',
			sourceAmount__c = 400,
			sourcePaymentDate__c = Date.today(),
			sourcePolicyNumber__c = POLICY_NUMBER,
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now(),
			parsedAt__c = System.now(),
			reconciliationMethod__c = method,
			reconciliationResult__c = result,
			installmentMatchReason__c = installmentReason
		);
		insert rec;
		return rec;
	}
}
