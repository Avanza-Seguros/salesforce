/**
 * @creation date: 26/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas de NotificacionesSiniestro: carta de programación según la aseguradora, aviso de reembolso con
 *               el folio de la solicitud, campos del folio combinados con los del siniestro, cartas adjuntas y avisos que
 *               no se envían (sin correo o aseguradora sin carta).
 */
@isTest
private class NotificacionesSiniestroTest {

	private static final Datetime INICIO = Datetime.newInstanceGmt(2026, 1, 1, 12, 0, 0);

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Póliza de Gastos médicos con un titular, un siniestro de programación y uno de reembolso.
	 * @return void
	 */
	@testSetup
	static void setup() {
		Account empresa = new Account(Name = 'Empresa Avisos');
		insert empresa;
		Contact titular = new Contact(LastName = 'Titular Avisos', FirstName = 'Ana', AccountId = empresa.Id, Email = 'ana@prueba.com');
		insert titular;
		InsurancePolicy pol = new InsurancePolicy(Name = 'AVISOS-1', NameInsuredId = empresa.Id, Status = 'Inicial', PremiumAmount = 1000,
			PaymentDueDate = Date.today().addDays(30), EffectiveDate = INICIO, ExpirationDate = INICIO.addYears(1));
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { pol.PremiumFrequency = pe.getValue(); break; }
		}
		insert pol;
		Id rt = Schema.SObjectType.Claim.getRecordTypeInfosByDeveloperName().get('Personas').getRecordTypeId();
		Claim programacion = new Claim(Name = 'Nuevo', RecordTypeId = rt, PolicyNumberId = pol.Id, Status = 'Abierto', ClaimType = 'Gastos médicos mayores',
			ClaimReasonType = 'Enfermedad', LossType = 'Programación de cirugía', LossDate = INICIO.addMonths(2), SourceSystem = 'Seguros Monterrey NYL',
			SourceSystemIdentifier = 'SMNYL-777', InitiationDate = Datetime.newInstance(2026, 3, 5, 10, 0, 0), Titular__c = titular.Id,
			Correo_Avisos__c = 'ana@prueba.com', Afectado__c = 'HIJO DE ANA');
		Claim reembolso = programacion.clone(false, true);
		reembolso.LossType = 'Reembolso';
		reembolso.SourceSystemIdentifier = null;
		insert new List<Claim>{ programacion, reembolso };
		insert new PaymentRequest(Name = 'Nueva', ClaimId = reembolso.Id, Status = 'Recibido', ReferenceNumber = 'PB01GMANRX1', SubmissionType = 'Factura');
		insert new ContentVersion(Title = 'Carta', PathOnClient = 'Carta.pdf', VersionData = Blob.valueOf('carta'), Carta_Autorizacion__c = true,
			FirstPublishLocationId = programacion.Id);
		insert new ContentVersion(Title = 'Otro', PathOnClient = 'Otro.pdf', VersionData = Blob.valueOf('otro'), FirstPublishLocationId = programacion.Id);
	}

	// Plantillas de prueba con los campos del folio (en las dos formas en que los escriben las plantillas).
	static void plantillasDePrueba() {
		List<EmailTemplate> ts = new List<EmailTemplate>();
		for (String n : new List<String>{ 'Prueba_Siniestro_Programacion', 'Prueba_Siniestro_Reembolso' }) {
			ts.add(new EmailTemplate(DeveloperName = n, Name = n, TemplateType = 'custom', FolderId = UserInfo.getUserId(), IsActive = true,
				Subject = 'Folio {!Control_de_Folios__c.Folio__c}',
				HtmlValue = '<p>Hola {!Control_de_Folios__c.Titular__c}, póliza {!Control_de_Folios__c:Poliza__c}, acuse {!Control_de_Folios__c:Fecha_de_Acuse__c}, {!Control_de_Folios__c.Otro__c}.</p>'));
		}
		System.runAs(new User(Id = UserInfo.getUserId())) { insert ts; }
		NotificacionesSiniestro.plantillas.put(NotificacionesSiniestro.PROGRAMACION + ':smnyl', 'Prueba_Siniestro_Programacion');
		NotificacionesSiniestro.plantillas.put(NotificacionesSiniestro.REEMBOLSO, 'Prueba_Siniestro_Reembolso');
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Carta de programación (Seguros Monterrey NYL) con la carta adjunta y aviso de reembolso con el folio de
	 *               su solicitud.
	 * @return void
	 */
	@isTest
	static void testProgramacionYReembolso() {
		plantillasDePrueba();
		Claim prog = [SELECT Id FROM Claim WHERE LossType = 'Programación de cirugía'];
		Claim reem = [SELECT Id FROM Claim WHERE LossType = 'Reembolso'];
		PaymentRequest r = [SELECT Id FROM PaymentRequest WHERE ClaimId = :reem.Id];
		Test.startTest();
		List<Messaging.SingleEmailMessage> l = NotificacionesSiniestro.armar(new List<NotificacionesSiniestro.Aviso>{
			new NotificacionesSiniestro.Aviso(NotificacionesSiniestro.PROGRAMACION, prog.Id, null),
			new NotificacionesSiniestro.Aviso(NotificacionesSiniestro.REEMBOLSO, reem.Id, r.Id)
		});
		Integer enviados = NotificacionesSiniestro.enviar(new List<NotificacionesSiniestro.Aviso>{
			new NotificacionesSiniestro.Aviso(NotificacionesSiniestro.PROGRAMACION, prog.Id, null) });
		Test.stopTest();
		System.assertEquals(2, l.size());
		System.assertEquals('Folio SMNYL-777', l[0].getSubject(), 'El número de la aseguradora');
		System.assert(l[0].getHtmlBody().contains('Hola Ana Titular Avisos, póliza AVISOS-1, acuse 05/03/2026, .'), l[0].getHtmlBody());
		System.assertEquals('ana@prueba.com', l[0].getToAddresses()[0]);
		System.assertEquals('correos@avanzaseguro.com', l[0].getCcAddresses()[0]);
		System.assertEquals(1, l[0].getFileAttachments().size(), 'Solo la carta de autorización');
		System.assertEquals('Carta.pdf', l[0].getFileAttachments()[0].getFileName());
		System.assertEquals('Folio PB01GMANRX1', l[1].getSubject(), 'El folio de la solicitud de reembolso');
		System.assertEquals(null, l[1].getFileAttachments(), 'Sin cartas');
		System.assert(enviados <= 1);
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: No se arma el aviso sin correo para avisos ni con una aseguradora sin carta de programación.
	 * @return void
	 */
	@isTest
	static void testSinCorreoNiCarta() {
		plantillasDePrueba();
		Claim prog = [SELECT Id FROM Claim WHERE LossType = 'Programación de cirugía'];
		Claim reem = [SELECT Id FROM Claim WHERE LossType = 'Reembolso'];
		update new List<Claim>{ new Claim(Id = prog.Id, SourceSystem = 'AXA Seguros'), new Claim(Id = reem.Id, Correo_Avisos__c = null) };
		Test.startTest();
		List<Messaging.SingleEmailMessage> l = NotificacionesSiniestro.armar(new List<NotificacionesSiniestro.Aviso>{
			new NotificacionesSiniestro.Aviso(NotificacionesSiniestro.PROGRAMACION, prog.Id, null),
			new NotificacionesSiniestro.Aviso(NotificacionesSiniestro.REEMBOLSO, reem.Id, null)
		});
		Test.stopTest();
		System.assertEquals(0, l.size());
		System.assertEquals('allianz', NotificacionesSiniestro.claveAseguradora('Allianz México'));
		System.assertEquals('smnyl', NotificacionesSiniestro.claveAseguradora('SMNYL'));
		System.assertEquals('a &amp; b', NotificacionesSiniestro.combinar('{!Control_de_Folios__c.Titular__c}',
			new Map<String, String>{ 'Titular__c' => 'a & b' }, true));
	}
}
