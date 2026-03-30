public with sharing class massEmailConsoleController {
    // Métricas principales para la pantalla
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getDashboardData() {
        System.debug('getDashboardData');
        Map<String, Object> data = new Map<String, Object>();

        // Total pendientes
        Integer pending = [
            SELECT COUNT() 
            FROM Items_Cases__c 
            WHERE Estatus__c = 'En proceso'
        ];

        // Total concluidos hoy
        Integer todaySent = [
            SELECT COUNT() 
            FROM Items_Cases__c 
            WHERE Estatus__c = 'Concluido' 
              AND LastModifiedDate = TODAY
        ];

        System.debug('pending: ' + pending);
        System.debug('todaySent: ' + todaySent);
        data.put('pending', pending);
        data.put('sentToday', todaySent);

        return data;
    }

    @AuraEnabled(cacheable=true)
    public static List<Case> getAvailableCases() {
        // Obtener casos que tienen items pendientes de enviar
        return [
            SELECT Id, CaseNumber, Subject, Status, CreatedDate
            FROM Case
            WHERE Status = 'En proceso'
            ORDER BY CreatedDate DESC
            LIMIT 100
        ];
    }

    // Ejecutar el flow que dispara el batch
    @AuraEnabled(cacheable=false)
    public static String runMassEmailFlow(String params) {
        System.debug('runMassEmailFlow iniciado');
        try {
            Map<String, Object> paramsMap = (Map<String, Object>)JSON.deserializeUntyped(params);
            String selectionMode = (String)paramsMap.get('selectionMode');
            System.debug('selectionMode: ' + selectionMode);
            
            List<Id> itemIds = new List<Id>();
            
            if (selectionMode == 'manual') {
                Object caseIdsObj = paramsMap.get('caseIds');
                
                if (caseIdsObj instanceof String) {
                    String caseId = (String)caseIdsObj;
                    if (String.isNotBlank(caseId)) {
                        // Buscar Items_Cases para este Caso
                        for (Items_Cases__c item : [
                            SELECT Id 
                            FROM Items_Cases__c 
                            WHERE Caso__c = :caseId
                            AND Estatus__c = 'En proceso'
                        ]) {
                            itemIds.add(item.Id);
                        }
                    }
                } else if (caseIdsObj instanceof List<Object>) {
                    // Si es una lista, tomar el primero
                    List<Object> caseList = (List<Object>)caseIdsObj;
                    if (!caseList.isEmpty()) {
                        String caseId = String.valueOf(caseList[0]);
                        for (Items_Cases__c item : [
                            SELECT Id 
                            FROM Items_Cases__c 
                            WHERE Caso__c = :caseId
                            AND Estatus__c = 'En proceso'
                        ]) {
                            itemIds.add(item.Id);
                        }
                    }
                }
            } else if (selectionMode == 'all') {
                // Si es "todos", obtener todos los pendientes
                for (Items_Cases__c item : [
                    SELECT Id 
                    FROM Items_Cases__c 
                    WHERE Estatus__c = 'En proceso'
                    ORDER BY CreatedDate DESC
                    LIMIT 200
                ]) {
                    itemIds.add(item.Id);
                }
            }
            
            System.debug('Items a procesar: ' + itemIds.size());
            
            if (itemIds.isEmpty()) {
                return 'INFO: No hay items pendientes para procesar';
            }
            
            // Ejecutar batch usando el nuevo método único
            // Pasar como List<Object> para compatibilidad
            Invocable_EnviarEmails.ejecutarBatch(itemIds);
            
            return 'OK - Procesando ' + itemIds.size() + ' items';
            
        } catch (Exception e) {
            System.debug('Error: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            return 'ERROR: ' + e.getMessage();
        }
    }
}