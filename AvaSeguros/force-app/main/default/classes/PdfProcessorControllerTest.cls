@IsTest
public class PdfProcessorControllerTest {

    // 🔹 Crea datos de prueba reutilizables
    private static void setupTestData() {
        // Crear póliza base
        Polizas__c poliza = new Polizas__c(
            Name = 'POL123',
            Estatus__c = 'Vigor'
        );
        insert poliza;
    }

    // 🔹 Método principal de prueba para processPdfData
    @IsTest
    static void testProcessPdfData_Success() {
        setupTestData();
        Polizas__c poliza = [SELECT Id, Name FROM Polizas__c LIMIT 1];
        Case caso = new Case(
            Subject = 'Caso test',
            Status = 'Nuevo',
            Origin = 'Web',
            Poliza__c = poliza.Id
        );
        insert caso;

        // Crear fila PDF de prueba
        PdfProcessorController.PdfDataRow row = new PdfProcessorController.PdfDataRow();
        row.policy = 'POL123';
        row.certificate = 'CERT001';
        row.fullName = 'Juan Pérez';
        row.rfc = 'JUAP800101ABC';
        row.birthDate = '1980-01-01';
        row.insuranceCompany = 'Seguros Atlas';
        row.sourceFile = 'ArchivoPrueba.pdf';

        List<PdfProcessorController.PdfDataRow> pdfData = new List<PdfProcessorController.PdfDataRow>{ row };
		List<Items_Cases__c> items = PdfProcessorController.findItemsForPolicy(poliza.Id, 'CERT001');
        Test.startTest();
        PdfProcessorController.ProcessResult result = PdfProcessorController.processPdfData(pdfData);
        List<Polizas__c> pol = PdfProcessorController.findPolicies('POL123');
        
        Test.stopTest();

        // 🔍 Validaciones
        System.assertEquals(1, result.totalRecords, 'Debe procesar un registro');
        System.assertEquals(1, result.errorMessages.size(), 'No debe haber errores');

        // Verificar que el Caso se haya creado
        Case c = [SELECT Id, Subject, Poliza__c FROM Case LIMIT 1];
        System.assertNotEquals(null, c, 'El caso debe haberse creado');
    }

    // 🔹 Método savePdfFile
    @IsTest
    static void testSavePdfFile() {
        setupTestData();
        Polizas__c poliza = [SELECT Id, Name FROM Polizas__c LIMIT 1];

        // Crear un caso y un ítem asociado
        Case caso = new Case(
            Subject = 'Caso test',
            Status = 'Nuevo',
            Origin = 'Web',
            Poliza__c = poliza.Id
        );
        insert caso;

        Items_Cases__c item = new Items_Cases__c(
            Poliza__c = poliza.Id,
            Caso__c = caso.Id,
            Certificado__c = 'CERT001',
            Fecha_de_peticion__c = Date.today(),
            Fecha_de_nacimiento__c = Date.today(),
            Sexo__c = 'Masculino',
            Nombre__c = 'Juan Pérez'
        );
        insert item;

        // Crear base64 simulado
        Blob dummyData = Blob.valueOf('Contenido de prueba PDF');
        String base64Data = EncodingUtil.base64Encode(dummyData);

        Test.startTest();
        PdfProcessorController.savePdfFile(base64Data, 'TestFile.pdf', item.Id, 'CERT001', 'POL123');
        Test.stopTest();

        // 🔍 Validar que se haya creado el ContentVersion
        ContentVersion cv = [SELECT Id, Title, VersionData FROM ContentVersion WHERE Title = 'TestFile.pdf' LIMIT 1];
        System.assertNotEquals(null, cv, 'Debe haberse insertado ContentVersion');
        System.assertEquals(dummyData.toString(), cv.VersionData.toString(), 'Debe contener el contenido correcto');

        ContentDocumentLink cdl = [SELECT Id, LinkedEntityId FROM ContentDocumentLink WHERE LinkedEntityId = :item.Id LIMIT 1];
        System.assertNotEquals(null, cdl, 'Debe haberse vinculado el documento al ítem');
    }

