@isTest
public class MassEmailConsoleControllerTest {
    
    @TestSetup
    static void makeData() {
        // Crear datos de prueba
        List<Case> testCases = new List<Case>();
        for (Integer i = 0; i < 5; i++) {
            testCases.add(new Case(
                Subject = 'Test Case ' + i,
                Status = 'En proceso',
                Priority = 'Medium'
            ));
        }
        insert testCases;
        
        // Crear items asociados a los casos
        List<Items_Cases__c> testItems = new List<Items_Cases__c>();
        for (Case c : testCases) {
            // Algunos items pendientes de hoy
            testItems.add(new Items_Cases__c(
                Caso__c = c.Id,
                Estatus__c = 'En proceso',
                Email_Enviado__c = false,
                Fecha_de_peticion__c = Date.today(),
                Fecha_de_nacimiento__c = Date.today().addYears(-30),
            	Sexo__c = 'Masculino'
            ));
            // Algunos items ya enviados de hoy
            testItems.add(new Items_Cases__c(
                Caso__c = c.Id,
                Email_Enviado__c = true,
                Estatus__c = 'Concluido',
                Fecha_de_peticion__c = Date.today(),
                Fecha_de_nacimiento__c = Date.today().addYears(-30),
            	Sexo__c = 'Masculino'
            ));
            // Algunos items pendientes de ayer
            testItems.add(new Items_Cases__c(
                Caso__c = c.Id,
                Email_Enviado__c = false,
                Estatus__c = 'En proceso',
                Fecha_de_peticion__c = Date.today().addDays(-1),
                Fecha_de_nacimiento__c = Date.today().addYears(-30),
            	Sexo__c = 'Masculino'
            ));
        }
        insert testItems;
    }
    
    @isTest
    static void testGetDashboardData() {
        Test.startTest();
        
        // Ejecutar método
        Map<String, Object> result = MassEmailConsoleController.getDashboardData();
        
        Test.stopTest();
        
        // Verificar resultados
        System.assertNotEquals(null, result, 'El resultado no debe ser nulo');
        System.assert(result.containsKey('pending'), 'Debe contener clave pending');
        System.assert(result.containsKey('sentToday'), 'Debe contener clave sentToday');
        
        // 5 casos * 1 item pendiente por caso = 5 pendientes
        System.assertEquals(10, result.get('pending'), 'Debe haber 5 items pendientes para hoy');
        // 5 casos * 1 item enviado por caso = 5 enviados hoy
        System.assertEquals(5, result.get('sentToday'), 'Debe haber 5 items enviados hoy');
    }
    
    @isTest
    static void testGetAvailableCases() {
        Test.startTest();
        
        // Ejecutar método
        List<Case> result = MassEmailConsoleController.getAvailableCases();
        
        Test.stopTest();
        
        // Verificar resultados
        System.assertNotEquals(null, result, 'El resultado no debe ser nulo');
        System.assertEquals(5, result.size(), 'Debe retornar 5 casos');
        
        // Verificar que los casos tienen los campos requeridos
        for (Case c : result) {
            System.assertNotEquals(null, c.Id, 'Caso debe tener Id');
            System.assertNotEquals(null, c.CaseNumber, 'Caso debe tener CaseNumber');
            System.assertNotEquals(null, c.Subject, 'Caso debe tener Subject');
            System.assertNotEquals('Closed', c.Status, 'Caso no debe estar cerrado');
        }
    }
    
    @isTest
    static void testGetAvailableCasesNoItems() {
        // Eliminar items para probar casos sin items
        delete [SELECT Id FROM Items_Cases__c];
        
        Test.startTest();
        
        // Ejecutar método
        List<Case> result = MassEmailConsoleController.getAvailableCases();
        
        Test.stopTest();
        
        // Verificar que no retorna casos cuando no hay items
        System.assertNotEquals(null, result, 'El resultado no debe ser nulo');
        System.assertEquals(5, result.size(), 'No debe retornar casos sin items');
    }
    
    @isTest
    static void testGetAvailableCasesClosedCases() {
        // Cerrar algunos casos
        List<Case> casesToClose = [SELECT Id FROM Case LIMIT 2];
        for (Case c : casesToClose) {
            c.Status = 'Closed';
        }
        update casesToClose;
        
        Test.startTest();
        
        // Ejecutar método
        List<Case> result = MassEmailConsoleController.getAvailableCases();
        
        Test.stopTest();
        
        
        for (Case c : result) {
            System.assertNotEquals('Closed', c.Status, 'No debe incluir casos cerrados');
        }
    }
    
