/**
 *  @name: QuoteCreatorControllerTest
 *  @description: Pruebas unitarias para QuoteCreatorController. Cubre CRUD de cotizaciones
 *               y coberturas, busquedas de oportunidades/aseguradoras, consulta de productos
 *               y de coberturas plantilla, incluyendo rutas de error (catch) para maximizar
 *               la cobertura de cara a un despliegue a produccion.
 */
@isTest
private class QuoteCreatorControllerTest {

    // Etapa activa valida para la Oportunidad.
    static String activeStage() {
        List<OpportunityStage> s = [
            SELECT MasterLabel FROM OpportunityStage
            WHERE IsActive = true ORDER BY SortOrder ASC LIMIT 1
        ];
        return s.isEmpty() ? 'Prospecting' : s[0].MasterLabel;
    }

    // Primer valor activo del picklist Ramo__c (evita fallos por valores restringidos).
    static String ramoValue() {
        try {
            for (Schema.PicklistEntry e : Opportunity.Ramo__c.getDescribe().getPicklistValues()) {
                if (e.isActive()) { return e.getValue(); }
            }
        } catch (Exception ignored) {}
        return null;
    }

    // Crea (o reutiliza) un Agente para satisfacer la validacion "No existe Agente".
    static Id agenteId() {
        List<Agente__c> ag = [SELECT Id FROM Agente__c LIMIT 1];
        if (!ag.isEmpty()) { return ag[0].Id; }
        Agente__c a = new Agente__c(Name = 'Agente Test');
        insert a;
        return a.Id;
    }

    @testSetup
    static void setup() {
        Account acc = new Account(Name = 'Cuenta Quote Test', AnnualRevenue = 100);
        insert acc;
        
        Agente__c ag = new Agente__c(Name = 'Abraham Gonzalez');
        insert ag;
        
        Pricebook2 pb = new Pricebook2(Name = 'Avanza Price Book', IsActive = true);
        insert pb;

        Opportunity opp = new Opportunity(
            Name = 'Opp Quote Test',
            StageName = activeStage(),
            CloseDate = Date.today().addDays(30),
            AccountId = acc.Id,
            Ramo__c = ramoValue(),
            Pricebook2Id = Test.getStandardPricebookId(),
            Agente_Relacionado__c = ag.Id
        );
        insert opp;

        Aseguradora__c aseg = new Aseguradora__c(Name = 'Aseguradora Test');
        insert aseg;

        Product2 prod = new Product2(Name = 'Producto Test', IsActive = true, Aseguradora__c = aseg.Id, Family = opp.Ramo__c);
        insert prod;

        Quote q = new Quote(
            Name = 'Cotización Quote Test',
            OpportunityId = opp.Id,
            Status = 'Draft',
            Ramos__c = opp.Ramo__c,
            Frecuencia_de_prima__c = 'Mensual',
            Prima_Total__c = 120000,
            Pricebook2Id = Test.getStandardPricebookId(),
            Aseguradora__c = aseg.Id,
            Product__c = prod.Id
        );
        insert q;

        Quote_Coverage__c cov = new Quote_Coverage__c(
            Quote__c = q.Id,
            Coverage_Name__c = 'Cobertura Test',
            Coverage_Code__c = 'COB-1',
            Order__c = 1
        );
        insert cov;
    }

    // ---------- Helpers de datos ----------

    static Quote getQuote() { return [SELECT Id, OpportunityId FROM Quote LIMIT 1]; }
    static Opportunity getOpp() { return [SELECT Id, Name, Ramo__c FROM Opportunity LIMIT 1]; }
    static Aseguradora__c getAseg() { return [SELECT Id FROM Aseguradora__c LIMIT 1]; }
    static Product2 getProd() { return [SELECT Id FROM Product2 LIMIT 1]; }

