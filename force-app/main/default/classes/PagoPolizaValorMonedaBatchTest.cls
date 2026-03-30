@isTest
public with sharing class PagoPolizaValorMonedaBatchTest {
    
    @TestSetup
    static void setupData() {

        Date todayDate = Date.today();
        Date oldDate = todayDate.addDays(-10);

        List<Exchange_Rate_History__c> rates = new List<Exchange_Rate_History__c>();

        Exchange_Rate_History__c r1 = new Exchange_Rate_History__c(
            CurrencyType__c = 'UDI',
            RateValue__c = 7,
            RateDate__c = oldDate,
            UniqueKey__c = 'UDI_' + String.valueOf(oldDate)
        );

        rates.add(r1);

        Exchange_Rate_History__c r2 = new Exchange_Rate_History__c(
            CurrencyType__c = 'UDI',
            RateValue__c = 10,
            RateDate__c = todayDate,
            UniqueKey__c = 'UDI_' + String.valueOf(todayDate)
        );
        rates.add(r2);

        Exchange_Rate_History__c r3 = new Exchange_Rate_History__c(
            CurrencyType__c = 'USD',
            RateValue__c = 20,
            RateDate__c = todayDate,
            UniqueKey__c = 'USD_' + String.valueOf(todayDate)
        );
        rates.add(r3);

        insert rates;

        List<Polizas__c> listaPolizas = new List<Polizas__c>();

        Polizas__c poliza1 = new Polizas__c(
            Name = '100001',
            Aseguradora__c = 'AXA',
            Moneda__c = 'UDIS',
            Estatus__c = 'Vigor',
            Fecha_de_Emision__c = todayDate.addDays(-110),
            Vigencia_desde__c = todayDate.addDays(-100),
            Vigencia_hasta__c = todayDate.addDays(-100).addMonths(12),
            Prima_Anual__c = 1500
        );
        listaPolizas.add(poliza1);

        Polizas__c poliza2 = new Polizas__c(
            Name = '100002',
            Aseguradora__c = 'Mapfre',
            Moneda__c = 'DLLS',
            Estatus__c = 'Vigor',
            Fecha_de_Emision__c = todayDate.addDays(-120),
            Vigencia_desde__c = todayDate.addDays(-110),
            Vigencia_hasta__c = todayDate.addDays(-110).addMonths(12),
            Prima_Anual__c = 1000
        );
        listaPolizas.add(poliza2);

        insert listaPolizas;

        List<Pago_Poliza__c> listaPagoPolizas = new List<Pago_Poliza__c>();

        Pago_Poliza__c pago1 = new Pago_Poliza__c(
            Poliza__c = poliza1.Id,
            Estatus_pago__c = 'Pendiente',
            Fecha_de_de_Vencimiento__c = Date.today().addMonths(1),
            Monto__c = 1500/12,
            Tipo_de_moneda__c = 'UDIS',
            Canal_de_Cobro__c = 'TARJETA DE CREDITO',
            Forma_pago__c = 'Anual'
        );
        listaPagoPolizas.add(pago1);

        Pago_Poliza__c pago2 = new Pago_Poliza__c(
            Poliza__c = poliza2.Id,
            Estatus_pago__c = 'Pagado',
            Fecha_de_Aplicaci_n_del_pago__c = Date.today().addDays(-100),
            Fecha_de_de_Vencimiento__c = Date.today().addMonths(-80),
            Monto__c = 1000/12,
            Tipo_de_moneda__c = 'USD',
            Canal_de_Cobro__c = 'TARJETA DE DEBITO',
            Forma_pago__c = 'Mensual'
        );
        listaPagoPolizas.add(pago2);

        insert listaPagoPolizas;

    }

    @IsTest
    static void testHistorico() {

        Test.startTest();
        Database.executeBatch(new PagoPolizaValorMonedaBatch(true), 200);
        Test.stopTest();

        List<Pago_Poliza__c> pagos = [
            SELECT Valor_Moneda__c
            FROM Pago_Poliza__c
        ];

        Assert.isTrue(pagos[0].Valor_Moneda__c != null);
    }

    @IsTest
    static void testDiario() {

        Test.startTest();
        Database.executeBatch(new PagoPolizaValorMonedaBatch(false), 200);
        Test.stopTest();

        List<Pago_Poliza__c> pagos = [
            SELECT Valor_Moneda__c
            FROM Pago_Poliza__c
        ];

        Assert.isTrue(pagos.size() > 0);
    }

    @IsTest
    static void testSchedule() {

        Test.startTest();

        String cron = '0 0 2 * * ?';
        System.schedule('Test Pago Scheduler', cron, new PagoPolizaValorMonedaScheduler());

        Test.stopTest();

        Assert.isTrue(true);
    }
}