/**
 *   @name: PolicyStatusBothChannelsTest
 *   @version: 1.0
 *   @creation date: 29/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: El estado que comunica la aseguradora se aplica igual venga por el
 *                 canal de pagos o por el de polizas: misma poliza, mismas cuotas, mismo plan;
 *                 gana la mas reciente y, en empate, el canal de polizas; la fecha y el motivo
 *                 de la cancelacion viven en la poliza; un cambio de agente es una baja que
 *                 conserva el estado exacto de la aseguradora;
 *                 y la poliza guarda cuando se la vio por ultima vez aunque nada cambie.
 */
@IsTest
private class PolicyStatusBothChannelsTest {
	private static final String POLICY_NUMBER = '0971450001';
	private static final String REASON = 'CANCELACION AUTOMATICA POR FALTA DE PAGO.';
	private static Integer sequence = 0;

	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	/**
	 * @description: Una cancelacion por el canal de polizas deja la poliza como
	 *               la dejaria el canal de pagos: Cancelado con la fecha y el motivo comunicados
	 *               (guardados en la poliza), la cuota posterior cancelada y enlazada a la
	 *               comunicacion, la anterior intacta y el plan cancelado.
	 */
	@IsTest
	static void cancellationThroughThePolicyChannel() {
		useMappings();
		Id policyId = createPolicy();
		Date cancelledOn = termStart().addMonths(2);

		Test.startTest();
		InboundPolicyUpdate__c c = communicate(
			'Cancelada',
			cancelledOn,
			DateTime.now().addHours(-1)
		);
		Test.stopTest();

		InsurancePolicy policy = policy(policyId);
		Assert.areEqual('Cancelado', policy.Status);
		Assert.areEqual('Cancelado', policy.carrierPolicyStatus__c);
		Assert.areEqual('Canal de polizas', policy.carrierStatusSource__c);
		Assert.areEqual(c.Id, policy.carrierStatusPolicyUpdate__c);
		Assert.isNull(policy.carrierStatusNotice__c);
		Assert.areEqual(cancelledOn, policy.carrierCancellationDate__c);
		Assert.areEqual(REASON, policy.carrierCancellationReason__c);
		Assert.areEqual(
			PolicyStatusService.mexicoMidnight(cancelledOn),
			policy.CancellationDate
		);
		Assert.areEqual(REASON, policy.CancellationReason);

		Map<Integer, PaymentPlanInstallment__c> installments = installments(
			policyId
		);
		Assert.areEqual('Pendiente', installments.get(1).installmentStatus__c);
		Assert.areEqual('Cancelado', installments.get(2).installmentStatus__c);
		Assert.areEqual(c.Id, installments.get(2).cancelledByPolicyUpdate__c);
		Assert.areEqual(
			'Cancelado',
			[
				SELECT planStatus__c
				FROM PaymentPlan__c
				WHERE insurancePolicy__c = :policyId
				LIMIT 1
			]
			.planStatus__c
		);
	}

	/**
	 * @description: La rehabilitacion por el canal de polizas reabre solo las cuotas que
	 *               cancelo esa cancelacion y vuelve a activar el plan.
	 */
	@IsTest
	static void rehabilitationReopensOnlyWhatTheCancellationCancelled() {
		useMappings();
		Id policyId = createPolicy();
		communicate(
			'Cancelada',
			termStart().addMonths(2),
			DateTime.now().addHours(-2)
		);

		Test.startTest();
		communicate('Vigor', null, DateTime.now().addHours(-1));
		Test.stopTest();

		Assert.areEqual('Vigente', policy(policyId).Status);
		PaymentPlanInstallment__c second = installments(policyId).get(2);
		Assert.areEqual('Pendiente', second.installmentStatus__c);
		Assert.isNull(second.cancelledByPolicyUpdate__c);
		Assert.isNotNull(second.reopenedFromCancelledOn__c);
	}

	/**
	 * @description: Con la misma fecha de sincronizacion, la comunicacion del canal de pagos
	 *               no pisa el estado que dejo el canal de polizas; una posterior si.
	 */
	@IsTest
	static void onATieThePolicyChannelWins() {
		useMappings();
		Id policyId = createPolicy();
		// Con milisegundos, como DateTime.now(): la poliza los pierde al guardar y aun asi es empate.
		DateTime syncedAt = DateTime.now().addHours(-2);
		communicate('Cancelada', termStart().addMonths(2), syncedAt);
		Id notice = insertNotice();

		Test.startTest();
		PolicyCarrierStatusService.applyCarrierStatus(
			new List<CarrierStatusCommunication>{
				paymentChannel(notice, policyId, 'Vigente', syncedAt)
			}
		);
		Assert.areEqual(
			'Cancelado',
			policy(policyId).carrierPolicyStatus__c,
			'Empate: manda el canal de polizas'
		);

		PolicyCarrierStatusService.applyCarrierStatus(
			new List<CarrierStatusCommunication>{
				paymentChannel(notice, policyId, 'Vigente', syncedAt.addMinutes(1))
			}
		);
		Test.stopTest();

		InsurancePolicy result = policy(policyId);
		Assert.areEqual(
			'Vigente',
			result.carrierPolicyStatus__c,
			'La mas reciente manda'
		);
		Assert.areEqual('Canal de pagos', result.carrierStatusSource__c);
		Assert.areEqual(notice, result.carrierStatusNotice__c);
		Assert.isNull(result.carrierStatusPolicyUpdate__c);
	}

