/**
 *   @name: InsurancePolicyExpirationBatchTest
 *   @version: 1.0
 *   @creation date: 16/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Verifica el proceso diario de fin de vigencia: que polizas pasan a Vencido,
 *                 cuales no se tocan, que correrlo dos veces no cambia nada, que un fallo no
 *                 detiene a las demas y que se programa.
 */
@IsTest
private class InsurancePolicyExpirationBatchTest {
	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	/**
	 * @description: Pasan a Vencido las polizas en Inicial o Vigente con la vigencia terminada;
	 *               no se tocan las que siguen en vigencia ni las canceladas.
	 */
	@IsTest
	static void expiresOnlyLivePoliciesWithEndedTerm() {
		Id activeEnded = createPolicy('Vigente', Date.today().addDays(-3));
		Id initialEnded = createPolicy('Inicial', Date.today().addDays(-1));
		Id activeRunning = createPolicy('Vigente', Date.today().addDays(30));
		Id endsToday = createPolicy('Vigente', PolicyStatusService.todayInMexico());
		Id cancelledEnded = createPolicy('Cancelado', Date.today().addDays(-3));

		Test.startTest();
		Database.executeBatch(new InsurancePolicyExpirationBatch());
		Test.stopTest();

		Map<Id, InsurancePolicy> byId = new Map<Id, InsurancePolicy>(
			[SELECT Id, Status FROM InsurancePolicy]
		);
		Assert.areEqual('Vencido', byId.get(activeEnded).Status);
		Assert.areEqual('Vencido', byId.get(initialEnded).Status);
		Assert.areEqual('Vigente', byId.get(activeRunning).Status);
		Assert.areEqual(
			'Vigente',
			byId.get(endsToday).Status,
			'El ultimo dia de vigencia todavia no esta vencido'
		);
		Assert.areEqual('Cancelado', byId.get(cancelledEnded).Status);
	}

	/**
	 * @description: Aplicar el fin de vigencia dos veces no cambia nada mas.
	 */
	@IsTest
	static void runningTwiceChangesNothingMore() {
		Id activeEnded = createPolicy('Vigente', Date.today().addDays(-3));
		List<InsurancePolicy> candidates = [
			SELECT Id, Status, ExpirationDate
			FROM InsurancePolicy
			WHERE Id = :activeEnded
		];
		PolicyStatusService.expireEndedTerms(candidates);
		DateTime afterFirstRun = [
			SELECT LastModifiedDate
			FROM InsurancePolicy
			WHERE Id = :activeEnded
		]
		.LastModifiedDate;

		Test.startTest();
		PolicyStatusService.expireEndedTerms(
			[
				SELECT Id, Status, ExpirationDate
				FROM InsurancePolicy
				WHERE Id = :activeEnded
			]
		);
		Integer dmlUsed = Limits.getDmlStatements();
		Test.stopTest();

		Assert.areEqual(
			'Vencido',
			[SELECT Status FROM InsurancePolicy WHERE Id = :activeEnded].Status
		);
		Assert.areEqual(0, dmlUsed, 'La segunda ejecucion no debe guardar nada');
		Assert.areEqual(
			afterFirstRun,
			[SELECT LastModifiedDate FROM InsurancePolicy WHERE Id = :activeEnded]
			.LastModifiedDate
		);
	}

	/**
	 * @description: Si una poliza no puede guardarse, las demas pasan a Vencido y el fallo
	 *               queda registrado.
	 */
	@IsTest
	static void failureOnOnePolicyDoesNotStopTheOthers() {
		Id failing = createPolicy('Vigente', Date.today().addDays(-3));
		Id healthy = createPolicy('Vigente', Date.today().addDays(-3));
		PolicyStatusService.failForTest.add(failing);

		Set<Id> policyIds = new Set<Id>{ failing, healthy };
		String failingId = String.valueOf(failing);

		Test.startTest();
		PolicyStatusService.expireEndedTerms(
			[
				SELECT Id, Status, ExpirationDate
				FROM InsurancePolicy
				WHERE Id IN :policyIds
			]
		);
		AppLogger.flush();
		Test.stopTest();

		Assert.areEqual(
			'Vigente',
			[SELECT Status FROM InsurancePolicy WHERE Id = :failing].Status
		);
		Assert.areEqual(
			'Vencido',
			[SELECT Status FROM InsurancePolicy WHERE Id = :healthy].Status
		);
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM AppLog__c
				WHERE
					eventCode__c = :CobranzaLog.EVENT_POLICY_STATUS_UPDATE_FAILED
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
		String jobName = InsurancePolicyExpirationBatch.JOB_NAME + ' (prueba)';

		Test.startTest();
		Id jobId = InsurancePolicyExpirationBatch.scheduleAs(jobName);
		Test.stopTest();

		CronTrigger job = [
			SELECT CronExpression, CronJobDetail.Name
			FROM CronTrigger
			WHERE Id = :jobId
		];
		Assert.areEqual(
			InsurancePolicyExpirationBatch.DAILY_CRON,
			job.CronExpression
		);
		Assert.areEqual(jobName, job.CronJobDetail.Name);
	}

	/**
	 * @description: La ejecucion programada lanza el proceso por lotes.
	 */
	@IsTest
	static void scheduledExecutionRunsTheBatch() {
		Id activeEnded = createPolicy('Vigente', Date.today().addDays(-3));

		Test.startTest();
		new InsurancePolicyExpirationBatch().execute((SchedulableContext) null);
		Test.stopTest();

		Assert.areEqual(
			'Vencido',
			[SELECT Status FROM InsurancePolicy WHERE Id = :activeEnded].Status
		);
	}

	private static Id createPolicy(String status, Date expirationDate) {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = 'Cancelado'.equals(status)
			? CollectionsTestDataFactory.buildPolicy(accountId, status)
			: CollectionsTestDataFactory.buildCompletePolicy(
					accountId,
					status,
					'Mensual',
					1200,
					Date.today()
			  );
		policy.EffectiveDate = DateTime.newInstanceGmt(
			expirationDate.addYears(-1),
			Time.newInstance(0, 0, 0, 0)
		);
		policy.ExpirationDate = DateTime.newInstanceGmt(
			expirationDate,
			Time.newInstance(0, 0, 0, 0)
		);
		insert policy;
		return policy.Id;
	}
}
