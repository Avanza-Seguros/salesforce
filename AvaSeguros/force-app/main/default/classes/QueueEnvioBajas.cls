public class QueueEnvioEmails implements Queueable {

    private Set<Id> ids;

    public QueueEnvioEmails(Set<Id> ids) {
        this.ids = ids;
    }

    public void execute(QueueableContext qc) {

        List<Items_Cases__c> items = [
            SELECT Id, Contacto__c, Nombre_cuenta__c, Asegurado__c, Correo_electronico__c, Categorias__c, Correo_Copia__c, Apellido_materno__c, Apellido_paterno__c
            FROM Items_Cases__c
            WHERE Id IN :ids
        ];

       System.debug('Items::: ' + items);
        List<Messaging.SingleEmailMessage> emails = EmailBuilder.buildAltas(items);
        System.debug('Emails::: ' + emails);
        EmailServiceFactory.getInstance().send(emails);
    }
}
