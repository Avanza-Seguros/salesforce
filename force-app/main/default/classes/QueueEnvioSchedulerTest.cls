@IsTest
private class QueueEnvioSchedulerTest {
    
    @IsTest
    static void testExecuteMethod() {
        Test.startTest();
        QueueEnvioScheduler scheduler = new QueueEnvioScheduler();
        scheduler.execute(null);
        Test.stopTest();
        
        // Verificar que no hay excepciones
        Assert.isTrue(true);
    }
    
    @IsTest
    static void testScheduleBatch() {
        Test.startTest();
        QueueEnvioScheduler.scheduleBatch();
        Test.stopTest();
        
        // Verificar que se creó el job
        List<CronTrigger> jobs = [
            SELECT Id, CronJobDetail.Name 
            FROM CronTrigger 
            WHERE CronJobDetail.Name LIKE 'BatchEnvioEmails_Daily%'
        ];
        Assert.isTrue(!jobs.isEmpty(), 'Debe haber al menos un job programado');
    }
    
    @IsTest
    static void testScheduleHourly() {
        Test.startTest();
        QueueEnvioScheduler.scheduleHourly();
        Test.stopTest();
        
        List<CronTrigger> jobs = [
            SELECT Id, CronJobDetail.Name 
            FROM CronTrigger 
            WHERE CronJobDetail.Name LIKE 'BatchEnvioEmails_Hourly%'
        ];
        Assert.isTrue(!jobs.isEmpty(), 'Debe haber al menos un job programado');
    }
    
    @IsTest
    static void testCancelAllJobs() {
        // Primero programar algunos jobs
        QueueEnvioScheduler.scheduleBatch();
        QueueEnvioScheduler.scheduleHourly();
        
        Test.startTest();
        QueueEnvioScheduler.cancelAllJobs();
        Test.stopTest();
        
        List<CronTrigger> jobs = [
            SELECT Id 
            FROM CronTrigger 
            WHERE CronJobDetail.Name LIKE 'BatchEnvioEmails_%'
        ];
        Assert.areEqual(0, jobs.size(), 'Todos los jobs deben estar cancelados');
    }
}