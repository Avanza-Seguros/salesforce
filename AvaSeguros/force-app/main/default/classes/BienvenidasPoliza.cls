public with sharing class BienvenidasPoliza {
    public static void EnvioEmail(Id objItemId) {
        try {
            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            Id senderEmailId = [SELECT Id FROM OrgWideEmailAddress WHERE Address = 'info@avanzaseguro.com' LIMIT 1].Id;

            Opportunity objItem = [SELECT Id, AccountId, Correo__c, Ramo__c FROM Opportunity WHERE Id = :objItemId LIMIT 1];

            if (objItem != null && objItem.Correo__c != null) {
                Account acc = [SELECT Name FROM Account WHERE Id = :objItem.AccountId LIMIT 1];
                
                String templateName;
                switch on objItem.Ramo__c {
                    when 'Daños', 'Gastos Medicos', 'Auto', 'RC', 'Mascota', 'Transportes', 'Fianzas', 'Administrativa', 'Accidentes', 'Viajes' {
                        templateName = 'Bienvenida_General_Poliza	';
                    }
                    when 'Vida', 'Ahorro', 'Retiro' {
                        templateName = 'Bienvenida_Vida_Poliza';
                    }
                    when null, '' {
                        System.debug('No valid Ramo__c value found.');
                        return; // Salir si no se encuentra un valor válido de Ramo__c
                    }
                }

                EmailTemplate et = [SELECT Id, Subject, Body FROM EmailTemplate WHERE DeveloperName = :templateName LIMIT 1];
                if (et != null) {
                    message.setToAddresses(new String[] { objItem.Correo__c });
                    message.setTemplateId(et.Id);
                    message.setOrgWideEmailAddressId(senderEmailId);
                    message.setWhatId(objItem.Id);
                    message.setSaveAsActivity(false);
                    message.setTargetObjectId(objItem.AccountId);
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
                    System.debug('No EmailTemplate found with the name: ' + templateName);
                }
            } else {
                System.debug('No Opportunity found or missing email address.');
            }
        } catch (Exception e) {
            System.debug('An error occurred: ' + e.getMessage());
        }
    }
    
    public static Map<ID, ContentVersion> getRelatedFilesByRecordId(String recordId) {
        List<ContentDocumentLink> files = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :recordId ORDER BY ContentDocument.CreatedDate ASC];
        List<ID> fileIDs = new List<ID>();
        for (ContentDocumentLink docLink : files) {
            fileIDs.add(docLink.ContentDocumentId);
        }

        List<ContentVersion> docs = [SELECT Id, ContentDocumentId, FileExtension, Title, VersionData, PathOnClient
                                     FROM ContentVersion WHERE ContentDocumentId IN :fileIDs ORDER BY ContentDocument.CreatedDate ASC];

        Map<ID, ContentVersion> mapIdTitle = new Map<ID, ContentVersion>();
        for (ContentVersion ctnVersion : docs) {
            mapIdTitle.put(ctnVersion.Id, ctnVersion);
        }

        return mapIdTitle;
    }
    
    public static List<Messaging.EmailFileAttachment> getAttachmentForEmail(Map<ID, ContentVersion> mapFile) {
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
        'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
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
        'php' => 'application/x-httpd-php',
        'ppt' => 'application/vnd.ms-powerpoint',
        'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
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
        'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'xml' => 'application/xml',
        'xul' => 'application/vnd.mozilla.xul+xml',
        'zip' => 'application/zip',
        '7z' => 'application/x-7z-compressed'
    };
}