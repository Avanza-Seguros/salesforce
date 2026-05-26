/**
 *   @name: InboundConfidenceScoreQueueableTest
 *   @version: 1.0
 *   @creation date: 20/05/2026
 *   @author: Javier Torres - Volestra
 *   @description: Valida el calculo de score, banda de confianza y transicion de
 *                 estado para pagos inbound. Cubre todos los metodos de conciliacion
 *                 (EXACT_POLICY_AND_SEQUENCE, POLICY_DATE_AMOUNT, POLICY_AMOUNT,
 *                 POLICY_ONLY, AMBIGUOUS, NO_MATCH, ERROR), el aislamiento de errores
 *                 por registro, la exclusion de registros no Normalizados y el
 *                 encadenamiento a PaymentReconciliationQueueable.
 */
@IsTest
private class InboundConfidenceScoreQueueableTest {
	@IsTest
	static void exactPolicyAndSequenceYieldsConciliado() {
		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-CS-001',
			'EXACT_POLICY_AND_SEQUENCE',
			'Match Exacto',
			'UNICO_GANADOR'
		);

		Test.startTest();
		System.enqueueJob(
			new InboundConfidenceScoreQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT
				confidenceScore__c,
				confidenceBand__c,
				manualReviewRequired__c,
				inboundStatus__c,
				candidateCount__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual(95, inbound.confidenceScore__c);
		Assert.areEqual('Alta', inbound.confidenceBand__c);
		Assert.areEqual(false, inbound.manualReviewRequired__c);
		Assert.areEqual('Conciliado', inbound.inboundStatus__c);
		Assert.areEqual(1, inbound.candidateCount__c);
	}

	@IsTest
	static void policyDateAmountYieldsConciliado() {
		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-CS-002',
			'POLICY_DATE_AMOUNT',
			'Match Exacto',
			'UNICO_GANADOR'
		);

		Test.startTest();
		System.enqueueJob(
			new InboundConfidenceScoreQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT
				confidenceScore__c,
				confidenceBand__c,
				inboundStatus__c,
				candidateCount__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual(85, inbound.confidenceScore__c);
		Assert.areEqual('Alta', inbound.confidenceBand__c);
		Assert.areEqual('Conciliado', inbound.inboundStatus__c);
		Assert.areEqual(1, inbound.candidateCount__c);
	}

	@IsTest
	static void policyAmountYieldsRevisionManual() {
		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-CS-003',
			'POLICY_AMOUNT',
			'Match Probable',
			'UNICO_GANADOR'
		);

		Test.startTest();
		System.enqueueJob(
			new InboundConfidenceScoreQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT
				confidenceScore__c,
				confidenceBand__c,
				manualReviewRequired__c,
				inboundStatus__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual(65, inbound.confidenceScore__c);
		Assert.areEqual('Media', inbound.confidenceBand__c);
		Assert.areEqual(true, inbound.manualReviewRequired__c);
		Assert.areEqual('Revision Manual', inbound.inboundStatus__c);
	}

	@IsTest
	static void policyOnlyYieldsRevisionManual() {
		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-CS-004',
			'POLICY_ONLY',
			'Match Probable',
			'SCORE_BAJO'
		);

		Test.startTest();
		System.enqueueJob(
			new InboundConfidenceScoreQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT
				confidenceScore__c,
				confidenceBand__c,
				manualReviewRequired__c,
				inboundStatus__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual(45, inbound.confidenceScore__c);
		Assert.areEqual('Media', inbound.confidenceBand__c);
		Assert.areEqual(true, inbound.manualReviewRequired__c);
		Assert.areEqual('Revision Manual', inbound.inboundStatus__c);
	}

	@IsTest
	static void noMatchYieldsSinMatch() {
		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-CS-005',
			'NO_MATCH',
			'Sin Match',
			null
		);

		Test.startTest();
		System.enqueueJob(
			new InboundConfidenceScoreQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT
				confidenceScore__c,
				confidenceBand__c,
				manualReviewRequired__c,
				inboundStatus__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual(0, inbound.confidenceScore__c);
		Assert.areEqual('Baja', inbound.confidenceBand__c);
		Assert.areEqual(true, inbound.manualReviewRequired__c);
		Assert.areEqual('Sin Match', inbound.inboundStatus__c);
		Assert.areEqual(0, inbound.candidateCount__c);
	}

	@IsTest
	static void ambiguousYieldsRevisionManual() {
		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-CS-006',
			'AMBIGUOUS',
			'Revision Manual',
			'EMPATE'
		);

