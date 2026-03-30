trigger GladiadoresTrigger on Gladiadores__c (before insert) {
    
    if( trigger.isInsert && trigger.isBefore){
        for(Gladiadores__c obj : Trigger.new){
         	Integer VCvalue =  System.today().year() - obj.Fecha_de_Alta__c.year();
            Criterio_Vacaciones__mdt params = [select Id, Dias_disponibles__c from Criterio_Vacaciones__mdt where  No_anos__c =: VCvalue limit 1];
            obj.Vacaciones_Otorgadas_2__c = params.Dias_disponibles__c;
            obj.Dias_Tomados__c = 0;

            List<Vacaciones_especiales__mdt> paramsEspeciales = [select Concepto__c, Dias_disponibles__c from Vacaciones_especiales__mdt];
            Map<String, Decimal> valuesMap = new Map<String, Decimal>();
            for(Vacaciones_especiales__mdt mdtObj : [select Concepto__c, Dias_disponibles__c from Vacaciones_especiales__mdt]){
                valuesMap.put(mdtObj.Concepto__c, mdtObj.Dias_disponibles__c);
            }
            obj.Dias_Enfermedad__c = valuesMap.get('Enfermedad trabajador');
            obj.Dias_Fallecimiento__c = valuesMap.get('Fallecimiento directo');
            obj.Dias_Familiar_Enfermedad__c	= valuesMap.get('Enfermedad grave familiar directo');
            obj.Dias_Hijo_Prematuro__c = (obj.sexo__c == 'Masculino' ? 0 : valuesMap.get('Hijos prematuros'));
            obj.Dias_Inexcusable__c	= valuesMap.get('Deberes inexcusables');
            obj.Dias_Matrimonio__c = valuesMap.get('Por matrimonio');
            obj.Dias_Mudanza__c	= valuesMap.get('Por mudanza');
            obj.Dias_Nacimiento__c = valuesMap.get('Nacimiento');
            obj.Cita_medica__c = 0;
            obj.Dias_Lactancia__c = (obj.sexo__c == 'Masculino' ? 0 : valuesMap.get('Lactancia materna'));
        }
    }

}