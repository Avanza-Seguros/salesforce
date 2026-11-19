/**
 * @creation date: 19/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas de ProductoPorSemejanza: producto igual al plan, el de mayor semejanza, el del ramo cuando
 * no hay pistas y sin aseguradora solo si el texto lo menciona; y la asignación al guardar los datos del PDF.
 */
@isTest
private class ProductoPorSemejanzaTest {

	@TestSetup
	static void datos() {
		Aseguradora__c q = new Aseguradora__c(Name = 'Quálitas Semejanza');
		Aseguradora__c m = new Aseguradora__c(Name = 'Seguros Monterrey Semejanza');
		insert new List<Aseguradora__c>{ q, m };
		insert new List<Product2>{
			new Product2(Name = 'Autos y Pickups Amplio', Family = 'Automoviles', IsActive = true, Aseguradora__c = q.Id),
			new Product2(Name = 'Autos y Pickups Limitado', Family = 'Automoviles', IsActive = true, Aseguradora__c = q.Id),
			new Product2(Name = 'Camiones y Equipo Pesado', Family = 'Automoviles', IsActive = true, Aseguradora__c = q.Id),
			new Product2(Name = 'Motocicletas', Family = 'Vida', IsActive = true, Aseguradora__c = q.Id),
			new Product2(Name = 'Alfa Medical®', Family = 'GMM', IsActive = true, Aseguradora__c = m.Id),
			new Product2(Name = 'Alfa Medical Flex®', Family = 'GMM', IsActive = true, Aseguradora__c = m.Id),
			new Product2(Name = 'Nuevo Plenitud®', Family = 'GMM', IsActive = true, Aseguradora__c = m.Id),
			new Product2(Name = 'Básico Vida', Family = 'Vida', IsActive = true, Aseguradora__c = m.Id),
			new Product2(Name = 'Orvi®', Family = 'Vida', IsActive = true, Aseguradora__c = m.Id),
			new Product2(Name = 'Producto Inactivo Amplia', Family = 'Automoviles', IsActive = false, Aseguradora__c = q.Id)
		};
	}

	private static Id aseguradora(String nombre) { return [SELECT Id FROM Aseguradora__c WHERE Name = :nombre].Id; }
	private static Id producto(String nombre) { return [SELECT Id FROM Product2 WHERE Name = :nombre].Id; }
	private static Map<String, Object> plan(String p) { return new Map<String, Object>{ 'plan' => p }; }

