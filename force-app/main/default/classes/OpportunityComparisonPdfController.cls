/**
 * Controlador de la página Visualforce que materializa el comparativo en PDF.
 *
 * Recibe el HTML a renderizar mediante un Map estático poblado por
 * VisualforcePdfRenderer: getContentAsPDF() emite un GET HTTP interno en la
 * MISMA transacción Apex, por lo que el static persiste durante esa llamada
 * sin necesidad de Platform Cache.
 */
public with sharing class OpportunityComparisonPdfController {
  private static Map<String, String> htmlByKey = new Map<String, String>();

  public static void put(String key, String html) {
    if (String.isNotBlank(key)) {
      htmlByKey.put(key, html == null ? '' : html);
    }
  }

  public static void remove(String key) {
    if (String.isNotBlank(key)) {
      htmlByKey.remove(key);
    }
  }

  public String htmlBody { get; private set; }

  public OpportunityComparisonPdfController() {
    String key = ApexPages.currentPage() == null
      ? null
      : ApexPages.currentPage().getParameters().get('k');
    htmlBody = (key != null && htmlByKey.containsKey(key))
      ? htmlByKey.get(key)
      : '';
  }
}