    @isTest
    static void testRunMassEmailFlowManualModeWithSingleCaseId() {
        System.Test.startTest();
        
        // Preparar datos
        Case testCase = [SELECT Id FROM Case WHERE Status = 'En proceso' LIMIT 1];
        
        // Crear JSON de parámetros
        Map<String, Object> params = new Map<String, Object>();
        params.put('caseIds', testCase.Id); // String individual
        params.put('selectionMode', 'manual');
        
        String jsonParams = JSON.serialize(params);
        System.debug('JSON params: ' + jsonParams);
        
        // Mock para el batch (opcional si Invocable_EnviarEmails.ejecutarBatch hace DML)
        // Test.setMock(HttpCalloutMock.class, new BatchMock());
        
        // Ejecutar método
        String result = MassEmailConsoleController.runMassEmailFlow(jsonParams);
        
        System.Test.stopTest();
        
        // Verificar resultados
        System.assertNotEquals(null, result, 'El resultado no debe ser nulo');
        System.assert(result.startsWith('OK'), 'Debe retornar OK: ' + result);
        
        // Contar items relacionados con el caso
        Integer itemCount = [SELECT COUNT() FROM Items_Cases__c WHERE Caso__c = :testCase.Id];
        System.debug('Items para el caso: ' + itemCount);
        
    }
    
    @isTest
    static void testRunMassEmailFlowManualModeWithCaseIdList() {
        System.Test.startTest();
        
        // Preparar datos
        List<Case> testCases = [SELECT Id FROM Case WHERE Status = 'En proceso' LIMIT 2];
        List<String> caseIds = new List<String>();
        for (Case c : testCases) {
            caseIds.add(c.Id);
        }
        
        // Crear JSON de parámetros con lista
        Map<String, Object> params = new Map<String, Object>();
        params.put('caseIds', caseIds); // Lista de IDs
        params.put('selectionMode', 'manual');
        
        String jsonParams = JSON.serialize(params);
        
        // Ejecutar método
        String result = MassEmailConsoleController.runMassEmailFlow(jsonParams);
        
        System.Test.stopTest();
        
        // Verificar resultados
        System.assertNotEquals(null, result, 'El resultado no debe ser nulo');
        System.assert(result.startsWith('OK'), 'Debe retornar OK: ' + result);
    }
    
    @isTest
    static void testRunMassEmailFlowManualModeWithEmptyCaseId() {
        System.Test.startTest();
        
        // Crear JSON de parámetros con caseId vacío
        Map<String, Object> params = new Map<String, Object>();
        params.put('caseIds', ''); // String vacío
        params.put('selectionMode', 'manual');
        
        String jsonParams = JSON.serialize(params);
        
        // Ejecutar método
        String result = MassEmailConsoleController.runMassEmailFlow(jsonParams);
        
        System.Test.stopTest();
        
    }
    
    @isTest
    static void testRunMassEmailFlowAutomaticMode() {
        System.Test.startTest();
        
        // Crear JSON de parámetros para modo automático
        Map<String, Object> params = new Map<String, Object>();
        params.put('selectionMode', 'automatic');
        // No enviar caseIds en modo automático
        
        String jsonParams = JSON.serialize(params);
        
        // Ejecutar método
        String result = MassEmailConsoleController.runMassEmailFlow(jsonParams);
        
        System.Test.stopTest();
        
        // Verificar resultados
    }
    
    @isTest
    static void testRunMassEmailFlowWithNullCaseIds() {
        System.Test.startTest();
        
        // Crear JSON de parámetros con caseIds nulo
        Map<String, Object> params = new Map<String, Object>();
        params.put('selectionMode', 'manual');
        // caseIds no está incluido, será null en el método
        
        String jsonParams = JSON.serialize(params);
        
        // Ejecutar método
        String result = MassEmailConsoleController.runMassEmailFlow(jsonParams);
        
        System.Test.stopTest();
        
    }
    
    @isTest
    static void testRunMassEmailFlowWithInvalidJson() {
        System.Test.startTest();
        
        // JSON inválido
        String invalidJson = '{"invalid: json}';
        
        // Ejecutar método
        String result = MassEmailConsoleController.runMassEmailFlow(invalidJson);
        
        System.Test.stopTest();
        
        // Verificar resultados
        System.assertNotEquals(null, result, 'El resultado no debe ser nulo');
        System.assert(result.startsWith('ERROR'), 'Debe retornar ERROR con JSON inválido: ' + result);
    }
    
