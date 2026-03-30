public with sharing class EnvioPlantillasWrapper {
    
    // Flags para control de tests
    @TestVisible
    private static Boolean forceBulkError = false;
    @TestVisible
    private static Boolean forceIndividualError = false;
    @TestVisible
    private static Boolean skipEmailSend = false;
    
    /* =====================================================
       MÉTODO BULK PRINCIPAL (para Batch)
       ===================================================== */
    
    public static void enviarEmailsBulk(List<Items_Cases__c> items) {
        System.debug('================= ENVIO EMAILS BULK =================');
        System.debug('forceBulkError: ' + forceBulkError);
        System.debug('forceIndividualError: ' + forceIndividualError);
        System.debug('skipEmailSend: ' + skipEmailSend);
        if (Test.isRunningTest() && forceBulkError) {
            throw new TestException('Forced bulk error for testing');
        }
        
        if (Test.isRunningTest() && skipEmailSend) {
            System.debug('Test mode: Skipping actual email send for ' + items.size() + ' items');
            return;
        }
        
        if (items == null || items.isEmpty()) {
            System.debug('⚠️ No hay items para enviar');
            return;
        }
        
        if (!EmailContextControl.canBatchSend()) {
            System.debug('🚫 Envío de correos bloqueado por contexto');
            return;
        }
        
        try {
            // Obtener templates necesarios
            Set<String> templateIds = EmailTemplateResolver.getRequiredTemplateIds(items);
            System.debug('Templates requeridas: ' + templateIds);
            Map<String, EmailTemplate> templates = EnvioPlantillas.getTemplatesById(templateIds);
            System.debug('Templates obtenidas: ' + templates.keySet());
            // Construir y enviar emails
            List<Messaging.SingleEmailMessage> emails = EnvioPlantillas.construirEmails(items, templates);
            System.debug('Emails construidos: ' + emails.size());
            if (!emails.isEmpty()) {
                EnvioPlantillas.enviarEmails(emails);
                System.debug('✅ ' + emails.size() + ' emails enviados exitosamente');
            }
            
        } catch (Exception e) {
            System.debug('🔥 Error en envío bulk: ' + e.getMessage());
            throw e;
        }
    }
    
    /* =====================================================
       MÉTODO INDIVIDUAL (para Trigger/otros)
       ===================================================== */
    
    public static void enviarEmailIndividual(Items_Cases__c item) {
        if (Test.isRunningTest() && forceIndividualError) {
            throw new TestException('Forced individual error for testing');
        }
        
        if (Test.isRunningTest() && skipEmailSend) {
            System.debug('Test mode: Skipping individual email send for item: ' + item.Id);
            return;
        }
        
        if (item == null || String.isBlank(item.Correo_electronico__c)) {
            System.debug('⚠️ Item nulo o sin email');
            return;
        }
        
        if (!EmailContextControl.canTriggerSend()) {
            System.debug('🚫 Envío individual bloqueado por contexto');
            return;
        }
        
        try {
            List<Items_Cases__c> items = new List<Items_Cases__c>{ item };
            Map<Id, List<ContentVersion>> allAttachments = EnvioPlantillas.getAllAttachmentsForItems(items);
            List<ContentVersion> itemAttachments = allAttachments.get(item.Id);
            EnvioPlantillas.enviarEmailIndividual(item, itemAttachments);
            System.debug('✅ Email individual enviado para: ' + item.Correo_electronico__c);
            
        } catch (Exception e) {
            System.debug('❌ Error en envío individual: ' + e.getMessage());
            throw e;
        }
    }
    
    /* =====================================================
       MÉTODO PARA TRIGGER (cuando se inserta/actualiza un item)
       ===================================================== */
    
    public static void enviarEmailDesdeTrigger(List<Items_Cases__c> itemsNuevos, Map<Id, Items_Cases__c> itemsAntiguos) {
        if (Test.isRunningTest() && skipEmailSend) {
            System.debug('Test mode: Skipping trigger email send');
            return;
        }
        
        List<Items_Cases__c> itemsParaEnviar = new List<Items_Cases__c>();
        
        for (Items_Cases__c itemNuevo : itemsNuevos) {
            Items_Cases__c itemAntiguo = itemsAntiguos != null ? itemsAntiguos.get(itemNuevo.Id) : null;
            
            // Lógica para determinar si enviar email desde trigger
            if (debeEnviarEmailDesdeTrigger(itemNuevo, itemAntiguo)) {
                itemsParaEnviar.add(itemNuevo);
            }
        }
        
        if (!itemsParaEnviar.isEmpty()) {
            // Si son pocos, enviar individualmente desde trigger
            for (Items_Cases__c item : itemsParaEnviar) {
                enviarEmailIndividual(item);
            }
        }
    }
    
    /* =====================================================
       MÉTODOS AUXILIARES
       ===================================================== */
    
    private static Boolean debeEnviarEmailDesdeTrigger(Items_Cases__c itemNuevo, Items_Cases__c itemAntiguo) {
        // Ejemplo de lógica para trigger:
        // 1. Cambió el estatus a "En proceso"
        // 2. Se acaba de crear y tiene email
        // 3. Cambió algún campo crítico
        
        if (itemAntiguo == null) {
            // Es nuevo - verificar si debe enviar inmediatamente
            return itemNuevo.Estatus__c == 'En proceso' && 
                   String.isNotBlank(itemNuevo.Correo_electronico__c);
        } else {
            // Es actualización - verificar cambio de estatus
            return itemNuevo.Estatus__c == 'En proceso' && 
                   itemAntiguo.Estatus__c != 'En proceso' &&
                   String.isNotBlank(itemNuevo.Correo_electronico__c);
        }
    }
    
    private static void lanzarBatchDesdeTrigger(List<Items_Cases__c> items) {
        // Para muchos items desde trigger, usar batch async
        List<Id> itemIds = new List<Id>();
        for (Items_Cases__c item : items) {
            itemIds.add(item.Id);
        }
        
        // Puedes usar Invocable_EnviarEmails o lanzar batch directamente
        try {
            Invocable_EnviarEmails.ejecutarBatch(itemIds);
            System.debug('✅ Batch lanzado desde trigger para ' + items.size() + ' items');
        } catch (Exception e) {
            System.debug('❌ Error lanzando batch desde trigger: ' + e.getMessage());
        }
    }
    
    /* =====================================================
       MÉTODOS PARA TESTS
       ===================================================== */
    
    public static void resetTestFlags() {
        forceBulkError = false;
        forceIndividualError = false;
        skipEmailSend = false;
    }
    
    public static void enableTestMode() {
        skipEmailSend = true;
    }
    
    public static void disableTestMode() {
        skipEmailSend = false;
    }
    
    /* =====================================================
       CLASE DE EXCEPCIÓN PARA TESTS
       ===================================================== */
    
    public class TestException extends Exception {}
}