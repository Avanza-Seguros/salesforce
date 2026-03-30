/**
 * @description InvocableMethod para generar relaciones de pólizas desde Flow
 *              Retorna un objeto estructurado con totales y mensaje de resultado
 */
public with sharing class GenerarRelacionPolizaInvocable {

    public class InputWrapper {
        @InvocableVariable(required=true description='IDs de las pólizas a procesar')
        public List<Id> polizaIds;
    }

    public class OutputWrapper {
        @InvocableVariable public String mensaje;
        @InvocableVariable public Integer totalPolizas;
        @InvocableVariable public Integer totalRelaciones;
        @InvocableVariable public Boolean exito;
    }

    @InvocableMethod(label='Generar Relaciones de Póliza' description='Crea registros en Relacion_Poliza__c basados en sus dependencias')
    public static List<OutputWrapper> ejecutar(List<InputWrapper> inputs) {
        List<OutputWrapper> resultados = new List<OutputWrapper>();

        for (InputWrapper input : inputs) {
            OutputWrapper result = new OutputWrapper();
            try {
                List<Relacion_Poliza__c> creadas = GenerarRelacionPolizaController.buildRelaciones(input.polizaIds);
                result.totalPolizas = input.polizaIds.size();
                result.totalRelaciones = creadas.size();
                result.mensaje = '✅ Se generaron ' + creadas.size() + ' relaciones para ' + input.polizaIds.size() + ' pólizas.';
                result.exito = true;
            } catch (Exception e) {
                result.mensaje = '❌ Error: ' + e.getMessage();
                result.totalPolizas = input.polizaIds != null ? input.polizaIds.size() : 0;
                result.totalRelaciones = 0;
                result.exito = false;
            }
            resultados.add(result);
        }

        return resultados;
    }
}