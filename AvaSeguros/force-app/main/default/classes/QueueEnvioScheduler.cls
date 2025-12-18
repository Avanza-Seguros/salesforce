public class QueueEnvioScheduler implements Schedulable {
    
    private Set<Id> itemIds;
    private String batchId;
    private Integer recursionLevel;
    
    public QueueEnvioScheduler() {
        // Constructor por defecto
    }
    
    public QueueEnvioScheduler(Set<Id> itemIds, String batchId, Integer recursionLevel) {
        this.itemIds = itemIds;
        this.batchId = batchId;
        this.recursionLevel = recursionLevel;
    }
    
    public void execute(SchedulableContext sc) {
        System.debug('QueueEnvioScheduler ejecutado');
        
        if (itemIds != null && !itemIds.isEmpty()) {
            // Reencolar el proceso
            System.enqueueJob(new QueueEnvioEmails(itemIds, recursionLevel, batchId));
        }
        
        // Eliminar el job schedule
        try {
            System.abortJob(sc.getTriggerId());
        } catch (Exception e) {
            System.debug('Error eliminando job schedule: ' + e.getMessage());
        }
    }
}