/**
 *   @name: ProductCoverageManagerController
 *   @version: 2.0
 *   @creation date: 02/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Controlador del Administrador de Productos y Coberturas. Flujo: se elige la
 *                 Aseguradora, se muestran solo sus productos activos y se asignan coberturas
 *                 (CoverageType) a los productos seleccionados. Las asignaciones se guardan en
 *                 ProductCoverage (objeto estándar) agregando las nuevas y quitando las
 *                 desmarcadas, dentro de una transacción con savepoint.
 */
public with sharing class ProductCoverageManagerController {

	/**
	 * @creation date: 03/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve las aseguradoras con el número de productos activos de cada una, para el selector
	 * del primer paso del LWC.
	 * @return Lista de mapas con Id, Name y productos (número de productos activos)
	 */
	@AuraEnabled(cacheable=false)
	public static List<Map<String, Object>> getAseguradoras() {
		try {
			Map<Id, Integer> productosPorAseguradora = new Map<Id, Integer>();
			for (AggregateResult ar : [
				SELECT Aseguradora__c aseg, COUNT(Id) n FROM Product2
				WHERE IsActive = true AND Aseguradora__c != null GROUP BY Aseguradora__c
			]) {
				productosPorAseguradora.put((Id) ar.get('aseg'), (Integer) ar.get('n'));
			}
			List<Map<String, Object>> out = new List<Map<String, Object>>();
			for (Aseguradora__c a : [SELECT Id, Name FROM Aseguradora__c ORDER BY Name]) {
				Integer n = productosPorAseguradora.containsKey(a.Id) ? productosPorAseguradora.get(a.Id) : 0;
				out.add(new Map<String, Object>{ 'Id' => a.Id, 'Name' => a.Name, 'productos' => n });
			}
			return out;
		} catch (Exception e) {
			throw new AuraHandledException('Error obteniendo aseguradoras: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve los productos activos de la aseguradora indicada, ordenados por nombre.
	 * @param aseguradoraId: Id de la Aseguradora__c seleccionada
	 * @return Productos activos de esa aseguradora (con su ramo en Family); vacío si no llega aseguradora
	 */
	@AuraEnabled(cacheable=false)
	public static List<Product2> getProducts(Id aseguradoraId) {
		if (aseguradoraId == null) { return new List<Product2>(); }
		try {
			return [
				SELECT Id, Name, Family
				FROM Product2
				WHERE IsActive = true AND Aseguradora__c = :aseguradoraId
				ORDER BY Name
			];
		} catch (Exception e) {
			throw new AuraHandledException('Error obteniendo productos: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve el catálogo de tipos de cobertura (CoverageType) ordenado por nombre.
	 * @return List<CoverageType>: Todos los tipos de cobertura.
	 */
	@AuraEnabled(cacheable=true)
	public static List<CoverageType> getCoverages() {
		try {
			return [
				SELECT Id, Name
				FROM CoverageType
				ORDER BY Name
			];
		} catch (Exception e) {
			throw new AuraHandledException('Error obteniendo coberturas: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cuenta, por tipo de cobertura, cuántos de los productos recibidos la tienen asignada en
	 * ProductCoverage. No es cacheable para que, después de guardar, se vea lo que realmente quedó.
	 * @param productIds: IDs de Product2 a evaluar.
	 * @return Map<Id, Integer>: CoverageTypeId -> número de productos (de la lista) que lo tienen.
	 */
	@AuraEnabled(cacheable=false)
	public static Map<Id, Integer> getAssignedCoveragesForMultipleProducts(List<Id> productIds) {
		Map<Id, Integer> coverageCountMap = new Map<Id, Integer>();
		if (productIds == null || productIds.isEmpty()) { return coverageCountMap; }
		try {
			for (AggregateResult result : [
				SELECT CoverageTypeId, COUNT_DISTINCT(ProductId) productCount
				FROM ProductCoverage
				WHERE ProductId IN :productIds
				GROUP BY CoverageTypeId
			]) {
				coverageCountMap.put((Id) result.get('CoverageTypeId'), (Integer) result.get('productCount'));
			}
			return coverageCountMap;
		} catch (Exception e) {
			throw new AuraHandledException('Error obteniendo las coberturas asignadas: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Deja en ProductCoverage exactamente las coberturas indicadas para cada producto seleccionado:
	 * inserta las que faltan y elimina las desmarcadas (las que ya existían se conservan). Valida que todos los
	 * productos pertenezcan a la aseguradora elegida. Todo en una transacción con savepoint/rollback.
	 * @param aseguradoraId: Id de la Aseguradora__c seleccionada
	 * @param productIds: IDs de Product2 a los que se les define su cobertura
	 * @param coverageIds: IDs de CoverageType a asignar (si es null se trata como lista vacía)
	 * @return Resumen con el número de coberturas agregadas y quitadas
	 */
	@AuraEnabled
	public static Map<String, Integer> saveAssignmentsForMultipleProducts(Id aseguradoraId, List<Id> productIds, List<Id> coverageIds) {
		if (aseguradoraId == null) {
			throw new AuraHandledException('Debe seleccionar la aseguradora');
		}
		if (productIds == null || productIds.isEmpty()) {
			throw new AuraHandledException('Debe seleccionar al menos un producto');
		}
		Set<Id> deseadas = new Set<Id>();
		for (Id c : (coverageIds == null ? new List<Id>() : coverageIds)) { if (c != null) { deseadas.add(c); } }

		// Regla: solo productos de la aseguradora seleccionada.
		Set<Id> productos = new Set<Id>(productIds);
		Integer deLaAseguradora = [
			SELECT COUNT() FROM Product2 WHERE Id IN :productos AND Aseguradora__c = :aseguradoraId
		];
		if (deLaAseguradora != productos.size()) {
			throw new AuraHandledException('Todos los productos deben pertenecer a la aseguradora seleccionada.');
		}

		Savepoint sp = Database.setSavepoint();
		try {
			// Coberturas actuales por producto.
			Set<String> existentes = new Set<String>();
			List<ProductCoverage> quitar = new List<ProductCoverage>();
			for (ProductCoverage pc : [
				SELECT Id, ProductId, CoverageTypeId FROM ProductCoverage WHERE ProductId IN :productos
			]) {
				String llave = pc.ProductId + '|' + pc.CoverageTypeId;
				if (deseadas.contains(pc.CoverageTypeId) && !existentes.contains(llave)) {
					existentes.add(llave);
				} else {
					quitar.add(pc); // desmarcada (o duplicada)
				}
			}

			List<ProductCoverage> agregar = new List<ProductCoverage>();
			for (Id productId : productos) {
				for (Id coverageId : deseadas) {
					if (!existentes.contains(productId + '|' + coverageId)) {
						agregar.add(new ProductCoverage(ProductId = productId, CoverageTypeId = coverageId, IsCovered = true));
					}
				}
			}

			if (!quitar.isEmpty()) { delete quitar; }
			if (!agregar.isEmpty()) { insert agregar; }
			return new Map<String, Integer>{ 'agregadas' => agregar.size(), 'quitadas' => quitar.size() };
		} catch (Exception e) {
			Database.rollback(sp);
			throw new AuraHandledException('Error al guardar las asignaciones: ' + e.getMessage());
		}
	}
}
