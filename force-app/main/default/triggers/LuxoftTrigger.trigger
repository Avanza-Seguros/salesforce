trigger LuxoftTrigger on Items_Cases__c (after insert, after update) {
    System.debug('=== LuxoftTrigger INICIADO ===');
    try {
        if (Trigger.isInsert) {
            System.debug('=== LuxoftTrigger PROCESANDO INSERT ===');
            processInsert();
        }

        if (Trigger.isUpdate) {
            Boolean hayCambiosReales = false;
            for (Integer i = 0; i < Trigger.new.size(); i++) {
                Items_Cases__c oldItem = Trigger.old[i];
                Items_Cases__c newItem = Trigger.new[i];
                
                if ((oldItem.Estatus__c != newItem.Estatus__c) || (oldItem.Estado_Envio_Email__c != newItem.Estado_Envio_Email__c) || (oldItem.Nombre_Beneficiario_1__c != newItem.Nombre_Beneficiario_1__c) || 
                    (oldItem.Nombre_Beneficiario_2__c != newItem.Nombre_Beneficiario_2__c) || (oldItem.Nombre_Beneficiario_3__c != newItem.Nombre_Beneficiario_3__c) ||
                    (oldItem.Nombre_Beneficiario_4__c != newItem.Nombre_Beneficiario_4__c) || (oldItem.Nombre_Beneficiario_5__c != newItem.Nombre_Beneficiario_5__c) ||
                    (oldItem.Porcentaje_Beneficiario_1__c != newItem.Porcentaje_Beneficiario_1__c) || (oldItem.Porcentaje_Beneficiario_2__c != newItem.Porcentaje_Beneficiario_2__c) ||
                    (oldItem.Porcentaje_Beneficiario_3__c != newItem.Porcentaje_Beneficiario_3__c) || (oldItem.Porcentaje_Beneficiario_4__c != newItem.Porcentaje_Beneficiario_4__c) ||
                    (oldItem.Porcentaje_Beneficiario_5__c != newItem.Porcentaje_Beneficiario_5__c) || (oldItem.Parentesco_Beneficiario_1__c != newItem.Parentesco_Beneficiario_1__c) ||
                    (oldItem.Parentesco_Beneficiario_2__c != newItem.Parentesco_Beneficiario_2__c) || (oldItem.Parentesco_Beneficiario_3__c != newItem.Parentesco_Beneficiario_3__c) ||
                    (oldItem.Parentesco_Beneficiario_4__c != newItem.Parentesco_Beneficiario_4__c) || (oldItem.Parentesco_Beneficiario_5__c != newItem.Parentesco_Beneficiario_5__c)) {
                    hayCambiosReales = true; 
                    System.debug('🔄 Cambio detectado en Asegurados para Item ID: ' + newItem.Id);
                    break;
                }
            }

            // Si no hay cambios reales, salir del trigger
            if (!hayCambiosReales) {
                System.debug('⚠️ No hay cambios reales, se omite procesamiento');
                TriggerControl.isExecuting = false;
                return;
            }
        }

        if (Trigger.isInsert || Trigger.isUpdate) {
            System.debug('=== FORZANDO EJECUCIÓN DE FLOW TRIGGER ===');
            List<Id> idsToProcess = new List<Id>(Trigger.newMap.keySet());
            
            if (!idsToProcess.isEmpty()) {
                // 👇 MEJORA: Validar antes de ejecutar el flow
                if (!TriggerControl.isAlreadyProcessed(idsToProcess[0])) {
                    forzarEjecucionFlowTrigger(idsToProcess);
                } else {
                    System.debug('⏭️ Item ya procesado, se omite flow');
                }
            }
        }

    } finally {
        System.debug('=== LuxoftTrigger FINALIZADO ===');
        TriggerControl.isExecuting = false;
    }

    /* ================= INSERT ================= */
    public static void processInsert() {
        System.debug('=== LuxoftTrigger.processInsert INICIADO ===');
        Set<Id> itemsForContact = new Set<Id>();

        for (Items_Cases__c item : Trigger.new) {
            System.debug('🔍 Procesando item: ' + item);
            if (String.isNotBlank(item.Nombre__c) && String.isNotBlank(item.Apellido_paterno__c) && item.Asegurado__c == null) {
                itemsForContact.add(item.Id);
            }
        }
        System.debug('📧 Items para procesar en ContactQueueable: ' + itemsForContact);
        if (!itemsForContact.isEmpty()) {
            System.enqueueJob(new ContactQueueable(itemsForContact));
        }
    }

    public void forzarEjecucionFlowTrigger(List<Id> itemIds) {
        System.debug('🔄 Ejecutando flow Procesamiento_de_polizas');
        
        try {
            // Obtener todos los campos que necesita el flow
            List<Items_Cases__c> items = [
                SELECT Id, Name, Nombre__c, Apellido_paterno__c, Asegurado__c,
                       Estatus__c, Poliza__c, Fecha_de_nacimiento__c, RecordTypeId,
                       RecordType.Name, CreatedDate, LastModifiedDate, Beneficiario__c,
                       AM_Beneficiario_1__c, AM_Beneficiario_2__c, AM_Beneficiario_3__c,
                       AP_Beneficiario_1__c, AP_Beneficiario_2__c, AP_Beneficiario_3__c,
                       Nombre_Beneficiario_1__c, Nombre_Beneficiario_2__c, Nombre_Beneficiario_3__c,
                       Nombre_Beneficiario_4__c, Nombre_Beneficiario_5__c,
                       Nombre_completo_beneficiario_1__c, Nombre_completo_beneficiario_2__c,
                       Nombre_completo_beneficiario_3__c, Porcentaje_Beneficiario_1__c,
                       Porcentaje_Beneficiario_2__c, Porcentaje_Beneficiario_3__c,
                       Porcentaje_Beneficiario_4__c, Porcentaje_Beneficiario_5__c,
                       Parentesco_Beneficiario_1__c, Parentesco_Beneficiario_2__c,
                       Parentesco_Beneficiario_3__c, Parentesco_Beneficiario_4__c,
                       Parentesco_Beneficiario_5__c, Dependiente_1__c, Dependiente_2__c,
                       Dependiente_3__c, Dependiente_4__c, Dependiente_5__c
                FROM Items_Cases__c 
                WHERE Id IN :itemIds
            ];
            
            Map<String, Object> flowParams = new Map<String, Object>();
            flowParams.put('recordIds', new List<Id>(itemIds));
            flowParams.put('operacion', 'UPDATE');
            
            // Ejecutar el flow
            Flow.Interview flow = Flow.Interview.createInterview('Procesamiento_de_polizas', flowParams);
            flow.start();
            
            System.debug('✅ Flow ejecutado exitosamente');
            
        } catch(Exception e) {
            System.debug('❌ Error en flow: ' + e.getMessage());
        }
    }
}