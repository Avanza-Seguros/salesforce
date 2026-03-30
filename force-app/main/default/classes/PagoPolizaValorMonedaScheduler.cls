public with sharing class PagoPolizaValorMonedaScheduler implements Schedulable {

    public void execute(SchedulableContext sc) {

        Database.executeBatch(new PagoPolizaValorMonedaBatch(false),200);
    }
}