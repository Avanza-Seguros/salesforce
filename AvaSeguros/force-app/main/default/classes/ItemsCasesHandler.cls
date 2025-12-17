public class ItemsCasesHandler {
    
    public static void processTrigger(List<Items_Cases__c> newItems, Map<Id, Items_Cases__c> oldMap, Boolean isInsert, Boolean isUpdate) {
        System.debug('newItems: ' + newItems);
        System.debug('oldMap: ' + oldMap);
        // Inicializar RecordTypes
        RecordTypeHelper.RecordTypeConfig config = RecordTypeHelper.getRecordTypeConfig();
        
        // Inicializar sets
        Set<Id> itemsForContact = new Set<Id>();
        Set<Id> itemsForEmailAlta = new Set<Id>();
        Set<Id> itemsForEmailBaja = new Set<Id>();
        
        // Evaluar cada item
        for (Items_Cases__c newItem : newItems) {
            Items_Cases__c oldItem = isUpdate ? oldMap.get(newItem.Id) : null;
            
            // 1. Evaluar para creación de contactos
            if (ContactServiceEvaluator.shouldCreateContact(newItem, oldItem, isInsert)) {
                itemsForContact.add(newItem.Id);
            }
            
            // 2. Evaluar para emails de Alta
            if (isUpdate && EmailEvaluator.shouldSendAltaEmail(newItem, oldItem, config.altaRecordTypeIds)) {
                itemsForEmailAlta.add(newItem.Id);
            }
            
            // 3. Evaluar para emails de Baja
            if (isUpdate && EmailEvaluator.shouldSendBajaEmail(newItem, oldItem, config.bajaRecordTypeIds)) {
                itemsForEmailBaja.add(newItem.Id);
            }
        }
        
        // Ejecutar procesos
        executeProcesses(itemsForContact, itemsForEmailAlta, itemsForEmailBaja);
    }
    
    private static void executeProcesses(Set<Id> contactItems, Set<Id> altaItems, Set<Id> bajaItems) {
        System.debug('Inicia executeProcesses');
        System.debug('contactItems: ' + contactItems);
        System.debug('altaItems: ' + altaItems);
        System.debug('bajaItems: ' + bajaItems);
        // 1. Proceso de Contactos (Queueable)
        if (!contactItems.isEmpty()) {
            enqueueIfPossible(new ContactQueueable(contactItems), 'ContactQueueable');
        }
        
        // 2. Proceso de Emails Alta (Queueable)
        if (!altaItems.isEmpty()) {
            enqueueIfPossible(new QueueEnvioEmails(altaItems), 'QueueEnvioEmails (Alta)');
        }
        
        // 3. Proceso de Emails Baja (Síncrono)
        if (!bajaItems.isEmpty()) {
            for (Id itemId : bajaItems) {
                try {
                    EnvioBajas.BajasEmail(itemId);
                } catch(Exception e) {
                    System.debug('Error en BajasEmail: ' + e.getMessage());
                }
            }
        }
    }
    
    private static void enqueueIfPossible(Queueable job, String jobName) {
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(job);
            System.debug(jobName + ' encolado');
        } else {
            System.debug('No se pudo encolar ' + jobName + ' - límite alcanzado');
        }
    }
}