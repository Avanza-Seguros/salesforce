/**
 *   @name: InsurancePolicyExpirationBatch
 *   @version: 1.0
 *   @creation date: 16/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Proceso diario que deja Vencido las polizas en Inicial o Vigente cuya
 *                 vigencia ya termino. Se programa una sola vez con scheduleDaily(); cada
 *                 ejecucion vuelve a comprobar estado y fecha, asi que correrlo dos veces el
 *                 mismo dia no cambia nada.
 */
public with sharing class InsurancePolicyExpirationBatch implements Database.Batchable<SObject>, Schedulable {
	public static final String JOB_NAME = 'Vencimiento diario de polizas';
	// Todos los dias a la 01:00, en la zona horaria del usuario que lo programa.
	public static final String DAILY_CRON = '0 0 1 * * ?';
	private static final Integer BATCH_SIZE = 200;

	/**
	 * @creation date: 16/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Programa el proceso diario.
	 * @return Id del trabajo programado.
	 */
	public static Id scheduleDaily() {
		return scheduleAs(JOB_NAME);
	}

	/**
	 * @creation date: 17/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Programa el proceso con un nombre concreto. En una organizacion no puede
	 *               haber dos trabajos con el mismo nombre, asi que una prueba usa el suyo y no
	 *               choca con el que ya esta programado.
	 * @param jobName: Nombre del trabajo programado.
	 * @return Id del trabajo programado.
	 */
	@TestVisible
	private static Id scheduleAs(String jobName) {
		return System.schedule(
			jobName,
			DAILY_CRON,
			new InsurancePolicyExpirationBatch()
		);
	}

	/**
	 * @creation date: 16/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Lanza el proceso por lotes desde la programacion.
	 * @param context: Contexto de la programacion.
	 * @return
	 */
	public void execute(SchedulableContext context) {
		Database.executeBatch(new InsurancePolicyExpirationBatch(), BATCH_SIZE);
	}

	/**
	 * @creation date: 16/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Busca las polizas en Inicial o Vigente con la vigencia terminada.
	 * @param context: Contexto del proceso.
	 * @return Localizador de las polizas candidatas.
	 */
	public Database.QueryLocator start(Database.BatchableContext context) {
		DateTime cutoff = PolicyStatusService.endedTermCutoff(
			PolicyStatusService.todayInMexico()
		);
		List<String> liveStatuses = new List<String>{
			PolicyStatusService.STATUS_INITIAL,
			PolicyStatusService.STATUS_ACTIVE
		};
		return Database.getQueryLocator(
			[
				SELECT Id, Status, ExpirationDate
				FROM InsurancePolicy
				WHERE Status IN :liveStatuses AND ExpirationDate < :cutoff
			]
		);
	}

	/**
	 * @creation date: 16/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Deja Vencido cada poliza del lote.
	 * @param context: Contexto del proceso.
	 * @param scope: Polizas del lote.
	 * @return
	 */
	public void execute(
		Database.BatchableContext context,
		List<InsurancePolicy> scope
	) {
		AppLogger.setJobContext(context.getJobId());
		PolicyStatusService.expireEndedTerms(scope);
		AppLogger.flush();
	}

	/**
	 * @creation date: 16/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Sin tareas al terminar: cada fallo ya quedo registrado en su lote.
	 * @param context: Contexto del proceso.
	 * @return
	 */
	public void finish(Database.BatchableContext context) {
		return;
	}
}
