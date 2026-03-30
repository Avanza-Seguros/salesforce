/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 05-05-2023
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public with sharing class ETC_UtilityMetadata {
    public static EmailMetadata__mdt getCustomMetadataRecord(String myName) {
        return [SELECT Id, DeveloperName,Body__c, Subject__c, EmailOrg__c , DisplayName__c,Plantilla_Email__c FROM EmailMetadata__mdt WHERE DeveloperName = :myName LIMIT 1];
     }

    public static Endpoint__mdt getCustomMetadataEndpoint(String myName) {
        return [SELECT Id, DeveloperName,Endpoint__c, Relative_endpoint__c, Request__c, Response__c, Token__c,Method__c FROM Endpoint__mdt WHERE DeveloperName = :myName LIMIT 1];
    }
}