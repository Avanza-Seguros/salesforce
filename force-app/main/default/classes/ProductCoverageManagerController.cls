/**
 *   @name: ProductCoverageManagerController
 *   @version: 1.0
 *   @creation date: 02/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Controlador del Administrador de Productos y Coberturas. Expone al
 *                 LWC el catálogo de productos activos y de tipos de cobertura, el
 *                 conteo de productos por cobertura, y el guardado masivo de
 *                 asignaciones producto x cobertura (borra las existentes de los
 *                 productos seleccionados y recrea las nuevas dentro de una
 *                 transacción con savepoint).
 */
public with sharing class ProductCoverageManagerController {

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve los productos activos ordenados por nombre para poblar el selector del LWC.
	 * @return List<Product2>: Productos con IsActive = true.
	 */
	@AuraEnabled(cacheable=true)
	public static List<Product2> getProducts() {
		try {
			return [
				SELECT Id, Name
				FROM Product2
				WHERE IsActive = true
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
	 * @description: Cuenta, por tipo de cobertura, cuántos de los productos recibidos la tienen asignada.
	 *               Usa una consulta agregada para no traer todos los registros a memoria.
	 * @param productIds: IDs de Product2 a evaluar.
	 * @return Map<Id, Integer>: CoverageTypeId -> número de productos (de la lista) que lo tienen.
	 */
	@AuraEnabled(cacheable=true)
	public static Map<Id, Integer> getAssignedCoveragesForMultipleProducts(List<Id> productIds) {
		if (productIds == null || productIds.isEmpty()) {
			return new Map<Id, Integer>();
		}

		try {
			Map<Id, Integer> coverageCountMap = new Map<Id, Integer>();

			// Agrupar por CoverageTypeId y contar cuántos productos distintos tienen cada cobertura.
			AggregateResult[] results = [
				SELECT CoverageTypeId, COUNT_DISTINCT(ProductId) productCount
				FROM ProductCoverage
				WHERE ProductId IN :productIds
				GROUP BY CoverageTypeId
			];

			for (AggregateResult result : results) {
				Id coverageId = (Id) result.get('CoverageTypeId');
				Integer count = (Integer) result.get('productCount');
				coverageCountMap.put(coverageId, count);
			}

			return coverageCountMap;
		} catch (Exception e) {
			System.debug('Error getting assigned coverages: ' + e.getMessage());
			return new Map<Id, Integer>();
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Reemplaza las coberturas de los productos indicados: elimina las asignaciones
	 *               (ProductCoverage) existentes de esos productos y crea el producto cartesiano
	 *               producto x cobertura recibido. Todo en una transacción con savepoint/rollback.
	 * @param productIds: IDs de Product2 a los que se les redefine su cobertura.
	 * @param coverageIds: IDs de CoverageType a asignar (si es null se trata como lista vacía).
	 * @return
	 */
	@AuraEnabled
	public static void saveAssignmentsForMultipleProducts(List<Id> productIds, List<Id> coverageIds) {
		// Validaciones de entrada.
		if (productIds == null || productIds.isEmpty()) {
			throw new AuraHandledException('Debe seleccionar al menos un producto');
		}

		if (coverageIds == null) {
			coverageIds = new List<Id>();
		}

		Savepoint sp = Database.setSavepoint();

		try {
			// 1. Eliminar todas las asignaciones existentes de los productos seleccionados.
			List<ProductCoverage> existingAssignments = [
				SELECT Id
				FROM ProductCoverage
				WHERE ProductId IN :productIds
			];

			if (!existingAssignments.isEmpty()) {
				delete existingAssignments;
				System.debug('Eliminadas ' + existingAssignments.size() + ' asignaciones existentes');
			}

			// 2. Construir las nuevas asignaciones (producto x cobertura).
			List<ProductCoverage> newAssignments = new List<ProductCoverage>();

			for (Id productId : productIds) {
				for (Id coverageId : coverageIds) {
					if (coverageId != null) {
						newAssignments.add(new ProductCoverage(
							ProductId = productId,
							CoverageTypeId = coverageId
						));
					}
				}
			}

			// 3. Insertar las nuevas asignaciones.
			if (!newAssignments.isEmpty()) {
				insert newAssignments;
				System.debug('Insertadas ' + newAssignments.size() + ' nuevas asignaciones');
			}

			System.debug('Guardado exitoso para ' + productIds.size() + ' productos con ' + coverageIds.size() + ' coberturas');

		} catch (Exception e) {
			Database.rollback(sp);
			System.debug('Error en saveAssignmentsForMultipleProducts: ' + e.getMessage());
			throw new AuraHandledException('Error al guardar las asignaciones: ' + e.getMessage());
		}
	}
}
