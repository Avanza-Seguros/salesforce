global class BatchEnvioEmails implements Database.Batchable<SObject>, Database.Stateful {

    Integer totalRecords;
    Integer processed = 0;
    

    global Database.QueryLocator start(Database.BatchableContext bc) {
        System.debug('Start BatchEnvioEmails');
        List<Items_Cases__c> pendingList = [
            SELECT Id FROM Items_Cases__c WHERE Estatus__c = 'En proceso'
        ];
        totalRecords = pendingList.size();
        System.debug('Total de items pendientes: ' + totalRecords);
        return Database.getQueryLocator([
            SELECT Id, Estatus__c, Contacto__c, Correo_electronico__c, Poliza__c, Vigencia__c, Nombre_cuenta__c, Correo_Copia__c
            FROM Items_Cases__c
            WHERE Estatus__c = 'En proceso'
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Items_Cases__c> scope) {
        try {
            System.debug('Procesando ' + scope.size() + ' items');
            System.debug('Items procesados: ' + scope);
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

            for (Items_Cases__c item : scope) {
                if (item.Correo_electronico__c != null) {
                    emails.add(EnvioPlantillas.buildEmail(item));
                    item.Estatus__c = 'Concluido';
                }
            }

            System.debug('Enviando ' + emails.size() + ' emails');
            if (!emails.isEmpty()) {
                Messaging.sendEmail(emails, false);
            }

            update scope;

            processed += scope.size();

            System.debug('Items procesados: ' + processed);
        }catch (Exception e) {
            System.debug('ERROR: ' + e.getMessage());
            System.debug('STACKTRACE: ' + e.getStackTraceString());
        }
    }

    global void finish(Database.BatchableContext bc) {
        
    }
}