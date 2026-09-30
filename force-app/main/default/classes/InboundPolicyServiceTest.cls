@IsTest
private class InboundPolicyServiceTest {
	private static final String ROW_1 = '{"sourcePolicyNumber__c":"0971522815","sourceCarrierCode__c":"qualitas","sourcePolicyStartDate__c":"2025-12-06","sourcePolicyEndDate__c":"2026-12-06","sourcePolicyStatusRaw__c":"Vigor","sourcePremiumFrequency__c":"Semestral","sourceTotalPremium__c":12500.50,"sourceNetPremium__c":"10000","sourceDiscountPercent__c":"10","sourcePaidPremium__c":6250,"sourceNextDueDate__c":"06/06/2026","sourceSynchronizedAt__c":"2026-09-25T10:57:14Z"}';
	private static final String ROW_2 = '{"sourcePolicyNumber__c":"0971387218","sourceCarrierCode__c":"QUALITAS","sourcePolicyStartDate__c":"15/01/2026","sourcePolicyStatusRaw__c":"Cancelada","sourceCancellationDate__c":"2026-03-01"}';

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Un lote valido se guarda entero: datos, JSON crudo, huella,
	 *               fecha de recepcion y sistema de origen.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void storesEveryRowWithItsRawJson() {
		Test.startTest();
		Map<String, Object> response = post('[' + ROW_1 + ',' + ROW_2 + ']');
		Test.stopTest();

		Assert.areEqual(202, RestContext.response.statusCode);
		Assert.areEqual(true, response.get('success'));
		Assert.areEqual(2, response.get('totalRecords'));
		Assert.areEqual(2, response.get('receivedCount'));
		Assert.areEqual(0, response.get('rejectedCount'));

		InboundPolicyUpdate__c first = load('0971522815');
		Assert.areEqual('Recibido', first.inboundStatus__c);
		Assert.areEqual('QUALITAS', first.sourceCarrierCode__c);
		Assert.areEqual(
			Date.newInstance(2025, 12, 6),
			first.sourcePolicyStartDate__c
		);
		Assert.areEqual(
			Date.newInstance(2026, 12, 6),
			first.sourcePolicyEndDate__c
		);
		Assert.areEqual('Vigor', first.sourcePolicyStatusRaw__c);
		Assert.areEqual(Decimal.valueOf('12500.50'), first.sourceTotalPremium__c);
		Assert.areEqual(Decimal.valueOf('10000'), first.sourceNetPremium__c);
		Assert.areEqual(Decimal.valueOf('10'), first.sourceDiscountPercent__c);
		Assert.areEqual(Decimal.valueOf('6250'), first.sourcePaidPremium__c);
		Assert.areEqual(Date.newInstance(2026, 6, 6), first.sourceNextDueDate__c);
		Assert.areEqual(
			Datetime.newInstanceGmt(2026, 9, 25, 10, 57, 14),
			first.sourceSynchronizedAt__c
		);
		Assert.areEqual('0971522815|2025-12-06|QUALITAS', first.identityKey__c);
		Assert.isTrue(first.sourcePayloadJson__c.contains('0971522815'));
		Assert.isNotNull(first.sourcePayloadHash__c);
		Assert.isNotNull(first.contentFingerprint__c);
		Assert.isNotNull(first.receivedAt__c);
		Assert.areEqual('MuleSoft', first.sourceSystem__c);
		Assert.areEqual(0, first.resendCount__c);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: La misma poliza reenviada sin cambios (aunque cambie la fecha de
	 *               sincronizacion) no se duplica: suma un reenvio.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void resendWithoutChangesDoesNotDuplicate() {
		post('[' + ROW_1 + ']');

		Test.startTest();
		Map<String, Object> response = post(
			'[' + ROW_1.replace('2026-09-25T10:57:14Z', '2026-09-26T08:00:00Z') + ']'
		);
		Test.stopTest();

		Assert.areEqual(202, RestContext.response.statusCode);
		Assert.areEqual(0, response.get('receivedCount'));
		Assert.areEqual(1, response.get('updatedCount'));
		Assert.areEqual('RESENT', firstItem(response).get('code'));
		Assert.areEqual(
			'0971522815',
			firstItem(response).get('sourcePolicyNumber')
		);
		Assert.areEqual(1, [SELECT COUNT() FROM InboundPolicyUpdate__c]);

		InboundPolicyUpdate__c saved = load('0971522815');
		Assert.areEqual(1, saved.resendCount__c);
		Assert.areEqual(
			Datetime.newInstanceGmt(2026, 9, 26, 8, 0, 0),
			saved.sourceSynchronizedAt__c
		);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Si cambia algo de la poliza, es otra comunicacion: se guarda aparte y la
	 *               anterior se conserva.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void changedContentIsANewCommunication() {
		post('[' + ROW_1 + ']');

		Test.startTest();
		Map<String, Object> response = post(
			'[' + ROW_1.replace('"Vigor"', '"Cancelada"') + ']'
		);
		Test.stopTest();

		Assert.areEqual(1, response.get('receivedCount'));
		Assert.areEqual(
			2,
			[
				SELECT COUNT()
				FROM InboundPolicyUpdate__c
				WHERE identityKey__c = '0971522815|2025-12-06|QUALITAS'
			]
		);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: La misma comunicacion dos veces en el mismo lote se guarda una vez.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void duplicateInsideTheBatchIsStoredOnce() {
		Test.startTest();
		Map<String, Object> response = post('[' + ROW_1 + ',' + ROW_1 + ']');
		Test.stopTest();

		Assert.areEqual(1, response.get('receivedCount'));
		Assert.areEqual(1, response.get('updatedCount'));
		Assert.areEqual(1, [SELECT COUNT() FROM InboundPolicyUpdate__c]);
		Assert.areEqual(1, load('0971522815').resendCount__c);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: El numero de poliza conserva sus ceros; si llega como numero se
	 *               rechaza con un motivo claro, y se guarda igual.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void numericPolicyNumberIsRejected() {
		Test.startTest();
		Map<String, Object> response = post(
			'[{"sourcePolicyNumber__c":971522815,"sourcePolicyStartDate__c":"2025-12-06"}]'
		);
		Test.stopTest();

		Assert.areEqual(400, RestContext.response.statusCode);
		Assert.areEqual('REJECTED', firstItem(response).get('code'));
		Assert.isTrue(
			((String) firstItem(response).get('message')).contains('como texto')
		);

		InboundPolicyUpdate__c saved = load('971522815');
		Assert.areEqual('Rechazado', saved.inboundStatus__c);
		Assert.isTrue(saved.rejectionReason__c.contains('ceros a la izquierda'));
		Assert.isNull(saved.identityKey__c);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Se aceptan fechas ISO y dd/mm/aaaa; una fecha imposible no se toma.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void acceptsBothDateFormats() {
		Test.startTest();
		post('[' + ROW_2 + ']');
		Test.stopTest();

		InboundPolicyUpdate__c saved = load('0971387218');
		Assert.areEqual(
			Date.newInstance(2026, 1, 15),
			saved.sourcePolicyStartDate__c
		);
		Assert.areEqual(
			Date.newInstance(2026, 3, 1),
			saved.sourceCancellationDate__c
		);
		Assert.areEqual(
			Date.newInstance(2025, 12, 6),
			InboundPolicyService.parseDate('2025-12-06T10:57:14Z')
		);
		Assert.isNull(InboundPolicyService.parseDate('31/02/2026'));
		Assert.isNull(InboundPolicyService.parseDate('06-12-2025'));
		Assert.areEqual(
			Datetime.newInstanceGmt(2026, 9, 25, 20, 30, 0),
			InboundPolicyService.parseDatetime('25/09/2026 14:30:00'),
			'Sin zona es hora de Ciudad de Mexico (GMT-6), como en el canal de pagos'
		);
		Assert.areEqual(
			Datetime.newInstanceGmt(2026, 9, 25, 20, 30, 0),
			InboundPolicyService.parseDatetime('2026-09-25T14:30:00'),
			'ISO sin zona, igual'
		);
		Assert.areEqual(
			Datetime.newInstanceGmt(2026, 9, 25, 14, 30, 0),
			InboundPolicyService.parseDatetime('2026-09-25T14:30:00Z'),
			'Con Z se respeta'
		);
		Assert.areEqual(
			Datetime.newInstanceGmt(2026, 9, 25, 20, 30, 0),
			InboundPolicyService.parseDatetime('2026-09-25T14:30:00-06:00')
		);
		Assert.isNull(InboundPolicyService.parseDatetime('no es fecha'));
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Las filas incompletas se rechazan con su motivo y las demas se
	 *               procesan; la respuesta lo dice fila por fila.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void incompleteRowsDoNotStopTheBatch() {
		String noNumber = '{"sourcePolicyStartDate__c":"2025-12-06"}';
		String noStart = '{"sourcePolicyNumber__c":"0971000001"}';
		String badStart = '{"sourcePolicyNumber__c":"0971000002","sourcePolicyStartDate__c":"ayer"}';

		Test.startTest();
		Map<String, Object> response = post(
			'[' +
				noNumber +
				',' +
				noStart +
				',' +
				badStart +
				',' +
				ROW_1 +
				',"texto"]'
		);
		Test.stopTest();

		Assert.areEqual(202, RestContext.response.statusCode);
		Assert.areEqual(false, response.get('success'));
		Assert.areEqual(1, response.get('receivedCount'));
		Assert.areEqual(4, response.get('rejectedCount'));

		List<Object> results = (List<Object>) response.get('results');
		Assert.isTrue(message(results, 0).contains('numero de poliza'));
		Assert.isTrue(message(results, 1).contains('Falta el inicio de vigencia'));
		Assert.isTrue(message(results, 2).contains('no es una fecha valida'));
		Assert.areEqual('RECEIVED', ((Map<String, Object>) results[3]).get('code'));
		Assert.isTrue(message(results, 4).contains('objeto JSON'));
		Assert.areEqual(
			4,
			[
				SELECT COUNT()
				FROM InboundPolicyUpdate__c
				WHERE inboundStatus__c = 'Rechazado'
			],
			'Nada se descarta: los rechazados tambien se guardan'
		);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Un cuerpo que no es un arreglo JSON responde error y queda guardado;
	 *               el mismo cuerpo reenviado suma un reenvio.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void malformedBodyIsStored() {
		Test.startTest();
		Map<String, Object> response = post('{esto no es json');
		post('{esto no es json');
		Test.stopTest();

		Assert.areEqual(400, RestContext.response.statusCode);
		Assert.areEqual('INVALID_JSON', response.get('code'));
		Assert.isNotNull(response.get('inboundPolicyUpdateId'));

		InboundPolicyUpdate__c saved = [
			SELECT
				inboundStatus__c,
				rejectionReason__c,
				sourcePayloadJson__c,
				resendCount__c
			FROM InboundPolicyUpdate__c
		];
		Assert.areEqual('Rechazado', saved.inboundStatus__c);
		Assert.areEqual('{esto no es json', saved.sourcePayloadJson__c);
		Assert.areEqual(1, saved.resendCount__c);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Cuerpo vacio, arreglo vacio, objeto suelto y lote demasiado grande.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void rejectsInvalidEnvelopes() {
		List<String> tooMany = new List<String>();

		for (Integer i = 0; i <= InboundPolicyService.MAX_ROWS; i++) {
			tooMany.add(ROW_1);
		}

		Test.startTest();
		Map<String, Object> empty = post('');
		Map<String, Object> emptyArray = post('[]');
		Map<String, Object> single = post(ROW_1);
		Map<String, Object> large = post('[' + String.join(tooMany, ',') + ']');
		Test.stopTest();

		Assert.areEqual('EMPTY_BODY', empty.get('code'));
		Assert.areEqual('EMPTY_BODY', emptyArray.get('code'));
		Assert.areEqual('INVALID_JSON', single.get('code'));
		Assert.areEqual('BATCH_TOO_LARGE', large.get('code'));
		Assert.areEqual(
			1,
			[SELECT COUNT() FROM InboundPolicyUpdate__c],
			'Solo el objeto suelto queda guardado, como cuerpo rechazado'
		);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Un fallo inesperado deshace todo, responde 500 y queda registrado.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void unexpectedFailureRollsBackAndIsLogged() {
		InboundPolicyRestResource.forceServiceException = true;

		Test.startTest();
		Map<String, Object> response = post('[' + ROW_1 + ']');
		Test.stopTest();

		Assert.areEqual(500, RestContext.response.statusCode);
		Assert.areEqual('INTERNAL_ERROR', response.get('code'));
		Assert.areEqual(0, [SELECT COUNT() FROM InboundPolicyUpdate__c]);
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM AppLog__c
				WHERE eventCode__c = 'POLICY_ENDPOINT_FAILED'
			]
		);
	}

	private static Map<String, Object> post(String body) {
		// Esta clase prueba solo la recepcion; aplicar a la poliza lo prueba
		// InboundPolicyApplyServiceTest.
		InboundPolicyService.applyDisabledForTest = true;
		RestRequest request = new RestRequest();
		request.requestURI = '/services/apexrest/collections/v1/inbound-policies';
		request.httpMethod = 'POST';
		request.requestBody = Blob.valueOf(body);
		RestContext.request = request;
		RestContext.response = new RestResponse();
		InboundPolicyRestResource.receive();
		return (Map<String, Object>) JSON.deserializeUntyped(
			RestContext.response.responseBody.toString()
		);
	}

	private static Map<String, Object> firstItem(Map<String, Object> response) {
		return (Map<String, Object>) ((List<Object>) response.get('results'))[0];
	}

	private static String message(List<Object> results, Integer index) {
		return (String) ((Map<String, Object>) results[index]).get('message');
	}

	private static InboundPolicyUpdate__c load(String policyNumber) {
		return [
			SELECT
				inboundStatus__c,
				rejectionReason__c,
				sourceCarrierCode__c,
				sourcePolicyStartDate__c,
				sourcePolicyEndDate__c,
				sourcePolicyStatusRaw__c,
				sourceTotalPremium__c,
				sourceNetPremium__c,
				sourceDiscountPercent__c,
				sourcePaidPremium__c,
				sourceNextDueDate__c,
				sourceCancellationDate__c,
				sourceSynchronizedAt__c,
				identityKey__c,
				sourcePayloadJson__c,
				sourcePayloadHash__c,
				contentFingerprint__c,
				receivedAt__c,
				sourceSystem__c,
				resendCount__c
			FROM InboundPolicyUpdate__c
			WHERE sourcePolicyNumber__c = :policyNumber
			ORDER BY CreatedDate
			LIMIT 1
		];
	}
}
