/**
 *   @name: PolicyPaymentReceiptTriggerHandlerTest
 *   @version: 1.1
 *   @creation date: 15/06/2026
 *   @author: Javier Torres - Volestra
 *   @description: Verifica el cierre automatico de la Opportunity a Closed Won
 *                 al registrarse un PolicyPaymentReceipt__c reconocido.
 */
@IsTest
private class PolicyPaymentReceiptTriggerHandlerTest {
	private static final String STAGE_POLIZA = 'Póliza';
	private static final String STAGE_CLOSED_WON = 'Closed Won';
	private static final String STAGE_CLOSED_LOST = 'Closed Lost';
	private static final String RECEIPT_STATUS_RECOGNIZED = 'Reconocido';
	private static final String RECEIPT_STATUS_PENDING = 'Pendiente de confirmacion';

	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	/**
	 * @creation date: 15/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA-1: Verifica que insertar un recibo Reconocido cierra
	 *               automaticamente la oportunidad vinculada a la poliza.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void closesOpportunityWhenFirstRecognizedReceiptInserted() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		Opportunity opp = createOpportunity(accountId, STAGE_POLIZA);
		InsurancePolicy policy = createPolicyLinkedToOpportunity(accountId, opp.Id);

		Test.startTest();
		insert buildReceipt(policy.Id, RECEIPT_STATUS_RECOGNIZED);
		Test.stopTest();

		Assert.areEqual(
			STAGE_CLOSED_WON,
			[SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName
		);
	}

	/**
	 * @creation date: 15/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA-2: Verifica que insertar un segundo recibo Reconocido no
	 *               produce error cuando la oportunidad ya esta en Closed Won.
	 *               La oportunidad se cierra primero via el propio handler (no via
	 *               insert directo en closed stage, que la validacion BloquearCerrada
	 *               bloquea para perfiles distintos de System Administrator).
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void doesNotUpdateAlreadyClosedWonOpportunity() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		Opportunity opp = createOpportunity(accountId, STAGE_POLIZA);
		InsurancePolicy policy = createPolicyLinkedToOpportunity(accountId, opp.Id);

		insert buildReceipt(policy.Id, RECEIPT_STATUS_RECOGNIZED);
		Assert.areEqual(
			STAGE_CLOSED_WON,
			[SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName,
			'Setup: la oportunidad debe estar en Closed Won antes de probar idempotencia'
		);

		Test.startTest();
		insert buildReceipt(policy.Id, RECEIPT_STATUS_RECOGNIZED);
		Test.stopTest();

		Assert.areEqual(
			STAGE_CLOSED_WON,
			[SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName
		);
	}

	/**
	 * @creation date: 15/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA-3: Verifica que un recibo en estado distinto de Reconocido
	 *               no modifica el stage de la oportunidad.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void doesNotCloseOpportunityWhenReceiptIsNotRecognized() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		Opportunity opp = createOpportunity(accountId, STAGE_POLIZA);
		InsurancePolicy policy = createPolicyLinkedToOpportunity(accountId, opp.Id);

		Test.startTest();
		insert buildReceipt(policy.Id, RECEIPT_STATUS_PENDING);
		Test.stopTest();

		Assert.areEqual(
			STAGE_POLIZA,
			[SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName
		);
	}

	/**
	 * @creation date: 15/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA-4: Verifica que insertar un recibo Reconocido en una poliza
	 *               sin oportunidad vinculada no lanza excepcion.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void doesNotFailWhenPolicyHasNoLinkedOpportunity() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = CollectionsTestDataFactory.createPolicy(
			accountId,
			'Cancelado'
		);

		Test.startTest();
		Boolean threwException = false;
		try {
			insert buildReceipt(policy.Id, RECEIPT_STATUS_RECOGNIZED);
		} catch (Exception e) {
			threwException = true;
		}
		Test.stopTest();

		Assert.isFalse(
			threwException,
			'No debe lanzar excepcion si la poliza no tiene oportunidad vinculada'
		);
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM PolicyPaymentReceipt__c
				WHERE insurancePolicy__c = :policy.Id
			]
		);
	}

	/**
	 * @creation date: 15/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA-5: Verifica que una oportunidad en Closed Lost no se
	 *               reabra ni modifique al llegar un recibo Reconocido.
	 *               La oportunidad se mueve a Closed Lost via update (no via insert
	 *               directo): al hacer update desde Poliza, PRIORVALUE(IsClosed)=False
	 *               por lo que BloquearCerrada no dispara.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void doesNotCloseOpportunityInClosedLostStage() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		Opportunity opp = createOpportunity(accountId, STAGE_POLIZA);
		update new Opportunity(Id = opp.Id, StageName = STAGE_CLOSED_LOST);
		InsurancePolicy policy = createPolicyLinkedToOpportunity(accountId, opp.Id);

		Test.startTest();
		insert buildReceipt(policy.Id, RECEIPT_STATUS_RECOGNIZED);
		Test.stopTest();

		Assert.areEqual(
			STAGE_CLOSED_LOST,
			[SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName
		);
	}

	/**
	 * @creation date: 15/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA-6: Verifica que actualizar un recibo de Pendiente de
	 *               confirmacion a Reconocido cierra la oportunidad vinculada.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void closesOpportunityWhenReceiptStatusUpdatedToRecognized() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		Opportunity opp = createOpportunity(accountId, STAGE_POLIZA);
		InsurancePolicy policy = createPolicyLinkedToOpportunity(accountId, opp.Id);

		PolicyPaymentReceipt__c receipt = buildReceipt(
			policy.Id,
			RECEIPT_STATUS_PENDING
		);
		insert receipt;

		Assert.areEqual(
			STAGE_POLIZA,
			[SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName,
			'La oportunidad no debe cerrarse con recibo en estado pendiente'
		);

		Test.startTest();
		receipt.receiptStatus__c = RECEIPT_STATUS_RECOGNIZED;
		update receipt;
		Test.stopTest();

		Assert.areEqual(
			STAGE_CLOSED_WON,
			[SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName
		);
	}

	/**
	 * @creation date: 15/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA-7: Verifica que insertar multiples recibos Reconocidos para
	 *               la misma poliza en el mismo batch no genera error de DML duplicado
	 *               y deja la oportunidad en Closed Won.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void closesOpportunityOnceForMultipleReceiptsInSameBatch() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		Opportunity opp = createOpportunity(accountId, STAGE_POLIZA);
		InsurancePolicy policy = createPolicyLinkedToOpportunity(accountId, opp.Id);

		Test.startTest();
		insert new List<PolicyPaymentReceipt__c>{
			buildReceipt(policy.Id, RECEIPT_STATUS_RECOGNIZED),
			buildReceipt(policy.Id, RECEIPT_STATUS_RECOGNIZED)
		};
		Test.stopTest();

		Assert.areEqual(
			STAGE_CLOSED_WON,
			[SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName
		);
		Assert.areEqual(
			2,
			[
				SELECT COUNT()
				FROM PolicyPaymentReceipt__c
				WHERE insurancePolicy__c = :policy.Id
			]
		);
	}

	private static Opportunity createOpportunity(Id accountId, String stageName) {
		Opportunity opp = new Opportunity(
			Name = 'Test Opportunity ' + stageName,
			AccountId = accountId,
			StageName = stageName,
			CloseDate = Date.today().addMonths(1),
			Agente_Relacionado__c = CollectionsTestDataFactory.getOrCreateAgenteId()
		);
		insert opp;
		return opp;
	}

	private static InsurancePolicy createPolicyLinkedToOpportunity(
		Id insuredAccountId,
		Id opportunityId
	) {
		InsurancePolicy policy = CollectionsTestDataFactory.buildPolicy(
			insuredAccountId,
			'Cancelado'
		);
		policy.SourceOpportunityId = opportunityId;
		// PremiumAmount, PremiumFrequency y PaymentDueDate son requeridos por la
		// regla PremiumFieldsRequired cuando el flow Update_Status_Insurance_Policy
		// actualiza la poliza a Vigente al cerrar la Opportunity a Closed Won.
		// Sin estos campos el flow revierte la transaccion en silencio.
		policy.PremiumAmount = 1200;
		policy.PremiumFrequency = 'Mensual';
		policy.PaymentDueDate = Date.today();
		insert policy;
		return policy;
	}

	private static PolicyPaymentReceipt__c buildReceipt(
		Id policyId,
		String status
	) {
		String uniqueId = String.valueOf(Math.abs(Crypto.getRandomInteger()));

		InboundInsurancePayment__c inbound = new InboundInsurancePayment__c(
			externalPaymentId__c = 'EXT-190-T-' + uniqueId,
			inboundStatus__c = 'Conciliado',
			candidatePolicy__c = policyId,
			sourceAmount__c = 1000,
			sourcePaymentDate__c = Date.today(),
			sourcePolicyNumber__c = 'POL-TEST',
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
