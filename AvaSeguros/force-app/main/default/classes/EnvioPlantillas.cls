public with sharing class EnvioPlantillas {
    
    public static void EnvioEmail(Id objItemId) {
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        Id senderEmailId = [SELECT Id FROM OrgWideEmailAddress WHERE Address = 'info@avanzaseguro.com' LIMIT 1].Id;

        Items_Cases__c objItem = [SELECT Id, Nombre_cuenta__c, Contacto__c, Correo_electronico__c,Correo_Copia__c, Categorias__c FROM Items_Cases__c WHERE Id = :objItemId LIMIT 1];

        if (objItem != null && objItem.Correo_electronico__c != null) {
            Account acc = [SELECT Name FROM Account WHERE Id = :objItem.Nombre_cuenta__c LIMIT 1];

            String[] plantillaRecordTypeNames = new String[]{'Plantilla de correo electrónico'};
            Set<Id> plantillaRecordTypeIds = new Set<Id>();

            for (String recordTypeName : plantillaRecordTypeNames) {
                Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.EmailTemplate.getRecordTypeInfosByName().get(recordTypeName);
                if (recordTypeInfo != null) {
                    plantillaRecordTypeIds.add(recordTypeInfo.getRecordTypeId());
                }
            }

            List<Asigacion_de_plantilla__c> asgList = [SELECT ID_de_la_plantilla__c, Categoria__c FROM Asigacion_de_plantilla__c WHERE Empresa__c = :acc.Id AND Categoria__c = :objItem.Categorias__c LIMIT 1];
            if (asgList.size() > 0) {
                Asigacion_de_plantilla__c asg = asgList[0];
                EmailTemplate et = [SELECT Id, Subject, Body FROM EmailTemplate WHERE DeveloperName = :asg.ID_de_la_plantilla__c LIMIT 1];

                if (objItem.Categorias__c == asg.Categoria__c) {
                    // 1. Enviar a Correo_electronico__c como destinatario principal
                    message.setToAddresses(new String[] { objItem.Correo_electronico__c });

                    // 2. Enviar al contacto relacionado (Contacto__c)
                    message.setTargetObjectId(objItem.Contacto__c);

                    // 3. Si Correo_Copia__c no es nulo, se agrega en CC; si es nulo, no se hace nada
                    if (objItem.Correo_Copia__c != null) {
                        message.setCcAddresses(new String[] { objItem.Correo_Copia__c });
                    }
                    message.setTemplateId(et.Id);
                    message.setOrgWideEmailAddressId(senderEmailId);
                    message.setWhatId(objItem.Id);
                    message.setSaveAsActivity(false);
                    message.setTargetObjectId(objItem.Contacto__c);
                    message.setUseSignature(true);
                    message.setFileAttachments(getAttachmentForEmail(getRelatedFilesByRecordId(objItem.Id)));
                    message.setHtmlBody(et.Body);

                    Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { message });

                    if (results[0].success) {
                        System.debug('The email was sent successfully.');
                    } else {
                        System.debug('The email failed to send: ' + results[0].errors[0].message);
                    }
                } else {
                    System.debug('The category in Items_Cases__c does not match the category in Asigacion_de_plantilla__c.');
                }
            } else {
                System.debug('No Asigacion_de_plantilla__c found for the account.');
            }
        } else {
            System.debug('The email address is null or the Items_Cases__c record does not exist.');
        }
    }

    public static Map<ID, ContentVersion> getRelatedFilesByRecordId(String recordId) {
        // Get record file IDs
        List<ContentDocumentLink> files = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :recordId order by ContentDocument.CreatedDate asc];
        List<ID> fileIDs = new List<ID>();
        for (ContentDocumentLink docLink : files) {
            fileIDs.add(docLink.ContentDocumentId);
        }
 
        List<ContentVersion> docs = [SELECT Id, ContentDocumentId, FileExtension, Title, VersionData, PathOnClient
            FROM ContentVersion WHERE ContentDocumentId IN : fileIDs order by ContentDocument.CreatedDate asc];

        Map<ID, ContentVersion> mapIdTitle = new Map<ID, ContentVersion>();
        for (ContentVersion ctnVersion : docs) {
            mapIdTitle.put(ctnVersion.Id, ctnVersion);
        }

        return mapIdTitle;
    }
    
    public static List<Messaging.EmailFileAttachment> getAttachmentForEmail(Map<ID, ContentVersion> mapFile){
        List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();
        for (Id key : mapFile.keySet()) {
            Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
            efa.setFileName(mapFile.get(key).PathOnClient);
            efa.setBody(mapFile.get(key).VersionData);
            efa.setContentType(fileMimeTypes.get(mapFile.get(key).FileExtension));
            attachments.add(efa);
        }
        return attachments;
    }
    
    private static Map<String, String> fileMimeTypes = new Map<String, String>{
        'abw' => 'application/x-abiword',
        'arc' => 'application/x-freearc',
        'bin' => 'application/octet-stream',
        'bmp' => 'image/bmp',
        'bz' => 'application/x-bzip',
        'bz2' => 'application/x-bzip2',
        'csh' => 'application/x-csh',
        'css' => 'text/css',
        'csv' => 'text/csv',
        'doc' => 'application/msword',
        'docx' => 'application/msword',
        'eot' => 'application/vnd.ms-fontobject',
        'epub' => 'application/epub+zip',
        'gz' => 'application/gzip',
        'gif' => 'image/gif',
        'htm' => 'text/html',
        'html' => 'text/html',
        'ico' => 'image/vnd.microsoft.icon',
        'ics' => 'text/calendar',
        'jpeg' => 'image/jpeg',
        'jpg' => 'image/jpeg',
        'js' => 'text/javascript',
        'json' => 'application/json',
        'jsonld' => 'application/ld+json',
        'mjs' => 'text/javascript',
        'png' => 'image/png',
        'pdf' => 'application/pdf',
        'php' => 'application/php',
        'ppt' => 'application/vnd.ms-powerpoint',
        'pptx' => 'application/vnd.ms-powerpoint',
        'rar' => 'application/vnd.rar',
        'rtf' => 'application/rtf',
        'sh' => 'application/x-sh',
        'svg' => 'image/svg+xml',
        'swf' => 'application/x-shockwave-flash',
        'tar' => 'application/x-tar',
        'tif' => 'image/tiff',
        'tiff' => 'image/tiff',
        'ts' => 'video/mp2t',
        'txt' => 'text/plain',
        'vsd' => 'application/vnd.visio',
        'wav' => 'audio/wav',
        'webp' => 'image/webp',
        'xhtml' => 'application/xhtml+xml',
        'xls' => 'application/vnd.ms-excel',
        'xlsx' => 'application/vnd.ms-excel',
        'xml' => 'application/xml',
        'xul' => 'application/vnd.mozilla.xul+xml',
        'zip' => 'application/zip',
        '7z' => 'application/x-7z-compressed'
    };


}