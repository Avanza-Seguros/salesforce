/**
 *   @name: PdfOpportunityController
 *   @version: 1.0
 *   @creation date: 02/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Orquesta la creacion de una Opportunity a partir de varios PDFs de
 *   cotizaciones. El proceso se divide en DOS llamadas (dos transacciones) a proposito:
 *   1) uploadAndCreateDraft: solo DML, crea la Opportunity borrador y sube los PDFs.
 *   2) compareAndCreateQuotes: compara las cotizaciones (mock por ahora; IA en Fase 4),
 *   crea un Quote hijo por cotizacion con todos los datos de cobertura, genera un PDF
 *   comparativo y lo liga a la Opp. Salesforce no permite hacer callouts despues de un
 *   DML sin commit dentro de la misma transaccion, por eso el borrador se crea y persiste
 *   en el paso 1 antes de comparar.
 */
public with sharing class PdfOpportunityController {
	private static final Integer MIN_PREFIX_LENGTH = 3;

	// Inyectable en tests para evitar la pagina Visualforce real.
	@TestVisible
	private static IPdfRenderer pdfRenderer = new VisualforcePdfRenderer();

	// JSON estatico usado en Fase 2; en Fase 4 lo reemplaza la llamada al flow de IA.
	// Los nombres de archivo (PLACEHOLDER_*) se sustituyen en runtime con los titulos reales.
	private static final String MOCK_COMPARISON_JSON =
		'{' +
			'"vehiculo": "Great Wall Tank 500 2024",' +
			'"cliente": "Juan Pérez García",' +
			'"ramo": "Auto",' +
			'"aseguradoras": [' +
				'{' +
					'"nombre": "GNP",' +
					'"no_cotizacion": "GNP-998877",' +
					'"archivo_origen": "PLACEHOLDER_FIRST_FILENAME",' +
					'"prima_anual": 28500.50,' +
					'"suma_asegurada": 850000,' +
					'"tipo_valor": "comercial",' +
					'"moneda": "MXN",' +
					'"vigencia_inicio": "2026-07-01",' +
					'"vigencia_fin": "2027-07-01",' +
					'"deducible_danos_pct": 5,' +
					'"deducible_danos_mxn": 42500,' +
					'"deducible_robo_pct": 10,' +
					'"deducible_robo_mxn": 85000,' +
					'"cristales": true,' +
					'"responsabilidad_civil": 3000000,' +
					'"gastos_medicos": 500000,' +
					'"asistencia_vial": true,' +
					'"defensa_juridica": true,' +
					'"vida_conductor": 100000,' +
					'"rc_extranjero": false,' +
					'"notas": "Exige GPS para robo total"' +
				'},' +
				'{' +
					'"nombre": "AXA",' +
					'"no_cotizacion": "AXA-554433",' +
					'"archivo_origen": "PLACEHOLDER_SECOND_FILENAME",' +
					'"prima_anual": 26800.00,' +
					'"suma_asegurada": 850000,' +
					'"tipo_valor": "comercial+10",' +
					'"moneda": "MXN",' +
					'"vigencia_inicio": "2026-07-01",' +
					'"vigencia_fin": "2027-07-01",' +
					'"deducible_danos_pct": 5,' +
					'"deducible_danos_mxn": 42500,' +
					'"deducible_robo_pct": 10,' +
					'"deducible_robo_mxn": 85000,' +
					'"cristales": true,' +
					'"responsabilidad_civil": 3000000,' +
					'"gastos_medicos": 500000,' +
					'"asistencia_vial": true,' +
					'"defensa_juridica": true,' +
					'"vida_conductor": 100000,' +
					'"rc_extranjero": true,' +
					'"notas": ""' +
				'}' +
			'],' +
			'"recomendacion": {' +
				'"ganadoras": [{"nombre":"AXA","etiqueta":"Mejor relación precio/valor","porque":"Prima más baja con valor +10% y RC extranjero incluido","a_cambio":"Sin notas especiales de robo"}],' +
				'"guia_frecuencia": [' +
					'{"riesgo":"Cristales/golpes menores","frecuencia":"Frecuente","gana":"Empate","detalle":"Ambas incluyen cristales sin deducible"},' +
					'{"riesgo":"Choque mayor","frecuencia":"Moderado","gana":"Empate","detalle":"Mismo deducible (5%) y suma asegurada"},' +
					'{"riesgo":"Robo total","frecuencia":"Bajo","gana":"AXA","detalle":"AXA no requiere GPS"}' +
				'],' +
				'"en_pocas_palabras": "AXA conviene ligeramente; GNP es alternativa sólida si ya tienes GPS instalado."' +
			'},' +
			'"glosario": [' +
				'{"termino":"Prima","definicion":"Lo que pagas al año por la cobertura."},' +
				'{"termino":"Deducible","definicion":"Lo que tú pones de tu bolsa cuando hay siniestro."},' +
				'{"termino":"Suma asegurada","definicion":"Tope máximo que paga la aseguradora."}' +
			'],' +
			'"comparativo_html": "<html><body><h1>Comparativo Great Wall Tank 500 2024</h1><table border=\'1\' cellpadding=\'8\'><tr><th>Cobertura</th><th>GNP</th><th>AXA</th></tr><tr><td>Prima anual</td><td>$28,500.50</td><td>$26,800.00</td></tr><tr><td>Suma asegurada</td><td>$850,000</td><td>$850,000</td></tr><tr><td>Tipo de valor</td><td>Comercial</td><td>Comercial +10%</td></tr></table><p><strong>Recomendación:</strong> AXA por mejor relación precio/valor.</p><p style=\'font-size:10px;color:#888\'>Documento informativo, no es una póliza. · Avanza Seguro.</p></body></html>",' +
			'"aviso": "Documento informativo, no es una póliza; sujeto a las condiciones generales de cada aseguradora. Avanza Seguro."' +
		'}';

	// ============================================================
	// Paso 1: crear borrador + subir PDFs (solo DML, sin callouts)
	// ============================================================
	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valida los archivos recibidos, crea una Opportunity borrador con nombre
	 * basado en el prefijo comun de los archivos, sube los PDFs como ContentVersion y los
	 * liga a la Opportunity mediante ContentDocumentLink. Solo ejecuta DML (sin callouts).
	 * @param fileNames: lista de nombres de los archivos PDF a subir.
	 * @param base64DataList: lista de contenidos de los archivos codificados en base64, en el mismo orden que fileNames.
	 * @return mapa con el Id de la Opportunity creada ('opportunityId') y la lista de Ids de los ContentDocument ('contentDocumentIds').
	 */
	@AuraEnabled
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

	// ============================================================
	// Paso 2: comparar cotizaciones, crear Quotes hijas y PDF comparativo.
	// Fase 2 usa MOCK_COMPARISON_JSON; en Fase 4 se reemplaza por la llamada al flow.
	// ============================================================
	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Compara las cotizaciones a partir del JSON (mock por ahora), actualiza la
	 * Opportunity con nombre/cuenta/descripcion, crea un Quote hijo por aseguradora, liga cada
	 * PDF origen a su Quote, genera un PDF comparativo y lo liga a la Opportunity.
	 * @param opportunityId: Id de la Opportunity borrador creada en el paso 1.
	 * @param contentDocumentIds: lista de Ids de los ContentDocument (PDFs) a comparar.
	 * @return mapa con datos de la Opportunity, cotizaciones creadas, recomendacion, glosario y aviso.
	 */
	@AuraEnabled
	public static Map<String, Object> compareAndCreateQuotes(
		Id opportunityId,
		List<Id> contentDocumentIds
	) {
		if (
			opportunityId == null ||
			contentDocumentIds == null ||
			contentDocumentIds.size() < 2
		) {
			throw new AuraHandledException(
				'Se requieren al menos 2 cotizaciones para comparar.'
			);
		}

		Map<Id, String> titlesById = new Map<Id, String>();
		for (ContentDocument cd : [
			SELECT Id, Title
			FROM ContentDocument
			WHERE Id IN :contentDocumentIds
		]) {
			titlesById.put(cd.Id, cd.Title);
		}

		String rawJson = MOCK_COMPARISON_JSON;
		List<String> orderedTitles = new List<String>();
		for (Id docId : contentDocumentIds) {
			if (titlesById.containsKey(docId)) {
				orderedTitles.add(titlesById.get(docId));
			}
		}
		if (orderedTitles.size() >= 1) {
			rawJson = rawJson.replace(
				'PLACEHOLDER_FIRST_FILENAME',
				orderedTitles[0]
			);
		}
		if (orderedTitles.size() >= 2) {
			rawJson = rawJson.replace(
				'PLACEHOLDER_SECOND_FILENAME',
				orderedTitles[1]
			);
		}

		Map<String, Object> comparison = parseFullComparisonJson(rawJson);
		List<Object> aseguradorasRaw = (List<Object>) comparison.get('aseguradoras');
		if (aseguradorasRaw == null || aseguradorasRaw.isEmpty()) {
			throw new AuraHandledException(
				'La comparación no devolvió aseguradoras para crear cotizaciones.'
			);
		}

		String vehiculo = stringOf(comparison.get('vehiculo'));
		String cliente = stringOf(comparison.get('cliente'));
		String ramo = stringOf(comparison.get('ramo'));
		String aviso = stringOf(comparison.get('aviso'));
		String comparativoHtml = stringOf(comparison.get('comparativo_html'));
		Map<String, Object> recomendacion = comparison.get('recomendacion') instanceof Map<String, Object>
			? (Map<String, Object>) comparison.get('recomendacion')
			: new Map<String, Object>();
		List<Object> glosarioRaw = comparison.get('glosario') instanceof List<Object>
			? (List<Object>) comparison.get('glosario')
			: new List<Object>();
		List<Map<String, Object>> glosario = new List<Map<String, Object>>();
		for (Object g : glosarioRaw) {
			if (g instanceof Map<String, Object>) {
				glosario.add((Map<String, Object>) g);
			}
		}

		try {
			Opportunity opp = [
				SELECT Id, Name, AccountId, Amount, Description
				FROM Opportunity
				WHERE Id = :opportunityId
				LIMIT 1
			];

			Id accountId = opp.AccountId;
			String accountWarning = '';
			if (String.isNotBlank(cliente)) {
				try {
					accountId = findOrCreateAccount(cliente).Id;
				} catch (Exception accountErr) {
					accountWarning =
						'No se pudo crear/buscar la cuenta "' +
						cliente +
						'" automáticamente: ' +
						accountErr.getMessage();
					System.debug(accountWarning);
				}
			}

			String nombreOpp = String.isBlank(vehiculo) || String.isBlank(cliente)
				? coalesce(vehiculo, cliente, opp.Name)
				: vehiculo + ' - ' + cliente;
			opp.Name = nombreOpp.left(120);
			if (accountId != null) {
				opp.AccountId = accountId;
			}
			opp.Description = buildOpportunityDescription(aviso, recomendacion, accountWarning);
			applyOpportunityDefaults(opp);
			update opp;

			Map<String, Id> nameToAseguradoraId = resolveAseguradoraLookups(aseguradorasRaw);

			List<Quote> quotesToInsert = new List<Quote>();
			List<Map<String, Object>> aseguradoraMaps = new List<Map<String, Object>>();
			Id stdPricebookId = getStandardPricebookId();
			for (Object a : aseguradorasRaw) {
				if (!(a instanceof Map<String, Object>)) {
					continue;
				}
				Map<String, Object> m = (Map<String, Object>) a;
				aseguradoraMaps.add(m);
				quotesToInsert.add(buildQuote(opportunityId, m, nameToAseguradoraId, stdPricebookId));
			}
			insert quotesToInsert;

			Map<String, Id> titleToDocId = new Map<String, Id>();
			for (Id docId : titlesById.keySet()) {
				titleToDocId.put(titlesById.get(docId), docId);
			}

			List<ContentDocumentLink> quoteLinks = new List<ContentDocumentLink>();
			List<Map<String, Object>> quoteSummaries = new List<Map<String, Object>>();
			for (Integer i = 0; i < quotesToInsert.size(); i++) {
				Quote q = quotesToInsert[i];
				Map<String, Object> m = aseguradoraMaps[i];
				String archivoOrigen = stringOf(m.get('archivo_origen'));
				Id docId = String.isBlank(archivoOrigen) ? null : titleToDocId.get(archivoOrigen);
				if (docId != null) {
					quoteLinks.add(
						new ContentDocumentLink(
							ContentDocumentId = docId,
							LinkedEntityId = q.Id,
							ShareType = 'V',
							Visibility = 'AllUsers'
						)
					);
				}
				quoteSummaries.add(
					new Map<String, Object>{
						'id' => q.Id,
						'name' => q.Name,
						'aseguradora' => stringOf(m.get('nombre')),
						'primaAnual' => m.get('prima_anual'),
						'sumaAsegurada' => m.get('suma_asegurada'),
						'archivoOrigen' => archivoOrigen
					}
				);
			}
			if (!quoteLinks.isEmpty()) {
				insert quoteLinks;
			}

			Id comparativoDocId = renderAndLinkComparativo(
				comparativoHtml,
				vehiculo,
				opportunityId
			);

			return new Map<String, Object>{
				'opportunityId' => opp.Id,
				'opportunityName' => opp.Name,
				'comparativoPdfId' => comparativoDocId,
				'vehiculo' => vehiculo,
				'cliente' => cliente,
				'ramo' => ramo,
				'quotes' => quoteSummaries,
				'recomendacion' => recomendacion,
				'glosario' => glosario,
				'aviso' => aviso
			};
		} catch (Exception e) {
			throw new AuraHandledException(
				'No se pudo crear el comparativo: ' + e.getMessage()
			);
		}
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
	 * @description: Construye un registro Quote a partir del mapa de una aseguradora, asignando
	 * nombre, status, pricebook, lookup de aseguradora (o nota si no existe el campo) y todos los
	 * campos de cobertura mediante put() dinamico.
	 * @param opportunityId: Id de la Opportunity padre del Quote.
	 * @param m: mapa con los datos de la aseguradora (nombre, prima, coberturas, etc.).
	 * @param nameToAseguradoraId: mapa nombre-de-aseguradora a Id de Aseguradora__c.
	 * @param stdPricebookId: Id del Pricebook estandar a asignar (puede ser null).
	 * @return el Quote construido en memoria (aun no insertado).
	 */
	@TestVisible
	private static Quote buildQuote(
		Id opportunityId,
		Map<String, Object> m,
		Map<String, Id> nameToAseguradoraId,
		Id stdPricebookId
	) {
		String nombre = stringOf(m.get('nombre'));
		String noCot = stringOf(m.get('no_cotizacion'));
		String quoteName = (String.isBlank(nombre) ? 'Cotización' : nombre) +
			(String.isBlank(noCot) ? '' : ' - ' + noCot);

		Quote q = new Quote();
		q.OpportunityId = opportunityId;
		q.Name = quoteName.left(255);
		q.Status = 'Draft';
		if (stdPricebookId != null) {
			q.Pricebook2Id = stdPricebookId;
		}
		String notas = stringOf(m.get('notas'));
		// Aseguradora__c no existe como lookup en Quote en el org actual; intentamos
		// asignarlo dinámicamente y, si falla, conservamos el nombre en Notas_IA__c.
		Id asegLookup = nameToAseguradoraId == null ? null : nameToAseguradoraId.get(nombre);
		if (asegLookup != null) {
			try {
				q.put('Aseguradora__c', asegLookup);
			} catch (Exception ignore) {
				notas = appendNote(notas, 'Aseguradora: ' + nombre);
			}
		} else if (String.isNotBlank(nombre)) {
			notas = appendNote(notas, 'Aseguradora: ' + nombre);
		}

		q.put('NumeroCotizacion__c', noCot);
		q.put('PrimaAnual__c', asDecimal(m.get('prima_anual')));
		q.put('SumaAsegurada__c', asDecimal(m.get('suma_asegurada')));
		q.put('TipoValor__c', stringOf(m.get('tipo_valor')));
		q.put('DeducibleDanos_Pct__c', asDecimal(m.get('deducible_danos_pct')));
		q.put('DeducibleDanos_Mxn__c', asDecimal(m.get('deducible_danos_mxn')));
		q.put('DeducibleRobo_Pct__c', asDecimal(m.get('deducible_robo_pct')));
		q.put('DeducibleRobo_Mxn__c', asDecimal(m.get('deducible_robo_mxn')));
		q.put('Cristales__c', asBoolean(m.get('cristales')));
		q.put('ResponsabilidadCivil__c', asDecimal(m.get('responsabilidad_civil')));
		q.put('GastosMedicos__c', asDecimal(m.get('gastos_medicos')));
		q.put('AsistenciaVial__c', asBoolean(m.get('asistencia_vial')));
		q.put('DefensaJuridica__c', asBoolean(m.get('defensa_juridica')));
		q.put('VidaConductor__c', asDecimal(m.get('vida_conductor')));
		q.put('RCExtranjero__c', asBoolean(m.get('rc_extranjero')));
		q.put('Notas_IA__c', notas == null ? '' : notas.left(32000));

		Date vigenciaFin = parseDate(stringOf(m.get('vigencia_fin')));
		if (vigenciaFin != null) {
			q.ExpirationDate = vigenciaFin;
		}
		return q;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Resuelve los nombres de aseguradoras a Ids de Aseguradora__c. Consulta las
	 * existentes por Name y crea las faltantes (insert parcial). Si el objeto no existe en el org
	 * o falla por permisos, devuelve el mapa con lo que se pudo resolver.
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
			acct = new Account(Name = clean.left(255));
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
}
