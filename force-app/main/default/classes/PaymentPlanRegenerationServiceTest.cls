@IsTest
private class PaymentPlanRegenerationServiceTest {
	private static final String EVENT_REGENERATED = 'PAYMENT_PLAN_REGENERATED';
	private static final String EVENT_FAILED = 'PAYMENT_PLAN_REGENERATION_FAILED';

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
	 * @description: CA1/CA2. Una poliza que nacio Anual con lo cotizado y cuya primera cuota
	 *               vence en el futuro pasa a Semestral sin error: el mismo plan se rehace con
	 *               dos cuotas. Hoy este guardado se rechazaba con el mensaje de la proxima
	 *               fecha de cobro pendiente.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void regeneratesPlanWithoutCollectionsWhenFrequencyChanges() {
		Date firstDueDate = Date.today().addDays(10);
		InsurancePolicy policy = createPolicy('Anual', 12000, firstDueDate);
		PaymentPlan__c originalPlan = CollectionsTestDataFactory.getActivePlan(
			policy.Id
		);
		Set<Id> originalInstallmentIds = installmentIds(policy.Id);

		Test.startTest();
		policy.PremiumFrequency = 'Semestral';
		update policy;
		Test.stopTest();

		PaymentPlan__c plan = loadPlan(originalPlan.Id);
		List<PaymentPlanInstallment__c> installments = CollectionsTestDataFactory.getInstallmentsByPolicy(
			policy.Id
		);

		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM PaymentPlan__c
				WHERE insurancePolicy__c = :policy.Id
			],
			'Se rehace el mismo plan: no se crea uno de reemplazo'
		);
		Assert.areEqual('Inicial', plan.planType__c);
		Assert.areEqual('Activo', plan.planStatus__c);
		Assert.areEqual('Semestral', plan.premiumFrequency__c);
		Assert.areEqual(2, plan.installmentCount__c);
		Assert.areEqual(firstDueDate, plan.firstDueDate__c);
		Assert.areEqual(2, installments.size());
		Assert.areEqual(firstDueDate, installments[0].dueDate__c);
		Assert.areEqual(firstDueDate.addMonths(6), installments[1].dueDate__c);
		Assert.areEqual(
			Decimal.valueOf('6000.00'),
			installments[0].expectedAmount__c
		);
		Assert.areEqual(
			Decimal.valueOf('12000.00'),
			CollectionsTestDataFactory.sumExpectedAmounts(installments)
		);
		Assert.areEqual('Pendiente', installments[0].installmentStatus__c);

		// CA4: las cuotas anteriores desaparecen, no quedan canceladas.
		Set<Id> currentIds = installmentIds(policy.Id);
		currentIds.retainAll(originalInstallmentIds);
		Assert.isTrue(currentIds.isEmpty(), 'Las cuotas anteriores se borran');
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA3. Cambiar la prima rehace las cuotas con el importe nuevo; hoy el plan
	 *               conservaba en silencio el importe cotizado.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void regeneratesPlanWhenPremiumChanges() {
		InsurancePolicy policy = createPolicy(
			'Trimestral',
			4000,
			Date.today().addDays(5)
		);

		Test.startTest();
		policy.PremiumAmount = 4800;
		update policy;
		Test.stopTest();

		List<PaymentPlanInstallment__c> installments = CollectionsTestDataFactory.getInstallmentsByPolicy(
			policy.Id
		);

		Assert.areEqual(4, installments.size());
		Assert.areEqual(
			Decimal.valueOf('1200.00'),
			installments[0].expectedAmount__c
		);
		Assert.areEqual(
			Decimal.valueOf('4800.00'),
			CollectionsTestDataFactory.sumExpectedAmounts(installments)
		);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA3. Cambiar la fecha de pago mueve todo el calendario y el resumen de
	 *               cobranza de la poliza la sigue sin volver a rehacer el plan.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void regeneratesPlanWhenPaymentDueDateChanges() {
		InsurancePolicy policy = createPolicy(
			'Mensual',
			1200,
			Date.today().addDays(5)
		);
		Date newFirstDueDate = Date.today().addDays(20);

		Test.startTest();
		policy.PaymentDueDate = newFirstDueDate;
		update policy;
		Test.stopTest();

		List<PaymentPlanInstallment__c> installments = CollectionsTestDataFactory.getInstallmentsByPolicy(
			policy.Id
		);
		InsurancePolicy saved = [
			SELECT PaymentDueDate
			FROM InsurancePolicy
			WHERE Id = :policy.Id
		];

		Assert.areEqual(12, installments.size());
		Assert.areEqual(newFirstDueDate, installments[0].dueDate__c);
		Assert.areEqual(newFirstDueDate.addMonths(11), installments[11].dueDate__c);
		Assert.areEqual(newFirstDueDate, saved.PaymentDueDate.dateGmt());
		Assert.areEqual(
			1,
			countLogs(policy.Id, EVENT_REGENERATED),
			'El resumen de cobranza mueve PaymentDueDate y no debe rehacer el plan otra vez'
		);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA4. La regeneracion queda en el registro de la aplicacion con la poliza,
	 *               los datos anteriores y los nuevos.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void logsPreviousAndNewTerms() {
		InsurancePolicy policy = createPolicy(
			'Anual',
			12000,
			Date.today().addDays(10)
		);

		Test.startTest();
		policy.PremiumFrequency = 'Semestral';
		update policy;
		Test.stopTest();

		AppLog__c log = [
			SELECT severity__c, stage__c, message__c
			FROM AppLog__c
			WHERE recordId__c = :policy.Id AND eventCode__c = :EVENT_REGENERATED
			LIMIT 1
		];

		Assert.areEqual('Informacion', log.severity__c);
		Assert.areEqual('Plan de pagos', log.stage__c);
		Assert.isTrue(log.message__c.contains('Antes: Anual'), log.message__c);
		Assert.isTrue(log.message__c.contains('Ahora: Semestral'), log.message__c);
		Assert.isTrue(log.message__c.contains('2 cuotas'), log.message__c);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA5/CA6. Un plan con una cuota conciliada no se rehace: se aplican las
	 *               reglas de hoy y se sigue rechazando el cambio antes de la proxima cuota.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void keepsCurrentRulesWhenPlanHasReconciledInstallment() {
		InsurancePolicy policy = createPolicy(
			'Semestral',
			1200,
			Date.today().addMonths(-4)
		);
		List<PaymentPlanInstallment__c> installments = CollectionsTestDataFactory.getInstallmentsByPolicy(
			policy.Id
		);
		installments[0].installmentStatus__c = 'Conciliado';
		update installments[0];
		Set<Id> originalInstallmentIds = installmentIds(policy.Id);

		Test.startTest();
		policy.PremiumFrequency = 'Mensual';
		Boolean threwException = false;

		try {
			update policy;
		} catch (DmlException e) {
			threwException = true;
			Assert.isTrue(
				e.getMessage().contains('proxima fecha de cobro pendiente'),
				e.getMessage()
			);
		}

		Test.stopTest();

		Assert.isTrue(threwException, 'Un plan con historia sigue protegido');
		Assert.areEqual(originalInstallmentIds, installmentIds(policy.Id));
		Assert.areEqual(0, countLogs(policy.Id, EVENT_REGENERATED));
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA5. Una cuota condonada ya es historia del plan (una decision sobre la
	 *               deuda): el plan no se rehace y el cambio sigue las reglas de hoy.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void keepsCurrentRulesWhenInstallmentWasForgiven() {
		InsurancePolicy policy = createPolicy(
			'Semestral',
			1200,
			Date.today().addDays(10)
		);
		List<PaymentPlanInstallment__c> installments = CollectionsTestDataFactory.getInstallmentsByPolicy(
			policy.Id
		);
		installments[0].installmentStatus__c = 'Condonado';
		update installments[0];

		Test.startTest();
		policy.PremiumFrequency = 'Mensual';
		Boolean threwException = false;

		try {
			update policy;
		} catch (DmlException e) {
			threwException = true;
			Assert.isTrue(
				e.getMessage().contains('proxima fecha de cobro pendiente'),
				e.getMessage()
			);
		}

		Test.stopTest();

		Assert.isTrue(threwException);
		Assert.isTrue(
			PaymentPlanRegenerationService.selectPoliciesWithoutCollections(
					new Set<Id>{ policy.Id }
				)
				.isEmpty()
		);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA5. En un plan con historia, cambiar la prima sigue sin tocar el plan,
	 *               igual que hoy (ajustarlo es la KAN-447).
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void doesNotTouchPlanWithHistoryWhenPremiumChanges() {
		InsurancePolicy policy = createPolicy(
			'Semestral',
			1200,
			Date.today().addMonths(-4)
		);
		List<PaymentPlanInstallment__c> installments = CollectionsTestDataFactory.getInstallmentsByPolicy(
			policy.Id
		);
		installments[0].installmentStatus__c = 'Conciliado';
		update installments[0];
		Set<Id> originalInstallmentIds = installmentIds(policy.Id);

		Test.startTest();
		policy.PremiumAmount = 1500;
		update policy;
		Test.stopTest();

		Assert.areEqual(originalInstallmentIds, installmentIds(policy.Id));
		Assert.areEqual(
			Decimal.valueOf('1200.00'),
			CollectionsTestDataFactory.sumExpectedAmounts(
				CollectionsTestDataFactory.getInstallmentsByPolicy(policy.Id)
			)
		);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA7. Rehabilitar una poliza cancelada no rehace su plan ni recrea cuotas,
	 *               aunque el plan no haya cobrado nada.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void doesNotRegenerateWhenPolicyIsReinstated() {
		InsurancePolicy policy = createPolicy(
			'Semestral',
			1200,
			Date.today().addDays(10)
		);
		policy.Status = 'Cancelado';
		update policy;
		Set<Id> originalInstallmentIds = installmentIds(policy.Id);

		Test.startTest();
		policy.Status = 'Vigente';
		update policy;
		Test.stopTest();

		Assert.areEqual(originalInstallmentIds, installmentIds(policy.Id));
		Assert.areEqual(0, countLogs(policy.Id, EVENT_REGENERATED));
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA8. Guardar otra vez la poliza con los mismos valores no cambia nada.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void savingSameValuesTwiceChangesNothing() {
		InsurancePolicy policy = createPolicy(
			'Anual',
			12000,
			Date.today().addDays(10)
		);
		policy.PremiumFrequency = 'Semestral';
		update policy;
		Set<Id> regeneratedIds = installmentIds(policy.Id);

		Test.startTest();
		update policy;
		Test.stopTest();

		Assert.areEqual(regeneratedIds, installmentIds(policy.Id));
		Assert.areEqual(1, countLogs(policy.Id, EVENT_REGENERATED));
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA9. Si el plan de una poliza del lote no se puede rehacer, las demas se
	 *               rehacen y el fallo queda registrado con la poliza y el motivo. La poliza
	 *               que fallo conserva sus cuotas.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void failureOnOnePolicyDoesNotStopTheOthers() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		List<InsurancePolicy> policies = new List<InsurancePolicy>{
			CollectionsTestDataFactory.buildCompletePolicy(
				accountId,
				'Inicial',
				'Anual',
				12000,
				Date.today().addDays(10)
			),
			CollectionsTestDataFactory.buildCompletePolicy(
				accountId,
				'Inicial',
				'Anual',
				12000,
				Date.today().addDays(10)
			)
		};
		insert policies;
		InsurancePolicy failing = policies[0];
		InsurancePolicy healthy = policies[1];
		Set<Id> failingInstallmentIds = installmentIds(failing.Id);
		PaymentPlanRegenerationService.failForTest.add(failing.Id);

		Test.startTest();
		for (InsurancePolicy policy : policies) {
			policy.PremiumFrequency = 'Semestral';
		}
		update policies;
		Test.stopTest();

		Assert.areEqual(2, installmentIds(healthy.Id).size());
		Assert.areEqual(1, countLogs(healthy.Id, EVENT_REGENERATED));
		Assert.areEqual(failingInstallmentIds, installmentIds(failing.Id));
		Assert.areEqual(1, countLogs(failing.Id, EVENT_FAILED));
		Assert.areEqual(0, countLogs(failing.Id, EVENT_REGENERATED));
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Una frecuencia que la cobranza no soporta se sigue rechazando aunque el
	 *               plan no haya cobrado nada, y el plan no se toca.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void rejectsUnsupportedFrequencyWithoutTouchingThePlan() {
		InsurancePolicy policy = createPolicy(
			'Anual',
			12000,
			Date.today().addDays(10)
		);
		Set<Id> originalInstallmentIds = installmentIds(policy.Id);

		Test.startTest();
		policy.PremiumFrequency = 'Quincenal';
		Boolean threwException = false;

		try {
			update policy;
		} catch (DmlException e) {
			threwException = true;
			Assert.isTrue(
				e.getMessage().contains('no esta soportada'),
				e.getMessage()
			);
		}

		Test.stopTest();

		Assert.isTrue(threwException);
		Assert.areEqual(originalInstallmentIds, installmentIds(policy.Id));
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Mientras la regeneracion esta suspendida (guardados del propio motor), un
	 *               cambio no rehace el plan y sigue las reglas de siempre.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void doesNotRegenerateWhileSuspended() {
		InsurancePolicy policy = createPolicy(
			'Anual',
			12000,
			Date.today().addDays(10)
		);
		Set<Id> originalInstallmentIds = installmentIds(policy.Id);

		Test.startTest();
		PaymentPlanRegenerationService.suspend();
		policy.PremiumAmount = 15000;
		update policy;
		PaymentPlanRegenerationService.resume();
		Test.stopTest();

		Assert.areEqual(originalInstallmentIds, installmentIds(policy.Id));
		Assert.areEqual(0, countLogs(policy.Id, EVENT_REGENERATED));
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Una poliza recien creada, sin ningun cobro, cuenta como plan sin cobros.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void newPolicyHasNoCollections() {
		InsurancePolicy policy = createPolicy(
			'Anual',
			12000,
			Date.today().addDays(10)
		);

		Test.startTest();
		Set<Id> result = PaymentPlanRegenerationService.selectPoliciesWithoutCollections(
			new Set<Id>{ policy.Id }
		);
		Set<Id> empty = PaymentPlanRegenerationService.selectPoliciesWithoutCollections(
			null
		);
		Test.stopTest();

		Assert.isTrue(result.contains(policy.Id));
		Assert.isTrue(empty.isEmpty());
	}

	private static InsurancePolicy createPolicy(
		String frequency,
		Decimal premium,
		Date firstDueDate
	) {
		return CollectionsTestDataFactory.createOperationalPolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			frequency,
			premium,
			firstDueDate
		);
	}

	private static PaymentPlan__c loadPlan(Id planId) {
		return [
			SELECT
				planType__c,
				planStatus__c,
				premiumFrequency__c,
				expectedTotalAmount__c,
				firstDueDate__c,
				installmentCount__c
			FROM PaymentPlan__c
			WHERE Id = :planId
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
