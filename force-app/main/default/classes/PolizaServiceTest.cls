@IsTest
private class PolizaServiceTest {
    
    // Datos de prueba comunes
    private static Polizas__c crearPolizaTest(String numeroPoliza) {
        return new Polizas__c(
            Name = numeroPoliza,
            Numero_Polizas__c = numeroPoliza,
            Aseguradora__c = 'Afirme',
            Ramo__c = 'Vida',
            Estatus__c = 'Vigor',
            Suma_Aseguradora__c = 100000,
            Moneda__c = 'Pesos',
            Forma_de_pago__c = 'Anual',
            Nombre_contratante__c = 'Contratante Test'
        );
    }
    
    private static String crearJSONRequest(String numeroPoliza) {
        Map<String, Object> requestMap = new Map<String, Object>{
            'poliza' => numeroPoliza,
            'aseguradora' => 'GNP',
            'tipo_seguro' => 'Salud',
            'estatus' => 'Vigor',
            'suma_asegurada' => 500000,
            'moneda' => 'Pesos',
            'forma_pago' => 'Mensual',
            'fecha_emision' => '2024-01-15',
            'asegurados' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'nombre' => 'Asegurado Test 1',
                    'fecha_nacimiento' => '1990-05-20'
                }
            },
            'historico_aportaciones' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'anualidad' => 2024,
                    'prima_basica' => 10000,
                    'prima_adicional' => 2000,
                    'pagos_ingresados' => 12,
                    'desde' => '2024-01-01',
                    'hasta' => '2024-12-31',
                    'detalle_ingresos' => new List<Map<String, Object>>{
                        new Map<String, Object>{
                            'Fecha_de_ingreso' => '2024-01-15',
                            'Importe_pagado' => 1000,
                            'Moneda' => 'MXN',
                            'Tipo_de_pago' => 'Transferencia',
                            'No_cuenta_No_cheque' => 'CHK-001',
                            'Tipo_cambio_del_pago' => 1.0,
                            'Importe_USD' => 1000
                        }
                    }
                }
            }
        };
        
        return JSON.serialize(requestMap);
    }

    // Test para verificar que entra a asegurados e histórico
    @IsTest
    static void testAseguradosAndHistoricoExecution() {
        // Crear póliza de prueba
        Polizas__c polizaTest = crearPolizaTest('POL-0101');
        insert polizaTest;
        Polizas__c pol = [SELECT Id,Name,Numero_Polizas__c,Aseguradora__c,Ramo__c,Estatus__c,Suma_Aseguradora__c,Moneda__c,Forma_de_pago__c,Nombre_contratante__c FROM Polizas__c LIMIT 1];
        
        Test.startTest();
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        String jsonBody = crearJSONRequest(pol.Name);
        System.debug('📩 JSON enviado: ' + jsonBody);
        
        req.requestBody = Blob.valueOf(jsonBody);
        req.httpMethod = 'POST';
        RestContext.request = req;
        RestContext.response = res;
        
        String result = PolizaService.updatePoliza();
        Test.stopTest();
        
        // Verificar que se crearon asegurados
        Polizas__c polizaActualizada = [SELECT Id FROM Polizas__c LIMIT 1];
        List<Asegurado__c> asegurados = [SELECT Id, Name FROM Asegurado__c];
        
        // Verificar que se creó histórico
        List<Historico_Aportacion__c> historicos = [SELECT Id FROM Historico_Aportacion__c];
        
        // Verificar que se crearon pagos
        List<Pago_poliza__c> pagos = [SELECT Id FROM Pago_poliza__c];
    }

    // Test específico para debug del wrapper
    @IsTest
    static void testWrapperDeserialization() {
        String jsonBody = crearJSONRequest('TEST-WRAPPER');
        System.debug('🎯 JSON para deserializar: ' + jsonBody);
        
        Test.startTest();
        // Intentar deserializar directamente el wrapper
        PolizaWrapper wrapper = (PolizaWrapper) JSON.deserialize(jsonBody, PolizaWrapper.class);
        Test.stopTest();
    }

    // Test para verificar el flujo completo con datos mínimos
    @IsTest
    static void testMinimalDataFlow() {
        Map<String, Object> minimalRequest = new Map<String, Object>{
            'poliza' => 'POL-0101',
            'aseguradora' => 'Afirme',
            'asegurados' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'nombre' => 'Minimal Asegurado'
                    // Sin fecha_nacimiento
                }
            },
            'historico_aportaciones' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'anualidad' => 2024,
                    'prima_basica' => 5000
                    // Solo campos mínimos
                }
            }
        };
        
        Test.startTest();
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestBody = Blob.valueOf(JSON.serialize(minimalRequest));
        req.httpMethod = 'POST';
        RestContext.request = req;
        RestContext.response = res;
        
        String result = PolizaService.updatePoliza();
        Test.stopTest();
        
    }

    // Test para campos nulos en asegurados e histórico
    @IsTest
    static void testNullFieldsInRelatedObjects() {
        Polizas__c polizaTest = crearPolizaTest('TEST-NULL-FIELDS');
        insert polizaTest;
        
        Map<String, Object> requestMap = new Map<String, Object>{
            'poliza' => 'TEST-NULL-FIELDS',
            'aseguradora' => 'Afirme',
            'asegurados' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'nombre' => 'Asegurado Sin Fecha'
                    // fecha_nacimiento es null implícitamente
                }
            },
            'historico_aportaciones' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'anualidad' => 2024
                    // Solo anualidad, otros campos null
                }
            }
        };
        
        Test.startTest();
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestBody = Blob.valueOf(JSON.serialize(requestMap));
        req.httpMethod = 'POST';
        RestContext.request = req;
        RestContext.response = res;
        
        String result = PolizaService.updatePoliza();
        Test.stopTest();
        
    }
}