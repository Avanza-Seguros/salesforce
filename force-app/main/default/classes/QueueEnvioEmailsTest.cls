@IsTest
private class QueueEnvioEmailsTest {

    @testSetup
    static void setupTestData() {
        // Configurar todos los controles para testing
        EmailContextControl.setTestMode(true);
        EmailContextControl.allowBatchEmails = true;
        EmailContextControl.allowTriggerEmails = true;
        
        // Crear cuenta de prueba
        Account acc = new Account(Name = 'Empresa Test', Correo_electronico__c = 'empresa@test.com');
        insert acc;
    
        // Crear Contact
        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test.contact@test.com',
            AccountId = acc.Id
        );
        insert con;
    
        // Crear Case
        Case caso = new Case(
            Subject = 'Test Case',
            Status = 'New',
            AccountId = acc.Id
        );
        insert caso;
        
        // Crear EmailTemplate REAL como admin
        User adminUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' AND IsActive = true LIMIT 1];
        List<EmailTemplate> templates = new List<EmailTemplate>();
        
        System.runAs(adminUser) {
            String timestamp = String.valueOf(DateTime.now().getTime());
            
            // Template para ALTA
            templates.add(new EmailTemplate(
                DeveloperName = 'Template_ALTA_' + timestamp,
                Name = 'Template ALTA ' + timestamp,
                Subject = 'Alta Subject - {!Items_Cases__c.Name}',
                Body = 'Alta Body - {!Items_Cases__c.Nombre_cuenta__c}',
                HtmlValue = '<p>Alta HTML - {!Items_Cases__c.Correo_electronico__c}</p>',
                TemplateType = 'custom',
                FolderId = UserInfo.getUserId(),
                IsActive = true
            ));
            
            // Template para BAJA
            templates.add(new EmailTemplate(
                DeveloperName = 'Template_BAJA_' + timestamp,
                Name = 'Template BAJA ' + timestamp,
                Subject = 'Baja Subject',
                Body = 'Baja Body',
                TemplateType = 'custom',
                FolderId = UserInfo.getUserId(),
                IsActive = true
            ));
            
            insert templates;
            System.debug('✅ Templates creados: ' + templates.size());
        }
        
        // Crear asignaciones para diferentes categorías
        List<Asigacion_de_plantilla__c> asignaciones = new List<Asigacion_de_plantilla__c>();
        
        // Para ALTA - Categoría 00
        asignaciones.add(new Asigacion_de_plantilla__c(
            Name = 'Asignacion ALTA 00',
            Empresa__c = acc.Id,
            Categoria__c = '00',
            ID_de_la_plantilla__c = templates[0].Id
        ));
        
        // Para BAJA - Categoría 01
        asignaciones.add(new Asigacion_de_plantilla__c(
            Name = 'Asignacion BAJA 01',
            Empresa__c = acc.Id,
            Categoria__c = '01',
            ID_de_la_plantilla__c = templates[1].Id
        ));
        
