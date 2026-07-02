/**
 *   @name: EmailProcessingControl
 *   @version: 1.0
 *   @creation date: 02/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Controla el seguimiento y la deduplicacion del envio de emails para registros Items_Cases__c. Mantiene caches en memoria (por transaccion y persistentes) del estado de envio, expone metodos para marcar items como pendientes, enviados, fallidos o no enviados (incluyendo versiones bulk), y valida si un email puede enviarse segun el contexto y los controles de EmailContextControl.
 */
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
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Marca un item como PENDIENTE DE ENVIO (llamado desde el trigger) para evitar que el mismo registro sea procesado multiples veces, agregandolo al cache en memoria y actualizando su estado en BD.
	 * @param itemId: Id del registro Items_Cases__c a marcar como pendiente
	 * @return void
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
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Verifica si ya se envio email para un item, considerando el flag global de EmailContextControl, los caches de transaccion y persistente, y finalmente el campo Email_Enviado__c en base de datos.
	 * @param itemId: Id del registro Items_Cases__c a verificar
	 * @return true si el email ya fue enviado (o los emails estan desactivados globalmente); false en caso contrario
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
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Verifica si el item ya esta marcado para envio en la transaccion actual, evitando duplicados.
	 * @param itemId: Id del registro Items_Cases__c a verificar
	 * @return true si el item ya esta marcado para envio; false en caso contrario
	 */
	public static Boolean isMarkedForSending(Id itemId) {
		return markedForSending.contains(itemId);
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Marca que se envio (o se va a enviar) email para el item, actualizando los caches en memoria, quitandolo de pendientes y actualizando los campos de BD.
	 * @param itemId: Id del registro Items_Cases__c a marcar como enviado
	 * @return void
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
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Marca un item como FALLIDO (para posibles reintentos), limpiando su estado de pendiente en memoria y actualizando su estado en BD.
	 * @param itemId: Id del registro Items_Cases__c a marcar como fallido
	 * @return void
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
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Marca que NO se ha enviado email para el item (para reintentos), actualizando los caches en memoria y el campo de BD.
	 * @param itemId: Id del registro Items_Cases__c a marcar como no enviado
	 * @return void
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
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Verifica si se puede enviar email para un item considerando los controles de contexto (TRIGGER/BATCH) de EmailContextControl, si ya esta marcado para envio y si ya fue enviado.
	 * @param itemId: Id del registro Items_Cases__c a evaluar
	 * @param context: Contexto de ejecucion ('TRIGGER' o 'BATCH') usado para elegir el control de contexto aplicable
	 * @return true si el email puede enviarse; false en caso contrario
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
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Actualiza el campo Email_Enviado__c en BD (si el campo existe en el schema) para el item indicado. Los errores se registran pero no se propagan.
	 * @param itemId: Id del registro Items_Cases__c a actualizar
	 * @param sent: Valor a asignar al campo Email_Enviado__c
	 * @return void
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
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Actualiza el campo Estado_Envio_Email__c en BD (si el campo existe en el schema) con el estado de envio indicado. Los errores se registran pero no se propagan.
	 * @param itemId: Id del registro Items_Cases__c a actualizar
	 * @param status: Estado de envio a asignar (por ejemplo 'Pending', 'Sent', 'Failed')
	 * @return void
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
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Limpia todos los caches en memoria (pendientes, enviados en transaccion y cache persistente). Util para tests y reinicios.
	 * @return void
	 */
	public static void clearCache() {
		markedForSending.clear();
		sentEmailItems.clear();
		sentEmailCache.clear();
		System.debug('🧹 Cache de EmailProcessingControl limpiado');
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve el estado actual de un item evaluando el flag global, los caches en memoria y persistente, y finalmente la base de datos.
	 * @param itemId: Id del registro Items_Cases__c a consultar
	 * @return Cadena con el estado del item (por ejemplo 'ITEM_NULL', 'EMAILS_DISABLED_GLOBALLY', 'MARKED_FOR_SENDING', 'SENT_IN_CURRENT_TRANSACTION', 'SENT_IN_CACHE', 'NOT_SENT_IN_CACHE', 'SENT_IN_DATABASE', 'NOT_SENT')
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
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Muestra en debug el estado de multiples items junto con los controles de contexto y los tamanos de los caches en memoria. Herramienta de diagnostico.
	 * @param itemIds: Lista de Ids de Items_Cases__c cuyo estado se desea inspeccionar
	 * @return void
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
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Indica si hay items pendientes de envio en la transaccion actual.
	 * @return true si el cache de pendientes no esta vacio; false en caso contrario
	 */
	public static Boolean hasPendingItems() {
		return !markedForSending.isEmpty();
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve una copia del conjunto de Ids pendientes de envio en la transaccion actual.
	 * @return Set de Ids de items marcados como pendientes
	 */
	public static Set<Id> getPendingItems() {
		return new Set<Id>(markedForSending);
	}
	// =============================================================================

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Marca varios items como ENVIADOS en una sola operacion DML, sincronizando los caches en memoria y actualizando Email_Enviado__c y Estado_Envio_Email__c. Reemplaza el patron de llamar markAsSent por cada item (2 DML/item) por un unico update masivo; incluye un fallback item por item si el update masivo falla.
	 * @param itemIds: Conjunto de Ids de Items_Cases__c a marcar como enviados
	 * @return void
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
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Marca varios items como FALLIDOS en una sola operacion DML, limpiando su estado de pendiente en memoria y actualizando Estado_Envio_Email__c. Equivalente bulk de markAsFailed.
	 * @param itemIds: Conjunto de Ids de Items_Cases__c a marcar como fallidos
	 * @return void
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
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Version bulk (opcional) de markForSending, para marcar muchos items como PENDIENTES desde el trigger en una sola operacion DML, actualizando el cache en memoria y Estado_Envio_Email__c.
	 * @param itemIds: Conjunto de Ids de Items_Cases__c a marcar como pendientes
	 * @return void
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
