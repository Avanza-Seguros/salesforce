/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 02-28-2025
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@isTest
public class TestPendientesDePago {
    
    @testSetup
    static void setupData() {
        Date fechaPendiente = Date.today().addDays(1); // 1 día después de hoy

        // 🔹 Insertamos un pago PENDIENTE
        Pago_poliza__c pagoPendiente = new Pago_poliza__c(
            Estatus_del_Pago__c = 'Pendiente',
            Poliza_sc__c = '1234', // Campo usado en la fórmula
            Fecha_de_de_Vencimiento__c = fechaPendiente // Campo usado en la fórmula
        );
        insert pagoPendiente;

        System.debug('✅ Pago Pendiente insertado - ID: ' + pagoPendiente.Id);
    }

    @isTest
    static void testActualizarPagoPendiente() {
        // 🔹 PASO 1: Verificamos que el pago pendiente existe antes del trigger
        Date fechaPendiente = Date.today().addDays(1); 
        
        Pago_poliza__c pagoAntes = [SELECT Id, Estatus_del_Pago__c, Poliza_sc__c, Fecha_de_de_Vencimiento__c
                                    FROM Pago_poliza__c 
                                    WHERE Poliza_sc__c = '1234' 
                                    AND Fecha_de_de_Vencimiento__c = :fechaPendiente
                                    AND Estatus_del_Pago__c = 'Pendiente'
                                    LIMIT 1];

        System.assertNotEquals(null, pagoAntes, '❌ ERROR: No se encontró el Pago Pendiente');
        System.debug('🔎 Pago Pendiente antes de la actualización - ID: ' + pagoAntes.Id);

        Test.startTest();
        
        // 🔹 PASO 2: Insertamos un pago PAGADO (Cobrado) para activar el Trigger `PolizasPendientes`
        Pago_poliza__c pagoCobrado = new Pago_poliza__c(
            Estatus_del_Pago__c = 'Cobrado', // Se considera pagado
            Poliza_sc__c = '1234', // Campo base de la fórmula
            Fecha_de_de_Vencimiento__c = fechaPendiente // Campo base de la fórmula
        );
        insert pagoCobrado; // 🔥 Aquí se activa el Trigger `PolizasPendientes`

        System.debug('✅ Pago Cobrado insertado - ID: ' + pagoCobrado.Id);

        Test.stopTest();
        
        // 🔹 PASO 3: Verificamos si el pago Pendiente se actualizó
        Pago_poliza__c pagoDespues = [SELECT Id, Estatus_del_Pago__c, Poliza_sc__c, Fecha_de_de_Vencimiento__c
                                      FROM Pago_poliza__c 
                                      WHERE Poliza_sc__c = '1234' 
                                      AND Fecha_de_de_Vencimiento__c = :fechaPendiente
                                      LIMIT 1];

        System.debug('🔎 Pago Pendiente después del Trigger - ID: ' + pagoDespues.Id + 
                     ', Estatus: ' + pagoDespues.Estatus_del_Pago__c);

        // 🔹 PASO 4: Validamos que el estatus haya cambiado a "Actualizado"
        System.assertEquals('Actualizado', pagoDespues.Estatus_del_Pago__c, 
            '❌ ERROR: El Trigger PolizasPendientes NO actualizó el pago Pendiente');
    }
}