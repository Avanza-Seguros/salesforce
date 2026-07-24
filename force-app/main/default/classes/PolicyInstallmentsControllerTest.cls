/**
 *   @name: PolicyInstallmentsControllerTest
 *   @version: 1.0
 *   @creation date: 20/07/2026
 *   @author: Javier Torres - Volestra
 *   @description: Valida que el controlador de cuotas de la pagina de InsurancePolicy
 *                 devuelva las cuotas de los planes de la poliza (relacion de dos
 *                 niveles) y maneje el caso sin poliza.
 */
@IsTest
private class PolicyInstallmentsControllerTest {
	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	@IsTest
	static void returnsInstallmentsOfThePolicy() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = new InsurancePolicy(
			Name = 'POL-LWC-001',
			PolicyName = 'POL-LWC-001',
			NameInsuredId = accountId,
			Status = 'Inicial',
			PremiumAmount = 1200,
			PremiumFrequency = 'Mensual',
			PaymentDueDate = Date.today()
		);
		insert policy;

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

		List<PaymentPlanInstallment__c> installments = new List<PaymentPlanInstallment__c>();
		for (Integer i = 1; i <= 3; i++) {
			installments.add(
				new PaymentPlanInstallment__c(
					paymentPlan__c = plan.Id,
					sequenceNumber__c = i,
					dueDate__c = Date.today().addMonths(i),
					expectedAmount__c = 400,
					installmentStatus__c = 'Pendiente'
				)
			);
		}
		insert installments;

		Test.startTest();
		List<PaymentPlanInstallment__c> rows = PolicyInstallmentsController.getInstallmentsByPolicy(
			policy.Id
		);
		List<PaymentPlanInstallment__c> none = PolicyInstallmentsController.getInstallmentsByPolicy(
			null
		);
		Test.stopTest();

		Assert.areEqual(3, rows.size(), 'Debe traer las 3 cuotas de la poliza');
		Assert.areEqual(1, rows[0].sequenceNumber__c, 'Ordenadas por secuencia');
		Assert.isNotNull(rows[0].paymentPlan__r.Name, 'Trae el plan padre');
		Assert.areEqual(0, none.size(), 'Sin poliza devuelve lista vacia');
	}
}