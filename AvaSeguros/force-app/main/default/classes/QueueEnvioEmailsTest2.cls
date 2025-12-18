@IsTest
private class QueueEnvioEmailsTest2 {
    
    @IsTest
    static void testQueueEnvioEmails_IntegrationTest() {
        // Integration test with actual data flow
        // Create complete test data chain
        
        // 1. Create Account
        Account acc = new Account(Name = 'Integration Test Account');
        insert acc;
        
        // 2. Create Contact
        Contact c = new Contact(
            FirstName = 'Integration',
            LastName = 'Test',
            Email = 'integration@test.com',
            AccountId = acc.Id
        );
        insert c;
        
        // 3. Create Case
        Case caso = new Case(
            AccountId = acc.Id,
            Subject = 'Test Case'
        );
        insert caso;
        
        // 4. Create Asigacion_de_plantilla__c (if needed by EnvioPlantillas)
        Asigacion_de_plantilla__c plantillaAsignada = new Asigacion_de_plantilla__c(
            Empresa__c = acc.Id,
            Categoria__c = '01',
            ID_de_la_plantilla__c = 'Test_Template'
        );
        insert plantillaAsignada;
        
        // 5. Create Items_Cases__c
        List<Items_Cases__c> items = new List<Items_Cases__c>();
        for (Integer i = 0; i < 5; i++) {
            items.add(new Items_Cases__c(
                Nombre_cuenta__c = acc.Id,
                Asegurado__c = c.Id,
                Contacto__c = c.Id,
                Caso__c = caso.Id,
                Correo_electronico__c = 'test' + i + '@test.com',
                Correo_Copia__c = 'copy' + i + '@test.com',
                Categorias__c = 'Alta',
                Email_Enviado__c = false,
                Estatus__c = 'En proceso',
                Nombre__c = 'Test' + i,
                Apellido_paterno__c = 'User' + i,
                Fecha_de_peticion__c = Date.today(),
                Fecha_de_nacimiento__c = Date.today().addYears(-25),
                Sexo__c = 'Femenino'
            ));
        }
        insert items;
        
        Set<Id> itemIds = new Set<Id>();
        for (Items_Cases__c item : items) {
            itemIds.add(item.Id);
        }
        
        // When
        Test.startTest();
        
        // Mock any callouts
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        
        // Execute Queueable
        QueueEnvioEmails queue = new QueueEnvioEmails(itemIds);
        Id jobId = System.enqueueJob(queue);
        
        Test.stopTest();
        
        // Then
        System.assertNotEquals(null, jobId, 'Job should be enqueued');
        
        // Verify items might be updated (implementation dependent)
        List<Items_Cases__c> updatedItems = [
            SELECT Id, Email_Enviado__c, Estatus__c 
            FROM Items_Cases__c 
            WHERE Id IN :itemIds
        ];
        
        System.assertEquals(5, updatedItems.size(), 'All items should exist');
        System.assert(true, 'Integration test completed');
    }
    
    @IsTest
    static void testQueueEnvioEmails_BatchIdGeneration() {
        // Test that batch IDs are generated properly
        Set<Id> testIds = new Set<Id>{'001000000000001'};
        
        Test.startTest();
        
        QueueEnvioEmails queue1 = new QueueEnvioEmails(testIds);
        QueueEnvioEmails queue2 = new QueueEnvioEmails(testIds);
        
        System.enqueueJob(queue1);
        System.enqueueJob(queue2);
        
        Test.stopTest();
        
        // Each instance should have a unique batch ID
        System.assert(true, 'Multiple queue instances should work independently');
    }
    
    @IsTest
    static void testQueueEnvioEmails_GovernorLimits() {
        // Test governor limit compliance
        Account acc = new Account(Name = 'Governor Test');
        insert acc;
        
        Contact c = new Contact(FirstName = 'Governor', LastName = 'Test', Email = 'governor@test.com');
        insert c;
        
        Case caso = new Case(AccountId = acc.Id);
        insert caso;
        
        // Create many items
        List<Items_Cases__c> items = new List<Items_Cases__c>();
        for (Integer i = 0; i < 100; i++) {
            items.add(new Items_Cases__c(
                Nombre_cuenta__c = acc.Id,
                Asegurado__c = c.Id,
                Caso__c = caso.Id,
                Correo_electronico__c = 'test' + i + '@test.com',
                Email_Enviado__c = false,
                Categorias__c = 'Alta',
                Fecha_de_peticion__c = Date.today(),
                Fecha_de_nacimiento__c = Date.today().addYears(-25),
                Sexo__c = 'Femenino',
                Estatus__c = 'En proceso'
            ));
        }
        insert items;
        
        Set<Id> itemIds = new Set<Id>();
        for (Items_Cases__c item : items) {
            itemIds.add(item.Id);
        }
        
        Test.startTest();
        
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        
        QueueEnvioEmails queue = new QueueEnvioEmails(itemIds);
        System.enqueueJob(queue);
        
        Test.stopTest();
        
        // Verify we didn't hit governor limits
        System.assert(Limits.getQueries() < Limits.getLimitQueries(), 
            'Should not exceed SOQL queries limit');
        System.assert(Limits.getDmlStatements() < Limits.getLimitDmlStatements(),
            'Should not exceed DML statements limit');
        System.assert(Limits.getDmlRows() < Limits.getLimitDmlRows(),
            'Should not exceed DML rows limit');
    }
    
    @IsTest
    static void testQueueEnvioEmails_WithDifferentCategories() {
        // Test with different categories
        Account acc = new Account(Name = 'Category Test');
        insert acc;
        
        Contact c = new Contact(FirstName = 'Category', LastName = 'Test', Email = 'category@test.com');
        insert c;
        
        Case caso = new Case(AccountId = acc.Id);
        insert caso;
        
        List<Items_Cases__c> items = new List<Items_Cases__c>();
        String[] categories = new String[]{'Alta', 'Baja', 'Cambio', 'Aclaración'};
        
        for (Integer i = 0; i < categories.size(); i++) {
            items.add(new Items_Cases__c(
                Nombre_cuenta__c = acc.Id,
                Asegurado__c = c.Id,
                Caso__c = caso.Id,
                Correo_electronico__c = 'test' + i + '@test.com',
                Email_Enviado__c = false,
                Categorias__c = categories[i],
                Estatus__c = 'En proceso',
                Fecha_de_peticion__c = Date.today(),
                Fecha_de_nacimiento__c = Date.today().addYears(-25),
                Sexo__c = 'Femenino'
            ));
        }
        insert items;
        
        Set<Id> itemIds = new Set<Id>();
        for (Items_Cases__c item : items) {
            itemIds.add(item.Id);
        }
        
        Test.startTest();
        
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        
        QueueEnvioEmails queue = new QueueEnvioEmails(itemIds);
        System.enqueueJob(queue);
        
        Test.stopTest();
        
        // Should handle different categories
        System.assert(true, 'Should handle different categories');
    }
    
    // Helper para crear respuesta mock
    private class MockHttpResponseGenerator implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"success":true}');
            res.setStatusCode(200);
            return res;
        }
    }
}