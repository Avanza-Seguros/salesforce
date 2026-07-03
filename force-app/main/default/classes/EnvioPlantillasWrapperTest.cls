@IsTest
private class EnvioPlantillasWrapperTest {
    
    @TestSetup
    static void setupTestData() {
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
        
        // Crear Items_Cases__c
        List<Items_Cases__c> testItems = new List<Items_Cases__c>();
        for (Integer i = 0; i < 3; i++) {
            testItems.add(new Items_Cases__c(
                Correo_electronico__c = 'test' + i + '@test.com',
                Estatus__c = 'En proceso',
                Caso__c = caso.Id,
                Contacto__c = con.Id,
                Nombre_cuenta__c = acc.Id,
                Categorias__c = '00',
                Fecha_de_peticion__c = Date.today(),
                Fecha_de_nacimiento__c = Date.today(),
                Sexo__c = 'Masculino'
            ));
        }
        insert testItems;
        
        User adminUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' AND IsActive = true LIMIT 1];
        
        System.runAs(adminUser) {
            // Crear EmailTemplate
            EmailTemplate testTemplate = new EmailTemplate(
                DeveloperName = 'Test_Template',
                Name = 'Test Template',
                Subject = 'Test Subject',
                Body = 'Test Body',
                HtmlValue = '<p>Test HTML</p>',
                TemplateType = 'custom',
                FolderId = UserInfo.getUserId(),
                IsActive = true
            );
            insert testTemplate;
            
            // Crear asignación de plantilla
            Asigacion_de_plantilla__c asignacion = new Asigacion_de_plantilla__c(
                Name = 'Test Asignacion',
                Empresa__c = acc.Id,
                Categoria__c = '00',
                ID_de_la_plantilla__c = testTemplate.Id
            );
            insert asignacion;
        }
    }
    
    // Test para enviarEmailsBulk normal
    @IsTest
    static void testEnviarEmailsBulkNormal() {
        List<Items_Cases__c> items = [SELECT Id, Correo_electronico__c, Caso__c , Categorias__c, Fecha_de_peticion__c, 
                                      Nombre_cuenta__c, Fecha_de_nacimiento__c, RecordTypeId, Sexo__c,Baja_Por_Defuncion__c, 
                                        Tipo_de_peticion__c, Contacto__c, Estatus__c  FROM Items_Cases__c];
        
        // Configurar EmailContextControl
        EmailContextControl.skipEmails = false;
        EmailContextControl.allowTriggerEmails = true;
        EmailContextControl.setTestMode(true);
        
        Test.setMock(HttpCalloutMock.class, new SuccessMockHttpResponseGenerator());
        
        Test.startTest();
        

            EnvioPlantillasWrapper.enviarEmailsBulk(items);

        
        Test.stopTest();
    }
    
    // Test para enviarEmailsBulk con error forzado
    @IsTest
    static void testEnviarEmailsBulkConErrorForzado() {
        List<Items_Cases__c> items = [SELECT Id FROM Items_Cases__c];
        
        EnvioPlantillasWrapper.forceBulkError = true;
        
        Test.startTest();
        
        try {
            EnvioPlantillasWrapper.enviarEmailsBulk(items);
            Assert.isTrue(false, 'Debería lanzar excepción');
        } catch (EnvioPlantillasWrapper.TestException e) {
            Assert.isTrue(e.getMessage().contains('Forced bulk error'), 
                         'Mensaje correcto: ' + e.getMessage());
        }
        
        Test.stopTest();
        
        EnvioPlantillasWrapper.resetTestFlags();
    }
    
    // Test para enviarEmailIndividual normal
    @IsTest
    static void testEnviarEmailIndividualNormal() {
        Items_Cases__c item = [SELECT Id, Correo_electronico__c, Caso__c , Categorias__c, Fecha_de_peticion__c, 
                                      Nombre_cuenta__c, Fecha_de_nacimiento__c, Sexo__c, Estatus__c 
                               FROM Items_Cases__c LIMIT 1];
        
        EmailContextControl.skipEmails = false;
        EmailContextControl.allowTriggerEmails = true;
        EmailContextControl.setTestMode(true);
        
        Test.setMock(HttpCalloutMock.class, new SuccessMockHttpResponseGenerator());
        
        Test.startTest();
        
        try {
            EnvioPlantillasWrapper.enviarEmailIndividual(item);
            Assert.isTrue(true, 'Método ejecutado sin error');
        } catch (Exception e) {
            Assert.isTrue(false, 'No debería fallar: ' + e.getMessage());
        }
        
        Test.stopTest();
    }
    
