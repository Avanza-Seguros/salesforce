public with sharing class ETC_UtilityFile {

    public static List<ContentVersion> getFiles(Id recordId) {
        Map<Id, ContentDocumentLink> mapContentDocumentLink = new Map<Id, ContentDocumentLink>([SELECT ContentDocumentId,Id,LinkedEntityId FROM ContentDocumentLink WHERE LinkedEntityId =: recordId]);
        Set<String> contentDocumentIds = new Set<String>();
        for (ContentDocumentLink item : mapContentDocumentLink.values()) {
            contentDocumentIds.add(item.ContentDocumentId);
        }
        return [SELECT ContentDocumentId,ContentSize,IsLatest,Title,VersionData,FileExtension FROM ContentVersion WHERE ContentDocumentId IN :contentDocumentIds AND IsLatest = true];
    }

}