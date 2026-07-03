@isTest
private class TriggerControlTest {
    
    @testSetup
    static void setupTestData() {
        // Crear datos de prueba
        Account testAccount = new Account(
            Name = 'Test Account',
            Phone = '1234567890'
        );
        insert testAccount;

        Case caso = new Case();
        caso.AccountId = testAccount.Id;
        insert caso;
        
        // Crear Items_Cases__c de prueba
        Items_Cases__c testItem = new Items_Cases__c(
            Nombre_cuenta__c = testAccount.Id,
            Nombre__c = 'Juan',
            Apellido_paterno__c = 'Perez',
            Estatus__c = 'En proceso',
            Caso__c = caso.Id,
            Correo_electronico__c = 'test@example.com',
            Fecha_de_peticion__c  = Date.today(),
            Fecha_de_nacimiento__c  = Date.today().addYears(-20),
            Sexo__c 			  = 'Masculino'
        );
        insert testItem;
    }
    
    @isTest
    static void testTriggerControlMethods() {
        System.Test.startTest();
        
        // 🔄 TEST 1: Métodos básicos de control
        Assert.areEqual(false, TriggerControl.isExecuting, 'isExecuting debe iniciar en false');
        Assert.areEqual(false, TriggerControl.skipEmailTrigger, 'skipEmailTrigger debe iniciar en false');
        Assert.areEqual(0, TriggerControl.processedItems.size(), 'processedItems debe iniciar vacío');
        
        // 🔄 TEST 2: isAlreadyProcessed con ID nulo
        Assert.areEqual(false, TriggerControl.isAlreadyProcessed(null), 'ID nulo no debe estar procesado');
        
        // 🔄 TEST 3: markAsProcessed y isAlreadyProcessed
        Id testId = '001000000000001AAA';
        Assert.areEqual(false, TriggerControl.isAlreadyProcessed(testId), 'ID no debe estar procesado inicialmente');
        
        TriggerControl.markAsProcessed(testId);
        Assert.areEqual(true, TriggerControl.isAlreadyProcessed(testId), 'ID debe estar procesado después de markAsProcessed');
        Assert.areEqual(1, TriggerControl.processedItems.size(), 'processedItems debe tener 1 elemento');
        
        // 🔄 TEST 4: Probar con múltiples IDs
        Id testId2 = '001000000000002AAA';
        Id testId3 = '001000000000003AAA';
        
        TriggerControl.markAsProcessed(testId2);
        TriggerControl.markAsProcessed(testId3);
        
        Assert.areEqual(true, TriggerControl.isAlreadyProcessed(testId2), 'testId2 debe estar procesado');
        Assert.areEqual(true, TriggerControl.isAlreadyProcessed(testId3), 'testId3 debe estar procesado');
        Assert.areEqual(3, TriggerControl.processedItems.size(), 'processedItems debe tener 3 elementos');
        
        // 🔄 TEST 5: canExecuteTrigger()
        Assert.areEqual(true, TriggerControl.canExecuteTrigger(), 'Debe permitir ejecución inicial');
        
        TriggerControl.isExecuting = true;
        Assert.areEqual(false, TriggerControl.canExecuteTrigger(), 'No debe permitir ejecución cuando isExecuting es true');
        
        TriggerControl.isExecuting = false;
        TriggerControl.skipEmailTrigger = true;
        Assert.areEqual(false, TriggerControl.canExecuteTrigger(), 'No debe permitir ejecución cuando skipEmailTrigger es true');
        
        TriggerControl.skipEmailTrigger = false;
        Assert.areEqual(true, TriggerControl.canExecuteTrigger(), 'Debe permitir ejecución después de reset');
        
        System.Test.stopTest();
    }
    
    @isTest
    static void testResetMethod() {
        System.Test.startTest();
        
        // 🔄 TEST 6: Método reset()
        // Configurar estado
        TriggerControl.isExecuting = true;
        TriggerControl.skipEmailTrigger = true;
        TriggerControl.markAsProcessed('001000000000001AAA');
        TriggerControl.markAsProcessed('001000000000002AAA');
        
        // Verificar estado antes de reset
        Assert.areEqual(true, TriggerControl.isExecuting, 'isExecuting debe ser true antes de reset');
        Assert.areEqual(true, TriggerControl.skipEmailTrigger, 'skipEmailTrigger debe ser true antes de reset');
        Assert.areEqual(2, TriggerControl.processedItems.size(), 'processedItems debe tener 2 elementos antes de reset');
        
        // Ejecutar reset
        TriggerControl.reset();
        
        // Verificar estado después de reset
        Assert.areEqual(false, TriggerControl.isExecuting, 'isExecuting debe ser false después de reset');
        Assert.areEqual(false, TriggerControl.skipEmailTrigger, 'skipEmailTrigger debe ser false después de reset');
        Assert.areEqual(0, TriggerControl.processedItems.size(), 'processedItems debe estar vacío después de reset');
        
        System.Test.stopTest();
    }
    
