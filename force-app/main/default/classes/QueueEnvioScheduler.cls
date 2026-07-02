/**
 *   @name: QueueEnvioScheduler
 *   @version: 1.0
 *   @creation date: 02/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Clase Schedulable que ejecuta el batch BatchEnvioEmails de forma programada. Ofrece utilidades para agendar el batch diariamente o cada hora y para cancelar los jobs programados existentes.
 */
public class QueueEnvioScheduler implements Schedulable {

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Ejecuta el batch general BatchEnvioEmails (sin Ids específicos) con tamaño de lote 50 al dispararse el schedule.
	 * @param sc: Contexto del schedule provisto por la plataforma.
	 * @return void
	 */
	public void execute(SchedulableContext sc) {
		System.debug('=== EJECUTANDO SCHEDULE BATCH ENVIO EMAILS ===');
		System.debug('Fecha/hora: ' + Datetime.now());

		// Ejecutar batch general (sin IDs específicos)
		BatchEnvioEmails batch = new BatchEnvioEmails();
		Database.executeBatch(batch, 50);

		System.debug('✅ Batch programado ejecutado exitosamente');
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Agenda el batch para ejecutarse todos los días a las 2:00 AM, generando un nombre de job único con timestamp.
	 * @return void
	 */
	public static void scheduleBatch() {
		try {
			String cronExp = '0 0 2 * * ?'; // Cada día a las 2:00 AM
			String jobName = 'BatchEnvioEmails_Daily_' + System.now().format('yyyyMMdd_HHmmss');

			System.schedule(jobName, cronExp, new QueueEnvioScheduler());
			System.debug('✅ Batch programado: ' + jobName + ' a las 2:00 AM');

		} catch (Exception e) {
			System.debug('❌ Error programando batch: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Agenda el batch para ejecutarse cada hora en punto, generando un nombre de job único con timestamp.
	 * @return void
	 */
	public static void scheduleHourly() {
		try {
			String cronExp = '0 0 * * * ?'; // Cada hora en punto
			String jobName = 'BatchEnvioEmails_Hourly_' + System.now().format('yyyyMMdd_HHmmss');

			System.schedule(jobName, cronExp, new QueueEnvioScheduler());
			System.debug('✅ Batch programado cada hora: ' + jobName);

		} catch (Exception e) {
			System.debug('❌ Error programando batch horario: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cancela todos los jobs programados cuyo nombre comienza con "BatchEnvioEmails_", abortando cada CronTrigger encontrado.
	 * @return void
	 */
	public static void cancelAllJobs() {
		try {
			List<CronTrigger> jobs = [
				SELECT Id, CronJobDetail.Name
				FROM CronTrigger
				WHERE CronJobDetail.Name LIKE 'BatchEnvioEmails_%'
			];

			for (CronTrigger job : jobs) {
				System.abortJob(job.Id);
				System.debug('❌ Job cancelado: ' + job.CronJobDetail.Name);
			}

			System.debug('✅ Total jobs cancelados: ' + jobs.size());

		} catch (Exception e) {
			System.debug('⚠️ Error cancelando jobs: ' + e.getMessage());
		}
	}
}
