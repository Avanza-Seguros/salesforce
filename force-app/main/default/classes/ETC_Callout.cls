/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 05-23-2023
 * @last modified by  : MRHE
**/
public virtual with sharing class ETC_Callout{

    public Endpoint__mdt mdt;
    public String claseApex;

    public class Callout{
        public Http http;
        public HttpRequest request;
        public HttpResponse response;
        public Callout(Http http, HttpRequest request, HttpResponse response){
            this.http = http;
            this.request = request;
            this.response = response;
        }
    }
    public ETC_Callout(){

    }
    public ETC_Callout(String metadataName){
        this.mdt = ETC_UtilityMetadata.getCustomMetadataEndpoint(metadataName);
    }

    public virtual Callout createCallout(String metadataName){
        Endpoint__mdt mdt = ETC_UtilityMetadata.getCustomMetadataEndpoint(metadataName);

        this.mdt = mdt;

        Http http = new Http();
        HttpRequest request = new HttpRequest();
        HttpResponse response = new HttpResponse();
        request.setEndpoint(mdt.Endpoint__c + mdt.Relative_Endpoint__c);
        request.setMethod(mdt.Method__c);
        request.setHeader('Accept-Encoding', 'gzip, deflate, br');
        request.setHeader('Accept', '*/*');
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('User-Agent', 'Apache-HttpClient/4.5.5 (Java/16.0.1)');
        request.setHeader('Connection', 'Keep-Alive');
        if(mdt.Token__c!=null) {request.setHeader('Bmx-Token', mdt.Token__c);}
        
        // request.setBody(mdt.Request__c);

        request.setCompressed(false);
        request.setTimeout(120000);
        return new Callout(http, request, response);
    }

    public virtual HttpResponse sendCallout(Callout callout) {
        callout.response = new HttpResponse();
        if(!Test.isRunningTest()){callout.response = callout.http.send(callout.request);}
        return callout.response;
    }

    
    public static Date getDate(String stringDate) {
        if(stringDate.equals('00/00/0000')){return null;}
        return (Date) JSON.deserialize('"' + stringDate + '"', Date.class);
    }
    public static Date getDateString(String stringDate) {
        if(stringDate.equals('00/00/0000')){return null;}
        String[] fecha = stringDate.split('/');
        return Date.newInstance(Integer.valueOf(fecha[2]), Integer.valueOf(fecha[1]), Integer.valueOf(fecha[0]));
    }
    public static Time getHour(String stringHour) {
        if(stringHour.equals('00:00') || String.isBlank(stringHour)){return null;}
        System.debug(stringHour);
        String[] strTimeSplit = stringHour.split(':');
        if(strTimeSplit.size()<=1){
            Long milliseconds = Long.valueOf(stringHour);
            Long seg = milliseconds / 1000;
            Time hora = Time.newInstance(0, 0, Integer.valueOf(seg), 0);
            System.debug('hora: '+hora);
            return hora;
        }
        return Time.newInstance( Integer.valueOf(strTimeSplit[0]),Integer.valueOf(strTimeSplit[1]),Integer.valueOf(strTimeSplit[2]),0);
    }

    public static DateTime getDateTime(Date dateConversion){
        return DateTime.newInstance(dateConversion.year(), dateConversion.month(), dateConversion.day());
    }

    public static String getString(String stringValidate){
        if(stringValidate == null){return '';}
        return stringValidate;
    }

    public static String getStringRemoveZero(String stringValidate){
        if(stringValidate == null){return '';}
        return stringValidate.replaceAll('^0+', '');
    }




    // public static SObjectType getSObjectTypeByString(String objectAPIName){
    //     return ((SObject) Type.forName(objectAPIName).newInstance()).getSObjectType();
    // }

    public static Schema.DescribeSObjectResult getSObjectTypeByString(String objectAPIName){
        return  Schema.getGlobalDescribe().get(objectAPIName).getDescribe();
    }

    public static Id getRecordTypeId (String objectAPIName, String recordTypeName){
        return getSObjectTypeByString(objectAPIName).getRecordTypeInfosByName().get(recordTypeName).getRecordTypeId();
    }

    // public String getAuthorizationHeader(){
    //     Blob headerValue = Blob.valueOf('{!HTMLENCODE($Credential.Username)}' + ':' + '{!HTMLENCODE($Credential.Password)}');
    //     return 'BASIC ' + EncodingUtil.base64Encode(headerValue);
    // }
}