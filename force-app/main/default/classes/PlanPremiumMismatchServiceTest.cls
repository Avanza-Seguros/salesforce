@IsTest
private class PlanPremiumMismatchServiceTest {
	private static final String EVENT_MISMATCH = 'PLAN_PREMIUM_MISMATCH';
	private static final String EVENT_CLEARED = 'PLAN_PREMIUM_MISMATCH_CLEARED';
	private static final String EVENT_FAILED = 'PLAN_PREMIUM_MISMATCH_FAILED';

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Crea la cuenta asegurada compartida usada por todos los tests de la clase.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA1/CA2. En una poliza que ya cobro, la prima nueva se queda en la poliza,
	 *               el plan no cambia y la poliza queda marcada con la prima del plan, la
	 *               fecha y la diferencia.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void marksPolicyWithCollectionsWhenPremiumChanges() {
		InsurancePolicy policy = createPolicyWithCollections();
		Set<Id> originalInstallmentIds = installmentIds(policy.Id);

		Test.startTest();
		policy.PremiumAmount = 1500;
		update policy;
		Test.stopTest();

		InsurancePolicy saved = loadPolicy(policy.Id);

		Assert.areEqual(Decimal.valueOf('1500.00'), saved.PremiumAmount);
		Assert.isTrue(saved.planPremiumMismatch__c);
		Assert.areEqual(Decimal.valueOf('1200.00'), saved.planPremiumAmount__c);
		Assert.areEqual(Decimal.valueOf('300.00'), saved.premiumMismatchAmount__c);
		Assert.isNotNull(saved.premiumMismatchSince__c);
		Assert.areEqual(originalInstallmentIds, installmentIds(policy.Id));
		Assert.areEqual(1, countLogs(policy.Id, EVENT_MISMATCH));
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA3. Una poliza sin cobros rehace su plan y no queda marcada.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void doesNotMarkPolicyWithoutCollections() {
		InsurancePolicy policy = CollectionsTestDataFactory.createOperationalPolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Semestral',
			1200,
			Date.today().addDays(10)
		);

		Test.startTest();
		policy.PremiumAmount = 1500;
		update policy;
		Test.stopTest();

		InsurancePolicy saved = loadPolicy(policy.Id);

		Assert.isFalse(saved.planPremiumMismatch__c);
		Assert.isNull(saved.planPremiumAmount__c);
		Assert.areEqual(0, countLogs(policy.Id, EVENT_MISMATCH));
		Assert.areEqual(
			Decimal.valueOf('1500.00'),
			CollectionsTestDataFactory.sumExpectedAmounts(
				CollectionsTestDataFactory.getInstallmentsByPolicy(policy.Id)
			),
			'El plan sin cobros se rehizo con la prima nueva'
		);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA4. Si la prima vuelve a coincidir con el plan, la marca se quita sola.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void clearsMarkWhenPremiumMatchesAgain() {
		InsurancePolicy policy = createPolicyWithCollections();
		policy.PremiumAmount = 1500;
		update policy;

		Test.startTest();
		policy.PremiumAmount = 1200;
		update policy;
		Test.stopTest();

		InsurancePolicy saved = loadPolicy(policy.Id);

		Assert.isFalse(saved.planPremiumMismatch__c);
		Assert.isNull(saved.planPremiumAmount__c);
		Assert.isNull(saved.premiumMismatchSince__c);
		Assert.isNull(saved.premiumMismatchAmount__c);
		Assert.areEqual(1, countLogs(policy.Id, EVENT_CLEARED));
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA4. Si es el plan el que vuelve a cuadrar con la prima, la marca tambien
	 *               se quita sola.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void clearsMarkWhenPlanMatchesAgain() {
		InsurancePolicy policy = createPolicyWithCollections();
		policy.PremiumAmount = 1500;
		update policy;
		PaymentPlan__c plan = CollectionsTestDataFactory.getActivePlan(policy.Id);

		Test.startTest();
		plan.expectedTotalAmount__c = 1500;
		update plan;
		Test.stopTest();

		Assert.isFalse(loadPolicy(policy.Id).planPremiumMismatch__c);
		Assert.areEqual(1, countLogs(policy.Id, EVENT_CLEARED));
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA6. Guardar otra vez la misma prima no cambia nada ni se vuelve a
	 *               registrar; una prima distinta si cuenta como una comunicacion nueva.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void samePremiumTwiceDoesNotLogAgain() {
		InsurancePolicy policy = createPolicyWithCollections();
		policy.PremiumAmount = 1500;
		update policy;
		Datetime firstSince = loadPolicy(policy.Id).premiumMismatchSince__c;

		Test.startTest();
		update policy;
		Assert.areEqual(1, countLogs(policy.Id, EVENT_MISMATCH));
		Assert.areEqual(firstSince, loadPolicy(policy.Id).premiumMismatchSince__c);

		policy.PremiumAmount = 1600;
		update policy;
		Test.stopTest();

		InsurancePolicy saved = loadPolicy(policy.Id);

		Assert.isTrue(saved.planPremiumMismatch__c);
		Assert.areEqual(Decimal.valueOf('1200.00'), saved.planPremiumAmount__c);
		Assert.areEqual(Decimal.valueOf('400.00'), saved.premiumMismatchAmount__c);
		Assert.areEqual(2, countLogs(policy.Id, EVENT_MISMATCH));
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA7. Si la marca de una poliza del lote no se puede guardar, las demas se
	 *               marcan y el fallo queda registrado con la poliza y el motivo.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void failureOnOnePolicyDoesNotStopTheOthers() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		Date firstDueDate = Date.today().addMonths(-4);
		List<InsurancePolicy> policies = new List<InsurancePolicy>{
			CollectionsTestDataFactory.buildCompletePolicy(
				accountId,
				'Inicial',
				'Semestral',
				1200,
				firstDueDate
			),
			CollectionsTestDataFactory.buildCompletePolicy(
				accountId,
				'Inicial',
				'Semestral',
				1200,
				firstDueDate
			)
		};
		insert policies;
		reconcileFirstInstallment(policies[0].Id);
		reconcileFirstInstallment(policies[1].Id);
		PlanPremiumMismatchService.failForTest.add(policies[0].Id);

		Test.startTest();
		for (InsurancePolicy policy : policies) {
			policy.PremiumAmount = 1500;
		}
		update policies;
		Test.stopTest();

		Assert.isFalse(loadPolicy(policies[0].Id).planPremiumMismatch__c);
		Assert.areEqual(1, countLogs(policies[0].Id, EVENT_FAILED));
		Assert.isTrue(loadPolicy(policies[1].Id).planPremiumMismatch__c);
		Assert.areEqual(1, countLogs(policies[1].Id, EVENT_MISMATCH));
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Despues de un cambio de frecuencia, la prima del plan sigue siendo la
	 *               prima completa: el plan nuevo lleva el saldo pendiente y lo ya cobrado
	 *               sigue en el plan reemplazado.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void planPremiumSurvivesFrequencyChange() {
		InsurancePolicy policy = CollectionsTestDataFactory.createOperationalPolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Semestral',
			1200,
			Date.today().addMonths(-6)
		);
		reconcileFirstInstallment(policy.Id);
		policy.PremiumFrequency = 'Mensual';
		update policy;

		Test.startTest();
		Map<Id, Decimal> planPremium = PlanPremiumMismatchService.selectPlanPremiumByPolicyId(
			new Set<Id>{ policy.Id }
		);
		Test.stopTest();

		Assert.areEqual(
			2,
			[
				SELECT COUNT()
				FROM PaymentPlan__c
				WHERE insurancePolicy__c = :policy.Id
			],
			'El cambio de frecuencia reemplazo el plan'
		);
		Assert.areEqual(Decimal.valueOf('1200.00'), planPremium.get(policy.Id));
		Assert.isFalse(loadPolicy(policy.Id).planPremiumMismatch__c);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Una poliza sin plan no tiene con que compararse y no se marca.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void doesNotMarkPolicyWithoutPlan() {
		InsurancePolicy policy = CollectionsTestDataFactory.createPolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Cancelado'
		);

		Test.startTest();
		policy.PremiumAmount = 1500;
		update policy;
		Test.stopTest();

		Assert.isFalse(loadPolicy(policy.Id).planPremiumMismatch__c);
		Assert.areEqual(0, countLogs(policy.Id, EVENT_MISMATCH));
	}

	private static InsurancePolicy createPolicyWithCollections() {
		InsurancePolicy policy = CollectionsTestDataFactory.createOperationalPolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Semestral',
			1200,
			Date.today().addMonths(-4)
		);
		reconcileFirstInstallment(policy.Id);
		return policy;
	}

	private static void reconcileFirstInstallment(Id policyId) {
		PaymentPlanInstallment__c first = CollectionsTestDataFactory.getInstallmentsByPolicy(
			policyId
		)[0];
		first.installmentStatus__c = 'Conciliado';
		update first;
	}

	private static InsurancePolicy loadPolicy(Id policyId) {
		return [
			SELECT
				PremiumAmount,
				planPremiumMismatch__c,
				planPremiumAmount__c,
				premiumMismatchAmount__c,
				premiumMismatchSince__c
			FROM InsurancePolicy
			WHERE Id = :policyId
		];
	}

	private static Set<Id> installmentIds(Id policyId) {
		return new Map<Id, PaymentPlanInstallment__c>(
				CollectionsTestDataFactory.getInstallmentsByPolicy(policyId)
			)
			.keySet()
			.clone();
	}

	private static Integer countLogs(Id policyId, String eventCode) {
		return [
			SELECT COUNT()
			FROM AppLog__c
			WHERE recordId__c = :policyId AND eventCode__c = :eventCode
		];
	}
}
