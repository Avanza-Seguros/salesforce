/**
 * @creation date: 11/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas unitarias de OpportunityQuotesController: cotizaciones de la oportunidad con sus
 * coberturas de catálogo (ProductCoverage) y enlaces al PDF del comparativo.
 */
@isTest
private class OpportunityQuotesControllerTest {

	/**
	 * @creation date: 11/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Crea una oportunidad con dos cotizaciones (una con producto y catálogo de coberturas), y un PDF
	 * de comparativo y otro archivo ligados a la oportunidad.
	 * @return void
	 */
	@testSetup
	static void setup() {
		Account acc = new Account(Name = 'Cliente Comparativo', AnnualRevenue = 100);
		insert acc;
		String etapa = 'Prospecting';
		for (OpportunityStage s : [
			SELECT MasterLabel FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1
		]) { etapa = s.MasterLabel; }
		Opportunity opp = new Opportunity(Name = 'Oportunidad Comparativo', AccountId = acc.Id, StageName = etapa,
			CloseDate = Date.today().addMonths(1), Ramo__c = 'Vida');
		insert opp;

		Aseguradora__c aseg = new Aseguradora__c(Name = 'Aseguradora Comparativo');
		insert aseg;
		Product2 prod = new Product2(Name = 'Plan Vida Comparativo', IsActive = true, Family = 'Vida', Aseguradora__c = aseg.Id);
		insert prod;
		CoverageType fallecimiento = new CoverageType(Name = 'Fallecimiento Test');
		CoverageType invalidez = new CoverageType(Name = 'Invalidez Test');
		insert new List<CoverageType>{ fallecimiento, invalidez };
		insert new List<ProductCoverage>{
			new ProductCoverage(ProductId = prod.Id, CoverageTypeId = fallecimiento.Id, IsCovered = true),
			new ProductCoverage(ProductId = prod.Id, CoverageTypeId = invalidez.Id, IsCovered = true)
		};

		Quote conProducto = cotizacion(opp.Id, 'Cotización Con Producto', 12000);
		conProducto.Product__c = prod.Id;
		conProducto.Aseguradora__c = aseg.Id;
		conProducto.Notas_IA__c = 'Incluye asistencia';
		Quote sinProducto = cotizacion(opp.Id, 'Cotización Sin Producto', 9000);
		insert new List<Quote>{ conProducto, sinProducto };

		insert new List<ContentVersion>{
			new ContentVersion(Title = 'Comparativo_Cliente', PathOnClient = 'Comparativo_Cliente.pdf',
				VersionData = Blob.valueOf('pdf'), FirstPublishLocationId = opp.Id),
			new ContentVersion(Title = 'Otro archivo', PathOnClient = 'otro.pdf',
				VersionData = Blob.valueOf('pdf'), FirstPublishLocationId = opp.Id)
		};
	}

	/**
	 * @creation date: 11/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma una cotización con los campos obligatorios del org.
	 * @param oppId: Id de la oportunidad
	 * @param nombre: Nombre de la cotización
	 * @param prima: Prima anual
	 * @return Cotización sin insertar
	 */
	static Quote cotizacion(Id oppId, String nombre, Decimal prima) {
		Quote q = new Quote(Name = nombre, OpportunityId = oppId, Status = 'Draft', PrimaAnual__c = prima,
			Prima_Total__c = prima, Pricebook2Id = Test.getStandardPricebookId());
		q.put('Frecuencia_de_prima__c', 'Anual');
		q.put('Ramos__c', 'Vida');
		return q;
	}

	/**
	 * @creation date: 11/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valida que se devuelvan las cotizaciones ordenadas por prima, con su aseguradora y las
	 * coberturas del catálogo de su producto (vacías si no tiene producto).
	 * @return void
	 */
	@isTest
	static void testCotizacionesConCoberturas() {
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
		Test.startTest();
		List<OpportunityQuotesController.QuoteSummary> rows = OpportunityQuotesController.getQuotesByOpportunity(opp.Id);
		Test.stopTest();

		System.assertEquals(2, rows.size(), 'Debe regresar las dos cotizaciones');
		System.assertEquals('Cotización Sin Producto', rows[0].name, 'Ordenadas por prima anual ascendente');
		System.assertEquals(0, rows[0].coberturas.size(), 'Sin producto no hay coberturas de catálogo');

		OpportunityQuotesController.QuoteSummary conProducto = rows[1];
		System.assertEquals('Aseguradora Comparativo', conProducto.aseguradora);
		System.assertEquals(12000, conProducto.primaAnual);
		System.assertEquals('Incluye asistencia', conProducto.notas);
		System.assertEquals(new List<String>{ 'Fallecimiento Test', 'Invalidez Test' }, conProducto.coberturas,
			'Coberturas del catálogo del producto, ordenadas por nombre');
	}

	/**
	 * @creation date: 11/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valida que sin oportunidad se avise el error.
	 * @return void
	 */
	@isTest
	static void testSinOportunidad() {
		Boolean error = false;
		try {
			OpportunityQuotesController.getQuotesByOpportunity(null);
		} catch (AuraHandledException e) {
			error = true;
		}
		System.assert(error, 'Debe exigir la oportunidad');
		System.assertEquals(null, new OpportunityQuotesController.QuoteSummary().coberturas, 'Constructor vacío para serializar');
	}

	/**
	 * @creation date: 11/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valida que solo se listen los PDFs de comparativo (título "Comparativo_") de la oportunidad.
	 * @return void
	 */
	@isTest
	static void testEnlacesComparativo() {
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
		Test.startTest();
		List<OpportunityQuotesController.ComparativoLink> links = OpportunityQuotesController.getComparativoLinks(opp.Id);
		Test.stopTest();
		System.assertEquals(1, links.size(), 'Solo el comparativo');
		System.assertEquals('Comparativo_Cliente', links[0].title);
		System.assertNotEquals(null, links[0].latestVersionId);
		System.assertEquals(0, OpportunityQuotesController.getComparativoLinks(null).size());
	}
}
