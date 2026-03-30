@IsTest
public with sharing class ETC_EmailTest {

    @isTest
    public static void emailTets() {
        Account acc = new Account();
        acc.Name = 'test';
        insert acc;

        Case caso = new Case();
        caso.AccountId = acc.Id;

        insert caso;

        Items_Cases__c itemCases = new Items_Cases__c();
        itemCases.Nombre_cuenta__c = acc.Id;
        itemCases.Correo_electronico__c = 'test@gmail.com';
        itemCases.Estatus__c = 'Nuevo';
        itemCases.Caso__c = caso.Id;
        insert itemCases;

        addFile(itemCases.Id);

        
        ETC_UtilityEmail.sendEmailWithFiles(itemCases.Correo_electronico__c, itemCases.Id);
    }

    @IsTest
    public static void emailFlowTest(){
        Account acc = new Account();
        acc.Name = 'test';
        insert acc;

        Case caso = new Case();
        caso.AccountId = acc.Id;

        insert caso;

        Items_Cases__c itemCases = new Items_Cases__c();
        itemCases.Nombre_cuenta__c = acc.Id;
        itemCases.Correo_electronico__c = 'test@gmail.com';
        itemCases.Estatus__c = 'Nuevo';
        itemCases.Caso__c = caso.Id;
        insert itemCases;

        addFile(itemCases.Id);

        List<List<String>> listIds = new List<List<String>>();
        listIds.add(new List<String>{itemCases.Id});
        ETC_FlowPeticion.createPdf(listIds);

    }

    public static ContentDocumentLink addFile(Id linkedId){
        ContentVersion contentVersion = new ContentVersion(
            Title = 'test',
            PathOnClient = 'test.jpg',
            VersionData = Blob.valueOf('Test Content'),
            IsMajorVersion = true
        );
        insert contentVersion;
        List<ContentDocument> documents = [SELECT Id, Title, LatestPublishedVersionId FROM ContentDocument];
        
        ContentDocumentLink cdl = New ContentDocumentLink();
        cdl.LinkedEntityId = linkedId;
        cdl.ContentDocumentId = documents[0].Id;
        cdl.shareType = 'V';
        insert cdl;
        return cdl;
    }
}