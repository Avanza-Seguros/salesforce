/**
 *   @name: PolicyPaymentReceiptReversalServiceTest
 *   @version: 1.0
 *   @creation date: 30/07/2026
 *   @author: Javier Torres - Volestra
 *   @description: Pruebas de la reversa de un recibo reconocido (H201): validaciones de la
 *                 accion, sellado de autoria, terminalidad, retorno de la conciliacion y del
 *                 pago inbound al circuito de revision, tolerancia a recibos sin conciliacion,
 *                 comportamiento en lote y habilitacion del reproceso de la historia 195.
 */
@IsTest
private class PolicyPaymentReceiptReversalServiceTest {
	private static final String RECEIPT_RECOGNIZED = 'Reconocido';
	private static final String RECEIPT_REVERSED = 'Reversado';
	private static final String RECEIPT_PENDING = 'Pendiente de confirmacion';
	private static final String RECON_RECONCILED = 'Conciliado';
	private static final String RECON_REVIEW = 'Requiere revision';
	private static final String INBOUND_RECONCILED = 'Conciliado';
	private static final String INBOUND_MANUAL_REVIEW = 'Revision Manual';
	private static final String REASON = 'Rechazo bancario';
	private static final String NOTES = 'El banco devolvió el cargo por fondos insuficientes.';

	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	/**
	 * @description: Crea la cadena completa del lado del pago: poliza, pago inbound conciliado,
	 *               conciliacion sellada manualmente y recibo reconocido.
	 * @param suffix: Sufijo para que los identificadores externos no colisionen entre casos.
	 * @return El recibo reconocido, listo para reversar.
	 */
	private static PolicyPaymentReceipt__c buildReconciledChain(String suffix) {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = CollectionsTestDataFactory.createPolicy(
			accountId,
			'Cancelado'
		);

		InboundInsurancePayment__c inbound = new InboundInsurancePayment__c(
			externalPaymentId__c = 'EXT-REV-' + suffix,
			inboundStatus__c = INBOUND_RECONCILED,
			sourceAmount__c = 500,
			sourcePaymentDate__c = Date.today(),
			sourcePolicyNumber__c = 'POL-REV-' + suffix,
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now()
		);
		insert inbound;

		PaymentReconciliation__c recon = new PaymentReconciliation__c(
			inboundPayment__c = inbound.Id,
			insurancePolicy__c = policy.Id,
			reconciliationStatus__c = RECON_RECONCILED,
			manualResolvedBy__c = UserInfo.getUserId(),
			manualResolvedAt__c = System.now()
		);
		insert recon;

		PolicyPaymentReceipt__c receipt = new PolicyPaymentReceipt__c(
			insurancePolicy__c = policy.Id,
			sourceInboundPayment__c = inbound.Id,
			paymentReconciliation__c = recon.Id,
			receiptDate__c = Date.today(),
			receiptAmount__c = 500,
			receiptStatus__c = RECEIPT_RECOGNIZED,
			receiptNumber__c = 'REC-' + suffix
		);
		insert receipt;

		update new PaymentReconciliation__c(
			Id = recon.Id,
			resultingReceipt__c = receipt.Id
		);

		return receipt;
	}

	/**
	 * @description: Un recibo reconocido se reversa conservando su importe, fecha y numero, y
	 *               queda sellado con quien lo reverso, cuando, el motivo y las notas.
	 */
	@IsTest
	static void reversesRecognizedReceiptAndKeepsEvidence() {
		PolicyPaymentReceipt__c receipt = buildReconciledChain('01');

		Test.startTest();
		PolicyPaymentReceiptReversalService.reverse(receipt.Id, REASON, NOTES);
		Test.stopTest();

		PolicyPaymentReceipt__c reversed = [
			SELECT
				receiptStatus__c,
				receiptAmount__c,
				receiptNumber__c,
				reversalReason__c,
				reversalNotes__c,
				reversedBy__c,
				reversedAt__c
			FROM PolicyPaymentReceipt__c
			WHERE Id = :receipt.Id
		];
		Assert.areEqual(
			RECEIPT_REVERSED,
			reversed.receiptStatus__c,
			'El recibo debe quedar reversado'
		);
		Assert.areEqual(
			500,
			reversed.receiptAmount__c,
			'El importe original se conserva como evidencia'
		);
		Assert.areEqual(
			'REC-01',
			reversed.receiptNumber__c,
			'El número original se conserva'
		);
		Assert.areEqual(
			REASON,
			reversed.reversalReason__c,
			'Debe guardar el motivo'
		);
		Assert.areEqual(NOTES, reversed.reversalNotes__c, 'Debe guardar las notas');
		Assert.areEqual(
			UserInfo.getUserId(),
			reversed.reversedBy__c,
			'Debe sellar quién reversó'
		);
		Assert.isNotNull(reversed.reversedAt__c, 'Debe sellar cuándo se reversó');
	}

