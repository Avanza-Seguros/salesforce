@isTest
public class EnvioCartaTest {

    @testSetup static void setup() {
        
        Contact co = new Contact();
        co.FirstName = 'test';
        co.LastName = 'test';
        co.Email = 'test@test.com';
        Insert co;
        
        Control_de_Folios__c cf = new Control_de_Folios__c();
        cf.Estatus__c = 'Nuevo';
        cf.Movimiento__c = 'Ingreso Hospitalario';
        cf.Correo__c = 'test@test.com';
        cf.Titular__c = co.Id;
		insert cf;
        
        ContentVersion content=new ContentVersion(); 
        content.Title='Header_Picture1'; 
        content.PathOnClient='/' + content.Title + '.jpg'; 
        Blob bodyBlob=Blob.valueOf('Unit Test ContentVersion Body'); 
        content.VersionData=bodyBlob; 
        //content.LinkedEntityId=sub.id;
        content.origin = 'H';
        insert content;
        
        ContentDocumentLink contentlink=new ContentDocumentLink();
        contentlink.LinkedEntityId=cf.id;
        contentlink.contentdocumentid=[select contentdocumentid from contentversion where id =: content.id].contentdocumentid;
        contentlink.ShareType = 'I';
        contentlink.Visibility = 'AllUsers';
        
        insert contentlink;      
    }
    
    static testmethod void triggerControlFoliosTest(){
        Test.startTest();
        Control_de_Folios__c cf = [select id, Correo__c, Titular__c from Control_de_Folios__c limit 1][0];
        cf.Estatus__c = 'Aceptado';
        Update cf;
        Test.stopTest();
    }
    
    static testmethod void sendEmailTest(){
        Test.startTest();
        Control_de_Folios__c cf = [select id, Correo__c, Titular__c from Control_de_Folios__c limit 1][0];
        cf.Estatus__c = 'Aceptado';
        EnvioCarta.EnvioIngreso(cf);
        Test.stopTest();
    }
}