	private static InsurancePolicy poliza(String numero, Id aseguradoraId, String ramo, Id productoId) {
		Account cuenta = new Account(Name = 'Cliente ' + numero, AnnualRevenue = 0);
		insert cuenta;
		InsurancePolicy pol = new InsurancePolicy(Name = numero, NameInsuredId = cuenta.Id, Status = 'Vigente',
			Aseguradora__c = aseguradoraId, Ramo__c = ramo, ProductId = productoId, PremiumAmount = 1000,
			PaymentDueDate = Date.today().addDays(30), EffectiveDate = Datetime.now().addDays(-10),
			ExpirationDate = Datetime.now().addDays(355), Primer_Pago__c = 250);
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { pol.PremiumFrequency = pe.getValue(); break; }
		}
		return pol;
	}

	/**
	 * @creation date: 19/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Sin pistas, entre los productos del ramo gana el que más pólizas de la aseguradora tienen.
	 * @return void
	 */
	@isTest
	static void sinPistasGanaElMasUsado() {
		Id m = aseguradora('Seguros Monterrey Semejanza');
		insert poliza('SEM-002', m, 'GMM', producto('Nuevo Plenitud®'));
		Test.startTest();
		System.assertEquals(producto('Nuevo Plenitud®'), ProductoPorSemejanza.buscar(m, 'GMM', null, null), 'El más usado');
		System.assertEquals(producto('Alfa Medical Flex®'), ProductoPorSemejanza.buscar(m, 'GMM', plan('Alfa Medical Flex'), null), 'El plan manda');
		Test.stopTest();
	}

	/**
	 * @creation date: 19/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: El plan igual o parecido al nombre elige ese producto ("AMPLIA" = "Amplio", "BÁSICO NUEVO
	 * PLENITUD" = "Nuevo Plenitud®", "ALFA MEDICAL FLEX" = "Alfa Medical Flex®") y nunca uno inactivo.
	 * @return void
	 */
	@isTest
	static void eligeElIgualOElMasParecido() {
		Id q = aseguradora('Quálitas Semejanza');
		Id m = aseguradora('Seguros Monterrey Semejanza');
		Test.startTest();
		System.assertEquals(producto('Autos y Pickups Amplio'), ProductoPorSemejanza.buscar(q, 'Automoviles', plan('AMPLIA'), null), 'Amplia = Amplio');
		System.assertEquals(producto('Autos y Pickups Limitado'), ProductoPorSemejanza.buscar(q, 'Automoviles', plan('LIMITADA'), null), 'Limitada = Limitado');
		System.assertEquals(producto('Nuevo Plenitud®'), ProductoPorSemejanza.buscar(m, 'GMM', plan('BÁSICO NUEVO PLENITUD'), null), 'Plenitud');
		System.assertEquals(producto('Alfa Medical Flex®'), ProductoPorSemejanza.buscar(m, 'GMM', plan('ALFA MEDICAL FLEX'), null), 'Flex');
		System.assertEquals(producto('Alfa Medical®'), ProductoPorSemejanza.buscar(m, 'GMM', plan('Alfa Medical'), null), 'Igual');
		System.assertEquals(producto('Orvi®'), ProductoPorSemejanza.buscar(m, 'Vida', null, 'Carátula de póliza ORVI 99 vida entera'), 'Por el texto');
		Test.stopTest();
	}

	/**
	 * @creation date: 19/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Sin pistas se elige el producto más general del ramo de la aseguradora; sin aseguradora solo si
	 * el texto menciona al producto.
	 * @return void
	 */
	@isTest
	static void sinPistasYSinAseguradora() {
		Id q = aseguradora('Quálitas Semejanza');
		Id m = aseguradora('Seguros Monterrey Semejanza');
		Test.startTest();
		System.assertEquals(producto('Alfa Medical®'), ProductoPorSemejanza.buscar(m, 'GMM', null, null), 'El más general del ramo');
		Id vida = ProductoPorSemejanza.buscar(m, 'Vida', new Map<String, Object>(), '');
		System.assertEquals('Vida', [SELECT Family FROM Product2 WHERE Id = :vida].Family, 'Uno del ramo');
		System.assertNotEquals(null, ProductoPorSemejanza.buscar(q, null, null, null), 'Con aseguradora siempre hay producto');
		System.assertEquals(null, ProductoPorSemejanza.buscar(null, 'GMM', null, 'Póliza de gastos médicos'), 'Sin aseguradora ni mención');
		System.assertEquals(producto('Nuevo Plenitud®'), ProductoPorSemejanza.buscar(null, 'GMM', plan('Nuevo Plenitud'), null), 'Sin aseguradora pero con plan');
		Aseguradora__c sinProductos = new Aseguradora__c(Name = 'Sin Productos Semejanza');
		insert sinProductos;
		System.assertEquals(null, ProductoPorSemejanza.buscar(sinProductos.Id, 'GMM', null, null), 'Aseguradora sin productos');
		System.assertEquals('GMM', ProductoPorSemejanza.ramoCanonico('Gastos Médicos Mayores'), 'GMM');
		System.assertEquals('Danos', ProductoPorSemejanza.ramoCanonico('Hogar'), 'Hogar');
		System.assertEquals('Vida', ProductoPorSemejanza.ramoCanonico('Ahorro'), 'Ahorro');
		System.assertEquals(15, ProductoPorSemejanza.puntajeRamo('Danos', 'Empresarial').intValue(), 'Patrimoniales');
		Test.stopTest();
	}

	/**
	 * @creation date: 19/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Al guardar los datos del PDF, una póliza sin producto toma el de mayor semejanza.
	 * @return void
	 */
	@isTest
	static void guardarDatosAsignaProducto() {
		Id q = aseguradora('Quálitas Semejanza');
		InsurancePolicy pol = poliza('SEM-001', q, 'Automoviles', null);
		insert pol;
		Test.startTest();
		Map<String, Object> resumen = PolicyController.guardarDatosPolizaDesdePdf(pol.Id, null,
			JSON.serialize(new Map<String, Object>{ 'plan' => 'LIMITADA' }));
		Test.stopTest();
		System.assertEquals(1, resumen.get('producto'), 'Avisa que asignó el producto');
		System.assertEquals(producto('Autos y Pickups Limitado'),
			[SELECT ProductId FROM InsurancePolicy WHERE Id = :pol.Id].ProductId, 'Producto asignado');
	}
}
