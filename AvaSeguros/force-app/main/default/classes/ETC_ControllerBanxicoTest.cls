/**
 * @description       : 
 * @author            : MRHE
 * @group             : 
 * @last modified on  : 05-23-2023
 * @last modified by  : MRHE
**/
@isTest
public with sharing class ETC_ControllerBanxicoTest {
    @isTest
    private static void controllerTest() {
        // Test data setup
    
        // Actual test
        Test.startTest();
        ETC_ControllerBanxico.getUDI();
        ETC_ControllerBanxico.getUSD();
        Test.stopTest();
    
        // Asserts
    }
}