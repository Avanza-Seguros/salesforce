@isTest
public class LuxoftTest {

    @testSetup static void setup() {
        
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
        itemCases.Estatus__c = 'Nuevo';
        itemCases.Caso__c = caso.Id;
        itemCases.Contacto__c = co.id;
        insert itemCases;

        itemCases.Estatus__c = 'Concluido';
        update itemCases;
   
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
    
    static testmethod void LuxoftTrigger (){
        Test.startTest();
        Items_Cases__c itemCases = [SELECT Id, Contacto__c FROM Items_Cases__c LIMIT 1][0];
        itemCases.Estatus__c = 'Concluido';
        Update itemCases;
        Test.stopTest();
    }
    
    static testmethod void sendEmailTest(){
        Test.startTest();
        Items_Cases__c itemCases = [SELECT Id, Contacto__c FROM Items_Cases__c LIMIT 1][0];
        itemCases.Estatus__c = 'Concluido';
        Luxoft.sendEmail(itemCases);
        Test.stopTest();
    }
}