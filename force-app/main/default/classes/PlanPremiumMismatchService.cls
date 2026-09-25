/**
 *   @name: PlanPremiumMismatchService
 *   @version: 1.0
 *   @creation date: 25/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Marca la poliza que ya cobro algo cuando su prima deja de coincidir con la
 *                 del plan de pagos, y la desmarca cuando vuelven a coincidir (KAN-447).
 *                 Es la otra mitad de PaymentPlanRegenerationService: un plan sin cobros se
 *                 rehace; uno con cobros no se toca, porque se perderia el historial, y el
 *                 descuadre queda a la vista en la vista «Polizas con prima desalineada».
 *                 La prima del plan es el importe del plan vigente mas lo ya cobrado o
 *                 condonado en los planes que reemplazo: un cambio de frecuencia deja en el
 *                 plan nuevo solo el saldo pendiente, y compararlo solo a el marcaria un
 *                 descuadre que no existe.
 */
public with sharing class PlanPremiumMismatchService {
	private static final String PLAN_STATUS_ACTIVE = 'Activo';
	private static final String PLAN_STATUS_REPLACED = 'Reemplazado';

	// Lo que ya se consumio de un plan reemplazado: lo cobrado y lo condonado. Lo pendiente
	// paso al plan que lo reemplazo y se cuenta ahi.
	private static final Set<String> SETTLED_INSTALLMENT_STATUSES = new Set<String>{
		'Conciliado',
		'Condonado'
	};

	// Fuerza el fallo del guardado de estas polizas para probar que el fallo queda
	// registrado y no detiene a las demas.
	@TestVisible
	private static Set<Id> failForTest = new Set<Id>();

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Revisa las polizas cuya prima cambio en este guardado. Corre despues de
	 *               la regeneracion del plan, asi que una poliza sin cobros ya tiene su plan
	 *               al dia y no se marca.
	 * @param newPolicies: Registros nuevos del trigger.
	 * @param oldMap: Valores anteriores de las polizas.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	public static void evaluateAfterUpdate(
		List<InsurancePolicy> newPolicies,
		Map<Id, InsurancePolicy> oldMap
	) {
		if (newPolicies == null || oldMap == null) {
			return;
		}

		Set<Id> changedPremiumIds = new Set<Id>();

		for (InsurancePolicy policy : newPolicies) {
			InsurancePolicy oldPolicy = policy == null ? null : oldMap.get(policy.Id);

			if (oldPolicy != null && premiumOf(policy) != premiumOf(oldPolicy)) {
				changedPremiumIds.add(policy.Id);
			}
		}

		if (!changedPremiumIds.isEmpty()) {
			evaluate(changedPremiumIds, changedPremiumIds);
		}
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Lee la prima sin romper cuando el registro no la trae: el manejador del
	 *               trigger tambien se invoca con polizas consultadas sin ese campo.
	 * @param policy: Poliza.
	 * @return: Decimal Prima, o null si el registro no la trae.
	 * @exception:
	 * @throws:
	 */
	private static Decimal premiumOf(InsurancePolicy policy) {
		try {
			return policy.PremiumAmount;
		} catch (SObjectException e) {
			return null;
		}
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Vuelve a revisar las polizas marcadas cuando cambia su plan, para quitar
	 *               la marca en cuanto el plan vuelve a cuadrar con la prima. Las no marcadas
	 *               se ignoran: un cambio del plan no crea un descuadre de prima.
	 * @param policyIds: Polizas cuyo plan cambio.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	public static void reevaluateMarked(Set<Id> policyIds) {
		if (policyIds == null || policyIds.isEmpty()) {
			return;
		}

		Set<Id> markedIds = new Map<Id, InsurancePolicy>(
				[
					SELECT Id
					FROM InsurancePolicy
					WHERE Id IN :policyIds AND planPremiumMismatch__c = TRUE
				]
			)
			.keySet();

		if (!markedIds.isEmpty()) {
			evaluate(markedIds, new Set<Id>());
		}
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Compara la prima de cada poliza con la de su plan y guarda la marca.
	 * @param policyIds: Polizas a revisar.
	 * @param changedPremiumIds: Las que acaban de recibir una prima nueva; si siguen
	 *                           desalineadas, cuenta como una comunicacion nueva.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	private static void evaluate(Set<Id> policyIds, Set<Id> changedPremiumIds) {
		Map<Id, Decimal> planPremiumByPolicyId = selectPlanPremiumByPolicyId(
			policyIds
		);
		Set<Id> withoutCollections = PaymentPlanRegenerationService.selectPoliciesWithoutCollections(
			policyIds
		);
		List<InsurancePolicy> toUpdate = new List<InsurancePolicy>();
		Map<Id, String> logMessageByPolicyId = new Map<Id, String>();

		for (InsurancePolicy policy : [
			SELECT
				Id,
				PremiumAmount,
				planPremiumMismatch__c,
				planPremiumAmount__c,
				premiumMismatchSince__c
			FROM InsurancePolicy
			WHERE Id IN :policyIds
		]) {
			Decimal planPremium = planPremiumByPolicyId.get(policy.Id);
			Boolean mismatch =
				planPremium != null &&
				policy.PremiumAmount != null &&
				!withoutCollections.contains(policy.Id) &&
				policy.PremiumAmount.setScale(2) != planPremium.setScale(2);

			if (mismatch) {
				Boolean newCommunication =
					!policy.planPremiumMismatch__c ||
					changedPremiumIds.contains(policy.Id);

				if (!newCommunication && policy.planPremiumAmount__c == planPremium) {
					continue;
				}

				InsurancePolicy marked = new InsurancePolicy(
					Id = policy.Id,
					planPremiumMismatch__c = true,
					planPremiumAmount__c = planPremium,
					premiumMismatchSince__c = newCommunication
						? System.now()
						: policy.premiumMismatchSince__c
				);
				toUpdate.add(marked);

				if (newCommunication) {
					logMessageByPolicyId.put(
						policy.Id,
						'La prima de la poliza no coincide con la del plan y la poliza ya ' +
							'cobro: el plan no se toca. Prima del plan: ' +
							planPremium.setScale(2) +
							'. Prima de la poliza: ' +
							policy.PremiumAmount.setScale(2) +
							'. Diferencia: ' +
							(policy.PremiumAmount - planPremium).setScale(2) +
							'.'
					);
				}
				continue;
			}

			if (policy.planPremiumMismatch__c) {
				toUpdate.add(
					new InsurancePolicy(
						Id = policy.Id,
						planPremiumMismatch__c = false,
						planPremiumAmount__c = null,
						premiumMismatchSince__c = null
					)
				);
				logMessageByPolicyId.put(policy.Id, null);
			}
		}

		save(toUpdate, logMessageByPolicyId);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Guarda las marcas poliza por poliza y deja constancia de cada una.
	 * @param toUpdate: Polizas a guardar.
	 * @param logMessageByPolicyId: Mensaje del descuadre, o null si la marca se quita.
	 *                              Las que no estan no se registran.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	private static void save(
		List<InsurancePolicy> toUpdate,
		Map<Id, String> logMessageByPolicyId
	) {
		if (toUpdate.isEmpty()) {
			return;
		}

		if (Test.isRunningTest() && !failForTest.isEmpty()) {
			for (InsurancePolicy policy : toUpdate) {
				if (failForTest.contains(policy.Id)) {
					policy.Name = null;
				}
			}
		}

		List<Database.SaveResult> results = Database.update(toUpdate, false);

		for (Integer i = 0; i < results.size(); i++) {
			Id policyId = toUpdate[i].Id;

			if (!results[i].isSuccess()) {
				List<String> errors = new List<String>();

				for (Database.Error error : results[i].getErrors()) {
					errors.add(error.getMessage());
				}

				CobranzaLog.error(
						CobranzaLog.STAGE_PLAN_PAGOS,
						CobranzaLog.EVENT_PLAN_PREMIUM_MISMATCH_FAILED,
						'No se pudo guardar la marca de prima desalineada. Motivo: ' +
						String.join(errors, '; ')
					)
					.onRecord(policyId);
				continue;
			}

			if (!logMessageByPolicyId.containsKey(policyId)) {
				continue;
			}

			String message = logMessageByPolicyId.get(policyId);

			if (message == null) {
				CobranzaLog.info(
						CobranzaLog.STAGE_PLAN_PAGOS,
						CobranzaLog.EVENT_PLAN_PREMIUM_MISMATCH_CLEARED,
						'La prima de la poliza vuelve a coincidir con la del plan: se quita la ' +
						'marca de prima desalineada.'
					)
					.onRecord(policyId);
			} else {
				CobranzaLog.warn(
						CobranzaLog.STAGE_PLAN_PAGOS,
						CobranzaLog.EVENT_PLAN_PREMIUM_MISMATCH,
						message
					)
					.onRecord(policyId);
			}
		}

		AppLogger.flush();
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Calcula la prima que cobra el plan de cada poliza: el importe del plan
	 *               vigente (el activo o, si no hay, el ultimo no reemplazado) mas lo cobrado
	 *               o condonado en los planes que reemplazo. Sin plan vigente no hay con que
	 *               comparar y la poliza no aparece en el mapa.
	 * @param policyIds: Polizas a calcular.
	 * @return: Map<Id, Decimal> Prima del plan por poliza.
	 * @exception:
	 * @throws:
	 */
	@TestVisible
	private static Map<Id, Decimal> selectPlanPremiumByPolicyId(
		Set<Id> policyIds
	) {
		Map<Id, PaymentPlan__c> currentPlanByPolicyId = new Map<Id, PaymentPlan__c>();
		Set<Id> replacedPlanIds = new Set<Id>();

		for (PaymentPlan__c plan : [
			SELECT Id, insurancePolicy__c, planStatus__c, expectedTotalAmount__c
			FROM PaymentPlan__c
			WHERE insurancePolicy__c IN :policyIds
			ORDER BY CreatedDate DESC
		]) {
			if (plan.planStatus__c == PLAN_STATUS_REPLACED) {
				replacedPlanIds.add(plan.Id);
				continue;
			}

			PaymentPlan__c chosen = currentPlanByPolicyId.get(
				plan.insurancePolicy__c
			);

			if (
				chosen == null ||
				(plan.planStatus__c == PLAN_STATUS_ACTIVE &&
				chosen.planStatus__c != PLAN_STATUS_ACTIVE)
			) {
				currentPlanByPolicyId.put(plan.insurancePolicy__c, plan);
			}
		}

		Map<Id, Decimal> settledByPolicyId = new Map<Id, Decimal>();

		if (!replacedPlanIds.isEmpty()) {
			for (AggregateResult row : [
				SELECT
					paymentPlan__r.insurancePolicy__c policyId,
					SUM(expectedAmount__c) total
				FROM PaymentPlanInstallment__c
				WHERE
					paymentPlan__c IN :replacedPlanIds
					AND installmentStatus__c IN :SETTLED_INSTALLMENT_STATUSES
				GROUP BY paymentPlan__r.insurancePolicy__c
			]) {
				settledByPolicyId.put(
					(Id) row.get('policyId'),
					(Decimal) row.get('total')
				);
			}
		}

		Map<Id, Decimal> planPremiumByPolicyId = new Map<Id, Decimal>();

		for (Id policyId : currentPlanByPolicyId.keySet()) {
			Decimal current = currentPlanByPolicyId.get(policyId)
				.expectedTotalAmount__c;

			if (current == null) {
				continue;
			}

			Decimal settled = settledByPolicyId.get(policyId);
			planPremiumByPolicyId.put(
				policyId,
				current + (settled == null ? 0 : settled)
			);
		}

		return planPremiumByPolicyId;
	}
}