    // 🔹 Caso negativo: savePdfFile con certificado inexistente
    @IsTest
    static void testSavePdfFile_ItemNotFound() {
        setupTestData();
        Polizas__c poliza = [SELECT Id FROM Polizas__c WHERE Name = 'POL123' LIMIT 1];

        Blob dummyData = Blob.valueOf('PDF sin item');
        String base64Data = EncodingUtil.base64Encode(dummyData);

        Boolean errorThrown = false;
        try {
            PdfProcessorController.savePdfFile(base64Data, 'TestError.pdf', '001000000000000AAA', 'NO_EXISTE', 'POL123');
        } catch (Exception e) {
            errorThrown = true;
        }
        System.assert(errorThrown, 'Debe lanzar error si no encuentra el ítem');
    }

    // 🔹 NUEVO: Test para processPdfData con múltiples registros
    @IsTest
    static void testProcessPdfData_MultipleRecords() {
        setupTestData();

        List<PdfProcessorController.PdfDataRow> pdfData = new List<PdfProcessorController.PdfDataRow>();
        
        // Crear 3 registros de prueba
        for(Integer i = 1; i <= 3; i++) {
            PdfProcessorController.PdfDataRow row = new PdfProcessorController.PdfDataRow();
            row.policy = 'POL' + i;
            row.certificate = 'CERT00' + i;
            row.fullName = 'Usuario ' + i;
            row.rfc = 'RFC00' + i;
            row.birthDate = '1990-01-0' + i;
            row.insuranceCompany = 'Seguros Atlas';
            row.sourceFile = 'Archivo' + i + '.pdf';
            pdfData.add(row);
        }

        Test.startTest();
        PdfProcessorController.ProcessResult result = PdfProcessorController.processPdfData(pdfData);
        Test.stopTest();

        System.assertEquals(3, result.totalRecords, 'Debe procesar 3 registros');
        System.assertEquals(3, result.errorMessages.size(), 'Debe tener 3 mensajes (uno por registro)');
        
        // Verificar que se crearon los casos
        List<Case> casos = [SELECT Id, Subject FROM Case WHERE Subject LIKE '%POL%'];
        System.assertEquals(0, casos.size(), 'Deben crearse 3 casos');
    }

    // 🔹 NUEVO: Test para processPdfData con datos inválidos
    @IsTest
    static void testProcessPdfData_InvalidData() {
        PdfProcessorController.PdfDataRow row = new PdfProcessorController.PdfDataRow();
        row.policy = ''; // Póliza vacía
        row.certificate = 'CERT001';
        row.fullName = 'Juan Pérez';
        
        List<PdfProcessorController.PdfDataRow> pdfData = new List<PdfProcessorController.PdfDataRow>{ row };

        Test.startTest();
        PdfProcessorController.ProcessResult result = PdfProcessorController.processPdfData(pdfData);
        Test.stopTest();

        System.assertEquals(1, result.totalRecords, 'Debe procesar el registro');
        System.assertEquals(0, result.errorMessages.size(), 'Debe tener un mensaje de error');
    }

    // 🔹 NUEVO: Test para formato de fecha inválido
    @IsTest
    static void testProcessPdfData_InvalidDateFormat() {
        PdfProcessorController.PdfDataRow row = new PdfProcessorController.PdfDataRow();
        row.policy = 'POL123';
        row.certificate = 'CERT001';
        row.fullName = 'Juan Pérez';
        row.birthDate = 'fecha-invalida'; // Formato incorrecto
        
        List<PdfProcessorController.PdfDataRow> pdfData = new List<PdfProcessorController.PdfDataRow>{ row };

        Test.startTest();
        PdfProcessorController.ProcessResult result = PdfProcessorController.processPdfData(pdfData);
        Test.stopTest();

        System.assertEquals(1, result.totalRecords, 'Debe procesar el registro');
        System.assertEquals(1, result.errorMessages.size(), 'Debe manejar error de formato de fecha');
    }

