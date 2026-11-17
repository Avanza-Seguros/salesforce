/**
 *   @name: FleetInstallmentService
 *   @version: 1.0
 *   @creation date: 16/11/2026
 *   @author: Javier Torres - Volestra
 *   @description: Liga las cuotas de una flotilla a sus incisos cuando el plan lo genera
 *                 Salesforce (emisión desde la pantalla de la póliza o endosos de flotilla), para
 *                 que la pestaña Pagos diga qué bien paga cada recibo y el pago de un inciso solo
 *                 compita por las cuotas de ese inciso.
 *                 - Una póliza se cobra por inciso cuando tiene dos o más bienes vivos con número
 *                   de inciso (AssetCode o el prefijo «Inciso N - » del nombre).
 *                 - Al generar el plan, cada cuota del calendario se reparte entre los incisos
 *                   vivos según su prima (en partes iguales si a alguno le falta): el importe de
 *                   cada periodo y el total del plan no cambian.
 *                 - Si los incisos llegan después y el plan no ha cobrado nada, el plan se rehace
 *                   por inciso. Si ya cobró, no se toca y queda un aviso para revisión.
 *                 - Un inciso que se da de alta en un plan ya repartido recibe sus cuotas desde el
 *                   periodo de su alta (prima del inciso entre el número de cuotas).
 *                 - Un inciso que se da de baja cancela sus cuotas sin cobro que vencen después
 *                   de la baja. Las cobradas no cambian.
 *                 Solo trabaja sobre cuotas que generó Salesforce: las que vienen de la
 *                 aseguradora (Handle, portal o con número de recibo) son la fuente de la verdad
 *                 y no se tocan.
 */
