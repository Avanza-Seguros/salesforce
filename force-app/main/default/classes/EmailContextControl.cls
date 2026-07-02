/**
 *   @name: EmailContextControl
 *   @version: 1.0
 *   @creation date: 02/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Control de contexto para el envío de correos. Expone flags estáticos para habilitar o deshabilitar el envío global, desde trigger o desde batch, y helpers para consultar si se permite enviar en cada contexto, contemplando el modo de prueba.
 */
public class EmailContextControl {

	// 🔕 Apaga TODOS los correos (tests / reprocesos)
	public static Boolean skipEmails = false;

	// 🚦 Control por contexto
	public static Boolean allowTriggerEmails = true;
	public static Boolean allowBatchEmails   = false;
	public static Boolean isTestMode = false;

	/* ==========================
	   HELPERS
	   ========================== */

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Indica si se permite el envío de correos desde el contexto de trigger, considerando el apagado global y el flag de triggers.
	 * @return True si se permite enviar desde trigger.
	 */
	public static Boolean canTriggerSend() {
		return !skipEmails && allowTriggerEmails;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Indica si se permite el envío de correos desde el contexto batch usando el contexto por defecto.
	 * @return True si se permite enviar desde batch.
	 */
	public static Boolean canBatchSend() {
		return canBatchSend('default');
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Indica si se permite el envío de correos desde el contexto batch para un contexto dado. En modo de prueba respeta el flag allowBatchEmails; fuera de pruebas permite el envío.
	 * @param context: Nombre del contexto de envío evaluado.
	 * @return True si se permite enviar desde batch en el contexto indicado.
	 */
	public static Boolean canBatchSend(String context) {
		if (isTestMode) {
			return allowBatchEmails;
		}
		// Lógica real aquí
		return true;
	}

	/* ==========================
	   TEST MODE
	   ========================== */

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Activa o desactiva el modo de prueba, que altera la lógica de canBatchSend.
	 * @param testMode: True para activar el modo de prueba, false para desactivarlo.
	 * @return void
	 */
	public static void setTestMode(Boolean testMode) {
		isTestMode = testMode;
	}
}
