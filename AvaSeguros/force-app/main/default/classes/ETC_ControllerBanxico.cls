/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 05-08-2023
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public with sharing class ETC_ControllerBanxico {
    
    @AuraEnabled
    public static Decimal getUSD(){
        return ETC_wsUSD.getUSD();
    }

    @AuraEnabled
    public static Decimal getUDI(){
        return ETC_wsUDI.getUDI();
    }
}