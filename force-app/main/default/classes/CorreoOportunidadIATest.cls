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
