/**
 *   @name: OpportunityQuotesController
 *   @version: 1.0
 *   @creation date: 02/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Controlador cacheable que expone al comparativo de IA las Quotes hijas de una Opportunity con sus campos custom y los ContentDocumentLinks del PDF comparativo. Aislado de PdfOpportunityController para no inflar el controlador principal y permitir cacheado.
 */
public with sharing class OpportunityQuotesController {

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve las Quotes hijas de una Opportunity con los campos custom usados por el comparativo de IA, envueltas en QuoteSummary y ordenadas por prima anual ascendente.
	 * @param opportunityId: Id de la Opportunity de la que se obtienen las Quotes.
	 * @return Lista de QuoteSummary con los datos de cada Quote.
	 */
	@AuraEnabled(cacheable = true)
	public static List<QuoteSummary> getQuotesByOpportunity(Id opportunityId) {
		if (opportunityId == null) {
		throw new AuraHandledException('Falta el Id de la oportunidad.');
		}
		List<QuoteSummary> out = new List<QuoteSummary>();
		Map<Id, QuoteSummary> byId = new Map<Id, QuoteSummary>();
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
		QuoteSummary s = new QuoteSummary(q);
		s.coberturas = new List<String>();
		out.add(s);
		byId.put(q.Id, s);
		}

		// Coberturas reales (Quote_Coverage__c) por cotización: alimentan la matriz
		// comparativa (cobertura × aseguradora) en el LWC. Se usa el nombre de la
		// cobertura (Coverage_Name__c) y, si viene vacío, el Name del registro.
		if (!byId.isEmpty()) {
		for (Quote_Coverage__c qc : [
			SELECT Quote__c, Coverage_Name__c, Name
			FROM Quote_Coverage__c
			WHERE Quote__c IN :byId.keySet()
			ORDER BY Order__c NULLS LAST, Coverage_Name__c
		]) {
			QuoteSummary s = byId.get(qc.Quote__c);
			if (s != null) {
			String nm = String.isNotBlank(qc.Coverage_Name__c)
				? qc.Coverage_Name__c
				: qc.Name;
			if (String.isNotBlank(nm)) {
				s.coberturas.add(nm);
			}
			}
		}
		}
		return out;
	}

  /**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve los ContentDocumentLinks de la Opportunity cuyo título empieza con "Comparativo_", permitiendo mostrar un acceso directo al PDF comparativo desde el record page.
	 * @param opportunityId: Id de la Opportunity de la que se obtienen los enlaces de documentos.
	 * @return Lista de ComparativoLink con los documentos comparativos encontrados.
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

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Wrapper serializable que expone los datos relevantes de una Quote al comparativo de IA en el frontend.
	 */
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
    @AuraEnabled
    public List<String> coberturas;

		/**
		 * @creation date: 02/07/2026
		 * @author: Sergio Uribe Toledo - Volestra
		 * @description: Constructor por defecto vacío requerido para la serialización.
		 * @return void
		 */
    public QuoteSummary() {
    }

		/**
		 * @creation date: 02/07/2026
		 * @author: Sergio Uribe Toledo - Volestra
		 * @description: Construye el wrapper a partir de un registro Quote, copiando cada campo custom al atributo correspondiente.
		 * @param q: Registro Quote origen de los datos.
		 * @return void
		 */
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
      this.coberturas = new List<String>();
    }
  }

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Wrapper serializable que representa un enlace a un documento comparativo (PDF) asociado a la Opportunity.
	 */
  public class ComparativoLink {
    @AuraEnabled
    public Id contentDocumentId;
    @AuraEnabled
    public Id latestVersionId;
    @AuraEnabled
    public String title;
  }
}
