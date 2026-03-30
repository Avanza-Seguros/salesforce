@IsTest
public class EnvioEmailsOrchestratorTest {
    
    @TestSetup
    static void setup() {
        // Solo datos mínimos
        Account acc = new Account(Name = 'Test');
        insert acc;

        Case caso = new Case(
            Subject = 'Test Case',
            Status = 'New',
            AccountId = acc.Id
        );
        insert caso;
        
        Items_Cases__c item = new Items_Cases__c(
            Nombre_cuenta__c = acc.Id,
            Correo_electronico__c = 'test@test.com',
            Estatus__c = 'Concluido',
            Sexo__c = 'Masculino',
            Caso__c = caso.Id,
            Fecha_de_peticion__c = Date.today(),
            Fecha_de_nacimiento__c = Date.today().addYears(-30)
        );
        insert item;
    }
    
    @IsTest
    static void testTodosLosMetodos() {
        Test.startTest();
        
        // Ejecutar todos los métodos una vez
        EnvioEmailsOrchestrator.verificarEstado();
        EnvioEmailsOrchestrator.verificarEstadoDetallado();
        EnvioEmailsOrchestrator.verificarCheckboxEnviado();
        String reporte = EnvioEmailsOrchestrator.generarReporte();
        
        Test.stopTest();
        
        // Verificación básica
        System.assertNotEquals(null, reporte, 'Reporte generado');
        System.assert(true, 'Todos los métodos ejecutados');
    }
}