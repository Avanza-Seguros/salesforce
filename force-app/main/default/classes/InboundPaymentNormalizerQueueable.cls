/**
 *   @name: InboundPaymentNormalizerQueueable
 *   @version: 2.0
 *   @creation date: 02/05/2026
 *   @author: Javier Torres - Volestra
 *   @description: Normaliza y enriquece pagos inbound en estado Parseado:
 *                 limpia y estandariza campos de texto, redondea montos a 2
 *                 decimales, asigna la cuota candidata por matching deterministico
 *                 jerarquico (numero de cuota > fecha de vencimiento) y actualiza
 *                 el estado a Normalizado o Rechazado segun el resultado.
 */
public with sharing class InboundPaymentNormalizerQueueable implements Queueable {
	private static final String STATUS_PARSED = 'Parseado';
	private static final String STATUS_NORMALIZED = 'Normalizado';
	private static final String STATUS_REJECTED = 'Rechazado';
	private static final String REASON_NORMALIZATION_ERROR = 'Error de normalizacion';

	@TestVisible
	private static Boolean forceFailureForTest = false;

	private class NormalizationException extends Exception {
	}

	private Set<Id> inboundPaymentIds;

	/**
	 * @creation date: 02/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Inicializa el job con los IDs de los registros a normalizar.
	 * @param inboundPaymentIds: Conjunto de IDs de InboundInsurancePayment__c en estado Parseado.
	 * @return
	 */
	public InboundPaymentNormalizerQueueable(Set<Id> inboundPaymentIds) {
		this.inboundPaymentIds = inboundPaymentIds;
	}

	/**
	 * @creation date: 02/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Punto de entrada del job. Consulta los registros en estado Parseado,
	 *               aplica la normalizacion de campos de texto y montos, resuelve la cuota
	 *               candidata y actualiza el estado a Normalizado o Rechazado segun resultado.
	 *               Si ocurre una excepcion durante el procesamiento de un registro individual,
	 *               ese registro queda con inboundStatus__c = Rechazado y rejectionReason__c
	 *               = 'Error de normalizacion', sin afectar al resto del lote.
	 * @param context: Contexto de ejecucion del Queueable proporcionado por la plataforma.
	 * @return
	 */
	public void execute(QueueableContext context) {
		List<InboundInsurancePayment__c> payments = [
			SELECT
				Id,
				candidatePolicy__c,
				sourceInstallmentNumber__c,
				sourceDueDate__c,
				sourcePolicyNumber__c,
				sourceReceiptNumber__c,
				sourceInsuranceCarrier__c,
				sourceAmount__c,
				sourceGrossCommission__c,
				sourceVatCommission__c
			FROM InboundInsurancePayment__c
			WHERE Id IN :inboundPaymentIds AND inboundStatus__c = :STATUS_PARSED
		];

		if (payments.isEmpty()) {
			return;
		}

		Set<Id> policyIds = new Set<Id>();
		for (InboundInsurancePayment__c p : payments) {
			if (
				p.candidatePolicy__c != null &&
				(p.sourceInstallmentNumber__c != null ||
				p.sourceDueDate__c != null)
			) {
				policyIds.add(p.candidatePolicy__c);
			}
		}

		Map<Id, List<PaymentPlanInstallment__c>> installmentsByPolicy = loadInstallmentsByPolicy(
			policyIds
		);

		Datetime normalizedAt = System.now();
		List<InboundInsurancePayment__c> toUpdate = new List<InboundInsurancePayment__c>();

		for (InboundInsurancePayment__c p : payments) {
			InboundInsurancePayment__c rec = new InboundInsurancePayment__c(
				Id = p.Id
			);
			try {
				if (forceFailureForTest) {
					throw new NormalizationException('Forced failure for test');
				}
				rec.sourcePolicyNumber__c = normalizeUppercase(p.sourcePolicyNumber__c);
				rec.sourceReceiptNumber__c = normalizeTrim(p.sourceReceiptNumber__c);
				rec.sourceInsuranceCarrier__c = normalizeUppercase(
					p.sourceInsuranceCarrier__c
				);
				rec.sourceAmount__c = roundAmount(p.sourceAmount__c);
				rec.sourceGrossCommission__c = roundAmount(p.sourceGrossCommission__c);
				rec.sourceVatCommission__c = roundAmount(p.sourceVatCommission__c);
				rec.candidateInstallment__c = matchInstallment(p, installmentsByPolicy);
				rec.inboundStatus__c = STATUS_NORMALIZED;
				rec.parsedAt__c = normalizedAt;
			} catch (Exception e) {
				rec.inboundStatus__c = STATUS_REJECTED;
				rec.rejectionReason__c = REASON_NORMALIZATION_ERROR;
				rec.parsedAt__c = normalizedAt;
			}
			toUpdate.add(rec);
		}

		update toUpdate;
	}

	/**
	 * @creation date: 02/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Aplica trim y convierte a mayusculas el valor recibido.
	 *               Retorna null si el valor es null.
	 * @param value: Texto a normalizar.
	 * @return Texto sin espacios extremos y en mayusculas, o null.
	 */
	private static String normalizeUppercase(String value) {
		return value == null ? null : value.trim().toUpperCase();
	}

	/**
	 * @creation date: 02/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Aplica trim al valor recibido sin modificar su capitalizacion.
	 *               Retorna null si el valor es null.
	 * @param value: Texto a normalizar.
	 * @return Texto sin espacios extremos, o null.
	 */
	private static String normalizeTrim(String value) {
		return value == null ? null : value.trim();
	}

	/**
	 * @creation date: 02/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Redondea el monto a 2 decimales usando la regla HALF_UP.
	 *               Retorna null si el valor es null.
	 * @param value: Monto a redondear.
	 * @return Monto con 2 decimales, o null.
	 */
	private static Decimal roundAmount(Decimal value) {
		return value == null ? null : value.setScale(2, RoundingMode.HALF_UP);
	}

	/**
	 * @creation date: 02/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Carga las cuotas de los planes de pago asociados a las polizas
	 *               indicadas, agrupadas por ID de poliza. Usa 2 consultas separadas
	 *               para evitar valores null en campos de relacion en SELECT.
	 * @param policyIds: Conjunto de IDs de InsurancePolicy a consultar.
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
	 * @creation date: 02/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Orquesta el matching jerarquico de cuota candidata para un pago.
	 *               Intenta primero por numero de cuota y luego por fecha de vencimiento.
	 *               Solo asigna si el match es univoco (exactamente 1 resultado).
	 * @param payment: Registro inbound a resolver.
	 * @param installmentsByPolicy: Cuotas disponibles agrupadas por poliza.
	 * @return ID de la cuota candidata, o null si no hay match univoco.
	 */
	private static Id matchInstallment(
		InboundInsurancePayment__c payment,
		Map<Id, List<PaymentPlanInstallment__c>> installmentsByPolicy
	) {
		if (payment.candidatePolicy__c == null) {
			return null;
		}
		List<PaymentPlanInstallment__c> installments = installmentsByPolicy.get(
			payment.candidatePolicy__c
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
	 * @creation date: 02/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Busca una cuota cuyo sequenceNumber__c coincida con el numero
	 *               de cuota informado. Retorna el ID solo si hay exactamente 1 match.
	 *               Si el valor recibido no puede convertirse a Decimal, retorna null
	 *               sin propagar la excepcion.
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
	 * @creation date: 02/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Busca una cuota cuyo dueDate__c coincida exactamente con la fecha
	 *               de vencimiento informada. Retorna el ID solo si hay exactamente 1 match.
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
