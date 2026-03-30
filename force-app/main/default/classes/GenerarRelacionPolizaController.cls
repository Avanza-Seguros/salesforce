public with sharing class GenerarRelacionPolizaController {

    /**
     * Construye registros de Relacion_Poliza__c en base a las dependencias de Poliza, Asegurado, Pago y Histórico.
     * 100% bulk-safe (sin SOQL/DML en loops).
     */
    @AuraEnabled(cacheable=false)
    public static List<Relacion_Poliza__c> buildRelaciones(List<Id> polizaIds) {
        List<Id> ids = new List<Id>();
        for (String polizaId : polizaIds) {
            if (String.isNotBlank(polizaId)) {
                ids.add((Id)polizaId);
            }
        }
        
        if (ids.isEmpty()) return new List<Relacion_Poliza__c>();

        // 1️⃣ Consultar pólizas
        Map<Id, Polizas__c> mapPolizas = new Map<Id, Polizas__c>([
            SELECT Id, Name FROM Polizas__c WHERE Id IN :ids
        ]);

        // 2️⃣ Consultar asegurados
        Map<Id, List<Asegurado__c>> mapAsegurados = new Map<Id, List<Asegurado__c>>();
        for (Asegurado__c a : [
            SELECT Id, Name, FechaNacimiento__c, Polizas__c
            FROM Asegurado__c
            WHERE Polizas__c IN :polizaIds
        ]) {
            if (!mapAsegurados.containsKey(a.Polizas__c)) {
                mapAsegurados.put(a.Polizas__c, new List<Asegurado__c>());
            }
            mapAsegurados.get(a.Polizas__c).add(a);
        }

        // 3️⃣ Consultar pagos
        Map<Id, List<Pago_Poliza__c>> mapPagos = new Map<Id, List<Pago_Poliza__c>>();
        for (Pago_Poliza__c p : [
            SELECT Id, Name, Poliza__c, Importe_de_Ultima_Aportacion__c,
                   Tipo_de_Moneda__c, Valor_Moneda__c, Pago_en_MXN__c,
                   Tipo_de_pago__c, Fecha_de_emision__c, Estatus_del_Pago__c
            FROM Pago_Poliza__c
            WHERE Poliza__c IN :polizaIds
            ORDER BY Fecha_de_emision__c DESC
        ]) {
            if (!mapPagos.containsKey(p.Poliza__c)) {
                mapPagos.put(p.Poliza__c, new List<Pago_Poliza__c>());
            }
            mapPagos.get(p.Poliza__c).add(p);
        }

        // 4️⃣ Consultar históricos
        Map<Id, List<Historico_Aportacion__c>> mapHistoricos = new Map<Id, List<Historico_Aportacion__c>>();
        for (Historico_Aportacion__c h : [
            SELECT Id, Name, Poliza__c, Anualidad__c, Desde__c, Hasta__c,
                   PagosIngresados__c, PrimaAdicional__c, PrimaBasica__c
            FROM Historico_Aportacion__c
            WHERE Poliza__c IN :polizaIds
            ORDER BY Desde__c DESC
        ]) {
            if (!mapHistoricos.containsKey(h.Poliza__c)) {
                mapHistoricos.put(h.Poliza__c, new List<Historico_Aportacion__c>());
            }
            mapHistoricos.get(h.Poliza__c).add(h);
        }

        // 5️⃣ Eliminar relaciones previas
        List<Relacion_Poliza__c> previas = [
            SELECT Id FROM Relacion_Poliza__c WHERE Poliza__c IN :polizaIds
        ];
        if (!previas.isEmpty()) {
            delete previas;
        }

        // 6️⃣ Construir nuevas relaciones
        List<Relacion_Poliza__c> nuevas = new List<Relacion_Poliza__c>();

        for (Id polizaId : polizaIds) {
            Polizas__c pol = mapPolizas.get(polizaId);
            if (pol == null) continue;

            List<Asegurado__c> asegurados = mapAsegurados.get(polizaId);
            List<Pago_Poliza__c> pagos = mapPagos.get(polizaId);
            List<Historico_Aportacion__c> historicos = mapHistoricos.get(polizaId);

            Pago_Poliza__c pagoReciente = (pagos != null && !pagos.isEmpty()) ? pagos[0] : null;
            Historico_Aportacion__c histReciente = (historicos != null && !historicos.isEmpty()) ? historicos[0] : null;

            if (asegurados != null && !asegurados.isEmpty()) {
                for (Asegurado__c a : asegurados) {
                    nuevas.add(new Relacion_Poliza__c(
                        Poliza__c = pol.Id,
                        Asegurado__c = a.Id,
                        Pago__c = (pagoReciente != null) ? pagoReciente.Id : null,
                        Historico__c = (histReciente != null) ? histReciente.Id : null
                    ));
                }
            } else {
                nuevas.add(new Relacion_Poliza__c(
                    Poliza__c = pol.Id,
                    Pago__c = (pagoReciente != null) ? pagoReciente.Id : null,
                    Historico__c = (histReciente != null) ? histReciente.Id : null
                ));
            }
        }

        if (!nuevas.isEmpty()) insert nuevas;

        return nuevas;
    }
}