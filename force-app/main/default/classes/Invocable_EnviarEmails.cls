public with sharing class Invocable_EnviarEmails {
    
    @InvocableMethod(label='Ejecutar Batch Envio Emails' 
                    description='Marca items para procesar y ejecuta batch' 
                    category='Items_Cases')
    public static void ejecutarBatch(List<Id> itemIds) {
        System.debug('===== EJECUTANDO BATCH PARA ENVIO DE EMAILS =====');
        System.debug('Cantidad de items: ' + (itemIds != null ? itemIds.size() : 0));
        
        if (itemIds == null || itemIds.isEmpty()) {
            System.debug('⚠️ No hay items para procesar');
            return;
        }
        
        // Verificar que los items existen y están en estado correcto
        List<Items_Cases__c> existingItems = [
            SELECT Id, Estatus__c, Correo_electronico__c 
            FROM Items_Cases__c 
            WHERE Id IN :itemIds 
            AND Estatus__c = 'En proceso'
        ];
        
        if (existingItems.isEmpty()) {
            System.debug('⚠️ No hay items pendientes para procesar');
            return;
        }
        
        // Marcar los items para procesar en el batch
        List<Items_Cases__c> itemsToMark = new List<Items_Cases__c>();
        for (Items_Cases__c item : existingItems) {
            itemsToMark.add(new Items_Cases__c(
                Id = item.Id,
                Procesar_Batch__c = true
            ));
        }
        
        try {
            update itemsToMark;
            System.debug('✅ Items marcados para procesar: ' + itemsToMark.size());
            
            // Ejecutar batch inmediatamente para estos items
            BatchEnvioEmails batch = new BatchEnvioEmails();
            batch.setItemIds(itemIds); // Pasar IDs específicos
            
            // Ejecutar con tamaño de lote apropiado
            Integer batchSize = 50; // Ajustar según límites de Salesforce
            Database.executeBatch(batch, batchSize);
            
            System.debug('✅ Batch ejecutado con ' + itemsToMark.size() + ' items y tamaño de lote ' + batchSize);
            
        } catch (Exception e) {
            System.debug('🔥 Error al ejecutar batch: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            throw new AuraHandledException('Error al procesar items: ' + e.getMessage());
        }
    }
}