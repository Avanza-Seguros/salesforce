/**
 * author: Cristian R. Venegas
 * email: crystian.r1010@gmail.com  
 * date: 06/08/2023
* description: This trigger is handleding the generation of url's for quick download stored at custom object created for that.
 **/

trigger ContentDocumentLinkTrigger on ContentDocumentLink (after insert) {

//When is after insert   
if(trigger.isInsert && trigger.isAfter){
    List<url_files_download__c> lstObjFiles = new List<url_files_download__c>();
    String baseUrl = ''+System.URL.getSalesforceBaseUrl().toExternalForm();
    for(ContentDocumentLink obj : Trigger.new){
        //Filtering to apply this only for 'Control_de_Folios__c' records
        if((''+obj.LinkedEntityId).startsWith('a03')){
            lstObjFiles.add(
            	new url_files_download__c(
                	Control_de_Folios__c = obj.LinkedEntityId,
                    url_file__c = baseUrl+'/sfc/servlet.shepherd/document/download/'+obj.ContentDocumentId
                )
            );
        }
    }
    Insert lstObjFiles;
  }
}