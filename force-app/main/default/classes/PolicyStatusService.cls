/**
 *   @name: PolicyStatusService
 *   @version: 1.0
 *   @creation date: 16/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Unico punto que escribe el estado operativo de la poliza (Status) desde la
 *                 cobranza. Hoy aplica los dos hechos que no dependen de la aseguradora: el
 *                 primer pago reconocido saca la poliza de Inicial y el fin de la vigencia la
 *                 deja Vencido. Nunca infiere una cancelacion: esa solo la comunica la
 *                 aseguradora.
 */
public with sharing class PolicyStatusService {
	public static final String STATUS_INITIAL = 'Inicial';
	public static final String STATUS_ACTIVE = 'Vigente';
	public static final String STATUS_EXPIRED = 'Vencido';

	@TestVisible
	private static final String MEXICO_TIME_ZONE = 'America/Mexico_City';

	// Fuerza el fallo del guardado de estas polizas para poder probar que un fallo no detiene a
	// las demas. Vaciar un campo obligatorio produce un fallo de plataforma devuelto como
	// resultado, que es exactamente el caso que hay que registrar.
	@TestVisible
	private static Set<Id> failForTest = new Set<Id>();

	/**
	 * @creation date: 16/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Saca de Inicial las polizas que acaban de recibir un pago reconocido. Una
	 *               poliza en Inicial esta vigente en espera de su primer pago: al llegar pasa a
	 *               Vigente, o a Vencido si su vigencia ya termino. Se llama despues de cerrar la
	 *               oportunidad: si la poliza la tiene, el flow del cierre ya la paso a Vigente y
	 *               aqui no se vuelve a tocar. Cubre a las polizas sin oportunidad (las migradas)
	 *               y a las que tienen una oportunidad que el cobro no cierra.
	 * @param policyIds: Polizas con un recibo recien reconocido.
	 * @return
	 */
	public static void activateOnFirstPayment(Set<Id> policyIds) {
		if (policyIds == null || policyIds.isEmpty()) {
			return;
		}
		Date today = todayInMexico();
		List<InsurancePolicy> toUpdate = new List<InsurancePolicy>();
		for (InsurancePolicy policy : [
			SELECT Id, Name, Status, ExpirationDate
			FROM InsurancePolicy
			WHERE Id IN :policyIds AND Status = :STATUS_INITIAL
		]) {
			toUpdate.add(
				new InsurancePolicy(
					Id = policy.Id,
					Status = termEnded(policy.ExpirationDate, today)
						? STATUS_EXPIRED
						: STATUS_ACTIVE
				)
			);
		}
		save(toUpdate);
	}

	/**
	 * @creation date: 16/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Deja Vencido las polizas en Inicial o Vigente cuya vigencia ya termino. Una
	 *               poliza Cancelado no se toca: la cancelacion es de la aseguradora. Vuelve a
	 *               comprobar estado y fecha de cada poliza, asi que aplicarlo dos veces no cambia
	 *               nada.
	 * @param policies: Polizas candidatas, con Status y ExpirationDate.
	 * @return
	 */
	public static void expireEndedTerms(List<InsurancePolicy> policies) {
		if (policies == null || policies.isEmpty()) {
			return;
		}
		Date today = todayInMexico();
		List<InsurancePolicy> toUpdate = new List<InsurancePolicy>();
		for (InsurancePolicy policy : policies) {
			Boolean live =
				STATUS_INITIAL.equals(policy.Status) ||
				STATUS_ACTIVE.equals(policy.Status);
			if (live && termEnded(policy.ExpirationDate, today)) {
				toUpdate.add(
					new InsurancePolicy(Id = policy.Id, Status = STATUS_EXPIRED)
				);
			}
		}
		save(toUpdate);
	}

	/**
	 * @creation date: 16/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Indica si la vigencia ya termino: el dia de fin es anterior a hoy. El dia
	 *               de fin se toma en UTC porque las polizas guardan la fecha de fin como
	 *               medianoche UTC (migracion), medianoche de Ciudad de Mexico (flow de alta, al
	 *               convertir la fecha de la cotizacion) o mediodia; en los tres casos la fecha UTC
	 *               es el dia correcto, y la de Ciudad de Mexico no lo es para la migracion.
	 * @param expirationDate: Fecha de fin de vigencia.
	 * @param today: Hoy en Ciudad de Mexico.
	 * @return true si la vigencia ya termino.
	 */
	@TestVisible
	private static Boolean termEnded(DateTime expirationDate, Date today) {
		return expirationDate != null && expirationDate.dateGmt() < today;
	}

	/**
	 * @creation date: 16/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Limite para buscar polizas con la vigencia terminada: toda fecha de fin
	 *               anterior a hoy a las 00:00 UTC. Coincide exactamente con termEnded.
	 * @param today: Hoy en Ciudad de Mexico.
	 * @return Fecha y hora limite.
	 */
	public static DateTime endedTermCutoff(Date today) {
		return DateTime.newInstanceGmt(today, Time.newInstance(0, 0, 0, 0));
	}

	/**
	 * @creation date: 16/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Hoy en Ciudad de Mexico, sea cual sea la zona del usuario que ejecuta el
	 *               proceso programado.
	 * @return Fecha de hoy.
	 */
	public static Date todayInMexico() {
		return Date.valueOf(DateTime.now().format('yyyy-MM-dd', MEXICO_TIME_ZONE));
	}

	/**
	 * @creation date: 16/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Guarda poliza por poliza para que una que falla (por ejemplo, por la regla
	 *               de datos de prima) no impida actualizar las demas, y deja constancia de cada
	 *               fallo con la poliza y el motivo.
	 * @param policies: Polizas con su nuevo estado.
	 * @return
	 */
	private static void save(List<InsurancePolicy> policies) {
		if (policies.isEmpty()) {
			return;
		}
		if (Test.isRunningTest()) {
			for (InsurancePolicy policy : policies) {
				if (failForTest.contains(policy.Id)) {
					policy.Name = null;
				}
			}
		}
		List<Database.SaveResult> results = Database.update(policies, false);
		for (Integer i = 0; i < results.size(); i++) {
			if (results[i].isSuccess()) {
				continue;
			}
			List<String> errors = new List<String>();
			for (Database.Error error : results[i].getErrors()) {
				errors.add(error.getMessage());
			}
			CobranzaLog.error(
					CobranzaLog.STAGE_ESTADO_POLIZA,
					CobranzaLog.EVENT_POLICY_STATUS_UPDATE_FAILED,
					'No se pudo pasar la póliza a ' +
						policies[i].Status +
						'. Las demás pólizas se actualizaron. Motivo: ' +
						String.join(errors, '; ')
				)
				.onRecord(policies[i].Id);
		}
	}
}