public with sharing class FleetInstallmentService {
	private static final String PLAN_STATUS_ACTIVE = 'Activo';
	private static final String STATUS_CANCELLED = 'Cancelado';
	private static final Set<String> UNPAID_STATUSES = new Set<String>{
		'Pendiente',
		'Vencido'
	};
	private static final Set<String> LIVE_POLICY_STATUSES = new Set<String>{
		'Inicial',
		'Vigente'
	};
	private static final Integer MIN_INCISOS = 2;

	// Evita volver a entrar mientras se rehace un plan o se guardan sus cuotas.
	private static Boolean running = false;

	/**
	 * @creation date: 16/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Reparte por inciso el calendario recién construido de los planes cuya póliza
	 *               se cobra por inciso. Los demás planes se devuelven tal cual.
	 * @param plansById: Planes del calendario, con insurancePolicy__c.
	 * @param calendar: Una cuota por periodo, sin inciso.
	 * @return: List<PaymentPlanInstallment__c> El calendario, con los periodos de las flotillas
	 *          partidos en una cuota por inciso.
	 * @exception:
	 * @throws:
	 */
	public static List<PaymentPlanInstallment__c> splitByInciso(
		Map<Id, PaymentPlan__c> plansById,
		List<PaymentPlanInstallment__c> calendar
	) {
		if (plansById == null || calendar == null || calendar.isEmpty()) {
			return calendar;
		}

		Set<Id> policyIds = new Set<Id>();
		for (PaymentPlan__c plan : plansById.values()) {
			if (plan.insurancePolicy__c != null) {
				policyIds.add(plan.insurancePolicy__c);
			}
		}
		if (policyIds.isEmpty()) {
			return calendar;
		}

		Map<Id, List<Inciso>> incisosByPolicy = loadIncisos(policyIds);
		List<PaymentPlanInstallment__c> result = new List<PaymentPlanInstallment__c>();

		for (PaymentPlanInstallment__c period : calendar) {
			PaymentPlan__c plan = plansById.get(period.paymentPlan__c);
			List<Inciso> live = plan == null
				? new List<Inciso>()
				: liveOnly(incisosByPolicy.get(plan.insurancePolicy__c));

			if (live.size() < MIN_INCISOS) {
				result.add(period);
				continue;
			}
			result.addAll(split(period, live));
		}

		return result;
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Punto de entrada del trigger de bienes de la póliza: altas, bajas y cambios
	 *               de inciso, fechas o prima. Las cargas masivas traen sus propias cuotas y no
	 *               pasan por aquí.
	 * @param records: Bienes nuevos del trigger.
	 * @param oldMap: Valores anteriores; nulo al insertar.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	public static void onAssetsChanged(
		List<InsurancePolicyAsset> records,
		Map<Id, InsurancePolicyAsset> oldMap
	) {
		if (records == null || BulkLoadBypass.isActive()) {
			return;
		}

		Set<Id> policyIds = new Set<Id>();
		for (InsurancePolicyAsset asset : records) {
			InsurancePolicyAsset previous = oldMap == null
				? null
				: oldMap.get(asset.Id);
			// Solo cuentan los bienes con número de inciso: un bien suelto no reparte nada.
			Boolean isInciso =
				FleetIncisoService.incisoOf(asset) != null ||
				(previous != null &&
				FleetIncisoService.incisoOf(previous) != null);
			if (isInciso && (previous == null || isRelevantChange(asset, previous))) {
				policyIds.add(asset.InsurancePolicyId);
			}
		}

		sync(policyIds);
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Pone las cuotas de cada póliza al día con sus incisos. Un fallo no detiene el
	 *               guardado del bien: se deshace lo que se hubiera hecho y queda en el log.
	 * @param policyIds: Pólizas a revisar.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	public static void sync(Set<Id> policyIds) {
		if (policyIds == null || running) {
			return;
		}
		policyIds.remove(null);
		if (policyIds.isEmpty()) {
			return;
		}

		running = true;
		Savepoint savepoint = Database.setSavepoint();
		try {
			syncPolicies(policyIds);
		} catch (Exception e) {
			Database.rollback(savepoint);
			for (Id policyId : policyIds) {
				CobranzaLog.error(
						CobranzaLog.STAGE_PLAN_PAGOS,
						CobranzaLog.EVENT_INSTALLMENTS_BY_INCISO_FAILED,
						'No se pudieron ligar las cuotas a los incisos: ' + e.getMessage()
					)
					.onRecord(policyId);
			}
		} finally {
			running = false;
		}
		AppLogger.flush();
	}

	private static void syncPolicies(Set<Id> policyIds) {
		Map<Id, PaymentPlan__c> planByPolicy = new Map<Id, PaymentPlan__c>();
		Map<Id, List<PaymentPlanInstallment__c>> installmentsByPlan = new Map<Id, List<PaymentPlanInstallment__c>>();
		for (PaymentPlan__c plan : singleActivePlanByPolicy(policyIds).values()) {
			// Sin cuotas no hay nada que ligar; las de la aseguradora no se tocan.
			if (
				plan.Installments__r.isEmpty() || comesFromCarrier(plan.Installments__r)
			) {
				continue;
			}
			planByPolicy.put(plan.insurancePolicy__c, plan);
			installmentsByPlan.put(plan.Id, plan.Installments__r);
		}
		if (planByPolicy.isEmpty()) {
			return;
		}

		Map<Id, List<Inciso>> incisosByPolicy = loadIncisos(planByPolicy.keySet());

		// Saber si un plan ya cobró cuesta varias consultas: solo se pregunta por los que se
		// rehacerían.
		Set<Id> rebuildCandidates = new Set<Id>();
		for (Id policyId : planByPolicy.keySet()) {
			if (
				!isSplit(installmentsByPlan.get(planByPolicy.get(policyId).Id)) &&
				liveOnly(incisosByPolicy.get(policyId)).size() >= MIN_INCISOS
			) {
				rebuildCandidates.add(policyId);
			}
		}
		Set<Id> withoutCollections = rebuildCandidates.isEmpty()
			? new Set<Id>()
			: PaymentPlanRegenerationService.selectPoliciesWithoutCollections(
					rebuildCandidates
			  );

		List<PaymentPlan__c> toRebuild = new List<PaymentPlan__c>();
		Changes changes = new Changes();

		for (Id policyId : planByPolicy.keySet()) {
			PaymentPlan__c plan = planByPolicy.get(policyId);
			List<PaymentPlanInstallment__c> installments = installmentsByPlan.get(
				plan.Id
			);
			List<Inciso> incisos = incisosByPolicy.get(policyId);
			if (incisos == null) {
				incisos = new List<Inciso>();
			}

			if (!isSplit(installments)) {
				if (liveOnly(incisos).size() < MIN_INCISOS) {
					continue;
				}
				if (withoutCollections.contains(policyId)) {
					toRebuild.add(plan);
				} else {
					changes.review(
						policyId,
						'La flotilla tiene ' +
							liveOnly(incisos).size() +
							' incisos, pero su plan ya cobró: no se reparte por inciso. ' +
							'Revisar el plan a mano.'
					);
				}
				continue;
			}

			addAltas(plan, installments, liveOnly(incisos), changes);
			addBajas(installments, incisos, changes);
		}

		rebuild(toRebuild);
		changes.save();
	}

	/**
	 * Rehace por inciso los planes sin cobros que se generaron antes de tener sus incisos. El
	 * generador reparte cada periodo al ver los incisos.
	 */
	private static void rebuild(List<PaymentPlan__c> plans) {
		if (plans.isEmpty()) {
			return;
		}
		Map<Id, PaymentPlan__c> plansById = new Map<Id, PaymentPlan__c>(plans);
		delete [
			SELECT Id
			FROM PaymentPlanInstallment__c
			WHERE paymentPlan__c IN :plansById.keySet()
		];
		PaymentPlanTriggerHandler.generateInstallments(plans);

		for (PaymentPlan__c plan : plans) {
			CobranzaLog.info(
					CobranzaLog.STAGE_PLAN_PAGOS,
					CobranzaLog.EVENT_INSTALLMENTS_BY_INCISO,
					'Plan sin cobros rehecho por inciso.'
				)
				.onRecord(plan.insurancePolicy__c);
		}
	}

	/**
	 * Un inciso vivo sin cuota en un periodo que cubre recibe la suya; una cuota sin tocar de un
	 * periodo anterior a su alta sobra (la pantalla de endosos crea el bien con la fecha de la
	 * póliza y le pone la del alta justo después).
	 */
	private static void addAltas(
		PaymentPlan__c plan,
		List<PaymentPlanInstallment__c> installments,
		List<Inciso> live,
		Changes changes
	) {
		List<PaymentPlanInstallment__c> calendar = PaymentPlanTriggerHandler.buildCalendar(
			plan
		);
		if (calendar.isEmpty()) {
			return;
		}

		for (Inciso inciso : live) {
			Map<Date, PaymentPlanInstallment__c> ownByDueDate = new Map<Date, PaymentPlanInstallment__c>();
			for (PaymentPlanInstallment__c inst : installments) {
				if (
					inst.policyAsset__c == inciso.assetId &&
					inst.installmentStatus__c != STATUS_CANCELLED
				) {
					ownByDueDate.put(inst.dueDate__c, inst);
				}
			}

			Boolean missingPremium = false;
			for (PaymentPlanInstallment__c period : calendar) {
				Boolean covered =
					inciso.fromDate == null ||
					period.periodEndDate__c >= inciso.fromDate;
				PaymentPlanInstallment__c own = ownByDueDate.get(period.dueDate__c);

				if (covered && own == null) {
					if (inciso.premium == null) {
						missingPremium = true;
						continue;
					}
					PaymentPlanInstallment__c created = period.clone(false, true);
					created.policyAsset__c = inciso.assetId;
					created.expectedAmount__c = (inciso.premium /
						plan.installmentCount__c)
						.setScale(2, RoundingMode.HALF_UP);
					changes.toInsert.add(created);
					changes.touch(plan.insurancePolicy__c);
				} else if (!covered && own != null && isUnpaid(own)) {
					changes.toDelete.add(own);
					changes.touch(plan.insurancePolicy__c);
				}
			}

			if (missingPremium) {
				changes.review(
					plan.insurancePolicy__c,
					'El inciso ' +
						inciso.code +
						' se dio de alta sin prima: no se le crearon cuotas.'
				);
			}
		}
	}

	/**
	 * Un inciso de baja cancela sus cuotas sin cobro que vencen después de la baja.
	 */
	private static void addBajas(
		List<PaymentPlanInstallment__c> installments,
		List<Inciso> incisos,
		Changes changes
	) {
		Map<Id, Date> bajaByAsset = new Map<Id, Date>();
		for (Inciso inciso : incisos) {
			if (!inciso.live) {
				bajaByAsset.put(
					inciso.assetId,
					inciso.toDate == null ? Date.today() : inciso.toDate
				);
			}
		}
		if (bajaByAsset.isEmpty()) {
			return;
		}

		for (PaymentPlanInstallment__c inst : installments) {
			Date baja = bajaByAsset.get(inst.policyAsset__c);
			if (
				baja != null &&
				inst.dueDate__c != null &&
				inst.dueDate__c > baja &&
				isUnpaid(inst)
			) {
				changes.toCancel.add(
					new PaymentPlanInstallment__c(
						Id = inst.Id,
						installmentStatus__c = STATUS_CANCELLED
					)
				);
				changes.touch(inst.paymentPlan__r.insurancePolicy__c);
			}
		}
	}

	private static List<PaymentPlanInstallment__c> split(
		PaymentPlanInstallment__c period,
		List<Inciso> live
	) {
		Boolean byPremium = true;
		Decimal totalPremium = 0;
		for (Inciso inciso : live) {
			if (inciso.premium == null) {
				byPremium = false;
			} else {
				totalPremium += inciso.premium;
			}
		}

		List<PaymentPlanInstallment__c> parts = new List<PaymentPlanInstallment__c>();
		Decimal assigned = 0;
		for (Integer i = 0; i < live.size(); i++) {
			Inciso inciso = live[i];
			Decimal amount;
			if (i == live.size() - 1) {
				amount = period.expectedAmount__c - assigned;
			} else if (byPremium) {
				amount = (period.expectedAmount__c *
					inciso.premium /
					totalPremium)
					.setScale(2, RoundingMode.HALF_UP);
			} else {
				amount = (period.expectedAmount__c / live.size())
					.setScale(2, RoundingMode.HALF_UP);
			}
			assigned += amount;

			PaymentPlanInstallment__c part = period.clone(false, true);
			part.policyAsset__c = inciso.assetId;
			part.expectedAmount__c = amount;
			parts.add(part);
		}
		return parts;
	}

	/**
	 * Incisos de cada póliza, vivos y de baja, ordenados por número. Si dos bienes vivos dicen
	 * ser el mismo inciso, cuenta el primero que se creó: el otro es un duplicado.
	 */
	private static Map<Id, List<Inciso>> loadIncisos(Set<Id> policyIds) {
		Map<Id, List<Inciso>> result = new Map<Id, List<Inciso>>();
		Map<Id, Set<String>> liveCodesByPolicy = new Map<Id, Set<String>>();

		for (InsurancePolicyAsset asset : [
			SELECT
				Id,
				InsurancePolicyId,
				AssetCode,
				AssetName,
				IsActive,
				EffectiveFromDate,
				EffectiveToDate,
				StandardPremiumAmount
			FROM InsurancePolicyAsset
			WHERE InsurancePolicyId IN :policyIds
			ORDER BY CreatedDate, Id
		]) {
			String code = FleetIncisoService.incisoOf(asset);
			if (code == null) {
				continue;
			}

			Inciso inciso = new Inciso();
			inciso.assetId = asset.Id;
			inciso.code = code;
			inciso.live = asset.IsActive != false;
			inciso.fromDate = asset.EffectiveFromDate;
			inciso.toDate = asset.EffectiveToDate;
			inciso.policyId = asset.InsurancePolicyId;
			inciso.premium = asset.StandardPremiumAmount != null &&
				asset.StandardPremiumAmount > 0
				? asset.StandardPremiumAmount
				: null;

			if (!liveCodesByPolicy.containsKey(asset.InsurancePolicyId)) {
				liveCodesByPolicy.put(asset.InsurancePolicyId, new Set<String>());
				result.put(asset.InsurancePolicyId, new List<Inciso>());
			}
			if (
				inciso.live && !liveCodesByPolicy.get(asset.InsurancePolicyId).add(code)
			) {
				continue;
			}
			result.get(asset.InsurancePolicyId).add(inciso);
		}

		for (List<Inciso> incisos : result.values()) {
			incisos.sort();
		}
		fillPremiumsFromFleet(result);
		return result;
	}

	/**
	 * La prima que no está en el bien se toma del inciso de flotilla con el mismo número. Solo se
	 * consulta si a algún inciso le falta.
	 */
	private static void fillPremiumsFromFleet(
		Map<Id, List<Inciso>> incisosByPolicy
	) {
		Set<Id> policyIds = new Set<Id>();
		for (Id policyId : incisosByPolicy.keySet()) {
			for (Inciso inciso : incisosByPolicy.get(policyId)) {
				if (inciso.premium == null) {
					policyIds.add(policyId);
				}
			}
		}
		if (policyIds.isEmpty()) {
			return;
		}

		Map<String, Decimal> fleetPremium = new Map<String, Decimal>();
		for (Inciso_Flotilla__c row : [
			SELECT Poliza__c, Numero_Inciso__c, Prima__c
			FROM Inciso_Flotilla__c
			WHERE
				Poliza__c IN :policyIds
				AND Numero_Inciso__c != NULL
				AND Prima__c > 0
		]) {
			fleetPremium.put(
				row.Poliza__c +
					'|' +
					FleetIncisoService.normalize(
						String.valueOf(row.Numero_Inciso__c.intValue())
					),
				row.Prima__c
			);
		}
		for (Id policyId : policyIds) {
			for (Inciso inciso : incisosByPolicy.get(policyId)) {
				if (inciso.premium == null) {
					inciso.premium = fleetPremium.get(policyId + '|' + inciso.code);
				}
			}
		}
	}

	private static List<Inciso> liveOnly(List<Inciso> incisos) {
		List<Inciso> live = new List<Inciso>();
		if (incisos == null) {
			return live;
		}
		for (Inciso inciso : incisos) {
			if (inciso.live) {
				live.add(inciso);
			}
		}
		return live;
	}

	private static Map<Id, PaymentPlan__c> singleActivePlanByPolicy(
		Set<Id> policyIds
	) {
		Map<Id, PaymentPlan__c> planByPolicy = new Map<Id, PaymentPlan__c>();
		Set<Id> withSeveralPlans = new Set<Id>();

		for (PaymentPlan__c plan : [
			SELECT
				Id,
				insurancePolicy__c,
				planStatus__c,
				premiumFrequency__c,
				expectedTotalAmount__c,
				firstDueDate__c,
				installmentCount__c,
				(
					SELECT
						Id,
						paymentPlan__c,
						paymentPlan__r.insurancePolicy__c,
						policyAsset__c,
						policyParticipant__c,
						installmentStatus__c,
						dueDate__c,
						matchedAmount__c,
						matchedReceipt__c,
						dataOrigin__c,
						carrierReceiptNumber__c
					FROM Installments__r
					ORDER BY dueDate__c, sequenceNumber__c
				)
			FROM PaymentPlan__c
			WHERE
				insurancePolicy__c IN :policyIds
				AND planStatus__c = :PLAN_STATUS_ACTIVE
				AND insurancePolicy__r.Status IN :LIVE_POLICY_STATUSES
		]) {
			if (planByPolicy.containsKey(plan.insurancePolicy__c)) {
				withSeveralPlans.add(plan.insurancePolicy__c);
			}
			planByPolicy.put(plan.insurancePolicy__c, plan);
		}

		for (Id policyId : withSeveralPlans) {
			planByPolicy.remove(policyId);
		}
		return planByPolicy;
	}

	private static Boolean comesFromCarrier(
		List<PaymentPlanInstallment__c> installments
	) {
		for (PaymentPlanInstallment__c inst : installments) {
			if (
				inst.dataOrigin__c != null ||
				inst.carrierReceiptNumber__c != null ||
				inst.policyParticipant__c != null
			) {
				return true;
			}
		}
		return false;
	}

	private static Boolean isSplit(List<PaymentPlanInstallment__c> installments) {
		for (PaymentPlanInstallment__c inst : installments) {
			if (inst.policyAsset__c != null) {
				return true;
			}
		}
		return false;
	}

	private static Boolean isUnpaid(PaymentPlanInstallment__c inst) {
		return UNPAID_STATUSES.contains(inst.installmentStatus__c) &&
			inst.matchedReceipt__c == null &&
			(inst.matchedAmount__c == null ||
			inst.matchedAmount__c == 0);
	}

	private static Boolean isRelevantChange(
		InsurancePolicyAsset asset,
		InsurancePolicyAsset previous
	) {
		return asset.InsurancePolicyId != previous.InsurancePolicyId ||
			asset.IsActive != previous.IsActive ||
			asset.EffectiveFromDate != previous.EffectiveFromDate ||
			asset.EffectiveToDate != previous.EffectiveToDate ||
			asset.AssetCode != previous.AssetCode ||
			asset.AssetName != previous.AssetName ||
			asset.StandardPremiumAmount != previous.StandardPremiumAmount;
	}

	/**
	 * Lo que hay que guardar de todas las pólizas del lote, para guardarlo de una vez.
	 */
	private class Changes {
		List<PaymentPlanInstallment__c> toInsert = new List<PaymentPlanInstallment__c>();
		List<PaymentPlanInstallment__c> toDelete = new List<PaymentPlanInstallment__c>();
		List<PaymentPlanInstallment__c> toCancel = new List<PaymentPlanInstallment__c>();
		Set<Id> touched = new Set<Id>();

		void touch(Id policyId) {
			touched.add(policyId);
		}

		void review(Id policyId, String message) {
			CobranzaLog.warn(
					CobranzaLog.STAGE_PLAN_PAGOS,
					CobranzaLog.EVENT_INSTALLMENTS_BY_INCISO_REVIEW,
					message
				)
				.onRecord(policyId);
		}

		void save() {
			removeReferenced();
			if (!toDelete.isEmpty()) {
				delete toDelete;
			}
			if (!toInsert.isEmpty()) {
				insert toInsert;
			}
			if (!toCancel.isEmpty()) {
				update toCancel;
			}
			for (Id policyId : touched) {
				CobranzaLog.info(
						CobranzaLog.STAGE_PLAN_PAGOS,
						CobranzaLog.EVENT_INSTALLMENTS_BY_INCISO,
						'Cuotas por inciso al día con las altas y bajas de la flotilla.'
					)
					.onRecord(policyId);
			}
		}

		/**
		 * Una cuota a la que ya apunta un pago o una conciliación no se borra: es historia.
		 */
		void removeReferenced() {
			if (toDelete.isEmpty()) {
				return;
			}
			Map<Id, PaymentPlanInstallment__c> byId = new Map<Id, PaymentPlanInstallment__c>(
				toDelete
			);
			for (InboundInsurancePayment__c payment : [
				SELECT candidateInstallment__c
				FROM InboundInsurancePayment__c
				WHERE candidateInstallment__c IN :byId.keySet()
			]) {
				byId.remove(payment.candidateInstallment__c);
			}
			for (PaymentReconciliation__c reconciliation : [
				SELECT paymentPlanInstallment__c
				FROM PaymentReconciliation__c
				WHERE paymentPlanInstallment__c IN :byId.keySet()
			]) {
				byId.remove(reconciliation.paymentPlanInstallment__c);
			}
			toDelete = byId.values();
		}
	}

	/**
	 * Un inciso de la póliza: su bien, su número, su prima y sus fechas.
	 */
	private class Inciso implements Comparable {
		Id assetId;
		Id policyId;
		String code;
		Boolean live;
		Decimal premium;
		Date fromDate;
		Date toDate;

		public Integer compareTo(Object other) {
			Inciso that = (Inciso) other;
			if (code.isNumeric() && that.code.isNumeric()) {
				Long a = Long.valueOf(code);
				Long b = Long.valueOf(that.code);
				return a == b ? 0 : (a < b ? -1 : 1);
			}
			return code.compareTo(that.code);
		}
	}
}
