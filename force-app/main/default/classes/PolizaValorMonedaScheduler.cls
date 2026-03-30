global with sharing class PolizaValorMonedaScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {

        if (Test.isRunningTest()) {
            return;
        }

        Database.executeBatch(new PolizaValorMonedaBatch(false), 200);
    }
}