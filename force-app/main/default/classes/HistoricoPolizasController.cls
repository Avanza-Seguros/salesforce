public with sharing class HistoricoPolizasController {
    // 🔹 Busca todas las relaciones de póliza que coincidan con el texto
    @AuraEnabled(cacheable=false)
    public static List<RelacionPolizaWrapper> buscaInicial() {
        try {
            List<Relacion_Poliza__c> relaciones = [
                SELECT 
                    Id, Name,
                    Poliza__r.Id,
                    Poliza__r.Name,
                    Poliza__r.Estatus__c,
                    Poliza__r.Moneda__c,
                    Poliza__r.Suma_Aseguradora__c,
                    Poliza__r.Fecha_de_Emision__c,
                    Poliza__r.Vigencia_hasta__c,
                    Poliza__r.Prima_Total__c,
                    Poliza__r.Ramo__c,
                    Asegurado__r.Id,
                    Asegurado__r.Name,
                    Asegurado__r.FechaNacimiento__c,

                    Historico__r.Id,
                    Historico__r.Name,
                    Historico__r.Anualidad__c,
                    Historico__r.PrimaBasica__c,
                    Historico__r.PrimaAdicional__c,
                    Historico__r.PagosIngresados__c,
                    Historico__r.Desde__c,
                    Historico__r.Hasta__c,

                    Pago__r.Id,
                    Pago__r.Name,
                    Pago__r.Importe_de_Ultima_Aportacion__c,
                    Pago__r.Tipo_de_Moneda__c,
                    Pago__r.Valor_Moneda__c,
                    Pago__r.Pago_en_MXN__c,
                    Pago__r.Tipo_de_pago__c,
                    Pago__r.Fecha_de_emision__c,
                    Pago__r.Estatus_del_Pago__c
                FROM Relacion_Poliza__c
                ORDER BY Poliza__r.Fecha_de_Emision__c DESC
            ];

            List<RelacionPolizaWrapper> wrappers = new List<RelacionPolizaWrapper>();
            for (Relacion_Poliza__c r : relaciones) {
                wrappers.add(new RelacionPolizaWrapper(r));
            }
            return wrappers;

        } catch (Exception e) {
            throw new AuraHandledException('Error al buscar relaciones: ' + e.getMessage());
        }
    }


    @AuraEnabled(cacheable=true)
    public static List<RelacionPolizaWrapper> buscarHistorico(String searchTerm) {
        try {
            String filtro = '%' + searchTerm.trim() + '%';

            List<Relacion_Poliza__c> relaciones = [
                SELECT 
                    Id, Name,
                    Poliza__r.Id,
                    Poliza__r.Name,
                    Poliza__r.Estatus__c,
                    Poliza__r.Moneda__c,
                    Poliza__r.Suma_Aseguradora__c,
                    Poliza__r.Fecha_de_Emision__c,
                    Poliza__r.Vigencia_hasta__c,
                    Poliza__r.Prima_Total__c,
                    Poliza__r.Ramo__c,
                    Asegurado__r.Id,
                    Asegurado__r.Name,
                    Asegurado__r.FechaNacimiento__c,

                    Historico__r.Id,
                    Historico__r.Name,
                    Historico__r.Anualidad__c,
                    Historico__r.PrimaBasica__c,
                    Historico__r.PrimaAdicional__c,
                    Historico__r.PagosIngresados__c,
                    Historico__r.Desde__c,
                    Historico__r.Hasta__c,

                    Pago__r.Id,
                    Pago__r.Name,
                    Pago__r.Importe_de_Ultima_Aportacion__c,
                    Pago__r.Tipo_de_Moneda__c,
                    Pago__r.Valor_Moneda__c,
                    Pago__r.Pago_en_MXN__c,
                    Pago__r.Tipo_de_pago__c,
                    Pago__r.Fecha_de_emision__c,
                    Pago__r.Estatus_del_Pago__c
                FROM Relacion_Poliza__c
                WHERE Poliza__r.Name LIKE :filtro
                   OR Asegurado__r.Name LIKE :filtro
                   OR Historico__r.Name LIKE :filtro
                ORDER BY Poliza__r.Fecha_de_Emision__c DESC
            ];

            List<RelacionPolizaWrapper> wrappers = new List<RelacionPolizaWrapper>();
            for (Relacion_Poliza__c r : relaciones) {
                wrappers.add(new RelacionPolizaWrapper(r));
            }
            return wrappers;

        } catch (Exception e) {
            throw new AuraHandledException('Error al buscar relaciones: ' + e.getMessage());
        }
    }

    // 🔹 Modificado: obtener detalle completo con lista de Asegurados, Históricos, Pagos, Relación y Póliza
    @AuraEnabled(cacheable=false)
    public static DetalleCompletoWrapper obtenerHistoricoPorRelacion(Id relacionId) {
        try {
            // Obtener la relación principal con todos sus datos
            Relacion_Poliza__c relacionPrincipal = [
                SELECT 
                    Id, Name,
                    Poliza__r.Id,
                    Poliza__r.Name,
                    Poliza__r.Estatus__c,
                    Poliza__r.Moneda__c,
                    Poliza__r.Suma_Aseguradora__c,
                    Poliza__r.Fecha_de_Emision__c,
                    Poliza__r.Vigencia_hasta__c,
                    Poliza__r.Prima_Total__c,
                    Poliza__r.Ramo__c,
                    Asegurado__r.Id,
                    Asegurado__r.Name,
                    Asegurado__r.FechaNacimiento__c,

                    Historico__r.Id,
                    Historico__r.Name,
                    Historico__r.Anualidad__c,
                    Historico__r.PrimaBasica__c,
                    Historico__r.PrimaAdicional__c,
                    Historico__r.PagosIngresados__c,
                    Historico__r.Desde__c,
                    Historico__r.Hasta__c,

                    Pago__r.Id,
                    Pago__r.Name,
                    Pago__r.Importe_de_Ultima_Aportacion__c,
                    Pago__r.Tipo_de_Moneda__c,
                    Pago__r.Valor_Moneda__c,
                    Pago__r.Pago_en_MXN__c,
                    Pago__r.Tipo_de_pago__c,
                    Pago__r.Fecha_de_emision__c,
                    Pago__r.Estatus_del_Pago__c
                FROM Relacion_Poliza__c
                WHERE Id = :relacionId
            ];

            // Obtener todos los asegurados relacionados con la misma póliza
            List<Asegurado__c> asegurados = [
                SELECT Id, Name, FechaNacimiento__c
                FROM Asegurado__c
                WHERE Polizas__c = :relacionPrincipal.Poliza__r.Id
            ];

            // Obtener todos los históricos relacionados con la misma póliza
            List<Historico_Aportacion__c> historicos = [
                SELECT Id, Name, Anualidad__c, PrimaBasica__c, PrimaAdicional__c, 
                       PagosIngresados__c, Desde__c, Hasta__c
                FROM Historico_Aportacion__c
                WHERE Poliza__c = :relacionPrincipal.Poliza__r.Id
            ];

            // Obtener todos los pagos relacionados con la misma póliza
            List<Pago_Poliza__c> pagos = [
                SELECT Id, Name, Importe_de_Ultima_Aportacion__c, Tipo_de_Moneda__c,
                       Valor_Moneda__c, Pago_en_MXN__c, Tipo_de_pago__c, 
                       Fecha_de_emision__c, Estatus_del_Pago__c
                FROM Pago_Poliza__c
                WHERE Poliza__c = :relacionPrincipal.Poliza__r.Id
                ORDER BY Fecha_de_emision__c DESC
            ];

            // Obtener todas las relaciones de la misma póliza
            List<Relacion_Poliza__c> relaciones = [
                SELECT 
                    Id, Name,
                    Poliza__r.Id,
                    Poliza__r.Name,
                    Poliza__r.Estatus__c,
                    Poliza__r.Moneda__c,
                    Poliza__r.Suma_Aseguradora__c,
                    Poliza__r.Fecha_de_Emision__c,
                    Poliza__r.Vigencia_hasta__c,
                    Poliza__r.Prima_Total__c,
                    Poliza__r.Ramo__c,
                    Asegurado__r.Id,
                    Asegurado__r.Name,
                    Asegurado__r.FechaNacimiento__c,

                    Historico__r.Id,
                    Historico__r.Name,
                    Historico__r.Anualidad__c,
                    Historico__r.PrimaBasica__c,
                    Historico__r.PrimaAdicional__c,
                    Historico__r.PagosIngresados__c,
                    Historico__r.Desde__c,
                    Historico__r.Hasta__c,

                    Pago__r.Id,
                    Pago__r.Name,
                    Pago__r.Importe_de_Ultima_Aportacion__c,
                    Pago__r.Tipo_de_Moneda__c,
                    Pago__r.Valor_Moneda__c,
                    Pago__r.Pago_en_MXN__c,
                    Pago__r.Tipo_de_pago__c,
                    Pago__r.Fecha_de_emision__c,
                    Pago__r.Estatus_del_Pago__c
                FROM Relacion_Poliza__c
                WHERE Poliza__c = :relacionPrincipal.Poliza__r.Id
            ];

            // Crear el wrapper completo con todos los datos
            return new DetalleCompletoWrapper(relacionPrincipal, asegurados, historicos, pagos, relaciones);

        } catch (Exception e) {
            throw new AuraHandledException('Error al obtener detalles completos: ' + e.getMessage());
        }
    }

    // Wrapper para el detalle completo
    public class DetalleCompletoWrapper {
        @AuraEnabled public RelacionPolizaWrapper relacionPrincipal;
        @AuraEnabled public List<AseguradoWrapper> asegurados;
        @AuraEnabled public List<HistoricoWrapper> historicos;
        @AuraEnabled public List<PagoWrapper> pagos;
        @AuraEnabled public List<RelacionPolizaWrapper> relaciones;
        @AuraEnabled public PolizaWrapper poliza;

        public DetalleCompletoWrapper(Relacion_Poliza__c relacionPrincipal, 
                                    List<Asegurado__c> asegurados, 
                                    List<Historico_Aportacion__c> historicos, 
                                    List<Pago_Poliza__c> pagos,
                                    List<Relacion_Poliza__c> relaciones) {
            
            this.relacionPrincipal = new RelacionPolizaWrapper(relacionPrincipal);
            this.asegurados = new List<AseguradoWrapper>();
            this.historicos = new List<HistoricoWrapper>();
            this.pagos = new List<PagoWrapper>();
            this.relaciones = new List<RelacionPolizaWrapper>();
            
            // Poliza desde la relación principal
            if (relacionPrincipal.Poliza__r != null) {
                this.poliza = new PolizaWrapper(relacionPrincipal.Poliza__r);
            }

            // Convertir lista de asegurados
            for (Asegurado__c a : asegurados) {
                this.asegurados.add(new AseguradoWrapper(a));
            }

            // Convertir lista de históricos
            for (Historico_Aportacion__c h : historicos) {
                this.historicos.add(new HistoricoWrapper(h));
            }

            // Convertir lista de pagos
            for (Pago_Poliza__c p : pagos) {
                this.pagos.add(new PagoWrapper(p));
            }

            // Convertir lista de relaciones
            for (Relacion_Poliza__c r : relaciones) {
                this.relaciones.add(new RelacionPolizaWrapper(r));
            }
        }
    }

    // Wrapper individual para Relación de Póliza
    public class RelacionPolizaWrapper {
        @AuraEnabled public Id relacionId;
        @AuraEnabled public String relacionName;

        @AuraEnabled public Id polizaId;
        @AuraEnabled public String polizaName;
        @AuraEnabled public String estatus;
        @AuraEnabled public String moneda;
        @AuraEnabled public Decimal sumaAsegurada;
        @AuraEnabled public Date fechaEmision;
        @AuraEnabled public Date fechaVencimiento;
        @AuraEnabled public Decimal primaTotal;
        @AuraEnabled public String planProducto;

        @AuraEnabled public AseguradoWrapper asegurado;
        @AuraEnabled public HistoricoWrapper historico;
        @AuraEnabled public PagoWrapper pago;

        public RelacionPolizaWrapper(Relacion_Poliza__c r) {
            this.relacionId = r.Id;
            this.relacionName = r.Name;

            if (r.Poliza__r != null) {
                this.polizaId = r.Poliza__r.Id;
                this.polizaName = r.Poliza__r.Name;
                this.estatus = r.Poliza__r.Estatus__c;
                this.moneda = r.Poliza__r.Moneda__c;
                this.sumaAsegurada = r.Poliza__r.Suma_Aseguradora__c;
                this.fechaEmision = r.Poliza__r.Fecha_de_Emision__c;
                this.fechaVencimiento = r.Poliza__r.Vigencia_hasta__c;
                this.primaTotal = r.Poliza__r.Prima_Total__c;
                this.planProducto = r.Poliza__r.Ramo__c;
            }

            if (r.Asegurado__r != null) this.asegurado = new AseguradoWrapper(r.Asegurado__r);
            if (r.Historico__r != null) this.historico = new HistoricoWrapper(r.Historico__r);
            if (r.Pago__r != null) this.pago = new PagoWrapper(r.Pago__r);
        }
    }

    // Wrapper específico para Póliza
    public class PolizaWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String estatus;
        @AuraEnabled public String moneda;
        @AuraEnabled public Decimal sumaAsegurada;
        @AuraEnabled public Date fechaEmision;
        @AuraEnabled public Date fechaVencimiento;
        @AuraEnabled public Decimal primaTotal;
        @AuraEnabled public String planProducto;

        public PolizaWrapper(Polizas__c p) {
            this.id = p.Id;
            this.name = p.Name;
            this.estatus = p.Estatus__c;
            this.moneda = p.Moneda__c;
            this.sumaAsegurada = p.Suma_Aseguradora__c;
            this.fechaEmision = p.Fecha_de_Emision__c;
            this.fechaVencimiento = p.Vigencia_hasta__c;
            this.primaTotal = p.Prima_Total__c;
            this.planProducto = p.Ramo__c;
        }
    }

    public class AseguradoWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Date fechaNacimiento;

        public AseguradoWrapper(Asegurado__c a) {
            id = a.Id;
            name = a.Name;
            fechaNacimiento = a.FechaNacimiento__c;
        }
    }

    public class HistoricoWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String anualidad;
        @AuraEnabled public Decimal primaBasica;
        @AuraEnabled public Decimal primaAdicional;
        @AuraEnabled public Decimal pagosIngresados;
        @AuraEnabled public Date desde;
        @AuraEnabled public Date hasta;

        public HistoricoWrapper(Historico_Aportacion__c h) {
            id = h.Id;
            name = h.Name;
            anualidad = h.Anualidad__c;
            primaBasica = h.PrimaBasica__c;
            primaAdicional = h.PrimaAdicional__c;
            pagosIngresados = h.PagosIngresados__c;
            desde = h.Desde__c;
            hasta = h.Hasta__c;
        }
    }

    public class PagoWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal importe;
        @AuraEnabled public String moneda;
        @AuraEnabled public Decimal valorMoneda;
        @AuraEnabled public Decimal pagoMXN;
        @AuraEnabled public String tipoPago;
        @AuraEnabled public Date fecha;
        @AuraEnabled public String estatusPago;

        public PagoWrapper(Pago_Poliza__c p) {
            id = p.Id;
            name = p.Name;
            importe = p.Importe_de_Ultima_Aportacion__c;
            moneda = p.Tipo_de_Moneda__c;
            valorMoneda = p.Valor_Moneda__c;
            pagoMXN = p.Pago_en_MXN__c;
            tipoPago = p.Tipo_de_pago__c;
            fecha = p.Fecha_de_emision__c;
            estatusPago = p.Estatus_del_Pago__c;
        }
    }
}