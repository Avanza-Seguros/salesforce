/**
 *   @name: InboundPolicyCandidateQueueable
 *   @version: 1.0
 *   @creation date: 07/05/2026
 *   @author: Javier Torres - Volestra
 *   @description: Identifica la poliza candidata para pagos inbound normalizados
 *                 usando el numero de poliza como criterio principal. Filtra
 *                 exclusivamente polizas en estado valido para conciliacion
 *                 (Vigente, Inicial), excluyendo Cancelado, Suspendido y similares.
 *                 Asigna candidatePolicy__c si el match es univoco; deja null si
 *                 no hay coincidencia (sin match) o si es ambiguo (multiples polizas
 *                 activas con el mismo numero). Tras resolver la poliza, re-evalua
 *                 candidateInstallment__c mediante matching jerarquico determinista.
 *                 Puede lanzarse manualmente sobre cualquier registro en estado
 *                 Normalizado sin requerir reenvio desde integracion.
 */
public with sharing class InboundPolicyCandidateQueueable implements Queueable {
	private static final String STATUS_NORMALIZED = 'Normalizado';
	private static final Set<String> VALID_POLICY_STATUSES = new Set<String>{
		'Vigente',
		'Inicial'
	};

	@TestVisible
	private static Boolean forceFailureForTest = false;

	private class PolicyMatchException extends Exception {
	}

	private Set<Id> inboundPaymentIds;

	/**
	 * @creation date: 07/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Inicializa el job con los IDs de los registros a enriquecer.
	 * @param inboundPaymentIds: Conjunto de IDs de InboundInsurancePayment__c en estado Normalizado.
	 * @return
	 */
	public InboundPolicyCandidateQueueable(Set<Id> inboundPaymentIds) {
		this.inboundPaymentIds = inboundPaymentIds;
	}

	/**
	 * @creation date: 07/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Punto de entrada del job. Consulta los registros en estado
	 *               Normalizado, resuelve la poliza candidata contra polizas en
	 *               estado valido para conciliacion, y re-evalua candidateInstallment__c
	 *               acorde al nuevo candidatePolicy__c. Si ocurre una excepcion en
	 *               un registro individual, sus candidatos quedan en null sin afectar
	 *               al resto del lote ni cambiar el estado del registro.
	 * @param context: Contexto de ejecucion del Queueable proporcionado por la plataforma.
	 * @return
	 */
	public void execute(QueueableContext context) {
		List<InboundInsurancePayment__c> payments = [
			SELECT
				Id,
				sourcePolicyNumber__c,
				sourceInsuranceCarrier__c,
				sourceInstallmentNumber__c,
				sourceDueDate__c
			FROM InboundInsurancePayment__c
			WHERE Id IN :inboundPaymentIds AND inboundStatus__c = :STATUS_NORMALIZED
		];

		if (payments.isEmpty()) {
			return;
		}

		Set<String> policyNumbers = new Set<String>();
		for (InboundInsurancePayment__c p : payments) {
			if (String.isNotBlank(p.sourcePolicyNumber__c)) {
				policyNumbers.add(p.sourcePolicyNumber__c);
			}
		}

		Map<String, Set<Id>> policiesByNumber = findActivePolicies(policyNumbers);

		Set<Id> resolvedPolicyIds = new Set<Id>();
		for (InboundInsurancePayment__c p : payments) {
			Set<Id> matches = policiesByNumber.get(p.sourcePolicyNumber__c);
			if (matches != null && matches.size() == 1) {
				resolvedPolicyIds.add(new List<Id>(matches)[0]);
			}
		}

		Map<Id, List<PaymentPlanInstallment__c>> installmentsByPolicy = loadInstallmentsByPolicy(
			resolvedPolicyIds
		);

		List<InboundInsurancePayment__c> toUpdate = new List<InboundInsurancePayment__c>();

		for (InboundInsurancePayment__c p : payments) {
			InboundInsurancePayment__c rec = new InboundInsurancePayment__c(
				Id = p.Id
			);
			try {
				if (forceFailureForTest) {
					throw new PolicyMatchException('Forced failure for test');
				}
				Id candidatePolicyId = resolvePolicy(
					p.sourcePolicyNumber__c,
					policiesByNumber
				);
				rec.candidatePolicy__c = candidatePolicyId;
				rec.candidateInstallment__c = matchInstallment(
					p,
					candidatePolicyId,
					installmentsByPolicy
				);
			} catch (Exception e) {
				rec.candidatePolicy__c = null;
				rec.candidateInstallment__c = null;
			}
			toUpdate.add(rec);
		}

		update toUpdate;
	}

	/**
	 * @creation date: 07/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Consulta InsurancePolicy filtrando por VALID_POLICY_STATUSES.
	 *               Agrupa los IDs encontrados por numero de poliza (Name y PolicyName)
	 *               para detectar coincidencias unicas y casos ambiguos.
	 *               Si el mismo numero coincide via Name y PolicyName en la misma poliza,
	 *               el ID se registra una sola vez por unicidad del Set.
	 * @param policyNumbers: Conjunto de numeros de poliza normalizados a buscar.
	 * @return Mapa de numero de poliza a conjunto de IDs de InsurancePolicy activas coincidentes.
	 */
	private static Map<String, Set<Id>> findActivePolicies(
		Set<String> policyNumbers
	) {
		Map<String, Set<Id>> result = new Map<String, Set<Id>>();
		if (policyNumbers.isEmpty()) {
			return result;
		}
		for (InsurancePolicy policy : [
			SELECT Id, Name, PolicyName
			FROM InsurancePolicy
			WHERE
				(Name IN :policyNumbers
				OR PolicyName IN :policyNumbers)
				AND Status IN :VALID_POLICY_STATUSES
		]) {
			for (String num : new List<String>{ policy.Name, policy.PolicyName }) {
				if (num != null && policyNumbers.contains(num)) {
					if (!result.containsKey(num)) {
						result.put(num, new Set<Id>());
					}
					result.get(num).add(policy.Id);
				}
			}
		}
		return result;
	}

	/**
	 * @creation date: 07/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Resuelve la poliza candidata unica a partir del numero de poliza.
	 *               Retorna el ID si hay exactamente 1 poliza activa coincidente.
	 *               Retorna null si no hay coincidencia (sin match) o si hay mas de
	 *               una poliza activa con ese numero (ambiguo). En ambos casos el
	 *               motor de conciliacion posterior opera con confianza baja o
	 *               deriva a revision manual.
	 * @param policyNumber: Numero de poliza normalizado del inbound.
	 * @param policiesByNumber: Mapa de numero de poliza a IDs de polizas activas.
	 * @return ID de la poliza candidata unica, o null si no hay match univoco.
	 */
	private static Id resolvePolicy(
		String policyNumber,
		Map<String, Set<Id>> policiesByNumber
	) {
		if (String.isBlank(policyNumber)) {
			return null;
		}
		Set<Id> matches = policiesByNumber.get(policyNumber);
		if (matches == null || matches.isEmpty() || matches.size() > 1) {
			return null;
		}
		return new List<Id>(matches)[0];
	}

	/**
	 * @creation date: 07/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Carga las cuotas de los planes de pago asociados a las polizas
	 *               indicadas, agrupadas por ID de poliza. Usa 2 consultas separadas
	 *               para evitar valores null en campos de relacion en SELECT.
	 * @param policyIds: Conjunto de IDs de InsurancePolicy candidatas resueltas.
	 * @return Mapa de policyId a lista de PaymentPlanInstallment__c de esa poliza.
	 */
	private static Map<Id, List<PaymentPlanInstallment__c>> loadInstallmentsByPolicy(
		Set<Id> policyIds
	) {
		Map<Id, List<PaymentPlanInstallment__c>> result = new Map<Id, List<PaymentPlanInstallment__c>>();
		if (policyIds.isEmpty()) {
			return result;
		}
		Map<Id, Id> policyByPlan = new Map<Id, Id>();
		for (PaymentPlan__c plan : [
			SELECT Id, insurancePolicy__c
			FROM PaymentPlan__c
			WHERE insurancePolicy__c IN :policyIds
		]) {
			policyByPlan.put(plan.Id, plan.insurancePolicy__c);
		}
		if (policyByPlan.isEmpty()) {
			return result;
		}
		for (PaymentPlanInstallment__c inst : [
			SELECT Id, sequenceNumber__c, dueDate__c, paymentPlan__c
			FROM PaymentPlanInstallment__c
			WHERE paymentPlan__c IN :policyByPlan.keySet()
		]) {
			Id policyId = policyByPlan.get(inst.paymentPlan__c);
			if (policyId == null) {
				continue;
			}
			if (!result.containsKey(policyId)) {
				result.put(policyId, new List<PaymentPlanInstallment__c>());
			}
			result.get(policyId).add(inst);
		}
		return result;
	}

	/**
	 * @creation date: 07/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Orquesta el matching jerarquico de cuota candidata para un pago
	 *               dado el candidatePolicy__c recien resuelto. Si la poliza es null,
	 *               retorna null sin intentar el matching. Intenta primero por numero
	 *               de cuota y luego por fecha de vencimiento.
	 * @param payment: Registro inbound procesado.
	 * @param policyId: ID de la poliza candidata resuelta, o null.
	 * @param installmentsByPolicy: Cuotas disponibles agrupadas por poliza.
	 * @return ID de la cuota candidata, o null si no hay match univoco.
	 */
	private static Id matchInstallment(
		InboundInsurancePayment__c payment,
		Id policyId,
		Map<Id, List<PaymentPlanInstallment__c>> installmentsByPolicy
	) {
		if (policyId == null) {
			return null;
		}
		List<PaymentPlanInstallment__c> installments = installmentsByPolicy.get(
			policyId
		);
		if (installments == null || installments.isEmpty()) {
			return null;
		}
		if (payment.sourceInstallmentNumber__c != null) {
			Id matchId = matchBySequenceNumber(
				payment.sourceInstallmentNumber__c,
				installments
			);
			if (matchId != null) {
				return matchId;
			}
		}
		if (payment.sourceDueDate__c != null) {
			return matchByDueDate(payment.sourceDueDate__c, installments);
		}
		return null;
	}

	/**
	 * @creation date: 07/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Busca una cuota cuyo sequenceNumber__c coincida con el numero
	 *               informado. Retorna el ID solo si hay exactamente 1 match.
	 *               Si el valor no puede convertirse a Decimal, retorna null sin
	 *               propagar la excepcion.
	 * @param installmentNumber: Numero de cuota como texto (puede tener espacios).
	 * @param installments: Lista de cuotas candidatas de la poliza.
	 * @return ID de la cuota coincidente, o null si no hay match univoco.
	 */
	private static Id matchBySequenceNumber(
		String installmentNumber,
		List<PaymentPlanInstallment__c> installments
	) {
		Decimal targetSeq;
		try {
			targetSeq = Decimal.valueOf(installmentNumber.trim());
		} catch (Exception e) {
			return null;
		}
		List<Id> matches = new List<Id>();
		for (PaymentPlanInstallment__c inst : installments) {
			if (
				inst.sequenceNumber__c != null &&
				inst.sequenceNumber__c == targetSeq
			) {
				matches.add(inst.Id);
			}
		}
		return matches.size() == 1 ? matches[0] : null;
	}

	/**
	 * @creation date: 07/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Busca una cuota cuyo dueDate__c coincida exactamente con la
	 *               fecha de vencimiento informada. Retorna el ID solo si hay
	 *               exactamente 1 match.
	 * @param dueDate: Fecha de vencimiento a comparar.
	 * @param installments: Lista de cuotas candidatas de la poliza.
	 * @return ID de la cuota coincidente, o null si no hay match univoco.
	 */
	private static Id matchByDueDate(
		Date dueDate,
		List<PaymentPlanInstallment__c> installments
	) {
		List<Id> matches = new List<Id>();
		for (PaymentPlanInstallment__c inst : installments) {
			if (inst.dueDate__c == dueDate) {
				matches.add(inst.Id);
			}
		}
		return matches.size() == 1 ? matches[0] : null;
	}
}
