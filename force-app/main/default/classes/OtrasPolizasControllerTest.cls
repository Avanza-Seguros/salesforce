/**
 * @creation date: 15/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas de OtrasPolizasController: el mismo asegurado, vehículo o ubicación en otra póliza.
 */
@isTest
private class OtrasPolizasControllerTest {

	static final String DIR = 'Av. Insurgentes Sur 1000, Col. Del Valle, Benito Juarez, CDMX, CP 03100';

	@testSetup
	static void setup() {
		Account acc = new Account(Name = 'Empresa Otras Polizas', AnnualRevenue = 100);
		insert acc;
		Datetime inicio = Datetime.now().addDays(-365);
		insert new List<InsurancePolicy>{
			poliza('POL-OTRA-A', acc.Id, 'Vida', inicio.addDays(-365)), poliza('POL-OTRA-B', acc.Id, 'Vida', inicio),
			poliza('POL-AUTO-A', acc.Id, 'Automoviles', inicio.addDays(-365)), poliza('POL-AUTO-B', acc.Id, 'Automoviles', inicio),
			poliza('POL-DANO-A', acc.Id, 'Danos', inicio.addDays(-365)), poliza('POL-DANO-B', acc.Id, 'Danos', inicio)
		};
		String rol = InsurancePolicyParticipant.Role.getDescribe().getPicklistValues()[0].getValue();
		insert new List<InsurancePolicyParticipant>{
			new InsurancePolicyParticipant(InsurancePolicyId = id('POL-OTRA-A'), PrimaryParticipantAccountId = acc.Id, Role = rol,
				ParticipantCode = '001', Identificacion__c = 'GORP800101AB1', FechaNacimiento__c = Date.newInstance(1980, 1, 1)),
			new InsurancePolicyParticipant(InsurancePolicyId = id('POL-OTRA-B'), PrimaryParticipantAccountId = acc.Id, Role = rol,
				ParticipantCode = '014', Identificacion__c = 'GORP800101AB1', FechaNacimiento__c = Date.newInstance(1980, 1, 1))
		};
		insert new List<Inciso_Flotilla__c>{
			new Inciso_Flotilla__c(Poliza__c = id('POL-AUTO-A'), Numero_Inciso__c = 1, Serie__c = '3GCEC14X38M114075', Descripcion__c = 'CHEVROLET SILVERADO'),
			new Inciso_Flotilla__c(Poliza__c = id('POL-AUTO-B'), Numero_Inciso__c = 7, Serie__c = '3GCEC14X38M114075', Descripcion__c = 'CHEVROLET SILVERADO 1500')
		};
		for (String n : new List<String>{ 'POL-DANO-A', 'POL-DANO-B' }) {
			PolicyController.guardarUbicacionesDesdePdf(id(n), acc.Id, new List<Object>{
				new Map<String, Object>{ 'inciso' => '1', 'direccion' => DIR, 'giro' => 'Oficinas', 'sumaAsegurada' => 1000000, 'primaTotal' => 5000 }
			});
		}
	}

	static InsurancePolicy poliza(String nombre, Id accountId, String ramo, Datetime inicio) {
		InsurancePolicy pol = new InsurancePolicy(Name = nombre, NameInsuredId = accountId, Status = 'Inicial', PremiumAmount = 1000,
			PaymentDueDate = Date.today().addDays(30), EffectiveDate = inicio, ExpirationDate = inicio.addDays(365));
		pol.put('Ramo__c', ramo);
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { pol.PremiumFrequency = pe.getValue(); break; }
		}
		return pol;
	}

	static Id id(String nombre) {
		return [SELECT Id FROM InsurancePolicy WHERE Name = :nombre LIMIT 1].Id;
	}

	static List<Object> polizas(Map<String, Object> r) {
		return (List<Object>) r.get('polizas');
	}

	/**
	 * @description: El asegurado (mismo RFC) y el vehículo (misma serie) aparecen en la otra póliza, no en la propia.
	 */
	@isTest
	static void testAseguradoYVehiculo() {
		Id pB = id('POL-OTRA-B');
		Id participante = [SELECT Id FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :pB LIMIT 1].Id;
		Id autoB = id('POL-AUTO-B');
		Id vehiculo = [SELECT Id FROM Inciso_Flotilla__c WHERE Poliza__c = :autoB LIMIT 1].Id;
		Test.startTest();
		Map<String, Object> a = OtrasPolizasController.buscar(participante, pB);
		Map<String, Object> v = OtrasPolizasController.buscar(vehiculo, autoB);
		Test.stopTest();
		System.assertEquals(1, polizas(a).size(), 'El asegurado está en la otra póliza');
		Map<String, Object> pa = (Map<String, Object>) polizas(a)[0];
		System.assertEquals('POL-OTRA-A', pa.get('poliza'));
		System.assertEquals('Mismo RFC', pa.get('coincide'));
		System.assertEquals(1, polizas(v).size(), 'El vehículo está en la otra póliza');
		Map<String, Object> pv = (Map<String, Object>) polizas(v)[0];
		System.assertEquals('POL-AUTO-A', pv.get('poliza'));
		System.assertEquals('Misma serie', pv.get('coincide'));
		System.assertEquals(true, pv.get('vigente'));
	}

	/**
	 * @description: La ubicación con el mismo domicilio aparece en la otra póliza; un registro no soportado da error.
	 */
	@isTest
	static void testUbicacion() {
		Id dB = id('POL-DANO-B');
		Id bien = [SELECT Id FROM InsurancePolicyAsset WHERE InsurancePolicyId = :dB LIMIT 1].Id;
		Test.startTest();
		Map<String, Object> u = OtrasPolizasController.buscar(bien, dB);
		Boolean error = false;
		try { OtrasPolizasController.buscar(dB, dB); } catch (AuraHandledException e) { error = true; }
		Test.stopTest();
		System.assertEquals(1, polizas(u).size(), 'La ubicación está en la otra póliza');
		System.assertEquals('POL-DANO-A', ((Map<String, Object>) polizas(u)[0]).get('poliza'));
		System.assert(error, 'Una póliza no se busca en otras pólizas');
		System.assertEquals(OtrasPolizasController.llaveDomicilio('Av Insurgentes Sur 1000, Del Valle, C.P. 03100'),
			OtrasPolizasController.llaveDomicilio('AV. INSURGENTES SUR 1000, COL. DEL VALLE, CP 03100'));
	}
}