	/**
	 * @description: En la misma tanda, con la misma fecha, se aplica al final la del canal
	 *               de polizas, sea cual sea el orden en que llegan.
	 */
	@IsTest
	static void sameTimestampSortsThePolicyChannelLast() {
		DateTime syncedAt = DateTime.now();
		CarrierStatusCommunication payments = new CarrierStatusCommunication();
		payments.source = CarrierStatusCommunication.SOURCE_PAYMENTS;
		payments.communicatedAt = syncedAt;
		CarrierStatusCommunication policies = new CarrierStatusCommunication();
		policies.source = CarrierStatusCommunication.SOURCE_POLICIES;
		policies.communicatedAt = syncedAt;
		List<CarrierStatusCommunication> ordered = new List<CarrierStatusCommunication>{
			policies,
			payments
		};

		ordered.sort();

		Assert.areEqual(
			CarrierStatusCommunication.SOURCE_POLICIES,
			ordered[1].source
		);
	}

	/**
	 * @description: «Se cambio de agente» se normaliza como Cancelado y conserva el estado
	 *               exacto; sin motivo comunicado, el motivo de la baja es ese estado. Cuotas
	 *               posteriores canceladas y las conciliadas intactas.
	 */
	@IsTest
	static void agentChangeIsATransfer() {
		useMappings();
		Id policyId = createPolicy();
		PaymentPlanInstallment__c first = installments(policyId).get(1);
		first.installmentStatus__c = 'Conciliado';
		update first;

		Test.startTest();
		communicate(
			'Se cambio de agente',
			termStart().addMonths(2),
			DateTime.now().addHours(-1)
		);
		Test.stopTest();

		InsurancePolicy policy = policy(policyId);
		Assert.areEqual('Cancelado', policy.carrierPolicyStatus__c);
		Assert.areEqual('Se cambio de agente', policy.carrierPolicyStatusRaw__c);
		Assert.areEqual('Cancelado', policy.Status);
		Assert.areEqual(
			'Se cambio de agente',
			policy.CancellationReason,
			'Sin motivo, lo explica el estado original'
		);
		Map<Integer, PaymentPlanInstallment__c> installments = installments(
			policyId
		);
		Assert.areEqual('Conciliado', installments.get(1).installmentStatus__c);
		Assert.areEqual('Cancelado', installments.get(2).installmentStatus__c);
		Assert.areEqual(
			'Cancelado',
			[
				SELECT planStatus__c
				FROM PaymentPlan__c
				WHERE insurancePolicy__c = :policyId
				LIMIT 1
			]
			.planStatus__c,
			'Con una cuota pagada y el resto cancelado, el plan queda Cancelado, no Completado'
		);
	}

	/**
	 * @description: La misma cancelacion aplicada dos veces no cancela nada mas ni reabre lo
	 *               que el analista hubiera resuelto.
	 */
	@IsTest
	static void applyingTheSameCancellationTwiceChangesNothing() {
		useMappings();
		Id policyId = createPolicy();
		InboundPolicyUpdate__c c = communicate(
			'Cancelada',
			termStart().addMonths(2),
			DateTime.now().addHours(-1)
		);
		// El analista resuelve a mano la cuota cancelada.
		PaymentPlanInstallment__c second = installments(policyId).get(2);
		second.installmentStatus__c = 'Condonado';
		update second;

		Test.startTest();
		update new InboundPolicyUpdate__c(Id = c.Id, inboundStatus__c = 'Recibido');
		InboundPolicyApplyService.apply(new Set<Id>{ c.Id });
		Test.stopTest();

		Assert.areEqual(
			'Condonado',
			installments(policyId).get(2).installmentStatus__c
		);
		Assert.areEqual('Cancelado', policy(policyId).Status);
	}

