/**
 *   @name: PolicyStatusFromCarrierTest
 *   @version: 1.0
 *   @creation date: 17/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Verifica que el estado operativo de la poliza refleja lo que comunica la
 *                 aseguradora: la cancelacion manda, la rehabilitacion la devuelve a vigente, un
 *                 "vigente" sobre una vigencia terminada la deja vencida, las cuotas y el plan
 *                 siguen a la poliza, un cobro de una poliza cancelada queda para revision y
 *                 aplicarlo dos veces no cambia nada.
 */
@IsTest
private class PolicyStatusFromCarrierTest {
	private static final String POLICY_NUMBER = 'POL-439-01';
	private static final Date CANCELLED_ON = Date.newInstance(2026, 6, 6);
	private static final String CANCELLATION_REASON = 'CANCELACION AUTOMATICA POR FALTA DE PAGO.';

	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	/**
	 * @description: La cancelacion comunicada deja la poliza cancelada, con la fecha y el motivo
	 *               que informo la aseguradora.
	 */
	@IsTest
	static void communicatedCancellationCancelsThePolicy() {
		Escenario e = nuevoEscenario('Vigente');

		Test.startTest();
		comunicar(
			e,
			'Cancelado',
			'Cancelada',
			CANCELLED_ON,
			DateTime.newInstanceGmt(2026, 9, 16, 16, 0, 0)
		);
		Test.stopTest();

		InsurancePolicy policy = poliza(e.policyId);
		Assert.areEqual('Cancelado', policy.Status);
		Assert.areEqual(CANCELLED_ON, policy.CancellationDate.dateGmt());
		Assert.areEqual(CANCELLATION_REASON, policy.CancellationReason);
	}

	/**
	 * @description: Al cancelar, dejan de deberse las cuotas que vencen despues de la cancelacion;
	 *               las anteriores sin pagar y las pagadas no se tocan, y el plan queda cancelado.
	 */
	@IsTest
	static void onlyInstallmentsDueAfterTheCancellationAreCancelled() {
		Escenario e = nuevoEscenario('Vigente');

		Test.startTest();
		comunicar(
			e,
			'Cancelado',
			'Cancelada',
			CANCELLED_ON,
			DateTime.newInstanceGmt(2026, 9, 16, 16, 0, 0)
		);
		Test.stopTest();

		Map<Integer, PaymentPlanInstallment__c> cuotas = cuotasPorSecuencia(
			e.policyId
		);
		Assert.areEqual(
			'Pendiente',
			cuotas.get(1).installmentStatus__c,
			'La anterior a la cancelacion se queda'
		);
		Assert.isNull(cuotas.get(1).cancelledByCarrierNotice__c);
		Assert.areEqual(
			'Cancelado',
			cuotas.get(2).installmentStatus__c,
			'La posterior deja de deberse'
		);
		Assert.areEqual(e.noticeId, cuotas.get(2).cancelledByCarrierNotice__c);
		Assert.areEqual('Cancelado', cuotas.get(3).installmentStatus__c);
		Assert.areEqual(
			'Conciliado',
			cuotas.get(4).installmentStatus__c,
			'Una cuota pagada no se toca'
		);
		Assert.areEqual(
			'Cancelado',
			[SELECT planStatus__c FROM PaymentPlan__c WHERE Id = :e.planId]
			.planStatus__c
		);
	}

	/**
	 * @description: La rehabilitacion devuelve la poliza a vigente, limpia su cancelacion, vuelve a
	 *               deber solo las cuotas que esa cancelacion habia cancelado y reactiva el plan.
	 */
	@IsTest
	static void rehabilitationRestoresThePolicyAndItsInstallments() {
		Escenario e = nuevoEscenario('Vigente');
		comunicar(
			e,
			'Cancelado',
			'Cancelada',
			CANCELLED_ON,
			DateTime.newInstanceGmt(2026, 9, 16, 16, 0, 0)
		);
		Assert.areEqual(
			'Cancelado',
			poliza(e.policyId).Status,
			'Setup: la poliza quedo cancelada'
		);

		Test.startTest();
		comunicar(
			e,
			'Vigente',
			'Vigente',
			null,
			DateTime.newInstanceGmt(2026, 9, 18, 16, 0, 0)
		);
		Test.stopTest();

		InsurancePolicy policy = poliza(e.policyId);
		Assert.areEqual('Vigente', policy.Status);
		Assert.isNull(policy.CancellationDate);
		Assert.isNull(policy.CancellationReason);
		Map<Integer, PaymentPlanInstallment__c> cuotas = cuotasPorSecuencia(
			e.policyId
		);
		Assert.areEqual('Pendiente', cuotas.get(2).installmentStatus__c);
		Assert.isNull(cuotas.get(2).cancelledByCarrierNotice__c);
		Assert.isNotNull(cuotas.get(2).reopenedFromCancelledOn__c);
		Assert.areEqual('Pendiente', cuotas.get(3).installmentStatus__c);
		Assert.areEqual(
			'Conciliado',
			cuotas.get(4).installmentStatus__c,
			'La pagada sigue pagada'
		);
		Assert.areEqual(
			'Activo',
			[SELECT planStatus__c FROM PaymentPlan__c WHERE Id = :e.planId]
			.planStatus__c
		);
	}

