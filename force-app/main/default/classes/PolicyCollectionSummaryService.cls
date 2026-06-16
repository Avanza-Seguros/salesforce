/**
 *   @name: PolicyCollectionSummaryService
 *   @version: 1.0
 *   @creation date: 12/06/2026
 *   @author: Javier Torres - Volestra
 *   @description: Mantiene el resumen operativo de cobranza en InsurancePolicy a partir
 *                 del plan de pagos vigente y sus cuotas. Escribe los campos estandar
 *                 PaidToDate (pagada hasta) y PaymentDueDate (proxima fecha estandar: se
 *                 mantiene al dia con la proxima cuota pero nunca se vacia, por la regla
 *                 PremiumFieldsRequired) y los campos custom collectionNextDueDate__c
 *                 (proxima fecha precisa, que si queda vacia al completar el plan) y
 *                 collectionPaymentStatus__c (estado de pago). La frecuencia
 *                 vigente se refleja en el estandar PremiumFrequency, que ya se mantiene
 *                 actualizado por el cambio de frecuencia, por lo que no se escribe aqui.
 *                 No es la fuente de verdad: solo refleja el estado del modulo de pagos.
 */
public with sharing class PolicyCollectionSummaryService {
	private static final String PLAN_STATUS_ACTIVE = 'Activo';
	private static final String PLAN_STATUS_COMPLETED = 'Completado';
	private static final String PLAN_STATUS_REPLACED = 'Reemplazado';
	private static final String PLAN_STATUS_CANCELLED = 'Cancelado';

	private static final String INSTALLMENT_STATUS_RECONCILED = 'Conciliado';
	private static final Set<String> OPEN_INSTALLMENT_STATUSES = new Set<String>{
		'Pendiente',
		'Vencido'
	};

	private static final String PAYMENT_STATUS_NONE = 'Sin pago';
	private static final String PAYMENT_STATUS_CURRENT = 'Al dia';
	private static final String PAYMENT_STATUS_OVERDUE = 'Vencido';
	private static final String PAYMENT_STATUS_COMPLETED = 'Completado';

	/**
	 * @creation date: 12/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Recalcula y actualiza el resumen de cobranza de las polizas indicadas
	 *               a partir del plan vigente (no Reemplazado/Cancelado) y sus cuotas.
	 *               Si una poliza no tiene plan vigente, deja el resumen en "Sin pago"
	 *               con fechas vacias. Solo emite un DML sobre las polizas afectadas.
	 * @param policyIds: IDs de InsurancePolicy a recalcular.
	 * @return
	 */
	public static void recalculate(Set<Id> policyIds) {
		if (policyIds == null || policyIds.isEmpty()) {
			return;
		}

		Map<Id, PaymentPlan__c> vigentePlanByPolicy = selectVigentePlanByPolicy(
			policyIds
		);

		Set<Id> planIds = new Set<Id>();
		for (PaymentPlan__c plan : vigentePlanByPolicy.values()) {
			planIds.add(plan.Id);
		}
		Map<Id, List<PaymentPlanInstallment__c>> installmentsByPlan = loadInstallmentsByPlan(
			planIds
		);

		Date today = Date.today();
		List<InsurancePolicy> toUpdate = new List<InsurancePolicy>();

		for (Id policyId : policyIds) {
			PaymentPlan__c plan = vigentePlanByPolicy.get(policyId);
			InsurancePolicy pol = new InsurancePolicy(Id = policyId);

			if (plan == null) {
				pol.PaidToDate = null;
				pol.collectionNextDueDate__c = null;
				pol.collectionPaymentStatus__c = PAYMENT_STATUS_NONE;
				toUpdate.add(pol);
				continue;
			}

			SummaryResult result = summarize(
				plan,
				installmentsByPlan.get(plan.Id),
				today
			);
			pol.PaidToDate = result.paidThroughDate;
			pol.collectionNextDueDate__c = result.nextDueDate;
			pol.collectionPaymentStatus__c = result.paymentStatus;
			// PaymentDueDate (estandar) se mantiene al dia con la proxima cuota, pero
			// nunca se vacia (regla PremiumFieldsRequired): si no hay proxima, se deja
			// el ultimo valor.
			if (result.nextDueDate != null) {
				pol.PaymentDueDate = result.nextDueDate;
			}
			toUpdate.add(pol);
		}

		if (!toUpdate.isEmpty()) {
			update toUpdate;
		}
	}

	/**
	 * @creation date: 12/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Selecciona el plan vigente por poliza: ignora los Reemplazado y
	 *               Cancelado, prefiere el Activo y, en su defecto, el mas reciente.
	 * @param policyIds: IDs de InsurancePolicy.
	 * @return Mapa de policyId al PaymentPlan__c vigente.
	 */
	private static Map<Id, PaymentPlan__c> selectVigentePlanByPolicy(
		Set<Id> policyIds
	) {
		Map<Id, PaymentPlan__c> result = new Map<Id, PaymentPlan__c>();
		for (PaymentPlan__c plan : [
			SELECT Id, insurancePolicy__c, planStatus__c
			FROM PaymentPlan__c
			WHERE
				insurancePolicy__c IN :policyIds
				AND planStatus__c != :PLAN_STATUS_REPLACED
				AND planStatus__c != :PLAN_STATUS_CANCELLED
			ORDER BY CreatedDate DESC
		]) {
			Id policyId = plan.insurancePolicy__c;
			PaymentPlan__c chosen = result.get(policyId);
			if (chosen == null) {
				result.put(policyId, plan);
			} else if (
				PLAN_STATUS_ACTIVE.equals(plan.planStatus__c) &&
				!PLAN_STATUS_ACTIVE.equals(chosen.planStatus__c)
			) {
				result.put(policyId, plan);
			}
		}
		return result;
	}

	/**
	 * @creation date: 12/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Carga las cuotas de los planes indicados agrupadas por plan.
	 * @param planIds: IDs de PaymentPlan__c.
	 * @return Mapa de planId a lista de cuotas.
	 */
	private static Map<Id, List<PaymentPlanInstallment__c>> loadInstallmentsByPlan(
		Set<Id> planIds
	) {
		Map<Id, List<PaymentPlanInstallment__c>> result = new Map<Id, List<PaymentPlanInstallment__c>>();
		if (planIds.isEmpty()) {
			return result;
		}
		for (PaymentPlanInstallment__c inst : [
			SELECT Id, paymentPlan__c, dueDate__c, installmentStatus__c
			FROM PaymentPlanInstallment__c
			WHERE paymentPlan__c IN :planIds
		]) {
			if (!result.containsKey(inst.paymentPlan__c)) {
				result.put(inst.paymentPlan__c, new List<PaymentPlanInstallment__c>());
			}
			result.get(inst.paymentPlan__c).add(inst);
		}
		return result;
	}

	/**
	 * @creation date: 12/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Calcula el resumen (pagada hasta, proxima fecha y estado) del plan
	 *               vigente. "Pagada hasta" = vencimiento mas alto entre cuotas
	 *               Conciliado; "proxima fecha" = vencimiento mas bajo entre cuotas
	 *               abiertas; estado: Completado si el plan lo esta; Vencido si hay
	 *               cuota abierta con vencimiento pasado; Al dia si hay alguna conciliada
	 *               y nada vencido; Sin pago si no hay ninguna conciliada.
	 * @param plan: Plan vigente.
	 * @param installments: Cuotas del plan, o null.
	 * @param today: Fecha de referencia para determinar vencidos.
	 * @return SummaryResult con los valores calculados.
	 */
	private static SummaryResult summarize(
		PaymentPlan__c plan,
		List<PaymentPlanInstallment__c> installments,
		Date today
	) {
		SummaryResult result = new SummaryResult();
		Boolean hasReconciled = false;
		Boolean hasOverdue = false;

		if (installments != null) {
			for (PaymentPlanInstallment__c inst : installments) {
				String status = inst.installmentStatus__c;
				if (INSTALLMENT_STATUS_RECONCILED.equals(status)) {
					hasReconciled = true;
					if (
						inst.dueDate__c != null &&
						(result.paidThroughDate == null ||
						inst.dueDate__c > result.paidThroughDate)
					) {
						result.paidThroughDate = inst.dueDate__c;
					}
				} else if (OPEN_INSTALLMENT_STATUSES.contains(status)) {
					if (
						inst.dueDate__c != null &&
						(result.nextDueDate == null ||
						inst.dueDate__c < result.nextDueDate)
					) {
						result.nextDueDate = inst.dueDate__c;
					}
					if (inst.dueDate__c != null && inst.dueDate__c < today) {
						hasOverdue = true;
					}
				}
			}
		}

		if (PLAN_STATUS_COMPLETED.equals(plan.planStatus__c)) {
			result.paymentStatus = PAYMENT_STATUS_COMPLETED;
		} else if (hasOverdue) {
			result.paymentStatus = PAYMENT_STATUS_OVERDUE;
		} else if (hasReconciled) {
			result.paymentStatus = PAYMENT_STATUS_CURRENT;
		} else {
			result.paymentStatus = PAYMENT_STATUS_NONE;
		}
		return result;
	}

	private class SummaryResult {
		Date paidThroughDate;
		Date nextDueDate;
		String paymentStatus;
	}
}
