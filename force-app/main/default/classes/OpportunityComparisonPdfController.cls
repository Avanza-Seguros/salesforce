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
    String raw = (key != null && htmlByKey.containsKey(key))
      ? htmlByKey.get(key)
      : '';
    htmlBody = normalize(raw);
  }

  // Deja el HTML listo para renderizar como PDF:
  // - Si ya es un documento completo (<html ...>), se usa tal cual.
  // - Si es un fragmento (p. ej. <div>...</div>), se envuelve en <html><body>.
  // Esto evita el HTML anidado (documento dentro de <html><body>) que producía PDFs en blanco.
  private String normalize(String html) {
    if (String.isBlank(html)) {
      return '';
    }
    String lower = html.toLowerCase();
    if (lower.contains('<html')) {
      return html;
    }
    return '<html><body>' + html + '</body></html>';
  }
}