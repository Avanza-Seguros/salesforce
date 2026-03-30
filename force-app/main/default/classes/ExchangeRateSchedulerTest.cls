@isTest
private with sharing class ExchangeRateSchedulerTest {
    @IsTest
    static void testSchedulerSchedulesJob() {

        Test.startTest();
        String jobId = System.schedule(
            'Test Banxico Scheduler',
            '0 0 0 * * ?',
            new ExchangeRateScheduler()
        );
        Test.stopTest();

        CronTrigger ct = [SELECT Id FROM CronTrigger WHERE Id = :jobId];
        Assert.areNotEqual(null, ct);
    }
}