	/**
	 * @description: Un "vigente" comunicado sobre una vigencia ya terminada deja la poliza vencida,
	 *               no vigente.
	 */
	@IsTest
	static void communicatedActiveOnAnEndedTermLeavesThePolicyExpired() {
		Escenario e = nuevoEscenario('Vigente', Date.today().addDays(-10));

		Test.startTest();
		comunicar(
			e,
			'Vigente',
			'Vigente',
			null,
			DateTime.newInstanceGmt(2026, 9, 18, 16, 0, 0)
		);
		Test.stopTest();

		Assert.areEqual('Vencido', poliza(e.policyId).Status);
	}

	/**
	 * @description: Aplicar dos veces la misma cancelacion no cancela mas cuotas ni cambia nada.
	 */
	@IsTest
	static void applyingTheSameCancellationTwiceChangesNothing() {
		Escenario e = nuevoEscenario('Vigente');
		comunicar(
			e,
			'Cancelado',
			'Cancelada',
			CANCELLED_ON,
			DateTime.newInstanceGmt(2026, 9, 16, 16, 0, 0)
		);
		Map<Integer, PaymentPlanInstallment__c> antes = cuotasPorSecuencia(
			e.policyId
		);

		Test.startTest();
		PolicyStatusService.applyCommunicatedStatus(new Set<Id>{ e.policyId });
		Integer dmlUsado = Limits.getDmlStatements();
		Test.stopTest();

		Assert.areEqual(0, dmlUsado, 'La segunda vez no guarda nada');
		Map<Integer, PaymentPlanInstallment__c> despues = cuotasPorSecuencia(
			e.policyId
		);
		for (Integer seq : antes.keySet()) {
			Assert.areEqual(
				antes.get(seq).installmentStatus__c,
				despues.get(seq).installmentStatus__c,
				'La cuota ' + seq + ' no cambia'
			);
		}
		Assert.areEqual('Cancelado', poliza(e.policyId).Status);
	}

