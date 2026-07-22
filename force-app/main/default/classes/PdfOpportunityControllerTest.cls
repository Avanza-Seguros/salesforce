@isTest
private class PdfOpportunityControllerTest {

  // Renderer falso para evitar la página Visualforce real en tests.
  public class MockPdfRenderer implements IPdfRenderer {
    public Blob renderToPdf(String htmlContent, String fileName) {
      return Blob.valueOf('test-pdf-' + (fileName == null ? '' : fileName));
    }
  }

  private static List<Id> uploadTwoPdfs(Id oppId, List<String> titles) {
    List<ContentVersion> cvs = new List<ContentVersion>();
    for (String t : titles) {
      cvs.add(
        new ContentVersion(
          Title = t,
          PathOnClient = t,
          VersionData = Blob.valueOf('pdf bytes ' + t),
          Origin = 'H'
        )
      );
    }
    insert cvs;
    Set<Id> cvIds = new Set<Id>();
    for (ContentVersion v : cvs) {
      cvIds.add(v.Id);
    }
    List<Id> docIds = new List<Id>();
    List<ContentDocumentLink> links = new List<ContentDocumentLink>();
    for (ContentVersion v : [
      SELECT Id, ContentDocumentId
      FROM ContentVersion
      WHERE Id IN :cvIds
    ]) {
      docIds.add(v.ContentDocumentId);
      links.add(
        new ContentDocumentLink(
          ContentDocumentId = v.ContentDocumentId,
          LinkedEntityId = oppId,
          ShareType = 'V',
          Visibility = 'AllUsers'
        )
      );
    }
    insert links;
    return docIds;
  }

  @isTest
  static void testUploadAndCreateDraftMultipleFiles() {
    String b64a = EncodingUtil.base64Encode(Blob.valueOf('pdf uno'));
    String b64b = EncodingUtil.base64Encode(Blob.valueOf('pdf dos'));

    Test.startTest();
    Map<String, Object> res = PdfOpportunityController.uploadAndCreateDraft(
      new List<String>{ 'cliente123_poliza.pdf', 'cliente123_cotizacion.pdf' },
      new List<String>{ b64a, b64b }
    );
    Test.stopTest();

    Id oppId = (Id) res.get('opportunityId');
    List<Id> docIds = (List<Id>) res.get('contentDocumentIds');
    System.assertNotEquals(null, oppId, 'Debe regresar la oportunidad borrador');
    System.assertEquals(2, docIds.size(), 'Debe regresar 2 ContentDocuments');

    Opportunity opp = [
      SELECT Id, Name
      FROM Opportunity
      WHERE Id = :oppId
    ];
    System.assert(
      opp.Name.contains('cliente123'),
      'El borrador conserva el prefijo común: ' + opp.Name
    );

    List<ContentDocumentLink> links = [
      SELECT Id
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :oppId AND ContentDocumentId IN :docIds
    ];
    System.assertEquals(
      2,
      links.size(),
      'Ambos PDFs deben quedar ligados a la oportunidad'
    );
  }

  @isTest
  static void testUploadRejectsSingleFile() {
    String b64 = EncodingUtil.base64Encode(Blob.valueOf('solo uno'));
    Test.startTest();
    try {
      PdfOpportunityController.uploadAndCreateDraft(
        new List<String>{ 'unico.pdf' },
        new List<String>{ b64 }
      );
      System.assert(false, 'Debe fallar con menos de 2 archivos');
    } catch (AuraHandledException e) {
      System.assert(true);
    }
    Test.stopTest();
  }

  @isTest
  static void testUploadRejectsNonMatchingPrefix() {
    String b64 = EncodingUtil.base64Encode(Blob.valueOf('contenido'));
    Test.startTest();
    try {
      PdfOpportunityController.uploadAndCreateDraft(
        new List<String>{ 'alfa.pdf', 'beta.pdf' },
        new List<String>{ b64, b64 }
      );
      System.assert(false, 'Debe fallar si los nombres no comparten prefijo');
    } catch (AuraHandledException e) {
      System.assert(true);
    }
    Test.stopTest();
  }

  @isTest
  static void testUploadRejectsMismatchedLists() {
    Test.startTest();
    try {
      PdfOpportunityController.uploadAndCreateDraft(
        new List<String>{ 'a.pdf', 'b.pdf' },
        new List<String>{ 'abc' }
      );
      System.assert(false, 'Debe fallar si los tamaños no coinciden');
    } catch (AuraHandledException e) {
      System.assert(true);
    }
    Test.stopTest();
  }

  @isTest
  static void testSharedFilenamePrefix() {
    System.assertEquals(
      'cliente123',
      PdfOpportunityController.sharedFilenamePrefix(
        new List<String>{
          'cliente123_poliza.pdf',
          'cliente123_cotizacion.pdf'
        }
      ),
      'Debe extraer el prefijo común recortando separadores'
    );
    System.assertEquals(
      '',
      PdfOpportunityController.sharedFilenamePrefix(
        new List<String>{ 'alfa.pdf', 'beta.pdf' }
      ),
      'Sin prefijo útil debe devolver vacío'
    );
    System.assertEquals(
      'mismonombre',
      PdfOpportunityController.sharedFilenamePrefix(
        new List<String>{ 'MismoNombre.pdf', 'mismonombre.PDF' }
      ),
      'La comparación es case-insensitive'
    );
  }

