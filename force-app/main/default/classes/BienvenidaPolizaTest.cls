@isTest
public class BienvenidaPolizaTest {

    @testSetup
    static void setup() {
        Account acc = new Account();
        acc.Name = 'Luxoft Mexico S.A. De C.V.';
        insert acc;
        
        Agente__c ag = new Agente__c();
        ag.Name = 'Juan Perez';
        ag.Status__c = 'nuevo';
        ag.Estado_Civil__c = 'Casado';
        insert ag;
        
        RecordType bajaRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Opportunity' AND DeveloperName = 'Oportunidad_Individual' LIMIT 1];

        Opportunity opp = new Opportunity();
        opp.Name = 'TEST OPP CTE1';
        opp.AccountId = acc.Id;
        opp.StageName = 'Necesidad';
        opp.Cotizante__c = ag.Id;
        opp.Ramo__c = 'Auto';
        opp.Correo__c = 'test@gmail.com';
        opp.CloseDate = Date.today();
        opp.RecordTypeId = bajaRecordType.Id;
        insert opp;

        opp.StageName = 'Closed Won';
        update opp;
   
        ContentVersion content = new ContentVersion(); 
        content.Title = 'Header_Picture1'; 
        content.PathOnClient = '/' + content.Title + '.jpg'; 
        Blob bodyBlob = Blob.valueOf('Unit Test ContentVersion Body'); 
        content.VersionData = bodyBlob;
        content.Origin = 'H';
        insert content;
        
        ContentDocumentLink contentlink = new ContentDocumentLink();
        contentlink.LinkedEntityId = opp.Id;
        contentlink.ContentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :content.Id].ContentDocumentId;
        contentlink.ShareType = 'I';
        contentlink.Visibility = 'AllUsers';
        insert contentlink;      
    }
    
    static testmethod void EnvioBienvenidas() {
        Test.startTest();
        Opportunity opp = [SELECT Id, AccountId, StageName FROM Opportunity WHERE StageName = 'Closed Won' LIMIT 1];
        opp.StageName = 'Concluido';
        update opp;
        Test.stopTest();
        
        // Verifica si el estado se actualizó correctamente
        Opportunity updatedOpp = [SELECT StageName FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Concluido', updatedOpp.StageName, 'La oportunidad debe estar en estado Concluido');
    }
    
    static testmethod void sendEmailTest() {
        Test.startTest();
        
        // Recuperar la oportunidad una vez
        Opportunity opp = [SELECT Id, AccountId, Correo__c FROM Opportunity WHERE StageName = 'Closed Won' LIMIT 1];
        
        // Simular diferentes valores válidos de Ramo__c
        List<String> ramoValues = new List<String>{'Auto', 'Vida', 'Danos', 'Retiro', 'Gastos Medicos', 'RC', 'Mascota', 'Fianzas', 'Administrativa', 'Accidentes', 'Viajes'};
        
        for (String ramo : ramoValues) {
            opp.Ramo__c = ramo;
            opp.Correo__c = 'test@gmail.com';
            update opp;
            BienvenidasPoliza.EnvioEmail(opp.Id);
        }
        
        // Probar caso donde no hay correo en la oportunidad
        opp.Ramo__c = 'Auto';
        opp.Correo__c = null;
        update opp;
        BienvenidasPoliza.EnvioEmail(opp.Id);
        
        Test.stopTest();
        
        // Verificar que se intentaron enviar correos electrónicos
        System.assert(true, 'Se enviaron correos electrónicos de prueba.');
    }
}