	/**
	 * @description: Un cobro de una poliza que la aseguradora da por cancelada queda para revision
	 *               manual, con el motivo, y no sigue al eslabon siguiente del circuito.
	 */
	@IsTest
	static void paymentOnACancelledPolicyGoesToManualReview() {
		Escenario e = nuevoEscenario('Vigente');
		comunicar(
			e,
			'Cancelado',
			'Cancelada',
			CANCELLED_ON,
			DateTime.newInstanceGmt(2026, 9, 16, 16, 0, 0)
		);
		InboundInsurancePayment__c pago = new InboundInsurancePayment__c(
			externalPaymentId__c = 'QUALITAS_R43901',
			inboundStatus__c = 'Normalizado',
			sourcePolicyNumber__c = POLICY_NUMBER,
			sourceCarrierCode__c = 'QUALITAS',
			sourceReceiptNumber__c = 'R43901',
			sourceAmount__c = 500,
			sourcePaymentDate__c = Date.today(),
			sourceDueDate__c = Date.today(),
			receivedAt__c = System.now()
		);
		insert pago;

		Test.startTest();
		System.enqueueJob(
			new InboundPolicyCandidateQueueable(new Set<Id>{ pago.Id })
		);
		Test.stopTest();

		InboundInsurancePayment__c despues = [
			SELECT
				inboundStatus__c,
				manualReviewRequired__c,
				manualReviewReason__c,
				candidatePolicy__c,
				candidateInstallment__c
			FROM InboundInsurancePayment__c
			WHERE Id = :pago.Id
		];
		Assert.areEqual('Revision Manual', despues.inboundStatus__c);
		Assert.isTrue(despues.manualReviewRequired__c);
		Assert.isTrue(
			despues.manualReviewReason__c.contains('cancelada'),
			despues.manualReviewReason__c
		);
		Assert.areEqual(
			e.policyId,
			despues.candidatePolicy__c,
			'La poliza si se identifica'
		);
		Assert.isNull(
			despues.candidateInstallment__c,
			'No sigue al eslabon de la cuota'
		);
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM AppLog__c
				WHERE eventCode__c = :CobranzaLog.EVENT_PAYMENT_ON_CANCELLED_POLICY
			]
		);
	}

	/**
	 * @description: Cerrar la oportunidad no revive una poliza que la aseguradora dio por cancelada:
	 *               el paso a Vigente del cierre solo aplica a polizas en Inicial.
	 */
	@IsTest
	static void closingTheOpportunityDoesNotRevivePolicy() {
		Escenario e = nuevoEscenario('Inicial');
		Opportunity opp = new Opportunity(
			Name = 'OPP-439',
			AccountId = CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			StageName = 'Póliza',
			CloseDate = Date.today().addMonths(1),
			Agente_Relacionado__c = CollectionsTestDataFactory.getOrCreateAgenteId(),
			Ramo__c = 'Automoviles'
		);
		insert opp;
		update new InsurancePolicy(Id = e.policyId, SourceOpportunityId = opp.Id);
		comunicar(
			e,
			'Cancelado',
			'Cancelada',
			CANCELLED_ON,
			DateTime.newInstanceGmt(2026, 9, 16, 16, 0, 0)
		);

		Test.startTest();
		insert reciboReconocido(e.policyId);
		Test.stopTest();

		Assert.areEqual(
			'Cancelado',
			poliza(e.policyId).Status,
			'La poliza cancelada por la aseguradora no vuelve a Vigente al cerrar la oportunidad'
		);
	}

	/**
	 * @description: Si una poliza no se puede guardar, las demas se aplican y el fallo queda
	 *               registrado.
	 */
	@IsTest
	static void failureOnOnePolicyDoesNotStopTheOthers() {
		Escenario falla = nuevoEscenario('Vigente');
		Escenario sana = nuevoEscenario(
			'Vigente',
			Date.today().addYears(1),
			'POL-439-02'
		);
		prepararComunicacion(
			falla,
			'Cancelado',
			'Cancelada',
			CANCELLED_ON,
			DateTime.newInstanceGmt(2026, 9, 16, 16, 0, 0)
		);
		prepararComunicacion(
			sana,
			'Cancelado',
			'Cancelada',
			CANCELLED_ON,
			DateTime.newInstanceGmt(2026, 9, 16, 16, 0, 0)
		);
		PolicyStatusService.failForTest.add(falla.policyId);

		Test.startTest();
		PolicyStatusService.applyCommunicatedStatus(
			new Set<Id>{ falla.policyId, sana.policyId }
		);
		AppLogger.flush();
		Test.stopTest();

		Assert.areEqual(
			'Vigente',
			poliza(falla.policyId).Status,
			'La que falla no cambia'
		);
		Assert.areEqual('Cancelado', poliza(sana.policyId).Status);
		Assert.areEqual(
			'Pendiente',
			cuotasPorSecuencia(falla.policyId).get(2).installmentStatus__c,
			'Si la poliza no se guardo, sus cuotas tampoco se cancelan'
		);
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM AppLog__c
				WHERE eventCode__c = :CobranzaLog.EVENT_POLICY_STATUS_UPDATE_FAILED
			]
		);
	}

	// ------------------------------------------------------------------ apoyo
	private class Escenario {
		Id policyId;
		Id planId;
		Id noticeId;
	}

	private static Escenario nuevoEscenario(String status) {
		return nuevoEscenario(status, Date.today().addYears(1), POLICY_NUMBER);
	}

	private static Escenario nuevoEscenario(String status, Date finVigencia) {
		return nuevoEscenario(status, finVigencia, POLICY_NUMBER);
	}

	private static Escenario nuevoEscenario(
		String status,
		Date finVigencia,
		String numero
	) {
		Escenario e = new Escenario();
		InsurancePolicy policy = CollectionsTestDataFactory.buildCompletePolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			status,
			'Mensual',
			1200,
			Date.today()
		);
		policy.Name = numero;
		policy.EffectiveDate = DateTime.newInstanceGmt(
			finVigencia.addYears(-1),
			Time.newInstance(6, 0, 0, 0)
		);
		policy.ExpirationDate = DateTime.newInstanceGmt(
			finVigencia,
			Time.newInstance(6, 0, 0, 0)
		);
		insert policy;
		e.policyId = policy.Id;

		// El trigger de la poliza le crea su plan inicial; si no, se crea aqui. Las cuotas que
		// hubiera generado se borran para que el escenario sea exactamente el que se quiere probar.
		List<PaymentPlan__c> planes = [
			SELECT Id
			FROM PaymentPlan__c
			WHERE insurancePolicy__c = :policy.Id
			LIMIT 1
		];
		PaymentPlan__c plan;
		if (planes.isEmpty()) {
			plan = new PaymentPlan__c(
				insurancePolicy__c = policy.Id,
				planType__c = 'Inicial',
				planStatus__c = 'Activo',
				premiumFrequency__c = 'Mensual',
				expectedTotalAmount__c = 1200
			);
			insert plan;
		} else {
			plan = planes[0];
		}
		e.planId = plan.Id;
		List<PaymentPlanInstallment__c> generadas = [
			SELECT Id
			FROM PaymentPlanInstallment__c
			WHERE paymentPlan__c = :plan.Id
		];
		if (!generadas.isEmpty()) {
			delete generadas;
		}

		List<PaymentPlanInstallment__c> cuotas = new List<PaymentPlanInstallment__c>{
			cuota(plan.Id, 1, CANCELLED_ON.addMonths(-1), 'Pendiente'),
			cuota(plan.Id, 2, CANCELLED_ON.addMonths(1), 'Pendiente'),
			cuota(plan.Id, 3, CANCELLED_ON.addMonths(2), 'Vencido'),
			cuota(plan.Id, 4, CANCELLED_ON.addMonths(-2), 'Conciliado')
		};
		insert cuotas;
		return e;
	}

	private static PaymentPlanInstallment__c cuota(
		Id planId,
		Integer secuencia,
		Date vencimiento,
		String estado
	) {
		return new PaymentPlanInstallment__c(
			paymentPlan__c = planId,
			sequenceNumber__c = secuencia,
			dueDate__c = vencimiento,
			expectedAmount__c = 300,
			installmentStatus__c = estado
		);
	}

	private static void prepararComunicacion(
		Escenario e,
		String normalizado,
		String original,
		Date fechaCancelacion,
		DateTime comunicadoEl
	) {
		InboundInsurancePayment__c notice = new InboundInsurancePayment__c(
			policyStatusNotice__c = true,
			inboundStatus__c = 'Estado de poliza',
			sourcePolicyNumber__c = [
				SELECT Name
				FROM InsurancePolicy
				WHERE Id = :e.policyId
			]
			.Name,
			sourceCarrierCode__c = 'QUALITAS',
			sourcePolicyStatusRaw__c = original,
			sourceCancellationDate__c = fechaCancelacion,
			sourceCancellationReason__c = fechaCancelacion == null
				? null
				: CANCELLATION_REASON,
			sourceSynchronizedAt__c = comunicadoEl,
			receivedAt__c = System.now(),
			candidatePolicy__c = e.policyId
		);
		insert notice;
		e.noticeId = notice.Id;
		update new InsurancePolicy(
			Id = e.policyId,
			carrierPolicyStatus__c = normalizado,
			carrierPolicyStatusRaw__c = original,
			carrierStatusSyncedAt__c = comunicadoEl,
			carrierStatusNotice__c = notice.Id
		);
	}

	private static void comunicar(
		Escenario e,
		String normalizado,
		String original,
		Date fechaCancelacion,
		DateTime comunicadoEl
	) {
		prepararComunicacion(
			e,
			normalizado,
			original,
			fechaCancelacion,
			comunicadoEl
		);
		PolicyStatusService.applyCommunicatedStatus(new Set<Id>{ e.policyId });
	}

	private static PolicyPaymentReceipt__c reciboReconocido(Id policyId) {
		String unico = String.valueOf(Math.abs(Crypto.getRandomInteger()));
		InboundInsurancePayment__c inbound = new InboundInsurancePayment__c(
			externalPaymentId__c = 'EXT-439-' + unico,
			inboundStatus__c = 'Conciliado',
			candidatePolicy__c = policyId,
			sourceAmount__c = 300,
			sourcePaymentDate__c = Date.today(),
			sourcePolicyNumber__c = POLICY_NUMBER,
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
			receiptStatus__c = 'Reconocido',
			receiptDate__c = Date.today(),
			receiptAmount__c = 300
		);
	}

	private static InsurancePolicy poliza(Id policyId) {
		return [
			SELECT
				Id,
				Status,
				CancellationDate,
				CancellationReason,
				carrierPolicyStatus__c
			FROM InsurancePolicy
			WHERE Id = :policyId
		];
	}

	private static Map<Integer, PaymentPlanInstallment__c> cuotasPorSecuencia(
		Id policyId
	) {
		Map<Integer, PaymentPlanInstallment__c> result = new Map<Integer, PaymentPlanInstallment__c>();
		for (PaymentPlanInstallment__c i : [
			SELECT
				Id,
				sequenceNumber__c,
				installmentStatus__c,
				cancelledByCarrierNotice__c,
				reopenedFromCancelledOn__c
			FROM PaymentPlanInstallment__c
			WHERE paymentPlan__r.insurancePolicy__c = :policyId
		]) {
			result.put(i.sequenceNumber__c.intValue(), i);
		}
		return result;
	}
}
