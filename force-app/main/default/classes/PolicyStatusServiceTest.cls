/**
 *   @name: PolicyStatusServiceTest
 *   @version: 1.0
 *   @creation date: 16/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Verifica que el primer pago reconocido saca la poliza de Inicial, con o sin
 *                 oportunidad, y la regla de fin de vigencia con las distintas formas en que
 *                 se guarda la fecha de fin.
 */
@IsTest
private class PolicyStatusServiceTest {
	private static final String STAGE_POLIZA = 'Póliza';
	private static final String STAGE_CLOSED_WON = 'Closed Won';
	private static final String RECEIPT_STATUS_RECOGNIZED = 'Reconocido';
	private static final String RECEIPT_STATUS_PENDING = 'Pendiente de confirmacion';

	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	/**
	 * @description: Una poliza en Inicial sin oportunidad pasa a Vigente con su primer pago
	 *               reconocido.
	 */
	@IsTest
	static void firstPaymentActivatesInitialPolicyWithoutOpportunity() {
		InsurancePolicy policy = createPolicy(
			'Inicial',
			Date.today().addYears(1),
			null
		);

		Test.startTest();
		insert buildReceipt(policy.Id, RECEIPT_STATUS_RECOGNIZED);
		Test.stopTest();

		Assert.areEqual('Vigente', statusOf(policy.Id));
	}

	/**
	 * @description: Si la vigencia ya termino cuando llega el primer pago, la poliza queda
	 *               Vencido y no Vigente.
	 */
	@IsTest
	static void firstPaymentOnEndedTermLeavesPolicyExpired() {
		InsurancePolicy policy = createPolicy(
			'Inicial',
			Date.today().addDays(-5),
			null
		);

		Test.startTest();
		insert buildReceipt(policy.Id, RECEIPT_STATUS_RECOGNIZED);
		Test.stopTest();

		Assert.areEqual('Vencido', statusOf(policy.Id));
	}

	/**
	 * @description: Un recibo que no esta reconocido no mueve el estado.
	 */
	@IsTest
	static void pendingReceiptDoesNotActivatePolicy() {
		InsurancePolicy policy = createPolicy(
			'Inicial',
			Date.today().addYears(1),
			null
		);

		Test.startTest();
		insert buildReceipt(policy.Id, RECEIPT_STATUS_PENDING);
		Test.stopTest();

		Assert.areEqual('Inicial', statusOf(policy.Id));
	}

	/**
	 * @description: Con oportunidad, el cierre de la oportunidad sigue pasando la poliza a
	 *               Vigente y el servicio no falla ni la toca otra vez.
	 */
	@IsTest
	static void policyWithOpportunityIsActivatedByTheOpportunityClosure() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		Opportunity opp = new Opportunity(
			Name = 'OPP-ESTADO-POLIZA',
			AccountId = accountId,
			StageName = STAGE_POLIZA,
			CloseDate = Date.today().addMonths(1),
			Agente_Relacionado__c = CollectionsTestDataFactory.getOrCreateAgenteId(),
			// Ramo__c es obligatorio y su valor por defecto no esta en todos los orgs.
			Ramo__c = 'Automoviles'
		);
		insert opp;
		InsurancePolicy policy = createPolicy(
			'Inicial',
			Date.today().addYears(1),
			opp.Id
		);

		Test.startTest();
		insert buildReceipt(policy.Id, RECEIPT_STATUS_RECOGNIZED);
		Test.stopTest();

		Assert.areEqual(
			STAGE_CLOSED_WON,
			[SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName
		);
		Assert.areEqual('Vigente', statusOf(policy.Id));
		Assert.areEqual(0, failureLogs());
	}

	/**
	 * @description: Una poliza Vencido que recibe un pago de su vigencia sigue Vencido.
	 */
	@IsTest
	static void expiredPolicyStaysExpiredWhenPaid() {
		InsurancePolicy policy = createPolicy(
			'Inicial',
			Date.today().addDays(-10),
			null
		);
		update new InsurancePolicy(Id = policy.Id, Status = 'Vencido');

		Test.startTest();
		insert buildReceipt(policy.Id, RECEIPT_STATUS_RECOGNIZED);
		Test.stopTest();

		Assert.areEqual('Vencido', statusOf(policy.Id));
	}

