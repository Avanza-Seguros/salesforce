public class GladiadoresBatch implements Database.Batchable<SObject>, Schedulable {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // No es necesario modificar este método para el flujo, ya que no se utiliza en este caso
        return Database.getQueryLocator('SELECT Id, Fecha_de_Alta__c, sexo__c, Name FROM Gladiadores__c');
    }

    public void execute(Database.BatchableContext bc, List<Gladiadores__c> scope) {
        Map<Decimal, Decimal> values = new Map<Decimal, Decimal>();
        for(Criterio_Vacaciones__mdt mdt : [select Id, Dias_disponibles__c, No_anos__c from Criterio_Vacaciones__mdt]){
            values.put(mdt.No_anos__c, mdt.Dias_disponibles__c);
        }

        Map<String, Decimal> valuesMap = new Map<String, Decimal>();
        for(Vacaciones_especiales__mdt mdtObj : [select Concepto__c, Dias_disponibles__c, Horas_Disponibles__c from Vacaciones_especiales__mdt]){
            valuesMap.put(mdtObj.Concepto__c, mdtObj.Dias_disponibles__c);
        }

        List<Gladiadores__c> lstGladiador = new List<Gladiadores__c>();
        for(Gladiadores__c gladiador : scope){ 
            if(gladiador.Fecha_de_Alta__c.month() == System.today().month() && gladiador.Fecha_de_Alta__c.day() == System.today().day()){
                lstGladiador.add(
                    new Gladiadores__c( Id = gladiador.Id,
                        Dias_Enfermedad__c = valuesMap.get('Enfermedad trabajador'),
                        Dias_Fallecimiento__c = valuesMap.get('Fallecimiento directo'),
                        Dias_Familiar_Enfermedad__c	= valuesMap.get('Enfermedad grave familiar directo'),
                        Dias_Hijo_Prematuro__c = (gladiador.sexo__c == 'Masculino' ? 0 : valuesMap.get('Hijos prematuros')),
                        Dias_Inexcusable__c	= valuesMap.get('Deberes inexcusables'),
                        Dias_Matrimonio__c = valuesMap.get('Por matrimonio'),
                        Dias_Mudanza__c	= valuesMap.get('Por mudanza'),
                        Dias_Nacimiento__c = valuesMap.get('Nacimiento'),
                        Cita_medica__c = 0,
                        Dias_Lactancia__c = (gladiador.sexo__c == 'Masculino' ? 0 : valuesMap.get('Lactancia materna')),
                        Vacaciones_Otorgadas_2__c = values.get(System.today().year() - gladiador.Fecha_de_Alta__c.year()),
                        Dias_Tomados__c = 0
                    )
                );
            }
        }
        Update lstGladiador;

        List<Solicitudes_de_Vacaciones__c> lstSV = new List<Solicitudes_de_Vacaciones__c>();
        for(Solicitudes_de_Vacaciones__c SV : [SELECT Id, Dias_Hasta__c, Etapa__c FROM Solicitudes_de_Vacaciones__c WHERE Etapa__c = 'Aceptado' AND Dias_Hasta__c <: System.today()]){ 
            lstSV.add(
                new Solicitudes_de_Vacaciones__c(
                    Id = SV.Id,
                    Etapa__c = 'Archivado'
                )
            );
        }
        Update lstSV;
    }

    public void Finish(Database.BatchableContext bc) {
        
    }
    public void execute(SchedulableContext bc) {
        Database.executebatch(new GladiadoresBatch());
        
    }
   
}