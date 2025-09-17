@isTest
public class ControlFoliosTriggerTest {
    @TestSetup
    static void makeData(){

        Control_de_Folios__c cf = new Control_de_Folios__c();
        cf.Estatus__c = 'Nuevo';
        cf.RecordtypeId = Schema.SObjectType.Control_de_Folios__c.getRecordTypeInfosByName().get('Siniestros').getRecordTypeId();
		insert cf;
        
    }

    @isTest
    static void isUpdateIsAfterTest() {
        Contact co = new Contact();
        co.FirstName = 'test';
        co.LastName = 'test';
        co.Email = 'test@test.com';
        Insert co;

        Control_de_Folios__c cf = new Control_de_Folios__c();
        cf.Estatus__c = 'Nuevo';
        cf.RecordtypeId = Schema.SObjectType.Control_de_Folios__c.getRecordTypeInfosByName().get('Siniestros').getRecordTypeId();
		insert cf;

        cf.Movimiento__c = 'Programación';
        cf.Estatus__c = 'Concluido';
        cf.Correo__c = 'test@test.com';
        cf.Titular__c = co.Id;
        //cf.Enviar_Encuesta__c = true;
        Update cf;
    }
    
    @isTest
    static void isInsertIsAfterTest() {
        Contact co = new Contact();
        co.FirstName = 'test';
        co.LastName = 'test';
        co.Email = 'test@test.com';
        Insert co;

        Control_de_Folios__c cf = new Control_de_Folios__c();
        cf.Estatus__c = 'Concluido';
        cf.Correo__c = 'test@test.com';
        cf.Titular__c = co.Id;
        cf.RecordtypeId = Schema.SObjectType.Control_de_Folios__c.getRecordTypeInfosByName().get('Siniestros').getRecordTypeId();
		insert cf;
    }
    
    @isTest
    static void isUpdateIsBeforeTest() {
        Contact co = new Contact();
        co.FirstName = 'test';
        co.LastName = 'test';
        co.Email = 'test@test.com';
        Insert co;

        Control_de_Folios__c cf = new Control_de_Folios__c();
        cf.Estatus__c = 'Nuevo';
        cf.Correo__c = 'test@test.com';
        cf.Titular__c = co.Id;
        cf.RecordtypeId = Schema.SObjectType.Control_de_Folios__c.getRecordTypeInfosByName().get('Siniestros').getRecordTypeId();
		insert cf;
        
        cf.Estatus__c = 'Concluido';
        Update cf;
    }

}