/**
 *   @name: CorreoOportunidadIATest
 *   @version: 1.0
 *   @creation date: 18/11/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Pruebas de CorreoOportunidadIA y del envío del correo de la oportunidad redactado con IA.
 */
@isTest
private class CorreoOportunidadIATest {

	private static final String PLANTILLA = 'Prueba_CorreoOportunidadIA_Test';

	@testSetup
	static void datos() {
		System.runAs(new User(Id = UserInfo.getUserId())) {
			insert new EmailTemplate(Name = 'Prueba correo IA', DeveloperName = PLANTILLA, TemplateType = 'text',
				FolderId = UserInfo.getUserId(), Subject = 'Cotización', Body = 'Hola', IsActive = true);
		}
		Account a = new Account(Name = 'Cliente Correo IA');
		insert a;
		Contact c = new Contact(FirstName = 'Ana', LastName = 'López', Email = 'ana.lopez@ejemplo.com', AccountId = a.Id);
		insert c;
		String etapa = 'Prospecting';
		for (OpportunityStage s : [
			SELECT MasterLabel FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1
		]) { etapa = s.MasterLabel; }
		Opportunity o = new Opportunity(Name = 'Opp Correo IA', AccountId = a.Id, StageName = etapa,
			CloseDate = Date.today().addDays(30));
		for (Schema.PicklistEntry pe : Opportunity.Ramo__c.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { o.Ramo__c = pe.getValue(); break; }
		}
		insert o;
		Quote q = new Quote(Name = 'Plan Amplio', OpportunityId = o.Id, PrimaAnual__c = 12500, Prima_Total__c = 12500,
			Ramos__c = o.Ramo__c);
		q.put('Frecuencia_de_prima__c', 'Anual');
		insert q;
		insert new ContentVersion(Title = 'Cotizacion GNP', PathOnClient = 'Cotizacion GNP.pdf', VersionData = Blob.valueOf('pdf'),
			FirstPublishLocationId = o.Id);
	}

	private static EnvioCorreoPlantilla.Solicitud solicitud() {
		EnvioCorreoPlantilla.Solicitud s = new EnvioCorreoPlantilla.Solicitud();
		s.plantilla = PLANTILLA;
		s.destinatarioId = [SELECT Id FROM Contact LIMIT 1].Id;
		s.registroId = [SELECT Id FROM Opportunity LIMIT 1].Id;
		s.adjuntarArchivos = true;
		s.promptIA = 'Correo_Cotizacion_Cliente';
		return s;
	}

	@isTest
	static void armaDatosYCorreo() {
		Opportunity o = [SELECT Id FROM Opportunity LIMIT 1];
		Contact c = [SELECT Id FROM Contact LIMIT 1];
		Map<String, Object> d = (Map<String, Object>) JSON.deserializeUntyped(
			CorreoOportunidadIA.datos(o.Id, c.Id, new List<String>{ 'Cotizacion GNP.pdf' }));
		System.assertEquals('Ana López', d.get('destinatario'));
		System.assertEquals('Ana', d.get('nombreDestinatario'));
		System.assertEquals(true, ((Map<String, Object>) ((List<Object>) d.get('cotizaciones'))[0]).get('recomendada'));

		// Recomendación: más suma asegurada por una prima a lo más 10% mayor gana a la de menor prima.
		List<Map<String, Object>> qs = new List<Map<String, Object>>{
			new Map<String, Object>{ 'primaAnual' => 1000, 'sumaAsegurada' => 100000 },
			new Map<String, Object>{ 'primaAnual' => 1080, 'sumaAsegurada' => 200000 },
			new Map<String, Object>{ 'primaAnual' => 2000, 'sumaAsegurada' => 900000 }
		};
		CorreoOportunidadIA.marcarRecomendada(qs);
		System.assertEquals(null, qs[0].get('recomendada'));
		System.assertEquals(true, qs[1].get('recomendada'));
		System.assertEquals(null, qs[2].get('recomendada'));
		System.assertEquals('Cliente Correo IA', d.get('cliente'));
		System.assertEquals(1, ((List<Object>) d.get('cotizaciones')).size());
		System.assertEquals(1, ((List<Object>) d.get('pdfsAdjuntos')).size());

		CorreoOportunidadIA.Correo r = CorreoOportunidadIA.interpretar(
			'```json\n{"asunto": "Tus cotizaciones", "cuerpo_html": "<p>Hola Ana</p>"}\n```');
		System.assertEquals('Tus cotizaciones', r.asunto);
		System.assert(r.html.contains('<p>Hola Ana</p>'));
		System.assert(r.html.contains('Avanza Seguro'));
		System.assertEquals('<p>Hola Ana</p>', r.cuerpo, 'El cuerpo de la IA sin marco');

		for (String malo : new List<String>{ null, 'sin json', '{"asunto": ""}' }) {
			try {
				CorreoOportunidadIA.interpretar(malo);
				System.assert(false, 'Debe rechazar: ' + malo);
			} catch (CorreoOportunidadIA.CorreoIAException e) {
				System.assertNotEquals(null, e.getMessage());
			}
		}
	}

