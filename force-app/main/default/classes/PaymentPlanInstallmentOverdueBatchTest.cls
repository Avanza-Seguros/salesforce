/**
 *   @name: PaymentPlanInstallmentOverdueBatchTest
 *   @version: 1.0
 *   @creation date: 20/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Verifica el proceso diario que deja Vencido las cuotas: cuales pasa, cuales no
 *                 toca, que correrlo dos veces no cambia nada, que un fallo no detiene a las demas
 *                 y que se programa.
 */
@IsTest
private class PaymentPlanInstallmentOverdueBatchTest {
	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	/**
	 * @description: Pasan a Vencido solo las cuotas Pendiente con el vencimiento ya pasado. El
	 *               mismo dia del vencimiento siguen Pendiente, y las que ya no se deben o no
	 *               tienen fecha no se tocan.
	 */
	@IsTest
	static void marksOnlyPendingInstallmentsAlreadyDue() {
		Id planId = planWithoutInstallments();
		Date today = PolicyStatusService.todayInMexico();
		Id overdue = installment(planId, 1, today.addDays(-1), 'Pendiente');
		Id dueToday = installment(planId, 2, today, 'Pendiente');
		Id reconciled = installment(planId, 3, today.addDays(-5), 'Conciliado');
		Id cancelled = installment(planId, 4, today.addDays(-5), 'Cancelado');
		Id forgiven = installment(planId, 5, today.addDays(-5), 'Condonado');
		Id withoutDate = installment(planId, 6, null, 'Pendiente');

		Test.startTest();
		Database.executeBatch(new PaymentPlanInstallmentOverdueBatch());
		Test.stopTest();

		Map<Id, PaymentPlanInstallment__c> byId = installmentsById();
		Assert.areEqual('Vencido', byId.get(overdue).installmentStatus__c);
		Assert.areEqual(
			'Pendiente',
			byId.get(dueToday).installmentStatus__c,
			'El dia del vencimiento todavia no esta vencida'
		);
		Assert.areEqual('Conciliado', byId.get(reconciled).installmentStatus__c);
		Assert.areEqual('Cancelado', byId.get(cancelled).installmentStatus__c);
		Assert.areEqual('Condonado', byId.get(forgiven).installmentStatus__c);
		Assert.areEqual(
			'Pendiente',
			byId.get(withoutDate).installmentStatus__c,
			'Sin vencimiento no se puede saber si vencio'
		);
	}

	/**
	 * @description: Aplicarlo dos veces no cambia nada mas.
	 */
	@IsTest
	static void runningTwiceChangesNothingMore() {
		Id planId = planWithoutInstallments();
		Id overdue = installment(
			planId,
			1,
			PolicyStatusService.todayInMexico().addDays(-3),
			'Pendiente'
		);
		PaymentPlanInstallmentOverdueBatch.markOverdue(candidates());
		DateTime afterFirstRun = [
			SELECT LastModifiedDate
			FROM PaymentPlanInstallment__c
			WHERE Id = :overdue
		]
		.LastModifiedDate;

		Test.startTest();
		PaymentPlanInstallmentOverdueBatch.markOverdue(candidates());
		Integer dmlUsed = Limits.getDmlStatements();
		Test.stopTest();

		Assert.areEqual(
			'Vencido',
			[
				SELECT installmentStatus__c
				FROM PaymentPlanInstallment__c
				WHERE Id = :overdue
			]
			.installmentStatus__c
		);
		Assert.areEqual(0, dmlUsed, 'La segunda ejecucion no debe guardar nada');
		Assert.areEqual(
			afterFirstRun,
			[
				SELECT LastModifiedDate
				FROM PaymentPlanInstallment__c
				WHERE Id = :overdue
			]
			.LastModifiedDate
		);
	}

