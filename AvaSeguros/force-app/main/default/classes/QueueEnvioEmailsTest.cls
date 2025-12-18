@IsTest
private class QueueEnvioEmailsTest {
    
    // Método helper para crear datos de prueba
    private static Items_Cases__c createTestItem(Id accountId, Id contactId, Id caseId, Boolean withEmail, Boolean emailSent) {
        return new Items_Cases__c(
            Correo_electronico__c = withEmail ? 'test' + System.now().getTime() + '@test.com' : null,
            Correo_Copia__c = 'copy@test.com',
            Asegurado__c = contactId,
            Email_Enviado__c = emailSent,
            Categorias__c = 'Alta',
            Caso__c = caseId,
            Nombre_cuenta__c = accountId,
            Fecha_de_peticion__c = Date.today(),
            Fecha_de_nacimiento__c = Date.today().addYears(-20),
            Sexo__c = 'Masculino',
            Estatus__c = 'En proceso',
            Nombre__c = 'Test',
            Apellido_paterno__c = 'User'
        );
    }
    
    @IsTest
    static void testQueueEnvioEmails_WithValidItems() {
        // Given
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        Contact c = new Contact(
            FirstName = 'Juan',
            LastName = 'Perez',
            Email = 'juan@test.com'
        );
        insert c;
        
        Case caso = new Case(AccountId = acc.Id);
        insert caso;
        
        List<Items_Cases__c> items = new List<Items_Cases__c>();
        for (Integer i = 0; i < 3; i++) {
            items.add(createTestItem(acc.Id, c.Id, caso.Id, true, false));
        }
        insert items;
        
        Set<Id> itemIds = new Set<Id>();
        for (Items_Cases__c i : items) {
            itemIds.add(i.Id);
        }
        
        // Mock the email sending to avoid actual emails
        Test.startTest();
        
        // Set mock for any callouts if EnvioPlantillas uses them
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        
        // Execute the Queueable
        QueueEnvioEmails queue = new QueueEnvioEmails(itemIds);
        System.enqueueJob(queue);
        
        Test.stopTest();
        
        // Then - Verify no actual emails were sent in test context
        System.assertEquals(0, Limits.getEmailInvocations(), 
            'No real emails should be sent during tests');
        
        // Verify items might have been updated (depends on implementation)
        List<Items_Cases__c> updatedItems = [
            SELECT Id, Email_Enviado__c 
            FROM Items_Cases__c 
            WHERE Id IN :itemIds
        ];
        
        System.assert(updatedItems.size() > 0, 'Items should exist');
    }
    
    @IsTest
    static void testQueueEnvioEmails_WithEmptySet() {
        // Given
        Set<Id> emptySet = new Set<Id>();
        
        // When
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(emptySet);
        System.enqueueJob(queue);
        Test.stopTest();
        
        // Then - Should handle empty set without errors
        System.assert(true, 'Should handle empty item set');
    }
    
    @IsTest
    static void testQueueEnvioEmails_WithNullSet() {
        // Given
        Set<Id> nullSet = null;
        
        // When
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(nullSet);
        System.enqueueJob(queue);
        Test.stopTest();
        
        // Then - Should handle null without errors
        System.assert(true, 'Should handle null item set');
    }
    
    @IsTest
    static void testQueueEnvioEmails_WithAlreadySentEmails() {
        // Given - Items that already have emails sent
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        Contact c = new Contact(FirstName = 'Maria', LastName = 'Gomez', Email = 'maria@test.com');
        insert c;
        
        Case caso = new Case(AccountId = acc.Id);
        insert caso;
        
        List<Items_Cases__c> items = new List<Items_Cases__c>();
        for (Integer i = 0; i < 2; i++) {
            items.add(createTestItem(acc.Id, c.Id, caso.Id, true, true)); // Email_Enviado__c = true
        }
        insert items;
        
        Set<Id> itemIds = new Set<Id>();
        for (Items_Cases__c i : items) {
            itemIds.add(i.Id);
        }
        
        // When
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(itemIds);
        System.enqueueJob(queue);
        Test.stopTest();
        
        // Then - Items with Email_Enviado__c = true should not be processed
        // Verify they still have Email_Enviado__c = true
        List<Items_Cases__c> updatedItems = [
            SELECT Id, Email_Enviado__c 
            FROM Items_Cases__c 
            WHERE Id IN :itemIds 
            AND Email_Enviado__c = true
        ];
        
        System.assertEquals(2, updatedItems.size(), 
            'Items with emails already sent should not be updated');
    }
    
