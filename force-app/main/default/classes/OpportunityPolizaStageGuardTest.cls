/**
 *   @name: OpportunityPolizaStageGuardTest
 *   @version: 1.0
 *   @creation date: 16/06/2026
 *   @author: Javier Torres - Volestra
 *   @description: Verifica que el flow Bloquear_Closed_Won_Sin_Pago_Reconocido impide
 *                 mover una Opportunity a Closed Won si no existe un recibo reconocido
 *                 válido vinculado a través de su InsurancePolicy.
 */
@IsTest
private class OpportunityPolizaStageGuardTest {
	private static final String STAGE_POLIZA = 'Póliza';
	private static final String STAGE_CLOSED_WON = 'Closed Won';
	private static final String RECEIPT_STATUS_RECOGNIZED = 'Reconocido';
	private static final String RECEIPT_STATUS_PENDING = 'Pendiente de confirmacion';
	private static final String RECEIPT_STATUS_REVERSED = 'Reversado';
	private static final String ERROR_MSG_FRAGMENT = 'pago reconocido';

	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	/**
	 * @description: CA-1 / CA-2: Una Opportunity con InsurancePolicy vinculada pero
	 *               sin ningún receipt no puede moverse manualmente a Closed Won.
	 */
	@IsTest
	static void blocksManualClosedWonWhenPolicyExistsButNoReceipt() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		Opportunity opp = createOpportunity(accountId, STAGE_POLIZA);
		createPolicyLinkedToOpportunity(accountId, opp.Id);

		Test.startTest();
		Boolean threwException = false;
		String errorMessage = '';
		try {
			update new Opportunity(Id = opp.Id, StageName = STAGE_CLOSED_WON);
		} catch (DmlException e) {
			threwException = true;
			errorMessage = e.getMessage();
		}
		Test.stopTest();

		Assert.isTrue(
			threwException,
			'Debe bloquear el cierre manual sin recibo reconocido'
		);
		Assert.isTrue(
			errorMessage.containsIgnoreCase(ERROR_MSG_FRAGMENT),
			'El mensaje debe indicar que falta un pago reconocido'
		);
		Assert.areEqual(
			STAGE_POLIZA,
			[SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName
		);
	}

	/**
	 * @description: CA-3: Que exista un PaymentReconciliation__c sin receipt reconocido
	 *               no es condición suficiente para cerrar la Opportunity.
	 */
	@IsTest
	static void blocksManualClosedWonWhenReconciliationExistsWithoutRecognizedReceipt() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		Opportunity opp = createOpportunity(accountId, STAGE_POLIZA);
		InsurancePolicy policy = createPolicyLinkedToOpportunity(accountId, opp.Id);

		String uniqueId = String.valueOf(Math.abs(Crypto.getRandomInteger()));
		InboundInsurancePayment__c inbound = new InboundInsurancePayment__c(
			externalPaymentId__c = 'EXT-191-T-' + uniqueId,
			inboundStatus__c = 'Conciliado',
			candidatePolicy__c = policy.Id,
			sourceAmount__c = 1000,
			sourcePaymentDate__c = Date.today(),
			sourcePolicyNumber__c = 'POL-TEST',
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now()
		);
		insert inbound;
		insert new PaymentReconciliation__c(
			inboundPayment__c = inbound.Id,
			insurancePolicy__c = policy.Id,
			reconciliationStatus__c = 'Conciliado',
			matchMethod__c = 'Cuota exacta',
			confidenceScore__c = 95,
			candidateCount__c = 1
		);

		Test.startTest();
		Boolean threwException = false;
		try {
			update new Opportunity(Id = opp.Id, StageName = STAGE_CLOSED_WON);
		} catch (DmlException e) {
			threwException = true;
		}
		Test.stopTest();

		Assert.isTrue(
			threwException,
			'La reconciliación sola no debe ser suficiente para cerrar la oportunidad'
		);
		Assert.areEqual(
			STAGE_POLIZA,
			[SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName
		);
	}

	/**
	 * @description: CA-4a: Un receipt en estado Pendiente de confirmacion no habilita
	 *               el cierre manual de la Opportunity.
	 */
	@IsTest
	static void blocksManualClosedWonWhenReceiptIsPending() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		Opportunity opp = createOpportunity(accountId, STAGE_POLIZA);
		InsurancePolicy policy = createPolicyLinkedToOpportunity(accountId, opp.Id);
		insert buildReceipt(policy.Id, RECEIPT_STATUS_PENDING);

		Test.startTest();
		Boolean threwException = false;
		try {
			update new Opportunity(Id = opp.Id, StageName = STAGE_CLOSED_WON);
		} catch (DmlException e) {
			threwException = true;
		}
		Test.stopTest();

