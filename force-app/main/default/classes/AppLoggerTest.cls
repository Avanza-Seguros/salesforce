/**
 *   @name: AppLoggerTest
 *   @version: 1.0
 *   @creation date: 29/07/2026
 *   @author: Javier Torres - Volestra
 *   @description: Pruebas del servicio de registro de aplicacion (H200): severidad fija por
 *                 operacion, derivacion de clase y metodo desde el rastro, contexto de
 *                 ejecucion, escritura agrupada en un unico DML, tolerancia a fallos y
 *                 asociacion al registro de negocio afectado.
 */
@isTest
private class AppLoggerTest {
	private class SampleException extends Exception {
	}

	/**
	 * @description: Un error registrado desde una excepcion guarda severidad Error, el
	 *               mensaje y el detalle tecnico de la propia excepcion.
	 */
	@isTest
	static void errorFromExceptionStoresMessageAndStackTrace() {
		Test.startTest();
		try {
			throw new SampleException('Fallo de prueba');
		} catch (Exception e) {
			AppLogger.error(
				AppLogger.DOMAIN_COBRANZA,
				'Etapa de prueba',
				'TEST_FAILED',
				e
			);
		}
		AppLogger.flush();
		Test.stopTest();

		AppLog__c log = [
			SELECT
				severity__c,
				domain__c,
				stage__c,
				eventCode__c,
				message__c,
				stackTrace__c,
				occurredAt__c
			FROM AppLog__c
			LIMIT 1
		];
		System.assertEquals('Error', log.severity__c, 'Debe ser severidad Error.');
		System.assertEquals('Cobranza', log.domain__c, 'Debe guardar el dominio.');
		System.assertEquals(
			'Etapa de prueba',
			log.stage__c,
			'Debe guardar la etapa.'
		);
		System.assertEquals(
			'TEST_FAILED',
			log.eventCode__c,
			'Debe guardar el codigo de evento.'
		);
		System.assertEquals(
			'Fallo de prueba',
			log.message__c,
			'Debe guardar el mensaje de la excepcion.'
		);
		System.assertNotEquals(
			null,
			log.stackTrace__c,
			'Debe guardar el detalle tecnico.'
		);
		System.assertNotEquals(
			null,
			log.occurredAt__c,
			'Debe guardar el momento del evento.'
		);
	}

	/**
	 * @description: La clase y el metodo de origen se derivan del rastro y apuntan al codigo
	 *               que invoco el registro, nunca al propio servicio.
	 */
	@isTest
	static void originPointsToCallerNotToLogger() {
		Test.startTest();
		AppLogger.warn(
			AppLogger.DOMAIN_COBRANZA,
			'Etapa',
			'TEST_WARN',
			'Advertencia de prueba'
		);
		AppLogger.flush();
		Test.stopTest();

		AppLog__c log = [
			SELECT className__c, methodName__c
			FROM AppLog__c
			LIMIT 1
		];
		System.assertEquals(
			'AppLoggerTest',
			log.className__c,
			'La clase de origen debe ser quien invoco, no AppLogger.'
		);
		System.assertEquals(
			'originPointsToCallerNotToLogger',
			log.methodName__c,
			'El metodo de origen debe ser quien invoco.'
		);
	}

