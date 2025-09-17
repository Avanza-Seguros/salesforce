/**
 * @description       : 
 * @author            : MRHE
 * @group             : 
 * @last modified on  : 05-23-2023
 * @last modified by  : MRHE
**/
@isTest
public with sharing class ETC_CalloutTest {
    @isTest
    private static void testTestCase() {
        // Test data setup
    
        // Actual test
        Test.startTest();
        ETC_Callout callout = new ETC_Callout(ETC_wsUDI.ENDPOINTNAME);
        ETC_wsUDI.getUDI();
        ETC_Callout.getString('');
        ETC_Callout.getStringRemoveZero('0000111');
        ETC_Callout.getDate('11-12-23');
        ETC_Callout.getDateString('11/12/2023');
        ETC_Callout.getHour('11:12:12');
        ETC_Callout.getDateTime(System.today());
        ETC_Callout.getSObjectTypeByString('Account');

        ETC_UtilityMetadata.getCustomMetadataRecord('Default');
        Test.stopTest();
    
        // Asserts
    }
}