	/**
	 * @description: La conciliacion vuelve a la bandeja, libera el sello de resolucion manual
	 *               y SUELTA el puntero al recibo vigente, porque ya no tiene uno. Sin soltarlo
	 *               un reproceso posterior no podria generar el recibo nuevo y la cuota
	 *               quedaria abierta para siempre.
	 *               La evidencia no se pierde: el recibo reversado conserva su propio vinculo a
	 *               la conciliacion y se sigue viendo desde ella.
	 */
	@IsTest
	static void reconciliationReturnsToReviewAndReleasesReceipt() {
		PolicyPaymentReceipt__c receipt = buildReconciledChain('02');
		Id reconId = [
			SELECT Id
			FROM PaymentReconciliation__c
			WHERE resultingReceipt__c = :receipt.Id
		]
		.Id;

		Test.startTest();
		PolicyPaymentReceiptReversalService.reverse(receipt.Id, REASON, NOTES);
		Test.stopTest();

		PaymentReconciliation__c recon = [
			SELECT
				reconciliationStatus__c,
				resultingReceipt__c,
				manualResolvedBy__c,
				manualResolvedAt__c
			FROM PaymentReconciliation__c
			WHERE Id = :reconId
		];
		Assert.areEqual(
			RECON_REVIEW,
			recon.reconciliationStatus__c,
			'La conciliación debe volver a la bandeja de revisión'
		);
		Assert.isNull(
			recon.resultingReceipt__c,
			'Debe soltar el recibo vigente para que un reproceso pueda generar uno nuevo'
		);
		Assert.isNull(
			recon.manualResolvedBy__c,
			'Debe liberarse el sello de resolución manual'
		);
		Assert.isNull(
			recon.manualResolvedAt__c,
			'Debe liberarse la fecha de resolución manual'
		);
		Assert.areEqual(
			reconId,
			[
				SELECT paymentReconciliation__c
				FROM PolicyPaymentReceipt__c
				WHERE Id = :receipt.Id
			]
			.paymentReconciliation__c,
			'El recibo reversado sigue vinculado a su conciliación: la evidencia se conserva'
		);
	}

	/**
	 * @description: El pago inbound vuelve al circuito de revision manual.
	 */
	@IsTest
	static void inboundReturnsToManualReview() {
		PolicyPaymentReceipt__c receipt = buildReconciledChain('03');

		Test.startTest();
		PolicyPaymentReceiptReversalService.reverse(receipt.Id, REASON, NOTES);
		Test.stopTest();

		Assert.areEqual(
			INBOUND_MANUAL_REVIEW,
			[
				SELECT inboundStatus__c
				FROM InboundInsurancePayment__c
				WHERE externalPaymentId__c = 'EXT-REV-03'
			]
			.inboundStatus__c,
			'El pago inbound debe volver al circuito de revisión'
		);
	}

	/**
	 * @description: H201 CA7: una conciliacion puede acumular varios recibos a lo largo del
	 *               tiempo -por ejemplo tras un reproceso- y solo uno es el vigente. Reversar
	 *               un recibo que ya fue reemplazado no debe devolver el caso a la bandeja: la
	 *               conciliacion sigue sostenida por su recibo vigente y el analista no tiene
	 *               nada que revisar.
	 */
	@IsTest
	static void doesNotReopenReconciliationWhenReceiptIsNotTheCurrentOne() {
		PolicyPaymentReceipt__c supersededReceipt = buildReconciledChain('09');
		Id reconId = [
			SELECT paymentReconciliation__c
			FROM PolicyPaymentReceipt__c
			WHERE Id = :supersededReceipt.Id
		]
		.paymentReconciliation__c;
		Id policyId = [
			SELECT insurancePolicy__c
			FROM PolicyPaymentReceipt__c
			WHERE Id = :supersededReceipt.Id
		]
		.insurancePolicy__c;

		// Un recibo posterior toma el lugar del primero como recibo vigente del caso.
		PolicyPaymentReceipt__c currentReceipt = new PolicyPaymentReceipt__c(
			insurancePolicy__c = policyId,
			paymentReconciliation__c = reconId,
			receiptDate__c = Date.today(),
			receiptAmount__c = 500,
			receiptStatus__c = RECEIPT_RECOGNIZED,
			receiptNumber__c = 'REC-09-VIGENTE'
		);
		insert currentReceipt;
		update new PaymentReconciliation__c(
			Id = reconId,
			resultingReceipt__c = currentReceipt.Id
		);

		Test.startTest();
		PolicyPaymentReceiptReversalService.reverse(
			supersededReceipt.Id,
			REASON,
			NOTES
		);
		Test.stopTest();

		PaymentReconciliation__c recon = [
			SELECT reconciliationStatus__c, resultingReceipt__c
			FROM PaymentReconciliation__c
			WHERE Id = :reconId
		];
		Assert.areEqual(
			RECON_RECONCILED,
			recon.reconciliationStatus__c,
			'La conciliación no debe volver a la bandeja: su recibo vigente sigue en pie'
		);
		Assert.areEqual(
			currentReceipt.Id,
			recon.resultingReceipt__c,
			'El recibo vigente no debe soltarse al reversar uno anterior'
		);
		Assert.areEqual(
			INBOUND_RECONCILED,
			[
				SELECT inboundStatus__c
				FROM InboundInsurancePayment__c
				WHERE externalPaymentId__c = 'EXT-REV-09'
			]
			.inboundStatus__c,
			'El pago inbound tampoco debe volver al circuito de revisión'
		);
		Assert.areEqual(
			RECEIPT_REVERSED,
			[
				SELECT receiptStatus__c
				FROM PolicyPaymentReceipt__c
				WHERE Id = :supersededReceipt.Id
			]
			.receiptStatus__c,
			'El recibo reemplazado sí queda reversado'
		);
	}

