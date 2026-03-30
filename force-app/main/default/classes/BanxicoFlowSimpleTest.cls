@IsTest
public with sharing class BanxicoFlowSimpleTest {
    
    // Datos de prueba comunes
    private static Pago_poliza__c crearPagoPolizaTest() {
        Pago_poliza__c pago = new Pago_poliza__c(
            Poliza__c = 'TEST-001',
            Monto__c = 1000,
            Estatus_del_Pago__c = 'Pendiente'
        );
        insert pago;
        return pago;
    }
    
    // Mock para respuestas exitosas de Banxico
    private class BanxicoMockSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            // Simular respuesta exitosa con valores realistas
            String jsonResponse = '{' +
                '"bmx": {' +
                '"series": [{' +
                '"idSerie": "SP68257",' +
                '"titulo": "UDI",' +
                '"datos": [{' +
                '"fecha": "2024-01-15",' +
                '"dato": "6.1234"' +
                '}]' +
                '}]' +
                '}' +
            '}';
            
            res.setBody(jsonResponse);
            return res;
        }
    }
    
    // Mock para respuesta de tipo de cambio
    private class BanxicoMockDLLS implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String jsonResponse = '{' +
                '"bmx": {' +
                '"series": [{' +
                '"idSerie": "SF63528",' +
                '"titulo": "Tipo de Cambio",' +
                '"datos": [{' +
                '"fecha": "2024-01-15",' +
                '"dato": "17.25"' +
                '}]' +
                '}]' +
                '}' +
            '}';
            
            res.setBody(jsonResponse);
            return res;
        }
    }
    
    // Mock para error de Banxico
    private class BanxicoMockError implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(400);
            res.setBody('{"error": "Token inválido"}');
            return res;
        }
    }
    
    // Mock para timeout
    private class BanxicoMockTimeout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            // Simular timeout
            throw new CalloutException('Read timed out');
        }
    }
    
    // TEST: Solicitud con ambos valores y actualización de registro
    @IsTest
    static void testObtenerYAplicarTipoCambio_AmbosValoresConActualizacion() {
        // Configurar
        Test.setMock(HttpCalloutMock.class, new BanxicoMockSuccess());
        
        Test.startTest();
        // Preparar solicitud
        List<BanxicoFlowSimple.ResultadoFlow> solicitud = BanxicoFlowSimple.obtenerValoresBanxico();
        Test.stopTest();
        
        
    }
}