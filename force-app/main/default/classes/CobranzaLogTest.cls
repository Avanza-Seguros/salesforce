/**
 *   @name: CobranzaLogTest
 *   @version: 1.0
 *   @creation date: 29/07/2026
 *   @author: Javier Torres - Volestra
 *   @description: Pruebas del catalogo y los atajos de registro del modulo de cobranza
 *                 (H200): rotura de cadena, sellado de la etapa alcanzada y finalizador de
 *                 interrupcion total.
 *                 El finalizador se prueba con un contexto simulado en lugar de provocar la
 *                 interrupcion real de un job: la plataforma no garantiza la ejecucion de
 *                 finalizadores en contexto de prueba, y de este modo la logica queda
 *                 cubierta igualmente. La ejecucion real se valida a mano en el entorno de
 *                 pruebas segun la guia de QA.
 */
@isTest
private class CobranzaLogTest {
	private class SampleAsyncException extends Exception {
	}

	/**
	 *   @description: Contexto de finalizador simulado, para cubrir la logica sin depender
	 *                 de que la plataforma ejecute finalizadores durante las pruebas.
	 */
	private class MockFinalizerContext implements System.FinalizerContext {
		private ParentJobResult result;
		private Exception cause;

		private MockFinalizerContext(ParentJobResult result, Exception cause) {
			this.result = result;
			this.cause = cause;
		}

		public Id getAsyncApexJobId() {
			return null;
		}

		public String getRequestId() {
			return 'TEST-REQUEST';
		}

		public ParentJobResult getResult() {
			return result;
		}

		public Exception getException() {
			return cause;
		}
	}

	/**
	 * @description: Crea pagos inbound minimos para las pruebas de sellado de etapa.
	 * @param quantity: Cantidad de pagos a crear.
	 * @return Pagos insertados.
	 */
	private static List<InboundInsurancePayment__c> createInbounds(
		Integer quantity
	) {
		List<InboundInsurancePayment__c> payments = new List<InboundInsurancePayment__c>();
		for (Integer i = 0; i < quantity; i++) {
			payments.add(
				new InboundInsurancePayment__c(
					externalPaymentId__c = 'CLT_' + i,
					inboundStatus__c = 'Normalizado',
					sourceAmount__c = 100 + i
				)
			);
		}
		insert payments;
		return payments;
	}

	/**
	 * @description: La rotura de cadena queda registrada como error, indicando que eslabon
	 *               no llego a ejecutarse y sobre que registros, para poder reintentarlo.
	 */
	@isTest
	static void chainBreakRecordsPendingWork() {
		List<InboundInsurancePayment__c> payments = createInbounds(2);
		Set<Id> pendingIds = new Map<Id, InboundInsurancePayment__c>(payments)
			.keySet();

		Test.startTest();
		CobranzaLog.chainBreak(
			CobranzaLog.STAGE_RECIBO,
			new SampleAsyncException('No se pudo encolar'),
			'PaymentInstallmentMatchQueueable',
			pendingIds
		);
		AppLogger.flush();
		Test.stopTest();

		AppLog__c log = [
			SELECT severity__c, stage__c, eventCode__c, stackTrace__c, recordId__c
			FROM AppLog__c
			LIMIT 1
		];
		System.assertEquals(
			'Error',
			log.severity__c,
			'Debe registrarse como Error.'
		);
		System.assertEquals(
			CobranzaLog.STAGE_RECIBO,
			log.stage__c,
			'Debe indicar la etapa donde quedaron detenidos los pagos.'
		);
		System.assertEquals(
			CobranzaLog.EVENT_CHAIN_ENQUEUE_FAILED,
			log.eventCode__c,
			'Debe usar el codigo de rotura de cadena.'
		);
		System.assert(
			log.stackTrace__c.contains('PaymentInstallmentMatchQueueable'),
			'Debe indicar que eslabon no llego a ejecutarse.'
		);
		System.assert(
			log.stackTrace__c.contains(String.valueOf(payments[0].Id)),
			'Debe listar los registros que quedaron sin continuar.'
		);
		System.assertNotEquals(
			null,
			log.recordId__c,
			'Debe apuntar a un registro afectado.'
		);
	}

	/**
	 * @description: El sellado de la etapa alcanzada escribe todos los pagos con una unica
	 *               operacion de base de datos, independientemente de la cantidad.
	 */
	@isTest
	static void markStageStampsAllPaymentsWithASingleDml() {
		List<InboundInsurancePayment__c> payments = createInbounds(20);
		Set<Id> ids = new Map<Id, InboundInsurancePayment__c>(payments).keySet();

		Test.startTest();
		Integer dmlBefore = Limits.getDmlStatements();
		CobranzaLog.markStage(ids, CobranzaLog.STAGE_CONCILIACION);
		Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
		Test.stopTest();

		System.assertEquals(
			1,
			dmlUsed,
			'El sellado debe consumir una unica operacion para todo el lote.'
		);
		System.assertEquals(
			20,
			[
				SELECT COUNT()
				FROM InboundInsurancePayment__c
				WHERE pipelineStage__c = :CobranzaLog.STAGE_CONCILIACION
			],
			'Todos los pagos deben quedar sellados con la etapa alcanzada.'
		);
	}