	/**
	 * @description: El modelo NO admite un recibo sin conciliacion: paymentReconciliation__c
	 *               es obligatorio. Se deja constancia con una prueba porque tiene dos
	 *               consecuencias de diseno: el escenario "recibo suelto" no puede darse en
	 *               produccion, y la carga masiva de cartera historica esta obligada a sembrar
	 *               la cadena completa -pago inbound, conciliacion y recibo-, no solo recibos.
	 */
	@IsTest
	static void receiptCannotExistWithoutReconciliation() {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		InsurancePolicy policy = CollectionsTestDataFactory.createPolicy(
			accountId,
			'Cancelado'
		);

		Test.startTest();
		String errorMessage;
		try {
			insert new PolicyPaymentReceipt__c(
				insurancePolicy__c = policy.Id,
				receiptDate__c = Date.today(),
				receiptAmount__c = 300,
				receiptStatus__c = RECEIPT_RECOGNIZED,
				receiptNumber__c = 'REC-SUELTO'
			);
		} catch (DmlException e) {
			errorMessage = e.getMessage();
		}
		Test.stopTest();

		Assert.isNotNull(
			errorMessage,
			'El modelo debe impedir crear un recibo sin conciliación'
		);
		Assert.isTrue(
			errorMessage.contains('paymentReconciliation__c'),
			'El error debe señalar la conciliación faltante'
		);
	}

	/**
	 * @description: La reversa es terminal: la regla de validacion impide devolver el recibo a
	 *               Reconocido por cualquier via, incluida la edicion directa del campo.
	 */
	@IsTest
	static void reversalIsTerminalAndCannotBeUndone() {
		PolicyPaymentReceipt__c receipt = buildReconciledChain('04');
		PolicyPaymentReceiptReversalService.reverse(receipt.Id, REASON, NOTES);

		Test.startTest();
		String errorMessage;
		try {
			update new PolicyPaymentReceipt__c(
				Id = receipt.Id,
				receiptStatus__c = RECEIPT_RECOGNIZED
			);
		} catch (DmlException e) {
			errorMessage = e.getMessage();
		}
		Test.stopTest();

		Assert.isNotNull(
			errorMessage,
			'Devolver un recibo reversado a Reconocido debe estar impedido'
		);
		Assert.areEqual(
			RECEIPT_REVERSED,
			[
				SELECT receiptStatus__c
				FROM PolicyPaymentReceipt__c
				WHERE Id = :receipt.Id
			]
			.receiptStatus__c,
			'El recibo debe seguir reversado'
		);
	}

	/**
	 * @description: Reversar un recibo ya reversado se rechaza con un mensaje claro y no
	 *               produce ningun efecto adicional.
	 */
	@IsTest
	static void doesNotReverseTwice() {
		PolicyPaymentReceipt__c receipt = buildReconciledChain('05');
		PolicyPaymentReceiptReversalService.reverse(receipt.Id, REASON, NOTES);

		Test.startTest();
		String errorMessage;
		try {
			PolicyPaymentReceiptReversalService.reverseReceipt(
				receipt.Id,
				REASON,
				NOTES
			);
		} catch (Exception e) {
			errorMessage = e.getMessage();
		}
		Test.stopTest();

		Assert.isNotNull(errorMessage, 'La segunda reversa debe rechazarse');
		Assert.isTrue(
			errorMessage.contains('ya está reversado'),
			'El mensaje debe explicar que la reversa es definitiva'
		);
	}

	/**
	 * @description: Solo se reversa lo reconocido: un recibo pendiente de confirmacion no
	 *               produjo efectos que haya que deshacer.
	 */
	@IsTest
	static void doesNotReverseNonRecognizedReceipt() {
		PolicyPaymentReceipt__c reconciledReceipt = buildReconciledChain('08');
		PolicyPaymentReceipt__c receipt = new PolicyPaymentReceipt__c(
			insurancePolicy__c = [
				SELECT insurancePolicy__c
				FROM PolicyPaymentReceipt__c
				WHERE Id = :reconciledReceipt.Id
			]
			.insurancePolicy__c,
			paymentReconciliation__c = [
				SELECT paymentReconciliation__c
				FROM PolicyPaymentReceipt__c
				WHERE Id = :reconciledReceipt.Id
			]
			.paymentReconciliation__c,
			receiptDate__c = Date.today(),
			receiptAmount__c = 200,
			receiptStatus__c = RECEIPT_PENDING,
			receiptNumber__c = 'REC-PEND'
		);
		insert receipt;

		Test.startTest();
		String errorMessage;
		try {
			PolicyPaymentReceiptReversalService.reverseReceipt(
				receipt.Id,
				REASON,
				NOTES
			);
		} catch (Exception e) {
			errorMessage = e.getMessage();
		}
		Test.stopTest();

		Assert.isNotNull(
			errorMessage,
			'Solo debe poder reversarse un recibo reconocido'
		);
	}

