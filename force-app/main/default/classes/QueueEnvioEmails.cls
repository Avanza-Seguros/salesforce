public class QueueEnvioEmails implements Queueable {
    private Set<Id> itemIds;
    private String tipoEmail; // 'ALTA' o 'BAJA'
    
    public QueueEnvioEmails(Set<Id> itemIds, String tipoEmail) {
        System.debug('=== QUEUEENVIOEMAILS CREADO ===');
        this.itemIds = itemIds;
        this.tipoEmail = tipoEmail;
        System.debug('📨 QueueEnvioEmails creado para ' + itemIds.size() + ' items de tipo: ' + tipoEmail);
    }
    
    public void execute(QueueableContext context) {
        System.debug('=== QUEUEENVIOEMAILS EJECUTANDO ===');
        System.debug('Tipo: ' + tipoEmail);
        System.debug('Items: ' + itemIds.size());
        
        // Verificar contexto de envío
        if (!EmailContextControl.canBatchSend()) {
            System.debug('🚫 Envío desactivado por contexto');
            return;
        }
        
        if (itemIds == null || itemIds.isEmpty()) {
            System.debug('⚠️ No hay items para procesar');
            return;
        }
        
        // Obtener items actualizados
        List<Items_Cases__c> items = [SELECT Id, Estatus__c, Correo_electronico__c, Correo_Copia__c,
                                     Nombre_cuenta__c, RecordTypeId, Contacto__c, Tipo_de_peticion__c,
                                     Baja_Por_Defuncion__c, Categorias__c, Asegurado__c
                                     FROM Items_Cases__c 
                                     WHERE Id IN :itemIds];
        
        System.debug('Items en BD: ' + items.size());
        
        // Filtrar solo los que pueden recibir email
        List<Items_Cases__c> itemsParaEmail = new List<Items_Cases__c>();
        for (Items_Cases__c item : items) {
            System.debug('🔍 Evaluando item ' + item.Id + ' con Estatus: ' + item.Estatus__c);
            if (item.Estatus__c == 'Concluido' && EmailProcessingControl.canSendEmail(item.Id, 'QUEUEABLE')) {
                System.debug('✅ Item ' + item.Id + ' califica para email');
                itemsParaEmail.add(item);
            } else {
                System.debug('⚠️ Item ' + item.Id + ' no califica:');
                System.debug('   Estatus: ' + item.Estatus__c);
                System.debug('   canSendEmail: ' + EmailProcessingControl.canSendEmail(item.Id, 'QUEUEABLE'));
            }
        }
        System.debug('Items para email después de filtro: ' + itemsParaEmail);
        if (itemsParaEmail.isEmpty()) {
            System.debug('⚠️ No hay items válidos para enviar email');
            return;
        }
        
        System.debug('Items válidos para email: ' + itemsParaEmail.size());
        
        try {
            // Obtener templates
            Set<String> templateIds = EmailTemplateResolver.getRequiredTemplateIds(itemsParaEmail);
            System.debug('Templates requeridos: ' + templateIds);
            Map<String, EmailTemplate> templates = EnvioPlantillas.getTemplatesById(templateIds);
            System.debug('Templates obtenidos: ' + templates.keySet());
            // Construir y enviar emails
            List<Messaging.SingleEmailMessage> emails = EnvioPlantillas.construirEmails(itemsParaEmail, templates);
            System.debug('Emails construidos: ' + emails);
            System.debug('Emails construidos: ' + emails.size());
            
            if (!emails.isEmpty() && EmailContextControl.canBatchSend()) {
                System.debug('🚀 Enviando ' + emails.size() + ' emails...');
                EnvioPlantillas.enviarEmails(emails);
                System.debug('✅ ' + emails.size() + ' emails enviados');
                
                // Marcar como enviados en BD (si hay campo)
                for (Items_Cases__c item : itemsParaEmail) {
                    System.debug('Marcando item ' + item.Id + ' como email enviado');
                    EmailProcessingControl.markAsSent(item.Id);
                }
            } else {
                System.debug('⚠️ No se enviaron emails');
            }
            
        } catch (Exception e) {
            System.debug('❌ Error: ' + e.getMessage());
            System.debug('Stack: ' + e.getStackTraceString());
            
            // Para reintentos, marcar como no enviados
            for (Items_Cases__c item : itemsParaEmail) {
                System.debug('Marcando item ' + item.Id + ' como no enviado debido a error');
                EmailProcessingControl.markAsFailed(item.Id);
            }
        }
    }
}