/**
 *   @name: PolicyCollectionSummaryServiceTest
 *   @version: 1.0
 *   @creation date: 12/06/2026
 *   @author: Javier Torres - Volestra
 *   @description: Valida el resumen de cobranza en InsurancePolicy: sin plan vigente o
 *                 sin pagos -> Sin pago; con cuota abierta a futuro -> Al dia/Sin pago y
 *                 proxima fecha; con cuota abierta vencida -> Vencido; plan completado ->
 *                 Completado sin proxima fecha; lote de polizas; y el enganche end-to-end
 *                 desde el trigger de cuotas (historia 188).
 */
@IsTest
private class PolicyCollectionSummaryServiceTest {
	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	@IsTest
	static void noVigentePlanSetsSinPago() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-CS-001', accountId);
		deleteCollectionData(policy.Id);

		Test.startTest();
		PolicyCollectionSummaryService.recalculate(new Set<Id>{ policy.Id });
		Test.stopTest();

		InsurancePolicy updated = queryPolicy(policy.Id);
		Assert.areEqual('Sin pago', updated.collectionPaymentStatus__c);
		Assert.isNull(updated.PaidToDate);
		Assert.isNull(updated.collectionNextDueDate__c);
	}

	@IsTest
	static void pendingOnlySetsSinPagoWithNextDue() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-CS-002', accountId);
		PaymentPlan__c plan = prepPlan(policy.Id, 'Activo');
		Date due1 = Date.today().addDays(10);
		addInstallment(plan.Id, 1, due1, 'Pendiente');
		addInstallment(plan.Id, 2, Date.today().addDays(40), 'Pendiente');

		PolicyCollectionSummaryService.recalculate(new Set<Id>{ policy.Id });

		InsurancePolicy updated = queryPolicy(policy.Id);
		Assert.areEqual('Sin pago', updated.collectionPaymentStatus__c);
		Assert.isNull(updated.PaidToDate);
		Assert.areEqual(due1, updated.collectionNextDueDate__c);
		Assert.areEqual(
			due1,
			updated.PaymentDueDate,
			'PaymentDueDate estandar tambien refleja la proxima cuota'
		);
	}

	@IsTest
	static void partialReconciledSetsAlDia() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-CS-003', accountId);
		PaymentPlan__c plan = prepPlan(policy.Id, 'Activo');
		Date paid = Date.today();
		Date next = Date.today().addDays(30);
		addInstallment(plan.Id, 1, paid, 'Conciliado');
		addInstallment(plan.Id, 2, next, 'Pendiente');

		PolicyCollectionSummaryService.recalculate(new Set<Id>{ policy.Id });

		InsurancePolicy updated = queryPolicy(policy.Id);
		Assert.areEqual('Al dia', updated.collectionPaymentStatus__c);
		Assert.areEqual(paid, updated.PaidToDate);
		Assert.areEqual(next, updated.collectionNextDueDate__c);
		Assert.areEqual(next, updated.PaymentDueDate);
	}

	@IsTest
	static void overdueOpenSetsVencido() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-CS-004', accountId);
		PaymentPlan__c plan = prepPlan(policy.Id, 'Activo');
		addInstallment(plan.Id, 1, Date.today().addDays(-60), 'Conciliado');
		addInstallment(plan.Id, 2, Date.today().addDays(-1), 'Pendiente');

		PolicyCollectionSummaryService.recalculate(new Set<Id>{ policy.Id });

		InsurancePolicy updated = queryPolicy(policy.Id);
		Assert.areEqual(
			'Vencido',
			updated.collectionPaymentStatus__c,
			'Una cuota abierta con vencimiento pasado marca Vencido'
		);
		Assert.areEqual(Date.today().addDays(-1), updated.collectionNextDueDate__c);
	}

	@IsTest
	static void completedPlanSetsCompletado() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-CS-005', accountId);
		PaymentPlan__c plan = prepPlan(policy.Id, 'Activo');
		Date last = Date.today();
		PaymentPlanInstallment__c i1 = addInstallment(
			plan.Id,
			1,
			Date.today().addDays(-30),
			'Pendiente'
		);
		PaymentPlanInstallment__c i2 = addInstallment(
			plan.Id,
			2,
			last,
			'Pendiente'
		);

		// Conciliar todas -> el trigger de la 188 marca el plan Completado.
		update new List<PaymentPlanInstallment__c>{
			new PaymentPlanInstallment__c(
				Id = i1.Id,
				installmentStatus__c = 'Conciliado'
			),
			new PaymentPlanInstallment__c(
				Id = i2.Id,
				installmentStatus__c = 'Conciliado'
			)
		};

		PolicyCollectionSummaryService.recalculate(new Set<Id>{ policy.Id });

		InsurancePolicy updated = queryPolicy(policy.Id);
		Assert.areEqual('Completado', updated.collectionPaymentStatus__c);
		Assert.areEqual(last, updated.PaidToDate);
		Assert.isNull(
			updated.collectionNextDueDate__c,
			'Un plan completado no tiene proxima fecha de pago'
		);
		Assert.isNotNull(
			updated.PaymentDueDate,
			'PaymentDueDate estandar no se vacia (regla PremiumFieldsRequired)'
		);
	}

	@IsTest
	static void bulkRecalculatesMultiplePolicies() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policyA = createPolicy('POL-CS-006A', accountId);
		InsurancePolicy policyB = createPolicy('POL-CS-006B', accountId);
		PaymentPlan__c planA = prepPlan(policyA.Id, 'Activo');
		PaymentPlan__c planB = prepPlan(policyB.Id, 'Activo');
		addInstallment(planA.Id, 1, Date.today(), 'Conciliado');
		addInstallment(planA.Id, 2, Date.today().addDays(30), 'Pendiente');
		addInstallment(planB.Id, 1, Date.today().addDays(20), 'Pendiente');

		PolicyCollectionSummaryService.recalculate(
			new Set<Id>{ policyA.Id, policyB.Id }
		);

		Assert.areEqual(
			'Al dia',
			queryPolicy(policyA.Id).collectionPaymentStatus__c
		);
		Assert.areEqual(
			'Sin pago',
			queryPolicy(policyB.Id).collectionPaymentStatus__c
		);
	}

	@IsTest
	static void triggerUpdatesPolicySummaryEndToEnd() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-CS-007', accountId);
		PaymentPlan__c plan = prepPlan(policy.Id, 'Activo');
		Date paid = Date.today();
		Date next = Date.today().addDays(30);
		PaymentPlanInstallment__c i1 = addInstallment(
			plan.Id,
			1,
			paid,
			'Pendiente'
		);
		addInstallment(plan.Id, 2, next, 'Pendiente');

		// Sin llamar al servicio: el trigger de la 188 debe encadenar el recalculo del resumen.
		update new PaymentPlanInstallment__c(
			Id = i1.Id,
			installmentStatus__c = 'Conciliado'
		);

		InsurancePolicy updated = queryPolicy(policy.Id);
		Assert.areEqual('Al dia', updated.collectionPaymentStatus__c);
		Assert.areEqual(paid, updated.PaidToDate);
		Assert.areEqual(next, updated.collectionNextDueDate__c);
		Assert.areEqual(next, updated.PaymentDueDate);
	}

	private static InsurancePolicy createPolicy(String name, Id accountId) {
		InsurancePolicy policy = new InsurancePolicy(
			Name = name,
			PolicyName = name,
			NameInsuredId = accountId,
			Status = 'Inicial',
			PremiumAmount = 1200,
			PremiumFrequency = 'Mensual',
			PaymentDueDate = Date.today()
		);
		insert policy;
		return policy;
	}

	private static void deleteCollectionData(Id policyId) {
		delete [
			SELECT Id
			FROM PaymentPlanInstallment__c
			WHERE paymentPlan__r.insurancePolicy__c = :policyId
		];
		delete [SELECT Id FROM PaymentPlan__c WHERE insurancePolicy__c = :policyId];
	}

	private static PaymentPlan__c prepPlan(Id policyId, String status) {
		deleteCollectionData(policyId);
		// Plan sin firstDueDate__c/installmentCount__c: no esta "listo", asi que el
		// trigger de PaymentPlan no auto-genera cuotas y el calendario lo arma el test.
		PaymentPlan__c plan = new PaymentPlan__c(
			insurancePolicy__c = policyId,
			planStatus__c = status,
			premiumFrequency__c = 'Mensual',
			expectedTotalAmount__c = 1200
		);
		insert plan;
		return plan;
	}

	private static PaymentPlanInstallment__c addInstallment(
		Id planId,
		Integer seq,
		Date dueDate,
		String status
	) {
		PaymentPlanInstallment__c inst = new PaymentPlanInstallment__c(
			paymentPlan__c = planId,
			sequenceNumber__c = seq,
			dueDate__c = dueDate,
			expectedAmount__c = 100,
			installmentStatus__c = status
		);
		insert inst;
		return inst;
	}

	private static InsurancePolicy queryPolicy(Id policyId) {
		return [
			SELECT
				PaidToDate,
				PaymentDueDate,
				collectionNextDueDate__c,
				collectionPaymentStatus__c
			FROM InsurancePolicy
			WHERE Id = :policyId
		];
	}
}