	/**
	 * @description: Si una cuota no puede guardarse, las demas pasan a Vencido y el fallo queda
	 *               registrado.
	 */
	@IsTest
	static void failureOnOneInstallmentDoesNotStopTheOthers() {
		Id planId = planWithoutInstallments();
		Date due = PolicyStatusService.todayInMexico().addDays(-2);
		Id failing = installment(planId, 1, due, 'Pendiente');
		Id healthy = installment(planId, 2, due, 'Pendiente');
		PaymentPlanInstallmentOverdueBatch.failForTest.add(failing);
		String failingId = String.valueOf(failing);

		Test.startTest();
		PaymentPlanInstallmentOverdueBatch.markOverdue(candidates());
		AppLogger.flush();
		Test.stopTest();

		Map<Id, PaymentPlanInstallment__c> byId = installmentsById();
		Assert.areEqual('Pendiente', byId.get(failing).installmentStatus__c);
		Assert.areEqual('Vencido', byId.get(healthy).installmentStatus__c);
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM AppLog__c
				WHERE
					eventCode__c = :CobranzaLog.EVENT_INSTALLMENT_OVERDUE_FAILED
					AND recordId__c = :failingId
			]
		);
	}

	/**
	 * @description: El proceso queda programado para correr todos los dias.
	 */
	@IsTest
	static void schedulesDailyJob() {
		// Con su propio nombre: el trabajo real ya puede estar programado en la organizacion y
		// dos trabajos no pueden compartir nombre.
		String jobName = PaymentPlanInstallmentOverdueBatch.JOB_NAME + ' (prueba)';

		Test.startTest();
		Id jobId = PaymentPlanInstallmentOverdueBatch.scheduleAs(jobName);
		Test.stopTest();

		CronTrigger job = [
			SELECT CronExpression, CronJobDetail.Name
			FROM CronTrigger
			WHERE Id = :jobId
		];
		Assert.areEqual(
			PaymentPlanInstallmentOverdueBatch.DAILY_CRON,
			job.CronExpression
		);
		Assert.areEqual(jobName, job.CronJobDetail.Name);
	}

	/**
	 * @description: La ejecucion programada lanza el proceso por lotes.
	 */
	@IsTest
	static void scheduledExecutionRunsTheBatch() {
		Id planId = planWithoutInstallments();
		Id overdue = installment(
			planId,
			1,
			PolicyStatusService.todayInMexico().addDays(-3),
			'Pendiente'
		);

		Test.startTest();
		new PaymentPlanInstallmentOverdueBatch().execute((SchedulableContext) null);
		Test.stopTest();

		Assert.areEqual(
			'Vencido',
			[
				SELECT installmentStatus__c
				FROM PaymentPlanInstallment__c
				WHERE Id = :overdue
			]
			.installmentStatus__c
		);
	}

	/**
	 * @description: Al dejar la cuota Vencido, el resumen de cobranza de la poliza se entera: es
	 *               el trigger de la cuota el que lo recalcula, y asi el campo dice la verdad sin
	 *               que nadie toque nada.
	 */
	@IsTest
	static void theJobLeavesThePolicySummaryOverdue() {
		Id planId = planWithoutInstallments();
		Id policyId = [
			SELECT insurancePolicy__c
			FROM PaymentPlan__c
			WHERE Id = :planId
		]
		.insurancePolicy__c;
		installment(
			planId,
			1,
			PolicyStatusService.todayInMexico().addDays(-3),
			'Pendiente'
		);
		// El resumen es una foto: mientras la cuota siguio Pendiente y su fecha no habia pasado,
		// la poliza figuraba al dia. Asi queda al llegar el dia siguiente al vencimiento.
		update new InsurancePolicy(
			Id = policyId,
			collectionPaymentStatus__c = 'Al dia'
		);

		Test.startTest();
		Database.executeBatch(new PaymentPlanInstallmentOverdueBatch());
		Test.stopTest();

		Assert.areEqual(
			'Vencido',
			[
				SELECT collectionPaymentStatus__c
				FROM InsurancePolicy
				WHERE Id = :policyId
			]
			.collectionPaymentStatus__c
		);
	}

	/**
	 * Un plan sin cuotas: la poliza genera las suyas al crearse y se borran para que el escenario
	 * sea exactamente el que se quiere probar.
	 */
	private static Id planWithoutInstallments() {
		InsurancePolicy policy = CollectionsTestDataFactory.createOperationalPolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Mensual',
			1200,
			Date.today()
		);
		PaymentPlan__c plan = CollectionsTestDataFactory.getActivePlan(policy.Id);
		List<PaymentPlanInstallment__c> generated = CollectionsTestDataFactory.getInstallmentsByPlan(
			plan.Id
		);
		if (!generated.isEmpty()) {
			delete generated;
		}
		return plan.Id;
	}

	private static Id installment(
		Id planId,
		Integer sequence,
		Date dueDate,
		String status
	) {
		PaymentPlanInstallment__c inst = new PaymentPlanInstallment__c(
			paymentPlan__c = planId,
			sequenceNumber__c = sequence,
			dueDate__c = dueDate,
			expectedAmount__c = 100,
			installmentStatus__c = status
		);
		insert inst;
		return inst.Id;
	}

	private static List<PaymentPlanInstallment__c> candidates() {
		return [
			SELECT Id, dueDate__c, installmentStatus__c
			FROM PaymentPlanInstallment__c
		];
	}

	private static Map<Id, PaymentPlanInstallment__c> installmentsById() {
		return new Map<Id, PaymentPlanInstallment__c>(
			[SELECT Id, installmentStatus__c FROM PaymentPlanInstallment__c]
		);
	}
}
