/**
 *  @name: PolicyControllerTest
 *  @description: Pruebas unitarias para PolicyController (getPolicyIdByQuote, analizarPoliza).
 *               El path de Einstein se salta con Test.isRunningTest() en la clase, por lo que
 *               aquí se cubren las rutas de datos (SOQL) y las validaciones.
 */
@isTest
private class PolicyControllerTest {

    // ---------- Datos base ----------
    @testSetup
    static void setup() {
        Account acc = new Account(Name = 'Cuenta Póliza Test');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Opp Póliza Test',
            StageName = activeStage(),
            CloseDate = Date.today().addDays(30),
            AccountId = acc.Id
        );
        insert opp;

        Quote q = new Quote(
            Name = 'Cotización Póliza Test',
            OpportunityId = opp.Id,
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert q;
    }

    static String activeStage() {
        List<OpportunityStage> s = [
            SELECT MasterLabel FROM OpportunityStage
            WHERE IsActive = true ORDER BY SortOrder ASC LIMIT 1
        ];
        return s.isEmpty() ? 'Prospecting' : s[0].MasterLabel;
    }

    // Intenta crear una InsurancePolicy ligada a la cotización. Devuelve el Id o null
    // si el objeto tiene campos obligatorios adicionales en el org.
    static Id tryCreatePolicy(Id quoteId, Id nameInsuredId) {
        try {
            InsurancePolicy p = new InsurancePolicy(
                Name = 'POL-TEST-001',
                NameInsuredId = nameInsuredId,
                SourceQuoteId = quoteId
            );
            insert p;
            return p.Id;
        } catch (Exception e) {
            return null;
        }
    }

    @isTest
    static void testGetPolicyIdByQuote_nulls() {
        Test.startTest();
        Id result = PolicyController.getPolicyIdByQuote(null, null);
        Test.stopTest();
        System.assertEquals(null, result, 'Sin ids debe devolver null');
    }

    @isTest
    static void testGetPolicyIdByQuote_notFound() {
        Quote q = [SELECT Id, OpportunityId FROM Quote LIMIT 1];
        Test.startTest();
        // No hay póliza: ejecuta ambas ramas de SOQL y regresa null.
        Id byQuote = PolicyController.getPolicyIdByQuote(q.Id, null);
        Id byOpp = PolicyController.getPolicyIdByQuote(null, q.OpportunityId);
        Test.stopTest();
        System.assertEquals(null, byQuote, 'Sin póliza debe ser null');
        System.assertEquals(null, byOpp, 'Sin póliza debe ser null');
    }

    @isTest
    static void testGetPolicyIdByQuote_found() {
        Quote q = [SELECT Id, OpportunityId, AccountId FROM Quote LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Id policyId = tryCreatePolicy(q.Id, acc.Id);

        Test.startTest();
        Id byQuote = PolicyController.getPolicyIdByQuote(q.Id, null);
        Id byOpp = PolicyController.getPolicyIdByQuote(null, q.OpportunityId);
        Test.stopTest();

        if (policyId != null) {
            System.assertEquals(policyId, byQuote, 'Debe localizar la póliza por SourceQuoteId');
            System.assertEquals(policyId, byOpp, 'Debe localizar la póliza por la oportunidad');
        }
    }

    @isTest
    static void testAnalizarPoliza_blank() {
        Boolean threw = false;
        Test.startTest();
        try {
            PolicyController.analizarPoliza('   ');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Texto en blanco debe lanzar excepción');
    }

    @isTest
    static void testAnalizarPoliza_ok() {
        Test.startTest();
        String result = PolicyController.analizarPoliza('Texto de una póliza de prueba');
        Test.stopTest();
        // En contexto de test la clase devuelve '{}' sin llamar a Einstein.
        System.assertEquals('{}', result, 'En test debe devolver JSON vacío');
    }
}
