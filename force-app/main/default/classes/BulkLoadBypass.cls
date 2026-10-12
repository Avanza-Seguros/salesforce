/**
 *   @name: BulkLoadBypass
 *   @version: 1.0
 *   @creation date: 11/10/2026
 *   @author: Javier Torres - Volestra
 *   @description: Interruptor de la carga masiva. Quien tiene el permiso personalizado
 *                 Carga_Masiva_Handle carga polizas, planes y cuotas tal como vienen de la
 *                 fuente, sin que los triggers regeneren planes ni creen cuotas: la carga ya
 *                 trae las cuotas de los recibos y el plan que les corresponde. Solo afecta a
 *                 los cambios de ese usuario; los demas siguen con las automatizaciones de
 *                 siempre, por eso no hace falta apagar los triggers en Setup mientras se carga.
 */
public with sharing class BulkLoadBypass {
	public static final String PERMISSION = 'Carga_Masiva_Handle';

	private static Boolean active;
	private static Id checkedUserId;

	@TestVisible
	private static Boolean forcedForTest;

	// Las pruebas corren con el usuario que despliega: si ese usuario tiene el permiso, todas las
	// pruebas que esperan que el trigger cree el plan fallarian. Por eso en pruebas el interruptor
	// solo mira el permiso cuando una prueba lo pide expresamente.
	@TestVisible
	private static Boolean checkPermissionInTests = false;

	/**
	 * @creation date: 11/10/2026
	 * @author: Javier Torres - Volestra
	 * @description: Indica si el usuario en curso esta cargando con el interruptor. Se consulta
	 *               una vez por usuario y transaccion: el permiso no cambia mientras dura.
	 * @return: Boolean true si los triggers deben dejar pasar los cambios sin automatizarlos.
	 */
	public static Boolean isActive() {
		if (forcedForTest != null) {
			return forcedForTest;
		}
		if (Test.isRunningTest() && !checkPermissionInTests) {
			return false;
		}
		if (active == null || checkedUserId != UserInfo.getUserId()) {
			active = FeatureManagement.checkPermission(PERMISSION);
			checkedUserId = UserInfo.getUserId();
		}
		return active;
	}
}
