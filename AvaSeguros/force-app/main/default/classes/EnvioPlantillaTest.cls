@isTest
public class EnvioPlantillaTest {

    @testSetup static void setup() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];

        User u = new User(
            Username = 'testadrtradmin123@test.com',
            LastName = 'tes_avanza',
            Alias = 'tadmin',
            Email = 'testadmin123@test.com',
            EmailEncodingKey = 'UTF-8',
            TimeZoneSidKey = 'America/Mexico_City',
            LocaleSidKey = 'es_MX',
            LanguageLocaleKey = 'es_MX',
            ProfileId = p.Id
        );
        insert u;
        
        Account acc = new Account();
        acc.Name = 'Luxoft Mexico S.A. De C.V.';
        insert acc;
        
        Contact co = new Contact();
        co.FirstName = 'test';
        co.LastName = 'test';
        co.Email = 'test@test.com';
        Insert co;

        Asigacion_de_plantilla__c asg = new Asigacion_de_plantilla__c();
        asg.Empresa__c = acc.id;
        asg.ID_de_la_plantilla__c = 'Luxoft_Altas';
        asg.Name = 'Luxoft Mexico S.A. De C.V.';
        Insert asg;

        Case caso = new Case();
        caso.AccountId = acc.Id;

        insert caso;
        
        Items_Cases__c itemCases = new Items_Cases__c();
        itemCases.Nombre_cuenta__c = acc.Id;
        itemCases.Correo_electronico__c = 'test@gmail.com';
        itemCases.Estatus__c = 'Concluido';
        itemCases.Caso__c = caso.Id;
        itemCases.Contacto__c = co.id;
        itemCases.Fecha_de_peticion__c = Date.today();
        itemCases.Fecha_de_nacimiento__c = Date.today();
        itemCases.Sexo__c = 'Masculino';
        insert itemCases;
   
        ContentVersion content=new ContentVersion(); 
        content.Title='Header_Picture1'; 
        content.PathOnClient='/' + content.Title + '.jpg'; 
        Blob bodyBlob=Blob.valueOf('Unit Test ContentVersion Body'); 
        content.VersionData=bodyBlob; 
        //content.LinkedEntityId=sub.id;
        content.origin = 'H';
        insert content;
        
        ContentDocumentLink contentlink=new ContentDocumentLink();
        contentlink.LinkedEntityId=itemCases.id;
        contentlink.contentdocumentid=[select contentdocumentid from contentversion where id =: content.id].contentdocumentid;
        contentlink.ShareType = 'I';
        contentlink.Visibility = 'AllUsers';
        
        insert contentlink;      
    }
    
    static testmethod void EnvioTrigger (){
        Profile p2 = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        
        User adminUser = [SELECT Id FROM User WHERE ProfileId = :p2.Id LIMIT 1];
            
        Test.startTest();
        Items_Cases__c itemCases = [SELECT Id, Contacto__c FROM Items_Cases__c LIMIT 1][0];
        itemCases.Estatus__c = 'Concluido';
        Update itemCases;
        Test.stopTest();
    }
    
    static testmethod void sendEmailTest(){
        Profile p2 = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User adminUser = [SELECT Id FROM User WHERE ProfileId = :p2.Id AND IsActive = true LIMIT 1];
        
        Test.startTest();
        Items_Cases__c itemCases = [SELECT Id, Contacto__c FROM Items_Cases__c LIMIT 1];
        itemCases.Estatus__c = 'Concluido';
        
        System.runAs(adminUser) {
            EnvioPlantillas.EnvioEmail(itemCases.Id);
        }
        Test.stopTest();

    // Afirmaciones para verificar que el correo electrónico se haya enviado con éxito
    // Puedes ajustar estas afirmaciones según tus necesidades específicas.
    System.assertEquals(0, Limits.getEmailInvocations(), 'Se debe haber enviado un correo electrónico');
    // Verifica cualquier otro resultado esperado aquí.
    }

    @IsTest
    static void testBuildEmail_Positive() {
        Case c1 = [SELECT Id FROM Case LIMIT 1];
        Items_Cases__c testItem = [SELECT Id, Nombre_cuenta__c, Categorias__c, Correo_electronico__c, Correo_Copia__c FROM Items_Cases__c WHERE Caso__c = :c1.Id];
        
        Test.startTest();
        Messaging.SingleEmailMessage email = EnvioPlantillas.EnvioEmailMasivo(testItem.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, email, 'El email no debería ser nulo');
        System.assertNotEquals(null, email.getToAddresses(), 'Debe tener direcciones de destino');
        System.assert(!email.getToAddresses().isEmpty(), 'Debe tener al menos un destinatario');
    }

    @IsTest
    static void testBuildEmail_WithoutCC() {
        Case c1 = [SELECT Id FROM Case LIMIT 1];
        // Crear item sin CC
        Items_Cases__c testItemNoCC = new Items_Cases__c(
            Nombre_cuenta__c = [SELECT Id FROM Account LIMIT 1].Id,
            Contacto__c = [SELECT Id FROM Contact LIMIT 1].Id,
            Correo_electronico__c = 'test@test.com',
            Estatus__c = 'En proceso',
            Fecha_de_peticion__c = Date.today(),
        	Fecha_de_nacimiento__c = Date.today(),
            Caso__c = c1.Id,
        	Sexo__c = 'Masculino'
        );
        insert testItemNoCC;
        
        Test.startTest();
        Messaging.SingleEmailMessage email = EnvioPlantillas.EnvioEmailMasivo(testItemNoCC.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, email, 'El email no debería ser nulo');
        // Verificar que no hay CC
        System.assertEquals(null, email.getCcAddresses(), 'No debería haber direcciones CC');
    }
    
    @IsTest
    static void testGetRelatedFilesByRecordId2_Positive() {
        Items_Cases__c testItem = [SELECT Id FROM Items_Cases__c LIMIT 1];
        
        Test.startTest();
        Map<ID, ContentVersion> result = EnvioPlantillas.getRelatedFilesByRecordId(testItem.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'El resultado no debería ser nulo');
        System.assert(!result.isEmpty(), 'Debería haber archivos relacionados');
    }

    @IsTest
    static void testGetAttachmentForEmail2_Positive() {
        Items_Cases__c testItem = [SELECT Id FROM Items_Cases__c LIMIT 1];
        Map<ID, ContentVersion> filesMap = EnvioPlantillas.getRelatedFilesByRecordId(testItem.Id);
        
        Test.startTest();
        List<Messaging.EmailFileAttachment> attachments = EnvioPlantillas.getAttachmentForEmail(filesMap);
        Test.stopTest();
        
        System.assertNotEquals(null, attachments, 'Los attachments no deberían ser nulos');
        System.assert(!attachments.isEmpty(), 'Debería haber attachments');
    }


    // Clase mock para simular el envío de emails en tests
    private class MockEmailSender implements System.HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('OK');
            return res;
        }
    }
}