@isTest
private class VisualforcePdfRendererTest {
  @isTest
  static void renderToPdfReturnsNonNullBlob() {
    IPdfRenderer renderer = new VisualforcePdfRenderer();
    String html = '<html><body>test</body></html>';

    Test.startTest();
    Blob result = renderer.renderToPdf(html, 'test.pdf');
    Test.stopTest();

    System.assertNotEquals(null, result, 'El renderer debe devolver un Blob.');
    System.assert(result.size() > 0, 'El Blob no puede estar vacío.');
  }

  @isTest
  static void controllerReadsHtmlFromStaticMap() {
    String key = 'unit-test-key';
    String html = '<p>hola</p>';
    OpportunityComparisonPdfController.put(key, html);

    PageReference pr = Page.OpportunityComparisonPdf;
    pr.getParameters().put('k', key);
    Test.setCurrentPage(pr);

    OpportunityComparisonPdfController ctrl = new OpportunityComparisonPdfController();
    // El fragmento se normaliza a un documento HTML completo.
    System.assertEquals('<html><body>' + html + '</body></html>', ctrl.htmlBody);

    OpportunityComparisonPdfController.remove(key);
  }

  @isTest
  static void controllerWithMissingKeyReturnsEmpty() {
    PageReference pr = Page.OpportunityComparisonPdf;
    Test.setCurrentPage(pr);

    OpportunityComparisonPdfController ctrl = new OpportunityComparisonPdfController();
    System.assertEquals('', ctrl.htmlBody);
  }
}