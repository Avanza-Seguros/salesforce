/**
 * Devuelve las Quotes hijas de una Opportunity con los campos custom usados por el comparativo de IA,
 * y los ContentDocumentLinks del PDF comparativo. Aislado de PdfOpportunityController para no inflar
 * el controlador principal y para poder cachear (cacheable=true).
 */
public with sharing class OpportunityQuotesController {
  @AuraEnabled(cacheable = true)
  public static List<QuoteSummary> getQuotesByOpportunity(Id opportunityId) {
    if (opportunityId == null) {
      throw new AuraHandledException('Falta el Id de la oportunidad.');
    }
    List<QuoteSummary> out = new List<QuoteSummary>();
    for (Quote q : [
      SELECT
        Id,
        Name,
        Aseguradora__r.Name,
        PrimaAnual__c,
        SumaAsegurada__c,
        TipoValor__c,
        DeducibleDanos_Pct__c,
        DeducibleDanos_Mxn__c,
        DeducibleRobo_Pct__c,
        DeducibleRobo_Mxn__c,
        Cristales__c,
        ResponsabilidadCivil__c,
        GastosMedicos__c,
        AsistenciaVial__c,
        DefensaJuridica__c,
        VidaConductor__c,
        RCExtranjero__c,
        Notas_IA__c,
        ExpirationDate
      FROM Quote
      WHERE OpportunityId = :opportunityId
      ORDER BY PrimaAnual__c ASC NULLS LAST
    ]) {
      out.add(new QuoteSummary(q));
    }
    return out;
  }

  /**
   * ContentDocumentLinks de la Opportunity cuyo título empieza con "Comparativo_".
   * Permite mostrar un acceso directo al PDF comparativo desde el record page.
   */
  @AuraEnabled(cacheable = true)
  public static List<ComparativoLink> getComparativoLinks(Id opportunityId) {
    if (opportunityId == null) {
      return new List<ComparativoLink>();
    }
    List<ComparativoLink> out = new List<ComparativoLink>();
    for (ContentDocumentLink link : [
      SELECT
        ContentDocumentId,
        ContentDocument.Title,
        ContentDocument.LatestPublishedVersionId
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :opportunityId
      ORDER BY SystemModstamp DESC
    ]) {
      String title = link.ContentDocument != null
        ? link.ContentDocument.Title
        : null;
      if (String.isNotBlank(title) && title.startsWith('Comparativo_')) {
        ComparativoLink c = new ComparativoLink();
        c.contentDocumentId = link.ContentDocumentId;
        c.title = title;
        c.latestVersionId = link.ContentDocument.LatestPublishedVersionId;
        out.add(c);
      }
    }
    return out;
  }

  public class QuoteSummary {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String aseguradora;
    @AuraEnabled
    public Decimal primaAnual;
    @AuraEnabled
    public Decimal sumaAsegurada;
    @AuraEnabled
    public String tipoValor;
    @AuraEnabled
    public Decimal deducibleDanosPct;
    @AuraEnabled
    public Decimal deducibleDanosMxn;
    @AuraEnabled
    public Decimal deducibleRoboPct;
    @AuraEnabled
    public Decimal deducibleRoboMxn;
    @AuraEnabled
    public Boolean cristales;
    @AuraEnabled
    public Decimal responsabilidadCivil;
    @AuraEnabled
    public Decimal gastosMedicos;
    @AuraEnabled
    public Boolean asistenciaVial;
    @AuraEnabled
    public Boolean defensaJuridica;
    @AuraEnabled
    public Decimal vidaConductor;
    @AuraEnabled
    public Boolean rcExtranjero;
    @AuraEnabled
    public String notas;
    @AuraEnabled
    public Date expirationDate;

    public QuoteSummary() {
    }

    public QuoteSummary(Quote q) {
      this.id = q.Id;
      this.name = q.Name;
      this.aseguradora = (q.Aseguradora__r != null)
        ? q.Aseguradora__r.Name
        : null;
      this.primaAnual = q.PrimaAnual__c;
      this.sumaAsegurada = q.SumaAsegurada__c;
      this.tipoValor = q.TipoValor__c;
      this.deducibleDanosPct = q.DeducibleDanos_Pct__c;
      this.deducibleDanosMxn = q.DeducibleDanos_Mxn__c;
      this.deducibleRoboPct = q.DeducibleRobo_Pct__c;
      this.deducibleRoboMxn = q.DeducibleRobo_Mxn__c;
      this.cristales = q.Cristales__c;
      this.responsabilidadCivil = q.ResponsabilidadCivil__c;
      this.gastosMedicos = q.GastosMedicos__c;
      this.asistenciaVial = q.AsistenciaVial__c;
      this.defensaJuridica = q.DefensaJuridica__c;
      this.vidaConductor = q.VidaConductor__c;
      this.rcExtranjero = q.RCExtranjero__c;
      this.notas = q.Notas_IA__c;
      this.expirationDate = q.ExpirationDate;
    }
  }

  public class ComparativoLink {
    @AuraEnabled
    public Id contentDocumentId;
    @AuraEnabled
    public Id latestVersionId;
    @AuraEnabled
    public String title;
  }
}