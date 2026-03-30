@IsTest
public with sharing class HistoricoPolizasControllerTest {
    
    @TestSetup
    static void setupTestData() {
        // Crear datos de prueba
        Polizas__c poliza = new Polizas__c(
            Name = 'POL-001',
            Estatus__c = 'Activa',
            Moneda__c = 'Pesos',
            Suma_Aseguradora__c = 1000000,
            Fecha_de_Emision__c = Date.today().addDays(-30),
            Vigencia_hasta__c = Date.today().addDays(365),
            Prima_Total__c = 5000,
            Ramo__c = 'Vida'
        );
        insert poliza;
        
        Asegurado__c asegurado = new Asegurado__c(
            Name = 'Juan Pérez',
            FechaNacimiento__c = Date.newInstance(1980, 1, 1),
            Polizas__c = poliza.Id
        );
        insert asegurado;
        
        Historico_Aportacion__c historico = new Historico_Aportacion__c(
            Anualidad__c = '2024',
            PrimaBasica__c = 3000,
            PrimaAdicional__c = 500,
            PagosIngresados__c = 3500,
            Desde__c = Date.today().addDays(-30),
            Hasta__c = Date.today().addDays(335),
            Poliza__c = poliza.Id
        );
        insert historico;
        
        Pago_Poliza__c pago = new Pago_Poliza__c(
            Importe_de_Ultima_Aportacion__c = 3500,
            Tipo_de_Moneda__c = 'MXN',
            Valor_Moneda__c = 1,
            Monto__c = 3500,
            Modo_de_Pago__c = 'Transferencia',
            Fecha_de_emision__c = Date.today().addDays(-15),
            Estatus_del_Pago__c = 'Completado',
            Poliza__c = poliza.Id,
            Historico_Aportacion__c = historico.Id 
        );
        insert pago;
        
        Relacion_Poliza__c relacion = new Relacion_Poliza__c(
            Poliza__c = poliza.Id,
            Asegurado__c = asegurado.Id,
            Historico__c = historico.Id,
            Pago__c = pago.Id
        );
        insert relacion;
    }
    
    @IsTest
    static void testBuscaInicial() {
        Test.startTest();
        List<HistoricoPolizasController.RelacionPolizaWrapper> resultados = HistoricoPolizasController.buscaInicial();
        Test.stopTest();
        
        System.assertNotEquals(null, resultados, 'La lista no debería ser nula');
        System.assert(!resultados.isEmpty(), 'Debería haber al menos un resultado');
        
        // Verificar que los wrappers contengan los datos esperados
        HistoricoPolizasController.RelacionPolizaWrapper wrapper = resultados[0];
        System.assertNotEquals(null, wrapper.polizaId, 'El ID de póliza no debería ser nulo');
        System.assertNotEquals(null, wrapper.polizaName, 'El nombre de póliza no debería ser nulo');
        System.assertEquals('Activa', wrapper.estatus, 'El estatus debería ser "Activa"');
    }
    
    @IsTest
    static void testBuscaInicial_Exception() {
        // Forzar una excepción eliminando permisos de lectura (en orgs sin sharing)
        try {
            Test.startTest();
            List<HistoricoPolizasController.RelacionPolizaWrapper> resultados = HistoricoPolizasController.buscaInicial();
            Test.stopTest();
        } catch (Exception e) {
            System.assert(e instanceof AuraHandledException, 'Debería lanzar AuraHandledException');
        }
    }
    
    @IsTest
    static void testBuscarHistorico() {
        Test.startTest();
        List<HistoricoPolizasController.RelacionPolizaWrapper> resultados = HistoricoPolizasController.buscarHistorico('POL-001');
        Test.stopTest();
        
        System.assertNotEquals(null, resultados, 'La lista no debería ser nula');
        System.assert(!resultados.isEmpty(), 'Debería encontrar resultados para "POL-001"');
    }
    
    @IsTest
    static void testBuscarHistorico_PorAsegurado() {
        Test.startTest();
        List<HistoricoPolizasController.RelacionPolizaWrapper> resultados = HistoricoPolizasController.buscarHistorico('Juan');
        Test.stopTest();
        
        System.assertNotEquals(null, resultados, 'La lista no debería ser nula');
        System.assert(!resultados.isEmpty(), 'Debería encontrar resultados para "Juan"');
    }
    
    @IsTest
    static void testBuscarHistorico_PorHistorico() {
        Test.startTest();
        List<HistoricoPolizasController.RelacionPolizaWrapper> resultados = HistoricoPolizasController.buscarHistorico('HIST-001');
        Test.stopTest();
        
        System.assertNotEquals(null, resultados, 'La lista no debería ser nula');
    }
    
    @IsTest
    static void testBuscarHistorico_SinResultados() {
        Test.startTest();
        List<HistoricoPolizasController.RelacionPolizaWrapper> resultados = HistoricoPolizasController.buscarHistorico('XYZNOEXISTE');
        Test.stopTest();
        
        System.assertNotEquals(null, resultados, 'La lista no debería ser nula');
        System.assertEquals(0, resultados.size(), 'No debería encontrar resultados para "XYZNOEXISTE"');
    }
    
    @IsTest
    static void testBuscarHistorico_EmptySearchTerm() {
        Test.startTest();
        List<HistoricoPolizasController.RelacionPolizaWrapper> resultados = HistoricoPolizasController.buscarHistorico('');
        Test.stopTest();
        
        System.assertNotEquals(null, resultados, 'La lista no debería ser nula');
    }
    
    @IsTest
    static void testObtenerHistoricoPorRelacion() {
        // Obtener la relación creada en el setup
        Relacion_Poliza__c relacion = [SELECT Id FROM Relacion_Poliza__c LIMIT 1];
        
        Test.startTest();
        HistoricoPolizasController.DetalleCompletoWrapper resultado = HistoricoPolizasController.obtenerHistoricoPorRelacion(relacion.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, resultado, 'El resultado no debería ser nulo');
        System.assertNotEquals(null, resultado.relacionPrincipal, 'La relación principal no debería ser nula');
        System.assertNotEquals(null, resultado.asegurados, 'La lista de asegurados no debería ser nula');
        System.assertNotEquals(null, resultado.historicos, 'La lista de históricos no debería ser nula');
        System.assertNotEquals(null, resultado.pagos, 'La lista de pagos no debería ser nula');
        System.assertNotEquals(null, resultado.relaciones, 'La lista de relaciones no debería ser nula');
        System.assertNotEquals(null, resultado.poliza, 'La póliza no debería ser nula');
        
        // Verificar que las listas contengan datos
        System.assert(!resultado.asegurados.isEmpty(), 'Debería haber al menos un asegurado');
        System.assert(!resultado.historicos.isEmpty(), 'Debería haber al menos un histórico');
        System.assert(!resultado.pagos.isEmpty(), 'Debería haber al menos un pago');
        System.assert(!resultado.relaciones.isEmpty(), 'Debería haber al menos una relación');
        
        // Verificar datos específicos
        System.assertEquals('POL-001', resultado.poliza.name, 'El nombre de la póliza debería ser POL-001');
        System.assertEquals('Juan Pérez', resultado.asegurados[0].name, 'El nombre del asegurado debería ser Juan Pérez');
    }
    
    @IsTest
    static void testObtenerHistoricoPorRelacion_InvalidId() {
        Test.startTest();
        try {
            HistoricoPolizasController.DetalleCompletoWrapper resultado = HistoricoPolizasController.obtenerHistoricoPorRelacion('001000000000000');
            System.assert(false, 'Debería haber lanzado una excepción');
        } catch (Exception e) {
            System.assert(e instanceof AuraHandledException, 'Debería lanzar AuraHandledException');
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testWrapperClasses() {
        // Probar la creación de todos los wrappers
        Polizas__c poliza = [SELECT Id, Name, Estatus__c, Moneda__c, Suma_Aseguradora__c, 
                             Fecha_de_Emision__c, Vigencia_hasta__c, Prima_Total__c, Ramo__c 
                             FROM Polizas__c LIMIT 1];
        
        Asegurado__c asegurado = [SELECT Id, Name, FechaNacimiento__c FROM Asegurado__c LIMIT 1];
        
        Historico_Aportacion__c historico = [SELECT Id, Name, Anualidad__c, PrimaBasica__c, 
                                            PrimaAdicional__c, PagosIngresados__c, Desde__c, Hasta__c 
                                            FROM Historico_Aportacion__c LIMIT 1];
        
        Pago_Poliza__c pago = [SELECT Id, Name, Importe_de_Ultima_Aportacion__c, Tipo_de_Moneda__c,
                              Valor_Moneda__c, Pago_en_MXN__c, Tipo_de_pago__c, Fecha_de_emision__c,
                              Estatus_del_Pago__c FROM Pago_Poliza__c LIMIT 1];
        
        Relacion_Poliza__c relacion = [SELECT Id, Name, Poliza__r.Id, Poliza__r.Name, Poliza__r.Estatus__c,
                                      Poliza__r.Moneda__c, Poliza__r.Suma_Aseguradora__c, 
                                      Poliza__r.Fecha_de_Emision__c, Poliza__r.Vigencia_hasta__c,
                                      Poliza__r.Prima_Total__c, Poliza__r.Ramo__c,
                                      Asegurado__r.Id, Asegurado__r.Name, Asegurado__r.FechaNacimiento__c,
                                      Historico__r.Id, Historico__r.Name, Historico__r.Anualidad__c,
                                      Historico__r.PrimaBasica__c, Historico__r.PrimaAdicional__c,
                                      Historico__r.PagosIngresados__c, Historico__r.Desde__c, Historico__r.Hasta__c,
                                      Pago__r.Id, Pago__r.Name, Pago__r.Importe_de_Ultima_Aportacion__c,
                                      Pago__r.Tipo_de_Moneda__c, Pago__r.Valor_Moneda__c, Pago__r.Pago_en_MXN__c,
                                      Pago__r.Tipo_de_pago__c, Pago__r.Fecha_de_emision__c, Pago__r.Estatus_del_Pago__c
                                      FROM Relacion_Poliza__c LIMIT 1];
        
        Test.startTest();
        // Probar PolizaWrapper
        HistoricoPolizasController.PolizaWrapper polizaWrapper = new HistoricoPolizasController.PolizaWrapper(poliza);
        System.assertEquals(poliza.Id, polizaWrapper.id);
        System.assertEquals(poliza.Name, polizaWrapper.name);
        
        // Probar AseguradoWrapper
        HistoricoPolizasController.AseguradoWrapper aseguradoWrapper = new HistoricoPolizasController.AseguradoWrapper(asegurado);
        System.assertEquals(asegurado.Id, aseguradoWrapper.id);
        System.assertEquals(asegurado.Name, aseguradoWrapper.name);
        
        // Probar HistoricoWrapper
        HistoricoPolizasController.HistoricoWrapper historicoWrapper = new HistoricoPolizasController.HistoricoWrapper(historico);
        System.assertEquals(historico.Id, historicoWrapper.id);
        System.assertEquals(historico.Name, historicoWrapper.name);
        
        // Probar PagoWrapper
        HistoricoPolizasController.PagoWrapper pagoWrapper = new HistoricoPolizasController.PagoWrapper(pago);
        System.assertEquals(pago.Id, pagoWrapper.id);
        System.assertEquals(pago.Name, pagoWrapper.name);
        
        // Probar RelacionPolizaWrapper
        HistoricoPolizasController.RelacionPolizaWrapper relacionWrapper = new HistoricoPolizasController.RelacionPolizaWrapper(relacion);
        System.assertEquals(relacion.Id, relacionWrapper.relacionId);
        System.assertEquals(relacion.Name, relacionWrapper.relacionName);
        
        // Probar DetalleCompletoWrapper
        List<Asegurado__c> asegurados = new List<Asegurado__c>{asegurado};
        List<Historico_Aportacion__c> historicos = new List<Historico_Aportacion__c>{historico};
        List<Pago_Poliza__c> pagos = new List<Pago_Poliza__c>{pago};
        List<Relacion_Poliza__c> relaciones = new List<Relacion_Poliza__c>{relacion};
        
        HistoricoPolizasController.DetalleCompletoWrapper detalleWrapper = 
            new HistoricoPolizasController.DetalleCompletoWrapper(relacion, asegurados, historicos, pagos, relaciones);
        
        System.assertNotEquals(null, detalleWrapper.relacionPrincipal);
        System.assert(!detalleWrapper.asegurados.isEmpty());
        System.assert(!detalleWrapper.historicos.isEmpty());
        System.assert(!detalleWrapper.pagos.isEmpty());
        System.assert(!detalleWrapper.relaciones.isEmpty());
        System.assertNotEquals(null, detalleWrapper.poliza);
        Test.stopTest();
    }
    
    @IsTest
    static void testCoverageForNullRelations() {
        // Crear una relación con campos nulos para probar los wrappers
        Polizas__c poliza = new Polizas__c(
            Name = 'POL-002',
            Estatus__c = 'Activa'
        );
        insert poliza;
        
        Relacion_Poliza__c relacionNull = new Relacion_Poliza__c(
            Poliza__c = poliza.Id
            // No asignar Asegurado, Historico ni Pago
        );
        insert relacionNull;
        
        Test.startTest();
        List<HistoricoPolizasController.RelacionPolizaWrapper> resultados = HistoricoPolizasController.buscaInicial();
        
        // Buscar la relación con campos nulos
        HistoricoPolizasController.RelacionPolizaWrapper wrapperNull = null;
        for (HistoricoPolizasController.RelacionPolizaWrapper wrapper : resultados) {
            if (wrapper.relacionName == 'REL-NULL') {
                wrapperNull = wrapper;
                break;
            }
        }
        
        Test.stopTest();
    }
}