	/**
	 * @description: Cada operacion publica fija su propia severidad; no existe forma de
	 *               registrar con una severidad distinta a la de la operacion usada.
	 */
	@isTest
	static void eachOperationFixesItsOwnSeverity() {
		Test.startTest();
		AppLogger.warn(AppLogger.DOMAIN_CORREOS, 'Etapa', 'W', 'advertencia');
		AppLogger.info(AppLogger.DOMAIN_CORREOS, 'Etapa', 'I', 'informacion');
		AppLogger.error(
			AppLogger.DOMAIN_CORREOS,
			'Etapa',
			'E',
			'error sin excepcion'
		);
		AppLogger.flush();
		Test.stopTest();

		Map<String, String> severityByCode = new Map<String, String>();
		for (AppLog__c log : [SELECT eventCode__c, severity__c FROM AppLog__c]) {
			severityByCode.put(log.eventCode__c, log.severity__c);
		}
		System.assertEquals(
			'Advertencia',
			severityByCode.get('W'),
			'warn debe registrar Advertencia.'
		);
		System.assertEquals(
			'Informacion',
			severityByCode.get('I'),
			'info debe registrar Informacion.'
		);
		System.assertEquals(
			'Error',
			severityByCode.get('E'),
			'error sin excepcion debe registrar Error.'
		);
	}

	/**
	 * @description: Todas las entradas de una misma ejecucion comparten identificador de
	 *               transaccion, de modo que puedan recuperarse juntas.
	 */
	@isTest
	static void entriesOfSameRunShareTransactionId() {
		Test.startTest();
		AppLogger.info(AppLogger.DOMAIN_OTRO, 'Etapa', 'A', 'primera');
		AppLogger.info(AppLogger.DOMAIN_OTRO, 'Etapa', 'B', 'segunda');
		AppLogger.flush();
		Test.stopTest();

		List<AppLog__c> logs = [SELECT transactionId__c FROM AppLog__c];
		System.assertEquals(2, logs.size(), 'Deben existir dos registros.');
		System.assertNotEquals(
			null,
			logs[0].transactionId__c,
			'El identificador de transaccion debe estar informado.'
		);
		System.assertEquals(
			logs[0].transactionId__c,
			logs[1].transactionId__c,
			'Ambas entradas deben compartir la transaccion.'
		);
	}

	/**
	 * @description: Registrar 50 eventos consume una unica operacion de base de datos, de
	 *               modo que registrar dentro de un bucle no agote los limites.
	 */
	@isTest
	static void flushWritesAllEntriesWithASingleDml() {
		Test.startTest();
		for (Integer i = 0; i < 50; i++) {
			AppLogger.info(AppLogger.DOMAIN_OTRO, 'Etapa', 'BULK', 'evento ' + i);
		}
		System.assertEquals(
			50,
			AppLogger.pendingCount(),
			'Las entradas deben quedar acumuladas sin escribirse.'
		);

		Integer dmlBefore = Limits.getDmlStatements();
		AppLogger.flush();
		Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
		Test.stopTest();

		System.assertEquals(
			1,
			dmlUsed,
			'Las 50 entradas deben escribirse con una unica operacion.'
		);
		System.assertEquals(
			50,
			[SELECT COUNT() FROM AppLog__c],
			'Deben persistirse las 50 entradas.'
		);
		System.assertEquals(
			0,
			AppLogger.pendingCount(),
			'El buffer debe quedar vacio tras escribir.'
		);
	}

	/**
	 * @description: Un fallo al escribir el registro no propaga al proceso llamador: se
	 *               pierde la traza, no la operacion de negocio.
	 */
	@isTest
	static void flushFailureDoesNotBreakCaller() {
		AppLogger.forceFlushFailureForTest = true;

		Test.startTest();
		AppLogger.info(AppLogger.DOMAIN_OTRO, 'Etapa', 'X', 'evento');
		Boolean callerSurvived = true;
		try {
			AppLogger.flush();
		} catch (Exception e) {
			callerSurvived = false;
		}
		Test.stopTest();

		System.assert(
			callerSurvived,
			'Un fallo al registrar no debe propagar al proceso llamador.'
		);
		System.assertEquals(
			0,
			[SELECT COUNT() FROM AppLog__c],
			'No debe persistirse nada si la escritura fallo.'
		);
		System.assertEquals(
			0,
			AppLogger.pendingCount(),
			'El buffer debe vaciarse igualmente para no reintentar indefinidamente.'
		);
	}

