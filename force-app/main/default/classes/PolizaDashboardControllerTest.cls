@IsTest
public with sharing class PolizaDashboardControllerTest {
    
    @TestSetup
    static void setupTestData() {
        // Crear datos de prueba para pólizas
        List<Polizas__c> testPolizas = new List<Polizas__c>();
        
        Date today = Date.today();
        Date startOfMonth = today.toStartOfMonth();
        
        // Crear pólizas para diferentes escenarios
        for (Integer i = 0; i < 5; i++) {
            Polizas__c poliza = new Polizas__c(
                Name = 'Test Poliza ' + i,
                Numero_Polizas__c = 'TEST-' + i,
                Estatus__c = i == 0 ? 'Vigor' : (i == 1 ? 'Vigor' : (i == 2 ? 'Cancelada' : 'Cancelada')),
                Nombre_contratante__c = 'Test Contratante ' + i,
                Moneda__c = 'Pesos',
                Forma_de_pago__c = 'Mensual',
                Fecha_de_Emision__c = startOfMonth.addDays(i),
                Vigencia_hasta__c = startOfMonth.addDays(i + 30),
                Suma_Aseguradora__c = 50000 + (i * 10000)
            );
            testPolizas.add(poliza);
        }
        
        // Crear pólizas vencidas
        for (Integer i = 5; i < 8; i++) {
            Polizas__c poliza = new Polizas__c(
                Name = 'Test Poliza Vencida ' + i,
                Numero_Polizas__c = 'TEST-VEN-' + i,
                Estatus__c = 'Vigor',
                Nombre_contratante__c = 'Test Contratante ' + i,
                Moneda__c = 'Pesos',
                Forma_de_pago__c = 'Mensual',
                Fecha_de_Emision__c = today.addDays(-60),
                Vigencia_hasta__c = today.addDays(-1),
                Suma_Aseguradora__c = 75000
            );
            testPolizas.add(poliza);
        }
        
        insert testPolizas;
    }
    
    @IsTest
    static void testGetDashboardDataCobranzaMensual() {
        Test.startTest();
        
        PolizaDashboardController.PolizaDashboardWrapper result = 
            PolizaDashboardController.getDashboardDataCobranza('mensual');
        
        Test.stopTest();
        
        // Verificaciones
        System.assertNotEquals(null, result, 'El resultado no debería ser nulo');
        System.assertEquals('mensual', result.periodo, 'El período debería ser mensual');
        System.assertNotEquals(null, result.polizas, 'La lista de pólizas no debería ser nula');
        System.assert(result.totalPolizas > 0, 'Debería haber pólizas en el período');
        System.assertNotEquals(null, result.totalPrimas, 'El total de primas no debería ser nulo');
        System.assertNotEquals(null, result.totalPendiente, 'El total pendiente no debería ser nulo');
        System.assertNotEquals(null, result.totalSumaAsegurada, 'El total de suma asegurada no debería ser nulo');
        System.assertNotEquals(null, result.resumenEstatus, 'El resumen por estatus no debería ser nulo');
    }
    
    @IsTest
    static void testGetDashboardDataCobranzaBimestral() {
        Test.startTest();
        
        PolizaDashboardController.PolizaDashboardWrapper result = 
            PolizaDashboardController.getDashboardDataCobranza('bimestral');
        
        Test.stopTest();
        
        // Verificaciones
        System.assertNotEquals(null, result, 'El resultado no debería ser nulo');
        System.assertEquals('bimestral', result.periodo, 'El período debería ser bimestral');
        System.assertNotEquals(null, result.fechaInicio, 'La fecha de inicio no debería ser nula');
        System.assertNotEquals(null, result.fechaFin, 'La fecha fin no debería ser nula');
    }
    
    @IsTest
    static void testGetDashboardDataCobranzaSemestral() {
        Test.startTest();
        
        PolizaDashboardController.PolizaDashboardWrapper result = 
            PolizaDashboardController.getDashboardDataCobranza('semestral');
        
        Test.stopTest();
        
        // Verificaciones
        System.assertNotEquals(null, result, 'El resultado no debería ser nulo');
        System.assertEquals('semestral', result.periodo, 'El período debería ser semestral');
    }
    
    @IsTest
    static void testGetDashboardDataCobranzaDefault() {
        Test.startTest();
        
        PolizaDashboardController.PolizaDashboardWrapper result = 
            PolizaDashboardController.getDashboardDataCobranza('invalid');
        
        Test.stopTest();
        
        // Verificaciones
        System.assertNotEquals(null, result, 'El resultado no debería ser nulo');
    }
    
    @IsTest
    static void testGetPolizasVencidas() {
        Test.startTest();
        
        List<Polizas__c> result = PolizaDashboardController.getPolizasVencidas();
        
        Test.stopTest();
        
        // Verificaciones
        System.assertNotEquals(null, result, 'El resultado no debería ser nulo');
        System.assert(result.size() > 0, 'Debería haber pólizas vencidas');
        
        // Verificar que las pólizas tienen fecha de emisión anterior a hoy
        for (Polizas__c poliza : result) {
            System.assert(poliza.Fecha_de_Emision__c < Date.today(), 
                         'La póliza debería tener fecha de emisión anterior a hoy');
        }
    }
    
    @IsTest
    static void testGetDashboardDataCobranzaWithNoData() {
        // Eliminar todos los datos de prueba primero
        delete [SELECT Id FROM Polizas__c];
        
        Test.startTest();
        
        PolizaDashboardController.PolizaDashboardWrapper result = 
            PolizaDashboardController.getDashboardDataCobranza('mensual');
        
        Test.stopTest();
        
        // Verificaciones para cuando no hay datos
        System.assertNotEquals(null, result, 'El resultado no debería ser nulo');
        System.assertEquals(0, result.totalPolizas, 'No debería haber pólizas');
        System.assertEquals(0, result.totalPrimas, 'El total de primas debería ser 0');
        System.assertEquals(0, result.totalPendiente, 'El total pendiente debería ser 0');
        System.assertEquals(0, result.totalSumaAsegurada, 'El total de suma asegurada debería ser 0');
    }
    
    @IsTest
    static void testResumenEstatusClass() {
        Test.startTest();
        
        // Probar la clase interna ResumenEstatus
        PolizaDashboardController.ResumenEstatus resumen = 
            new PolizaDashboardController.ResumenEstatus('Test', 5);
        
        Test.stopTest();
        
        // Verificaciones
        System.assertEquals('Test', resumen.estatus, 'El estatus debería coincidir');
        System.assertEquals(5, resumen.cantidad, 'La cantidad debería coincidir');
    }
    
    @IsTest
    static void testWrapperClass() {
        Test.startTest();
        
        // Crear datos de prueba para el wrapper
        List<Polizas__c> polizas = new List<Polizas__c>();
        List<PolizaDashboardController.ResumenEstatus> resumenList = new List<PolizaDashboardController.ResumenEstatus>{
            new PolizaDashboardController.ResumenEstatus('Vigor', 3)
        };
        
        PolizaDashboardController.PolizaDashboardWrapper wrapper = 
            new PolizaDashboardController.PolizaDashboardWrapper(
                polizas, 
                10000, 
                5000, 
                5, 
                500000, 
                resumenList, 
                'Mensual', 
                2024, 
                Date.today(), 
                Date.today().addDays(30)
            );
        
        Test.stopTest();
        
        // Verificaciones
        System.assertEquals(polizas, wrapper.polizas, 'Las pólizas deberían coincidir');
        System.assertEquals(10000, wrapper.totalPrimas, 'El total de primas debería coincidir');
        System.assertEquals(5000, wrapper.totalPendiente, 'El total pendiente debería coincidir');
        System.assertEquals(5, wrapper.totalPolizas, 'El total de pólizas debería coincidir');
        System.assertEquals(500000, wrapper.totalSumaAsegurada, 'El total de suma asegurada debería coincidir');
        System.assertEquals(resumenList, wrapper.resumenEstatus, 'El resumen por estatus debería coincidir');
        System.assertEquals('Mensual', wrapper.periodo, 'El período debería coincidir');
        System.assertEquals(2024, wrapper.year, 'El año debería coincidir');
    }
}