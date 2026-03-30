public class QueueEnvioScheduler implements Schedulable {
    
    public void execute(SchedulableContext sc) {
        System.debug('=== EJECUTANDO SCHEDULE BATCH ENVIO EMAILS ===');
        System.debug('Fecha/hora: ' + Datetime.now());
        
        // Ejecutar batch general (sin IDs específicos)
        BatchEnvioEmails batch = new BatchEnvioEmails();
        Database.executeBatch(batch, 50);
        
        System.debug('✅ Batch programado ejecutado exitosamente');
    }
    
    public static void scheduleBatch() {
        try {
            String cronExp = '0 0 2 * * ?'; // Cada día a las 2:00 AM
            String jobName = 'BatchEnvioEmails_Daily_' + System.now().format('yyyyMMdd_HHmmss');
            
            System.schedule(jobName, cronExp, new QueueEnvioScheduler());
            System.debug('✅ Batch programado: ' + jobName + ' a las 2:00 AM');
            
        } catch (Exception e) {
            System.debug('❌ Error programando batch: ' + e.getMessage());
        }
    }
    
    // Método para programar cada hora
    public static void scheduleHourly() {
        try {
            String cronExp = '0 0 * * * ?'; // Cada hora en punto
            String jobName = 'BatchEnvioEmails_Hourly_' + System.now().format('yyyyMMdd_HHmmss');
            
            System.schedule(jobName, cronExp, new QueueEnvioScheduler());
            System.debug('✅ Batch programado cada hora: ' + jobName);
            
        } catch (Exception e) {
            System.debug('❌ Error programando batch horario: ' + e.getMessage());
        }
    }
    
    // Método para cancelar jobs existentes
    public static void cancelAllJobs() {
        try {
            List<CronTrigger> jobs = [
                SELECT Id, CronJobDetail.Name 
                FROM CronTrigger 
                WHERE CronJobDetail.Name LIKE 'BatchEnvioEmails_%'
            ];
            
            for (CronTrigger job : jobs) {
                System.abortJob(job.Id);
                System.debug('❌ Job cancelado: ' + job.CronJobDetail.Name);
            }
            
            System.debug('✅ Total jobs cancelados: ' + jobs.size());
            
        } catch (Exception e) {
            System.debug('⚠️ Error cancelando jobs: ' + e.getMessage());
        }
    }
}