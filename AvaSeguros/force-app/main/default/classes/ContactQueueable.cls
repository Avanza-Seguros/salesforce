public class ContactQueueable implements Queueable {
    
    private Set<Id> itemIds;
    private Boolean triggerEmailQueue = true; // Bandera para encolar emails después
    
    public ContactQueueable(Set<Id> itemIds) {
        this.itemIds = itemIds;
    }
    
    public ContactQueueable(Set<Id> itemIds, Boolean triggerEmailQueue) {
        this.itemIds = itemIds;
        this.triggerEmailQueue = triggerEmailQueue;
    }
    
    public void execute(QueueableContext qc) {
        try {
            // 1. Crear/obtener contactos (tu lógica existente)
            Map<Id, Contact> contactsCreated = ContactService.createAndRelateContacts(itemIds);
            
            // 2. Actualizar Items_Cases__c con Asegurado__c
            updateItemsWithContacts(contactsCreated);
            
            // 3. Si hay contactos creados y la bandera está activa, encolar emails
            if (triggerEmailQueue && !contactsCreated.isEmpty()) {
                System.debug('🔄 ContactQueueable completado, encolando QueueEnvioEmails...');
                
                Set<Id> itemsWithContact = contactsCreated.keySet();
                
                // Verificar límites antes de encolar
                if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                    QueueEnvioEmails emailJob = new QueueEnvioEmails(itemsWithContact);
                    System.enqueueJob(emailJob);
                    System.debug('✅ QueueEnvioEmails encolado para ' + itemsWithContact.size() + ' items');
                } else {
                    System.debug('⚠️ Límite alcanzado, no se pudo encolar QueueEnvioEmails');
                }
            }
            
        } catch(Exception e) {
            System.debug('❌ Error en ContactQueueable: ' + e.getMessage());
        }
    }
    
    private void updateItemsWithContacts(Map<Id, Contact> itemContactMap) {
        List<Items_Cases__c> toUpdate = new List<Items_Cases__c>();
        for (Id itemId : itemContactMap.keySet()) {
            Contact c = itemContactMap.get(itemId);
            if (c != null && c.Id != null) {
                toUpdate.add(new Items_Cases__c(
                    Id = itemId,
                    Asegurado__c = c.Id
                ));
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}