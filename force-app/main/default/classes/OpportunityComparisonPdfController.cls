/**
 * @creation date: 27/07/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Controlador de la página Visualforce que convierte el comparativo de cotizaciones en PDF. Lee el
 * HTML desde la oportunidad (o del mapa estático) y lo adapta al motor de PDF.
 */
public with sharing class OpportunityComparisonPdfController {
  private static Map<String, String> htmlByKey = new Map<String, String>();

  /**
   * @creation date: 27/07/2026
   * @author: Sergio Uribe Toledo - Volestra
   * @description: Guarda en el mapa estático el HTML a renderizar con una llave.
   * @param key: Llave del comparativo
   * @param html: HTML a renderizar
   * @return void
   */
  public static void put(String key, String html) {
    if (String.isNotBlank(key)) {
      htmlByKey.put(key, html == null ? '' : html);
    }
  }

  /**
   * @creation date: 27/07/2026
   * @author: Sergio Uribe Toledo - Volestra
   * @description: Quita del mapa estático el HTML de una llave.
   * @param key: Llave del comparativo
   * @return void
   */
  public static void remove(String key) {
    if (String.isNotBlank(key)) {
      htmlByKey.remove(key);
    }
  }

  public String htmlBody { get; private set; }

  /**
   * @creation date: 27/07/2026
   * @author: Sergio Uribe Toledo - Volestra
   * @description: Constructor: obtiene el HTML del comparativo desde la oportunidad (parámetro oppId) o desde el
   * mapa estático y lo deja listo en htmlBody.
   */
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

  /**
   * @creation date: 03/08/2026
   * @author: Sergio Uribe Toledo - Volestra
   * @description: Deja el HTML listo para renderizar como PDF: si es un fragmento lo envuelve en un documento
   * completo con los estilos del PDF.
   * @param html: HTML del comparativo
   * @return Documento HTML completo
   */
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

  /**
   * @creation date: 29/09/2026
   * @author: Sergio Uribe Toledo - Volestra
   * @description: Adapta el HTML al motor de PDF: reemplaza los degradados (linear-gradient), que no soporta, por
   * su primer color.
   * @param html: HTML del comparativo
   * @return HTML compatible con el PDF
   */
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

  /**
   * @creation date: 29/09/2026
   * @author: Sergio Uribe Toledo - Volestra
   * @description: Obtiene el primer color (#hex o rgb/rgba) de un segmento de CSS.
   * @param segmento: Texto del degradado
   * @return Color encontrado; null si no hay
   */
  private static String primerColor(String segmento) {
    Matcher c = Pattern.compile('(#[0-9a-fA-F]{3,8}|rgba?\\([^)]*\\))').matcher(segmento == null ? '' : segmento);
    return c.find() ? c.group(1) : null;
  }
}