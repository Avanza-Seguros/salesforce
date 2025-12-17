public class QueueEnvioEmails implements Queueable {

    private Set<Id> itemIds;
    private static final Integer MAX_EMAILS_POR_QUEUE = 9;

    public QueueEnvioEmails(Set<Id> itemIds) {
        this.itemIds = itemIds;
    }

    public void execute(QueueableContext qc) {
        if (itemIds == null || itemIds.isEmpty()) return;

        EmailContextControl.skipEmails = true;

        // CONSULTA MEJORADA: Solo traer items válidos
        List<Items_Cases__c> items = [
            SELECT Id, Correo_electronico__c, Correo_Copia__c,
                   Asegurado__c, Nombre_cuenta__c, Categorias__c
            FROM Items_Cases__c
            WHERE Id IN :itemIds
            AND Correo_electronico__c != null
            AND Asegurado__c != null
            AND Email_Enviado__c = false // 👈 Evitar reenvíos
            LIMIT :MAX_EMAILS_POR_QUEUE
        ];

        System.debug('Items a procesar para email: ' + items.size());

        if (items.isEmpty()) {
            // NO HAY items válidos, NO reencolar
            System.debug('No hay items válidos, finalizando Queueable');
            return;
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        Set<Id> itemsProcesados = new Set<Id>();

        for (Items_Cases__c item : items) {
            System.debug('Procesando item ' + item.Id);
            try {
                System.debug('Construyendo email para item ' + item.Id);
                Messaging.SingleEmailMessage mail = EnvioPlantillas.EnvioEmailMasivo(item.Id);
                System.debug('Email construido para item ' + mail);
                if (mail != null) {
                    System.debug('Email construido para item ' + item.Id);
                    emails.add(mail);
                    itemsProcesados.add(item.Id);
                }
            } catch(Exception e) {
                System.debug('Error con item ' + item.Id + ': ' + e.getMessage());
            }
        }

        // Enviar emails
        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails, false);
                System.debug('Emails enviados: ' + emails.size());
                
                // Marcar como enviados (opcional)
                // markAsSent(itemsProcesados);
                
            } catch(Exception e) {
                System.debug('Error enviando emails: ' + e.getMessage());
                // No marcar como enviados si falló
                itemsProcesados.clear();
            }
        }

        // 🔄 Preparar siguiente lote (solo items NO procesados)
        Set<Id> remainingIds = new Set<Id>(itemIds);
        remainingIds.removeAll(itemsProcesados);
        
        // IMPORTANTE: También remover los que no cumplían condiciones
        // (ya filtrados en la query, pero por seguridad)
        for (Items_Cases__c item : items) {
            remainingIds.remove(item.Id);
        }

        // Reencolar solo si quedan items
        if (!remainingIds.isEmpty()) {
            System.debug('Reencolando ' + remainingIds.size() + ' items restantes');
            System.enqueueJob(new QueueEnvioEmails(remainingIds));
        } else {
            System.debug('Queueable completado exitosamente');
        }
    }

    
    private void markAsSent(Set<Id> itemIds) {
        List<Items_Cases__c> toUpdate = new List<Items_Cases__c>();
        for (Id itemId : itemIds) {
            toUpdate.add(new Items_Cases__c(
                Id = itemId,
                Email_Enviado__c = true
            ));
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
    
}