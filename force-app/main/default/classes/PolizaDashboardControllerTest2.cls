@IsTest
private class PolizaDashboardControllerTest2 {

    private static Pago_Poliza__c buildPago(Id polizaId, Date venc, Date pago, Decimal monto, Decimal mxn, String comentario) {
        Pago_Poliza__c p = new Pago_Poliza__c();
        p.Poliza__c = polizaId;

        p.Fecha_de_de_Vencimiento__c = venc;
        p.Fecha_de_Aplicaci_n_del_pago__c = pago;

        p.Monto__c = monto;

        p.Tipo_de_Moneda__c = 'MXN';
        p.Valor_Moneda__c = 1;

        p.Estatus_Pago__c = 'Pendiente';
        p.Estatus_Poliza_Actual__c = 'Vigor';

        p.Comentarios__c = comentario;
        p.Forma_pago__c = 'Mensual';
        p.Modo_de_Pago__c = 'Transferencia';
        p.Canal_de_Cobro__c = 'Test';
        p.Aseguradora__c = 'Test';
        p.Ramo__c = 'Test';
        p.Folio__c = 'F-1';
        p.Numero_de_Pago__c = '1';

        return p;
    }

    @TestSetup
    static void setup() {
        Account asegurado = new Account(Name='Asegurado Modal Test');
        insert asegurado;

        Date vigDesde = Date.today().addMonths(-6);
        Date vigHasta = Date.today().addMonths(6);

        Polizas__c pol = new Polizas__c(
            Name = 'POL-TEST-MODAL',
            Estatus__c = 'Vigor',
            Aseguradora__c = 'Afirme',
            Forma_de_pago__c = 'Mensual',
            Vigencia_desde__c = vigDesde,
            Vigencia_hasta__c = vigHasta,
            Prima_Anual__c = 1200
        );

        insert pol;

        Date mes1 = Date.today().addMonths(-1);
        Date mes2 = Date.today().addMonths(-2);

        List<Pago_Poliza__c> pagos = new List<Pago_Poliza__c>();
        pagos.add(buildPago(pol.Id, mes2.addDays(10), mes2.addDays(12), 100, 100, 'coment viejo'));
        pagos.add(buildPago(pol.Id, mes1.addDays(10), mes1.addDays(12), 200, 200, 'coment nuevo'));
        insert pagos;
    }

    @IsTest
    static void testObtenerPagosDePoliza_blank() {
        Test.startTest();
        List<PolizaDashboardController.PagoPolizaDTO> res =
            PolizaDashboardController.obtenerPagosDePoliza(null);
        Test.stopTest();

        Assert.isNotNull(res, 'La lista no debe ser null');
        Assert.areEqual(0, res.size(), 'Si numeroPoliza es blank debe devolver lista vacía');
    }

    @IsTest
    static void testObtenerPagosDePoliza_ok() {
        Test.startTest();
        List<PolizaDashboardController.PagoPolizaDTO> res =
            PolizaDashboardController.obtenerPagosDePoliza('POL-TEST-MODAL');
        Test.stopTest();

        Assert.isTrue(res.size() >= 2, 'Debe traer los pagos de la póliza');

        PolizaDashboardController.PagoPolizaDTO primero = res[0];
        PolizaDashboardController.PagoPolizaDTO segundo = res[1];

        Assert.isNotNull(primero.id, 'El id del primer DTO no debe ser null');
        Assert.isNotNull(primero.name, 'El name del primer DTO no debe ser null');

        Assert.isNotNull(primero.fechaPago, 'La fechaPago del primer DTO no debe ser null');
        Assert.isNotNull(primero.fechaVencimiento, 'La fechaVencimiento del primer DTO no debe ser null');

        Assert.isTrue(primero.fechaPago >= segundo.fechaPago, 'Debe ordenar por fechaPago DESC');

        Assert.isNotNull(primero.monto, 'El monto del primer DTO no debe ser null');
        Assert.areEqual('MXN', primero.moneda, 'La moneda debe ser MXN');
        Assert.isNotNull(primero.montoMXN, 'El montoMXN no debe ser null');
        Assert.isNotNull(primero.estatusPago, 'El estatusPago no debe ser null');
    }

    @IsTest
    static void testActualizarComentariosPago_nullOrEmpty() {
        Test.startTest();
        PolizaDashboardController.actualizarComentariosPago(null);
        PolizaDashboardController.actualizarComentariosPago(new Map<Id, String>());
        Test.stopTest();

        Assert.isTrue(true, 'No debe lanzar excepción con map null o vacío');
    }

    @IsTest
    static void testActualizarComentariosPago_ok() {
        Pago_Poliza__c pago = [
            SELECT Id, Comentarios__c
            FROM Pago_Poliza__c
            LIMIT 1
        ];

        Map<Id, String> cambios = new Map<Id, String>();
        cambios.put(pago.Id, 'comentario actualizado desde test');

        Test.startTest();
        PolizaDashboardController.actualizarComentariosPago(cambios);
        Test.stopTest();

        Pago_Poliza__c actualizado = [
            SELECT Id, Comentarios__c
            FROM Pago_Poliza__c
            WHERE Id = :pago.Id
        ];

        Assert.areEqual('comentario actualizado desde test', actualizado.Comentarios__c);
    }
}