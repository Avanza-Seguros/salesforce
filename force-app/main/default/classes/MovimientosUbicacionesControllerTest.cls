/**
 * @creation date: 01/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas de MovimientosUbicacionesController: endosos de una póliza de Daños (baja con motivo, cambio,
 *               alta y reingreso de una ubicación), renovación (listado desde la póliza anterior, movimientos sobre el
 *               listado y emisión con ese listado) y validaciones.
 */
@isTest
private class MovimientosUbicacionesControllerTest {

	static final String DIR_1 = 'Av. Insurgentes Sur 1000, Col. Del Valle, Benito Juarez, CDMX, CP 03100';
	static final String DIR_2 = 'Calle Industria 25, Parque Industrial, Tlalnepantla, Edo. Mex., CP 54030';
	static final String DIR_3 = 'Av. Vallarta 3000, Col. Vallarta, Guadalajara, Jal., CP 44690';
	static final String DIR_4 = 'Av. 5 de Febrero 1500, Zona Industrial, Queretaro, Qro., CP 76120';

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Empresa, póliza de Daños con 3 ubicaciones (que vence hoy) y oportunidad de renovación.
	 * @return void
	 */
	@testSetup
	static void setup() {
		Account acc = new Account(Name = 'Empresa Danos Test', AnnualRevenue = 100);
		insert acc;
		String etapa = 'Prospecting';
		for (OpportunityStage s : [
			SELECT MasterLabel FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1
		]) { etapa = s.MasterLabel; }
		List<Agente__c> agentes = [SELECT Id FROM Agente__c LIMIT 1];
		if (agentes.isEmpty()) {
			Agente__c ag = new Agente__c(Name = 'Agente Danos Test', Status__c = 'Nuevo', Estado_Civil__c = 'Casado');
			insert ag;
			agentes.add(ag);
		}
		Opportunity opp = new Opportunity(Name = 'Opp Renovacion Danos', AccountId = acc.Id, StageName = etapa,
			CloseDate = Date.today().addDays(30), Agente_Relacionado__c = agentes[0].Id);
		opp.put('Ramo__c', 'Danos');
		opp.put('Tipo_Contratacion__c', 'Colectiva');
		insert opp;
		Datetime inicio = Datetime.now().addDays(-365);
		insert poliza('POL-DAN-1', acc.Id, null, inicio);
		PolicyController.guardarUbicacionesDesdePdf(poliza().Id, acc.Id, new List<Object>{
			ubicacion(1, DIR_1, 12000000, 18000),
			ubicacion(2, DIR_2, 25000000, 41000),
			ubicacion(3, DIR_3, 8000000, 11000)
		});
	}

