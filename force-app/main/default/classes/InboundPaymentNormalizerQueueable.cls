/**
 *   @name: InboundPaymentNormalizerQueueable
 *   @version: 2.0
 *   @creation date: 02/05/2026
 *   @author: Javier Torres - Volestra
 *   @description: Normaliza y estandariza pagos inbound en estado Parseado:
 *                 limpia y estandariza campos de texto, redondea montos a 2
 *                 decimales y actualiza el estado a Normalizado o Rechazado
 *                 segun el resultado. Encadena a InboundPolicyCandidateQueueable
 *                 para la resolucion de poliza candidata.
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
	 *               aplica la normalizacion de campos de texto y montos, y actualiza el
	 *               estado a Normalizado o Rechazado segun resultado. Si ocurre una
	 *               excepcion durante el procesamiento de un registro individual, ese
	 *               registro queda con inboundStatus__c = Rechazado y rejectionReason__c
	 *               = 'Error de normalizacion', sin afectar al resto del lote.
	 *               Encadena a InboundPolicyCandidateQueueable con los IDs normalizados.
	 * @param context: Contexto de ejecucion del Queueable proporcionado por la plataforma.
	 * @return
	 */
	public void execute(QueueableContext context) {
		List<InboundInsurancePayment__c> payments = [
			SELECT
				Id,
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

		Set<Id> normalizedIds = new Set<Id>();
		for (InboundInsurancePayment__c rec : toUpdate) {
			if (rec.inboundStatus__c == STATUS_NORMALIZED) {
				normalizedIds.add(rec.Id);
			}
		}
		if (!normalizedIds.isEmpty()) {
			System.enqueueJob(new InboundPolicyCandidateQueueable(normalizedIds));
		}
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
}
