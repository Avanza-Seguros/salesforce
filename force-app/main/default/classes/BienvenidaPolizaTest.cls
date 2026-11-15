/**
 *   @name: BienvenidaPolizaTest
 *   @description: Pruebas de BienvenidasPoliza: el correo de bienvenida se envía una sola vez y solo a Correo__c.
 *                 No depende de tipos de registro ni de pasar la oportunidad a Closed Won (validaciones de la org).
 */
@isTest
public class BienvenidaPolizaTest {

    static String activeStage() {
        List<OpportunityStage> s = [
            SELECT MasterLabel FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1
        ];
        return s.isEmpty() ? 'Prospecting' : s[0].MasterLabel;
    }

    @testSetup
    static void setup() {
        Account acc = new Account(Name = 'Luxoft Mexico S.A. De C.V.');
        insert acc;
        Contact c = new Contact(LastName = 'Pérez', FirstName = 'Juan', AccountId = acc.Id, Email = 'juan.perez@ejemplo.com');
        insert c;

        Opportunity opp = new Opportunity(Name = 'TEST OPP CTE1', AccountId = acc.Id, StageName = activeStage(),
            Ramo__c = 'Vida', Correo__c = 'test@ejemplo.com', CloseDate = Date.today().addDays(30));
        insert opp;
        // Algunos flujos de la org reescriben el correo al crear la oportunidad: se vuelve a poner.
        update new Opportunity(Id = opp.Id, Ramo__c = 'Vida', Correo__c = 'test@ejemplo.com');

        ContentVersion content = new ContentVersion(Title = 'Header_Picture1', PathOnClient = '/Header_Picture1.jpg',
            VersionData = Blob.valueOf('Unit Test ContentVersion Body'), Origin = 'H');
        insert content;
        insert new ContentDocumentLink(LinkedEntityId = opp.Id, ShareType = 'I', Visibility = 'AllUsers',
            ContentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :content.Id].ContentDocumentId);
    }

    @isTest
    static void enviaUnaSolaVezPorTransaccion() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Test.startTest();
        BienvenidasPoliza.EnvioEmail(opp.Id);
        Integer despuesDelPrimero = Limits.getEmailInvocations();
        BienvenidasPoliza.EnvioEmail(opp.Id);
        Integer despuesDelSegundo = Limits.getEmailInvocations();
        Test.stopTest();
        System.assertEquals(despuesDelPrimero, despuesDelSegundo, 'La segunda llamada no debe volver a enviar');
        System.assert(BienvenidasPoliza.enviadas.contains(opp.Id));
    }

    @isTest
    static void conCorreoYPlantilla() {
        Opportunity opp = [SELECT Id, Correo__c, Ramo__c FROM Opportunity LIMIT 1];
        System.assertEquals('test@ejemplo.com', opp.Correo__c, 'El correo debe quedar en la oportunidad');
        Test.startTest();
        BienvenidasPoliza.EnvioEmail(opp.Id);           // con contacto: usa la plantilla
        BienvenidasPoliza.enviadas.clear();
        delete [SELECT Id FROM Contact];
        BienvenidasPoliza.EnvioEmail(opp.Id);           // sin contacto: asunto y contenido de la plantilla
        Test.stopTest();
    }

    @isTest
    static void ramosYContacto() {
        Opportunity opp = [SELECT Id, AccountId, Contacto__c, Account.PersonContactId FROM Opportunity LIMIT 1];
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        System.assertEquals('Bienvenida_Vida_Poliza', BienvenidasPoliza.plantillaDe('Vida'));
        System.assertEquals('Bienvenida_General_Poliza', BienvenidasPoliza.plantillaDe('RC'));
        System.assertEquals(null, BienvenidasPoliza.plantillaDe(null));
        System.assertEquals(c.Id, BienvenidasPoliza.contactoDe(opp));
        System.assertEquals(null, BienvenidasPoliza.contactoDe(new Opportunity()));
    }

    @isTest
    static void sinContactoNiCorreo() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        delete [SELECT Id FROM Contact];
        Test.startTest();
        opp.Ramo__c = 'RC';
        update opp;
        BienvenidasPoliza.EnvioEmail(opp.Id);   // sin contacto: asunto y contenido de la plantilla
        BienvenidasPoliza.enviadas.clear();
        opp.Correo__c = null;
        update opp;
        BienvenidasPoliza.EnvioEmail(opp.Id);   // sin correo: no envía
        BienvenidasPoliza.enviadas.clear();
        opp.Ramo__c = 'Dental';
        opp.Correo__c = 'test@ejemplo.com';
        update opp;
        BienvenidasPoliza.EnvioEmail(opp.Id);   // ramo sin plantilla: no envía
        BienvenidasPoliza.EnvioEmail(null);
        Test.stopTest();
        System.assert(BienvenidasPoliza.enviadas.contains(opp.Id));
    }
}
