public class PolizaWrapper {
    public String poliza;
    public String numeroPolizas;
    public String aseguradora;
    public String tipo_seguro;
    public String plan;
    public String estatus;
    public Decimal suma_asegurada;
    public String moneda;
    public String forma_pago;
    public String agente;
    public String contratante;
    public String fecha_emision;
    public List<AseguradoWrapper> asegurados;
    public List<HistoricoAportacionWrapper> historico_aportaciones;
    
    public class AseguradoWrapper {
        public String nombre;
        public String fecha_nacimiento;
    }
    
    public class HistoricoAportacionWrapper {
        public String anualidad; // Cambiado de Integer a Decimal
        public Decimal prima_basica;
        public Decimal prima_adicional;
        public Decimal pagos_ingresados; // Cambiado de Integer a Decimal
        public String desde;
        public String hasta;
        public List<PagosPolizaWrapper> detalle_ingresos;
    }
    
    public class PagosPolizaWrapper {
        public String Fecha_de_ingreso;
        public Decimal Importe_pagado;
        public String Moneda;
        public String Tipo_de_pago;
        public String No_cuenta_No_cheque;
        public Decimal Tipo_cambio_del_pago;
        public Decimal Importe_USD;
    }
}