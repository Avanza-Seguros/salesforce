public class GeneradorRegistroUDIDiario {
    private static final String BANXICO_TOKEN = '16bed06c833adc1ef469fb960bb36f5c49b9f55eac58eebf19781be2b847d34f';

    @future(callout=true)
    public static void generarRegistroUDIDiario() {
        // Realizar una solicitud HTTP GET a la API de Banxico para obtener los datos de la UDI
        HttpRequest httpRequest = new HttpRequest();
        String url = 'https://www.banxico.org.mx/SieAPIRest/service/v1/series/SF43718/datos/oportuno?token=' + BANXICO_TOKEN;
        httpRequest.setEndpoint(url);
        httpRequest.setMethod('GET');
        HttpResponse httpResponse = new Http().send(httpRequest);

        // Verificar si la solicitud fue exitosa (código de respuesta 200)
        if (httpResponse.getStatusCode() == 200) {
            // Analizar la respuesta JSON para obtener el valor de la UDI
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(httpResponse.getBody());
            List<Object> series = (List<Object>) responseMap.get('bmx');
            List<Object> datos = (List<Object>) series[0];
            Map<String, Object> ultimoDato = (Map<String, Object>) datos[datos.size() - 1];
            String udiValue = (String) ultimoDato.get('dato');

            // Crear un nuevo registro diario de la UDI
            RegistroDiarioUDI__c nuevoRegistro = new RegistroDiarioUDI__c();
            nuevoRegistro.ValorUDI__c = Decimal.valueOf(udiValue);
            nuevoRegistro.Fecha__c = Date.today();

            // Insertar el registro diario de la UDI
            insert nuevoRegistro;
        }
    }
}