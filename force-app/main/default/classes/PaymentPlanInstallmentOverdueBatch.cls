/**
 *   @name: PaymentPlanInstallmentOverdueBatch
 *   @version: 1.0
 *   @creation date: 20/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Proceso diario que deja Vencido las cuotas Pendiente cuyo vencimiento ya paso.
 *                 El mismo dia del vencimiento la cuota sigue Pendiente. No toca las pagadas,
 *                 canceladas ni condonadas, ni las que no tienen vencimiento. Se programa una sola
 *                 vez con scheduleDaily(); cada ejecucion vuelve a comprobar estado y fecha, asi
 *                 que correrlo dos veces el mismo dia no cambia nada. Que una cuota este Vencido no
 *                 impide cobrarla: el motor concilia igual las Pendiente y las Vencido.
 */
public with sharing class PaymentPlanInstallmentOverdueBatch implements Database.Batchable<SObject>, Schedulable {
	public static final String JOB_NAME = 'Cuotas vencidas';
	// Todos los dias a la 01:30, despues del vencimiento de polizas, en la zona horaria del
	// usuario que lo programa.
	public static final String DAILY_CRON = '0 30 1 * * ?';
	private static final Integer BATCH_SIZE = 200;
	private static final String STATUS_PENDING = 'Pendiente';
	private static final String STATUS_OVERDUE = 'Vencido';

	// Fuerza el fallo del guardado de estas cuotas para probar que el fallo queda registrado y
	// que no detiene a las demas. Un estado que no existe en el picklist restringido produce un
	// fallo de plataforma devuelto como resultado, que es exactamente el caso que hay que registrar.
	@TestVisible
	private static Set<Id> failForTest = new Set<Id>();

	/**
	 * @creation date: 20/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Programa el proceso diario.
	 * @return Id del trabajo programado.
	 */
	public static Id scheduleDaily() {
		return scheduleAs(JOB_NAME);
	}

	/**
	 * @creation date: 20/09/2026
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
			new PaymentPlanInstallmentOverdueBatch()
		);
	}

	/**
	 * @creation date: 20/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Lanza el proceso por lotes desde la programacion.
	 * @param context: Contexto de la programacion.
	 * @return
	 */
	public void execute(SchedulableContext context) {
		Database.executeBatch(new PaymentPlanInstallmentOverdueBatch(), BATCH_SIZE);
	}

	/**
	 * @creation date: 20/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Busca las cuotas Pendiente con el vencimiento pasado.
	 * @param context: Contexto del proceso.
	 * @return Localizador de las cuotas candidatas.
	 */
	public Database.QueryLocator start(Database.BatchableContext context) {
		Date today = PolicyStatusService.todayInMexico();
		return Database.getQueryLocator(
			[
				SELECT Id, dueDate__c, installmentStatus__c
				FROM PaymentPlanInstallment__c
				WHERE installmentStatus__c = :STATUS_PENDING AND dueDate__c < :today
			]
		);
	}

	/**
	 * @creation date: 20/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Deja Vencido cada cuota del lote.
	 * @param context: Contexto del proceso.
	 * @param scope: Cuotas del lote.
	 * @return
	 */
	public void execute(
		Database.BatchableContext context,
		List<PaymentPlanInstallment__c> scope
	) {
		AppLogger.setJobContext(context.getJobId());
		markOverdue(scope);
		AppLogger.flush();
	}

	/**
	 * @creation date: 20/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Sin tareas al terminar: cada fallo ya quedo registrado en su lote.
	 * @param context: Contexto del proceso.
	 * @return
	 */
	public void finish(Database.BatchableContext context) {
		return;
	}

	/**
	 * @creation date: 20/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Deja Vencido las cuotas que siguen Pendiente y ya vencieron. Vuelve a
	 *               comprobar estado y fecha de cada una, asi que aplicarlo dos veces no cambia
	 *               nada. Un fallo al guardar una cuota queda registrado y no detiene a las demas.
	 * @param installments: Cuotas a revisar, con su estado y su vencimiento.
	 * @return
	 */
	@TestVisible
	private static void markOverdue(
		List<PaymentPlanInstallment__c> installments
	) {
		Date today = PolicyStatusService.todayInMexico();
		List<PaymentPlanInstallment__c> toUpdate = new List<PaymentPlanInstallment__c>();
		for (PaymentPlanInstallment__c inst : installments) {
			if (
				!STATUS_PENDING.equals(inst.installmentStatus__c) ||
				inst.dueDate__c == null ||
				inst.dueDate__c >= today
			) {
				continue;
			}
			PaymentPlanInstallment__c upd = new PaymentPlanInstallment__c(
				Id = inst.Id,
				installmentStatus__c = STATUS_OVERDUE
			);
			if (Test.isRunningTest() && failForTest.contains(inst.Id)) {
				upd.installmentStatus__c = 'ESTADO QUE NO EXISTE';
			}
			toUpdate.add(upd);
		}
		if (toUpdate.isEmpty()) {
			return;
		}
		List<Database.SaveResult> results = Database.update(toUpdate, false);
		for (Integer i = 0; i < results.size(); i++) {
			if (results[i].isSuccess()) {
				continue;
			}
			List<String> errors = new List<String>();
			for (Database.Error error : results[i].getErrors()) {
				errors.add(error.getMessage());
			}
			CobranzaLog.error(
					CobranzaLog.STAGE_CUOTA,
					CobranzaLog.EVENT_INSTALLMENT_OVERDUE_FAILED,
					'No se pudo dejar la cuota como vencida. Motivo: ' +
					String.join(errors, '; ')
				)
				.onRecord(toUpdate[i].Id);
		}
	}
}
