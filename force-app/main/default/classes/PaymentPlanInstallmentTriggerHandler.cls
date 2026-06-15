/**
 *   @name: PaymentPlanInstallmentTriggerHandler
 *   @version: 1.0
 *   @creation date: 11/06/2026
 *   @author: Javier Torres - Volestra
 *   @description: Recalcula planStatus__c del PaymentPlan__c padre a partir del estado
 *                 agregado de sus cuotas (PaymentPlanInstallment__c), cada vez que una
 *                 cuota cambia de estado. Reglas: si hay cuotas abiertas (Pendiente o
 *                 Vencido) el plan queda Activo; si no hay abiertas y al menos una esta
 *                 Conciliado el plan queda Completado; los planes en estados protegidos
 *                 (Reemplazado, Cancelado, Suspendido) o sin cuotas no se modifican. El
 *                 calculo se basa en el estado de las cuotas, no en importes de cabecera.
 */
public with sharing class PaymentPlanInstallmentTriggerHandler {
	private static final String PLAN_STATUS_ACTIVE = 'Activo';
	private static final String PLAN_STATUS_COMPLETED = 'Completado';

	private static final Set<String> PROTECTED_PLAN_STATUSES = new Set<String>{
		'Reemplazado',
		'Cancelado',
		'Suspendido'
	};

	private static final Set<String> OPEN_INSTALLMENT_STATUSES = new Set<String>{
		'Pendiente',
		'Vencido'
	};

	private static final String INSTALLMENT_STATUS_RECONCILED = 'Conciliado';

	/**
	 * @creation date: 11/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Punto de entrada del trigger. Reune los planes cuyas cuotas
	 *               cambiaron de estado (en insert toma todas; en update solo las que
	 *               cambiaron installmentStatus__c) y dispara el recalculo.
	 * @param newInstallments: Cuotas del contexto del trigger (Trigger.new).
	 * @param oldMap: Valores anteriores de las cuotas, o null en insert.
	 * @return
	 */
	public static void handleAfterTrigger(
		List<PaymentPlanInstallment__c> newInstallments,
		Map<Id, PaymentPlanInstallment__c> oldMap
	) {
		if (newInstallments == null || newInstallments.isEmpty()) {
			return;
		}

		Set<Id> planIds = new Set<Id>();
		for (PaymentPlanInstallment__c inst : newInstallments) {
			if (inst.paymentPlan__c == null) {
				continue;
			}
			if (oldMap == null) {
				planIds.add(inst.paymentPlan__c);
				continue;
			}
			PaymentPlanInstallment__c oldInst = oldMap.get(inst.Id);
			if (
				oldInst == null ||
				oldInst.installmentStatus__c != inst.installmentStatus__c
			) {
				planIds.add(inst.paymentPlan__c);
			}
		}

		if (planIds.isEmpty()) {
			return;
		}

		recalculatePlans(planIds);
	}

	/**
	 * @creation date: 11/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Recalcula planStatus__c de los planes indicados a partir del conteo
	 *               de cuotas por estado. Omite planes en estados protegidos y planes sin
	 *               cuotas. Solo emite DML para los planes cuyo estado cambia. No genera
	 *               recursion: el cambio de estado del plan no dispara generacion de
	 *               cuotas (requiere Activo y plan sin cuotas previas).
	 * @param planIds: IDs de PaymentPlan__c a reevaluar.
	 * @return
	 */
	@TestVisible
	private static void recalculatePlans(Set<Id> planIds) {
		Map<Id, PaymentPlan__c> plansById = new Map<Id, PaymentPlan__c>(
			[
				SELECT Id, planStatus__c, insurancePolicy__c
				FROM PaymentPlan__c
				WHERE Id IN :planIds
			]
		);
		if (plansById.isEmpty()) {
			return;
		}

		Map<Id, Integer> totalByPlan = new Map<Id, Integer>();
		Map<Id, Integer> openByPlan = new Map<Id, Integer>();
		Map<Id, Integer> reconciledByPlan = new Map<Id, Integer>();

		for (AggregateResult ar : [
			SELECT
				paymentPlan__c planId,
				installmentStatus__c instStatus,
				COUNT(Id) qty
			FROM PaymentPlanInstallment__c
			WHERE paymentPlan__c IN :planIds
			GROUP BY paymentPlan__c, installmentStatus__c
		]) {
			Id planId = (Id) ar.get('planId');
			String instStatus = (String) ar.get('instStatus');
			Integer qty = (Integer) ar.get('qty');

			addCount(totalByPlan, planId, qty);
			if (OPEN_INSTALLMENT_STATUSES.contains(instStatus)) {
				addCount(openByPlan, planId, qty);
			}
			if (INSTALLMENT_STATUS_RECONCILED.equals(instStatus)) {
				addCount(reconciledByPlan, planId, qty);
			}
		}

		List<PaymentPlan__c> toUpdate = new List<PaymentPlan__c>();
		for (PaymentPlan__c plan : plansById.values()) {
			if (PROTECTED_PLAN_STATUSES.contains(plan.planStatus__c)) {
				continue;
			}
			Integer total = nullToZero(totalByPlan.get(plan.Id));
			if (total == 0) {
				continue;
			}
			Integer openCount = nullToZero(openByPlan.get(plan.Id));
			Integer reconciledCount = nullToZero(reconciledByPlan.get(plan.Id));

			String newStatus = plan.planStatus__c;
			if (openCount > 0) {
				newStatus = PLAN_STATUS_ACTIVE;
			} else if (reconciledCount > 0) {
				newStatus = PLAN_STATUS_COMPLETED;
			}

			if (newStatus != plan.planStatus__c) {
				toUpdate.add(
					new PaymentPlan__c(Id = plan.Id, planStatus__c = newStatus)
				);
			}
		}

		if (!toUpdate.isEmpty()) {
			update toUpdate;
		}

		// Historia 189: refleja el resumen de cobranza en la poliza de cada plan afectado.
		Set<Id> policyIds = new Set<Id>();
		for (PaymentPlan__c plan : plansById.values()) {
			if (plan.insurancePolicy__c != null) {
				policyIds.add(plan.insurancePolicy__c);
			}
		}
		PolicyCollectionSummaryService.recalculate(policyIds);
	}

	/**
	 * @creation date: 11/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Acumula un conteo en el mapa para la clave dada.
	 * @param counts: Mapa de conteos por plan.
	 * @param key: ID del plan.
	 * @param qty: Cantidad a sumar.
	 * @return
	 */
	private static void addCount(Map<Id, Integer> counts, Id key, Integer qty) {
		counts.put(key, nullToZero(counts.get(key)) + qty);
	}

	/**
	 * @creation date: 11/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Devuelve 0 si el valor es null.
	 * @param value: Entero o null.
	 * @return Entero no nulo.
	 */
	private static Integer nullToZero(Integer value) {
		return value == null ? 0 : value;
	}
}