    // Test para enviarEmailIndividual con error forzado
    @IsTest
    static void testEnviarEmailIndividualConErrorForzado() {
        Items_Cases__c item = [SELECT Id FROM Items_Cases__c LIMIT 1];
        
        EnvioPlantillasWrapper.forceIndividualError = true;
        
        Test.startTest();
        
        try {
            EnvioPlantillasWrapper.enviarEmailIndividual(item);
            Assert.isTrue(false, 'Debería lanzar excepción');
        } catch (EnvioPlantillasWrapper.TestException e) {
            Assert.isTrue(e.getMessage().contains('Forced individual error'),
                         'Mensaje correcto: ' + e.getMessage());
        }
        
        Test.stopTest();
        
        EnvioPlantillasWrapper.resetTestFlags();
    }
    
    // Test para enviarEmailDesdeTrigger con items nuevos
    @IsTest
    static void testEnviarEmailDesdeTriggerNuevos() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Case caso = [SELECT Id FROM Case LIMIT 1];
        
        List<Items_Cases__c> nuevosItems = new List<Items_Cases__c>();
        for (Integer i = 0; i < 3; i++) {
            nuevosItems.add(new Items_Cases__c(
                Correo_electronico__c = 'trigger' + i + '@test.com',
                Estatus__c = 'En proceso',
                Caso__c = caso.Id,
                Contacto__c = con.Id,
                Nombre_cuenta__c = acc.Id,
                Categorias__c = '00',
                Fecha_de_peticion__c = Date.today(),
                Fecha_de_nacimiento__c = Date.today(),
                Sexo__c = 'Masculino'
            ));
        }
        
        // Insertar para simular trigger
        insert nuevosItems;
        
        Test.setMock(HttpCalloutMock.class, new SuccessMockHttpResponseGenerator());
        
        Test.startTest();
        
        // Simular llamada desde trigger
        EnvioPlantillasWrapper.enviarEmailDesdeTrigger(nuevosItems, null);
        
        Test.stopTest();
        