		Assert.isTrue(
			threwException,
			'Un recibo Pendiente no debe habilitar el cierre'
		);
		Assert.areEqual(
			STAGE_POLIZA,
			[SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName
		);
	}

	/**
	 * @description: CA-4b: Un receipt en estado Reversado no habilita el cierre
	 *               manual de la Opportunity.
	 */
	@IsTest
	static void blocksManualClosedWonWhenReceiptIsReversed() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		Opportunity opp = createOpportunity(accountId, STAGE_POLIZA);
		InsurancePolicy policy = createPolicyLinkedToOpportunity(accountId, opp.Id);
		insert buildReceipt(policy.Id, RECEIPT_STATUS_REVERSED);

		Test.startTest();
		Boolean threwException = false;
		try {
			update new Opportunity(Id = opp.Id, StageName = STAGE_CLOSED_WON);
		} catch (DmlException e) {
			threwException = true;
		}
		Test.stopTest();

		Assert.isTrue(
			threwException,
			'Un recibo Reversado no debe habilitar el cierre'
		);
		Assert.areEqual(
			STAGE_POLIZA,
			[SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName
		);
	}

	/**
	 * @description: CA-5: Cuando existe un recibo Reconocido, el trigger de Historia 190
	 *               cierra la Opportunity y el flow Before-Save lo permite.
	 *               Prueba la coexistencia de ambos mecanismos.
	 */
	@IsTest
	static void allowsClosedWonWhenRecognizedReceiptExistsViaHistory190() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		Opportunity opp = createOpportunity(accountId, STAGE_POLIZA);
		InsurancePolicy policy = createPolicyWithPremiumFields(accountId, opp.Id);

		Test.startTest();
		insert buildReceipt(policy.Id, RECEIPT_STATUS_RECOGNIZED);
		Test.stopTest();

		Assert.areEqual(
			STAGE_CLOSED_WON,
			[SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName,
			'El trigger de H190 debe cerrar la Opportunity y el flow Before-Save debe permitirlo'
		);
	}

	/**
	 * @description: CA-6: Con el retiro del modelo legacy (se reemplaza al desplegar a
	 *               produccion), una Opportunity sin InsurancePolicy vinculada tampoco
	 *               puede cerrarse manualmente a Closed Won: el guard exige un pago
	 *               reconocido del modelo nuevo en todos los casos.
	 */
	@IsTest
	static void blocksManualClosedWonWhenNoPolicyLinked() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		Opportunity opp = createOpportunity(accountId, STAGE_POLIZA);

		Test.startTest();
		Boolean threwException = false;
		String errorMessage = '';
		try {
			update new Opportunity(Id = opp.Id, StageName = STAGE_CLOSED_WON);
		} catch (DmlException e) {
			threwException = true;
			errorMessage = e.getMessage();
		}
		Test.stopTest();

		Assert.isTrue(
			threwException,
			'Una Opportunity sin InsurancePolicy vinculada tampoco debe poder cerrarse a Closed Won sin pago reconocido (el modelo nuevo reemplaza al legacy)'
		);
		Assert.isTrue(
			errorMessage.containsIgnoreCase(ERROR_MSG_FRAGMENT),
			'El mensaje debe indicar que falta un pago reconocido'
		);
		Assert.areEqual(
			STAGE_POLIZA,
			[SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName
		);
	}

	// ─── Helpers ────────────────────────────────────────────────────────────────

	private static Opportunity createOpportunity(Id accountId, String stageName) {
		Opportunity opp = new Opportunity(
			Name = 'Test 191 ' + stageName,
			AccountId = accountId,
			StageName = stageName,
			CloseDate = Date.today().addMonths(1),
			Agente_Relacionado__c = CollectionsTestDataFactory.getOrCreateAgenteId()
		);
		insert opp;
		return opp;
	}

	private static InsurancePolicy createPolicyLinkedToOpportunity(
		Id accountId,
		Id opportunityId
	) {
		InsurancePolicy policy = CollectionsTestDataFactory.buildPolicy(
			accountId,
			'Cancelado'
		);
		policy.SourceOpportunityId = opportunityId;
		insert policy;
		return policy;
	}

	private static InsurancePolicy createPolicyWithPremiumFields(
		Id accountId,
		Id opportunityId
	) {
		InsurancePolicy policy = CollectionsTestDataFactory.buildPolicy(
			accountId,
			'Cancelado'
		);
		policy.SourceOpportunityId = opportunityId;
		// Requeridos por PremiumFieldsRequired cuando Update_Status_Insurance_Policy
		// intenta mover la póliza a Vigente al cerrar la Opportunity a Closed Won.
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
			externalPaymentId__c = 'EXT-191-T-' + uniqueId,
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