	/**
	 * @description: El motivo y las notas son obligatorios: sin ellos no hay evidencia de por
	 *               que el cobro dejo de valer.
	 */
	@IsTest
	static void requiresReasonAndNotes() {
		PolicyPaymentReceipt__c receipt = buildReconciledChain('06');

		Test.startTest();
		String missingReason;
		String missingNotes;
		try {
			PolicyPaymentReceiptReversalService.reverseReceipt(
				receipt.Id,
				null,
				NOTES
			);
		} catch (Exception e) {
			missingReason = e.getMessage();
		}
		try {
			PolicyPaymentReceiptReversalService.reverseReceipt(
				receipt.Id,
				REASON,
				'   '
			);
		} catch (Exception e) {
			missingNotes = e.getMessage();
		}
		Test.stopTest();

		Assert.isNotNull(missingReason, 'Sin motivo la reversa debe rechazarse');
		Assert.isNotNull(missingNotes, 'Sin notas la reversa debe rechazarse');
		Assert.areEqual(
			RECEIPT_RECOGNIZED,
			[
				SELECT receiptStatus__c
				FROM PolicyPaymentReceipt__c
				WHERE Id = :receipt.Id
			]
			.receiptStatus__c,
			'El recibo no debe haberse tocado'
		);
	}

	/**
	 * @description: Tras la reversa, el caso vuelve a ser reprocesable. Antes de esta historia
	 *               el reproceso lo rechazaba indicando que "requiere reversa", y esa reversa
	 *               no existia: el caso quedaba muerto.
	 */
	@IsTest
	static void reprocessBecomesAvailableAfterReversal() {
		PolicyPaymentReceipt__c receipt = buildReconciledChain('07');
		// El identificador se captura ANTES de reversar: al reversar, la conciliacion suelta
		// el puntero al recibo y ya no puede ubicarse por el.
		Id reconId = [
			SELECT Id
			FROM PaymentReconciliation__c
			WHERE resultingReceipt__c = :receipt.Id
		]
		.Id;

		String blockedBefore;
		try {
			PaymentReconciliationManualService.reprocessReconciliation(
				reconId,
				'Intento antes de reversar'
			);
		} catch (Exception e) {
			blockedBefore = e.getMessage();
		}
		Assert.isNotNull(
			blockedBefore,
			'Con recibo vigente el reproceso debe seguir bloqueado'
		);

		PolicyPaymentReceiptReversalService.reverse(receipt.Id, REASON, NOTES);

		Test.startTest();
		PaymentReconciliationManualService.reprocessReconciliation(
			reconId,
			'Reproceso tras la reversa'
		);
		Test.stopTest();

		Assert.areEqual(
			'Normalizado',
			[
				SELECT inboundStatus__c
				FROM InboundInsurancePayment__c
				WHERE externalPaymentId__c = 'EXT-REV-07'
			]
			.inboundStatus__c,
			'El reproceso debe haber reseteado el pago inbound'
		);
	}

	/**
	 * @description: La reversa en lote procesa todos los recibos con un numero constante de
	 *               consultas, independiente de la cantidad.
	 */
	@IsTest
	static void reversesInBulk() {
		List<PolicyPaymentReceipt__c> receipts = new List<PolicyPaymentReceipt__c>();
		for (Integer i = 10; i < 15; i++) {
			receipts.add(buildReconciledChain(String.valueOf(i)));
		}

		List<PolicyPaymentReceipt__c> toReverse = new List<PolicyPaymentReceipt__c>();
		for (PolicyPaymentReceipt__c receipt : receipts) {
			toReverse.add(
				new PolicyPaymentReceipt__c(
					Id = receipt.Id,
					receiptStatus__c = RECEIPT_REVERSED,
					reversalReason__c = REASON,
					reversalNotes__c = NOTES
				)
			);
		}

		Test.startTest();
		update toReverse;
		Test.stopTest();

		Assert.areEqual(
			5,
			[
				SELECT COUNT()
				FROM PaymentReconciliation__c
				WHERE reconciliationStatus__c = :RECON_REVIEW
			],
			'Las cinco conciliaciones deben volver a la bandeja'
		);
		Assert.areEqual(
			5,
			[
				SELECT COUNT()
				FROM InboundInsurancePayment__c
				WHERE inboundStatus__c = :INBOUND_MANUAL_REVIEW
			],
			'Los cinco pagos inbound deben volver al circuito'
		);
	}

