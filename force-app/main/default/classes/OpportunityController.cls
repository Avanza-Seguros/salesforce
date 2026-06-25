public with sharing class OpportunityController {

    @AuraEnabled(cacheable=false)
    public static List<Opportunity> getOpportunities() {
        try {
            return [
                SELECT
                    Id,
                    Name,
                    StageName,
                    CloseDate,
                    Amount,
                    Prima_Total__c,
                    Description,
                    Type,
                    LeadSource,
                    Probability,
                    AccountId,
                    Ramo__c,
                    Canal__c,
                    Mercado__c,
                    Account.Name,
                    Owner.Name,
                    CreatedDate
                FROM Opportunity
                ORDER BY CreatedDate DESC
                LIMIT 50
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error al cargar oportunidades: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static OpportunityDetailWrapper getOpportunityDetails(String opportunityId) {
        try {
            OpportunityDetailWrapper wrapper = new OpportunityDetailWrapper();
            wrapper.opportunity = [
                SELECT Id, Name, StageName, Type, Canal__c, Mercado__c,
                       Ramo__c, CloseDate, Amount, Prima_Total__c,
                       AccountId, Account.Name, Description
                FROM Opportunity
                WHERE Id = :opportunityId
                LIMIT 1
            ];

            // - QuoteLineItem    → línea con el PRODUCTO de la cotización
            // - Quote_Coverage__c → COBERTURAS reales (objeto custom)
            wrapper.quotes = [
                SELECT Id, IsDeleted, Name, Pricebook2Id, ContactId, Contact.Name, QuoteNumber,
                       IsSyncing, Tax, Status, ExpirationDate, Subtotal, TotalPrice, Email, AccountId,
                       Account.Name, Product__c, Product__r.Name, Is_Selected__c,
                       Aseguradora__c, Aseguradora__r.Name, Price_Book__c,
                       (SELECT Id, Product2Id, Product2.Name, Quantity, UnitPrice, TotalPrice
                        FROM QuoteLineItems)
                FROM Quote
                WHERE OpportunityId = :opportunityId
                ORDER BY CreatedDate DESC
            ];

            // Coberturas (Quote_Coverage__c) por cotización: traemos el
            // nombre y el orden. Con eso el LWC arma:
            //   • el conteo total para la tabla y el KPI
            //   • el comparativo imprimible (matriz cobertura × compañía)
            Set<Id> quoteIds = new Set<Id>();
            for (Quote q : wrapper.quotes) quoteIds.add(q.Id);

            Map<Id, Integer> coverageCounts = new Map<Id, Integer>();
            Map<Id, List<String>> coverageNamesByQuote = new Map<Id, List<String>>();
            if (!quoteIds.isEmpty()) {
                for (Quote_Coverage__c qc : [
                    SELECT Id, Quote__c, Coverage_Name__c, Name, Order__c
                    FROM Quote_Coverage__c
                    WHERE Quote__c IN :quoteIds
                    ORDER BY Order__c NULLS LAST, Coverage_Name__c
                ]) {
                    Id qid = qc.Quote__c;
                    if (!coverageNamesByQuote.containsKey(qid)) {
                        coverageNamesByQuote.put(qid, new List<String>());
                        coverageCounts.put(qid, 0);
                    }
                    String covName = String.isNotBlank(qc.Coverage_Name__c)
                                     ? qc.Coverage_Name__c : qc.Name;
                    coverageNamesByQuote.get(qid).add(covName);
                    coverageCounts.put(qid, coverageCounts.get(qid) + 1);
                }
            }
            wrapper.coverageCounts = coverageCounts;
            wrapper.coverageNamesByQuote = coverageNamesByQuote;

            return wrapper;
        } catch (Exception e) {
            throw new AuraHandledException('Error al cargar detalles de la oportunidad: ' + e.getMessage());
        }
    }

    public class OpportunityDetailWrapper {
        @AuraEnabled public Opportunity opportunity;
        @AuraEnabled public List<Quote> quotes;
        @AuraEnabled public Map<Id, Integer> coverageCounts;
        @AuraEnabled public Map<Id, List<String>> coverageNamesByQuote;
    }

    @AuraEnabled(cacheable=false)
    public static void deleteOpportunity(String opportunityId) {
        try {
            Opportunity opp = [SELECT Id FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
            delete opp;
        } catch (Exception e) {
            throw new AuraHandledException('Error al eliminar oportunidad: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<Agente__c> searchAgentsProspectors(String searchTerm) {
        try {
            if (String.isBlank(searchTerm) || searchTerm.length() < 3) {
                return new List<Agente__c>();
            }
            String searchQuery = '%' + searchTerm + '%';
            return [
                SELECT Id, Name, Email__c, Telefono__c, Contacto__r.Name, Horno_mes__c
                FROM Agente__c
                WHERE (Name LIKE :searchQuery
                       OR Email__c LIKE :searchQuery
                       OR Contacto__r.Name LIKE :searchQuery)
                ORDER BY Name
                LIMIT 10
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error en búsqueda de agentes: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<PdfWrapper> getPdfFiles(Id recordId) {
        List<PdfWrapper> result = new List<PdfWrapper>();
        for (ContentDocumentLink cdl : [
            SELECT ContentDocument.Id,
                   ContentDocument.Title,
                   ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
        ]) {
            result.add(new PdfWrapper(
                cdl.ContentDocument.Id,
                cdl.ContentDocument.Title,
                cdl.ContentDocument.LatestPublishedVersionId
            ));
        }
        return result;
    }

    public class PdfWrapper {
        @AuraEnabled public Id documentId;
        @AuraEnabled public String title;
        @AuraEnabled public Id versionId;

        public PdfWrapper(Id docId, String t, Id vId) {
            documentId = docId;
            title = t;
            versionId = vId;
        }
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> extractPolicyData(String fileContent) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            Blob fileBlob = EncodingUtil.base64Decode(fileContent.split(',')[1]);
            // Integración futura con OCR (Google Vision, AWS Textract, etc.)
            result.put('success', true);
            result.put('confidence', 85);
            List<Map<String, Object>> extractedFields = new List<Map<String, Object>>();
            extractedFields.add(createField('NumeroPoliza__c', 'Número de Póliza', 'P-2024-0012345', 95));
            extractedFields.add(createField('Aseguradora__c', 'Compañía Aseguradora', 'Mapfre', 90));
            extractedFields.add(createField('Prima_Total__c', 'Prima Total', '1250.00', 80));
            result.put('extractedFields', extractedFields);
        } catch (Exception e) {
            result.put('success', false);
            result.put('error', e.getMessage());
        }
        return result;
    }

    private static Map<String, Object> createField(String name, String label, String value, Integer confidence) {
        Map<String, Object> field = new Map<String, Object>();
        field.put('name', name);
        field.put('label', label);
        field.put('value', value);
        field.put('confidence', confidence);
        return field;
    }

    public class AccountResult {
        @AuraEnabled public Id Id;
        @AuraEnabled public String Name;
        @AuraEnabled public Boolean IsPersonAccount;
        @AuraEnabled public String typeLabel;
        @AuraEnabled public String detailLine;
        @AuraEnabled public String clienteNombre;
        @AuraEnabled public String clienteRFC;
        @AuraEnabled public String clienteEmail;
        @AuraEnabled public String clienteTelefono;
        @AuraEnabled public String clienteCP;
        @AuraEnabled public String clienteDireccion;
    }

    @AuraEnabled(cacheable=false)
    public static List<AccountResult> searchAccounts(String searchTerm) {
        String busqTerm = '%' + searchTerm + '%';
        List<AccountResult> out = new List<AccountResult>();
        for (Account a : [
            SELECT Id, Name, IsPersonAccount, Phone,
                   BillingStreet, BillingPostalCode,
                   PersonEmail, PersonMobilePhone,
                   PersonMailingStreet, PersonMailingPostalCode
            FROM Account
            WHERE Name LIKE :busqTerm
            ORDER BY Name LIMIT 20
        ]) {
            AccountResult r = new AccountResult();
            r.Id = a.Id;  r.Name = a.Name;  r.IsPersonAccount = a.IsPersonAccount;
            r.typeLabel = a.IsPersonAccount ? 'Persona' : 'Empresa';
            r.clienteNombre = a.Name;
            if (a.IsPersonAccount) {
                r.clienteEmail = a.PersonEmail;
                r.clienteTelefono = a.PersonMobilePhone != null ? a.PersonMobilePhone : a.Phone;
                r.clienteCP = a.PersonMailingPostalCode;
                r.clienteDireccion = a.PersonMailingStreet;
            } else {
                r.clienteTelefono = a.Phone;
                r.clienteCP = a.BillingPostalCode;
                r.clienteDireccion = a.BillingStreet;
            }
            r.detailLine = r.typeLabel + (String.isNotBlank(r.clienteRFC) ? '  ·  RFC ' + r.clienteRFC : '');
            out.add(r);
        }
        return out;
    }

    @AuraEnabled(cacheable=false)
    public static Id saveOpportunity(String opportunityJson, Boolean isNewAccount) {
        Map<String, Object> d =
            (Map<String, Object>) JSON.deserializeUntyped(opportunityJson);

        Id accountId = d.get('AccountId') != null
            ? (Id) String.valueOf(d.get('AccountId'))
            : null;

        // ------------------------------------------------------------
        // 1) CUENTA NUEVA
        // ------------------------------------------------------------
        if (isNewAccount == true && accountId == null) {
            String tipoCliente = getStr(d, 'tipoCliente');
            Account acc = new Account();

            if (tipoCliente == 'Persona') {
                Id paRtId = getPersonAccountRecordTypeId();
                if (paRtId != null) {
                    acc.RecordTypeId = paRtId;
                }
                acc.FirstName = getStr(d, 'clienteNombre');
                acc.LastName  = getStr(d, 'clienteApellidos');
                if (String.isBlank(acc.LastName)) {
                    acc.LastName  = String.isNotBlank(acc.FirstName)
                                    ? acc.FirstName : getStr(d, 'AccountName');
                    acc.FirstName = null;
                }
                acc.PersonEmail             = getStr(d, 'clienteEmail');
                acc.Phone                   = getStr(d, 'clienteTelefono');
                acc.PersonMailingStreet     = getStr(d, 'clienteDireccion');
                acc.PersonMailingPostalCode = getStr(d, 'clienteCP');
            } else {
                acc.Name = getStr(d, 'AccountName');
                if (String.isBlank(acc.Name)) {
                    acc.Name = getStr(d, 'clienteNombre');
                }
                acc.Phone             = getStr(d, 'clienteTelefono');
                acc.BillingStreet     = getStr(d, 'clienteDireccion');
                acc.BillingPostalCode = getStr(d, 'clienteCP');
            }

            insert acc;
            accountId = acc.Id;
        }

        // ------------------------------------------------------------
        // 2) OPORTUNIDAD (crear o actualizar)
        // ------------------------------------------------------------
        Opportunity opp = new Opportunity();
        if (d.get('Id') != null) {
            opp.Id = (Id) String.valueOf(d.get('Id'));
        }
        opp.Name        = getStr(d, 'Name');
        opp.StageName   = getStr(d, 'StageName');
        opp.AccountId   = accountId;
        opp.Type        = getStr(d, 'Type');
        opp.Canal__c    = getStr(d, 'Canal__c');
        opp.Mercado__c  = getStr(d, 'Mercado__c');
        opp.Ramo__c     = getStr(d, 'Ramo__c');
        opp.Description = getStr(d, 'Description');

        // Prima Total (campo custom) — sustituye al Amount estándar
        Object primaRaw = d.get('Prima_Total__c');
        if (primaRaw != null && String.isNotBlank(String.valueOf(primaRaw))) {
            try {
                opp.Prima_Total__c = Decimal.valueOf(String.valueOf(primaRaw));
            } catch (Exception ex) {
                // Si llega un valor no numérico, lo ignoramos en vez de tronar
            }
        }

        String closeDateStr = getStr(d, 'CloseDate');
        if (String.isNotBlank(closeDateStr)) {
            opp.CloseDate = Date.valueOf(closeDateStr);
        } else if (opp.Id == null) {
            opp.CloseDate = Date.today().addDays(30);
        }

        upsert opp;
        return opp.Id;
    }

    private static String getStr(Map<String, Object> m, String key) {
        Object v = m.get(key);
        return v == null ? null : String.valueOf(v);
    }

    private static Id getPersonAccountRecordTypeId() {
        for (RecordType rt : [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true AND IsActive = true
            LIMIT 1
        ]) {
            return rt.Id;
        }
        return null;
    }

    @AuraEnabled(cacheable=true)
    public static List<Product2> getProducts(String ramo) {
        if (String.isBlank(ramo)) {
            return new List<Product2>();
        }
        return [
            SELECT Id, Name, ProductCode, Family
            FROM Product2
            WHERE IsActive = true
                AND Family = :ramo
            ORDER BY Name
        ];
    }
}