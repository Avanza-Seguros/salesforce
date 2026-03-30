@isTest
private with sharing class BanxicoQueueableTest {
    private static void cleanupHistory() {
        List<Exchange_Rate_History__c> recs = [SELECT Id FROM Exchange_Rate_History__c];
        if (!recs.isEmpty()) delete recs;
    }

    @IsTest
    static void testDailyQueueableExecutesCallout() {
        cleanupHistory();
        Test.setMock(HttpCalloutMock.class, new BanxicoHttpMock());

        Test.startTest();
        System.enqueueJob(new BanxicoQueueable());
        Test.stopTest();

        Assert.areEqual(2, [SELECT COUNT() FROM Exchange_Rate_History__c WHERE CurrencyType__c = 'USD']);
        Assert.areEqual(2, [SELECT COUNT() FROM Exchange_Rate_History__c WHERE CurrencyType__c = 'UDI']);
    }

    @IsTest
    static void testHistoricalQueueableChains() {
        cleanupHistory();
        Test.setMock(HttpCalloutMock.class, new BanxicoHttpMock());

        Date startDate = Date.newInstance(2026, 1, 2);
        Date endDate   = Date.newInstance(2026, 1, 2);

        Test.startTest();
        System.enqueueJob(new BanxicoQueueable(startDate, endDate, 1));
        Test.stopTest();

        Assert.areEqual(2, [SELECT COUNT() FROM Exchange_Rate_History__c WHERE CurrencyType__c = 'USD']);
        Assert.areEqual(2, [SELECT COUNT() FROM Exchange_Rate_History__c WHERE CurrencyType__c = 'UDI']);
    }

    @IsTest
    static void testHistoricalQueueableInvalidRangeDoesNothing() {
        cleanupHistory();
        Test.setMock(HttpCalloutMock.class, new BanxicoHttpMock());

        Date startDate = Date.newInstance(2026, 1, 2);
        Date endDate   = Date.newInstance(2026, 1, 1);

        Test.startTest();
        System.enqueueJob(new BanxicoQueueable(startDate, endDate, 1));
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Exchange_Rate_History__c]);
    }
}