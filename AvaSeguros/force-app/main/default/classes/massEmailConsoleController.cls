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


    // Ejecutar el flow que dispara el batch
    @AuraEnabled
    public static void runMassEmailFlow() {
        System.debug('runMassEmailFlow');
        Integer batchSize = calcularBatchSize();
        Database.executeBatch(new BatchActualizarItems() ,batchSize);
    }

    private static Integer calcularBatchSize() {
        // Calcular tamaño de batch basado en límites disponibles
        Integer emailsPorBatch = 10; // Conservador para evitar límites
        
        // Si hay muchos registros, usar tamaño más pequeño
        Integer totalRegistros = [SELECT COUNT() FROM Items_Cases__c 
                                  WHERE Estatus__c = 'En proceso' 
                                  AND Correo_electronico__c != null];
        
        if (totalRegistros > 200) {
            emailsPorBatch = 5;
        } else if (totalRegistros > 50) {
            emailsPorBatch = 10;
        } else {
            emailsPorBatch = 20;
        }
        
        System.debug('Batch size calculado: ' + emailsPorBatch);
        return emailsPorBatch;
    }
}