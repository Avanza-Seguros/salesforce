/**
 *   @name: PdfOpportunityCreatorController
 *   @version: 1.0
 *   @creation date: 02/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Orquesta la creacion de una Opportunity a partir de varios PDFs de
 *   cotizaciones. El proceso se divide en DOS llamadas (dos transacciones) a proposito:
 *   1) uploadAndCreateDraft: solo DML, crea la Opportunity borrador y sube los PDFs.
 *   2) compareAndCreateQuotes: compara las cotizaciones (Einstein si esta disponible; si no,
 *   usa el ejemplo interno como respaldo), crea un Quote hijo por cotizacion con todos los
 *   datos de cobertura, genera un PDF comparativo y lo liga a la Opp. Salesforce no permite
 *   hacer callouts despues de un DML sin commit dentro de la misma transaccion, por eso el
 *   borrador se crea y persiste en el paso 1 antes de comparar.
 *
 *   Cambios recientes: el paso 2 devuelve todos los campos de cobertura al componente,
 *   detecta oportunidades duplicadas y reutiliza la existente, y el comparativo llama a un
 *   Prompt Template de Einstein soportando N aseguradoras; si Einstein falla o no esta
 *   configurado, cae al ejemplo interno para no romper el flujo.
 */
public with sharing class PdfOpportunityCreatorController {
	private static final Integer MIN_PREFIX_LENGTH = 3;

	// API Name del Prompt Template creado en Prompt Builder (ajústalo al de tu org).
	// El template debe recibir un input de texto con las cotizaciones y devolver el JSON
	// con el mismo formato del ejemplo de abajo.
	private static final String PROMPT_TEMPLATE_API_NAME = 'Comparador_Cotizaciones_Auto';
	// API Name del input de texto definido dentro del Prompt Template (ej. "Input:Cotizaciones").
	private static final String PROMPT_INPUT_PARAM = 'Input:Cotizaciones';

	// Inyectable en tests para evitar la página Visualforce real.
	@TestVisible
	private static IPdfRenderer pdfRenderer = new VisualforcePdfRenderer();

	// JSON de respaldo: se usa SOLO si Einstein no está disponible o falla, y en tests.
	// Los nombres de archivo (PLACEHOLDER_*) se sustituyen en runtime con los títulos reales.
	private static final String MOCK_COMPARISON_JSON =
	'{"ramo":"GMM","cliente":{"nombre":"MONICA NATALIA SAUCEDO MENDEZ","rfc":"","email":"","telefono":"","cp":"","direccion":""},"detalle":{"numAsegurados":1,"tipoEstructura":"Familiar","estado":"","redHospitalaria":"","maternidad":true,"asegurados":[{"nombre":"MONICA NATALIA SAUCEDO MENDEZ","edad":0,"parentesco":"Titular"}]},"aseguradoras":[{"nombre":"METLIFE MÉXICO","plan":"MédicaLife Familiar Básico","no_cotizacion":"73036-1782413280679","archivo_origen":"SGMM METLIFE BASICO (DED 60) $36,027.64 MONICA NATALIA SAUCEDO MENDEZ.pdf","prima_anual":36027.64,"moneda":"MXN","vigencia_inicio":"","vigencia_fin":"","notas":"Suma Asegurada en UMAM. Deducibles 60,000/70,000/80,000. Coaseguro 10% tope $88,000.","coberturas":[{"nombre":"Suma Asegurada","suma_asegurada":26000,"deducible":"","coaseguro":""},{"nombre":"Deducible","suma_asegurada":"Incluida","deducible":"60,000 / 70,000 / 80,000","coaseguro":""},{"nombre":"Coaseguro","suma_asegurada":"Incluida","deducible":"","coaseguro":"10% (tope $88,000)"},{"nombre":"Parto normal y cesárea","suma_asegurada":"Incluida","deducible":"","coaseguro":""},{"nombre":"MetDental","suma_asegurada":"Incluida","deducible":"","coaseguro":""},{"nombre":"Asistencia Integral","suma_asegurada":"Incluida","deducible":"","coaseguro":""},{"nombre":"Emergencia en el Extranjero","suma_asegurada":"Incluida","deducible":"","coaseguro":""}]},{"nombre":"GRUPO NACIONAL PROVINCIAL","plan":"Línea Azul Flexible Ámbar","no_cotizacion":"8990418","archivo_origen":"SGMM GNP AMBAR $31,143.11 MONICA NATALIA SAUCEDO MENDEZ.pdf","prima_anual":31143.11,"moneda":"MXN","vigencia_inicio":"","vigencia_fin":"2027-06-25","notas":"Suma asegurada 121,353,000. Deducible $69,000. Coaseguro 10% tope $100,000.","coberturas":[{"nombre":"Suma Asegurada","suma_asegurada":121353000,"deducible":"","coaseguro":""},{"nombre":"Deducible","suma_asegurada":"Incluida","deducible":"69,000","coaseguro":""},{"nombre":"Coaseguro","suma_asegurada":"Incluida","deducible":"","coaseguro":"10% (tope $100,000)"},{"nombre":"Emergencia Médica en el Extranjero","suma_asegurada":"Incluida","deducible":"","coaseguro":""},{"nombre":"Cero Deducible por Accidente","suma_asegurada":"Incluida","deducible":"","coaseguro":""}]},{"nombre":"MAPFRE MÉXICO","plan":"Protección Médica Alta - Optima","no_cotizacion":"2880013545622","archivo_origen":"SGMM MAPFRE OPTIMA $19,186.01 MONICA NATALIA SAUCEDO MENDEZ.pdf","prima_anual":19186.01,"moneda":"MXN","vigencia_inicio":"","vigencia_fin":"","notas":"Suma asegurada $130,000,000. Deducible $60,000. Coaseguro 10% tope $60,000.","coberturas":[{"nombre":"Suma Asegurada","suma_asegurada":130000000,"deducible":"","coaseguro":""},{"nombre":"Deducible","suma_asegurada":"Incluida","deducible":"60,000","coaseguro":""},{"nombre":"Coaseguro","suma_asegurada":"Incluida","deducible":"","coaseguro":"10% (tope $60,000)"},{"nombre":"Gastos Hospitalarios","suma_asegurada":"Incluida","deducible":"","coaseguro":""},{"nombre":"Honorarios Médicos","suma_asegurada":"Incluida","deducible":"","coaseguro":""},{"nombre":"Asistencia en Viaje","suma_asegurada":"Incluida","deducible":"","coaseguro":""}]}],"recomendacion":{"ganadoras":[{"nombre":"MAPFRE MÉXICO","etiqueta":"Mejor prima","porque":"Prima anual más baja.","a_cambio":"Tope de coaseguro menor ($60,000)."},{"nombre":"GRUPO NACIONAL PROVINCIAL","etiqueta":"Mejor equilibrio","porque":"Suma asegurada alta y tope de coaseguro mayor ($100,000).","a_cambio":"Prima superior a la más barata."}],"guia_frecuencia":[{"riesgo":"Hospitalización por enfermedad","frecuencia":"Frecuente","gana":"MAPFRE MÉXICO","detalle":"Suma asegurada alta y coberturas hospitalarias claras."},{"riesgo":"Parto y maternidad","frecuencia":"Moderado","gana":"METLIFE MÉXICO","detalle":"Menciona parto normal y cesárea y plan familiar."},{"riesgo":"Emergencia en el extranjero","frecuencia":"Bajo","gana":"GRUPO NACIONAL PROVINCIAL","detalle":"Incluye emergencia en el extranjero y cero deducible por accidente."}],"en_pocas_palabras":"MAPFRE es la más económica; GNP mejor equilibrio; MetLife destaca en maternidad y dental."},"validacion":{"mismo_cliente":true,"mismo_vehiculo":true,"alerta":""},"glosario":[{"termino":"Deducible","definicion":"Monto fijo que el asegurado paga en cada siniestro antes de que la aseguradora cubra el resto."},{"termino":"Coaseguro","definicion":"Porcentaje que el asegurado paga sobre los gastos cubiertos después del deducible; puede tener tope."},{"termino":"Suma Asegurada","definicion":"Límite máximo que la aseguradora pagará. Puede expresarse en UMAM o en moneda."}],"comparativo_html":"<!DOCTYPE html><html lang=\\"es\\"><head><meta charset=\\"utf-8\\"><title>Comparativo GMM - MONICA NATALIA SAUCEDO MENDEZ</title><style>body{font-family:Arial,Helvetica,sans-serif;background:#f6f6f6;color:#333;margin:0;padding:20px}.container{max-width:1100px;margin:0 auto;background:#fff;padding:20px;border:1px solid #e6e6e6}h1{font-size:20px;margin:0 0 10px}.table{width:100%;border-collapse:collapse;margin-top:20px}.table th,.table td{border:1px solid #ddd;padding:10px;text-align:left;vertical-align:top}.table th{background:#fafafa}.badge{display:inline-block;background:#ffefdd;color:#b85b00;padding:4px 8px;border-radius:4px;font-weight:700;margin-left:8px}.highlight{background:rgba(255,226,181,0.5);border:1px solid #ffd0a8}.sub{display:block;font-size:12px;color:#666}</style></head><body><div class=\\"container\\"><h1>Comparativo de Seguro GMM - MONICA NATALIA SAUCEDO MENDEZ</h1><table class=\\"table\\"><thead><tr><th>Concepto</th><th class=\\"highlight\\">MAPFRE MÉXICO <span class=\\"badge\\">Mejor precio</span></th><th>GNP <span class=\\"badge\\">Mejor equilibrio</span></th><th>METLIFE MÉXICO</th></tr></thead><tbody><tr><td>Precio Anual</td><td>$19,186 <span class=\\"sub\\">el más barato</span></td><td>$31,143</td><td>$36,028</td></tr><tr><td>Suma Asegurada</td><td>$130,000,000</td><td>$121,353,000</td><td>26,000 UMAM</td></tr><tr><td>Deducible</td><td>$60,000</td><td>$69,000</td><td>60,000/70,000/80,000</td></tr><tr><td>Coaseguro</td><td>10% (tope $60,000)</td><td>10% (tope $100,000)</td><td>10% (tope $88,000)</td></tr><tr><td>Parto y Maternidad</td><td>—</td><td>—</td><td>Incluida</td></tr><tr><td>Cero Deducible por Accidente</td><td>—</td><td>Incluida</td><td>—</td></tr></tbody></table></div></body></html>","aviso":"Revisar condiciones y vigencias antes de contratar."}';

	// ============================================================
	// Paso 1: crear borrador + subir PDFs (solo DML, sin callouts)
	// ============================================================
	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valida los archivos recibidos, crea una Opportunity borrador con nombre
	 * basado en el prefijo comun de los archivos, sube los PDFs como ContentVersion y los liga
	 * a la Opportunity mediante ContentDocumentLink. Solo ejecuta DML (sin callouts).
	 * @param fileNames: lista de nombres de los archivos PDF a subir.
	 * @param base64DataList: lista de contenidos de los archivos codificados en base64, en el mismo orden que fileNames.
	 * @return mapa con el Id de la Opportunity creada ('opportunityId') y la lista de Ids de los ContentDocument ('contentDocumentIds').
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> uploadAndCreateDraft(
		List<String> fileNames,
		List<String> base64DataList
	) {
		if (
			fileNames == null ||
			base64DataList == null ||
			fileNames.size() != base64DataList.size()
		) {
			throw new AuraHandledException(
				'Los archivos llegaron incompletos al servidor.'
			);
		}
		if (fileNames.size() < 2) {
			throw new AuraHandledException(
				'Sube al menos 2 PDFs para crear la oportunidad.'
			);
		}
		for (Integer i = 0; i < fileNames.size(); i++) {
			if (
				String.isBlank(fileNames[i]) || String.isBlank(base64DataList[i])
			) {
				throw new AuraHandledException(
					'Uno de los archivos está vacío o sin nombre.'
				);
			}
		}
		String sharedPrefix = sharedFilenamePrefix(fileNames);
		if (String.isBlank(sharedPrefix)) {
			throw new AuraHandledException(
				'Los nombres de los PDFs no comparten un prefijo común — renómbralos para que tengan la misma base (mín. ' +
					MIN_PREFIX_LENGTH +
					' caracteres).'
			);
		}

		try {
			Opportunity draft = new Opportunity(
				Name = 'Análisis IA en proceso — ' + sharedPrefix,
				StageName = defaultStageName(),
				CloseDate = Date.today().addMonths(1)
			);
			insert draft;

			List<ContentVersion> versions = new List<ContentVersion>();
			for (Integer i = 0; i < fileNames.size(); i++) {
				versions.add(
					new ContentVersion(
						Title = fileNames[i],
						PathOnClient = fileNames[i],
						VersionData = EncodingUtil.base64Decode(base64DataList[i]),
						Origin = 'H'
					)
				);
			}
			insert versions;

			Set<Id> versionIds = new Set<Id>();
			for (ContentVersion v : versions) {
				versionIds.add(v.Id);
			}
			Map<Id, Id> versionToDoc = new Map<Id, Id>();
			for (ContentVersion v : [
				SELECT Id, ContentDocumentId
				FROM ContentVersion
				WHERE Id IN :versionIds
			]) {
				versionToDoc.put(v.Id, v.ContentDocumentId);
			}

			List<ContentDocumentLink> links = new List<ContentDocumentLink>();
			List<Id> documentIds = new List<Id>();
			for (ContentVersion v : versions) {
				Id docId = versionToDoc.get(v.Id);
				documentIds.add(docId);
				links.add(
					new ContentDocumentLink(
						ContentDocumentId = docId,
						LinkedEntityId = draft.Id,
						ShareType = 'V',
						Visibility = 'AllUsers'
					)
				);
			}
			insert links;

			return new Map<String, Object>{
				'opportunityId' => draft.Id,
				'contentDocumentIds' => documentIds
			};
		} catch (Exception e) {
			throw new AuraHandledException(
				'No se pudo preparar el análisis: ' + e.getMessage()
			);
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Indica si el org esta en modo prueba (usar mock) leyendo el custom setting
	 * Config_IA__c y su campo Usar_Mock__c. Devuelve false ante cualquier error.
	 * @return true si Config_IA__c.Usar_Mock__c es true; false en otro caso.
	 */
	private static Boolean useMockTesting() {
		try {
			Config_IA__c cfg = Config_IA__c.getInstance();
			return cfg != null && cfg.Usar_Mock__c == true;
		} catch (Exception e) {
			return false;
		}
	}

	@TestVisible
	private static Boolean lastUsedMock = false;

	// ============================================================
	// Integración con Einstein (Prompt Builder)
	// ============================================================
	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Pide a Einstein (Prompt Template) el JSON del comparativo a partir del texto
	 * de los PDFs. Si no hay texto, si corre en test, o si Einstein falla o no esta configurado,
	 * devuelve el ejemplo interno (MOCK_COMPARISON_JSON) para no romper el flujo. Registra el
	 * origen usado en la variable lastUsedMock.
	 * @param fileNames: lista de nombres de archivo (para etiquetar cada bloque de texto).
	 * @param pdfTexts: lista de textos extraidos de los PDFs (en el mismo orden que fileNames).
	 * @return cadena JSON del comparativo (de Einstein o el mock de respaldo).
	 */
	@TestVisible
	private static String requestComparisonJson(List<String> fileNames, List<String> pdfTexts) {
		lastUsedMock = true;
		if (useMockTesting()) {
			System.debug('IA::: modo prueba (Usar_Mock) -> MOCK, sin llamar a Einstein');
			return MOCK_COMPARISON_JSON;
		}
		if (Test.isRunningTest()) { return MOCK_COMPARISON_JSON; }

		Integer total = pdfTexts == null ? 0 : pdfTexts.size();
		Integer conTexto = 0;
		if (pdfTexts != null) {
			for (String t : pdfTexts) { if (String.isNotBlank(t)) conTexto++; }
		}
		System.debug('IA::: archivos=' + total + ' conTexto=' + conTexto);

		if (pdfTexts == null || pdfTexts.isEmpty() || conTexto == 0) {
			System.debug('IA::: SIN TEXTO -> usando MOCK');
			return MOCK_COMPARISON_JSON;
		}

		try {
			String docs = '';
			for (Integer i = 0; i < pdfTexts.size(); i++) {
				String fn = (fileNames != null && i < fileNames.size()) ? fileNames[i] : ('Cotización ' + (i + 1));
				String t = pdfTexts[i] == null ? '' : pdfTexts[i];
				docs += '\n\n===== ARCHIVO: ' + fn + ' =====\n' + t;
			}
			if (docs.length() > 100000) { docs = docs.substring(0, 100000); }

			ConnectApi.WrappedValue wrapped = new ConnectApi.WrappedValue();
			wrapped.value = docs;
			Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
			inputParams.put(PROMPT_INPUT_PARAM, wrapped);

			ConnectApi.EinsteinPromptTemplateGenerationsInput genInput = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
			genInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
			genInput.additionalConfig.applicationName = 'PromptBuilderPreview';
			genInput.isPreview = false;
			genInput.inputParams = inputParams;

			ConnectApi.EinsteinPromptTemplateGenerationsRepresentation gen =
				ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(PROMPT_TEMPLATE_API_NAME, genInput);

			if (gen != null && gen.generations != null && !gen.generations.isEmpty()
					&& String.isNotBlank(gen.generations[0].text)) {
				lastUsedMock = false;
				System.debug('IA::: Einstein respondió OK');
				return gen.generations[0].text;
			}
			System.debug('IA::: Einstein devolvió VACÍO -> MOCK');
		} catch (Exception e) {
			System.debug('IA::: EXCEPCION Einstein -> ' + e.getMessage());
		}
		return MOCK_COMPARISON_JSON;
	}

	// ============================================================
	// Helpers de comparación (testeables sin callouts)
	// ============================================================

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Limpia y parsea el JSON del comparativo. Quita fences de codigo Markdown
	 * (```), recorta al primer '{' y ultimo '}', y deserializa a un mapa. Devuelve mapa vacio si falla.
	 * @param raw: cadena de texto con el JSON crudo (posiblemente envuelto en fences).
	 * @return mapa deserializado del JSON, o mapa vacio si el texto es invalido.
	 */
	@TestVisible
	private static Map<String, Object> parseFullComparisonJson(String raw) {
		if (String.isBlank(raw)) {
			return new Map<String, Object>();
		}
		String payload = raw.trim();
		if (payload.startsWith('```')) {
			payload = payload.replaceFirst('^```[a-zA-Z]*', '').trim();
			if (payload.endsWith('```')) {
				payload = payload.substring(0, payload.length() - 3).trim();
			}
		}
		Integer start = payload.indexOf('{');
		Integer last = payload.lastIndexOf('}');
		if (start < 0 || last < start) {
			return new Map<String, Object>();
		}
		payload = payload.substring(start, last + 1);
		try {
			return (Map<String, Object>) JSON.deserializeUntyped(payload);
		} catch (Exception e) {
			return new Map<String, Object>();
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Busca una Opportunity existente con el mismo nombre (y cuenta si se provee),
	 * distinta del borrador actual (excludeId). Devuelve null si no hay duplicado.
	 * @param oppName: nombre de la Opportunity a buscar.
	 * @param accountId: Id de cuenta para acotar la busqueda (puede ser null).
	 * @param excludeId: Id de Opportunity a excluir de la busqueda (el borrador actual).
	 * @return la Opportunity duplicada mas antigua, o null si no existe.
	 */
	@TestVisible
	private static Opportunity findDuplicateOpportunity(
		String oppName,
		Id accountId,
		Id excludeId
	) {
		if (String.isBlank(oppName)) {
			return null;
		}
		List<Opportunity> matches;
		if (accountId != null) {
			matches = [
				SELECT Id, Name
				FROM Opportunity
				WHERE Name = :oppName AND AccountId = :accountId AND Id != :excludeId
				ORDER BY CreatedDate ASC
				LIMIT 1
			];
		} else {
			matches = [
				SELECT Id, Name
				FROM Opportunity
				WHERE Name = :oppName AND Id != :excludeId
				ORDER BY CreatedDate ASC
				LIMIT 1
			];
		}
		return matches.isEmpty() ? null : matches[0];
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Resuelve nombres de aseguradoras a Ids de Aseguradora__c. Si el objeto no
	 * existe en el org devuelve un mapa vacio. Consulta las existentes por Name y crea las
	 * faltantes (insert parcial), tolerando fallos de permisos o validation rules.
	 * @param aseguradorasRaw: lista de objetos (mapas) con al menos la clave 'nombre'.
	 * @return mapa nombre-de-aseguradora a Id de Aseguradora__c.
	 */
	@TestVisible
	private static Map<String, Id> resolveAseguradoraLookups(List<Object> aseguradorasRaw) {
		Map<String, Id> result = new Map<String, Id>();
		Schema.SObjectType aseguradoraType = Schema.getGlobalDescribe().get('Aseguradora__c');
		if (aseguradoraType == null) {
			return result;
		}
		Set<String> nombres = new Set<String>();
		for (Object a : aseguradorasRaw) {
			if (a instanceof Map<String, Object>) {
				String n = stringOf(((Map<String, Object>) a).get('nombre'));
				if (String.isNotBlank(n)) {
					nombres.add(n);
				}
			}
		}
		if (nombres.isEmpty()) {
			return result;
		}
		try {
			String soql = 'SELECT Id, Name FROM Aseguradora__c WHERE Name IN :nombres';
			List<SObject> existing = Database.query(soql);
			for (SObject so : existing) {
				result.put((String) so.get('Name'), (Id) so.get('Id'));
			}
			List<SObject> toInsert = new List<SObject>();
			for (String n : nombres) {
				if (!result.containsKey(n)) {
					SObject novo = aseguradoraType.newSObject();
					novo.put('Name', n);
					toInsert.add(novo);
				}
			}
			if (!toInsert.isEmpty()) {
				Database.SaveResult[] srs = Database.insert(toInsert, false);
				for (Integer i = 0; i < srs.size(); i++) {
					if (srs[i].isSuccess()) {
						result.put((String) toInsert[i].get('Name'), srs[i].getId());
					}
				}
			}
		} catch (Exception ignore) {
			// Sin permisos o con validation rules: dejamos el mapa con lo que pudimos.
		}
		return result;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Aplica valores por defecto a la Opportunity (Ramo__c y Prima_Total__c /
	 * Prima_anual__c) usando put() dentro de try para tolerar campos ausentes o picklists restringidos.
	 * @param opp: la Opportunity a la que se le aplican los valores por defecto.
	 * @return void
	 */
	@TestVisible
	private static void applyOpportunityDefaults(Opportunity opp) {
		// Los campos custom dependen del org; los aplicamos con put() para no romper
		// compilación si alguno cambia, y los envolvemos en try para tolerar picklists
		// restringidos con valores distintos.
		try {
			opp.put('Ramo__c', 'Automoviles');
		} catch (Exception ignore) {
		}
		try {
			opp.put('Prima_Total__c', 0);
		} catch (Exception ignore) {
			try {
				opp.put('Prima_anual__c', 0);
			} catch (Exception ignore2) {
			}
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma el texto de la Descripcion de la Opportunity concatenando la advertencia
	 * de cuenta, el aviso y la recomendacion en pocas palabras. Recorta a 32000 caracteres.
	 * @param aviso: aviso informativo a incluir.
	 * @param recomendacion: mapa de recomendacion (se lee 'en_pocas_palabras').
	 * @param accountWarning: advertencia si no se pudo crear/buscar la cuenta.
	 * @return texto de descripcion construido (maximo 32000 caracteres).
	 */
	@TestVisible
	private static String buildOpportunityDescription(
		String aviso,
		Map<String, Object> recomendacion,
		String accountWarning
	) {
		String s = '';
		if (String.isNotBlank(accountWarning)) {
			s += accountWarning + '\n\n';
		}
		if (String.isNotBlank(aviso)) {
			s += aviso + '\n\n';
		}
		if (recomendacion != null) {
			Object enPocas = recomendacion.get('en_pocas_palabras');
			if (enPocas != null && String.isNotBlank(String.valueOf(enPocas))) {
				s += 'Recomendación: ' + String.valueOf(enPocas);
			}
		}
		return s.left(32000);
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Renderiza el HTML del comparativo a PDF (via pdfRenderer), lo guarda como
	 * ContentVersion y lo liga a la Opportunity mediante ContentDocumentLink. Devuelve null si no hay HTML.
	 * @param html: contenido HTML del comparativo a renderizar.
	 * @param vehiculo: descripcion del vehiculo, usada para nombrar el archivo.
	 * @param opportunityId: Id de la Opportunity a la que se liga el PDF.
	 * @return Id del ContentDocument generado, o null si no habia HTML.
	 */
	@TestVisible
	private static Id renderAndLinkComparativo(
		String html,
		String vehiculo,
		Id opportunityId
	) {
		if (String.isBlank(html)) {
			return null;
		}
		String filename = 'Comparativo_' +
			(String.isBlank(vehiculo) ? 'cotizaciones' : vehiculo) +
			'.pdf';
		Blob pdfBlob = pdfRenderer.renderToPdf(html, filename);
		ContentVersion cv = new ContentVersion(
			Title = filename,
			PathOnClient = filename,
			VersionData = pdfBlob,
			Origin = 'H'
		);
		insert cv;
		ContentVersion stored = [
			SELECT Id, ContentDocumentId
			FROM ContentVersion
			WHERE Id = :cv.Id
			LIMIT 1
		];
		insert new ContentDocumentLink(
			ContentDocumentId = stored.ContentDocumentId,
			LinkedEntityId = opportunityId,
			ShareType = 'V',
			Visibility = 'AllUsers'
		);
		return stored.ContentDocumentId;
	}

	/**
	 * @description: Sube UN archivo (PDF) y lo liga a una Opportunity YA EXISTENTE.
	 *               Se llama uno por uno desde el LWC para no exceder el tamaño de request.
	 * @param opportunityId: Id de la oportunidad a la que se adjunta.
	 * @param fileName: nombre del archivo.
	 * @param base64Data: contenido del archivo en base64.
	 * @return Id del ContentDocument creado.
	 */
	@AuraEnabled
	public static Id guardarArchivoEnOportunidad(Id opportunityId, String fileName, String base64Data) {
		if (opportunityId == null || String.isBlank(fileName) || String.isBlank(base64Data)) {
			throw new AuraHandledException('Faltan datos para guardar el archivo.');
		}
		try {
			ContentVersion cv = new ContentVersion(
				Title = fileName,
				PathOnClient = fileName,
				VersionData = EncodingUtil.base64Decode(base64Data),
				Origin = 'H'
			);
			insert cv;
			ContentVersion stored = [
				SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1
			];
			insert new ContentDocumentLink(
				ContentDocumentId = stored.ContentDocumentId,
				LinkedEntityId = opportunityId,
				ShareType = 'V',
				Visibility = 'AllUsers'
			);
			return stored.ContentDocumentId;
		} catch (Exception e) {
			throw new AuraHandledException('No se pudo guardar el archivo "' + fileName + '": ' + e.getMessage());
		}
	}

	/**
	 * @description: Renderiza el HTML del comparativo a PDF y lo liga a la Opportunity.
	 *               Devuelve null si no hay HTML.
	 * @param opportunityId: Id de la oportunidad.
	 * @param comparativoHtml: HTML del comparativo.
	 * @param nombreArchivo: base para el nombre del PDF.
	 * @return Id del ContentDocument, o null si no había HTML.
	 */
	@AuraEnabled
	public static void actualizarComparativoOpp(Id opportunityId, String comparativoHtml) {
		if (opportunityId == null || String.isBlank(comparativoHtml)) { return; }
		try {
			Opportunity o = new Opportunity(Id = opportunityId);
			o.Descripcion__c = comparativoHtml.length() > 131072
				? comparativoHtml.substring(0, 131072)
				: comparativoHtml;
			update o;
		} catch (Exception e) {
			throw new AuraHandledException('No se pudo actualizar el comparativo: ' + e.getMessage());
		}
	}

	@AuraEnabled
	public static Id guardarComparativoPdf(Id opportunityId, String nombreArchivo) {
		if (opportunityId == null) { return null; }
		try {
			// El HTML se lee desde la Oportunidad (Descripcion__c), un registro ya COMMITTED,
			// para que la página VF lo reciba de forma confiable (los statics no sobreviven a
			// getContentAsPDF). No se hace DML antes de getContentAsPDF (evita "uncommitted work").
			String html;
			for (Opportunity o : [SELECT Descripcion__c FROM Opportunity WHERE Id = :opportunityId LIMIT 1]) {
				html = o.Descripcion__c;
			}
			if (String.isBlank(html)) { return null; }

			String filename = 'Comparativo_' +
				(String.isBlank(nombreArchivo) ? 'cotizaciones' : nombreArchivo) + '.pdf';

			Blob pdfBlob;
			if (Test.isRunningTest()) {
				pdfBlob = Blob.valueOf(html);
			} else {
				PageReference pr = Page.OpportunityComparisonPdf;
				pr.getParameters().put('oppId', opportunityId);
				pdfBlob = pr.getContentAsPDF();
			}

			ContentVersion cv = new ContentVersion(
				Title = filename,
				PathOnClient = filename,
				VersionData = pdfBlob,
				Origin = 'H'
			);
			insert cv;
			ContentVersion stored = [
				SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1
			];
			insert new ContentDocumentLink(
				ContentDocumentId = stored.ContentDocumentId,
				LinkedEntityId = opportunityId,
				ShareType = 'V',
				Visibility = 'AllUsers'
			);
			return stored.ContentDocumentId;
		} catch (Exception e) {
			throw new AuraHandledException('No se pudo generar el PDF del comparativo: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve el Id del Pricebook estandar. En contexto de test usa
	 * Test.getStandardPricebookId(); en runtime consulta el Pricebook2 con IsStandard = true.
	 * @return Id del Pricebook estandar, o null si no existe.
	 */
	@TestVisible
	private static Id getStandardPricebookId() {
		if (Test.isRunningTest()) {
			return Test.getStandardPricebookId();
		}
		List<Pricebook2> pbs = [
			SELECT Id
			FROM Pricebook2
			WHERE IsStandard = TRUE
			LIMIT 1
		];
		return pbs.isEmpty() ? null : pbs[0].Id;
	}

	// ============================================================
	// Utilidades de tipo
	// ============================================================
	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Convierte un Object a String recortado (trim), o null si el objeto es null.
	 * @param o: objeto a convertir.
	 * @return representacion String recortada, o null.
	 */
	private static String stringOf(Object o) {
		return o == null ? null : String.valueOf(o).trim();
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve el primer valor no vacio entre a, b y c (en ese orden); cadena vacia si todos son nulos.
	 * @param a: primer candidato.
	 * @param b: segundo candidato.
	 * @param c: tercer candidato (fallback).
	 * @return el primer valor no vacio, o cadena vacia.
	 */
	private static String coalesce(String a, String b, String c) {
		if (String.isNotBlank(a)) {
			return a;
		}
		if (String.isNotBlank(b)) {
			return b;
		}
		return c == null ? '' : c;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Agrega una linea (addition) a un texto existente (current), separando con salto de linea.
	 * @param current: texto actual.
	 * @param addition: texto a agregar.
	 * @return texto combinado.
	 */
	private static String appendNote(String current, String addition) {
		if (String.isBlank(addition)) {
			return current;
		}
		if (String.isBlank(current)) {
			return addition;
		}
		return current + '\n' + addition;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Convierte un Object a Decimal, manejando Decimal, Integer, Long, Double y String
	 * (limpiando caracteres no numericos). Devuelve null si no es convertible.
	 * @param o: objeto a convertir.
	 * @return valor Decimal, o null.
	 */
	private static Decimal asDecimal(Object o) {
		if (o == null) {
			return null;
		}
		if (o instanceof Decimal) {
			return (Decimal) o;
		}
		if (o instanceof Integer) {
			return (Decimal) ((Integer) o);
		}
		if (o instanceof Long) {
			return Decimal.valueOf((Long) o);
		}
		if (o instanceof Double) {
			return Decimal.valueOf(String.valueOf(o));
		}
		try {
			String s = String.valueOf(o).replaceAll('[^0-9.\\-]', '');
			return String.isBlank(s) ? null : Decimal.valueOf(s);
		} catch (Exception e) {
			return null;
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Convierte un Object a Boolean, aceptando Boolean directo o textos como 'true', '1', 'sí', 'si'.
	 * @param o: objeto a convertir.
	 * @return true/false segun el valor; false si es null.
	 */
	private static Boolean asBoolean(Object o) {
		if (o == null) {
			return false;
		}
		if (o instanceof Boolean) {
			return (Boolean) o;
		}
		String s = String.valueOf(o).toLowerCase().trim();
		return s == 'true' || s == '1' || s == 'sí' || s == 'si';
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Parsea una fecha ISO (yyyy-MM-dd). Devuelve null si esta en blanco o el formato es invalido.
	 * @param s: cadena de fecha en formato ISO.
	 * @return Date parseado, o null.
	 */
	private static Date parseDate(String s) {
		if (String.isBlank(s)) {
			return null;
		}
		try {
			// ISO yyyy-MM-dd
			return Date.valueOf(s);
		} catch (Exception e) {
			return null;
		}
	}

	// ============================================================
	// Helpers compartidos (también usados por uploadAndCreateDraft)
	// ============================================================

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve el prefijo comun (case-insensitive) de los nombres de archivo sin
	 * extension, recortando separadores finales (-, _, ., espacio). Si el prefijo resultante es
	 * menor a MIN_PREFIX_LENGTH, devuelve cadena vacia (no hay coincidencia util).
	 * @param fileNames: lista de nombres de archivo a comparar.
	 * @return prefijo comun util, o cadena vacia.
	 */
	@TestVisible
	private static String sharedFilenamePrefix(List<String> fileNames) {
		if (fileNames == null || fileNames.isEmpty()) {
			return '';
		}
		List<String> bases = new List<String>();
		for (String n : fileNames) {
			String base = n == null ? '' : n;
			Integer dot = base.lastIndexOf('.');
			if (dot > 0) {
				base = base.substring(0, dot);
			}
			bases.add(base.toLowerCase());
		}
		String prefix = bases[0];
		for (Integer i = 1; i < bases.size(); i++) {
			String other = bases[i];
			Integer maxLen = Math.min(prefix.length(), other.length());
			Integer j = 0;
			while (j < maxLen && prefix.charAt(j) == other.charAt(j)) {
				j++;
			}
			prefix = prefix.substring(0, j);
			if (prefix.length() == 0) {
				break;
			}
		}
		while (
			prefix.length() > 0 &&
			'._- '.indexOf(prefix.substring(prefix.length() - 1)) >= 0
		) {
			prefix = prefix.substring(0, prefix.length() - 1);
		}
		return prefix.length() >= MIN_PREFIX_LENGTH ? prefix : '';
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Normaliza un texto a minusculas, elimina acentos/dieresis, convierte ñ a n y colapsa espacios.
	 * @param s: cadena a normalizar.
	 * @return cadena normalizada (sin acentos, en minusculas), o cadena vacia si es null.
	 */
	@TestVisible
	private static String fold(String s) {
		if (s == null) {
			return '';
		}
		String out = s.toLowerCase();
		out = out.replaceAll('[áàäâã]', 'a');
		out = out.replaceAll('[éèëê]', 'e');
		out = out.replaceAll('[íìïî]', 'i');
		out = out.replaceAll('[óòöôõ]', 'o');
		out = out.replaceAll('[úùüû]', 'u');
		out = out.replaceAll('ñ', 'n');
		out = out.replaceAll('\\s+', ' ').trim();
		return out;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Busca una cuenta por nombre; si no existe, la crea. Si el org tiene Person
	 * Accounts habilitados y un RecordType disponible con IsPersonType=true, prefiere crear un
	 * Person Account real (FirstName + LastName + RecordTypeId) para evitar validation rules de
	 * Business Accounts.
	 * @param name: nombre de la cuenta/cliente a buscar o crear.
	 * @return el Account existente o el recien creado.
	 */
	@TestVisible
	private static Account findOrCreateAccount(String name) {
		String clean = name.trim();
		List<Account> existing = [
			SELECT Id, Name
			FROM Account
			WHERE Name = :clean
			LIMIT 1
		];
		if (!existing.isEmpty()) {
			return existing[0];
		}

		Id personAccountRtId = personAccountRecordTypeId();
		Account acct;
		if (personAccountRtId != null) {
			Map<String, String> parts = splitPersonName(clean);
			acct = new Account(
				FirstName = parts.get('first'),
				LastName = parts.get('last').left(80),
				RecordTypeId = personAccountRtId
			);
		} else {
			acct = new Account(Name = clean.left(255), AnnualRevenue = 0);
		}
		insert acct;
		return acct;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve el Id de un RecordType de Account de tipo Person Account activo y
	 * disponible. Devuelve null si el org no tiene Person Accounts o no hay RecordType usable.
	 * @return Id del RecordType Person Account disponible, o null.
	 */
	@TestVisible
	private static Id personAccountRecordTypeId() {
		if (
			!Schema.SObjectType.Account.fields.getMap().containsKey('isPersonAccount')
		) {
			return null;
		}
		List<RecordType> personRts = [
			SELECT Id
			FROM RecordType
			WHERE
				SObjectType = 'Account'
				AND IsPersonType = TRUE
				AND IsActive = TRUE
			LIMIT 1
		];
		if (personRts.isEmpty()) {
			return null;
		}
		Id rtId = personRts[0].Id;
		Map<Id, Schema.RecordTypeInfo> infos = Schema.SObjectType.Account.getRecordTypeInfosById();
		Schema.RecordTypeInfo rti = infos.get(rtId);
		return (rti != null && rti.isAvailable()) ? rtId : null;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Divide un nombre completo en 'first' (primer token) y 'last' (resto). Si hay un
	 * solo token, va a 'last'. Si esta en blanco, usa 'Cliente' como apellido.
	 * @param fullName: nombre completo a dividir.
	 * @return mapa con claves 'first' y 'last'.
	 */
	@TestVisible
	private static Map<String, String> splitPersonName(String fullName) {
		Map<String, String> r = new Map<String, String>{
			'first' => null,
			'last' => fullName
		};
		if (String.isBlank(fullName)) {
			r.put('last', 'Cliente');
			return r;
		}
		List<String> parts = fullName.trim().split('\\s+');
		if (parts.size() == 1) {
			r.put('last', parts[0]);
		} else {
			r.put('first', parts[0]);
			List<String> rest = new List<String>();
			for (Integer i = 1; i < parts.size(); i++) {
				rest.add(parts[i]);
			}
			r.put('last', String.join(rest, ' '));
		}
		return r;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve el MasterLabel de la primera etapa de Opportunity activa (por SortOrder).
	 * Si no hay etapas activas, devuelve 'Prospecting'.
	 * @return nombre de la etapa por defecto.
	 */
	@TestVisible
	private static String defaultStageName() {
		List<OpportunityStage> stages = [
			SELECT MasterLabel
			FROM OpportunityStage
			WHERE IsActive = TRUE
			ORDER BY SortOrder ASC
			LIMIT 1
		];
		return stages.isEmpty() ? 'Prospecting' : stages[0].MasterLabel;
	}

	// ============================================================
	// Paso ÚNICO (modo "alimentar formulario"): analizar sin crear registros.
	// Devuelve las cotizaciones en el MISMO formato que consume el LWC padre
	// (opportunityCreator): compania, ramo, primaTotal, tablaCompletaCoberturas
	// y datos del cliente. NO crea Opportunity ni Quotes: el padre llena su
	// formulario y el usuario revisa y guarda.
	// ============================================================
	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Analiza las cotizaciones (via Einstein o mock) y devuelve los datos en el
	 * formato que consume el LWC padre: ramo, detalle, cliente, lista de quotes (con coberturas),
	 * aseguradora ganadora, validacion, recomendacion, glosario y aviso. NO crea registros.
	 * @param fileNames: lista de nombres de archivo de las cotizaciones.
	 * @param pdfTexts: lista de textos extraidos de los PDFs (en el mismo orden que fileNames).
	 * @return mapa con los datos analizados listos para alimentar el formulario del LWC.
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> analyzeQuotes(List<String> fileNames, List<String> pdfTexts) {
		String rawJson = requestComparisonJson(fileNames, pdfTexts);
		if (fileNames != null && fileNames.size() >= 1 && fileNames[0] != null) {
			rawJson = rawJson.replace('PLACEHOLDER_FIRST_FILENAME', fileNames[0]);
		}
		if (fileNames != null && fileNames.size() >= 2 && fileNames[1] != null) {
			rawJson = rawJson.replace('PLACEHOLDER_SECOND_FILENAME', fileNames[1]);
		}

		Map<String, Object> comparison = parseFullComparisonJson(rawJson);
		List<Object> aseguradorasRaw = comparison.get('aseguradoras') instanceof List<Object>
			? (List<Object>) comparison.get('aseguradoras')
			: new List<Object>();

		String ramoForm = mapRamoToFormValue(stringOf(comparison.get('ramo')));

		// Datos comunes (mismos para todas): se devuelven UNA sola vez, aparte.
		Map<String, Object> detalle = buildDetalle(comparison);
		Map<String, Object> cliente = buildCliente(comparison);

		// Las cotizaciones solo traen lo que cambia entre aseguradoras.
		List<Map<String, Object>> quotes = new List<Map<String, Object>>();
		for (Object a : aseguradorasRaw) {
			if (!(a instanceof Map<String, Object>)) {
				continue;
			}
			quotes.add(mapAseguradoraToFormQuote((Map<String, Object>) a, ramoForm));
		}

		// --- Aseguradora ganadora (de la recomendación de la IA) ---
		String ganadora = '';
		Map<String, Object> rec = comparison.get('recomendacion') instanceof Map<String, Object>
			? (Map<String, Object>) comparison.get('recomendacion')
			: null;
		if (rec != null && rec.get('ganadoras') instanceof List<Object>) {
			List<Object> gs = (List<Object>) rec.get('ganadoras');
			if (!gs.isEmpty() && gs[0] instanceof Map<String, Object>) {
				ganadora = stringOf(((Map<String, Object>) gs[0]).get('nombre'));
			}
		}
		// Marcamos la cotización ganadora dentro de la lista.
		if (String.isNotBlank(ganadora)) {
			for (Map<String, Object> qq : quotes) {
				if (ganadora.equalsIgnoreCase(stringOf(qq.get('compania')))) {
					qq.put('esGanadora', true);
				}
			}
		}

		// --- Validación de mismo cliente / mismo vehículo ---
		Map<String, Object> validacion = comparison.get('validacion') instanceof Map<String, Object>
			? (Map<String, Object>) comparison.get('validacion')
			: new Map<String, Object>{
					'mismo_cliente' => true,
					'mismo_vehiculo' => true,
					'alerta' => ''
				};

		// El HTML del comparativo lo genera la IA, pero a veces llega truncado
		// (p. ej. solo la etiqueta de apertura). Si viene incompleto lo armamos
		// nosotros con los datos ya estructurados para no mostrar algo roto.
		String htmlIa = stringOf(comparison.get('comparativo_html'));
		String htmlComparativo = esHtmlComparativoCompleto(htmlIa)
			? htmlIa
			: construirComparativoHtml(ramoForm, cliente, quotes, ganadora);

		return new Map<String, Object>{
			'ramo' => ramoForm,
			'detalle' => detalle,
			'cliente' => cliente,
			'quotes' => quotes,
			'ganadora' => ganadora,
			'validacion' => validacion,
			'recomendacion' => comparison.get('recomendacion'),
			'glosario' => comparison.get('glosario'),
			'fuente' => lastUsedMock ? 'mock' : 'einstein',
			'aviso' => stringOf(comparison.get('aviso')),
			'comparativo_html' => htmlComparativo
		};
	}

	// ============================================================
	// Comparativo HTML de respaldo (cuando la IA lo devuelve truncado)
	// ============================================================

	// Se considera completo si trae una etiqueta de cierre real (no solo la de
	// apertura que a veces devuelve truncada la IA).
	private static Boolean esHtmlComparativoCompleto(String html) {
		if (String.isBlank(html)) { return false; }
		String h = html.toLowerCase();
		Boolean cierra = h.contains('</table>') || h.contains('</html>') || h.contains('</body>');
		return cierra && html.length() > 300;
	}

	// Arma un comparativo en HTML a partir de los datos ya estructurados
	// (aseguradoras y coberturas). Se usa como respaldo confiable.
	private static String construirComparativoHtml(
		String ramoForm,
		Map<String, Object> cliente,
		List<Map<String, Object>> quotes,
		String ganadora
	) {
		if (quotes == null || quotes.isEmpty()) { return ''; }

		String nombreCliente = cliente != null ? stringOf(cliente.get('nombre')) : '';

		// Nombres de cobertura en orden de aparicion (union de todas las aseguradoras).
		List<String> nombresCob = new List<String>();
		Set<String> vistos = new Set<String>();
		for (Map<String, Object> q : quotes) {
			for (Map<String, Object> c : coberturasDe(q)) {
				String nom = stringOf(c.get('cobertura'));
				if (String.isNotBlank(nom) && !vistos.contains(nom.toLowerCase())) {
					vistos.add(nom.toLowerCase());
					nombresCob.add(nom);
				}
			}
		}

		String th = 'padding:8px 10px;border:1px solid #d9dee6;text-align:left;font-size:13px;';
		String td = 'padding:8px 10px;border:1px solid #eef1f5;text-align:left;font-size:13px;vertical-align:top;';

		String html = '<div style="font-family:\'Segoe UI\',Arial,sans-serif;color:#1c2433;">';
		html += '<h2 style="font-size:18px;margin:0 0 12px;">Comparativo ' + htmlEscape(ramoForm);
		if (String.isNotBlank(nombreCliente)) { html += ' - ' + htmlEscape(nombreCliente); }
		html += '</h2>';
		html += '<table style="width:100%;border-collapse:collapse;">';

		// Encabezado: aseguradoras
		html += '<tr><th style="' + th + 'background:#f4f6f9;">Concepto</th>';
		for (Map<String, Object> q : quotes) {
			String comp = stringOf(q.get('compania'));
			Boolean esGan = String.isNotBlank(ganadora) && ganadora.equalsIgnoreCase(comp);
			String bg = esGan ? 'background:#fff3e0;' : 'background:#f4f6f9;';
			html += '<th style="' + th + bg + '">' + htmlEscape(comp);
			if (esGan) { html += ' <span style="color:#b85b00;font-size:11px;">&#9733; Recomendada</span>'; }
			html += '</th>';
		}
		html += '</tr>';

		// Plan
		html += filaHtml('Plan', quotes, 'plan', td, th);

		// Prima anual
		html += '<tr><th style="' + th + '">Prima Anual</th>';
		for (Map<String, Object> q : quotes) {
			Decimal prima = asDecimal(q.get('primaTotal'));
			String moneda = coalesceStr(stringOf(q.get('moneda')), 'MXN');
			String txt = prima != null ? ('$' + formatoMonto(prima) + ' ' + moneda) : '-';
			html += '<td style="' + td + '">' + htmlEscape(txt) + '</td>';
		}
		html += '</tr>';

		// Coberturas
		for (String nom : nombresCob) {
			html += '<tr><th style="' + th + '">' + htmlEscape(nom) + '</th>';
			for (Map<String, Object> q : quotes) {
				html += '<td style="' + td + '">' + htmlEscape(valorCobertura(q, nom)) + '</td>';
			}
			html += '</tr>';
		}

		html += '</table></div>';
		return html;
	}

	private static String filaHtml(String etiqueta, List<Map<String, Object>> quotes, String key, String td, String th) {
		String row = '<tr><th style="' + th + '">' + htmlEscape(etiqueta) + '</th>';
		for (Map<String, Object> q : quotes) {
			String v = stringOf(q.get(key));
			row += '<td style="' + td + '">' + (String.isBlank(v) ? '-' : htmlEscape(v)) + '</td>';
		}
		return row + '</tr>';
	}

	private static List<Map<String, Object>> coberturasDe(Map<String, Object> q) {
		List<Map<String, Object>> out = new List<Map<String, Object>>();
		if (q.get('tablaCompletaCoberturas') instanceof List<Object>) {
			for (Object o : (List<Object>) q.get('tablaCompletaCoberturas')) {
				if (o instanceof Map<String, Object>) { out.add((Map<String, Object>) o); }
			}
		}
		return out;
	}

	private static String valorCobertura(Map<String, Object> q, String nombre) {
		for (Map<String, Object> c : coberturasDe(q)) {
			if (nombre.equalsIgnoreCase(stringOf(c.get('cobertura')))) {
				String suma = stringOf(c.get('sumaAsegurada'));
				String ded = stringOf(c.get('deducible'));
				String coa = stringOf(c.get('coaseguro'));
				List<String> partes = new List<String>();
				if (String.isNotBlank(suma)) { partes.add(suma); }
				if (String.isNotBlank(ded)) { partes.add('Ded: ' + ded); }
				if (String.isNotBlank(coa)) { partes.add('Coa: ' + coa); }
				return partes.isEmpty() ? '-' : String.join(partes, ' | ');
			}
		}
		return '-';
	}

	private static String formatoMonto(Decimal d) {
		if (d == null) { return '0'; }
		return d.setScale(0).format();
	}

	private static String htmlEscape(String s) {
		if (String.isBlank(s)) { return ''; }
		return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;');
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Mapea el mapa de una aseguradora al formato de quote que consume el LWC,
	 * incluyendo solo lo que cambia entre aseguradoras (sin cliente ni vehiculo) y la tabla de coberturas.
	 * @param m: mapa con los datos de la aseguradora.
	 * @param ramoForm: valor del ramo ya traducido al picklist del formulario.
	 * @return mapa con los campos de la cotizacion para el LWC.
	 */
	@TestVisible
	private static Map<String, Object> mapAseguradoraToFormQuote(
		Map<String, Object> m,
		String ramoForm
	) {
		Map<String, Object> q = new Map<String, Object>();
		q.put('compania', stringOf(m.get('nombre')));
		q.put('plan', stringOf(m.get('plan')));
		q.put('ramo', ramoForm);
		q.put('primaTotal', asDecimal(m.get('prima_anual')));
		q.put('moneda', coalesceStr(stringOf(m.get('moneda')), 'MXN'));
		q.put('vigencia', stringOf(m.get('vigencia_fin')));
		q.put('noCotizacion', stringOf(m.get('no_cotizacion')));
		q.put('archivoOrigen', stringOf(m.get('archivo_origen')));
		q.put('notas', stringOf(m.get('notas')));
		q.put('tablaCompletaCoberturas', buildCoberturas(m));
		return q;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve el objeto "detalle" del ramo tal cual lo manda la IA. Como respaldo,
	 * si llega el esquema viejo de auto (vehiculo_detalle), lo adapta agregando la descripcion.
	 * @param comparison: mapa completo del comparativo devuelto por la IA.
	 * @return mapa con el detalle del ramo/vehiculo.
	 */
	@TestVisible
	private static Map<String, Object> buildDetalle(Map<String, Object> comparison) {
		if (comparison.get('detalle') instanceof Map<String, Object>) {
			return (Map<String, Object>) comparison.get('detalle');
		}
		if (comparison.get('vehiculo_detalle') instanceof Map<String, Object>) {
			Map<String, Object> r = new Map<String, Object>(
				(Map<String, Object>) comparison.get('vehiculo_detalle')
			);
			if (!r.containsKey('descripcion')) {
				r.put('descripcion', stringOf(comparison.get('vehiculo')));
			}
			return r;
		}
		return new Map<String, Object>();
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma la tabla de coberturas { cobertura, sumaAsegurada, deducible, coaseguro }.
	 * Prioriza el esquema nuevo generico (lista "coberturas"); como respaldo usa el esquema viejo
	 * especifico de auto con campos fijos.
	 * @param m: mapa de la aseguradora con sus coberturas.
	 * @return lista de mapas de coberturas.
	 */
	@TestVisible
	private static List<Map<String, Object>> buildCoberturas(Map<String, Object> m) {
		List<Map<String, Object>> cobs = new List<Map<String, Object>>();

		// 1) Esquema NUEVO y genérico (cualquier ramo): la IA manda "coberturas".
		if (m.get('coberturas') instanceof List<Object>) {
			for (Object o : (List<Object>) m.get('coberturas')) {
				if (o instanceof Map<String, Object>) {
					Map<String, Object> c = (Map<String, Object>) o;
					cobs.add(new Map<String, Object>{
						'cobertura' => stringOf(c.get('nombre')),
						'sumaAsegurada' => normalizeSuma(c.get('suma_asegurada')),
						'deducible' => stringOf(c.get('deducible')),
						'coaseguro' => stringOf(c.get('coaseguro'))
					});
				}
			}
			if (!cobs.isEmpty()) {
				return cobs;
			}
		}

		// 2) Respaldo: esquema viejo específico de AUTO (campos fijos).
		Decimal suma = asDecimal(m.get('suma_asegurada'));
		if (suma != null) {
			cobs.add(cobertura('Daños Materiales', suma, pctText(m.get('deducible_danos_pct')), ''));
		}
		if (asDecimal(m.get('deducible_robo_pct')) != null || asDecimal(m.get('deducible_robo_mxn')) != null) {
			cobs.add(cobertura('Robo Total', suma, pctText(m.get('deducible_robo_pct')), ''));
		}
		Decimal rc = asDecimal(m.get('responsabilidad_civil'));
		if (rc != null) { cobs.add(cobertura('Responsabilidad Civil', rc, '', '')); }
		Decimal gm = asDecimal(m.get('gastos_medicos'));
		if (gm != null) { cobs.add(cobertura('Gastos Médicos Ocupantes', gm, '', '')); }
		Decimal vc = asDecimal(m.get('vida_conductor'));
		if (vc != null) { cobs.add(cobertura('Vida del Conductor', vc, '', '')); }
		if (asBoolean(m.get('cristales')))        { cobs.add(coberturaTxt('Cristales', 'Incluida')); }
		if (asBoolean(m.get('asistencia_vial')))  { cobs.add(coberturaTxt('Asistencia Vial', 'Incluida')); }
		if (asBoolean(m.get('defensa_juridica'))) { cobs.add(coberturaTxt('Defensa Jurídica', 'Incluida')); }
		if (asBoolean(m.get('rc_extranjero')))    { cobs.add(coberturaTxt('RC en el Extranjero', 'Incluida')); }
		return cobs;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Normaliza una suma asegurada que puede venir como numero (850000) o como texto
	 * ("Incluida"): respeta ambos, devolviendo Decimal cuando es convertible o el String original.
	 * @param o: valor de suma asegurada a normalizar.
	 * @return Decimal, String o null segun el valor.
	 */
	private static Object normalizeSuma(Object o) {
		if (o == null) { return null; }
		if (o instanceof String) {
			Decimal d = asDecimal(o);
			return (d != null) ? (Object) d : (Object) ((String) o);
		}
		return asDecimal(o);
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Extrae los datos del cliente una sola vez. Acepta "cliente" como objeto (con
	 * nombre, rfc, email, etc.) o como texto (solo el nombre).
	 * @param comparison: mapa completo del comparativo devuelto por la IA.
	 * @return mapa con los datos del cliente.
	 */
	@TestVisible
	private static Map<String, Object> buildCliente(Map<String, Object> comparison) {
		Object c = comparison.get('cliente');
		if (c instanceof Map<String, Object>) {
			Map<String, Object> cm = (Map<String, Object>) c;
			return new Map<String, Object>{
				'nombre' => stringOf(cm.get('nombre')),
				'rfc' => stringOf(cm.get('rfc')),
				'email' => stringOf(cm.get('email')),
				'telefono' => stringOf(cm.get('telefono')),
				'cp' => stringOf(cm.get('cp')),
				'direccion' => stringOf(cm.get('direccion'))
			};
		}
		return new Map<String, Object>{
			'nombre' => stringOf(c),
			'rfc' => '',
			'email' => '',
			'telefono' => '',
			'cp' => '',
			'direccion' => ''
		};
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Construye un mapa de cobertura con suma asegurada numerica y sus deducible/coaseguro.
	 * @param nombre: nombre de la cobertura.
	 * @param suma: suma asegurada.
	 * @param ded: deducible.
	 * @param coa: coaseguro.
	 * @return mapa de la cobertura.
	 */
	private static Map<String, Object> cobertura(String nombre, Decimal suma, String ded, String coa) {
		return new Map<String, Object>{
			'cobertura' => nombre,
			'sumaAsegurada' => suma,
			'deducible' => ded,
			'coaseguro' => coa
		};
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Construye un mapa de cobertura cuya suma asegurada es un texto (p. ej. "Incluida"),
	 * con deducible y coaseguro vacios.
	 * @param nombre: nombre de la cobertura.
	 * @param texto: valor textual de la suma asegurada.
	 * @return mapa de la cobertura.
	 */
	private static Map<String, Object> coberturaTxt(String nombre, String texto) {
		return new Map<String, Object>{
			'cobertura' => nombre,
			'sumaAsegurada' => texto,
			'deducible' => '',
			'coaseguro' => ''
		};
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Formatea un valor a texto de porcentaje (agrega "%"). Devuelve cadena vacia si no es numerico.
	 * @param o: valor a formatear como porcentaje.
	 * @return texto de porcentaje, o cadena vacia.
	 */
	private static String pctText(Object o) {
		Decimal d = asDecimal(o);
		return d == null ? '' : (String.valueOf(d) + '%');
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve a si no esta en blanco; de lo contrario devuelve b.
	 * @param a: candidato principal.
	 * @param b: valor de respaldo.
	 * @return a si no esta en blanco; si no, b.
	 */
	private static String coalesceStr(String a, String b) {
		return String.isNotBlank(a) ? a : b;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Traduce el ramo que devuelve la IA al valor exacto del picklist Ramo__c del LWC
	 * (Automoviles, GMM, Vida, Viajes, Danos, Empresarial, Fianzas, Dental, Vision, RC).
	 * @param ramo: ramo tal como lo devuelve la IA.
	 * @return valor del picklist correspondiente, o el ramo original si no hay coincidencia.
	 */
	@TestVisible
	private static String mapRamoToFormValue(String ramo) {
		if (String.isBlank(ramo)) {
			return '';
		}
		String u = ramo.toUpperCase();
		if (u.contains('AUTO')) return 'Automoviles';
		if (u.contains('GMM') || u.contains('MEDIC')) return 'GMM';
		if (u.contains('VIDA')) return 'Vida';
		if (u.contains('VIAJE')) return 'Viajes';
		if (u.contains('DAÑO') || u.contains('DANO')) return 'Danos';
		if (u.contains('EMPRES')) return 'Empresarial';
		if (u.contains('FIANZ')) return 'Fianzas';
		if (u.contains('DENTAL')) return 'Dental';
		if (u.contains('VISION') || u.contains('VISIÓN')) return 'Vision';
		if (u == 'RC' || u.contains('RESPONSAB')) return 'RC';
		return ramo;
	}

	// ============================================================
	// Wrappers para el LWC
	// ============================================================
	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Wrapper expuesto al LWC con el resumen de una cotizacion (id, nombre,
	 * aseguradora, prima anual, suma asegurada y archivo origen).
	 */
	public class QuoteSummary {
		@AuraEnabled
		public Id id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String aseguradora;
		@AuraEnabled
		public Decimal primaAnual;
		@AuraEnabled
		public Decimal sumaAsegurada;
		@AuraEnabled
		public String archivoOrigen;
	}

	// === API Names confirmados de tu org ===
	private static final String QF_RAMO        = 'Ramos__c';
	private static final String QF_ASEGURADORA = 'Aseguradora__c';
	private static final String QF_PRODUCT     = 'Product__c';
	private static final String QF_FRECUENCIA  = 'Frecuencia_de_prima__c';
	private static final String QF_RATINGDATE  = 'RatingDate';

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Crea registros Quote hijos de una Opportunity a partir del JSON de cotizaciones.
	 * Resuelve contacto/email (rol primario o Person Account), aseguradoras y productos por
	 * aseguradora+ramo, arma cada Quote con sus campos y los inserta. Devuelve el conteo y el detalle.
	 * @param opportunityId: Id de la Opportunity padre.
	 * @param quotesJson: JSON (lista) con las cotizaciones a crear.
	 * @return mapa con 'creadas' (cantidad) y 'detalle' (lista de mapas por cotizacion).
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String,Object> crearCotizacionesDesdePdf(Id opportunityId, String quotesJson) {
		System.debug('crearCotizacionesDesdePdf: oppId=' + opportunityId + ', quotesJson=' + quotesJson);
		if (opportunityId == null || String.isBlank(quotesJson)) {
			return new Map<String,Object>{ 'creadas' => 0, 'detalle' => new List<Object>() };
		}
		List<Object> raw;
		try {
			raw = (List<Object>) JSON.deserializeUntyped(quotesJson);
			System.debug('crearCotizacionesDesdePdf: raw=' + raw);
			if (raw == null || raw.isEmpty()) {
				return new Map<String,Object>{ 'creadas' => 0, 'detalle' => new List<Object>() };
			}
		}catch (Exception e) { throw new AuraHandledException('Cotizaciones inválidas: ' + e.getMessage()); }

		Opportunity opp = [
			SELECT Id, AccountId, Pricebook2Id, Ramo__c, Name
			FROM Opportunity WHERE Id = :opportunityId LIMIT 1
		];
		Id pbId = opp.Pricebook2Id != null ? opp.Pricebook2Id : getStandardPricebookId();

		// Contacto + email (rol primario de la opp; si no, Person Account)
		Id contactId; String email;
		for (OpportunityContactRole r : [
			SELECT ContactId, Contact.Email FROM OpportunityContactRole
			WHERE OpportunityId = :opportunityId AND IsPrimary = true LIMIT 1
		]) { contactId = r.ContactId; email = r.Contact.Email; }
		if (contactId == null && opp.AccountId != null) {
			try {
				for (Account a : [
					SELECT PersonContactId, PersonEmail FROM Account
					WHERE Id = :opp.AccountId AND IsPersonAccount = true LIMIT 1
				]) { contactId = a.PersonContactId; email = a.PersonEmail; }
			} catch (Exception ignore) {}
		}

		Set<String> nombresAseg = new Set<String>();
		for (Object o : raw) if (o instanceof Map<String,Object>) {
			String n = stringOf(((Map<String,Object>)o).get('compania'));
			if (String.isNotBlank(n)) nombresAseg.add(n);
		}
		Map<String, Id> asegByName = resolveAseguradoraByName(nombresAseg);

		List<Quote> toInsert = new List<Quote>();
		List<Map<String,Object>> detalle = new List<Map<String,Object>>();
		Set<Id> prodIds = new Set<Id>();

		for (Object o : raw) {
			if (!(o instanceof Map<String,Object>)) { continue; }
			Map<String,Object> m = (Map<String,Object>) o;
			String compania = stringOf(m.get('compania'));
			String ramo     = stringOf(m.get('ramo'));
			String plan     = stringOf(m.get('plan'));
			Decimal prima   = asDecimal(m.get('primaTotal'));
			Id asegId = asegByName.get(compania);
			Object aidRaw = m.get('aseguradoraId');
			if (aidRaw != null && String.isNotBlank(String.valueOf(aidRaw))) {
				try { asegId = (Id) String.valueOf(aidRaw); } catch (Exception e) { /* id inválido: se ignora */ }
			}
			Id productId;
			Object pidRaw = m.get('productId');
			if (pidRaw != null && String.isNotBlank(String.valueOf(pidRaw))) {
				try { productId = (Id) String.valueOf(pidRaw); } catch (Exception e) { productId = null; }
			}
			if (productId == null) { productId = findProductByAseguradoraRamo(asegId, ramo); }
			if (productId != null) { prodIds.add(productId); }

			detalle.add(new Map<String,Object>{
				'compania'=>compania, 'plan'=>plan, 'ramo'=>ramo,
				'aseguradoraId'=>asegId, 'productId'=>productId
			});

			// === Construcción del Quote con todos los campos requeridos ===
			Quote q = new Quote();
			q.OpportunityId = opportunityId;
			q.Name = ((String.isBlank(compania)?'Cotización':compania) + (String.isBlank(plan)?'':' - '+plan)).left(255);
			q.Status = 'In Review';
			q.Pricebook2Id = pbId;
			if (contactId != null)        { q.ContactId = contactId; }
			if (String.isNotBlank(email)) { q.Email = email; }

			Date vig = parseDate(stringOf(m.get('vigencia')));
			if (vig != null) { q.ExpirationDate = vig; }
			if (asegId != null)    { q.put(QF_ASEGURADORA, asegId); }
			if (productId != null) { q.put(QF_PRODUCT, productId); }
			q.put(QF_RAMO, String.isNotBlank(opp.Ramo__c) ? opp.Ramo__c : ramo);
			q.put(QF_RATINGDATE, Date.today());
			q.put(QF_FRECUENCIA, 'Mensual');
			q.Prima_Total__c = prima;
			toInsert.add(q);
		}

		// Nombres de los productos asignados (para ver qué se envió)
		Map<Id,String> pName = new Map<Id,String>();
		Map<Id,String> pCode = new Map<Id,String>();
		for (Product2 p : [SELECT Id, Name, ProductCode FROM Product2 WHERE Id IN :prodIds]) {
			pName.put(p.Id, p.Name); pCode.put(p.Id, p.ProductCode);
		}
		for (Map<String,Object> d : detalle) {
			Id pid = (Id) d.get('productId');
			d.put('productName', pid != null ? pName.get(pid) : '(SIN PRODUCTO)');
			d.put('productCode', pid != null ? pCode.get(pid) : '');
			System.debug('COT-PROD::: ' + JSON.serialize(d));
		}

		try {
			if (!toInsert.isEmpty()) { insert toInsert; }
		} catch (Exception e) {
			System.debug('COT::: ' + e.getMessage() + ' | ' + e.getStackTraceString());
			throw new AuraHandledException('No se pudieron crear las cotizaciones: ' + e.getMessage());
		}

		return new Map<String,Object>{ 'creadas' => toInsert.size(), 'detalle' => detalle };
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Busca un producto ACTIVO de esa aseguradora y ese ramo (Family). Si no hay,
	 * devuelve null (no asigna productos de otro ramo).
	 * @param asegId: Id de la Aseguradora__c.
	 * @param ramo: ramo (mapeado al campo Family del producto).
	 * @return Id del producto encontrado, o null.
	 */
	@TestVisible
	private static Id findProductByAseguradoraRamo(Id asegId, String ramo) {
		if (asegId == null || String.isBlank(ramo)) { return null; }
		List<Product2> ps = [
			SELECT Id FROM Product2
			WHERE IsActive = true
			  AND Aseguradora__c = :asegId
			  AND Family = :ramo
			ORDER BY Name
			LIMIT 1
		];
		return ps.isEmpty() ? null : ps[0].Id;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Busca la Aseguradora__c existente que corresponde a cada nombre del PDF. NO crea
	 * aseguradoras: hace match por palabras clave (tokenizando, ignorando stopwords y aplicando alias
	 * como bupa->chubb, insignia->latino, continental->gmx) y elige la de mayor coincidencia.
	 * @param nombres: conjunto de nombres de aseguradora tal como aparecen en los PDFs.
	 * @return mapa nombre-solicitado a Id de la Aseguradora__c con mejor coincidencia.
	 */
	@TestVisible
	private static Map<String, Id> resolveAseguradoraByName(Set<String> nombres) {
		Map<String, Id> result = new Map<String, Id>();
		if (nombres == null || nombres.isEmpty()) { return result; }

		// Palabras a ignorar al comparar (genéricas).
		Set<String> stop = new Set<String>{'seguros','seguro','mexico','de','del','la','el','nyl','sa','cv','consultores'};
		// Alias de nombres cortos del PDF hacia la marca real en el org.
		Map<String,String> alias = new Map<String,String>{ 'bupa'=>'chubb', 'insignia'=>'latino', 'continental'=>'gmx' };

		List<Aseguradora__c> all = [SELECT Id, Name FROM Aseguradora__c];
		List<Set<String>> tokensList = new List<Set<String>>();
		List<Id> idList = new List<Id>();
		for (Aseguradora__c a : all) {
			Set<String> toks = new Set<String>();
			for (String t : fold(a.Name).split(' ')) {
				if (String.isNotBlank(t) && !stop.contains(t)) { toks.add(t); }
			}
			tokensList.add(toks); idList.add(a.Id);
		}

		for (String req : nombres) {
			Set<String> reqToks = new Set<String>();
			for (String t : fold(req).split(' ')) {
				if (String.isNotBlank(t) && !stop.contains(t)) { reqToks.add(t); }
			}
			// aplicar alias (bupa->chubb, insignia->latino, continental->gmx)
			Set<String> aliased = new Set<String>(reqToks);
			for (String t : reqToks) { if (alias.containsKey(t)) { aliased.add(alias.get(t)); } }

			Id best = null; Integer bestScore = 0;
			for (Integer i = 0; i < tokensList.size(); i++) {
				Integer score = 0;
				for (String t : aliased) { if (tokensList[i].contains(t)) { score++; } }
				if (score > bestScore) { bestScore = score; best = idList[i]; }
			}
			if (best != null) { result.put(req, best); }
		}
		return result;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Asigna un campo a un SObject solo si el campo existe en el org (evita errores si
	 * el campo no esta). Ignora valores null.
	 * @param so: el SObject a modificar.
	 * @param field: API name del campo a asignar.
	 * @param value: valor a asignar.
	 * @return void
	 */
	private static void setIfExists(SObject so, String field, Object value) {
		if (value == null) { return; }
		try {
			so.put(field, value);
		} catch (Exception ignore) {
			// El campo no existe en este org: lo omitimos.
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve, por cotizacion, sus datos mas la lista de productos disponibles (de esa
	 * aseguradora y ramo; si no hay, todos los de la aseguradora) para que el usuario elija en el LWC,
	 * ademas de un producto sugerido.
	 * @param quotesJson: JSON (lista) con las cotizaciones a preparar.
	 * @return lista de mapas con datos de cada cotizacion y sus productos disponibles.
	 */
	@AuraEnabled(cacheable=false)
	public static List<Map<String,Object>> prepararCotizaciones(String quotesJson) {
		List<Map<String,Object>> out = new List<Map<String,Object>>();
		if (String.isBlank(quotesJson)) { return out; }
		List<Object> raw;
		try { raw = (List<Object>) JSON.deserializeUntyped(quotesJson); }
		catch (Exception e) { return out; }
		if (raw == null || raw.isEmpty()) { return out; }

		Set<String> nombres = new Set<String>();
		for (Object o : raw) if (o instanceof Map<String,Object>) {
			String n = stringOf(((Map<String,Object>)o).get('compania'));
			if (String.isNotBlank(n)) nombres.add(n);
		}
		Map<String,Id> asegByName = resolveAseguradoraByName(nombres);

		List<Map<String,Object>> asegOpts = new List<Map<String,Object>>();
		for (Aseguradora__c a : [SELECT Id, Name FROM Aseguradora__c ORDER BY Name]) {
			asegOpts.add(new Map<String,Object>{ 'label' => a.Name, 'value' => a.Id });
		}

		for (Object o : raw) {
			if (!(o instanceof Map<String,Object>)) { continue; }
			Map<String,Object> m = (Map<String,Object>) o;
			String compania = stringOf(m.get('compania'));
			String ramo = stringOf(m.get('ramo'));
			Id asegId = asegByName.get(compania);

			// Productos de esa aseguradora + ramo; si no hay, todos los de la aseguradora.
			List<Product2> prods = new List<Product2>();
			if (asegId != null && String.isNotBlank(ramo)) {
				prods = [SELECT Id, Name FROM Product2
						 WHERE IsActive = true AND Aseguradora__c = :asegId AND Family = :ramo
						 ORDER BY Name];
			}
			if (prods.isEmpty() && asegId != null) {
				prods = [SELECT Id, Name FROM Product2
						 WHERE IsActive = true AND Aseguradora__c = :asegId
						 ORDER BY Name];
			}
			List<Map<String,Object>> productos = new List<Map<String,Object>>();
			for (Product2 p : prods) {
				productos.add(new Map<String,Object>{ 'label' => p.Name, 'value' => p.Id });
			}
			Id sugerido = prods.isEmpty() ? null : prods[0].Id;

			out.add(new Map<String,Object>{
				'id' => stringOf(m.get('id')),
				'compania' => compania,
				'aseguradoraId' => asegId,
				'plan' => stringOf(m.get('plan')),
				'ramo' => ramo,
				'primaTotal' => m.get('primaTotal'),
				'vigencia' => stringOf(m.get('vigencia')),
				'noCotizacion' => stringOf(m.get('noCotizacion')),
				'productoSugeridoId' => sugerido,
				'productos' => productos,
				'aseguradoras' => asegOpts
			});
		}
		return out;
	}

	@AuraEnabled(cacheable=false)
	public static List<Map<String,Object>> getProductosPorAseguradoraRamo(Id aseguradoraId, String ramo) {
		List<Map<String,Object>> out = new List<Map<String,Object>>();
		if (aseguradoraId == null) { return out; }
	
		// Primero productos de esa aseguradora + ramo; si no hay, todos los de la aseguradora.
		List<Product2> prods = new List<Product2>();
		if (String.isNotBlank(ramo)) {
			prods = [SELECT Id, Name FROM Product2
					WHERE IsActive = true AND Aseguradora__c = :aseguradoraId AND Family = :ramo
					ORDER BY Name];
		}
		if (prods.isEmpty()) {
			prods = [SELECT Id, Name FROM Product2
					WHERE IsActive = true AND Aseguradora__c = :aseguradoraId
					ORDER BY Name];
		}
		for (Product2 p : prods) {
			out.add(new Map<String,Object>{ 'label' => p.Name, 'value' => p.Id });
		}
		return out;
	}
}