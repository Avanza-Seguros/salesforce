@isTest
public class DownloadAttachmentControllerTest {
    @isTest
    static void testGetAttachmentIds() {
        // Utilizar el ID del caso específico
        //Id testCaseId = '5008a00002EHnatAAD';
        Account acc = new Account();
        acc.Name = 'Test';
        Insert acc;
        
        Case cs = new Case();
        cs.Subject = 'test';
        Insert cs;

        // Crear un registro de prueba de Items_Cases__c vinculado al Case
        Items_Cases__c testItem = new Items_Cases__c();
        testItem.Caso__c = cs.Id;
        testItem.Correo_electronico__c = 'test@test.com';
        testItem.Nombre_cuenta__c = acc.Id;
        insert testItem;

        // Crear un registro de prueba de ContentDocument vinculado al Items_Cases__c
        ContentVersion testContentVersion = new ContentVersion();
        testContentVersion.Title = 'Test Document';
        testContentVersion.PathOnClient = 'TestPath/TestDocument.txt';
        testContentVersion.VersionData = Blob.valueOf('Test content');
        insert testContentVersion;

        // Obtener el ContentDocumentId del ContentVersion
        Id contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :testContentVersion.Id LIMIT 1][0].ContentDocumentId;

        // Crear un registro de prueba de ContentDocumentLink vinculado al Items_Cases__c
        ContentDocumentLink testContentDocumentLink = new ContentDocumentLink();
        testContentDocumentLink.LinkedEntityId = cs.Id;
        testContentDocumentLink.ContentDocumentId = contentDocumentId;
        insert testContentDocumentLink;

        // Llamar al método del controlador
        Test.startTest();
        List<String> result = DownloadAttachmentController.getAttachmentUrls(cs.Id);
        Test.stopTest();

        // Verificar resultados
        //System.assertEquals(1, result.size());
    }
}