/**
 *   @name: PolicyCarrierStatusServiceTest
 *   @version: 1.0
 *   @creation date: 16/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Verifica la recepcion y el procesamiento de las comunicaciones de estado de
 *                 poliza: que no se rechazan, que la poliza guarda lo que dijo la aseguradora,
 *                 que gana la mas reciente, que no se duplican, que un estado sin equivalencia no
 *                 se pierde, que una poliza inexistente va a revision, que se elige la vigencia
 *                 correcta y que un rechazado anterior se recupera.
 */
@IsTest
private class PolicyCarrierStatusServiceTest {
	private static final String POLICY_NUMBER = 'POL-438-01';
	private static final String SYNC_16 = '16/09/2026 10:57:14';

	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	/**
	 * @description: Una comunicacion de estado no se rechaza, no entra al circuito y la poliza
	 *               guarda lo que dijo la aseguradora sin cambiar su estado operativo.
	 */
	@IsTest
	static void noticeIsStoredAndPolicyKeepsWhatTheCarrierSaid() {
		useDefaultMappings();
		Id policyId = createPolicy(POLICY_NUMBER, Date.newInstance(2026, 1, 1));

		Test.startTest();
		InboundInsurancePaymentService.EndpointResult result = InboundInsurancePaymentService.receive(
			body(notice(POLICY_NUMBER, 'Cancelada', '06/06/2026', SYNC_16))
		);
		Test.stopTest();

		Assert.isTrue(
			result.body.results[0].success,
			result.body.results[0].message
		);
		InboundInsurancePayment__c stored = onlyNotice();
		Assert.areEqual('Estado de poliza', stored.inboundStatus__c);
		Assert.isTrue(stored.policyStatusNotice__c);
		Assert.isNull(stored.rejectionReason__c);
		Assert.areEqual(policyId, stored.candidatePolicy__c);
		Assert.areEqual(
			0,
			[
				SELECT COUNT()
				FROM PaymentReconciliation__c
				WHERE inboundPayment__c = :stored.Id
			]
		);

		InsurancePolicy policy = policyById(policyId);
		Assert.areEqual('Cancelado', policy.carrierPolicyStatus__c);
		Assert.areEqual('Cancelada', policy.carrierPolicyStatusRaw__c);
		Assert.areEqual(
			stored.sourceSynchronizedAt__c,
			policy.carrierStatusSyncedAt__c
		);
		Assert.areEqual(stored.Id, policy.carrierStatusNotice__c);
		Assert.areEqual('Vigente', policy.Status, 'El estado operativo no cambia');
	}

	/**
	 * @description: Una comunicacion anterior a la ultima guardada no cambia la poliza.
	 */
	@IsTest
	static void olderCommunicationDoesNotOverwriteANewerOne() {
		useDefaultMappings();
		Id policyId = createPolicy(POLICY_NUMBER, Date.newInstance(2026, 1, 1));
		DateTime newer = DateTime.newInstanceGmt(2026, 9, 20, 12, 0, 0);
		update new InsurancePolicy(
			Id = policyId,
			carrierPolicyStatus__c = 'Vigente',
			carrierPolicyStatusRaw__c = 'Vigente',
			carrierStatusSyncedAt__c = newer
		);

		Test.startTest();
		InboundInsurancePaymentService.receive(
			body(notice(POLICY_NUMBER, 'Cancelada', '06/06/2026', SYNC_16))
		);
		Test.stopTest();

		InsurancePolicy policy = policyById(policyId);
		Assert.areEqual('Vigente', policy.carrierPolicyStatus__c);
		Assert.areEqual(newer, policy.carrierStatusSyncedAt__c);
		Assert.areEqual(
			'Estado de poliza',
			onlyNotice().inboundStatus__c,
			'La comunicacion queda guardada'
		);
	}

