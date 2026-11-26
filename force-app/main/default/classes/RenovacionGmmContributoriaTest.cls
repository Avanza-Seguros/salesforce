/**
 *   @name: RenovacionGmmContributoriaTest
 *   @version: 1.0
 *   @creation date: 26/11/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Pruebas de RenovacionGmmContributoria: el correo de renovación de GMM contributorio por titular, desde los
 *                 asegurados de la póliza.
 */
@isTest
private class RenovacionGmmContributoriaTest {

	@testSetup
	static void datos() {
		Account a = new Account(Name = 'PCE Paragon Prueba', AnnualRevenue = 100);
		insert a;
		Contact victor = new Contact(AccountId = a.Id, LastName = 'DE ANDA REYNA VICTOR MANUEL', Email = 'victor@ejemplo.test');
		Contact claudia = new Contact(AccountId = a.Id, LastName = 'GARCIA NUNEZ CLAUDIA CECILIA');
		Contact ana = new Contact(AccountId = a.Id, LastName = 'SIN CORREO ANA');
		insert new List<Contact>{ victor, claudia, ana };
		InsurancePolicy pol = new InsurancePolicy(Name = 'GMG-PRUEBA-REN', NameInsuredId = a.Id, Status = 'Inicial', PremiumAmount = 1000, PaymentDueDate = Date.today().addDays(30),
			EffectiveDate = Datetime.newInstance(2026, 12, 1, 12, 0, 0), ExpirationDate = Datetime.newInstance(2027, 12, 1, 12, 0, 0));
		pol.put('Ramo__c', 'GMM');
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { pol.PremiumFrequency = pe.getValue(); break; }
		}
		insert pol;
		Schema.DescribeFieldResult rol = InsurancePolicyParticipant.Role.getDescribe();
		String rolAsegurado = CensoColectivoController.valorPicklist(rol, new List<String>{ 'Asegurado', 'Insured' });
		InsurancePolicyParticipant t = new InsurancePolicyParticipant(InsurancePolicyId = pol.Id, Role = rolAsegurado,
			PrimaryParticipantContactId = victor.Id, ParticipantName = 'DE ANDA REYNA VICTOR MANUEL', ParticipantCode = 'JUB-001', IsActiveParticipant = true,
			TermPremiumAmount = 73540.52, FechaNacimiento__c = Date.today().addYears(-62).addDays(-10));
		t.put('Categoria__c', 'JUBILADOS');
		InsurancePolicyParticipant sin = new InsurancePolicyParticipant(InsurancePolicyId = pol.Id, Role = rolAsegurado,
			PrimaryParticipantContactId = ana.Id, ParticipantName = 'SIN CORREO ANA', ParticipantCode = 'JUB-002', IsActiveParticipant = true, TermPremiumAmount = 1000);
		sin.put('Categoria__c', 'JUBILADOS');
		insert new List<InsurancePolicyParticipant>{ t, sin };
		InsurancePolicyParticipant dep = new InsurancePolicyParticipant(InsurancePolicyId = pol.Id,
			Role = CensoColectivoController.valorPicklist(rol, new List<String>{ 'Miembro familiar', 'FamilyMember' }),
			PrimaryParticipantContactId = claudia.Id, ParticipantName = 'GARCIA NUNEZ CLAUDIA CECILIA', RelatedInsPolicyParticipantId = t.Id,
			ParticipantCode = 'JUB-001', IsActiveParticipant = true, TermPremiumAmount = 85480.40, FechaNacimiento__c = Date.today().addYears(-68).addDays(-10));
		dep.put('Categoria__c', 'JUBILADOS');
		insert dep;
	}

	static Id poliza() { return [SELECT Id FROM InsurancePolicy WHERE Name = 'GMG-PRUEBA-REN' LIMIT 1].Id; }

	@isTest
	static void correoDeUnaFamilia() {
		Id polId = poliza();
		RenovacionGmmContributoria.Familia f;
		for (RenovacionGmmContributoria.Familia x : RenovacionGmmContributoria.familias(polId)) {
			if (x.titular.ParticipantCode == 'JUB-001') { f = x; }
		}
		Assert.areEqual(2, f.miembros.size());
		Assert.areEqual('victor@ejemplo.test', f.correo);
		Assert.areEqual('Víctor Manuel', f.nombrePila);
		RenovacionGmmContributoria.Envio e = new RenovacionGmmContributoria.Envio();
		e.empresa = 'PCE Paragon';
		e.aseguradora = 'Seguros Monterrey';
		e.inicio = Date.newInstance(2026, 12, 1);
		e.fin = Date.newInstance(2027, 12, 1);
		e.fechaLimite = Date.newInstance(2026, 12, 10);
		e.derecho = 130;
		EmailTemplate tpl = new EmailTemplate(Subject = '{{NOMBRE}}, confirma la renovación de tu póliza de Gastos Médicos Mayores {{PERIODO}}',
			HtmlValue = '{{AVISO_PRUEBA}}<p>{{NOMBRE_COMPLETO}} {{CATEGORIA}} {{EMPRESA}} {{INICIO}} al {{FIN}} {{FECHA_LIMITE}} {{NUM_ASEGURADOS}}</p>'
				+ '<table>{{FILAS}}</table><p>{{PRIMA_NETA}}|{{DERECHO}}|{{IVA}}|{{TOTAL}}|{{PRIMA_DIARIA}}</p>'
				+ '<a href="mailto:x@y.z?subject={{PERIODO}}%20-%20{{NOMBRE_COMPLETO}}&body={{LISTA_ASEGURADOS}}">Sí</a>');
		Map<String, String> c = RenovacionGmmContributoria.armar(f, e, tpl, new Map<String, String>());
		Assert.areEqual(null, RenovacionGmmContributoria.vistaPrevia(polId, polId, '2026-12-10', 130));
		Assert.areEqual('Víctor Manuel, confirma la renovación de tu póliza de Gastos Médicos Mayores 2026-2027', c.get('asunto'));
		for (String t : new List<String>{ 'De Anda Reyna Víctor Manuel JUBILADOS PCE Paragon 01/12/2026 al 01/12/2027 10/12/2026 2',
			'$136,957.00|$130.00|$21,933.92|$159,020.92|$435.67', '$85,480.40', '>68<', '>62<', 'García Núñez Claudia Cecilia',
			'subject=2026-2027%20-%20De%20Anda%20Reyna%20V%C3%ADctor%20Manuel', '%0A-%20Garc%C3%ADa%20N%C3%BA%C3%B1ez%20Claudia%20Cecilia' }) {
			Assert.isTrue(c.get('html').contains(t), t + ' en ' + c.get('html'));
		}
	}

	@isTest
	static void enviaYMarcaLaFamilia() {
		Id polId = poliza();
		List<Id> ids = new List<Id>();
		for (InsurancePolicyParticipant p : [SELECT Id FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :polId AND RelatedInsPolicyParticipantId = null]) {
			ids.add(p.Id);
		}
		Map<String, Object> r;
		Test.startTest();
		try {
			r = RenovacionGmmContributoria.enviar(polId, ids, '2026-12-10', 130, 'Copia@Ejemplo.test; copia@ejemplo.test');
		} catch (AuraHandledException e) {
			// Org sin entrega de correo habilitada.
			Assert.isTrue(e.getMessage().contains('correo'), e.getMessage());
		}
		Test.stopTest();
		if (r == null) { return; }
		Assert.areEqual(1, r.get('enviados'), String.valueOf(r));
		Assert.isTrue(String.valueOf(r.get('errores')).contains('SIN CORREO ANA'), String.valueOf(r));
		Assert.areEqual(2, [SELECT COUNT() FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :polId AND Correo_Enviado__c = true]);
	}

	@isTest
	static void validacionesYNombres() {
		Id polId = poliza();
		Id uno = [SELECT Id FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :polId LIMIT 1].Id;
		for (List<Object> caso : new List<List<Object>>{
			new List<Object>{ new List<Id>(), '2026-12-10', 130, 'al menos', null },
			new List<Object>{ new List<Id>{ uno }, null, 130, 'fecha límite', null },
			new List<Object>{ new List<Id>{ uno }, '2026-12-10', -1, 'negativo', null },
			new List<Object>{ new List<Id>{ uno }, '2026-12-10', 130, 'no es válido', 'a@b.com, malo' } }) {
			try {
				RenovacionGmmContributoria.enviar(polId, (List<Id>) caso[0], (String) caso[1], (Decimal) caso[2], (String) caso[4]);
				Assert.fail('Debió fallar: ' + caso);
			} catch (AuraHandledException e) {
				Assert.isTrue(e.getMessage().contains((String) caso[3]), e.getMessage());
			}
		}
		Map<String, String> casos = new Map<String, String>{
			'OCHOA ELIZONDO JOSE RAMON' => 'José Ramón', 'RAMIREZ FREGOSO JOSE DE JESUS' => 'José de Jesús',
			'CAMARENA LEDESMA MARIA DEL CARMEN' => 'María del Carmen', 'JUAN CARLOS MEDINA HERRERA' => 'Juan Carlos',
			'ROBLES GIL BERNAL ANA LUISA' => 'Ana Luisa', 'XYZ QWERTY' => 'Xyz Qwerty' };
		for (String n : casos.keySet()) { Assert.areEqual(casos.get(n), RenovacionGmmContributoria.primerNombre(n), n); }
		Assert.areEqual('Ana de la Torre y López', RenovacionGmmContributoria.nombreVisible('ANA DE LA TORRE Y LOPEZ'));
		Assert.areEqual(null, RenovacionGmmContributoria.edadDe(new InsurancePolicyParticipant()));
		Assert.areEqual(new List<String>{ 'mariana@x.com', 'marco@x.com' }, RenovacionGmmContributoria.correos(' Mariana@x.com,marco@x.com ; mariana@x.com'));
	}
}
