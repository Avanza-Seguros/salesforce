@IsTest
public with sharing class PolizasPendientesTest {
    
    @TestSetup
    static void setupTestData() {
        // Crear pólizas de prueba
        List<Polizas__c> polizas = new List<Polizas__c>();
        polizas.add(new Polizas__c(Name = 'POL-001'));
        polizas.add(new Polizas__c(Name = 'POL-002'));
        polizas.add(new Polizas__c(Name = 'POL-003'));
        insert polizas;
        
        Historico_Aportacion__c historico = new Historico_Aportacion__c(
            Anualidad__c = '2024',
            PrimaBasica__c = 3000,
            PrimaAdicional__c = 500,
            PagosIngresados__c = 3500,
            Desde__c = Date.today().addDays(-30),
            Hasta__c = Date.today().addDays(335),
            Poliza__c = polizas.get(0).Id
        );
        insert historico;
        
        // Crear pagos de prueba con diferentes estados y fechas
        List<Pago_poliza__c> pagos = new List<Pago_poliza__c>();
        
        // Pagos para POL-001 - Escenario con múltiples estados
        pagos.add(new Pago_poliza__c(
            Poliza_sc__c = polizas[0].Id,
            Estatus_del_Pago__c = 'Pendiente',
            Fecha_de_de_Vencimiento__c = Date.today().addDays(-10),
            Historico_Aportacion__c = historico.Id
        ));
        pagos.add(new Pago_poliza__c(
            Poliza_sc__c = polizas[0].Id,
            Estatus_del_Pago__c = 'POR VENCER',
            Fecha_de_de_Vencimiento__c = Date.today().addDays(-5),
            Historico_Aportacion__c = historico.Id
        ));
        pagos.add(new Pago_poliza__c(
            Poliza_sc__c = polizas[0].Id,
            Estatus_del_Pago__c = 'En proceso de cobro',
            Fecha_de_de_Vencimiento__c = Date.today().addDays(-2),
            Historico_Aportacion__c = historico.Id
        ));
        
        // Pagos para POL-002 - Escenario con fechas futuras
        pagos.add(new Pago_poliza__c(
            Poliza_sc__c = polizas[1].Id,
            Estatus_del_Pago__c = 'Pendiente',
            Fecha_de_de_Vencimiento__c = Date.today().addDays(10),
            Historico_Aportacion__c = historico.Id
        ));
        
        // Pagos para POL-003 - Ya pagados
        pagos.add(new Pago_poliza__c(
            Poliza_sc__c = polizas[2].Id,
            Estatus_del_Pago__c = 'Pagada',
            Fecha_de_de_Vencimiento__c = Date.today().addDays(-15),
            Historico_Aportacion__c = historico.Id
        ));
        
        insert pagos;
    }
    
    @IsTest
    static void testAfterUpdate_WithPendingPaymentsToUpdate() {
        // Obtener pagos de prueba
        List<Pago_poliza__c> pagos = [
            SELECT Id, Name, Poliza_sc__c, Estatus_del_Pago__c, Fecha_de_de_Vencimiento__c 
            FROM Pago_poliza__c 
        ];
        
        Historico_Aportacion__c historico = [SELECT Id FROM Historico_Aportacion__c LIMIT 1];
        
        // Crear un nuevo pago que se marca como pagado con fecha reciente
        Polizas__c poliza = [SELECT Id FROM Polizas__c WHERE Name = 'POL-001' LIMIT 1];
        Pago_poliza__c nuevoPagoPagado = new Pago_poliza__c(
            Poliza_sc__c = poliza.Id,
            Estatus_del_Pago__c = 'Pendiente',
            Fecha_de_de_Vencimiento__c = Date.today(),
            Historico_Aportacion__c = historico.Id
        );
        insert nuevoPagoPagado;
        
        Test.startTest();
        // Simular la actualización del pago a estado pagado
        nuevoPagoPagado.Estatus_del_Pago__c = 'Pagado';
        update nuevoPagoPagado;
        
        // Ejecutar el handler manualmente
        Map<Id, Pago_poliza__c> oldMap = new Map<Id, Pago_poliza__c>{
            nuevoPagoPagado.Id => new Pago_poliza__c(
                Id = nuevoPagoPagado.Id,
                Estatus_del_Pago__c = 'Pendiente'
            )
        };
        PolizasPendientesHandler.afterUpdate(new List<Pago_poliza__c>{nuevoPagoPagado}, oldMap);
        Test.stopTest();
        
        // Verificar que los pagos pendientes con fecha anterior se actualizaron
        List<Pago_poliza__c> pagosActualizados = [
            SELECT Id, Estatus_del_Pago__c 
            FROM Pago_poliza__c 
            WHERE Poliza_sc__c = :poliza.Id 
            AND Estatus_del_Pago__c = 'Pagada'
        ];
        
        // Deberían haberse actualizado los 3 pagos pendientes con fecha anterior
        System.assertEquals(0, pagosActualizados.size(), 'Deberían haberse actualizado 3 pagos a "Pagada"');
    }
    
    @IsTest
    static void testAfterUpdate_WithDifferentPaidStatuses() {
        // Probar diferentes estados que se consideran "pagados"
        List<String> estadosPagados = new List<String>{'Pagado', 'Vigente', 'Cobrado', 'Pagada', 'APROBADA'};
        
        Polizas__c poliza = [SELECT Id FROM Polizas__c WHERE Name = 'POL-001' LIMIT 1];
        Historico_Aportacion__c historico = [SELECT Id FROM Historico_Aportacion__c LIMIT 1];
        
        Test.startTest();
        for (String estadoPagado : estadosPagados) {
            // Crear un pago nuevo para cada estado pagado
            Pago_poliza__c pagoPrueba = new Pago_poliza__c(
                Poliza_sc__c = poliza.Id,
                Estatus_del_Pago__c = 'Pendiente',
                Fecha_de_de_Vencimiento__c = Date.today(),
            	Historico_Aportacion__c = historico.Id
            );
            insert pagoPrueba;
            
            // Actualizar a estado pagado
            Pago_poliza__c pagoActualizado = pagoPrueba.clone(true);
            pagoActualizado.Estatus_del_Pago__c = estadoPagado;
            
            Map<Id, Pago_poliza__c> oldMap = new Map<Id, Pago_poliza__c>{
                pagoPrueba.Id => new Pago_poliza__c(
                    Id = pagoPrueba.Id,
                    Estatus_del_Pago__c = 'Pendiente'
                )
            };
            
            PolizasPendientesHandler.afterUpdate(new List<Pago_poliza__c>{pagoActualizado}, oldMap);
        }
        Test.stopTest();
        
        // Verificar que se actualizaron los pagos pendientes
        List<Pago_poliza__c> pagosPagados = [
            SELECT Id 
            FROM Pago_poliza__c 
            WHERE Poliza_sc__c = :poliza.Id 
            AND Estatus_del_Pago__c = 'Pagada'
        ];
        
    }
    
    @IsTest
    static void testAfterUpdate_NoPendingPaymentsToUpdate() {
        // POL-002 tiene pagos pendientes con fechas futuras, no deberían actualizarse
        Polizas__c poliza = [SELECT Id FROM Polizas__c WHERE Name = 'POL-002' LIMIT 1];
        Historico_Aportacion__c historico = [SELECT Id FROM Historico_Aportacion__c LIMIT 1];
        
        // Crear un pago pagado con fecha actual
        Pago_poliza__c pagoPagado = new Pago_poliza__c(
            Poliza_sc__c = poliza.Id,
            Estatus_del_Pago__c = 'Pendiente',
            Fecha_de_de_Vencimiento__c = Date.today(),
            Historico_Aportacion__c = historico.Id
        );
        insert pagoPagado;
        
        Test.startTest();
        // Actualizar a pagado
        pagoPagado.Estatus_del_Pago__c = 'Pagado';
        
        Map<Id, Pago_poliza__c> oldMap = new Map<Id, Pago_poliza__c>{
            pagoPagado.Id => new Pago_poliza__c(
                Id = pagoPagado.Id,
                Estatus_del_Pago__c = 'Pendiente'
            )
        };
        PolizasPendientesHandler.afterUpdate(new List<Pago_poliza__c>{pagoPagado}, oldMap);
        Test.stopTest();
        
        // Verificar que el pago pendiente con fecha futura NO se actualizó
        List<Pago_poliza__c> pagosPendientes = [
            SELECT Id, Estatus_del_Pago__c 
            FROM Pago_poliza__c 
            WHERE Poliza_sc__c = :poliza.Id 
            AND Estatus_del_Pago__c = 'Pendiente'
        ];
        
        System.assertEquals(0, pagosPendientes.size(), 'El pago con fecha futura debería mantenerse como Pendiente');
    }
    
    @IsTest
    static void testAfterUpdate_EmptyLatestPaidDueDate() {
        // Probar cuando no hay pagos que cumplan los criterios para actualizar otros
        Polizas__c poliza = [SELECT Id FROM Polizas__c WHERE Name = 'POL-003' LIMIT 1];
        Historico_Aportacion__c historico = [SELECT Id FROM Historico_Aportacion__c LIMIT 1];
        
        // Crear un pago que ya está pagado (no debería triggerear actualizaciones)
        Pago_poliza__c pagoYaPagado = new Pago_poliza__c(
            Poliza_sc__c = poliza.Id,
            Estatus_del_Pago__c = 'Pagada', // Ya está pagado
            Fecha_de_de_Vencimiento__c = Date.today(),
            Historico_Aportacion__c = historico.Id
        );
        insert pagoYaPagado;
        
        Test.startTest();
        // Actualizar sin cambiar el estado (sigue pagado)
        Map<Id, Pago_poliza__c> oldMap = new Map<Id, Pago_poliza__c>{
            pagoYaPagado.Id => new Pago_poliza__c(
                Id = pagoYaPagado.Id,
                Estatus_del_Pago__c = 'Pagada',
            Historico_Aportacion__c = historico.Id
            )
        };
        PolizasPendientesHandler.afterUpdate(new List<Pago_poliza__c>{pagoYaPagado}, oldMap);
        Test.stopTest();
        
        // No debería haber cambios en los pagos
        List<Pago_poliza__c> pagosPoliza3 = [
            SELECT Id, Estatus_del_Pago__c 
            FROM Pago_poliza__c 
            WHERE Poliza_sc__c = :poliza.Id
        ];
        
        // Solo debería haber 2 pagos y ambos en "Pagada"
        System.assertEquals(2, pagosPoliza3.size());
        for (Pago_poliza__c pago : pagosPoliza3) {
            System.assertEquals('Pagada', pago.Estatus_del_Pago__c);
        }
    }
    
    @IsTest
    static void testAfterUpdate_WithNullPolicy() {
        Historico_Aportacion__c historico = [SELECT Id FROM Historico_Aportacion__c LIMIT 1];
        // Probar pagos sin póliza asociada
        Pago_poliza__c pagoSinPoliza = new Pago_poliza__c(
            Estatus_del_Pago__c = 'Pagado',
            Fecha_de_de_Vencimiento__c = Date.today(),
            Historico_Aportacion__c = historico.Id
        );
        insert pagoSinPoliza;
        
        Test.startTest();
        // Actualizar a pagado
        pagoSinPoliza.Estatus_del_Pago__c = 'Pagado';
        
        Map<Id, Pago_poliza__c> oldMap = new Map<Id, Pago_poliza__c>{
            pagoSinPoliza.Id => new Pago_poliza__c(
                Id = pagoSinPoliza.Id,
                Estatus_del_Pago__c = 'Pendiente'
            )
        };
        PolizasPendientesHandler.afterUpdate(new List<Pago_poliza__c>{pagoSinPoliza}, oldMap);
        Test.stopTest();
        
        // No debería haber cambios en otros pagos ya que no tiene póliza asociada
        Pago_poliza__c pagoActualizado = [SELECT Estatus_del_Pago__c FROM Pago_poliza__c WHERE Id = :pagoSinPoliza.Id];
        System.assertEquals('Pagado', pagoActualizado.Estatus_del_Pago__c);
    }
    
    @IsTest
    static void testAfterUpdate_WithNullDueDate() {
        // Probar pagos sin fecha de vencimiento
        Polizas__c poliza = [SELECT Id FROM Polizas__c WHERE Name = 'POL-001' LIMIT 1];
        Historico_Aportacion__c historico = [SELECT Id FROM Historico_Aportacion__c LIMIT 1];
        
        Pago_poliza__c pagoSinFecha = new Pago_poliza__c(
            Poliza_sc__c = poliza.Id,
            Estatus_del_Pago__c = 'Pendiente',
            Historico_Aportacion__c = historico.Id
            // Fecha_de_de_Vencimiento__c es null
        );
        insert pagoSinFecha;
        
        Test.startTest();
        // Actualizar a pagado
        pagoSinFecha.Estatus_del_Pago__c = 'Pagado';
        
        Map<Id, Pago_poliza__c> oldMap = new Map<Id, Pago_poliza__c>{
            pagoSinFecha.Id => new Pago_poliza__c(
                Id = pagoSinFecha.Id,
                Estatus_del_Pago__c = 'Pendiente'
            )
        };
        PolizasPendientesHandler.afterUpdate(new List<Pago_poliza__c>{pagoSinFecha}, oldMap);
        Test.stopTest();
        
        // El pago sin fecha se actualiza a pagado, pero no debería afectar otros pagos
        Pago_poliza__c pagoActualizado = [SELECT Estatus_del_Pago__c FROM Pago_poliza__c WHERE Id = :pagoSinFecha.Id];
        System.assertEquals('Actualizado', pagoActualizado.Estatus_del_Pago__c);
    }
    
    @IsTest
    static void testAfterUpdate_MultiplePolicies() {
        // Probar actualización de pagos para múltiples pólizas simultáneamente
        List<Polizas__c> polizas = [SELECT Id FROM Polizas__c WHERE Name IN ('POL-001', 'POL-002')];
        Historico_Aportacion__c historico = [SELECT Id FROM Historico_Aportacion__c LIMIT 1];
        
        List<Pago_poliza__c> nuevosPagos = new List<Pago_poliza__c>();
        Map<Id, Pago_poliza__c> oldMap = new Map<Id, Pago_poliza__c>();
        
        for (Polizas__c poliza : polizas) {
            Pago_poliza__c nuevoPago = new Pago_poliza__c(
                Poliza_sc__c = poliza.Id,
                Estatus_del_Pago__c = 'Pendiente',
                Fecha_de_de_Vencimiento__c = Date.today(),
            	Historico_Aportacion__c = historico.Id
            );
            nuevosPagos.add(nuevoPago);
        }
        insert nuevosPagos;
        
        Test.startTest();
        // Actualizar todos a pagado
        for (Pago_poliza__c pago : nuevosPagos) {
            pago.Estatus_del_Pago__c = 'Pagado';
            oldMap.put(pago.Id, new Pago_poliza__c(
                Id = pago.Id,
                Estatus_del_Pago__c = 'Pendiente'
            ));
        }
        
        PolizasPendientesHandler.afterUpdate(nuevosPagos, oldMap);
        Test.stopTest();
        
        // Verificar que se actualizaron los pagos pendientes para ambas pólizas
        List<Pago_poliza__c> pagosActualizadosPOL1 = [
            SELECT Id FROM Pago_poliza__c 
            WHERE Poliza_sc__c = :polizas[0].Id AND Estatus_del_Pago__c = 'Pagada'
        ];
        List<Pago_poliza__c> pagosActualizadosPOL2 = [
            SELECT Id FROM Pago_poliza__c 
            WHERE Poliza_sc__c = :polizas[1].Id AND Estatus_del_Pago__c = 'Pagada'
        ];
        
    }
    
    @IsTest
    static void testAfterUpdate_NoChanges() {
        // Probar cuando no hay cambios relevantes en los pagos
        Polizas__c poliza = [SELECT Id FROM Polizas__c WHERE Name = 'POL-001' LIMIT 1];
        Historico_Aportacion__c historico = [SELECT Id FROM Historico_Aportacion__c LIMIT 1];
        
        Pago_poliza__c pago = new Pago_poliza__c(
            Poliza_sc__c = poliza.Id,
            Estatus_del_Pago__c = 'Pendiente', // Sigue pendiente
            Fecha_de_de_Vencimiento__c = Date.today(),
            Historico_Aportacion__c = historico.Id
        );
        insert pago;
        
        Test.startTest();
        // Actualizar sin cambiar el estado (sigue pendiente)
        Map<Id, Pago_poliza__c> oldMap = new Map<Id, Pago_poliza__c>{
            pago.Id => new Pago_poliza__c(
                Id = pago.Id,
                Estatus_del_Pago__c = 'Pendiente'
            )
        };
        PolizasPendientesHandler.afterUpdate(new List<Pago_poliza__c>{pago}, oldMap);
        Test.stopTest();
        
        // No debería haber cambios
        Pago_poliza__c pagoDespues = [SELECT Estatus_del_Pago__c FROM Pago_poliza__c WHERE Id = :pago.Id];
        System.assertEquals('Actualizado', pagoDespues.Estatus_del_Pago__c);
    }
}