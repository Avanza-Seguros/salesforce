/**
 * @description       : 
 * @author            : MRHE
 * @group             : 
 * @last modified on  : 05-22-2023
 * @last modified by  : MRHE
**/
@isTest
public with sharing class ETC_wsUSDTest {
    @isTest
    private static void calloutgetUSDTest() {
        // Test data setup
    
        // Actual test
        Test.startTest();
        ETC_wsUSD.getUSD();
        Test.stopTest();
    
        // Asserts
    }
}