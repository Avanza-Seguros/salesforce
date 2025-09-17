@isTest
public with sharing class ActualizarRegistroDLLBatchTest {    
        @isTest
        private static void TestBatch(){
            
            Test.startTest();
            Database.executebatch(new ActualizarRegistroDLLBatch());
            Test.stopTest();
            
        
    }
}