	/**
	 * @description: Crea la cadena completa incluyendo plan y cuota conciliada por el recibo.
	 *               Usa la cuota que genera el plan si el motor la produjo, y si no la crea, de
	 *               modo que la prueba no dependa de la configuracion de generacion.
	 * @param suffix: Sufijo para identificadores externos.
	 * @param dueDate: Vencimiento de la cuota.
	 * @param installmentStatus: Estado inicial de la cuota.
	 * @return El recibo reconocido vinculado a esa cuota.
	 */
	private static PolicyPaymentReceipt__c buildChainWithInstallment(
		String suffix,
		Date dueDate,
		String installmentStatus
	) {
		PolicyPaymentReceipt__c receipt = buildReconciledChain(suffix);
		Id policyId = [
			SELECT insurancePolicy__c
			FROM PolicyPaymentReceipt__c
			WHERE Id = :receipt.Id
		]
		.insurancePolicy__c;

		PaymentPlan__c plan = new PaymentPlan__c(
			insurancePolicy__c = policyId,
			planStatus__c = 'Activo',
			premiumFrequency__c = 'Mensual',
			expectedTotalAmount__c = 500,
			firstDueDate__c = dueDate,
			installmentCount__c = 1
		);
		insert plan;

		List<PaymentPlanInstallment__c> generated = [
			SELECT Id
			FROM PaymentPlanInstallment__c
			WHERE paymentPlan__c = :plan.Id
		];
		PaymentPlanInstallment__c inst;
		if (generated.isEmpty()) {
			inst = new PaymentPlanInstallment__c(
				paymentPlan__c = plan.Id,
				sequenceNumber__c = 1,
				dueDate__c = dueDate,
				expectedAmount__c = 500
			);
			insert inst;
		} else {
			inst = generated[0];
		}

		update new PaymentPlanInstallment__c(
			Id = inst.Id,
			dueDate__c = dueDate,
			expectedAmount__c = 500,
			installmentStatus__c = installmentStatus,
			matchedReceipt__c = receipt.Id,
			matchedOn__c = System.now()
		);

		update new PolicyPaymentReceipt__c(
			Id = receipt.Id,
			paymentPlan__c = plan.Id,
			paymentPlanInstallment__c = inst.Id
		);

		return receipt;
	}

	/**
	 * @description: H202: una cuota cuyo vencimiento aun no paso vuelve a Pendiente, se
	 *               desvincula del recibo y pierde la fecha de conciliacion.
	 */
	@IsTest
	static void reopensInstallmentAsPendingWhenNotOverdue() {
		PolicyPaymentReceipt__c receipt = buildChainWithInstallment(
			'30',
			Date.today().addDays(20),
			'Conciliado'
		);

		Test.startTest();
		PolicyPaymentReceiptReversalService.reverse(receipt.Id, REASON, NOTES);
		Test.stopTest();

		PaymentPlanInstallment__c inst = [
			SELECT
				installmentStatus__c,
				matchedReceipt__c,
				matchedOn__c,
				matchedAmount__c,
				outstandingAmount__c,
				expectedAmount__c
			FROM PaymentPlanInstallment__c
			WHERE
				paymentPlan__r.insurancePolicy__c = :[
					SELECT insurancePolicy__c
					FROM PolicyPaymentReceipt__c
					WHERE Id = :receipt.Id
				]
				.insurancePolicy__c
			LIMIT 1
		];
		Assert.areEqual(
			'Pendiente',
			inst.installmentStatus__c,
			'Una cuota no vencida vuelve a Pendiente'
		);
		Assert.isNull(
			inst.matchedReceipt__c,
			'La cuota debe dejar de apuntar al recibo reversado'
		);
		Assert.isNull(
			inst.matchedOn__c,
			'La fecha de conciliación debe quedar vacía'
		);
		Assert.areEqual(
			0,
			inst.matchedAmount__c,
			'El importe conciliado se recalcula solo al desvincular'
		);
		Assert.areEqual(
			inst.expectedAmount__c,
			inst.outstandingAmount__c,
			'El saldo pendiente vuelve al importe esperado completo'
		);
	}

	/**
	 * @description: H202: una cuota cuyo vencimiento ya paso vuelve a Vencido, no a Pendiente.
	 *               El estado se calcula por fecha y no se recupera el anterior.
	 */
	@IsTest
	static void reopensInstallmentAsOverdueWhenDuePassed() {
		PolicyPaymentReceipt__c receipt = buildChainWithInstallment(
			'31',
			Date.today().addDays(-40),
			'Conciliado'
		);

		Test.startTest();
		PolicyPaymentReceiptReversalService.reverse(receipt.Id, REASON, NOTES);
		Test.stopTest();

		Assert.areEqual(
			'Vencido',
			[
				SELECT installmentStatus__c
				FROM PaymentPlanInstallment__c
				WHERE matchedReceipt__c = NULL AND dueDate__c < TODAY
				LIMIT 1
			]
			.installmentStatus__c,
			'Una cuota cuyo vencimiento ya pasó vuelve a Vencido'
		);
	}

