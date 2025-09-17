public class ActualizarRegistroDLLBatch implements Database.Batchable<SObject>, Database.allowsCallouts, Schedulable {
    // Agrega una variable de clase para almacenar los valores capturados del flujo
    private Date fecha;

   

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // No es necesario modificar este método para el flujo, ya que no se utiliza en este caso
        return Database.getQueryLocator('select id, Fecha__c, ValorDLL__c from RegistroDiarioDLL__c order by createddate desc Limit 1');
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
       

        // Crear un nuevo registro diario de DLL con los valores capturados del flujo
        RegistroDiarioDLL__c nuevoRegistroDLL = new RegistroDiarioDLL__c();
        nuevoRegistroDLL.Fecha__c = date.today();
        nuevoRegistroDLL.ValorDLL__c = ETC_wsUSD.getUSD(); // Asignar el valor de la UDI obtenido de la API como un Decimal

        // Insertar el registro en Salesforce
        insert nuevoRegistroDLL;
    }

    public void Finish(Database.BatchableContext bc) {
        // Procesamiento adicional al finalizar el lote
    }
    public void execute(SchedulableContext bc) {
        Database.executebatch(new ActualizarRegistroDLLBatch());
        
    }
   
}