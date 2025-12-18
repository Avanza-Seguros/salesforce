public class QueueEnvioEmails implements Queueable, Database.AllowsCallouts {
    
    private Set<Id> itemIds;
    private static final Integer MAX_EMAILS_POR_QUEUE = 9;
    private static final Integer MAX_RECURSION_DEPTH = 3; // REDUCIDO de 5 a 3
    private Integer recursionLevel = 0;
    private String batchId; // Para tracking entre ejecuciones
    
    // Constructor principal
    public QueueEnvioEmails(Set<Id> itemIds) {
        this.itemIds = (itemIds != null) ? new Set<Id>(itemIds) : new Set<Id>();
        this.batchId = generateBatchId();
    }
    
    // Constructor con nivel de recursión (para uso interno)
    public QueueEnvioEmails(Set<Id> itemIds, Integer recursionLevel, String batchId) {
        this.itemIds = (itemIds != null) ? new Set<Id>(itemIds) : new Set<Id>();
        this.recursionLevel = recursionLevel;
        this.batchId = batchId;
    }
    
    public void execute(QueueableContext qc) {
        System.debug('=== QueueEnvioEmails.execute() iniciado ===');
        System.debug('Batch ID: ' + batchId);
        System.debug('Nivel recursión: ' + recursionLevel);
        System.debug('Items recibidos: ' + (itemIds != null ? itemIds.size() : 0));
        
        // Validación básica
        if (itemIds == null || itemIds.isEmpty()) {
            System.debug('No hay items para procesar, finalizando.');
            return;
        }
        
        // VERIFICACIÓN CRÍTICA: Evitar recursión infinita
        if (recursionLevel >= MAX_RECURSION_DEPTH) {
            System.debug('Límite de recursión alcanzado (' + MAX_RECURSION_DEPTH + '), finalizando.');
            
            // Marcar items pendientes como error para evitar reprocesamiento
            marcarItemsComoError(itemIds, 'Límite recursión alcanzado');
            return;
        }
        
        // Verificar límites de envío de emails
        if (!canSendEmails()) {
            System.debug('No se pueden enviar más emails, programando reintento.');
            programarReintento(itemIds, recursionLevel, batchId);
            return;
        }
        
        try {
            // Desactivar triggers si es necesario
            Boolean originalSkipValue = EmailContextControl.skipEmails;
            EmailContextControl.skipEmails = true;
            
            // Procesar items
            ProcesamientoResultado resultado = procesarItems();
            
            // Restaurar valor original
            EmailContextControl.skipEmails = originalSkipValue;
            
            // VERIFICACIÓN IMPORTANTE: ¿Quedaron items pendientes?
            if (!resultado.remainingIds.isEmpty()) {
                System.debug('Items pendientes después de procesar: ' + resultado.remainingIds.size());
                
                // ¿Son los mismos items? Podría ser loop infinito
                if (sonLosMismosItems(itemIds, resultado.remainingIds)) {
                    System.debug('¡POSIBLE LOOP INFINITO! Los mismos items no se procesaron.');
                    marcarItemsComoError(resultado.remainingIds, 'No procesable - Loop detectado');
                    return; // NO reencolar
                }
                
                // Reencolar solo si hay progreso
                if (resultado.processedIds.size() > 0) {
                    System.debug('Reencolando items pendientes...');
                    reencolarItems(resultado.remainingIds, recursionLevel + 1, batchId);
                } else {
                    System.debug('No hubo progreso, marcando items como error.');
                    marcarItemsComoError(resultado.remainingIds, 'Sin progreso después de ' + recursionLevel + ' intentos');
                }
            } else {
                System.debug('¡Todos los items procesados exitosamente!');
            }
            
            // Registrar éxito
            logExito(resultado, batchId);
            
        } catch (Exception e) {
            System.debug('Error en execute(): ' + e.getMessage() + '\n' + e.getStackTraceString());
            
            // Reintentar con delay en caso de error específico
            if (shouldRetry(e)) {
                programarReintento(itemIds, recursionLevel, batchId);
            } else {
                // Marcar como error fatal
                marcarItemsComoError(itemIds, 'Error fatal: ' + e.getMessage());
            }
        }
    }
    
    // Método para verificar si son los mismos items (evitar loops)
    private Boolean sonLosMismosItems(Set<Id> originalIds, Set<Id> remainingIds) {
        if (originalIds.size() != remainingIds.size()) return false;
        
        for (Id itemId : originalIds) {
            if (!remainingIds.contains(itemId)) {
                return false;
            }
        }
        return true;
    }
    
    // Método para reencolar de forma segura
    private void reencolarItems(Set<Id> ids, Integer nextLevel, String batchId) {
        // Verificar que no estemos reencolando los mismos items demasiadas veces
        if (nextLevel >= MAX_RECURSION_DEPTH) {
            System.debug('No se puede reencolar - Nivel máximo alcanzado.');
            marcarItemsComoError(ids, 'Máximo nivel de reintentos alcanzado');
            return;
        }
        
        // Verificar límites de Queueable
        Integer currentQueueableJobs = Limits.getQueueableJobs();
        Integer queueableLimit = Limits.getLimitQueueableJobs();
        
        if (currentQueueableJobs >= queueableLimit) {
            System.debug('Límite de Queueable jobs alcanzado, programando para más tarde.');
            programarReintento(ids, nextLevel, batchId);
            return;
        }
        
        System.debug('Reencolando ' + ids.size() + ' items (nivel ' + nextLevel + ')');
        System.enqueueJob(new QueueEnvioEmails(ids, nextLevel, batchId));
    }
    
    // Método para programar reintento (evitar recursión inmediata)
    private void programarReintento(Set<Id> ids, Integer level, String batchId) {
        // Usar Scheduled Apex en lugar de Queueable inmediato
        String jobName = 'QueueEnvioRetry_' + batchId + '_' + level + '_' + DateTime.now().getTime();
        
        // Programar para 2-5 minutos en el futuro
        Integer minutesDelay = 2 + (level * 1); // Incrementar delay con cada nivel
        
        System.debug('Programando reintento en ' + minutesDelay + ' minutos: ' + jobName);
        
        try {
            // Crear clase Schedule si no existe
            Type scheduleType = Type.forName('QueueEnvioScheduler');
            if (scheduleType != null) {
                Schedulable scheduleJob = (Schedulable) scheduleType.newInstance();
                String cronExp = getCronExpression(minutesDelay);
                System.schedule(jobName, cronExp, scheduleJob);
            }
        } catch (Exception e) {
            System.debug('Error programando reintento: ' + e.getMessage());
            // Último recurso: marcar como error
            marcarItemsComoError(ids, 'Error programando reintento: ' + e.getMessage());
        }
    }
    
    private String getCronExpression(Integer minutesFromNow) {
        DateTime now = DateTime.now().addMinutes(minutesFromNow);
        return '' + now.second() + ' ' + now.minute() + ' ' + now.hour() + ' ' + now.day() + ' ' + now.month() + ' ? ' + now.year();
    }
    
    // Generar ID único para el batch
    private String generateBatchId() {
        return 'BATCH_' + DateTime.now().getTime() + '_' + Crypto.getRandomInteger();
    }
    
    // Clase interna para resultados (igual que antes, pero mejorada)
    private class ProcesamientoResultado {
        public Set<Id> processedIds = new Set<Id>();
        public Set<Id> remainingIds = new Set<Id>();
        public Integer emailsEnviados = 0;
        public Integer errores = 0;
        public List<String> erroresDetallados = new List<String>();
        public Boolean huboProgreso = false;
    }
    
    private ProcesamientoResultado procesarItems() {
        ProcesamientoResultado resultado = new ProcesamientoResultado();
        
        System.debug('Consultando items válidos...');
        List<Items_Cases__c> items = consultarItemsValidos();
        System.debug('Items válidos encontrados: ' + items.size());
        
        if (items.isEmpty()) {
            System.debug('No hay items válidos para procesar.');
            resultado.remainingIds = new Set<Id>(itemIds); // Todos pendientes
            return resultado;
        }
        
        // Construir y enviar emails
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        Map<Id, Items_Cases__c> itemsParaEmail = new Map<Id, Items_Cases__c>();
        
        for (Items_Cases__c item : items) {
            try {
                Messaging.SingleEmailMessage email = construirEmailParaItem(item);
                if (email != null) {
                    emails.add(email);
                    itemsParaEmail.put(item.Id, item);
                    resultado.processedIds.add(item.Id);
                    resultado.huboProgreso = true;
                } else {
                    resultado.errores++;
                    resultado.erroresDetallados.add('No se pudo construir email para item: ' + item.Id);
                }
            } catch (Exception e) {
                resultado.errores++;
                resultado.erroresDetallados.add('Error construyendo email para ' + item.Id + ': ' + e.getMessage());
                System.debug('Error procesando item ' + item.Id + ': ' + e.getMessage());
            }
        }
        
        // Enviar emails si hay alguno
        if (!emails.isEmpty()) {
            resultado.emailsEnviados = enviarEmails(emails, itemsParaEmail);
        }
        
        // Preparar remaining IDs (SOLO los que NO fueron procesados)
        resultado.remainingIds = new Set<Id>(itemIds);
        resultado.remainingIds.removeAll(resultado.processedIds);
        
        // Marcar como procesados SI Y SOLO SI el email se envió exitosamente
        if (!resultado.processedIds.isEmpty()) {
            marcarItemsComoProcesados(resultado.processedIds);
        }
        
        return resultado;
    }
    
    private List<Items_Cases__c> consultarItemsValidos() {
        // IMPORTANTE: Excluir items que ya tienen error
        return [
            SELECT Id, Name, Correo_electronico__c, Correo_Copia__c,
                   Asegurado__c, Nombre_cuenta__c, Categorias__c,
                   Contacto__c, Email_Enviado__c, Estatus__c
            FROM Items_Cases__c
            WHERE Id IN :itemIds
            AND Correo_electronico__c != null
            AND (Asegurado__c != null OR Contacto__c != null)
            AND Email_Enviado__c = false
            AND Estatus__c != 'Error'
            LIMIT :MAX_EMAILS_POR_QUEUE
        ];
    }
    
    private Messaging.SingleEmailMessage construirEmailParaItem(Items_Cases__c item) {
        try {
            return EnvioPlantillas.EnvioEmailMasivo(item.Id);
        } catch (Exception e) {
            System.debug('Error llamando a EnvioPlantillas para item ' + item.Id + ': ' + e.getMessage());
            
            // Incrementar contador de reintentos
            incrementarReintentos(item.Id);
            
            throw new QueueEnvioException('Error construyendo email: ' + e.getMessage());
        }
    }
    
    private void incrementarReintentos(Id itemId) {
        try {
            Items_Cases__c item = new Items_Cases__c(
                Id = itemId
            );
            update item;
        } catch (Exception e) {
            System.debug('Error incrementando reintentos: ' + e.getMessage());
        }
    }
    
    private Integer enviarEmails(List<Messaging.SingleEmailMessage> emails, Map<Id, Items_Cases__c> itemsMap) {
        if (emails.isEmpty()) return 0;
        
        System.debug('Intentando enviar ' + emails.size() + ' emails...');
        
        // Verificar límites
        if (Limits.getEmailInvocations() + emails.size() > Limits.getLimitEmailInvocations()) {
            throw new QueueEnvioException('Límite de emails excedido. Disponibles: ' + 
                (Limits.getLimitEmailInvocations() - Limits.getEmailInvocations()));
        }
        
        try {
            List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails, false);
            
            Integer enviadosExitosos = 0;
            Set<Id> itemsConError = new Set<Id>();
            
            // Procesar resultados
            Integer index = 0;
            for (Messaging.SendEmailResult result : results) {
                Id itemId = new List<Id>(itemsMap.keySet())[index];
                
                if (result.isSuccess()) {
                    enviadosExitosos++;
                    System.debug('Email enviado exitosamente para item: ' + itemId);
                } else {
                    itemsConError.add(itemId);
                    String errorMsg = 'Error enviando email para ' + itemId + ': ';
                    for (Messaging.SendEmailError error : result.getErrors()) {
                        errorMsg += error.getMessage() + '; ';
                    }
                    System.debug(errorMsg);
                    
                    // Incrementar reintentos para este item
                    incrementarReintentos(itemId);
                }
                index++;
            }
            
            // Remover items con error del procesamiento exitoso
            if (!itemsConError.isEmpty()) {
                for (Id errorId : itemsConError) {
                    itemsMap.remove(errorId);
                    // Estos items permanecerán en remainingIds
                }
            }
            
            return enviadosExitosos;
            
        } catch (Exception e) {
            System.debug('Error en sendEmail: ' + e.getMessage());
            throw new QueueEnvioException('Error enviando emails: ' + e.getMessage());
        }
    }
    
    private void marcarItemsComoProcesados(Set<Id> processedIds) {
        if (processedIds.isEmpty()) return;
        
        try {
            List<Items_Cases__c> itemsToUpdate = new List<Items_Cases__c>();
            for (Id itemId : processedIds) {
                itemsToUpdate.add(new Items_Cases__c(
                    Id = itemId,
                    Email_Enviado__c = true
                ));
            }
            
            Database.update(itemsToUpdate, false);
            
        } catch (Exception e) {
            System.debug('Error marcando items como procesados: ' + e.getMessage());
        }
    }
    
    private void marcarItemsComoError(Set<Id> errorIds, String motivo) {
        if (errorIds.isEmpty()) return;
        
        try {
            List<Items_Cases__c> itemsToUpdate = new List<Items_Cases__c>();
            for (Id itemId : errorIds) {
                itemsToUpdate.add(new Items_Cases__c(
                    Id = itemId,
                    Estatus__c = 'Error'
                ));
            }
            
            Database.update(itemsToUpdate, false);
            System.debug('Marcados ' + errorIds.size() + ' items como error: ' + motivo);
            
        } catch (Exception e) {
            System.debug('Error marcando items como error: ' + e.getMessage());
        }
    }
    
    private Boolean canSendEmails() {
        Integer emailsDisponibles = Limits.getLimitEmailInvocations() - Limits.getEmailInvocations();
        return emailsDisponibles >= 1;
    }
    
    private Boolean shouldRetry(Exception e) {
        String errorMessage = e.getMessage();
        
        // Solo reintentar errores transitorios
        return (errorMessage.contains('UNABLE_TO_LOCK_ROW') ||
                errorMessage.contains('LIMIT_EXCEEDED') ||
                errorMessage.contains('TIMEOUT')) &&
               recursionLevel < 2;
    }
    
    private void logExito(ProcesamientoResultado resultado, String batchId) {
        System.debug('=== PROCESAMIENTO EXITOSO ===');
        System.debug('Batch ID: ' + batchId);
        System.debug('Emails enviados: ' + resultado.emailsEnviados);
        System.debug('Items procesados: ' + resultado.processedIds.size());
        System.debug('Errores: ' + resultado.errores);
        System.debug('Items pendientes: ' + resultado.remainingIds.size());
    }
    
    // Clase de excepción personalizada
    public class QueueEnvioException extends Exception {}
}