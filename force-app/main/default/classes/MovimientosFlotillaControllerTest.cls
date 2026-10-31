/**
 * @creation date: 31/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas de MovimientosFlotillaController: endosos de una flotilla (baja con motivo, cambio, alta y
 *               reingreso de un vehículo), comparación de un archivo de la aseguradora, renovación (censo desde la
 *               póliza anterior y movimientos sobre el censo) y validaciones.
 */
@isTest
private class MovimientosFlotillaControllerTest {

	static final String SERIE_1 = '3N1CN7AD5KL800001';
	static final String SERIE_2 = '3N1CN7AD5KL800002';
	static final String SERIE_3 = '3N1CN7AD5KL800003';
	static final String SERIE_4 = '3N1CN7AD5KL800004';

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Empresa, póliza de flotilla con 3 vehículos (que vence hoy) y oportunidad de renovación.
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
		Opportunity opp = new Opportunity(Name = 'Opp Renovacion Flotilla', AccountId = acc.Id, StageName = etapa,
			CloseDate = Date.today().addDays(30), Agente_Relacionado__c = agentes[0].Id);
		opp.put('Ramo__c', 'Automoviles');
		opp.put('Tipo_Contratacion__c', 'Colectiva');
		insert opp;
		Datetime inicio = Datetime.now().addDays(-365);
		InsurancePolicy pol = new InsurancePolicy(Name = 'POL-FLOT-1', NameInsuredId = acc.Id, Status = 'Inicial', PremiumAmount = 30000,
			PaymentDueDate = Date.today().addDays(30), EffectiveDate = inicio, ExpirationDate = inicio.addDays(365));
		pol.put('Ramo__c', 'Automoviles');
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { pol.PremiumFrequency = pe.getValue(); break; }
		}
		insert pol;
		PolicyController.guardarVehiculosDesdePdf(pol.Id, acc.Id, null, new List<Object>{
			vehiculo(1, SERIE_1, 'NISSAN VERSA SENSE', 'ABC1234', 9000),
			vehiculo(2, SERIE_2, 'NISSAN NP300 DOBLE CABINA', 'ABC5678', 11000),
			vehiculo(3, SERIE_3, 'CHEVROLET AVEO LS', 'XYZ9999', 10000)
		});
	}

	static Map<String, Object> vehiculo(Integer inciso, String serie, String descripcion, String placas, Decimal prima) {
		return new Map<String, Object>{ 'inciso' => inciso, 'serie' => serie, 'descripcion' => descripcion, 'anio' => 2022,
			'placas' => placas, 'uso' => 'Particular', 'primaTotal' => prima };
	}

	static InsurancePolicy poliza() {
		return [SELECT Id, NameInsuredId FROM InsurancePolicy WHERE Name = 'POL-FLOT-1' LIMIT 1];
	}

	static Id inciso(Id policyId, String serie) {
		return [SELECT Id FROM Inciso_Flotilla__c WHERE Poliza__c = :policyId AND Serie__c = :serie LIMIT 1].Id;
	}

	static String motivo() {
		return Inciso_Flotilla__c.Motivo_Baja__c.getDescribe().getPicklistValues()[0].getValue();
	}

	static Map<String, Object> mov(String tipo, Id id, Map<String, Object> datos, Date fecha) {
		Map<String, Object> m = new Map<String, Object>{ 'tipo' => tipo, 'fecha' => String.valueOf(fecha), 'endoso' => 'END-V1' };
		if (id != null) { m.put('id', id); }
		if (datos != null) { m.put('datos', datos); }
		if (tipo == 'baja') { m.put('motivo', motivo()); }
		return m;
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Endoso: baja (inciso con fecha y motivo, bien de póliza inactivo), cambio de placas y prima, alta de
	 *               un vehículo nuevo y reingreso del que se dio de baja.
	 * @return void
	 */
	@isTest
	static void testEndososPoliza() {
		InsurancePolicy pol = poliza();
		Date hoy = Date.today();
		Id inc1 = inciso(pol.Id, SERIE_1);
		Id inc2 = inciso(pol.Id, SERIE_2);
		Test.startTest();
		Map<String, Object> r = MovimientosFlotillaController.aplicar(pol.Id, JSON.serialize(new List<Object>{
			mov('baja', inc1, null, hoy),
			mov('cambio', inc2, new Map<String, Object>{ 'placas' => 'NEW 0001', 'prima' => 12500 }, hoy),
			mov('alta', null, new Map<String, Object>{ 'serie' => SERIE_4, 'descripcion' => 'TOYOTA HILUX', 'modelo' => 2024,
				'placas' => 'HIL0001', 'valor' => 550000, 'paquete' => 'Amplia', 'prima' => 15000 }, hoy)
		}));
		Test.stopTest();
		System.assertEquals(1, r.get('altas'));
		System.assertEquals(1, r.get('bajas'));
		System.assertEquals(1, r.get('cambios'));

		Inciso_Flotilla__c b = [SELECT Fecha_Baja__c, Motivo_Baja__c, Vehiculo__c FROM Inciso_Flotilla__c WHERE Id = :inc1];
		System.assertEquals(hoy, b.Fecha_Baja__c);
		System.assertEquals(motivo(), b.Motivo_Baja__c);
		InsurancePolicyAsset a = [SELECT IsActive, EffectiveToDate FROM InsurancePolicyAsset WHERE InsurancePolicyId = :pol.Id AND CustomerPropertyId = :b.Vehiculo__c];
		System.assertEquals(false, a.IsActive);
		System.assertEquals(hoy, a.EffectiveToDate);

		Inciso_Flotilla__c c = [SELECT Placas__c, Prima__c, Vehiculo__c FROM Inciso_Flotilla__c WHERE Id = :inc2];
		System.assertEquals('NEW0001', c.Placas__c);
		System.assertEquals(12500, c.Prima__c);
		System.assertEquals('NEW0001', [SELECT RegistrationNumber FROM CustomerProperty WHERE Id = :c.Vehiculo__c].RegistrationNumber);

		Inciso_Flotilla__c n = [SELECT Numero_Inciso__c, Fecha_Alta__c, Valor__c, Paquete__c, Vehiculo__c FROM Inciso_Flotilla__c
			WHERE Poliza__c = :pol.Id AND Serie__c = :SERIE_4];
		System.assertEquals(4, n.Numero_Inciso__c);
		System.assertEquals(hoy, n.Fecha_Alta__c);
		System.assertEquals(550000, n.Valor__c);
		System.assertEquals(hoy, [SELECT EffectiveFromDate FROM InsurancePolicyAsset WHERE InsurancePolicyId = :pol.Id AND CustomerPropertyId = :n.Vehiculo__c].EffectiveFromDate);
		System.assertEquals(3, [SELECT COUNT() FROM Movimiento_Poliza__c WHERE Poliza__c = :pol.Id AND Inciso__c != null]);

		// Reingreso del vehículo dado de baja (misma serie).
		MovimientosFlotillaController.aplicar(pol.Id, JSON.serialize(new List<Object>{
			mov('alta', null, new Map<String, Object>{ 'serie' => SERIE_1, 'prima' => 9500 }, hoy)
		}));
		b = [SELECT Fecha_Baja__c, Fecha_Alta__c, Prima__c FROM Inciso_Flotilla__c WHERE Id = :inc1];
		System.assertEquals(null, b.Fecha_Baja__c);
		System.assertEquals(9500, b.Prima__c);

		Map<String, Object> d = MovimientosFlotillaController.getDatos(pol.Id);
		System.assertEquals(true, d.get('aplica'));
		System.assertEquals(4, ((List<Object>) d.get('vehiculos')).size());
		System.assertEquals(4, ((List<Object>) d.get('movimientos')).size());
		System.assertEquals(true, MovimientosColectivoController.getDatos(pol.Id).get('flotilla'));
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Archivo de la aseguradora contra la póliza: reconoce por serie o por placas, propone alta, baja y cambio.
	 * @return void
	 */
	@isTest
	static void testCompararArchivo() {
		InsurancePolicy pol = poliza();
		List<Object> archivo = new List<Object>{
			// Mismo vehículo, prima nueva.
			new Map<String, Object>{ 'inciso' => 1, 'serie' => SERIE_1.toLowerCase(), 'descripcion' => 'nissan versa sense', 'prima' => 9900, 'tipoVehiculo' => 'Automóviles' },
			// Sin serie: se reconoce por placas y no cambia nada.
			new Map<String, Object>{ 'placas' => 'abc 5678', 'descripcion' => 'NISSAN NP300 DOBLE CABINA' },
			// Nuevo.
			new Map<String, Object>{ 'serie' => SERIE_4, 'descripcion' => 'TOYOTA HILUX', 'modelo' => 2024 }
		};
		Map<String, Object> r = MovimientosFlotillaController.compararArchivo(pol.Id, JSON.serialize(archivo), true);
		System.assertEquals(1, ((List<Object>) r.get('altas')).size());
		System.assertEquals(1, ((List<Object>) r.get('cambios')).size());
		System.assertEquals(1, ((List<Object>) r.get('bajas')).size(), 'El AVEO no viene en el censo completo');
		System.assertEquals(1, r.get('sinCambios'));
		Map<String, Object> c = (Map<String, Object>) ((List<Object>) r.get('cambios'))[0];
		System.assertEquals(1, ((List<Object>) c.get('diferencias')).size(), 'Solo la prima: el tipo de vehículo no cuenta');
		// Solo movimientos: no propone bajas.
		r = MovimientosFlotillaController.compararArchivo(pol.Id, JSON.serialize(archivo), false);
		System.assertEquals(0, ((List<Object>) r.get('bajas')).size());
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Renovación: el censo se llena con los vehículos vigentes de la póliza anterior (sin el dado de
	 *               baja) y sobre él se aplican baja (registrada contra la póliza anterior), cambio y alta.
	 * @return void
	 */
	@isTest
	static void testRenovacion() {
		InsurancePolicy pol = poliza();
		Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Opp Renovacion Flotilla' LIMIT 1];
		MovimientosFlotillaController.aplicar(pol.Id, JSON.serialize(new List<Object>{ mov('baja', inciso(pol.Id, SERIE_3), null, Date.today()) }));

		Map<String, Object> d = MovimientosFlotillaController.getDatos(opp.Id);
		System.assertEquals(pol.Id, d.get('polizaAnteriorId'));
		System.assertEquals(2, d.get('vehiculosAnterior'));
		Test.startTest();
		System.assertEquals(2, MovimientosFlotillaController.traerDePoliza(opp.Id, true));
		Map<String, Id> censo = new Map<String, Id>();
		for (Inciso_Flotilla__c i : [SELECT Id, Serie__c FROM Inciso_Flotilla__c WHERE Oportunidad__c = :opp.Id AND Poliza__c = null]) {
			censo.put(i.Serie__c, i.Id);
		}
		Map<String, Object> r = MovimientosFlotillaController.aplicar(opp.Id, JSON.serialize(new List<Object>{
			mov('baja', censo.get(SERIE_1), null, Date.today()),
			mov('cambio', censo.get(SERIE_2), new Map<String, Object>{ 'valor' => 400000 }, Date.today()),
			mov('alta', null, new Map<String, Object>{ 'serie' => SERIE_4, 'descripcion' => 'TOYOTA HILUX' }, Date.today())
		}));
		Test.stopTest();
		System.assertEquals(1, r.get('bajas'));
		System.assertEquals(1, r.get('cambios'));
		System.assertEquals(1, r.get('altas'));
		System.assertEquals(2, [SELECT COUNT() FROM Inciso_Flotilla__c WHERE Oportunidad__c = :opp.Id AND Poliza__c = null]);
		Movimiento_Poliza__c baja = [SELECT Poliza__c, Inciso__c, Contexto__c FROM Movimiento_Poliza__c WHERE Oportunidad__c = :opp.Id AND Tipo__c = 'Baja'];
		System.assertEquals(pol.Id, baja.Poliza__c);
		System.assertEquals(inciso(pol.Id, SERIE_1), baja.Inciso__c);
		System.assertEquals(400000, [SELECT Valor__c FROM Inciso_Flotilla__c WHERE Id = :censo.get(SERIE_2)].Valor__c);
		System.assertEquals(3, [SELECT Numero_Inciso__c FROM Inciso_Flotilla__c WHERE Oportunidad__c = :opp.Id AND Serie__c = :SERIE_4].Numero_Inciso__c);
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Validaciones: sin motivo, sin fecha, alta de una serie vigente, baja repetida y alta sin serie en la póliza.
	 * @return void
	 */
	@isTest
	static void testValidaciones() {
		InsurancePolicy pol = poliza();
		Id inc1 = inciso(pol.Id, SERIE_1);
		Map<String, Object> sinMotivo = mov('baja', inc1, null, Date.today());
		sinMotivo.remove('motivo');
		Map<String, Object> sinFecha = mov('baja', inc1, null, Date.today());
		sinFecha.remove('fecha');
		List<List<Object>> casos = new List<List<Object>>{
			new List<Object>{ sinMotivo },
			new List<Object>{ sinFecha },
			new List<Object>{ mov('alta', null, new Map<String, Object>{ 'serie' => SERIE_2, 'descripcion' => 'X' }, Date.today()) },
			new List<Object>{ mov('alta', null, new Map<String, Object>{ 'descripcion' => 'Sin serie' }, Date.today()) },
			new List<Object>{ mov('baja', inc1, null, Date.today().addYears(-5)) },
			new List<Object>()
		};
		Integer errores = 0;
		for (List<Object> caso : casos) {
			try {
				MovimientosFlotillaController.aplicar(pol.Id, JSON.serialize(caso));
			} catch (AuraHandledException e) {
				errores++;
			}
		}
		System.assertEquals(casos.size(), errores);
		MovimientosFlotillaController.aplicar(pol.Id, JSON.serialize(new List<Object>{ mov('baja', inc1, null, Date.today()) }));
		try {
			MovimientosFlotillaController.aplicar(pol.Id, JSON.serialize(new List<Object>{ mov('baja', inc1, null, Date.today()) }));
			System.assert(false, 'La baja repetida debe fallar');
		} catch (AuraHandledException e) {
			System.assert(e.getMessage().contains('ya está dado de baja'), e.getMessage());
		}
		Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Opp Renovacion Flotilla' LIMIT 1];
		try {
			MovimientosFlotillaController.traerDePoliza(opp.Id, true);
			MovimientosFlotillaController.aplicar(opp.Id, JSON.serialize(new List<Object>{
				mov('alta', null, new Map<String, Object>{ 'serie' => SERIE_2, 'descripcion' => 'Repetido' }, Date.today()) }));
			System.assert(false, 'La serie repetida en el censo debe fallar');
		} catch (AuraHandledException e) {
			System.assert(e.getMessage().contains('ya está en el censo'), e.getMessage());
		}
		System.assertEquals(true, MovimientosFlotillaController.esFlotilla('Automóviles'));
		System.assertEquals(false, MovimientosFlotillaController.esFlotilla('GMM'));
	}
}
