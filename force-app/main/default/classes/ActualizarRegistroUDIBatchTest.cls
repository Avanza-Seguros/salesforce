@isTest
public with sharing class ActualizarRegistroUDIBatchTest {    
        @isTest
        private static void TestBatch(){
            
            Test.startTest();
            Database.executebatch(new ActualizarRegistroUDIBatch());
            Test.stopTest();
            
        
    }
}