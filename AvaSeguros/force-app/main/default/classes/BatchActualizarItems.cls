global class BatchActualizarItems implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {
    
    global Integer totalProcesados = 0;
    global Integer totalActualizados = 0;
    global Integer totalEnviados = 0;
    global Integer totalErrores = 0;
    global List<String> logs = new List<String>();
    global Map<Id, String> erroresPorItem = new Map<Id, String>();
    
    global Database.QueryLocator start(Database.BatchableContext bc) {
        logs.add('=== INICIANDO BATCH === ' + System.now());
        System.debug('BatchActualizarItems - Iniciando query');
        
        return Database.getQueryLocator([
            SELECT Id, Name, Estatus__c, Correo_electronico__c, Correo_Copia__c,
                   Categorias__c, Nombre_cuenta__c, Contacto__c, Asegurado__c,
                   Apellido_paterno__c, Apellido_materno__c, Certificado__c
            FROM Items_Cases__c
            WHERE Estatus__c = 'En proceso'
            AND Correo_electronico__c != null
            ORDER BY CreatedDate ASC
        ]);
    }
    
    global void execute(Database.BatchableContext bc, List<Items_Cases__c> scope) {
        logs.add('--- Ejecutando lote con ' + scope.size() + ' registros ---');
        System.debug('Procesando lote de ' + scope.size() + ' registros');
        
        // ========== FASE 1: ACTUALIZAR REGISTROS PRIMERO ==========
        List<Items_Cases__c> itemsParaUpdate = new List<Items_Cases__c>();
        Map<Id, Items_Cases__c> itemsOriginales = new Map<Id, Items_Cases__c>();
        Map<Id, Items_Cases__c> itemsParaEmail = new Map<Id, Items_Cases__c>();
        
        try {
            // Preparar registros para actualización
            for (Items_Cases__c item : scope) {
                totalProcesados++;
                itemsOriginales.put(item.Id, item);
                
                try {
                    // Validar email antes de proceder
                    if (!esEmailValido(item.Correo_electronico__c)) {
                        throw new BatchException('Email inválido: ' + item.Correo_electronico__c);
                    }
                    
                    // Crear registro para actualizar (CORRECCIÓN CLAVE)
                    Items_Cases__c itemParaUpdate = new Items_Cases__c();
                    itemParaUpdate.Id = item.Id;
                    itemParaUpdate.Estatus__c = 'Concluido';
                    itemParaUpdate.Email_Enviado__c = true;
                    itemsParaUpdate.add(itemParaUpdate);
                    itemsParaEmail.put(item.Id, item); // Guardar para enviar email después
                    
                    logs.add('Preparado para update: ' + item.Id + ' -> Concluido');
                    
                } catch (Exception e) {
                    totalErrores++;
                    String errorMsg = 'Error preparando item ' + item.Id + ': ' + e.getMessage();
                    logs.add('ERROR PREP: ' + errorMsg);
                    erroresPorItem.put(item.Id, errorMsg);
                    
                    // Marcar como error
                    Items_Cases__c itemError = new Items_Cases__c(
                        Id = item.Id,
                        Estatus__c = 'En proceso'
                    );
                    itemsParaUpdate.add(itemError);
                }
            }
            
            // ========== ACTUALIZAR REGISTROS ==========
            if (!itemsParaUpdate.isEmpty()) {
                logs.add('Intentando actualizar ' + itemsParaUpdate.size() + ' registros...');
                
                // Opción 1: Update directo con allOrNone = false
                List<Database.SaveResult> updateResults = Database.update(itemsParaUpdate, false);
                
                // Analizar resultados
                Integer successCount = 0;
                Integer failCount = 0;
                Set<Id> idsActualizadosExitosamente = new Set<Id>();
                Set<Id> idsConErrorUpdate = new Set<Id>();
                
                for (Integer i = 0; i < updateResults.size(); i++) {
                    Database.SaveResult sr = updateResults[i];
                    Items_Cases__c itemIntentado = itemsParaUpdate[i];
                    
                    if (sr.isSuccess()) {
                        successCount++;
                        totalActualizados++;
                        idsActualizadosExitosamente.add(itemIntentado.Id);
                        logs.add('UPDATE EXITOSO: ' + itemIntentado.Id + ' -> ' + itemIntentado.Estatus__c);
                    } else {
                        failCount++;
                        totalErrores++;
                        idsConErrorUpdate.add(itemIntentado.Id);
                        
                        String errorMsg = 'ERROR UPDATE para ' + itemIntentado.Id + ': ';
                        for (Database.Error err : sr.getErrors()) {
                            errorMsg += err.getStatusCode() + ': ' + err.getMessage() + ' ';
                        }
                        logs.add(errorMsg);
                        erroresPorItem.put(itemIntentado.Id, errorMsg);
                        
                        // Remover de items para email
                        itemsParaEmail.remove(itemIntentado.Id);
                    }
                }
                
                logs.add('Resultados update: ' + successCount + ' exitosos, ' + failCount + ' fallidos');
                
                // ========== VERIFICAR QUE LOS UPDATES SE APLICARON ==========
                if (!idsActualizadosExitosamente.isEmpty()) {
                    List<Items_Cases__c> itemsVerificados = [
                        SELECT Id, Estatus__c, Name 
                        FROM Items_Cases__c 
                        WHERE Id IN :idsActualizadosExitosamente 
                        LIMIT 10
                    ];
                    
                    logs.add('=== VERIFICACIÓN UPDATES (primeros 10) ===');
                    for (Items_Cases__c item : itemsVerificados) {
                        logs.add('Item ' + item.Name + ' (' + item.Id + ') -> Estatus: ' + item.Estatus__c);
                    }
                }
                
                // ========== FASE 2: ENVIAR EMAILS SOLO SI SE ACTUALIZÓ ==========
                if (!itemsParaEmail.isEmpty() && !idsActualizadosExitosamente.isEmpty()) {
                    logs.add('Preparando emails para ' + itemsParaEmail.size() + ' registros actualizados...');
                    
                    // Filtrar solo los que se actualizaron exitosamente
                    Map<Id, Items_Cases__c> itemsParaEnviarEmail = new Map<Id, Items_Cases__c>();
                    for (Id itemId : itemsParaEmail.keySet()) {
                        if (idsActualizadosExitosamente.contains(itemId)) {
                            itemsParaEnviarEmail.put(itemId, itemsParaEmail.get(itemId));
                        }
                    }
                    
                    if (!itemsParaEnviarEmail.isEmpty()) {
                        enviarEmails(itemsParaEnviarEmail.values());
                    } else {
                        logs.add('No hay registros válidos para enviar email');
                    }
                }
            }
            
        } catch (Exception e) {
            totalErrores++;
            String errorMsg = 'ERROR GLOBAL en execute: ' + e.getMessage() + ' - ' + e.getStackTraceString();
            logs.add(errorMsg);
            System.debug(errorMsg);
        }
        
        logs.add('--- Lote completado ---');
    }
    
    // ========== MÉTODO PARA ENVIAR EMAILS ==========
    private void enviarEmails(List<Items_Cases__c> items) {
        try {
            logs.add('Construyendo ' + items.size() + ' emails...');
            
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            Map<Id, Messaging.SingleEmailMessage> emailsPorItem = new Map<Id, Messaging.SingleEmailMessage>();
            
            // Construir todos los emails primero
            for (Items_Cases__c item : items) {
                try {
                    Messaging.SingleEmailMessage email = construirEmailParaItem(item);
                    if (email != null) {
                        emails.add(email);
                        emailsPorItem.put(item.Id, email);
                        logs.add('Email construido para: ' + item.Id);
                    }
                } catch (Exception e) {
                    totalErrores++;
                    String errorMsg = 'Error construyendo email para ' + item.Id + ': ' + e.getMessage();
                    logs.add(errorMsg);
                    erroresPorItem.put(item.Id, errorMsg);
                }
            }
            
            // Enviar emails si hay alguno construido
            if (!emails.isEmpty()) {
                // Verificar límites
                Integer emailsDisponibles = Limits.getLimitEmailInvocations() - Limits.getEmailInvocations();
                if (emails.size() > emailsDisponibles) {
                    throw new BatchException('Límite de emails excedido. Disponibles: ' + 
                        emailsDisponibles + ', Necesarios: ' + emails.size());
                }
                
                logs.add('Enviando ' + emails.size() + ' emails...');
                List<Messaging.SendEmailResult> sendResults = Messaging.sendEmail(emails, false);
                
                // Procesar resultados
                Integer enviadosCount = 0;
                Integer errorEnvioCount = 0;
                
                for (Integer i = 0; i < sendResults.size(); i++) {
                    Messaging.SendEmailResult result = sendResults[i];
                    Id itemId = new List<Id>(emailsPorItem.keySet())[i];
                    
                    if (result.isSuccess()) {
                        enviadosCount++;
                        totalEnviados++;
                        logs.add('EMAIL ENVIADO: ' + itemId);
                    } else {
                        errorEnvioCount++;
                        totalErrores++;
                        
                        String errorMsg = 'Error enviando email para ' + itemId + ': ';
                        for (Messaging.SendEmailError error : result.getErrors()) {
                            errorMsg += error.getMessage() + '; ';
                        }
                        logs.add('ERROR ENVIO: ' + errorMsg);
                        erroresPorItem.put(itemId, errorMsg);
                        
                        // Actualizar el registro a estado de error de envío
                        actualizarEstadoError(itemId, errorMsg);
                    }
                }
                
                logs.add('Resultados envío: ' + enviadosCount + ' enviados, ' + errorEnvioCount + ' errores');
            }
            
        } catch (Exception e) {
            totalErrores++;
            String errorMsg = 'Error en enviarEmails: ' + e.getMessage();
            logs.add(errorMsg);
            System.debug(errorMsg);
        }
    }
    
    // ========== MÉTODO PARA ACTUALIZAR ESTADO DE ERROR ==========
    private void actualizarEstadoError(Id itemId, String errorMsg) {
        try {
            Items_Cases__c itemError = new Items_Cases__c(
                Id = itemId,
                Estatus__c = 'En proceso'
            );
            
            Database.SaveResult sr = Database.update(itemError, false);
            if (sr.isSuccess()) {
                logs.add('Estado actualizado a Error Envio para: ' + itemId);
            } else {
                logs.add('No se pudo actualizar estado de error para: ' + itemId);
            }
        } catch (Exception e) {
            logs.add('Error en actualizarEstadoError: ' + e.getMessage());
        }
    }
    
    global void finish(Database.BatchableContext bc) {
        logs.add('=== BATCH FINALIZADO === ' + System.now());
        logs.add('RESUMEN:');
        logs.add('- Total procesados: ' + totalProcesados);
        logs.add('- Total actualizados: ' + totalActualizados);
        logs.add('- Total emails enviados: ' + totalEnviados);
        logs.add('- Total errores: ' + totalErrores);
        
        // Imprimir logs en debug
        for (String log : logs) {
            System.debug('BATCH LOG: ' + log);
        }
        
        // Enviar resumen
        enviarResumenEjecucion(bc);
        
        // Si no se actualizó nada pero se procesó, hay un problema
        if (totalProcesados > 0 && totalActualizados == 0) {
            logs.add('¡ALERTA! Se procesaron ' + totalProcesados + ' registros pero NINGUNO se actualizó.');
            logs.add('Posibles causas:');
            logs.add('1. Validación de campos en el objeto Items_Cases__c');
            logs.add('2. Triggers bloqueando updates');
            logs.add('3. Reglas de validación (Validation Rules)');
            logs.add('4. Procesos (Process Builder/Flow)');
            logs.add('5. Falta de permisos de escritura');
        }
    }
    
    // ========== MÉTODOS AUXILIARES ==========
    
    private Messaging.SingleEmailMessage construirEmailParaItem(Items_Cases__c item) {
        try {
            // Obtener plantilla
            EmailTemplate template = obtenerPlantillaParaItem(item);
            if (template == null) {
                throw new BatchException('No se encontró plantilla para categoría: ' + item.Categorias__c);
            }
            
            // Obtener targetObjectId
            Id targetObjectId = obtenerTargetObjectId(item);
            
            // Construir email
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            
            if (targetObjectId != null) {
                email.setTemplateId(template.Id);
                email.setTargetObjectId(targetObjectId);
                email.setWhatId(item.Id);
            } else {
                email.setSubject(template.Subject);
                email.setHtmlBody(template.HtmlValue);
                email.setPlainTextBody(template.Body);
            }
            
            email.setToAddresses(new List<String>{item.Correo_electronico__c.trim()});
            
            if (String.isNotBlank(item.Correo_Copia__c)) {
                List<String> ccEmails = obtenerEmailsCCValidos(item.Correo_Copia__c);
                if (!ccEmails.isEmpty()) {
                    email.setCcAddresses(ccEmails);
                }
            }
            
            Id orgWideEmailId = obtenerOrgWideEmailId();
            if (orgWideEmailId != null) {
                email.setOrgWideEmailAddressId(orgWideEmailId);
            }
            
            email.setSaveAsActivity(false);
            
            List<Messaging.EmailFileAttachment> adjuntos = obtenerAdjuntosParaItem(item.Id);
            if (!adjuntos.isEmpty()) {
                email.setFileAttachments(adjuntos);
            }
            
            return email;
            
        } catch (Exception e) {
            throw new BatchException('Error construyendo email: ' + e.getMessage());
        }
    }
    
    private Boolean esEmailValido(String email) {
        if (String.isBlank(email)) return false;
        
        String emailRegex = '^[a-zA-Z0-9._|\\\\%#~`=?&/$^*!}{+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$';
        Pattern emailPattern = Pattern.compile(emailRegex);
        Matcher emailMatcher = emailPattern.matcher(email.trim());
        return emailMatcher.matches();
    }
    
    private List<String> obtenerEmailsCCValidos(String ccEmails) {
        List<String> emailsValidos = new List<String>();
        if (String.isNotBlank(ccEmails)) {
            String[] emails = ccEmails.split('[,;]');
            for (String email : emails) {
                String trimmedEmail = email.trim();
                if (esEmailValido(trimmedEmail)) {
                    emailsValidos.add(trimmedEmail);
                }
            }
        }
        return emailsValidos;
    }
    
    private Id obtenerTargetObjectId(Items_Cases__c item) {
        if (item.Contacto__c != null) return item.Contacto__c;
        if (item.Asegurado__c != null) {
            try {
                String sObjName = item.Asegurado__c.getSObjectType().getDescribe().getName();
                if (sObjName == 'Contact') return item.Asegurado__c;
            } catch (Exception e) {
                logs.add('Error obteniendo tipo de Asegurado: ' + e.getMessage());
            }
        }
        return null;
    }
    
    private EmailTemplate obtenerPlantillaParaItem(Items_Cases__c item) {
        try {
            Asigacion_de_plantilla__c asg = [
                SELECT ID_de_la_plantilla__c
                FROM Asigacion_de_plantilla__c
                WHERE Empresa__c = :item.Nombre_cuenta__c
                AND Categoria__c = :item.Categorias__c
                LIMIT 1
            ];
            
            if (asg != null && String.isNotBlank(asg.ID_de_la_plantilla__c)) {
                return [
                    SELECT Id, Subject, HtmlValue, Body
                    FROM EmailTemplate
                    WHERE DeveloperName = :asg.ID_de_la_plantilla__c
                    LIMIT 1
                ];
            }
        } catch (Exception e) {
            logs.add('Error obteniendo plantilla: ' + e.getMessage());
        }
        return null;
    }
    
    private Id obtenerOrgWideEmailId() {
        try {
            OrgWideEmailAddress[] addresses = [
                SELECT Id FROM OrgWideEmailAddress 
                WHERE Address = 'info@avanzaseguro.com' 
                LIMIT 1
            ];
            return addresses.isEmpty() ? null : addresses[0].Id;
        } catch (Exception e) {
            return null;
        }
    }
    
    private List<Messaging.EmailFileAttachment> obtenerAdjuntosParaItem(Id itemId) {
        // Implementar según tu lógica
        return new List<Messaging.EmailFileAttachment>();
    }
    
    private void enviarResumenEjecucion(Database.BatchableContext bc) {
        try {
            AsyncApexJob job = [SELECT Id, Status, NumberOfErrors, JobItemsProcessed,
                                TotalJobItems, CreatedBy.Email, CreatedDate, CompletedDate
                                FROM AsyncApexJob WHERE Id = :bc.getJobId()];
            
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[]{job.CreatedBy.Email});
            mail.setSubject('Batch Envío Emails - ' + job.Status);
            
            String body = 'Resumen ejecución batch:\n\n';
            body += 'Job ID: ' + job.Id + '\n';
            body += 'Estado: ' + job.Status + '\n';
            body += 'Inicio: ' + job.CreatedDate + '\n';
            body += 'Fin: ' + job.CompletedDate + '\n';
            body += 'Total items procesados: ' + totalProcesados + '\n';
            body += 'Registros actualizados: ' + totalActualizados + '\n';
            body += 'Emails enviados: ' + totalEnviados + '\n';
            body += 'Errores: ' + totalErrores + '\n\n';
            
            if (totalProcesados > 0 && totalActualizados == 0) {
                body += '¡IMPORTANTE! Se procesaron ' + totalProcesados + ' registros pero NINGUNO se actualizó.\n';
                body += 'Esto significa que los updates están fallando.\n';
                body += 'Revise logs y validaciones del objeto Items_Cases__c.\n\n';
            }
            
            if (!erroresPorItem.isEmpty()) {
                body += 'Errores por item (primeros 10):\n';
                Integer count = 0;
                for (Id itemId : erroresPorItem.keySet()) {
                    if (count < 10) {
                        body += '- ' + itemId + ': ' + erroresPorItem.get(itemId) + '\n';
                        count++;
                    }
                }
            }
            
            mail.setPlainTextBody(body);
            
            if (Limits.getEmailInvocations() < Limits.getLimitEmailInvocations()) {
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{mail});
            }
            
        } catch (Exception e) {
            System.debug('Error enviando resumen: ' + e.getMessage());
        }
    }
    
    public class BatchException extends Exception {}
}