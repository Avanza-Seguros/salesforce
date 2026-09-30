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
    html = paraPdf(html);
    String lower = html.toLowerCase();
    if (lower.contains('<html')) {
      // Inserta el estilo de página dentro del <head> (o al inicio del <body>).
      Integer i = lower.indexOf('</head>');
      if (i >= 0) {
        return html.substring(0, i) + ESTILO_PDF + html.substring(i);
      }
      Integer b = lower.indexOf('<body');
      if (b >= 0) {
        Integer fin = html.indexOf('>', b);
        if (fin >= 0) {
          return html.substring(0, fin + 1) + ESTILO_PDF + html.substring(fin + 1);
        }
      }
      return html;
    }
    return '<html><head>' + ESTILO_PDF + '</head><body>' + html + '</body></html>';
  }

  // Carta horizontal y fuente con acentos/ñ para el motor de PDF de Visualforce.
  private static final String ESTILO_PDF =
    '<style type="text/css">@page { size: letter landscape; margin: 12mm; } ' +
    'body { font-family: "Arial Unicode MS", Arial, sans-serif; font-size: 11px; }</style>';

  // El motor de PDF no soporta degradados (linear-gradient): el encabezado quedaba en blanco
  // y el título (texto blanco) desaparecía. Se reemplaza cada degradado por su primer color.
  @TestVisible
  private static String paraPdf(String html) {
    if (String.isBlank(html) || !html.containsIgnoreCase('gradient(')) {
      return html;
    }
    Pattern p = Pattern.compile('(?i)background(-image)?\\s*:\\s*[a-z-]*gradient\\(([^;"]*)');
    Matcher m = p.matcher(html);
    String out = '';
    Integer ultimo = 0;
    while (m.find()) {
      String color = primerColor(m.group(2));
      out += html.substring(ultimo, m.start()) + 'background-color:' + (color != null ? color : '#0052CC');
      ultimo = m.end();
    }
    return out + html.substring(ultimo);
  }

  private static String primerColor(String segmento) {
    Matcher c = Pattern.compile('(#[0-9a-fA-F]{3,8}|rgba?\\([^)]*\\))').matcher(segmento == null ? '' : segmento);
    return c.find() ? c.group(1) : null;
  }
}