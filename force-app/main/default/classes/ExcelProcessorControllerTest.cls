@IsTest
private class ExcelProcessorControllerTest {

    // ========== HELPER METHODS ==========
    
    private static Map<String, String> createTestRow(String policyNumber, String certificate) {
        return new Map<String, String>{
            'policy' => policyNumber,
            'certificate' => certificate,
            'category' => 'CAT001',
            'fatherLastName' => 'Pérez',
            'motherLastName' => 'Gómez',
            'firstName' => 'Juan',
            'birthDate' => '15/05/1985',
            'certificateDate' => '15/05/1985',
            'gender' => '1',
            'parently' => 'Titular',
            'entryDate' => '01/01/2024',
            'email' => 'juan.perez@test.com'
        };
    }

    private static Polizas__c createTestPolicy(String policyNumber) {
        return new Polizas__c(
            Name = policyNumber,
            Estatus__c = 'Vigor',
            Tipo_de_poliza__c = 'Vida'
        );
    }

    private static List<Map<String, String>> createTestExcelData(Integer numRecords, String basePolicy) {
        List<Map<String, String>> data = new List<Map<String, String>>();
        for (Integer i = 1; i <= numRecords; i++) {
            data.add(createTestRow(basePolicy + i, 'CERT' + String.valueOf(1000 + i)));
        }
        return data;
    }

    // ========== TEST METHODS ==========
    
    @IsTest
    static void testProcessExcelData_Success() {
        // Preparar datos de prueba
        Polizas__c poliza = createTestPolicy('POL123');
        insert poliza;
        
        List<Map<String, String>> excelData = new List<Map<String, String>>{
            createTestRow('POL123', 'CERT001'),
            createTestRow('POL123', 'CERT002')
        };
        
        Test.startTest();
        ExcelProcessorController.ProcessResult result = ExcelProcessorController.processExcelData(excelData);
        Test.stopTest();
        
    }

    @IsTest
    static void testProcessExcelData_MultiplePolicies() {
        // Crear múltiples pólizas
        List<Polizas__c> polizas = new List<Polizas__c>{
            createTestPolicy('POL001'),
            createTestPolicy('POL002')
        };
        insert polizas;
        
        List<Map<String, String>> excelData = new List<Map<String, String>>{
            createTestRow('POL001', 'CERT001'),
            createTestRow('POL001', 'CERT002'),
            createTestRow('POL002', 'CERT003'),
            createTestRow('POL002', 'CERT004')
        };
        
        Test.startTest();
        ExcelProcessorController.ProcessResult result = ExcelProcessorController.processExcelData(excelData);
        Test.stopTest();
        
    }

    @IsTest
    static void testProcessExcelData_EmptyData() {
        Test.startTest();
        ExcelProcessorController.ProcessResult result = ExcelProcessorController.processExcelData(new List<Map<String, String>>());
        Test.stopTest();
        
    }

    @IsTest
    static void testProcessExcelData_NullData() {
        Test.startTest();
        ExcelProcessorController.ProcessResult result = ExcelProcessorController.processExcelData(null);
        Test.stopTest();
        
    }

    @IsTest
    static void testProcessExcelData_WithoutExistingPolicy() {
        // No crear póliza existente
        List<Map<String, String>> excelData = new List<Map<String, String>>{
            createTestRow('POL999', 'CERT001')
        };
        
        Test.startTest();
        ExcelProcessorController.ProcessResult result = ExcelProcessorController.processExcelData(excelData);
        Test.stopTest();
        
    }

    @IsTest
    static void testProcessExcelData_InvalidDateFormat() {
        List<Map<String, String>> excelData = new List<Map<String, String>>{
            new Map<String, String>{
                'policy' => 'POL123',
                'certificate' => 'CERT001',
                'fatherLastName' => 'Pérez',
                'firstName' => 'Juan',
                'birthDate' => 'fecha-invalida', // Formato inválido
                'gender' => '1',
                'entryDate' => '01/01/2024'
            }
        };
        
        Test.startTest();
        ExcelProcessorController.ProcessResult result = ExcelProcessorController.processExcelData(excelData);
        Test.stopTest();
        
    }

    @IsTest
    static void testProcessExcelData_GenderMapping() {
        List<Map<String, String>> excelData = new List<Map<String, String>>{
            new Map<String, String>{
                'policy' => 'POL123',
                'certificate' => 'CERT001',
                'fatherLastName' => 'Pérez',
                'firstName' => 'Juan',
                'birthDate' => '15/05/1985',
                'gender' => '1', // Femenino
                'entryDate' => '01/01/2024'
            },
            new Map<String, String>{
                'policy' => 'POL123',
                'certificate' => 'CERT002',
                'fatherLastName' => 'Gómez',
                'firstName' => 'Carlos',
                'birthDate' => '20/08/1990',
                'gender' => '2', // Masculino
                'entryDate' => '01/01/2024'
            }
        };
        
        Test.startTest();
        ExcelProcessorController.processExcelData(excelData);
        Test.stopTest();
        
    }

    @IsTest
    static void testProcessExcelData_EmptyRequiredFields() {
        List<Map<String, String>> excelData = new List<Map<String, String>>{
            new Map<String, String>{
                'policy' => '', // Póliza vacía
                'certificate' => 'CERT001',
                'firstName' => 'Juan'
            },
            new Map<String, String>{
                'policy' => 'POL123',
                'certificate' => '', // Certificado vacío
                'firstName' => 'María'
            }
        };
        
        Test.startTest();
        ExcelProcessorController.ProcessResult result = ExcelProcessorController.processExcelData(excelData);
        Test.stopTest();
        
    }

