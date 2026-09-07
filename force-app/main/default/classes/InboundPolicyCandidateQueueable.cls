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

	// KAN-423. Identificar la poliza es una cuestion de llave, no de vigencia: si el numero
	// existe, es esa poliza, este como este. El estado dejo de filtrar aqui. Lo que si hace
	// falta es desempatar entre las varias vigencias que comparten numero, y eso se resuelve
	// por periodo contra la fecha del recibo.
	private static final String REASON_SINGLE_WINNER = 'UNICO_GANADOR';
	private static final String REASON_BY_TERM = 'RESUELTO_POR_VIGENCIA';
	private static final String REASON_AMBIGUOUS_TERM = 'VIGENCIA_AMBIGUA';
	private static final String REASON_NO_POLICY = 'SIN_POLIZA';
	private static final String REASON_NO_NUMBER = 'SIN_NUMERO';

	@TestVisible
	private static Boolean forceFailureForTest = false;

	private class PolicyMatchException extends Exception {
	}

	private class PolicyMatchResult {
		Id policyId;
		String reason;

		PolicyMatchResult(Id policyId, String reason) {
			this.policyId = policyId;
			this.reason = reason;
		}
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
		AppLogger.setJobContext(context == null ? null : context.getJobId());
		System.attachFinalizer(
			CobranzaLog.finalizerFor(
				CobranzaLog.STAGE_POLIZA_CANDIDATA,
				inboundPaymentIds
			)
		);

		List<InboundInsurancePayment__c> payments = [
			SELECT Id, sourcePolicyNumber__c, sourceDueDate__c, sourcePaymentDate__c
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

		Map<String, List<InsurancePolicy>> policiesByNumber = findPolicies(
			policyNumbers
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
				PolicyMatchResult result = resolvePolicy(p, policiesByNumber);
				rec.candidatePolicy__c = result.policyId;
				rec.policyMatchReason__c = result.reason;
				logTermResolution(p, result, policiesByNumber);
			} catch (Exception e) {
				rec.candidatePolicy__c = null;
				rec.policyMatchReason__c = null;
				CobranzaLog.error(
						CobranzaLog.STAGE_POLIZA_CANDIDATA,
						CobranzaLog.EVENT_POLICY_MATCH_FAILED,
						e
					)
					.onInbound(p.Id);
			}
			rec.pipelineStage__c = CobranzaLog.STAGE_POLIZA_CANDIDATA;
			toUpdate.add(rec);
		}

		update toUpdate;

		Set<Id> allIds = new Set<Id>();
		for (InboundInsurancePayment__c rec : toUpdate) {
			allIds.add(rec.Id);
		}
		try {
			System.enqueueJob(new InboundInstallmentCandidateQueueable(allIds));
		} catch (System.AsyncException e) {
			CobranzaLog.chainBreak(
				CobranzaLog.STAGE_POLIZA_CANDIDATA,
				e,
				'InboundInstallmentCandidateQueueable',
				allIds
			);
		}

		AppLogger.flush();
	}

	/**
	 * @creation date: 31/08/2026
	 * @author: Javier Torres - Volestra
	 * @description: Consulta InsurancePolicy por numero, SIN filtrar por estado (KAN-423).
	 *               Que la poliza este vencida o cancelada no cambia cual es: la aseguradora
	 *               puede cobrar sobre ella, y filtrarla producia un "Sin Match" que ademas
	 *               desinformaba, porque la poliza si existia. Trae el periodo de vigencia
	 *               para poder desempatar cuando varias vigencias comparten numero.
	 * @param policyNumbers: Conjunto de numeros de poliza normalizados a buscar.
	 * @return Mapa de numero de poliza a las polizas coincidentes.
	 */
	private static Map<String, List<InsurancePolicy>> findPolicies(
		Set<String> policyNumbers
	) {
		Map<String, List<InsurancePolicy>> result = new Map<String, List<InsurancePolicy>>();
		if (policyNumbers.isEmpty()) {
			return result;
		}
		Set<String> seen = new Set<String>();
		for (InsurancePolicy policy : [
			SELECT Id, Name, PolicyName, Status, EffectiveDate, ExpirationDate
			FROM InsurancePolicy
			WHERE Name IN :policyNumbers OR PolicyName IN :policyNumbers
		]) {
			for (String num : new List<String>{ policy.Name, policy.PolicyName }) {
				if (num == null) {
					continue;
				}
				String numUpper = num.toUpperCase();
				if (!policyNumbers.contains(numUpper)) {
					continue;
				}
				// Una misma poliza puede coincidir por Name y por PolicyName; contarla dos
				// veces la haria parecer un empate entre vigencias que no existe.
				String key = numUpper + '|' + policy.Id;
				if (seen.contains(key)) {
					continue;
				}
				seen.add(key);
				if (!result.containsKey(numUpper)) {
					result.put(numUpper, new List<InsurancePolicy>());
				}
				result.get(numUpper).add(policy);
			}
		}
		return result;
	}

	/**
	 * @creation date: 31/08/2026
	 * @author: Javier Torres - Volestra
	 * @description: Resuelve la poliza del pago (KAN-423). Con una sola coincidencia, esa es.
	 *               Con varias -el caso de las renovaciones, donde cada vigencia es una poliza
	 *               propia con el mismo numero- gana aquella cuyo periodo contiene la fecha del
	 *               recibo. Si ninguna la contiene, o la contienen varias, no se elige por
	 *               descarte: el pago queda para revision manual con el motivo, porque atribuir
	 *               un cobro a la vigencia equivocada es peor que dejarlo sin resolver.
	 * @param payment: Pago inbound con numero de poliza y fechas.
	 * @param policiesByNumber: Polizas coincidentes agrupadas por numero.
	 * @return Resultado con la poliza elegida (o null) y el motivo.
	 */
	private static PolicyMatchResult resolvePolicy(
		InboundInsurancePayment__c payment,
		Map<String, List<InsurancePolicy>> policiesByNumber
	) {
		if (String.isBlank(payment.sourcePolicyNumber__c)) {
			return new PolicyMatchResult(null, REASON_NO_NUMBER);
		}
		List<InsurancePolicy> matches = policiesByNumber.get(
			payment.sourcePolicyNumber__c
		);
		if (matches == null || matches.isEmpty()) {
			return new PolicyMatchResult(null, REASON_NO_POLICY);
		}
		if (matches.size() == 1) {
			return new PolicyMatchResult(matches[0].Id, REASON_SINGLE_WINNER);
		}

		Date reference = referenceDateFor(payment);
		if (reference == null) {
			return new PolicyMatchResult(null, REASON_AMBIGUOUS_TERM);
		}

		Id winner = null;
		Integer hits = 0;
		for (InsurancePolicy policy : matches) {
			if (termContains(policy, reference)) {
				winner = policy.Id;
				hits++;
			}
		}
		if (hits != 1) {
			return new PolicyMatchResult(null, REASON_AMBIGUOUS_TERM);
		}
		return new PolicyMatchResult(winner, REASON_BY_TERM);
	}

	/**
	 * @creation date: 31/08/2026
	 * @author: Javier Torres - Volestra
	 * @description: Fecha con la que se decide a que vigencia pertenece el recibo. Se prefiere
	 *               la de vencimiento porque es la que la aseguradora le asigna al emitirlo y no
	 *               cambia; la de pago sirve de alternativa, aunque un pago tardio puede caer
	 *               fuera del periodo y por eso no se usa primero.
	 * @param payment: Pago inbound a evaluar.
	 * @return Fecha de referencia, o null si el recibo no trae ninguna.
	 */
	private static Date referenceDateFor(InboundInsurancePayment__c payment) {
		return payment.sourceDueDate__c != null
			? payment.sourceDueDate__c
			: payment.sourcePaymentDate__c;
	}

	/**
	 * @creation date: 31/08/2026
	 * @author: Javier Torres - Volestra
	 * @description: Indica si la fecha cae dentro del periodo de la poliza. Los limites son
	 *               DateTime en el modelo estandar y se comparan por su parte de fecha: incluir
	 *               la hora dejaria fuera un recibo del ultimo dia de vigencia. Una poliza sin
	 *               ninguno de los dos extremos no puede ganar un desempate, porque no aporta
	 *               ninguna evidencia de a que periodo pertenece.
	 * @param policy: Poliza con su periodo.
	 * @param reference: Fecha del recibo.
	 * @return true si la fecha pertenece al periodo.
	 */
	private static Boolean termContains(InsurancePolicy policy, Date reference) {
		if (policy.EffectiveDate == null && policy.ExpirationDate == null) {
			return false;
		}
		if (
			policy.EffectiveDate != null &&
			reference < policy.EffectiveDate.date()
		) {
			return false;
		}
		if (
			policy.ExpirationDate != null &&
			reference > policy.ExpirationDate.date()
		) {
			return false;
		}
		return true;
	}

	/**
	 * @creation date: 31/08/2026
	 * @author: Javier Torres - Volestra
	 * @description: Deja constancia de la decision cuando el numero correspondia a varias
	 *               vigencias. Es la unica parte del match que no se puede reconstruir mirando
	 *               el registro: el resultado muestra que poliza gano, pero no cuantas
	 *               competian ni con que fecha se resolvio.
	 * @param payment: Pago inbound evaluado.
	 * @param result: Resultado de la resolucion.
	 * @param policiesByNumber: Polizas coincidentes agrupadas por numero.
	 * @return
	 */
	private static void logTermResolution(
		InboundInsurancePayment__c payment,
		PolicyMatchResult result,
		Map<String, List<InsurancePolicy>> policiesByNumber
	) {
		if (
			!REASON_BY_TERM.equals(result.reason) &&
			!REASON_AMBIGUOUS_TERM.equals(result.reason)
		) {
			return;
		}
		List<InsurancePolicy> matches = policiesByNumber.get(
			payment.sourcePolicyNumber__c
		);
		Integer total = matches == null ? 0 : matches.size();
		Date reference = referenceDateFor(payment);

		if (REASON_BY_TERM.equals(result.reason)) {
			CobranzaLog.info(
					CobranzaLog.STAGE_POLIZA_CANDIDATA,
					CobranzaLog.EVENT_POLICY_TERM_RESOLVED,
					'El numero corresponde a ' +
						total +
						' vigencias. Se eligio la que contiene la fecha ' +
						reference +
						'.'
				)
				.onInbound(payment.Id);
			return;
		}

		CobranzaLog.warn(
				CobranzaLog.STAGE_POLIZA_CANDIDATA,
				CobranzaLog.EVENT_POLICY_TERM_AMBIGUOUS,
				'El numero corresponde a ' +
					total +
					' vigencias y la fecha ' +
					reference +
					' no identifica una sola. El pago queda para revision manual: elegir por ' +
					'descarte podria atribuir el cobro a la vigencia equivocada.'
			)
			.onInbound(payment.Id);
	}
}
