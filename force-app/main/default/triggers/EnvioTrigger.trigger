trigger EnvioTrigger on Items_Cases__c (after update) {
    System.debug('=== EnvioTrigger INICIADO ===');
    try {
        // =============================================
        // 📋 PROCESAR UPDATE
        // =============================================
        if (Trigger.isUpdate) {
            System.debug('=== PROCESANDO UPDATE ===');
            processUpdate(Trigger.new, Trigger.oldMap);
        }
    } catch(Exception e) {
        System.debug('❌ ERROR en EnvioTrigger: ' + e.getMessage() + ' - ' + e.getStackTraceString());
        // Considera agregar un mecanismo de notificación de errores aquí
        
    } finally {
        TriggerControl.isExecuting = false;
        System.debug('=== EnvioTrigger FINALIZADO ===');
    }

    /* ================= MÉTODOS AUXILIARES ================= */

    // 🏷️ OBTENER RECORDTYPE IDs
    private static Map<String, Set<Id>> getRecordTypeIdsByCategory() {
        System.debug('Obteniendo RecordTypeIds por categoría...');
        Map<String, Set<Id>> recordTypeMap = new Map<String, Set<Id>>();
        recordTypeMap.put('ALTA', new Set<Id>());
        recordTypeMap.put('BAJA', new Set<Id>());
        
        Map<String, Schema.RecordTypeInfo> rtMap = Schema.SObjectType.Items_Cases__c.getRecordTypeInfosByName();
        
        // RecordTypes de ALTA
        String[] altaNames = new String[]{'Alta', 'Alta solicitada', 'Alta con Dependientes'};
        for (String name : altaNames) {
            if (rtMap.containsKey(name)) {
                recordTypeMap.get('ALTA').add(rtMap.get(name).getRecordTypeId());
                System.debug('✅ RecordType ALTA agregado: ' + name);
            }
        }
        
        // RecordTypes de BAJA
        String[] bajaNames = new String[]{'Baja', 'Baja solicitada'};
        for (String name : bajaNames) {
            if (rtMap.containsKey(name)) {
                recordTypeMap.get('BAJA').add(rtMap.get(name).getRecordTypeId());
                System.debug('✅ RecordType BAJA agregado: ' + name);
            }
        }
        
        return recordTypeMap;
    }

    /* ================= UPDATE ================= */
    private static void processUpdate(List<Items_Cases__c> newItems, Map<Id, Items_Cases__c> oldMap) {
        System.debug('=== PROCESS UPDATE INICIADO ===');
        
        // Verificar si se permite envío de emails
        if (!EmailContextControl.canTriggerSend()) {
            System.debug('🚫 Envío de emails no permitido en este contexto');
            return;
        }
        
        // Obtener RecordTypes
        Map<String, Set<Id>> recordTypeMap = getRecordTypeIdsByCategory();
        Set<Id> altaRecordTypeIds = recordTypeMap.get('ALTA');
        Set<Id> bajaRecordTypeIds = recordTypeMap.get('BAJA');
        
        Set<Id> itemsForAltaEmail = new Set<Id>();
        Set<Id> itemsForBajaEmail = new Set<Id>();
        
        System.debug('=== ANALIZANDO ' + newItems.size() + ' REGISTROS ===');
        
        for (Items_Cases__c newItem : newItems) {
            Items_Cases__c oldItem = oldMap.get(newItem.Id);
            
            System.debug('🔍 Procesando item: ' + newItem.Id);
            System.debug('  Estatus anterior: ' + (oldItem != null ? oldItem.Estatus__c : 'N/A'));
            System.debug('  Estatus nuevo: ' + newItem.Estatus__c);
            
            // 🔴 VERIFICAR SI YA FUE PROCESADO
            if (TriggerControl.isAlreadyProcessed(newItem.Id)) {
                System.debug('  ⏭️  Item ya procesado en esta transacción');
                continue;
            }
            
            // =============================================
            // ✅ CONDICIÓN UNIFICADA Y MEJORADA
            // =============================================
            
            Boolean debeProcesarEmail = false;
            
            // CASO 1: Cambió a "Concluido" desde cualquier estado (excepto si ya estaba Concluido)
            if (oldItem != null && oldItem.Estatus__c != 'Concluido' && newItem.Estatus__c == 'Concluido') {
                debeProcesarEmail = true;
                System.debug('  ✅ Caso 1: Cambió a Concluido');
            }
            
            // CASO 2: Ya estaba "Concluido" pero no se ha enviado email aún
            else if (newItem.Estatus__c == 'Concluido' && EmailProcessingControl.canSendEmail(newItem.Id, 'TRIGGER')) {
                debeProcesarEmail = true;
                System.debug('  ✅ Caso 2: Ya Concluido pero necesita email');
            }
            
            if (!debeProcesarEmail) {
                System.debug('  ❌ No cumple condiciones para envío de email');
                continue;
            }
            
            System.debug('  ✅ Cumple condiciones para envío de email');
            
            // =============================================
            // 📧 CLASIFICAR POR RECORD TYPE
            // =============================================
            
            // ALTA: Solo si tiene correo
            if (altaRecordTypeIds.contains(newItem.RecordTypeId)) {
                System.debug('  📋 Es RecordType de ALTA');
                if (String.isNotBlank(newItem.Correo_electronico__c)) {
                    itemsForAltaEmail.add(newItem.Id);
                    System.debug('  ✅ Agregado para email de ALTA');
                    TriggerControl.markAsProcessed(newItem.Id);
                    EmailProcessingControl.markForSending(newItem.Id);
                } else {
                    System.debug('  ⚠️  No tiene correo para ALTA');
                }
            }
            
            // BAJA: Solo si no es por defunción
            if (bajaRecordTypeIds.contains(newItem.RecordTypeId)) {
                System.debug('  📋 Es RecordType de BAJA');
                if (!newItem.Baja_Por_Defuncion__c) {
                    itemsForBajaEmail.add(newItem.Id);
                    System.debug('  ✅ Agregado para email de BAJA');
                    TriggerControl.markAsProcessed(newItem.Id);
                    EmailProcessingControl.markForSending(newItem.Id);
                } else {
                    System.debug('  ⚠️  Es baja por defunción, no se envía email');
                }
            }
        }

        System.debug('=== RESUMEN FINAL EnvioTrigger ===');
        System.debug('Altas para email: ' + itemsForAltaEmail.size());
        System.debug('Bajas para email: ' + itemsForBajaEmail.size());
        
        // =============================================
        // 🚀 ENCOLAR JOBS
        // =============================================
        
        // Encolar emails de ALTA
        if (!itemsForAltaEmail.isEmpty()) {
            System.debug('📧 Encolando ' + itemsForAltaEmail.size() + ' email(s) de ALTA');
            System.enqueueJob(new QueueEnvioEmails(itemsForAltaEmail, 'ALTA'));
        }
        
        // Encolar emails de BAJA
        if (!itemsForBajaEmail.isEmpty()) {
            System.debug('📧 Encolando ' + itemsForBajaEmail.size() + ' email(s) de BAJA');
            System.enqueueJob(new QueueEnvioEmails(itemsForBajaEmail, 'BAJA'));
        }
    }
}