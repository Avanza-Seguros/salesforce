/**
 *   @name: PdfProcessor
 *   @version: 1.0
 *   @creation date: 02/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Cliente HTTP que envía un PDF codificado en Base64 a un servicio externo de procesamiento (IDP) mediante callout REST, y estructura la respuesta (éxito, datos extraídos, mensajes de error) en un wrapper para su consumo.
 */
public class PdfProcessor {

	// Endpoint del servicio
	private static final String ENDPOINT = 'http://137.184.132.216:5000/api/salesforce/pdf/process';

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Envía un PDF (Base64) al servicio de procesamiento vía callout HTTP POST, construyendo el cuerpo JSON, ejecutando la solicitud y delegando el manejo de la respuesta. Ante excepción devuelve una respuesta de error estructurada.
	 * @param pdfBase64: PDF codificado en Base64.
	 * @param fileName: Nombre del archivo PDF a procesar.
	 * @return PdfProcessorResponse con el estado, datos y mensaje del procesamiento.
	 */
	public static PdfProcessorResponse processPDF(String pdfBase64, String fileName) {
		try {
			// Construir el cuerpo de la solicitud
			Map<String, Object> requestBody = new Map<String, Object>();
			requestBody.put('file_base64', pdfBase64);
			requestBody.put('file_name', fileName);

			// Convertir a JSON
			String requestBodyJson = JSON.serialize(requestBody);

			// Configurar la solicitud HTTP
			HttpRequest req = new HttpRequest();
			req.setEndpoint(ENDPOINT);
			req.setMethod('POST');
			req.setHeader('Content-Type', 'application/json');
			req.setHeader('Accept', 'application/json');

			// Establecer el cuerpo
			req.setBody(requestBodyJson);

			// Enviar la solicitud
			Http http = new Http();
			HttpResponse res = http.send(req);

			// Procesar la respuesta
			return handleResponse(res);

		} catch (Exception e) {
			System.debug('Error en IDPClient.processPDF: ' + e.getMessage() + ' - ' + e.getStackTraceString());

			// Crear una respuesta de error
			PdfProcessorResponse errorResponse = new PdfProcessorResponse();
			errorResponse.status = 'false';
			errorResponse.message = 'Error al procesar el PDF: ' + e.getMessage();

			return errorResponse;
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Maneja la respuesta HTTP del servicio IDP: si es 200 parsea el cuerpo y extrae datos comunes; en otro caso construye un mensaje de error a partir del cuerpo o del estado HTTP.
	 * @param res: HttpResponse devuelta por el servicio.
	 * @return PdfProcessorResponse estructurada con el resultado del procesamiento.
	 */
	private static PdfProcessorResponse handleResponse(HttpResponse res) {
		PdfProcessorResponse response = new PdfProcessorResponse();
		try {
			if (res.getStatusCode() == 200) {
				// Parsear la respuesta exitosa
				Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

				response.status = 'true';
				response.data = result;
				response.message = res.getBody();

				// Extraer datos comunes si existen
				if (result.containsKey('extracted_data')) {
					response.data = (Map<String, Object>) result.get('extracted_data');
				}
				if (result.containsKey('metadata')) {
					response.data = (Map<String, Object>) result.get('metadata');
				}

			} else {
				// Manejar errores
				response.status = 'false';
				response.message = res.getBody();

				try {
					Map<String, Object> errorData = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
					response.message = (String) errorData.get('error') != null ?
						(String) errorData.get('error') : res.getStatus();
				} catch (Exception e) {
					response.message = res.getStatus() + ' - ' + res.getBody();
				}
			}

		} catch (Exception e) {
			response.status = 'false';
			response.message = 'Error al procesar la respuesta: ' + e.getMessage();
			response.warnings = res.getBody();
		}

		return response;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Clase wrapper serializable para la respuesta del servicio IDP, con estado, datos extraídos, advertencias y mensaje.
	 */
	public class PdfProcessorResponse {
		@AuraEnabled public Integer totalRecords { get; set; }
		@AuraEnabled public String status { get; set; }
		@AuraEnabled public Map<String, Object> data { get; set; }
		@AuraEnabled public String warnings { get; set; }
		@AuraEnabled public String message { get; set; }

		/**
		 * @creation date: 02/07/2026
		 * @author: Sergio Uribe Toledo - Volestra
		 * @description: Constructor por defecto que inicializa los campos del wrapper con valores neutros.
		 * @return void
		 */
		public PdfProcessorResponse() {
			this.warnings = '';
			this.message = '';
			this.data = new Map<String, Object>();
			this.totalRecords = 0;
			this.status = 'SUCCEEDED';
		}
	}
}
