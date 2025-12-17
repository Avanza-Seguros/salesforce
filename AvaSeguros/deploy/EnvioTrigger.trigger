trigger EnvioTrigger on Items_Cases__c (after update) {
    // Este trigger se activa cuando ContactQueueable actualiza Asegurado__c
    // y envía los emails automáticos
    
    Set<Id> itemsForAutoEmail = new Set<Id>();
    Set<Id> altaRecordTypeIds = getAltaRecordTypeIds();
    
    for (Items_Cases__c newItem : Trigger.new) {
        Items_Cases__c oldItem = Trigger.oldMap.get(newItem.Id);
        
        // Detectar si se asignó un contacto (Asegurado__c)
        Boolean contactAssigned = (oldItem.Asegurado__c == null && newItem.Asegurado__c != null);
        
        // Si se asignó contacto y es RecordType de Alta, enviar email
        if (contactAssigned && 
            altaRecordTypeIds.contains(newItem.RecordTypeId) &&
            String.isNotBlank(newItem.Correo_electronico__c)) {
            
            itemsForAutoEmail.add(newItem.Id);
        }
    }
    
    // Encolar emails automáticos
    if (!itemsForAutoEmail.isEmpty()) {
        System.debug('🚀 Activando QueueEnvioEmails para ' + itemsForAutoEmail.size() + ' items');
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new QueueEnvioEmails(itemsForAutoEmail));
        }
    }
    
    private static Set<Id> getAltaRecordTypeIds() {
        Set<Id> ids = new Set<Id>();
        String[] names = new String[]{'Alta', 'Alta solicitada', 'Alta con Dependientes'};
        for (String name : names) {
            Schema.RecordTypeInfo info = Schema.SObjectType.Items_Cases__c.getRecordTypeInfosByName().get(name);
            if (info != null) ids.add(info.getRecordTypeId());
        }
        return ids;
    }
}