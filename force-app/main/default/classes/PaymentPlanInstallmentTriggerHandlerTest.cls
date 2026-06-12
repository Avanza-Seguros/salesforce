/**
 *   @name: PaymentPlanInstallmentTriggerHandlerTest
 *   @version: 1.0
 *   @creation date: 11/06/2026
 *   @author: Javier Torres - Volestra
 *   @description: Valida el recalculo de planStatus__c segun el estado de las cuotas:
 *                 todas satisfechas -> Completado; con cuota abierta -> Activo; estados
 *                 protegidos no se tocan; plan sin cuotas se respeta; borde todas
 *                 canceladas no completa; reapertura vuelve a Activo; y procesamiento en
 *                 lote de multiples planes.
 */
@IsTest
private class PaymentPlanInstallmentTriggerHandlerTest {
	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	@IsTest
	static void allReconciledMarksCompleted() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-PS-001', accountId);
		PaymentPlan__c plan = prepPlan(policy.Id, 'Activo');
		PaymentPlanInstallment__c i1 = addInstallment(plan.Id, 1, 100, 'Pendiente');
		PaymentPlanInstallment__c i2 = addInstallment(plan.Id, 2, 100, 'Pendiente');

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

		Assert.areEqual('Completado', queryPlanStatus(plan.Id));
	}

	@IsTest
	static void openInstallmentKeepsActive() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-PS-002', accountId);
		PaymentPlan__c plan = prepPlan(policy.Id, 'Activo');
		PaymentPlanInstallment__c i1 = addInstallment(plan.Id, 1, 100, 'Pendiente');
		addInstallment(plan.Id, 2, 100, 'Pendiente');

		// Solo una cuota se concilia; la otra sigue Pendiente (p. ej. pago parcial).
		update new PaymentPlanInstallment__c(
			Id = i1.Id,
			installmentStatus__c = 'Conciliado'
		);

		Assert.areEqual(
			'Activo',
			queryPlanStatus(plan.Id),
			'Con una cuota abierta el plan no debe completarse'
		);
	}

	@IsTest
	static void draftBecomesActiveWhenInstallmentAdded() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-PS-003', accountId);
		PaymentPlan__c plan = prepPlan(policy.Id, 'Borrador');

		// El insert de una cuota Pendiente debe mover el plan de Borrador a Activo.
		addInstallment(plan.Id, 1, 100, 'Pendiente');

		Assert.areEqual('Activo', queryPlanStatus(plan.Id));
	}

	@IsTest
	static void protectedReplacedPlanNotRecalculated() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-PS-004', accountId);
		PaymentPlan__c plan = prepPlan(policy.Id, 'Reemplazado');
		PaymentPlanInstallment__c i1 = addInstallment(plan.Id, 1, 100, 'Pendiente');
		PaymentPlanInstallment__c i2 = addInstallment(plan.Id, 2, 100, 'Pendiente');

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

		Assert.areEqual(
			'Reemplazado',
			queryPlanStatus(plan.Id),
			'Un plan reemplazado no debe recalcularse'
		);
	}

	@IsTest
	static void allCancelledDoesNotComplete() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-PS-005', accountId);
		PaymentPlan__c plan = prepPlan(policy.Id, 'Activo');
		PaymentPlanInstallment__c i1 = addInstallment(plan.Id, 1, 100, 'Pendiente');
		PaymentPlanInstallment__c i2 = addInstallment(plan.Id, 2, 100, 'Pendiente');

		// Todas canceladas, ninguna conciliada: no debe marcarse Completado.
		update new List<PaymentPlanInstallment__c>{
			new PaymentPlanInstallment__c(
				Id = i1.Id,
				installmentStatus__c = 'Cancelado'
			),
			new PaymentPlanInstallment__c(
				Id = i2.Id,
				installmentStatus__c = 'Cancelado'
			)
		};

		Assert.areEqual(
			'Activo',
			queryPlanStatus(plan.Id),
			'Sin ninguna cuota conciliada el plan no se completa'
		);
	}

	@IsTest
	static void reopenedInstallmentReturnsPlanToActive() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-PS-006', accountId);
		PaymentPlan__c plan = prepPlan(policy.Id, 'Activo');
		PaymentPlanInstallment__c i1 = addInstallment(plan.Id, 1, 100, 'Pendiente');
		PaymentPlanInstallment__c i2 = addInstallment(plan.Id, 2, 100, 'Pendiente');

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
		Assert.areEqual('Completado', queryPlanStatus(plan.Id));

		// Se reabre una cuota -> el plan debe volver a Activo.
		update new PaymentPlanInstallment__c(
			Id = i1.Id,
			installmentStatus__c = 'Pendiente'
		);
		Assert.areEqual('Activo', queryPlanStatus(plan.Id));
	}

	@IsTest
	static void planWithoutInstallmentsIsLeftUnchanged() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = createPolicy('POL-PS-007', accountId);
		PaymentPlan__c plan = prepPlan(policy.Id, 'Borrador');

		Test.startTest();
		PaymentPlanInstallmentTriggerHandler.recalculatePlans(
			new Set<Id>{ plan.Id }
		);
		Test.stopTest();

		Assert.areEqual(
			'Borrador',
			queryPlanStatus(plan.Id),
			'Un plan sin cuotas no se recalcula'
		);
	}

	@IsTest
	static void bulkRecalculatesMultiplePlans() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policyA = createPolicy('POL-PS-008A', accountId);
		InsurancePolicy policyB = createPolicy('POL-PS-008B', accountId);
		PaymentPlan__c planA = prepPlan(policyA.Id, 'Activo');
		PaymentPlan__c planB = prepPlan(policyB.Id, 'Activo');
		PaymentPlanInstallment__c a1 = addInstallment(
			planA.Id,
			1,
			100,
			'Pendiente'
		);
		PaymentPlanInstallment__c b1 = addInstallment(
			planB.Id,
			1,
			100,
			'Pendiente'
		);

		update new List<PaymentPlanInstallment__c>{
			new PaymentPlanInstallment__c(
				Id = a1.Id,
				installmentStatus__c = 'Conciliado'
			),
			new PaymentPlanInstallment__c(
				Id = b1.Id,
				installmentStatus__c = 'Conciliado'
			)
		};

		Assert.areEqual('Completado', queryPlanStatus(planA.Id));
		Assert.areEqual('Completado', queryPlanStatus(planB.Id));
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

	private static PaymentPlan__c prepPlan(Id policyId, String status) {
		delete [
			SELECT Id
			FROM PaymentPlanInstallment__c
			WHERE paymentPlan__r.insurancePolicy__c = :policyId
		];
		delete [SELECT Id FROM PaymentPlan__c WHERE insurancePolicy__c = :policyId];
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
		Decimal amount,
		String status
	) {
		PaymentPlanInstallment__c inst = new PaymentPlanInstallment__c(
			paymentPlan__c = planId,
			sequenceNumber__c = seq,
			dueDate__c = Date.today().addDays(30 * seq),
			expectedAmount__c = amount,
			installmentStatus__c = status
		);
		insert inst;
		return inst;
	}

	private static String queryPlanStatus(Id planId) {
		return [SELECT planStatus__c FROM PaymentPlan__c WHERE Id = :planId]
		.planStatus__c;
	}
}
