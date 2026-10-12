/**
 *   @name: HandleLoadSwitchesTest
 *   @version: 1.0
 *   @creation date: 11/10/2026
 *   @author: Javier Torres - Volestra
 *   @description: Pruebas de los dos interruptores de la carga de Handle: el de carga, que deja
 *                 subir polizas, planes y cuotas sin que los triggers los automaticen, y el de
 *                 origen por aseguradora, que hace que los canales de pagos y de polizas guarden
 *                 sin aplicar lo que llega de una aseguradora que se carga desde Handle.
 */
@IsTest
private class HandleLoadSwitchesTest {
	private static final String HANDLE_CARRIER = 'Aseguradora Prueba Handle';
	private static Integer sequence = 0;

	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
		insert new Aseguradora__c(Name = HANDLE_CARRIER);
	}

	@IsTest
	static void loadDoesNotCreateThePlanOfALivePolicy() {
		BulkLoadBypass.forcedForTest = true;

		InsurancePolicy policy = livePolicy('HDL-0001', null);

		Assert.areEqual(
			0,
			[
				SELECT COUNT()
				FROM PaymentPlan__c
				WHERE insurancePolicy__c = :policy.Id
			],
			'La carga trae su propio plan: el trigger no debe crear otro.'
		);
	}

	@IsTest
	static void outsideTheLoadALivePolicyGetsItsPlan() {
		BulkLoadBypass.forcedForTest = false;

		InsurancePolicy policy = livePolicy('HDL-0002', null);

		Assert.areEqual(
			1,
			[SELECT COUNT() FROM PaymentPlan__c WHERE insurancePolicy__c = :policy.Id]
		);
		Assert.isFalse(
			CollectionsTestDataFactory.getInstallmentsByPolicy(policy.Id).isEmpty(),
			'Sin el interruptor todo sigue como antes.'
		);
	}

	@IsTest
	static void loadedPlanDoesNotGenerateInstallments() {
		BulkLoadBypass.forcedForTest = true;
		InsurancePolicy policy = CollectionsTestDataFactory.createPolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Vencido'
		);

		PaymentPlan__c plan = CollectionsTestDataFactory.createPlan(
			policy.Id,
			'Activo',
			'Mensual',
			1200,
			Date.today(),
			12
		);

		Assert.areEqual(
			0,
			CollectionsTestDataFactory.getInstallmentsByPlan(plan.Id).size(),
			'Las cuotas las sube la carga desde los recibos.'
		);
	}

	@IsTest
	static void loadChangingThePremiumKeepsTheInstallments() {
		BulkLoadBypass.forcedForTest = false;
		InsurancePolicy policy = livePolicy('HDL-0003', null);
		List<PaymentPlanInstallment__c> before = CollectionsTestDataFactory.getInstallmentsByPolicy(
			policy.Id
		);

		BulkLoadBypass.forcedForTest = true;
		policy.PremiumAmount = 2400;
		update policy;

		List<PaymentPlanInstallment__c> after = CollectionsTestDataFactory.getInstallmentsByPolicy(
			policy.Id
		);
		Assert.areEqual(before.size(), after.size());
		for (Integer i = 0; i < before.size(); i++) {
			Assert.areEqual(before[i].Id, after[i].Id, 'La carga no rehace el plan.');
			Assert.areEqual(before[i].expectedAmount__c, after[i].expectedAmount__c);
		}
	}

	@IsTest
	static void thePermissionTurnsTheSwitchOnOnlyForItsHolder() {
		User loader = newUser('carga');
		User other = newUser('otro');
		System.runAs(new User(Id = UserInfo.getUserId())) {
			insert new List<User>{ loader, other };
			insert new PermissionSetAssignment(
				AssigneeId = loader.Id,
				PermissionSetId = [
					SELECT Id
					FROM PermissionSet
					WHERE Name = 'Carga_Masiva_Handle'
				]
				.Id
			);
		}

		BulkLoadBypass.checkPermissionInTests = true;
		Boolean loaderActive;
		Boolean otherActive;
		System.runAs(loader) {
			loaderActive = BulkLoadBypass.isActive();
		}
		System.runAs(other) {
			otherActive = BulkLoadBypass.isActive();
		}

		Assert.isTrue(loaderActive);
		Assert.isFalse(
			otherActive,
			'Quien no carga sigue con las automatizaciones.'
		);
	}

	@IsTest
	static void otherTestsIgnoreThePermissionOfWhoRunsThem() {
		User loader = newUser('carga');
		System.runAs(new User(Id = UserInfo.getUserId())) {
			insert loader;
			insert new PermissionSetAssignment(
				AssigneeId = loader.Id,
				PermissionSetId = [
					SELECT Id
					FROM PermissionSet
					WHERE Name = 'Carga_Masiva_Handle'
				]
				.Id
			);
		}

		Boolean active;
		System.runAs(loader) {
			active = BulkLoadBypass.isActive();
		}

		Assert.isFalse(
			active,
			'Si quien despliega tiene el permiso, las pruebas que esperan el plan del trigger no deben fallar.'
		);
	}

	@IsTest
	static void aCarrierWithoutSettingComesFromItsPortal() {
		CarrierDataSourceService.sourceByCarrierForTest = new Map<String, String>{
			HANDLE_CARRIER => CarrierDataSourceService.SOURCE_HANDLE
		};

		Assert.areEqual(
			CarrierDataSourceService.SOURCE_HANDLE,
			CarrierDataSourceService.sourceOf(' aseguradora prueba HANDLE ')
		);
		Assert.areEqual(
			CarrierDataSourceService.SOURCE_PORTAL,
			CarrierDataSourceService.sourceOf('Otra aseguradora')
		);
		Assert.areEqual(
			CarrierDataSourceService.SOURCE_PORTAL,
			CarrierDataSourceService.sourceOf(null)
		);
	}

	@IsTest
	static void paymentOfAHandleCarrierIsKeptWithoutReconciling() {
		InsurancePolicy policy = livePolicy('HDL-0004', carrierId());
		CarrierDataSourceService.sourceByCarrierForTest = new Map<String, String>{
			HANDLE_CARRIER => CarrierDataSourceService.SOURCE_HANDLE
		};
		InboundInsurancePayment__c inbound = normalizedPayment(policy.Name);

		Test.startTest();
		System.enqueueJob(
			new InboundPolicyCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT
				inboundStatus__c,
				candidatePolicy__c,
				manualReviewRequired__c,
				manualReviewReason__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual('Revision Manual', inbound.inboundStatus__c);
		Assert.isTrue(inbound.manualReviewRequired__c);
		Assert.isTrue(inbound.manualReviewReason__c.contains('Handle'));
		Assert.areEqual(policy.Id, inbound.candidatePolicy__c);
	}

	@IsTest
	static void paymentOfAPortalCarrierFollowsItsCourse() {
		InsurancePolicy policy = livePolicy('HDL-0005', carrierId());
		CarrierDataSourceService.sourceByCarrierForTest = new Map<String, String>();
		InboundInsurancePayment__c inbound = normalizedPayment(policy.Name);

		Test.startTest();
		System.enqueueJob(
			new InboundPolicyCandidateQueueable(new Set<Id>{ inbound.Id })
		);
		Test.stopTest();

		inbound = [
			SELECT inboundStatus__c, candidatePolicy__c, manualReviewRequired__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inbound.Id
		];
		Assert.areEqual(policy.Id, inbound.candidatePolicy__c);
		Assert.areNotEqual('Revision Manual', inbound.inboundStatus__c);
		Assert.isFalse(inbound.manualReviewRequired__c);
	}

	@IsTest
	static void refundOfAHandleCarrierIsKeptWithoutApplying() {
		InsurancePolicy policy = livePolicy('HDL-0006', carrierId());
		CarrierDataSourceService.sourceByCarrierForTest = new Map<String, String>{
			HANDLE_CARRIER => CarrierDataSourceService.SOURCE_HANDLE
		};
		sequence++;
		InboundInsurancePayment__c refund = new InboundInsurancePayment__c(
			externalPaymentId__c = 'EXT-HDL-R' + sequence,
			sourceReceiptNumber__c = 'R-HDL-' + sequence,
			inboundStatus__c = 'Devolucion',
			sourceAmount__c = -600,
			sourceDueDate__c = Date.today(),
			sourcePolicyNumber__c = policy.Name,
			carrierReceiptStatus__c = 'Pagado',
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now()
		);
		insert refund;

		Test.startTest();
		InboundRefundService.process(new Set<Id>{ refund.Id });
		Test.stopTest();

		refund = [
			SELECT
				inboundStatus__c,
				refundOutcome__c,
				refundReviewReason__c,
				candidatePolicy__c
			FROM InboundInsurancePayment__c
			WHERE Id = :refund.Id
		];
		Assert.areEqual('Revision Manual', refund.inboundStatus__c);
		Assert.areEqual(
			InboundRefundService.OUTCOME_REVIEW,
			refund.refundOutcome__c
		);
		Assert.isTrue(refund.refundReviewReason__c.contains('Handle'));
		Assert.areEqual(policy.Id, refund.candidatePolicy__c);
		Assert.areEqual(
			0,
			[
				SELECT COUNT()
				FROM PaymentPlanInstallment__c
				WHERE
					paymentPlan__r.insurancePolicy__c = :policy.Id
					AND installmentStatus__c = 'Cancelado'
			],
			'La devolucion no toca las cuotas.'
		);
	}

	@IsTest
	static void policyUpdateOfAHandleCarrierIsKeptWithoutApplying() {
		InsurancePolicy policy = livePolicy('HDL-0007', carrierId());
		CarrierDataSourceService.sourceByCarrierForTest = new Map<String, String>{
			HANDLE_CARRIER => CarrierDataSourceService.SOURCE_HANDLE
		};
		InboundPolicyUpdate__c communication = new InboundPolicyUpdate__c(
			sourcePolicyNumber__c = policy.Name,
			sourcePolicyStartDate__c = Date.today(),
			sourcePolicyEndDate__c = Date.today().addYears(2),
			sourceCarrierCode__c = 'PRUEBA',
			sourceSynchronizedAt__c = System.now(),
			inboundStatus__c = 'Recibido',
			contentFingerprint__c = 'prueba-handle-' + policy.Name,
			receivedAt__c = System.now()
		);
		insert communication;

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ communication.Id });
		Test.stopTest();

		communication = [
			SELECT
				inboundStatus__c,
				candidatePolicy__c,
				manualReviewRequired__c,
				reviewReasonCode__c
			FROM InboundPolicyUpdate__c
			WHERE Id = :communication.Id
		];
		Assert.areEqual('Revision Manual', communication.inboundStatus__c);
		Assert.areEqual('ORIGEN_HANDLE', communication.reviewReasonCode__c);
		Assert.isTrue(communication.manualReviewRequired__c);
		Assert.areEqual(policy.Id, communication.candidatePolicy__c);
		Assert.areEqual(
			PolicyStatusService.mexicoMidnight(Date.today().addYears(1)),
			[SELECT ExpirationDate FROM InsurancePolicy WHERE Id = :policy.Id]
			.ExpirationDate,
			'La poliza no cambia.'
		);
	}

	private static InsurancePolicy livePolicy(String policyNumber, Id carrierId) {
		InsurancePolicy policy = CollectionsTestDataFactory.buildCompletePolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Vigente',
			'Semestral',
			1200,
			Date.today()
		);
		policy.Name = policyNumber;
		policy.Aseguradora__c = carrierId;
		policy.EffectiveDate = PolicyStatusService.mexicoMidnight(Date.today());
		policy.ExpirationDate = PolicyStatusService.mexicoMidnight(
			Date.today().addYears(1)
		);
		insert policy;
		return policy;
	}

	private static Id carrierId() {
		return [SELECT Id FROM Aseguradora__c WHERE Name = :HANDLE_CARRIER LIMIT 1]
		.Id;
	}

	private static InboundInsurancePayment__c normalizedPayment(
		String policyNumber
	) {
		sequence++;
		InboundInsurancePayment__c inbound = new InboundInsurancePayment__c(
			externalPaymentId__c = 'EXT-HDL-' + sequence,
			inboundStatus__c = 'Normalizado',
			sourceAmount__c = 600,
			sourcePaymentDate__c = Date.today(),
			sourceDueDate__c = Date.today(),
			sourcePolicyNumber__c = policyNumber,
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now(),
			parsedAt__c = System.now()
		);
		insert inbound;
		return inbound;
	}

	private static User newUser(String alias) {
		String unique =
			alias + String.valueOf(Crypto.getRandomInteger()).replace('-', '');
		// La org puede limitar los dominios de correo de sus usuarios: se usa el del usuario
		// que corre la prueba, que por fuerza es uno permitido.
		String allowedDomain = UserInfo.getUserEmail().substringAfter('@');
		return new User(
			Alias = alias,
			Email = unique + '@' + allowedDomain,
			Username = unique + '@prueba-handle.test',
			LastName = 'Prueba ' + alias,
			EmailEncodingKey = 'UTF-8',
			LanguageLocaleKey = 'es',
			LocaleSidKey = 'es_MX',
			TimeZoneSidKey = 'America/Mexico_City',
			ProfileId = [
				SELECT Id
				FROM Profile
				WHERE PermissionsModifyAllData = TRUE AND UserType = 'Standard'
				LIMIT 1
			]
			.Id
		);
	}
}
