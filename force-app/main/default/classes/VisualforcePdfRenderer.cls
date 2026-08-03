/**
 * Render por defecto basado en una página Visualforce con renderAs="pdf".
 *
 * El HTML se pasa al controlador de la VF vía un Map estático: getContentAsPDF()
 * dispara un GET interno HTTP a la página DENTRO de la misma transacción Apex,
 * por lo que el static sobrevive a esa llamada sin necesidad de Platform Cache
 * (este org no tiene partition configurada).
 */
public with sharing class VisualforcePdfRenderer implements IPdfRenderer {
  public Blob renderToPdf(String htmlContent, String fileName) {
    String safeHtml = htmlContent == null ? '' : htmlContent;
    String key = String.valueOf(Crypto.getRandomLong());
    OpportunityComparisonPdfController.put(key, safeHtml);
    try {
      PageReference pr = Page.OpportunityComparisonPdf;
      pr.getParameters().put('k', key);
      // En tests, getContentAsPDF no produce bytes reales y puede fallar:
      // devolvemos el HTML como Blob para validar el contrato del método.
      return Test.isRunningTest()
        ? Blob.valueOf(safeHtml)
        : pr.getContentAsPDF();
    } finally {
      OpportunityComparisonPdfController.remove(key);
    }
  }
}