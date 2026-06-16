public with sharing class QuoteCreatorController {

    @AuraEnabled(cacheable=false)
    public static List<Quote> getQuotes() {
        try {
            // Subquery a Quote_Coverage__c para mostrar el conteo de
            // coberturas en cada tarjeta de la lista sin queries extra.
            return [
                SELECT Id, Name, OpportunityId, Opportunity.Name, Aseguradora__r.Name,
                       Opportunity.Ramo__c, Status, TotalPrice, RatingDate,
                       ExpirationDate, CreatedDate,
                       (SELECT Id FROM Quotes_Coverages__r)
                FROM Quote
                ORDER BY CreatedDate DESC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error loading quotes: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static Quote getQuoteById(Id quoteId) {
        try {
            return [
                SELECT Id, Name, OpportunityId, Opportunity.Name, Aseguradora__r.Name,
                       Opportunity.Ramo__c, Status, TotalPrice, RatingDate,
                       ExpirationDate, CreatedDate,
                       Aseguradora__c, Product__c, Product__r.Name, Description
                FROM Quote
                WHERE Id = :quoteId
            ];
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

    /**
     * Coberturas de una cotización — sólo los campos que el negocio usa
     * por ahora: nombre y vínculos. Los importes, deducibles y coaseguros
     * quedan fuera del modelo actual.
     */
    @AuraEnabled(cacheable=true)
    public static List<Quote_Coverage__c> getCoveragesByQuoteId(Id quoteId) {
        if (quoteId == null) return new List<Quote_Coverage__c>();
        return [
            SELECT Id, Name, Quote__c, Product__c, Product_Coverage__c,
                   Coverage_Name__c, Coverage_Code__c, Order__c
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

    /**
     * Productos del catálogo filtrados por Ramo (Family) y Aseguradora.
     * Ambos son obligatorios; sin aseguradora no se devuelve nada.
     */
    @AuraEnabled(cacheable=true)
    public static List<Product2> getProducts(String ramo, Id aseguradoraId) {
        if (String.isBlank(ramo) || aseguradoraId == null) return new List<Product2>();
        return [SELECT Id, Name, ProductCode, Aseguradora__c, Aseguradora__r.Name
                FROM Product2
                WHERE IsActive = TRUE
                  AND Family = :ramo
                  AND Aseguradora__c = :aseguradoraId
                ORDER BY Name];
    }

    /**
     * Plantilla de coberturas del producto.
     *
     * Busca primero en el objeto custom `Product_Coverage__c` (que es donde
     * Avanza modela las plantillas, según el campo Quote_Coverage__c.Product_Coverage__c).
     * Si esa fuente está vacía, cae al objeto estándar `ProductCoverage`.
     * Devuelve un wrapper uniforme para que el LWC no dependa de la fuente.
     */
    @AuraEnabled(cacheable=true)
    public static List<CoverageTemplateWrapper> getCoveragesByProduct(Id productId) {
        List<CoverageTemplateWrapper> result = new List<CoverageTemplateWrapper>();
        if (productId == null) return result;

        // 1) Fuente principal: objeto custom Product_Coverage__c
        try {
            for (ProductCoverage pc : [
                SELECT Id, Name, ProductId, Product.Name, CoverageType.CoverageCode, CoverageType.Name
                FROM ProductCoverage
                WHERE ProductId = :productId
                ORDER BY Name
            ]) {
                CoverageTemplateWrapper w = new CoverageTemplateWrapper();
                w.Id          = pc.Id;
                w.coverageName = String.isNotBlank(pc.CoverageType.Name) ? pc.CoverageType.Name : pc.Name;
                w.coverageCode = pc.CoverageType.CoverageCode;
                result.add(w);
            }
        } catch (Exception e) {
            // El objeto custom puede no existir — pasamos al fallback.
            System.debug(':::QuoteCreator::: Product_Coverage__c no disponible: ' + e.getMessage());
        }

        // 2) Fallback: ProductCoverage estándar (Salesforce Industries)
        if (result.isEmpty()) {
            try {
                Integer i = 0;
                for (ProductCoverage pc : [
                    SELECT Id, Name, ProductId, CoverageTypeId, CoverageType.Name
                    FROM ProductCoverage
                    WHERE ProductId = :productId
                ]) {
                    CoverageTemplateWrapper w = new CoverageTemplateWrapper();
                    w.Id          = pc.Id;
                    w.coverageName = pc.CoverageType != null ? pc.CoverageType.Name : pc.Name;
                    w.orderNum     = ++i;
                    result.add(w);
                }
            } catch (Exception e) {
                System.debug(':::QuoteCreator::: ProductCoverage no disponible: ' + e.getMessage());
            }
        }
        return result;
    }

    /** Wrapper uniforme para coberturas plantilla (LWC no distingue la fuente). */
    public class CoverageTemplateWrapper {
        @AuraEnabled public Id Id;
        @AuraEnabled public String coverageName;
        @AuraEnabled public String coverageCode;
        @AuraEnabled public Integer orderNum;
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