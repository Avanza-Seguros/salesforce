global class BatchEnvioEmailsOptimizado
    implements Database.Batchable<SObject>, Database.Stateful {

    global Database.QueryLocator start(Database.BatchableContext bc) {

        return Database.getQueryLocator([
            SELECT Id,
                   Correo_electronico__c,
                   Correo_Copia__c,
                   Nombre__c,
                   Apellido_paterno__c,
                   Apellido_materno__c,
                   Certificado__c,
                   Asegurado__c,
                   Contacto__c
            FROM Items_Cases__c
            WHERE Estatus__c = 'Concluido'
            AND Correo_electronico__c != null
        ]);
    }

    global void execute(
        Database.BatchableContext bc,List<Items_Cases__c> scope) {
        System.debug('Procesando batch scope: ' + scope.size());

        // ⛔ Evitar trigger emails
        EmailContextControl.skipEmails = true;

        // 🔹 Construir correos
        List<Messaging.SingleEmailMessage> emails = EmailBuilder.buildAltas(scope);

        // 🔹 Enviar en chunks seguros
        EmailServiceFactory.getInstance().send(emails);
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('BatchEnvioEmailsOptimizado finalizado');
    }
}
