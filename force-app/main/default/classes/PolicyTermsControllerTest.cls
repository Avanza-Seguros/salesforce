/**
 *   @name: PolicyTermsControllerTest
 *   @version: 1.0
 *   @creation date: 02/11/2026
 *   @author: Javier Torres - Volestra
 *   @description: Valida que la pestaña Vigencias reciba la cadena entera de vigencias de
 *                 una póliza, en los dos sentidos y en orden, con lo pagado, lo pendiente,
 *                 los documentos y el cambio de número de cada una.
 */
@IsTest
private class PolicyTermsControllerTest {
	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	private static InsurancePolicy buildTerm(Integer startYear, Id previousId) {
		InsurancePolicy policy = CollectionsTestDataFactory.buildCompletePolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Inicial',
			'Mensual',
			1200,
			Date.newInstance(startYear, 1, 15)
		);
		policy.EffectiveDate = Datetime.newInstanceGmt(startYear, 1, 15);
		policy.ExpirationDate = Datetime.newInstanceGmt(startYear + 1, 1, 15);
		policy.PriorPolicyId = previousId;
		return policy;
	}

	private static Map<Id, PolicyTermsController.Term> byPolicy(
		List<PolicyTermsController.Term> terms
	) {
		Map<Id, PolicyTermsController.Term> result = new Map<Id, PolicyTermsController.Term>();
		for (PolicyTermsController.Term term : terms) {
			result.put(term.policyId, term);
		}
		return result;
	}

	@IsTest
	static void returnsTheWholeChainFromAMiddleTerm() {
		InsurancePolicy oldest = buildTerm(2024, null);
		insert oldest;
		InsurancePolicy middle = buildTerm(2025, oldest.Id);
		insert middle;
		InsurancePolicy newest = buildTerm(2026, middle.Id);
		insert newest;
		insert new ContentVersion(
			Title = 'Caratula',
			PathOnClient = 'caratula.pdf',
			VersionData = Blob.valueOf('pdf'),
			FirstPublishLocationId = middle.Id
		);

		Test.startTest();
		List<PolicyTermsController.Term> terms = PolicyTermsController.getTermsByPolicy(
			middle.Id
		);
		Test.stopTest();

		Assert.areEqual(3, terms.size(), 'Trae las anteriores y las posteriores');
		Assert.areEqual(newest.Id, terms[0].policyId, 'La más reciente primero');
		Assert.areEqual(middle.Id, terms[1].policyId);
		Assert.areEqual(oldest.Id, terms[2].policyId, 'La más antigua al final');

		Map<Id, PolicyTermsController.Term> byId = byPolicy(terms);
		Assert.isTrue(byId.get(middle.Id).isCurrent, 'Marca la que se está viendo');
		Assert.isFalse(byId.get(newest.Id).isCurrent);
		Assert.areEqual(1, byId.get(middle.Id).documentCount);
		Assert.areEqual(0, byId.get(newest.Id).documentCount);
		Assert.isTrue(
			byId.get(newest.Id).renumbered,
			'Un número distinto al de la anterior es una renumeración'
		);
		Assert.areEqual(
			[SELECT Name FROM InsurancePolicy WHERE Id = :middle.Id].Name,
			byId.get(newest.Id).previousNumber
		);
		Assert.isFalse(
			byId.get(oldest.Id).hasPrevious,
			'La primera registrada no tiene anterior'
		);
		Assert.isFalse(byId.get(oldest.Id).renumbered);
		Assert.isNotNull(byId.get(oldest.Id).period, 'Trae el período');
	}

	@IsTest
	static void amountsLeaveOutClosedAndReplacedInstallments() {
		InsurancePolicy policy = buildTerm(2026, null);
		insert policy;
		PaymentPlan__c plan = CollectionsTestDataFactory.getActivePlan(policy.Id);
		List<PaymentPlanInstallment__c> generated = CollectionsTestDataFactory.getInstallmentsByPlan(
			plan.Id
		);
		if (!generated.isEmpty()) {
			delete generated;
		}
		PaymentPlanInstallment__c replaced = new PaymentPlanInstallment__c(
			paymentPlan__c = plan.Id,
			sequenceNumber__c = 1,
			dueDate__c = Date.newInstance(2026, 1, 15),
			expectedAmount__c = 700,
			installmentStatus__c = 'Pendiente'
		);
		insert replaced;
		insert new List<PaymentPlanInstallment__c>{
			new PaymentPlanInstallment__c(
				paymentPlan__c = plan.Id,
				sequenceNumber__c = 2,
				dueDate__c = Date.newInstance(2026, 1, 15),
				expectedAmount__c = 400,
				installmentStatus__c = 'Pendiente',
				replacesInstallment__c = replaced.Id
			),
			new PaymentPlanInstallment__c(
				paymentPlan__c = plan.Id,
				sequenceNumber__c = 3,
				dueDate__c = Date.newInstance(2026, 7, 15),
				expectedAmount__c = 999,
				installmentStatus__c = 'Cancelado'
			)
		};

		Test.startTest();
		List<PolicyTermsController.Term> terms = PolicyTermsController.getTermsByPolicy(
			policy.Id
		);
		Test.stopTest();

		Assert.areEqual(
			1,
			terms.size(),
			'Una póliza sin cadena es su única vigencia'
		);
		Assert.isTrue(terms[0].isCurrent);
		Assert.areEqual(
			400,
			terms[0].outstanding,
			'Solo cuenta la cuota viva: ni la reemplazada ni la cancelada'
		);
		Assert.areEqual(0, terms[0].paid);
	}

	@IsTest
	static void withoutPolicyReturnsNothing() {
		Assert.areEqual(0, PolicyTermsController.getTermsByPolicy(null).size());
	}
}
