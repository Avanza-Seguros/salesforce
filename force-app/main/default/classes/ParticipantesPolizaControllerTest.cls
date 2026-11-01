/**
 * @creation date: 01/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas de ParticipantesPolizaController: contratante, titular con contacto, dependiente ligado,
 *               beneficiario con porcentaje, participante dado de baja, conductor (otro rol) y coberturas individuales.
 */
@isTest
private class ParticipantesPolizaControllerTest {

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Empresa contratante, póliza de Vida y sus participantes.
	 * @return void
	 */
	@testSetup
	static void setup() {
		Account acc = new Account(Name = 'Empresa Participantes Test', AnnualRevenue = 100, Phone = '5555555555',
			BillingStreet = 'Av. Reforma 100', BillingCity = 'CDMX', BillingPostalCode = '06600');
		insert acc;
		Contact titular = new Contact(LastName = 'Pérez López', FirstName = 'Juan', AccountId = acc.Id, Email = 'juan@test.com',
			MobilePhone = '5511111111', Birthdate = Date.newInstance(1980, 5, 10), Title = 'Gerente', MailingCity = 'CDMX');
		Contact conyuge = new Contact(LastName = 'García', FirstName = 'Ana', AccountId = acc.Id, Birthdate = Date.newInstance(1982, 3, 1));
		insert new List<Contact>{ titular, conyuge };

		Datetime inicio = Datetime.now().addDays(-30);
		InsurancePolicy pol = new InsurancePolicy(Name = 'POL-PART-1', NameInsuredId = acc.Id, Status = 'Inicial', PremiumAmount = 50000,
			PaymentDueDate = Date.today().addDays(30), EffectiveDate = inicio, ExpirationDate = inicio.addDays(365));
		pol.put('Ramo__c', 'Vida');
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { pol.PremiumFrequency = pe.getValue(); break; }
		}
		insert pol;

		Schema.DescribeFieldResult rol = InsurancePolicyParticipant.Role.getDescribe();
		String rolAsegurado = CensoColectivoController.valorPicklist(rol, new List<String>{ 'Asegurado', 'Insured' });
		InsurancePolicyParticipant t = new InsurancePolicyParticipant(InsurancePolicyId = pol.Id, Role = rolAsegurado,
			PrimaryParticipantContactId = titular.Id, ParticipantCode = '1', StandardPremiumAmount = 1200);
		t.put('Categoria__c', 'Ejecutivos');
		InsurancePolicyParticipant baja = new InsurancePolicyParticipant(InsurancePolicyId = pol.Id, Role = rolAsegurado,
			PrimaryParticipantAccountId = acc.Id, ParticipantCode = '2', IsActiveParticipant = false,
			EffectiveToDate = Date.today().addDays(-1));
		InsurancePolicyParticipant conductor = new InsurancePolicyParticipant(InsurancePolicyId = pol.Id,
			Role = CensoColectivoController.valorPicklist(rol, new List<String>{ 'Conductor', 'Driver' }), PrimaryParticipantAccountId = acc.Id);
		insert new List<InsurancePolicyParticipant>{ t, baja, conductor };

		InsurancePolicyParticipant dep = new InsurancePolicyParticipant(InsurancePolicyId = pol.Id,
			Role = CensoColectivoController.valorPicklist(rol, new List<String>{ 'Miembro familiar', 'FamilyMember' }),
			PrimaryParticipantContactId = conyuge.Id, RelatedInsPolicyParticipantId = t.Id, ParticipantCode = '1');
		InsurancePolicyParticipant ben = new InsurancePolicyParticipant(InsurancePolicyId = pol.Id,
			Role = CensoColectivoController.valorPicklist(rol, new List<String>{ 'Beneficiario', 'Beneficiary' }),
			PrimaryParticipantContactId = conyuge.Id, RelatedInsPolicyParticipantId = t.Id, BeneficiarySharePercentage = 100);
		insert new List<InsurancePolicyParticipant>{ dep, ben };

