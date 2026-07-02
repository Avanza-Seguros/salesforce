/**
 *   @name: GetFilesSelected
 *   @version: 1.0
 *   @creation date: 02/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Controlador para componentes que gestiona los archivos (ContentVersion) relacionados con un registro, distinguiendo entre archivos marcados como Carta de Autorización y los normales, y permitiendo marcar un archivo como carta de autorización.
 */
public without sharing class GetFilesSelected {

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve los archivos (ContentVersion) relacionados con un registro que estén marcados como Carta de Autorización.
	 * @param IdRecord: Id del registro cuyos archivos relacionados se consultan.
	 * @return Lista de ContentVersion marcados como Carta de Autorización.
	 */
	@AuraEnabled(cacheable=true)
	public static List<ContentVersion> getFiles(String IdRecord){
		set<Id> ids = new set<Id>();
		for(ContentDocumentLink obj : [SELECT Id, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId =: IdRecord]){
			ids.add(obj.ContentDocumentId);
		}
		return [SELECT Id, ContentDocumentId, FileExtension, Title, ContentModifiedBy.Name, ContentModifiedDate  FROM ContentVersion WHERE ContentDocumentId IN : ids AND Carta_Autorizacion__c = true];
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve los archivos (ContentVersion) relacionados con un registro que NO estén marcados como Carta de Autorización (archivos normales).
	 * @param IdRecord: Id del registro cuyos archivos relacionados se consultan.
	 * @return Lista de ContentVersion no marcados como Carta de Autorización.
	 */
	@AuraEnabled(cacheable=true)
	public static List<ContentVersion> getNormalFiles(String IdRecord){
		set<Id> ids = new set<Id>();
		for(ContentDocumentLink obj : [SELECT Id, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId =: IdRecord]){
			ids.add(obj.ContentDocumentId);
		}
		return [SELECT Id, ContentDocumentId, FileExtension, Title, ContentModifiedBy.Name, ContentModifiedDate  FROM ContentVersion WHERE ContentDocumentId IN : ids AND Carta_Autorizacion__c = false];

	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Marca como Carta de Autorización la versión de contenido asociada al ContentDocument indicado.
	 * @param IdRecord: Id del ContentDocument cuyo ContentVersion se marcará como Carta de Autorización.
	 * @return void
	 */
	@AuraEnabled
	public static void UpdateFile(String IdRecord){

		List<ContentVersion> lstFiles = [SELECT Id, ContentDocumentId, FileExtension, Title FROM ContentVersion WHERE ContentDocumentId =: IdRecord];
		ContentVersion cv = new ContentVersion(Id = lstFiles[0].Id, Carta_Autorizacion__c = true);
		Update cv;
	}
}
