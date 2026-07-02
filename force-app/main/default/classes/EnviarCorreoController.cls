/**
 *   @name: EnviarCorreoController
 *   @version: 1.0
 *   @creation date: 02/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Controlador de página Visualforce (StandardController de Items_Cases__c) que envía un correo de texto plano al correo del registro, adjuntando los Attachment relacionados con dicho registro.
 */
public class EnviarCorreoController {
	private final Items_Cases__c objeto;

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Constructor que recibe el StandardController de la página y obtiene el registro Items_Cases__c asociado.
	 * @param controller: StandardController de la página Visualforce.
	 * @return void
	 */
	public EnviarCorreoController(ApexPages.StandardController controller) {
		this.objeto = (Items_Cases__c)controller.getRecord();
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Construye y envía un correo de texto plano al correo del registro, adjuntando los Attachment relacionados con el mismo.
	 * @return PageReference null (permanece en la misma página).
	 */
	public PageReference enviarCorreo() {
		Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
		email.setSubject('Asunto del correo');
		email.setPlainTextBody('Cuerpo del correo');
		email.setToAddresses(new List<String>{objeto.Correo_electronico__c});

		// Adjuntar archivos relacionados
		List<Attachment> adjuntos = [SELECT Id, Name, Body FROM Attachment WHERE ParentId = :objeto.Id];
		if (!adjuntos.isEmpty()) {
			Messaging.EmailFileAttachment[] fileAttachments = new Messaging.EmailFileAttachment[]{};
			for (Attachment adjunto : adjuntos) {
				Messaging.EmailFileAttachment fileAttachment = new Messaging.EmailFileAttachment();
				fileAttachment.setFileName(adjunto.Name);
				fileAttachment.setBody(adjunto.Body);
				fileAttachments.add(fileAttachment);
			}
			email.setFileAttachments(fileAttachments);
		}

		Messaging.sendEmail(new Messaging.SingleEmailMessage[]{email});

		return null;
	}
}
