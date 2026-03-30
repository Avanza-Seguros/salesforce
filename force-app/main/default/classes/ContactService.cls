public with sharing class ContactService {

    /**
     * Fase 1: Crear/obtener contactos (sin actualizar Items_Cases__c)
     */
    public static Map<Id, Contact> processContacts(List<Items_Cases__c> items) {
        Map<Id, Contact> result = new Map<Id, Contact>();
        if (items == null || items.isEmpty()) return result;
        
        // Filtrar items válidos
        List<Items_Cases__c> validItems = new List<Items_Cases__c>();
        for (Items_Cases__c i : items) {
            if (isValidItem(i)) {
                validItems.add(i);
            }
        }
        
        if (validItems.isEmpty()) return result;
        
        // Buscar contactos existentes
        Map<String, Contact> existingContactsMap = loadExistingContacts(validItems);
        
        // Preparar nuevos contactos
        List<Contact> contactsToCreate = new List<Contact>();
        Map<String, Id> keyToItemIdMap = new Map<String, Id>();
        
        for (Items_Cases__c i : validItems) {
            String contactKey = createKey(i);
            keyToItemIdMap.put(contactKey, i.Id);
            
            if (!existingContactsMap.containsKey(contactKey)) {
                Contact newContact = createContact(i);
                contactsToCreate.add(newContact);
                existingContactsMap.put(contactKey, newContact);
            }
        }
        
        // Insertar nuevos contactos
        if (!contactsToCreate.isEmpty()) {
            insert contactsToCreate;
        }
        
        // Crear mapa resultado
        for (Items_Cases__c i : validItems) {
            String contactKey = createKey(i);
            Contact assignedContact = existingContactsMap.get(contactKey);
            if (assignedContact != null) {
                result.put(i.Id, assignedContact);
            }
        }
        
        return result;
    }
    
    /**
     * Fase 2: Actualizar Items_Cases__c con los contactos
     * Este método se debe llamar DESPUÉS del trigger, en contexto diferente
     */
    public static void updateItemsWithContacts(Map<Id, Contact> itemContactMap) {
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
    
    /**
     * Método completo para usar en @future o Queueable
     */
    @future
    public static void createAndRelateContactsAsync(Set<Id> itemIds) {
        // Consultar los items
        List<Items_Cases__c> items = [
            SELECT Id, Nombre__c, Apellido_paterno__c, 
                   Apellido_materno__c, Correo_electronico__c
            FROM Items_Cases__c
            WHERE Id IN :itemIds
        ];
        
        // Procesar contactos
        Map<Id, Contact> itemContactMap = processContacts(items);
        
        // Actualizar items
        updateItemsWithContacts(itemContactMap);
    }
    
    // Métodos auxiliares (iguales que antes)
    private static Map<String, Contact> loadExistingContacts(List<Items_Cases__c> items) {
        Map<String, Contact> contactsMap = new Map<String, Contact>();
        
        Set<String> nombres = new Set<String>();
        Set<String> apellidos = new Set<String>();
        
        for (Items_Cases__c i : items) {
            nombres.add(i.Nombre__c);
            apellidos.add(i.Apellido_paterno__c);
        }
        
        List<Contact> existingContacts = [
            SELECT Id, FirstName, LastName, MiddleName, Email
            FROM Contact
            WHERE FirstName IN :nombres
            AND LastName IN :apellidos
        ];
        
        for (Contact c : existingContacts) {
            String key = createKey(c.FirstName, c.LastName, c.MiddleName);
            contactsMap.put(key, c);
        }
        
        return contactsMap;
    }
    
    private static Boolean isValidItem(Items_Cases__c item) {
        return item != null && 
               String.isNotBlank(item.Nombre__c) && 
               String.isNotBlank(item.Apellido_paterno__c);
    }
    
    private static String createKey(Items_Cases__c item) {
        return createKey(item.Nombre__c, item.Apellido_paterno__c, item.Apellido_materno__c);
    }
    
    private static String createKey(String firstName, String lastName, String secondLastName) {
        String fName = (firstName != null) ? firstName.trim().toLowerCase() : '';
        String lName = (lastName != null) ? lastName.trim().toLowerCase() : '';
        String sName = (secondLastName != null) ? secondLastName.trim().toLowerCase() : '';
        
        return fName + '|' + lName + '|' + sName;
    }
    
    private static Contact createContact(Items_Cases__c item) {
        return new Contact(
            FirstName = item.Nombre__c,
            LastName = item.Apellido_paterno__c,
            MiddleName = item.Apellido_materno__c,
            Email = item.Correo_electronico__c
        );
    }
}