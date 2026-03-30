public with sharing class PolizasPendientesHandler {
    public static void afterUpdate(List<Pago_poliza__c> newRecords, Map<Id, Pago_poliza__c> oldMap) {
        
        Set<String> paidStatuses = new Set<String>{'Pagado', 'Vigente', 'Cobrado', 'Pagada', 'APROBADA'};
        Map<String, Date> latestPaidDueDateByPolicy = new Map<String, Date>();

        for (Pago_poliza__c pago : newRecords) {
            
            Boolean isPaidNow = paidStatuses.contains(pago.Estatus_del_Pago__c);
            
            // On an insert operation, oldMap is null, so we must check for it.
            Boolean wasPaidBefore = false;
            if (oldMap != null && oldMap.containsKey(pago.Id)) {
                wasPaidBefore = paidStatuses.contains(oldMap.get(pago.Id).Estatus_del_Pago__c);
            }

            if (isPaidNow && pago.Poliza_sc__c != null && pago.Fecha_de_de_Vencimiento__c != null) {
                if (!latestPaidDueDateByPolicy.containsKey(pago.Poliza_sc__c) || 
                     latestPaidDueDateByPolicy.get(pago.Poliza_sc__c) < pago.Fecha_de_de_Vencimiento__c) {
                    latestPaidDueDateByPolicy.put(pago.Poliza_sc__c, pago.Fecha_de_de_Vencimiento__c);
                }
            }
        }

        if (latestPaidDueDateByPolicy.isEmpty()) {
            return;
        }

        List<Pago_poliza__c> paymentsToUpdate = new List<Pago_poliza__c>();
        Set<String> pendingStatuses = new Set<String>{'Pendiente', 'POR VENCER', 'En proceso de cobro'};

        List<Pago_poliza__c> potentialPayments = [
            SELECT Id, Estatus_del_Pago__c, Poliza_sc__c, Fecha_de_de_Vencimiento__c
            FROM Pago_poliza__c
            WHERE Poliza_sc__c IN :latestPaidDueDateByPolicy.keySet()
              AND Estatus_del_Pago__c IN :pendingStatuses
        ];

        for (Pago_poliza__c payment : potentialPayments) {
            Date latestPaidDate = latestPaidDueDateByPolicy.get(payment.Poliza_sc__c);
            if (payment.Fecha_de_de_Vencimiento__c <= latestPaidDate) {
                payment.Estatus_del_Pago__c = 'Pagada';
                paymentsToUpdate.add(payment);
            }
        }

        if (!paymentsToUpdate.isEmpty()) {
            update paymentsToUpdate;
        }
    }
}