public class BatchEnvioEmails implements Database.Batchable<sObject>, Database.Stateful, Database.AllowsCallouts {
    
    // Variables de instancia
    public List<Id> specificItemIds;
    public Boolean processMarkedOnly = false;
    public Integer totalEmailsSent = 0;
    public Integer totalEmailsFailed = 0;
    public List<String> errorMessages = new List<String>();
    
    // Constructor por defecto
    public BatchEnvioEmails() {
        this.processMarkedOnly = false;
    }
    
    // Método para establecer IDs específicos
    public void setItemIds(List<Id> itemIds) {
        this.specificItemIds = itemIds;
        this.processMarkedOnly = (itemIds != null && !itemIds.isEmpty());
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        System.debug('================= INICIANDO BATCH =================');
        
        String query = 'SELECT Id, Name, Correo_electronico__c, Correo_Copia__c,' +
                      'Estatus__c, Caso__c, Caso__r.CaseNumber, Contacto__c, ' +
                      'Procesar_Batch__c, Nombre_cuenta__c, Tipo_de_peticion__c, Baja_Por_Defuncion__c, ' +
                      'RecordTypeId, Categorias__c, Asegurado__c, ' +
                      'CreatedDate, LastModifiedDate ' +
                      'FROM Items_Cases__c ' +
                      'WHERE Estatus__c = \'En proceso\' ';
        
        if (processMarkedOnly && specificItemIds != null && !specificItemIds.isEmpty()) {
            query += ' AND Id IN :specificItemIds ';
            System.debug('Procesando IDs específicos: ' + specificItemIds.size() + ' items');
            System.debug('IDs específicos: ' + specificItemIds);
        } else {
            System.debug('Procesando todos los items con estatus "En proceso"');
        }
        
        System.debug('Query: ' + query);
        System.debug('===================================================');
                
        return Database.getQueryLocator(query);
    }
    
    public void execute(Database.BatchableContext bc, List<Items_Cases__c> scope) {
        System.debug('================= EJECUTANDO LOTE =================');
        System.debug('Procesando lote de ' + scope.size() + ' items');
        
        // Verificar que hay items para procesar
        if (scope.isEmpty()) {
            System.debug('No hay items para procesar en este lote');
            return;
        }
        
        // Mostrar información de los items
        for (Items_Cases__c item : scope) {
            System.debug('Item: ' + item.Name + ' | ID: ' + item.Id + ' | Email: ' + item.Correo_electronico__c);
        }
        
        List<Items_Cases__c> itemsToUpdate = new List<Items_Cases__c>();
        List<Id> itemIds = new List<Id>();
        
        try {
            // 1. Primero, intentar enviar los emails
            Boolean envioExitoso = false;
            
            if (scope.size() > 0) {
                System.debug('Intentando enviar emails...');
                
                // Llamar al wrapper para enviar emails
                try {
                    // Asumiendo que EnvioPlantillasWrapper.enviarEmailsBulk retorna un booleano
                    // o podemos usar try-catch para ver si lanza excepción
                    EnvioPlantillasWrapper.enviarEmailsBulk(scope);
                    envioExitoso = true;
                    System.debug('✅ Método enviarEmailsBulk ejecutado sin excepciones');
                } catch (Exception wrapperEx) {
                    System.debug('❌ Error en enviarEmailsBulk: ' + wrapperEx.getMessage());
                    System.debug('StackTrace: ' + wrapperEx.getStackTraceString());
                    envioExitoso = false;
                    errorMessages.add('Error en envío: ' + wrapperEx.getMessage());
                }
            }
            
            // 2. Actualizar los items según el resultado
            for (Items_Cases__c item : scope) {
                itemIds.add(item.Id);
                
                if (envioExitoso) {
                    item.Estatus__c = 'Concluido';
                    item.Procesar_Batch__c = false;
                    totalEmailsSent++;
                    System.debug('Marcando como Concluido: ' + item.Id);
                } else {
                    item.Estatus__c = 'En proceso';
                    item.Procesar_Batch__c = true; // Mantener marcado para reintentar
                    totalEmailsFailed++;
                    System.debug('Marcando como Error en envío: ' + item.Id);
                }
                itemsToUpdate.add(item);
            }
            
            // 3. Actualizar los registros en la base de datos
            if (!itemsToUpdate.isEmpty()) {
                System.debug('Intentando actualizar ' + itemsToUpdate.size() + ' registros...');
                
                // Usar Database.update con allOrNone=false para manejar errores individuales
                Database.SaveResult[] saveResults = Database.update(itemsToUpdate, false);
                
                // Verificar resultados de la actualización
                Integer actualizadosExitosamente = 0;
                Integer actualizadosConError = 0;
                
                for (Integer i = 0; i < saveResults.size(); i++) {
                    Database.SaveResult sr = saveResults[i];
                    Items_Cases__c item = itemsToUpdate[i];
                    
                    if (sr.isSuccess()) {
                        actualizadosExitosamente++;
                        System.debug('✅ Registro actualizado: ' + item.Id);
                    } else {
                        actualizadosConError++;
                        String errorMsg = 'Error actualizando ' + item.Id + ': ';
                        for (Database.Error err : sr.getErrors()) {
                            errorMsg += err.getMessage() + '; ';
                        }
                        System.debug('❌ ' + errorMsg);
                        errorMessages.add(errorMsg);
                    }
                }
                
                System.debug('Resultados actualización: ' + actualizadosExitosamente + ' exitosos, ' + actualizadosConError + ' con error');
            }

        } catch (Exception e) {
            System.debug('🔥 ERROR GENERAL en execute: ' + e.getMessage());
            System.debug('StackTrace: ' + e.getStackTraceString());
            errorMessages.add('Error general en execute: ' + e.getMessage());
            
            // Intentar marcar todos como error
            for (Items_Cases__c item : scope) {
                item.Estatus__c = 'En proceso';
                item.Procesar_Batch__c = true;
            }
            
            try {
                Database.update(scope, false);
            } catch (Exception ex) {
                System.debug('🔥 No se pudieron actualizar los items después de error general');
            }
        }
        
        System.debug('===================================================');
    }
    
