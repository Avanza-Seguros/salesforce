/**
 * @creation date: 30/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas unitarias de CensoVehiculosController: alta del censo de vehículos de una oportunidad
 * colectiva de Autos, resumen por tipo, agregar (actualiza por serie) y reemplazar, vehículos ya en una póliza
 * (no se modifican ni se borran), validaciones y eliminación.
 */
@isTest
private class CensoVehiculosControllerTest {

	/**
	 * @creation date: 30/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Crea la empresa contratante y la oportunidad colectiva de Autos.
	 * @return void
	 */
	@testSetup
	static void setup() {
		Account acc = new Account(Name = 'Empresa Flotilla Test', AnnualRevenue = 100);
		insert acc;
		String etapa = 'Prospecting';
		for (OpportunityStage s : [
			SELECT MasterLabel FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1
		]) { etapa = s.MasterLabel; }
		List<Agente__c> agentes = [SELECT Id FROM Agente__c LIMIT 1];
		if (agentes.isEmpty()) {
			Agente__c ag = new Agente__c(Name = 'Agente Flotilla Test', Status__c = 'Nuevo', Estado_Civil__c = 'Casado');
			insert ag;
			agentes.add(ag);
		}
		Opportunity o = new Opportunity(Name = 'Opp Flotilla Test', AccountId = acc.Id, StageName = etapa,
			CloseDate = Date.today().addDays(30), Agente_Relacionado__c = agentes[0].Id);
		o.put('Ramo__c', 'Automoviles');
		o.put('Tipo_Contratacion__c', 'Colectiva');
		insert o;
	}

	/**
	 * @creation date: 30/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Vehículo de ejemplo como lo manda el LWC.
	 * @param inciso: número de inciso
	 * @param serie: número de serie
	 * @param tipo: tipo de vehículo
	 * @param valor: valor asegurado
	 * @return Map con los datos del vehículo
	 */
	static Map<String, Object> vehiculo(Integer inciso, String serie, String tipo, Decimal valor) {
		return new Map<String, Object>{
			'inciso' => inciso, 'serie' => serie, 'descripcion' => 'CHEVROLET AVEO LS', 'modelo' => 2022, 'placas' => 'ABC123',
			'uso' => 'Particular', 'tipoVehiculo' => tipo, 'paquete' => 'Amplia', 'tipoValor' => 'Comercial', 'valor' => valor,
			'dedDM' => 5, 'dedRT' => 10, 'rc' => 3000000, 'prima' => 1000
		};
	}

	/**
	 * @creation date: 30/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Guarda, agrega (la misma serie se actualiza), reemplaza y elimina; los vehículos ya en una póliza
	 * se conservan.
	 * @return void
	 */
	@isTest
	static void testCensoVehiculos() {
		Id oppId = [SELECT Id FROM Opportunity LIMIT 1].Id;
		Test.startTest();
		Integer total = CensoVehiculosController.guardarCensoVehiculos(oppId, JSON.serialize(new List<Object>{
			vehiculo(1, '3g1tc5cf0nl000001', 'Automóviles', 250000),
			vehiculo(2, '3G1TC5CF0NL000002', 'Automóviles', 260000),
			vehiculo(3, null, 'Camiones', 900000)
		}), true);
		System.assertEquals(3, total);

		Map<String, Object> censo = CensoVehiculosController.getCensoVehiculos(oppId);
		System.assertEquals(3, censo.get('total'));
		System.assertEquals(0, censo.get('enPoliza'));
		System.assertEquals(1410000, (Decimal) censo.get('valorTotal'));
		System.assertEquals(2, ((List<Object>) censo.get('tipos')).size(), 'Automóviles y Camiones');
		Inciso_Flotilla__c uno = [
			SELECT Serie__c, Modelo__c, Deducible_DM__c, Responsabilidad_Civil__c, Cotizacion__c
			FROM Inciso_Flotilla__c WHERE Numero_Inciso__c = 1
		];
		System.assertEquals('3G1TC5CF0NL000001', uno.Serie__c, 'Serie en mayúsculas');
		System.assertEquals(2022, uno.Modelo__c);
		System.assertEquals(5, uno.Deducible_DM__c);
		System.assertEquals(null, uno.Cotizacion__c);

		// Agregar: la misma serie actualiza el vehículo en vez de duplicarlo.
		total = CensoVehiculosController.guardarCensoVehiculos(oppId, JSON.serialize(new List<Object>{
			vehiculo(1, '3G1TC5CF0NL000001', 'Automóviles', 300000), vehiculo(4, '3G1TC5CF0NL000004', 'Automóviles', 100000)
		}), false);
		System.assertEquals(4, total);
		System.assertEquals(300000, [SELECT Valor__c FROM Inciso_Flotilla__c WHERE Numero_Inciso__c = 1].Valor__c);

		// Un vehículo ya en una póliza no se modifica ni se borra al reemplazar o eliminar.
		Account acc = [SELECT Id FROM Account LIMIT 1];
		InsurancePolicy pol = new InsurancePolicy(Name = 'FLOT-001', NameInsuredId = acc.Id, Status = 'Inicial',
			PremiumAmount = 1000, PaymentDueDate = Date.today().addDays(30),
			EffectiveDate = Datetime.newInstance(Date.today(), Time.newInstance(12, 0, 0, 0)),
			ExpirationDate = Datetime.newInstance(Date.today().addYears(1), Time.newInstance(12, 0, 0, 0)));
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { pol.PremiumFrequency = pe.getValue(); break; }
		}
		insert pol;
		update new Inciso_Flotilla__c(Id = [SELECT Id FROM Inciso_Flotilla__c WHERE Numero_Inciso__c = 2].Id, Poliza__c = pol.Id);
		total = CensoVehiculosController.guardarCensoVehiculos(oppId, JSON.serialize(new List<Object>{
			vehiculo(2, '3G1TC5CF0NL000002', 'Camiones', 1), vehiculo(5, '3G1TC5CF0NL000005', 'Automóviles', 100000)
		}), true);
		System.assertEquals(2, total, 'El de la póliza y el nuevo');
		System.assertEquals(260000, [SELECT Valor__c FROM Inciso_Flotilla__c WHERE Numero_Inciso__c = 2].Valor__c);
		System.assertEquals(1, CensoVehiculosController.getCensoVehiculos(oppId).get('enPoliza'));

		System.assertEquals(1, CensoVehiculosController.eliminarCensoVehiculos(oppId), 'Queda el de la póliza');

		// Validaciones.
		Boolean fallo = false;
		try { CensoVehiculosController.guardarCensoVehiculos(oppId, '[]', true); } catch (AuraHandledException e) { fallo = true; }
		System.assert(fallo, 'Sin vehículos');
		fallo = false;
		try { CensoVehiculosController.guardarCensoVehiculos(oppId, '{x', true); } catch (AuraHandledException e) { fallo = true; }
		System.assert(fallo, 'JSON inválido');
		Test.stopTest();
	}
}