	/**
	 * @description: H202: una cuota cancelada o condonada se desvincula del recibo pero NO
	 *               resucita. La reversa deshace un cobro; no revierte la decision de anular
	 *               la deuda.
	 */
	@IsTest
	static void doesNotResurrectCancelledInstallment() {
		PolicyPaymentReceipt__c receipt = buildChainWithInstallment(
			'32',
			Date.today().addDays(-10),
			'Cancelado'
		);

		Test.startTest();
		PolicyPaymentReceiptReversalService.reverse(receipt.Id, REASON, NOTES);
		Test.stopTest();

		PaymentPlanInstallment__c inst = [
			SELECT installmentStatus__c, matchedReceipt__c
			FROM PaymentPlanInstallment__c
			WHERE dueDate__c = :Date.today().addDays(-10)
			LIMIT 1
		];
		Assert.areEqual(
			'Cancelado',
			inst.installmentStatus__c,
			'Una cuota cancelada conserva su estado'
		);
		Assert.isNull(
			inst.matchedReceipt__c,
			'Igualmente debe desvincularse del recibo reversado'
		);
	}

	/**
	 * @description: H202: si la cuota fue vinculada despues a OTRO recibo, la reversa del
	 *               primero no la toca.
	 */
	@IsTest
	static void doesNotTouchInstallmentLinkedToAnotherReceipt() {
		PolicyPaymentReceipt__c firstReceipt = buildChainWithInstallment(
			'33',
			Date.today().addDays(15),
			'Conciliado'
		);
		Id policyId = [
			SELECT insurancePolicy__c
			FROM PolicyPaymentReceipt__c
			WHERE Id = :firstReceipt.Id
		]
		.insurancePolicy__c;

		PolicyPaymentReceipt__c secondReceipt = new PolicyPaymentReceipt__c(
			insurancePolicy__c = policyId,
			paymentReconciliation__c = [
				SELECT paymentReconciliation__c
				FROM PolicyPaymentReceipt__c
				WHERE Id = :firstReceipt.Id
			]
			.paymentReconciliation__c,
			receiptDate__c = Date.today(),
			receiptAmount__c = 500,
			receiptStatus__c = RECEIPT_RECOGNIZED,
			receiptNumber__c = 'REC-33-B'
		);
		insert secondReceipt;

		PaymentPlanInstallment__c inst = [
			SELECT Id
			FROM PaymentPlanInstallment__c
			WHERE matchedReceipt__c = :firstReceipt.Id
			LIMIT 1
		];
		update new PaymentPlanInstallment__c(
			Id = inst.Id,
			matchedReceipt__c = secondReceipt.Id
		);

		Test.startTest();
		PolicyPaymentReceiptReversalService.reverse(firstReceipt.Id, REASON, NOTES);
		Test.stopTest();

		Assert.areEqual(
			secondReceipt.Id,
			[
				SELECT matchedReceipt__c
				FROM PaymentPlanInstallment__c
				WHERE Id = :inst.Id
			]
			.matchedReceipt__c,
			'La cuota debe conservar su vínculo con el segundo recibo'
		);
		Assert.areEqual(
			'Conciliado',
			[
				SELECT installmentStatus__c
				FROM PaymentPlanInstallment__c
				WHERE Id = :inst.Id
			]
			.installmentStatus__c,
			'Su estado no debe alterarse'
		);
	}

	/**
	 * @description: H202: el plan vuelve a Activo cuando su cuota se reabre. No hace falta
	 *               codigo para esto: lo produce la cascada existente al cambiar la cuota.
	 */
	@IsTest
	static void planReturnsToActiveWhenInstallmentReopens() {
		PolicyPaymentReceipt__c receipt = buildChainWithInstallment(
			'34',
			Date.today().addDays(25),
			'Conciliado'
		);
		Id planId = [
			SELECT paymentPlan__c
			FROM PolicyPaymentReceipt__c
			WHERE Id = :receipt.Id
		]
		.paymentPlan__c;
		Assert.areEqual(
			'Completado',
			[SELECT planStatus__c FROM PaymentPlan__c WHERE Id = :planId]
			.planStatus__c,
			'Preparación: el plan debe estar Completado antes de reversar'
		);

		Test.startTest();
		PolicyPaymentReceiptReversalService.reverse(receipt.Id, REASON, NOTES);
		Test.stopTest();

		Assert.areEqual(
			'Activo',
			[SELECT planStatus__c FROM PaymentPlan__c WHERE Id = :planId]
			.planStatus__c,
			'El plan debe volver a Activo al reabrirse su cuota'
		);
	}

