// Clase evaluadora para Emails
public class EmailEvaluator {
    public static Boolean shouldSendAltaEmail(Items_Cases__c newItem, Items_Cases__c oldItem, Set<Id> altaRecordTypeIds) {
        return (
            oldItem != null &&
            String.isNotBlank(newItem.Correo_electronico__c) && 
            oldItem.Estatus__c != newItem.Estatus__c && 
            String.isNotBlank(newItem.Nombre_cuenta__c) && 
            altaRecordTypeIds.contains(newItem.RecordTypeId) && 
            newItem.Estatus__c == 'Concluido'
        );
    }
    
    public static Boolean shouldSendBajaEmail(Items_Cases__c newItem, Items_Cases__c oldItem, Set<Id> bajaRecordTypeIds) {
        return (
            oldItem != null &&
            bajaRecordTypeIds.contains(newItem.RecordTypeId) && 
            oldItem.Estatus__c != newItem.Estatus__c && 
            newItem.Estatus__c == 'Concluido' && 
            !newItem.Baja_Por_Defuncion__c
        );
    }
}
