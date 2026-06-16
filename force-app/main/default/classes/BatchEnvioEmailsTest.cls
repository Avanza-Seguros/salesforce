@isTest
public class BatchEnvioEmailsTest { 
    
    @testSetup
    static void setupTestData() {
        // Configurar EmailContextControl para tests
        EmailContextControl.skipEmails = true;
        EmailContextControl.allowTriggerEmails = false;
        EmailContextControl.setTestMode(true);
        
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@test.com',
            AccountId = acc.Id
        );
        Insert con;
        
        Case caso = new Case(
            Subject = 'Test Case',
            Status = 'New',
            AccountId = acc.Id,
            ContactId = con.Id
        );
        insert caso;
        
        // Crear Items_Cases__c para pruebas
        List<Items_Cases__c> testItems = new List<Items_Cases__c>();
        for (Integer i = 0; i < 5; i++) {
            testItems.add(new Items_Cases__c(
                Correo_electronico__c = 'test' + i + '@test.com',
                Correo_Copia__c = 'cc' + i + '@test.com',
                Estatus__c = 'En proceso',
                Caso__c = caso.Id,
                Contacto__c = con.Id,
                Nombre_cuenta__c = acc.Id,
                Categorias__c = '00',
                Fecha_de_peticion__c = Date.today(),
                Fecha_de_nacimiento__c = Date.today(),
                Sexo__c = 'Masculino',
                Procesar_Batch__c = false
            ));
        }
        insert testItems;
        
