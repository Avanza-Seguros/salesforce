/**
 *   @name: Luxoft
 *   @version: 1.0
 *   @creation date: 02/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Envía el correo de altas de Luxoft con archivos adjuntos a partir de un registro Items_Cases__c, usando la plantilla "Luxoft_Altas" y adjuntando los archivos relacionados con el registro.
 */
public without sharing class Luxoft {

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Construye y envía el correo de alta de Luxoft usando la plantilla "Luxoft_Altas", consultando el correo del item y adjuntando los archivos relacionados con el registro.
	 * @param objitem: Registro Items_Cases__c con los datos del item y destinatario.
	 * @return void
	 */
	public static void sendEmail(Items_Cases__c objitem){
		Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
		Id senderEmailId = null;
		senderEmailId = [SELECT Id FROM OrgWideEmailAddress WHERE Address = 'info@avanzaseguro.com' LIMIT 1].Id;
		EmailTemplate et = [SELECT Id,Subject, Body FROM EmailTemplate WHERE DeveloperName = 'Luxoft_Altas'][0];
		Items_Cases__c queriedItem = [SELECT Id, Contacto__c, Correo_electronico__c FROM Items_Cases__c WHERE Id = :objitem.Id LIMIT 1];
		if (queriedItem.Correo_electronico__c != null) {
			message.toAddresses = new String[] {queriedItem.Correo_electronico__c};
		} else {
			// Manejar el caso donde el campo de correo electrónico es nulo
			// Puedes imprimir un mensaje, lanzar una excepción, etc.
		}
		message.setTemplateId(et.Id);
		message.setOrgWideEmailAddressId(senderEmailId);
		message.setWhatId(objitem.id);
		message.setSaveAsActivity(false);
		message.setTargetObjectId(objitem.Contacto__c);
		//message.toAddresses = new String[] {objitem.Correo_electronico__c};
		//message.toAddresses = new String[] {'crystian.r1010@gmail.com', 'misael.velarde@avanzaseguro.com'};
		//message.setSubject(et.Subject);
		message.setUseSignature(true);
		message.setFileAttachments(getAttachmentForEmail(getRelatedFilesByRecordId(objitem.Id)));
		message.setHtmlBody(et.Body);
		Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
		Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
		if (results[0].success) {
			System.debug('The email was sent succesfully.');
		} else {
			System.debug('The email failed to send: ' + results[0].errors[0].message);
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Obtiene los archivos (ContentVersion) relacionados con un registro, indexados por Id de versión.
	 * @param recordId: Id del registro cuyos archivos relacionados se consultan.
	 * @return Mapa de Id de ContentVersion a su registro ContentVersion.
	 */
	public static Map<ID, ContentVersion> getRelatedFilesByRecordId(String recordId) {
		// Get record file IDs
		List<ContentDocumentLink> files = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :recordId order by ContentDocument.CreatedDate asc];
		List<ID> fileIDs = new List<ID>();
		for (ContentDocumentLink docLink : files) {
			fileIDs.add(docLink.ContentDocumentId);
		}

		List<ContentVersion> docs = [SELECT Id, ContentDocumentId, FileExtension, Title, VersionData, PathOnClient
			FROM ContentVersion WHERE ContentDocumentId IN : fileIDs order by ContentDocument.CreatedDate asc];

		Map<ID, ContentVersion> mapIdTitle = new Map<ID, ContentVersion>();
		for (ContentVersion ctnVersion : docs) {
			mapIdTitle.put(ctnVersion.Id, ctnVersion);
		}

		return mapIdTitle;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Transforma un mapa de ContentVersion en una lista de adjuntos de correo (EmailFileAttachment), asignando nombre, cuerpo y tipo MIME.
	 * @param mapFile: Mapa de Id de ContentVersion a su registro ContentVersion.
	 * @return Lista de adjuntos listos para agregar al correo.
	 */
	public static List<Messaging.EmailFileAttachment> getAttachmentForEmail(Map<ID, ContentVersion> mapFile){
		List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();
		for (Id key : mapFile.keySet()) {
			Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
			efa.setFileName(mapFile.get(key).PathOnClient);
			efa.setBody(mapFile.get(key).VersionData);
			efa.setContentType(fileMimeTypes.get(mapFile.get(key).FileExtension));
			attachments.add(efa);
		}
		return attachments;
	}

	private static Map<String, String> fileMimeTypes = new Map<String, String>{
		'abw' => 'application/x-abiword',
		'arc' => 'application/x-freearc',
		'bin' => 'application/octet-stream',
		'bmp' => 'image/bmp',
		'bz' => 'application/x-bzip',
		'bz2' => 'application/x-bzip2',
		'csh' => 'application/x-csh',
		'css' => 'text/css',
		'csv' => 'text/csv',
		'doc' => 'application/msword',
		'docx' => 'application/msword',
		'eot' => 'application/vnd.ms-fontobject',
		'epub' => 'application/epub+zip',
		'gz' => 'application/gzip',
		'gif' => 'image/gif',
		'htm' => 'text/html',
		'html' => 'text/html',
		'ico' => 'image/vnd.microsoft.icon',
		'ics' => 'text/calendar',
		'jpeg' => 'image/jpeg',
		'jpg' => 'image/jpeg',
		'js' => 'text/javascript',
		'json' => 'application/json',
		'jsonld' => 'application/ld+json',
		'mjs' => 'text/javascript',
		'png' => 'image/png',
		'pdf' => 'application/pdf',
		'php' => 'application/php',
		'ppt' => 'application/vnd.ms-powerpoint',
		'pptx' => 'application/vnd.ms-powerpoint',
		'rar' => 'application/vnd.rar',
		'rtf' => 'application/rtf',
		'sh' => 'application/x-sh',
		'svg' => 'image/svg+xml',
		'swf' => 'application/x-shockwave-flash',
		'tar' => 'application/x-tar',
		'tif' => 'image/tiff',
		'tiff' => 'image/tiff',
		'ts' => 'video/mp2t',
		'txt' => 'text/plain',
		'vsd' => 'application/vnd.visio',
		'wav' => 'audio/wav',
		'webp' => 'image/webp',
		'xhtml' => 'application/xhtml+xml',
		'xls' => 'application/vnd.ms-excel',
		'xlsx' => 'application/vnd.ms-excel',
		'xml' => 'application/xml',
		'xul' => 'application/vnd.mozilla.xul+xml',
		'zip' => 'application/zip',
		'7z' => 'application/x-7z-compressed'
	};
}
