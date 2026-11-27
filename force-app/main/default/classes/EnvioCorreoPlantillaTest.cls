/**
 *   @name: EnvioCorreoPlantillaTest
 *   @version: 1.0
 *   @creation date: 12/11/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Pruebas de EnvioCorreoPlantilla.
 */
@isTest
private class EnvioCorreoPlantillaTest {

	private static final String PLANTILLA = 'Prueba_EnvioCorreoPlantilla_Test';

	@testSetup
	static void datos() {
		System.runAs(new User(Id = UserInfo.getUserId())) {
			insert new EmailTemplate(Name = 'Prueba envío', DeveloperName = PLANTILLA, TemplateType = 'text',
				FolderId = UserInfo.getUserId(), Subject = 'Póliza {!Contact.FirstName}', Body = 'Hola {!Contact.FirstName}',
				IsActive = true);
		}
		Contact c = new Contact(FirstName = 'Ana', LastName = 'López', Email = 'ana.lopez@ejemplo.com');
		insert c;
		insert new ContentVersion(Title = 'poliza', PathOnClient = 'poliza.pdf', VersionData = Blob.valueOf('pdf'),
			FirstPublishLocationId = c.Id);
	}

	private static EnvioCorreoPlantilla.Solicitud solicitud(Contact c, String correo) {
		EnvioCorreoPlantilla.Solicitud s = new EnvioCorreoPlantilla.Solicitud();
		s.plantilla = PLANTILLA;
		s.destinatarioId = c.Id;
		s.registroId = c.Id;
		s.correo = correo;
		s.adjuntarArchivos = true;
		s.remitente = 'info@avanzaseguro.com';
		return s;
	}

	@isTest
	static void enviaUnaVezPorDireccion() {
		Contact c = [SELECT Id FROM Contact LIMIT 1];
		Test.startTest();
		List<EnvioCorreoPlantilla.Resultado> rs = EnvioCorreoPlantilla.enviar(new List<EnvioCorreoPlantilla.Solicitud>{
			solicitud(c, 'ana.lopez@ejemplo.com'), solicitud(c, 'ANA.LOPEZ@ejemplo.com')
		});
		Integer correos = Limits.getEmailInvocations();
		Test.stopTest();
		System.assertEquals(2, rs.size());
		// Si la org permite enviar, la segunda solicitud (misma dirección) no vuelve a enviar.
		if (rs[0].enviado) {
			System.assertEquals(1, correos, 'Debe enviarse un solo correo');
			System.assert(rs[1].mensaje.startsWith('Ya se había enviado'), rs[1].mensaje);
		}
	}

	@isTest
	static void usaElCorreoDelContactoYAdjuntaArchivos() {
		Contact c = [SELECT Id FROM Contact LIMIT 1];
		System.assertEquals('ana.lopez@ejemplo.com', EnvioCorreoPlantilla.correoDestino(solicitud(c, null)));
		List<Id> versiones = new List<Id>();
		System.assertEquals(0, EnvioCorreoPlantilla.archivosDe(c.Id, versiones));
		System.assertEquals(1, versiones.size());
		EnvioCorreoPlantilla.enviar(new List<EnvioCorreoPlantilla.Solicitud>{ solicitud(c, null) });
	}

	@isTest
	static void sinCorreoNoEnvia() {
		Contact c = new Contact(LastName = 'Sin correo');
		insert c;
		EnvioCorreoPlantilla.Solicitud s = solicitud(c, null);
		List<EnvioCorreoPlantilla.Resultado> rs = EnvioCorreoPlantilla.enviar(new List<EnvioCorreoPlantilla.Solicitud>{ s });
		System.assertEquals(false, rs[0].enviado);
		System.assertEquals('El destinatario no tiene correo.', rs[0].mensaje);

		EnvioCorreoPlantilla.Solicitud otra = solicitud(c, 'x@ejemplo.com');
		otra.plantilla = 'No_Existe_Plantilla_XYZ';
		rs = EnvioCorreoPlantilla.enviar(new List<EnvioCorreoPlantilla.Solicitud>{ otra });
		System.assertEquals(false, rs[0].enviado);
	}

	@isTest
	static void elBannerLlevaElRamoDelRegistro() {
		Account cuenta = DatosPruebaPolizas.createInsuredAccount();
		Opportunity autos = new Opportunity(Name = 'Ramo correo', AccountId = cuenta.Id, StageName = 'Gestion Comercial',
			CloseDate = Date.today().addDays(10), Agente_Relacionado__c = DatosPruebaPolizas.getOrCreateAgenteId(),
			Ramo__c = 'Automoviles');
		insert autos;
		String ramo = EnvioCorreoPlantilla.ramoDe(autos.Id);
		System.assertEquals('automóviles', ramo, 'El ramo de la oportunidad como se lee en el correo');
		String html = '<img alt="¡Bienvenido! A tu seguro de gastos médicos mayores">';
		System.assertEquals('<img alt="¡Bienvenido! A tu seguro de automóviles">', EnvioCorreoPlantilla.conRamo(html, ramo));
		System.assertEquals('<img alt="¡Bienvenido! A tu seguro">', EnvioCorreoPlantilla.conRamo(html, null), 'Sin ramo no se inventa uno');
		Contact c = [SELECT Id FROM Contact LIMIT 1];
		System.assertEquals(null, EnvioCorreoPlantilla.ramoDe(c.Id), 'Un registro sin ramo');
		System.assertEquals(null, EnvioCorreoPlantilla.ramoDe(null));
	}

	@isTest
	static void ponElTextoDeLaIAEnElDisenoDeLaPlantilla() {
		String plantilla = '<html><img src="banner.png"><div style="text-align: center;"><span>Apreciable %%Nombre del cliente%%</span></div>'
			+ '<div style="text-align: justify;"><span>Texto fijo de la plantilla.</span></div>'
			+ '<div style="text-align: center;"><span>Agradecemos tu confianza.</span></div><img src="pie.png"></html>';
		String html = EnvioCorreoPlantilla.enDisenoDePlantilla(plantilla, '<p>Hola, Ana:</p><table><tr><td>HDI</td></tr></table>');
		System.assert(html.contains('<p>Hola, Ana:</p><table><tr><td>HDI</td></tr></table>'), 'Lleva el texto de la IA');
		System.assert(!html.contains('Texto fijo de la plantilla'), 'Sin el texto fijo de la plantilla');
		System.assert(!html.contains('Apreciable'), 'Sin el saludo de la plantilla: la IA ya saluda');
		System.assert(html.contains('banner.png') && html.contains('pie.png') && html.contains('Agradecemos tu confianza.'),
			'Conserva el banner, el cierre y el pie de la plantilla');
		System.assertEquals(null, EnvioCorreoPlantilla.enDisenoDePlantilla('<p>Sin bloque</p>', '<p>Hola</p>'),
			'Sin el bloque de texto de la plantilla se usa el marco sencillo');
		System.assertEquals(null, EnvioCorreoPlantilla.enDisenoDePlantilla(null, '<p>Hola</p>'), 'Sin plantilla HTML');
	}
}