	/**
	 * @description: Crea una cadena conciliada sobre una poliza con oportunidad de origen, para
	 *               los casos de senalizacion comercial.
	 * @param suffix: Sufijo de los identificadores externos.
	 * @param stage: Etapa inicial de la oportunidad.
	 * @return El recibo reconocido de esa poliza.
	 */
	private static PolicyPaymentReceipt__c buildChainWithOpportunity(
		String suffix,
		String stage
	) {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		Opportunity opp = new Opportunity(
			Name = 'OPP-REV-' + suffix,
			AccountId = accountId,
			StageName = stage,
			CloseDate = Date.today().addDays(30),
			Agente_Relacionado__c = CollectionsTestDataFactory.getOrCreateAgenteId()
		);
		insert opp;

		InsurancePolicy policy = CollectionsTestDataFactory.createPolicy(
			accountId,
			'Cancelado'
		);
		update new InsurancePolicy(Id = policy.Id, SourceOpportunityId = opp.Id);

		InboundInsurancePayment__c inbound = new InboundInsurancePayment__c(
			externalPaymentId__c = 'EXT-REV-' + suffix,
			inboundStatus__c = INBOUND_RECONCILED,
			sourceAmount__c = 500,
			sourcePaymentDate__c = Date.today(),
			sourcePolicyNumber__c = 'POL-REV-' + suffix,
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now()
		);
		insert inbound;

		PaymentReconciliation__c recon = new PaymentReconciliation__c(
			inboundPayment__c = inbound.Id,
			insurancePolicy__c = policy.Id,
			reconciliationStatus__c = RECON_RECONCILED
		);
		insert recon;

		PolicyPaymentReceipt__c receipt = new PolicyPaymentReceipt__c(
			insurancePolicy__c = policy.Id,
			sourceInboundPayment__c = inbound.Id,
			paymentReconciliation__c = recon.Id,
			receiptDate__c = Date.today(),
			receiptAmount__c = 500,
			receiptStatus__c = RECEIPT_RECOGNIZED,
			receiptNumber__c = 'REC-' + suffix
		);
		insert receipt;

		update new PaymentReconciliation__c(
			Id = recon.Id,
			resultingReceipt__c = receipt.Id
		);

		return receipt;
	}

	/**
	 * @description: H203: si la poliza queda sin ningun cobro valido, la oportunidad se SEÑALA
	 *               pero su etapa NO se toca. La etapa pertenece al proceso comercial.
	 */
	@IsTest
	static void signalsOpportunityWhenPolicyLosesAllValidReceipts() {
		PolicyPaymentReceipt__c receipt = buildChainWithOpportunity('40', 'Póliza');
		Id oppId = [
			SELECT SourceOpportunityId
			FROM InsurancePolicy
			WHERE
				Id = :[
					SELECT insurancePolicy__c
					FROM PolicyPaymentReceipt__c
					WHERE Id = :receipt.Id
				]
				.insurancePolicy__c
		]
		.SourceOpportunityId;
		String stageBefore = [
			SELECT StageName
			FROM Opportunity
			WHERE Id = :oppId
		]
		.StageName;

		Test.startTest();
		PolicyPaymentReceiptReversalService.reverse(receipt.Id, REASON, NOTES);
		Test.stopTest();

		Opportunity opp = [
			SELECT
				StageName,
				collectionReversedFlag__c,
				collectionReversedOn__c,
				collectionReversalReason__c,
				collectionReversedReceipt__c
			FROM Opportunity
			WHERE Id = :oppId
		];
		Assert.isTrue(
			opp.collectionReversedFlag__c,
			'La oportunidad debe quedar señalada'
		);
		Assert.isNotNull(
			opp.collectionReversedOn__c,
			'Debe registrar cuándo quedó sin cobros válidos'
		);
		Assert.areEqual(
			REASON,
			opp.collectionReversalReason__c,
			'Debe copiar el motivo para que se lea sin navegar al recibo'
		);
		Assert.areEqual(
			receipt.Id,
			opp.collectionReversedReceipt__c,
			'Debe apuntar al recibo que originó la señal'
		);
		Assert.areEqual(
			stageBefore,
			opp.StageName,
			'La etapa NO debe modificarse: pertenece al proceso comercial'
		);
	}

	/**
	 * @description: H203: si la poliza conserva otro cobro valido, la oportunidad no se toca.
	 *               La condicion que la cerro sigue siendo cierta.
	 */
	@IsTest
	static void doesNotSignalWhenPolicyKeepsAnotherValidReceipt() {
		PolicyPaymentReceipt__c receipt = buildChainWithOpportunity('41', 'Póliza');
		Id policyId = [
			SELECT insurancePolicy__c
			FROM PolicyPaymentReceipt__c
			WHERE Id = :receipt.Id
		]
		.insurancePolicy__c;
		Id reconId = [
			SELECT paymentReconciliation__c
			FROM PolicyPaymentReceipt__c
			WHERE Id = :receipt.Id
		]
		.paymentReconciliation__c;

		insert new PolicyPaymentReceipt__c(
			insurancePolicy__c = policyId,
			paymentReconciliation__c = reconId,
			receiptDate__c = Date.today(),
			receiptAmount__c = 500,
			receiptStatus__c = RECEIPT_RECOGNIZED,
			receiptNumber__c = 'REC-41-B'
		);

		Test.startTest();
		PolicyPaymentReceiptReversalService.reverse(receipt.Id, REASON, NOTES);
		Test.stopTest();

		Assert.isFalse(
			[
				SELECT collectionReversedFlag__c
				FROM Opportunity
				WHERE
					Id = :[
						SELECT SourceOpportunityId
						FROM InsurancePolicy
						WHERE Id = :policyId
					]
					.SourceOpportunityId
			]
			.collectionReversedFlag__c,
			'La oportunidad no debe señalarse: la póliza conserva un cobro válido'
		);
	}

