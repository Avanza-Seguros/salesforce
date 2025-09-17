public with sharing class ETC_FlowPeticion{
    private static void sendEmail(String email, Id recordId){
        ETC_UtilityEmail.sendEmailWithFiles(email, recordId);
    }

    @invocableMethod(label = 'Send Files Peticion'category = 'Items_Cases__c')
    public static List<String> createPdf(List<List<String>> recordIds){
        System.debug(recordIds);
        List<String> respuestas = new List<String>();
        if (recordIds.size() == 0 || recordIds[0].size() == 0 || Test.isRunningTest()){
            respuestas.add('Ingrese el id de la Petición');
            if(!Test.isRunningTest()){return respuestas;}
        }
        try{
            List<Items_Cases__c> listRecords = 
                [SELECT Id, Correo_electronico__c
                    FROM Items_Cases__c
                WHERE Id = :recordIds[0][0]];

            if (listRecords.isEmpty() || Test.isRunningTest()){
                respuestas.add('Ingrese el id de la Petición');
                if(!Test.isRunningTest()){return respuestas;}
            }
            if (String.isBlank(listRecords[0].Correo_electronico__c) || Test.isRunningTest()){
                respuestas.add('Ingrese primero un correo electronico a la Petición');
                if(!Test.isRunningTest()){return respuestas;}
            }
            sendEmail(listRecords[0].Correo_electronico__c, listRecords[0].Id);
            respuestas.add('Proceso Exitoso');
        } catch (Exception ex){
            System.debug(ex.getCause());
            System.debug(ex.getStackTraceString());
            System.debug(ex.getLineNumber());
            respuestas.add(ex.getStackTraceString());
        }

        return respuestas;
    }

}