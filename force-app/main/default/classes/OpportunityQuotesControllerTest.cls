@isTest
private class OpportunityQuotesControllerTest {
  @isTest
  static void returnsChildQuotes() {
    Account acc = new Account(Name = 'Cliente Demo');
    insert acc;

    Opportunity opp = new Opportunity(
      Name = 'Oportunidad Demo',
      StageName = 'Prospecting',
      CloseDate = Date.today().addMonths(1),
      AccountId = acc.Id
    );
    insert opp;

    Quote q = new Quote(
      Name = 'Cotización Demo',
      OpportunityId = opp.Id,
      PrimaAnual__c = 12000
    );
    insert q;

    Test.startTest();
    List<OpportunityQuotesController.QuoteSummary> rows = OpportunityQuotesController.getQuotesByOpportunity(
      opp.Id
    );
    Test.stopTest();

    System.assertEquals(1, rows.size(), 'Debe regresar la cotización hija');
    System.assertEquals(q.Id, rows[0].id, 'Id de la cotización debe coincidir');
    System.assertEquals(12000, rows[0].primaAnual, 'Prima debe coincidir');
  }

  @isTest
  static void rejectsNullOpportunityId() {
    Boolean thrown = false;
    try {
      OpportunityQuotesController.getQuotesByOpportunity(null);
    } catch (AuraHandledException e) {
      thrown = true;
    }
    System.assert(thrown, 'Debe lanzar AuraHandledException con Id nulo');
  }

  @isTest
  static void findsComparativoLinks() {
    Opportunity opp = new Opportunity(
      Name = 'Oportunidad Demo',
      StageName = 'Prospecting',
      CloseDate = Date.today().addMonths(1)
    );
    insert opp;

    ContentVersion cv = new ContentVersion(
      Title = 'Comparativo_Demo',
      PathOnClient = 'Comparativo_Demo.pdf',
      VersionData = Blob.valueOf('demo'),
      Origin = 'H'
    );
    insert cv;
    Id docId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :cv.Id
    ]
    .ContentDocumentId;
    insert new ContentDocumentLink(
      ContentDocumentId = docId,
      LinkedEntityId = opp.Id,
      ShareType = 'V',
      Visibility = 'AllUsers'
    );

    Test.startTest();
    List<OpportunityQuotesController.ComparativoLink> links = OpportunityQuotesController.getComparativoLinks(
      opp.Id
    );
    Test.stopTest();

    System.assertEquals(1, links.size(), 'Debe encontrar el PDF comparativo');
    System.assertEquals(docId, links[0].contentDocumentId);
  }
}