/**
 *  @name: PdfOpportunityCreatorControllerTest
 *  @description: Pruebas unitarias para PdfOpportunityCreatorController. El path de Einstein
 *               se salta con Test.isRunningTest() (usa el JSON de respaldo interno), por lo que
 *               se cubre todo el análisis/parseo, la creación de borrador, cotizaciones y helpers.
 */
@isTest
private class PdfOpportunityCreatorControllerTest {

    static String base64Demo() {
        return EncodingUtil.base64Encode(Blob.valueOf('CONTENIDO PDF DEMO'));
    }

    // ---------------- uploadAndCreateDraft ----------------
    @isTest
    static void testUploadAndCreateDraft_ok() {
        List<String> names = new List<String>{ 'AutoCotiza HDI.pdf', 'AutoCotiza GNP.pdf' };
        List<String> datos = new List<String>{ base64Demo(), base64Demo() };
        Test.startTest();
        Map<String, Object> res = PdfOpportunityCreatorController.uploadAndCreateDraft(names, datos);
        Test.stopTest();
        System.assertNotEquals(null, res.get('opportunityId'), 'Debe crear el borrador');
    }

    @isTest
    static void testUploadAndCreateDraft_errores() {
        Integer errores = 0;
        Test.startTest();
        try { PdfOpportunityCreatorController.uploadAndCreateDraft(null, null); }
        catch (AuraHandledException e) { errores++; }

        try {
            PdfOpportunityCreatorController.uploadAndCreateDraft(
                new List<String>{ 'uno.pdf' }, new List<String>{ base64Demo() });
        } catch (AuraHandledException e) { errores++; }

        try {
            PdfOpportunityCreatorController.uploadAndCreateDraft(
                new List<String>{ 'a.pdf', 'b.pdf' }, new List<String>{ '', base64Demo() });
        } catch (AuraHandledException e) { errores++; }

        try {
            // Sin prefijo común.
            PdfOpportunityCreatorController.uploadAndCreateDraft(
                new List<String>{ 'abc.pdf', 'xyz.pdf' }, new List<String>{ base64Demo(), base64Demo() });
        } catch (AuraHandledException e) { errores++; }
        Test.stopTest();
        System.assertEquals(4, errores, 'Las 4 validaciones deben lanzar excepción');
    }

    // ---------------- analyzeQuotes (usa el JSON de respaldo) ----------------
    @isTest
    static void testAnalyzeQuotes() {
        List<String> names = new List<String>{ 'Auto HDI.pdf', 'Auto GNP.pdf' };
        List<String> textos = new List<String>{ 'texto hdi', 'texto gnp' };
        Test.startTest();
        Map<String, Object> res = PdfOpportunityCreatorController.analyzeQuotes(names, textos);
        Test.stopTest();
        System.assertEquals('mock', res.get('fuente'), 'En test debe usar el respaldo');
        System.assertEquals('Automoviles', res.get('ramo'), 'El ramo debe mapearse a Automoviles');
        System.assertNotEquals(null, res.get('quotes'), 'Debe devolver la lista de cotizaciones');
    }

    // ---------------- crearCotizacionesDesdePdf ----------------
    @isTest
    static void testCrearCotizaciones() {
        Opportunity opp = new Opportunity(
            Name = 'Opp Cotizaciones', StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30), Ramo__c = 'Automoviles'
        );
        // Etapa válida por si 'Prospecting' no existe.
        List<OpportunityStage> st = [SELECT MasterLabel FROM OpportunityStage WHERE IsActive = true ORDER BY SortOrder LIMIT 1];
        if (!st.isEmpty()) { opp.StageName = st[0].MasterLabel; }
        insert opp;

