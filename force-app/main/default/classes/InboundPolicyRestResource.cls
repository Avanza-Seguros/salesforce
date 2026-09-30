/**
 *   @name: InboundPolicyRestResource
 *   @version: 1.0
 *   @creation date: 25/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Endpoint REST del canal de polizas (KAN-448): recibe las polizas que la
 *                 aseguradora sincroniza por MuleSoft. Mismo contrato tecnico que el canal de
 *                 pagos (/collections/v1/inbound-payments).
 */
@RestResource(urlMapping='/collections/v1/inbound-policies')
global with sharing class InboundPolicyRestResource {
	@TestVisible
	private static Boolean forceServiceException = false;

	// Tope del cuerpo que se copia al registro del error.
	private static final Integer MAX_LOGGED_BODY = 30000;

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Atiende el POST. Los problemas de cada fila los resuelve el servicio; lo
	 *               que llega al catch es un fallo inesperado: se deshace todo lo escrito y se
	 *               registra DESPUES de deshacer, porque registrado antes el rollback lo
	 *               borraria.
	 * @return:
	 * @exception:
	 * @throws:
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
			InboundPolicyService.EndpointResult result = InboundPolicyService.receive(
				requestBody
			);
			writeResponse(response, result.statusCode, result.body);
		} catch (Exception e) {
			Database.rollback(beforeProcessing);
			CobranzaLog.error(
					CobranzaLog.STAGE_RECEPCION_POLIZAS,
					CobranzaLog.EVENT_POLICY_ENDPOINT_FAILED,
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
				new InboundPolicyService.ResponseBody(
					false,
					'INTERNAL_ERROR',
					'Ocurrio un error inesperado al procesar las polizas.',
					null,
					0,
					0,
					0,
					0,
					new List<InboundPolicyService.ItemResult>()
				)
			);
		}
	}

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
