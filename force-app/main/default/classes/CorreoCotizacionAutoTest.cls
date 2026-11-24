/**
 *   @name: CorreoCotizacionAutoTest
 *   @version: 1.0
 *   @creation date: 24/11/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Pruebas de CorreoCotizacionAuto: el correo de cotización de Auto (comparativo y una opción) y su envío.
 */
@isTest
private class CorreoCotizacionAutoTest {

	@testSetup
	static void datos() {
		Account a = new Account(Name = 'Cliente Auto Correo');
		insert a;
		Contact c = new Contact(FirstName = 'TANIA', LastName = 'Prueba', Email = 'tania@ejemplo.test', AccountId = a.Id);
		insert c;
		String etapa = 'Prospecting';
		for (OpportunityStage s : [
			SELECT MasterLabel FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1
		]) { etapa = s.MasterLabel; }
		Opportunity o = new Opportunity(Name = 'Opp Correo Auto', AccountId = a.Id, StageName = etapa, CloseDate = Date.today().addDays(30),
			Ramo__c = 'Automoviles', Tipo_Contratacion__c = 'Individual', Contacto__c = c.Id,
			Description = 'Nota\n\nDetalle del ramo (Automoviles):\n• descripcion_completa__c: SWIFT GLX BOOSTERGREEN, L4, 1.2L\n• Modelo__c: 2023\n• Marca__c: Suzuki\n• Anio__c: 2023');
		insert o;
		Aseguradora__c hdi = new Aseguradora__c(Name = 'HDI Seguros');
		Aseguradora__c chubb = new Aseguradora__c(Name = 'Chubb México');
		chubb.Logo_URL__c = 'https://ejemplo.test/chubb.png';
		insert new List<Aseguradora__c>{ hdi, chubb };
		insert new List<Quote>{
			new Quote(Name = 'Chubb - AMPLIA', OpportunityId = o.Id, Aseguradora__c = chubb.Id, Prima_Total__c = 16680.02, SumaAsegurada__c = 211000,
				Frecuencia_de_prima__c = 'Anual', Ramos__c = 'Automoviles'),
			new Quote(Name = 'HDI - HDI EN MI AUTO', OpportunityId = o.Id, Aseguradora__c = hdi.Id, PrimaAnual__c = 14069.33, Prima_Total__c = 14069.33, SumaAsegurada__c = 177400,
				DeducibleDanos_Pct__c = 5, Plan__c = 'HDI EN MI AUTO AMPLIA', Frecuencia_de_prima__c = 'Anual', Ramos__c = 'Automoviles')
		};
		insert new Document(Name = 'Correo', DeveloperName = 'Correo_Icono_Correo', FolderId = UserInfo.getUserId(), Body = Blob.valueOf('x'),
			IsPublic = true, Type = 'png');
	}

	static Id oportunidad() { return [SELECT Id FROM Opportunity WHERE Name = 'Opp Correo Auto' LIMIT 1].Id; }

	@isTest
	static void comparativo() {
		Test.startTest();
		CorreoOportunidadIA.Correo c = CorreoCotizacionAuto.armar(oportunidad());
		Test.stopTest();
		Assert.areEqual('Tania, tu cotización de seguro para el Suzuki Swift GLX Boostergreen 2023 está lista', c.asunto);
		for (String t : new List<String>{ 'Hola, Tania: tu cotización está lista', 'HDI en mi auto amplia', '$14,069.33', '$38.55 al día',
			'Suma asegurada: $177,400.00', '>Recomendada<', 'https://ejemplo.test/chubb.png', 'Nuestra recomendación: HDI Seguros.',
			'mantiene cobertura amplia con deducible de daños del 5%', 'https://wa.me/52', 'Qué te cubre un plan amplio',
			'subject=RE%3A%20Tania%2C%20tu%20cotizaci%C3%B3n', 'servlet.ImageServer' }) {
			Assert.isTrue(c.html.contains(t), t);
		}
		Assert.isTrue(c.html.indexOf('HDI Seguros</strong>') < c.html.indexOf('Chubb México</strong>'), 'Primero la recomendada');
		Assert.isFalse(c.html.contains('{{'), 'Sin marcadores: ' + c.html.substringAfter('{{').left(30));
		Assert.isFalse(c.html.contains('Ricardo'), 'Sin el testimonio de ejemplo');
	}