    public void finish(Database.BatchableContext bc) {
        System.debug('================= BATCH COMPLETADO =================');
        System.debug('Total emails enviados: ' + totalEmailsSent);
        System.debug('Total emails con error: ' + totalEmailsFailed);
        System.debug('Total errores registrados: ' + errorMessages.size());

        if (processMarkedOnly && specificItemIds != null) {
            System.debug('Batch específico completado para ' + specificItemIds.size() + ' items');
        }
        
        // Enviar notificación si hay errores
        if (totalEmailsFailed > 0 || !errorMessages.isEmpty()) {
            System.debug('⚠️ Errores encontrados:');
            for (String error : errorMessages) {
                System.debug('  - ' + error);
            }
            
            // También puedes crear un registro de log
        }
        
        System.debug('===================================================');
        
        // Opcional: Enviar email de resumen al administrador
        enviarResumenAdministrador();
    }
    
    private void enviarResumenAdministrador() {
        try {
            // Enviar email de resumen al administrador del sistema
            String[] toAddresses = new String[]{'sergio.uribe@volestra.com'}; // Cambiar por email real
            String subject = 'Resumen Batch Envío Emails - ' + System.now();
            String body = '<h2>Resumen del proceso de envío de emails</h2>';
            body += '<p><strong>Fecha:</strong> ' + System.now() + '</p>';
            body += '<p><strong>Total procesados:</strong> ' + (totalEmailsSent + totalEmailsFailed) + '</p>';
            body += '<p><strong>Enviados exitosamente:</strong> ' + totalEmailsSent + '</p>';
            body += '<p><strong>Con errores:</strong> ' + totalEmailsFailed + '</p>';
            
            if (!errorMessages.isEmpty()) {
                body += '<h3>Errores:</h3><ul>';
                for (String error : errorMessages) {
                    body += '<li>' + error + '</li>';
                }
                body += '</ul>';
            }
            
            
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(toAddresses);
            mail.setSubject(subject);
            mail.setHtmlBody(body);
            mail.setSaveAsActivity(false);
            
            // Enviar el email
            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{mail});
            
            
            System.debug('Email de resumen preparado para enviar');
            
        } catch (Exception e) {
            System.debug('Error enviando resumen: ' + e.getMessage());
        }
    }
}