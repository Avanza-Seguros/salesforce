@isTest
private class PolizasPendientesTest {

    @testSetup
    static void makeData(){
        List<Pago_poliza__c> testPayments = new List<Pago_poliza__c>();

        // Scenario 1: Policy with multiple pending payments
        testPayments.add(new Pago_poliza__c(
            Poliza_sc__c = 'POL-001',
            Estatus_del_Pago__c = 'Pendiente',
            Fecha_de_de_Vencimiento__c = Date.newInstance(2024, 6, 1),
            Monto__c = 100
        ));
        testPayments.add(new Pago_poliza__c(
            Poliza_sc__c = 'POL-001',
            Estatus_del_Pago__c = 'Pendiente',
            Fecha_de_de_Vencimiento__c = Date.newInstance(2024, 7, 1),
            Monto__c = 100
        ));
        testPayments.add(new Pago_poliza__c(
            Poliza_sc__c = 'POL-001',
            Estatus_del_Pago__c = 'Pendiente',
            Fecha_de_de_Vencimiento__c = Date.newInstance(2024, 8, 1),
            Monto__c = 100
        ));

        // Scenario 2: A different policy to ensure it's not affected
        testPayments.add(new Pago_poliza__c(
            Poliza_sc__c = 'POL-002',
            Estatus_del_Pago__c = 'Pendiente',
            Fecha_de_de_Vencimiento__c = Date.newInstance(2024, 7, 1),
            Monto__c = 200
        ));
        
        insert testPayments;
    }

    @isTest
    static void testUpdatePastPendingPayments() {
        // Get the July payment for POL-001 to mark as paid
        Pago_poliza__c julyPayment = [
            SELECT Id, Estatus_del_Pago__c 
            FROM Pago_poliza__c 
            WHERE Poliza_sc__c = 'POL-001' AND Fecha_de_de_Vencimiento__c = :Date.newInstance(2024, 7, 1)
            LIMIT 1
        ];

        Test.startTest();
            julyPayment.Estatus_del_Pago__c = 'Pagada';
            update julyPayment;
        Test.stopTest();

        // Verification
        Pago_poliza__c junePayment = [SELECT Estatus_del_Pago__c FROM Pago_poliza__c WHERE Poliza_sc__c = 'POL-001' AND Fecha_de_de_Vencimiento__c = :Date.newInstance(2024, 6, 1)];
        Pago_poliza__c augustPayment = [SELECT Estatus_del_Pago__c FROM Pago_poliza__c WHERE Poliza_sc__c = 'POL-001' AND Fecha_de_de_Vencimiento__c = :Date.newInstance(2024, 8, 1)];
        Pago_poliza__c otherPolicyPayment = [SELECT Estatus_del_Pago__c FROM Pago_poliza__c WHERE Poliza_sc__c = 'POL-002'];
        
        // Assert: June payment should be updated because it's before the paid one.
        System.assertEquals('Pagada', junePayment.Estatus_del_Pago__c, 'Previous pending payment should be updated to Pagada.');

        // Assert: August payment should NOT be updated because it's in the future.
        System.assertEquals('Pendiente', augustPayment.Estatus_del_Pago__c, 'Future pending payment should not be changed.');
        
        // Assert: The payment for the other policy should not be affected.
        System.assertEquals('Pendiente', otherPolicyPayment.Estatus_del_Pago__c, 'Payment for another policy should not be changed.');
    }
    
    @isTest
    static void testNoStatusChange() {
        Pago_poliza__c paymentToUpdate = [SELECT Id, Estatus_del_Pago__c FROM Pago_poliza__c WHERE Poliza_sc__c = 'POL-001' LIMIT 1];
        
        Test.startTest();
            // This update should not trigger the logic because the status is not 'Pagada'
            paymentToUpdate.Monto__c = 150;
            update paymentToUpdate;
        Test.stopTest();

        List<Pago_poliza__c> results = [SELECT Id FROM Pago_poliza__c WHERE Estatus_del_Pago__c = 'Pagada'];
        
        // Assert: No records should have been updated to 'Pagada'.
        System.assertEquals(0, results.size(), 'No payments should be updated if the status does not change to a paid one.');
    }

    @isTest
    static void testInsertNewPaidPayment() {
        Test.startTest();
        // Insert a new payment that is already paid. This simulates receiving a historical payment record.
        Pago_poliza__c newPaidPayment = new Pago_poliza__c(
            Poliza_sc__c = 'POL-001',
            Estatus_del_Pago__c = 'Pagada',
            Fecha_de_de_Vencimiento__c = Date.newInstance(2024, 7, 15), // A date after July 1st
            Monto__c = 100
        );
        insert newPaidPayment;
        Test.stopTest();

        // Verification
        Pago_poliza__c junePayment = [SELECT Estatus_del_Pago__c FROM Pago_poliza__c WHERE Poliza_sc__c = 'POL-001' AND Fecha_de_de_Vencimiento__c = :Date.newInstance(2024, 6, 1)];
        Pago_poliza__c julyPayment = [SELECT Estatus_del_Pago__c FROM Pago_poliza__c WHERE Poliza_sc__c = 'POL-001' AND Fecha_de_de_Vencimiento__c = :Date.newInstance(2024, 7, 1)];
        
        // Assert: Both June and July payments should now be updated because their due dates are before the new paid payment.
        System.assertEquals('Pagada', junePayment.Estatus_del_Pago__c, 'June payment should be updated.');
        System.assertEquals('Pagada', julyPayment.Estatus_del_Pago__c, 'July payment should be updated.');
    }
}