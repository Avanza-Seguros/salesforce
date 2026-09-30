/**
 *   @name: PaymentPlanRegenerationService
 *   @version: 1.0
 *   @creation date: 25/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Rehace el plan de pagos de una poliza que todavia no cobro nada cuando se
 *                 corrige su frecuencia, su prima o su fecha de pago (KAN-446).
 *                 La poliza nace con lo cotizado y la aseguradora emite a menudo otra cosa:
 *                 mientras no haya ningun cobro no hay historial que conservar, asi que el
 *                 plan se recalcula entero sobre el mismo registro. Un plan con historia sigue
 *                 pasando por PaymentPlanFrequencyChangeService, sin ningun cambio.
 *                 Solo reacciona a cambios de PremiumFrequency, PremiumAmount y
 *                 PaymentDueDate, nunca a Status: asi no choca con la rehabilitacion ni con la
 *                 creacion del plan inicial.
 */
public with sharing class PaymentPlanRegenerationService {
	private static final String PLAN_STATUS_ACTIVE = 'Activo';

	private static final Set<String> OPERATIONAL_POLICY_STATUSES = new Set<String>{
		'Inicial',
		'Vigente'
	};

	// Estados de cuota que solo se alcanzan con dinero de por medio o con una decision
	// sobre la deuda: cualquiera de los dos es historia del plan.
	private static final Set<String> INSTALLMENT_STATUSES_WITH_HISTORY = new Set<String>{
		'Conciliado',
		'Condonado'
	};

	// Polizas que el before update aprobo para rehacer su plan; el after update las consume.
	private static Set<Id> scheduledPolicyIds = new Set<Id>();

	// Mientras sea mayor que cero, los guardados de poliza no rehacen planes. Lo usa el
	// resumen de cobranza, que mueve PaymentDueDate a la proxima cuota.
	private static Integer suspendDepth = 0;

	// Fuerza el fallo del guardado del plan de estas polizas para probar que el fallo queda
	// registrado y no detiene a las demas del lote.
	@TestVisible
	private static Set<Id> failForTest = new Set<Id>();

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Deja de rehacer planes hasta la llamada a resume(). Para guardados de la
	 *               poliza que hace el propio motor y que no son una correccion de nadie.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	public static void suspend() {
		suspendDepth++;
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Deshace un suspend().
	 * @return:
	 * @exception:
	 * @throws:
	 */
	public static void resume() {
		if (suspendDepth > 0) {
			suspendDepth--;
		}
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Indica si la poliza va a rehacer su plan en este guardado, para que el
	 *               cambio de frecuencia no la trate como un plan con historia.
	 * @param policyId: Identificador de la poliza.
	 * @return: Boolean Verdadero si el plan se rehace.
	 * @exception:
	 * @throws:
	 */
	public static Boolean isScheduled(Id policyId) {
		return policyId != null && scheduledPolicyIds.contains(policyId);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Devuelve las polizas que todavia no cobraron nada: ninguna cuota
	 *               conciliada, condonada, con recibo o con importe aplicado; ningun recibo
	 *               de la poliza; ningun pago de la integracion ni conciliacion apuntando a
	 *               sus cuotas. Es el unico criterio de "plan sin cobros" del motor: lo usan
	 *               tambien las historias que ajustan el plan desde la aseguradora.
	 * @param policyIds: Polizas a evaluar.
	 * @return: Set<Id> Las que no tienen ningun cobro.
	 * @exception:
	 * @throws:
	 */
	public static Set<Id> selectPoliciesWithoutCollections(Set<Id> policyIds) {
		Set<Id> result = new Set<Id>();

		if (policyIds == null || policyIds.isEmpty()) {
			return result;
		}

		result.addAll(policyIds);
		result.removeAll(
			new CollectionHistoryReader().selectWithHistory(policyIds)
		);
		return result;
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Antes del guardado, aparta las polizas cuyo plan se va a rehacer: siguen
	 *               operativas, cambiaron frecuencia, prima o fecha, no cobraron nada, tienen
	 *               un unico plan activo y su frecuencia nueva la soporta la cobranza. Las
	 *               demas siguen el camino de siempre, con sus mensajes de siempre.
	 * @param newPolicies: Registros nuevos del trigger.
	 * @param oldMap: Valores anteriores de las polizas.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	public static void prepareBeforeUpdate(
		List<InsurancePolicy> newPolicies,
		Map<Id, InsurancePolicy> oldMap
	) {
		if (newPolicies == null || oldMap == null) {
			return;
		}

		// Cada guardado decide de nuevo: una marca de un guardado anterior que no llego a
		// completarse no puede arrastrarse a este.
		for (InsurancePolicy policy : newPolicies) {
			if (policy != null && policy.Id != null) {
				scheduledPolicyIds.remove(policy.Id);
			}
		}

		if (suspendDepth > 0) {
			return;
		}

		Map<Id, InsurancePolicy> candidates = new Map<Id, InsurancePolicy>();

		for (InsurancePolicy policy : newPolicies) {
			if (policy == null || policy.Id == null) {
				continue;
			}

			InsurancePolicy oldPolicy = oldMap.get(policy.Id);

			if (
				oldPolicy == null ||
				!isOperational(policy) ||
				!isOperational(oldPolicy) ||
				!hasTermsChange(policy, oldPolicy)
			) {
				continue;
			}

			candidates.put(policy.Id, policy);
		}

		if (candidates.isEmpty()) {
			return;
		}

		Map<Id, PaymentPlan__c> planByPolicyId = selectSingleActivePlanByPolicyId(
			selectPoliciesWithoutCollections(candidates.keySet())
		);

		for (Id policyId : planByPolicyId.keySet()) {
			PaymentPlan__c target = new PaymentPlan__c();
			InsurancePolicyTriggerHandler.applyPolicyTerms(
				target,
				candidates.get(policyId)
			);

			// Frecuencia que la cobranza no soporta: no se toca el plan y el cambio de
			// frecuencia la rechaza con su mensaje de siempre.
			if (target.premiumFrequency__c == null) {
				continue;
			}

			if (sameTerms(planByPolicyId.get(policyId), target)) {
				continue;
			}

			scheduledPolicyIds.add(policyId);
		}
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Despues del guardado, rehace el plan de las polizas apartadas: guarda
	 *               los datos nuevos en el mismo plan, borra sus cuotas y genera el
	 *               calendario otra vez. Una poliza que falla no detiene a las demas; el fallo
	 *               y cada plan rehecho quedan en el registro de la aplicacion.
	 * @param newPolicies: Registros nuevos del trigger.
	 * @param oldMap: Valores anteriores de las polizas.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	public static void regenerateAfterUpdate(
		List<InsurancePolicy> newPolicies,
		Map<Id, InsurancePolicy> oldMap
	) {
		if (scheduledPolicyIds.isEmpty() || newPolicies == null || oldMap == null) {
			return;
		}

		Map<Id, InsurancePolicy> policiesById = new Map<Id, InsurancePolicy>();

		for (InsurancePolicy policy : newPolicies) {
			if (policy != null && scheduledPolicyIds.remove(policy.Id)) {
				policiesById.put(policy.Id, policy);
			}
		}

		if (policiesById.isEmpty()) {
			return;
		}

		Map<Id, PaymentPlan__c> planByPolicyId = selectSingleActivePlanByPolicyId(
			policiesById.keySet()
		);
		List<PaymentPlan__c> plansToUpdate = new List<PaymentPlan__c>();
		Map<Id, String> previousTermsByPlanId = new Map<Id, String>();

		for (Id policyId : planByPolicyId.keySet()) {
			PaymentPlan__c plan = planByPolicyId.get(policyId);
			String previousTerms = describeTerms(plan);

			InsurancePolicyTriggerHandler.applyPolicyTerms(
				plan,
				policiesById.get(policyId)
			);

			if (previousTerms == describeTerms(plan)) {
				continue;
			}

			if (Test.isRunningTest() && failForTest.contains(policyId)) {
				plan.premiumFrequency__c = 'Frecuencia invalida';
			}

			previousTermsByPlanId.put(plan.Id, previousTerms);
			plansToUpdate.add(plan);
		}

		if (plansToUpdate.isEmpty()) {
			return;
		}

		List<PaymentPlan__c> savedPlans = new List<PaymentPlan__c>();
		List<Database.SaveResult> updateResults = Database.update(
			plansToUpdate,
			false
		);

		for (Integer i = 0; i < updateResults.size(); i++) {
			if (updateResults[i].isSuccess()) {
				savedPlans.add(plansToUpdate[i]);
				continue;
			}

			logFailure(
				plansToUpdate[i].insurancePolicy__c,
				'No se pudo guardar el plan con los datos nuevos. Motivo: ' +
				joinErrors(updateResults[i].getErrors())
			);
		}

		List<PaymentPlan__c> plansToRebuild = deleteInstallments(savedPlans);
		PaymentPlanTriggerHandler.generateInstallments(plansToRebuild);

		for (PaymentPlan__c plan : plansToRebuild) {
			CobranzaLog.info(
					CobranzaLog.STAGE_PLAN_PAGOS,
					CobranzaLog.EVENT_PAYMENT_PLAN_REGENERATED,
					'Plan sin cobros rehecho. Antes: ' +
						previousTermsByPlanId.get(plan.Id) +
						'. Ahora: ' +
						describeTerms(plan) +
						'.'
				)
				.onRecord(plan.insurancePolicy__c);
		}

		AppLogger.flush();
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Borra las cuotas de los planes que se van a rehacer. Un plan cuyas
	 *               cuotas no se pudieron borrar no se rehace, para no dejarlo con cuotas
	 *               duplicadas.
	 * @param plans: Planes ya guardados con los datos nuevos.
	 * @return: List<PaymentPlan__c> Planes listos para generar su calendario.
	 * @exception:
	 * @throws:
	 */
	private static List<PaymentPlan__c> deleteInstallments(
		List<PaymentPlan__c> plans
	) {
		if (plans.isEmpty()) {
			return plans;
		}

		Map<Id, PaymentPlan__c> plansById = new Map<Id, PaymentPlan__c>(plans);
		List<PaymentPlanInstallment__c> installments = [
			SELECT Id, paymentPlan__c
			FROM PaymentPlanInstallment__c
			WHERE paymentPlan__c IN :plansById.keySet()
		];

		if (installments.isEmpty()) {
			return plans;
		}

		List<Database.DeleteResult> deleteResults = Database.delete(
			installments,
			false
		);
		Map<Id, List<String>> errorsByPlanId = new Map<Id, List<String>>();

		for (Integer i = 0; i < deleteResults.size(); i++) {
			if (deleteResults[i].isSuccess()) {
				continue;
			}

			Id planId = installments[i].paymentPlan__c;

			if (!errorsByPlanId.containsKey(planId)) {
				errorsByPlanId.put(planId, new List<String>());
			}

			errorsByPlanId.get(planId).add(joinErrors(deleteResults[i].getErrors()));
		}

		for (Id planId : errorsByPlanId.keySet()) {
			logFailure(
				plansById.get(planId).insurancePolicy__c,
				'El plan guardo los datos nuevos pero no se pudieron borrar sus cuotas ' +
					'anteriores; revisar el plan a mano. Motivo: ' +
					String.join(errorsByPlanId.get(planId), '; ')
			);
			plansById.remove(planId);
		}

		return plansById.values();
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Carga el plan activo de cada poliza. Las que tienen mas de uno quedan
	 *               fuera: no se sabe cual rehacer y el cambio de frecuencia ya lo rechaza.
	 * @param policyIds: Polizas a consultar.
	 * @return: Map<Id, PaymentPlan__c> Plan activo por poliza.
	 * @exception:
	 * @throws:
	 */
	private static Map<Id, PaymentPlan__c> selectSingleActivePlanByPolicyId(
		Set<Id> policyIds
	) {
		Map<Id, PaymentPlan__c> planByPolicyId = new Map<Id, PaymentPlan__c>();

		if (policyIds == null || policyIds.isEmpty()) {
			return planByPolicyId;
		}

		Set<Id> withSeveralPlans = new Set<Id>();

		for (PaymentPlan__c plan : [
			SELECT
				Id,
				insurancePolicy__c,
				planStatus__c,
				premiumFrequency__c,
				expectedTotalAmount__c,
				firstDueDate__c,
				installmentCount__c
			FROM PaymentPlan__c
			WHERE
				insurancePolicy__c IN :policyIds
				AND planStatus__c = :PLAN_STATUS_ACTIVE
		]) {
			if (planByPolicyId.containsKey(plan.insurancePolicy__c)) {
				withSeveralPlans.add(plan.insurancePolicy__c);
			}

			planByPolicyId.put(plan.insurancePolicy__c, plan);
		}

		for (Id policyId : withSeveralPlans) {
			planByPolicyId.remove(policyId);
		}

		return planByPolicyId;
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Indica si cambio alguno de los tres datos que definen el plan. La fecha
	 *               se compara por dia: el resumen de cobranza la guarda a medianoche de
	 *               Mexico y una pantalla puede guardarla a otra hora del mismo dia.
	 * @param policy: Poliza nueva.
	 * @param oldPolicy: Poliza anterior.
	 * @return: Boolean Verdadero si cambio frecuencia, prima o fecha de pago.
	 * @exception:
	 * @throws:
	 */
	private static Boolean hasTermsChange(
		InsurancePolicy policy,
		InsurancePolicy oldPolicy
	) {
		return policy.PremiumFrequency != oldPolicy.PremiumFrequency ||
			policy.PremiumAmount != oldPolicy.PremiumAmount ||
			dayOf(policy.PaymentDueDate) != dayOf(oldPolicy.PaymentDueDate);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Compara los datos del plan guardado con los que le tocarian.
	 * @param plan: Plan guardado.
	 * @param target: Plan calculado desde la poliza.
	 * @return: Boolean Verdadero si no hay nada que rehacer.
	 * @exception:
	 * @throws:
	 */
	private static Boolean sameTerms(PaymentPlan__c plan, PaymentPlan__c target) {
		return describeTerms(plan) == describeTerms(target);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Resume los datos del plan en un texto legible para el registro de la
	 *               aplicacion; sirve tambien para comparar dos planes.
	 * @param plan: Plan a describir.
	 * @return: String Frecuencia, prima, primera fecha y cantidad de cuotas.
	 * @exception:
	 * @throws:
	 */
	private static String describeTerms(PaymentPlan__c plan) {
		return plan.premiumFrequency__c +
			', prima ' +
			(plan.expectedTotalAmount__c == null
				? 'null'
				: String.valueOf(plan.expectedTotalAmount__c.setScale(2))) +
			', primera cuota ' +
			String.valueOf(plan.firstDueDate__c) +
			', ' +
			(plan.installmentCount__c == null
				? 'null'
				: String.valueOf(plan.installmentCount__c.intValue())) +
			' cuotas';
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Dia de una fecha y hora, con el mismo criterio que usa el plan inicial.
	 * @param value: Fecha y hora.
	 * @return: Date Dia en GMT.
	 * @exception:
	 * @throws:
	 */
	private static Date dayOf(Datetime value) {
		return value == null ? null : value.dateGmt();
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Indica si la poliza esta en un estado operativo para cobranza.
	 * @param policy: Poliza a evaluar.
	 * @return: Boolean Resultado de la validacion.
	 * @exception:
	 * @throws:
	 */
	private static Boolean isOperational(InsurancePolicy policy) {
		return policy != null &&
			OPERATIONAL_POLICY_STATUSES.contains(policy.Status);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Registra que no se pudo rehacer el plan de una poliza.
	 * @param policyId: Poliza afectada.
	 * @param message: Motivo.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	private static void logFailure(Id policyId, String message) {
		CobranzaLog.error(
				CobranzaLog.STAGE_PLAN_PAGOS,
				CobranzaLog.EVENT_PAYMENT_PLAN_REGENERATION_FAILED,
				message
			)
			.onRecord(policyId);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Une los mensajes de error de una operacion DML.
	 * @param errors: Errores devueltos por la plataforma.
	 * @return: String Mensajes separados por punto y coma.
	 * @exception:
	 * @throws:
	 */
	private static String joinErrors(List<Database.Error> errors) {
		List<String> messages = new List<String>();

		for (Database.Error error : errors) {
			messages.add(error.getMessage());
		}

		return String.join(messages, '; ');
	}

	/**
	 *   @name: CollectionHistoryReader
	 *   @creation date: 25/09/2026
	 *   @author: Javier Torres - Volestra
	 *   @description: Busca la historia de cobro sin reglas de comparticion. Quien corrige
	 *                 la poliza puede no ver los recibos ni los pagos de la integracion, y
	 *                 si no los viera tomaria por virgen un plan que ya cobro y lo borraria.
	 */
	private without sharing class CollectionHistoryReader {
		/**
		 * @creation date: 25/09/2026
		 * @author: Javier Torres - Volestra
		 * @description: Devuelve las polizas que tienen al menos un rastro de cobro.
		 * @param policyIds: Polizas a evaluar.
		 * @return: Set<Id> Polizas con historia de cobro.
		 * @exception:
		 * @throws:
		 */
		Set<Id> selectWithHistory(Set<Id> policyIds) {
			Set<Id> withHistory = new Set<Id>();

			for (AggregateResult row : [
				SELECT insurancePolicy__c policyId
				FROM PolicyPaymentReceipt__c
				WHERE insurancePolicy__c IN :policyIds
				GROUP BY insurancePolicy__c
			]) {
				withHistory.add((Id) row.get('policyId'));
			}

			for (AggregateResult row : [
				SELECT paymentPlan__r.insurancePolicy__c policyId
				FROM PaymentPlanInstallment__c
				WHERE
					paymentPlan__r.insurancePolicy__c IN :policyIds
					AND (matchedReceipt__c != NULL
					OR matchedAmount__c > 0
					OR installmentStatus__c IN :INSTALLMENT_STATUSES_WITH_HISTORY)
				GROUP BY paymentPlan__r.insurancePolicy__c
			]) {
				withHistory.add((Id) row.get('policyId'));
			}

			for (AggregateResult row : [
				SELECT
					candidateInstallment__r.paymentPlan__r.insurancePolicy__c policyId
				FROM InboundInsurancePayment__c
				WHERE
					candidateInstallment__r.paymentPlan__r.insurancePolicy__c IN :policyIds
				GROUP BY candidateInstallment__r.paymentPlan__r.insurancePolicy__c
			]) {
				withHistory.add((Id) row.get('policyId'));
			}

			for (AggregateResult row : [
				SELECT
					paymentPlanInstallment__r.paymentPlan__r.insurancePolicy__c policyId
				FROM PaymentReconciliation__c
				WHERE
					paymentPlanInstallment__r.paymentPlan__r.insurancePolicy__c IN :policyIds
				GROUP BY paymentPlanInstallment__r.paymentPlan__r.insurancePolicy__c
			]) {
				withHistory.add((Id) row.get('policyId'));
			}

			return withHistory;
		}
	}
}
