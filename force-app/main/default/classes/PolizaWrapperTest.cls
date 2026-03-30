@IsTest
public class PolizaWrapperTest {
    
    @IsTest
    static void testPolizaWrapperConstructorAndSetters() {
        // Test constructor por defecto y setters
        PolizaWrapper wrapper = new PolizaWrapper();
        
        // Establecer valores
        wrapper.poliza = 'POL-123456';
        wrapper.numeroPolizas = '1';
        wrapper.aseguradora = 'Seguros Test';
        wrapper.tipo_seguro = 'Vida';
        wrapper.plan = 'Plan Básico';
        wrapper.estatus = 'Activa';
        wrapper.suma_asegurada = 1000000.00;
        wrapper.moneda = 'MXN';
        wrapper.forma_pago = 'Anual';
        wrapper.agente = 'Juan Pérez';
        wrapper.contratante = 'María García';
        wrapper.fecha_emision = '2024-01-15';
        
        // Verificar valores
        System.assertEquals('POL-123456', wrapper.poliza, 'El número de póliza debe coincidir');
        System.assertEquals('Seguros Test', wrapper.aseguradora, 'La aseguradora debe coincidir');
        System.assertEquals(1000000.00, wrapper.suma_asegurada, 'La suma asegurada debe coincidir');
        System.assertEquals('MXN', wrapper.moneda, 'La moneda debe coincidir');
    }
    
    @IsTest
    static void testAseguradoWrapper() {
        // Test AseguradoWrapper
        PolizaWrapper.AseguradoWrapper asegurado = new PolizaWrapper.AseguradoWrapper();
        asegurado.nombre = 'Carlos López';
        asegurado.fecha_nacimiento = '1990-05-20';
        
        System.assertEquals('Carlos López', asegurado.nombre, 'El nombre del asegurado debe coincidir');
        System.assertEquals('1990-05-20', asegurado.fecha_nacimiento, 'La fecha de nacimiento debe coincidir');
    }
    
    @IsTest
    static void testHistoricoAportacionWrapper() {
        // Test HistoricoAportacionWrapper
        PolizaWrapper.HistoricoAportacionWrapper historico = new PolizaWrapper.HistoricoAportacionWrapper();
        historico.anualidad = '2024';
        historico.prima_basica = 5000.00;
        historico.prima_adicional = 1000.00;
        historico.pagos_ingresados = 6000.00;
        historico.desde = '2024-01-01';
        historico.hasta = '2024-12-31';
        
        System.assertEquals('2024', historico.anualidad, 'La anualidad debe coincidir');
        System.assertEquals(5000.00, historico.prima_basica, 'La prima básica debe coincidir');
        System.assertEquals(1000.00, historico.prima_adicional, 'La prima adicional debe coincidir');
        System.assertEquals(6000.00, historico.pagos_ingresados, 'Los pagos ingresados deben coincidir');
    }
    
    @IsTest
    static void testPagosPolizaWrapper() {
        // Test PagosPolizaWrapper
        PolizaWrapper.PagosPolizaWrapper pago = new PolizaWrapper.PagosPolizaWrapper();
        pago.Fecha_de_ingreso = '2024-01-15';
        pago.Importe_pagado = 1500.00;
        pago.Moneda = 'MXN';
        pago.Tipo_de_pago = 'Transferencia';
        pago.No_cuenta_No_cheque = '1234567890';
        pago.Tipo_cambio_del_pago = 17.50;
        pago.Importe_USD = 85.71;
        
        System.assertEquals('2024-01-15', pago.Fecha_de_ingreso, 'La fecha de ingreso debe coincidir');
        System.assertEquals(1500.00, pago.Importe_pagado, 'El importe pagado debe coincidir');
        System.assertEquals('Transferencia', pago.Tipo_de_pago, 'El tipo de pago debe coincidir');
        System.assertEquals(17.50, pago.Tipo_cambio_del_pago, 'El tipo de cambio debe coincidir');
        System.assertEquals(85.71, pago.Importe_USD, 'El importe en USD debe coincidir');
    }
    
