@isTest
private with sharing class BanxicoExchangeRateServiceLatestTest {
    
    @IsTest
    static void testFetchLatestRates() {

        Test.setMock(HttpCalloutMock.class, new BanxicoHttpMock());

        Test.startTest();
        BanxicoExchangeRateService.fetchLatestRates();
        Test.stopTest();

        List<Exchange_Rate_History__c> records = [
            SELECT Id, RateDate__c, RateValue__c, CurrencyType__c
            FROM Exchange_Rate_History__c
        ];

        Assert.areEqual(2, [SELECT COUNT() FROM Exchange_Rate_History__c WHERE CurrencyType__c = 'USD']);
        Assert.areEqual(2, [SELECT COUNT() FROM Exchange_Rate_History__c WHERE CurrencyType__c = 'UDI']);
    }
}