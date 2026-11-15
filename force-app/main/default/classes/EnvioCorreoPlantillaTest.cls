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
}
