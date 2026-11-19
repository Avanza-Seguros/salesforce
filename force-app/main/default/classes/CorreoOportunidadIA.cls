/**
 *   @name: CorreoOportunidadIA
 *   @version: 1.0
 *   @creation date: 18/11/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Redacta con Prompt Builder el correo de la oportunidad que manda las cotizaciones (al cliente o al
 *                 agente). Arma los datos de la oportunidad, sus cotizaciones y los PDFs adjuntos, llama al prompt
 *                 (Correo_Cotizacion_Cliente / Correo_Cotizacion_Agente) y devuelve el asunto y el cuerpo HTML con el
 *                 formato de Avanza.
 */
public with sharing class CorreoOportunidadIA {

	/** Respuesta simulada de la IA en las pruebas (ConnectApi no corre en pruebas). */
	@TestVisible
	private static String respuestaPrueba;

	/** Asunto y cuerpo HTML del correo. */
	public class Correo {
		public String asunto;
		public String html;
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Redacta el correo con el prompt indicado.
	 * @param prompt: Nombre API del prompt (Correo_Cotizacion_Cliente o Correo_Cotizacion_Agente)
	 * @param oportunidadId: Oportunidad de las cotizaciones
	 * @param destinatarioId: Contacto o usuario que recibe el correo (para el saludo)
	 * @param adjuntos: Nombres de los PDFs que van adjuntos
	 * @return Asunto y cuerpo HTML
	 */
	public static Correo generar(String prompt, Id oportunidadId, Id destinatarioId, List<String> adjuntos) {
		ConnectApi.WrappedValue datos = new ConnectApi.WrappedValue();
		datos.value = datos(oportunidadId, destinatarioId, adjuntos);
		String texto;
		if (Test.isRunningTest()) {
			texto = respuestaPrueba;
		} else {
			ConnectApi.EinsteinPromptTemplateGenerationsInput entrada = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
			entrada.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
			entrada.additionalConfig.applicationName = 'PromptBuilderPreview';
			entrada.isPreview = false;
			entrada.inputParams = new Map<String, ConnectApi.WrappedValue>{ 'Input:Datos' => datos };
			ConnectApi.EinsteinPromptTemplateGenerationsRepresentation gen =
				ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(prompt, entrada);
			if (gen != null && gen.generations != null && !gen.generations.isEmpty()) {
				texto = gen.generations[0].text;
			}
		}
		return interpretar(texto);
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Datos que recibe el prompt (JSON): oportunidad, cliente, agente, destinatario, cotizaciones y PDFs.
	 * @param oportunidadId: Oportunidad
	 * @param destinatarioId: Contacto o usuario que recibe el correo
	 * @param adjuntos: Nombres de los PDFs adjuntos
	 * @return JSON con los datos
	 */
	@TestVisible
	private static String datos(Id oportunidadId, Id destinatarioId, List<String> adjuntos) {
		Opportunity o = [
			SELECT Name, toLabel(StageName), toLabel(Ramo__c), Tipo_Contratacion__c, CloseDate, Prima_Total__c, Prima_Neta__c,
				Account.Name, Producer__r.Name, Contacto__r.Name, Owner.Name
			FROM Opportunity WHERE Id = :oportunidadId LIMIT 1
		];
		List<Map<String, Object>> cotizaciones = new List<Map<String, Object>>();
		for (Quote q : [
			SELECT Name, Aseguradora__r.Name, PrimaAnual__c, SumaAsegurada__c, Notas_IA__c, ExpirationDate
			FROM Quote WHERE OpportunityId = :oportunidadId ORDER BY PrimaAnual__c ASC NULLS LAST LIMIT 20
		]) {
			cotizaciones.add(new Map<String, Object>{
				'aseguradora' => q.Aseguradora__r?.Name,
				'plan' => q.Name,
				'primaAnual' => q.PrimaAnual__c,
				'sumaAsegurada' => q.SumaAsegurada__c,
				'notas' => q.Notas_IA__c,
				'vigenteHasta' => q.ExpirationDate
			});
		}
		marcarRecomendada(cotizaciones);
		String[] nombres = nombre(destinatarioId);
		return JSON.serialize(new Map<String, Object>{
			'oportunidad' => o.Name,
			'etapa' => o.StageName,
			'ramo' => o.Ramo__c,
			'tipoContratacion' => o.Tipo_Contratacion__c == 'Colectiva' ? 'Empresarial' : o.Tipo_Contratacion__c,
			'primaTotal' => o.Prima_Total__c,
			'primaNeta' => o.Prima_Neta__c,
			'cliente' => o.Account?.Name,
			'contactoCliente' => o.Contacto__r?.Name,
			'agente' => o.Producer__r?.Name,
			'ejecutivo' => o.Owner?.Name,
			'destinatario' => nombres[0],
			'nombreDestinatario' => nombres[1],
			'cotizaciones' => cotizaciones,
			'pdfsAdjuntos' => adjuntos == null ? new List<String>() : adjuntos
		});
	}

	// Nombre completo y nombre de pila del contacto o usuario que recibe el correo.
	private static String[] nombre(Id destinatarioId) {
		String[] r = new String[]{ null, null };
		if (destinatarioId == null) { return r; }
		String tipo = destinatarioId.getSObjectType().getDescribe().getName();
		if (tipo == 'Contact') {
			for (Contact c : [SELECT Name, FirstName FROM Contact WHERE Id = :destinatarioId LIMIT 1]) {
				r = new String[]{ c.Name, c.FirstName };
			}
		} else if (tipo == 'User') {
			for (User u : [SELECT Name, FirstName FROM User WHERE Id = :destinatarioId LIMIT 1]) {
				r = new String[]{ u.Name, u.FirstName };
			}
		}
		// Saludo con la primera palabra del nombre (hay contactos con el nombre completo en FirstName), con mayúscula inicial.
		String base = String.isNotBlank(r[1]) ? r[1] : r[0];
		if (String.isNotBlank(base)) {
			String primera = base.trim().split('\\s+')[0].toLowerCase();
			r[1] = primera.left(1).toUpperCase() + primera.substring(1);
		}
		return r;
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Marca la cotización recomendada (la misma en el correo del cliente y en el del agente): la de menor
	 *               prima, salvo que otra dé más suma asegurada con una prima a lo más 10% mayor (entonces la de mayor
	 *               suma asegurada de esas). Pone "recomendada" y "motivoRecomendacion".
	 * @param cotizaciones: Cotizaciones ordenadas de menor a mayor prima
	 * @return void
	 */
	@TestVisible
	private static void marcarRecomendada(List<Map<String, Object>> cotizaciones) {
		Map<String, Object> menor = null;
		for (Map<String, Object> c : cotizaciones) {
			if (c.get('primaAnual') != null) { menor = c; break; }
		}
		if (menor == null) { return; }
		Decimal prima = (Decimal) menor.get('primaAnual');
		Decimal suma = menor.get('sumaAsegurada') == null ? 0 : (Decimal) menor.get('sumaAsegurada');
		Map<String, Object> elegida = menor;
		for (Map<String, Object> c : cotizaciones) {
			Decimal p = (Decimal) c.get('primaAnual');
			Decimal sa = (Decimal) c.get('sumaAsegurada');
			if (p != null && sa != null && sa > suma && p <= prima * 1.10) {
				elegida = c;
				suma = sa;
			}
		}
		elegida.put('recomendada', true);
		elegida.put('motivoRecomendacion', elegida == menor ? 'Es la opción con la prima más baja.'
			: 'Da mayor suma asegurada por una prima muy similar a la más baja.');
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Lee la respuesta de la IA ({"asunto": "...", "cuerpo_html": "..."}) y pone el cuerpo en el formato
	 *               de correo de Avanza.
	 * @param texto: Respuesta de la IA
	 * @return Asunto y cuerpo HTML
	 */
	@TestVisible
	private static Correo interpretar(String texto) {
		if (String.isBlank(texto)) { throw new CorreoIAException('La IA no devolvió el correo.'); }
		String limpio = texto.trim();
		Integer ini = limpio.indexOf('{');
		Integer fin = limpio.lastIndexOf('}');
		if (ini < 0 || fin <= ini) { throw new CorreoIAException('La IA no devolvió el correo en el formato esperado.'); }
		Map<String, Object> r = (Map<String, Object>) JSON.deserializeUntyped(limpio.substring(ini, fin + 1));
		String asunto = r.get('asunto') == null ? null : String.valueOf(r.get('asunto')).trim();
		String cuerpo = r.get('cuerpo_html') == null ? null : String.valueOf(r.get('cuerpo_html'));
		if (String.isBlank(asunto) || String.isBlank(cuerpo)) {
			throw new CorreoIAException('La IA no devolvió el asunto o el cuerpo del correo.');
		}
		Correo c = new Correo();
		c.asunto = asunto.left(200);
		c.html = '<html><body style="margin:0;padding:0;background:#f4f6f9;">'
			+ '<table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f6f9;"><tr><td align="center" style="padding:24px 12px;">'
			+ '<table width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#ffffff;border-radius:6px;">'
			+ '<tr><td style="background:#2980b9;color:#ffffff;padding:18px 28px;font-family:Arial,Helvetica,sans-serif;'
			+ 'font-size:20px;font-weight:bold;border-radius:6px 6px 0 0;">Avanza Seguro</td></tr>'
			+ '<tr><td style="padding:24px 28px;font-family:Arial,Helvetica,sans-serif;font-size:15px;line-height:1.5;color:#333333;">'
			+ cuerpo
			+ '</td></tr></table></td></tr></table></body></html>';
		return c;
	}

	public class CorreoIAException extends Exception {}
}
