/**
 *   @name: AppLogFinalizer
 *   @version: 1.0
 *   @creation date: 29/07/2026
 *   @author: Javier Torres - Volestra
 *   @description: Finalizador generico que deja registro cuando un proceso asincrono se
 *                 interrumpe por completo -excepcion no controlada o limite de plataforma-
 *                 y no llega a registrar nada por si mismo (H200).
 *                 Es la unica forma de cubrir ese caso: el finalizador se ejecuta en una
 *                 transaccion nueva, por lo que su registro sobrevive a la reversion del
 *                 proceso fallido. Por la misma razon no dispone del buffer acumulado por
 *                 el proceso original -los estaticos no cruzan transacciones- y escribe su
 *                 propia entrada directamente.
 *                 No registra nada cuando el proceso termina bien: el camino exitoso ya se
 *                 refleja en los campos de estado de cada objeto de negocio.
 *                 Se adjunta con System.attachFinalizer al inicio del execute de cada
 *                 eslabon; la plataforma admite un unico finalizador por job.
 */
public without sharing class AppLogFinalizer implements Finalizer {
	@TestVisible
	private static final String EVENT_JOB_ABORTED = 'JOB_ABORTED';

	private String domain;
	private String stage;
	private List<Id> recordIds;

	/**
	 * @creation date: 29/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Inicializa el finalizador con el contexto funcional del eslabon y los
	 *               registros que estaba procesando, para que el registro indique donde se
	 *               interrumpio y sobre que.
	 * @param domain: Dominio funcional del proceso (constantes AppLogger.DOMAIN_*).
	 * @param stage: Etapa funcional del eslabon.
	 * @param recordIds: Registros que el eslabon estaba procesando.
	 * @return
	 */
	public AppLogFinalizer(String domain, String stage, Set<Id> recordIds) {
		this.domain = domain;
		this.stage = stage;
		this.recordIds = recordIds == null
			? new List<Id>()
			: new List<Id>(recordIds);
	}

	/**
	 * @creation date: 29/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Punto de entrada del finalizador. Solo actua si el job termino con una
	 *               excepcion no controlada; en ese caso registra la etapa, la causa y los
	 *               registros en proceso. El registro se escribe con la misma tolerancia a
	 *               fallos del servicio, de modo que un problema aqui no genera una segunda
	 *               falla en cadena.
	 * @param context: Contexto del finalizador provisto por la plataforma.
	 * @return
	 */
	public void execute(FinalizerContext context) {
		if (
			context == null ||
			context.getResult() != ParentJobResult.UNHANDLED_EXCEPTION
		) {
			return;
		}

		AppLogger.setJobContext(context.getAsyncApexJobId());

		Exception cause = context.getException();
		AppLogger.Entry entry = cause == null
			? AppLogger.warn(
					domain,
					stage,
					EVENT_JOB_ABORTED,
					'El proceso se interrumpió sin causa informada por la plataforma.'
			  )
			: AppLogger.error(domain, stage, EVENT_JOB_ABORTED, cause);

		entry.appendDetails(describeRecords());
		if (!recordIds.isEmpty()) {
			entry.onRecord(recordIds[0]);
		}

		AppLogger.flush();
	}

	/**
	 * @creation date: 29/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Describe los registros que el eslabon estaba procesando, para que el
	 *               caso pueda reintentarse manualmente sin adivinar el alcance.
	 * @return Texto con la cantidad y los identificadores en proceso.
	 */
	private String describeRecords() {
		if (recordIds.isEmpty()) {
			return 'Sin registros asociados al proceso interrumpido.';
		}
		return 'Registros en proceso al interrumpirse (' +
			recordIds.size() +
			'): ' +
			String.join(recordIds, ', ');
	}
}
