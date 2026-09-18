/**
 *   @name: PolicyStatusService
 *   @version: 1.1
 *   @creation date: 16/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Unico punto que escribe el estado operativo de la poliza (Status) desde la
 *                 cobranza. Manda lo que comunica la aseguradora: si la da por cancelada, la
 *                 poliza queda Cancelado; si la da por vigente, vuelve a estarlo salvo que su
 *                 vigencia haya terminado. A falta de comunicacion aplica los dos hechos que no
 *                 dependen de ella: el primer pago reconocido saca la poliza de Inicial y el fin
 *                 de la vigencia la deja Vencido. Nunca infiere una cancelacion.
 */
public with sharing class PolicyStatusService {
	public static final String STATUS_INITIAL = 'Inicial';
	public static final String STATUS_ACTIVE = 'Vigente';
	public static final String STATUS_EXPIRED = 'Vencido';
	public static final String STATUS_CANCELLED = 'Cancelado';

	private static final String INSTALLMENT_PENDING = 'Pendiente';
	private static final String INSTALLMENT_OVERDUE = 'Vencido';
	private static final String INSTALLMENT_CANCELLED = 'Cancelado';
	private static final String PLAN_ACTIVE = 'Activo';
	private static final String PLAN_CANCELLED = 'Cancelado';
	private static final Set<String> PLAN_STATUSES_TO_CANCEL = new Set<String>{
		'Borrador',
		'Activo',
		'Suspendido'
	};
	private static final Set<String> OPEN_INSTALLMENT_STATUSES = new Set<String>{
		INSTALLMENT_PENDING,
		INSTALLMENT_OVERDUE
	};

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
	 * @creation date: 17/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Lleva al estado operativo de la poliza lo que comunico la aseguradora, ya
	 *               guardado en ella. Cancelada manda siempre; vigente la devuelve a Vigente,
	 *               salvo que su vigencia haya terminado, en cuyo caso queda Vencido: un "vigente"
	 *               desactualizado no revive una poliza cuyo periodo ya paso. Al cancelar, las
	 *               cuotas que vencen despues de la cancelacion dejan de deberse y el plan se
	 *               cancela; al rehabilitar, vuelven a deberse exactamente esas y el plan vuelve a
	 *               estar activo. Aplicarlo dos veces no cambia nada.
	 * @param policyIds: Polizas cuyo estado comunicado acaba de guardarse.
	 * @return
	 */
	public static void applyCommunicatedStatus(Set<Id> policyIds) {
		if (policyIds == null || policyIds.isEmpty()) {
			return;
		}
		Date today = todayInMexico();
		List<InsurancePolicy> toUpdate = new List<InsurancePolicy>();
		Map<Id, Date> cancelledFrom = new Map<Id, Date>();
		// Ya estaban canceladas (por ejemplo, las de una carga): la poliza no cambia, pero sus
		// cuotas posteriores a la cancelacion siguen dejando de deberse.
		Map<Id, Date> alreadyCancelledFrom = new Map<Id, Date>();
		Map<Id, Id> noticeByPolicy = new Map<Id, Id>();
		Set<Id> rehabilitated = new Set<Id>();

		for (InsurancePolicy policy : [
			SELECT
				Id,
				Name,
				Status,
				ExpirationDate,
				carrierPolicyStatus__c,
				carrierStatusSyncedAt__c,
				carrierStatusNotice__c,
				carrierStatusNotice__r.sourceCancellationDate__c,
				carrierStatusNotice__r.sourceCancellationReason__c
			FROM InsurancePolicy
			WHERE Id IN :policyIds AND carrierPolicyStatus__c != NULL
		]) {
			String communicated = policy.carrierPolicyStatus__c;

			if (STATUS_CANCELLED.equals(communicated)) {
				Date since = cancellationDateOf(policy, today);
				if (STATUS_CANCELLED.equals(policy.Status)) {
					alreadyCancelledFrom.put(policy.Id, since);
					noticeByPolicy.put(policy.Id, policy.carrierStatusNotice__c);
					continue;
				}
				InsurancePolicy upd = new InsurancePolicy(
					Id = policy.Id,
					Status = STATUS_CANCELLED,
					CancellationDate = DateTime.newInstanceGmt(
						since,
						Time.newInstance(0, 0, 0, 0)
					)
				);
				String reason = policy.carrierStatusNotice__c == null
					? null
					: policy.carrierStatusNotice__r.sourceCancellationReason__c;
				if (String.isNotBlank(reason)) {
					upd.CancellationReason = reason;
				}
				toUpdate.add(upd);
				cancelledFrom.put(policy.Id, since);
				noticeByPolicy.put(policy.Id, policy.carrierStatusNotice__c);
				continue;
			}

			if (STATUS_ACTIVE.equals(communicated)) {
				String target = termEnded(policy.ExpirationDate, today)
					? STATUS_EXPIRED
					: STATUS_ACTIVE;
				if (target.equals(policy.Status)) {
					continue;
				}
				InsurancePolicy upd = new InsurancePolicy(
					Id = policy.Id,
					Status = target
				);
				if (STATUS_CANCELLED.equals(policy.Status)) {
					// Deja de estar cancelada: su fecha y su motivo de cancelacion ya no aplican.
					upd.CancellationDate = null;
					upd.CancellationReason = null;
					if (STATUS_ACTIVE.equals(target)) {
						rehabilitated.add(policy.Id);
					}
				}
				toUpdate.add(upd);
				continue;
			}

			if (
				STATUS_EXPIRED.equals(communicated) &&
				!STATUS_EXPIRED.equals(policy.Status)
			) {
				toUpdate.add(
					new InsurancePolicy(Id = policy.Id, Status = STATUS_EXPIRED)
				);
			}
		}

		Set<Id> saved = save(toUpdate);
		Map<Id, Date> toCancel = new Map<Id, Date>(alreadyCancelledFrom);
		for (Id policyId : cancelledFrom.keySet()) {
			if (saved.contains(policyId)) {
				toCancel.put(policyId, cancelledFrom.get(policyId));
			}
		}
		cancelInstallmentsAfterCancellation(toCancel, noticeByPolicy);
		rehabilitated.retainAll(saved);
		reopenInstallmentsCancelledByNotice(rehabilitated);
	}

	/**
	 * @creation date: 17/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Fecha desde la que la poliza esta cancelada: la que informa la aseguradora en
	 *               su comunicacion y, si no la informa, la fecha de la propia comunicacion.
	 * @param policy: Poliza con su comunicacion.
	 * @param today: Hoy en Ciudad de Mexico.
	 * @return Fecha de cancelacion.
	 */
	private static Date cancellationDateOf(InsurancePolicy policy, Date today) {
		if (
			policy.carrierStatusNotice__c != null &&
			policy.carrierStatusNotice__r.sourceCancellationDate__c != null
		) {
			return policy.carrierStatusNotice__r.sourceCancellationDate__c;
		}
		return policy.carrierStatusSyncedAt__c == null
			? today
			: policy.carrierStatusSyncedAt__c.dateGmt();
	}

	/**
	 * @creation date: 17/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Cancela las cuotas que ya no se deben y el plan. Solo las abiertas que vencen
	 *               DESPUES de la cancelacion: las anteriores sin pagar se quedan como estan,
	 *               porque son la deuda que explica la cancelacion, y las pagadas no se tocan.
	 *               Quedan enlazadas a la comunicacion, que es lo que permite reabrir exactamente
	 *               esas si la aseguradora rehabilita la poliza.
	 * @param cancelledFrom: Fecha de cancelacion por poliza.
	 * @param noticeByPolicy: Comunicacion que cancelo cada poliza.
	 * @return
	 */
	private static void cancelInstallmentsAfterCancellation(
		Map<Id, Date> cancelledFrom,
		Map<Id, Id> noticeByPolicy
	) {
		if (cancelledFrom.isEmpty()) {
			return;
		}
		List<PaymentPlanInstallment__c> toCancel = new List<PaymentPlanInstallment__c>();
		for (PaymentPlanInstallment__c installment : [
			SELECT Id, dueDate__c, paymentPlan__r.insurancePolicy__c
			FROM PaymentPlanInstallment__c
			WHERE
				paymentPlan__r.insurancePolicy__c IN :cancelledFrom.keySet()
				AND installmentStatus__c IN :OPEN_INSTALLMENT_STATUSES
		]) {
			Id policyId = installment.paymentPlan__r.insurancePolicy__c;
			Date since = cancelledFrom.get(policyId);
			if (installment.dueDate__c == null || since == null) {
				continue;
			}
			if (installment.dueDate__c > since) {
				toCancel.add(
					new PaymentPlanInstallment__c(
						Id = installment.Id,
						installmentStatus__c = INSTALLMENT_CANCELLED,
						cancelledByCarrierNotice__c = noticeByPolicy.get(policyId)
					)
				);
			}
		}
		saveInstallments(toCancel);
		setPlanStatus(
			cancelledFrom.keySet(),
			PLAN_STATUSES_TO_CANCEL,
			PLAN_CANCELLED
		);
	}

	/**
	 * @creation date: 17/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Devuelve a Pendiente las cuotas que cancelo la cancelacion de la poliza, y
	 *               solo esas: se reconocen por su enlace a la comunicacion. El plan vuelve a
	 *               estar activo; como ya tiene cuotas, no se generan de nuevo.
	 * @param policyIds: Polizas rehabilitadas.
	 * @return
	 */
	private static void reopenInstallmentsCancelledByNotice(Set<Id> policyIds) {
		if (policyIds.isEmpty()) {
			return;
		}
		DateTime now = System.now();
		List<PaymentPlanInstallment__c> toReopen = new List<PaymentPlanInstallment__c>();
		for (PaymentPlanInstallment__c installment : [
			SELECT Id
			FROM PaymentPlanInstallment__c
			WHERE
				paymentPlan__r.insurancePolicy__c IN :policyIds
				AND cancelledByCarrierNotice__c != NULL
				AND installmentStatus__c = :INSTALLMENT_CANCELLED
		]) {
			toReopen.add(
				new PaymentPlanInstallment__c(
					Id = installment.Id,
					installmentStatus__c = INSTALLMENT_PENDING,
					cancelledByCarrierNotice__c = null,
					reopenedFromCancelledOn__c = now
				)
			);
		}
		saveInstallments(toReopen);
		setPlanStatus(policyIds, new Set<String>{ PLAN_CANCELLED }, PLAN_ACTIVE);
	}

	/**
	 * @creation date: 17/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Cambia el estado de los planes de esas polizas que estan en alguno de los
	 *               estados de partida. Los planes reemplazados o completados no se tocan.
	 * @param policyIds: Polizas afectadas.
	 * @param fromStatuses: Estados de partida.
	 * @param toStatus: Estado destino.
	 * @return
	 */
	private static void setPlanStatus(
		Set<Id> policyIds,
		Set<String> fromStatuses,
		String toStatus
	) {
		List<PaymentPlan__c> toUpdate = new List<PaymentPlan__c>();
		for (PaymentPlan__c plan : [
			SELECT Id, planStatus__c
			FROM PaymentPlan__c
			WHERE insurancePolicy__c IN :policyIds AND planStatus__c IN :fromStatuses
		]) {
			toUpdate.add(new PaymentPlan__c(Id = plan.Id, planStatus__c = toStatus));
		}
		if (toUpdate.isEmpty()) {
			return;
		}
		logFailures(Database.update(toUpdate, false), toUpdate, 'el plan de pagos');
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
	 * @return Polizas que si se guardaron.
	 */
	private static Set<Id> save(List<InsurancePolicy> policies) {
		Set<Id> saved = new Set<Id>();
		if (policies.isEmpty()) {
			return saved;
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
				saved.add(policies[i].Id);
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
		return saved;
	}

	/**
	 * @creation date: 17/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Guarda las cuotas una por una, para que el fallo de una no deje a las demas
	 *               sin actualizar, y registra cada fallo.
	 * @param installments: Cuotas a guardar.
	 * @return
	 */
	private static void saveInstallments(
		List<PaymentPlanInstallment__c> installments
	) {
		if (installments.isEmpty()) {
			return;
		}
		logFailures(Database.update(installments, false), installments, 'la cuota');
	}

	/**
	 * @creation date: 17/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Deja en el registro de la aplicacion los registros que no se pudieron
	 *               guardar, con su motivo.
	 * @param results: Resultados del guardado.
	 * @param records: Registros en el mismo orden.
	 * @param what: Como nombrar al registro en el mensaje.
	 * @return
	 */
	private static void logFailures(
		List<Database.SaveResult> results,
		List<SObject> records,
		String what
	) {
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
					'No se pudo actualizar ' +
						what +
						' al aplicar el estado que comunicó la aseguradora. Motivo: ' +
						String.join(errors, '; ')
				)
				.onRecord(records[i].Id);
		}
	}
}