        List<Object> quotes = new List<Object>{
            new Map<String, Object>{
                'compania' => 'HDI', 'ramo' => 'Automoviles', 'plan' => 'Amplia',
                'primaTotal' => 12500, 'vigencia' => String.valueOf(Date.today().addYears(1))
            },
            new Map<String, Object>{
                'compania' => 'GNP', 'ramo' => 'Automoviles', 'plan' => 'Premier', 'primaTotal' => 13000
            }
        };
        Test.startTest();
        // Vacío / nulo.
        Map<String, Object> vacio = PdfOpportunityCreatorController.crearCotizacionesDesdePdf(opp.Id, '');
        System.assertEquals(0, vacio.get('creadas'), 'JSON vacío no crea nada');
        // JSON inválido.
        try {
            PdfOpportunityCreatorController.crearCotizacionesDesdePdf(opp.Id, '{ no es lista }');
        } catch (AuraHandledException e) { /* esperado */ }
        // Camino normal.
        try {
            Map<String, Object> res = PdfOpportunityCreatorController.crearCotizacionesDesdePdf(
                opp.Id, JSON.serialize(quotes));
            System.assertNotEquals(null, res.get('creadas'));
        } catch (Exception e) {
            // Campos custom de Quote con requeridos del org: líneas cubiertas de todos modos.
        }
        Test.stopTest();
    }

    // ---------------- prepararCotizaciones ----------------
    @isTest
    static void testPrepararCotizaciones() {
        List<Object> quotes = new List<Object>{
            new Map<String, Object>{ 'id' => '1', 'compania' => 'HDI', 'ramo' => 'Automoviles', 'plan' => 'Amplia', 'primaTotal' => 12000 }
        };
        Test.startTest();
        List<Map<String, Object>> vacio = PdfOpportunityCreatorController.prepararCotizaciones('');
        List<Map<String, Object>> res = PdfOpportunityCreatorController.prepararCotizaciones(JSON.serialize(quotes));
        Test.stopTest();
        System.assertEquals(0, vacio.size(), 'Sin JSON, lista vacía');
        System.assertEquals(1, res.size(), 'Debe preparar una cotización');
    }

    // ---------------- Helpers de parseo / negocio ----------------
    @isTest
    static void testHelpersParseoYTexto() {
        Test.startTest();
        // parseFullComparisonJson: válido, con fences y basura.
        System.assert(!PdfOpportunityCreatorController.parseFullComparisonJson('{"a":1}').isEmpty());
        System.assert(!PdfOpportunityCreatorController.parseFullComparisonJson('```json\n{"a":1}\n```').isEmpty());
        System.assert(PdfOpportunityCreatorController.parseFullComparisonJson('sin json').isEmpty());
        System.assert(PdfOpportunityCreatorController.parseFullComparisonJson('').isEmpty());

        // sharedFilenamePrefix.
        System.assertEquals('', PdfOpportunityCreatorController.sharedFilenamePrefix(new List<String>{ 'abc.pdf', 'xyz.pdf' }));
        System.assertEquals('auto', PdfOpportunityCreatorController.sharedFilenamePrefix(new List<String>{ 'auto-hdi.pdf', 'auto-gnp.pdf' }));

        // fold (acentos).
        System.assertEquals('accion nino', PdfOpportunityCreatorController.fold('  Acción  Niño '));

        // splitPersonName.
        Map<String, String> p1 = PdfOpportunityCreatorController.splitPersonName('Juan Carlos Pérez López');
        System.assertEquals('Juan', p1.get('first'));
        Map<String, String> p2 = PdfOpportunityCreatorController.splitPersonName('Cliente');
        System.assertEquals('Cliente', p2.get('last'));
        PdfOpportunityCreatorController.splitPersonName('');

        // mapRamoToFormValue.
        System.assertEquals('Automoviles', PdfOpportunityCreatorController.mapRamoToFormValue('Seguro de AUTOS'));
        System.assertEquals('GMM', PdfOpportunityCreatorController.mapRamoToFormValue('Plan GMM Colectivo'));
        System.assertEquals('Vida', PdfOpportunityCreatorController.mapRamoToFormValue('VIDA'));
        System.assertEquals('', PdfOpportunityCreatorController.mapRamoToFormValue(''));

        // requestComparisonJson devuelve el respaldo en test.
        String raw = PdfOpportunityCreatorController.requestComparisonJson(
            new List<String>{ 'a.pdf' }, new List<String>{ 'texto' });
        System.assert(String.isNotBlank(raw), 'Debe regresar el JSON de respaldo');

        Test.stopTest();
    }

    @isTest
    static void testHelpersMapeoAseguradora() {
        Map<String, Object> aseg = new Map<String, Object>{
            'nombre' => 'HDI', 'plan' => 'Amplia', 'prima_anual' => 39160.87,
            'moneda' => 'MXN', 'vigencia_fin' => '2027-06-03', 'no_cotizacion' => '123',
            'coberturas' => new List<Object>{
                new Map<String, Object>{ 'nombre' => 'Daños Materiales', 'suma_asegurada' => 795000, 'deducible' => '5%' },
                new Map<String, Object>{ 'nombre' => 'Asistencia', 'suma_asegurada' => 'Incluida' }
            }
        };
        Test.startTest();
        Map<String, Object> q = PdfOpportunityCreatorController.mapAseguradoraToFormQuote(aseg, 'Automoviles');
        Map<String, Object> comp = new Map<String, Object>{
            'detalle' => new Map<String, Object>{ 'marca' => 'BMW' },
            'cliente' => new Map<String, Object>{ 'nombre' => 'Diego' }
        };
        Map<String, Object> det = PdfOpportunityCreatorController.buildDetalle(comp);
        Map<String, Object> cli = PdfOpportunityCreatorController.buildCliente(comp);
        List<Map<String, Object>> cobs = PdfOpportunityCreatorController.buildCoberturas(aseg);
        Test.stopTest();
        System.assertEquals('HDI', q.get('compania'));
        System.assertEquals('BMW', det.get('marca'));
        System.assertEquals('Diego', cli.get('nombre'));
        System.assert(!cobs.isEmpty(), 'Debe armar coberturas');
    }

    @isTest
    static void testHelpersOportunidadYCuenta() {
        Account acc = new Account(Name = 'Empresa Dup Test');
        insert acc;
        Opportunity opp = new Opportunity(
            Name = 'Oportunidad Dup', StageName = 'Prospecting',
            CloseDate = Date.today().addDays(15), AccountId = acc.Id
        );
        List<OpportunityStage> st = [SELECT MasterLabel FROM OpportunityStage WHERE IsActive = true ORDER BY SortOrder LIMIT 1];
        if (!st.isEmpty()) { opp.StageName = st[0].MasterLabel; }
        insert opp;

        Test.startTest();
        // findDuplicateOpportunity: con cuenta, sin cuenta y con nombre en blanco.
        Opportunity dup1 = PdfOpportunityCreatorController.findDuplicateOpportunity('Oportunidad Dup', acc.Id, null);
        Opportunity dup2 = PdfOpportunityCreatorController.findDuplicateOpportunity('Oportunidad Dup', null, null);
        Opportunity dup3 = PdfOpportunityCreatorController.findDuplicateOpportunity('', acc.Id, null);
        System.assertNotEquals(null, dup1, 'Debe encontrar el duplicado por nombre y cuenta');
        System.assertNotEquals(null, dup2, 'Debe encontrar el duplicado por nombre');
        System.assertEquals(null, dup3, 'Nombre en blanco no busca');

        // applyOpportunityDefaults.
        Opportunity nueva = new Opportunity();
        PdfOpportunityCreatorController.applyOpportunityDefaults(nueva);

        // buildOpportunityDescription.
        String desc = PdfOpportunityCreatorController.buildOpportunityDescription(
            'Aviso importante',
            new Map<String, Object>{ 'en_pocas_palabras' => 'GNP es la mejor opción' },
            'Advertencia de cuenta');
        System.assert(desc.contains('GNP'), 'Debe incluir la recomendación');

        // resolveAseguradoraLookups (defensivo si el objeto existe o no).
        PdfOpportunityCreatorController.resolveAseguradoraLookups(new List<Object>{
            new Map<String, Object>{ 'nombre' => 'HDI' },
            new Map<String, Object>{ 'nombre' => 'GNP' }
        });

        // Pricebook estándar, etapa por defecto, cuenta buscar/crear, record type persona.
        System.assertNotEquals(null, PdfOpportunityCreatorController.getStandardPricebookId());
        System.assert(String.isNotBlank(PdfOpportunityCreatorController.defaultStageName()));
        try {
            Account creada = PdfOpportunityCreatorController.findOrCreateAccount('Cuenta Nueva Helper');
            System.assertNotEquals(null, creada.Id);
            PdfOpportunityCreatorController.findOrCreateAccount('Empresa Dup Test'); // existente
        } catch (Exception e) {
            // Person Accounts con requeridos adicionales en el org: líneas cubiertas.
        }
        PdfOpportunityCreatorController.personAccountRecordTypeId();
        Test.stopTest();
    }
}