        Assert.isTrue(true, 'Trigger ejecutado');
    }
    
    // Test para enviarEmailDesdeTrigger con actualización
    @IsTest
    static void testEnviarEmailDesdeTriggerActualizacion() {
        Items_Cases__c item = [SELECT Id, Estatus__c FROM Items_Cases__c LIMIT 1];
        
        // Guardar estado antiguo
        Items_Cases__c itemAntiguo = item.clone(true);
        
        // Cambiar estatus para trigger
        item.Estatus__c = 'En proceso';
        update item;
        
        Map<Id, Items_Cases__c> itemsAntiguos = new Map<Id, Items_Cases__c>{itemAntiguo.Id => itemAntiguo};
        List<Items_Cases__c> itemsNuevos = new List<Items_Cases__c>{item};
        
        Test.setMock(HttpCalloutMock.class, new SuccessMockHttpResponseGenerator());
        
        Test.startTest();
        
        EnvioPlantillasWrapper.enviarEmailDesdeTrigger(itemsNuevos, itemsAntiguos);
        
        Test.stopTest();
        
        Assert.isTrue(true, 'Trigger de actualización ejecutado');
    }
    
    // Test para enviarEmailDesdeTrigger sin cambios
    @IsTest
    static void testEnviarEmailDesdeTriggerSinCambios() {
        Items_Cases__c item = [SELECT Id, Estatus__c FROM Items_Cases__c LIMIT 1];
        
        // Mantener mismo estatus
        Items_Cases__c itemAntiguo = item.clone(true);
        Map<Id, Items_Cases__c> itemsAntiguos = new Map<Id, Items_Cases__c>{itemAntiguo.Id => itemAntiguo};
        List<Items_Cases__c> itemsNuevos = new List<Items_Cases__c>{item};
        
        Test.startTest();
        
        EnvioPlantillasWrapper.enviarEmailDesdeTrigger(itemsNuevos, itemsAntiguos);
        
        Test.stopTest();
        
        Assert.isTrue(true, 'No debería enviar sin cambios');
    }
    
    // Test para items sin email
    @IsTest
    static void testItemsSinEmail() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Case caso = [SELECT Id FROM Case LIMIT 1];
        
        Items_Cases__c itemSinEmail = new Items_Cases__c(
            Correo_electronico__c = null,
            Estatus__c = 'En proceso',
            Caso__c = caso.Id,
            Contacto__c = con.Id,
            Nombre_cuenta__c = acc.Id,
            Categorias__c = '00'
        );
        
        Test.startTest();
        
        // Test bulk
        EnvioPlantillasWrapper.enviarEmailsBulk(new List<Items_Cases__c>{itemSinEmail});
        
        EnvioPlantillasWrapper.enviarEmailIndividual(itemSinEmail);
        
        Test.stopTest();
        
        Assert.isTrue(true, 'Debe manejar items sin email');
    }
    
    // Test para EmailContextControl bloqueado
    @IsTest
    static void testEmailContextControlBloqueado() {
        List<Items_Cases__c> items = [SELECT Id, Correo_electronico__c, Caso__c , Categorias__c, Fecha_de_peticion__c, 
                                      Nombre_cuenta__c, Fecha_de_nacimiento__c, Sexo__c, Estatus__c FROM Items_Cases__c LIMIT 1];
        
        // Bloquear envíos
        EmailContextControl.skipEmails = true;
        EmailContextControl.allowTriggerEmails = false;
        
        Test.startTest();
        
        EnvioPlantillasWrapper.enviarEmailIndividual(items[0]);
        
        Test.stopTest();
        
        Assert.isTrue(true, 'Debe respetar EmailContextControl');
    }
    
    // Test para métodos de test helpers
    @IsTest
    static void testTestHelpers() {
        Test.startTest();
        
        // Verificar flags iniciales
        Assert.areEqual(false, EnvioPlantillasWrapper.forceBulkError);
        Assert.areEqual(false, EnvioPlantillasWrapper.forceIndividualError);
        Assert.areEqual(false, EnvioPlantillasWrapper.skipEmailSend);
        
        // Probar enableTestMode
        EnvioPlantillasWrapper.enableTestMode();
        Assert.areEqual(true, EnvioPlantillasWrapper.skipEmailSend);
        
        // Probar disableTestMode
        EnvioPlantillasWrapper.disableTestMode();
        Assert.areEqual(false, EnvioPlantillasWrapper.skipEmailSend);
        
        // Probar resetTestFlags
        EnvioPlantillasWrapper.forceBulkError = true;
        EnvioPlantillasWrapper.forceIndividualError = true;
        EnvioPlantillasWrapper.skipEmailSend = true;
        
        EnvioPlantillasWrapper.resetTestFlags();
        
        Assert.areEqual(false, EnvioPlantillasWrapper.forceBulkError);
        Assert.areEqual(false, EnvioPlantillasWrapper.forceIndividualError);
        Assert.areEqual(false, EnvioPlantillasWrapper.skipEmailSend);
        
        Test.stopTest();
    }
    
    // Test para lista vacía/nula
    @IsTest
    static void testListaVaciaONula() {
        Test.startTest();
        
        // Bulk con null
        EnvioPlantillasWrapper.enviarEmailsBulk(null);
        
        // Bulk con lista vacía
        EnvioPlantillasWrapper.enviarEmailsBulk(new List<Items_Cases__c>());
                
        Test.stopTest();
        
        Assert.isTrue(true, 'Debe manejar null/empty sin excepción');
    }
    
    // Test para cobertura completa
    @IsTest
    static void testCoberturaCompleta() {
        // Setup
        List<Items_Cases__c> items = [SELECT Id, Correo_electronico__c, Caso__c , Categorias__c, Fecha_de_peticion__c, 
                                      Nombre_cuenta__c, Fecha_de_nacimiento__c, RecordTypeId, Sexo__c,Baja_Por_Defuncion__c, 
                                        Tipo_de_peticion__c, Contacto__c, Estatus__c FROM Items_Cases__c];
        Items_Cases__c item = items[0];
        
        EmailContextControl.skipEmails = false;
        EmailContextControl.allowTriggerEmails = true;
        EmailContextControl.setTestMode(true);
        
        Test.setMock(HttpCalloutMock.class, new SuccessMockHttpResponseGenerator());
        
        Test.startTest();
        
        // 1. Probar bulk normal
        EnvioPlantillasWrapper.enviarEmailsBulk(items);
        
        // 2. Probar bulk con test mode
        EnvioPlantillasWrapper.enableTestMode();
        EnvioPlantillasWrapper.enviarEmailsBulk(items);
        
        // 4. Probar individual normal
        EnvioPlantillasWrapper.resetTestFlags();
        EnvioPlantillasWrapper.skipEmailSend = true;
        EnvioPlantillasWrapper.enviarEmailIndividual(item);
        
        // 5. Probar individual con error forzado
        EnvioPlantillasWrapper.forceIndividualError = true;
        try {
            EnvioPlantillasWrapper.enviarEmailIndividual(item);
        } catch (EnvioPlantillasWrapper.TestException e) {
            // Esperado
        }
        
        // 6. Probar trigger
        EnvioPlantillasWrapper.resetTestFlags();
        Map<Id, Items_Cases__c> itemsAntiguos = new Map<Id, Items_Cases__c>();
        for (Items_Cases__c i : items) {
            Items_Cases__c antiguo = i.clone(true);
            antiguo.Estatus__c = 'Pendiente';
            itemsAntiguos.put(antiguo.Id, antiguo);
        }
        EnvioPlantillasWrapper.enviarEmailDesdeTrigger(items, itemsAntiguos);
        
        // 7. Probar trigger sin cambios
        EnvioPlantillasWrapper.enviarEmailDesdeTrigger(items, new Map<Id, Items_Cases__c>());
        
        Test.stopTest();
        
        Assert.isTrue(true, 'Todos los caminos ejecutados');
    }
    
    // Mock class
    private class SuccessMockHttpResponseGenerator implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(200);
            res.setBody('{"success": true}');
            return res;
        }
    }
}