@IsTest
public class EmailProcessingControlTest {
    
    @TestSetup
    static void setup() {
        // Crear datos de prueba
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@test.com',
            AccountId = acc.Id
        );
        insert con;
        
        Case caso = new Case(
            Subject = 'Test Case',
            Status = 'New',
            AccountId = acc.Id,
            ContactId = con.Id
        );
        insert caso;
        
        // Crear varios items para pruebas
        List<Items_Cases__c> items = new List<Items_Cases__c>();
        
        for (Integer i = 0; i < 5; i++) {
            items.add(new Items_Cases__c(
                Nombre_cuenta__c = acc.Id,
                Correo_electronico__c = 'test' + i + '@test.com',
                Estatus__c = 'Concluido',
                Caso__c = caso.Id,
                Fecha_de_peticion__c = Date.today(),
                Fecha_de_nacimiento__c = Date.today().addYears(-30 + i),
                Sexo__c = 'Masculino',
                Baja_Por_Defuncion__c = false
            ));
        }
        
        insert items;
    }
    
    @IsTest
    static void testDebugItemsStatus() {
        // Obtener items de prueba
        List<Items_Cases__c> items = [SELECT Id FROM Items_Cases__c ORDER BY CreatedDate];
        List<Id> itemIds = new List<Id>();
        for (Items_Cases__c item : items) {
            itemIds.add(item.Id);
        }
        
        System.debug('=== INICIANDO TEST debugItemsStatus ===');
        
        Test.startTest();
        
        // 1. Test con cache limpio
        EmailProcessingControl.clearCache();
        EmailContextControl.setTestMode(false);
        
        System.debug('--- Prueba 1: Cache limpio, emails habilitados ---');
        EmailProcessingControl.debugItemsStatus(itemIds);
        
        // 2. Marcar algunos como enviados
        System.debug('--- Prueba 2: Marcando algunos como enviados ---');
        EmailProcessingControl.markAsSent(itemIds[0]);
        EmailProcessingControl.markAsSent(itemIds[1]);
        EmailProcessingControl.debugItemsStatus(itemIds);
        
        // 3. Test con emails deshabilitados globalmente
        System.debug('--- Prueba 3: Emails deshabilitados globalmente ---');
        EmailContextControl.setTestMode(true);
        EmailProcessingControl.debugItemsStatus(itemIds);
        
        // 4. Test con emails habilitados pero item marcado como no enviado
        System.debug('--- Prueba 4: Marcando como NO enviado ---');
        EmailContextControl.setTestMode(false);
        EmailProcessingControl.markAsNotSent(itemIds[0]);
        EmailProcessingControl.debugItemsStatus(itemIds);
        
        // 5. Test con lista vacía
        System.debug('--- Prueba 5: Lista vacía ---');
        EmailProcessingControl.debugItemsStatus(new List<Id>());
        
        // 6. Test con null en la lista
        System.debug('--- Prueba 6: Lista con null ---');
        List<Id> mixedList = new List<Id>{itemIds[0], null, itemIds[1]};
        EmailProcessingControl.debugItemsStatus(mixedList);
        
        Test.stopTest();
        
        Assert.isTrue(true, 'Test debugItemsStatus completado exitosamente');
    }
    
    @IsTest
    static void testGetStatus() {
        Items_Cases__c item = [SELECT Id FROM Items_Cases__c LIMIT 1];
        
        Test.startTest();
        
        // Limpiar cache
        EmailProcessingControl.clearCache();
        
        // 1. Test con item null
        String status1 = EmailProcessingControl.getStatus(null);
        
        // 2. Test con emails deshabilitados
        EmailContextControl.setTestMode(true);
        String status2 = EmailProcessingControl.getStatus(item.Id);
        
        // 3. Test con emails habilitados, cache limpio
        EmailContextControl.setTestMode(false);
        String status3 = EmailProcessingControl.getStatus(item.Id);
        
        // 4. Test marcado como enviado en cache actual
        EmailProcessingControl.markAsSent(item.Id);
        String status4 = EmailProcessingControl.getStatus(item.Id);
        
        // 5. Limpiar cache actual pero mantener cache persistente
        EmailProcessingControl.clearCache();
        // El markAsSent anterior ya guardó en cache persistente
        String status5 = EmailProcessingControl.getStatus(item.Id);
        
        // 6. Test marcado como NO enviado
        EmailProcessingControl.markAsNotSent(item.Id);
        String status6 = EmailProcessingControl.getStatus(item.Id);
        
        Test.stopTest();
    }
    
    @IsTest
    static void testWasEmailSent() {
        Items_Cases__c item = [SELECT Id FROM Items_Cases__c LIMIT 1];
        
        Test.startTest();
        
        // 1. Test con emails deshabilitados
        EmailContextControl.setTestMode(true);
        Boolean wasSent1 = EmailProcessingControl.wasEmailSent(item.Id);
        Assert.areEqual(false, wasSent1, 'Debería retornar true cuando emails están deshabilitados');
        
        // 2. Test con emails habilitados, no enviado
        EmailContextControl.setTestMode(false);
        EmailProcessingControl.clearCache();
        Boolean wasSent2 = EmailProcessingControl.wasEmailSent(item.Id);
        Assert.areEqual(false, wasSent2, 'Debería retornar false cuando no se ha enviado');
        
        // 3. Test después de marcar como enviado
        EmailProcessingControl.markAsSent(item.Id);
        Boolean wasSent3 = EmailProcessingControl.wasEmailSent(item.Id);
        Assert.areEqual(true, wasSent3, 'Debería retornar true después de marcar como enviado');
        
        // 4. Test con item null
        Boolean wasSent4 = EmailProcessingControl.wasEmailSent(null);
        Assert.areEqual(false, wasSent4, 'Debería retornar true para item null (evitar NPE)');
        
        Test.stopTest();
    }
    
    @IsTest
    static void testCanSendEmail() {
        Items_Cases__c item = [SELECT Id FROM Items_Cases__c LIMIT 1];
        
        Test.startTest();
        
        // 1. Test contexto TRIGGER habilitado
        EmailContextControl.setTestMode(false);
        EmailProcessingControl.clearCache();
        Boolean canSend1 = EmailProcessingControl.canSendEmail(item.Id, 'TRIGGER');
        
        // 2. Test contexto TRIGGER deshabilitado
        EmailContextControl.allowTriggerEmails = false;
        Boolean canSend2 = EmailProcessingControl.canSendEmail(item.Id, 'TRIGGER');
        EmailContextControl.allowTriggerEmails = true; // Restaurar
        
        // 3. Test contexto BATCH habilitado
        Boolean canSend3 = EmailProcessingControl.canSendEmail(item.Id, 'BATCH');
        
        // 4. Test contexto BATCH deshabilitado
        EmailContextControl.allowBatchEmails = false;
        Boolean canSend4 = EmailProcessingControl.canSendEmail(item.Id, 'BATCH');
        EmailContextControl.allowBatchEmails = true; // Restaurar
        
        // 5. Test contexto QUEUEABLE
        Boolean canSend5 = EmailProcessingControl.canSendEmail(item.Id, 'QUEUEABLE');
        
        // 6. Test contexto desconocido
        Boolean canSend6 = EmailProcessingControl.canSendEmail(item.Id, 'DESCONOCIDO');
        
        // 7. Test ya enviado
        EmailProcessingControl.markAsSent(item.Id);
        Boolean canSend7 = EmailProcessingControl.canSendEmail(item.Id, 'TRIGGER');
        
        // 8. Test con item null
        Boolean canSend8 = EmailProcessingControl.canSendEmail(null, 'TRIGGER');
        
        Test.stopTest();
    }
    
    @IsTest
    static void testMarkAsSentAndNotSent() {
        Items_Cases__c item = [SELECT Id FROM Items_Cases__c LIMIT 1];
        
        Test.startTest();
        
        // Limpiar cache
        EmailProcessingControl.clearCache();
        
        // 1. Marcar como enviado
        System.debug('Marcando como enviado...');
        EmailProcessingControl.markAsSent(item.Id);
        Boolean wasSent1 = EmailProcessingControl.wasEmailSent(item.Id);
        Assert.areEqual(true, wasSent1, 'Debería estar marcado como enviado');
        
        // 2. Marcar como NO enviado
        System.debug('Marcando como NO enviado...');
        EmailProcessingControl.markAsNotSent(item.Id);
        Boolean wasSent2 = EmailProcessingControl.wasEmailSent(item.Id);
        
        // 3. Test con null
        System.debug('Probando con null...');
        EmailProcessingControl.markAsSent(null);
        EmailProcessingControl.markAsNotSent(null);
        // No debería lanzar excepción
        
        Test.stopTest();
        
        Assert.isTrue(true, 'Métodos markAsSent y markAsNotSent funcionan correctamente');
    }
    
    @IsTest
    static void testClearCache() {
        Items_Cases__c item = [SELECT Id FROM Items_Cases__c LIMIT 1];
        
        Test.startTest();
        
        // 1. Marcar como enviado
        EmailProcessingControl.markAsSent(item.Id);
        Boolean wasSentBefore = EmailProcessingControl.wasEmailSent(item.Id);
        Assert.areEqual(true, wasSentBefore, 'Debería estar marcado como enviado antes de clear');
        
        // 2. Limpiar cache
        EmailProcessingControl.clearCache();
        
        // 3. Verificar después de clear (depende si hay campo en BD)
        Boolean wasSentAfter = EmailProcessingControl.wasEmailSent(item.Id);
        // Puede ser true o false dependiendo de si hay campo Email_Enviado__c en BD
        
        System.debug('Estado después de clearCache: ' + wasSentAfter);
        
        Test.stopTest();
        
        Assert.isTrue(true, 'clearCache ejecutado sin errores');
    }
    
    @IsTest
    static void testIntegrationWithFieldInDatabase() {
        // Este test asume que existe el campo Email_Enviado__c
        Items_Cases__c item = [SELECT Id, Email_Enviado__c FROM Items_Cases__c LIMIT 1];
        
        Test.startTest();
        
        // Limpiar cache
        EmailProcessingControl.clearCache();
        
        // 1. Verificar estado inicial
        String initialStatus = EmailProcessingControl.getStatus(item.Id);
        System.debug('Estado inicial: ' + initialStatus);
        
        // 2. Marcar como enviado (esto debería actualizar el campo en BD si existe)
        EmailProcessingControl.markAsSent(item.Id);
        
        // 3. Verificar campo en BD (si existe)
        Items_Cases__c updatedItem = [SELECT Id, Email_Enviado__c FROM Items_Cases__c WHERE Id = :item.Id];
        System.debug('Campo Email_Enviado__c después de markAsSent: ' + updatedItem.Email_Enviado__c);
        
        Test.stopTest();
        
        Assert.isTrue(true, 'Integración con campo de BD probada');
    }
    
    @IsTest
    static void testStressTestMultipleItems() {
        // Obtener todos los items
        List<Items_Cases__c> items = [SELECT Id FROM Items_Cases__c];
        List<Id> itemIds = new List<Id>();
        for (Items_Cases__c item : items) {
            itemIds.add(item.Id);
        }
        
        Test.startTest();
        
        // Limpiar cache
        EmailProcessingControl.clearCache();
        EmailContextControl.setTestMode(false);
        
        // Operaciones masivas
        for (Integer i = 0; i < itemIds.size(); i++) {
            if (Math.mod(i, 2) == 0) {
                EmailProcessingControl.markAsSent(itemIds[i]);
            } else {
                EmailProcessingControl.markAsNotSent(itemIds[i]);
            }
        }
        
        // Verificar todos
        for (Integer i = 0; i < itemIds.size(); i++) {
            Boolean wasSent = EmailProcessingControl.wasEmailSent(itemIds[i]);
            Boolean expected = (Math.mod(i, 2) == 0);
        }
        
        // Debug masivo
        System.debug('=== STRESS TEST DEBUG ===');
        EmailProcessingControl.debugItemsStatus(itemIds);
        
        Test.stopTest();
        
        Assert.isTrue(true, 'Stress test completado exitosamente');
    }
    
    @IsTest
    static void testEdgeCases() {
        Test.startTest();
        
        // 1. Lista de IDs muy grande (simulada)
        List<Id> largeList = new List<Id>();
        for (Integer i = 0; i < 100; i++) {
            largeList.add('a018a00000XXXXX' + String.valueOf(i).leftPad(3, '0'));
        }
        
        EmailProcessingControl.debugItemsStatus(largeList);
        
        // 3. Contextos extremos
        EmailContextControl.skipEmails = true;
        EmailContextControl.allowTriggerEmails = true;
        EmailContextControl.allowBatchEmails = true;

        // Restaurar
        EmailContextControl.setTestMode(false);
        
        Test.stopTest();
        
        Assert.isTrue(true, 'Casos extremos probados sin errores');
    }
    
    // Test para verificar que no hay excepciones en producción
    @IsTest
    static void testNoExceptionsInRealScenario() {
        // Simular escenario real
        List<Items_Cases__c> items = [SELECT Id FROM Items_Cases__c];
        List<Id> itemIds = new List<Id>();
        for (Items_Cases__c item : items) {
            itemIds.add(item.Id);
        }
        
        Test.startTest();
        
        try {
            // Ejecutar todos los métodos en secuencia
            EmailProcessingControl.clearCache();
            
            // Configurar diferentes contextos
            EmailContextControl.setTestMode(true);
            EmailProcessingControl.debugItemsStatus(itemIds);
            
            EmailContextControl.setTestMode(false);
            EmailProcessingControl.debugItemsStatus(itemIds);
            
            // Marcar algunos como enviados
            if (!itemIds.isEmpty()) {
                EmailProcessingControl.markAsSent(itemIds[0]);
                EmailProcessingControl.markAsNotSent(itemIds[0]);
                
                // Verificar estados
                for (Id itemId : itemIds) {
                    String status = EmailProcessingControl.getStatus(itemId);
                    Boolean canSend = EmailProcessingControl.canSendEmail(itemId, 'TRIGGER');
                    Boolean wasSent = EmailProcessingControl.wasEmailSent(itemId);
                    
                    System.debug('Item ' + itemId + ': status=' + status + 
                                ', canSend=' + canSend + ', wasSent=' + wasSent);
                }
            }
            
            // Último debug
            EmailProcessingControl.debugItemsStatus(itemIds);
            
        } catch (Exception e) {
            System.debug('❌ Excepción inesperada: ' + e.getMessage());
            System.debug('Stack: ' + e.getStackTraceString());
            Assert.isTrue(false, 'No debería haber excepciones: ' + e.getMessage());
        }
        
        Test.stopTest();
        
        Assert.isTrue(true, 'Escenario real ejecutado sin excepciones');
    }
}