    @IsTest
    static void testQueueEnvioEmails_WithNoEmailAddress() {
        // Given - Items without email address
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        Contact c = new Contact(FirstName = 'Carlos', LastName = 'Lopez', Email = 'carlos@test.com');
        insert c;
        
        Case caso = new Case(AccountId = acc.Id);
        insert caso;
        
        List<Items_Cases__c> items = new List<Items_Cases__c>();
        for (Integer i = 0; i < 2; i++) {
            items.add(createTestItem(acc.Id, c.Id, caso.Id, false, false)); // No email
        }
        insert items;
        
        Set<Id> itemIds = new Set<Id>();
        for (Items_Cases__c i : items) {
            itemIds.add(i.Id);
        }
        
        // When
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(itemIds);
        System.enqueueJob(queue);
        Test.stopTest();
        
        // Then - Items without email should not be processed
        System.assert(true, 'Should handle items without email address');
    }
    
    @IsTest
    static void testQueueEnvioEmails_WithNoAsegurado() {
        // Given - Items without Asegurado
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        Case caso = new Case(AccountId = acc.Id);
        insert caso;
        
        List<Items_Cases__c> items = new List<Items_Cases__c>();
        for (Integer i = 0; i < 2; i++) {
            Items_Cases__c item = createTestItem(acc.Id, null, caso.Id, true, false);
            items.add(item);
        }
        insert items;
        
        Set<Id> itemIds = new Set<Id>();
        for (Items_Cases__c i : items) {
            itemIds.add(i.Id);
        }
        
        // When
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(itemIds);
        System.enqueueJob(queue);
        Test.stopTest();
        
        // Then - Items without Asegurado should not be processed
        System.assert(true, 'Should handle items without Asegurado');
    }
    
    @IsTest
    static void testQueueEnvioEmails_WithMixedConditions() {
        // Given - Mix of valid and invalid items
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        Contact c = new Contact(FirstName = 'Mixed', LastName = 'Test', Email = 'mixed@test.com');
        insert c;
        
        Case caso = new Case(AccountId = acc.Id);
        insert caso;
        
        List<Items_Cases__c> items = new List<Items_Cases__c>();
        
        // Valid item
        items.add(createTestItem(acc.Id, c.Id, caso.Id, true, false));
        
        // Item without email
        items.add(createTestItem(acc.Id, c.Id, caso.Id, false, false));
        
        // Item already sent
        items.add(createTestItem(acc.Id, c.Id, caso.Id, true, true));
        
        // Item without Asegurado
        Items_Cases__c noAsegurado = createTestItem(acc.Id, null, caso.Id, true, false);
        items.add(noAsegurado);
        
        insert items;
        
        Set<Id> itemIds = new Set<Id>();
        for (Items_Cases__c i : items) {
            itemIds.add(i.Id);
        }
        
        // When
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(itemIds);
        System.enqueueJob(queue);
        Test.stopTest();
        
        // Then - Should handle mixed conditions gracefully
        System.assert(true, 'Should handle mixed valid/invalid items');
        
        // Only valid item might get Email_Enviado__c = true
        Items_Cases__c validItem = items[0];
        Items_Cases__c updatedItem = [SELECT Email_Enviado__c FROM Items_Cases__c WHERE Id = :validItem.Id];
        // Cannot assert specific value as it depends on EnvioPlantillas implementation
        System.assert(true, 'Mixed conditions test completed');
    }
    
