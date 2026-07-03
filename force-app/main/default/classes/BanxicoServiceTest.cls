@IsTest
public with sharing class BanxicoServiceTest {
    
    // Mock class para simular respuestas HTTP
    private class MockHttpResponseGenerator implements HttpCalloutMock {
        private String responseBody;
        private Integer statusCode;
        
        public MockHttpResponseGenerator(String responseBody, Integer statusCode) {
            this.responseBody = responseBody;
            this.statusCode = statusCode;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(this.responseBody);
            res.setStatusCode(this.statusCode);
            return res;
        }
    }
    
    // Respuesta exitosa para UDI
    private static String getSuccessResponseUDI() {
        return '{' +
            '"bmx": {' +
            '  "series": [' +
            '    {' +
            '      "idSerie": "SP68257",' +
            '      "titulo": "UDIS",' +
            '      "datos": [' +
            '        {' +
            '          "fecha": "31/12/2023",' +
            '          "dato": "7.456789"' +
            '        }' +
            '      ]' +
            '    }' +
            '  ]' +
            '}' +
            '}';
    }
    
    // Respuesta exitosa para DLLS
    private static String getSuccessResponseDLLS() {
        return '{' +
            '"bmx": {' +
            '  "series": [' +
            '    {' +
            '      "idSerie": "SF63528",' +
            '      "titulo": "Tipo de Cambio",' +
            '      "datos": [' +
            '        {' +
            '          "fecha": "31/12/2023",' +
            '          "dato": "17.1234"' +
            '        }' +
            '      ]' +
            '    }' +
            '  ]' +
            '}' +
            '}';
    }
    
    // Respuesta de error
    private static String getErrorResponseBody() {
        return '{' +
            '"error": {' +
            '  "code": "400",' +
            '  "message": "Bad Request"' +
            '}' +
            '}';
    }
    
    // Respuesta vacía
    private static String getEmptyResponseBody() {
        return '{' +
            '"bmx": {' +
            '  "series": []' +
            '}' +
            '}';
    }
    
    // Respuesta con datos nulos
    private static String getNullDataResponse() {
        return '{' +
            '"bmx": {' +
            '  "series": [' +
            '    {' +
            '      "idSerie": "SP68257",' +
            '      "titulo": "UDIS",' +
            '      "datos": null' +
            '    }' +
            '  ]' +
            '}' +
            '}';
    }
    
    @IsTest
    static void testObtenerUDI_Success() {
        // Configurar mock
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(getSuccessResponseUDI(), 200));
        
        Test.startTest();
        Decimal result = BanxicoService.obtenerUDI();
        Test.stopTest();
        
        // Verificaciones
        Assert.areNotEqual(null, result, 'El resultado no debería ser nulo');
        Assert.areEqual(7.456789, result, 'El valor UDI debería ser 7.456789');
    }
    
    @IsTest
    static void testObtenerDLLS_Success() {
        // Configurar mock
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(getSuccessResponseDLLS(), 200));
        
        Test.startTest();
        Decimal result = BanxicoService.obtenerDLLS();
        Test.stopTest();
        
        // Verificaciones
        Assert.areNotEqual(null, result, 'El resultado no debería ser nulo');
        Assert.areEqual(17.1234, result, 'El valor DLLS debería ser 17.1234');
    }
    
    @IsTest
    static void testObtenerValor_ConEnumUDI() {
        // Configurar mock
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(getSuccessResponseUDI(), 200));
        
        Test.startTest();
        Decimal result = BanxicoService.obtenerValor(BanxicoService.TipoSerie.UDI);
        Test.stopTest();
        
        Assert.areNotEqual(null, result, 'El resultado no debería ser nulo');
        Assert.areEqual(7.456789, result, 'El valor UDI debería ser 7.456789');
    }
    
    @IsTest
    static void testObtenerValor_ConEnumDLLS() {
        // Configurar mock
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(getSuccessResponseDLLS(), 200));
        
        Test.startTest();
        Decimal result = BanxicoService.obtenerValor(BanxicoService.TipoSerie.DLLS);
        Test.stopTest();
        
        Assert.areNotEqual(null, result, 'El resultado no debería ser nulo');
        Assert.areEqual(17.1234, result, 'El valor DLLS debería ser 17.1234');
    }
    
    @IsTest
    static void testObtenerValor_ConStringUDI() {
        // Configurar mock
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(getSuccessResponseUDI(), 200));
        
        Test.startTest();
        Decimal result = BanxicoService.obtenerValor('UDI');
        Test.stopTest();
        
        Assert.areNotEqual(null, result, 'El resultado no debería ser nulo');
        Assert.areEqual(7.456789, result, 'El valor UDI debería ser 7.456789');
    }
    
    @IsTest
    static void testObtenerValor_ConStringDLLS() {
        // Configurar mock
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(getSuccessResponseDLLS(), 200));
        
        Test.startTest();
        Decimal result = BanxicoService.obtenerValor('DLLS');
        Test.stopTest();
        
        Assert.areNotEqual(null, result, 'El resultado no debería ser nulo');
        Assert.areEqual(17.1234, result, 'El valor DLLS debería ser 17.1234');
    }
    
    @IsTest
    static void testObtenerValor_ConStringCaseInsensitive() {
        // Configurar mock
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(getSuccessResponseUDI(), 200));
        
        Test.startTest();
        Decimal result = BanxicoService.obtenerValor('udi');
        Test.stopTest();
        
        Assert.areNotEqual(null, result, 'El resultado no debería ser nulo');
        Assert.areEqual(7.456789, result, 'El valor UDI debería ser 7.456789');
    }
    
    @IsTest
    static void testObtenerValor_StringInvalido() {
        Test.startTest();
        try {
            Decimal result = BanxicoService.obtenerValor('INVALIDO');
            Assert.isTrue(false, 'Debería haber lanzado una excepción');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('Tipo de serie no válido'), 'Debería indicar tipo inválido');
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testObtenerValor_ConConfiguracion() {
        // Configurar mock
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(getSuccessResponseUDI(), 200));
        
        BanxicoService.ConfiguracionBanxico config = new BanxicoService.ConfiguracionBanxico();
        config.token = 'test-token';
        config.timeoutMs = 60000;
        
        Test.startTest();
        Decimal result = BanxicoService.obtenerValor(BanxicoService.TipoSerie.UDI, config);
        Test.stopTest();
        
        Assert.areNotEqual(null, result, 'El resultado no debería ser nulo');
    }
    
    @IsTest
    static void testObtenerValor_ConConfiguracionNull() {
        // Configurar mock
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(getSuccessResponseUDI(), 200));
        
        Test.startTest();
        Decimal result = BanxicoService.obtenerValor(BanxicoService.TipoSerie.UDI, null);
        Test.stopTest();
        
        Assert.areNotEqual(null, result, 'El resultado no debería ser nulo');
    }
    
    @IsTest
    static void testObtenerValor_HttpError() {
        // Configurar mock con error HTTP
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(getErrorResponseBody(), 400));
        
        Test.startTest();
        Decimal result = BanxicoService.obtenerUDI();
        Test.stopTest();
        
        Assert.areEqual(null, result, 'El resultado debería ser nulo en caso de error HTTP');
    }
    
    @IsTest
    static void testObtenerValor_EmptyResponse() {
        // Configurar mock con respuesta vacía
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(getEmptyResponseBody(), 200));
        
        Test.startTest();
        Decimal result = BanxicoService.obtenerUDI();
        Test.stopTest();
        
        Assert.areEqual(null, result, 'El resultado debería ser nulo cuando la respuesta está vacía');
    }
    
    @IsTest
    static void testObtenerValor_NullData() {
        // Configurar mock con datos nulos
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(getNullDataResponse(), 200));
        
        Test.startTest();
        Decimal result = BanxicoService.obtenerUDI();
        Test.stopTest();
        
        Assert.areEqual(null, result, 'El resultado debería ser nulo cuando los datos son nulos');
    }
    
    @IsTest
    static void testObtenerValorBanxico_Flow_SingleUDI() {
        // Configurar mock
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(getSuccessResponseUDI(), 200));
        
        List<BanxicoService.SolicitudWrapper> solicitudes = new List<BanxicoService.SolicitudWrapper>{
            new BanxicoService.SolicitudWrapper('UDI')
        };
        
        Test.startTest();
        List<BanxicoService.ResultadoWrapper> resultados = BanxicoService.obtenerValorBanxico(solicitudes);
        Test.stopTest();
        
        Assert.areEqual(1, resultados.size(), 'Debería retornar un resultado');
        Assert.areEqual('UDI', resultados[0].tipo, 'El tipo debería ser UDI');
        Assert.areEqual(7.456789, resultados[0].valor, 'El valor debería ser 7.456789');
        Assert.areEqual(true, resultados[0].exito, 'La operación debería ser exitosa');
    }
    
    @IsTest
    static void testObtenerValorBanxico_Flow_SingleDLLS() {
        // Configurar mock
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(getSuccessResponseDLLS(), 200));
        
        List<BanxicoService.SolicitudWrapper> solicitudes = new List<BanxicoService.SolicitudWrapper>{
            new BanxicoService.SolicitudWrapper('DLLS')
        };
        
        Test.startTest();
        List<BanxicoService.ResultadoWrapper> resultados = BanxicoService.obtenerValorBanxico(solicitudes);
        Test.stopTest();
        
        Assert.areEqual(1, resultados.size(), 'Debería retornar un resultado');
        Assert.areEqual('DLLS', resultados[0].tipo, 'El tipo debería ser DLLS');
        Assert.areEqual(17.1234, resultados[0].valor, 'El valor debería ser 17.1234');
        Assert.areEqual(true, resultados[0].exito, 'La operación debería ser exitosa');
    }
    
    @IsTest
    static void testObtenerValorBanxico_Flow_Multiple() {
        // Configurar mock para UDI
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(getSuccessResponseUDI(), 200));
        
        List<BanxicoService.SolicitudWrapper> solicitudes = new List<BanxicoService.SolicitudWrapper>{
            new BanxicoService.SolicitudWrapper('UDI'),
            new BanxicoService.SolicitudWrapper('DLLS')
        };
        
        Test.startTest();
        List<BanxicoService.ResultadoWrapper> resultados = BanxicoService.obtenerValorBanxico(solicitudes);
        Test.stopTest();
        
        Assert.areEqual(2, resultados.size(), 'Debería retornar dos resultados');
    }
    
    @IsTest
    static void testObtenerValorBanxico_Flow_EmptyList() {
        List<BanxicoService.SolicitudWrapper> solicitudes = new List<BanxicoService.SolicitudWrapper>();
        
        Test.startTest();
        Map<String, Object> resultados = BanxicoService.obtenerAmbosValoresConDetalles();
        Test.stopTest();
        
        Assert.areEqual(4, resultados.size(), 'Debería retornar lista vacía');
    }
    
    @IsTest
    static void testObtenerValorBanxico_Flow_Error() {
        // Configurar mock con error
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(getErrorResponseBody(), 400));
        
        List<BanxicoService.SolicitudWrapper> solicitudes = new List<BanxicoService.SolicitudWrapper>{
            new BanxicoService.SolicitudWrapper('UDI')
        };
        
        Test.startTest();
        List<BanxicoService.ResultadoWrapper> resultados = BanxicoService.obtenerValorBanxico(solicitudes);
        Test.stopTest();
        
        Assert.areEqual(1, resultados.size(), 'Debería retornar un resultado');
        Assert.areEqual(null, resultados[0].valor, 'El valor debería ser nulo en caso de error');
        Assert.areEqual(false, resultados[0].exito, 'La operación debería ser fallida');
    }
    
    @IsTest
    static void testSolicitudWrapperConstructors() {
        Test.startTest();
        BanxicoService.SolicitudWrapper wrapper1 = new BanxicoService.SolicitudWrapper();
        BanxicoService.SolicitudWrapper wrapper2 = new BanxicoService.SolicitudWrapper('UDI');
        Test.stopTest();
        
        Assert.areNotEqual(null, wrapper1, 'Wrapper vacío no debería ser nulo');
        Assert.areNotEqual(null, wrapper2, 'Wrapper con tipo no debería ser nulo');
        Assert.areEqual('UDI', wrapper2.tipo, 'El tipo debería ser UDI');
    }
    
    @IsTest
    static void testResultadoWrapperConstructors() {
        Test.startTest();
        BanxicoService.ResultadoWrapper wrapper1 = new BanxicoService.ResultadoWrapper();
        Test.stopTest();
        
        Assert.areNotEqual(null, wrapper1, 'Wrapper vacío no debería ser nulo');
    }
    
    @IsTest
    static void testConfiguracionBanxicoConstructors() {
        Test.startTest();
        BanxicoService.ConfiguracionBanxico config1 = new BanxicoService.ConfiguracionBanxico();
        Boolean tok = BanxicoService.validarToken();
        Test.stopTest();
        
        Assert.areNotEqual(null, config1, 'La configuración no debería ser nula');
        Assert.areNotEqual(null, config1.token, 'El token no debería ser nulo');
        Assert.areEqual(30000, config1.timeoutMs, 'El timeout debería ser 30000');
    }
}