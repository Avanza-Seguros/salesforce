public without sharing class BanxicoFlowSimple {
    
    @InvocableMethod(label='Obtener Valores Banxico' description='Obtiene valores de UDI y USD de Banxico sin actualizar registros')
    public static List<ResultadoFlow> obtenerValoresBanxico() {
        List<ResultadoFlow> resultados = new List<ResultadoFlow>();
        
        // Obtener valores de Banxico
        Decimal valorUDI = BanxicoService.obtenerUDI();
        Decimal valorDLLS = BanxicoService.obtenerDLLS();
        
        String mensaje = 'Consulta exitosa - ';
        Boolean exito = true;
        
        if (valorUDI == null && valorDLLS == null) {
            exito = false;
            mensaje = 'No se pudieron obtener los valores de Banxico';
        } else {
            if (valorUDI != null) {
                mensaje += 'UDI: ' + valorUDI + '; ';
            } else {
                mensaje += 'UDI: N/A; ';
            }
            
            if (valorDLLS != null) {
                mensaje += 'USD: ' + valorDLLS + '; ';
            } else {
                mensaje += 'USD: N/A; ';
            }
        }
        
        resultados.add(new ResultadoFlow(
            exito,
            mensaje,
            valorDLLS,
            valorUDI
        ));
        
        return resultados;
    }
    
    // CLASE RESULTADO SIN RECORD_ID
    public class ResultadoFlow {
        @InvocableVariable(label='Éxito')
        public Boolean exito;
        
        @InvocableVariable(label='Mensaje')
        public String mensaje;
        
        @InvocableVariable(label='Valor DLLS')
        public Decimal valorDLLS;
        
        @InvocableVariable(label='Valor UDI')
        public Decimal valorUDI;
        
        public ResultadoFlow(Boolean exito, String mensaje, Decimal valorDLLS, Decimal valorUDI) {
            this.exito = exito;
            this.mensaje = mensaje;
            this.valorDLLS = valorDLLS;
            this.valorUDI = valorUDI;
        }
    }
}