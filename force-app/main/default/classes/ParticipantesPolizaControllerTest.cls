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
			PrimaryParticipantContactId = titular.Id, ParticipantCode = '1', StandardPremiumAmount = 1200,
			Fecha_Antiguedad__c = Date.newInstance(2020, 3, 15));
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
		// Archivo adjunto al contacto del titular.
		Contact juan = [SELECT Id FROM Contact WHERE FirstName = 'Juan' LIMIT 1];
		ContentVersion cv = new ContentVersion(Title = 'INE Juan', PathOnClient = 'ine.pdf', VersionData = Blob.valueOf('pdf'));
		insert cv;
		Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
		insert new ContentDocumentLink(ContentDocumentId = docId, LinkedEntityId = juan.Id, ShareType = 'V');
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
		Assert.areEqual(Date.newInstance(2020, 3, 15), (Date) titular.get('antiguedad'));
		Assert.areEqual('Reconocida', titular.get('antiguedadOrigen'));
		Assert.areEqual('Inicio', porGrupo.get('dependiente').get('antiguedadOrigen'), 'Sin fecha de alta cuenta desde el inicio de la póliza');
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

		// Sin registros de movimiento se deduce: alta para los vigentes y baja para los dados de baja.
		Assert.areEqual('Alta', titular.get('tipoMovimiento'));
		List<Object> archivos = (List<Object>) titular.get('archivos');
		Assert.areEqual(1, archivos.size(), 'El archivo del contacto aparece en el titular');
		Assert.areEqual('INE Juan', ((Map<String, Object>) archivos[0]).get('titulo'));
		Assert.areEqual(0, ((List<Object>) porGrupo.get('dependiente').get('archivos')).size(), 'La cónyuge no tiene archivos');
		for (Object o : (List<Object>) d.get('participantes')) {
			Map<String, Object> p = (Map<String, Object>) o;
			if (p.get('activo') != true) { Assert.areEqual('Baja', p.get('tipoMovimiento'), 'El dado de baja muestra su baja'); }
		}
	}

	/**
	 * @creation date: 11/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Envío de correo: plantillas disponibles, envío al titular con su archivo, marca de enviado, aviso del
	 *               participante sin correo y validaciones.
	 * @return void
	 */
	@isTest
	static void testEnviarCorreo() {
		EmailTemplate tpl = new EmailTemplate(Name = 'Bienvenida Participante Test', DeveloperName = 'Bienvenida_Participante_Test_X1',
			TemplateType = 'text', FolderId = UserInfo.getUserId(), IsActive = true, Subject = 'Bienvenido', Body = 'Hola {!Contact.FirstName}');
		System.runAs(new User(Id = UserInfo.getUserId())) { insert tpl; }
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'POL-PART-1' LIMIT 1];
		Contact juan = [SELECT Id FROM Contact WHERE FirstName = 'Juan' LIMIT 1];
		ContentVersion cv = new ContentVersion(Title = 'Certificado Juan', PathOnClient = 'cert.pdf', VersionData = Blob.valueOf('pdf'));
		insert cv;
		insert new ContentDocumentLink(ContentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId,
			LinkedEntityId = juan.Id, ShareType = 'V');
		InsurancePolicyParticipant titular = [SELECT Id FROM InsurancePolicyParticipant WHERE PrimaryParticipantContactId = :juan.Id AND ParticipantCode = '1' LIMIT 1];
		InsurancePolicyParticipant dep = [SELECT Id FROM InsurancePolicyParticipant WHERE RelatedInsPolicyParticipantId = :titular.Id AND BeneficiarySharePercentage = null LIMIT 1];

		Boolean hayPlantilla = false;
		for (Map<String, Object> p : ParticipantesPolizaController.getPlantillas()) { if (p.get('id') == tpl.Id) { hayPlantilla = true; } }
		Assert.isTrue(hayPlantilla, 'La plantilla activa aparece en la lista');

		Test.startTest();
		Map<String, Object> r;
		try {
			r = ParticipantesPolizaController.enviarCorreo(pol.Id, new List<Id>{ titular.Id, dep.Id }, tpl.Id, true);
		} catch (AuraHandledException e) {
			// Org sin entrega de correo habilitada: se informa el motivo.
			Assert.isNotNull(e.getMessage());
		}
		Test.stopTest();
		if (r != null) {
			List<String> errores = (List<String>) r.get('errores');
			Assert.isTrue(String.join(errores, ' ').contains('no tiene correo'), 'La cónyuge no tiene correo');
			if ((Integer) r.get('enviados') == 1) {
				InsurancePolicyParticipant t = [SELECT Correo_Enviado__c, Fecha_Envio_Correo__c, Plantilla_Correo__c FROM InsurancePolicyParticipant WHERE Id = :titular.Id];
				Assert.isTrue(t.Correo_Enviado__c);
				Assert.isNotNull(t.Fecha_Envio_Correo__c);
				Assert.areEqual('Bienvenida Participante Test', t.Plantilla_Correo__c);
				Map<String, Object> d = ParticipantesPolizaController.getDatos(pol.Id);
				for (Object o : (List<Object>) d.get('participantes')) {
					Map<String, Object> p = (Map<String, Object>) o;
					if (p.get('id') == titular.Id) { Assert.areEqual(true, p.get('correoEnviado')); }
				}
			}
		}

		for (List<Object> caso : new List<List<Object>>{ new List<Object>{ new List<Id>(), tpl.Id }, new List<Object>{ new List<Id>{ titular.Id }, null } }) {
			try {
				ParticipantesPolizaController.enviarCorreo(pol.Id, (List<Id>) caso[0], (Id) caso[1], false);
				Assert.fail('Debió fallar');
			} catch (AuraHandledException e) {
				Assert.isNotNull(e.getMessage());
			}
		}
	}

	// Al dado de baja siempre se le adjunta su baja: una constancia PDF si no se subió documento, o el documento subido.
	// A los activos solo se les adjunta si se pidió.
	@isTest
	static void testAdjuntoDeBaja() {
		InsurancePolicy pol = [SELECT Id, Name, EffectiveDate, ExpirationDate FROM InsurancePolicy WHERE Name = 'POL-PART-1' LIMIT 1];
		InsurancePolicyParticipant baja = [SELECT Id FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :pol.Id AND IsActiveParticipant = false AND EffectiveToDate != null LIMIT 1];
		Movimiento_Poliza__c mov = new Movimiento_Poliza__c(Poliza__c = pol.Id, Participante__c = baja.Id, Tipo__c = 'Baja',
			Contexto__c = 'Endoso', Fecha_Movimiento__c = Date.today(), Numero_Endoso__c = 'E-9');
		insert mov;
		List<InsurancePolicyParticipant> ps = [
			SELECT Id, ParticipantName, ParticipantCode, PrimaryParticipantContactId, PrimaryParticipantAccountId, IsActiveParticipant, Correo_Personal__c,
				Motivo_Baja__c, EffectiveToDate
			FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :pol.Id AND (IsActiveParticipant = false OR ParticipantCode = '1')
		];
		Test.startTest();
		Map<Id, List<Messaging.EmailFileAttachment>> r = ParticipantesPolizaController.adjuntos(ps, false, pol, 'Aseguradora Test');
		Assert.areEqual(1, r.size(), 'Sin pedir adjuntos solo lleva archivo el dado de baja');
		Assert.areEqual(1, r.get(baja.Id).size());
		Assert.isTrue(r.get(baja.Id)[0].getFileName().endsWith('.pdf'), 'Constancia de baja generada');

		ContentVersion cv = new ContentVersion(Title = 'Baja firmada', PathOnClient = 'baja.pdf', VersionData = Blob.valueOf('pdf'),
			FirstPublishLocationId = mov.Id);
		insert cv;
		r = ParticipantesPolizaController.adjuntos(ps, false, pol, 'Aseguradora Test');
		Test.stopTest();
		Assert.areEqual('Baja firmada.pdf', r.get(baja.Id)[0].getFileName(), 'Si se subió documento se adjunta ese');
		Assert.areEqual(1, r.get(baja.Id).size());
	}

	// El correo cierra solo el último movimiento del participante y no vuelve a cambiar uno ya cerrado.
	@isTest
	static void testCerrarMovimientos() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'POL-PART-1' LIMIT 1];
		InsurancePolicyParticipant t = [SELECT Id FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :pol.Id AND ParticipantCode = '1' AND RelatedInsPolicyParticipantId = null LIMIT 1];
		Movimiento_Poliza__c mov = new Movimiento_Poliza__c(Poliza__c = pol.Id, Participante__c = t.Id, Tipo__c = 'Alta',
			Contexto__c = 'Endoso', Fecha_Movimiento__c = Date.today());
		insert mov;
		ParticipantesPolizaController.cerrarMovimientos(pol.Id, new Set<Id>{ t.Id });
		Datetime cierre = [SELECT Fecha_Cierre__c FROM Movimiento_Poliza__c WHERE Id = :mov.Id].Fecha_Cierre__c;
		Assert.isNotNull(cierre);
		ParticipantesPolizaController.cerrarMovimientos(pol.Id, new Set<Id>{ t.Id });
		Assert.areEqual(cierre, [SELECT Fecha_Cierre__c FROM Movimiento_Poliza__c WHERE Id = :mov.Id].Fecha_Cierre__c);
		ParticipantesPolizaController.cerrarMovimientos(pol.Id, new Set<Id>());
	}

	// Marcadores {{...}} de las plantillas: valores, enlaces sin valor y marcadores desconocidos.
	@isTest
	static void testLlenarMarcadores() {
		Map<String, String> v = new Map<String, String>{ 'NOMBRE_ASEGURADO' => 'José <Pérez>', 'POLIZA' => 'POL-1' };
		String html = ParticipantesPolizaController.llenar('Hola {{NOMBRE_ASEGURADO}} {{POLIZA}} <a href="{{LINK_RED}}">x</a>{{OTRO}}', v, true);
		Assert.areEqual('Hola José &lt;Pérez&gt; POL-1 <a href="#">x</a>', html);
		Assert.areEqual('Hola José <Pérez>', ParticipantesPolizaController.llenar('Hola {{NOMBRE_ASEGURADO}}', v, false));
		Assert.areEqual('Sin marcadores', ParticipantesPolizaController.llenar('Sin marcadores', v, true));
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
