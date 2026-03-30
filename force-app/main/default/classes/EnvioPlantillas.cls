public with sharing class EnvioPlantillas {

    /* =====================================================
       API PRINCIPAL (BULK)
       ===================================================== */
    private static final String DEFAULT_EMAIL = 'info@avanzaseguro.com';
    
    // Cache para almacenar archivos ya consultados
    private static Map<Id, List<ContentVersion>> fileCache = new Map<Id, List<ContentVersion>>();

    public static List<Messaging.SingleEmailMessage> construirEmails(List<Items_Cases__c> items, Map<String, EmailTemplate> templatesByName) {
        System.debug('::: Iniciando construirEmails :::');
        System.debug('📧 Construyendo emails para ' + items.size() + ' items');
        
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        if (items == null || items.isEmpty()) {
            System.debug('📧 Lista de items vacía');
            return emails;
        }

        // PRIMERO: Obtener TODOS los archivos adjuntos en una sola consulta
        System.debug('📊 Precargando archivos adjuntos...');
        Map<Id, List<ContentVersion>> allAttachments = getAllAttachmentsForItems(items);
        System.debug('📊 Archivos precargados para ' + allAttachments.size() + ' items');

        // SEGUNDO: Construir emails usando los datos precargados
        Integer processedCount = 0;
        
        for (Items_Cases__c item : items) {
            processedCount++;
            
            System.debug('🔍 Procesando item ' + processedCount + ' de ' + items.size() + ': ' + item.Id);
            
            if (String.isBlank(item.Correo_electronico__c)) {
                continue;
            }
            
            // Obtener adjuntos del cache
            List<ContentVersion> itemAttachments = allAttachments.get(item.Id);
            if(item.Tipo_de_peticion__c == 'Baja') {
                enviarEmailIndividual(item, itemAttachments);
            } else {
                Messaging.SingleEmailMessage email = construirEmailControlado(item, templatesByName, itemAttachments);
                if (email != null) emails.add(email);
            }
            
            // Verificar límites
            if (Limits.getQueries() > 180) {
                System.debug('⚠️ ADVERTENCIA: Límite de SOQL queries cercano (' + Limits.getQueries() + ')');
                break;
            }
        }
        
        System.debug('📧 === FIN construirEmails ===');
        System.debug('📧 Total emails construidos: ' + emails.size());
        System.debug('📊 SOQL queries utilizadas: ' + Limits.getQueries());
        System.debug('📊 Heap size final: ' + Limits.getHeapSize());
        
        return emails;
    }

    /* =====================================================
       MÉTODO PARA OBTENER TODOS LOS ARCHIVOS EN UNA SOLA CONSULTA
       ===================================================== */
    
    public static Map<Id, List<ContentVersion>> getAllAttachmentsForItems(List<Items_Cases__c> items) {
        Map<Id, List<ContentVersion>> result = new Map<Id, List<ContentVersion>>();
        
        if (items == null || items.isEmpty()) {
            return result;
        }
        
        Set<Id> itemIds = new Set<Id>();
        for (Items_Cases__c item : items) {
            itemIds.add(item.Id);
        }
        
        try {
            // Obtener TODOS los ContentDocumentLink en una sola consulta
            List<ContentDocumentLink> allLinks = [
                SELECT ContentDocumentId, LinkedEntityId 
                FROM ContentDocumentLink 
                WHERE LinkedEntityId IN :itemIds
                LIMIT 500
            ];
            
            System.debug('🔍 Total de ContentDocumentLink encontrados: ' + allLinks.size());
            
            if (allLinks.isEmpty()) {
                return result;
            }
            
            // Agrupar por LinkedEntityId
            Map<Id, Set<Id>> documentIdsByItem = new Map<Id, Set<Id>>();
            for (ContentDocumentLink link : allLinks) {
                if (!documentIdsByItem.containsKey(link.LinkedEntityId)) {
                    documentIdsByItem.put(link.LinkedEntityId, new Set<Id>());
                }
                documentIdsByItem.get(link.LinkedEntityId).add(link.ContentDocumentId);
            }
            
            // Obtener TODOS los ContentVersion en una sola consulta
            Set<Id> allDocIds = new Set<Id>();
            for (Set<Id> docIds : documentIdsByItem.values()) {
                allDocIds.addAll(docIds);
            }
            
            List<ContentVersion> allVersions = [
                SELECT Id, ContentDocumentId, FileExtension, Title, 
                    VersionData, PathOnClient, ContentSize
                FROM ContentVersion
                WHERE ContentDocumentId IN :allDocIds
                AND IsLatest = true
                ORDER BY ContentSize ASC
                LIMIT 200
            ];
            
            System.debug('🔍 Total de ContentVersion encontrados: ' + allVersions.size());
            
            // Organizar por ContentDocumentId para búsqueda rápida
            Map<Id, ContentVersion> versionsByDocId = new Map<Id, ContentVersion>();
            for (ContentVersion ver : allVersions) {
                versionsByDocId.put(ver.ContentDocumentId, ver);
            }
            
            // Asignar archivos a cada item
            for (Id itemId : documentIdsByItem.keySet()) {
                List<ContentVersion> itemFiles = new List<ContentVersion>();
                Set<Id> docIdsForItem = documentIdsByItem.get(itemId);
                
                for (Id docId : docIdsForItem) {
                    if (versionsByDocId.containsKey(docId)) {
                        itemFiles.add(versionsByDocId.get(docId));
                    }
                }
                
                if (!itemFiles.isEmpty()) {
                    result.put(itemId, itemFiles);
                }
            }
            
        } catch (Exception e) {
            System.debug('❌ Error obteniendo archivos adjuntos: ' + e.getMessage());
        }
        
        return result;
    }

    /* =====================================================
       CONSTRUIR EMAIL CON CONTROL DE MEMORIA Y ADJUNTOS
       ===================================================== */
    
    public static Messaging.SingleEmailMessage construirEmailControlado(Items_Cases__c item, Map<String, EmailTemplate> templatesByName, List<ContentVersion> attachments) {
        System.debug('📧 Construyendo email controlado para: ' + item.Id);
        
        String templateIdentifier = EmailTemplateResolver.resolveTemplateName(item);

        EmailTemplate template = new EmailTemplate();
        if(templatesByName.containsKey(templateIdentifier)) {
            template = templatesByName.get(templateIdentifier);
        } else {
            System.debug('⚠️ Template no encontrado para identificador: ' + templateIdentifier);
            template = null;
        }
        
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        
        if (template != null) {
            email.setTemplateId(template.Id);
            if (item.Contacto__c != null) {
                email.setTargetObjectId(item.Contacto__c);
            } else {
                email.setTargetObjectId(item.Asegurado__c);
            }
        }
        
        email.setWhatId(item.Id);
        email.setSaveAsActivity(false);
        
        // Configurar direcciones de email
        List<String> toAddresses = getEmailAddresses(item.Correo_electronico__c);
        if (!toAddresses.isEmpty()) {
            email.setToAddresses(toAddresses);
        }
        List<String> toAddressesCC = getEmailAddresses(item.Correo_Copia__c);
        if (!toAddressesCC.isEmpty()) {
            email.setCcAddresses(toAddressesCC);
        }
        
        // Configurar remitente
        Id senderEmailId = getSenderEmailId();
        if (senderEmailId != null) {
            email.setOrgWideEmailAddressId(senderEmailId);
        }

        try {
            email.setFileAttachments(createEmailAttachments(attachments));
        }catch(Exception e) {
            System.debug('No se encontraron archivos adjuntos');
        }
        
        return email;
    }

    /* =====================================================
       ENVÍO INDIVIDUAL OPTIMIZADO
       ===================================================== */
    
    public static void enviarEmailIndividual(Items_Cases__c item, List<ContentVersion> attachments) {
        System.debug('::: Iniciando enviarEmailIndividual :::');
        
        if (item == null || String.isBlank(item.Correo_electronico__c)) {
            return;
        }

        if (!EmailContextControl.canBatchSend()) {
            System.debug('🚫 Envío de correos bloqueado por contexto');
            return;
        }

        try {
            EmailTemplate template;
            if(item.Tipo_de_peticion__c == 'Baja') {
                template = [
                    SELECT Id, Subject, Body, HtmlValue, DeveloperName, Name, IsActive
                    FROM EmailTemplate
                    WHERE DeveloperName = 'Bajas'
                    LIMIT 1
                ];
            } else {
                String templateId = EmailTemplateResolver.resolveTemplateName(item);
                if (String.isNotBlank(templateId)) {
                    template = [
                        SELECT Id, Subject, Body, HtmlValue, DeveloperName, Name, IsActive
                        FROM EmailTemplate
                        WHERE Id = :templateId
                        LIMIT 1
                    ];
                }
            }
            
            if (template != null) {
                Messaging.SingleEmailMessage email = construirEmailIndividual(item, template, attachments);
                if (email != null) {
                    Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{email}, true);
                    System.debug('✅ Email individual enviado para: ' + item.Correo_electronico__c);
                }
            } else {
                System.debug('⚠️ No se encontró template para el item');
            }
        } catch (Exception e) {
            System.debug('🔥 Error enviando email individual: ' + e.getMessage());
            // No lanzar excepción para no detener el proceso batch
        }
    }

    /* =====================================================
       MÉTODOS AUXILIARES OPTIMIZADOS
       ===================================================== */
    
    public static Messaging.SingleEmailMessage construirEmailIndividual(Items_Cases__c item, EmailTemplate template, List<ContentVersion> attachments) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        
        if (template.Id != null) {
            email.setTemplateId(template.Id);
            if (item.Contacto__c != null) {
                email.setTargetObjectId(item.Contacto__c);
            } else {
                email.setTargetObjectId(item.Asegurado__c);
            }
        }
        
        email.setWhatId(item.Id);
        email.setSaveAsActivity(false);
        
        List<String> toAddresses = getEmailAddresses(item.Correo_electronico__c);
        if (toAddresses.isEmpty()) {
            return null;
        }
        List<String> toAddressesCC = new List<String>();
        if(item.Correo_Copia__c != null) {
            email.setCcAddresses(getEmailAddresses(item.Correo_Copia__c));
        }
        
        email.setToAddresses(toAddresses);
        email.setCcAddresses(toAddressesCC);
        
        // Agregar adjuntos si existen
        try {
            email.setFileAttachments(createEmailAttachments(attachments));
        }catch(Exception e) {
            System.debug('No se encontraron archivos adjuntos');
        }
        
        Id senderEmailId = getSenderEmailId();
        if (senderEmailId != null) {
            email.setOrgWideEmailAddressId(senderEmailId);
        }
        
        return email;
    }
    
    public static List<String> getEmailAddresses(String emailString) {
        List<String> toAddresses = new List<String>();
        if (String.isNotBlank(emailString)) {
            String[] emails = emailString.split(',');
            for (String em : emails) {
                String cleanEmail = em.trim();
                if (String.isNotBlank(cleanEmail)) {
                    toAddresses.add(cleanEmail);
                }
            }
        }
        return toAddresses;
    }
    
    public static List<Messaging.EmailFileAttachment> createEmailAttachments(List<ContentVersion> versions) {
        List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();
        
        if (versions == null || versions.isEmpty()) {
            return attachments;
        }
        
        for (ContentVersion ver : versions) {
            try {
                Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
                att.setFileName(ver.PathOnClient);
                
                if (ver.VersionData != null) {
                    att.setBody(ver.VersionData);
                    att.setContentType(getContentType(ver.FileExtension));
                    
                    attachments.add(att);
                }
            } catch (Exception e) {
                System.debug('⚠️ Error creando adjunto: ' + e.getMessage());
            }
        }
        
        return attachments;
    }

    /* =====================================================
       MÉTODOS RESTANTES (sin cambios importantes)
       ===================================================== */
    
    public static void enviarEmails(List<Messaging.SingleEmailMessage> emails) {
        System.debug('::: Iniciando enviarEmails :::');
        if (emails == null || emails.isEmpty()) {
            return;
        }
        
        if (!EmailContextControl.canBatchSend()) {
            System.debug('🚫 Envío de correos bloqueado por contexto');
            return;
        }
        
        try {
            Messaging.sendEmail(emails, true);
            System.debug('✅ ' + emails.size() + ' emails enviados exitosamente');
        } catch (Exception e) {
            System.debug('🔥 Error enviando emails: ' + e.getMessage());
        }
    }
    
    public static Map<String, EmailTemplate> getTemplatesById(Set<String> templateIds) {
        Map<String, EmailTemplate> templatesById = new Map<String, EmailTemplate>();
        
        if (templateIds == null || templateIds.isEmpty()) {
            return templatesById;
        }
        
        try {
            List<EmailTemplate> templates = [
                SELECT Id, DeveloperName, Subject, Body, HtmlValue, Name
                FROM EmailTemplate
                WHERE DeveloperName IN :templateIds OR Id IN :templateIds
            ];
            
            for (EmailTemplate template : templates) {
                templatesById.put(template.Id, template);
            }
        } catch (Exception e) {
            System.debug('🔥 Error obteniendo templates: ' + e.getMessage());
        }
        
        return templatesById;
    }
    
    public static void enviarEmailsBulk(List<Items_Cases__c> items) {
        System.debug('::: Iniciando enviarEmailsBulk :::');
        
        if (items == null || items.isEmpty()) {
            return;
        }
        
        if (!EmailContextControl.canBatchSend()) {
            System.debug('🚫 Envío de correos bloqueado por contexto');
            return;
        }
        
        // Limitar número de items procesados por batch
        Integer maxItems = Math.min(items.size(), 100); // Procesar máximo 100 items por batch
        List<Items_Cases__c> itemsToProcess = new List<Items_Cases__c>();
        
        for (Integer i = 0; i < maxItems; i++) {
            itemsToProcess.add(items[i]);
        }
        
        Set<String> templateIds = EmailTemplateResolver.getRequiredTemplateIds(itemsToProcess);
        
        if (templateIds.isEmpty()) {
            System.debug('⚠️ No se encontraron templates asignados');
            return;
        }
        
        Map<String, EmailTemplate> templatesById = getTemplatesById(templateIds);
        
        if (templatesById.isEmpty()) {
            System.debug('⚠️ No se pudieron cargar los templates');
            return;
        }
        
        List<Messaging.SingleEmailMessage> emails = construirEmails(itemsToProcess, templatesById);
        
        if (!emails.isEmpty()) {
            enviarEmails(emails);
        }
    }
    
    public static Id getSenderEmailId() {
        try {
            List<OrgWideEmailAddress> addresses = [
                SELECT Id, Address 
                FROM OrgWideEmailAddress 
                WHERE Address = :DEFAULT_EMAIL 
                LIMIT 1
            ];
            
            if (!addresses.isEmpty()) {
                return addresses[0].Id;
            }
        } catch (Exception e) {
            System.debug('Error obteniendo sender email: ' + e.getMessage());
        }
        return null;
    }
    
    public static String getContentType(String fileExtension) {
        if (String.isBlank(fileExtension)) {
            return 'application/octet-stream';
        }
        
        Map<String, String> fileMimeTypes = new Map<String, String>{
            'pdf' => 'application/pdf',
            'png' => 'image/png', 
            'jpg' => 'image/jpeg', 
            'jpeg' => 'image/jpeg',
            'gif' => 'image/gif',
            'txt' => 'text/plain', 
            'csv' => 'text/csv',
            'doc' => 'application/msword', 
            'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'xls' => 'application/vnd.ms-excel',
            'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'ppt' => 'application/vnd.ms-powerpoint',
            'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation'
        };
        
        String extension = fileExtension.toLowerCase();
        return fileMimeTypes.get(extension) != null ? 
               fileMimeTypes.get(extension) : 'application/octet-stream';
    }
}