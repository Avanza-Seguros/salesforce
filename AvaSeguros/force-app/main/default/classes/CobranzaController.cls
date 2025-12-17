public with sharing class CobranzaController {

    @AuraEnabled(cacheable=false)
    public static List<Pago_poliza__c> getUltimosPagosPoliza(Date fechaInicio, Date fechaFin) {
        try {
            if (fechaInicio == null || fechaFin == null) {
                throw new AuraHandledException('Error al obtener últimos pagos: fechaInicio/fechaFin no pueden ser nulas.');
            }
            if (fechaFin < fechaInicio) {
                throw new AuraHandledException('Error al obtener últimos pagos: fechaFin no puede ser menor que fechaInicio.');
            }

            List<Pago_poliza__c> rows = [
                SELECT Id, Name, Poliza__c, Cliente__c, Fecha_de_de_Vencimiento__c,
                       Valor_Moneda__c, Pago_en_MXN__c, Fecha_de_Aplicaci_n_del_pago__c,
                       Tipo_de_Moneda__c, Poliza_sc__c, Estatus_Pago__c, Estatus_Poliza_Actual__c,
                       Folio__c, Ramo__c, Monto__c, Numero_de_Pago__c, Canal_de_Cobro__c,
                       Modo_de_Pago__c, Aseguradora__c, Contacto__c, Cancelacion__c,
                       Fecha_de_Emision_scr__c, Forma_pago__c, Folio_interno__c,
                       Agente_Relacionado__c, Comentarios__c, Poliza__r.Proxima_Fecha_de_Pago__c,
                       Proximo_Pago__c, Poliza__r.Name, CreatedDate
                FROM Pago_poliza__c
                WHERE Proximo_Pago__c >= :fechaInicio
                  AND Proximo_Pago__c <= :fechaFin
                ORDER BY Poliza__c,
                         Proximo_Pago__c DESC NULLS LAST,
                         CreatedDate DESC
            ];

            // Nos quedamos con el primero de cada póliza (por el ORDER BY ya es el último aplicado)
            Map<Id, Pago_poliza__c> pick = new Map<Id, Pago_poliza__c>();
            for (Pago_poliza__c p : rows) {
                if (!pick.containsKey(p.Poliza__c)) pick.put(p.Poliza__c, p);
            }
            return rows;
        } catch (Exception e) {
            throw new AuraHandledException('Error al obtener últimos pagos: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<Pago_poliza__c> getUltimosPagosPolizaEficiente(Date fechaInicio, Date fechaFin) {
        try {
            if (fechaInicio == null || fechaFin == null) {
                throw new AuraHandledException('Error al obtener últimos pagos (eficiente): fechaInicio/fechaFin no pueden ser nulas.');
            }
            if (fechaFin < fechaInicio) {
                throw new AuraHandledException('Error al obtener últimos pagos (eficiente): fechaFin no puede ser menor que fechaInicio.');
            }

            List<AggregateResult> AR = [
                SELECT Poliza__c p, MAX(Proximo_Pago__c) f
                FROM Pago_poliza__c
                WHERE Proximo_Pago__c >= :fechaInicio
                  AND Proximo_Pago__c <= :fechaFin
                GROUP BY Poliza__c
            ];

            Set<Id> polIds = new Set<Id>();
            Map<Id, Date> maxFechaPorPoliza = new Map<Id, Date>();
            for (AggregateResult a : AR) {
                Id polId = (Id)a.get('p');
                Date f = (Date)a.get('f');
                polIds.add(polId);
                maxFechaPorPoliza.put(polId, f);
            }
            if (polIds.isEmpty()) return new List<Pago_poliza__c>();

            // Traemos los pagos de esas pólizas en ese rango y nos quedamos con el registro cuyo
            // Fecha_de_Aplicaci_n_del_pago__c == MAX para esa póliza (desempate por CreatedDate)
            List<Pago_poliza__c> candidatos = [
                SELECT Id, Name, Poliza__c, Cliente__c, Fecha_de_de_Vencimiento__c,
                       Valor_Moneda__c, Pago_en_MXN__c, Fecha_de_Aplicaci_n_del_pago__c,
                       Tipo_de_Moneda__c, Poliza_sc__c, Estatus_Pago__c, Estatus_Poliza_Actual__c,
                       Folio__c, Ramo__c, Monto__c, Numero_de_Pago__c, Canal_de_Cobro__c,
                       Modo_de_Pago__c, Aseguradora__c, Contacto__c, Cancelacion__c,
                       Fecha_de_Emision_scr__c, Forma_pago__c, Folio_interno__c,
                       Agente_Relacionado__c, Comentarios__c, Poliza__r.Proxima_Fecha_de_Pago__c,
                       Proximo_Pago__c, Poliza__r.Name, CreatedDate
                FROM Pago_poliza__c
                WHERE Poliza__c IN :polIds
                  AND Proximo_Pago__c >= :fechaInicio
                  AND Proximo_Pago__c <= :fechaFin
                ORDER BY Poliza__c, Proximo_Pago__c DESC, CreatedDate DESC
            ];

            Map<Id, Pago_poliza__c> result = new Map<Id, Pago_poliza__c>();
            for (Pago_poliza__c p : candidatos) {
                Date maxF = maxFechaPorPoliza.get(p.Poliza__c);
                if (p.Proximo_Pago__c == maxF && !result.containsKey(p.Poliza__c)) {
                    result.put(p.Poliza__c, p);
                }
            }
            return result.values();
        } catch (Exception e) {
            throw new AuraHandledException('Error al obtener últimos pagos (eficiente): ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<EstadisticaMensual> getEstadisticasPorMesYEstatusConFechas(Date fechaInicio, Date fechaFin) {
        try {
            String q = 'SELECT CALENDAR_YEAR(Proximo_Pago__c) anio, ' +
                       'CALENDAR_MONTH(Proximo_Pago__c) mes, ' +
                       'Estatus_Pago__c, COUNT(Id) totalPagos, SUM(Monto__c) montoTotal ' +
                       'FROM Pago_poliza__c';
            if (fechaInicio != null) q += ' WHERE Proximo_Pago__c >= :fechaInicio';
            if (fechaFin != null)   q += ' AND Proximo_Pago__c <= :fechaFin';
            q += ' GROUP BY CALENDAR_YEAR(Proximo_Pago__c), CALENDAR_MONTH(Proximo_Pago__c), Estatus_Pago__c' +
                 ' ORDER BY CALENDAR_YEAR(Proximo_Pago__c) DESC, CALENDAR_MONTH(Proximo_Pago__c) DESC';

            List<AggregateResult> agg = Database.query(q);
            List<EstadisticaMensual> out = new List<EstadisticaMensual>();
            for (AggregateResult ar : agg) {
                out.add(new EstadisticaMensual(
                    (Integer)ar.get('anio'),
                    (Integer)ar.get('mes'),
                    (String)ar.get('Estatus_Pago__c'),
                    (Integer)ar.get('totalPagos'),
                    (Decimal)ar.get('montoTotal')
                ));
            }
            return out;
        } catch (Exception e) {
            throw new AuraHandledException('Error obteniendo estadísticas: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<EstadisticaMensual> getEstadisticasPorMesYEstatus() {
        return getEstadisticasPorMesYEstatusConFechas(null, null);
    }

    @AuraEnabled(cacheable=false)
    public static Polizas__c getPoliza (Id idPol) {
        return [
            SELECT Id, Estatus__c, Name, Asegurado__r.Name, Aseguradora__c, Forma_de_pago__c,
                   Agente__c, Agente_asignado__c, Monto_Proximo_Pago__c, Proxima_Fecha_de_Pago__c,
                   Prima_Anual__c, Dias_Vencimiento__c, Vigencia_desde__c, Vigencia_hasta__c
            FROM Polizas__c
            WHERE Id = :idPol
        ];
    }

    @AuraEnabled(cacheable=false)
    public static List<Pago_poliza__c> getPagosPol (Id pagoPol) {
        return [
            SELECT Id, Name, Poliza__c, Cliente__c, Fecha_de_de_Vencimiento__c,
                   Valor_Moneda__c, Pago_en_MXN__c, Fecha_de_Aplicaci_n_del_pago__c,
                   Tipo_de_Moneda__c, Poliza_sc__c, Estatus_Pago__c, Estatus_Poliza_Actual__c, Folio__c,
                   Ramo__c, Monto__c, Numero_de_Pago__c, Canal_de_Cobro__c,
                   Modo_de_Pago__c, Aseguradora__c, Contacto__c, Cancelacion__c,
                   Fecha_de_Emision_scr__c, Forma_pago__c, Folio_interno__c,
                   Agente_Relacionado__c, Comentarios__c, Proximo_Pago__c
            FROM Pago_poliza__c
            WHERE Id = :pagoPol
        ];
    }

    public class EstadisticaMensual {
        @AuraEnabled public Integer anio { get; set; }
        @AuraEnabled public Integer mes { get; set; }
        @AuraEnabled public String estatus { get; set; }
        @AuraEnabled public Integer totalPagos { get; set; }
        @AuraEnabled public Decimal montoTotal { get; set; }
        public EstadisticaMensual(Integer anio, Integer mes, String estatus, Integer totalPagos, Decimal montoTotal) {
            this.anio = anio; this.mes = mes; this.estatus = estatus;
            this.totalPagos = totalPagos; this.montoTotal = montoTotal;
        }
    }
}