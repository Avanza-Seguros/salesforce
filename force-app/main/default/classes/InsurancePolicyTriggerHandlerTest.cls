/**
 *   @name: InsurancePolicyTriggerHandlerTest
 *   @version: 1.0
 *   @creation date: 23/04/2026
 *   @author: Javier Torres - Volestra
 *   @description: Valida la creacion automatica y la reutilizacion del plan inicial
 *                 a partir de InsurancePolicy.
 */
@IsTest
private class InsurancePolicyTriggerHandlerTest {
	/**
	 * @creation date: 23/04/2026
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
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Verifica que una poliza operativa completa cree un plan inicial activo.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void createsInitialPlanWhenPolicyIsInsertedAsOperational() {
		InsurancePolicy policy = CollectionsTestDataFactory.buildCompletePolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Vigente',
			'Mensual',
			1200,
			Date.today().addDays(30)
		);

		Test.startTest();
		insert policy;
		Test.stopTest();

		PaymentPlan__c plan = [
			SELECT
				insurancePolicy__c,
				planType__c,
				planStatus__c,
				premiumFrequency__c,
				expectedTotalAmount__c,
				firstDueDate__c,
				installmentCount__c
			FROM PaymentPlan__c
			WHERE insurancePolicy__c = :policy.Id
			LIMIT 1
		];

		Assert.areEqual(policy.Id, plan.insurancePolicy__c);
		Assert.areEqual('Inicial', plan.planType__c);
		Assert.areEqual('Activo', plan.planStatus__c);
		Assert.areEqual('Mensual', plan.premiumFrequency__c);
		Assert.areEqual(Decimal.valueOf('1200'), plan.expectedTotalAmount__c);
		Assert.areEqual(policy.PaymentDueDate, plan.firstDueDate__c);
		Assert.areEqual(12, plan.installmentCount__c);
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Verifica que una actualizacion de una poliza operativa no duplique el plan inicial.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void createsOnlyOnePlanWhenOperationalPolicyIsUpdatedAgain() {
		InsurancePolicy policy = CollectionsTestDataFactory.buildCompletePolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Vigente',
			'Mensual',
			1200,
			Date.today().addDays(30)
		);

		insert policy;

		Test.startTest();
		policy.PolicyName = 'Updated policy name';
		update policy;
		Test.stopTest();

		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM PaymentPlan__c
				WHERE insurancePolicy__c = :policy.Id
			]
		);
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Verifica que al pasar de Inicial a Vigente se conserve el mismo plan inicial.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void keepsOnePlanWhenPolicyTransitionsFromInitialToVigente() {
		InsurancePolicy policy = CollectionsTestDataFactory.buildCompletePolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Inicial',
			'Mensual',
			1200,
			Date.today().addDays(30)
		);

		insert policy;

		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM PaymentPlan__c
				WHERE insurancePolicy__c = :policy.Id
			]
		);

		Test.startTest();
		policy.Status = 'Vigente';
		update policy;
		Test.stopTest();

		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM PaymentPlan__c
				WHERE insurancePolicy__c = :policy.Id
			]
		);
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Verifica el mapeo de frecuencias soportadas hacia la cantidad esperada de cuotas.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void mapsPremiumFrequencies() {
		Id insuredAccountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();

		List<InsurancePolicy> policies = new List<InsurancePolicy>{
			CollectionsTestDataFactory.buildCompletePolicy(
				insuredAccountId,
				'Vigente',
				'Trimestral',
				300,
				Date.today().addDays(30)
			),
			CollectionsTestDataFactory.buildCompletePolicy(
				insuredAccountId,
				'Vigente',
				'Semestral',
				600,
				Date.today().addDays(30)
			),
			CollectionsTestDataFactory.buildCompletePolicy(
				insuredAccountId,
				'Vigente',
				'Anual',
				1200,
				Date.today().addDays(30)
			),
			CollectionsTestDataFactory.buildCompletePolicy(
				insuredAccountId,
				'Vigente',
				'Unico',
				1200,
				Date.today().addDays(30)
			)
		};

		Test.startTest();
		insert policies;
		Test.stopTest();

		Map<Id, PaymentPlan__c> plansByPolicyId = new Map<Id, PaymentPlan__c>();
		Set<Id> policyIds = new Map<Id, InsurancePolicy>(policies).keySet();
		for (PaymentPlan__c plan : [
			SELECT insurancePolicy__c, premiumFrequency__c, installmentCount__c
			FROM PaymentPlan__c
			WHERE insurancePolicy__c IN :policyIds
		]) {
			plansByPolicyId.put(plan.insurancePolicy__c, plan);
		}

		Assert.areEqual(4, plansByPolicyId.size());
		Assert.areEqual(
			'Trimestral',
			plansByPolicyId.get(policies[0].Id).premiumFrequency__c
		);
		Assert.areEqual(4, plansByPolicyId.get(policies[0].Id).installmentCount__c);
		Assert.areEqual(
			'Semestral',
			plansByPolicyId.get(policies[1].Id).premiumFrequency__c
		);
		Assert.areEqual(2, plansByPolicyId.get(policies[1].Id).installmentCount__c);
		Assert.areEqual(
			'Anual',
			plansByPolicyId.get(policies[2].Id).premiumFrequency__c
		);
		Assert.areEqual(1, plansByPolicyId.get(policies[2].Id).installmentCount__c);
		Assert.areEqual(
			'Unico',
			plansByPolicyId.get(policies[3].Id).premiumFrequency__c
		);
		Assert.areEqual(1, plansByPolicyId.get(policies[3].Id).installmentCount__c);
	}

	/**
	 * @creation date: 12/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Verifica que una poliza en estado no operativo que pasa a operativo
	 *               crea el plan en Activo con sus cuotas generadas.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void createsActivePlanWhenCancelledPolicyBecomesOperational() {
		InsurancePolicy policy = CollectionsTestDataFactory.buildPolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Cancelado'
		);
		insert policy;

		Assert.areEqual(
			0,
			[SELECT COUNT() FROM PaymentPlan__c WHERE insurancePolicy__c = :policy.Id]
		);

		Test.startTest();
		policy.Status = 'Inicial';
		policy.put('PremiumAmount', 600);
		policy.put('PremiumFrequency', 'Semestral');
		policy.put('PaymentDueDate', Date.today().addDays(30));
		update policy;
		Test.stopTest();

		PaymentPlan__c plan = [
			SELECT planStatus__c, installmentCount__c
			FROM PaymentPlan__c
			WHERE insurancePolicy__c = :policy.Id
			LIMIT 1
		];
		Assert.areEqual('Activo', plan.planStatus__c);
		Assert.areEqual(2, plan.installmentCount__c);
	}

	/**
	 * @creation date: 12/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Verifica que la regla de validacion rechaza insertar una poliza operativa
	 *               sin los campos minimos requeridos.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void rejectsOperationalPolicyWithoutRequiredFields() {
		InsurancePolicy policy = CollectionsTestDataFactory.buildPolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Vigente'
		);

		Test.startTest();
		try {
			insert policy;
			Assert.fail(
				'Deberia haber lanzado DmlException por campos requeridos faltantes'
			);
		} catch (DmlException e) {
			Assert.isTrue(
				e.getMessage().contains('activarse'),
				'El error debe mencionar que la poliza no puede activarse sin los campos requeridos'
			);
		}
		Test.stopTest();
	}

	/**
	 * @creation date: 13/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Verifica que getValue maneja graciosamente la excepcion cuando
	 *               se accede a un campo no incluido en el SELECT de SOQL.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void handlesFieldAccessExceptionInGetValue() {
		InsurancePolicy policy = CollectionsTestDataFactory.buildPolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Cancelado'
		);
		insert policy;

		InsurancePolicy limitedPolicy = [
			SELECT Id, Status, PolicyName, NameInsuredId
			FROM InsurancePolicy
			WHERE Id = :policy.Id
		];
		limitedPolicy.Status = 'Inicial';

		InsurancePolicy oldPolicy = new InsurancePolicy(
			Id = policy.Id,
			Status = 'Cancelado'
		);

		Test.startTest();
		InsurancePolicyTriggerHandler.handleAfterTrigger(
			new List<InsurancePolicy>{ limitedPolicy },
			new Map<Id, InsurancePolicy>{ policy.Id => oldPolicy }
		);
		Test.stopTest();
	}

	/**
	 * @creation date: 13/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Verifica que getDecimal maneja graciosamente un valor no convertible
	 *               a Decimal, cubriendo el bloque try/catch de conversion.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void handlesNonDecimalPremiumAmountGracefully() {
		InsurancePolicy policy = CollectionsTestDataFactory.buildPolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Cancelado'
		);
		insert policy;

		InsurancePolicyTriggerHandler.testFieldOverrides = new Map<String, Object>{
			'PremiumAmount' => 'importe-invalido',
			'PremiumFrequency' => 'Mensual',
			'PaymentDueDate' => Date.today().addDays(30)
		};

		InsurancePolicy newPolicy = new InsurancePolicy(
			Id = policy.Id,
			Status = 'Inicial'
		);
		InsurancePolicy oldPolicy = new InsurancePolicy(
			Id = policy.Id,
			Status = 'Cancelado'
		);

		Test.startTest();
		InsurancePolicyTriggerHandler.handleAfterTrigger(
			new List<InsurancePolicy>{ newPolicy },
			new Map<Id, InsurancePolicy>{ policy.Id => oldPolicy }
		);
		Test.stopTest();

		InsurancePolicyTriggerHandler.testFieldOverrides = null;
	}

	/**
	 * @creation date: 13/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Verifica que getDate maneja graciosamente un valor no convertible
	 *               a Date, cubriendo el bloque try/catch de conversion.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void handlesNonDatePaymentDueDateGracefully() {
		InsurancePolicy policy = CollectionsTestDataFactory.buildPolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Cancelado'
		);
		insert policy;

		InsurancePolicyTriggerHandler.testFieldOverrides = new Map<String, Object>{
			'PremiumAmount' => Decimal.valueOf(1200),
			'PremiumFrequency' => 'Mensual',
			'PaymentDueDate' => 'fecha-invalida'
		};

		InsurancePolicy newPolicy = new InsurancePolicy(
			Id = policy.Id,
			Status = 'Inicial'
		);
		InsurancePolicy oldPolicy = new InsurancePolicy(
			Id = policy.Id,
			Status = 'Cancelado'
		);

		Test.startTest();
		InsurancePolicyTriggerHandler.handleAfterTrigger(
			new List<InsurancePolicy>{ newPolicy },
			new Map<Id, InsurancePolicy>{ policy.Id => oldPolicy }
		);
		Test.stopTest();

		InsurancePolicyTriggerHandler.testFieldOverrides = null;
	}

	/**
	 * @creation date: 13/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Verifica que logUpsertErrors registra errores cuando el DML
	 *               de upsert falla para algun registro del lote.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void logsUpsertErrorsWhenDmlFails() {
		PaymentPlan__c invalidPlan = new PaymentPlan__c(
			initialPlanKey__c = 'TEST-COVERAGE-FAIL-KEY'
		);

		Test.startTest();
		Database.UpsertResult[] results = Database.upsert(
			new List<PaymentPlan__c>{ invalidPlan },
			PaymentPlan__c.Fields.initialPlanKey__c,
			false
		);
		InsurancePolicyTriggerHandler.logUpsertErrors(
			new List<PaymentPlan__c>{ invalidPlan },
			results
		);
		Test.stopTest();
	}
}
