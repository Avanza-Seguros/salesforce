@IsTest
private class ContactServiceTest {

    @IsTest
    static void testCreateOnePerItem() {

        Account acc = new Account();
        acc.Name = 'Luxoft Mexico S.A. De C.V.';
        insert acc;
        
        Case caso = new Case();
        caso.AccountId = acc.Id;

        insert caso;
        // 🔹 Crear Items_Cases__c
        List<Items_Cases__c> items = new List<Items_Cases__c>();

        for (Integer i = 0; i < 3; i++) {
            items.add(new Items_Cases__c(
                Nombre__c = 'Juan',
                Apellido_paterno__c = 'Perez',
                Apellido_materno__c = 'Lopez',
                Caso__c = caso.Id,
                Correo_electronico__c = 'test' + i + '@mail.com',
                Fecha_de_peticion__c = Date.today(),
        		Fecha_de_nacimiento__c = Date.today(),
        		Sexo__c = 'Masculino'
            ));
        }

        insert items;

        Test.startTest();
        Map<Id, Contact> result =
            ContactService.processContacts(items);
        Test.stopTest();

        System.assertEquals(
            3,
            result.size(),
            'Debe crear un contacto por cada item'
        );

        for (Contact c : result.values()) {
            System.assertNotEquals(null, c.Id);
        }
    }
}