	/**
	 * @description: El estado exacto de la aseguradora se guarda siempre, aunque normalice igual:
	 *               de «Vigor» a «Vigor sin Pago de Primas» la poliza sigue Vigente, pero el
	 *               estado original cambia y queda con la fecha de la comunicacion nueva.
	 */
	@IsTest
	static void exactCarrierStatusIsKeptEvenIfItNormalizesTheSame() {
		useMappings();
		Id policyId = createPolicy();
		communicate('Vigor', null, DateTime.now().addHours(-2));
		DateTime later = DateTime.now().addHours(-1);

		Test.startTest();
		communicate('Vigor sin Pago de Primas', null, later);
		Test.stopTest();

		InsurancePolicy policy = policy(policyId);
		Assert.areEqual(
			'Vigor sin Pago de Primas',
			policy.carrierPolicyStatusRaw__c
		);
		Assert.areEqual('Vigente', policy.carrierPolicyStatus__c);
		Assert.areEqual('Vigente', policy.Status);
		Assert.areEqual(later, policy.carrierStatusSyncedAt__c);
	}

	/**
	 * @description: Un estado sin equivalencia se guarda tal cual, el normalizado queda
	 *               vacio, se registra y la poliza no cambia de estado.
	 */
	@IsTest
	static void statusWithoutEquivalenceIsKept() {
		useMappings();
		Id policyId = createPolicy();

		Test.startTest();
		InboundPolicyUpdate__c c = communicate(
			'En tramite',
			null,
			DateTime.now().addHours(-1)
		);
		Test.stopTest();

		InsurancePolicy policy = policy(policyId);
		Assert.areEqual('En tramite', policy.carrierPolicyStatusRaw__c);
		Assert.isNull(policy.carrierPolicyStatus__c);
		Assert.areEqual('Vigente', policy.Status);
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM AppLog__c
				WHERE
					eventCode__c = 'CARRIER_POLICY_STATUS_UNMAPPED'
					AND recordId__c = :String.valueOf(c.Id)
			]
		);
	}

	/**
	 * @description: Un reenvio sin cambios no se vuelve a aplicar, pero deja en la poliza
	 *               la fecha en que la aseguradora la reporto; la fecha del estado no cambia.
	 */
	@IsTest
	static void resendMarksThePolicyAsSeen() {
		useMappings();
		Id policyId = createPolicy();
		String row =
			'[{"sourcePolicyNumber__c":"' +
			POLICY_NUMBER +
			'","sourceCarrierCode__c":"QUALITAS","sourcePolicyStatusRaw__c":"Vigor",' +
			'"sourcePolicyStartDate__c":"' +
			String.valueOf(termStart()) +
			'","sourceSynchronizedAt__c":"%SYNC%"}]';
		InboundPolicyService.receive(row.replace('%SYNC%', '2026-09-01T10:00:00Z'));
		InboundPolicyApplyService.apply(pendingOrAll());
		InsurancePolicy before = policy(policyId);
		Assert.areEqual(
			DateTime.newInstanceGmt(2026, 9, 1, 10, 0, 0),
			before.carrierLastSeenAt__c
		);

		Test.startTest();
		InboundPolicyService.EndpointResult r = InboundPolicyService.receive(
			row.replace('%SYNC%', '2026-09-08T10:00:00Z')
		);
		Test.stopTest();

		Assert.areEqual('RESENT', r.body.results[0].code);
		InsurancePolicy after = policy(policyId);
		Assert.areEqual(
			DateTime.newInstanceGmt(2026, 9, 8, 10, 0, 0),
			after.carrierLastSeenAt__c
		);
		Assert.areEqual(
			before.carrierStatusSyncedAt__c,
			after.carrierStatusSyncedAt__c
		);
	}

	/**
	 * @description: Una poliza que lleva mas dias sin reportarse que los de su aseguradora
	 *               (7 por defecto) queda marcada; una Cancelado no, y una reportada hace poco
	 *               tampoco. Nada cambia su estado.
	 */
	@IsTest
	static void unreportedPoliciesAreFlagged() {
		Id policyId = createPolicy();

		Test.startTest();
		update new InsurancePolicy(
			Id = policyId,
			carrierLastSeenAt__c = DateTime.now().addDays(-30)
		);
		InsurancePolicy stale = policy(policyId);
		update new InsurancePolicy(
			Id = policyId,
			carrierLastSeenAt__c = DateTime.now().addDays(-1)
		);
		InsurancePolicy fresh = policy(policyId);
		Test.stopTest();

		Assert.isTrue(stale.carrierUnreported__c);
		Assert.isTrue(stale.carrierDaysUnreported__c >= 29);
		Assert.areEqual('Vigente', stale.Status);
		Assert.isFalse(fresh.carrierUnreported__c);
	}

	private static void useMappings() {
		PolicyCarrierStatusService.mappingsForTest = new Map<String, String>{
			PolicyCarrierStatusService.mappingKey(
				'QUALITAS',
				'Cancelada'
			) => 'Cancelado',
			PolicyCarrierStatusService.mappingKey('QUALITAS', 'Vigor') => 'Vigente',
			PolicyCarrierStatusService.mappingKey(
				'QUALITAS',
				'Vigor sin Pago de Primas'
			) => 'Vigente',
			PolicyCarrierStatusService.mappingKey('QUALITAS', 'Vigente') => 'Vigente',
			PolicyCarrierStatusService.mappingKey(
				'QUALITAS',
				'Se cambio de agente'
			) => 'Cancelado'
		};
	}

	private static Date termStart() {
		return Date.today().addMonths(-3);
	}

	private static Id createPolicy() {
		InsurancePolicy policy = CollectionsTestDataFactory.buildCompletePolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Vigente',
			'Semestral',
			1200,
			termStart()
		);
		policy.Name = POLICY_NUMBER;
		policy.EffectiveDate = PolicyStatusService.mexicoMidnight(termStart());
		policy.ExpirationDate = PolicyStatusService.mexicoMidnight(
			termStart().addYears(1)
		);
		insert policy;
		return policy.Id;
	}

	/**
	 * Guarda una comunicacion del canal de polizas y la aplica (dentro de un Test.startTest,
	 * el Test.stopTest la termina de procesar).
	 */
	private static InboundPolicyUpdate__c communicate(
		String rawStatus,
		Date cancelledOn,
		DateTime syncedAt
	) {
		sequence++;
		InboundPolicyUpdate__c c = new InboundPolicyUpdate__c(
			sourcePolicyNumber__c = POLICY_NUMBER,
			sourcePolicyStartDate__c = termStart(),
			sourceCarrierCode__c = 'QUALITAS',
			sourcePolicyStatusRaw__c = rawStatus,
			sourceCancellationDate__c = cancelledOn,
			// Solo la cancelacion trae motivo: el cambio de agente llega sin el, para probar que
			// entonces el motivo de la baja es el estado original.
			sourceCancellationReason__c = rawStatus == 'Cancelada' ? REASON : null,
			sourceSynchronizedAt__c = syncedAt,
			inboundStatus__c = 'Recibido',
			contentFingerprint__c = 'kan450-' + sequence,
			receivedAt__c = System.now()
		);
		insert c;
		InboundPolicyApplyService.apply(new Set<Id>{ c.Id });
		return c;
	}

	private static Set<Id> pendingOrAll() {
		return new Map<Id, InboundPolicyUpdate__c>(
				[SELECT Id FROM InboundPolicyUpdate__c]
			)
			.keySet();
	}

	private static Id insertNotice() {
		InboundInsurancePayment__c notice = new InboundInsurancePayment__c(
			policyStatusNotice__c = true,
			inboundStatus__c = 'Estado de poliza',
			sourcePolicyNumber__c = POLICY_NUMBER,
			sourceCarrierCode__c = 'QUALITAS',
			sourcePolicyStatusRaw__c = 'Vigente',
			receivedAt__c = System.now()
		);
		insert notice;
		return notice.Id;
	}

	private static CarrierStatusCommunication paymentChannel(
		Id noticeId,
		Id policyId,
		String rawStatus,
		DateTime syncedAt
	) {
		CarrierStatusCommunication c = new CarrierStatusCommunication();
		c.sourceRecordId = noticeId;
		c.policyId = policyId;
		c.source = CarrierStatusCommunication.SOURCE_PAYMENTS;
		c.carrierCode = 'QUALITAS';
		c.rawStatus = rawStatus;
		c.communicatedAt = syncedAt;
		return c;
	}

	private static InsurancePolicy policy(Id policyId) {
		return [
			SELECT
				Id,
				Status,
				CancellationDate,
				CancellationReason,
				carrierPolicyStatus__c,
				carrierPolicyStatusRaw__c,
				carrierStatusSyncedAt__c,
				carrierStatusSource__c,
				carrierStatusNotice__c,
				carrierStatusPolicyUpdate__c,
				carrierCancellationDate__c,
				carrierCancellationReason__c,
				carrierLastSeenAt__c,
				carrierDaysUnreported__c,
				carrierUnreported__c
			FROM InsurancePolicy
			WHERE Id = :policyId
		];
	}

	private static Map<Integer, PaymentPlanInstallment__c> installments(
		Id policyId
	) {
		Map<Integer, PaymentPlanInstallment__c> result = new Map<Integer, PaymentPlanInstallment__c>();
		for (PaymentPlanInstallment__c i : [
			SELECT
				Id,
				sequenceNumber__c,
				installmentStatus__c,
				cancelledByPolicyUpdate__c,
				reopenedFromCancelledOn__c
			FROM PaymentPlanInstallment__c
			WHERE
				paymentPlan__r.insurancePolicy__c = :policyId
				AND paymentPlan__r.planStatus__c != 'Reemplazado'
		]) {
			result.put(i.sequenceNumber__c.intValue(), i);
		}
		return result;
	}
}
