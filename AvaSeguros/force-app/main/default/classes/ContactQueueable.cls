public class ContactQueueable implements Queueable, Database.AllowsCallouts {
    
    private Set<Id> itemIds;
    private Integer retryCount = 0;
    private static final Integer MAX_RETRIES = 3;
    
    // Constructor principal
    public ContactQueueable(Set<Id> itemIds) {
        this.itemIds = itemIds;
        this.retryCount = 0;
    }
    
    // Constructor para reintentos
    public ContactQueueable(Set<Id> itemIds, Integer retryCount) {
        this.itemIds = itemIds;
        this.retryCount = retryCount;
    }
    
    public void execute(QueueableContext context) {
        try {
            // 1. Validar que no estamos en un bucle infinito
            if (retryCount >= MAX_RETRIES) {
                System.debug('Máximo de reintentos alcanzado para items: ' + itemIds);
                logError('Máximo de reintentos alcanzado', itemIds);
                return; // FINALIZA la ejecución
            }
            
            // 2. Verificar si hay items para procesar
            if (itemIds == null || itemIds.isEmpty()) {
                System.debug('No hay items para procesar');
                return; // FINALIZA la ejecución
            }
            
            // 3. Consultar items actuales
            List<Items_Cases__c> items = [
                SELECT Id, Nombre__c, Apellido_paterno__c, 
                       Apellido_materno__c, Correo_electronico__c,
                       Asegurado__c, Nombre_cuenta__c // Verificar si ya tiene contacto
                FROM Items_Cases__c
                WHERE Id IN :itemIds
                AND Asegurado__c = null // Solo procesar si no tiene contacto
                LIMIT 100 // LIMITE para evitar sobrecarga
            ];
            
            // 4. Si no hay items válidos, finalizar
            if (items.isEmpty()) {
                System.debug('Todos los items ya tienen contacto asignado o no son válidos');
                return; // FINALIZA la ejecución
            }
            
            // 5. Procesar contactos
            Map<Id, Contact> itemContactMap = processContacts(items);
            
            // 6. Actualizar items con los contactos
            updateItemsWithContacts(itemContactMap);
            
            // 7. Verificar si quedan items pendientes (lote parcial)
            Set<Id> processedIds = itemContactMap.keySet();
            Set<Id> remainingIds = new Set<Id>();
            
            for (Id itemId : itemIds) {
                if (!processedIds.contains(itemId)) {
                    remainingIds.add(itemId);
                }
            }
            
            // 8. Si hay items pendientes, encolar nuevo job (con límite)
            if (!remainingIds.isEmpty() && retryCount < MAX_RETRIES - 1) {
                System.debug('Procesando lote pendiente: ' + remainingIds.size() + ' items');
                enqueueNextJob(remainingIds, retryCount + 1);
            } else if (!remainingIds.isEmpty()) {
                System.debug('Items no procesados después de reintentos: ' + remainingIds);
                logError('Items no procesados después de ' + MAX_RETRIES + ' reintentos', remainingIds);
            }
            
        } catch(Exception e) {
            // Manejo de errores con reintento controlado
            System.debug('Error en ContactQueueable: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            
            if (retryCount < MAX_RETRIES) {
                // Reintentar
                System.debug('Reintentando (intento ' + (retryCount + 1) + ' de ' + MAX_RETRIES + ')');
                enqueueNextJob(itemIds, retryCount + 1);
            } else {
                // Límite de reintentos alcanzado
                logError('Error después de ' + MAX_RETRIES + ' reintentos: ' + e.getMessage(), itemIds);
            }
        }
    }
    
    private Map<Id, Contact> processContacts(List<Items_Cases__c> items) {
        // Tu lógica de procesamiento de contactos aquí
        Map<Id, Contact> result = new Map<Id, Contact>();
        
        try {
            // Implementar la lógica de ContactService.processContacts
            // pero dentro de este método
            Map<String, Contact> existingContactsMap = new Map<String, Contact>();
            List<Contact> contactsToCreate = new List<Contact>();
            
            // 1. Recolectar datos para búsqueda
            Set<String> nombres = new Set<String>();
            Set<String> apellidos = new Set<String>();
            
            for (Items_Cases__c item : items) {
                nombres.add(item.Nombre__c);
                apellidos.add(item.Apellido_paterno__c);
            }
            
            // 2. Buscar contactos existentes
            List<Contact> existingContacts = [
                SELECT Id, FirstName, LastName, Apellido_Materno__c, Email, AccountId
                FROM Contact
                WHERE FirstName IN :nombres
                AND LastName IN :apellidos
            ];
            
            for (Contact c : existingContacts) {
                String key = createKey(c.FirstName, c.LastName, c.Apellido_Materno__c);
                existingContactsMap.put(key, c);
            }
            
            // 3. Procesar cada item
            Map<String, Id> keyToItemIdMap = new Map<String, Id>();
            
            for (Items_Cases__c item : items) {
                String contactKey = createKey(item);
                keyToItemIdMap.put(contactKey, item.Id);
                
                if (!existingContactsMap.containsKey(contactKey)) {
                    Contact newContact = new Contact(
                        FirstName = item.Nombre__c,
                        LastName = item.Apellido_paterno__c,
                        AccountId = item.Nombre_cuenta__c,
                        Apellido_Materno__c = item.Apellido_materno__c,
                        Email = item.Correo_electronico__c
                    );
                    contactsToCreate.add(newContact);
                    existingContactsMap.put(contactKey, newContact);
                }
            }
            
            // 4. Insertar nuevos contactos
            if (!contactsToCreate.isEmpty()) {
                insert contactsToCreate;
            }
            
            // 5. Crear mapa de resultados
            for (Items_Cases__c item : items) {
                String contactKey = createKey(item);
                Contact assignedContact = existingContactsMap.get(contactKey);
                if (assignedContact != null) {
                    result.put(item.Id, assignedContact);
                }
            }
            
        } catch(Exception e) {
            System.debug('Error en processContacts: ' + e.getMessage());
            throw e; // Propagar el error para manejo en execute()
        }
        
        return result;
    }
    
    private void updateItemsWithContacts(Map<Id, Contact> itemContactMap) {
        if (itemContactMap == null || itemContactMap.isEmpty()) return;
        
        List<Items_Cases__c> itemsToUpdate = new List<Items_Cases__c>();
        
        for (Id itemId : itemContactMap.keySet()) {
            Contact c = itemContactMap.get(itemId);
            if (c != null && c.Id != null) {
                itemsToUpdate.add(new Items_Cases__c(
                    Id = itemId,
                    Asegurado__c = c.Id
                ));
            }
        }
        
        if (!itemsToUpdate.isEmpty()) {
            update itemsToUpdate;
        }
    }
    
    private void enqueueNextJob(Set<Id> nextItemIds, Integer nextRetryCount) {
        // Verificar límites antes de encolar
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            ContactQueueable nextJob = new ContactQueueable(nextItemIds, nextRetryCount);
            System.enqueueJob(nextJob);
            System.debug('Job encolado para ' + nextItemIds.size() + ' items, reintento: ' + nextRetryCount);
        } else {
            System.debug('Límite de Queueable Jobs alcanzado, no se puede encolar más trabajos');
            logError('Límite de Queueable Jobs alcanzado', nextItemIds);
        }
    }
    
    private String createKey(Items_Cases__c item) {
        return createKey(item.Nombre__c, item.Apellido_paterno__c, item.Apellido_materno__c);
    }
    
    private String createKey(String firstName, String lastName, String secondLastName) {
        String fName = (firstName != null) ? firstName.trim().toLowerCase() : '';
        String lName = (lastName != null) ? lastName.trim().toLowerCase() : '';
        String sName = (secondLastName != null) ? secondLastName.trim().toLowerCase() : '';
        return fName + '|' + lName + '|' + sName;
    }
    
    private void logError(String message, Set<Id> itemIds) {
        // Puedes implementar logging en un objeto personalizado
        System.debug('ERROR: ' + message + ' - Items: ' + itemIds);
        
        // Ejemplo: Crear registro de error
        /*
        Error_Log__c log = new Error_Log__c(
            Type__c = 'ContactQueueable',
            Message__c = message,
            Details__c = 'Item IDs: ' + String.join(new List<Id>(itemIds), ', '),
            Stack_Trace__c = ''
        );
        insert log;
        */
    }
}