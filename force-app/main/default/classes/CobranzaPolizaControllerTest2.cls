@isTest
public with sharing class CobranzaPolizaControllerTest2 {

    private static Date monthKey(Date d) {
        return Date.newInstance(d.year(), d.month(), 1);
    }
    private static Date endOfMonth(Date d) {
        Date m = monthKey(d);
        return m.addMonths(1).addDays(-1);
    }

    private static Pago_Poliza__c buildPago(
        Id polizaId,
        Date venc,
        Date aplic,
        String estatus,
        Decimal monto,
        String moneda,
        Decimal valorMoneda
    ) {
        Pago_Poliza__c p = new Pago_Poliza__c();
        p.Poliza__c = polizaId;
        p.Fecha_de_de_Vencimiento__c = venc;
        p.Fecha_de_Aplicaci_n_del_pago__c = aplic;
        p.Estatus_pago__c = estatus;
        p.Monto__c = monto;
        p.Tipo_de_Moneda__c = moneda;
        p.Valor_Moneda__c = valorMoneda;
        return p;
    }

    @TestSetup
    static void setupData() {
        List<Exchange_Rate_History__c> rates = new List<Exchange_Rate_History__c>();
        rates.add(new Exchange_Rate_History__c(
            CurrencyType__c='USD',
            RateValue__c=17.677,
            RateDate__c=Date.today(),
            SeriesCode__c='TEST',
            Source__c='TEST',
            UniqueKey__c='USD_' + String.valueOf(Date.today())
        ));
        rates.add(new Exchange_Rate_History__c(
            CurrencyType__c='UDI',
            RateValue__c=7.1234,
            RateDate__c=Date.today(),
            SeriesCode__c='TEST',
            Source__c='TEST',
            UniqueKey__c='UDI_' + String.valueOf(Date.today())
        ));
        insert rates;

        Account a = new Account(Name='Asegurado Test');
        insert a;

        Date vigDesde = monthKey(Date.today().addMonths(-10));
        Date vigHasta = vigDesde.addMonths(12).addDays(-1);

        Polizas__c polA = new Polizas__c(
            Name='POL-A',
            Asegurado__c=a.Id,
            Vigencia_desde__c=vigDesde,
            Vigencia_hasta__c=vigHasta,
            Forma_de_pago__c='Mensual',
            Prima_Anual__c=1200,
            Estatus__c='Vigor',
            Moneda__c='Pesos'
        );
        insert polA;

        Date mesMix = monthKey(vigDesde.addMonths(2));
        List<Pago_Poliza__c> pagosA = new List<Pago_Poliza__c>();
        pagosA.add(buildPago(polA.Id, mesMix.addDays(5), mesMix.addDays(6), 'Pagado', 100, 'MXN', 1));
        pagosA.add(buildPago(polA.Id, mesMix.addDays(15), null, 'Pendiente', 100, 'MXN', 1));

        Date mesCancel = monthKey(vigDesde.addMonths(3));
        pagosA.add(buildPago(polA.Id, mesCancel.addDays(5), null, 'Cancelado', 999, 'MXN', 1));

        Date mesPosterior = monthKey(vigDesde.addMonths(4));
        pagosA.add(buildPago(polA.Id, mesPosterior.addDays(5), null, 'Pendiente', 50, 'MXN', 1));

        insert pagosA;

        Polizas__c polB = new Polizas__c(
            Name='POL-B',
            Asegurado__c=a.Id,
            Vigencia_desde__c=vigDesde,
            Vigencia_hasta__c=vigHasta,
            Forma_de_pago__c='Mensual',
            Prima_Anual__c=1200,
            Estatus__c='Cancelada',
            Moneda__c='Pesos'
        );
        insert polB;

        Date mesB = monthKey(vigDesde.addMonths(1));
        insert new List<Pago_Poliza__c>{
            buildPago(polB.Id, mesB.addDays(5), null, 'Vencida', 200, 'MXN', 1)
        };

        Polizas__c polC = new Polizas__c(
            Name='POL-C',
            Asegurado__c=a.Id,
            Vigencia_desde__c=vigDesde,
            Vigencia_hasta__c=vigHasta,
            Forma_de_pago__c='Mensual',
            Prima_Anual__c=1200,
            Estatus__c='Vigor',
            Moneda__c='Pesos'
        );
        insert polC;

        Date ultimoMesAnio = monthKey(vigDesde.addMonths(11));
        insert new List<Pago_Poliza__c>{
            buildPago(polC.Id, ultimoMesAnio.addDays(1), ultimoMesAnio.addDays(2), 'Pagado', 100, 'MXN', 1)
        };

        Polizas__c polD = new Polizas__c(
            Name='POL-D',
            Asegurado__c=a.Id,
            Vigencia_desde__c=vigDesde,
            Vigencia_hasta__c=vigHasta,
            Forma_de_pago__c='Mensual',
            Prima_Anual__c=1200,
            Estatus__c='Vigor',
            Moneda__c='Pesos'
        );
        insert polD;

        List<Pago_Poliza__c> pagosD = new List<Pago_Poliza__c>();
        for (Integer i = 0; i < 11; i++) {
            Date m = monthKey(vigDesde.addMonths(i));
            pagosD.add(buildPago(polD.Id, m.addDays(5), m.addDays(6), 'Pagado', 100, 'MXN', 1));
        }
        Date spillVenc = vigHasta.addDays(5);
        pagosD.add(buildPago(polD.Id, spillVenc, null, 'Pendiente', 100, 'MXN', 1));
        insert pagosD;
    }

    @IsTest
    static void testPagadoPendienteMismoMes_yCanceladoIntermedioFiltrado() {
        Polizas__c polA = [SELECT Id, Vigencia_desde__c FROM Polizas__c WHERE Name='POL-A' LIMIT 1];

        Date mesMix = monthKey(polA.Vigencia_desde__c.addMonths(2));
        Date desde = mesMix;
        Date hasta = endOfMonth(mesMix);

        Test.startTest();
        List<CobranzaPolizaController.ProyeccionCobranzaDTO> res =
            CobranzaPolizaController.obtenerProyeccionCobranza(desde, hasta);
        Test.stopTest();

        List<CobranzaPolizaController.ProyeccionCobranzaDTO> filas = new List<CobranzaPolizaController.ProyeccionCobranzaDTO>();
        for (CobranzaPolizaController.ProyeccionCobranzaDTO d : res) {
            if (d.polizaId == polA.Id) filas.add(d);
        }

        Assert.areEqual(1, filas.size(), 'Debe agrupar en 1 fila por mes para POL-A');

        CobranzaPolizaController.ProyeccionCobranzaDTO dto = filas[0];
        Assert.areEqual(true, dto.esPagoReal);
        Assert.areEqual(true, dto.estaPagado);
        Assert.areEqual(true, dto.tieneMontoPendiente);
        Assert.areEqual(200, dto.monto);
        Assert.areEqual('Pagado', dto.estatusRecibo);

        Date mesCancel = monthKey(polA.Vigencia_desde__c.addMonths(3));

        List<CobranzaPolizaController.ProyeccionCobranzaDTO> res2 =
            CobranzaPolizaController.obtenerProyeccionCobranza(mesCancel, endOfMonth(mesCancel));

        Boolean vioMonto999 = false;
        for (CobranzaPolizaController.ProyeccionCobranzaDTO d : res2) {
            if (d.polizaId == polA.Id && d.monto != null && d.monto >= 900) {
                vioMonto999 = true;
            }
        }
        Assert.areEqual(false, vioMonto999, 'El cancelado intermedio debe ser filtrado');
    }

    @IsTest
    static void testPolizaInactiva_NoProyecta() {
        Polizas__c polB = [SELECT Id, Vigencia_desde__c FROM Polizas__c WHERE Name='POL-B' LIMIT 1];

        Date mesB = monthKey(polB.Vigencia_desde__c.addMonths(1));
        Date desde = mesB;
        Date hasta = endOfMonth(mesB);

        Test.startTest();
        List<CobranzaPolizaController.ProyeccionCobranzaDTO> res =
            CobranzaPolizaController.obtenerProyeccionCobranza(desde, hasta);
        Test.stopTest();

        Integer countPolB = 0;
        for (CobranzaPolizaController.ProyeccionCobranzaDTO d : res) {
            if (d.polizaId != polB.Id) continue;
            countPolB++;
            Assert.areEqual(true, d.esPolizaInactiva);
            Assert.areEqual(true, d.esPagoReal);
        }
        Assert.isTrue(countPolB > 0, 'Debe devolver al menos un registro real para poliza inactiva');
    }

    @IsTest
    static void testArrastre_SeMuestra() {
        Polizas__c polC = [SELECT Id, Vigencia_desde__c, Vigencia_hasta__c FROM Polizas__c WHERE Name='POL-C' LIMIT 1];

        Date inicioNuevaVig = polC.Vigencia_hasta__c.addDays(1);
        Date mesNueva = monthKey(inicioNuevaVig);

        Date desde = mesNueva;
        Date hasta = endOfMonth(mesNueva.addMonths(2));

        Test.startTest();
        List<CobranzaPolizaController.ProyeccionCobranzaDTO> res =
            CobranzaPolizaController.obtenerProyeccionCobranza(desde, hasta);
        Test.stopTest();

        CobranzaPolizaController.ProyeccionCobranzaDTO dtoMes1 = null;
        for (CobranzaPolizaController.ProyeccionCobranzaDTO d : res) {
            if (d.polizaId == polC.Id && d.fechaEsperadaPago == mesNueva) {
                dtoMes1 = d;
                break;
            }
        }

        Assert.isNotNull(dtoMes1, 'Debe existir fila para el primer mes de la nueva vigencia');
        Assert.areEqual(true, dtoMes1.tieneArrastre, 'Debe marcar arrastre');
        Assert.areEqual('Pendiente', dtoMes1.estatusRecibo);
        Assert.isTrue(dtoMes1.monto > 0, 'Debe tener monto > 0');
    }

    @IsTest
    static void testCruceNuevaVigencia_MezclaRealYProyeccion() {
        Polizas__c polD = [SELECT Id, Vigencia_hasta__c FROM Polizas__c WHERE Name='POL-D' LIMIT 1];

        Date inicioNuevaVig = polD.Vigencia_hasta__c.addDays(1);
        Date mesNueva = monthKey(inicioNuevaVig);

        Date desde = mesNueva;
        Date hasta = endOfMonth(mesNueva);

        Test.startTest();
        List<CobranzaPolizaController.ProyeccionCobranzaDTO> res =
            CobranzaPolizaController.obtenerProyeccionCobranza(desde, hasta);
        Test.stopTest();

        CobranzaPolizaController.ProyeccionCobranzaDTO dto = null;
        for (CobranzaPolizaController.ProyeccionCobranzaDTO d : res) {
            if (d.polizaId == polD.Id && d.fechaEsperadaPago == mesNueva) {
                dto = d;
                break;
            }
        }

        Assert.isNotNull(dto, 'Debe devolver fila para el mes de nueva vigencia');
        Assert.areEqual(true, dto.tieneMezclaVigencia);
        Assert.areEqual(true, dto.esPagoReal);
        Assert.areEqual(false, dto.estaPagado);
        Assert.areEqual(true, dto.esNuevaVigencia);
        Assert.isTrue(dto.monto > 0, 'Debe sumar real + proyección');
    }
}