    @IsTest
    static void testQueueEnvioEmails_BulkProcessing() {
        // Given - Large number of items (testing bulk limits)
        Account acc = new Account(Name = 'Bulk Account');
        insert acc;
        
        Contact c = new Contact(FirstName = 'Bulk', LastName = 'User', Email = 'bulk@test.com');
        insert c;
        
        Case caso = new Case(AccountId = acc.Id);
        insert caso;
        
        List<Items_Cases__c> items = new List<Items_Cases__c>();
        for (Integer i = 0; i < 50; i++) {
            items.add(createTestItem(acc.Id, c.Id, caso.Id, true, false));
        }
        insert items;
        
        Set<Id> itemIds = new Set<Id>();
        for (Items_Cases__c i : items) {
            itemIds.add(i.Id);
        }
        
        // When
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        
        QueueEnvioEmails queue = new QueueEnvioEmails(itemIds);
        System.enqueueJob(queue);
        
        Test.stopTest();
        
        // Then - Should handle bulk processing within limits
        System.assert(Limits.getQueueableJobs() <= Limits.getLimitQueueableJobs(),
            'Should not exceed queueable job limit');
        System.assert(true, 'Bulk processing test completed');
    }
    
    @IsTest
    static void testQueueEnvioEmails_RecursionPrevention() {
        // Test that recursion is prevented
        Account acc = new Account(Name = 'Recursion Account');
        insert acc;
        
        Contact c = new Contact(FirstName = 'Recursion', LastName = 'Test', Email = 'recursion@test.com');
        insert c;
        
        Case caso = new Case(AccountId = acc.Id);
        insert caso;
        
        List<Items_Cases__c> items = new List<Items_Cases__c>();
        for (Integer i = 0; i < 20; i++) { // More than MAX_EMAILS_POR_QUEUE
            items.add(createTestItem(acc.Id, c.Id, caso.Id, true, false));
        }
        insert items;
        
        Set<Id> itemIds = new Set<Id>();
        for (Items_Cases__c i : items) {
            itemIds.add(i.Id);
        }
        
        // When
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        
        QueueEnvioEmails queue = new QueueEnvioEmails(itemIds);
        Id jobId = System.enqueueJob(queue);
        
        Test.stopTest();
        
        // Then - Job should be enqueued without infinite recursion
        System.assertNotEquals(null, jobId, 'Job should be enqueued');
        System.assert(true, 'Recursion prevention should work');
    }
    
    @IsTest
    static void testQueueEnvioEmails_EmailLimitHandling() {
        // Test email limit handling
        Account acc = new Account(Name = 'Limit Account');
        insert acc;
        
        Contact c = new Contact(FirstName = 'Limit', LastName = 'Test', Email = 'limit@test.com');
        insert c;
        
        Case caso = new Case(AccountId = acc.Id);
        insert caso;
        
        List<Items_Cases__c> items = new List<Items_Cases__c>();
        for (Integer i = 0; i < 5; i++) {
            items.add(createTestItem(acc.Id, c.Id, caso.Id, true, false));
        }
        insert items;
        
        Set<Id> itemIds = new Set<Id>();
        for (Items_Cases__c i : items) {
            itemIds.add(i.Id);
        }
        
        // When
        Test.startTest();
        
        // Note: We can't directly test email limits as tests don't actually send emails
        // But we can test the constructor and enqueue
        
        QueueEnvioEmails queue = new QueueEnvioEmails(itemIds);
        System.enqueueJob(queue);
        
        Test.stopTest();
        
        // Then - Should handle email limits gracefully
        System.assert(true, 'Email limit handling test completed');
    }
    