	@isTest
	static void enviaRedactadoConIA() {
		CorreoOportunidadIA.respuestaPrueba = '{"asunto": "Tus cotizaciones de seguro", "cuerpo_html": "<p>Hola Ana</p>"}';
		Test.startTest();
		EnvioCorreoPlantilla.Resultado r = EnvioCorreoPlantilla.enviar(new List<EnvioCorreoPlantilla.Solicitud>{ solicitud() })[0];
		Test.stopTest();
		// Si la org permite enviar correos, se indica que lo redactó la IA.
		if (r.enviado) {
			System.assert(r.mensaje.contains('redactado con IA'), r.mensaje);
		}
	}

	// Póliza del cliente de prueba con prima, vigencia, fecha de pago en 5 días y una cobertura.
	private static InsurancePolicy poliza() {
		Account a = [SELECT Id FROM Account LIMIT 1];
		InsurancePolicy p = new InsurancePolicy(Name = 'POL-IA-001', NameInsuredId = a.Id, Status = 'Vigente',
			PremiumAmount = 15000, PaymentDueDate = Date.today().addDays(5), Moneda__c = 'PESOS', Primer_Pago__c = 3750,
			EffectiveDate = Datetime.newInstanceGmt(Date.newInstance(2026, 1, 15), Time.newInstance(12, 0, 0, 0)),
			ExpirationDate = Datetime.newInstanceGmt(Date.newInstance(2027, 1, 15), Time.newInstance(12, 0, 0, 0)));
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { p.PremiumFrequency = pe.getValue(); break; }
		}
		insert p;
		insert new InsurancePolicyCoverage(InsurancePolicyId = p.Id, CoverageName = 'Daños materiales', LimitAmount = 350000);
		insert new ContentVersion(Title = 'Poliza POL-IA-001', PathOnClient = 'Poliza POL-IA-001.pdf',
			VersionData = Blob.valueOf('pdf'), FirstPublishLocationId = p.Id);
		return p;
	}

	@isTest
	static void armaDatosDeLaPoliza() {
		InsurancePolicy p = poliza();
		Contact c = [SELECT Id FROM Contact LIMIT 1];
		Test.startTest();
		Map<String, Object> d = (Map<String, Object>) JSON.deserializeUntyped(
			CorreoOportunidadIA.datosPoliza(p.Id, c.Id, new List<String>{ 'Poliza POL-IA-001.pdf' }));
		Test.stopTest();
		System.assertEquals('POL-IA-001', d.get('numeroPoliza'));
		System.assertEquals('Cliente Correo IA', d.get('cliente'));
		System.assertEquals('Ana', d.get('nombreDestinatario'));
		System.assertEquals('15 de enero de 2026', d.get('vigenciaDesde'));
		System.assertEquals('15 de enero de 2027', d.get('vigenciaHasta'));
		System.assertEquals('MXN', d.get('moneda'));
		System.assertEquals(5, d.get('diasParaFechaLimitePago'));
		System.assertNotEquals(null, d.get('fechaLimitePago'));
		System.assertEquals(1, d.get('totalCoberturas'));
		System.assertEquals('nueva', d.get('situacion'));
		String pasos = String.join((List<Object>) d.get('pasosAgente'), ' | ');
		System.assert(pasos.contains('(faltan 5 días)'), pasos);
		System.assert(pasos.contains('le falta: producto'), pasos);
		System.assert(!pasos.contains('nueva vigencia'), pasos);
		System.assertEquals('USD', CorreoOportunidadIA.moneda('Dólares americanos'));
		System.assertEquals('UDI', CorreoOportunidadIA.moneda('UDIS'));
		System.assertEquals(null, CorreoOportunidadIA.fechaTexto(null));
		System.assertEquals('15 asegurados, 9 miembros familiares y 1 titular', CorreoOportunidadIA.personasPorRol(
			new Map<String, Integer>{ 'Titular' => 1, 'Asegurado' => 15, 'Miembro familiar' => 9 }));
	}

	@isTest
	static void enviaCorreoDePolizaConIA() {
		InsurancePolicy p = poliza();
		CorreoOportunidadIA.respuestaPrueba = '{"asunto": "Su póliza ya está lista", "cuerpo_html": "<p>Hola Ana</p>"}';
		EnvioCorreoPlantilla.Solicitud s = solicitud();
		s.registroId = p.Id;
		s.promptIA = 'Correo_Poliza_Cliente';
		Test.startTest();
		EnvioCorreoPlantilla.Resultado r = EnvioCorreoPlantilla.enviar(new List<EnvioCorreoPlantilla.Solicitud>{ s })[0];
		Test.stopTest();
		if (r.enviado) {
			System.assert(r.mensaje.contains('redactado con IA'), r.mensaje);
		}
	}

	@isTest
	static void sinIAUsaLaPlantilla() {
		CorreoOportunidadIA.respuestaPrueba = null;
		Test.startTest();
		EnvioCorreoPlantilla.Resultado r = EnvioCorreoPlantilla.enviar(new List<EnvioCorreoPlantilla.Solicitud>{ solicitud() })[0];
		Test.stopTest();
		if (r.enviado) {
			System.assert(r.mensaje.contains('con la plantilla'), r.mensaje);
		}
	}
}