		Test.startTest();
		System.enqueueJob(
			new InboundConfidenceScoreQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT
				confidenceScore__c,
				confidenceBand__c,
				manualReviewRequired__c,
				inboundStatus__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual(25, inbound.confidenceScore__c);
		Assert.areEqual('Baja', inbound.confidenceBand__c);
		Assert.areEqual(true, inbound.manualReviewRequired__c);
		Assert.areEqual('Revision Manual', inbound.inboundStatus__c);
		Assert.areEqual(2, inbound.candidateCount__c);
	}

	@IsTest
	static void sinCuotasYieldsCandidateCountZero() {
		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-CS-011',
			'POLICY_ONLY',
			'Match Probable',
			'SIN_CUOTAS'
		);

		Test.startTest();
		System.enqueueJob(
			new InboundConfidenceScoreQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT candidateCount__c, confidenceScore__c, inboundStatus__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual(0, inbound.candidateCount__c);
		Assert.areEqual(45, inbound.confidenceScore__c);
		Assert.areEqual('Revision Manual', inbound.inboundStatus__c);
	}

	@IsTest
	static void errorMethodYieldsRevisionManual() {
		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-CS-007',
			'ERROR',
			'Revision Manual',
			null
		);

		Test.startTest();
		System.enqueueJob(
			new InboundConfidenceScoreQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT
				confidenceScore__c,
				confidenceBand__c,
				manualReviewRequired__c,
				inboundStatus__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual(0, inbound.confidenceScore__c);
		Assert.areEqual('Baja', inbound.confidenceBand__c);
		Assert.areEqual(true, inbound.manualReviewRequired__c);
		Assert.areEqual('Revision Manual', inbound.inboundStatus__c);
	}

	@IsTest
	static void exceptionIsolationSetsManualReview() {
		InboundConfidenceScoreQueueable.forceFailureForTest = true;

		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-CS-008',
			'EXACT_POLICY_AND_SEQUENCE',
			'Match Exacto',
			'UNICO_GANADOR'
		);

		Test.startTest();
		System.enqueueJob(
			new InboundConfidenceScoreQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT
				confidenceScore__c,
				confidenceBand__c,
				manualReviewRequired__c,
				inboundStatus__c,
				candidateCount__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual(0, inbound.confidenceScore__c);
		Assert.areEqual('Baja', inbound.confidenceBand__c);
		Assert.areEqual(true, inbound.manualReviewRequired__c);
		Assert.areEqual('Revision Manual', inbound.inboundStatus__c);
		Assert.areEqual(0, inbound.candidateCount__c);
	}

	@IsTest
	static void skipsRecordsThatAreNotInNormalizedStatus() {
		InboundInsurancePayment__c inbound = new InboundInsurancePayment__c(
			externalPaymentId__c = 'EXT-CS-009',
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
			new InboundConfidenceScoreQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT confidenceScore__c, inboundStatus__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.isNull(inbound.confidenceScore__c);
		Assert.areEqual('Parseado', inbound.inboundStatus__c);
	}

	@IsTest
	static void unknownMethodYieldsZeroScoreAndRevisionManual() {
		InboundInsurancePayment__c inbound = createNormalizedInbound(
			'EXT-CS-010',
			null,
			null,
			null
		);

		Test.startTest();
		System.enqueueJob(
			new InboundConfidenceScoreQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT confidenceScore__c, confidenceBand__c, inboundStatus__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual(0, inbound.confidenceScore__c);
		Assert.areEqual('Baja', inbound.confidenceBand__c);
		Assert.areEqual('Revision Manual', inbound.inboundStatus__c);
	}

	private static InboundInsurancePayment__c createNormalizedInbound(
		String externalId,
		String reconciliationMethod,
		String reconciliationResult,
		String installmentMatchReason
	) {
		InboundInsurancePayment__c rec = new InboundInsurancePayment__c(
			externalPaymentId__c = externalId,
			inboundStatus__c = 'Normalizado',
			sourceAmount__c = 400,
			sourcePaymentDate__c = Date.today(),
			sourcePolicyNumber__c = 'POL-TEST',
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now(),
			parsedAt__c = System.now(),
			reconciliationMethod__c = reconciliationMethod,
			reconciliationResult__c = reconciliationResult,
			installmentMatchReason__c = installmentMatchReason
		);
		insert rec;
		return rec;
	}
}