	/**
	 * @description: Sellar sin pagos no consume operaciones ni falla.
	 */
	@isTest
	static void markStageWithoutPaymentsDoesNothing() {
		Test.startTest();
		Integer dmlBefore = Limits.getDmlStatements();
		CobranzaLog.markStage(null, CobranzaLog.STAGE_RECIBO);
		CobranzaLog.markStage(new Set<Id>(), CobranzaLog.STAGE_RECIBO);
		Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
		Test.stopTest();

		System.assertEquals(
			0,
			dmlUsed,
			'Sin pagos que sellar no debe consumirse ninguna operacion.'
		);
	}

	/**
	 * @description: Un job interrumpido por una excepcion no controlada deja registro de
	 *               error con la etapa, la causa y los registros que estaba procesando.
	 */
	@isTest
	static void finalizerRecordsAbortedJob() {
		List<InboundInsurancePayment__c> payments = createInbounds(2);
		Set<Id> ids = new Map<Id, InboundInsurancePayment__c>(payments).keySet();

		Test.startTest();
		CobranzaLog.finalizerFor(CobranzaLog.STAGE_CUOTA_CANDIDATA, ids)
			.execute(
				new MockFinalizerContext(
					ParentJobResult.UNHANDLED_EXCEPTION,
					new SampleAsyncException('Limite excedido')
				)
			);
		Test.stopTest();

		AppLog__c log = [
			SELECT severity__c, stage__c, eventCode__c, message__c, stackTrace__c
			FROM AppLog__c
			LIMIT 1
		];
		System.assertEquals(
			'Error',
			log.severity__c,
			'Debe registrarse como Error.'
		);
		System.assertEquals(
			CobranzaLog.STAGE_CUOTA_CANDIDATA,
			log.stage__c,
			'Debe indicar la etapa donde se interrumpio el proceso.'
		);
		System.assertEquals(
			'JOB_ABORTED',
			log.eventCode__c,
			'Debe usar el codigo de interrupcion del proceso.'
		);
		System.assertEquals(
			'Limite excedido',
			log.message__c,
			'Debe guardar la causa informada por la plataforma.'
		);
		System.assert(
			log.stackTrace__c.contains(String.valueOf(payments[0].Id)),
			'Debe listar los registros en proceso al interrumpirse.'
		);
	}

	/**
	 * @description: Un job que termina correctamente no genera ningun registro: el camino
	 *               exitoso ya se refleja en los campos de estado de cada objeto.
	 */
	@isTest
	static void finalizerIgnoresSuccessfulJob() {
		Test.startTest();
		CobranzaLog.finalizerFor(CobranzaLog.STAGE_RECIBO, new Set<Id>())
			.execute(new MockFinalizerContext(ParentJobResult.SUCCESS, null));
		CobranzaLog.finalizerFor(CobranzaLog.STAGE_RECIBO, new Set<Id>())
			.execute(null);
		Test.stopTest();

		System.assertEquals(
			0,
			[SELECT COUNT() FROM AppLog__c],
			'Un proceso que termina bien no debe generar registros.'
		);
	}

	/**
	 * @description: Si la plataforma no informa la causa de la interrupcion, igual queda
	 *               constancia del corte, como advertencia.
	 */
	@isTest
	static void finalizerRecordsAbortedJobWithoutCause() {
		Test.startTest();
		CobranzaLog.finalizerFor(CobranzaLog.STAGE_SCORE, new Set<Id>())
			.execute(
				new MockFinalizerContext(ParentJobResult.UNHANDLED_EXCEPTION, null)
			);
		Test.stopTest();

		AppLog__c log = [
			SELECT severity__c, eventCode__c, stackTrace__c
			FROM AppLog__c
			LIMIT 1
		];
		System.assertEquals(
			'Advertencia',
			log.severity__c,
			'Sin causa informada se registra como advertencia.'
		);
		System.assertEquals(
			'JOB_ABORTED',
			log.eventCode__c,
			'Debe usar el codigo de interrupcion del proceso.'
		);
		System.assert(
			log.stackTrace__c.contains('Sin registros asociados'),
			'Debe indicar que no habia registros asociados.'
		);
	}

	/**
	 * @description: Los atajos del modulo fijan el dominio Cobranza sin que cada punto de
	 *               llamada tenga que repetirlo.
	 */
	@isTest
	static void moduleShortcutsSetCollectionsDomain() {
		Test.startTest();
		CobranzaLog.warn(CobranzaLog.STAGE_OPORTUNIDAD, 'W', 'advertencia');
		CobranzaLog.info(CobranzaLog.STAGE_RECEPCION, 'I', 'informacion');
		CobranzaLog.error(CobranzaLog.STAGE_OPORTUNIDAD, 'E', 'error');
		AppLogger.flush();
		Test.stopTest();

		System.assertEquals(
			3,
			[SELECT COUNT() FROM AppLog__c WHERE domain__c = 'Cobranza'],
			'Los tres registros deben quedar en el dominio Cobranza.'
		);
	}
}
