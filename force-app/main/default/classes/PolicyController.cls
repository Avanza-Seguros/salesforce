/**
 *   @name: PolicyController
 *   @version: 1.0
 *   @creation date: 08/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Apoya al LWC policyCreator: localiza la InsurancePolicy generada por
 *                 el flow del org al pasar la oportunidad a Póliza. La póliza se ubica
 *                 por la cotización origen (SourceQuoteId) y, como respaldo, por las
 *                 cotizaciones de la oportunidad.
 */
public with sharing class PolicyController {

	/**
	 * @creation date: 08/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve el Id de la InsurancePolicy asociada a la cotización o a la
	 *               oportunidad indicadas. Primero busca por SourceQuoteId = quoteId; si no
	 *               la encuentra, busca por las cotizaciones de la oportunidad.
	 * @param quoteId: Id de la cotización aceptada (origen de la póliza). Puede ser null.
	 * @param opportunityId: Id de la oportunidad. Puede ser null.
	 * @return Id de la InsurancePolicy encontrada, o null si no existe.
	 */
	@AuraEnabled(cacheable=false)
	public static Id getPolicyIdByQuote(Id quoteId, Id opportunityId) {
		try {
			// 1) Por la cotización origen (SourceQuoteId).
			if (quoteId != null) {
				List<InsurancePolicy> ps = [
					SELECT Id FROM InsurancePolicy
					WHERE SourceQuoteId = :quoteId
					ORDER BY CreatedDate DESC
					LIMIT 1
				];
				if (!ps.isEmpty()) { return ps[0].Id; }
			}
			// 2) Respaldo: por cualquier cotización de la oportunidad.
			if (opportunityId != null) {
				Set<Id> quoteIds = new Set<Id>();
				for (Quote q : [SELECT Id FROM Quote WHERE OpportunityId = :opportunityId]) {
					quoteIds.add(q.Id);
				}
				if (!quoteIds.isEmpty()) {
					List<InsurancePolicy> ps = [
						SELECT Id FROM InsurancePolicy
						WHERE SourceQuoteId IN :quoteIds
						ORDER BY CreatedDate DESC
						LIMIT 1
					];
					if (!ps.isEmpty()) { return ps[0].Id; }
				}
			}
			return null;
		} catch (Exception e) {
			throw new AuraHandledException('Error al localizar la póliza: ' + e.getMessage());
		}
	}

	// API Name del Prompt Template y de su variable de entrada (Prompt Builder).
	private static final String PROMPT_TEMPLATE_API_NAME = 'Analizador_Poliza_Auto';
	private static final String PROMPT_INPUT_PARAM = 'Input:TextoPoliza';

	/**
	 * @creation date: 10/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Envía a Einstein (Prompt Template) el texto extraído de un PDF de póliza
	 *               y devuelve el JSON con los datos de la póliza para llenar el formulario.
	 *               El texto se extrae en el navegador (pdf.js); aquí solo se llama al prompt.
	 * @param textoPoliza: texto plano de la póliza (extraído del PDF en el LWC).
	 * @return cadena JSON con los datos de la póliza (limpia de fences de código), o '' si falla.
	 */
	@AuraEnabled(cacheable=false)
	public static String analizarPoliza(String textoPoliza) {
		if (String.isBlank(textoPoliza)) {
			throw new AuraHandledException('No se recibió texto de la póliza para analizar.');
		}
		if (Test.isRunningTest()) { return '{}'; }
		try {
			String texto = textoPoliza.length() > 100000
				? textoPoliza.substring(0, 100000)
				: textoPoliza;

			ConnectApi.WrappedValue wrapped = new ConnectApi.WrappedValue();
			wrapped.value = texto;
			Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
			inputParams.put(PROMPT_INPUT_PARAM, wrapped);

			ConnectApi.EinsteinPromptTemplateGenerationsInput genInput = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
			genInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
			genInput.additionalConfig.applicationName = 'PromptBuilderPreview';
			genInput.isPreview = false;
			genInput.inputParams = inputParams;

			ConnectApi.EinsteinPromptTemplateGenerationsRepresentation gen =
				ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(PROMPT_TEMPLATE_API_NAME, genInput);

			if (gen != null && gen.generations != null && !gen.generations.isEmpty() && String.isNotBlank(gen.generations[0].text)) {
				return cleanJson(gen.generations[0].text);
			}
			throw new AuraHandledException('La IA no devolvió información de la póliza.');
		} catch (AuraHandledException ahe) {
			// Se re-lanza tal cual para conservar el mensaje real (si no, queda "Script-thrown exception").
			throw ahe;
		} catch (Exception e) {
			throw new AuraHandledException('Error al analizar la póliza: ' + e.getMessage());
		}
	}

	// Quita fences de Markdown (```json ... ```) y recorta al primer '{' y último '}'.
	private static String cleanJson(String raw) {
		if (String.isBlank(raw)) { return '{}'; }
		String payload = raw.trim();
		if (payload.startsWith('```')) {
			payload = payload.replaceFirst('^```[a-zA-Z]*', '').trim();
			if (payload.endsWith('```')) {
				payload = payload.substring(0, payload.length() - 3).trim();
			}
		}
		Integer start = payload.indexOf('{');
		Integer last = payload.lastIndexOf('}');
		if (start < 0 || last < start) { return '{}'; }
		return payload.substring(start, last + 1);
	}
}