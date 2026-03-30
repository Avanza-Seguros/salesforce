@isTest
private with sharing class BanxicoExchangeRateServiceHistoricalTest {
    @IsTest
    static void testFetchHistoricalRates() {

        Test.setMock(HttpCalloutMock.class, new BanxicoHttpMock());

        Date startDate = Date.newInstance(2024,1,1);
        Date endDate   = Date.newInstance(2024,1,2);

        Test.startTest();
        BanxicoExchangeRateService.fetchHistoricalRates(startDate, endDate);
        Test.stopTest();

        List<Exchange_Rate_History__c> records = [SELECT Id FROM Exchange_Rate_History__c];

        Assert.isTrue(records.size() > 0);
    }
}