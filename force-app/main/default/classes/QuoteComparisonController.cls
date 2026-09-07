public with sharing class QuoteComparisonController {

    @AuraEnabled(cacheable=true)
    public static List<QuoteWrapper> getQuotes(Id opportunityId) {

        List<Quote> quotes = [
            SELECT Id, Name, TotalPrice,
                   Aseguradora__r.Name
            FROM Quote
            WHERE OpportunityId = :opportunityId
        ];

        List<Quote_Coverage__c> coverages = [
            SELECT Id,
                   Quote__c,
                   Name,
                   Is_Selected__c,
                   Premium__c
            FROM Quote_Coverage__c
            WHERE Quote__c IN :quotes
        ];

        Map<Id, List<Quote_Coverage__c>> mapCov = new Map<Id, List<Quote_Coverage__c>>();

        for (Quote_Coverage__c qc : coverages) {
            if (!mapCov.containsKey(qc.Quote__c)) {
                mapCov.put(qc.Quote__c, new List<Quote_Coverage__c>());
            }
            mapCov.get(qc.Quote__c).add(qc);
        }

        List<QuoteWrapper> result = new List<QuoteWrapper>();

        for (Quote q : quotes) {
            QuoteWrapper w = new QuoteWrapper();
            w.quoteId = q.Id;
            w.name = q.Name;
            w.carrier = q.Aseguradora__r.Name;
            w.total = q.TotalPrice;
            w.coverages = mapCov.get(q.Id);
            result.add(w);
        }

        return result;
    }

    public class QuoteWrapper {
        @AuraEnabled public Id quoteId;
        @AuraEnabled public String name;
        @AuraEnabled public String carrier;
        @AuraEnabled public Decimal total;
        @AuraEnabled public List<Quote_Coverage__c> coverages;
    }
}