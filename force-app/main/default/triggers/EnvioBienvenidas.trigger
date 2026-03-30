trigger EnvioBienvenidas on Opportunity (after update) {
    // Iterar solo sobre el registro de Opportunity que se actualiza
    for (Opportunity opp : Trigger.new) {
        // Verificar si el campo 'Ramo__c' o 'StageName' ha sido modificado y cumple con las condiciones
        Opportunity oldOpp = Trigger.oldMap.get(opp.Id);
        if ((opp.Ramo__c != oldOpp.Ramo__c || opp.StageName != oldOpp.StageName) &&
            opp.Tipo_de_poliza__c != 'Individual') {
            
            // Asegurarse de que el campo Ramo__c no sea nulo y verificar el StageName
            if (opp.Ramo__c != null && opp.StageName == 'Closed Won') {
                BienvenidasPoliza.EnvioEmail(opp.Id);
            }
        }
    }
}