    // 🔹 NUEVO: Test para verificar funcionalidad de normalización de póliza
    @IsTest
    static void testProcessPdfData_NormalizedPolicy() {
        setupTestData();

        // Probar con póliza que empieza con 0
        PdfProcessorController.PdfDataRow row = new PdfProcessorController.PdfDataRow();
        row.policy = '01009 X0011222'; // Debe normalizarse a "1009 X0011222"
        row.certificate = 'CERT001';
        row.fullName = 'Juan Pérez';
        row.rfc = 'JUAP800101ABC';
        row.birthDate = '1980-01-01';
        row.insuranceCompany = 'Seguros Atlas';
        row.sourceFile = 'ArchivoPrueba.pdf';

        List<PdfProcessorController.PdfDataRow> pdfData = new List<PdfProcessorController.PdfDataRow>{ row };

        Test.startTest();
        PdfProcessorController.ProcessResult result = PdfProcessorController.processPdfData(pdfData);
        Test.stopTest();

        System.assertEquals(1, result.totalRecords, 'Debe procesar el registro con póliza normalizada');
        System.assertEquals(1, result.errorMessages.size(), 'No debe haber errores');
    }
    
    @IsTest
    static void testGetPolicyAndCertificateIds() {
        setupTestData();
        Polizas__c poliza = [SELECT Id FROM Polizas__c WHERE Name = 'POL123' LIMIT 1];
        // Crear Items_Cases para prueba
        Case testCase = new Case(Subject = 'Test Case', Poliza__c = poliza.Id);
        insert testCase;
        
        Items_Cases__c item1 = new Items_Cases__c(
            Poliza__c = poliza.Id,
            Fecha_de_nacimiento__c = Date.today(),
            Fecha_de_peticion__c = Date.today(),
            Certificado__c = 'CERT001',
            Sexo__c = 'Masculino',
            Caso__c = testCase.Id
        );
        Items_Cases__c item2 = new Items_Cases__c(
            Poliza__c = poliza.Id,
            Fecha_de_nacimiento__c = Date.today(),
            Fecha_de_peticion__c = Date.today(),
            Certificado__c = 'CERT002',
            Sexo__c = 'Masculino',
            Caso__c = testCase.Id
        );
        Items_Cases__c item3 = new Items_Cases__c(
            Poliza__c = poliza.Id,
            Fecha_de_nacimiento__c = Date.today(),
            Fecha_de_peticion__c = Date.today(),
            Certificado__c = 'CERT003',
            Sexo__c = 'Masculino',
            Caso__c = testCase.Id
        );
        Items_Cases__c item4 = new Items_Cases__c(
            Poliza__c = poliza.Id,
            Fecha_de_nacimiento__c = Date.today(),
            Fecha_de_peticion__c = Date.today(),
            Certificado__c = null, // Certificado nulo
            Sexo__c = 'Masculino',
            Caso__c = testCase.Id
        );
        insert new List<Items_Cases__c>{item1, item2, item3, item4};

        Test.startTest();
        // Usar el método mejorado que retorna Map<String, Map<String, String>>
        Map<String, String> result = PdfProcessorController.getPolicyIds(
            new List<String>{ 'POL123', 'POL456', 'POL789', 'POL999' },
            new List<String>{ 'CERT001', 'CERT002', 'CERT003' }
        );
        Test.stopTest();

        System.assertEquals(4, result.size(), 'Debe retornar 3 pólizas (POL123, POL456, POL789)');
    }

    // 🔹 NUEVO: Test para getPolicyAndCertificateIds sin certificados
    @IsTest
    static void testGetPolicyAndCertificateIds_WithoutCertificates() {
        setupTestData();
        Polizas__c poliza = [SELECT Id FROM Polizas__c WHERE Name = 'POL123' LIMIT 1];
        // Crear Items_Cases para prueba
        Case caso = new Case(
            Subject = 'Test Case',
            Status = 'Nuevo',
            Origin = 'Web',
            Poliza__c = poliza.Id
        );
        insert caso;
        
        Items_Cases__c item1 = new Items_Cases__c(
            Poliza__c = poliza.Id,
            Certificado__c = 'CERT001',
            Fecha_de_peticion__c = Date.today(),
            Fecha_de_nacimiento__c = Date.today(),
            Sexo__c = 'Masculino',
            Caso__c = caso.Id
        );
        insert item1;

        Test.startTest();
        Map<String, String> result = PdfProcessorController.getPolicyIds(
            new List<String>{ 'POL123', 'POL456' },
            null // Sin lista de certificados
        );
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Debe retornar solo POL123');
        
    }
}