global with sharing class ExchangeRateScheduler implements Schedulable {
    
    global void execute(SchedulableContext sc) {

        if (Test.isRunningTest()) {
            return;
        }
        System.enqueueJob(new BanxicoQueueable());
    }
}