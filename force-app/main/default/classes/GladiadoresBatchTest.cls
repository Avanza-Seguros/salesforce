@isTest
public  class GladiadoresBatchTest {

    @testSetup static void setup() {
        Gladiadores__c gld = new Gladiadores__c();
        gld.Name = 'test';
        gld.Contrase_a__c = 'test';
        gld.Tipo_de_Contrato__c = 'Colaborador';
        gld.Fecha_de_Alta__c = System.today();
        gld.sexo__c = 'Masculino';
        gld.email__c = 'Test@test.com';

        Insert gld;
        /*

        gld.Tipo_de_Contrato__c
        gld.Tipo_de_Contrato__c
        gld.Tipo_de_Contrato__c
        gld.Tipo_de_Contrato__c
        */
        Insert new Solicitudes_de_Vacaciones__c(
            Gladiador__c = gld.Id,
            Fecha_de_Solicitud__c = System.today(),
            Dias_Desde__c = date.valueOf(System.today()),
            Dias_Hasta__c = date.valueOf(System.today()),
            TIpo_de_Permiso__c = 'Vacaciones',
            Motivo_Ausencia__c = null,
            Motivo_de_ausencia__c = null,
            Dias_que_se_Solicitan__c = 1,
            Etapa__c = 'Creado'
        );
    }

    static testmethod void runBatchTest(){
        Database.executebatch(new GladiadoresBatch());
    }
}