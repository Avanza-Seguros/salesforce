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
    // Un fragmento se envuelve en un documento completo con el estilo del PDF (@page) y conserva su contenido.
    System.assert(ctrl.htmlBody.startsWith('<html><head>'), 'Debe envolver el fragmento en un documento HTML.');
    System.assert(ctrl.htmlBody.contains('@page'), 'Debe incluir el estilo de página del PDF.');
    System.assert(ctrl.htmlBody.contains('<body>' + html + '</body>'), 'Debe conservar el HTML guardado en el cuerpo.');

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