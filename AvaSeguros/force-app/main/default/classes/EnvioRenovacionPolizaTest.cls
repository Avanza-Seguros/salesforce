@isTest
private class EnvioRenovacionPolizaTest {
    
    // Método para preparar datos de prueba
    static Polizas__c setupTestData() {
        Account acc = new Account();
        acc.Name = 'Luxoft Mexico S.A. De C.V.';
        insert acc;
       
       
        Polizas__c testPoliza = new Polizas__c(
            Asegurado__c = acc.id, // Asegúrate de que este ID sea válido en tu contexto de pruebas
            Correo__c = 'test@example.com',
            Vigencia_desde__c = Date.today().addYears(-1) // Ajusta la fecha de inicio de vigencia a un año antes
        );
        insert testPoliza;
        return testPoliza;
    }

    // Test para verificar el funcionamiento con datos completos
    @isTest static void testEnvioRenovacionConDatosCompletos() {
        Polizas__c testPoliza = setupTestData();

        Test.startTest();
        EnvioRenovacionPoliza.EnvioRenovacion(testPoliza);
        Test.stopTest();

        // Añade aserciones aquí para verificar el resultado esperado
    }

    // Test para verificar el manejo correcto cuando faltan datos necesarios
    @isTest static void testEnvioRenovacionSinDatosNecesarios() {
        Polizas__c testPoliza = new Polizas__c(); // Sin configurar datos necesarios
        insert testPoliza;

        Test.startTest();
        EnvioRenovacionPoliza.EnvioRenovacion(testPoliza);
        Test.stopTest();

        // Añade aserciones aquí para verificar el manejo de errores o la ausencia de acciones
    }
}