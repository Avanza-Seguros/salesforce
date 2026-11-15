public with sharing class BienvenidasPoliza {
    // Oportunidades a las que ya se envió la bienvenida en esta transacción: el trigger puede volver a correr cuando
    // flujos o reglas actualizan la misma oportunidad, y no debe salir el correo dos veces.
    @TestVisible
    private static Set<Id> enviadas = new Set<Id>();

    public static void EnvioEmail(Id objItemId) {
        if (objItemId == null || enviadas.contains(objItemId)) { return; }
        enviadas.add(objItemId);
        try {
            Opportunity objItem = [SELECT Id, AccountId, Correo__c, Ramo__c, Contacto__c, Account.PersonContactId
                                   FROM Opportunity WHERE Id = :objItemId LIMIT 1];
            if (String.isBlank(objItem.Correo__c)) {
                System.debug('La oportunidad no tiene correo.');
                return;
            }
            String templateName = plantillaDe(objItem.Ramo__c);
            if (templateName == null) {
                System.debug('No valid Ramo__c value found.');
                return;
            }
            List<EmailTemplate> ets = [SELECT Id, Subject, Body, HtmlValue FROM EmailTemplate WHERE DeveloperName = :templateName LIMIT 1];
            if (ets.isEmpty()) {
                System.debug('No EmailTemplate found with the name: ' + templateName);
                return;
            }
            EmailTemplate et = ets[0];
            List<OrgWideEmailAddress> owe = [SELECT Id FROM OrgWideEmailAddress WHERE Address = 'info@avanzaseguro.com' LIMIT 1];

            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            // Se envía SOLO a Correo__c. El contacto se usa para llenar la plantilla pero no recibe otra copia.
            message.setToAddresses(new String[] { objItem.Correo__c });
            Id contactoId = contactoDe(objItem);
            if (contactoId != null) {
                message.setTemplateId(et.Id);
                message.setTargetObjectId(contactoId);
                message.setTreatTargetObjectAsRecipient(false);
                message.setWhatId(objItem.Id);
            } else {
                // Sin contacto no se puede usar la plantilla como tal: se manda su asunto y contenido.
                message.setSubject(et.Subject);
                if (String.isNotBlank(et.HtmlValue)) { message.setHtmlBody(et.HtmlValue); } else { message.setPlainTextBody(et.Body); }
            }
            if (!owe.isEmpty()) { message.setOrgWideEmailAddressId(owe[0].Id); }
            message.setSaveAsActivity(false);
            message.setUseSignature(false);
            message.setFileAttachments(getAttachmentForEmail(getRelatedFilesByRecordId(objItem.Id)));

            Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { message });
            if (results[0].success) {
                System.debug('The email was sent successfully.');
            } else {
                System.debug('The email failed to send: ' + results[0].errors[0].message);
            }
        } catch (Exception e) {
            System.debug('An error occurred: ' + e.getMessage());
        }
    }

    // Plantilla de bienvenida según el ramo (null si el ramo no tiene).
    @TestVisible
    private static String plantillaDe(String ramo) {
        switch on ramo {
            when 'Daños', 'Gastos Medicos', 'Auto', 'RC', 'Mascota', 'Transportes', 'Fianzas', 'Administrativa', 'Accidentes', 'Viajes' {
                return 'Bienvenida_General_Poliza';
            }
            when 'Vida', 'Ahorro', 'Retiro' {
                return 'Bienvenida_Vida_Poliza';
            }
            when else {
                return null;
            }
        }
    }

    // Contacto para llenar la plantilla: el de la oportunidad, el de la cuenta persona o el primero de la cuenta.
    @TestVisible
    private static Id contactoDe(Opportunity o) {
        if (o.Contacto__c != null) { return o.Contacto__c; }
        if (o.Account != null && o.Account.PersonContactId != null) { return o.Account.PersonContactId; }
        if (o.AccountId == null) { return null; }
        List<Contact> cs = [SELECT Id FROM Contact WHERE AccountId = :o.AccountId ORDER BY CreatedDate LIMIT 1];
        return cs.isEmpty() ? null : cs[0].Id;
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