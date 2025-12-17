public class EmailBuilder {

    public static List<Messaging.SingleEmailMessage> buildAltas(Items_Cases__c item) {
        System.debug('item: ' + item);
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();


        if (item.Asegurado__c == null) {
            System.debug('⛔ Sin contacto para item ' + item.Id);
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTargetObjectId(c.Id);
        mail.setWhatId(item.Id);
        mail.setSaveAsActivity(false);

        mail.setToAddresses(new String[]{ item.Correo_electronico__c });

        if (item.Correo_Copia__c != null)
            mail.setCcAddresses(new String[]{ item.Correo_Copia__c });

        emails.add(mail);

        return emails;
    }
}
