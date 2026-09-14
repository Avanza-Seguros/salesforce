/**
 *   @name: InboundInsurancePaymentRestResourceTest
 *   @version: 1.0
 *   @creation date: 24/04/2026
 *   @author: Javier Torres - Volestra
 *   @description: Valida la recepcion tecnica de pagos inbound por lote,
 *                 incluyendo escenarios validos, invalidos, duplicados y
 *                 verificacion de bulkificacion contra limites de gobernador.
 */
@IsTest
private class InboundInsurancePaymentRestResourceTest {
	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	@IsTest
	static void receivesValidInboundPaymentBatch() {
		InsurancePolicy policy = CollectionsTestDataFactory.buildCompletePolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Inicial',
			'Mensual',
			1200,
			Date.today()
		);
		policy.Name = 'POL-REST-001';
		policy.PolicyName = 'POL-REST-001';
		insert policy;

		Test.startTest();
		invokeEndpoint(
			'[' +
				'{' +
				'"externalPaymentId__c":"EXT-1001",' +
				'"sourcePolicyNumber__c":"POL-REST-001",' +
				'"sourceAmount__c":1200.50,' +
				'"sourcePaymentDate__c":"24/04/2026",' +
				'"sourceDueDate__c":"30/04/2026",' +
				'"sourceReceiptNumber__c":"REC-1001",' +
				'"sourceCollectionChannel__c":"Domiciliacion",' +
				'"sourcePaymentStatusRaw__c":"PAGADO",' +
				'"sourcePaymentStatus__c":"Pagado",' +
				'"sourceCurrency__c":"MXN",' +
				'"sourceInsuranceCarrier__c":"GNP",' +
				'"sourcePolicyBranch__c":"Autos",' +
				'"sourceInstallmentNumber__c":"1",' +
				'"sourceCustomerExternalId__c":"CLI-001",' +
				'"sourceSynchronizedAt__c":"24/04/2026 11:30:00",' +
				'"sourceGrossCommission__c":100.25,' +
				'"sourceVatCommission__c":16.04' +
				'}' +
				']'
		);
		Test.stopTest();

		Assert.areEqual(202, RestContext.response.statusCode);

		Map<String, Object> responseBody = getResponseBody();
		Assert.areEqual(true, responseBody.get('success'));
		Assert.areEqual('BATCH_PROCESSED', responseBody.get('code'));
		Assert.areEqual(1, toInteger(responseBody.get('totalRecords')));
		Assert.areEqual(1, toInteger(responseBody.get('receivedCount')));
		Assert.areEqual(0, toInteger(responseBody.get('updatedCount')));
		Assert.areEqual(0, toInteger(responseBody.get('rejectedCount')));

		InboundInsurancePayment__c inboundPayment = [
			SELECT
				externalPaymentId__c,
				inboundStatus__c,
				receivedAt__c,
				parsedAt__c,
				sourceAmount__c,
				sourceDueDate__c,
				sourcePayloadHash__c,
				sourcePayloadJson__c,
				sourcePaymentDate__c,
				sourcePolicyNumber__c,
				sourceReceiptNumber__c,
				sourceSystem__c,
				candidatePolicy__c,
				rejectionReason__c,
				sourceCollectionChannel__c,
				sourcePaymentStatusRaw__c,
				sourcePaymentStatus__c,
				sourceCurrency__c,
				sourceInsuranceCarrier__c,
				sourcePolicyBranch__c,
				sourceInstallmentNumber__c,
				sourceCustomerExternalId__c,
				sourceSynchronizedAt__c,
				sourceGrossCommission__c,
				sourceVatCommission__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'EXT-1001'
			LIMIT 1
		];

