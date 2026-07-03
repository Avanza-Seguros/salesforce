@IsTest
public with sharing class GenerarRelacionPolizaControllerTest {
    
    @TestSetup
    static void setupTestData() {
        // Crear pólizas de prueba
        List<Polizas__c> polizas = new List<Polizas__c>();
        for (Integer i = 0; i < 3; i++) {
            polizas.add(new Polizas__c(
                Name = 'POL-TEST-' + i
            ));
        }
        insert polizas;
        
        Historico_Aportacion__c h1 = new Historico_Aportacion__c(
            Anualidad__c = '2024',
            PrimaBasica__c = 3000,
            PrimaAdicional__c = 500,
            PagosIngresados__c = 3500,
            Desde__c = Date.today().addDays(-30),
            Hasta__c = Date.today().addDays(335),
            Poliza__c = polizas[0].Id
        );
        insert h1;
        
        // Crear asegurados para algunas pólizas
        List<Asegurado__c> asegurados = new List<Asegurado__c>();
        for (Polizas__c poliza : polizas) {
            if (poliza.Name == 'POL-TEST-0') {
                // Múltiples asegurados para la primera póliza
                asegurados.add(new Asegurado__c(
                    Name = 'Asegurado 1 - ' + poliza.Name,
                    Polizas__c = poliza.Id,
                    FechaNacimiento__c = Date.newInstance(1980, 1, 1)
                ));
                asegurados.add(new Asegurado__c(
                    Name = 'Asegurado 2 - ' + poliza.Name,
                    Polizas__c = poliza.Id,
                    FechaNacimiento__c = Date.newInstance(1985, 6, 15)
                ));
            } else if (poliza.Name == 'POL-TEST-1') {
                // Un solo asegurado para la segunda póliza
                asegurados.add(new Asegurado__c(
                    Name = 'Asegurado 1 - ' + poliza.Name,
                    Polizas__c = poliza.Id,
                    FechaNacimiento__c = Date.newInstance(1990, 3, 20)
                ));
            }
            // La tercera póliza no tiene asegurados
        }
        if (!asegurados.isEmpty()) {
            insert asegurados;
        }
        
        // Crear pagos para las pólizas
        List<Pago_Poliza__c> pagos = new List<Pago_Poliza__c>();
        for (Polizas__c poliza : polizas) {
            // Múltiples pagos para cada póliza (se ordenarán por fecha descendente)
            pagos.add(new Pago_Poliza__c(
                Poliza__c = poliza.Id,
                Importe_de_Ultima_Aportacion__c = 1000,
                Tipo_de_Moneda__c = 'MXN',
                Valor_Moneda__c = 1,
                Modo_de_Pago__c = 'Transferencia',
                Fecha_de_emision__c = Date.today(),
                Estatus_del_Pago__c = 'Pagado',
            	Historico_Aportacion__c = h1.Id
            ));
            pagos.add(new Pago_Poliza__c(
                Poliza__c = poliza.Id,
                Importe_de_Ultima_Aportacion__c = 500,
                Tipo_de_Moneda__c = 'USD',
                Valor_Moneda__c = 20,
                Modo_de_Pago__c = 'Efectivo',
                Fecha_de_emision__c = Date.today().addDays(-30),
                Estatus_del_Pago__c = 'Pagado',
            	Historico_Aportacion__c = h1.Id
            ));
        }
        insert pagos;
        
        // Crear históricos para las pólizas
        List<Historico_Aportacion__c> historicos = new List<Historico_Aportacion__c>();
        for (Polizas__c poliza : polizas) {
            // Múltiples históricos para cada póliza (se ordenarán por fecha descendente)
            historicos.add(new Historico_Aportacion__c(
                Poliza__c = poliza.Id,
                Anualidad__c = '2024',
                Desde__c = Date.today().addDays(-60),
                Hasta__c = Date.today().addDays(-30),
                PagosIngresados__c = 1000,
                PrimaAdicional__c = 100,
                PrimaBasica__c = 900
            ));
            historicos.add(new Historico_Aportacion__c(
                Poliza__c = poliza.Id,
                Anualidad__c = '2023',
                Desde__c = Date.today().addDays(-90),
                Hasta__c = Date.today().addDays(-61),
                PagosIngresados__c = 800,
                PrimaAdicional__c = 80,
                PrimaBasica__c = 720
            ));
        }
        insert historicos;
    }
    
    @IsTest
    static void testBuildRelaciones_WithMultipleAsegurados() {
        // Obtener la póliza con múltiples asegurados
        Polizas__c polizaConMultiplesAsegurados = [SELECT Id FROM Polizas__c WHERE Name = 'POL-TEST-0' LIMIT 1];
        
        Test.startTest();
        List<Relacion_Poliza__c> relaciones = GenerarRelacionPolizaController.buildRelaciones(
            new List<Id>{polizaConMultiplesAsegurados.Id}
        );
        Test.stopTest();
        
        // Verificar resultados
        Assert.areNotEqual(null, relaciones, 'La lista de relaciones no debería ser nula');
        Assert.areEqual(2, relaciones.size(), 'Deberían crearse 2 relaciones (uno por cada asegurado)');
        
        // Verificar que se usó el pago más reciente y el histórico más reciente
        for (Relacion_Poliza__c relacion : relaciones) {
            Assert.areEqual(polizaConMultiplesAsegurados.Id, relacion.Poliza__c, 'La relación debe apuntar a la póliza correcta');
            Assert.areNotEqual(null, relacion.Asegurado__c, 'Debe tener un asegurado asignado');
            Assert.areNotEqual(null, relacion.Pago__c, 'Debe tener un pago asignado');
            Assert.areNotEqual(null, relacion.Historico__c, 'Debe tener un histórico asignado');
        }
        
        // Verificar que se eliminaron relaciones previas y se crearon nuevas
        List<Relacion_Poliza__c> relacionesEnBD = [
            SELECT Id FROM Relacion_Poliza__c 
            WHERE Poliza__c = :polizaConMultiplesAsegurados.Id
        ];
        Assert.areEqual(2, relacionesEnBD.size(), 'Debería haber exactamente 2 relaciones en la BD');
    }
    
    @IsTest
    static void testBuildRelaciones_WithSingleAsegurado() {
        // Obtener la póliza con un solo asegurado
        Polizas__c polizaConUnAsegurado = [SELECT Id FROM Polizas__c WHERE Name = 'POL-TEST-1' LIMIT 1];
        
        Test.startTest();
        List<Relacion_Poliza__c> relaciones = GenerarRelacionPolizaController.buildRelaciones(
            new List<Id>{polizaConUnAsegurado.Id}
        );
        Test.stopTest();
        
        // Verificar resultados
        Assert.areNotEqual(null, relaciones, 'La lista de relaciones no debería ser nula');
        Assert.areEqual(1, relaciones.size(), 'Debería crearse 1 relación (un solo asegurado)');
        
        Relacion_Poliza__c relacion = relaciones[0];
        Assert.areEqual(polizaConUnAsegurado.Id, relacion.Poliza__c, 'La relación debe apuntar a la póliza correcta');
        Assert.areNotEqual(null, relacion.Asegurado__c, 'Debe tener un asegurado asignado');
        Assert.areNotEqual(null, relacion.Historico__c, 'Debe tener un histórico asignado');
    }
    
    @IsTest
    static void testBuildRelaciones_WithoutAsegurados() {
        // Obtener la póliza sin asegurados
        Polizas__c polizaSinAsegurados = [SELECT Id FROM Polizas__c WHERE Name = 'POL-TEST-2' LIMIT 1];
        
        Test.startTest();
        List<Relacion_Poliza__c> relaciones = GenerarRelacionPolizaController.buildRelaciones(
            new List<Id>{polizaSinAsegurados.Id}
        );
        Test.stopTest();
        
        // Verificar resultados
        Assert.areNotEqual(null, relaciones, 'La lista de relaciones no debería ser nula');
        Assert.areEqual(1, relaciones.size(), 'Debería crearse 1 relación incluso sin asegurados');
        
        Relacion_Poliza__c relacion = relaciones[0];
        Assert.areEqual(polizaSinAsegurados.Id, relacion.Poliza__c, 'La relación debe apuntar a la póliza correcta');
        Assert.areEqual(null, relacion.Asegurado__c, 'No debe tener asegurado asignado');
        Assert.areNotEqual(null, relacion.Historico__c, 'Debe tener un histórico asignado');
    }
    
    @IsTest
    static void testBuildRelaciones_MultiplePolizas() {
        // Obtener todas las pólizas
        List<Polizas__c> polizas = [SELECT Id FROM Polizas__c ORDER BY Name];
        List<Id> polizaIds = new List<Id>();
        for (Polizas__c poliza : polizas) {
            polizaIds.add(poliza.Id);
        }
        
        Test.startTest();
        List<Relacion_Poliza__c> relaciones = GenerarRelacionPolizaController.buildRelaciones(polizaIds);
        Test.stopTest();
        
        // Verificar resultados
        Assert.areNotEqual(null, relaciones, 'La lista de relaciones no debería ser nula');
        
        // POL-TEST-0: 2 asegurados = 2 relaciones
        // POL-TEST-1: 1 asegurado = 1 relación
        // POL-TEST-2: 0 asegurados = 1 relación
        // Total: 4 relaciones
        Assert.areEqual(4, relaciones.size(), 'Deberían crearse 4 relaciones en total para las 3 pólizas');

    }
    
    @IsTest
    static void testBuildRelaciones_WithExistingRelations() {
        // Crear relaciones existentes primero
        Polizas__c poliza = [SELECT Id FROM Polizas__c WHERE Name = 'POL-TEST-0' LIMIT 1];
        Asegurado__c asegurado = [SELECT Id FROM Asegurado__c WHERE Polizas__c = :poliza.Id LIMIT 1];
        Pago_Poliza__c pago = [SELECT Id FROM Pago_Poliza__c WHERE Poliza__c = :poliza.Id LIMIT 1];
        Historico_Aportacion__c historico = [SELECT Id FROM Historico_Aportacion__c WHERE Poliza__c = :poliza.Id LIMIT 1];
        
        // Crear relación existente
        Relacion_Poliza__c relacionExistente = new Relacion_Poliza__c(
            Poliza__c = poliza.Id,
            Asegurado__c = asegurado.Id,
            Pago__c = pago.Id,
            Historico__c = historico.Id
        );
        insert relacionExistente;
        
        // Verificar que existe la relación previa
        List<Relacion_Poliza__c> relacionesPrevias = [
            SELECT Id FROM Relacion_Poliza__c WHERE Poliza__c = :poliza.Id
        ];
        Assert.areEqual(1, relacionesPrevias.size(), 'Debería existir una relación previa');
        
        Test.startTest();
        List<Relacion_Poliza__c> nuevasRelaciones = GenerarRelacionPolizaController.buildRelaciones(
            new List<Id>{poliza.Id}
        );
        Test.stopTest();
        
        // Verificar que se eliminó la relación previa y se crearon las nuevas
        List<Relacion_Poliza__c> relacionesFinales = [
            SELECT Id FROM Relacion_Poliza__c WHERE Poliza__c = :poliza.Id
        ];
        Assert.areEqual(2, relacionesFinales.size(), 'Deberían haberse creado 2 nuevas relaciones');
        Assert.areEqual(2, nuevasRelaciones.size(), 'Deberían retornarse 2 nuevas relaciones');
    }
    
    @IsTest
    static void testBuildRelaciones_EmptyPolizaIds() {
        Test.startTest();
        List<Relacion_Poliza__c> relaciones = GenerarRelacionPolizaController.buildRelaciones(new List<Id>());
        Test.stopTest();
        
        Assert.areNotEqual(null, relaciones, 'La lista de relaciones no debería ser nula');
        Assert.areEqual(0, relaciones.size(), 'Debería retornar una lista vacía para IDs vacíos');
    }
    
    @IsTest
    static void testBuildRelaciones_WithInvalidPolizaId() {
        Test.startTest();
        List<Relacion_Poliza__c> relaciones = GenerarRelacionPolizaController.buildRelaciones(
            new List<Id>{'001000000000000'} // ID inválido
        );
        Test.stopTest();
        
        Assert.areNotEqual(null, relaciones, 'La lista de relaciones no debería ser nula');
        Assert.areEqual(0, relaciones.size(), 'Debería retornar una lista vacía para ID inválido');
    }
    
    @IsTest
    static void testBuildRelaciones_UsesMostRecentPagoAndHistorico() {
        Polizas__c poliza = [SELECT Id FROM Polizas__c WHERE Name = 'POL-TEST-0' LIMIT 1];
        
        Test.startTest();
        List<Relacion_Poliza__c> relaciones = GenerarRelacionPolizaController.buildRelaciones(
            new List<Id>{poliza.Id}
        );
        Test.stopTest();
        
        // Obtener el pago más reciente y histórico más reciente
        Pago_Poliza__c pagoReciente = [
            SELECT Id, Name, Fecha_de_emision__c 
            FROM Pago_Poliza__c 
            WHERE Poliza__c = :poliza.Id 
            ORDER BY Fecha_de_emision__c DESC 
            LIMIT 1
        ];
        
        Historico_Aportacion__c historicoReciente = [
            SELECT Id, Name, Desde__c 
            FROM Historico_Aportacion__c 
            WHERE Poliza__c = :poliza.Id 
            ORDER BY Desde__c DESC 
            LIMIT 1
        ];
        
        // Verificar que todas las relaciones usan los registros más recientes
        for (Relacion_Poliza__c relacion : relaciones) {
            Assert.areEqual(pagoReciente.Id, relacion.Pago__c, 
                'Debe usar el pago más reciente por fecha de emisión');
            Assert.areEqual(historicoReciente.Id, relacion.Historico__c, 
                'Debe usar el histórico más reciente por fecha desde');
        }
    }
    
    @IsTest
    static void testBuildRelaciones_WithoutPagos() {
        // Crear una póliza sin pagos
        Polizas__c polizaSinPagos = new Polizas__c(Name = 'POL-SIN-PAGOS');
        insert polizaSinPagos;
        
        // Crear un asegurado para esta póliza
        Asegurado__c asegurado = new Asegurado__c(
            Name = 'Asegurado Sin Pagos',
            Polizas__c = polizaSinPagos.Id
        );
        insert asegurado;
        
        Test.startTest();
        List<Relacion_Poliza__c> relaciones = GenerarRelacionPolizaController.buildRelaciones(
            new List<Id>{polizaSinPagos.Id}
        );
        Test.stopTest();
        
        Assert.areEqual(1, relaciones.size(), 'Debería crearse 1 relación');
        Assert.areEqual(null, relaciones[0].Pago__c, 'El pago debería ser nulo cuando no hay pagos');
        Assert.areEqual(null, relaciones[0].Historico__c, 'El histórico debería ser nulo cuando no hay históricos');
    }
    
    @IsTest
    static void testBuildRelaciones_WithoutHistoricos() {
        // Crear una póliza sin históricos
        Polizas__c polizaSinHistoricos = new Polizas__c(Name = 'POL-SIN-HISTORICOS');
        insert polizaSinHistoricos;
        
        Historico_Aportacion__c h1 = new Historico_Aportacion__c(
            Anualidad__c = '2024',
            PrimaBasica__c = 3000,
            PrimaAdicional__c = 500,
            PagosIngresados__c = 3500,
            Desde__c = Date.today().addDays(-30),
            Hasta__c = Date.today().addDays(335),
            Poliza__c = polizaSinHistoricos.Id
        );
        insert h1;
        
        // Crear un asegurado para esta póliza
        Asegurado__c asegurado = new Asegurado__c(
            Name = 'Asegurado Sin Historicos',
            Polizas__c = polizaSinHistoricos.Id
        );
        insert asegurado;
        
        // Crear un pago para esta póliza
        Pago_Poliza__c pago = new Pago_Poliza__c(
            Poliza__c = polizaSinHistoricos.Id,
            Fecha_de_emision__c = Date.today(),
            Historico_Aportacion__c = h1.Id
        );
        insert pago;
        
        Test.startTest();
        List<Relacion_Poliza__c> relaciones = GenerarRelacionPolizaController.buildRelaciones(
            new List<Id>{polizaSinHistoricos.Id}
        );
        Test.stopTest();
        
    }
    
    @IsTest
    static void testBuildRelaciones_BulkSafeOperation() {
        // Crear múltiples pólizas para probar operación bulk
        List<Polizas__c> polizasBulk = new List<Polizas__c>();
        List<Id> polizaIds = new List<Id>();
        
        for (Integer i = 0; i < 10; i++) {
            Polizas__c poliza = new Polizas__c(Name = 'POL-BULK-' + i);
            polizasBulk.add(poliza);
        }
        insert polizasBulk;
        
        for (Polizas__c poliza : polizasBulk) {
            polizaIds.add(poliza.Id);
        }
        
        Test.startTest();
        List<Relacion_Poliza__c> relaciones = GenerarRelacionPolizaController.buildRelaciones(polizaIds);
        Test.stopTest();
        
        Assert.areNotEqual(null, relaciones, 'La lista de relaciones no debería ser nula');
        // Cada póliza sin asegurados crea 1 relación = 10 relaciones
        Assert.areEqual(10, relaciones.size(), 'Deberían crearse 10 relaciones');
    }
}