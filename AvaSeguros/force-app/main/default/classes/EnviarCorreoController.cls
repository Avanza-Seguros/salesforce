public class EnviarCorreoController {
    private final Items_Cases__c objeto;

    public EnviarCorreoController(ApexPages.StandardController controller) {
        this.objeto = (Items_Cases__c)controller.getRecord();
    }

    public PageReference enviarCorreo() {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setSubject('Asunto del correo');
        email.setPlainTextBody('Cuerpo del correo');
        email.setToAddresses(new List<String>{objeto.Correo_electronico__c});

        // Adjuntar archivos relacionados
        List<Attachment> adjuntos = [SELECT Id, Name, Body FROM Attachment WHERE ParentId = :objeto.Id];
        if (!adjuntos.isEmpty()) {
            Messaging.EmailFileAttachment[] fileAttachments = new Messaging.EmailFileAttachment[]{};
            for (Attachment adjunto : adjuntos) {
                Messaging.EmailFileAttachment fileAttachment = new Messaging.EmailFileAttachment();
                fileAttachment.setFileName(adjunto.Name);
                fileAttachment.setBody(adjunto.Body);
                fileAttachments.add(fileAttachment);
            }
            email.setFileAttachments(fileAttachments);
        }

        Messaging.sendEmail(new Messaging.SingleEmailMessage[]{email});

        return null;
    }
}