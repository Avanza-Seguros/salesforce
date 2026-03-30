public without sharing class BanxicoService {
    
    // Enum para los tipos de serie permitidos
    public enum TipoSerie { UDI, DLLS }
    
    // Clase para configuración
    public class ConfiguracionBanxico {
        @AuraEnabled
        public String token { get; set; }
        @AuraEnabled
        public Integer timeoutMs { get; set; }
        @AuraEnabled
        public String baseUrl { get; set; }
        
        public ConfiguracionBanxico() {
            // Valores por defecto actualizados
            this.token = 'ac14f32941ea8b61d77dfb8303760d1ef130dc8f0eb1fc736e94e9288ab164aa';
            this.timeoutMs = 30000; // Reducido a 30 segundos
            this.baseUrl = 'https://www.banxico.org.mx/SieAPIRest/service/v1/series';
        }
    }
    
    // Mapa de series permitidas actualizado
    private static Map<TipoSerie, String> SERIES_BANXICO = new Map<TipoSerie, String>{
        TipoSerie.UDI => 'SP68257',  // UDI
        TipoSerie.DLLS => 'SF63528'  // Tipo de cambio USD/MXN FIX
    };
    
    // Método principal para obtener UDI o DLLS
    public static Decimal obtenerValor(TipoSerie tipo) {
        if (!SERIES_BANXICO.containsKey(tipo)) {
            throw new IllegalArgumentException('Tipo de serie no válido: ' + tipo);
        }
        
        String serieId = SERIES_BANXICO.get(tipo);
        ConfiguracionBanxico config = new ConfiguracionBanxico();
        return obtenerValorSerie(serieId, config);
    }
    
    public static Decimal obtenerValor(TipoSerie tipo, ConfiguracionBanxico config) {
        if (!SERIES_BANXICO.containsKey(tipo)) {
            throw new IllegalArgumentException('Tipo de serie no válido: ' + tipo);
        }
        
        if (config == null) {
            config = new ConfiguracionBanxico();
        }
        
        String serieId = SERIES_BANXICO.get(tipo);
        return obtenerValorSerie(serieId, config);
    }
    
    // Método para obtener valor por string (case insensitive)
    public static Decimal obtenerValor(String tipoStr) {
        try {
            TipoSerie tipo = TipoSerie.valueOf(tipoStr.toUpperCase());
            return obtenerValor(tipo);
        } catch (Exception e) {
            throw new IllegalArgumentException('Tipo de serie no válido: ' + tipoStr + '. Valores permitidos: UDI, DLLS');
        }
    }
    
    // Método interno para obtener la serie - ACTUALIZADO
    private static Decimal obtenerValorSerie(String serieId, ConfiguracionBanxico config) {
        HttpRequest req = new HttpRequest();
        HttpResponse res = new HttpResponse();
        Http http = new Http();
        
        try {
            // Construir endpoint con parámetros correctos
            String endpoint = config.baseUrl + '/' + serieId + '/datos/oportuno';
            endpoint += '?token=' + EncodingUtil.urlEncode(config.token, 'UTF-8');
            
            System.debug('Endpoint: ' + endpoint);
            
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(config.timeoutMs);
            
            // Agregar headers necesarios
            req.setHeader('Accept', 'application/json');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Bmx-Token', config.token);
            
            // Realizar la llamada
            res = http.send(req);
            
            System.debug('Status Code: ' + res.getStatusCode());
            System.debug('Status: ' + res.getStatus());
            System.debug('Response Body: ' + res.getBody());
            
            if(res.getStatusCode() == 200) {
                return parsearRespuesta(res.getBody());
            } else {
                String errorMsg = 'Error en la respuesta: ' + res.getStatus() + 
                                '. Código: ' + res.getStatusCode() + 
                                '. Body: ' + res.getBody();
                System.debug(errorMsg);
                throw new CalloutException(errorMsg);
            }
            
        } catch (System.CalloutException e) {
            System.debug('Error de callout: ' + e.getMessage());
            System.debug('Response status: ' + res.getStatus());
            System.debug('Response code: ' + res.getStatusCode());
            return null;
        } catch (Exception e) {
            System.debug('Error general obteniendo valor de serie ' + serieId + ': ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            return null;
        }
    }
    
    // Método para parsear la respuesta - MEJORADO
    private static Decimal parsearRespuesta(String jsonResponse) {
        try {
            // Limpiar respuesta si es necesario
            if (jsonResponse.contains('<!DOCTYPE')) {
                System.debug('Respuesta parece ser HTML en lugar de JSON');
                return null;
            }
            
            Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(jsonResponse);
            
            // Verificar estructura de respuesta
            if (!responseMap.containsKey('bmx')) {
                System.debug('No se encontró el objeto bmx en la respuesta: ' + jsonResponse);
                return null;
            }
            
            Map<String, Object> bmxMap = (Map<String, Object>)responseMap.get('bmx');
            
            if (!bmxMap.containsKey('series')) {
                System.debug('No se encontró series en bmx: ' + jsonResponse);
                return null;
            }
            
            List<Object> seriesList = (List<Object>)bmxMap.get('series');
            if (seriesList == null || seriesList.isEmpty()) {
                System.debug('Lista de series vacía o nula');
                return null;
            }
            
            Map<String, Object> primeraSerie = (Map<String, Object>)seriesList[0];
            
            if (!primeraSerie.containsKey('datos')) {
                System.debug('No se encontró datos en la serie');
                return null;
            }
            
            List<Object> datos = (List<Object>)primeraSerie.get('datos');
            
            if (datos == null || datos.isEmpty()) {
                System.debug('No se encontraron datos en la serie');
                return null;
            }
            
            Map<String, Object> ultimoDato = (Map<String, Object>)datos[0];
            String valorString = (String)ultimoDato.get('dato');
            
            if (String.isBlank(valorString)) {
                System.debug('El valor del dato está vacío');
                return null;
            }
            
            // Limpiar y convertir el valor
            valorString = valorString.trim();
            
            // Manejar valores que pueden venir con formato mexicano
            valorString = valorString.replace(',', '');
            
            return Decimal.valueOf(valorString);
            
        } catch (Exception e) {
            System.debug('Error parseando respuesta JSON: ' + e.getMessage());
            System.debug('JSON que causó el error: ' + jsonResponse);
            return null;
        }
    }
    
    // ✅ MÉTODOS DE PRUEBA Y DIAGNÓSTICO
    
    // Método para probar la conexión con detalles
    public static Map<String, Object> probarConexion() {
        Map<String, Object> resultado = new Map<String, Object>();
        
        try {
            ConfiguracionBanxico config = new ConfiguracionBanxico();
            String endpoint = config.baseUrl + '/SP68257/datos/oportuno?token=' + EncodingUtil.urlEncode(config.token, 'UTF-8');
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(10000);
            req.setHeader('Accept', 'application/json');
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            resultado.put('statusCode', res.getStatusCode());
            resultado.put('status', res.getStatus());
            resultado.put('isSuccess', res.getStatusCode() == 200);
            resultado.put('responseLength', res.getBody()?.length());
            resultado.put('endpoint', endpoint);
            
            if (res.getStatusCode() != 200) {
                resultado.put('error', res.getBody());
            }
            
        } catch (Exception e) {
            resultado.put('error', e.getMessage());
            resultado.put('isSuccess', false);
        }
        
        return resultado;
    }
    
    // Método para obtener valores con manejo de errores mejorado
    public static Map<String, Object> obtenerValorConDetalles(TipoSerie tipo) {
        Map<String, Object> resultado = new Map<String, Object>();
        
        try {
            Decimal valor = obtenerValor(tipo);
            
            resultado.put('tipo', tipo.name());
            resultado.put('valor', valor);
            resultado.put('exito', valor != null);
            resultado.put('fecha', System.now());
            resultado.put('mensaje', valor != null ? 'Valor obtenido correctamente' : 'No se pudo obtener el valor');
            
        } catch (Exception e) {
            resultado.put('tipo', tipo.name());
            resultado.put('valor', null);
            resultado.put('exito', false);
            resultado.put('fecha', System.now());
            resultado.put('mensaje', 'Error: ' + e.getMessage());
            resultado.put('error', e.getStackTraceString());
        }
        
        return resultado;
    }
    
    // ✅ MÉTODOS ESPECÍFICOS CONVENCIONALES (mantenidos)
    
    public static Decimal obtenerUDI() {
        return obtenerValor(TipoSerie.UDI);
    }
    
    public static Decimal obtenerDLLS() {
        return obtenerValor(TipoSerie.DLLS);
    }
    
    // ✅ MÉTODO INVOCABLE PARA FLOW (actualizado)
    
    @InvocableMethod(label='Obtener UDI o DLLS desde Banxico' description='Devuelve el valor de UDI o DLLS según el tipo especificado. Valores permitidos: UDI, DLLS')
    public static List<ResultadoWrapper> obtenerValorBanxico(List<SolicitudWrapper> solicitudes) {
        List<ResultadoWrapper> resultados = new List<ResultadoWrapper>();
        
        for (SolicitudWrapper solicitud : solicitudes) {
            try {
                String tipo = solicitud.tipo;
                Map<String, Object> resultadoDetallado = obtenerValorConDetalles(TipoSerie.valueOf(tipo.toUpperCase()));
                
                resultados.add(new ResultadoWrapper(
                    tipo,
                    (Decimal)resultadoDetallado.get('valor'),
                    System.now(),
                    (Boolean)resultadoDetallado.get('exito'),
                    (String)resultadoDetallado.get('mensaje')
                ));
                
            } catch (Exception e) {
                System.debug('Error procesando solicitud: ' + e.getMessage());
                resultados.add(new ResultadoWrapper(
                    solicitud.tipo,
                    null,
                    System.now(),
                    false,
                    'Error: ' + e.getMessage()
                ));
            }
        }
        
        return resultados;
    }
    
    // ✅ CLASES WRAPPER PARA FLOW (actualizadas)
    
    public class SolicitudWrapper {
        @InvocableVariable(label='Tipo de valor a obtener' description='Valores permitidos: UDI, DLLS' required=true)
        public String tipo;
        
        public SolicitudWrapper() {
            // Constructor vacío para Flow
        }
        
        public SolicitudWrapper(String tipo) {
            this.tipo = tipo;
        }
    }
    
    public class ResultadoWrapper {
        @InvocableVariable(label='Tipo de valor obtenido')
        public String tipo;
        
        @InvocableVariable(label='Valor obtenido')
        public Decimal valor;
        
        @InvocableVariable(label='Fecha de obtención')
        public Datetime fechaObtencion;
        
        @InvocableVariable(label='¿Éxito en la operación?')
        public Boolean exito;
        
        @InvocableVariable(label='Mensaje de error')
        public String mensajeError;
        
        public ResultadoWrapper(String tipo, Decimal valor, Datetime fechaObtencion, Boolean exito, String mensajeError) {
            this.tipo = tipo;
            this.valor = valor;
            this.fechaObtencion = fechaObtencion;
            this.exito = exito;
            this.mensajeError = mensajeError;
        }
        
        public ResultadoWrapper() {
            this.fechaObtencion = System.now();
            this.exito = false;
        }
    }
    
    // ✅ MÉTODOS ADICIONALES MEJORADOS
    
    // Obtener ambos valores con manejo robusto
    public static Map<String, Object> obtenerAmbosValoresConDetalles() {
        Map<String, Object> resultados = new Map<String, Object>();
        
        resultados.put('UDI', obtenerValorConDetalles(TipoSerie.UDI));
        resultados.put('DLLS', obtenerValorConDetalles(TipoSerie.DLLS));
        resultados.put('fechaConsulta', System.now());
        resultados.put('version', '2.0');
        
        return resultados;
    }
    
    // Método para verificar el token
    public static Boolean validarToken() {
        Map<String, Object> prueba = probarConexion();
        return (Boolean)prueba.get('isSuccess');
    }
}