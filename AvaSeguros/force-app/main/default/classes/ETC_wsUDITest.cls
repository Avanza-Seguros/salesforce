/**
 * @description       : 
 * @author            : MRHE
 * @group             : 
 * @last modified on  : 05-22-2023
 * @last modified by  : MRHE
**/
@isTest
public with sharing class ETC_wsUDITest {
    @isTest
    private static void calloutgetUDITest() {
        // Test data setup
    
        // Actual test
        Test.startTest();
        ETC_wsUDI.getUDI();
        Test.stopTest();
    
        // Asserts
    }
}