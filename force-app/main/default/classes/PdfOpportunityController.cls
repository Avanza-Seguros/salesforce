/**
 * Orquesta la creación de una Opportunity a partir de varios PDFs analizados por IA.
 *
 * El proceso se divide en DOS llamadas (dos transacciones) a propósito:
 *  1) uploadAndCreateDraft  -> solo DML: crea la Opportunity borrador y sube todos los PDFs.
 *  2) analyzeAndPopulate    -> primero los callouts de IA (flows con prompt templates) por
 *                              cada documento y DESPUÉS el DML para poblar la oportunidad.
 * Salesforce no permite hacer callouts después de un DML sin commit dentro de la misma
 * transacción, por eso el borrador se crea y persiste en el paso 1 antes de analizar.
 */
public with sharing class PdfOpportunityController {
  private static final String ANALYSIS_FLOW = 'Analyze_Document_with_AI';
  private static final String EXTRACTION_FLOW = 'Extract_Document_Data_with_AI';
  private static final Integer MIN_PREFIX_LENGTH = 3;

  // ============================================================
  // Paso 1: crear borrador + subir PDFs (solo DML, sin callouts)
  // ============================================================
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
  // Paso 2: analizar con IA y poblar (callouts -> luego DML)
  // ============================================================
  @AuraEnabled
  public static Map<String, Object> analyzeAndPopulate(
    Id opportunityId,
    List<Id> contentDocumentIds
  ) {
    if (
      opportunityId == null ||
      contentDocumentIds == null ||
      contentDocumentIds.isEmpty()
    ) {
      throw new AuraHandledException(
        'Faltan identificadores para el análisis.'
      );
    }

    // Títulos por documento para etiquetar el análisis y el comparativo.
    Map<Id, String> titlesById = new Map<Id, String>();
    for (ContentDocument cd : [
      SELECT Id, Title
      FROM ContentDocument
      WHERE Id IN :contentDocumentIds
    ]) {
      titlesById.put(cd.Id, cd.Title);
    }

    // --- Callouts de IA primero (no debe haber DML sin commit antes de esto) ---
    List<DocAnalysis> perDoc = new List<DocAnalysis>();
    ExtractedData merged = new ExtractedData();
    Integer idx = 1;
    for (Id docId : contentDocumentIds) {
      String analysis = runAnalysisFlow(opportunityId, docId);
      String extractedJson = runExtractionFlow(docId);
      ExtractedData partial = parseExtraction(extractedJson);

      DocAnalysis da = new DocAnalysis();
      da.contentDocumentId = docId;
      da.title = titlesById.containsKey(docId)
        ? titlesById.get(docId)
        : 'Documento ' + idx;
      da.analysis = analysis;
      da.data = partial.toMap();
      perDoc.add(da);

      mergeInto(merged, partial);
      idx++;
    }
    String executiveSummary = buildExecutiveSummary(perDoc, merged);
    String combinedAnalysis = buildCombinedAnalysis(perDoc, executiveSummary);

    // --- Ahora sí, DML para poblar la oportunidad ---
    try {
      Opportunity opp = [
        SELECT Id, Name, AccountId, Amount, Description
        FROM Opportunity
        WHERE Id = :opportunityId
        LIMIT 1
      ];

      // La creación de cuenta es best-effort: si el org tiene validation rules
      // (p. ej. AnnualRevenue obligatorio), continuamos sin AccountId para que
      // la oportunidad se cree igual. El usuario puede ligar la cuenta luego.
      Id accountId = opp.AccountId;
      String accountWarning = '';
      if (String.isNotBlank(merged.nombreCliente)) {
        try {
          accountId = findOrCreateAccount(merged.nombreCliente).Id;
        } catch (Exception accountErr) {
          accountWarning =
            'No se pudo crear/buscar la cuenta "' +
            merged.nombreCliente +
            '" automáticamente: ' +
            accountErr.getMessage() +
            ' — la oportunidad se creó sin cuenta asociada.';
          System.debug(accountWarning);
        }
      }

      String descriptionAnalysis = combinedAnalysis;
      if (String.isNotBlank(accountWarning)) {
        descriptionAnalysis = '⚠️ ' + accountWarning + '\n\n' + combinedAnalysis;
      }
      applyExtraction(opp, merged, descriptionAnalysis, accountId);
      update opp;

      // Campos opcionales/custom en un DML tolerante a fallos (picklists, etc.)
      applyOptionalFields(opp.Id, merged);

      return new Map<String, Object>{
        'opportunityId' => opp.Id,
        'opportunityName' => opp.Name,
        'accountId' => accountId,
        'accountWarning' => accountWarning,
        'executiveSummary' => executiveSummary,
        'analysis' => combinedAnalysis,
        'data' => merged.toMap(),
        'documents' => perDoc
      };
    } catch (Exception e) {
      throw new AuraHandledException(
        'No se pudo crear/actualizar la oportunidad: ' + e.getMessage()
      );
    }
  }

  // ============================================================
  // Invocación de flows (callouts a los prompt templates de IA)
  // ============================================================
  @TestVisible
  private static String runAnalysisFlow(
    Id opportunityId,
    Id contentDocumentId
  ) {
    try {
      Flow.Interview flow = Flow.Interview.createInterview(
        ANALYSIS_FLOW,
        new Map<String, Object>{
          'opportunityId' => String.valueOf(opportunityId),
          'contentDocumentId' => String.valueOf(contentDocumentId)
        }
      );
      flow.start();
      Object result = flow.getVariableValue('analysisResult');
      return result == null ? '' : String.valueOf(result);
    } catch (Exception e) {
      throw new AuraHandledException(
        'Falló el análisis del documento con IA: ' + e.getMessage()
      );
    }
  }

  @TestVisible
  private static String runExtractionFlow(Id contentDocumentId) {
    try {
      Flow.Interview flow = Flow.Interview.createInterview(
        EXTRACTION_FLOW,
        new Map<String, Object>{
          'contentDocumentId' => String.valueOf(contentDocumentId)
        }
      );
      flow.start();
      Object result = flow.getVariableValue('extractedData');
      return result == null ? '' : String.valueOf(result);
    } catch (Exception e) {
      throw new AuraHandledException(
        'Falló la extracción de datos con IA: ' + e.getMessage()
      );
    }
  }

  // ============================================================
  // Helpers (testeables sin callouts)
  // ============================================================

  /**
   * Resumen ejecutivo: 3-5 líneas con cliente, ramo y, si aplica, la diferencia
   * de prima entre los documentos. Se muestra como cabecera tanto en la UI
   * como en el campo Description del registro.
   */
  @TestVisible
  private static String buildExecutiveSummary(
    List<DocAnalysis> docs,
    ExtractedData merged
  ) {
    if (docs == null || docs.isEmpty()) {
      return '';
    }
    String cliente = String.isNotBlank(merged.nombreCliente)
      ? merged.nombreCliente
      : 'el cliente';
    String ramo = String.isNotBlank(merged.ramo)
      ? ' (ramo ' + merged.ramo + ')'
      : '';
    String s = 'Se analizaron ' +
      docs.size() +
      ' documentos para ' +
      cliente +
      ramo +
      '.\n';
    for (DocAnalysis d : docs) {
      List<String> details = new List<String>();
      String tipo = asMapString(d.data, 'tipoDocumento');
      String aseg = asMapString(d.data, 'aseguradora');
      String prima = asMapString(d.data, 'prima');
      String moneda = asMapString(d.data, 'moneda');
      if (String.isNotBlank(tipo)) {
        details.add(tipo);
      }
      if (String.isNotBlank(aseg)) {
        details.add('Aseguradora: ' + aseg);
      }
      if (String.isNotBlank(prima)) {
        details.add(
          'Prima: ' +
            (String.isNotBlank(moneda) ? moneda + ' ' : '') +
            prima
        );
      }
      String line = '• ' + d.title;
      if (!details.isEmpty()) {
        line += ' — ' + String.join(details, '; ');
      }
      s += line + '\n';
    }
    if (docs.size() == 2) {
      Decimal p1 = primaDec(docs[0]);
      Decimal p2 = primaDec(docs[1]);
      if (p1 != null && p2 != null && p1 != p2) {
        Decimal diff = p1 > p2 ? p1 - p2 : p2 - p1;
        String mejor = p1 < p2 ? docs[0].title : docs[1].title;
        s +=
          '\nDiferencia de prima: ' +
          diff +
          '. Opción más económica: ' +
          mejor +
          '.';
      }
    }
    return s.trim();
  }

  private static String asMapString(Map<String, Object> m, String key) {
    if (m == null) {
      return null;
    }
    Object v = m.get(key);
    return v == null ? null : String.valueOf(v).trim();
  }

  private static Decimal primaDec(DocAnalysis d) {
    if (d == null || d.data == null) {
      return null;
    }
    Object o = d.data.get('prima');
    if (o == null) {
      return null;
    }
    if (o instanceof Decimal) {
      return (Decimal) o;
    }
    try {
      String s = String.valueOf(o).replaceAll('[^0-9.\\-]', '');
      return String.isBlank(s) ? null : Decimal.valueOf(s);
    } catch (Exception e) {
      return null;
    }
  }

  /**
   * Arma el texto del "Análisis IA" combinado para persistir en Description:
   * resumen ejecutivo + tabla markdown del comparativo + análisis prosa por doc.
   */
  @TestVisible
  private static String buildCombinedAnalysis(
    List<DocAnalysis> docs,
    String executiveSummary
  ) {
    if (docs == null || docs.isEmpty()) {
      return '';
    }
    String s = '';
    if (String.isNotBlank(executiveSummary)) {
      s += '=== RESUMEN EJECUTIVO ===\n' + executiveSummary + '\n\n';
    }
    if (docs.size() >= 2) {
      s += '=== COMPARATIVO ===\n';
      s += buildComparisonTable(docs);
    }
    for (DocAnalysis d : docs) {
      s += '\n=== ' + d.title + ' ===\n';
      s += String.isBlank(d.analysis)
        ? '(Sin análisis disponible para este documento.)'
        : d.analysis;
      s += '\n';
    }
    return s;
  }

  /** Tabla markdown con un campo por fila y un documento por columna. */
  @TestVisible
  private static String buildComparisonTable(List<DocAnalysis> docs) {
    List<List<String>> fieldDefs = comparisonFieldLabels();
    String header = '| Campo';
    String sep = '| ---';
    for (DocAnalysis d : docs) {
      header += ' | ' + d.title;
      sep += ' | ---';
    }
    String table = header + ' |\n' + sep + ' |\n';
    for (List<String> def : fieldDefs) {
      String field = def[0];
      String label = def[1];
      String row = '| ' + label;
      for (DocAnalysis d : docs) {
        Object v = d.data == null ? null : d.data.get(field);
        String cell = (v == null || String.valueOf(v).trim().length() == 0)
          ? '—'
          : String.valueOf(v);
        row += ' | ' + cell;
      }
      table += row + ' |\n';
    }
    return table;
  }

  private static List<List<String>> comparisonFieldLabels() {
    return new List<List<String>>{
      new List<String>{ 'tipoDocumento', 'Tipo' },
      new List<String>{ 'nombreCliente', 'Cliente' },
      new List<String>{ 'aseguradora', 'Aseguradora' },
      new List<String>{ 'ramo', 'Ramo' },
      new List<String>{ 'numeroPoliza', 'No. Póliza' },
      new List<String>{ 'numeroCotizacion', 'No. Cotización' },
      new List<String>{ 'prima', 'Prima' },
      new List<String>{ 'sumaAsegurada', 'Suma asegurada' },
      new List<String>{ 'moneda', 'Moneda' },
      new List<String>{ 'vigenciaInicio', 'Vigencia inicio' },
      new List<String>{ 'vigenciaFin', 'Vigencia fin' },
      new List<String>{ 'correoCliente', 'Correo' },
      new List<String>{ 'telefonoCliente', 'Teléfono' }
    };
  }

  /** Combina la extracción de un documento adicional dentro del acumulador, prefiriendo valores no vacíos. */
  @TestVisible
  private static void mergeInto(ExtractedData target, ExtractedData src) {
    if (src == null) {
      return;
    }
    target.esDocumentoValido = target.esDocumentoValido && src.esDocumentoValido;
    target.tipoDocumento = pickString(target.tipoDocumento, src.tipoDocumento);
    target.nombreCliente = pickString(target.nombreCliente, src.nombreCliente);
    target.correoCliente = pickString(target.correoCliente, src.correoCliente);
    target.telefonoCliente = pickString(
      target.telefonoCliente,
      src.telefonoCliente
    );
    target.aseguradora = pickString(target.aseguradora, src.aseguradora);
    target.ramo = pickString(target.ramo, src.ramo);
    target.numeroPoliza = pickString(target.numeroPoliza, src.numeroPoliza);
    target.numeroCotizacion = pickString(
      target.numeroCotizacion,
      src.numeroCotizacion
    );
    target.prima = target.prima != null ? target.prima : src.prima;
    target.sumaAsegurada = target.sumaAsegurada != null
      ? target.sumaAsegurada
      : src.sumaAsegurada;
    target.moneda = pickString(target.moneda, src.moneda);
    target.vigenciaInicio = pickString(
      target.vigenciaInicio,
      src.vigenciaInicio
    );
    target.vigenciaFin = pickString(target.vigenciaFin, src.vigenciaFin);
    target.resumen = pickString(target.resumen, src.resumen);
  }

  private static String pickString(String current, String incoming) {
    if (String.isNotBlank(current)) {
      return current;
    }
    return String.isBlank(incoming) ? current : incoming;
  }

  /** Limpia la respuesta de la IA y la convierte en datos estructurados. */
  @TestVisible
  private static ExtractedData parseExtraction(String raw) {
    ExtractedData data = new ExtractedData();
    if (String.isBlank(raw)) {
      return data;
    }
    String payload = raw.trim();
    // Quitar posibles fences de Markdown (bloques de codigo).
    if (payload.startsWith('```')) {
      payload = payload.replaceFirst('^```[a-zA-Z]*', '').trim();
      if (payload.endsWith('```')) {
        payload = payload.substring(0, payload.length() - 3).trim();
      }
    }
    // Quedarnos solo con el objeto JSON { ... }
    Integer start = payload.indexOf('{');
    Integer last = payload.lastIndexOf('}');
    if (start < 0 || last < start) {
      return data;
    }
    payload = payload.substring(start, last + 1);

    try {
      Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(
        payload
      );
      Object validObj = m.get('esDocumentoValido');
      data.esDocumentoValido = (validObj == null)
        ? true
        : Boolean.valueOf(String.valueOf(validObj));
      data.tipoDocumento = asString(m.get('tipoDocumento'));
      data.nombreCliente = asString(m.get('nombreCliente'));
      data.correoCliente = asString(m.get('correoCliente'));
      data.telefonoCliente = asString(m.get('telefonoCliente'));
      data.aseguradora = asString(m.get('aseguradora'));
      data.ramo = asString(m.get('ramo'));
      data.numeroPoliza = asString(m.get('numeroPoliza'));
      data.numeroCotizacion = asString(m.get('numeroCotizacion'));
      data.prima = asDecimal(m.get('prima'));
      data.sumaAsegurada = asDecimal(m.get('sumaAsegurada'));
      data.moneda = asString(m.get('moneda'));
      data.vigenciaInicio = asString(m.get('vigenciaInicio'));
      data.vigenciaFin = asString(m.get('vigenciaFin'));
      data.resumen = asString(m.get('resumen'));
    } catch (Exception e) {
      // JSON inválido: devolvemos lo que se haya podido (data vacío) sin romper el flujo.
      data.resumen = 'No se pudo interpretar la respuesta de la IA.';
    }
    return data;
  }

  /** Asigna a la oportunidad los datos extraídos (sin DML). */
  @TestVisible
  private static void applyExtraction(
    Opportunity opp,
    ExtractedData data,
    String analysis,
    Id accountId
  ) {
    if (String.isNotBlank(data.nombreCliente)) {
      opp.Name = data.nombreCliente.left(120);
    }
    if (accountId != null) {
      opp.AccountId = accountId;
    }
    Decimal amount = data.prima != null ? data.prima : data.sumaAsegurada;
    if (amount != null) {
      opp.Amount = amount;
    }
    opp.Description = buildDescription(data, analysis);
  }

  /**
   * Campos custom/opcionales en DML aparte para que un valor inválido no rompa todo.
   * Mapea el "ramo" extraído por la IA al valor real del picklist Ramo__c
   * (insensible a mayúsculas/acentos) antes de asignarlo.
   */
  @TestVisible
  private static void applyOptionalFields(
    Id opportunityId,
    ExtractedData data
  ) {
    String resolvedRamo = resolveRamoPicklist(data.ramo);
    if (String.isBlank(resolvedRamo) && String.isBlank(data.correoCliente)) {
      return;
    }
    try {
      Opportunity opp = new Opportunity(Id = opportunityId);
      if (String.isNotBlank(resolvedRamo)) {
        opp.put('Ramo__c', resolvedRamo);
      }
      if (String.isNotBlank(data.correoCliente)) {
        opp.put('Correo__c', data.correoCliente);
      }
      update opp;
    } catch (Exception e) {
      // Valores no válidos para los campos del org: se ignoran (ya quedaron en Description).
      System.debug('Campos opcionales no aplicados: ' + e.getMessage());
    }
  }

  /** Devuelve el API name del picklist Ramo__c que mejor coincide, o null. */
  @TestVisible
  private static String resolveRamoPicklist(String aiValue) {
    if (String.isBlank(aiValue)) {
      return null;
    }
    String target = fold(aiValue);
    List<Schema.PicklistEntry> entries = Opportunity.Ramo__c.getDescribe()
      .getPicklistValues();

    // 1) Coincidencia exacta (insensible a mayúsculas/acentos) contra value o label
    for (Schema.PicklistEntry e : entries) {
      if (!e.isActive()) {
        continue;
      }
      if (
        fold(e.getValue()).equals(target) ||
        fold(e.getLabel()).equals(target)
      ) {
        return e.getValue();
      }
    }
    // 2) Coincidencia por contención (ej. "Seguro de Auto" -> "Auto")
    for (Schema.PicklistEntry e : entries) {
      if (!e.isActive()) {
        continue;
      }
      String fv = fold(e.getValue());
      String fl = fold(e.getLabel());
      if (
        target.contains(fv) ||
        fv.contains(target) ||
        target.contains(fl) ||
        fl.contains(target)
      ) {
        return e.getValue();
      }
    }
    return null;
  }

  /** Normaliza para comparar: minúsculas + acentos eliminados + espacios colapsados. */
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
    // Recortar separadores finales
    while (
      prefix.length() > 0 &&
      '._- '.indexOf(prefix.substring(prefix.length() - 1)) >= 0
    ) {
      prefix = prefix.substring(0, prefix.length() - 1);
    }
    return prefix.length() >= MIN_PREFIX_LENGTH ? prefix : '';
  }

  /**
   * Busca una cuenta por nombre. Si no existe, intenta crearla.
   *
   * Si el org tiene Person Accounts habilitados y un RecordType disponible con
   * IsPersonType=true, prefiere crear el registro como Person Account real
   * (FirstName + LastName + RecordTypeId). Esto evita validation rules
   * pensadas para Business Accounts (p. ej. AnnualRevenue obligatorio).
   *
   * Si Person Accounts no está disponible, hace fallback a un Business Account
   * tradicional con solo el Name (puede fallar por validation rules del org;
   * la captura ocurre arriba en analyzeAndPopulate).
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
   * Devuelve el Id del RecordType de Person Account activo y disponible para el
   * usuario actual, o null. Consultamos RecordType directamente (en vez de usar
   * RecordTypeInfo.isPersonType, que requiere API v55+ del Apex class) para que
   * funcione independientemente de la versión de la clase.
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

  /** Divide "Juan Pérez García" en first/last para un Person Account. */
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

  @TestVisible
  private static String buildDescription(ExtractedData data, String analysis) {
    String s = '=== DATOS EXTRAÍDOS POR IA ===\n';
    s += 'Tipo de documento: ' + nv(data.tipoDocumento) + '\n';
    s += 'Cliente: ' + nv(data.nombreCliente) + '\n';
    s += 'Aseguradora: ' + nv(data.aseguradora) + '\n';
    s += 'Ramo: ' + nv(data.ramo) + '\n';
    s += 'No. Póliza: ' + nv(data.numeroPoliza) + '\n';
    s += 'No. Cotización: ' + nv(data.numeroCotizacion) + '\n';
    s +=
      'Prima: ' +
      nv(data.prima == null ? null : String.valueOf(data.prima)) +
      '\n';
    s +=
      'Suma asegurada: ' +
      nv(
        data.sumaAsegurada == null ? null : String.valueOf(data.sumaAsegurada)
      ) +
      '\n';
    s += 'Moneda: ' + nv(data.moneda) + '\n';
    s +=
      'Vigencia: ' +
      nv(data.vigenciaInicio) +
      ' a ' +
      nv(data.vigenciaFin) +
      '\n';
    s += 'Correo: ' + nv(data.correoCliente) + '\n';
    s += 'Teléfono: ' + nv(data.telefonoCliente) + '\n';
    if (String.isNotBlank(data.resumen)) {
      s += '\nResumen: ' + data.resumen + '\n';
    }
    if (String.isNotBlank(analysis)) {
      s += '\n=== ANÁLISIS COMPLETO (IA) ===\n' + analysis;
    }
    return s.left(32000);
  }

  private static String nv(String v) {
    return String.isBlank(v) ? '—' : v;
  }

  private static String asString(Object o) {
    return o == null ? null : String.valueOf(o).trim();
  }

  private static Decimal asDecimal(Object o) {
    if (o == null) {
      return null;
    }
    try {
      String s = String.valueOf(o).replaceAll('[^0-9.\\-]', '');
      return String.isBlank(s) ? null : Decimal.valueOf(s);
    } catch (Exception e) {
      return null;
    }
  }

  // ============================================================
  // Wrapper de datos extraídos
  // ============================================================
  public class ExtractedData {
    @AuraEnabled
    public Boolean esDocumentoValido = true;
    @AuraEnabled
    public String tipoDocumento;
    @AuraEnabled
    public String nombreCliente;
    @AuraEnabled
    public String correoCliente;
    @AuraEnabled
    public String telefonoCliente;
    @AuraEnabled
    public String aseguradora;
    @AuraEnabled
    public String ramo;
    @AuraEnabled
    public String numeroPoliza;
    @AuraEnabled
    public String numeroCotizacion;
    @AuraEnabled
    public Decimal prima;
    @AuraEnabled
    public Decimal sumaAsegurada;
    @AuraEnabled
    public String moneda;
    @AuraEnabled
    public String vigenciaInicio;
    @AuraEnabled
    public String vigenciaFin;
    @AuraEnabled
    public String resumen;

    public Map<String, Object> toMap() {
      return new Map<String, Object>{
        'esDocumentoValido' => esDocumentoValido,
        'tipoDocumento' => tipoDocumento,
        'nombreCliente' => nombreCliente,
        'correoCliente' => correoCliente,
        'telefonoCliente' => telefonoCliente,
        'aseguradora' => aseguradora,
        'ramo' => ramo,
        'numeroPoliza' => numeroPoliza,
        'numeroCotizacion' => numeroCotizacion,
        'prima' => prima,
        'sumaAsegurada' => sumaAsegurada,
        'moneda' => moneda,
        'vigenciaInicio' => vigenciaInicio,
        'vigenciaFin' => vigenciaFin,
        'resumen' => resumen
      };
    }
  }

  /** Snapshot del análisis y datos extraídos de UN documento, para alimentar el LWC. */
  public class DocAnalysis {
    @AuraEnabled
    public Id contentDocumentId;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String analysis;
    @AuraEnabled
    public Map<String, Object> data;
  }
}