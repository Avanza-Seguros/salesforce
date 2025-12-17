public class ContactServiceEvaluator {
    public static Boolean shouldCreateContact(Items_Cases__c newItem, Items_Cases__c oldItem, Boolean isInsert) {
        // Validación básica
        if (String.isBlank(newItem.Nombre__c) || 
            String.isBlank(newItem.Apellido_paterno__c) || 
            newItem.Asegurado__c != null) {
            return false;
        }
        
        // Para inserts, siempre crear contacto
        if (isInsert) return true;
        
        // Para updates, verificar cambios
        if (oldItem == null) return false;
        
        return (
            newItem.Nombre__c != oldItem.Nombre__c ||
            newItem.Apellido_paterno__c != oldItem.Apellido_paterno__c ||
            newItem.Apellido_materno__c != oldItem.Apellido_materno__c ||
            newItem.Correo_electronico__c != oldItem.Correo_electronico__c ||
            (newItem.Estatus__c != oldItem.Estatus__c && newItem.Estatus__c == 'Concluido')
        );
    }
}