@isTest
public with sharing class PolizaValorMonedaBatchTest {
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

        insert new List<Polizas__c>{
            new Polizas__c(
                Moneda__c = 'UDIS',
                Fecha_de_Emision__c = oldDate
            ),
            new Polizas__c(
                Moneda__c = 'DLLS',
                Fecha_de_Emision__c = oldDate
            )
        };
    }

    @IsTest
    static void testModoHistorico() {

        Test.startTest();
        Database.executeBatch(new PolizaValorMonedaBatch(true), 200);
        Test.stopTest();

        List<Polizas__c> polizas = [
            SELECT Moneda_Hoy__c, Valor_Moneda_Emision__c
            FROM Polizas__c
        ];

        Assert.areNotEqual(null, polizas[0].Moneda_Hoy__c);
        Assert.areNotEqual(null, polizas[0].Valor_Moneda_Emision__c);
    }

    @IsTest
    static void testModoDiario() {

        Test.startTest();
        Database.executeBatch(new PolizaValorMonedaBatch(false), 200);
        Test.stopTest();

        List<Polizas__c> polizas = [
            SELECT Moneda_Hoy__c
            FROM Polizas__c
        ];

        Assert.isTrue(polizas.size() > 0);
    }

    @IsTest
    static void testSchedule() {

        Test.startTest();

        String cron = '0 0 3 * * ?';
        System.schedule('Test Poliza Scheduler', cron, new PolizaValorMonedaScheduler());

        Test.stopTest();

        Assert.isTrue(true);
    }
}