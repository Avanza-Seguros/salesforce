public with sharing class PolizaDashboardController {

    @AuraEnabled(cacheable=true)
    public static PolizaDashboardWrapper getDashboardDataCobranza(String periodo) {
        try {
            Integer year = Date.today().year();
            Date fechaInicio;
            Date fechaFin;
            
            // Determinar rango de fechas para cobranza
            if (periodo == 'mensual') {
                fechaInicio = Date.today().toStartOfMonth();
                fechaFin = fechaInicio.addMonths(1).addDays(-1);
            } else if (periodo == 'bimestral') {
                fechaInicio = Date.today().toStartOfMonth();
                fechaFin = fechaInicio.addMonths(2).addDays(-1);
            } else if (periodo == 'semestral') {
                fechaInicio = Date.today().toStartOfMonth();
                fechaFin = fechaInicio.addMonths(6).addDays(-1);
            } else {
                // Por defecto mensual
                fechaInicio = Date.today().toStartOfMonth();
                fechaFin = fechaInicio.addMonths(1).addDays(-1);
            }

            System.debug('🔍 Consultando pólizas para cobranza período: ' + periodo);
            System.debug('📅 Rango de fechas para cobranza: ' + fechaInicio + ' - ' + fechaFin);

            // Consultar pólizas detalladas para cobranza
            List<Polizas__c> polizas = [
                SELECT Id, Name, Numero_Polizas__c, Estatus__c,
                       Nombre_contratante__c, Moneda__c,
                       Fecha_de_Emision__c, Vigencia_hasta__c,
                       PrimaTotal__c, Suma_Aseguradora__c,
                       Pago_en_MXN__c
                FROM Polizas__c
                WHERE Fecha_de_Emision__c >= :fechaInicio 
                  AND Fecha_de_Emision__c <= :fechaFin
                  AND Estatus__c IN ('Activa', 'Vigor', 'Pendiente', 'Vigor Prorrogado')
                ORDER BY Fecha_de_Emision__c ASC
            ];

            // Calcular métricas manualmente
            Decimal totalPendiente = 0;
            Decimal totalPrimas = 0;
            Decimal totalSumaAsegurada = 0;
            Integer totalPolizasCount = polizas.size();
            
            // Mapa para contar por estatus
            Map<String, Integer> contadorEstatus = new Map<String, Integer>();
            
            for (Polizas__c poliza : polizas) {
                totalPendiente += poliza.Pago_en_MXN__c != null ? poliza.Pago_en_MXN__c : 0;
                totalPrimas += poliza.PrimaTotal__c != null ? poliza.PrimaTotal__c : 0;
                totalSumaAsegurada += poliza.Suma_Aseguradora__c != null ? poliza.Suma_Aseguradora__c : 0;
                
                // Contar por estatus
                String estatus = poliza.Estatus__c != null ? poliza.Estatus__c : 'Sin Estatus';
                if (contadorEstatus.containsKey(estatus)) {
                    contadorEstatus.put(estatus, contadorEstatus.get(estatus) + 1);
                } else {
                    contadorEstatus.put(estatus, 1);
                }
            }

            // Procesar resumen por estatus
            List<ResumenEstatus> resumenEstatus = new List<ResumenEstatus>();
            for (String estatus : contadorEstatus.keySet()) {
                resumenEstatus.add(new ResumenEstatus(estatus, contadorEstatus.get(estatus)));
            }

            System.debug('📊 Métricas de cobranza: ' + totalPolizasCount + ' pólizas, $' + totalPendiente + ' pendientes');

            return new PolizaDashboardWrapper(
                polizas, 
                totalPrimas, 
                totalPendiente, 
                totalPolizasCount,
                totalSumaAsegurada,
                resumenEstatus,
                periodo, 
                year,
                fechaInicio,
                fechaFin
            );
            
        } catch (Exception e) {
            System.debug('❌ Error en getDashboardDataCobranza: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            throw new AuraHandledException('Error al cargar datos de cobranza: ' + e.getMessage());
        }
    }

    // Método para obtener pólizas vencidas
    @AuraEnabled(cacheable=true)
    public static List<Polizas__c> getPolizasVencidas() {
        try {
            Date hoy = Date.today();
            
            List<Polizas__c> polizasVencidas = [
                SELECT Id, Name, Numero_Polizas__c, Estatus__c,
                       Nombre_contratante__c, Moneda__c,
                       Fecha_de_Emision__c, Vigencia_hasta__c,
                       PrimaTotal__c, Suma_Aseguradora__c,
                       Pago_en_MXN__c, Proxima_Fecha_de_Pago__c
                FROM Polizas__c
                  WHERE Proxima_Fecha_de_Pago__c > :hoy
                  AND Estatus__c IN ('Activa', 'Vigor', 'Pendiente', 'Vigor Prorrogado')
                ORDER BY Fecha_de_Emision__c ASC
            ];
            
            return polizasVencidas;
            
        } catch (Exception e) {
            System.debug('❌ Error en getPolizasVencidas: ' + e.getMessage());
            throw new AuraHandledException('Error al cargar pólizas vencidas: ' + e.getMessage());
        }
    }

    // Wrapper principal para el dashboard
    public class PolizaDashboardWrapper {
        @AuraEnabled public List<Polizas__c> polizas;
        @AuraEnabled public Decimal totalPrimas;
        @AuraEnabled public Decimal totalPendiente;
        @AuraEnabled public Integer totalPolizas;
        @AuraEnabled public Decimal totalSumaAsegurada;
        @AuraEnabled public List<ResumenEstatus> resumenEstatus;
        @AuraEnabled public String periodo;
        @AuraEnabled public Integer year;
        @AuraEnabled public Date fechaInicio;
        @AuraEnabled public Date fechaFin;

        public PolizaDashboardWrapper(List<Polizas__c> polizas, Decimal totalPrimas, Decimal totalPendiente, 
                                    Integer totalPolizas, Decimal totalSumaAsegurada, 
                                    List<ResumenEstatus> resumenEstatus, String periodo, Integer year,
                                    Date fechaInicio, Date fechaFin) {
            this.polizas = polizas;
            this.totalPrimas = totalPrimas;
            this.totalPendiente = totalPendiente;
            this.totalPolizas = totalPolizas;
            this.totalSumaAsegurada = totalSumaAsegurada;
            this.resumenEstatus = resumenEstatus;
            this.periodo = periodo;
            this.year = year;
            this.fechaInicio = fechaInicio;
            this.fechaFin = fechaFin;
        }
    }
    
    // Clase para resumen por estatus
    public class ResumenEstatus {
        @AuraEnabled public String estatus { get; set; }
        @AuraEnabled public Integer cantidad { get; set; }
        
        public ResumenEstatus(String estatus, Integer cantidad) {
            this.estatus = estatus;
            this.cantidad = cantidad;
        }
    }

    //Pago poliza
    public class PagoPolizaDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;

        @AuraEnabled public Date fechaPago;
        @AuraEnabled public Date fechaVencimiento;
        @AuraEnabled public Decimal monto;
        @AuraEnabled public String moneda;
        @AuraEnabled public Decimal montoMXN;

        @AuraEnabled public String estatusPago;
        @AuraEnabled public String estatusPolizaActual;

        @AuraEnabled public String formaPago;
        @AuraEnabled public String modoPago;
        @AuraEnabled public String canalCobro;

        @AuraEnabled public String aseguradora;
        @AuraEnabled public String ramo;

        @AuraEnabled public String folio;
        @AuraEnabled public String folioInterno;
        @AuraEnabled public String numeroPago;

        @AuraEnabled public String agenteRelacionado;
        @AuraEnabled public String comentarios;

        @AuraEnabled public Date proximoPago;
        @AuraEnabled public Datetime createdDate;
    }

    @AuraEnabled(cacheable=false)
    public static List<PagoPolizaDTO> obtenerPagosDePoliza(String numeroPoliza) {

        if (String.isBlank(numeroPoliza)) {
            return new List<PagoPolizaDTO>();
        }

        Polizas__c poliza = [
            SELECT Id, Estatus__c, Name, Asegurado__r.Name, Aseguradora__c, Forma_de_pago__c,
                   Agente__c, Agente_asignado__c, Monto_Proximo_Pago__c, Proxima_Fecha_de_Pago__c,
                   Prima_Anual__c, Dias_Vencimiento__c, Vigencia_desde__c, Vigencia_hasta__c
            FROM Polizas__c
            WHERE Name = :numeroPoliza
            LIMIT 1
        ];

        List<PagoPolizaDTO> resultado = new List<PagoPolizaDTO>();

        for (Pago_Poliza__c p : [
            SELECT Id, Name, Poliza__c, Cliente__c, Fecha_de_de_Vencimiento__c,
                Valor_Moneda__c, Pago_en_MXN__c, Fecha_de_Aplicaci_n_del_pago__c,
                Tipo_de_Moneda__c, Poliza_sc__c, Estatus_Pago__c, Estatus_Poliza_Actual__c, Folio__c,
                Ramo__c, Monto__c, Numero_de_Pago__c, Canal_de_Cobro__c,
                Modo_de_Pago__c, Aseguradora__c, Contacto__c, Cancelacion__c,
                Fecha_de_Emision_scr__c, Forma_pago__c, Folio_interno__c,
                Agente_Relacionado__c, Comentarios__c, Proximo_Pago__c,
                CreatedDate
            FROM Pago_Poliza__c
            WHERE Poliza__c = :poliza.Id
            ORDER BY Fecha_de_Aplicaci_n_del_pago__c DESC, CreatedDate DESC
        ]) {
            PagoPolizaDTO dto = new PagoPolizaDTO();

            dto.id = p.Id;
            dto.name = p.Name;

            dto.fechaPago = p.Fecha_de_Aplicaci_n_del_pago__c;
            dto.fechaVencimiento = p.Fecha_de_de_Vencimiento__c;
            dto.monto = p.Monto__c;
            dto.moneda = p.Tipo_de_Moneda__c;
            dto.montoMXN = p.Pago_en_MXN__c;

            dto.estatusPago = p.Estatus_Pago__c;
            dto.estatusPolizaActual = p.Estatus_Poliza_Actual__c;

            dto.formaPago = p.Forma_pago__c;
            dto.modoPago = p.Modo_de_Pago__c;
            dto.canalCobro = p.Canal_de_Cobro__c;

            dto.aseguradora = p.Aseguradora__c;
            dto.ramo = p.Ramo__c;

            dto.folio = p.Folio__c;
            dto.folioInterno = p.Folio_interno__c;
            dto.numeroPago = p.Numero_de_Pago__c;

            dto.agenteRelacionado = p.Agente_Relacionado__c;
            dto.comentarios = p.Comentarios__c;

            dto.proximoPago = p.Proximo_Pago__c;
            dto.createdDate = p.CreatedDate;

            resultado.add(dto);
        }

        return resultado;
    }

    @AuraEnabled
    public static void actualizarComentariosPago(Map<Id, String> comentariosPorPago) {

        if (comentariosPorPago == null || comentariosPorPago.isEmpty()) {
            return;
        }

        List<Pago_Poliza__c> pagosActualizar = new List<Pago_Poliza__c>();

        for (Id pagoId : comentariosPorPago.keySet()) {
            pagosActualizar.add(new Pago_Poliza__c(
                Id = pagoId,
                Comentarios__c = comentariosPorPago.get(pagoId)
            ));
        }

        update pagosActualizar;
    }

}