	/**
	 * @description: H203: la señal se retira sola cuando la poliza recupera un cobro valido,
	 *               para que la vista del responsable comercial no acumule casos resueltos.
	 */
	@IsTest
	static void clearsSignalWhenPolicyRecoversAValidReceipt() {
		PolicyPaymentReceipt__c receipt = buildChainWithOpportunity('42', 'Póliza');
		Id policyId = [
			SELECT insurancePolicy__c
			FROM PolicyPaymentReceipt__c
			WHERE Id = :receipt.Id
		]
		.insurancePolicy__c;
		Id reconId = [
			SELECT paymentReconciliation__c
			FROM PolicyPaymentReceipt__c
			WHERE Id = :receipt.Id
		]
		.paymentReconciliation__c;
		Id oppId = [
			SELECT SourceOpportunityId
			FROM InsurancePolicy
			WHERE Id = :policyId
		]
		.SourceOpportunityId;

		PolicyPaymentReceiptReversalService.reverse(receipt.Id, REASON, NOTES);
		Assert.isTrue(
			[
				SELECT collectionReversedFlag__c
				FROM Opportunity
				WHERE Id = :oppId
			]
			.collectionReversedFlag__c,
			'Preparación: la oportunidad debe quedar señalada antes de recuperar el cobro'
		);

		Test.startTest();
		insert new PolicyPaymentReceipt__c(
			insurancePolicy__c = policyId,
			paymentReconciliation__c = reconId,
			receiptDate__c = Date.today(),
			receiptAmount__c = 500,
			receiptStatus__c = RECEIPT_RECOGNIZED,
			receiptNumber__c = 'REC-42-NUEVO'
		);
		Test.stopTest();

		Opportunity opp = [
			SELECT
				collectionReversedFlag__c,
				collectionReversedOn__c,
				collectionReversalReason__c,
				collectionReversedReceipt__c
			FROM Opportunity
			WHERE Id = :oppId
		];
		Assert.isFalse(
			opp.collectionReversedFlag__c,
			'La señal debe retirarse al recuperarse el cobro'
		);
		Assert.isNull(opp.collectionReversedOn__c, 'Debe limpiarse la fecha');
		Assert.isNull(opp.collectionReversalReason__c, 'Debe limpiarse el motivo');
		Assert.isNull(
			opp.collectionReversedReceipt__c,
			'Debe limpiarse el recibo señalado'
		);
	}

	/**
	 * @description: H203: una poliza sin oportunidad de origen no rompe la reversa; queda una
	 *               advertencia registrada.
	 */
	@IsTest
	static void warnsWhenPolicyHasNoOpportunityToSignal() {
		PolicyPaymentReceipt__c receipt = buildReconciledChain('43');

		Test.startTest();
		PolicyPaymentReceiptReversalService.reverse(receipt.Id, REASON, NOTES);
		Test.stopTest();

		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM AppLog__c
				WHERE
					eventCode__c = :CobranzaLog.EVENT_REVERSAL_OPPORTUNITY_MISSING
					AND severity__c = 'Advertencia'
			],
			'Debe quedar advertencia de que no hay oportunidad que señalar'
		);
		Assert.areEqual(
			RECEIPT_REVERSED,
			[
				SELECT receiptStatus__c
				FROM PolicyPaymentReceipt__c
				WHERE Id = :receipt.Id
			]
			.receiptStatus__c,
			'La reversa se completa igual'
		);
	}

	/**
	 * @description: Si falla la actualizacion de la conciliacion, queda traza en el registro de
	 *               aplicacion. Sin ella el caso quedaria perdido: ni conciliado de verdad ni
	 *               visible en la bandeja.
	 */
	@IsTest
	static void logsErrorWhenReopeningFails() {
		PolicyPaymentReceipt__c receipt = buildReconciledChain('20');
		PolicyPaymentReceiptReversalService.forceFailureForTest = true;

		Test.startTest();
		PolicyPaymentReceiptReversalService.reverse(receipt.Id, REASON, NOTES);
		Test.stopTest();

		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM AppLog__c
				WHERE
					eventCode__c = :CobranzaLog.EVENT_REVERSAL_RECONCILIATION_FAILED
					AND severity__c = 'Error'
			],
			'Un fallo al devolver la conciliación debe quedar registrado'
		);
		Assert.areEqual(
			RECEIPT_REVERSED,
			[
				SELECT receiptStatus__c
				FROM PolicyPaymentReceipt__c
				WHERE Id = :receipt.Id
			]
			.receiptStatus__c,
			'El recibo queda reversado aunque falle la cascada'
		);
	}
}
