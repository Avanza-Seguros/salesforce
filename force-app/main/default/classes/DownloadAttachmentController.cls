public with sharing class DownloadAttachmentController {

    @AuraEnabled
    public static List<String> getAttachmentUrls(Id recordId) {
        List<String> attachmentUrls = new List<String>();
        
        // Busca los registros ContentDocumentLink relacionados con el registro proporcionado.
        List<ContentDocumentLink> documentLinks = [SELECT ContentDocumentId
                                                    FROM ContentDocumentLink
                                                    WHERE LinkedEntityId = :recordId];
        
        String downloadUrl = URL.getSalesforceBaseUrl().toExternalForm() +
        '/sfc/servlet.shepherd/document/download/';
        string FilesId = '';
        for (ContentDocumentLink link : documentLinks) {
        FilesId = FilesId + link.ContentDocumentId + '/';               
        }
        
        attachmentUrls.add(downloadUrl + FilesId);
        
        return attachmentUrls;
    }
}