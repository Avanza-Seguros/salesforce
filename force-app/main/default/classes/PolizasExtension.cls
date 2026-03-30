public class PolizasExtension {
    private final Polizas__c poliza;

    public PolizasExtension(ApexPages.StandardController controller) {
        this.poliza = (Polizas__c)controller.getRecord();
    }

    public void eliminarRegistrosRelacionados() {
        List<Pago_Poliza__c> pagos = [SELECT Id FROM Pago_Poliza__c WHERE Poliza__c = :poliza.Id];
        if (!pagos.isEmpty()) {
            delete pagos;
        }
    }
}