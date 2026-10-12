/**
 * @creation date: 03/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas unitarias de ProductCoverageManagerController: aseguradoras, productos por aseguradora,
 * catálogo de coberturas y guardado de asignaciones en ProductCoverage.
 */
@isTest
private class ProductCoverageManagerControllerTest {

	/**
	 * @creation date: 03/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Crea dos aseguradoras con un producto cada una y dos tipos de cobertura.
	 * @return void
	 */
	@testSetup
	static void setup() {
		Aseguradora__c a1 = new Aseguradora__c(Name = 'Aseguradora Uno Test');
		Aseguradora__c a2 = new Aseguradora__c(Name = 'Aseguradora Dos Test');
		insert new List<Aseguradora__c>{ a1, a2 };
		insert new List<Product2>{
			new Product2(Name = 'Producto Uno A', IsActive = true, Aseguradora__c = a1.Id, Family = 'Vida'),
			new Product2(Name = 'Producto Uno B', IsActive = true, Aseguradora__c = a1.Id, Family = 'Vida'),
			new Product2(Name = 'Producto Dos', IsActive = true, Aseguradora__c = a2.Id)
		};
		insert new List<CoverageType>{ new CoverageType(Name = 'Cobertura Test 1'), new CoverageType(Name = 'Cobertura Test 2') };
	}

	/**
	 * @creation date: 03/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valida que se listen las aseguradoras con su número de productos y solo los productos de la
	 * aseguradora elegida.
	 * @return void
	 */
	@isTest
	static void testAseguradorasYProductos() {
		Aseguradora__c a1 = [SELECT Id FROM Aseguradora__c WHERE Name = 'Aseguradora Uno Test'];
		Integer productosA1;
		for (Map<String, Object> a : ProductCoverageManagerController.getAseguradoras()) {
			if (a.get('Id') == a1.Id) { productosA1 = (Integer) a.get('productos'); }
		}
		System.assertEquals(2, productosA1);
		List<Product2> prods = ProductCoverageManagerController.getProducts(a1.Id);
		System.assertEquals(2, prods.size(), 'Solo los productos de la aseguradora');
		System.assertEquals(0, ProductCoverageManagerController.getProducts(null).size());
		System.assert(ProductCoverageManagerController.getCoverages().size() >= 2);
	}

	/**
	 * @creation date: 03/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valida que el guardado agregue las coberturas nuevas, quite las desmarcadas, conserve las que
	 * siguen marcadas y rechace productos de otra aseguradora.
	 * @return void
	 */
	@isTest
	static void testGuardarAsignaciones() {
		Aseguradora__c a1 = [SELECT Id FROM Aseguradora__c WHERE Name = 'Aseguradora Uno Test'];
		List<Id> productos = new List<Id>(new Map<Id, Product2>(ProductCoverageManagerController.getProducts(a1.Id)).keySet());
		CoverageType c1 = [SELECT Id FROM CoverageType WHERE Name = 'Cobertura Test 1'];
		CoverageType c2 = [SELECT Id FROM CoverageType WHERE Name = 'Cobertura Test 2'];

		Test.startTest();
		Map<String, Integer> r1 = ProductCoverageManagerController.saveAssignmentsForMultipleProducts(
			a1.Id, productos, new List<Id>{ c1.Id, c2.Id });
		Id conservada = [SELECT Id FROM ProductCoverage WHERE CoverageTypeId = :c1.Id AND ProductId = :productos[0]].Id;
		Map<String, Integer> r2 = ProductCoverageManagerController.saveAssignmentsForMultipleProducts(
			a1.Id, productos, new List<Id>{ c1.Id });
		Test.stopTest();

		System.assertEquals(4, r1.get('agregadas'));
		System.assertEquals(0, r2.get('agregadas'));
		System.assertEquals(2, r2.get('quitadas'), 'Se quita la cobertura desmarcada de los dos productos');
		System.assertEquals(conservada, [SELECT Id FROM ProductCoverage WHERE CoverageTypeId = :c1.Id AND ProductId = :productos[0]].Id,
			'La cobertura que sigue marcada no se borra ni se recrea');
		Map<Id, Integer> conteo = ProductCoverageManagerController.getAssignedCoveragesForMultipleProducts(productos);
		System.assertEquals(2, conteo.get(c1.Id));
		System.assert(!conteo.containsKey(c2.Id));

		// Regla: productos de otra aseguradora se rechazan.
		Product2 otro = [SELECT Id FROM Product2 WHERE Name = 'Producto Dos'];
		try {
			ProductCoverageManagerController.saveAssignmentsForMultipleProducts(a1.Id, new List<Id>{ otro.Id }, new List<Id>{ c1.Id });
			System.assert(false, 'Debe rechazar productos de otra aseguradora');
		} catch (AuraHandledException e) {
			System.assert(true);
		}
	}

	/**
	 * @creation date: 03/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valida que el guardado exija aseguradora y productos.
	 * @return void
	 */
	@isTest
	static void testValidaciones() {
		Aseguradora__c a1 = [SELECT Id FROM Aseguradora__c WHERE Name = 'Aseguradora Uno Test'];
		Integer errores = 0;
		try { ProductCoverageManagerController.saveAssignmentsForMultipleProducts(null, new List<Id>(), null); }
		catch (AuraHandledException e) { errores++; }
		try { ProductCoverageManagerController.saveAssignmentsForMultipleProducts(a1.Id, new List<Id>(), null); }
		catch (AuraHandledException e) { errores++; }
		System.assertEquals(2, errores);
		System.assertEquals(0, ProductCoverageManagerController.getAssignedCoveragesForMultipleProducts(null).size());
	}
}