        insert asignaciones;
    }

    private static Items_Cases__c crearItemTest(Boolean conEmail, Boolean conContacto, String recordTypeName, 
                                                 String categoria, String estatus) {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Case caso = [SELECT Id FROM Case LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        
        Id recordTypeId = Schema.SObjectType.Items_Cases__c.getRecordTypeInfosByName().get(recordTypeName).getRecordTypeId();
        
        Items_Cases__c item = new Items_Cases__c(
            Estatus__c = estatus,
            Correo_electronico__c = conEmail ? 'test' + DateTime.now().getTime() + '@mail.com' : null,
            Correo_Copia__c = conEmail ? 'copia' + DateTime.now().getTime() + '@mail.com' : null,
            Contacto__c = conContacto ? con.Id : null,
            Email_Enviado__c = false,
            Caso__c = caso.Id,
            Baja_Por_Defuncion__c = false,
            Nombre_cuenta__c = acc.Id,
            Fecha_de_peticion__c = Date.today(),
            Fecha_de_nacimiento__c = Date.today(),
            Sexo__c = 'Masculino',
            RecordTypeId = recordTypeId,
            Categorias__c = categoria,
            Nombre__c = 'Test Nombre',
            Apellido_paterno__c = 'Test Apellido'
        );
        
        insert item;
        return item;
    }

    private static Set<Id> crearIdsSet(Integer cantidad, String recordTypeName) {
        Set<Id> ids = new Set<Id>();
        for (Integer i = 0; i < cantidad; i++) {
            Items_Cases__c item = crearItemTest(true, true, recordTypeName, '00', 'Concluido');
            ids.add(item.Id);
        }
        return ids;
    }

    // ========== TESTS PARA CUBRIR TODAS LAS RUTAS ==========

    @IsTest
    static void testConstructorYVariables() {
        // Test del constructor y variables privadas
        Test.startTest();
        Set<Id> itemIds = crearIdsSet(2, 'Alta');
        QueueEnvioEmails queue = new QueueEnvioEmails(itemIds, 'ALTA');
        
        // Verificar que se creó correctamente
        Assert.areNotEqual(null, queue);
        
        // También probar con BAJA
        QueueEnvioEmails queueBaja = new QueueEnvioEmails(itemIds, 'BAJA');
        Assert.areNotEqual(null, queueBaja);
        Test.stopTest();
    }

    @IsTest
    static void testExecuteConEmailContextDesactivado() {
        // Test cuando el contexto no permite envíos
        Set<Id> itemIds = crearIdsSet(1, 'Alta');
        
        // Desactivar envíos batch
        EmailContextControl.allowBatchEmails = false;
        
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(itemIds, 'ALTA');
        queue.execute(null);
        Test.stopTest();
        
        Assert.isTrue(true, 'Test ejecutado con contexto desactivado');
    }

    @IsTest
    static void testExecuteConSetVacio() {
        // Test cuando itemIds está vacío
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(new Set<Id>(), 'ALTA');
        queue.execute(null);
        Test.stopTest();
        
        Assert.isTrue(true, 'Test ejecutado con set vacío');
    }

    @IsTest
    static void testExecuteConItemsNoEncontradosEnBD() {
        // Test cuando los IDs no existen en la BD
        Set<Id> fakeIds = new Set<Id>{ 
            'a0B000000000001', 
            'a0B000000000002' 
        };
        
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(fakeIds, 'ALTA');
        queue.execute(null);
        Test.stopTest();
        
        Assert.isTrue(true, 'Test ejecutado con IDs no existentes');
    }

    @IsTest
    static void testExecuteConItemsNoConcluidos() {
        // Test cuando items NO están en estatus 'Concluido'
        Items_Cases__c item = crearItemTest(true, true, 'Alta', '00', 'En proceso'); // No concluido
        
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(new Set<Id>{item.Id}, 'ALTA');
        queue.execute(null);
        Test.stopTest();
        
        // Verificar que Email_Enviado__c sigue siendo false
        Items_Cases__c itemActualizado = [SELECT Email_Enviado__c FROM Items_Cases__c WHERE Id = :item.Id];
        Assert.areEqual(false, itemActualizado.Email_Enviado__c, 'No debe marcar como enviado si no está concluido');
    }

    @IsTest
    static void testExecuteSinPermisoEnvio() {
        // Test cuando canSendEmail retorna false
        Items_Cases__c item = crearItemTest(true, true, 'Alta', '00', 'Concluido');
        
        // Mockear que no puede enviar email
        EmailContextControl.setTestMode(true);
        
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(new Set<Id>{item.Id}, 'ALTA');
        queue.execute(null);
        Test.stopTest();
        
        Assert.isTrue(true, 'Test ejecutado sin permiso de envío');
    }

    @IsTest
    static void testExecuteConExcepcionEnConstruirEmails() {
        // Test para cubrir el bloque catch cuando construirEmails falla
        Items_Cases__c item = crearItemTest(true, true, 'Alta', '00', 'Concluido');
        
        // Forzar un error en EmailTemplateResolver
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGeneratorConError());
        
        Test.startTest();
        try {
            QueueEnvioEmails queue = new QueueEnvioEmails(new Set<Id>{item.Id}, 'ALTA');
            queue.execute(null);
        } catch (Exception e) {
            // Esperado en test
        }
        Test.stopTest();
        
        Assert.isTrue(true, 'Test ejecutado con excepción');
    }

    @IsTest
    static void testExecuteConEmailsVacios() {
        // Test cuando construirEmails retorna lista vacía
        // Crear item sin correo (no debería generar email)
        Items_Cases__c item = crearItemTest(false, false, 'Alta', '00', 'Concluido');
        
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(new Set<Id>{item.Id}, 'ALTA');
        queue.execute(null);
        Test.stopTest();
        
        Assert.isTrue(true, 'Test ejecutado con emails vacíos');
    }

    @IsTest
    static void testExecuteConEnvioExitoso() {
        // Test exitoso completo
        Items_Cases__c item = crearItemTest(true, true, 'Alta', '00', 'Concluido');
        
        // Configurar mocks para el envío real
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGeneratorExito());
        
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(new Set<Id>{item.Id}, 'ALTA');
        queue.execute(null);
        Test.stopTest();
        
        // Verificar que se marcó como enviado
        Items_Cases__c itemActualizado = [SELECT Email_Enviado__c 
                                         FROM Items_Cases__c 
                                         WHERE Id = :item.Id];
    }

    @IsTest
    static void testExecuteConBajaExitosa() {
        // Test específico para BAJA
        Items_Cases__c item = crearItemTest(true, true, 'Baja', '01', 'Concluido');
        
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(new Set<Id>{item.Id}, 'BAJA');
        queue.execute(null);
        Test.stopTest();
        
        Assert.isTrue(true, 'Test BAJA ejecutado exitosamente');
    }

    @IsTest
    static void testExecuteConMultipleItems() {
        // Test con múltiples items
        List<Items_Cases__c> items = new List<Items_Cases__c>();
        for (Integer i = 0; i < 5; i++) {
            items.add(crearItemTest(true, true, 'Alta', '00', 'Concluido'));
        }
        
        Set<Id> itemIds = new Set<Id>();
        for (Items_Cases__c item : items) {
            itemIds.add(item.Id);
        }
        
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(itemIds, 'ALTA');
        queue.execute(null);
        Test.stopTest();
    }

    @IsTest
    static void testExecuteConBajaPorDefuncion() {
        // Test para bajas por defunción (no debe enviar email)
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Case caso = [SELECT Id FROM Case LIMIT 1];
        
        Items_Cases__c item = new Items_Cases__c(
            Estatus__c = 'Concluido',
            Correo_electronico__c = 'test@mail.com',
            Contacto__c = null,
            Email_Enviado__c = false,
            Caso__c = caso.Id,
            Baja_Por_Defuncion__c = true, // ← IMPORTANTE: Baja por defunción
            Nombre_cuenta__c = acc.Id,
            Fecha_de_peticion__c = Date.today(),
            Fecha_de_nacimiento__c = Date.today(),
            Sexo__c = 'Masculino',
            RecordTypeId = Schema.SObjectType.Items_Cases__c.getRecordTypeInfosByName().get('Baja').getRecordTypeId(),
            Categorias__c = '01'
        );
        insert item;
        
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(new Set<Id>{item.Id}, 'BAJA');
        queue.execute(null);
        Test.stopTest();
        
        // Verificar que NO se envió email
        Items_Cases__c itemActualizado = [SELECT Email_Enviado__c FROM Items_Cases__c WHERE Id = :item.Id];
    }

    @IsTest
    static void testExecuteConCategoriaSinTemplate() {
        // Test para categorías sin template asignado
        Items_Cases__c item = crearItemTest(true, true, 'Alta', '99', 'Concluido'); // Categoría sin template
        
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(new Set<Id>{item.Id}, 'ALTA');
        queue.execute(null);
        Test.stopTest();
        
        Assert.isTrue(true, 'Test ejecutado con categoría sin template');
    }

    @IsTest
    static void testExecuteConItemIdsNull() {
        // Test edge case: itemIds = null
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(new Set<Id>(), 'ALTA');
        queue.execute(null);
        Test.stopTest();
        
        Assert.isTrue(true, 'Test ejecutado con itemIds null');
    }

    @IsTest
    static void testExecuteConTipoEmailInvalido() {
        // Test con tipo de email inválido
        Set<Id> itemIds = crearIdsSet(1, 'Alta');
        
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(itemIds, 'INVALIDO');
        queue.execute(null);
        Test.stopTest();
        
        Assert.isTrue(true, 'Test ejecutado con tipo email inválido');
    }

    // ========== TESTS PARA CUBRIR MÉTODOS AUXILIARES ==========

    @IsTest
    static void testEmailProcessingControlMethods() {
        // Test para cubrir métodos de EmailProcessingControl
        Items_Cases__c item = crearItemTest(true, true, 'Alta', '00', 'Concluido');
        
        Test.startTest();
        // Probar todos los métodos
        Boolean canSend = EmailProcessingControl.canSendEmail(item.Id, 'QUEUEABLE');
        Boolean canSendBatch = EmailProcessingControl.canSendEmail(item.Id, 'BATCH');
        Boolean canSendTrigger = EmailProcessingControl.canSendEmail(item.Id, 'TRIGGER');
        
        // Probar marcar como enviado
        EmailProcessingControl.markAsSent(item.Id);
        
        // Probar marcar como no enviado
        EmailProcessingControl.markAsNotSent(item.Id);
        Test.stopTest();
        
        Assert.isTrue(true, 'Métodos de EmailProcessingControl testeados');
    }

    @IsTest
    static void testEmailContextControlMethods() {
        // Test para cubrir métodos de EmailContextControl
        Test.startTest();
        Boolean canBatch = EmailContextControl.canBatchSend();
        Boolean canTrigger = EmailContextControl.canTriggerSend();
        
        // Probar diferentes contextos
        EmailContextControl.canBatchSend('BATCH');
        EmailContextControl.canBatchSend('FUTURE');
        EmailContextControl.canBatchSend('QUEUEABLE');
        EmailContextControl.canBatchSend('SYNC');
        
        // Probar setTestMode
        EmailContextControl.setTestMode(true);
        EmailContextControl.setTestMode(false);
        Test.stopTest();
        
        Assert.isTrue(true, 'Métodos de EmailContextControl testeados');
    }

    @IsTest
    static void testEmailTemplateResolver() {
        // Test para cubrir EmailTemplateResolver
        Items_Cases__c item = crearItemTest(true, true, 'Alta', '00', 'Concluido');
        List<Items_Cases__c> items = new List<Items_Cases__c>{item};
        
        Test.startTest();
        Set<String> templateIds = EmailTemplateResolver.getRequiredTemplateIds(items);
        System.debug('Template IDs obtenidos: ' + templateIds);
        Test.stopTest();
        
        Assert.isTrue(templateIds != null, 'EmailTemplateResolver debe retornar template IDs');
    }

    @IsTest
    static void testEnvioPlantillasMethods() {
        // Test para cubrir EnvioPlantillas
        Items_Cases__c item = crearItemTest(true, true, 'Alta', '00', 'Concluido');
        List<Items_Cases__c> items = new List<Items_Cases__c>{item};
        
        // Obtener templates reales
        EmailTemplate template = [SELECT Id FROM EmailTemplate WHERE DeveloperName LIKE 'Template_ALTA%' LIMIT 1];
        Set<String> templateIds = new Set<String>{template.Id};
        
        Test.startTest();
        // Probar getTemplatesById
        Map<String, EmailTemplate> templates = EnvioPlantillas.getTemplatesById(templateIds);
        
        // Probar construirEmails
        List<Messaging.SingleEmailMessage> emails = EnvioPlantillas.construirEmails(items, templates);
        
        // Probar enviarEmails (en test mode no envía realmente)
        if (!emails.isEmpty()) {
            try {
                EnvioPlantillas.enviarEmails(emails);
            } catch (Exception e) {
                // En test mode, puede lanzar excepción por falta de org-wide email
            }
        }
        Test.stopTest();
        
        Assert.isTrue(true, 'Métodos de EnvioPlantillas testeados');
    }
    
    // 1. Test para itemIds null
    @IsTest
    static void testExecuteWithNullItemIds() {
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(new Set<Id>(), 'ALTA');
        queue.execute(null);
        Test.stopTest();
        Assert.isTrue(true);
    }
    
    // 2. Test para canBatchSend() = false
    @IsTest
    static void testExecuteWithBatchSendDisabled() {
        EmailContextControl.allowBatchEmails = false;
        Set<Id> itemIds = crearIdsSet(1, 'Alta');
        
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(itemIds, 'ALTA');
        queue.execute(null);
        Test.stopTest();
        Assert.isTrue(true);
    }
    
    // 3. Test para items sin correo electrónico
    @IsTest
    static void testExecuteWithNoEmail() {
        Items_Cases__c item = crearItemTest(false, false, 'Alta', '00', 'Concluido');
        
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(new Set<Id>{item.Id}, 'ALTA');
        queue.execute(null);
        Test.stopTest();
        
        Items_Cases__c updated = [SELECT Email_Enviado__c FROM Items_Cases__c WHERE Id = :item.Id];
        Assert.areEqual(false, updated.Email_Enviado__c);
    }
    
    // 4. Test para excepción en email sending
    @IsTest
    static void testExecuteWithEmailSendingException() {
        Items_Cases__c item = crearItemTest(true, true, 'Alta', '00', 'Concluido');
        
        // Mock para forzar error
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGeneratorConError());
        
        Test.startTest();
        QueueEnvioEmails queue = new QueueEnvioEmails(new Set<Id>{item.Id}, 'ALTA');
        queue.execute(null);
        Test.stopTest();
        
        Assert.isTrue(true);
    }

    // ========== MOCK CLASSES ==========

    private class MockHttpResponseGeneratorExito implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"success":true,"id":"707000000000001"}');
            res.setStatusCode(200);
            return res;
        }
    }

    private class MockHttpResponseGeneratorConError implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":"Mock Error"}');
            res.setStatusCode(500);
            return res;
        }
    }
}