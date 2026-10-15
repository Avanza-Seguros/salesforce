/**
 * @creation date: 12/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas unitarias de CensoColectivoController: alta del censo de una oportunidad colectiva
 * (titulares, dependientes y categorías), consulta del resumen, agregar/reemplazar, validaciones, eliminación
 * y la llamada a la IA para censos en PDF.
 */
@isTest
private class CensoColectivoControllerTest {

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Crea la empresa contratante y la oportunidad colectiva.
	 * @return void
	 */
	@testSetup
	static void setup() {
		Account acc = new Account(Name = 'Empresa Censo Test', AnnualRevenue = 100);
		insert acc;
		String etapa = 'Prospecting';
		for (OpportunityStage s : [
			SELECT MasterLabel FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1
		]) { etapa = s.MasterLabel; }
		List<Agente__c> agentes = [SELECT Id FROM Agente__c LIMIT 1];
		if (agentes.isEmpty()) {
			Agente__c ag = new Agente__c(Name = 'Agente Censo Test', Status__c = 'Nuevo', Estado_Civil__c = 'Casado');
			insert ag;
			agentes.add(ag);
		}
		Opportunity o = new Opportunity(Name = 'Opp Censo Test', AccountId = acc.Id, StageName = etapa,
			CloseDate = Date.today().addDays(30), Agente_Relacionado__c = agentes[0].Id);
		o.put('Ramo__c', 'Vida');
		o.put('Tipo_Contratacion__c', 'Colectiva');
		insert o;
		// Categoría ya existente de la empresa: debe reutilizarse (sin importar acentos/mayúsculas).
		insert new GroupClass(Name = 'Dirección', AccountId = acc.Id);
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Censo de ejemplo: 2 titulares en 2 categorías, cónyuge e hijo del primero.
	 * @return JSON de MiembroEntrada
	 */
	static String censoJson() {
		return JSON.serialize(new List<Object>{
			new Map<String, Object>{ 'fila' => 2, 'nombre' => 'Juan', 'apellidos' => 'Pérez García', 'fechaNacimiento' => '1980-05-10',
				'sexo' => 'Hombre', 'parentesco' => 'Titular', 'categoria' => 'DIRECCION', 'sueldoAnual' => 600000,
				'sumaAsegurada' => 1000000, 'prima' => 4634.07, 'certificado' => '001', 'numEmpleado' => 'E-1', 'rfc' => 'pega800510abc',
				'email' => 'juan@test.com', 'telefono' => '5551234567', 'fechaAlta' => '2020-01-15' },
			new Map<String, Object>{ 'fila' => 3, 'nombreCompleto' => 'María López Ruiz', 'fechaNacimiento' => '1982-08-15',
				'sexo' => 'Mujer', 'parentesco' => 'Cónyuge', 'titularIndex' => 0, 'certificado' => '001', 'fechaAlta' => '2020-01-15' },
			new Map<String, Object>{ 'fila' => 4, 'nombreCompleto' => 'Sofía Pérez', 'edad' => 10, 'parentesco' => 'Hijo(a)',
				'titularIndex' => 0, 'email' => 'correo-invalido' },
			new Map<String, Object>{ 'fila' => 5, 'nombreCompleto' => 'Pedro', 'edad' => 40, 'parentesco' => 'Titular',
				'categoria' => 'Empleados', 'sueldoAnual' => 200000 }
		});
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Guarda el censo y valida titulares, dependientes, categorías (reutilizada y nueva) y resumen.
	 * @return void
	 */
	@isTest
	static void testGuardarYConsultarCenso() {
		Opportunity opp = [SELECT Id, AccountId FROM Opportunity LIMIT 1];
		Test.startTest();
		Integer total = CensoColectivoController.guardarCenso(opp.Id, censoJson(), true);
		Map<String, Object> censo = CensoColectivoController.getCenso(opp.Id);
		Test.stopTest();

		System.assertEquals(4, total, 'Se guardan los 4 asegurados');
		System.assertNotEquals(null, censo.get('censoId'), 'Se crea el censo de la oportunidad');
		System.assertEquals(2, censo.get('titulares'), 'Dos titulares');
		System.assertEquals(2, censo.get('dependientes'), 'Dos dependientes');
		System.assertEquals(2, [SELECT COUNT() FROM GroupClass WHERE AccountId = :opp.AccountId],
			'Reutiliza "Dirección" y crea "Empleados"');
		System.assertEquals(2, ((List<Object>) censo.get('categorias')).size(), 'Resumen por 2 categorías');
		List<Object> miembros = (List<Object>) censo.get('miembros');
		System.assertEquals('Juan Pérez García', ((Map<String, Object>) miembros[1]).get('titular'),
			'Cada dependiente se lista debajo de su titular');
		System.assertEquals('Pedro', ((Map<String, Object>) miembros[3]).get('nombre'), 'El siguiente titular va después de la familia');

		GroupCensusMember hijo = [SELECT PrimaryGroupCensusMember.Name, GroupClass.Name, AssociationWithPrimaryMbr, Email, Edad__c
			FROM GroupCensusMember WHERE Name = 'Sofía Pérez'];
		System.assertEquals('Juan Pérez García', hijo.PrimaryGroupCensusMember.Name, 'El hijo queda ligado a su titular');
		System.assertEquals('Dirección', hijo.GroupClass.Name, 'El dependiente hereda la categoría del titular');
		System.assertEquals('Child', hijo.AssociationWithPrimaryMbr, 'Parentesco hijo');
		System.assertEquals(null, hijo.Email, 'Un correo inválido no se guarda');
		System.assertEquals(10, hijo.Edad__c, 'Guarda la edad cuando no hay fecha de nacimiento');

		GroupCensusMember juan = [SELECT FirstName, Lastname, RFC__c, Certificado__c FROM GroupCensusMember WHERE Name = 'Juan Pérez García'];
		System.assertEquals('PEGA800510ABC', juan.RFC__c, 'RFC en mayúsculas');
		System.assertEquals('001', juan.Certificado__c, 'Guarda el certificado');
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: "Agregar al censo" suma asegurados y "Reemplazar" deja solo los nuevos.
	 * @return void
	 */
	@isTest
	static void testAgregarYReemplazar() {
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
		Test.startTest();
		CensoColectivoController.guardarCenso(opp.Id, censoJson(), false);
		Integer agregado = CensoColectivoController.guardarCenso(opp.Id, censoJson(), false);
		Integer reemplazado = CensoColectivoController.guardarCenso(opp.Id, censoJson(), true);
		Test.stopTest();
		System.assertEquals(8, agregado, 'Agregar suma a los existentes');
		System.assertEquals(4, reemplazado, 'Reemplazar deja solo la nueva carga');
		System.assertEquals(1, [SELECT COUNT() FROM GroupCensus WHERE Oportunidad__c = :opp.Id], 'Un solo censo por oportunidad');
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valida los errores: censo vacío, JSON inválido, dependiente sin titular, renglón sin nombre
	 * y oportunidad sin empresa. Ninguno deja registros a medias.
	 * @return void
	 */
	@isTest
	static void testValidaciones() {
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
		List<String> casos = new List<String>{
			'[]',
			'{no es json',
			JSON.serialize(new List<Object>{ new Map<String, Object>{ 'fila' => 2, 'nombreCompleto' => 'Ana', 'titularIndex' => 5 } }),
			JSON.serialize(new List<Object>{ new Map<String, Object>{ 'fila' => 2, 'parentesco' => 'Titular' } })
		};
		Integer errores = 0;
		Test.startTest();
		for (String c : casos) {
			try {
				CensoColectivoController.guardarCenso(opp.Id, c, true);
			} catch (AuraHandledException e) {
				errores++;
			}
		}
		opp.AccountId = null;
		update opp;
		try {
			CensoColectivoController.guardarCenso(opp.Id, censoJson(), true);
		} catch (AuraHandledException e) {
			errores++;
			System.assert(e.getMessage().contains('empresa contratante'), 'Mensaje de oportunidad sin cliente: ' + e.getMessage());
		}
		Test.stopTest();
		System.assertEquals(5, errores, 'Todos los casos inválidos se rechazan');
		System.assertEquals(0, [SELECT COUNT() FROM GroupCensusMember], 'No quedan asegurados a medias');
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Elimina el censo con sus asegurados y conserva las categorías de la empresa.
	 * @return void
	 */
	@isTest
	static void testEliminarCenso() {
		Opportunity opp = [SELECT Id, AccountId FROM Opportunity LIMIT 1];
		CensoColectivoController.guardarCenso(opp.Id, censoJson(), true);
		Test.startTest();
		CensoColectivoController.eliminarCenso(opp.Id);
		CensoColectivoController.eliminarCenso(opp.Id); // sin censo: no truena
		Test.stopTest();
		System.assertEquals(0, [SELECT COUNT() FROM GroupCensus WHERE Oportunidad__c = :opp.Id], 'Se elimina el censo');
		System.assertEquals(0, [SELECT COUNT() FROM GroupCensusMember], 'Se eliminan los asegurados');
		System.assertEquals(null, CensoColectivoController.getCenso(opp.Id).get('censoId'), 'Sin censo después de eliminar');
		System.assertEquals(2, [SELECT COUNT() FROM GroupClass WHERE AccountId = :opp.AccountId], 'Las categorías se conservan');
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Lectura de censos en PDF (en pruebas no llama a Einstein) y helpers de texto/fecha/parentesco.
	 * @return void
	 */
	@isTest
	static void testIaYHelpers() {
		Test.startTest();
		System.assertEquals('{"asegurados":[]}', CensoColectivoController.analizarCensoPdf('JUAN PEREZ 10/05/1980 TITULAR'));
		Boolean vacio = false;
		try { CensoColectivoController.analizarCensoPdf('  '); } catch (AuraHandledException e) { vacio = true; }
		Test.stopTest();
		System.assert(vacio, 'Texto vacío se rechaza');

		System.assertEquals('{"a":1}', CensoColectivoController.limpiarJson('```json\n{"a":1}\n```'));
		System.assertEquals('{"asegurados":[]}', CensoColectivoController.limpiarJson('sin json'));
		System.assertEquals('{"asegurados":[]}', CensoColectivoController.limpiarJson(null));
		System.assertEquals(Date.newInstance(1980, 5, 10), CensoColectivoController.fecha('1980-05-10'));
		System.assertEquals(null, CensoColectivoController.fecha('10/05/1980'));
		System.assertEquals('direccion general', CensoColectivoController.llave('  Dirección   GENERAL '));

		System.assertEquals('Self', CensoColectivoController.asociacion('Hijo', true));
		System.assertEquals('Spouse', CensoColectivoController.asociacion('Esposa', false));
		System.assertEquals('Parent-in-law', CensoColectivoController.asociacion('Suegra', false));
		System.assertEquals('Parent', CensoColectivoController.asociacion('Madre', false));
		System.assertEquals('Other', CensoColectivoController.asociacion('Sobrino', false));
		System.assertEquals('Titular', CensoColectivoController.parentescoVisible('Self', false));
		System.assertEquals('Cónyuge', CensoColectivoController.parentescoVisible('Spouse', false));
		System.assertEquals('Otro', CensoColectivoController.parentescoVisible('Other', false));
	}

	/**
	 * @creation date: 15/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Al emitir la póliza el censo pasa a participantes: titulares, dependientes ligados a su titular con
	 *               su parentesco, certificado y categoría; sin duplicar si se vuelve a copiar.
	 * @return void
	 */
	@isTest
	static void testCopiarCensoAPoliza() {
		Opportunity opp = [SELECT Id, AccountId FROM Opportunity LIMIT 1];
		CensoColectivoController.guardarCenso(opp.Id, censoJson(), true);
		InsurancePolicy pol = new InsurancePolicy(Name = 'POL-CENSO-1', NameInsuredId = opp.AccountId, SourceOpportunityId = opp.Id,
			Status = 'Inicial', PremiumAmount = 1200, PaymentDueDate = Date.today().addDays(30), EffectiveDate = Datetime.now(),
			ExpirationDate = Datetime.now().addDays(365));
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { pol.PremiumFrequency = pe.getValue(); break; }
		}
		insert pol;
		Test.startTest();
		Integer creados = CensoColectivoController.copiarCensoAPoliza(opp.Id, pol.Id);
		Integer otraVez = CensoColectivoController.copiarCensoAPoliza(opp.Id, pol.Id);
		Integer vacio = CensoColectivoController.copiarCensoAPoliza(null, pol.Id);
		Test.stopTest();
		System.assertEquals(4, creados, 'Un participante por asegurado del censo');
		System.assertEquals(0, otraVez, 'No duplica al volver a copiar');
		System.assertEquals(0, vacio, 'Sin oportunidad no copia');
		InsurancePolicyParticipant conyuge = [SELECT RelationshipToInsured, RelatedInsPolicyParticipantId, ParticipantCode
			FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :pol.Id AND ParticipantName LIKE 'Mar%'];
		System.assertNotEquals(null, conyuge.RelatedInsPolicyParticipantId, 'Dependiente ligado a su titular');
		System.assertEquals('001', conyuge.ParticipantCode, 'Certificado');
		InsurancePolicyParticipant titular = [SELECT Id, ParticipantCode, RelatedInsPolicyParticipantId FROM InsurancePolicyParticipant
			WHERE InsurancePolicyId = :pol.Id AND ParticipantName LIKE 'Juan%'];
		System.assertEquals('001', titular.ParticipantCode, 'Certificado del titular');
		System.assertEquals(4634.07, [SELECT TermPremiumAmount FROM InsurancePolicyParticipant WHERE Id = :titular.Id].TermPremiumAmount, 'Prima del asegurado');
		System.assertEquals(null, titular.RelatedInsPolicyParticipantId, 'El titular no depende de nadie');
		System.assertEquals(new List<String>{ 'Mujer', 'Esposa' }, CensoColectivoController.parentescoPoliza('Cónyuge', 'Mujer'));
		System.assertEquals(new List<String>{ 'Hijo' }, CensoColectivoController.parentescoPoliza('Secundario', 'Hombre'));
		System.assertEquals(new List<String>{ 'Hija' }, CensoColectivoController.parentescoPoliza('Child', 'Femenino'));
		System.assertEquals(new List<String>{ 'Suegro' }, CensoColectivoController.parentescoPoliza('Suegro', null));
		System.assertEquals(new List<String>{ 'Padre' }, CensoColectivoController.parentescoPoliza('Padre', 'Masculino'));
		System.assertEquals(new List<String>(), CensoColectivoController.parentescoPoliza(null, null));
		System.assertEquals('IVAN', CensoColectivoController.sinPalabraRepetida('IVAN ORLANDO', 'ORLANDO RANGEL'), 'Quita la palabra repetida');
		System.assertEquals('ROMAN ALEJANDRO', CensoColectivoController.sinPalabraRepetida('ROMAN ALEJANDRO', 'REYES SAUCEDO'), 'Sin repetición no cambia');
		System.assertEquals('ORLANDO', CensoColectivoController.sinPalabraRepetida('ORLANDO', 'ORLANDO RANGEL'), 'Un solo nombre no se toca');
		System.assertEquals(null, CensoColectivoController.sinPalabraRepetida(null, 'X'));
		String texto = 'Nombre Certificado Parentesco\nROBLEDO RODRIGUEZ KATTYA 00000001 TITULAR MUJER 47\n'
			+ 'REYES SAUCEDO ROMAN\n00000002 TITULAR HOMBRE 29\nALEJANDRO\n'
			+ 'UTRILLA ACEVEDO BRAULIO\n00000003 TITULAR HOMBRE 35\nRODRIGO\n'
			+ 'SANCHEZ MONTOYA 00000009 TITULAR MUJER 26\nNAOMI MONSERRAT\nMEDINA PEREZ LUIS ANGEL 00000010 TITULAR HOMBRE 26';
		List<String> unidos = CensoColectivoController.unirNombresPartidos(texto).split('\n');
		System.assertEquals(6, unidos.size(), 'Un renglón por asegurado más el encabezado: ' + unidos);
		System.assertEquals('REYES SAUCEDO ROMAN ALEJANDRO 00000002 TITULAR HOMBRE 29', unidos[2], 'Nombre de arriba + de abajo');
		System.assertEquals('UTRILLA ACEVEDO BRAULIO RODRIGO 00000003 TITULAR HOMBRE 35', unidos[3], 'Siguiente asegurado partido');
		System.assertEquals('SANCHEZ MONTOYA NAOMI MONSERRAT 00000009 TITULAR MUJER 26', unidos[4], 'Pedazo de abajo al final del nombre');
		System.assertEquals('ROBLEDO RODRIGUEZ KATTYA 00000001 TITULAR MUJER 47', unidos[1], 'Renglón completo sin cambios');
	}
}
