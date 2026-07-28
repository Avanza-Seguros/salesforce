public class BatchEnvioEmails implements Database.Batchable<sObject>, Database.Stateful, Database.AllowsCallouts {
    
    // Variables de instancia
    public List<Id> specificItemIds;
    public Boolean processMarkedOnly = false;
    public Integer totalEmailsSent = 0;
    public Integer totalEmailsFailed = 0;
    public Integer totalItemsProcessed = 0;
    public List<String> errorMessages = new List<String>();
    public Map<Id, String> itemErrors = new Map<Id, String>(); // Errores por item específico
    public String batchErrorSummary = ''; // Resumen general de errores
    
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
        
        totalItemsProcessed += scope.size();
        
        // Mostrar información de los items
        for (Items_Cases__c item : scope) {
            System.debug('Item: ' + item.Name + ' | ID: ' + item.Id + ' | Email: ' + item.Correo_electronico__c);
        }
        
        List<Items_Cases__c> itemsToUpdate = new List<Items_Cases__c>();
        List<Id> itemIds = new List<Id>();
        
        // Variables para tracking de errores en este lote
        Boolean batchHasError = false;
        String batchErrorDetail = '';
        
        try {
            // 1. Validar items antes de enviar
            for (Items_Cases__c item : scope) {
                if (String.isBlank(item.Correo_electronico__c)) {
                    String error = 'Item ' + item.Id + ' - ' + item.Name + ': Correo electrónico vacío';
                    errorMessages.add(error);
                    itemErrors.put(item.Id, error);
                    item.Estatus__c = 'En proceso';
                    item.Procesar_Batch__c = true;
                    totalEmailsFailed++;
                    batchHasError = true;
                    itemsToUpdate.add(item);
                }
            }
            
            // Filtrar solo los items válidos para enviar
            List<Items_Cases__c> validItems = new List<Items_Cases__c>();
            for (Items_Cases__c item : scope) {
                if (!itemErrors.containsKey(item.Id)) {
                    validItems.add(item);
                }
            }
            
            // 2. Enviar emails solo para items válidos
            Boolean envioExitoso = false;
            String envioErrorMsg = '';
            
            if (!validItems.isEmpty()) {
                System.debug('Intentando enviar ' + validItems.size() + ' emails...');
                
                try {
                    EnvioPlantillasWrapper.enviarEmailsBulk(validItems);
                    envioExitoso = true;
                    System.debug('✅ Método enviarEmailsBulk ejecutado sin excepciones');
                } catch (Exception wrapperEx) {
                    envioExitoso = false;
                    envioErrorMsg = wrapperEx.getMessage();
                    batchErrorDetail = 'Error en wrapper: ' + envioErrorMsg;
                    batchHasError = true;
                    
                    String errorGeneral = 'ERROR EN LOTE - Fallo en envío bulk: ' + envioErrorMsg;
                    errorMessages.add(errorGeneral);
                    System.debug('❌ Error en enviarEmailsBulk: ' + wrapperEx.getMessage());
                    System.debug('StackTrace: ' + wrapperEx.getStackTraceString());
                }
            }
            
            // 3. Actualizar los items según el resultado
            for (Items_Cases__c item : scope) {
                // Si el item ya fue procesado como error por validación, saltar
                if (itemErrors.containsKey(item.Id)) {
                    continue;
                }
                
                itemIds.add(item.Id);
                
                if (envioExitoso) {
                    item.Estatus__c = 'Concluido';
                    item.Procesar_Batch__c = false;
                    totalEmailsSent++;
                    System.debug('✅ Marcando como Concluido: ' + item.Id);
                } else {
                    item.Estatus__c = 'En proceso';
                    item.Procesar_Batch__c = true;
                    totalEmailsFailed++;
                    
                    String errorDetail = 'Item ' + item.Id + ' - ' + item.Name + 
                                       ': Fallo en envío - ' + envioErrorMsg;
                    errorMessages.add(errorDetail);
                    itemErrors.put(item.Id, errorDetail);
                    
                    System.debug('❌ Marcando como Error en envío: ' + item.Id);
                }
                itemsToUpdate.add(item);
            }
            
            // 4. Actualizar los registros en la base de datos
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
                        String errorMsg = 'Error en BD actualizando ' + item.Id + ': ';
                        for (Database.Error err : sr.getErrors()) {
                            errorMsg += err.getMessage() + '; ';
                        }
                        System.debug('❌ ' + errorMsg);
                        errorMessages.add(errorMsg);
                        itemErrors.put(item.Id, errorMsg);
                        
                        // Ajustar contadores si la actualización falló
                        if (item.Estatus__c == 'Concluido') {
                            totalEmailsSent--;
                            totalEmailsFailed++;
                        }
                    }
                }
                
                System.debug('Resultados actualización: ' + actualizadosExitosamente + 
                           ' exitosos, ' + actualizadosConError + ' con error');
                
                if (actualizadosConError > 0) {
                    batchHasError = true;
                }
            }
            
            // Si hubo error en el lote, agregar resumen
            if (batchHasError) {
                batchErrorSummary += 'Lote con ' + scope.size() + ' items - ' + batchErrorDetail + '\n';
            }

        } catch (Exception e) {
            System.debug('🔥 ERROR GENERAL en execute: ' + e.getMessage());
            System.debug('StackTrace: ' + e.getStackTraceString());
            
            String errorDetallado = 'ERROR CRÍTICO en lote: ' + e.getMessage() + 
                                   ' | Línea: ' + e.getLineNumber() +
                                   ' | Tipo: ' + e.getTypeName();
            
            errorMessages.add(errorDetallado);
            batchErrorSummary += 'ERROR CRÍTICO en lote de ' + scope.size() + ' items: ' + e.getMessage() + '\n';
            
            // Marcar todos los items del lote como error
            for (Items_Cases__c item : scope) {
                if (!itemErrors.containsKey(item.Id)) {
                    item.Estatus__c = 'En proceso';
                    item.Procesar_Batch__c = true;
                    itemErrors.put(item.Id, 'Error crítico: ' + e.getMessage());
                    totalEmailsFailed++;
                }
            }
            
            try {
                Database.update(scope, false);
            } catch (Exception ex) {
                String errorUpdate = 'No se pudieron actualizar items después de error: ' + ex.getMessage();
                errorMessages.add(errorUpdate);
                System.debug('🔥 ' + errorUpdate);
            }
        }
        
        System.debug('===================================================');
    }
    
    public void finish(Database.BatchableContext bc) {
        System.debug('================= BATCH COMPLETADO =================');
        System.debug('Total items procesados: ' + totalItemsProcessed);
        System.debug('Total emails enviados: ' + totalEmailsSent);
        System.debug('Total emails con error: ' + totalEmailsFailed);
        System.debug('Total errores registrados: ' + errorMessages.size());
        
        if (processMarkedOnly && specificItemIds != null) {
            System.debug('Batch específico completado para ' + specificItemIds.size() + ' items');
        }
        
        // Mostrar errores en debug
        if (totalEmailsFailed > 0 || !errorMessages.isEmpty()) {
            System.debug('⚠️ RESUMEN DE ERRORES:');
            System.debug('Total de errores: ' + errorMessages.size());
            for (Integer i = 0; i < Math.min(10, errorMessages.size()); i++) {
                System.debug('  Error ' + (i+1) + ': ' + errorMessages[i]);
            }
            if (errorMessages.size() > 10) {
                System.debug('  ... y ' + (errorMessages.size() - 10) + ' errores más');
            }
        }
        
        // Enviar resumen detallado al administrador
        enviarResumenAdministrador();
        
        System.debug('===================================================');
    }
    
    private void enviarResumenAdministrador() {
        try {
            // Enviar email de resumen al administrador del sistema
            String[] toAddresses = new String[]{'sergio.uribe@volestra.com'};
            String subject = '📧 Resumen Batch Envío Emails - ' + System.now().format();
            
            String body = '<html>';
            body += '<head><style>';
            body += 'body { font-family: Arial, sans-serif; }';
            body += '.success { color: green; font-weight: bold; }';
            body += '.error { color: red; font-weight: bold; }';
            body += '.warning { color: orange; }';
            body += 'table { border-collapse: collapse; width: 100%; margin: 10px 0; }';
            body += 'th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }';
            body += 'th { background-color: #f2f2f2; }';
            body += '.error-detail { background-color: #ffeeee; margin-top: 20px; }';
            body += '</style></head>';
            body += '<body>';
            
            body += '<h2>📊 Resumen del proceso de envío de emails</h2>';
            body += '<p><strong>📅 Fecha y hora:</strong> ' + System.now() + '</p>';
            body += '<p><strong>🎯 Tipo de proceso:</strong> ' + (processMarkedOnly ? 'IDs específicos' : 'Todos los items en proceso') + '</p>';
            
            // Tabla de resumen
            body += '<table>';
            body += '<tr><th>Métrica</th><th>Valor</th></tr>';
            body += '<tr><td>Total items procesados</td><td><strong>' + totalItemsProcessed + '</strong></td></tr>';
            body += '<tr><td>✅ Enviados exitosamente</td><td class="success">' + totalEmailsSent + '</td></tr>';
            body += '<tr><td>❌ Con errores</td><td class="error">' + totalEmailsFailed + '</td></tr>';
            body += '<tr><td>Tasa de éxito</td><td>' + 
                   (totalItemsProcessed > 0 ? 
                   Math.round((totalEmailsSent * 100.0) / totalItemsProcessed) : 0) + 
                   '%</td></tr>';
            body += '</table>';
            
            // Detalle de errores si existen
            if (!errorMessages.isEmpty()) {
                body += '<div class="error-detail">';
                body += '<h3 class="error">❌ DETALLE DE ERRORES (' + errorMessages.size() + ' errores)</h3>';
                
                if (errorMessages.size() <= 50) {
                    // Mostrar todos los errores
                    body += '<ul>';
                    for (String error : errorMessages) {
                        body += '<li>' + escapeHtml(error) + '</li>';
                    }
                    body += '</ul>';
                } else {
                    // Mostrar resumen de errores
                    body += '<p><strong>Se generaron ' + errorMessages.size() + ' errores.</strong></p>';
                    body += '<p>Los primeros 25 errores:</p>';
                    body += '<ul>';
                    for (Integer i = 0; i < 25; i++) {
                        body += '<li>' + escapeHtml(errorMessages[i]) + '</li>';
                    }
                    body += '</ul>';
                    body += '<p class="warning">⚠️ Hay ' + (errorMessages.size() - 25) + ' errores adicionales no mostrados.</p>';
                }
                
                // Agregar resumen por tipo de error
                body += '<h4>📋 Resumen por tipo de error:</h4>';
                Map<String, Integer> errorTypes = new Map<String, Integer>();
                for (String error : errorMessages) {
                    String errorKey = error.contains('Correo electrónico vacío') ? 'Email vacío' :
                                    (error.contains('Error en wrapper') ? 'Error en wrapper' :
                                    (error.contains('Error en BD') ? 'Error de base de datos' :
                                    (error.contains('ERROR CRÍTICO') ? 'Error crítico' : 'Otro error')));
                    Integer count = errorTypes.get(errorKey);
                    if (count == null) {
                        errorTypes.put(errorKey, 1);
                    } else {
                        errorTypes.put(errorKey, count + 1);
                    }
                }
                
                body += '<ul>';
                for (String errorType : errorTypes.keySet()) {
                    body += '<li><strong>' + errorType + ':</strong> ' + errorTypes.get(errorType) + ' errores</li>';
                }
                body += '</ul>';
                
                body += '</div>';
            }
            
            // Resumen de batch errors
            if (String.isNotBlank(batchErrorSummary)) {
                body += '<div class="error-detail">';
                body += '<h3>⚠️ Resumen de errores por lote:</h3>';
                body += '<pre>' + escapeHtml(batchErrorSummary) + '</pre>';
                body += '</div>';
            }
            
            // Recomendaciones si hay errores
            if (totalEmailsFailed > 0) {
                body += '<div style="background-color: #fff3cd; padding: 10px; margin-top: 20px;">';
                body += '<h3>💡 Recomendaciones:</h3>';
                body += '<ul>';
                body += '<li>Revise los items con error en Salesforce (Estatus = "En proceso" y Procesar_Batch__c = true)</li>';
                body += '<li>Verifique que los correos electrónicos sean válidos</li>';
                body += '<li>Revise los logs de ejecución para más detalles</li>';
                body += '<li>Considere ejecutar nuevamente el batch para los items fallidos</li>';
                body += '</ul>';
                body += '</div>';
            }
            
            body += '<hr>';
            body += '<p style="font-size: 12px; color: gray;">Este es un mensaje automático del BatchEnvioEmails de Salesforce</p>';
            body += '</body></html>';
            
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(toAddresses);
            mail.setSubject(subject);
            mail.setHtmlBody(body);
            mail.setSaveAsActivity(false);
            
            // Enviar el email
            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{mail});
            
            System.debug('✅ Email de resumen enviado exitosamente');
            
        } catch (Exception e) {
            System.debug('❌ Error enviando resumen por email: ' + e.getMessage());
            System.debug('StackTrace: ' + e.getStackTraceString());
            
            // Si falla el email, al menos dejar el error en los logs
            System.debug('=== RESUMEN DEL BATCH (no se pudo enviar email) ===');
            System.debug('Total items: ' + totalItemsProcessed);
            System.debug('Éxitos: ' + totalEmailsSent);
            System.debug('Fallos: ' + totalEmailsFailed);
            System.debug('Errores: ' + errorMessages);
        }
    }
    
    // Método auxiliar para escapar HTML y evitar inyección
    private String escapeHtml(String input) {
    if (String.isBlank(input)) return '';
    return input.replace('&', '&amp;')
               .replace('<', '&lt;')
               .replace('>', '&gt;')
               .replace('"', '&quot;')
               .replace('\'', '&#39;'); 
}
}