  @isTest
  static void testFoldNormalizesAccents() {
    System.assertEquals('danos', PdfOpportunityController.fold('Daños'));
    System.assertEquals(
      'gastos medicos',
      PdfOpportunityController.fold('Gastos  Médicos')
    );
  }

  @isTest
  static void testFindOrCreateAccount() {
    Test.startTest();
    Account created = PdfOpportunityController.findOrCreateAccount(
      'Cliente Nuevo SA'
    );
    Account reused = PdfOpportunityController.findOrCreateAccount(
      'Cliente Nuevo SA'
    );
    Test.stopTest();
    System.assertEquals(
      created.Id,
      reused.Id,
      'Debe reusar la cuenta existente por nombre'
    );
  }

  @isTest
  static void testSplitPersonName() {
    Map<String, String> single = PdfOpportunityController.splitPersonName(
      'Cliente'
    );
    System.assertEquals(null, single.get('first'));
    System.assertEquals('Cliente', single.get('last'));

    Map<String, String> three = PdfOpportunityController.splitPersonName(
      'Juan Pérez García'
    );
    System.assertEquals('Juan', three.get('first'));
    System.assertEquals('Pérez García', three.get('last'));

    Map<String, String> blank = PdfOpportunityController.splitPersonName('');
    System.assertEquals('Cliente', blank.get('last'));
  }

  @isTest
  static void testDefaultStageName() {
    String stage = PdfOpportunityController.defaultStageName();
    System.assertNotEquals(null, stage, 'Debe regresar un stage válido');
  }

  @isTest
  static void testParseFullComparisonJson() {
    String raw = '{"vehiculo":"Tank 500","cliente":"Juan","aseguradoras":[{"nombre":"GNP","prima_anual":1000}],"aviso":"x"}';
    Map<String, Object> parsed = PdfOpportunityController.parseFullComparisonJson(raw);
    System.assertEquals('Tank 500', parsed.get('vehiculo'));
    System.assertEquals('Juan', parsed.get('cliente'));
    List<Object> aseg = (List<Object>) parsed.get('aseguradoras');
    System.assertEquals(1, aseg.size());
    Map<String, Object> a = (Map<String, Object>) aseg[0];
    System.assertEquals('GNP', a.get('nombre'));
  }

  @isTest
  static void testParseFullComparisonJsonWithFences() {
    String fenced = '```json\n{"vehiculo":"X","aseguradoras":[]}\n```';
    Map<String, Object> parsed = PdfOpportunityController.parseFullComparisonJson(fenced);
    System.assertEquals('X', parsed.get('vehiculo'));
  }

  @isTest
  static void testParseFullComparisonJsonHandlesInvalid() {
    System.assertEquals(
      0,
      PdfOpportunityController.parseFullComparisonJson('').size(),
      'JSON vacío'
    );
    System.assertEquals(
      0,
      PdfOpportunityController.parseFullComparisonJson('no es json').size(),
      'Texto sin objeto'
    );
    System.assertEquals(
      0,
      PdfOpportunityController.parseFullComparisonJson('{ roto: }').size(),
      'JSON corrupto'
    );
  }

  @isTest
  static void testResolveAseguradoraLookupsSafeWhenObjectMissing() {
    // El org de test no tiene Aseguradora__c (o no hay permisos), por lo que el
    // mapa debe regresar vacío sin lanzar excepción.
    List<Object> input = new List<Object>{
      new Map<String, Object>{ 'nombre' => 'GNP' },
      new Map<String, Object>{ 'nombre' => 'AXA' }
    };
    Map<String, Id> result = PdfOpportunityController.resolveAseguradoraLookups(input);
    System.assertNotEquals(null, result, 'Nunca debe regresar null');
  }

  @isTest
  static void testCompareAndCreateQuotesValidations() {
    try {
      PdfOpportunityController.compareAndCreateQuotes(null, null);
      System.assert(false, 'Debe fallar sin identificadores');
    } catch (AuraHandledException e) {
      System.assert(true);
    }
    try {
      PdfOpportunityController.compareAndCreateQuotes(
        UserInfo.getUserId(),
        new List<Id>()
      );
      System.assert(false, 'Debe fallar con lista vacía');
    } catch (AuraHandledException e) {
      System.assert(true);
    }
  }

