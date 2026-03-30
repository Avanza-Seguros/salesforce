public with sharing class ExcelProcessorController {
    
    @AuraEnabled(cacheable=false)
    public static ProcessResult processExcelData(List<Map<String, String>> excelData) {
        System.debug('Inicia processExcelData');
        ProcessResult result = new ProcessResult();
        
        try {
            // Validación inicial
            System.debug('excelData recibido: ' + excelData);
            System.debug('Número de registros: ' + (excelData != null ? excelData.size() : 0));
            
            if (excelData == null || excelData.isEmpty()) {
                result.errorMessages.add('No se proporcionaron datos para procesar');
                return result;
            }

            // Agrupar datos por póliza
            Map<String, List<ExcelDataWrapper>> policyToRecordsMap = groupRecordsByPolicy(excelData);
            System.debug('Total de pólizas a procesar: ' + policyToRecordsMap.size());
            System.debug('Pólizas encontradas: ' + policyToRecordsMap.keySet());

            // Obtener IDs de pólizas existentes
            Map<String, Id> policyNumberToIdMap = getPolicyIds(policyToRecordsMap.keySet());
            System.debug('Pólizas encontradas en el sistema: ' + policyNumberToIdMap.size());
            System.debug('Mapa póliza->ID: ' + policyNumberToIdMap);

            // 🔹 PASO 1: Crear casos
            Map<String, Id> policyNumberToCaseIdMap = new Map<String, Id>();
            Set<String> processedPolicies = new Set<String>();
            List<Case> casesToInsert = new List<Case>();
            
            for (String policyNumber : policyToRecordsMap.keySet()) {
                System.debug('Procesando póliza: ' + policyNumber);
                Id policyId = policyNumberToIdMap.get(policyNumber);
                System.debug('ID de póliza encontrado: ' + policyId);
                
                // Crear caso
                Case policyCase = createPolicyCase(policyNumber, policyId, policyToRecordsMap.get(policyNumber));
                if (policyCase != null) {
                    System.debug('Caso creado para póliza: ' + policyNumber);
                    casesToInsert.add(policyCase);
                } else {
                    System.debug('No se pudo crear caso para póliza: ' + policyNumber);
                }
            }
            
            System.debug('Total de casos a insertar: ' + casesToInsert.size());
            
            // Insertar casos
            if (!casesToInsert.isEmpty()) {
                Database.SaveResult[] caseResults = Database.insert(casesToInsert, false);
                
                for (Integer i = 0; i < caseResults.size(); i++) {
                    Database.SaveResult sr = caseResults[i];
                    if (sr.isSuccess()) {
                        Case insertedCase = casesToInsert[i];
                        String policyNumber = insertedCase.Poliza_Number__c; // Asegúrate que este campo existe
                        String policyId = insertedCase.Poliza__c;
                        policyNumberToCaseIdMap.put(policyNumber, insertedCase.Id);
                        processedPolicies.add(policyId);
                        System.debug('✅ Caso insertado ID: ' + insertedCase.Id + ' para póliza: ' + policyNumber);
                    } else {
                        System.debug('❌ Error insertando caso: ' + sr.getErrors()[0].getMessage());
                    }
                }
            }
            
            System.debug('Casos creados: ' + policyNumberToCaseIdMap.size());
            System.debug('Mapa póliza->CaseId: ' + policyNumberToCaseIdMap);
            
            // 🔹 PASO 2: Crear items
            List<Items_Cases__c> allItemsToInsert = new List<Items_Cases__c>();
            
            for (String policyNumber : policyToRecordsMap.keySet()) {
                System.debug('policyNumber::: ' + policyNumber);
                Id policyId = policyNumberToIdMap.get(policyNumber);
                System.debug('policyId::: ' + policyId);
                Id caseId = policyNumberToCaseIdMap.get(policyNumber);
                System.debug('caseId::: ' + caseId);
                
                System.debug('Creando items para póliza: ' + policyNumber);
                System.debug('  - CaseId: ' + caseId);
                System.debug('  - PolicyId: ' + policyId);
                
                if (caseId != null) {
                    List<ExcelDataWrapper> records = policyToRecordsMap.get(policyNumber);
                    System.debug('  - Registros a procesar: ' + records.size());
                    
                    List<Items_Cases__c> policyItems = createPolicyItems(
                        records,
                        policyNumber,
                        policyId,
                        caseId
                    );
                    
                    System.debug('  - Items creados: ' + policyItems.size());
                    allItemsToInsert.addAll(policyItems);
                } else {
                    System.debug('⚠️ No se crearon items para póliza ' + policyNumber + ' porque no tiene CaseId');
                }
            }
            
            System.debug('Total de items a insertar: ' + allItemsToInsert.size());
            
            // 🔹 PASO 3: Insertar items usando el método correcto
            if (!allItemsToInsert.isEmpty()) {
                System.debug('Iniciando inserción de items...');
                insertItemsWithDetailedResults(allItemsToInsert, result);
                System.debug('Inserción de items completada');
            } else {
                System.debug('⚠️ No hay items para insertar');
            }

            // Resultados
            result.totalRecords = excelData.size();
            result.policiesProcessed = processedPolicies.size();
            result.casesCreated = policyNumberToCaseIdMap.size();
            result.itemsCreated = allItemsToInsert.size();
            
            System.debug('Resultado final:');
            System.debug('  - Total records: ' + result.totalRecords);
            System.debug('  - Policies processed: ' + result.policiesProcessed);
            System.debug('  - Cases created: ' + result.casesCreated);
            System.debug('  - Items created: ' + result.itemsCreated);

            // Obtener números de caso
            if (!policyNumberToCaseIdMap.isEmpty()) {
                result.caseNumbers = getCaseNumbers(policyNumberToCaseIdMap.values());
                System.debug('Números de caso: ' + result.caseNumbers);
            }
            
        } catch (Exception e) {
            System.debug('❌ ERROR en processExcelData: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            result.errorMessages.add('Error: ' + e.getMessage() + ' (línea ' + e.getLineNumber() + ')');
        }
        return result;
    }

    // 🔹 MÉTODO AUXILIAR: Obtener números de caso
    private static List<String> getCaseNumbers(List<Id> caseIds) {
        List<String> caseNumbers = new List<String>();
    
        try {
            List<Case> cases = [SELECT Id, CaseNumber FROM Case WHERE Id IN :caseIds];
            for (Case c : cases) {
                caseNumbers.add(c.CaseNumber);
            }
        } catch (Exception e) {
            System.debug('Error obteniendo números de caso: ' + e.getMessage());
        }
        
        return caseNumbers;
    }

    // 🔹 NUEVO MÉTODO: Crear e insertar caso en un solo paso
    public static Case createAndInsertPolicyCase(String policyNumber, Id policyId, List<ExcelDataWrapper> records) {
        if (records == null || records.isEmpty()) return null;
        
        Case c = createPolicyCase(policyNumber, policyId, records);
        
        if (c != null) {
            try {
                insert c;
                System.debug('✅ Caso insertado: ' + c.Subject + ' - ID: ' + c.Id);
                return c;
            } catch (Exception e) {
                System.debug('❌ Error insertando caso para póliza ' + policyNumber + ': ' + e.getMessage());
                return null;
            }
        }
        
        return null;
    }

    // Insertar ítems
    public static void insertItems(List<Items_Cases__c> itemsToInsert) {
        System.debug('Inicia insertItems::: ');
        System.debug(itemsToInsert);
        if (itemsToInsert == null || itemsToInsert.isEmpty()) {
            System.debug('⚠️ No hay Items_Cases__c para insertar');
            return;
        }

        Database.SaveResult[] itemResults = Database.insert(itemsToInsert, false);

        for (Integer i = 0; i < itemResults.size(); i++) {
            Database.SaveResult sr = itemResults[i];
            if (!sr.isSuccess()) {
                for (Database.Error err : sr.getErrors()) {
                    System.debug('❌ Error insertando Item_Case ' + i + ': ' + err.getMessage());
                }
            }
        }
    }

    // Extraer número de póliza desde el Subject del caso
    public static String extractPolicyNumberFromSubject(String subject) {
        System.debug('Inicia extractPolicyNumberFromSubject: ');
        if (subject != null && subject.contains(':')) {
            String[] parts = subject.split(':');
            if (parts.size() > 1) return parts[1].trim();
        }
        return null;
    }

    // Buscar pólizas existentes
    public static Map<String, Id> getPolicyIds(Set<String> policyNumbers) {
        System.debug('Buscando pólizas para: ' + policyNumbers);
        Map<String, Id> policyMap = new Map<String, Id>();
        
        if (policyNumbers == null || policyNumbers.isEmpty()) {
            System.debug('No hay números de póliza para buscar');
            return policyMap;
        }

        try {
            // Limpiar y preparar los números de póliza
            List<String> cleanPolicyNumbers = new List<String>();
            for (String pn : policyNumbers) {
                if (String.isNotBlank(pn)) {
                    String cleanPn = pn.trim();
                    cleanPolicyNumbers.add(cleanPn);
                    System.debug('Buscando póliza: "' + cleanPn + '"');
                }
            }
            
            if (cleanPolicyNumbers.isEmpty()) {
                return policyMap;
            }
            
            // Buscar por campo Numero_Polizas__c o Name
            List<Polizas__c> existingPolicies = [
                SELECT Id, Name, Numero_Polizas__c 
                FROM Polizas__c 
                WHERE Numero_Polizas__c IN :cleanPolicyNumbers 
                   OR Name IN :cleanPolicyNumbers
                ORDER BY CreatedDate DESC
                LIMIT 100
            ];
            
            System.debug('Pólizas encontradas en SOQL: ' + existingPolicies.size());
            
            // Mapear resultados
            for (Polizas__c policy : existingPolicies) {
                System.debug('Póliza encontrada: ID=' + policy.Id + 
                          ', Name=' + policy.Name + 
                          ', Numero=' + policy.Numero_Polizas__c);
                
                // Buscar coincidencia exacta
                for (String searchPn : cleanPolicyNumbers) {
                    if ((policy.Numero_Polizas__c != null && policy.Numero_Polizas__c.equals(searchPn)) ||
                        (policy.Name != null && policy.Name.equals(searchPn))) {
                        policyMap.put(searchPn, policy.Id);
                        System.debug('  Mapeado: ' + searchPn + ' -> ' + policy.Id);
                        break;
                    }
                }
            }
            
        } catch (Exception e) {
            System.debug('❌ Error en getPolicyIds: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
        }
        
        System.debug('Total de pólizas mapeadas: ' + policyMap.size());
        return policyMap;
    }

    // Crear un caso por póliza
    public static Case createPolicyCase(String policyNumber, Id policyId, List<ExcelDataWrapper> records) {
        System.debug('Creando caso para póliza: ' + policyNumber);
        
        if (records == null || records.isEmpty()) {
            System.debug('No hay registros para crear caso');
            return null;
        }
        
        try {
            Case c = new Case();
            c.Subject = 'Procesamiento Excel - Póliza ' + policyNumber;
            c.Origin = 'Excel Upload';
            c.Status = 'En proceso';
            c.Priority = 'Medium';
            c.Description = 'Proceso ejecutado correctamente para ' + records.size() + ' registros';
            
            // Campo personalizado para almacenar el número de póliza
            c.Poliza_Number__c = policyNumber; // Necesitas crear este campo en el objeto Case
                        
            // Si encontramos la póliza, asignar AccountId
            if (policyId != null) {
                c.Poliza__c = policyId; // Lookup a Polizas__c
                
                // Obtener el Asegurado__c de la póliza
                try {
                    Polizas__c pol = [SELECT Id, Asegurado__c FROM Polizas__c WHERE Id = :policyId LIMIT 1];
                    if (pol != null && pol.Asegurado__c != null) {
                        c.AccountId = pol.Asegurado__c;
                        System.debug('Asignado AccountId: ' + pol.Asegurado__c);
                    }
                } catch (QueryException e) {
                    System.debug('No se pudo obtener Asegurado para póliza ' + policyId);
                }
            }
            
            System.debug('Caso creado: ' + c.Subject);
            return c;
            
        } catch (Exception e) {
            System.debug('❌ Error creando caso: ' + e.getMessage());
            return null;
        }
    }

    // Crear los ítems de una póliza (sin CaseId aún)
    // 🔹 MÉTODO ACTUALIZADO: Crear items CON CaseId
    public static List<Items_Cases__c> createPolicyItems(List<ExcelDataWrapper> records, String policyNumber, Id policyId, Id caseId) {
        List<Items_Cases__c> items = new List<Items_Cases__c>();
        if (records == null || records.isEmpty() || caseId == null) {
            System.debug('⚠️ No se pueden crear items: sin registros o sin CaseId');
            return items;
        }
        Contact con = new Contact();
        Polizas__c pol = new Polizas__c();
        try {
            con = [SELECT Id FROM Contact WHERE email = 'correos@avanzaseguro.com' LIMIT 1];
            pol = [SELECT Asegurado__c FROM Polizas__c WHERE Id = :policyId LIMIT 1];
        }catch (Exception e) {
            con.Id = null;
            pol.Asegurado__c = null;
        }
        for (ExcelDataWrapper record : records) {
            System.debug(record);
            
            try {
                Items_Cases__c item = new Items_Cases__c();
                
                // 🔹 Campos de relación (AMBOS requeridos)
                item.Caso__c = caseId; // ✅ Ahora tiene valor
                item.Poliza__c = policyId; // Puede ser null si no existe la póliza
                item.Contacto__c = con.Id;
                item.Nombre_cuenta__c = pol.Asegurado__c;
                // Información del asegurado
                item.Certificado__c = record.certificate;
                item.Nombre__c = record.firstName;
                item.Apellido_paterno__c = record.fatherLastName;
                item.Apellido_materno__c = record.motherLastName;
                item.Categorias__c = record.category;
                item.Estatus__c = 'En proceso';
                // Fechas y datos personales
                item.Fecha_de_nacimiento__c = parseDate(record.birthDate);
                item.Sexo__c = record.gender == '1' ? 'Femenino' : 'Masculino';
                item.Correo_electronico__c = record.email;

                if (record.parently == '01' || record.parently == '1') {
                    item.Parentesco__c = '01 Titular';
                } else if (record.parently == '02' || record.parently == '2') {
                    item.Parentesco__c = '02 Conyuge';
                } else {
                    item.Parentesco__c = '03 Hijo';
                }
                // Fechas administrativas
                item.Fecha_de_antiguedad__c = parseDate(record.entryDate);
                item.Fecha_de_peticion__c = parseDate(record.entryDate);
                item.Fecha_de_creacion__c = Date.today();
                
                items.add(item);
                
                System.debug('✅ Item creado - Póliza: ' + policyNumber + 
                        ' - Certificado: ' + record.certificate + 
                        ' - CaseId: ' + caseId);
                
            } catch (Exception e) {
                System.debug('❌ Error creando item: ' + e.getMessage());
            }
        }
        
        return items;
    }

    // Agrupar registros por póliza
    public static Map<String, List<ExcelDataWrapper>> groupRecordsByPolicy(List<Map<String, String>> excelData) {
        System.debug('Inicia groupRecordsByPolicy: ');
        Map<String, List<ExcelDataWrapper>> policyMap = new Map<String, List<ExcelDataWrapper>>();

        if (excelData == null || excelData.isEmpty()) {
            return policyMap;
        }

        for (Map<String, String> row : excelData) {
            try {
                ExcelDataWrapper wrapper = new ExcelDataWrapper(row);
                String policyNumber = wrapper.policy;
                if (String.isNotBlank(policyNumber)) {
                    if (!policyMap.containsKey(policyNumber)) {
                        policyMap.put(policyNumber, new List<ExcelDataWrapper>());
                    }
                    policyMap.get(policyNumber).add(wrapper);
                }
            } catch (Exception e) {
                System.debug('Error procesando fila: ' + e.getMessage());
            }
        }
        return policyMap;
    }

    public static String generateCaseDescription(String policyNumber, List<ExcelDataWrapper> records) {
        System.debug('Inicia generateCaseDescription');
        String description = 'Póliza: ' + policyNumber + '\n';
        description += 'Total de registros: ' + records.size() + '\n\n';
        description += 'Registros procesados:\n';
        for (ExcelDataWrapper r : records) {
            description += '- Certificado: ' + r.certificate + ', Nombre: ' + r.firstName + ' ' + r.fatherLastName + '\n';
        }
        return description;
    }

    public static Date parseDate(String dateString) {
        if (String.isBlank(dateString)) return null;
        try {
            if (dateString.contains('/')) {
                List<String> parts = dateString.split('/');
                if (parts.size() == 3) {
                    return Date.newInstance(
                        Integer.valueOf(parts[2]),
                        Integer.valueOf(parts[1]),
                        Integer.valueOf(parts[0])
                    );
                }
            } else if (dateString.contains('-')) {
                return Date.valueOf(dateString);
            }
        } catch (Exception e) {
            System.debug('Error parseando fecha: ' + dateString + ' - ' + e.getMessage());
        }
        return null;
    }

    // ---------- CLASES AUXILIARES ----------
    public class ExcelDataWrapper {
        public String policy { get; set; }
        public String certificate { get; set; }
        public String category { get; set; }
        public String fatherLastName { get; set; }
        public String motherLastName { get; set; }
        public String firstName { get; set; }
        public String birthDate { get; set; }
        public String certificateDate { get; set; }
        public String gender { get; set; }
        public String beneficiary { get; set; }
        public String parently { get; set; }
        public String entryDate { get; set; }
        public String email { get; set; }

        public ExcelDataWrapper(Map<String, String> row) {
            this.policy = getSafeString(row, 'policy');
            this.certificate = getSafeString(row, 'certificate');
            this.category = getSafeString(row, 'category');
            this.fatherLastName = getSafeString(row, 'fatherLastName');
            this.motherLastName = getSafeString(row, 'motherLastName');
            this.firstName = getSafeString(row, 'firstName');
            this.birthDate = getSafeString(row, 'birthDate');
            this.certificateDate = getSafeString(row, 'certificateDate');
            this.gender = getSafeString(row, 'gender');
            this.beneficiary = getSafeString(row, 'beneficiary');
            this.parently = getSafeString(row, 'parently');
            this.entryDate = getSafeString(row, 'entryDate');
            this.email = getSafeString(row, 'email');
        }

        private String getSafeString(Map<String, String> row, String key) {
            return row != null && row.containsKey(key) ? String.valueOf(row.get(key)) : '';
        }
    }

    public class ProcessResult {
        public Integer totalRecords { get; set; }
        public Integer policiesProcessed { get; set; }
        public Integer casesCreated { get; set; }
        public Integer itemsCreated { get; set; }
        public Integer itemsSuccessfullyCreated { get; set; }
        public Integer itemsFailed { get; set; }
        public List<String> caseNumbers { get; set; }
        public List<String> errorMessages { get; set; }
        public List<String> successMessages { get; set; }
        public Boolean hasPartialErrors { get; set; }
        
        public ProcessResult() {
            this.caseNumbers = new List<String>();
            this.errorMessages = new List<String>();
            this.successMessages = new List<String>();
            this.hasPartialErrors = false;
            this.itemsSuccessfullyCreated = 0;
            this.itemsFailed = 0;
        }
    }

    // Método de inserción optimizado
    private static void insertItemsWithDetailedResults(List<Items_Cases__c> itemsToInsert, ProcessResult result) {
        if (itemsToInsert == null || itemsToInsert.isEmpty()) {
            System.debug('No hay items para insertar');
            return;
        }
        
        System.debug('Iniciando inserción de ' + itemsToInsert.size() + ' items');
        
        Integer batchSize = 200;
        Integer totalBatches = (itemsToInsert.size() + batchSize - 1) / batchSize;
        
        for (Integer batchIndex = 0; batchIndex < totalBatches; batchIndex++) {
            Integer startIndex = batchIndex * batchSize;
            Integer endIndex = Math.min(startIndex + batchSize, itemsToInsert.size());
            
            List<Items_Cases__c> currentBatch = new List<Items_Cases__c>();
            for (Integer i = startIndex; i < endIndex; i++) {
                currentBatch.add(itemsToInsert[i]);
            }
            
            if (!currentBatch.isEmpty()) {
                System.debug('Procesando lote ' + (batchIndex + 1) + ' de ' + totalBatches + 
                          ' (' + currentBatch.size() + ' items)');
                
                try {
                    Database.SaveResult[] saveResults = Database.insert(currentBatch, false);
                    
                    // Procesar resultados
                    for (Integer i = 0; i < saveResults.size(); i++) {
                        if (saveResults[i].isSuccess()) {
                            result.itemsSuccessfullyCreated++;
                        } else {
                            result.itemsFailed++;
                            result.hasPartialErrors = true;
                            
                            Database.Error error = saveResults[i].getErrors()[0];
                            String errorMsg = 'Item ' + (startIndex + i + 1) + ': ' + error.getMessage();
                            result.errorMessages.add(errorMsg);
                            
                            System.debug('❌ Error en item: ' + errorMsg);
                        }
                    }
                    
                    System.debug('✅ Lote ' + (batchIndex + 1) + 
                              ' completado: ' + (currentBatch.size() - (saveResults.size() - result.itemsSuccessfullyCreated)) + 
                              ' de ' + currentBatch.size() + ' items insertados');
                    
                } catch (Exception e) {
                    System.debug('❌ Error en lote ' + (batchIndex + 1) + ': ' + e.getMessage());
                }
            }
        }
        
        System.debug('Inserción completada: ' + result.itemsSuccessfullyCreated + ' éxitos, ' + 
                  result.itemsFailed + ' errores');
    }
}