	/**
	 * @description: La misma comunicacion reenviada no se duplica, se cuenta como reenvio y no
	 *               cambia la poliza.
	 */
	@IsTest
	static void repeatedCommunicationIsNotDuplicatedAndChangesNothing() {
		useDefaultMappings();
		Id policyId = createPolicy(POLICY_NUMBER, Date.newInstance(2026, 1, 1));
		InboundInsurancePaymentService.receive(
			body(notice(POLICY_NUMBER, 'Cancelada', '06/06/2026', SYNC_16))
		);
		PolicyCarrierStatusService.process(new Set<Id>{ onlyNotice().Id });
		DateTime firstSync = policyById(policyId).carrierStatusSyncedAt__c;
		Assert.isNotNull(firstSync, 'Setup: la primera comunicacion se aplico');

		Test.startTest();
		InboundInsurancePaymentService.receive(
			body(
				notice(POLICY_NUMBER, 'Cancelada', '06/06/2026', '17/09/2026 10:57:14')
			)
		);
		Test.stopTest();

		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM InboundInsurancePayment__c
				WHERE policyStatusNotice__c = TRUE
			]
		);
		Assert.areEqual(1, onlyNotice().resendCount__c);
		Assert.areEqual(firstSync, policyById(policyId).carrierStatusSyncedAt__c);
	}

	/**
	 * @description: Un estado sin equivalencia guarda el original, deja vacio el normalizado y lo
	 *               registra; al configurar la equivalencia, la siguiente comunicacion la aplica.
	 */
	@IsTest
	static void statusWithoutEquivalenceKeepsTheOriginalAndIsLogged() {
		PolicyCarrierStatusService.mappingsForTest = new Map<String, String>();
		Id policyId = createPolicy(POLICY_NUMBER, Date.newInstance(2026, 1, 1));
		Id noticeId = insertNotice(POLICY_NUMBER, 'Suspendida');

		Test.startTest();
		PolicyCarrierStatusService.process(new Set<Id>{ noticeId });
		AppLogger.flush();
		InsurancePolicy unmapped = policyById(policyId);
		PolicyCarrierStatusService.mappingsForTest = new Map<String, String>{
			PolicyCarrierStatusService.mappingKey(
				'QUALITAS',
				'Suspendida'
			) => 'Vencido'
		};
		PolicyCarrierStatusService.process(new Set<Id>{ noticeId });
		Test.stopTest();

		Assert.isNull(unmapped.carrierPolicyStatus__c);
		Assert.areEqual('Suspendida', unmapped.carrierPolicyStatusRaw__c);
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM AppLog__c
				WHERE eventCode__c = :CobranzaLog.EVENT_CARRIER_POLICY_STATUS_UNMAPPED
			]
		);
		Assert.areEqual(
			'Vencido',
			policyById(policyId).carrierPolicyStatus__c,
			'Con la equivalencia configurada, la siguiente comunicacion la aplica'
		);
	}

	/**
	 * @description: Una comunicacion de una poliza que no existe va a revision manual; creada la
	 *               poliza, el analista la reprocesa y se aplica.
	 */
	@IsTest
	static void communicationForAMissingPolicyGoesToReviewAndIsReprocessed() {
		useDefaultMappings();

		Test.startTest();
		InboundInsurancePaymentService.receive(
			body(notice('POL-438-NUEVA', 'Cancelada', '06/06/2026', SYNC_16))
		);
		Test.stopTest();

		InboundInsurancePayment__c inReview = onlyNotice();
		Assert.areEqual('Revision Manual', inReview.inboundStatus__c);
		Assert.isTrue(inReview.manualReviewRequired__c);
		Assert.areEqual('SIN_POLIZA', inReview.policyMatchReason__c);

		Id policyId = createPolicy('POL-438-NUEVA', Date.newInstance(2026, 1, 1));
		String message = PolicyCarrierStatusService.reprocessNotice(inReview.Id);

		InboundInsurancePayment__c reprocessed = onlyNotice();
		Assert.areEqual('Estado de poliza', reprocessed.inboundStatus__c, message);
		Assert.isFalse(reprocessed.manualReviewRequired__c);
		Assert.areEqual(policyId, reprocessed.candidatePolicy__c);
		Assert.areEqual('Cancelado', policyById(policyId).carrierPolicyStatus__c);
	}

	/**
	 * @description: Reprocesar solo aplica a comunicaciones de estado en revision manual.
	 */
	@IsTest
	static void reprocessOnlyAppliesToCommunicationsInReview() {
		InboundInsurancePayment__c payment = new InboundInsurancePayment__c(
			externalPaymentId__c = 'EXT-438-PAGO',
			inboundStatus__c = 'Revision Manual',
			sourcePolicyNumber__c = POLICY_NUMBER,
			sourceAmount__c = 100
		);
		insert payment;
		Id noticeId = insertNotice(POLICY_NUMBER, 'Cancelada');

		Test.startTest();
		String paymentError = errorOf(payment.Id);
		String notInReviewError = errorOf(noticeId);
		Test.stopTest();

		Assert.isTrue(paymentError.contains('solo aplica'), paymentError);
		Assert.isTrue(
			notInReviewError.contains('revisión manual'),
			notInReviewError
		);
	}

	/**
	 * @description: Con varias vigencias del mismo numero se aplica a la que contiene la fecha de
	 *               cancelacion; si no la contiene ninguna, va a revision sin elegir.
	 */
	@IsTest
	static void severalTermsAreResolvedByTheCancellationDate() {
		useDefaultMappings();
		Id previousTerm = createPolicy('POL-438-07', Date.newInstance(2025, 1, 1));
		Id currentTerm = createPolicy('POL-438-07', Date.newInstance(2026, 1, 1));

		Test.startTest();
		InboundInsurancePaymentService.receive(
			body(
				notice('POL-438-07', 'Cancelada', '06/06/2026', SYNC_16) +
					',' +
					notice('POL-438-07', 'Cancelada', '06/06/2030', SYNC_16)
			)
		);
		Test.stopTest();

		Assert.areEqual(
			'Cancelado',
			policyById(currentTerm).carrierPolicyStatus__c
		);
		Assert.isNull(policyById(previousTerm).carrierPolicyStatus__c);
		Date outsideBoth = Date.newInstance(2030, 6, 6);
		InboundInsurancePayment__c ambiguous = [
			SELECT inboundStatus__c, policyMatchReason__c
			FROM InboundInsurancePayment__c
			WHERE sourceCancellationDate__c = :outsideBoth
		];
		Assert.areEqual('Revision Manual', ambiguous.inboundStatus__c);
		Assert.areEqual('VIGENCIA_AMBIGUA', ambiguous.policyMatchReason__c);
	}

	/**
	 * @description: Un recibo con folio que ademas informa el estado de la poliza se procesa como
	 *               pago y tambien guarda el estado en la poliza.
	 */
	@IsTest
	static void receiptWithPolicyStatusIsAPaymentAndAlsoUpdatesThePolicy() {
		useDefaultMappings();
		Id policyId = createPolicy(POLICY_NUMBER, Date.newInstance(2026, 1, 1));

		Test.startTest();
		InboundInsurancePaymentService.receive(
			body(
				'{' +
					'"sourcePolicyNumber__c":"' +
					POLICY_NUMBER +
					'",' +
					'"sourceReceiptNumber__c":"R43808",' +
					'"sourceCarrierCode__c":"QUALITAS",' +
					'"sourceAmount__c":100.00,' +
					'"sourcePaymentStatus__c":"Pagado",' +
					'"sourcePaymentDate__c":"10/06/2026",' +
					'"sourceDueDate__c":"08/06/2026",' +
					'"sourcePolicyStatusRaw__c":"Vigente",' +
					'"sourceSynchronizedAt__c":"' +
					SYNC_16 +
					'"' +
					'}'
			)
		);
		Test.stopTest();

		InboundInsurancePayment__c payment = [
			SELECT policyStatusNotice__c, inboundStatus__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'QUALITAS_R43808'
		];
		Assert.isFalse(payment.policyStatusNotice__c);
		Assert.areNotEqual('Estado de poliza', payment.inboundStatus__c);
		Assert.areNotEqual('Rechazado', payment.inboundStatus__c);
		Assert.areEqual('Vigente', policyById(policyId).carrierPolicyStatus__c);
	}

	/**
	 * @description: Una comunicacion que antes se rechazaba por no traer folio se reconoce como el
	 *               mismo registro al reenviarse y se procesa.
	 */
	@IsTest
	static void communicationRejectedBeforeIsRecoveredWhenResent() {
		useDefaultMappings();
		Id policyId = createPolicy(POLICY_NUMBER, Date.newInstance(2026, 1, 1));
		InboundInsurancePaymentService.policyStatusNoticesDisabledForTest = true;
		InboundInsurancePaymentService.receive(
			body(notice(POLICY_NUMBER, 'Cancelada', '06/06/2026', SYNC_16))
		);
		InboundInsurancePayment__c rejected = [
			SELECT Id, inboundStatus__c
			FROM InboundInsurancePayment__c
			WHERE sourcePolicyNumber__c = :POLICY_NUMBER
		];
		Assert.areEqual(
			'Rechazado',
			rejected.inboundStatus__c,
			'Setup: antes se rechazaba'
		);
		InboundInsurancePaymentService.policyStatusNoticesDisabledForTest = false;

		Test.startTest();
		InboundInsurancePaymentService.receive(
			body(
				notice(POLICY_NUMBER, 'Cancelada', '06/06/2026', '17/09/2026 08:00:00')
			)
		);
		Test.stopTest();

		List<InboundInsurancePayment__c> records = [
			SELECT Id, inboundStatus__c, rejectionReason__c, policyStatusNotice__c
			FROM InboundInsurancePayment__c
			WHERE sourcePolicyNumber__c = :POLICY_NUMBER
		];
		Assert.areEqual(1, records.size());
		Assert.areEqual(rejected.Id, records[0].Id);
		Assert.areEqual('Estado de poliza', records[0].inboundStatus__c);
		Assert.isNull(records[0].rejectionReason__c);
		Assert.isTrue(records[0].policyStatusNotice__c);
		Assert.areEqual('Cancelado', policyById(policyId).carrierPolicyStatus__c);
	}

	/**
	 * @description: Si la poliza no se puede guardar, el fallo queda registrado con la poliza.
	 */
	@IsTest
	static void policyThatCannotBeSavedIsLogged() {
		useDefaultMappings();
		Id policyId = createPolicy(POLICY_NUMBER, Date.newInstance(2026, 1, 1));
		Id noticeId = insertNotice(POLICY_NUMBER, 'Cancelada');
		PolicyCarrierStatusService.failForTest.add(policyId);
		String policyIdText = String.valueOf(policyId);

		Test.startTest();
		PolicyCarrierStatusService.process(new Set<Id>{ noticeId });
		AppLogger.flush();
		Test.stopTest();

		Assert.isNull(policyById(policyId).carrierPolicyStatus__c);
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM AppLog__c
				WHERE
					eventCode__c = :CobranzaLog.EVENT_CARRIER_POLICY_STATUS_FAILED
					AND recordId__c = :policyIdText
			]
		);
	}

	private static void useDefaultMappings() {
		PolicyCarrierStatusService.mappingsForTest = new Map<String, String>{
			PolicyCarrierStatusService.mappingKey(
				'QUALITAS',
				'Cancelada'
			) => 'Cancelado',
			PolicyCarrierStatusService.mappingKey('QUALITAS', 'Vigente') => 'Vigente'
		};
	}

	private static String notice(
		String policyNumber,
		String status,
		String cancellationDate,
		String synchronizedAt
	) {
		return '{' +
			'"sourcePolicyNumber__c":"' +
			policyNumber +
			'",' +
			'"sourcePolicyStatusRaw__c":"' +
			status +
			'",' +
			'"sourceCancellationDate__c":"' +
			cancellationDate +
			'",' +
			'"sourceCancellationReason__c":"CANCELACION AUTOMATICA POR FALTA DE PAGO.",' +
			'"sourcePaymentStatusRaw__c":"Cancelada",' +
			'"sourcePaymentStatus__c":"Cancelado",' +
			'"sourceAmount__c":6106.25,' +
			'"sourceSynchronizedAt__c":"' +
			synchronizedAt +
			'",' +
			'"sourceCarrierCode__c":"QUALITAS",' +
			'"sourceInsuranceCarrier__c":"QUALITAS"' +
			'}';
	}

	private static String body(String rows) {
		return '[' + rows + ']';
	}

	private static Id insertNotice(String policyNumber, String status) {
		InboundInsurancePayment__c rec = new InboundInsurancePayment__c(
			policyStatusNotice__c = true,
			inboundStatus__c = 'Estado de poliza',
			sourcePolicyNumber__c = policyNumber,
			sourceCarrierCode__c = 'QUALITAS',
			sourcePolicyStatusRaw__c = status,
			sourceCancellationDate__c = Date.newInstance(2026, 6, 6),
			sourceSynchronizedAt__c = DateTime.newInstanceGmt(
				2026,
				9,
				16,
				16,
				57,
				14
			),
			receivedAt__c = System.now()
		);
		insert rec;
		return rec.Id;
	}

	private static String errorOf(Id inboundId) {
		try {
			PolicyCarrierStatusService.reprocessNotice(inboundId);
		} catch (AuraHandledException e) {
			return e.getMessage();
		}
		return '';
	}

	private static InboundInsurancePayment__c onlyNotice() {
		return [
			SELECT
				Id,
				inboundStatus__c,
				policyStatusNotice__c,
				rejectionReason__c,
				candidatePolicy__c,
				sourceSynchronizedAt__c,
				manualReviewRequired__c,
				policyMatchReason__c,
				resendCount__c
			FROM InboundInsurancePayment__c
			WHERE policyStatusNotice__c = TRUE
		];
	}

	private static InsurancePolicy policyById(Id policyId) {
		return [
			SELECT
				Id,
				Status,
				carrierPolicyStatus__c,
				carrierPolicyStatusRaw__c,
				carrierStatusSyncedAt__c,
				carrierStatusNotice__c
			FROM InsurancePolicy
			WHERE Id = :policyId
		];
	}

	private static Id createPolicy(String policyNumber, Date termStart) {
		InsurancePolicy policy = CollectionsTestDataFactory.buildCompletePolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Vigente',
			'Mensual',
			1200,
			termStart
		);
		policy.Name = policyNumber;
		policy.EffectiveDate = DateTime.newInstanceGmt(
			termStart,
			Time.newInstance(6, 0, 0, 0)
		);
		policy.ExpirationDate = DateTime.newInstanceGmt(
			termStart.addYears(1),
			Time.newInstance(6, 0, 0, 0)
		);
		insert policy;
		return policy.Id;
	}
}
