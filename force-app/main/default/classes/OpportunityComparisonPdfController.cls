/**
 * Controlador de la página Visualforce que materializa el comparativo en PDF.
 *
 * El HTML a renderizar se entrega leyéndolo desde la Oportunidad (Descripcion__c),
 * un registro ya COMMITTED: getContentAsPDF() emite un GET HTTP interno en una
 * transacción propia, por lo que las variables static NO sobreviven a esa llamada.
 * Por compatibilidad se conserva el respaldo por Map estático (parámetro 'k').
 *
 * El HTML del comparativo puede llegar como fragmento (<div ...>) o como documento
 * completo (<!DOCTYPE html><html>...). normalize() garantiza que siempre se emita un
 * documento HTML válido, por eso la página VF no debe envolverlo en <html><body>.
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
    String raw = '';
    PageReference pg = ApexPages.currentPage();
    if (pg != null) {
      // 1) Vía principal: HTML committed en la Oportunidad.
      String oppId = pg.getParameters().get('oppId');
      if (String.isNotBlank(oppId)) {
        for (Opportunity o : [
          SELECT Descripcion__c FROM Opportunity WHERE Id = :oppId LIMIT 1
        ]) {
          raw = o.Descripcion__c;
        }
      }
      // 2) Respaldo: Map estático por clave 'k'.
      if (String.isBlank(raw)) {
        String key = pg.getParameters().get('k');
        if (String.isNotBlank(key) && htmlByKey.containsKey(key)) {
          raw = htmlByKey.get(key);
        }
      }
    }
    htmlBody = normalize(raw);
  }

  // Garantiza un documento HTML válido: si ya es documento completo lo deja igual;
  // si es fragmento lo envuelve. Cadena vacía se conserva vacía.
  private static String normalize(String html) {
    if (String.isBlank(html)) { return ''; }
    return html.toLowerCase().contains('<html')
      ? html
      : '<html><body>' + html + '</body></html>';
  }
}
