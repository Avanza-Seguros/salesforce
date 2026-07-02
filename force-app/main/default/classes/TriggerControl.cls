/**
 *   @name: TriggerControl
 *   @version: 1.0
 *   @creation date: 02/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Utilidad de control de ejecución de triggers para evitar recursión y reprocesamiento. Mantiene flags de estado y un conjunto de items ya procesados en la transacción, con métodos para consultar, marcar y reiniciar el estado.
 */
public class TriggerControl {
	// Control para evitar recursión
	public static Boolean isExecuting = false;
	public static Boolean skipEmailTrigger = false;
	public static Set<Id> processedItems = new Set<Id>();

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Verifica si un item ya fue procesado en la transacción actual.
	 * @param itemId: Id del item a consultar.
	 * @return True si el item ya fue procesado.
	 */
	public static Boolean isAlreadyProcessed(Id itemId) {
		return processedItems.contains(itemId);
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Marca un item como procesado en la transacción actual.
	 * @param itemId: Id del item a marcar.
	 * @return void
	 */
	public static void markAsProcessed(Id itemId) {
		processedItems.add(itemId);
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Reinicia el estado de control para una nueva transacción: limpia flags de ejecución y el conjunto de items procesados.
	 * @return void
	 */
	public static void reset() {
		isExecuting = false;
		skipEmailTrigger = false;
		processedItems.clear();
		System.debug('🔄 TriggerControl reseteado');
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Indica si el trigger puede ejecutarse, es decir, si no está en ejecución y no está deshabilitado el envío por trigger.
	 * @return True si el trigger puede ejecutarse.
	 */
	public static Boolean canExecuteTrigger() {
		return !isExecuting && !skipEmailTrigger;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Limpia el conjunto de items procesados.
	 * @return void
	 */
	public static void clearProcessedItems() {
		processedItems.clear();
	}
}