	@isTest
	static void unaOpcionYSinVehiculo() {
		Id oppId = oportunidad();
		delete [SELECT Id FROM Quote WHERE OpportunityId = :oppId AND Name LIKE 'HDI%'];
		update new Opportunity(Id = oppId, Description = null);
		update new Quote(Id = [SELECT Id FROM Quote WHERE OpportunityId = :oppId LIMIT 1].Id, Plan__c = 'Limitada', SumaAsegurada__c = null);
		Test.startTest();
		CorreoOportunidadIA.Correo c = CorreoCotizacionAuto.armar(oppId);
		Test.stopTest();
		Assert.areEqual('Tania, tu cotización de seguro de auto está lista', c.asunto);
		for (String t : new List<String>{ 'Resumen de tu cotización', '$16,680.02 MXN', 'Equivale a $45.70 al día', 'Ver PDF adjunto', 'Limitada',
			'Quiero%20contratar%20mi%20seguro%20de%20auto%20con%20Chubb%20M%C3%A9xico' }) {
			Assert.isTrue(c.html.contains(t), t);
		}
		Assert.isFalse(c.html.contains('{{') || c.html.contains('Qué te cubre un plan amplio'), 'Sin el recuadro del plan amplio');
	}

	@isTest
	static void soloAutoIndividual() {
		Id oppId = oportunidad();
		Assert.areEqual(null, CorreoCotizacionAuto.armar(null));
		Assert.areEqual(null, CorreoCotizacionAuto.armar([SELECT Id FROM Contact LIMIT 1].Id));
		update new Opportunity(Id = oppId, Tipo_Contratacion__c = 'Colectiva');
		Assert.areEqual(null, CorreoCotizacionAuto.armar(oppId), 'Flotilla: el correo de siempre');
		update new Opportunity(Id = oppId, Tipo_Contratacion__c = 'Individual');
		delete [SELECT Id FROM Quote WHERE OpportunityId = :oppId];
		Assert.areEqual(null, CorreoCotizacionAuto.armar(oppId), 'Sin cotizaciones');
	}

