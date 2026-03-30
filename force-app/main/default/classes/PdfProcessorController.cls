public with sharing class PdfProcessorController {

    public class PdfDataRow {
        @AuraEnabled public String policy { get; set; }
        @AuraEnabled public String certificate { get; set; }
        @AuraEnabled public String fullName { get; set; }
        @AuraEnabled public String rfc { get; set; }
        @AuraEnabled public String birthDate { get; set; }
        @AuraEnabled public String insuranceCompany { get; set; }
        @AuraEnabled public String sourceFile { get; set; }
        @AuraEnabled public String plan { get; set; }
        @AuraEnabled public String vigenciaDesde { get; set; }
        @AuraEnabled public String vigenciaHasta { get; set; }
    }

    public class ProcessResult {
        @AuraEnabled public Integer totalRecords { get; set; }
        @AuraEnabled public Integer policiesProcessed { get; set; }
        @AuraEnabled public Integer casesCreated { get; set; }
        @AuraEnabled public Integer itemsCreated { get; set; }
        @AuraEnabled public List<String> errorMessages { get; set; }

        public ProcessResult() {
            errorMessages = new List<String>();
        }
    }

    @AuraEnabled(cacheable=false)
    public static ProcessResult processPdfData(List<PdfDataRow> pdfData) {
        System.debug('pdfData::: ' + pdfData);
        ProcessResult result = new ProcessResult();
        if (pdfData == null || pdfData.isEmpty()) {
            throw new AuraHandledException('No hay datos para procesar.');
        }

        result.totalRecords = pdfData.size();
        Map<String, List<PdfDataRow>> grouped = new Map<String, List<PdfDataRow>>();
        List<Items_Cases__c> items = new List<Items_Cases__c>();
        for (PdfDataRow r : pdfData) {
            if (String.isBlank(r.policy)) continue;
            String key = r.policy.trim();
            if (!grouped.containsKey(key)) grouped.put(key, new List<PdfDataRow>());
            grouped.get(key).add(r); 
        }

        for (String policyNum : grouped.keySet()) {
            try {
                Polizas__c poliza = upsertPolicy(policyNum);
                System.debug('Poliza::: ' + poliza);
                Case caso = createCaseForPolicy(poliza);
                System.debug('Caso::: ' + caso);
                for (PdfDataRow r : grouped.get(policyNum)) {
                    items.add(new Items_Cases__c(
                        Poliza__c = poliza.Id,
                        Caso__c = caso.Id,
                        Nombre__c = r.fullName,
                        Certificado__c = r.certificate,
                        Categorias__c = r.insuranceCompany,
                        RFC__c = r.rfc
                    ));
                }
                insert items;
                result.itemsCreated += items.size();
            } catch (Exception e) {
                result.errorMessages.add('Error procesando póliza ' + policyNum + ': ' + e.getMessage());
            }
        }

        return result;
    }

    private static Polizas__c upsertPolicy(String policyNumber) {
        Polizas__c p = [SELECT Id, Name FROM Polizas__c WHERE Name = :policyNumber LIMIT 1];
        /*if (p == null) {
            p = new Polizas__c(Name = policyNumber, Estatus__c = 'Activa');
            insert p;
        }*/
        return p;
    }

    private static Case createCaseForPolicy(Polizas__c policy) {
        Case c = [SELECT Id, Subject, Status, Poliza__c FROM Case WHERE Poliza__c = :policy.Id LIMIT 1];

        return c;
    }

    // 🔍 Obtener IDs de pólizas existentes
    @AuraEnabled(cacheable=false)
    public static Map<String, String> getPolicyIds(List<String> policyNumbers, List<String> certificateNumbers) {
        Map<String, String> resultMap = new Map<String, String>();
        
        try {
            System.debug('🔍 Búsqueda de Items_Cases por pólizas y certificados');
            System.debug('   Pólizas recibidas: ' + policyNumbers);
            System.debug('   Certificados recibidos: ' + certificateNumbers);
            
            // Primero: Buscar las Polizas__c que coinciden con los números
            List<Items_Cases__c> items = [
                SELECT Id, Poliza__c, Poliza__r.Numero_Polizas__c, 
                       Certificado__c, Parentesco__c, Name
                FROM Items_Cases__c 
                WHERE Poliza__r.Numero_Polizas__c IN :policyNumbers
                AND Parentesco__c IN ('01','01 Titular')
                ORDER BY CreatedDate DESC
            ];
            
            System.debug('Items_Cases encontrados con Parentesco__c = "01": ' + items.size());
            
            // Crear mapa: Poliza -> Item Id
            for (Items_Cases__c item : items) {
                if (item.Poliza__r.Numero_Polizas__c != null) {
                    String key = item.Poliza__r.Numero_Polizas__c;
                    resultMap.put(key, item.Id);
                    System.debug('Mapeado: ' + key + ' -> ' + item.Id + ' (Parentesco: ' + item.Parentesco__c + ')');
                }
            }
            
            } catch (Exception e) {
            System.debug('Error en getPolicyIds: ' + e.getMessage());
            throw new AuraHandledException('Error buscando Items_Cases: ' + e.getMessage());
        }
        
        return resultMap;
    }

    // 💾 Guardar PDF en ContentVersion y relacionar con Poliza__c
    @AuraEnabled(cacheable=false)
    public static String savePdfFile(String base64Data, String fileName, String parentId, String certificate, String policyNumber) {
        System.debug('dsvePdfFile');
        System.debug('base64Data: ' + base64Data);
        System.debug('fileName: ' + fileName);
        System.debug('parentId: ' + parentId);
        System.debug('certificate: ' + certificate);
        System.debug('policyNumber: ' + policyNumber);
        try {
            // Decodificar Base64
            Blob fileBlob = EncodingUtil.base64Decode(base64Data);
            
            // Crear ContentVersion
            ContentVersion cv = new ContentVersion();
            cv.VersionData = fileBlob;
            cv.Title = fileName.endsWith('.pdf') ? fileName : fileName + '.pdf';
            cv.PathOnClient = fileName.endsWith('.pdf') ? fileName : fileName + '.pdf';
            cv.Description = 'Póliza: ' + (policyNumber != null ? policyNumber : 'N/A') + 
                           ' | Certificado: ' + (certificate != null ? certificate : 'N/A');
            
            // Asociar al Item_case si existe
            if (String.isNotBlank(parentId)) {
                cv.FirstPublishLocationId = parentId;
            }
            
            insert cv;
            
            return cv.Id;
            
        } catch (Exception e) {
            System.debug('Error: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            throw new AuraHandledException('Error guardando archivo: ' + e.getMessage());
        }
    }

    // Método Apex para buscar pólizas
    @AuraEnabled(cacheable=false)
    public static List<Polizas__c> findPolicies(String searchTerm) {
        String likeTerm = '%' + searchTerm + '%';
        
        return [
            SELECT Id, Name, Numero_Polizas__c, Estatus__c, Tipo_de_poliza__c
            FROM Polizas__c 
            WHERE Name LIKE :likeTerm
            ORDER BY CreatedDate DESC
        ];
    }

    // Método Apex para buscar Items_Cases
    @AuraEnabled(cacheable=true)
    public static List<Items_Cases__c> findItemsForPolicy(Id policyId, String certificate) {
        System.debug('findItemsForPolicy: ' + policyId + ' | ' + certificate);
        // Primero, encontrar el último Case relacionado a la póliza y certificado
        Case lastCase = [
            SELECT Id, CreatedDate
            FROM Case 
            WHERE Poliza__c = :policyId
            AND Status = 'En proceso'
            ORDER BY CreatedDate DESC 
            LIMIT 1
        ];
        System.debug('lastCase::: ' + lastCase);
        if (lastCase.Id == null) {
            System.debug('No se encontró ningún Case para la póliza ' + policyId + ' y certificado ' + certificate);
            return new List<Items_Cases__c>();
        }
        
        // Luego, obtener los items relacionados a ese Case
        List<Items_Cases__c> items = [
            SELECT Id, Name, Poliza__c, Certificado__c, 
                Parentesco__c, Nombre_completo__c, Caso__c
            FROM Items_Cases__c 
            WHERE Caso__c = :lastCase.Id
            AND Certificado__c = :certificate
            AND Parentesco__c = '01 Titular'
            ORDER BY CreatedDate DESC
        ];
        
        System.debug('Items_Cases encontrados para el último Case ' + lastCase.Id + ': ' + items.size());
        for (Items_Cases__c item : items) {
            System.debug('  - ' + item.Name + ' (Parentesco: ' + item.Parentesco__c + ')');
        }
        System.debug('Items::: ' + items);
        return items;
    }

    // Método auxiliar para verificar si un Item_Cases es titular
    @AuraEnabled
    public static Boolean isTitular(String itemCaseId) {
        try {
            Items_Cases__c item = [
                SELECT Id, Parentesco__c 
                FROM Items_Cases__c 
                WHERE Id = :itemCaseId 
                LIMIT 1
            ];
            
            return item.Parentesco__c == '01 Titular' 
                || item.Parentesco__c == '01';
            
        } catch (Exception e) {
            System.debug('Error en isTitular: ' + e.getMessage());
            return false;
        }
    }

}