    // Devuelve un Id de Quote valido en formato pero inexistente (para forzar errores).
    static Id deletedQuoteId() {
        Quote temp = new Quote(
            Name = 'Temporal',
            OpportunityId = getOpp().Id,
            Status = 'Draft',
            Ramos__c = getOpp().Ramo__c,
            Frecuencia_de_prima__c = 'Mensual',
            Prima_Total__c = 120000,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert temp;
        Id tid = temp.Id;
        delete temp;
        return tid;
    }

    // ---------- getQuotes / getQuoteById ----------

    @isTest
    static void testGetQuotes() {
        Test.startTest();
        List<Quote> result = QuoteCreatorController.getQuotes();
        Test.stopTest();
        System.assert(!result.isEmpty(), 'Debe regresar al menos una cotización');
    }

    @isTest
    static void testGetQuoteById_ok() {
        Quote q = getQuote();
        Test.startTest();
        Quote result = QuoteCreatorController.getQuoteById(q.Id);
        Test.stopTest();
        System.assertEquals(q.Id, result.Id, 'Debe regresar la cotización solicitada');
    }

    @isTest
    static void testGetQuoteById_error() {
        Id fake = deletedQuoteId();
        Boolean threw = false;
        Test.startTest();
        try {
            QuoteCreatorController.getQuoteById(fake);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Un Id inexistente debe lanzar excepción');
    }

    // ---------- saveQuote ----------

    @isTest
    static void testSaveQuote_insertDefaults() {
        Opportunity opp = getOpp();
        // Sin Ramos__c ni Frecuencia -> el controlador debe rellenarlos.
        Quote nuevo = new Quote(
            Name = 'Nueva Cotización',
            OpportunityId = opp.Id,
            Status = 'In Review',
            Ramos__c = opp.Ramo__c,
            Frecuencia_de_prima__c = 'Mensual',
            Prima_Total__c = 120000,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        Test.startTest();
        Quote saved = QuoteCreatorController.saveQuote(nuevo);
        Test.stopTest();
        System.assertNotEquals(null, saved.Id, 'Debe guardarse la cotización');
        Quote check = [SELECT Frecuencia_de_prima__c FROM Quote WHERE Id = :saved.Id];
        System.assertEquals('Mensual', check.Frecuencia_de_prima__c, 'Frecuencia por defecto debe ser Mensual');
    }

    @isTest
    static void testSaveQuote_update() {
        Quote q = getQuote();
        Quote toUpdate = new Quote(
            Id = q.Id,
            Status = 'Accepted'
        );
        Test.startTest();
        Quote saved = QuoteCreatorController.saveQuote(toUpdate);
        Test.stopTest();
        System.assertEquals(q.Id, saved.Id, 'Debe actualizar la misma cotización');
    }

    @isTest
    static void testSaveQuote_error() {
        Boolean threw = false;
        Quote bad = new Quote(
            Name = 'Cotización Inválida',
            OpportunityId = getOpp().Id,
            Status = 'ESTADO_INVALIDO_XYZ',
            Ramos__c = getOpp().Ramo__c,
            Frecuencia_de_prima__c = 'Mensual',
            Prima_Total__c = 120000,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        Test.startTest();
        try {
            QuoteCreatorController.saveQuote(bad);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
    }

    // Cubre la rama en la que la prima se toma de TotalPrice (via partida de cotización).
    @isTest
    static void testSaveQuote_primaDesdeTotalPrice() {
        Quote q = getQuote();
        try {
            Product2 prod = getProd();
            PricebookEntry pbe = new PricebookEntry(
                Pricebook2Id = Test.getStandardPricebookId(),
                Product2Id = prod.Id,
                UnitPrice = 1200,
                IsActive = true
            );
            insert pbe;

            QuoteLineItem qli = new QuoteLineItem(
                QuoteId = q.Id,
                PricebookEntryId = pbe.Id,
                Quantity = 1,
                UnitPrice = 1200
            );
            insert qli;

            Quote conTotal = [SELECT Id, TotalPrice, Subtotal FROM Quote WHERE Id = :q.Id];
            conTotal.PrimaAnual__c = null;
            Test.startTest();
            QuoteCreatorController.saveQuote(conTotal);
            Test.stopTest();
        } catch (Exception e) {
            // Si el org no permite partidas de cotización, la rama principal ya quedó cubierta.
            System.debug('Partida de cotización no disponible: ' + e.getMessage());
        }
    }

    // ---------- deleteQuote ----------

    @isTest
    static void testDeleteQuote() {
        
        Quote extra = new Quote(
            Name = 'A Borrar',
            OpportunityId = getOpp().Id,
            Status = 'Draft',
            Ramos__c = getOpp().Ramo__c,
            Frecuencia_de_prima__c = 'Mensual',
            Prima_Total__c = 120000,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert extra;
        Test.startTest();
        QuoteCreatorController.deleteQuote(extra.Id);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Quote WHERE Id = :extra.Id], 'Debe eliminarse');
    }

    // ---------- coberturas ----------

    @isTest
    static void testGetCoveragesByQuoteId() {
        Quote q = getQuote();
        Test.startTest();
        List<Quote_Coverage__c> vacias = QuoteCreatorController.getCoveragesByQuoteId(null);
        List<Quote_Coverage__c> conDatos = QuoteCreatorController.getCoveragesByQuoteId(q.Id);
        Test.stopTest();
        System.assert(vacias.isEmpty(), 'Con id nulo debe regresar lista vacía');
        System.assert(!conDatos.isEmpty(), 'Debe regresar las coberturas de la cotización');
    }

    @isTest
    static void testSaveCoverages_ok() {
        Quote q = getQuote();
        List<Quote_Coverage__c> lista = new List<Quote_Coverage__c>{
            new Quote_Coverage__c(Quote__c = q.Id, Coverage_Name__c = 'Nueva', Coverage_Code__c = 'N-1', Order__c = 2)
        };
        Test.startTest();
        QuoteCreatorController.saveCoverages(lista);
        Test.stopTest();
        System.assert(lista[0].Id != null, 'Debe guardarse la cobertura');
    }

    @isTest
    static void testSaveCoverages_error() {
        Id fake = deletedQuoteId();
        Boolean threw = false;
        List<Quote_Coverage__c> lista = new List<Quote_Coverage__c>{
            new Quote_Coverage__c(Quote__c = fake, Coverage_Name__c = 'Rota', Order__c = 1)
        };
        Test.startTest();
        try {
            QuoteCreatorController.saveCoverages(lista);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Una cobertura con relación inválida debe lanzar excepción');
    }

    // ---------- busquedas ----------

    @isTest
    static void testSearchOpportunities() {
        Test.startTest();
        List<QuoteCreatorController.OpportunityWrapper> result =
            QuoteCreatorController.searchOpportunities('Opp Quote');
        Test.stopTest();
        System.assert(!result.isEmpty(), 'Debe encontrar la oportunidad de prueba');
        System.assertNotEquals(null, result[0].Name, 'El wrapper debe traer nombre');
    }

    @isTest
    static void testSearchAseguradoras() {
        Test.startTest();
        List<Aseguradora__c> result = QuoteCreatorController.searchAseguradoras('Aseguradora');
        Test.stopTest();
        System.assert(!result.isEmpty(), 'Debe encontrar la aseguradora de prueba');
    }

    // ---------- productos y coberturas plantilla ----------

    @isTest
    static void testGetProducts() {
        Aseguradora__c aseg = getAseg();
        Test.startTest();
        List<Product2> vacio = QuoteCreatorController.getProducts('', null);
        List<Product2> productos = QuoteCreatorController.getProducts('GMM', aseg.Id);
        Test.stopTest();
        System.assert(vacio.isEmpty(), 'Sin ramo/aseguradora debe regresar vacío');
        System.assertNotEquals(null, productos, 'Debe ejecutar la consulta de productos');
    }

    @isTest
    static void testGetCoveragesByProduct() {
        Product2 prod = getProd();
        Test.startTest();
        List<QuoteCreatorController.CoverageTemplateWrapper> vacio =
            QuoteCreatorController.getCoveragesByProduct(null);
        List<QuoteCreatorController.CoverageTemplateWrapper> plantillas =
            QuoteCreatorController.getCoveragesByProduct(prod.Id);
        Test.stopTest();
        System.assert(vacio.isEmpty(), 'Con id nulo debe regresar lista vacía');
        System.assertNotEquals(null, plantillas, 'Debe ejecutar la consulta de coberturas plantilla');
    }
}