	@isTest
	static void seEnviaYDejaSeguimiento() {
		Id oppId = oportunidad();
		EnvioCorreoPlantilla.Solicitud s = new EnvioCorreoPlantilla.Solicitud();
		s.plantilla = 'X120_OPORTUNIDAD_CLIENTE';
		s.correo = 'tania@ejemplo.test';
		s.registroId = oppId;
		s.promptIA = 'Correo_Cotizacion_Cliente';
		Test.startTest();
		List<EnvioCorreoPlantilla.Resultado> rs = EnvioCorreoPlantilla.enviar(new List<EnvioCorreoPlantilla.Solicitud>{ s });
		CorreoCotizacionAuto.seguimiento(oppId);
		CorreoCotizacionAuto.seguimiento(oppId);
		Test.stopTest();
		Assert.isFalse(rs[0].mensaje.contains('IA'), rs[0].mensaje);
		Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE WhatId = :oppId], 'Una sola tarea abierta');
	}

	@isTest
	static void reglas() {
		Assert.areEqual('523312345678', CorreoCotizacionAuto.whatsapp('+52 1 33 1234-5678'));
		Assert.areEqual('523312345678', CorreoCotizacionAuto.whatsapp('(33) 1234 5678'));
		Assert.areEqual('523312345678', CorreoCotizacionAuto.whatsapp('52-3312345678'));
		Assert.areEqual(null, CorreoCotizacionAuto.whatsapp('1234'));
		Assert.areEqual(null, CorreoCotizacionAuto.whatsapp(null));
		String sitio = 'https://' + DomainCreator.getExperienceCloudSitesHostname() + '/resource/';
		for (String l : new List<String>{ '/resource/1795534385000/afirmeLogo', 'resource/1795534385000/afirmeLogo',
			'https://x--uat.sandbox.lightning.force.com/resource/1795534385000/afirmeLogo',
			' https://x.my.salesforce.com/resource/1795534385000/afirmeLogo ' }) {
			Assert.areEqual(sitio + '1795534385000/afirmeLogo', CorreoCotizacionAuto.ligaPublica(l), l);
		}
		Assert.areEqual('https://ejemplo.test/a.png', CorreoCotizacionAuto.ligaPublica('ejemplo.test/a.png'));
		Assert.areEqual('https://x.my.site.com/resource/a', CorreoCotizacionAuto.ligaPublica('https://x.my.site.com/resource/a'));
		Assert.areEqual(Url.getOrgDomainUrl().toExternalForm() + '/servlet/servlet.ImageServer?id=1', CorreoCotizacionAuto.ligaPublica('/servlet/servlet.ImageServer?id=1'));
		Assert.areEqual(null, CorreoCotizacionAuto.ligaPublica('/sfc/servlet.shepherd/version/download/068'), 'Archivo interno: siglas');
		Assert.areEqual(null, CorreoCotizacionAuto.ligaPublica(' '));
		Assert.areEqual('HDI', CorreoCotizacionAuto.siglas('HDI Seguros'));
		Assert.areEqual('CH', CorreoCotizacionAuto.siglas('Chubb México'));
		Assert.areEqual(Date.newInstance(2026, 11, 27), CorreoCotizacionAuto.diasHabiles(Date.newInstance(2026, 11, 24), 3));
		Assert.areEqual(Date.newInstance(2026, 12, 1), CorreoCotizacionAuto.diasHabiles(Date.newInstance(2026, 11, 26), 3));
		Assert.areEqual('HDI en mi auto', CorreoCotizacionAuto.planDe(new Quote(Name = 'x', Plan__c = 'HDI EN MI AUTO')));
		Assert.areEqual('Amplia Plus', CorreoCotizacionAuto.planDe(new Quote(Name = 'HDI - Amplia Plus')));
		Map<String, String> vehiculos = new Map<String, String>{
			'EX30 ULTRA VOLVO EX30 ULTRA 5P ELECTRICO, 5 ocupantes|Volvo|2024' => 'Volvo EX30 Ultra 2024',
			'SPARK LTZ CHEVROLET SPARK LTZ 5 PUERTAS|Chevrolet|2016' => 'Chevrolet Spark LTZ 2016',
			'FORD TERRITORY TITANIUM 1.5 TURBO AUT|Ford|2024' => 'Ford Territory Titanium 2024' };
		for (String v : vehiculos.keySet()) {
			List<String> p = v.split('\\|');
			Assert.areEqual(vehiculos.get(v), CorreoCotizacionAuto.vehiculoDe(new Opportunity(Description = 'Detalle del ramo (Automoviles):\n• descripcion_completa__c: '
				+ p[0] + '\n• Modelo__c: ' + p[2] + '\n• Marca__c: ' + p[1])));
		}
		Assert.areEqual(null, CorreoCotizacionAuto.vehiculoDe(new Opportunity()));
		Assert.areEqual('Ingrid', CorreoCotizacionAuto.nombreCliente(new Opportunity(Name = 'x', Account = new Account(Name = 'Familia INGRID ROSALES'))));
		Assert.areEqual('Transportes SA de CV', CorreoCotizacionAuto.nombreCliente(new Opportunity(Name = 'x', Account = new Account(Name = 'Transportes SA de CV'))));
		Assert.areEqual('<a href="mailto:x?cc=a@b.c&s=J%C3%A9%20R">Jé R</a>', CorreoCotizacionAuto.llenar('<a href="mailto:x?cc={{CORREO_AGENTE}}&s={{AGENTE}}">{{AGENTE}}</a>',
			new Map<String, String>{ 'AGENTE' => 'Jé R', 'CORREO_AGENTE' => 'a@b.c' }, new Map<String, String>()));
	}
}