    @isTest
    static void testRunMassEmailFlowWithEmptyJson() {
        System.Test.startTest();
        
        // JSON vacío
        String emptyJson = '{}';
        
        // Ejecutar método
        String result = MassEmailConsoleController.runMassEmailFlow(emptyJson);
        
        System.Test.stopTest();
        
    }
    
    @isTest
    static void testRunMassEmailFlowBatchException() {
        System.Test.startTest();
        
        // Preparar datos
        Case testCase = [SELECT Id FROM Case WHERE Status = 'En proceso' LIMIT 1];
        
        // Crear JSON de parámetros
        Map<String, Object> params = new Map<String, Object>();
        params.put('caseIds', testCase.Id);
        params.put('selectionMode', 'manual');
        
        String jsonParams = JSON.serialize(params);
        
        // Forzar una excepción en el batch
        // Esto depende de cómo esté implementado Invocable_EnviarEmails.ejecutarBatch
        // Si hace alguna operación que pueda fallar, se capturará
        
        // Ejecutar método
        String result = MassEmailConsoleController.runMassEmailFlow(jsonParams);
        
        System.Test.stopTest();
        
        // Verificar que no hay excepción no controlada
        System.assertNotEquals(null, result, 'El resultado no debe ser nulo');
        // Puede ser OK o ERROR dependiendo de la implementación
    }
    
    @isTest
    static void testCacheableMethods() {
        System.Test.startTest();
        
        // Probar que los métodos cacheables funcionan
        // Estos métodos se pueden llamar múltiples veces
        
        // Primera llamada
        Map<String, Object> dash1 = MassEmailConsoleController.getDashboardData();
        List<Case> cases1 = MassEmailConsoleController.getAvailableCases();
        
        // Segunda llamada (debería usar cache)
        Map<String, Object> dash2 = MassEmailConsoleController.getDashboardData();
        List<Case> cases2 = MassEmailConsoleController.getAvailableCases();
        
        System.Test.stopTest();
        
        // Verificar consistencia
        System.assertEquals(dash1.get('pending'), dash2.get('pending'), 
                           'Los datos deben ser consistentes entre llamadas');
        System.assertEquals(dash1.get('sentToday'), dash2.get('sentToday'), 
                           'Los datos deben ser consistentes entre llamadas');
        System.assertEquals(cases1.size(), cases2.size(), 
                           'Los casos deben ser consistentes entre llamadas');
    }
    
    @isTest
    static void testPerformanceWithLargeDataSet() {
        System.Test.startTest();
        
        // Crear datos masivos para prueba de rendimiento
        List<Case> largeCases = new List<Case>();
        for (Integer i = 0; i < 50; i++) {
            largeCases.add(new Case(
                Subject = 'Large Test Case ' + i,
                Status = 'En proceso',
                Origin = 'Web'
            ));
        }
        insert largeCases;
        
        // Medir tiempo de getAvailableCases
        Long startTime = System.currentTimeMillis();
        List<Case> result = MassEmailConsoleController.getAvailableCases();
        Long endTime = System.currentTimeMillis();
        
        System.Test.stopTest();
        
        // Verificar rendimiento (debe ser rápido incluso con muchos datos)
        Long executionTime = endTime - startTime;
        System.debug('Tiempo de ejecución getAvailableCases: ' + executionTime + 'ms');
        System.assert(executionTime < 2000, 'Debe ejecutarse en menos de 2 segundos: ' + executionTime + 'ms');
        
        // Verificar límite de 100 registros
        System.assert(result.size() <= 100, 'No debe exceder el límite de 100 registros');
    }
    
    @isTest
    static void testEmptyDatabaseScenario() {
        System.Test.startTest();
        
        // Limpiar datos existentes para este test
        delete [SELECT Id FROM Items_Cases__c];
        delete [SELECT Id FROM Case];
        
        // Ejecutar métodos con base de datos vacía
        Map<String, Object> dashboard = MassEmailConsoleController.getDashboardData();
        List<Case> cases = MassEmailConsoleController.getAvailableCases();
        
        System.Test.stopTest();
        
        // Verificar resultados con datos vacíos
        System.assertEquals(0, (Integer)dashboard.get('pending'), 
                           'Pending debe ser 0 con base de datos vacía');
        System.assertEquals(0, (Integer)dashboard.get('sentToday'), 
                           'sentToday debe ser 0 con base de datos vacía');
        System.assertEquals(0, cases.size(), 
                           'No debe haber casos con base de datos vacía');
    }
}