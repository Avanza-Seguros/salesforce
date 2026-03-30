@IsTest
public with sharing class GenerarRelacionPolizaInvocableTest {

    @IsTest
    static void testEjecutarDesdeFlow() {
        // Datos base
        Polizas__c pol1 = new Polizas__c(Name = 'Póliza Flow Test');
        insert pol1;
        
        Historico_Aportacion__c h1 = new Historico_Aportacion__c(
            Anualidad__c = '2024',
            PrimaBasica__c = 3000,
            PrimaAdicional__c = 500,
            PagosIngresados__c = 3500,
            Desde__c = Date.today().addDays(-30),
            Hasta__c = Date.today().addDays(335),
            Poliza__c = pol1.Id
        );
        insert h1;

        Asegurado__c a1 = new Asegurado__c(Name = 'Laura García', FechaNacimiento__c = Date.newInstance(1988, 4, 22), Polizas__c = pol1.Id);
        insert a1;

        Pago_Poliza__c p1 = new Pago_Poliza__c(
            Poliza__c = pol1.Id,
            Importe_de_Ultima_Aportacion__c = 900,
            Fecha_de_emision__c = Date.today(),
            Historico_Aportacion__c = h1.Id
        );
        insert p1;

        // Invocar método Invocable
        GenerarRelacionPolizaInvocable.InputWrapper input = new GenerarRelacionPolizaInvocable.InputWrapper();
        input.polizaIds = new List<Id>{ pol1.Id };
            
        GenerarRelacionPolizaInvocable.InputWrapper input2 = new GenerarRelacionPolizaInvocable.InputWrapper();
        input.polizaIds = new List<Id>{  };

        Test.startTest();
        List<GenerarRelacionPolizaInvocable.OutputWrapper> salida = GenerarRelacionPolizaInvocable.ejecutar(new List<GenerarRelacionPolizaInvocable.InputWrapper>{ input });
        List<GenerarRelacionPolizaInvocable.OutputWrapper> salida2 = GenerarRelacionPolizaInvocable.ejecutar(new List<GenerarRelacionPolizaInvocable.InputWrapper>{ input2 });
        Test.stopTest();

        System.assertEquals(1, salida.size(), 'Debe devolver una respuesta.');
        System.assertEquals(true, salida[0].exito, 'Debe marcar éxito.');
        System.assert(salida[0].mensaje.contains('✅'), 'Debe tener mensaje exitoso.');

        List<Relacion_Poliza__c> rels = [
            SELECT Id, Poliza__c, Asegurado__c, Pago__c, Historico__c
            FROM Relacion_Poliza__c WHERE Poliza__c = :pol1.Id
        ];
    }
}