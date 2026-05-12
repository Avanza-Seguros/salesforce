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
 *                 activas con el mismo numero). Puede lanzarse manualmente sobre
 *                 cualquier registro en estado Normalizado sin requerir reenvio desde
 *                 integracion. Encadena a InboundInstallmentCandidateQueueable para
 *                 la resolucion de cuota candidata.
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
	 *               estado valido para conciliacion y actualiza candidatePolicy__c.
	 *               Si ocurre una excepcion en un registro individual, su candidato
	 *               queda en null sin afectar al resto del lote ni cambiar el estado
	 *               del registro. Encadena a InboundInstallmentCandidateQueueable
	 *               con todos los IDs del lote para la resolucion de cuota candidata.
	 * @param context: Contexto de ejecucion del Queueable proporcionado por la plataforma.
	 * @return
	 */
	public void execute(QueueableContext context) {
		List<InboundInsurancePayment__c> payments = [
			SELECT Id, sourcePolicyNumber__c
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

		List<InboundInsurancePayment__c> toUpdate = new List<InboundInsurancePayment__c>();

		for (InboundInsurancePayment__c p : payments) {
			InboundInsurancePayment__c rec = new InboundInsurancePayment__c(
				Id = p.Id
			);
			try {
				if (forceFailureForTest) {
					throw new PolicyMatchException('Forced failure for test');
				}
				rec.candidatePolicy__c = resolvePolicy(
					p.sourcePolicyNumber__c,
					policiesByNumber
				);
			} catch (Exception e) {
				rec.candidatePolicy__c = null;
			}
			toUpdate.add(rec);
		}

		update toUpdate;

		Set<Id> allIds = new Set<Id>();
		for (InboundInsurancePayment__c rec : toUpdate) {
			allIds.add(rec.Id);
		}
		System.enqueueJob(new InboundInstallmentCandidateQueueable(allIds));
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
}
