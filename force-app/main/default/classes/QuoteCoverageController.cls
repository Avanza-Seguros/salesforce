public with sharing class QuoteCoverageController {

    @AuraEnabled(cacheable=true)
    public static List<Quote_Coverage__c> getCoverages(String quoteId) {
        String quoteIdStr = quoteId;
        if (quoteIdStr == null || quoteIdStr == '') {
            quoteIdStr = '%%';
        }else {
            quoteIdStr = '%' + quoteIdStr + '%';
        }

        return [
            SELECT Id,
                   Name,
                   Is_Selected__c,
                   Sum_Insured__c,
                   Deductible__c,
                   Premium__c
            FROM Quote_Coverage__c
            WHERE Name LIKE :quoteIdStr
        ];
    }

    @AuraEnabled
    public static void saveCoverages(List<Quote_Coverage__c> coverages) {
        update coverages;
    }
}