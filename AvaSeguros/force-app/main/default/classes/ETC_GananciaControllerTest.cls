/**
 * @description       : 
 * @author            : MRHE
 * @group             : 
 * @last modified on  : 05-23-2023
 * @last modified by  : MRHE
**/
@isTest
public with sharing class ETC_GananciaControllerTest {
    @isTest
    private static void testTestCase() {
        // Test data setup
    
        // Actual test
        Test.startTest();
        ETC_GananciaController.getGananciaActual();
        ETC_GananciaController.getGananciaAnterior();
        Test.stopTest();
    
        // Asserts
    }
}