/**
 *   @name: QuoteCreatorController
 *   @version: 1.0
 *   @creation date: 02/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Controlador Apex (expuesto a LWC via @AuraEnabled) para la creacion y gestion de cotizaciones (Quote) y sus coberturas (Quote_Coverage__c). Provee CRUD de cotizaciones y coberturas, busqueda de oportunidades y aseguradoras, consulta de productos del catalogo por ramo y aseguradora, y obtencion de plantillas de coberturas por producto.
 */
public with sharing class QuoteCreatorController {

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve todas las cotizaciones (Quote) ordenadas por fecha de creacion descendente, incluyendo una subconsulta a Quotes_Coverages__r para mostrar el conteo de coberturas por tarjeta sin queries adicionales.
	 * @return Lista de Quote con sus coberturas relacionadas
	 */
	@AuraEnabled(cacheable=false)
	public static List<Quote> getQuotes() {
		try {
			// Subquery a Quote_Coverage__c para mostrar el conteo de
			// coberturas en cada tarjeta de la lista sin queries extra.
			return [
				SELECT Id, Name, OpportunityId, Opportunity.Name, Aseguradora__r.Name,
					   Opportunity.Ramo__c, Status, TotalPrice, Prima_Total__c, PrimaAnual__c, RatingDate,
					   ExpirationDate, CreatedDate,
					   (SELECT Id FROM Quotes_Coverages__r)
				FROM Quote
				ORDER BY CreatedDate DESC
			];
		} catch (Exception e) {
			throw new AuraHandledException('Error loading quotes: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve una cotizacion (Quote) por su Id con los campos necesarios para el detalle.
	 * @param quoteId: Id de la cotizacion a recuperar
	 * @return Quote correspondiente al Id indicado
	 */
	@AuraEnabled(cacheable=false)
	public static Quote getQuoteById(Id quoteId) {
		try {
			return [
				SELECT Id, Name, OpportunityId, Opportunity.Name, Aseguradora__r.Name,
					   Opportunity.Ramo__c, Status, TotalPrice, RatingDate,
					   ExpirationDate, CreatedDate, Ramos__c, Prima_Total__c, PrimaAnual__c, Frecuencia_de_prima__c,
					   Aseguradora__c, Product__c, Product__r.Name, Description
				FROM Quote
				WHERE Id = :quoteId
			];
		} catch (Exception e) {
			throw new AuraHandledException('Error loading quote: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Inserta o actualiza (upsert) una cotizacion (Quote).
	 * @param quote: Cotizacion a guardar
	 * @return Quote guardada
	 */
	@AuraEnabled
	public static Quote saveQuote(Quote quote) {
		try {
			// Salvaguarda: rellena los campos requeridos si el formulario no los envía.
			// Ramos__c -> del ramo de la oportunidad.
			if (String.isBlank((String) quote.get('Ramos__c')) && quote.OpportunityId != null) {
				for (Opportunity o : [SELECT Ramo__c FROM Opportunity WHERE Id = :quote.OpportunityId LIMIT 1]) {
					quote.put('Ramos__c', o.Ramo__c); 
				}
			}
			// Frecuencia de prima -> 'Mensual' por defecto.
			if (String.isBlank((String) quote.get('Frecuencia_de_prima__c'))) {
				quote.put('Frecuencia_de_prima__c', 'Mensual');
			}
			// Prima anual -> si no viene, usa TotalPrice o Subtotal.
			if (quote.get('PrimaAnual__c') == null) {
				Decimal prima = (quote.TotalPrice != null)
					? quote.TotalPrice
					: (quote.Subtotal != null ? quote.Subtotal : null);
				if (prima != null) { quote.put('Prima_Total__c', prima); }
			}
			upsert quote;
			return quote;
		} catch (Exception e) {
			throw new AuraHandledException('No se pudo guardar la cotización: ' + detalleError(e));
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Elimina la cotizacion (Quote) correspondiente al Id indicado.
	 * @param quoteId: Id de la cotizacion a eliminar
	 * @return void
	 */
	@AuraEnabled
	public static void deleteQuote(Id quoteId) {
		try {
			delete [SELECT Id FROM Quote WHERE Id = :quoteId];
		} catch (Exception e) {
			throw new AuraHandledException('No se pudo eliminar la cotización: ' + detalleError(e));
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve las coberturas (Quote_Coverage__c) de una cotizacion, solo con los campos usados actualmente por el negocio (nombre y vinculos), ordenadas por Order__c y nombre. Los importes, deducibles y coaseguros quedan fuera del modelo actual.
	 * @param quoteId: Id de la cotizacion cuyas coberturas se solicitan
	 * @return Lista de Quote_Coverage__c de la cotizacion, o lista vacia si quoteId es null
	 */
	@AuraEnabled(cacheable=true)
	public static List<Quote_Coverage__c> getCoveragesByQuoteId(Id quoteId) {
		if (quoteId == null) return new List<Quote_Coverage__c>();
		return [
			SELECT Id, Name, Quote__c, Product__c, Product_Coverage__c,
				   Coverage_Name__c, Coverage_Code__c, Order__c
			FROM Quote_Coverage__c
			WHERE Quote__c = :quoteId
			ORDER BY Order__c NULLS LAST, Coverage_Name__c
		];
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Inserta o actualiza (upsert) una lista de coberturas (Quote_Coverage__c).
	 * @param coverages: Lista de coberturas a guardar
	 * @return void
	 */
	@AuraEnabled
	public static void saveCoverages(List<Quote_Coverage__c> coverages) {
		try {
			upsert coverages;
		} catch (Exception e) {
			throw new AuraHandledException('No se pudieron guardar las coberturas: ' + detalleError(e));
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Busca oportunidades (Opportunity) cuyo Name coincida parcialmente con el termino de busqueda y las devuelve envueltas en OpportunityWrapper.
	 * @param searchTerm: Termino de busqueda a comparar con el Name de la oportunidad (busqueda LIKE)
	 * @return Lista de OpportunityWrapper coincidentes
	 */
	@AuraEnabled(cacheable=false)
	public static List<OpportunityWrapper> searchOpportunities(String searchTerm) {
		String searchPattern = '%' + searchTerm + '%';
		List<Opportunity> opps = [
			SELECT Id, Name, Ramo__c, Account.Name, StageName
			FROM Opportunity
			WHERE Name LIKE :searchPattern
			ORDER BY Name];

		List<OpportunityWrapper> result = new List<OpportunityWrapper>();
		for (Opportunity o : opps) {
			result.add(new OpportunityWrapper(o));
		}
		return result;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Busca aseguradoras (Aseguradora__c) cuyo Name coincida parcialmente con el termino de busqueda, limitando a 10 resultados.
	 * @param searchTerm: Termino de busqueda a comparar con el Name de la aseguradora (busqueda LIKE)
	 * @return Lista de Aseguradora__c coincidentes (maximo 10)
	 */
	@AuraEnabled(cacheable=false)
	public static List<Aseguradora__c> searchAseguradoras(String searchTerm) {
		try {
			String searchPattern = '%' + searchTerm + '%';
			return [SELECT Id, Name FROM Aseguradora__c WHERE Name LIKE :searchPattern ORDER BY Name LIMIT 10];
		} catch (Exception e) {
			throw new AuraHandledException('Error searching aseguradoras: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve los productos activos del catalogo (Product2) filtrados por Ramo (Family) y Aseguradora. Ambos son obligatorios; sin aseguradora no se devuelve nada.
	 * @param ramo: Ramo por el que se filtra (campo Family del producto)
	 * @param aseguradoraId: Id de la aseguradora por la que se filtra
	 * @return Lista de Product2 coincidentes, o lista vacia si falta ramo o aseguradora
	 */
	@AuraEnabled(cacheable=true)
	public static List<Product2> getProducts(String ramo, Id aseguradoraId) {
		if (String.isBlank(ramo) || aseguradoraId == null) return new List<Product2>();
		return [SELECT Id, Name, ProductCode, Aseguradora__c, Aseguradora__r.Name
				FROM Product2
				WHERE IsActive = TRUE
				  AND Family = :ramo
				  AND Aseguradora__c = :aseguradoraId
				ORDER BY Name];
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Obtiene la plantilla de coberturas de un producto. Consulta el objeto ProductCoverage y, si no hay resultados, aplica un fallback sobre el mismo objeto con otros campos. Devuelve un wrapper uniforme (CoverageTemplateWrapper) para que el LWC no dependa de la fuente.
	 * @param productId: Id del producto cuyas coberturas plantilla se solicitan
	 * @return Lista de CoverageTemplateWrapper con las coberturas plantilla, o lista vacia si productId es null
	 */
	@AuraEnabled(cacheable=true)
	public static List<CoverageTemplateWrapper> getCoveragesByProduct(Id productId) {
		if (productId == null) { return new List<CoverageTemplateWrapper>(); }
		// Se lee SIN COMPARTIR: los registros de CoverageType pueden no ser visibles
		// para el usuario por reglas de colaboración; sin esto, CoverageType.Name llega
		// vacío y se mostraría el código (PC-...) en lugar del nombre de la cobertura.
		return new CoberturasCatalogo().porProducto(productId);
	}

	private without sharing class CoberturasCatalogo {
		List<CoverageTemplateWrapper> porProducto(Id productId) {
			List<CoverageTemplateWrapper> result = new List<CoverageTemplateWrapper>();
			try {
				Integer i = 0;
				for (ProductCoverage pc : [
					SELECT Id, Name, CoverageType.Name, CoverageType.CoverageCode
					FROM ProductCoverage
					WHERE ProductId = :productId
					ORDER BY Name
				]) {
					i++;
					CoverageTemplateWrapper w = new CoverageTemplateWrapper();
					w.Id           = pc.Id;
					w.coverageName = (pc.CoverageType != null && String.isNotBlank(pc.CoverageType.Name))
						? pc.CoverageType.Name
						: pc.Name;
					w.coverageCode = pc.CoverageType != null ? pc.CoverageType.CoverageCode : null;
					w.orderNum     = i;
					result.add(w);
				}
			} catch (Exception e) {
				System.debug(':::QuoteCreator::: coberturas catálogo: ' + e.getMessage());
			}
			return result;
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Wrapper uniforme para las coberturas plantilla, de modo que el LWC no distinga la fuente de datos.
	 */
	public class CoverageTemplateWrapper {
		@AuraEnabled public Id Id;
		@AuraEnabled public String coverageName;
		@AuraEnabled public String coverageCode;
		@AuraEnabled public Integer orderNum;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Wrapper de Opportunity expuesto al LWC con los campos basicos (Id, nombre, ramo, etapa y nombre de la cuenta).
	 */
	public class OpportunityWrapper {
		@AuraEnabled public Id Id;
		@AuraEnabled public String Name;
		@AuraEnabled public String Ramo;
		@AuraEnabled public String StageName;
		@AuraEnabled public String AccountName;

		/**
		 * @creation date: 02/07/2026
		 * @author: Sergio Uribe Toledo - Volestra
		 * @description: Constructor. Inicializa el wrapper a partir de una Opportunity, tomando el nombre de la cuenta si esta disponible.
		 * @param o: Opportunity origen de los datos del wrapper
		 * @return void
		 */
		public OpportunityWrapper(Opportunity o) {
			this.Id = o.Id;
			this.Name = o.Name;
			this.Ramo = o.Ramo__c;
			this.StageName = o.StageName;
			this.AccountName = o.Account != null ? o.Account.Name : '';
		}
	}
	/**
	 * @description: Devuelve un texto de error legible. Para errores de guardado (DML)
	 *               arma el detalle de las validaciones/campos que fallaron.
	 */
	private static String detalleError(Exception e) {
		if (e instanceof DmlException) {
			DmlException de = (DmlException) e;
			List<String> partes = new List<String>();
			for (Integer i = 0; i < de.getNumDml(); i++) {
				String m = de.getDmlMessage(i);
				if (String.isNotBlank(m)) { partes.add(m); }
			}
			if (!partes.isEmpty()) { return String.join(partes, ' | '); }
		}
		return e.getMessage();
	}
}