		Assert.areEqual('Normalizado', inboundPayment.inboundStatus__c);
		Assert.areEqual(1200.50, inboundPayment.sourceAmount__c);
		Assert.areEqual(
			Date.newInstance(2026, 4, 24),
			inboundPayment.sourcePaymentDate__c
		);
		Assert.areEqual(
			Date.newInstance(2026, 4, 30),
			inboundPayment.sourceDueDate__c
		);
		Assert.areEqual('REC-1001', inboundPayment.sourceReceiptNumber__c);
		Assert.areEqual('MuleSoft', inboundPayment.sourceSystem__c);
		Assert.areEqual('Domiciliacion', inboundPayment.sourceCollectionChannel__c);
		Assert.areEqual('PAGADO', inboundPayment.sourcePaymentStatusRaw__c);
		Assert.areEqual('Pagado', inboundPayment.sourcePaymentStatus__c);
		Assert.areEqual('MXN', inboundPayment.sourceCurrency__c);
		Assert.areEqual('GNP', inboundPayment.sourceInsuranceCarrier__c);
		Assert.areEqual('Autos', inboundPayment.sourcePolicyBranch__c);
		Assert.areEqual('1', inboundPayment.sourceInstallmentNumber__c);
		Assert.areEqual('CLI-001', inboundPayment.sourceCustomerExternalId__c);
		Assert.areEqual(100.25, inboundPayment.sourceGrossCommission__c);
		Assert.areEqual(16.04, inboundPayment.sourceVatCommission__c);
		Assert.areEqual(policy.Id, inboundPayment.candidatePolicy__c);
		Assert.isNotNull(inboundPayment.receivedAt__c);
		Assert.isNotNull(inboundPayment.parsedAt__c);
		Assert.isNotNull(inboundPayment.sourcePayloadHash__c);
		Assert.isTrue(inboundPayment.sourcePayloadJson__c.contains('EXT-1001'));
		Assert.areEqual(null, inboundPayment.rejectionReason__c);
	}

	@IsTest
	static void handlesMixedBatchWithUpdateAndRejected() {
		Test.startTest();
		invokeEndpoint(
			'[' +
				'{' +
				'"externalPaymentId__c":"EXT-2001",' +
				'"sourcePolicyNumber__c":"POL-DUP-001",' +
				'"sourceAmount__c":980.00,' +
				'"sourcePaymentDate__c":"24/04/2026"' +
				'},' +
				'{' +
				'"externalPaymentId__c":"EXT-2001",' +
				'"sourcePolicyNumber__c":"POL-DUP-001",' +
				'"sourceAmount__c":980.00,' +
				'"sourcePaymentDate__c":"24/04/2026"' +
				'},' +
				'{' +
				'"externalPaymentId__c":"EXT-2003",' +
				'"sourcePolicyNumber__c":"POL-INVALID-001",' +
				'"sourceAmount__c":0,' +
				'"sourcePaymentDate__c":"24/04/2026"' +
				'}' +
				']'
		);
		Test.stopTest();

		Assert.areEqual(202, RestContext.response.statusCode);

		Map<String, Object> responseBody = getResponseBody();
		Assert.areEqual(false, responseBody.get('success'));
		Assert.areEqual(3, toInteger(responseBody.get('totalRecords')));
		Assert.areEqual(1, toInteger(responseBody.get('receivedCount')));
		Assert.areEqual(1, toInteger(responseBody.get('updatedCount')));
		Assert.areEqual(1, toInteger(responseBody.get('rejectedCount')));

		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM InboundInsurancePayment__c
				WHERE externalPaymentId__c = 'EXT-2001'
			]
		);

		InboundInsurancePayment__c rejected = [
			SELECT externalPaymentId__c, inboundStatus__c, rejectionReason__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'EXT-2003'
			LIMIT 1
		];
		Assert.areEqual('Rechazado', rejected.inboundStatus__c);
		Assert.areEqual('Importe invalido', rejected.rejectionReason__c);
	}

	@IsTest
	static void doesNotTreatCancellationDateAsPayment() {
		// Antes, un recibo sin fecha de pago pero con fecha de
		// cancelacion se procesaba COMO SI estuviera cobrado: el motor copiaba la fecha de
		// cancelacion a la fecha de pago, generaba el recibo, conciliaba la cuota y cerraba
		// la oportunidad. Este es el mismo mensaje de entonces; el resultado ya no.
		Test.startTest();
		invokeEndpoint(
			'[' +
				'{' +
				'"externalPaymentId__c":"EXT-3001",' +
				'"sourcePolicyNumber__c":"POL-CANCEL-001",' +
				'"sourceAmount__c":450.00,' +
				'"sourceCancellationDate__c":"20/04/2026"' +
				'}' +
				']'
		);
		Test.stopTest();

		Assert.areEqual(202, RestContext.response.statusCode);

		InboundInsurancePayment__c inboundPayment = [
			SELECT
				sourcePaymentDate__c,
				sourceCancellationDate__c,
				inboundStatus__c,
				carrierReceiptStatus__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'EXT-3001'
			LIMIT 1
		];

		Assert.areEqual(
			Date.newInstance(2026, 4, 20),
			inboundPayment.sourceCancellationDate__c,
			'La fecha de cancelacion se conserva como lo que es.'
		);
		Assert.isNull(
			inboundPayment.sourcePaymentDate__c,
			'La fecha de cancelacion no puede convertirse en fecha de pago.'
		);
		Assert.areEqual(
			'Pendiente',
			inboundPayment.carrierReceiptStatus__c,
			'Sin estatus informado y sin fecha de pago, el recibo no esta cobrado.'
		);
		Assert.areEqual(
			'Pendiente de Pago',
			inboundPayment.inboundStatus__c,
			'No entra al pipeline: sin cobro no hay nada que conciliar.'
		);
		Assert.isTrue(
			[
				SELECT COUNT()
				FROM PolicyPaymentReceipt__c
				WHERE sourceInboundPayment__c = :inboundPayment.Id
			] == 0,
			'Un recibo cancelado no puede generar un cobro.'
		);
	}

	@IsTest
	static void keepsCancelledReceiptOutOfThePipeline() {
		// Mismo caso pero con el estatus informado por la aseguradora, que es como llegara
		// cuando la integracion envie el vocabulario acordado.
		Test.startTest();
		invokeEndpoint(
			'[' +
				'{' +
				'"externalPaymentId__c":"EXT-3002",' +
				'"sourcePolicyNumber__c":"POL-CANCEL-002",' +
				'"sourceAmount__c":450.00,' +
				'"sourcePaymentStatus__c":"Cancelado",' +
				'"sourcePaymentStatusRaw__c":"CANCELADA POR FALTA DE PAGO",' +
				'"sourceCancellationDate__c":"20/04/2026"' +
				'}' +
				']'
		);
		Test.stopTest();

		Assert.areEqual(202, RestContext.response.statusCode);

		InboundInsurancePayment__c inboundPayment = [
			SELECT inboundStatus__c, carrierReceiptStatus__c, manualReviewRequired__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'EXT-3002'
			LIMIT 1
		];

		Assert.areEqual('Cancelado', inboundPayment.carrierReceiptStatus__c);
		Assert.areEqual(
			'No Conciliable',
			inboundPayment.inboundStatus__c,
			'La aseguradora no lo da por cobrado: no se concilia y no es un pago detenido.'
		);
		Assert.isFalse(
			inboundPayment.manualReviewRequired__c,
			'No hay nada que decidir: no es un caso para el analista.'
		);
	}

	@IsTest
	static void sendsPaidWithoutPaymentDateToManualReview() {
		// Dato contradictorio: afirma el cobro y no dice cuando. No deberia presentarse
		// nunca; si se presenta, lo mira una persona en vez de resolverse solo.
		Test.startTest();
		invokeEndpoint(
			'[' +
				'{' +
				'"externalPaymentId__c":"EXT-3003",' +
				'"sourcePolicyNumber__c":"POL-CANCEL-003",' +
				'"sourceAmount__c":450.00,' +
				'"sourcePaymentStatus__c":"Pagado"' +
				'}' +
				']'
		);
		Test.stopTest();

		InboundInsurancePayment__c inboundPayment = [
			SELECT inboundStatus__c, carrierReceiptStatus__c, manualReviewRequired__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'EXT-3003'
			LIMIT 1
		];

		Assert.areEqual('Pagado', inboundPayment.carrierReceiptStatus__c);
		Assert.areEqual('Revision Manual', inboundPayment.inboundStatus__c);
		Assert.isTrue(
			inboundPayment.manualReviewRequired__c,
			'La bandeja del analista filtra por esta marca, no por el estado.'
		);
	}

	@IsTest
	static void reopensNotReconcilableWhenCarrierLaterReportsItPaid() {
		// Salida del estado No Conciliable: la aseguradora reporto el recibo como vencido y
		// despues lo dio por cobrado. Sin esta transicion, un recibo que se cobra tarde
		// quedaria fuera del pipeline para siempre.
		invokeEndpoint(
			'[' +
				'{' +
				'"externalPaymentId__c":"EXT-3005",' +
				'"sourcePolicyNumber__c":"POL-CANCEL-005",' +
				'"sourceAmount__c":450.00,' +
				'"sourcePaymentStatus__c":"Vencido"' +
				'}' +
				']'
		);

		InboundInsurancePayment__c beforePayment = [
			SELECT inboundStatus__c, carrierReceiptStatus__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'EXT-3005'
			LIMIT 1
		];
		Assert.areEqual('Vencido', beforePayment.carrierReceiptStatus__c);
		Assert.areEqual('No Conciliable', beforePayment.inboundStatus__c);

		Test.startTest();
		invokeEndpoint(
			'[' +
				'{' +
				'"externalPaymentId__c":"EXT-3005",' +
				'"sourcePolicyNumber__c":"POL-CANCEL-005",' +
				'"sourceAmount__c":450.00,' +
				'"sourcePaymentStatus__c":"Pagado",' +
				'"sourcePaymentDate__c":"20/04/2026"' +
				'}' +
				']'
		);
		Test.stopTest();

		InboundInsurancePayment__c afterPayment = [
			SELECT inboundStatus__c, carrierReceiptStatus__c, sourcePaymentDate__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'EXT-3005'
			LIMIT 1
		];
		Assert.areEqual('Pagado', afterPayment.carrierReceiptStatus__c);
		Assert.areEqual(
			Date.newInstance(2026, 4, 20),
			afterPayment.sourcePaymentDate__c
		);
		Assert.areNotEqual(
			'No Conciliable',
			afterPayment.inboundStatus__c,
			'Un recibo que la aseguradora pasa a pagado tiene que volver al pipeline.'
		);
	}

	@IsTest
	static void sendsUnknownCarrierStatusToManualReview() {
		Test.startTest();
		invokeEndpoint(
			'[' +
				'{' +
				'"externalPaymentId__c":"EXT-3004",' +
				'"sourcePolicyNumber__c":"POL-CANCEL-004",' +
				'"sourceAmount__c":450.00,' +
				'"sourcePaymentStatus__c":"LIQUIDADO PARCIAL",' +
				'"sourcePaymentDate__c":"20/04/2026"' +
				'}' +
				']'
		);
		Test.stopTest();

		InboundInsurancePayment__c inboundPayment = [
			SELECT inboundStatus__c, carrierReceiptStatus__c, manualReviewRequired__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'EXT-3004'
			LIMIT 1
		];

		Assert.areEqual(
			'Desconocido',
			inboundPayment.carrierReceiptStatus__c,
			'Un valor fuera del vocabulario acordado no se adivina.'
		);
		Assert.areEqual('Revision Manual', inboundPayment.inboundStatus__c);
		Assert.isTrue(inboundPayment.manualReviewRequired__c);
	}

	// ================================================================
	// Un reenvio solo se reprocesa si algo cambio.

	private static String resendBody(String amount, String extra) {
		return '[' +
			'{' +
			'"externalPaymentId__c":"EXT-424-01",' +
			'"sourcePolicyNumber__c":"POL-424-01",' +
			'"sourceAmount__c":' +
			amount +
			',' +
			'"sourceDueDate__c":"15/09/2026",' +
			'"sourcePaymentDate__c":"15/09/2026",' +
			'"sourcePaymentStatus__c":"Pagado"' +
			extra +
			'}' +
			']';
	}

	/**
	 * Deja el pago EXT-424-01 como si ya se hubiera conciliado: con su conciliacion, su
	 * comprobante vigente y el estado Conciliado. Se arma a mano porque el pipeline es
	 * asincrono y en una prueba solo avanza un eslabon.
	 *
	 * Marcar el pago como Conciliado tiene un efecto util aparte: el normalizador que quedo
	 * encolado por la primera recepcion busca pagos en Parseado, no lo encuentra y no hace
	 * nada. Asi el estado que se observa al final es el que dejo el reenvio, y no el que
	 * dejo el pipeline corriendo por su cuenta.
	 */
	private static PolicyPaymentReceipt__c buildReconciledChain(
		String policyNumber
	) {
		InboundInsurancePayment__c inbound = [
			SELECT Id
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'EXT-424-01'
			LIMIT 1
		];

		InsurancePolicy policy = new InsurancePolicy(
			Name = policyNumber,
			PolicyName = 'Test Policy',
			NameInsuredId = CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			Status = 'Vigente',
			PremiumAmount = 1000,
			PremiumFrequency = 'Mensual',
			PaymentDueDate = Date.today()
		);
		insert policy;

		PaymentReconciliation__c recon = new PaymentReconciliation__c(
			inboundPayment__c = inbound.Id,
			insurancePolicy__c = policy.Id,
			reconciliationStatus__c = 'Conciliado'
		);
		insert recon;

		PolicyPaymentReceipt__c receipt = new PolicyPaymentReceipt__c(
			insurancePolicy__c = policy.Id,
			sourceInboundPayment__c = inbound.Id,
			paymentReconciliation__c = recon.Id,
			receiptDate__c = Date.today(),
			receiptAmount__c = 1000,
			receiptStatus__c = 'Reconocido',
			receiptNumber__c = 'REC-424-01'
		);
		insert receipt;

		update new PaymentReconciliation__c(
			Id = recon.Id,
			resultingReceipt__c = receipt.Id
		);
		update new InboundInsurancePayment__c(
			Id = inbound.Id,
			inboundStatus__c = 'Conciliado'
		);
		return receipt;
	}

	@IsTest
	static void identicalResendChangesNothing() {
		invokeEndpoint(resendBody('1000.00', ''));
		buildReconciledChain('POL-424-01');

		Test.startTest();
		invokeEndpoint(resendBody('1000.00', ''));
		Test.stopTest();

		InboundInsurancePayment__c after = [
			SELECT inboundStatus__c, resendCount__c, resendChangeLog__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'EXT-424-01'
			LIMIT 1
		];
		Assert.areEqual(
			'Conciliado',
			after.inboundStatus__c,
			'Un pago conciliado que se reenvia identico sigue conciliado. Este es el caso ' +
			'que el guardail existe para proteger.'
		);
		Assert.areEqual(
			1,
			after.resendCount__c,
			'El reenvio se cuenta aunque no cambie nada.'
		);
		Assert.isTrue(
			String.isBlank(after.resendChangeLog__c),
			'Sin cambios no se ensucia la bitacora.'
		);
	}

	@IsTest
	static void informationalChangeIsStoredWithoutReprocessing() {
		invokeEndpoint(resendBody('1000.00', ''));
		buildReconciledChain('POL-424-01');

		Test.startTest();
		invokeEndpoint(
			resendBody('1000.00', ',"sourceCustomerName__c":"CLIENTE CORREGIDO"')
		);
		Test.stopTest();

		InboundInsurancePayment__c after = [
			SELECT inboundStatus__c, sourceCustomerName__c, resendChangeLog__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'EXT-424-01'
			LIMIT 1
		];
		Assert.areEqual(
			'CLIENTE CORREGIDO',
			after.sourceCustomerName__c,
			'El dato nuevo se guarda igual.'
		);
		Assert.areEqual(
			'Conciliado',
			after.inboundStatus__c,
			'El nombre del cliente no afecta al cobro: no se reprocesa.'
		);
		Assert.isTrue(String.isBlank(after.resendChangeLog__c));
	}

	@IsTest
	static void amountChangeIsRecordedAndReprocessed() {
		invokeEndpoint(resendBody('1000.00', ''));

		Test.startTest();
		invokeEndpoint(resendBody('1200.00', ''));
		Test.stopTest();

		InboundInsurancePayment__c after = [
			SELECT
				sourceAmount__c,
				resendCount__c,
				resendChangeLog__c,
				lastResendAt__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'EXT-424-01'
			LIMIT 1
		];
		Assert.areEqual(1200.00, after.sourceAmount__c);
		Assert.areEqual(1, after.resendCount__c);
		Assert.isNotNull(after.lastResendAt__c);
		Assert.isTrue(
			after.resendChangeLog__c.contains('importe'),
			'La bitacora tiene que decir que cambio el importe.'
		);
		Assert.isTrue(
			after.resendChangeLog__c.contains('1000') &&
			after.resendChangeLog__c.contains('1200'),
			'Con el valor anterior y el nuevo: ' + after.resendChangeLog__c
		);
	}

	@IsTest
	static void changeLogKeepsPreviousEntries() {
		invokeEndpoint(resendBody('1000.00', ''));
		invokeEndpoint(resendBody('1200.00', ''));

		Test.startTest();
		invokeEndpoint(resendBody('1300.00', ''));
		Test.stopTest();

		InboundInsurancePayment__c after = [
			SELECT resendChangeLog__c, resendCount__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'EXT-424-01'
			LIMIT 1
		];
		Assert.areEqual(2, after.resendCount__c);
		Assert.isTrue(
			after.resendChangeLog__c.contains('1000') &&
			after.resendChangeLog__c.contains('1300'),
			'La bitacora se agrega al final, no se sobrescribe: ' +
			after.resendChangeLog__c
		);
	}

	@IsTest
	static void carrierStatusChangeIsMaterial() {
		invokeEndpoint(resendBody('1000.00', ''));

		Test.startTest();
		// El mismo recibo, ahora cancelado por la aseguradora.
		invokeEndpoint(
			'[' +
				'{' +
				'"externalPaymentId__c":"EXT-424-01",' +
				'"sourcePolicyNumber__c":"POL-424-01",' +
				'"sourceAmount__c":1000.00,' +
				'"sourceDueDate__c":"15/09/2026",' +
				'"sourcePaymentStatus__c":"Cancelado"' +
				'}' +
				']'
		);
		Test.stopTest();

		InboundInsurancePayment__c after = [
			SELECT carrierReceiptStatus__c, inboundStatus__c, resendChangeLog__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'EXT-424-01'
			LIMIT 1
		];
		Assert.areEqual('Cancelado', after.carrierReceiptStatus__c);
		Assert.areEqual(
			'No Conciliable',
			after.inboundStatus__c,
			'Que la aseguradora deje de darlo por cobrado es un cambio material.'
		);
		Assert.isTrue(
			after.resendChangeLog__c.contains('estatus del recibo'),
			'Tiene que quedar constancia del cambio de estatus.'
		);
	}

	@IsTest
	static void annulsLiveReceiptWhenResendChangesTheAmount() {
		// El corazon del caso: un cobro ya registrado no puede sobrevivir a una
		// correccion de la aseguradora. Se arma la cadena a mano porque el pipeline es
		// asincrono y en una prueba solo avanza un eslabon.
		invokeEndpoint(resendBody('1000.00', ''));
		PolicyPaymentReceipt__c receipt = buildReconciledChain('POL-424-01');

		Test.startTest();
		invokeEndpoint(resendBody('1200.00', ''));
		Test.stopTest();

		receipt = [
			SELECT receiptStatus__c, reversalReason__c, reversedAt__c
			FROM PolicyPaymentReceipt__c
			WHERE Id = :receipt.Id
		];
		Assert.areEqual(
			'Reversado',
			receipt.receiptStatus__c,
			'El cobro anterior deja de ser valido en cuanto la aseguradora corrige el importe.'
		);
		Assert.areEqual(
			'Correccion de la aseguradora',
			receipt.reversalReason__c,
			'El motivo distingue esta anulacion de una decidida por un analista.'
		);
		Assert.isNotNull(
			receipt.reversedAt__c,
			'La anulacion se sella aunque no la haya hecho una persona.'
		);
	}

	@IsTest
	static void doesNotAnnulWhenNothingMaterialChanged() {
		invokeEndpoint(resendBody('1000.00', ''));
		PolicyPaymentReceipt__c receipt = buildReconciledChain('POL-424-02');

		Test.startTest();
		invokeEndpoint(resendBody('1000.00', ''));
		Test.stopTest();

		receipt = [
			SELECT receiptStatus__c
			FROM PolicyPaymentReceipt__c
			WHERE Id = :receipt.Id
		];
		Assert.areEqual(
			'Reconocido',
			receipt.receiptStatus__c,
			'Este es el caso que mas importa: una sincronizacion rutinaria no puede tumbar ' +
			'un cobro que estaba bien.'
		);
	}

	@IsTest
	static void mixedResendBatchTreatsEachPaymentOnItsOwn() {
		// Una sincronizacion real no llega ordenada: en el mismo lote vienen recibos que no
		// cambiaron, otros con un dato informativo distinto y otros con el importe corregido.
		// Cada uno tiene que recibir el tratamiento que le toca, sin contagiarse.
		List<String> primero = new List<String>();
		for (Integer i = 0; i < 30; i++) {
			primero.add(
				'{' +
					'"externalPaymentId__c":"EXT-424-B' +
					i +
					'",' +
					'"sourcePolicyNumber__c":"POL-424-B",' +
					'"sourceAmount__c":1000.00,' +
					'"sourceDueDate__c":"15/09/2026",' +
					'"sourcePaymentDate__c":"15/09/2026",' +
					'"sourcePaymentStatus__c":"Pagado"' +
					'}'
			);
		}
		invokeEndpoint('[' + String.join(primero, ',') + ']');

		// Se marcan como conciliados para que el reenvio se evalue sobre un estado estable y
		// no sobre el pipeline corriendo por su cuenta.
		List<InboundInsurancePayment__c> creados = [
			SELECT Id
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c LIKE 'EXT-424-B%'
		];
		for (InboundInsurancePayment__c rec : creados) {
			rec.inboundStatus__c = 'Conciliado';
		}
		update creados;

		List<String> reenvio = new List<String>();
		for (Integer i = 0; i < 30; i++) {
			// Un tercio identico, un tercio con cambio informativo, un tercio con el importe
			// corregido.
			String amount = Math.mod(i, 3) == 2 ? '1200.00' : '1000.00';
			String extra = Math.mod(i, 3) == 1
				? ',"sourceCustomerName__c":"CLIENTE ' + i + '"'
				: '';
			reenvio.add(
				'{' +
					'"externalPaymentId__c":"EXT-424-B' +
					i +
					'",' +
					'"sourcePolicyNumber__c":"POL-424-B",' +
					'"sourceAmount__c":' +
					amount +
					',' +
					'"sourceDueDate__c":"15/09/2026",' +
					'"sourcePaymentDate__c":"15/09/2026",' +
					'"sourcePaymentStatus__c":"Pagado"' +
					extra +
					'}'
			);
		}

		Test.startTest();
		invokeEndpoint('[' + String.join(reenvio, ',') + ']');
		Test.stopTest();

		Integer sinTocar = 0;
		Integer reprocesados = 0;
		for (InboundInsurancePayment__c rec : [
			SELECT
				externalPaymentId__c,
				inboundStatus__c,
				resendCount__c,
				resendChangeLog__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c LIKE 'EXT-424-B%'
		]) {
			Assert.areEqual(
				1,
				rec.resendCount__c,
				'Todos se reenviaron una vez, cambiaran o no.'
			);
			if (String.isBlank(rec.resendChangeLog__c)) {
				sinTocar++;
				Assert.areEqual(
					'Conciliado',
					rec.inboundStatus__c,
					'Sin cambio material el pago conserva su estado: ' +
					rec.externalPaymentId__c
				);
			} else {
				reprocesados++;
				Assert.isTrue(
					rec.resendChangeLog__c.contains('importe'),
					'Solo el cambio de importe justifica reprocesar: ' +
					rec.resendChangeLog__c
				);
			}
		}

		Assert.areEqual(
			20,
			sinTocar,
			'Los identicos y los de cambio informativo no se reprocesan.'
		);
		Assert.areEqual(10, reprocesados, 'Solo los del importe corregido.');
	}

	@IsTest
	static void rejectsMalformedJson() {
		Test.startTest();
		invokeEndpoint('[{"externalPaymentId__c":"EXT-4001"');
		Test.stopTest();

		Assert.areEqual(400, RestContext.response.statusCode);

		Map<String, Object> responseBody = getResponseBody();
		Assert.areEqual(false, responseBody.get('success'));
		Assert.areEqual('INVALID_JSON', responseBody.get('code'));
	}

	@IsTest
	static void rejectsEmptyBody() {
		Test.startTest();
		invokeEndpoint(null);
		Test.stopTest();

		Assert.areEqual(400, RestContext.response.statusCode);

		Map<String, Object> responseBody = getResponseBody();
		Assert.areEqual(false, responseBody.get('success'));
		Assert.areEqual('EMPTY_BODY', responseBody.get('code'));
	}

	@IsTest
	static void returns500WhenServiceThrowsUnexpectedly() {
		InboundInsurancePaymentRestResource.forceServiceException = true;

		Test.startTest();
		invokeEndpoint('[]');
		Test.stopTest();

		InboundInsurancePaymentRestResource.forceServiceException = false;

		Assert.areEqual(500, RestContext.response.statusCode);

		Map<String, Object> responseBody = getResponseBody();
		Assert.areEqual(false, responseBody.get('success'));
		Assert.areEqual('INTERNAL_ERROR', responseBody.get('code'));
	}

	@IsTest
	static void processesLargeBatchWithinGovernorLimits() {
		Integer batchSize = 100;
		List<String> rows = new List<String>();
		for (Integer i = 0; i < batchSize; i++) {
			rows.add(
				'{' +
					'"externalPaymentId__c":"EXT-BULK-' +
					i +
					'",' +
					'"sourcePolicyNumber__c":"POL-BULK-' +
					i +
					'",' +
					'"sourceAmount__c":100.00,' +
					'"sourcePaymentDate__c":"24/04/2026"' +
					'}'
			);
		}

		Test.startTest();
		Integer queriesBefore = Limits.getQueries();
		Integer dmlBefore = Limits.getDmlStatements();
		invokeEndpoint('[' + String.join(rows, ',') + ']');
		Integer queriesUsed = Limits.getQueries() - queriesBefore;
		Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
		Test.stopTest();

		Assert.areEqual(202, RestContext.response.statusCode);
		Map<String, Object> responseBody = getResponseBody();
		Assert.areEqual(batchSize, toInteger(responseBody.get('receivedCount')));
		Assert.areEqual(0, toInteger(responseBody.get('rejectedCount')));
		Assert.areEqual(
			batchSize,
			[
				SELECT COUNT()
				FROM InboundInsurancePayment__c
				WHERE externalPaymentId__c LIKE 'EXT-BULK-%'
			]
		);
		Assert.isTrue(
			queriesUsed <= 5,
			'Se esperaban a lo sumo 5 SOQL para todo el lote, se usaron ' +
			queriesUsed
		);
		// Alta de los pagos, registro de la aplicacion y el punto de restauracion que el
		// endpoint fija para poder deshacer la peticion completa ante un fallo no previsto
		// (la plataforma lo cuenta como DML). Los tres son uno por peticion, no por pago.
		Assert.isTrue(
			dmlUsed <= 3,
			'Se esperaban a lo sumo 3 DML para todo el lote, se usaron ' + dmlUsed
		);
	}

	@IsTest
	static void computesExternalIdFromCarrierAndReceipt() {
		Test.startTest();
		invokeEndpoint(
			'[' +
				'{' +
				'"sourcePolicyNumber__c":"POL-GNP-001",' +
				'"sourceAmount__c":1200.00,' +
				'"sourcePaymentDate__c":"24/04/2026",' +
				'"sourceCarrierCode__c":"GNP",' +
				'"sourceReceiptNumber__c":"1234"' +
				'}' +
				']'
		);
		Test.stopTest();

		Assert.areEqual(202, RestContext.response.statusCode);

		InboundInsurancePayment__c inboundPayment = [
			SELECT externalPaymentId__c, sourceCarrierCode__c, sourceReceiptNumber__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'GNP_1234'
			LIMIT 1
		];

		Assert.areEqual('GNP', inboundPayment.sourceCarrierCode__c);
		Assert.areEqual('1234', inboundPayment.sourceReceiptNumber__c);
		Assert.areEqual('GNP_1234', inboundPayment.externalPaymentId__c);
	}

	@IsTest
	static void storesAllNewSourceFields() {
		Test.startTest();
		invokeEndpoint(
			'[' +
				'{' +
				'"sourcePolicyNumber__c":"POL-NEW-001",' +
				'"sourceAmount__c":500.00,' +
				'"sourcePaymentDate__c":"24/04/2026",' +
				'"sourceCarrierCode__c":"HDI",' +
				'"sourceReceiptNumber__c":"9001",' +
				'"sourcePolicyStatusRaw__c":"Cancelada",' +
				'"sourceCustomerName__c":"Juan Perez",' +
				'"sourceIsCollective__c":true,' +
				'"sourceRetryCount__c":2,' +
				'"sourceRejectionReason__c":"Fondos insuficientes",' +
				'"sourceCancellationReason__c":"Solicitud del cliente",' +
				'"sourcePolicyStartDate__c":"01/01/2026",' +
				'"sourcePolicyRenewalDate__c":"01/01/2027",' +
				'"sourcePolicyIssueDate__c":"15/12/2025"' +
				'}' +
				']'
		);
		Test.stopTest();

		Assert.areEqual(202, RestContext.response.statusCode);

		InboundInsurancePayment__c inboundPayment = [
			SELECT
				sourcePolicyStatusRaw__c,
				sourceCustomerName__c,
				sourceIsCollective__c,
				sourceRetryCount__c,
				sourceRejectionReason__c,
				sourceCancellationReason__c,
				sourcePolicyStartDate__c,
				sourcePolicyRenewalDate__c,
				sourcePolicyIssueDate__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'HDI_9001'
			LIMIT 1
		];

		Assert.areEqual('Cancelada', inboundPayment.sourcePolicyStatusRaw__c);
		Assert.areEqual('Juan Perez', inboundPayment.sourceCustomerName__c);
		Assert.areEqual(true, inboundPayment.sourceIsCollective__c);
		Assert.areEqual(2, inboundPayment.sourceRetryCount__c.intValue());
		Assert.areEqual(
			'Fondos insuficientes',
			inboundPayment.sourceRejectionReason__c
		);
		Assert.areEqual(
			'Solicitud del cliente',
			inboundPayment.sourceCancellationReason__c
		);
		Assert.areEqual(
			Date.newInstance(2026, 1, 1),
			inboundPayment.sourcePolicyStartDate__c
		);
		Assert.areEqual(
			Date.newInstance(2027, 1, 1),
			inboundPayment.sourcePolicyRenewalDate__c
		);
		Assert.areEqual(
			Date.newInstance(2025, 12, 15),
			inboundPayment.sourcePolicyIssueDate__c
		);
	}

	@IsTest
	static void omittingNewFieldsCreatesRecordWithNulls() {
		Test.startTest();
		invokeEndpoint(
			'[' +
				'{' +
				'"sourcePolicyNumber__c":"POL-BARE-001",' +
				'"sourceAmount__c":300.00,' +
				'"sourcePaymentDate__c":"24/04/2026",' +
				'"sourceCarrierCode__c":"AXA",' +
				'"sourceReceiptNumber__c":"7777"' +
				'}' +
				']'
		);
		Test.stopTest();

		Assert.areEqual(202, RestContext.response.statusCode);

		InboundInsurancePayment__c inboundPayment = [
			SELECT
				sourcePolicyStatusRaw__c,
				sourceCustomerName__c,
				sourceIsCollective__c,
				sourceRetryCount__c,
				sourceRejectionReason__c,
				sourceCancellationReason__c,
				sourcePolicyStartDate__c,
				sourcePolicyRenewalDate__c,
				sourcePolicyIssueDate__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'AXA_7777'
			LIMIT 1
		];

		Assert.areEqual(null, inboundPayment.sourcePolicyStatusRaw__c);
		Assert.areEqual(null, inboundPayment.sourceCustomerName__c);
		Assert.areEqual(false, inboundPayment.sourceIsCollective__c);
		Assert.areEqual(null, inboundPayment.sourceRetryCount__c);
		Assert.areEqual(null, inboundPayment.sourceRejectionReason__c);
		Assert.areEqual(null, inboundPayment.sourceCancellationReason__c);
		Assert.areEqual(null, inboundPayment.sourcePolicyStartDate__c);
		Assert.areEqual(null, inboundPayment.sourcePolicyRenewalDate__c);
		Assert.areEqual(null, inboundPayment.sourcePolicyIssueDate__c);
	}

	@IsTest
	static void acceptsPaymentWithoutPaymentDate() {
		Test.startTest();
		invokeEndpoint(
			'[' +
				'{' +
				'"sourcePolicyNumber__c":"POL-NODATE-001",' +
				'"sourceAmount__c":650.00,' +
				'"sourceCarrierCode__c":"MAPFRE",' +
				'"sourceReceiptNumber__c":"4242"' +
				'}' +
				']'
		);
		Test.stopTest();

		Assert.areEqual(202, RestContext.response.statusCode);

		Map<String, Object> responseBody = getResponseBody();
		Assert.areEqual(1, toInteger(responseBody.get('receivedCount')));
		Assert.areEqual(0, toInteger(responseBody.get('rejectedCount')));

		InboundInsurancePayment__c inboundPayment = [
			SELECT inboundStatus__c, rejectionReason__c, sourcePaymentDate__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'MAPFRE_4242'
			LIMIT 1
		];

		Assert.areNotEqual('Rechazado', inboundPayment.inboundStatus__c);
		Assert.areEqual(null, inboundPayment.rejectionReason__c);
		Assert.areEqual(null, inboundPayment.sourcePaymentDate__c);
	}

	@IsTest
	static void sameCarrierSameFolioDoesNotDuplicate() {
		Test.startTest();
		invokeEndpoint(
			'[' +
				'{' +
				'"sourcePolicyNumber__c":"POL-DEDUP-001",' +
				'"sourceAmount__c":800.00,' +
				'"sourcePaymentDate__c":"24/04/2026",' +
				'"sourceCarrierCode__c":"GNP",' +
				'"sourceReceiptNumber__c":"5555"' +
				'},' +
				'{' +
				'"sourcePolicyNumber__c":"POL-DEDUP-001",' +
				'"sourceAmount__c":800.00,' +
				'"sourcePaymentDate__c":"24/04/2026",' +
				'"sourceCarrierCode__c":"GNP",' +
				'"sourceReceiptNumber__c":"5555"' +
				'}' +
				']'
		);
		Test.stopTest();

		Assert.areEqual(202, RestContext.response.statusCode);
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM InboundInsurancePayment__c
				WHERE externalPaymentId__c = 'GNP_5555'
			]
		);
	}

	@IsTest
	static void differentCarrierSameFolioCreatesTwoRecords() {
		Test.startTest();
		invokeEndpoint(
			'[' +
				'{' +
				'"sourcePolicyNumber__c":"POL-GNP-XY",' +
				'"sourceAmount__c":800.00,' +
				'"sourcePaymentDate__c":"24/04/2026",' +
				'"sourceCarrierCode__c":"GNP",' +
				'"sourceReceiptNumber__c":"1234"' +
				'},' +
				'{' +
				'"sourcePolicyNumber__c":"POL-HDI-XY",' +
				'"sourceAmount__c":800.00,' +
				'"sourcePaymentDate__c":"24/04/2026",' +
				'"sourceCarrierCode__c":"HDI",' +
				'"sourceReceiptNumber__c":"1234"' +
				'}' +
				']'
		);
		Test.stopTest();

		Assert.areEqual(202, RestContext.response.statusCode);
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM InboundInsurancePayment__c
				WHERE externalPaymentId__c = 'GNP_1234'
			]
		);
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM InboundInsurancePayment__c
				WHERE externalPaymentId__c = 'HDI_1234'
			]
		);
	}

	@IsTest
	static void withoutPaymentDateCreatesPendingAndNotEnqueued() {
		Test.startTest();
		invokeEndpoint(
			'[' +
				'{' +
				'"sourcePolicyNumber__c":"POL-HB-01",' +
				'"sourceAmount__c":500.00,' +
				'"sourceCarrierCode__c":"GNP",' +
				'"sourceReceiptNumber__c":"HB-1"' +
				'}' +
				']'
		);
		Test.stopTest();

		Assert.areEqual(202, RestContext.response.statusCode);
		Map<String, Object> responseBody = getResponseBody();
		Assert.areEqual(1, toInteger(responseBody.get('receivedCount')));
		Assert.areEqual(0, toInteger(responseBody.get('rejectedCount')));

		InboundInsurancePayment__c inboundPayment = [
			SELECT inboundStatus__c, sourcePaymentDate__c
			FROM InboundInsurancePayment__c
			WHERE
				externalPaymentId__c = 'GNP_HB-1'
				AND inboundStatus__c = 'Pendiente de Pago'
			LIMIT 1
		];

		Assert.areEqual('Pendiente de Pago', inboundPayment.inboundStatus__c);
		Assert.areEqual(null, inboundPayment.sourcePaymentDate__c);
	}

	@IsTest
	static void resendWithoutPaymentDateStaysPending() {
		Test.startTest();
		invokeEndpoint(
			'[' +
				'{' +
				'"sourcePolicyNumber__c":"POL-HB-02",' +
				'"sourceAmount__c":500.00,' +
				'"sourceCarrierCode__c":"GNP",' +
				'"sourceReceiptNumber__c":"HB-2"' +
				'}' +
				']'
		);
		invokeEndpoint(
			'[' +
				'{' +
				'"sourcePolicyNumber__c":"POL-HB-02",' +
				'"sourceAmount__c":750.00,' +
				'"sourceCarrierCode__c":"GNP",' +
				'"sourceReceiptNumber__c":"HB-2"' +
				'}' +
				']'
		);
		Test.stopTest();

		Assert.areEqual(202, RestContext.response.statusCode);
		Map<String, Object> responseBody = getResponseBody();
		Assert.areEqual(1, toInteger(responseBody.get('updatedCount')));

		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM InboundInsurancePayment__c
				WHERE externalPaymentId__c = 'GNP_HB-2'
			]
		);

		InboundInsurancePayment__c inboundPayment = [
			SELECT inboundStatus__c, sourceAmount__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'GNP_HB-2'
			LIMIT 1
		];
		Assert.areEqual('Pendiente de Pago', inboundPayment.inboundStatus__c);
		Assert.areEqual(750.00, inboundPayment.sourceAmount__c);
	}

	@IsTest
	static void pendingTransitionsToParsedWhenPaymentDateArrives() {
		Test.startTest();
		invokeEndpoint(
			'[' +
				'{' +
				'"sourcePolicyNumber__c":"POL-HB-03",' +
				'"sourceAmount__c":500.00,' +
				'"sourceCarrierCode__c":"GNP",' +
				'"sourceReceiptNumber__c":"HB-3"' +
				'}' +
				']'
		);
		invokeEndpoint(
			'[' +
				'{' +
				'"sourcePolicyNumber__c":"POL-HB-03",' +
				'"sourceAmount__c":500.00,' +
				'"sourcePaymentDate__c":"10/07/2026",' +
				'"sourceCarrierCode__c":"GNP",' +
				'"sourceReceiptNumber__c":"HB-3"' +
				'}' +
				']'
		);
		Test.stopTest();

		Assert.areEqual(202, RestContext.response.statusCode);

		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM InboundInsurancePayment__c
				WHERE externalPaymentId__c = 'GNP_HB-3'
			]
		);

		InboundInsurancePayment__c inboundPayment = [
			SELECT inboundStatus__c, sourcePaymentDate__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'GNP_HB-3'
			LIMIT 1
		];
		Assert.areEqual('Normalizado', inboundPayment.inboundStatus__c);
		Assert.areEqual(
			Date.newInstance(2026, 7, 10),
			inboundPayment.sourcePaymentDate__c
		);
	}

	@IsTest
	static void withPaymentDateFromFirstSyncEntersPipeline() {
		Test.startTest();
		invokeEndpoint(
			'[' +
				'{' +
				'"sourcePolicyNumber__c":"POL-HB-04",' +
				'"sourceAmount__c":500.00,' +
				'"sourcePaymentDate__c":"10/07/2026",' +
				'"sourceCarrierCode__c":"GNP",' +
				'"sourceReceiptNumber__c":"HB-4"' +
				'}' +
				']'
		);
		Test.stopTest();

		Assert.areEqual(202, RestContext.response.statusCode);

		InboundInsurancePayment__c inboundPayment = [
			SELECT inboundStatus__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'GNP_HB-4'
			LIMIT 1
		];
		Assert.areEqual('Normalizado', inboundPayment.inboundStatus__c);
	}

	@IsTest
	static void rejectedDoesNotTransitionToPending() {
		Test.startTest();
		invokeEndpoint(
			'[' +
				'{' +
				'"sourcePolicyNumber__c":"POL-HB-05",' +
				'"sourceAmount__c":0,' +
				'"sourceCarrierCode__c":"GNP",' +
				'"sourceReceiptNumber__c":"HB-5"' +
				'}' +
				']'
		);
		invokeEndpoint(
			'[' +
				'{' +
				'"sourcePolicyNumber__c":"POL-HB-05",' +
				'"sourceAmount__c":500.00,' +
				'"sourceCarrierCode__c":"GNP",' +
				'"sourceReceiptNumber__c":"HB-5"' +
				'}' +
				']'
		);
		Test.stopTest();

		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM InboundInsurancePayment__c
				WHERE externalPaymentId__c = 'GNP_HB-5'
			]
		);

		InboundInsurancePayment__c inboundPayment = [
			SELECT inboundStatus__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'GNP_HB-5'
			LIMIT 1
		];
		Assert.areEqual('Rechazado', inboundPayment.inboundStatus__c);
	}

	/**
	 * @creation date: 30/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: H200: si la integracion reenvia un pago YA CONCILIADO con un importe o
	 *               una fecha distintos a los conciliados, queda constancia. Es la senal de
	 *               que lo conciliado dejo de coincidir con lo que informa la aseguradora.
	 */
	@IsTest
	static void logsInfoWhenReconciledPaymentIsResentWithChanges() {
		insert new InboundInsurancePayment__c(
			externalPaymentId__c = 'AXA_7001',
			inboundStatus__c = 'Conciliado',
			sourceAmount__c = 1000.00,
			sourcePaymentDate__c = Date.newInstance(2026, 4, 24),
			sourcePolicyNumber__c = 'POL-RESENT-001',
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now()
		);

		Test.startTest();
		invokeEndpoint(
			'[' +
				'{' +
				'"sourcePolicyNumber__c":"POL-RESENT-001",' +
				'"sourceAmount__c":1250.00,' +
				'"sourcePaymentDate__c":"24/04/2026",' +
				'"sourceCarrierCode__c":"AXA",' +
				'"sourceReceiptNumber__c":"7001"' +
				'}' +
				']'
		);
		Test.stopTest();

		List<AppLog__c> logs = [
			SELECT severity__c, eventCode__c, message__c, inboundPayment__c
			FROM AppLog__c
			WHERE eventCode__c = :CobranzaLog.EVENT_INBOUND_RESENT_CHANGED
		];
		Assert.areEqual(
			1,
			logs.size(),
			'Debe registrarse un unico aviso de reenvio'
		);
		Assert.areEqual(
			'Informacion',
			logs[0].severity__c,
			'Un reenvio con cambios se informa, no es un error del motor'
		);
		Assert.areEqual(
			CobranzaLog.EVENT_INBOUND_RESENT_CHANGED,
			logs[0].eventCode__c,
			'Debe usar el codigo de reenvio con cambios'
		);
		Assert.isTrue(
			logs[0].message__c.contains('importe'),
			'El mensaje debe indicar que dato cambio'
		);
		Assert.isNotNull(
			logs[0].inboundPayment__c,
			'Debe quedar visible desde el pago afectado'
		);
	}

	/**
	 * @creation date: 30/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: H200: el reenvio rutinario de un pago sin cambios NO genera registro.
	 *               La integracion reenvia el historico constantemente y registrarlo
	 *               inundaria el objeto sin aportar nada.
	 */
	@IsTest
	static void doesNotLogWhenReconciledPaymentIsResentWithoutChanges() {
		insert new InboundInsurancePayment__c(
			externalPaymentId__c = 'AXA_7002',
			inboundStatus__c = 'Conciliado',
			sourceAmount__c = 1000.00,
			sourcePaymentDate__c = Date.newInstance(2026, 4, 24),
			sourcePolicyNumber__c = 'POL-RESENT-002',
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now()
		);

		Test.startTest();
		invokeEndpoint(
			'[' +
				'{' +
				'"sourcePolicyNumber__c":"POL-RESENT-002",' +
				'"sourceAmount__c":1000.00,' +
				'"sourcePaymentDate__c":"24/04/2026",' +
				'"sourceCarrierCode__c":"AXA",' +
				'"sourceReceiptNumber__c":"7002"' +
				'}' +
				']'
		);
		Test.stopTest();

		Assert.areEqual(
			0,
			[
				SELECT COUNT()
				FROM AppLog__c
				WHERE eventCode__c = :CobranzaLog.EVENT_INBOUND_RESENT_CHANGED
			],
			'Un reenvio sin cambios no debe generar ruido en el registro'
		);
	}

	/**
	 * @creation date: 30/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: H200: todo pago recibido queda sellado en la primera etapa del
	 *               pipeline, que es lo que permite listar despues los pagos detenidos.
	 *               Se usa un pago SIN fecha de pago porque queda en 'Pendiente de Pago' y
	 *               no entra al pipeline: asi la etapa se puede observar en Recepcion. Un
	 *               pago con fecha avanzaria a Normalizacion al ejecutarse el primer
	 *               eslabon, que es justamente lo que verifica el caso siguiente.
	 */
	@IsTest
	static void stampsReceptionStageOnReceivedPayment() {
		Test.startTest();
		invokeEndpoint(
			'[' +
				'{' +
				'"sourcePolicyNumber__c":"POL-STAGE-001",' +
				'"sourceAmount__c":300.00,' +
				'"sourceCarrierCode__c":"AXA",' +
				'"sourceReceiptNumber__c":"8001"' +
				'}' +
				']'
		);
		Test.stopTest();

		Assert.areEqual(
			CobranzaLog.STAGE_RECEPCION,
			[
				SELECT pipelineStage__c
				FROM InboundInsurancePayment__c
				WHERE externalPaymentId__c = 'AXA_8001'
			]
			.pipelineStage__c,
			'El pago debe quedar sellado en la etapa de recepcion'
		);
	}

	/**
	 * @creation date: 30/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: H200: un pago que entra al pipeline avanza la etapa alcanzada. Es lo
	 *               que permite distinguir despues hasta donde llego cada pago.
	 */
	@IsTest
	static void advancesStageWhenPaymentEntersPipeline() {
		Test.startTest();
		invokeEndpoint(
			'[' +
				'{' +
				'"sourcePolicyNumber__c":"POL-STAGE-002",' +
				'"sourceAmount__c":300.00,' +
				'"sourcePaymentDate__c":"24/04/2026",' +
				'"sourceCarrierCode__c":"AXA",' +
				'"sourceReceiptNumber__c":"8002"' +
				'}' +
				']'
		);
		Test.stopTest();

		Assert.areEqual(
			CobranzaLog.STAGE_NORMALIZACION,
			[
				SELECT pipelineStage__c
				FROM InboundInsurancePayment__c
				WHERE externalPaymentId__c = 'AXA_8002'
			]
			.pipelineStage__c,
			'Tras ejecutarse el primer eslabon la etapa debe haber avanzado'
		);
	}

	// ================================================================
	// Un reenvio sin cambios reales no toca lo conciliado, y un pago defectuoso no afecta
	// al resto del envio.

	private static InboundInsurancePayment__c resentPayment() {
		return [
			SELECT
				Id,
				inboundStatus__c,
				pipelineStage__c,
				sourceAmount__c,
				sourceCurrency__c,
				sourceInstallmentNumber__c,
				carrierReceiptStatus__c,
				resendCount__c,
				lastResendAt__c,
				resendChangeLog__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'EXT-424-01'
			LIMIT 1
		];
	}

	private static String receiptStatus(Id receiptId) {
		return [
			SELECT receiptStatus__c
			FROM PolicyPaymentReceipt__c
			WHERE Id = :receiptId
		]
		.receiptStatus__c;
	}

	private static String paidRow(String folio, String extra) {
		return '{' +
			'"sourcePolicyNumber__c":"POL-431",' +
			'"sourceAmount__c":500.00,' +
			'"sourcePaymentDate__c":"10/09/2026",' +
			'"sourcePaymentStatus__c":"Pagado",' +
			'"sourceCarrierCode__c":"GNP",' +
			'"sourceReceiptNumber__c":"' +
			folio +
			'"' +
			extra +
			'}';
	}

	private static Map<String, Object> resultFor(String externalPaymentId) {
		for (Object item : (List<Object>) getResponseBody().get('results')) {
			Map<String, Object> result = (Map<String, Object>) item;
			if (externalPaymentId.equals(result.get('externalPaymentId'))) {
				return result;
			}
		}
		return null;
	}

	@IsTest
	static void identicalResendKeepsStageAndCreatesNothing() {
		invokeEndpoint(resendBody('1000.00', ''));
		PolicyPaymentReceipt__c receipt = buildReconciledChain('POL-431-01');
		update new InboundInsurancePayment__c(
			Id = resentPayment().Id,
			pipelineStage__c = CobranzaLog.STAGE_CUOTA
		);

		Test.startTest();
		invokeEndpoint(resendBody('1000.00', ''));
		Test.stopTest();

		InboundInsurancePayment__c after = resentPayment();
		Assert.areEqual('Conciliado', after.inboundStatus__c);
		Assert.areEqual(
			CobranzaLog.STAGE_CUOTA,
			after.pipelineStage__c,
			'Un reenvio sin cambios no reinicia la etapa: el pago no vuelve a recorrer el circuito.'
		);
		Assert.areEqual(
			1,
			after.resendCount__c,
			'Solo registra que llego otra vez.'
		);
		Assert.isNotNull(after.lastResendAt__c);
		Assert.areEqual('Reconocido', receiptStatus(receipt.Id));
		Assert.areEqual(
			1,
			[SELECT COUNT() FROM PolicyPaymentReceipt__c],
			'No se crea ningun recibo nuevo.'
		);
		Assert.areEqual(
			1,
			[SELECT COUNT() FROM PaymentReconciliation__c],
			'No se crea ninguna conciliacion nueva.'
		);
	}

	@IsTest
	static void trailingZeroInAmountIsNotACorrection() {
		invokeEndpoint(resendBody('2979.40', ''));
		PolicyPaymentReceipt__c receipt = buildReconciledChain('POL-431-02');

		Test.startTest();
		invokeEndpoint(resendBody('2979.4', ''));
		Test.stopTest();

		InboundInsurancePayment__c after = resentPayment();
		Assert.areEqual(
			'Reconocido',
			receiptStatus(receipt.Id),
			'2979.40 y 2979.4 son el mismo importe: el cobro no se anula.'
		);
		Assert.areEqual('Conciliado', after.inboundStatus__c);
		Assert.isTrue(String.isBlank(after.resendChangeLog__c));
	}

	@IsTest
	static void installmentNumberWrittenDifferentlyIsNotACorrection() {
		invokeEndpoint(resendBody('1000.00', ',"sourceInstallmentNumber__c":"1"'));
		PolicyPaymentReceipt__c receipt = buildReconciledChain('POL-431-03');

		Test.startTest();
		invokeEndpoint(
			resendBody('1000.00', ',"sourceInstallmentNumber__c":"01/02"')
		);
		Test.stopTest();

		InboundInsurancePayment__c after = resentPayment();
		Assert.areEqual(
			'01/02',
			after.sourceInstallmentNumber__c,
			'El dato se actualiza tal como llega.'
		);
		Assert.areEqual('Reconocido', receiptStatus(receipt.Id));
		Assert.areEqual('Conciliado', after.inboundStatus__c);
		Assert.isTrue(String.isBlank(after.resendChangeLog__c));
	}

	@IsTest
	static void completingAnEmptyCurrencyOrStatusIsNotACorrection() {
		invokeEndpoint(resendBody('1000.00', ''));
		PolicyPaymentReceipt__c receipt = buildReconciledChain('POL-431-04');
		// Asi quedaron los pagos de la carga inicial: sin moneda y sin estatus de la
		// aseguradora.
		update new InboundInsurancePayment__c(
			Id = resentPayment().Id,
			carrierReceiptStatus__c = null,
			sourcePaymentStatus__c = null,
			sourceCurrency__c = null
		);

		Test.startTest();
		invokeEndpoint(resendBody('1000.00', ',"sourceCurrency__c":"MXN"'));
		Test.stopTest();

		InboundInsurancePayment__c after = resentPayment();
		Assert.areEqual('MXN', after.sourceCurrency__c, 'Se completa la moneda.');
		Assert.areEqual(
			'Pagado',
			after.carrierReceiptStatus__c,
			'Se completa el estatus.'
		);
		Assert.areEqual(
			'Reconocido',
			receiptStatus(receipt.Id),
			'Un pago con fecha de pago y sin estatus ya se daba por pagado: no hay cambio.'
		);
		Assert.areEqual('Conciliado', after.inboundStatus__c);
		Assert.isTrue(String.isBlank(after.resendChangeLog__c));
	}

	@IsTest
	static void realCorrectionAnnulsReceiptAndPaymentReentersTheCircuit() {
		invokeEndpoint(resendBody('1000.00', ''));
		PolicyPaymentReceipt__c receipt = buildReconciledChain('POL-431-05');

		Test.startTest();
		invokeEndpoint(
			resendBody('1000.00', '')
				.replace(
					'"sourceDueDate__c":"15/09/2026"',
					'"sourceDueDate__c":"20/09/2026"'
				)
		);
		Test.stopTest();

		InboundInsurancePayment__c after = resentPayment();
		Assert.areEqual('Reversado', receiptStatus(receipt.Id));
		Assert.isTrue(
			after.resendChangeLog__c.contains('fecha de vencimiento'),
			'La bitacora dice que cambio: ' + after.resendChangeLog__c
		);
		Assert.areEqual(
			'Normalizado',
			after.inboundStatus__c,
			'La reversa no puede dejar en revision manual un pago que se esta reprocesando: ' +
			'tiene que seguir por el circuito.'
		);
		Assert.areEqual(
			0,
			[
				SELECT COUNT()
				FROM AppLog__c
				WHERE eventCode__c = :CobranzaLog.EVENT_RESEND_NOT_REQUEUED
			]
		);
	}

	@IsTest
	static void rejectedPaymentResentUpdatesTheSameRecord() {
		String body =
			'[{"sourcePolicyNumber__c":"POL-431-06","sourceAmount__c":0,' +
			'"sourceCarrierCode__c":"GNP","sourceReceiptNumber__c":"431-6"}]';
		invokeEndpoint(body);

		Test.startTest();
		invokeEndpoint(
			body.replace('"sourceAmount__c":0', '"sourceAmount__c":-10')
		);
		Test.stopTest();

		Assert.areNotEqual(500, RestContext.response.statusCode);
		InboundInsurancePayment__c rejected = [
			SELECT
				inboundStatus__c,
				rejectionReason__c,
				sourceAmount__c,
				resendCount__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c = 'GNP_431-6'
		];
		Assert.areEqual('Rechazado', rejected.inboundStatus__c);
		Assert.areEqual('Importe invalido', rejected.rejectionReason__c);
		Assert.areEqual(
			-10,
			rejected.sourceAmount__c,
			'Se actualiza el mismo registro.'
		);
		Assert.areEqual(1, rejected.resendCount__c, 'Y se cuenta el reenvio.');
	}

	@IsTest
	static void rejectedWithoutFolioIsRecognizedAcrossSyncs() {
		String body =
			'[{"sourcePolicyNumber__c":"POL-431-07","sourceAmount__c":450.00,' +
			'"sourceCarrierCode__c":"QUALITAS","sourceInsuranceCarrier__c":"QUALITAS",' +
			'"sourcePaymentStatus__c":"Cancelado","sourceCancellationDate__c":"31/10/2025",' +
			'"sourceSynchronizedAt__c":"10/09/2026 14:24:00"}]';
		invokeEndpoint(body);

		Test.startTest();
		invokeEndpoint(body.replace('10/09/2026 14:24:00', '11/09/2026 08:00:00'));
		invokeEndpoint(body.replace('450.00', '451.00'));
		Test.stopTest();

		Assert.areEqual(
			2,
			[
				SELECT COUNT()
				FROM InboundInsurancePayment__c
				WHERE sourcePolicyNumber__c = 'POL-431-07'
			],
			'El mismo contenido en otra sincronizacion es el mismo recibo; otro importe es otro.'
		);
		Assert.areEqual(
			1,
			[
				SELECT resendCount__c
				FROM InboundInsurancePayment__c
				WHERE sourcePolicyNumber__c = 'POL-431-07' AND sourceAmount__c = 450.00
			]
			.resendCount__c
		);
	}

	@IsTest
	static void repeatedRejectedRowsInOneBatchAreStoredOnce() {
		String withFolio =
			'{"sourcePolicyNumber__c":"POL-431-12","sourceAmount__c":0,' +
			'"sourceCarrierCode__c":"GNP","sourceReceiptNumber__c":"431-12"}';
		String withoutFolio =
			'{"sourcePolicyNumber__c":"POL-431-12","sourceAmount__c":90.00,' +
			'"sourceCarrierCode__c":"GNP","sourcePaymentStatus__c":"Cancelado"}';

		Test.startTest();
		invokeEndpoint(
			'[' +
				withFolio +
				',' +
				withFolio +
				',' +
				withoutFolio +
				',' +
				withoutFolio +
				']'
		);
		Test.stopTest();

		Assert.areNotEqual(500, RestContext.response.statusCode);
		Assert.areEqual(
			2,
			[
				SELECT COUNT()
				FROM InboundInsurancePayment__c
				WHERE sourcePolicyNumber__c = 'POL-431-12'
			]
		);
		Assert.areEqual(4, toInteger(getResponseBody().get('rejectedCount')));
	}

	@IsTest
	static void oneBadPaymentDoesNotAffectTheRestOfTheBatch() {
		// Un dato que no cabe en su campo hace fallar el guardado de ese pago, y solo de ese.
		String tooLong = ',"sourceCustomerName__c":"' + 'X'.repeat(300) + '"';

		Test.startTest();
		invokeEndpoint(
			'[' +
				paidRow('431-8A', '') +
				',' +
				paidRow('431-8B', tooLong) +
				',' +
				paidRow('431-8C', '') +
				']'
		);
		Test.stopTest();

		Assert.areEqual(202, RestContext.response.statusCode);
		Map<String, Object> body = getResponseBody();
		Assert.areEqual(2, toInteger(body.get('receivedCount')));
		Assert.areEqual(1, toInteger(body.get('rejectedCount')));

		Map<String, Object> bad = resultFor('GNP_431-8B');
		Assert.areEqual(false, bad.get('success'));
		Assert.areEqual('WRITE_FAILED', bad.get('code'));
		Assert.isTrue(
			String.valueOf(bad.get('message')).contains('STRING_TOO_LONG'),
			'La respuesta dice por que fallo: ' + bad.get('message')
		);

		Assert.areEqual(
			2,
			[
				SELECT COUNT()
				FROM InboundInsurancePayment__c
				WHERE externalPaymentId__c IN ('GNP_431-8A', 'GNP_431-8C')
			]
		);
		List<AppLog__c> logs = [
			SELECT message__c, stackTrace__c
			FROM AppLog__c
			WHERE eventCode__c = :CobranzaLog.EVENT_INBOUND_WRITE_FAILED
		];
		Assert.areEqual(1, logs.size(), 'El fallo queda registrado para soporte.');
		Assert.isTrue(logs[0].message__c.contains('GNP_431-8B'));
		Assert.isTrue(
			logs[0].stackTrace__c.contains('431-8B'),
			'Con el JSON recibido, para poder reenviarlo.'
		);
	}

	@IsTest
	static void failedSaveDoesNotAnnulTheReceipt() {
		invokeEndpoint(resendBody('1000.00', ''));
		PolicyPaymentReceipt__c receipt = buildReconciledChain('POL-431-09');

		Test.startTest();
		invokeEndpoint(
			resendBody(
				'1200.00',
				',"sourceCustomerName__c":"' + 'X'.repeat(300) + '"'
			)
		);
		Test.stopTest();

		Assert.areNotEqual(500, RestContext.response.statusCode);
		Assert.areEqual(
			'Reconocido',
			receiptStatus(receipt.Id),
			'Si la correccion no se pudo guardar, el cobro anterior sigue vigente.'
		);
		InboundInsurancePayment__c after = resentPayment();
		Assert.areEqual(1000.00, after.sourceAmount__c);
		Assert.areEqual('Conciliado', after.inboundStatus__c);
	}

	@IsTest
	static void invalidResendOfAValidPaymentIsNotApplied() {
		invokeEndpoint(resendBody('1000.00', ''));
		PolicyPaymentReceipt__c receipt = buildReconciledChain('POL-431-10');

		Test.startTest();
		invokeEndpoint(resendBody('0', ''));
		Test.stopTest();

		Assert.areNotEqual(500, RestContext.response.statusCode);
		InboundInsurancePayment__c after = resentPayment();
		Assert.areEqual(
			1000.00,
			after.sourceAmount__c,
			'Los datos buenos no se pisan.'
		);
		Assert.areEqual('Conciliado', after.inboundStatus__c);
		Assert.areEqual('Reconocido', receiptStatus(receipt.Id));
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM AppLog__c
				WHERE eventCode__c = :CobranzaLog.EVENT_INVALID_RESEND_IGNORED
			]
		);
	}

	@IsTest
	static void unexpectedFailureUndoesTheWholeRequestAndIsLogged() {
		invokeEndpoint(resendBody('1000.00', ''));
		PolicyPaymentReceipt__c receipt = buildReconciledChain('POL-431-11');
		InboundInsurancePaymentService.forceFailureAfterWritesForTest = true;

		Test.startTest();
		invokeEndpoint(resendBody('1200.00', ''));
		Test.stopTest();

		InboundInsurancePaymentService.forceFailureAfterWritesForTest = false;

		Assert.areEqual(500, RestContext.response.statusCode);
		Assert.areEqual(
			'Reconocido',
			receiptStatus(receipt.Id),
			'La anulacion que alcanzo a hacerse se deshace con el resto de la peticion.'
		);
		InboundInsurancePayment__c after = resentPayment();
		Assert.areEqual(1000.00, after.sourceAmount__c);
		Assert.areEqual('Conciliado', after.inboundStatus__c);
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM AppLog__c
				WHERE eventCode__c = :CobranzaLog.EVENT_ENDPOINT_FAILED
			],
			'Y el fallo queda registrado aunque todo lo demas se deshaga.'
		);
	}

	@IsTest
	static void repeatedMalformedBodyDoesNotFail() {
		Test.startTest();
		invokeEndpoint('[{"externalPaymentId__c":"EXT-4312"');
		invokeEndpoint('[{"externalPaymentId__c":"EXT-4312"');
		Test.stopTest();

		Assert.areEqual(400, RestContext.response.statusCode);
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM InboundInsurancePayment__c
				WHERE rejectionReason__c = 'Payload malformado'
			]
		);
	}

	private static void invokeEndpoint(String requestBody) {
		RestRequest request = new RestRequest();
		request.requestUri = '/services/apexrest/collections/v1/inbound-payments';
		request.httpMethod = 'POST';
		if (requestBody != null) {
			request.requestBody = Blob.valueOf(requestBody);
		}

		RestContext.request = request;
		RestContext.response = new RestResponse();

		InboundInsurancePaymentRestResource.receive();
	}

	private static Map<String, Object> getResponseBody() {
		return (Map<String, Object>) JSON.deserializeUntyped(
			RestContext.response.responseBody.toString()
		);
	}

	private static Integer toInteger(Object value) {
		return value == null
			? 0
			: Decimal.valueOf(String.valueOf(value)).intValue();
	}
}