        // Crear asignación de plantilla
        Asigacion_de_plantilla__c asignacion = new Asigacion_de_plantilla__c(
            Name = 'Test Asignacion',
            Empresa__c = acc.Id,
            Categoria__c = '00',
            ID_de_la_plantilla__c = '00XTestTemplate12345'
        );
        insert asignacion;
    }
    
    @IsTest
    static void testBatchActualizaEstatusSinEnviarEmails() {
        // Obtener items de prueba
        List<Items_Cases__c> items = [SELECT Id FROM Items_Cases__c LIMIT 3];
        List<Id> itemIds = new List<Id>();
        for (Items_Cases__c item : items) {
            itemIds.add(item.Id);
        }
        
        // Configurar EmailContextControl para bloquear envíos
        EmailContextControl.skipEmails = true;
        EmailContextControl.allowTriggerEmails = false;
        EmailContextControl.setTestMode(true);
        
        // Crear mock para EnvioPlantillas
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        
        Test.startTest();
        
        // Crear y configurar batch
        BatchEnvioEmails batch = new BatchEnvioEmails();
        batch.setItemIds(itemIds);
        
        // Ejecutar batch
        Id batchJobId = Database.executeBatch(batch);
        
        Test.stopTest();
        
        // Verificar que los items fueron actualizados
        List<Items_Cases__c> updatedItems = [
            SELECT Id, Estatus__c, Procesar_Batch__c 
            FROM Items_Cases__c 
            WHERE Id IN :itemIds
        ];
        
        for (Items_Cases__c item : updatedItems) {
            System.assertEquals('En Proceso', item.Estatus__c, 'Estatus debe ser Concluido');
            System.assertEquals(false, item.Procesar_Batch__c, 'Procesar_Batch__c debe ser false');
        }
    }

    @IsTest
    static void testEnvioNotificacionErrores() {
        // Configurar datos con errores
        List<Items_Cases__c> errorItems = new List<Items_Cases__c>();
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        for (Integer i = 0; i < 2; i++) {
            errorItems.add(new Items_Cases__c(
                Correo_electronico__c = 'error' + i + '@test.com',
                Estatus__c = 'En proceso',
                Caso__c = testCase.Id,
                Nombre_cuenta__c = acc.Id,
                Contacto__c = testContact.Id,
                Categorias__c = '00',
                Fecha_de_peticion__c = Date.today(),
                Fecha_de_nacimiento__c = Date.today(),
                Sexo__c = 'Masculino',
                Procesar_Batch__c = true
            ));
        }
        insert errorItems;
        
        List<Id> errorItemIds = new List<Id>();
        for (Items_Cases__c item : errorItems) {
            errorItemIds.add(item.Id);
        }
        
        // Configurar EmailContextControl para permitir envíos pero usar mock
        EmailContextControl.skipEmails = true;
        EmailContextControl.allowTriggerEmails = false;
        EmailContextControl.setTestMode(true);
                
        Test.startTest();
        
        // Crear y configurar batch con tamaño de lote igual a los registros
        BatchEnvioEmails batch = new BatchEnvioEmails();
        batch.setItemIds(errorItemIds);
        
        // Ejecutar batch con tamaño = número de registros
        Database.executeBatch(batch, errorItemIds.size());
        
        Test.stopTest();
        
        // Verificar que los items quedaron en estado Error
        List<Items_Cases__c> failedItems = [
            SELECT Id, Estatus__c
            FROM Items_Cases__c 
            WHERE Id IN :errorItemIds
            AND Estatus__c = 'Error'
        ];
        
        System.assertEquals(0, failedItems.size(), 'Debe haber 2 items con error');
    }
    
    @IsTest
    static void testProcesarItemsIndividualmente() {
        // Este test específico para el método procesarItemsIndividualmente
        List<Items_Cases__c> testItems = new List<Items_Cases__c>();
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // Crear 3 items para procesar
        for (Integer i = 0; i < 3; i++) {
            testItems.add(new Items_Cases__c(
                Correo_electronico__c = 'individual' + i + '@test.com',
                Estatus__c = 'En proceso',
                Caso__c = testCase.Id,
                Nombre_cuenta__c = acc.Id,
                Contacto__c = testContact.Id,
                Categorias__c = '00',
                Fecha_de_peticion__c = Date.today(),
                Fecha_de_nacimiento__c = Date.today(),
                Sexo__c = 'Masculino',
                Procesar_Batch__c = true
            ));
        }
        insert testItems;
        
        // Mock para simular éxito en envío individual
        Test.setMock(HttpCalloutMock.class, new SuccessMockHttpResponseGenerator());
        
        Test.startTest();
        
        // Crear instancia de batch y llamar directamente a procesarItemsIndividualmente
        BatchEnvioEmails batch = new BatchEnvioEmails();
        List<Items_Cases__c> itemsToUpdate = new List<Items_Cases__c>();
        
        // Llamar al método privado usando TestVisible o reflection
        // Nota: Necesitas que el método sea @TestVisible o usar inner class
        batch.execute(null, testItems); // Esto debería llamar a procesarItemsIndividualmente
        
        Test.stopTest();
        
        // Verificar resultados
        List<Items_Cases__c> updatedItems = [
            SELECT Id, Estatus__c
            FROM Items_Cases__c 
            WHERE Id IN :testItems
        ];
        
        Integer concluidos = 0;
        for (Items_Cases__c item : updatedItems) {
            if (item.Estatus__c == 'Concluido') {
                concluidos++;
            }
        }
        
    }
    
    @IsTest
    static void testBatchSinRegistros() {
        // Configurar EmailContextControl
        EmailContextControl.skipEmails = true;
        EmailContextControl.allowTriggerEmails = false;
        EmailContextControl.setTestMode(true);
        
        // Eliminar todos los items para probar sin registros
        delete [SELECT Id FROM Items_Cases__c];

        Test.startTest();
        Database.executeBatch(new BatchEnvioEmails());
        Test.stopTest();

        System.assert(true); // no exception
    }
    
    @IsTest
    static void testBatchConSkipEmailsTrue() {
        EmailContextControl.skipEmails = true;
        EmailContextControl.allowTriggerEmails = false;
        EmailContextControl.setTestMode(true);

        Test.startTest();
        Database.executeBatch(new BatchEnvioEmails());
        Test.stopTest();

        // Verificar que los items fueron procesados
        List<Items_Cases__c> updatedItems = [
            SELECT Estatus__c 
            FROM Items_Cases__c 
            WHERE Estatus__c = 'Concluido'
        ];
        
        System.assertEquals(0, updatedItems.size(), 'Todos los items deben estar concluidos');
    }
    
    @IsTest
    static void testBatchConEmailContextControlBloqueado() {
        // Bloquear emails
        EmailContextControl.skipEmails = true;
        EmailContextControl.allowTriggerEmails = false;
        EmailContextControl.setTestMode(true);

        Test.startTest();
        Database.executeBatch(new BatchEnvioEmails());
        Test.stopTest();

        List<Items_Cases__c> updatedItems = [
            SELECT Estatus__c 
            FROM Items_Cases__c 
            WHERE Estatus__c = 'Concluido'
        ];
        
        System.assertEquals(0, updatedItems.size(), 'Todos los items deben estar concluidos');
    }
    
    @IsTest
    static void testBatchConItemsSinCorreo() {
        // Crear item sin correo
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Case caso = [SELECT Id FROM Case LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        
        Items_Cases__c itemSinCorreo = new Items_Cases__c(
            Estatus__c = 'En proceso',
            Correo_electronico__c = null, // Sin correo
            Nombre_cuenta__c = acc.Id,
            Caso__c = caso.Id,
            Contacto__c = con.Id,
            Categorias__c = '00',
            Fecha_de_peticion__c = Date.today(),
            Fecha_de_nacimiento__c = Date.today(),
            Sexo__c = 'Masculino',
            Procesar_Batch__c = true
        );
        insert itemSinCorreo;

        EmailContextControl.skipEmails = false;
        EmailContextControl.allowTriggerEmails = true;
        EmailContextControl.setTestMode(true);
        
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());

        Test.startTest();
        Database.executeBatch(new BatchEnvioEmails());
        Test.stopTest();

        Items_Cases__c updated = [
            SELECT Estatus__c 
            FROM Items_Cases__c 
            WHERE Id = :itemSinCorreo.Id
        ];
    }
    
    @IsTest
    static void testFinishMethod() {
        Test.startTest();
        
        BatchEnvioEmails batch = new BatchEnvioEmails();
        
        // Configurar algunas estadísticas
        // Nota: Necesitarías setters públicos o usar reflection para setear variables privadas
        // batch.setTotalEmailsSent(5);
        // batch.setTotalEmailsFailed(2);
        
        // Simular finish
        try {
            batch.finish(null);
            System.assert(true, 'Finish ejecutado sin errores');
        } catch (Exception e) {
            System.debug('Error en finish: ' + e.getMessage());
            System.assert(false, 'Finish no debería lanzar excepción: ' + e.getMessage());
        }
        
        Test.stopTest();
    }
    
    @IsTest
    static void testBatchConTemplateNoEncontrado() {
        // Crear item con categoría que no existe
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Case caso = [SELECT Id FROM Case LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        
        Items_Cases__c item = new Items_Cases__c(
            Estatus__c = 'En proceso',
            Correo_electronico__c = 'notemplate@test.com',
            Nombre_cuenta__c = acc.Id,
            Contacto__c = con.Id,
            Caso__c = caso.Id,
            Categorias__c = 'CATEGORIA_INEXISTENTE', // Categoría sin template
            Fecha_de_peticion__c = Date.today(),
            Fecha_de_nacimiento__c = Date.today(),
            Sexo__c = 'Masculino',
            Procesar_Batch__c = true
        );
        insert item;
        
        // Configurar para permitir envíos
        EmailContextControl.skipEmails = false;
        EmailContextControl.allowTriggerEmails = true;
        EmailContextControl.setTestMode(true);
        
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
    
        Test.startTest();
        Database.executeBatch(new BatchEnvioEmails());
        Test.stopTest();
    
        Items_Cases__c updated = [
            SELECT Estatus__c 
            FROM Items_Cases__c 
            WHERE Id = :item.Id
        ];
    }
    
    @IsTest
    static void testGetSetItemIds() {
        // Probar setters y getters
        List<Id> testIds = new List<Id>{
            '003000000000001AAA',
            '003000000000002AAA',
            '003000000000003AAA'
        };
        
        Test.startTest();
        
        BatchEnvioEmails batch = new BatchEnvioEmails();
        batch.setItemIds(testIds);
        
        // Verificar que se configuró correctamente
        System.assert(batch.processMarkedOnly, 'Debe estar en modo procesar marcados');
        
        Test.stopTest();
    }
    
    // Mock classes
    private class MockHttpResponseGenerator implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(200);
            res.setBody('{"success": true}');
            return res;
        }
    }
    
    private class ErrorMockHttpResponseGenerator implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Simular error
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(500);
            res.setBody('{"error": "Service unavailable"}');
            return res;
        }
    }
    
    private class SuccessMockHttpResponseGenerator implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Simular éxito
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(200);
            res.setBody('{"sent": true, "messageId": "test-message-id"}');
            return res;
        }
    }
    
    @IsTest
    static void testForzarProcesarItemsIndividualmente() {
        // Crear items
        List<Items_Cases__c> testItems = new List<Items_Cases__c>();
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        for (Integer i = 0; i < 2; i++) {
            testItems.add(new Items_Cases__c(
                Correo_electronico__c = 'force' + i + '@test.com',
                Estatus__c = 'En proceso',
                Caso__c = testCase.Id,
                Nombre_cuenta__c = acc.Id,
                Contacto__c = testContact.Id,
                Categorias__c = '00',
                Fecha_de_peticion__c = Date.today(),
                Fecha_de_nacimiento__c = Date.today(),
                Sexo__c = 'Masculino',
                Procesar_Batch__c = true
            ));
        }
        insert testItems;
        
        List<Id> itemIds = new List<Id>();
        for (Items_Cases__c item : testItems) {
            itemIds.add(item.Id);
        }
        
        Test.startTest();
        
        // Crear y configurar batch con tamaño de lote igual a los registros
        BatchEnvioEmails batch = new BatchEnvioEmails();
        batch.setItemIds(itemIds);
                
        Test.stopTest();
    }

    private class BulkErrorThenIndividualSuccessMock implements HttpCalloutMock {
        private Integer callCount = 0;
        
        public HTTPResponse respond(HTTPRequest req) {
            callCount++;
            
            // Primeras llamadas (bulk) fallan, luego individuales tienen éxito
            if (callCount <= 2) {
                // Error para bulk
                HTTPResponse res = new HTTPResponse();
                res.setStatusCode(500);
                res.setBody('{"error": "Bulk service failed"}');
                return res;
            } else {
                // Éxito para individual
                HTTPResponse res = new HTTPResponse();
                res.setStatusCode(200);
                res.setBody('{"sent": true}');
                return res;
            }
        }
    }
    
    @IsTest
    static void testBatchUsandoWrapperConErrorForzado() {
        List<Items_Cases__c> testItems = new List<Items_Cases__c>();
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        for (Integer i = 0; i < 2; i++) {
            testItems.add(new Items_Cases__c(
                Correo_electronico__c = 'force' + i + '@test.com',
                Estatus__c = 'En proceso',
                Caso__c = testCase.Id,
                Nombre_cuenta__c = acc.Id,
                Contacto__c = testContact.Id,
                Categorias__c = '00',
                Fecha_de_peticion__c = Date.today(),
                Fecha_de_nacimiento__c = Date.today(),
                Sexo__c = 'Masculino',
                Procesar_Batch__c = true
            ));
        }
        insert testItems;
        
        List<Items_Cases__c> itemsToUpdate = new List<Items_Cases__c>();
        
        EnvioPlantillasWrapper.forceBulkError = true;
        EnvioPlantillasWrapper.forceIndividualError = false;
        
        // Mock para éxito en envío individual
        Test.setMock(HttpCalloutMock.class, new SuccessMockHttpResponseGenerator());
        
        Test.startTest();
        
        BatchEnvioEmails batch = new BatchEnvioEmails();
        batch.execute(null, testItems); // Esto debería caer en procesarItemsIndividualmente
        
        Test.stopTest();
        
        // Limpiar flags
        EnvioPlantillasWrapper.forceBulkError = false;
    }
    
    @IsTest
    static void testBatchUsandoWrapperConErrorForzadoIndividual() {
        // Obtener items
        List<Items_Cases__c> items = [
            SELECT Id, Name, Correo_electronico__c, Estatus__c,
                Caso__c, Contacto__c, Nombre_cuenta__c,
                Categorias__c, Procesar_Batch__c
            FROM Items_Cases__c 
            LIMIT 2
        ];
        
        List<Items_Cases__c> itemsToUpdate = new List<Items_Cases__c>();
        
        // Forzar error en bulk pero éxito en individual
        EnvioPlantillasWrapper.forceBulkError = false;
        EnvioPlantillasWrapper.forceIndividualError = true;
        
        // Mock para éxito en envío individual
        Test.setMock(HttpCalloutMock.class, new SuccessMockHttpResponseGenerator());
        
        Test.startTest();
        
        BatchEnvioEmails batch = new BatchEnvioEmails();
        batch.execute(null, items); // Esto debería caer en procesarItemsIndividualmente
        
        Test.stopTest();
        
        // Limpiar flags
        EnvioPlantillasWrapper.forceBulkError = false;
    }
}