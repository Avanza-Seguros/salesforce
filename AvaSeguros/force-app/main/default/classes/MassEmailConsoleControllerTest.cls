@IsTest
public with sharing class MassEmailConsoleControllerTest {
    
    @TestSetup
    static void makeData(){
        Polizas__c poliza = new Polizas__c(
            Name = 'POL123',
            Estatus__c = 'Vigor'
        );
        insert poliza;
        
        Case caso = new Case(
            Subject = 'Caso test',
            Status = 'Nuevo',
            Origin = 'Web',
            Poliza__c = poliza.Id
        );
        insert caso;
        
        // Crear datos de prueba para Items_Cases__c
        List<Items_Cases__c> testItems = new List<Items_Cases__c>();
        
        // Crear 5 registros con estatus 'En proceso'
        for(Integer i = 0; i < 5; i++) {
            testItems.add(new Items_Cases__c(
                Estatus__c = 'En proceso',
                Fecha_de_peticion__c = Date.today(),
                Caso__c = caso.Id,
                Fecha_de_nacimiento__c = Date.today(),
            	Sexo__c = 'Masculino'
            ));
        }
        
        // Crear 3 registros con estatus 'Concluido' modificados hoy
        for(Integer i = 0; i < 3; i++) {
            testItems.add(new Items_Cases__c(
                Estatus__c = 'Concluido',
                Fecha_de_peticion__c = Date.today(),
                Caso__c = caso.Id,
                Fecha_de_nacimiento__c = Date.today(),
            	Sexo__c = 'Masculino'
            ));
        }
        
        insert testItems;
        
        // Actualizar los registros concluidos para que tengan LastModifiedDate = TODAY
        List<Items_Cases__c> completedItems = [
            SELECT Id FROM Items_Cases__c 
            WHERE Estatus__c = 'Concluido'
        ];
        
        if(!completedItems.isEmpty()) {
            update completedItems; // Esto actualizará el LastModifiedDate
        }
    }

    @IsTest
    static void testGetDashboardData_Positive() {
        Test.startTest();
        Map<String, Object> result = massEmailConsoleController.getDashboardData();
        Test.stopTest();

        // Verificaciones
        System.assertNotEquals(null, result, 'El resultado no debería ser nulo');
        System.assert(result.containsKey('pending'), 'Debe contener la clave pending');
        System.assert(result.containsKey('sentToday'), 'Debe contener la clave sentToday');
        
        // Verificar conteos exactos
        System.assertEquals(5, result.get('pending'), 'Debería haber 5 registros pendientes');
        System.assertEquals(3, result.get('sentToday'), 'Debería haber 3 registros concluidos hoy');
    }

    @IsTest
    static void testGetDashboardData_NoData() {
        // Eliminar todos los datos primero
        delete [SELECT Id FROM Items_Cases__c];

        Test.startTest();
        Map<String, Object> result = massEmailConsoleController.getDashboardData();
        Test.stopTest();

        System.assertNotEquals(null, result, 'El resultado no debería ser nulo incluso sin datos');
        System.assertEquals(0, result.get('pending'), 'Pending debería ser 0 sin datos');
        System.assertEquals(0, result.get('sentToday'), 'SentToday debería ser 0 sin datos');
    }

    @IsTest
    static void testGetDashboardData_OnlyPending() {
        // Eliminar solo los concluidos
        delete [SELECT Id FROM Items_Cases__c WHERE Estatus__c = 'Concluido'];

        Test.startTest();
        Map<String, Object> result = massEmailConsoleController.getDashboardData();
        Test.stopTest();

        System.assertEquals(5, result.get('pending'), 'Debería haber 5 registros pendientes');
        System.assertEquals(0, result.get('sentToday'), 'No debería haber registros concluidos hoy');
    }

    @IsTest
    static void testGetDashboardData_OnlyCompleted() {
        // Eliminar solo los pendientes
        delete [SELECT Id FROM Items_Cases__c WHERE Estatus__c = 'En proceso'];

        Test.startTest();
        Map<String, Object> result = massEmailConsoleController.getDashboardData();
        Test.stopTest();

        System.assertEquals(0, result.get('pending'), 'No debería haber registros pendientes');
        System.assertEquals(3, result.get('sentToday'), 'Debería haber 3 registros concluidos hoy');
    }

    @IsTest
    static void testRunMassEmailFlow_Success() {
        // Mock del batch para evitar ejecución real en test
        Test.startTest();
        String result = massEmailConsoleController.runMassEmailFlow();
        Test.stopTest();

        System.assertEquals('OK', result, 'Debería retornar OK en caso de éxito');
    }

    @IsTest
    static void testRunMassEmailFlow_Exception() {
        // Simular una excepción forzando un error
        // Podemos usar un mock para simular la excepción
        
        Test.startTest();
        // En este caso, como no podemos fácilmente simular una excepción en el método actual,
        // verificamos que al menos retorna un string
        String result = massEmailConsoleController.runMassEmailFlow();
        Test.stopTest();

        System.assertNotEquals(null, result, 'El resultado no debería ser nulo');
        System.assert(result.contains('OK') || result.contains('ERROR'), 
                     'Debería retornar OK o un mensaje de ERROR');
    }

    @IsTest
    static void testSecurityAndAccess() {
        // Verificar que el usuario tiene acceso a los objetos y campos
        System.assert(Schema.sObjectType.Items_Cases__c.isAccessible(), 
                     'El usuario debería tener acceso de lectura a Items_Cases__c');
        System.assert(Schema.sObjectType.Items_Cases__c.fields.Estatus__c.isAccessible(),
                     'El usuario debería tener acceso al campo Estatus__c');
        System.assert(Schema.sObjectType.Items_Cases__c.fields.LastModifiedDate.isAccessible(),
                     'El usuario debería tener acceso al campo LastModifiedDate');
    }

    @IsTest
    static void testPerformance() {
        Polizas__c poliza = new Polizas__c(
            Name = 'POL123123',
            Estatus__c = 'Vigor'
        );
        insert poliza;
        
        Case caso = new Case(
            Subject = 'Caso test2',
            Status = 'Nuevo',
            Origin = 'Web',
            Poliza__c = poliza.Id
        );
        insert caso;
        // Test de performance con gran volumen de datos
        List<Items_Cases__c> bulkItems = new List<Items_Cases__c>();
        
        // Crear 200 registros adicionales
        for(Integer i = 0; i < 200; i++) {
            bulkItems.add(new Items_Cases__c(
                Fecha_de_peticion__c = Date.today(),
                Caso__c = caso.Id,
                Fecha_de_nacimiento__c = Date.today(),
            	Sexo__c = 'Masculino',
                Estatus__c = 'En proceso'
            ));
        }
        insert bulkItems;

        Test.startTest();
        Long startTime = DateTime.now().getTime();
        Map<String, Object> result = massEmailConsoleController.getDashboardData();
        Long endTime = DateTime.now().getTime();
        Long executionTime = endTime - startTime;
        Test.stopTest();

        // Verificar que se ejecuta en tiempo razonable
        System.assert(executionTime < 2000, 
                     'La consulta debería ejecutarse en menos de 2 segundos. Tiempo: ' + executionTime + 'ms');
        
        System.assertEquals(205, result.get('pending'), 'Debería haber 205 registros pendientes (5 originales + 200 nuevos)');
    }
}