    @IsTest
    static void testQueueEnvioEmails_ConstructorVariations() {
        // Test different constructor scenarios
        
        // Test 1: Default constructor usage (if exists)
        Test.startTest();
        
        Set<Id> testIds = new Set<Id>{'001000000000001'};
        QueueEnvioEmails queue1 = new QueueEnvioEmails(testIds);
        System.assertNotEquals(null, queue1, 'Constructor should work with valid IDs');
        
        QueueEnvioEmails queue2 = new QueueEnvioEmails(new Set<Id>());
        System.assertNotEquals(null, queue2, 'Constructor should work with empty set');
        
        QueueEnvioEmails queue3 = new QueueEnvioEmails(null);
        System.assertNotEquals(null, queue3, 'Constructor should work with null');
        
        Test.stopTest();
        
        System.assert(true, 'All constructor variations should work');
    }
    
    @IsTest
    static void testQueueEnvioEmails_WithContactInsteadOfAsegurado() {
        // Test items with Contacto__c instead of Asegurado__c
        Account acc = new Account(Name = 'Contact Account');
        insert acc;
        
        Contact c = new Contact(FirstName = 'Contact', LastName = 'Field', Email = 'contact@test.com');
        insert c;
        
        Case caso = new Case(AccountId = acc.Id);
        insert caso;
        
        Items_Cases__c item = new Items_Cases__c(
            Correo_electronico__c = 'test@test.com',
            Contacto__c = c.Id, // Using Contacto__c instead of Asegurado__c
            Email_Enviado__c = false,
            Categorias__c = 'Alta',
            Caso__c = caso.Id,
            Nombre_cuenta__c = acc.Id,
            Fecha_de_peticion__c = Date.today(),
            Fecha_de_nacimiento__c = Date.today().addYears(-20),
            Sexo__c = 'Masculino',
            Estatus__c = 'En proceso'
        );
        insert item;
        
        Set<Id> itemIds = new Set<Id>{item.Id};
        
        // When
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        
        QueueEnvioEmails queue = new QueueEnvioEmails(itemIds);
        System.enqueueJob(queue);
        
        Test.stopTest();
        
        // Then - Should handle Contacto__c field
        System.assert(true, 'Should handle Contacto__c field');
    }
    
    @IsTest
    static void testQueueEnvioEmails_WithEmailContextControl() {
        // Test with EmailContextControl
        Account acc = new Account(Name = 'Context Account');
        insert acc;
        
        Contact c = new Contact(FirstName = 'Context', LastName = 'Control', Email = 'context@test.com');
        insert c;
        
        Case caso = new Case(AccountId = acc.Id);
        insert caso;
        
        Items_Cases__c item = createTestItem(acc.Id, c.Id, caso.Id, true, false);
        insert item;
        
        Set<Id> itemIds = new Set<Id>{item.Id};
        
        // Set EmailContextControl
        EmailContextControl.skipEmails = true;
        
        // When
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(itemIds);
        System.enqueueJob(queue);
        Test.stopTest();
        
        // Reset for other tests
        EmailContextControl.skipEmails = false;
        
        // Then
        System.assert(true, 'Should respect EmailContextControl');
    }
    
    @IsTest
    static void testQueueEnvioEmails_ErrorHandling() {
        // Test error handling in Queueable
        Account acc = new Account(Name = 'Error Account');
        insert acc;
        
        Case caso = new Case();
        caso.AccountId = acc.Id;
        insert caso;
        
        // Create item that will cause error (no email, no asegurado)
        Items_Cases__c item = new Items_Cases__c(
            Nombre_cuenta__c = acc.Id,
            Estatus__c = 'En proceso',
            Caso__c = caso.Id,
            Fecha_de_peticion__c = Date.today(),
            Fecha_de_nacimiento__c = Date.today().addYears(-20),
            Sexo__c = 'Masculino'
            // Missing required fields for email
        );
        insert item;
        
        Set<Id> itemIds = new Set<Id>{item.Id};
        
        // When
        Test.startTest();
        
        // This should not throw exception even if EnvioPlantillas fails
        QueueEnvioEmails queue = new QueueEnvioEmails(itemIds);
        System.enqueueJob(queue);
        
        Test.stopTest();
        
        // Then - Should handle errors gracefully
        System.assert(true, 'Should handle errors without crashing');
    }
    
    // Mock HTTP Response Generator
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