  @isTest
  static void testCompareAndCreateQuotesFromMock() {
    Opportunity opp = new Opportunity(
      Name = 'Borrador',
      StageName = PdfOpportunityController.defaultStageName(),
      CloseDate = Date.today().addMonths(1)
    );
    insert opp;

    // El JSON mock referencia PLACEHOLDER_FIRST_FILENAME y PLACEHOLDER_SECOND_FILENAME;
    // los reemplazamos en runtime con los títulos reales de los ContentDocument.
    List<Id> docIds = uploadTwoPdfs(
      opp.Id,
      new List<String>{
        'PLACEHOLDER_FIRST_FILENAME',
        'PLACEHOLDER_SECOND_FILENAME'
      }
    );

    PdfOpportunityController.pdfRenderer = new MockPdfRenderer();

    Test.startTest();
    Map<String, Object> res = PdfOpportunityController.compareAndCreateQuotes(
      opp.Id,
      docIds
    );
    Test.stopTest();

    System.assertEquals(opp.Id, res.get('opportunityId'));
    System.assertEquals('Great Wall Tank 500 2024', res.get('vehiculo'));
    System.assertEquals('Juan Pérez García', res.get('cliente'));
    System.assertEquals('Auto', res.get('ramo'));
    System.assertNotEquals(null, res.get('aviso'));

    List<Object> quotes = (List<Object>) res.get('quotes');
    System.assertEquals(2, quotes.size(), 'Debe haber 2 cotizaciones');

    List<Quote> persisted = [
      SELECT Id, Name, OpportunityId, PrimaAnual__c, SumaAsegurada__c, Cristales__c,
             RCExtranjero__c, NumeroCotizacion__c
      FROM Quote
      WHERE OpportunityId = :opp.Id
      ORDER BY PrimaAnual__c DESC
    ];
    System.assertEquals(2, persisted.size(), 'Se insertaron 2 Quotes');
    System.assertEquals(28500.50, persisted[0].PrimaAnual__c, 'GNP primero por prima descendente');
    System.assertEquals(true, persisted[0].Cristales__c);
    System.assertEquals(26800.00, persisted[1].PrimaAnual__c, 'AXA');
    System.assertEquals(true, persisted[1].RCExtranjero__c);
    System.assertEquals('GNP-998877', persisted[0].NumeroCotizacion__c);
    System.assert(
      persisted[0].Name.contains('GNP') && persisted[0].Name.contains('GNP-998877'),
      'Nombre del Quote concatena aseguradora + no_cotizacion: ' + persisted[0].Name
    );

    // Verifica que los PDFs originales se ligaron a sus Quotes correspondientes
    // sin crear nuevos ContentVersion: el ContentDocumentId queda compartido.
    List<ContentDocumentLink> quoteLinks = [
      SELECT Id, LinkedEntityId, ContentDocumentId
      FROM ContentDocumentLink
      WHERE LinkedEntityId IN :persisted
    ];
    System.assertEquals(2, quoteLinks.size(), 'Cada Quote tiene su PDF original linkeado');
    for (ContentDocumentLink l : quoteLinks) {
      System.assert(
        docIds.contains(l.ContentDocumentId),
        'El link reusa el ContentDocumentId original'
      );
    }

    // PDF comparativo
    Id comparativoDocId = (Id) res.get('comparativoPdfId');
    System.assertNotEquals(null, comparativoDocId, 'Debe regresar el id del PDF comparativo');
    List<ContentDocumentLink> compLinks = [
      SELECT Id
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :opp.Id AND ContentDocumentId = :comparativoDocId
    ];
    System.assertEquals(1, compLinks.size(), 'El PDF comparativo queda ligado a la Opp');

    Opportunity reloaded = [SELECT Id, Name, Description FROM Opportunity WHERE Id = :opp.Id];
    System.assert(
      reloaded.Name.contains('Great Wall Tank 500 2024') &&
        reloaded.Name.contains('Juan Pérez García'),
      'El nombre de la Opp combina vehículo y cliente: ' + reloaded.Name
    );
    System.assert(
      reloaded.Description.contains('Recomendación'),
      'La descripción incluye la recomendación en pocas palabras'
    );
  }

  @isTest
  static void testCompareAndCreateQuotesWithoutAseguradoraLookupKeepsNameInNotes() {
    Opportunity opp = new Opportunity(
      Name = 'Borrador',
      StageName = PdfOpportunityController.defaultStageName(),
      CloseDate = Date.today().addMonths(1)
    );
    insert opp;
    List<Id> docIds = uploadTwoPdfs(
      opp.Id,
      new List<String>{
        'PLACEHOLDER_FIRST_FILENAME',
        'PLACEHOLDER_SECOND_FILENAME'
      }
    );
    PdfOpportunityController.pdfRenderer = new MockPdfRenderer();

    Test.startTest();
    PdfOpportunityController.compareAndCreateQuotes(opp.Id, docIds);
    Test.stopTest();

    // Como el org de prueba no tiene Aseguradora__c lookup en Quote, el nombre
    // del seguro debe haber quedado preservado en Notas_IA__c como fallback.
    List<Quote> persisted = [
      SELECT Id, Notas_IA__c
      FROM Quote
      WHERE OpportunityId = :opp.Id
    ];
    Boolean foundGNP = false;
    Boolean foundAXA = false;
    for (Quote q : persisted) {
      String notas = q.Notas_IA__c == null ? '' : q.Notas_IA__c;
      if (notas.contains('GNP')) {
        foundGNP = true;
      }
      if (notas.contains('AXA')) {
        foundAXA = true;
      }
    }
    System.assert(
      foundGNP && foundAXA,
      'Los nombres de aseguradora deben quedar en Notas_IA__c cuando no hay lookup'
    );
  }
}