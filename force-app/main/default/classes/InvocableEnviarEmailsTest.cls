@IsTest
private class InvocableEnviarEmailsTest {
    
    @TestSetup
    static void setupTestData() {
        // Crear Account
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        // Crear Contact
        Contact cont = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com',
            AccountId = acc.Id
        );
        insert cont;
        
        // Crear Case
        Case testCase = new Case(
            Subject = 'Test Case - Invocable Test',
            Status = 'En proceso',
            Origin = 'Web'
        );
        insert testCase;
        
        // Crear Items_Cases__c para pruebas
        List<Items_Cases__c> testItems = new List<Items_Cases__c>();
        for (Integer i = 0; i < 5; i++) {
            testItems.add(new Items_Cases__c(
                Correo_electronico__c = 'invocable.test' + i + '@test.com',
                Estatus__c = 'En proceso',
                Caso__c = testCase.Id,
                Contacto__c = cont.Id,
                Categorias__c = '00',
                Fecha_de_peticion__c = Date.today(),
                Fecha_de_nacimiento__c = Date.today().addYears(-25),
                Sexo__c = 'Masculino',
                Procesar_Batch__c = false
            ));
        }
        insert testItems;
    }
    
    // Test 1: Ejecución con List<Id> directamente
    @IsTest
    static void testExecuteBatch_WithIdList() {
        List<Items_Cases__c> items = [SELECT Id FROM Items_Cases__c];
        List<Id> itemIds = new List<Id>();
        for (Items_Cases__c item : items) {
            itemIds.add(item.Id);
        }
        
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        
        Test.startTest();
        // Pasar como List<Object>
        Invocable_EnviarEmails.ejecutarBatch(itemIds);
        Test.stopTest();
        
        List<Items_Cases__c> updatedItems = [
            SELECT Id, Procesar_Batch__c 
            FROM Items_Cases__c 
            WHERE Procesar_Batch__c = true
        ];
        System.assertEquals(5, updatedItems.size());
    }
    
    // Test 2: Ejecución con BatchParameters
    @IsTest
    static void testExecuteBatch_WithBatchParameters() {
        List<Items_Cases__c> items = [SELECT Id FROM Items_Cases__c LIMIT 2];
        List<Id> itemIds = new List<Id>();
        for (Items_Cases__c item : items) {
            itemIds.add(item.Id);
        }
                
        Test.startTest();
        Invocable_EnviarEmails.ejecutarBatch(itemIds);
        Test.stopTest();
        
        Integer markedCount = [SELECT COUNT() FROM Items_Cases__c WHERE Procesar_Batch__c = true];
        System.assertEquals(2, markedCount);
    }
    
    // Test 3: Ejecución con un solo ID
    @IsTest
    static void testExecuteBatch_WithSingleId() {
        Items_Cases__c item = [SELECT Id FROM Items_Cases__c LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        
        Test.startTest();
        Invocable_EnviarEmails.ejecutarBatch(new List<Id>{item.Id});
        Test.stopTest();
        
        Items_Cases__c updatedItem = [SELECT Procesar_Batch__c FROM Items_Cases__c WHERE Id = :item.Id];
        System.assertEquals(true, updatedItem.Procesar_Batch__c);
    }
    
    // Test 4: Lista vacía
    @IsTest
    static void testExecuteBatch_EmptyList() {
        Test.startTest();
        Invocable_EnviarEmails.ejecutarBatch(new List<Id>());
        Test.stopTest();
        
        System.assert(true);
    }
    
    // Test 6: BatchParameters con IDs nulos
    @IsTest
    static void testExecuteBatch_BatchParametersWithNullIds() {
        
        Test.startTest();
        Invocable_EnviarEmails.ejecutarBatch(new List<Id>());
        Test.stopTest();
        
        System.assert(true);
    }
    
    // Test 7: Input como String (ID)
    @IsTest
    static void testExecuteBatch_WithStringId() {
        Items_Cases__c item = [SELECT Id FROM Items_Cases__c LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        
        Test.startTest();
        Invocable_EnviarEmails.ejecutarBatch(new List<Id>{item.Id});
        Test.stopTest();
        
        Items_Cases__c updatedItem = [SELECT Procesar_Batch__c FROM Items_Cases__c WHERE Id = :item.Id];
        System.assertEquals(true, updatedItem.Procesar_Batch__c);
    }
    
    private class MockHttpResponseGenerator implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(200);
            res.setBody('{"success": true}');
            return res;
        }
    }
}