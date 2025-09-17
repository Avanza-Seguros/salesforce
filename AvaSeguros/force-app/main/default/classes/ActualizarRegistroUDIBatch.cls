public class ActualizarRegistroUDIBatch implements Database.Batchable<SObject>, Database.allowsCallouts, Schedulable {
    // Agrega una variable de clase para almacenar los valores capturados del flujo
    private Date fecha;

    // Constructor que recibe los parámetros del flujo
    //public ActualizarRegistroUDIBatch(Date fecha) {
   //     this.fecha = fecha;
    //}

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // No es necesario modificar este método para el flujo, ya que no se utiliza en este caso
        return Database.getQueryLocator('select id, Fecha__c, ValorUDI__c from RegistroDiarioUDI__c order by createddate desc Limit 1');
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        // Realiza la llamada a la API de Banxico para obtener el valor de la UDI
       // String valorUDI = obtenerValorUDI(); // Llamada a la API de Banxico para obtener el valor de la UDI

        // Crear un nuevo registro diario de UDI con los valores capturados del flujo
        RegistroDiarioUDI__c nuevoRegistroUDI = new RegistroDiarioUDI__c();
        nuevoRegistroUDI.Fecha__c = date.today();
        nuevoRegistroUDI.ValorUDI__c = ETC_wsUDI.getUDI(); // Asignar el valor de la UDI obtenido de la API como un Decimal

        // Insertar el registro en Salesforce
        insert nuevoRegistroUDI;
    }

    public void Finish(Database.BatchableContext bc) {
        // Procesamiento adicional al finalizar el lote
    }
    public void execute(SchedulableContext bc) {
        Database.executebatch(new ActualizarRegistroUDIBatch());
        // 
    }


   /* private String obtenerValorUDI() {
        // El código para obtener el valor de la UDI se mantiene igual
        String url = 'https://www.banxico.org.mx/SieAPIRest/service/v1/series/SF60653/datos/oportuno?token=67c29ad9ada4819c51eec55a61ef52455a4845e763804c0e093c2ce3478f4307';
        HttpRequest request = new HttpRequest();
        request.setEndpoint(url);
        request.setMethod('GET');

        Http http = new Http();
        HttpResponse response = http.send(request);

        if (response.getStatusCode() == 200) {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            List<Object> series = (List<Object>) data.get('bmx');
            Map<String, Object> serie = (Map<String, Object>) series[0];
            List<Object> datos = (List<Object>) serie.get('datos');
            Map<String, Object> dato = (Map<String, Object>) datos[0];
            String valor = (String) dato.get('dato');

            return valor;
        } else {
            return null;
        }
    }*/
}