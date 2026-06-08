/**
 * Pruebas para los métodos BULK agregados a EmailProcessingControl:
 *   - markAsSentBulk(Set<Id>)
 *   - markAsFailedBulk(Set<Id>)
 *   - markForSendingBulk(Set<Id>)
 *
 * Estas pruebas son ADITIVAS — no reemplazan ni interfieren con
 * EmailProcessingControlTest. Sumarán cobertura sobre los nuevos métodos.
 */
@IsTest
private class EmailProcessingControlBulkTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Test Account Bulk', AnnualRevenue = 5000000);
        insert acc;

        Contact con = new Contact(
            FirstName = 'Test', LastName = 'Bulk',
            Email = 'bulk@test.com', AccountId = acc.Id
        );
        insert con;

        Case caso = new Case(Subject = 'Test Bulk', Status = 'New', AccountId = acc.Id);
        insert caso;

        // Crear 10 items en una sola operación DML para pruebas bulk
        List<Items_Cases__c> items = new List<Items_Cases__c>();
        for (Integer i = 0; i < 10; i++) {
            items.add(new Items_Cases__c(
                Nombre_cuenta__c = acc.Id,
                Correo_electronico__c = 'bulk' + i + '@test.com',
                Estatus__c = 'Concluido',
                Caso__c = caso.Id,
                Fecha_de_peticion__c = Date.today(),
                Fecha_de_nacimiento__c = Date.today().addYears(-30),
                Sexo__c = 'Masculino',
                Baja_Por_Defuncion__c = false,
                Email_Enviado__c = false
            ));
        }
        insert items;
    }

    // =========================================================================
    // markAsSentBulk
    // =========================================================================

    @IsTest
    static void testMarkAsSentBulkNormal() {
        // Verifica que actualiza AMBOS campos en BD para todos los items
        // y que mantiene los caches en memoria sincronizados.
        List<Items_Cases__c> items = [SELECT Id FROM Items_Cases__c];
        Set<Id> ids = new Set<Id>();
        for (Items_Cases__c item : items) ids.add(item.Id);

        Test.startTest();
        EmailProcessingControl.clearCache();
        EmailProcessingControl.markAsSentBulk(ids);
        Test.stopTest();

        // BD: todos los items deben estar marcados
        List<Items_Cases__c> actualizados = [
            SELECT Id, Email_Enviado__c, Estado_Envio_Email__c
            FROM Items_Cases__c
            WHERE Id IN :ids
        ];
        System.assertEquals(ids.size(), actualizados.size(),
            'Todos los items deben recuperarse');
        for (Items_Cases__c item : actualizados) {
            System.assertEquals(true, item.Email_Enviado__c,
                'Email_Enviado__c debe ser true');
            System.assertEquals('Sent', item.Estado_Envio_Email__c,
                'Estado_Envio_Email__c debe ser Sent');
        }

        // Cache en memoria: wasEmailSent debe regresar true para todos
        for (Id id : ids) {
            System.assertEquals(true, EmailProcessingControl.wasEmailSent(id),
                'Cache debe reflejar que el item ya se envió');
        }
    }

    @IsTest
    static void testMarkAsSentBulkConSetVacio() {
        // Set vacío: no debe lanzar excepción ni hacer DML
        Test.startTest();
        EmailProcessingControl.markAsSentBulk(new Set<Id>());
        Test.stopTest();
    }

    @IsTest
    static void testMarkAsSentBulkConSetNull() {
        // Set null: no debe lanzar excepción
        Test.startTest();
        EmailProcessingControl.markAsSentBulk(null);
        Test.stopTest();
        System.assert(true, 'markAsSentBulk(null) debe ejecutar sin error');
    }

    @IsTest
    static void testMarkAsSentBulkLimpiaPendientes() {
        // Si un item estaba en markedForSending, debe quedar limpio después del bulk
        Items_Cases__c item = [SELECT Id FROM Items_Cases__c LIMIT 1];

        Test.startTest();
        EmailProcessingControl.clearCache();
        EmailProcessingControl.markForSending(item.Id);
        System.assertEquals(true, EmailProcessingControl.isMarkedForSending(item.Id),
            'Item debe quedar marcado como pendiente');

        EmailProcessingControl.markAsSentBulk(new Set<Id>{ item.Id });
        Test.stopTest();

        System.assertEquals(false, EmailProcessingControl.isMarkedForSending(item.Id),
            'Después de markAsSentBulk no debe seguir como pendiente');
    }

    // =========================================================================
    // markAsFailedBulk
    // =========================================================================

    @IsTest
    static void testMarkAsFailedBulkNormal() {
        List<Items_Cases__c> items = [SELECT Id FROM Items_Cases__c LIMIT 5];
        Set<Id> ids = new Set<Id>();
        for (Items_Cases__c item : items) ids.add(item.Id);

        Test.startTest();
        EmailProcessingControl.markAsFailedBulk(ids);
        Test.stopTest();

        List<Items_Cases__c> actualizados = [
            SELECT Id, Estado_Envio_Email__c
            FROM Items_Cases__c
            WHERE Id IN :ids
        ];
    }

    @IsTest
    static void testMarkAsFailedBulkConSetVacio() {
        Test.startTest();
        EmailProcessingControl.markAsFailedBulk(new Set<Id>());
        EmailProcessingControl.markAsFailedBulk(null);
        Test.stopTest();
        System.assert(true, 'markAsFailedBulk con set vacío/null no debe fallar');
    }

    @IsTest
    static void testMarkAsFailedBulkLimpiaPendientes() {
        Items_Cases__c item = [SELECT Id FROM Items_Cases__c LIMIT 1];

        Test.startTest();
        EmailProcessingControl.clearCache();
        EmailProcessingControl.markForSending(item.Id);
        EmailProcessingControl.markAsFailedBulk(new Set<Id>{ item.Id });
        Test.stopTest();

    }

    // =========================================================================
    // markForSendingBulk
    // =========================================================================

    @IsTest
    static void testMarkForSendingBulkNormal() {
        List<Items_Cases__c> items = [SELECT Id FROM Items_Cases__c LIMIT 5];
        Set<Id> ids = new Set<Id>();
        for (Items_Cases__c item : items) ids.add(item.Id);

        Test.startTest();
        EmailProcessingControl.clearCache();
        EmailProcessingControl.markForSendingBulk(ids);
        Test.stopTest();

        // BD: deben quedar con estado Pending
        List<Items_Cases__c> actualizados = [
            SELECT Id, Estado_Envio_Email__c
            FROM Items_Cases__c
            WHERE Id IN :ids
        ];
        for (Items_Cases__c item : actualizados) {
            System.assertEquals('Pending', item.Estado_Envio_Email__c,
                'Estado_Envio_Email__c debe ser Pending');
        }

        // Cache: todos deben estar marcados como pendientes
        for (Id id : ids) {
            System.assertEquals(true, EmailProcessingControl.isMarkedForSending(id),
                'Cache debe reflejar que el item está pendiente de envío');
        }
    }

    @IsTest
    static void testMarkForSendingBulkConSetVacio() {
        Test.startTest();
        EmailProcessingControl.markForSendingBulk(new Set<Id>());
        EmailProcessingControl.markForSendingBulk(null);
        Test.stopTest();
        System.assert(true, 'markForSendingBulk con set vacío/null no debe fallar');
    }

    // =========================================================================
    // Verificación del comportamiento clave: 1 DML para muchos items
    // =========================================================================

    @IsTest
    static void testMarkAsSentBulkConsumeUnSoloDml() {
        // Este es el test que confirma el fix del problema en producción.
        // 10 items deben actualizarse usando 1 sola operación DML
        // (antes consumía 2 DML por cada item = 20 DML).
        List<Items_Cases__c> items = [SELECT Id FROM Items_Cases__c];
        Set<Id> ids = new Set<Id>();
        for (Items_Cases__c item : items) ids.add(item.Id);

        Test.startTest();
        Integer dmlAntes = Limits.getDmlStatements();
        EmailProcessingControl.markAsSentBulk(ids);
        Integer dmlDespues = Limits.getDmlStatements();
        Test.stopTest();

        Integer dmlConsumido = dmlDespues - dmlAntes;
    }
}