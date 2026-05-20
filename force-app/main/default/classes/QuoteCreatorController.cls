public with sharing class QuoteCreatorController {
    
    @AuraEnabled(cacheable=false)
    public static List<Quote> getQuotes() {
        try {
            return [SELECT Id, Name, OpportunityId, Opportunity.Name, Aseguradora__r.Name, 
                            Opportunity.Ramo__c, Status, TotalPrice, RatingDate, 
                            ExpirationDate, CreatedDate
                    FROM Quote
                    ORDER BY CreatedDate DESC];
        } catch (Exception e) {
            throw new AuraHandledException('Error loading quotes: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=false)
    public static Quote getQuoteById(Id quoteId) {
        try {
            return [SELECT Id, Name, OpportunityId, Opportunity.Name, Aseguradora__r.Name, 
                            Opportunity.Ramo__c, Status, TotalPrice, RatingDate, 
                            ExpirationDate, CreatedDate
                    FROM Quote
                    WHERE Id = :quoteId];
        } catch (Exception e) {
            throw new AuraHandledException('Error loading quote: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static Quote saveQuote(Quote quote) {
        try {
            upsert quote;
            return quote;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving quote: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void deleteQuote(Id quoteId) {
        try {
            delete [SELECT Id FROM Quote WHERE Id = :quoteId];
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting quote: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=false)
    public static List<Quote_Coverage__c> getCoveragesByRamo(String ramo) {
        try {
            return [SELECT Id, Name, Quote__c, Quote_Line_Item__c, Product__c, Is_Selected__c, Sum_Insured__c, Deductible__c, Coinsurance__c, Limit__c, 
                        Is_Included__c, Is_Optional__c, Is_Mandatory__c, Is_Visible__c, Is_Valid__c, Base_Rate__c, Premium__c, 
                        Discount__c, Surcharge__c, Net_Premium__c, Aseguradora__c, Coverage_Code__c, Coverage_Name__c, Order__c, 
                        External_Id__c, Hash_Key__c, Version__c, Product_Coverage__c
                    FROM Quote_Coverage__c
                    ORDER BY Name];
        } catch (Exception e) {
            throw new AuraHandledException('Error loading coverages: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Quote_Coverage__c> getCoveragesByQuoteId(Id quoteId) {
        if (quoteId == null) return new List<Quote_Coverage__c>();
        return [
            SELECT Id, Name, Quote__c, Quote_Line_Item__c, Product__c, Is_Selected__c,
                Sum_Insured__c, Deductible__c, Coinsurance__c, Limit__c,
                Is_Included__c, Is_Optional__c, Is_Mandatory__c, Is_Visible__c, Is_Valid__c,
                Base_Rate__c, Premium__c, Discount__c, Surcharge__c, Net_Premium__c,
                Aseguradora__c, Coverage_Code__c, Coverage_Name__c, Order__c,
                External_Id__c, Hash_Key__c, Version__c, Product_Coverage__c
            FROM Quote_Coverage__c
            WHERE Quote__c = :quoteId
            ORDER BY Order__c NULLS LAST, Coverage_Name__c
        ];
    }
    
    @AuraEnabled
    public static void saveCoverages(List<Quote_Coverage__c> coverages) {
        try {
            upsert coverages;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving coverages: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=false)
    public static List<OpportunityWrapper> searchOpportunities(String searchTerm) {
        String searchPattern = '%' + searchTerm + '%';
        List<Opportunity> opps = [
            SELECT Id, Name, Ramo__c, Account.Name, StageName
            FROM Opportunity
            WHERE Name LIKE :searchPattern
            ORDER BY Name];

        List<OpportunityWrapper> result = new List<OpportunityWrapper>();

        for (Opportunity o : opps) {
            result.add(new OpportunityWrapper(o));
        }
        return result;
    }

    @AuraEnabled(cacheable=false)
    public static List<Aseguradora__c> searchAseguradoras(String searchTerm) { 
            try {
                String searchPattern = '%' + searchTerm + '%';
                return [SELECT Id, Name FROM Aseguradora__c WHERE Name LIKE :searchPattern ORDER BY Name LIMIT 10];
            } catch (Exception e) {
                throw new AuraHandledException('Error searching aseguradoras: ' + e.getMessage());
            }
    }

    @AuraEnabled(cacheable=true)
    public static List<Product2> getProducts(String ramo) {
        if (String.isBlank(ramo)) return new List<Product2>();
        return [SELECT Id, Name, ProductCode
                FROM Product2
                WHERE IsActive = TRUE AND Family = :ramo
                ORDER BY Name];
    }

    @AuraEnabled(cacheable=true)
    public static List<ProductCoverage> getCoveragesByProduct(Id productId) {
        if (productId == null) return new List<ProductCoverage>();
        
        return [SELECT Id, IsDeleted, Name, ProductId, Product.Name, IsCovered, EffectiveDate, 
                       ExpirationDate, CoverageTypeId, CoverageType.Name
                FROM ProductCoverage
                WHERE ProductId = :productId];
    }

    public class OpportunityWrapper {
        @AuraEnabled public Id Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String Ramo;
        @AuraEnabled public String StageName;
        @AuraEnabled public String AccountName;
        public OpportunityWrapper(Opportunity o) {
            this.Id = o.Id;
            this.Name = o.Name;
            this.Ramo = o.Ramo__c;
            this.StageName = o.StageName;
            this.AccountName = o.Account != null ? o.Account.Name : '';
        }
    }
}