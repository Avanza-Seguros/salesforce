global class PolizaRenovacionScheduler implements Schedulable {
    global void execute(SchedulableContext SC) {
        try {
            List<Polizas__c> polizasParaRenovar = [
                SELECT Id, Asegurado__c, Correo__c
                FROM Polizas__c
                WHERE Fecha_de_Renovacion__c = TODAY
            ];

            if (polizasParaRenovar.isEmpty()) {
                System.debug('No hay pólizas para renovar hoy.');
                return;
            }

            for (Polizas__c poliza : polizasParaRenovar) {
                EnvioRenovacionPoliza.EnvioRenovacion(poliza);
            }
        } catch (Exception e) {
            System.debug('Error al procesar las renovaciones: ' + e.getMessage());
            // Considera re-lanzar la excepción o manejarla de forma que alerte a los administradores
        }
    }
}