	/**
	 * @description: El registro afectado se asocia por lookup y ademas de forma generica,
	 *               resolviendo a que objeto pertenece.
	 */
	@isTest
	static void entryAssociatesAffectedRecord() {
		InboundInsurancePayment__c inbound = new InboundInsurancePayment__c(
			externalPaymentId__c = 'TEST_LOG_1',
			inboundStatus__c = 'Parseado',
			sourceAmount__c = 100
		);
		insert inbound;

		Test.startTest();
		AppLogger.info(AppLogger.DOMAIN_COBRANZA, 'Etapa', 'REL', 'evento')
			.onInbound(inbound.Id);
		AppLogger.flush();
		Test.stopTest();

		AppLog__c log = [
			SELECT inboundPayment__c, recordId__c, recordObject__c
			FROM AppLog__c
			LIMIT 1
		];
		System.assertEquals(
			inbound.Id,
			log.inboundPayment__c,
			'Debe asociar el pago inbound por lookup.'
		);
		System.assertEquals(
			String.valueOf(inbound.Id),
			log.recordId__c,
			'Debe completar el registro afectado generico.'
		);
		System.assertEquals(
			'InboundInsurancePayment__c',
			log.recordObject__c,
			'Debe resolver el objeto del registro afectado.'
		);
	}

	/**
	 * @description: Un mensaje mas largo que el campo destino se recorta y no impide guardar
	 *               el registro.
	 */
	@isTest
	static void longMessageIsTruncatedInsteadOfFailing() {
		String longMessage = 'x'.repeat(400);

		Test.startTest();
		AppLogger.info(AppLogger.DOMAIN_OTRO, 'Etapa', 'LONG', longMessage);
		AppLogger.flush();
		Test.stopTest();

		AppLog__c log = [SELECT message__c FROM AppLog__c LIMIT 1];
		System.assertEquals(
			255,
			log.message__c.length(),
			'El mensaje debe recortarse a la longitud del campo.'
		);
	}

	/**
	 * @description: El identificador del proceso asincrono se aplica a las entradas de la
	 *               transaccion una vez fijado.
	 */
	@isTest
	static void jobContextIsAppliedToEntries() {
		Id fakeJobId = UserInfo.getUserId();

		Test.startTest();
		AppLogger.setJobContext(fakeJobId);
		AppLogger.info(AppLogger.DOMAIN_OTRO, 'Etapa', 'JOB', 'evento');
		AppLogger.flush();
		Test.stopTest();

		AppLog__c log = [SELECT jobId__c FROM AppLog__c LIMIT 1];
		System.assertEquals(
			String.valueOf(fakeJobId),
			log.jobId__c,
			'Debe guardar el identificador del proceso asincrono.'
		);
	}

	/**
	 * @description: Un rastro vacio o no interpretable deja la clase y el metodo sin
	 *               informar, sin impedir que el registro se guarde.
	 */
	@isTest
	static void unparseableStackTraceLeavesOriginEmpty() {
		AppLog__c log = new AppLog__c(severity__c = 'Error');

		Test.startTest();
		AppLogger.applyOrigin(log, null);
		AppLogger.applyOrigin(log, 'texto sin formato de rastro');
		Test.stopTest();

		System.assertEquals(
			null,
			log.className__c,
			'Un rastro no interpretable no debe informar la clase.'
		);
		System.assertEquals(
			null,
			log.methodName__c,
			'Un rastro no interpretable no debe informar el metodo.'
		);
	}

	/**
	 * @description: Escribir sin entradas acumuladas no consume operaciones de base de datos.
	 */
	@isTest
	static void flushWithEmptyBufferDoesNothing() {
		Test.startTest();
		Integer dmlBefore = Limits.getDmlStatements();
		AppLogger.flush();
		Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
		Test.stopTest();

		System.assertEquals(
			0,
			dmlUsed,
			'Sin entradas acumuladas no debe consumirse ninguna operacion.'
		);
	}
}