	/**
	 * @description: Si una poliza no puede guardarse, las demas se actualizan igual y el
	 *               fallo queda registrado con la poliza.
	 */
	@IsTest
	static void failureOnOnePolicyDoesNotStopTheOthers() {
		InsurancePolicy failing = createPolicy(
			'Inicial',
			Date.today().addYears(1),
			null
		);
		InsurancePolicy healthy = createPolicy(
			'Inicial',
			Date.today().addYears(1),
			null
		);
		PolicyStatusService.failForTest.add(failing.Id);

		Test.startTest();
		PolicyStatusService.activateOnFirstPayment(
			new Set<Id>{ failing.Id, healthy.Id }
		);
		AppLogger.flush();
		Test.stopTest();

		Assert.areEqual('Inicial', statusOf(failing.Id));
		Assert.areEqual('Vigente', statusOf(healthy.Id));
		List<AppLog__c> logs = [
			SELECT recordId__c, stage__c
			FROM AppLog__c
			WHERE eventCode__c = :CobranzaLog.EVENT_POLICY_STATUS_UPDATE_FAILED
		];
		Assert.areEqual(1, logs.size());
		Assert.areEqual(String.valueOf(failing.Id), logs[0].recordId__c);
		Assert.areEqual(CobranzaLog.STAGE_ESTADO_POLIZA, logs[0].stage__c);
	}

	/**
	 * @description: El dia de fin es el correcto con las tres formas en que se guarda la fecha
	 *               de fin: medianoche UTC (migracion), medianoche de Ciudad de Mexico (alta
	 *               desde la cotizacion) y mediodia.
	 */
	@IsTest
	static void termEndsTheDayAfterItsEndDateWhateverTheStoredTime() {
		Date endDate = Date.newInstance(2026, 9, 15);
		List<DateTime> encodings = new List<DateTime>{
			DateTime.newInstanceGmt(endDate, Time.newInstance(0, 0, 0, 0)),
			DateTime.newInstanceGmt(endDate, Time.newInstance(6, 0, 0, 0)),
			DateTime.newInstanceGmt(endDate, Time.newInstance(18, 0, 0, 0))
		};
		for (DateTime stored : encodings) {
			Assert.isFalse(
				PolicyStatusService.termEnded(stored, endDate),
				'El ultimo dia de vigencia todavia no esta vencido: ' + stored
			);
			Assert.isTrue(
				PolicyStatusService.termEnded(stored, endDate.addDays(1)),
				'Al dia siguiente del fin ya esta vencido: ' + stored
			);
			Assert.areEqual(
				stored < PolicyStatusService.endedTermCutoff(endDate.addDays(1)),
				PolicyStatusService.termEnded(stored, endDate.addDays(1)),
				'La busqueda del proceso y la regla deben coincidir: ' + stored
			);
		}
		Assert.isFalse(PolicyStatusService.termEnded(null, endDate));
	}

	private static InsurancePolicy createPolicy(
		String status,
		Date expirationDate,
		Id opportunityId
	) {
		InsurancePolicy policy = CollectionsTestDataFactory.buildCompletePolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
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
		policy.SourceOpportunityId = opportunityId;
		insert policy;
		return policy;
	}

	private static String statusOf(Id policyId) {
		return [SELECT Status FROM InsurancePolicy WHERE Id = :policyId].Status;
	}

	private static Integer failureLogs() {
		return [
			SELECT COUNT()
			FROM AppLog__c
			WHERE eventCode__c = :CobranzaLog.EVENT_POLICY_STATUS_UPDATE_FAILED
		];
	}

	private static PolicyPaymentReceipt__c buildReceipt(
		Id policyId,
		String status
	) {
		String uniqueId = String.valueOf(Math.abs(Crypto.getRandomInteger()));
		InboundInsurancePayment__c inbound = new InboundInsurancePayment__c(
			externalPaymentId__c = 'EXT-EST-' + uniqueId,
			inboundStatus__c = 'Conciliado',
			candidatePolicy__c = policyId,
			sourceAmount__c = 1000,
			sourcePaymentDate__c = Date.today(),
			sourcePolicyNumber__c = 'POL-EST',
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now()
		);
		insert inbound;
		PaymentReconciliation__c recon = new PaymentReconciliation__c(
			inboundPayment__c = inbound.Id,
			insurancePolicy__c = policyId,
			reconciliationStatus__c = 'Conciliado',
			matchMethod__c = 'Cuota exacta',
			confidenceScore__c = 95,
			candidateCount__c = 1
		);
		insert recon;
		return new PolicyPaymentReceipt__c(
			insurancePolicy__c = policyId,
			paymentReconciliation__c = recon.Id,
			receiptStatus__c = status,
			receiptDate__c = Date.today(),
			receiptAmount__c = 1000
		);
	}
}
