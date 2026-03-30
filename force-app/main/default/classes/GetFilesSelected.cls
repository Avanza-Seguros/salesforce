public without sharing class GetFilesSelected {

    @AuraEnabled(cacheable=true)
    public static List<ContentVersion> getFiles(String IdRecord){
            set<Id> ids = new set<Id>();
            for(ContentDocumentLink obj : [SELECT Id, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId =: IdRecord]){
                ids.add(obj.ContentDocumentId);
            }
            return [SELECT Id, ContentDocumentId, FileExtension, Title, ContentModifiedBy.Name, ContentModifiedDate  FROM ContentVersion WHERE ContentDocumentId IN : ids AND Carta_Autorizacion__c = true];
    }

    @AuraEnabled(cacheable=true)
    public static List<ContentVersion> getNormalFiles(String IdRecord){
            set<Id> ids = new set<Id>();
            for(ContentDocumentLink obj : [SELECT Id, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId =: IdRecord]){
                ids.add(obj.ContentDocumentId);
            }
            return [SELECT Id, ContentDocumentId, FileExtension, Title, ContentModifiedBy.Name, ContentModifiedDate  FROM ContentVersion WHERE ContentDocumentId IN : ids AND Carta_Autorizacion__c = false];

    }

    @AuraEnabled
    public static void UpdateFile(String IdRecord){

            List<ContentVersion> lstFiles = [SELECT Id, ContentDocumentId, FileExtension, Title FROM ContentVersion WHERE ContentDocumentId =: IdRecord];
            ContentVersion cv = new ContentVersion(Id = lstFiles[0].Id, Carta_Autorizacion__c = true);
            Update cv;
    }

    
}