	static InsurancePolicy poliza(String nombre, Id accountId, Id oppId, Datetime inicio) {
		InsurancePolicy pol = new InsurancePolicy(Name = nombre, NameInsuredId = accountId, Status = 'Inicial', PremiumAmount = 70000,
			PaymentDueDate = Date.today().addDays(30), EffectiveDate = inicio, ExpirationDate = inicio.addDays(365), SourceOpportunityId = oppId);
		pol.put('Ramo__c', 'Danos');
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { pol.PremiumFrequency = pe.getValue(); break; }
		}
		return pol;
	}

	static Map<String, Object> ubicacion(Integer inciso, String dir, Decimal suma, Decimal prima) {
		return new Map<String, Object>{ 'inciso' => String.valueOf(inciso), 'direccion' => dir, 'giro' => 'Oficinas',
			'sumaAsegurada' => suma, 'primaTotal' => prima };
	}

	static InsurancePolicy poliza() {
		return [SELECT Id, NameInsuredId FROM InsurancePolicy WHERE Name = 'POL-DAN-1' LIMIT 1];
	}

	static Id bien(Id policyId, Integer inciso) {
		return [SELECT Id FROM InsurancePolicyAsset WHERE InsurancePolicyId = :policyId AND AssetName LIKE :('Inciso ' + inciso + ' -%') LIMIT 1].Id;
	}

	static String motivo() {
		return InsurancePolicyAsset.Motivo_Baja__c.getDescribe().getPicklistValues()[0].getValue();
	}

	static Map<String, Object> mov(String tipo, Id id, Map<String, Object> datos, Date fecha) {
		Map<String, Object> m = new Map<String, Object>{ 'tipo' => tipo, 'fecha' => String.valueOf(fecha), 'endoso' => 'END-U1' };
		if (id != null) { m.put('id', id); }
		if (datos != null) { m.put('datos', datos); }
		if (tipo == 'baja') { m.put('motivo', motivo()); }
		return m;
	}

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Endoso: baja con motivo, cambio de suma, prima y giro, alta de una ubicación nueva y reingreso.
	 * @return void
	 */
	@isTest
	static void testEndososPoliza() {
		InsurancePolicy pol = poliza();
		Id b1 = bien(pol.Id, 1);
		Id b2 = bien(pol.Id, 2);
		Test.startTest();
		Map<String, Object> r = MovimientosUbicacionesController.aplicar(pol.Id, JSON.serialize(new List<Object>{
			mov('baja', b1, null, Date.today()),
			mov('cambio', b2, new Map<String, Object>{ 'sumaAsegurada' => 26000000, 'prima' => 43000, 'giro' => 'Almacén' }, Date.today()),
			mov('alta', null, new Map<String, Object>{ 'direccion' => DIR_4, 'giro' => 'Planta', 'sumaAsegurada' => 30000000, 'prima' => 39000 }, Date.today())
		}));
		Map<String, Object> reingreso = MovimientosUbicacionesController.aplicar(pol.Id, JSON.serialize(new List<Object>{
			mov('alta', null, new Map<String, Object>{ 'direccion' => DIR_1, 'sumaAsegurada' => 12500000 }, Date.today())
		}));
		Test.stopTest();
		System.assertEquals(1, r.get('bajas'));
		System.assertEquals(1, r.get('cambios'));
		System.assertEquals(1, r.get('altas'));
		System.assertEquals(1, reingreso.get('altas'));
		InsurancePolicyAsset a1 = [SELECT IsActive, Fecha_Baja__c, Suma_Asegurada__c FROM InsurancePolicyAsset WHERE Id = :b1];
		System.assertEquals(null, a1.Fecha_Baja__c, 'Reingreso');
		System.assertEquals(true, a1.IsActive);
		System.assertEquals(12500000, a1.Suma_Asegurada__c);
		InsurancePolicyAsset a2 = [SELECT Suma_Asegurada__c, StandardPremiumAmount, CustomerProperty.Uso__c FROM InsurancePolicyAsset WHERE Id = :b2];
		System.assertEquals(26000000, a2.Suma_Asegurada__c);
		System.assertEquals(43000, a2.StandardPremiumAmount);
		System.assertEquals('Almacén', a2.CustomerProperty.Uso__c);
		InsurancePolicyAsset a4 = [SELECT AssetName, EffectiveFromDate, Suma_Asegurada__c FROM InsurancePolicyAsset WHERE InsurancePolicyId = :pol.Id AND AssetName LIKE 'Inciso 4 -%'];
		System.assertEquals(Date.today(), a4.EffectiveFromDate);
		System.assertEquals(30000000, a4.Suma_Asegurada__c);
		System.assertEquals(4, [SELECT COUNT() FROM Movimiento_Poliza__c WHERE Poliza__c = :pol.Id]);
		Map<String, Object> d = MovimientosUbicacionesController.getDatos(pol.Id);
		System.assertEquals(true, d.get('aplica'));
		System.assertEquals(4, ((List<Object>) d.get('ubicaciones')).size());
		Movimiento_Poliza__c baja = [SELECT Motivo_Baja_Ubicacion__c, Certificado__c FROM Movimiento_Poliza__c WHERE Poliza__c = :pol.Id AND Tipo__c = 'Baja'];
		System.assertEquals(motivo(), baja.Motivo_Baja_Ubicacion__c);
		System.assertEquals('Inciso 1', baja.Certificado__c);
	}

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Renovación: listado desde la póliza anterior, baja, cambio y alta en el listado y emisión de la
	 *               póliza nueva con ese listado, ligada a la anterior.
	 * @return void
	 */
	@isTest
	static void testRenovacion() {
		InsurancePolicy pol = poliza();
		Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Opp Renovacion Danos' LIMIT 1];
		MovimientosUbicacionesController.aplicar(pol.Id, JSON.serialize(new List<Object>{ mov('baja', bien(pol.Id, 3), null, Date.today()) }));
		Map<String, Object> d = MovimientosUbicacionesController.getDatos(opp.Id);
		System.assertEquals(pol.Id, d.get('polizaAnteriorId'));
		System.assertEquals(2, d.get('ubicacionesAnterior'));
		System.assertEquals(2, MovimientosUbicacionesController.traerDePoliza(opp.Id, true));
		List<Categoria_Colectiva__c> lista = MovimientosUbicacionesController.censo(opp.Id, null);
		System.assertEquals('Oficinas', MovimientosUbicacionesController.giro(lista[0]));
		Test.startTest();
		Map<String, Object> r = MovimientosUbicacionesController.aplicar(opp.Id, JSON.serialize(new List<Object>{
			mov('baja', lista[0].Id, null, Date.today()),
			mov('cambio', lista[1].Id, new Map<String, Object>{ 'sumaAsegurada' => 27000000, 'giro' => 'Bodega' }, Date.today()),
			mov('alta', null, new Map<String, Object>{ 'direccion' => DIR_4, 'nombre' => 'Planta', 'sumaAsegurada' => 30000000, 'prima' => 39000 }, Date.today())
		}));
		InsurancePolicy nueva = poliza('POL-DAN-2', pol.NameInsuredId, opp.Id, Datetime.now());
		insert nueva;
		Map<String, Object> emision = PolicyController.completarPoliza(nueva.Id, opp.Id);
		Test.stopTest();
		System.assertEquals(1, r.get('bajas'));
		System.assertEquals(1, r.get('cambios'));
		System.assertEquals(1, r.get('altas'));
		System.assertEquals(2, emision.get('ubicaciones'), JSON.serialize(emision));
		System.assertEquals(pol.Id, [SELECT PriorPolicyId FROM InsurancePolicy WHERE Id = :nueva.Id].PriorPolicyId, 'Póliza anterior');
		System.assertEquals(27000000, [SELECT Suma_Asegurada__c FROM InsurancePolicyAsset WHERE InsurancePolicyId = :nueva.Id AND AssetName LIKE 'Inciso 1 -%'].Suma_Asegurada__c);
		Movimiento_Poliza__c baja = [SELECT Poliza__c, Contexto__c FROM Movimiento_Poliza__c WHERE Oportunidad__c = :opp.Id AND Tipo__c = 'Baja'];
		System.assertEquals(pol.Id, baja.Poliza__c);
		System.assertEquals(3, ((List<Object>) MovimientosColectivoController.historial(opp.Id)).size());
	}

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Validaciones: sin motivo, alta sin domicilio, alta de una ubicación vigente, cambio de domicilio en la
	 *               póliza, fecha anterior al inicio, sin movimientos y alta repetida en la renovación.
	 * @return void
	 */
	@isTest
	static void testValidaciones() {
		InsurancePolicy pol = poliza();
		Id b1 = bien(pol.Id, 1);
		Map<String, Object> sinMotivo = mov('baja', b1, null, Date.today());
		sinMotivo.remove('motivo');
		List<List<Object>> casos = new List<List<Object>>{
			new List<Object>{ sinMotivo },
			new List<Object>{ mov('alta', null, new Map<String, Object>{ 'giro' => 'X' }, Date.today()) },
			new List<Object>{ mov('alta', null, new Map<String, Object>{ 'direccion' => DIR_2 }, Date.today()) },
			new List<Object>{ mov('cambio', b1, new Map<String, Object>{ 'direccion' => DIR_4 }, Date.today()) },
			new List<Object>{ mov('baja', b1, null, Date.today().addYears(-5)) },
			new List<Object>()
		};
		Integer errores = 0;
		for (List<Object> caso : casos) {
			try {
				MovimientosUbicacionesController.aplicar(pol.Id, JSON.serialize(caso));
			} catch (AuraHandledException e) {
				errores++;
			}
		}
		Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Opp Renovacion Danos' LIMIT 1];
		MovimientosUbicacionesController.traerDePoliza(opp.Id, false);
		try {
			MovimientosUbicacionesController.aplicar(opp.Id, JSON.serialize(new List<Object>{
				mov('alta', null, new Map<String, Object>{ 'direccion' => DIR_1 }, Date.today()) }));
		} catch (AuraHandledException e) {
			errores++;
		}
		System.assertEquals(casos.size() + 1, errores, 'Todos los casos deben fallar');
		System.assertEquals(0, [SELECT COUNT() FROM Movimiento_Poliza__c WHERE Poliza__c = :pol.Id]);
		System.assertEquals(false, MovimientosUbicacionesController.esUbicaciones('GMM'));
	}
}