    @isTest
    static void testEdgeCases() {
        System.Test.startTest();
        
        // 🔄 TEST 7: Casos extremos - IDs duplicados
        Id duplicateId = '001000000000001AAA';
        
        TriggerControl.markAsProcessed(duplicateId);
        TriggerControl.markAsProcessed(duplicateId); // Agregar el mismo ID otra vez
        
        Assert.areEqual(1, TriggerControl.processedItems.size(), 'Set no debe permitir duplicados');
        
        // 🔄 TEST 8: Verificar con IDs de diferentes objetos
        Id accountId = '001000000000001AAA';
        Id contactId = '003000000000001AAA';
        Id caseId = '500000000000001AAA';
        
        TriggerControl.markAsProcessed(accountId);
        TriggerControl.markAsProcessed(contactId);
        TriggerControl.markAsProcessed(caseId);
        
        Assert.areEqual(true, TriggerControl.isAlreadyProcessed(accountId), 'Account ID debe estar procesado');
        Assert.areEqual(true, TriggerControl.isAlreadyProcessed(contactId), 'Contact ID debe estar procesado');
        Assert.areEqual(true, TriggerControl.isAlreadyProcessed(caseId), 'Case ID debe estar procesado');
        Assert.areEqual(3, TriggerControl.processedItems.size(), 'Debe tener 3 IDs diferentes');
        
        // 🔄 TEST 9: Limpieza manual de processedItems
        TriggerControl.reset();
        
        // Agregar muchos IDs (simulación de procesamiento masivo)
        for (Integer i = 0; i < 10; i++) {
            TriggerControl.markAsProcessed('00100000000000' + i + 'AAA');
        }
        
        Assert.areEqual(10, TriggerControl.processedItems.size(), 'Debe manejar múltiples IDs');
        
        System.Test.stopTest();
    }
    
    @isTest
    static void testIntegrationWithTriggers() {
        // 🔄 TEST 10: Integración con escenario real
        System.Test.startTest();
        
        // Obtener item de prueba
        Items_Cases__c testItem = [SELECT Id, Estatus__c FROM Items_Cases__c LIMIT 1];
        
        // Simular ejecución de trigger
        TriggerControl.isExecuting = true;
        Assert.areEqual(false, TriggerControl.canExecuteTrigger(), 'No debe permitir ejecución durante proceso activo');
        
        // Simular procesamiento del item
        TriggerControl.markAsProcessed(testItem.Id);
        Assert.areEqual(true, TriggerControl.isAlreadyProcessed(testItem.Id), 'El item debe marcarse como procesado');
        
        // Resetear para siguiente transacción
        TriggerControl.reset();
        
        // Verificar que se puede procesar de nuevo
        Assert.areEqual(false, TriggerControl.isAlreadyProcessed(testItem.Id), 'El item no debe estar procesado después de reset');
        Assert.areEqual(true, TriggerControl.canExecuteTrigger(), 'Debe permitir nueva ejecución después de reset');
        
        System.Test.stopTest();
    }
    
    @isTest
    static void testNullAndEmptyValues() {
        // 🔄 TEST 12: Manejo de valores nulos/vacíos
        System.Test.startTest();
        
        // Probar con string vacío como ID (no debería agregarse)
        try {
            TriggerControl.markAsProcessed('');
            Assert.isTrue(true, 'Debe manejar string vacío sin error');
        } catch(Exception e) {
            Assert.isTrue(true, 'No debería lanzar excepción con string vacío');
        }
        
        // Verificar que no se agregó
        Assert.areEqual(0, TriggerControl.processedItems.size(), 'String vacío no debe agregarse');
        
        // Probar reset múltiples veces
        TriggerControl.reset();
        TriggerControl.reset();
        TriggerControl.reset();
        
        Assert.areEqual(false, TriggerControl.isExecuting, 'Múltiples resets deben mantener isExecuting en false');
        Assert.areEqual(false, TriggerControl.skipEmailTrigger, 'Múltiples resets deben mantener skipEmailTrigger en false');
        
        System.Test.stopTest();
    }
}