		insert new InsurancePolicyCoverage(InsurancePolicyId = pol.Id, InsurancePolicyParticipantId = t.Id, CoverageName = 'Fallecimiento',
			LimitAmount = 500000, StandardPremiumAmount = 900);
	}

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Agrupa por rol, cuenta vigentes y bajas, y trae contacto, cuenta, titular y coberturas.
	 * @return void
	 */
	@isTest
	static void testGetDatos() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'POL-PART-1' LIMIT 1];
		Test.startTest();
		Map<String, Object> d = ParticipantesPolizaController.getDatos(pol.Id);
		Test.stopTest();

		Map<String, Object> poliza = (Map<String, Object>) d.get('poliza');
		Assert.areEqual('Vida', poliza.get('ramo'));
		Assert.areEqual('Empresa Participantes Test', ((Map<String, Object>) poliza.get('contratante')).get('nombre'));
		Assert.isTrue(((String) ((Map<String, Object>) poliza.get('contratante')).get('domicilio')).contains('CP 06600'));

		Map<String, Integer> resumen = (Map<String, Integer>) d.get('resumen');
		Assert.areEqual(2, resumen.get('asegurado'), 'Titular y el dado de baja');
		Assert.areEqual(1, resumen.get('dependiente'));
		Assert.areEqual(1, resumen.get('beneficiario'));
		Assert.areEqual(1, resumen.get('otro'), 'Conductor');
		Assert.areEqual(1, resumen.get('bajas'));
		Assert.areEqual(4, resumen.get('vigentes'));
		Assert.areEqual(false, d.get('limite'));

		Map<String, Map<String, Object>> porGrupo = new Map<String, Map<String, Object>>();
		for (Object o : (List<Object>) d.get('participantes')) {
			Map<String, Object> p = (Map<String, Object>) o;
			if (p.get('activo') == true) { porGrupo.put((String) p.get('grupo'), p); }
		}
		Map<String, Object> titular = porGrupo.get('asegurado');
		Assert.areEqual('Ejecutivos', titular.get('categoria'));
		Assert.areEqual(500000, (Decimal) titular.get('sumaAsegurada'));
		Assert.areEqual(1, ((List<Object>) titular.get('coberturas')).size());
		Map<String, Object> contacto = (Map<String, Object>) titular.get('contacto');
		Assert.areEqual('juan@test.com', contacto.get('correo'));
		Assert.areEqual('Empresa Participantes Test', contacto.get('cuentaNombre'));

		Map<String, Object> dep = porGrupo.get('dependiente');
		Assert.areEqual(titular.get('id'), dep.get('titularId'));
		Assert.areEqual(titular.get('nombre'), dep.get('titularNombre'));
		Assert.areEqual(100, (Decimal) porGrupo.get('beneficiario').get('porcentaje'));
		Assert.areEqual('Empresa Participantes Test', ((Map<String, Object>) porGrupo.get('otro').get('cuenta')).get('nombre'));
	}

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Grupo por rol (valor o etiqueta) y error con un Id que no es póliza.
	 * @return void
	 */
	@isTest
	static void testGrupoYError() {
		InsurancePolicyParticipant ligado = new InsurancePolicyParticipant();
		Assert.areEqual('asegurado', ParticipantesPolizaController.grupo(new List<String>{ 'Miembro de plan de salud' }, ligado));
		Assert.areEqual('dependiente', ParticipantesPolizaController.grupo(new List<String>{ 'Miembro familiar' }, ligado));
		Assert.areEqual('beneficiario', ParticipantesPolizaController.grupo(new List<String>{ 'Beneficiary' }, ligado));
		Assert.areEqual('otro', ParticipantesPolizaController.grupo(new List<String>{ 'Pagador del acuerdo' }, ligado));
		Assert.areEqual('otro', ParticipantesPolizaController.grupo(new List<String>(), ligado));

		Account acc = [SELECT Id FROM Account LIMIT 1];
		try {
			ParticipantesPolizaController.getDatos(acc.Id);
			Assert.fail('Debió fallar');
		} catch (AuraHandledException e) {
			Assert.isNotNull(e.getMessage());
		}
	}
}
