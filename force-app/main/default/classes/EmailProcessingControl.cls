public class EmailProcessingControl {
    // =============================================
    // 🗄️ CACHE PARA SEGUIMIENTO DE EMAILS ENVIADOS
    // =============================================
    
    // Cache para emails marcados para envío (en esta transacción)
    private static Set<Id> markedForSending = new Set<Id>();

    // Cache estático para esta transacción
    private static Set<Id> sentEmailItems = new Set<Id>();
    
    // Cache entre transacciones (usando Platform Cache si disponible)
    private static Map<Id, Boolean> sentEmailCache = new Map<Id, Boolean>();
    
    // =============================================
    // 📋 MÉTODOS PRINCIPALES
    // =============================================
    

    /**
     * Marcar como PENDIENTE DE ENVÍO (llamado desde el trigger)
     * Esto evita que el mismo registro sea procesado múltiples veces
     */
    public static void markForSending(Id itemId) {
        if (itemId == null) {
            System.debug('⚠️ Intentando marcar null como pendiente de envío');
            return;
        }
        
        markedForSending.add(itemId);
        System.debug('📝 Marcado como PENDIENTE DE ENVÍO: ' + itemId);
        
        // Opcional: Marcar campo en BD si existe
        updateEmailSendingStatus(itemId, 'Pending');
    }

    /**
     * Verificar si ya se envió email para este item
     * Considera el contexto y configuraciones de EmailContextControl
     */
    public static Boolean wasEmailSent(Id itemId) {
        System.debug('🔍 Verificando si email ya fue enviado para item: ' + itemId);

        // Si los emails están desactivados globalmente, considerar como "ya enviado"
        if (EmailContextControl.skipEmails) {
            System.debug('🔕 Emails desactivados globalmente, considerando como ya enviado');
            return true;
        }
        
        // Verificar en cache de esta transacción
        if (sentEmailItems.contains(itemId)) {
            System.debug('✅ Email ya enviado en esta transacción para item: ' + itemId);
            return true;
        }
        
        // Verificar en cache persistente
        if (sentEmailCache.containsKey(itemId)) {
            Boolean sent = sentEmailCache.get(itemId);
            System.debug('📋 Cache: Email ' + (sent ? 'ya enviado' : 'no enviado') + ' para item: ' + itemId);
            return sent;
        }
        
        // Opcional: Verificar en base de datos si hay campo de tracking
        try {
            Items_Cases__c item = [SELECT Id, Email_Enviado__c FROM Items_Cases__c WHERE Id = :itemId LIMIT 1];

            if (item.Email_Enviado__c != null && item.Email_Enviado__c) {
                sentEmailCache.put(itemId, true);
                System.debug('💾 BD: Email ya enviado para item: ' + itemId);
                return true;
            }
        } catch (Exception e) {
            System.debug('⚠️ No se pudo verificar campo Email_Enviado__c: ' + e.getMessage());
        }
        
        System.debug('🆕 Email NO enviado aún para item: ' + itemId);
        return false;
    }

    /**
     * Verificar si el item ya está marcado para envío (evita duplicados en la misma transacción)
     */
    public static Boolean isMarkedForSending(Id itemId) {
        return markedForSending.contains(itemId);
    }
    
    /**
     * Marcar que se envió (o se va a enviar) email para este item
     */
    public static void markAsSent(Id itemId) {
        if (itemId == null) {
            System.debug('⚠️ Intentando marcar null como enviado');
            return;
        }
        
        sentEmailItems.add(itemId);
        sentEmailCache.put(itemId, true);
        
        System.debug('✅ Marcado como enviado/para enviar: ' + itemId);

        // Actualizar cache de pendientes
        markedForSending.remove(itemId);
        
        // Opcional: Actualizar campo en base de datos
        updateEmailSentField(itemId, true);
        updateEmailSendingStatus(itemId, 'Sent');
    }

    /**
     * Marcar como FALLIDO (para posibles reintentos)
     */
    public static void markAsFailed(Id itemId) {
        if (itemId == null) return;
        
        // Limpiar estado de pendiente
        markedForSending.remove(itemId);
        
        System.debug('❌ Marcado como FALLIDO: ' + itemId);
        
        // Opcional: Actualizar campo de error en BD
        updateEmailSendingStatus(itemId, 'Failed');
    }
    
    /**
     * Marcar que NO se ha enviado email (para reintentos)
     */
    public static void markAsNotSent(Id itemId) {
        if (itemId == null) return;
        
        sentEmailItems.remove(itemId);
        sentEmailCache.put(itemId, false);
        
        System.debug('🔄 Marcado como NO enviado: ' + itemId);
        
        // Opcional: Actualizar campo en base de datos
        updateEmailSentField(itemId, false);
    }
    
    /**
     * Verificar si se puede enviar email considerando todos los controles
     */
    public static Boolean canSendEmail(Id itemId, String context) {
        System.debug('🔍 Verificando si se puede enviar email:');
        System.debug('  Item: ' + itemId);
        System.debug('  Contexto: ' + context);
        
        // 1. Verificar controles de contexto
        Boolean contextAllowed = true;
        if (context == 'TRIGGER') {
            contextAllowed = EmailContextControl.canTriggerSend();
        } else if (context == 'BATCH') {
            contextAllowed = EmailContextControl.canBatchSend();
        }

        System.debug('  Contexto permitido: ' + contextAllowed);

        if (!contextAllowed) {
            System.debug('🚫 Contexto no permitido para envío');
            return false;
        }
        
        // 2. Verificar si ya está marcado para envío en esta transacción
        if (isMarkedForSending(itemId)) {
            System.debug('🚫 Ya marcado para envío en esta transacción');
            return false;
        }
        
        // 3. Verificar si ya fue enviado exitosamente
        if (wasEmailSent(itemId)) {
            System.debug('🚫 Email ya enviado para este item');
            return false;
        }
        
        System.debug('✅ Se puede enviar email');
        return true;
    }
    
    // =============================================
    // 🔧 MÉTODOS AUXILIARES
    // =============================================
    
    /**
     * Actualizar campo en BD (si existe el campo Email_Enviado__c)
     */
    private static void updateEmailSentField(Id itemId, Boolean sent) {
        try {
            // Verificar si el campo existe en el schema
            Schema.SObjectField emailSentField = Items_Cases__c.Email_Enviado__c;
            if (emailSentField != null) {
                Items_Cases__c item = new Items_Cases__c(
                    Id = itemId,
                    Email_Enviado__c = sent
                );
                update item;
                System.debug('💾 Actualizado campo Email_Enviado__c a ' + sent + ' para item: ' + itemId);
            }
        } catch (Exception e) {
            System.debug('⚠️ No se pudo actualizar campo Email_Enviado__c: ' + e.getMessage());
            // No es crítico si falla, seguimos con el cache
        }
    }

    /**
     * Actualizar estado de envío (para tracking)
     */
    private static void updateEmailSendingStatus(Id itemId, String status) {
        try {
            // Si tienes un campo para tracking del estado
            Schema.SObjectField statusField = Items_Cases__c.Estado_Envio_Email__c;
            if (statusField != null) {
                Items_Cases__c item = new Items_Cases__c(
                    Id = itemId,
                    Estado_Envio_Email__c = status
                );
                update item;
                System.debug('💾 Estado de envío actualizado a ' + status + ' para item: ' + itemId);
            }
        } catch (Exception e) {
            System.debug('⚠️ No se pudo actualizar estado de envío: ' + e.getMessage());
        }
    }
    
    /**
     * Limpiar cache (útil para tests y reinicios)
     */
    public static void clearCache() {
        markedForSending.clear();
        sentEmailItems.clear();
        sentEmailCache.clear();
        System.debug('🧹 Cache de EmailProcessingControl limpiado');
    }
    
    /**
     * Verificar estado actual de un item
     */
    public static String getStatus(Id itemId) {
        if (itemId == null) return 'ITEM_NULL';
        
        if (EmailContextControl.skipEmails) return 'EMAILS_DISABLED_GLOBALLY';
        if (markedForSending.contains(itemId)) return 'MARKED_FOR_SENDING';
        if (sentEmailItems.contains(itemId)) return 'SENT_IN_CURRENT_TRANSACTION';
        if (sentEmailCache.containsKey(itemId)) {
            return sentEmailCache.get(itemId) ? 'SENT_IN_CACHE' : 'NOT_SENT_IN_CACHE';
        }
        
        try {
            Items_Cases__c item = [SELECT Id, Email_Enviado__c FROM Items_Cases__c WHERE Id = :itemId LIMIT 1];
            if (item.Email_Enviado__c != null && item.Email_Enviado__c) {
                return 'SENT_IN_DATABASE';
            }
        } catch (Exception e) {
            // Ignorar
        }
        
        return 'NOT_SENT';
    }
    
    /**
     * Debug: Mostrar estado de múltiples items
     */
    public static void debugItemsStatus(List<Id> itemIds) {
        System.debug('=== DEBUG EMAIL PROCESSING STATUS ===');
        System.debug('Total items: ' + itemIds.size());
        
        for (Id itemId : itemIds) {
            String status = getStatus(itemId);
            System.debug('Item: ' + itemId + ' -> ' + status);
        }
        
        System.debug('Context Controls:');
        System.debug('  skipEmails: ' + EmailContextControl.skipEmails);
        System.debug('  allowTriggerEmails: ' + EmailContextControl.allowTriggerEmails);
        System.debug('  allowBatchEmails: ' + EmailContextControl.allowBatchEmails);
        System.debug('Marked for sending: ' + markedForSending.size() + ' items');
        System.debug('Sent in transaction: ' + sentEmailItems.size() + ' items');
    }

    /**
     * Verificar si hay items pendientes de envío
     */
    public static Boolean hasPendingItems() {
        return !markedForSending.isEmpty();
    }
    
    /**
     * Obtener lista de IDs pendientes de envío
     */
    public static Set<Id> getPendingItems() {
        return new Set<Id>(markedForSending);
    }
    // =============================================================================

    /**
     * Marcar varios items como ENVIADOS en una sola operación DML.
     *
     * Reemplaza el patrón:
     *     for (Id id : ids) EmailProcessingControl.markAsSent(id);
     * (que consumía 2 DML por cada item: Email_Enviado__c + Estado_Envio_Email__c)
     *
     * Por:
     *     EmailProcessingControl.markAsSentBulk(ids);
     * (que consume 1 sola DML para TODOS los items, sin importar la cantidad)
     *
     * Mantiene además los caches en memoria sincronizados igual que markAsSent.
     */
    public static void markAsSentBulk(Set<Id> itemIds) {
        if (itemIds == null || itemIds.isEmpty()) {
            System.debug('⚠️ markAsSentBulk recibió un set vacío');
            return;
        }

        // 1) Actualizar caches en memoria (mismos que usa markAsSent)
        sentEmailItems.addAll(itemIds);
        for (Id id : itemIds) {
            sentEmailCache.put(id, true);
            markedForSending.remove(id);
        }

        // 2) Construir UN SOLO registro por item con AMBOS campos a la vez.
        //    Esto colapsa lo que antes eran 2 updates por item en 1 update masivo.
        List<Items_Cases__c> updates = new List<Items_Cases__c>();
        for (Id id : itemIds) {
            updates.add(new Items_Cases__c(
                Id = id,
                Email_Enviado__c = true,
                Estado_Envio_Email__c = 'Sent'
            ));
        }

        try {
            update updates; // 1 sola operación DML
            System.debug('✅ Bulk: ' + updates.size() + ' items marcados como Sent (1 DML)');
        } catch (DmlException e) {
            System.debug('⚠️ Error en markAsSentBulk: ' + e.getMessage());

            // Fallback: si el update masivo falla por algún registro problemático,
            // intentamos uno por uno los que sí puedan pasar. Esto consume más DML
            // pero solo se ejecuta como excepción, no en el camino normal.
            for (Items_Cases__c rec : updates) {
                try {
                    update rec;
                } catch (Exception ex) {
                    System.debug('⚠️ Falló item ' + rec.Id + ': ' + ex.getMessage());
                }
            }
        }
    }

    /**
     * Marcar varios items como FALLIDOS en una sola operación DML.
     * Equivalente bulk de markAsFailed.
     */
    public static void markAsFailedBulk(Set<Id> itemIds) {
        if (itemIds == null || itemIds.isEmpty()) {
            System.debug('⚠️ markAsFailedBulk recibió un set vacío');
            return;
        }

        // Limpiar estado de pendiente en memoria
        for (Id id : itemIds) {
            markedForSending.remove(id);
        }

        List<Items_Cases__c> updates = new List<Items_Cases__c>();
        for (Id id : itemIds) {
            updates.add(new Items_Cases__c(
                Id = id,
                Estado_Envio_Email__c = 'Failed'
            ));
        }

        try {
            update updates; // 1 sola operación DML
            System.debug('❌ Bulk: ' + updates.size() + ' items marcados como Failed (1 DML)');
        } catch (DmlException e) {
            System.debug('⚠️ Error en markAsFailedBulk: ' + e.getMessage());
        }
    }

    /**
     * (Opcional) Versión bulk de markForSending, por si se requiere desde el
     * trigger cuando procesa muchos registros a la vez.
     */
    public static void markForSendingBulk(Set<Id> itemIds) {
        if (itemIds == null || itemIds.isEmpty()) return;

        markedForSending.addAll(itemIds);

        List<Items_Cases__c> updates = new List<Items_Cases__c>();
        for (Id id : itemIds) {
            updates.add(new Items_Cases__c(
                Id = id,
                Estado_Envio_Email__c = 'Pending'
            ));
        }

        try {
            update updates; // 1 sola operación DML
            System.debug('📝 Bulk: ' + updates.size() + ' items marcados como Pending (1 DML)');
        } catch (DmlException e) {
            System.debug('⚠️ Error en markForSendingBulk: ' + e.getMessage());
        }
    }
}