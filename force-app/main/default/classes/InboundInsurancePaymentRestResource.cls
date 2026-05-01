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

  /**
   * @creation date: 24/04/2026
   * @author: Javier Torres - Volestra
   * @description: Atiende requests POST de pagos inbound y responde con un
   *               contrato tecnico JSON estable para el integrador.
   */
  @HttpPost
  global static void receive() {
    RestRequest request = RestContext.request;
    RestResponse response = RestContext.response;

    try {
      if (Test.isRunningTest() && forceServiceException) {
        throw new CalloutException('Forced test exception');
      }
      InboundInsurancePaymentService.EndpointResult result = InboundInsurancePaymentService.receive(
        request == null ||
          request.requestBody == null
          ? null
          : request.requestBody.toString()
      );
      writeResponse(response, result.statusCode, result.body);
    } catch (Exception e) {
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
