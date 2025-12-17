trigger LuxoftTrigger on Items_Cases__c (after insert, after update) {
    
    // 1️⃣ Obtener RecordTypeIds
    Set<Id> altaRecordTypeIds = getRecordTypeIds(new String[]{'Alta', 'Alta solicitada', 'Alta con Dependientes'});
    Set<Id> bajaRecordTypeIds = getRecordTypeIds(new String[]{'Baja', 'Baja solicitada'});
    
    // 2️⃣ Inicializar sets para diferentes procesos
    Set<Id> itemsForContactProcessing = new Set<Id>();      // Flujo automático: crear contactos
    Set<Id> itemsForManualAltaEmail = new Set<Id>();        // Flujo manual: email inmediato
    Set<Id> itemsForQueueAltaEmail = new Set<Id>();         // Flujo automático: email después de contacto
    Set<Id> itemsForBajaEmail = new Set<Id>();              // Flujo manual: bajas
    
    // 3️⃣ Variables para detectar contexto
    Boolean isManualStatusChange = false;
    Boolean hasEmailContextControl = (EmailContextControl.skipEmails != null);
    
    // 4️⃣ Procesar cada registro
    if (Trigger.isAfter) {
        Map<Id, Items_Cases__c> oldMap = Trigger.isUpdate ? Trigger.oldMap : new Map<Id, Items_Cases__c>();
        
        for (Items_Cases__c newItem : Trigger.new) {
            Items_Cases__c oldItem = oldMap.get(newItem.Id);
            
            // 🔍 DETECTAR SI ES CAMBIO MANUAL DE ESTATUS
            Boolean isStatusChangeToConcluido = (Trigger.isUpdate && oldItem != null && 
                                                oldItem.Estatus__c != newItem.Estatus__c && 
                                                newItem.Estatus__c == 'Concluido');
            
            // 🔷 PROCESO 1: CREACIÓN DE CONTACTOS (Solo flujo automático)
            // Solo si NO hay contacto asignado Y tiene nombre/apellido
            if (String.isNotBlank(newItem.Nombre__c) && String.isNotBlank(newItem.Apellido_paterno__c) && newItem.Asegurado__c == null) {
                
                if (Trigger.isInsert) {
                    // Insert: siempre procesar para crear contacto
                    itemsForContactProcessing.add(newItem.Id);
                    itemsForQueueAltaEmail.add(newItem.Id); // Email después del contacto
                    
                } else if (Trigger.isUpdate) {
                    // Update: solo si cambió algún campo relevante
                    Boolean fieldsChanged = (newItem.Nombre__c != oldItem.Nombre__c || newItem.Apellido_paterno__c != oldItem.Apellido_paterno__c ||
                        newItem.Apellido_materno__c != oldItem.Apellido_materno__c || newItem.Correo_electronico__c != oldItem.Correo_electronico__c ||
                        isStatusChangeToConcluido // También si cambió a Concluido
                    );
                    
                    if (fieldsChanged) {
                        itemsForContactProcessing.add(newItem.Id);
                        itemsForQueueAltaEmail.add(newItem.Id); // Email después del contacto
                    }
                }
            }
            
            // 🔷 PROCESO 2: EMAILS MANUALES DE ALTA
            // Solo si es RecordType de Alta Y cambió manualmente a Concluido
            if (isStatusChangeToConcluido && altaRecordTypeIds.contains(newItem.RecordTypeId) && String.isNotBlank(newItem.Correo_electronico__c) &&
                String.isNotBlank(newItem.Nombre_cuenta__c)) {
                
                // Ya tiene contacto → es cambio manual
                itemsForManualAltaEmail.add(newItem.Id);
                // Remover del flujo automático si estaba allí
                itemsForQueueAltaEmail.remove(newItem.Id);
            }
            
            // 🔷 PROCESO 3: EMAILS DE BAJA (siempre manual)
            if (isStatusChangeToConcluido && 
                bajaRecordTypeIds.contains(newItem.RecordTypeId) &&
                !newItem.Baja_Por_Defuncion__c) {
                
                itemsForBajaEmail.add(newItem.Id);
            }
        }
        
        // 5️⃣ LOGGING para debugging
        System.debug('📊 Items_CasesTrigger - Resumen:');
        System.debug('  - Contactos a crear: ' + itemsForContactProcessing.size() + ' ' + itemsForContactProcessing);
        System.debug('  - Emails Manuales Alta: ' + itemsForManualAltaEmail.size() + ' ' + itemsForManualAltaEmail);
        System.debug('  - Emails Automáticos Alta: ' + itemsForQueueAltaEmail.size() + ' ' + itemsForQueueAltaEmail);
        System.debug('  - Emails Baja: ' + itemsForBajaEmail.size() + ' ' + itemsForBajaEmail);
        System.debug('  - EmailContextControl.skipEmails: ' + EmailContextControl.skipEmails);
        
        // 6️⃣ EJECUTAR PROCESOS
        
        // 🔄 A. CONTACTQUEUEABLE (Flujo automático)
        if (!itemsForContactProcessing.isEmpty()) {
            executeQueueable(new ContactQueueable(itemsForContactProcessing), 
                           'ContactQueueable', itemsForContactProcessing.size());
        }
        
        // 📧 B. EMAILS MANUALES DE ALTA (Ejecución síncrona inmediata)
        if (!itemsForManualAltaEmail.isEmpty()) {
            System.debug('🚀 Ejecutando emails MANUALES de Alta...');
            for (Id itemId : itemsForManualAltaEmail) {
                try {
                    // Ejecutar inmediatamente (síncrono)
                    EnvioPlantillas.EnvioEmail(itemId);
                    System.debug('  ✓ Email manual enviado para item: ' + itemId);
                } catch(Exception e) {
                    System.debug('  ✗ Error en email manual para ' + itemId + ': ' + e.getMessage());
                }
            }
        }
        
        // 📧 C. QUEUEENVIOEMAILS (Flujo automático - después de contactos)
        // NOTA: Este se ejecutará cuando ContactQueueable termine y actualice Asegurado__c
        // Se maneja en un trigger separado o en el finish de ContactQueueable
        
        // 📧 D. EMAILS DE BAJA (Siempre manual, ejecución síncrona)
        if (!itemsForBajaEmail.isEmpty()) {
            System.debug('📤 Ejecutando emails de Baja...');
            for (Id itemId : itemsForBajaEmail) {
                try {
                    EnvioBajas.BajasEmail(itemId);
                    System.debug('  ✓ Email baja enviado para item: ' + itemId);
                } catch(Exception e) {
                    System.debug('  ✗ Error en email baja para ' + itemId + ': ' + e.getMessage());
                }
            }
        }
    }
    
    // 7️⃣ Helper: Obtener RecordTypeIds
    private static Set<Id> getRecordTypeIds(String[] names) {
        Set<Id> ids = new Set<Id>();
        for (String name : names) {
            Schema.RecordTypeInfo info = Schema.SObjectType.Items_Cases__c.getRecordTypeInfosByName().get(name);
            if (info != null) ids.add(info.getRecordTypeId());
        }
        return ids;
    }
    
    // 8️⃣ Helper: Ejecutar Queueable con verificación de límites
    private static void executeQueueable(Queueable job, String jobName, Integer itemCount) {
        Integer currentJobs = Limits.getQueueableJobs();
        Integer maxJobs = Limits.getLimitQueueableJobs();
        
        if (currentJobs < maxJobs) {
            System.enqueueJob(job);
            System.debug('✅ ' + jobName + ' encolado para ' + itemCount + ' items');
        } else {
            System.debug('⚠️ NO se pudo encolar ' + jobName + ' - Límite: ' + currentJobs + '/' + maxJobs);
            // Opcional: Guardar para procesar después
        }
    }
}