    @IsTest
    static void testCompletePolizaWrapperStructure() {
        // Test de estructura completa con listas
        PolizaWrapper polizaCompleta = new PolizaWrapper();
        
        // Datos básicos de la póliza
        polizaCompleta.poliza = 'POL-789012';
        polizaCompleta.aseguradora = 'Aseguradora Completa';
        polizaCompleta.suma_asegurada = 2000000.00;
        
        // Crear lista de asegurados
        polizaCompleta.asegurados = new List<PolizaWrapper.AseguradoWrapper>();
        
        PolizaWrapper.AseguradoWrapper asegurado1 = new PolizaWrapper.AseguradoWrapper();
        asegurado1.nombre = 'Ana Rodríguez';
        asegurado1.fecha_nacimiento = '1985-08-12';
        
        PolizaWrapper.AseguradoWrapper asegurado2 = new PolizaWrapper.AseguradoWrapper();
        asegurado2.nombre = 'Pedro Sánchez';
        asegurado2.fecha_nacimiento = '1988-03-25';
        
        polizaCompleta.asegurados.add(asegurado1);
        polizaCompleta.asegurados.add(asegurado2);
        
        // Crear histórico de aportaciones
        polizaCompleta.historico_aportaciones = new List<PolizaWrapper.HistoricoAportacionWrapper>();
        
        PolizaWrapper.HistoricoAportacionWrapper historico = new PolizaWrapper.HistoricoAportacionWrapper();
        historico.anualidad = '2024';
        historico.prima_basica = 7500.00;
        historico.prima_adicional = 1500.00;
        historico.pagos_ingresados = 9000.00;
        historico.desde = '2024-01-01';
        historico.hasta = '2024-12-31';
        
        // Crear detalle de pagos
        historico.detalle_ingresos = new List<PolizaWrapper.PagosPolizaWrapper>();
        
        PolizaWrapper.PagosPolizaWrapper pago1 = new PolizaWrapper.PagosPolizaWrapper();
        pago1.Fecha_de_ingreso = '2024-01-10';
        pago1.Importe_pagado = 4500.00;
        pago1.Moneda = 'MXN';
        pago1.Tipo_de_pago = 'Cheque';
        
        PolizaWrapper.PagosPolizaWrapper pago2 = new PolizaWrapper.PagosPolizaWrapper();
        pago2.Fecha_de_ingreso = '2024-07-10';
        pago2.Importe_pagado = 4500.00;
        pago2.Moneda = 'MXN';
        pago2.Tipo_de_pago = 'Transferencia';
        
        historico.detalle_ingresos.add(pago1);
        historico.detalle_ingresos.add(pago2);
        
        polizaCompleta.historico_aportaciones.add(historico);
        
        // Verificaciones
        System.assertEquals(2, polizaCompleta.asegurados.size(), 'Debe haber 2 asegurados');
        System.assertEquals(1, polizaCompleta.historico_aportaciones.size(), 'Debe haber 1 histórico de aportaciones');
        System.assertEquals(2, polizaCompleta.historico_aportaciones[0].detalle_ingresos.size(), 'Debe haber 2 pagos en el detalle');
        
        // Verificar datos específicos
        System.assertEquals('Ana Rodríguez', polizaCompleta.asegurados[0].nombre, 'El primer asegurado debe ser Ana Rodríguez');
        System.assertEquals(7500.00, polizaCompleta.historico_aportaciones[0].prima_basica, 'La prima básica debe ser 7500.00');
        System.assertEquals('Cheque', polizaCompleta.historico_aportaciones[0].detalle_ingresos[0].Tipo_de_pago, 'El primer pago debe ser por cheque');
    }
    
    @IsTest
    static void testEdgeCases() {
        // Test casos límite y valores nulos
        PolizaWrapper wrapper = new PolizaWrapper();
        
        // Verificar que no hay excepciones con valores nulos
        System.assertEquals(null, wrapper.poliza, 'La póliza debe ser null por defecto');
        System.assertEquals(null, wrapper.asegurados, 'La lista de asegurados debe ser null por defecto');
        System.assertEquals(null, wrapper.historico_aportaciones, 'El histórico debe ser null por defecto');
        
        // Test con valores decimales extremos
        PolizaWrapper.HistoricoAportacionWrapper historico = new PolizaWrapper.HistoricoAportacionWrapper();
        historico.prima_basica = 0.00;
        historico.prima_adicional = 999999999.99;
        historico.pagos_ingresados = 1000000000.00;
        
        System.assertEquals(0.00, historico.prima_basica, 'La prima básica debe ser 0.00');
        System.assertEquals(999999999.99, historico.prima_adicional, 'La prima adicional debe ser 999999999.99');
    }
    
    @IsTest
    static void testSerialization() {
        // Test para verificar que los objetos pueden ser serializados (importante para APIs)
        PolizaWrapper wrapper = createTestPolizaWrapper();
        
        // Intentar serializar a JSON
        String jsonString;
        try {
            jsonString = JSON.serialize(wrapper);
            System.assertNotEquals(null, jsonString, 'La serialización no debe retornar null');
            System.assert(jsonString.length() > 0, 'El JSON serializado no debe estar vacío');
        } catch (Exception e) {
            System.assert(false, 'No debería haber excepción en la serialización: ' + e.getMessage());
        }
        
        // Intentar deserializar
        try {
            PolizaWrapper deserializedWrapper = (PolizaWrapper) JSON.deserialize(jsonString, PolizaWrapper.class);
            System.assertNotEquals(null, deserializedWrapper, 'La deserialización no debe retornar null');
            System.assertEquals('TEST-001', deserializedWrapper.poliza, 'La póliza deserializada debe coincidir');
        } catch (Exception e) {
            System.assert(false, 'No debería haber excepción en la deserialización: ' + e.getMessage());
        }
    }
    
    // Método helper para crear una póliza de prueba
    private static PolizaWrapper createTestPolizaWrapper() {
        PolizaWrapper wrapper = new PolizaWrapper();
        wrapper.poliza = 'TEST-001';
        wrapper.aseguradora = 'Test Aseguradora';
        wrapper.tipo_seguro = 'Test';
        wrapper.suma_asegurada = 500000.00;
        wrapper.moneda = 'USD';
        
        return wrapper;
    }
}