public class RecordTypeHelper {
    public class RecordTypeConfig {
        public Set<Id> altaRecordTypeIds {get; set;}
        public Set<Id> bajaRecordTypeIds {get; set;}
    }
    
    public static RecordTypeConfig getRecordTypeConfig() {
        RecordTypeConfig config = new RecordTypeConfig();
        config.altaRecordTypeIds = getRecordTypeIds(new String[]{'Alta', 'Alta solicitada', 'Alta con Dependientes'});
        config.bajaRecordTypeIds = getRecordTypeIds(new String[]{'Baja', 'Baja solicitada'});
        return config;
    }
    
    private static Set<Id> getRecordTypeIds(String[] names) {
        Set<Id> ids = new Set<Id>();
        for (String name : names) {
            Schema.RecordTypeInfo info = Schema.SObjectType.Items_Cases__c.getRecordTypeInfosByName().get(name);
            if (info != null) ids.add(info.getRecordTypeId());
        }
        return ids;
    }
}