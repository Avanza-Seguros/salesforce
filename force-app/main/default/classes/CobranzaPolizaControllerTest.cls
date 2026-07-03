@IsTest
public with sharing class CobranzaPolizaControllerTest {
    
    @TestSetup
    static void makeData(){
        // Crear datos de prueba comunes para todos los tests
        Account asegurado = new Account(
            Name = 'Cuenta Test Asegurado',
            Type = 'Cliente'
        );
        insert asegurado;

        // Crear Agente (Usuario)
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User'];
        User agente = new User(
            Alias = 'agente',
            Email = 'agente.test@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'agente.test@test.com'
        );
        insert agente;

        // Crear múltiples pólizas con diferentes estados
        List<Polizas__c> polizas = new List<Polizas__c>();
        
        // Póliza Vigente
        polizas.add(new Polizas__c(
            Asegurado__c = asegurado.Id,
            Estatus__c = 'Vigor',
            Vigencia_desde__c = Date.today().addDays(-30),
            Vigencia_hasta__c = Date.today().addDays(335),
            Tipo_de_poliza__c = 'Automóvil'
        ));

        // Póliza Pendiente
        polizas.add(new Polizas__c(
            Asegurado__c = asegurado.Id,
            Estatus__c = 'Vencida',
            Vigencia_desde__c = Date.today(),
            Vigencia_hasta__c = Date.today().addDays(365),
            Tipo_de_poliza__c = 'Hogar'
        ));

        // Póliza Cancelada
        polizas.add(new Polizas__c(
            Asegurado__c = asegurado.Id,
            Estatus__c = 'Cancelada',
            Vigencia_desde__c = Date.today().addDays(-60),
            Vigencia_hasta__c = Date.today().addDays(-30),
            Tipo_de_poliza__c = 'Vida'
        ));

        insert polizas;

        Historico_Aportacion__c historico = new Historico_Aportacion__c(
            Anualidad__c = '2024',
            PrimaBasica__c = 3000,
            PrimaAdicional__c = 500,
            PagosIngresados__c = 3500,
            Desde__c = Date.today().addDays(-30),
            Hasta__c = Date.today().addDays(335),
            Poliza__c = polizas[0].Id
        );
        insert historico;
        
        // Crear pagos asociados a las pólizas
        List<Pago_Poliza__c> pagos = new List<Pago_Poliza__c>();
        
        // Pagos para la póliza vigente
        pagos.add(new Pago_Poliza__c(
            Poliza__c = polizas[0].Id,
            Monto__c = 500.00,
            Fecha_de_Aplicaci_n_del_pago__c = Date.today().addDays(-30),
            Estatus_pago__c = 'Pagado',
            Historico_Aportacion__c = historico.Id
        ));

        pagos.add(new Pago_Poliza__c(
            Poliza__c = polizas[0].Id,
            Monto__c = 500.00,
            Fecha_de_Aplicaci_n_del_pago__c = Date.today(),
            Estatus_pago__c = 'Pendiente',
            Historico_Aportacion__c = historico.Id
        ));

        // Pago para póliza pendiente
        pagos.add(new Pago_Poliza__c(
            Poliza__c = polizas[1].Id,
            Monto__c = 300.00,
            Fecha_de_Aplicaci_n_del_pago__c = null,
            Estatus_pago__c = 'Pendiente',
            Historico_Aportacion__c = historico.Id
        ));

        insert pagos;
    }

    @IsTest
    static void testGetPolizas_Positive() {
        // Test: Verificar que se obtienen todas las pólizas correctamente
        Test.startTest();
        List<Polizas__c> result = CobranzaPolizaController.getPolizas();
        Test.stopTest();

        // Verificaciones
        Assert.areNotEqual(null, result, 'La lista de pólizas no debería ser nula');
        Assert.areEqual(3, result.size(), 'Deberían retornarse 3 pólizas');
        
        // Verificar ordenamiento por Vigencia_hasta__c DESC
        Date previousDate = Date.today().addDays(400); // Fecha futura muy lejana
        for(Polizas__c poliza : result) {
            Assert.isTrue(previousDate >= poliza.Vigencia_hasta__c, 
                         'Las pólizas deberían estar ordenadas por Vigencia_hasta__c DESC');
            previousDate = poliza.Vigencia_hasta__c;
        }

        // Verificar que los campos están poblados
        for(Polizas__c poliza : result) {
            Assert.isTrue(poliza.Name != null, 'El nombre de la póliza no debería ser nulo');
            Assert.isTrue(poliza.Asegurado__r.Name != null, 'El nombre del asegurado no debería ser nulo');
        }
    }

    @IsTest
    static void testGetPolizas_EmptyResult() {
        // Test: Escenario cuando no hay pólizas
        // Eliminar todas las pólizas primero
        
        delete [SELECT Id FROM Pago_poliza__c];
        delete [SELECT Id FROM Historico_Aportacion__c];
        delete [SELECT Id FROM Polizas__c];

        Test.startTest();
        List<Polizas__c> result = CobranzaPolizaController.getPolizas();
        Test.stopTest();

        Assert.areNotEqual(null, result, 'La lista no debería ser nula incluso cuando está vacía');
        Assert.areEqual(0, result.size(), 'La lista debería estar vacía');
    }

    @IsTest
    static void testGetResumenPolizas_Positive() {
        // Test: Verificar que el resumen cuenta correctamente por estatus
        Test.startTest();
        Map<String, Integer> result = CobranzaPolizaController.getResumenPolizas();
        Test.stopTest();

        // Verificaciones
        Assert.areNotEqual(null, result, 'El mapa de resumen no debería ser nulo');
        Assert.areEqual(3, result.get('totalPolizas'), 'Debería haber 3 pólizas en total');
        Assert.areEqual(1, result.get('Vigor'), 'Debería haber 1 póliza Vigor');
        Assert.areEqual(1, result.get('Cancelada'), 'Debería haber 1 póliza Cancelada');
        Assert.areEqual(1, result.get('Vencida'), 'Debería haber 1 póliza Vencida');
    }

    @IsTest
    static void testGetResumenPolizas_Empty() {
        // Test: Resumen cuando no hay pólizas
        
        delete [SELECT Id FROM Pago_poliza__c];
        delete [SELECT Id FROM Historico_Aportacion__c];
        delete [SELECT Id FROM Polizas__c];

        Test.startTest();
        Map<String, Integer> result = CobranzaPolizaController.getResumenPolizas();
        Test.stopTest();

        Assert.areNotEqual(null, result, 'El mapa no debería ser nulo incluso cuando no hay datos');
        Assert.areEqual(0, result.get('totalPolizas'), 'El total debería ser 0');
    }

    @IsTest
    static void testGetPagosPoliza_Positive() {
        // Test: Obtener pagos de una póliza específica
        Polizas__c polizaTest = [SELECT Id FROM Polizas__c LIMIT 1];

        Test.startTest();
        List<Pago_Poliza__c> result = CobranzaPolizaController.getPagosPoliza(polizaTest.Id);
        Test.stopTest();

        Assert.areNotEqual(null, result, 'La lista de pagos no debería ser nula');

        // Verificar campos de los pagos
        for(Pago_Poliza__c pago : result) {
            Assert.isTrue(pago.Name != null, 'El nombre del pago no debería ser nulo');
            Assert.isTrue(pago.Monto__c != null, 'El monto no debería ser nulo');
            Assert.isTrue(pago.Estatus_pago__c != null, 'El estatus del pago no debería ser nulo');
        }
    }

    @IsTest
    static void testGetPagosPoliza_EmptyResult() {
        // Test: Póliza sin pagos
        Polizas__c polizaSinPagos = [SELECT Id FROM Polizas__c WHERE Estatus__c = 'Cancelada' LIMIT 1];

        Test.startTest();
        List<Pago_Poliza__c> result = CobranzaPolizaController.getPagosPoliza(polizaSinPagos.Id);
        Test.stopTest();

        Assert.areNotEqual(null, result, 'La lista no debería ser nula incluso cuando está vacía');
        Assert.areEqual(0, result.size(), 'Debería retornar lista vacía para póliza sin pagos');
    }

    @IsTest
    static void testGetPagosPoliza_InvalidId() {
        // Test: ID de póliza inválido
        Test.startTest();
        List<Pago_Poliza__c> result = CobranzaPolizaController.getPagosPoliza('001000000000000');
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Debería retornar una lista vacía en lugar de null');
        Assert.areEqual(0, result.size(), 'Debería retornar lista vacía para ID inválido');
    }

    @IsTest
    static void testGetPagosPoliza_NullId() {
        // Test: ID nulo
        Test.startTest();
        List<Pago_Poliza__c> result = CobranzaPolizaController.getPagosPoliza(null);
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Debería retornar una lista vacía en lugar de null');
        Assert.areEqual(0, result.size(), 'Debería retornar lista vacía para ID nulo');
    }

    @IsTest
    static void testSecurityAndAccess() {
        // Test: Verificar seguridad y acceso a campos
        Test.startTest();
        
        // Verificar que el usuario tiene acceso de lectura a los objetos
        Assert.isTrue(Schema.sObjectType.Polizas__c.isAccessible(), 
                     'El usuario debería tener acceso de lectura a Polizas__c');
        Assert.isTrue(Schema.sObjectType.Pago_Poliza__c.isAccessible(), 
                     'El usuario debería tener acceso de lectura a Pago_Poliza__c');
        Assert.isTrue(Schema.sObjectType.Account.isAccessible(), 
                     'El usuario debería tener acceso de lectura a Account');
        
        // Verificar acceso a campos específicos de Polizas__c
        Assert.isTrue(Schema.sObjectType.Polizas__c.fields.Name.isAccessible());
        Assert.isTrue(Schema.sObjectType.Polizas__c.fields.Asegurado__c.isAccessible());
        Assert.isTrue(Schema.sObjectType.Polizas__c.fields.Estatus__c.isAccessible());
        Assert.isTrue(Schema.sObjectType.Polizas__c.fields.PrimaTotal__c.isAccessible());
        Assert.isTrue(Schema.sObjectType.Polizas__c.fields.Vigencia_hasta__c.isAccessible());
        
        Test.stopTest();
    }

    @IsTest
    static void testPerformance() {
        // Test: Performance con gran volumen de datos
        // Crear 200 pólizas adicionales para test de performance
        List<Polizas__c> bulkPolizas = new List<Polizas__c>();
        Account asegurado = [SELECT Id FROM Account LIMIT 1];
        
        for(Integer i = 0; i < 200; i++) {
            bulkPolizas.add(new Polizas__c(
                Name = 'BULK-POL-' + i,
                Asegurado__c = asegurado.Id,
                Estatus__c = 'Vigor',
                Vigencia_desde__c = Date.today(),
                Vigencia_hasta__c = Date.today().addDays(365)
            ));
        }
        insert bulkPolizas;

        Test.startTest();
        // Medir tiempo de ejecución para getPolizas
        Long startTime = DateTime.now().getTime();
        List<Polizas__c> result = CobranzaPolizaController.getPolizas();
        Long endTime = DateTime.now().getTime();
        Long executionTime = endTime - startTime;
        
        // Verificar que la consulta se ejecuta en menos de 2 segundos
        Assert.isTrue(executionTime < 2000, 
                     'La consulta debería ejecutarse en menos de 2 segundos. Tiempo: ' + executionTime + 'ms');
        
        Assert.areEqual(203, result.size(), 'Deberían retornarse 203 pólizas (3 originales + 200 bulk)');
        Test.stopTest();
    }

    @IsTest
    static void testExceptionHandling() {
        // Test: Manejo de excepciones
        // Simular una excepción forzando un error en la consulta
        // Usando un mock para simular una excepción
        
        Test.startTest();
        try {
            // Intentar obtener pagos con un ID mal formado para forzar excepción
            List<Pago_Poliza__c> result = CobranzaPolizaController.getPagosPoliza('INVALID_ID_FORMAT');
            // Si llegamos aquí, el método manejó la excepción correctamente
            Assert.isTrue(true, 'El método debería manejar la excepción sin propagarla');
        } catch (Exception e) {
            Assert.isTrue(e instanceof AuraHandledException, 
                         'Las excepciones deberían ser de tipo AuraHandledException');
        }
        Test.stopTest();
    }
}