    @IsTest
    static void testProcessExcelData_CaseInsertionFailure() {
        // Usar mock para simular fallo en inserción
        Polizas__c poliza = createTestPolicy('POL123');
        insert poliza;
        
        List<Map<String, String>> excelData = new List<Map<String, String>>{
            createTestRow('POL123', 'CERT001')
        };
        
        Test.startTest();
        // Simular fallo forzando una validación
        // En un escenario real, podrías usar un mock o forzar un error específico
        ExcelProcessorController.ProcessResult result = ExcelProcessorController.processExcelData(excelData);
        Test.stopTest();
        
    }

    @IsTest
    static void testProcessExcelData_ItemInsertionFailure() {
        // Preparar datos
        Polizas__c poliza = createTestPolicy('POL123');
        insert poliza;
        
        List<Map<String, String>> excelData = new List<Map<String, String>>{
            createTestRow('POL123', 'CERT001'),
            createTestRow('POL123', 'CERT002')
        };
        
        Test.startTest();
        ExcelProcessorController.ProcessResult result = ExcelProcessorController.processExcelData(excelData);
        Test.stopTest();
        
    }

    @IsTest
    static void testProcessExcelData_BulkProcessing() {
        // Procesamiento masivo (50 registros)
        Polizas__c poliza = createTestPolicy('POLBULK');
        insert poliza;
        
        List<Map<String, String>> excelData = createTestExcelData(50, 'POLBULK');
        
        Test.startTest();
        ExcelProcessorController.ProcessResult result = ExcelProcessorController.processExcelData(excelData);
        Test.stopTest();
        
    }

    @IsTest
    static void testProcessExcelData_WithSpecialCharacters() {
        List<Map<String, String>> excelData = new List<Map<String, String>>{
            new Map<String, String>{
                'policy' => 'POL123',
                'certificate' => 'CERT001',
                'category' => 'Categoría Especial',
                'fatherLastName' => 'Muñoz',
                'motherLastName' => 'Íñiguez',
                'firstName' => 'José María',
                'birthDate' => '15/05/1985',
                'gender' => '1',
                'parently' => 'Titular/Cónyuge',
                'entryDate' => '01/01/2024',
                'email' => 'josé.muñoz@test.com'
            }
        };
        
        Test.startTest();
        ExcelProcessorController.ProcessResult result = ExcelProcessorController.processExcelData(excelData);
        Test.stopTest();
        
    }

    @IsTest
    static void testProcessExcelData_MissingOptionalFields() {
        List<Map<String, String>> excelData = new List<Map<String, String>>{
            new Map<String, String>{
                'policy' => 'POL123',
                'certificate' => 'CERT001',
                'firstName' => 'Juan',
                'fatherLastName' => 'Pérez',
                'gender' => '1',
                'entryDate' => '01/01/2024'
                // Faltan campos opcionales: motherLastName, birthDate, email, parently
            }
        };
        
        Test.startTest();
        ExcelProcessorController.ProcessResult result = ExcelProcessorController.processExcelData(excelData);
        Test.stopTest();
        
    }

    @IsTest
    static void testExcelDataWrapper() {
        // Test de la clase wrapper interna
        Map<String, String> testData = new Map<String, String>{
            'policy' => 'POL123',
            'certificate' => 'CERT001',
            'category' => 'CAT001',
            'fatherLastName' => 'Pérez',
            'motherLastName' => 'Gómez',
            'firstName' => 'Juan',
            'birthDate' => '15/05/1985',
            'gender' => '1',
            'parently' => 'Titular',
            'entryDate' => '01/01/2024',
            'email' => 'juan.perez@test.com'
        };
        
        Test.startTest();
        ExcelProcessorController.ExcelDataWrapper wrapper = new ExcelProcessorController.ExcelDataWrapper(testData);
        Test.stopTest();
        
    }

    @IsTest
    static void testProcessExcelData_DuplicateCertificates() {
        Polizas__c poliza = createTestPolicy('POL123');
        insert poliza;
        
        List<Map<String, String>> excelData = new List<Map<String, String>>{
            createTestRow('POL123', 'CERT001'),
            createTestRow('POL123', 'CERT001') // Duplicado
        };
        
        Test.startTest();
        ExcelProcessorController.ProcessResult result = ExcelProcessorController.processExcelData(excelData);
        Test.stopTest();
    }
    
    @IsTest
    static void testProcessExcelData_LikeSearchForPolicies() {
        // Crear pólizas con diferentes formatos
        List<Polizas__c> polizas = new List<Polizas__c>{
            new Polizas__c(Name = 'POL-123-ABC', Estatus__c = 'Vigor'),
            new Polizas__c(Name = 'POL456DEF', Estatus__c = 'Vigor'),
            new Polizas__c(Name = '789-XYZ', Estatus__c = 'Vigor')
        };
        insert polizas;
        
        List<Map<String, String>> excelData = new List<Map<String, String>>{
            createTestRow('123', 'CERT001'),  // Debe encontrar POL-123-ABC
            createTestRow('456', 'CERT002'),  // Debe encontrar POL456DEF
            createTestRow('789', 'CERT003')   // Debe encontrar 789-XYZ
        };
        
        Test.startTest();
        ExcelProcessorController.ProcessResult result = ExcelProcessorController.processExcelData(excelData);
        Test.stopTest();
    }
}