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
    PageReference pg = ApexPages.currentPage();
    String raw = '';
    if (pg != null) {
      // Preferido: leer el comparativo desde la Oportunidad (dato ya guardado/committed).
      // Es confiable porque las variables estáticas NO sobreviven a getContentAsPDF.
      String oppId = pg.getParameters().get('oppId');
      if (String.isNotBlank(oppId)) {
        try {
          for (Opportunity o : [SELECT Descripcion__c FROM Opportunity WHERE Id = :oppId LIMIT 1]) {
            raw = o.Descripcion__c;
          }
        } catch (Exception e) {
          raw = '';
        }
      } else {
        // Compatibilidad: mecanismo previo por variable estática.
        String key = pg.getParameters().get('k');
        if (String.isNotBlank(key) && htmlByKey.containsKey(key)) {
          raw = htmlByKey.get(key);
        }
      }
    }
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