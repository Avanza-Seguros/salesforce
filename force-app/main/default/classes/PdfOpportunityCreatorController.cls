/**
 * Orquesta la creación de una Opportunity a partir de varios PDFs de cotizaciones.
 *
 * El proceso se divide en DOS llamadas (dos transacciones) a propósito:
 *  1) uploadAndCreateDraft     -> solo DML: crea la Opportunity borrador y sube los PDFs.
 *  2) compareAndCreateQuotes   -> compara las cotizaciones (Einstein si está disponible;
 *                                 si no, usa el ejemplo interno como respaldo), crea un
 *                                 Quote hijo por cotización con todos los datos de cobertura,
 *                                 genera un PDF comparativo y lo liga a la Opp.
 * Salesforce no permite hacer callouts después de un DML sin commit dentro de la misma
 * transacción, por eso el borrador se crea y persiste en el paso 1 antes de comparar.
 *
 * CAMBIOS recientes:
 *  - El paso 2 ahora devuelve TODOS los campos de cobertura al componente (antes solo 6),
 *    por lo que las tarjetas dejan de salir vacías.
 *  - El paso 2 detecta oportunidades duplicadas (mismo nombre/cuenta) y reutiliza la
 *    existente en lugar de crear otra.
 *  - El comparativo ya no usa datos de ejemplo: llama a un Prompt Template de Einstein con
 *    el texto de los PDFs (extraído en el navegador) y soporta N aseguradoras, no solo 2.
 *    Si Einstein no está configurado o falla, cae automáticamente al ejemplo interno para
 *    no romper el flujo.
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
    '{' +
      '"ramo":"Automoviles",' +
      '"vehiculo_detalle":{"marca":"BMW","modelo":"X3","anio":"2024","version":"sDrive20i","placa":"","serie":""},' +
      '"vehiculo":"BMW X3 sDrive20i 2024",' +
      '"cliente":{"nombre":"Cliente de Prueba","rfc":"","email":"","telefono":"","cp":"","direccion":""},' +
      '"aseguradoras":[' +
        '{"nombre":"GNP","plan":"Amplia","no_cotizacion":"GNP-001","archivo_origen":"PLACEHOLDER_FIRST_FILENAME","prima_anual":36998,"moneda":"MXN","vigencia_inicio":"2026-07-01","vigencia_fin":"2027-07-01","notas":"Requiere localizador para robo",' +
          '"coberturas":[' +
            '{"nombre":"Daños Materiales","suma_asegurada":948551,"deducible":"5%","coaseguro":""},' +
            '{"nombre":"Robo Total","suma_asegurada":948551,"deducible":"10%","coaseguro":""},' +
            '{"nombre":"Responsabilidad Civil","suma_asegurada":3000000,"deducible":"","coaseguro":""},' +
            '{"nombre":"Asistencia Vial","suma_asegurada":"Incluida","deducible":"","coaseguro":""}' +
          ']},' +
        '{"nombre":"HDI","plan":"HDI En Mi Auto","no_cotizacion":"HDI-002","archivo_origen":"PLACEHOLDER_SECOND_FILENAME","prima_anual":39160.87,"moneda":"MXN","vigencia_inicio":"2026-07-01","vigencia_fin":"2027-07-01","notas":"",' +
          '"coberturas":[' +
            '{"nombre":"Daños Materiales","suma_asegurada":795000,"deducible":"5%","coaseguro":""},' +
            '{"nombre":"Robo Total","suma_asegurada":795000,"deducible":"10%","coaseguro":""},' +
            '{"nombre":"Responsabilidad Civil","suma_asegurada":3000000,"deducible":"","coaseguro":""},' +
            '{"nombre":"Gastos Médicos Ocupantes","suma_asegurada":400000,"deducible":"","coaseguro":""}' +
          ']}' +
      '],' +
      '"recomendacion":{"ganadoras":[{"nombre":"GNP","etiqueta":"Mejor prima","porque":"Prima más baja con buena suma asegurada","a_cambio":"Requiere localizador para robo"}],' +
        '"guia_frecuencia":[{"riesgo":"Robo total","frecuencia":"Moderado","gana":"GNP","detalle":"GNP exige localizador"}],' +
        '"en_pocas_palabras":"GNP es la más económica; HDI ofrece buen equilibrio."},' +
      '"validacion":{"mismo_cliente":true,"mismo_vehiculo":true,"alerta":""},' +
      '"glosario":[{"termino":"Prima","definicion":"Lo que pagas al año por la cobertura."},{"termino":"Deducible","definicion":"Lo que pones de tu bolsa cuando hay siniestro."}],' +
      '"comparativo_html":"<html><body><h1>Comparativo de prueba</h1></body></html>",' +
      '"aviso":"Documento informativo de PRUEBA (mock), no es una póliza. Avanza Seguro."' +
    '}';

  // ============================================================
  // Paso 1: crear borrador + subir PDFs (solo DML, sin callouts)
  // ============================================================
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

  // ============================================================
  // Paso 2: comparar cotizaciones, crear Quotes hijas y PDF comparativo.
  // Usa Einstein si está configurado; si no, cae al ejemplo interno.
  // pdfTexts: texto de cada PDF extraído en el navegador, en el MISMO orden que
  //           contentDocumentIds. Puede llegar vacío (entonces se usa el respaldo).
  // ============================================================
  @AuraEnabled(cacheable=false)
  public static Map<String, Object> compareAndCreateQuotes(
    Id opportunityId,
    List<Id> contentDocumentIds,
    List<String> pdfTexts
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

    List<String> orderedTitles = new List<String>();
    for (Id docId : contentDocumentIds) {
      if (titlesById.containsKey(docId)) {
        orderedTitles.add(titlesById.get(docId));
      }
    }

    // === IA: pedimos a Einstein el comparativo (o usamos el respaldo) ===
    String rawJson = requestComparisonJson(orderedTitles, pdfTexts);

    // Sustitución de placeholders: solo afecta al ejemplo interno; en la respuesta
    // real de Einstein estos textos no existen y no se toca nada.
    if (orderedTitles.size() >= 1) {
      rawJson = rawJson.replace('PLACEHOLDER_FIRST_FILENAME', orderedTitles[0]);
    }
    if (orderedTitles.size() >= 2) {
      rawJson = rawJson.replace('PLACEHOLDER_SECOND_FILENAME', orderedTitles[1]);
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
      nombreOpp = nombreOpp.left(120);

      // === Prevención de duplicados ===
      // Si ya existe otra oportunidad con el mismo nombre (y cuenta), reutilizamos esa
      // en lugar de crear una nueva, y eliminamos el borrador vacío de este proceso.
      Opportunity dup = findDuplicateOpportunity(nombreOpp, accountId, opp.Id);
      Id targetOppId;
      String targetOppName;
      Boolean reused = false;

      if (dup != null) {
        reused = true;
        targetOppId = dup.Id;
        targetOppName = dup.Name;
        // Re-ligamos los PDFs subidos a la oportunidad existente.
        List<ContentDocumentLink> reLinks = new List<ContentDocumentLink>();
        for (Id docId : contentDocumentIds) {
          reLinks.add(
            new ContentDocumentLink(
              ContentDocumentId = docId,
              LinkedEntityId = dup.Id,
              ShareType = 'V',
              Visibility = 'AllUsers'
            )
          );
        }
        try {
          Database.insert(reLinks, false);
        } catch (Exception ignore) {
        }
        // Borramos el borrador vacío creado en el paso 1.
        try {
          delete opp;
        } catch (Exception ignore) {
        }
        aviso = appendNote(
          aviso,
          'Nota: ya existía una oportunidad para este cliente/vehículo; las cotizaciones se agregaron a la existente en lugar de crear una nueva.'
        );
      } else {
        targetOppId = opp.Id;
        opp.Name = nombreOpp;
        if (accountId != null) {
          opp.AccountId = accountId;
        }
        opp.Description = buildOpportunityDescription(aviso, recomendacion, accountWarning);
        applyOpportunityDefaults(opp);
        update opp;
        targetOppName = opp.Name;
      }

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
        quotesToInsert.add(buildQuote(targetOppId, m, nameToAseguradoraId, stdPricebookId));
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
        // IMPORTANTE: devolvemos TODOS los campos que la pantalla muestra, no solo prima/suma.
        // Antes solo se enviaban 6 datos y por eso las tarjetas salían casi vacías.
        quoteSummaries.add(
          new Map<String, Object>{
            'id' => q.Id,
            'name' => q.Name,
            'aseguradora' => stringOf(m.get('nombre')),
            'archivoOrigen' => archivoOrigen,
            'primaAnual' => m.get('prima_anual'),
            'sumaAsegurada' => m.get('suma_asegurada'),
            'tipoValor' => stringOf(m.get('tipo_valor')),
            'deducibleDanosPct' => m.get('deducible_danos_pct'),
            'deducibleDanosMxn' => m.get('deducible_danos_mxn'),
            'deducibleRoboPct' => m.get('deducible_robo_pct'),
            'deducibleRoboMxn' => m.get('deducible_robo_mxn'),
            'responsabilidadCivil' => m.get('responsabilidad_civil'),
            'gastosMedicos' => m.get('gastos_medicos'),
            'vidaConductor' => m.get('vida_conductor'),
            'cristales' => asBoolean(m.get('cristales')),
            'asistenciaVial' => asBoolean(m.get('asistencia_vial')),
            'defensaJuridica' => asBoolean(m.get('defensa_juridica')),
            'rcExtranjero' => asBoolean(m.get('rc_extranjero')),
            'notas' => stringOf(m.get('notas'))
          }
        );
      }
      if (!quoteLinks.isEmpty()) {
        insert quoteLinks;
      }

      Id comparativoDocId = renderAndLinkComparativo(
        comparativoHtml,
        vehiculo,
        targetOppId
      );

      return new Map<String, Object>{
        'opportunityId' => targetOppId,
        'opportunityName' => targetOppName,
        'reused' => reused,
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

  // ¿Estamos en modo prueba (sin llamar a Einstein)?
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
   * Pide a Einstein el JSON del comparativo a partir del texto de los PDFs.
   * Si no hay texto, si corre en test, o si Einstein falla / no está configurado,
   * devuelve el ejemplo interno (MOCK_COMPARISON_JSON) para no romper el flujo.
   *
   * El Prompt Template (PROMPT_TEMPLATE_API_NAME) debe estar instruido para devolver
   * EXCLUSIVAMENTE un JSON con la misma estructura del ejemplo (aseguradoras[], etc.).
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

  // Busca una oportunidad existente con el mismo nombre (y cuenta si la hay),
  // distinta del borrador actual. Devuelve null si no hay duplicado.
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

  // Si el objeto Aseguradora__c no existe en el org no podemos hacer SOQL/DML sobre él;
  // en ese caso devolvemos un mapa vacío y el nombre acaba en Notas_IA__c.
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
  private static String stringOf(Object o) {
    return o == null ? null : String.valueOf(o).trim();
  }

  private static String coalesce(String a, String b, String c) {
    if (String.isNotBlank(a)) {
      return a;
    }
    if (String.isNotBlank(b)) {
      return b;
    }
    return c == null ? '' : c;
  }

  private static String appendNote(String current, String addition) {
    if (String.isBlank(addition)) {
      return current;
    }
    if (String.isBlank(current)) {
      return addition;
    }
    return current + '\n' + addition;
  }

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
   * Devuelve el prefijo común (case-insensitive) de los nombres de archivo sin extensión.
   * Recorta separadores finales (`-`, `_`, `.`, espacio). Si el prefijo resultante es
   * menor a MIN_PREFIX_LENGTH, devuelve cadena vacía (no hay coincidencia útil).
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
   * Busca una cuenta por nombre. Si no existe, intenta crearla.
   *
   * Si el org tiene Person Accounts habilitados y un RecordType disponible con
   * IsPersonType=true, prefiere crear el registro como Person Account real
   * (FirstName + LastName + RecordTypeId). Esto evita validation rules
   * pensadas para Business Accounts (p. ej. AnnualRevenue obligatorio).
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
      'aviso' => stringOf(comparison.get('aviso'))
    };
  }

  // Solo lo que cambia entre aseguradoras (sin cliente ni vehículo).
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

  // Devuelve el objeto "detalle" del ramo tal cual lo manda la IA.
  // Respaldo: si llega el esquema viejo de auto (vehiculo_detalle), lo adapta.
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

  // Arma la tabla de coberturas { cobertura, sumaAsegurada, deducible, coaseguro }.
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

  // Una suma puede venir como número (850000) o como texto ("Incluida"): respetamos ambos.
  private static Object normalizeSuma(Object o) {
    if (o == null) { return null; }
    if (o instanceof String) {
      Decimal d = asDecimal(o);
      return (d != null) ? (Object) d : (Object) ((String) o);
    }
    return asDecimal(o);
  }

  // Datos del cliente, una sola vez. Acepta "cliente" como objeto o como texto (nombre).
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

  private static Map<String, Object> cobertura(String nombre, Decimal suma, String ded, String coa) {
    return new Map<String, Object>{
      'cobertura' => nombre,
      'sumaAsegurada' => suma,
      'deducible' => ded,
      'coaseguro' => coa
    };
  }

  private static Map<String, Object> coberturaTxt(String nombre, String texto) {
    return new Map<String, Object>{
      'cobertura' => nombre,
      'sumaAsegurada' => texto,
      'deducible' => '',
      'coaseguro' => ''
    };
  }

  private static String pctText(Object o) {
    Decimal d = asDecimal(o);
    return d == null ? '' : (String.valueOf(d) + '%');
  }

  private static String coalesceStr(String a, String b) {
    return String.isNotBlank(a) ? a : b;
  }

  // Traduce el ramo que devuelve la IA al valor exacto del picklist Ramo__c del LWC.
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

  // ============================================================
  // Crear las cotizaciones (Quotes) en la oportunidad ya guardada.
  // Solo inserta el Quote; la automatización del org crea QuoteLineItem y
  // Quote_Coverage__c. El Producto se busca por Aseguradora + Family(ramo).
  // ============================================================
  @AuraEnabled
  public static Integer crearCotizacionesDesdePdf(Id opportunityId, String quotesJson) {
    if (opportunityId == null || String.isBlank(quotesJson)) {
      return 0;
    }
    List<Object> raw;
    try {
      raw = (List<Object>) JSON.deserializeUntyped(quotesJson);
    } catch (Exception e) {
      throw new AuraHandledException('Cotizaciones con formato inválido: ' + e.getMessage());
    }
    if (raw == null || raw.isEmpty()) {
      return 0;
    }

    // Aseguradoras: resolver/crear Ids por nombre.
    Set<String> nombresAseg = new Set<String>();
    for (Object o : raw) {
      if (o instanceof Map<String, Object>) {
        String n = stringOf(((Map<String, Object>) o).get('compania'));
        if (String.isNotBlank(n)) { nombresAseg.add(n); }
      }
    }
    Map<String, Id> asegByName = resolveAseguradoraByName(nombresAseg);

    Id stdPb = getStandardPricebookId();
    List<Quote> toInsert = new List<Quote>();

    for (Object o : raw) {
      if (!(o instanceof Map<String, Object>)) { continue; }
      Map<String, Object> m = (Map<String, Object>) o;

      String compania = stringOf(m.get('compania'));
      String ramo = stringOf(m.get('ramo'));
      String plan = stringOf(m.get('plan'));
      String noCot = stringOf(m.get('noCotizacion'));
      Decimal prima = asDecimal(m.get('primaTotal'));

      Id asegId = asegByName.get(compania);
      Id productId = findProductByAseguradoraRamo(asegId, ramo);

      Quote q = new Quote();
      q.OpportunityId = opportunityId;
      String nm = (String.isBlank(compania) ? 'Cotización' : compania) +
                  (String.isBlank(plan) ? '' : ' - ' + plan);
      q.Name = nm.left(255);
      q.Status = 'Draft';
      if (stdPb != null) { q.Pricebook2Id = stdPb; }

      Date vig = parseDate(stringOf(m.get('vigencia')));
      if (vig != null) { q.ExpirationDate = vig; }

      // Campos del modelo (existen en tu org): Aseguradora__c y Product__c.
      if (asegId != null)    { q.put('Aseguradora__c', asegId); }
      if (productId != null) { q.put('Product__c', productId); }

      // Campos opcionales: se asignan solo si existen en el org (no rompen si faltan).
      setIfExists(q, 'NumeroCotizacion__c', noCot);
      setIfExists(q, 'Plan__c', plan);
      setIfExists(q, 'PrimaAnual__c', prima);
      setIfExists(q, 'Prima_Total__c', prima);

      toInsert.add(q);
    }

    try {
      if (!toInsert.isEmpty()) {
        insert toInsert; // la automatización crea QuoteLineItem + Quote_Coverage__c
      }
    } catch (Exception e) {
      System.debug('COT::: error insertando quotes -> ' + e.getMessage() + ' | ' + e.getStackTraceString());
      throw new AuraHandledException('No se pudieron crear las cotizaciones: ' + e.getMessage());
    }
    return toInsert.size();
  }

  // Busca el Producto por Aseguradora + Family(ramo). Si no hay match exacto por
  // ramo, cae a solo aseguradora. Devuelve null si no encuentra.
  @TestVisible
  private static Id findProductByAseguradoraRamo(Id asegId, String ramo) {
    if (asegId == null) { return null; }
    if (String.isNotBlank(ramo)) {
      List<Product2> conRamo = [
        SELECT Id FROM Product2
        WHERE IsActive = true AND Aseguradora__c = :asegId AND Family = :ramo
        LIMIT 1
      ];
      if (!conRamo.isEmpty()) { return conRamo[0].Id; }
    }
    List<Product2> soloAseg = [
      SELECT Id FROM Product2
      WHERE IsActive = true AND Aseguradora__c = :asegId
      LIMIT 1
    ];
    return soloAseg.isEmpty() ? null : soloAseg[0].Id;
  }

  // Resuelve/crea Aseguradora__c por nombre (versión que recibe nombres).
  @TestVisible
  private static Map<String, Id> resolveAseguradoraByName(Set<String> nombres) {
    Map<String, Id> result = new Map<String, Id>();
    if (nombres == null || nombres.isEmpty()) { return result; }
    Schema.SObjectType t = Schema.getGlobalDescribe().get('Aseguradora__c');
    if (t == null) { return result; }
    try {
      for (SObject so : Database.query('SELECT Id, Name FROM Aseguradora__c WHERE Name IN :nombres')) {
        result.put((String) so.get('Name'), (Id) so.get('Id'));
      }
      List<SObject> toIns = new List<SObject>();
      for (String n : nombres) {
        if (!result.containsKey(n)) {
          SObject s = t.newSObject();
          s.put('Name', n);
          toIns.add(s);
        }
      }
      if (!toIns.isEmpty()) {
        Database.SaveResult[] srs = Database.insert(toIns, false);
        for (Integer i = 0; i < srs.size(); i++) {
          if (srs[i].isSuccess()) {
            result.put((String) toIns[i].get('Name'), srs[i].getId());
          }
        }
      }
    } catch (Exception ignore) {
    }
    return result;
  }

  // Asigna un campo solo si existe en el org (evita errores si el campo no está).
  private static void setIfExists(SObject so, String field, Object value) {
    if (value == null) { return; }
    try {
      so.put(field, value);
    } catch (Exception ignore) {
      // El campo no existe en este org: lo omitimos.
    }
  }
}