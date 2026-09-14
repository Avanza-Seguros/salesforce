/**
 *   @name: InboundInsurancePaymentRestResource
 *   @version: 1.0
 *   @creation date: 24/04/2026
 *   @author: Javier Torres - Volestra
 *   @description: Expone el endpoint REST oficial para recibir pagos inbound
 *                 enviados por MuleSoft hacia el modulo de cobranzas.
 */
@RestResource(urlMapping='/collections/v1/inbound-payments')
global with sharing class InboundInsurancePaymentRestResource {
	@TestVisible
	private static Boolean forceServiceException = false;

	// Tope del cuerpo que se copia al registro del error. El registro ya trunca, pero
	// cortar antes evita armar en memoria un texto enorme que luego se descarta.
	private static final Integer MAX_LOGGED_BODY = 30000;

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Atiende requests POST de pagos inbound y responde con un
	 *               contrato tecnico JSON estable para el integrador.
	 *               Los errores de cada pago los resuelve e informa el servicio uno a uno;
	 *               lo que llega al catch es un fallo que el servicio no esperaba. Para ese
	 *               caso se deshace todo lo que alcanzo a escribir, de modo que la peticion no
	 *               quede a medias, y el fallo se registra DESPUES de deshacer: registrado
	 *               antes, el rollback tambien lo borraria.
	 */
	@HttpPost
	global static void receive() {
		RestRequest request = RestContext.request;
		RestResponse response = RestContext.response;
		String requestBody = request == null ||
			request.requestBody == null
			? null
			: request.requestBody.toString();

		Savepoint beforeProcessing = Database.setSavepoint();
		try {
			if (Test.isRunningTest() && forceServiceException) {
				throw new CalloutException('Forced test exception');
			}
			InboundInsurancePaymentService.EndpointResult result = InboundInsurancePaymentService.receive(
				requestBody
			);
			writeResponse(response, result.statusCode, result.body);
		} catch (Exception e) {
			Database.rollback(beforeProcessing);
			CobranzaLog.error(
					CobranzaLog.STAGE_RECEPCION,
					CobranzaLog.EVENT_ENDPOINT_FAILED,
					e
				)
				.appendDetails(
					'Se deshizo todo lo que el envio habia escrito. Cuerpo recibido: ' +
					(requestBody == null ? '(vacio)' : requestBody.left(MAX_LOGGED_BODY))
				);
			AppLogger.flush();
			writeResponse(
				response,
				500,
				new InboundInsurancePaymentService.ResponseBody(
					false,
					'INTERNAL_ERROR',
					'Ocurrio un error inesperado al procesar el pago inbound.',
					null,
					null
				)
			);
		}
	}

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Escribe la respuesta HTTP en formato JSON y asegura el codigo
	 *               de estado y el content type esperado por MuleSoft.
	 * @param response: Respuesta REST a poblar.
	 * @param statusCode: Codigo HTTP a responder.
	 * @param body: Cuerpo serializable de la respuesta.
	 */
	private static void writeResponse(
		RestResponse response,
		Integer statusCode,
		Object body
	) {
		response.statusCode = statusCode;
		response.addHeader('Content-Type', 'application/json');
		response.responseBody = Blob.valueOf(JSON.serialize(body));
	}
}
