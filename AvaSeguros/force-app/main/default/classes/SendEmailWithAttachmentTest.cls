/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 03-06-2025
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@isTest
public class SendEmailWithAttachmentTest {

    @testSetup static void setup() {
        Contact co = new Contact();
        co.FirstName = 'test';
        co.LastName = 'test';
        co.Email = 'test@test.com';
        insert co;
        
        Control_de_Folios__c cf = new Control_de_Folios__c();
        cf.Estatus__c = 'Nuevo';
        cf.Movimiento__c = 'Programación';
        cf.Correo__c = 'test@test.com';
        cf.Titular__c = co.Id;
        cf.Aseguradora__c = 'SMNYL'; // Se establece un valor para la aseguradora
        insert cf;
        
        ContentVersion content = new ContentVersion(); 
        content.Title = 'Header_Picture1'; 
        content.PathOnClient = '/' + content.Title + '.jpg'; 
        Blob bodyBlob = Blob.valueOf('Unit Test ContentVersion Body'); 
        content.VersionData = bodyBlob; 
        content.origin = 'H';
        insert content;
        
        ContentDocumentLink contentlink = new ContentDocumentLink();
        contentlink.LinkedEntityId = cf.Id;
        contentlink.ContentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :content.Id].ContentDocumentId;
        contentlink.ShareType = 'I';
        contentlink.Visibility = 'AllUsers';
        insert contentlink;      
    }
    
    static testmethod void triggerControlFoliosTest() {
        Test.startTest();
        Control_de_Folios__c cf = [SELECT Id, Correo__c, Titular__c, Aseguradora__c FROM Control_de_Folios__c LIMIT 1]; // 🔹 Se agregó Aseguradora__c
        cf.Estatus__c = 'Aceptado';
        update cf;
        Test.stopTest();
    }
    
    static testmethod void sendEmailTest() {
        Test.startTest();
        // 🔹 Se asegura de incluir Aseguradora__c en la consulta SOQL
        Control_de_Folios__c cf = [SELECT Id, Correo__c, Titular__c, Aseguradora__c FROM Control_de_Folios__c LIMIT 1];
        
        // 🔹 Verificación para evitar fallos si el campo es NULL
        System.assertNotEquals(null, cf.Aseguradora__c, 'El campo Aseguradora__c no debería ser NULL');
        
        SendEmailWithAttachment.sendEmail(cf);
        Test.stopTest();
    }
}