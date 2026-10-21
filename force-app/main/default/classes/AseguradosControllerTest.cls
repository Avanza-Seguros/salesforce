/**
 * @creation date: 12/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas unitarias de AseguradosController: alta masiva y manual de asegurados de una oportunidad
 * colectiva (roles de contacto con parentesco, fecha de nacimiento y edad), consulta, eliminación y copia de los
 * asegurados a la póliza como participantes.
 */
@isTest
private class AseguradosControllerTest {

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Crea la cuenta de la empresa, la oportunidad colectiva y un contacto existente.
	 * @return void
	 */
	@testSetup
	static void setup() {
		Account acc = new Account(Name = 'Empresa Colectivo Test', AnnualRevenue = 100);
		insert acc;
		String etapa = 'Prospecting';
		for (OpportunityStage s : [
			SELECT MasterLabel FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1
		]) { etapa = s.MasterLabel; }
		insert oportunidad('Opp Colectivo Test', acc.Id, etapa);
		insert new Contact(FirstName = 'Laura', LastName = 'Existente', Email = 'laura.existente@test.com', AccountId = acc.Id);
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma una oportunidad colectiva con los campos que el org exige (ramo y agente relacionado).
	 * @param nombre: Nombre de la oportunidad
	 * @param cuentaId: Cuenta de la oportunidad
	 * @param etapa: Etapa
	 * @return Oportunidad sin insertar
	 */
	static Opportunity oportunidad(String nombre, Id cuentaId, String etapa) {
		List<Agente__c> agentes = [SELECT Id FROM Agente__c LIMIT 1];
		if (agentes.isEmpty()) {
			Agente__c ag = new Agente__c(Name = 'Agente Colectivo Test', Status__c = 'Nuevo', Estado_Civil__c = 'Casado');
			insert ag;
			agentes.add(ag);
		}
		Opportunity o = new Opportunity(Name = nombre, AccountId = cuentaId, StageName = etapa,
			CloseDate = Date.today().addDays(30), Agente_Relacionado__c = agentes[0].Id);
		o.put('Ramo__c', 'Vida');
		return o;
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma el JSON de asegurados con las variantes que acepta guardarAsegurados: nombre completo,
	 * nombre y apellidos separados, contacto existente por correo, fecha dd/mm/aaaa y edad sin fecha.
	 * @return JSON de asegurados
	 */
	static String jsonAsegurados() {
		return JSON.serialize(new List<Object>{
			new Map<String, Object>{ 'nombreCompleto' => 'Juan Carlos Pérez García', 'parentesco' => 'Contratante',
				'fechaNacimiento' => '1980-05-10', 'rfc' => 'pega800510abc', 'telefono' => '5551234567' },
			new Map<String, Object>{ 'nombre' => 'María', 'apellidoPaterno' => 'López', 'apellidoMaterno' => 'Ruiz',
				'parentesco' => 'Conyuge', 'fechaNacimiento' => '15/08/1982' },
			new Map<String, Object>{ 'nombre' => 'Laura', 'email' => 'LAURA.EXISTENTE@test.com', 'parentesco' => 'Empleado',
				'edad' => '35' },
			new Map<String, Object>{ 'nombreCompleto' => 'Sofia', 'parentesco' => 'Hijo', 'fechaNacimiento' => '2012-01-01' },
			new Map<String, Object>{ 'parentesco' => 'Otro' } // sin nombre: no se crea
		});
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valida el alta de asegurados: crea los contactos que faltan, reutiliza el existente por correo,
	 * guarda parentesco/fecha/edad, marca un solo principal y no duplica al volver a guardar.
	 * @return void
	 */
	@isTest
	static void testGuardarYListarAsegurados() {
		Opportunity opp = [SELECT Id, AccountId FROM Opportunity LIMIT 1];
		Contact existente = [SELECT Id FROM Contact WHERE Email = 'laura.existente@test.com'];

		Test.startTest();
		Integer total = AseguradosController.guardarAsegurados(opp.Id, jsonAsegurados());
		Integer otraVez = AseguradosController.guardarAsegurados(opp.Id, jsonAsegurados());
		List<AseguradosController.AseguradoRow> filas = AseguradosController.getAsegurados(opp.Id);
		Test.stopTest();

		System.assertEquals(4, total, 'Cuatro asegurados con nombre (el que no tiene nombre se omite)');
		System.assertEquals(4, otraVez, 'Volver a guardar no duplica');
		System.assertEquals(4, filas.size());

		Integer principales = 0;
		Map<String, AseguradosController.AseguradoRow> porParentesco = new Map<String, AseguradosController.AseguradoRow>();
		for (AseguradosController.AseguradoRow r : filas) {
			if (r.isPrincipal == true) { principales++; }
			porParentesco.put(r.parentesco, r);
		}
		System.assertEquals(1, principales, 'Un solo asegurado principal');
		System.assertEquals(true, porParentesco.get('Contratante').isPrincipal, 'El contratante es el principal');
		System.assertEquals(Date.newInstance(1980, 5, 10), porParentesco.get('Contratante').fechaNacimiento);
		System.assertEquals('PEGA800510ABC', porParentesco.get('Contratante').rfc, 'El RFC se guarda en mayúsculas');
		System.assertEquals(Date.newInstance(1982, 8, 15), porParentesco.get('Conyuge').fechaNacimiento, 'Acepta dd/mm/aaaa');
		System.assertNotEquals(null, porParentesco.get('Conyuge').edad, 'La edad se calcula con la fecha de nacimiento');
		System.assertEquals(existente.Id, porParentesco.get('Empleado').contactId, 'Reutiliza el contacto existente por correo');
		System.assertEquals(35, porParentesco.get('Empleado').edad, 'Sin fecha se usa la edad capturada');
		System.assertEquals(opp.AccountId, [SELECT AccountId FROM Contact WHERE Id = :porParentesco.get('Hijo').contactId].AccountId,
			'Los contactos nuevos quedan bajo la cuenta de la oportunidad');
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valida las entradas vacías o inválidas: sin oportunidad, sin JSON, lista vacía y JSON roto.
	 * @return void
	 */
	@isTest
	static void testEntradasVacias() {
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
		System.assertEquals(0, AseguradosController.guardarAsegurados(null, '[]'));
		System.assertEquals(0, AseguradosController.guardarAsegurados(opp.Id, ''));
		System.assertEquals(0, AseguradosController.guardarAsegurados(opp.Id, '[]'));
		System.assertEquals(0, AseguradosController.getAsegurados(null).size());
		AseguradosController.eliminarAsegurado(null);
		Boolean error = false;
		try {
			AseguradosController.guardarAsegurados(opp.Id, '{ no es una lista }');
		} catch (AuraHandledException e) {
			error = true;
		}
		System.assert(error, 'Un JSON inválido debe avisar');
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valida que eliminar un asegurado quite su rol de la oportunidad sin borrar el contacto.
	 * @return void
	 */
	@isTest
	static void testEliminarAsegurado() {
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
		AseguradosController.guardarAsegurados(opp.Id, jsonAsegurados());
		AseguradosController.AseguradoRow fila = AseguradosController.getAsegurados(opp.Id)[0];

		Test.startTest();
		AseguradosController.eliminarAsegurado(fila.ocrId);
		Test.stopTest();

		System.assertEquals(3, AseguradosController.getAsegurados(opp.Id).size(), 'Se quita el rol');
		System.assertEquals(1, [SELECT COUNT() FROM Contact WHERE Id = :fila.contactId], 'El contacto se conserva');
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valida que los asegurados se copien a la póliza como participantes (rol Asegurado) sin
	 * duplicarlos, y que sin oportunidad, póliza o asegurados no se haga nada.
	 * @return void
	 */
	@isTest
	static void testCopiarAseguradosAPoliza() {
		Opportunity opp = [SELECT Id, AccountId FROM Opportunity LIMIT 1];
		AseguradosController.guardarAsegurados(opp.Id, jsonAsegurados());
		InsurancePolicy pol = new InsurancePolicy(Name = 'POL-COLECTIVO-1', NameInsuredId = opp.AccountId,
			SourceOpportunityId = opp.Id, Status = 'Inicial', PremiumAmount = 5000,
			PaymentDueDate = Date.today().addDays(30), EffectiveDate = Datetime.now());
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { pol.PremiumFrequency = pe.getValue(); break; }
		}
		insert pol;

		Test.startTest();
		Integer copiados = AseguradosController.copiarAseguradosAPoliza(opp.Id, pol.Id);
		Integer otraVez = AseguradosController.copiarAseguradosAPoliza(opp.Id, pol.Id);
		Test.stopTest();

		System.assertEquals(4, copiados, 'Un participante por asegurado');
		System.assertEquals(0, otraVez, 'No duplica participantes');
		System.assertEquals(4, [SELECT COUNT() FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :pol.Id]);
		System.assertEquals(0, AseguradosController.copiarAseguradosAPoliza(null, pol.Id));
		System.assertEquals(0, AseguradosController.copiarAseguradosAPoliza(opp.Id, null));

		Account otra = new Account(Name = 'Empresa Sin Asegurados', AnnualRevenue = 100);
		insert otra;
		Opportunity sinAsegurados = oportunidad('Opp Sin Asegurados', otra.Id,
			[SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName);
		insert sinAsegurados;
		System.assertEquals(0, AseguradosController.copiarAseguradosAPoliza(sinAsegurados.Id, pol.Id), 'Sin asegurados no copia nada');
	}
}
