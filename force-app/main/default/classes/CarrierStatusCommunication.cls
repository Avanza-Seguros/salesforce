/**
 *   @name: CarrierStatusCommunication
 *   @version: 1.0
 *   @creation date: 29/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Lo que comunica la aseguradora sobre el estado de una poliza, sin importar por
 *                 que canal llego. El servicio que guarda el estado solo trabaja con
 *                 esto: el canal de pagos y el de polizas arman cada uno el suyo.
 */
public with sharing class CarrierStatusCommunication implements Comparable {
	public static final String SOURCE_PAYMENTS = 'Canal de pagos';
	public static final String SOURCE_POLICIES = 'Canal de polizas';

	// Registro que trajo la comunicacion: un pago inbound o una comunicacion de poliza.
	public Id sourceRecordId;
	public Id policyId;
	public String source;
	public String carrierCode;
	// Vacio: la comunicacion no informa estado; solo cuenta como que la poliza se reporto.
	public String rawStatus;
	public Date cancellationDate;
	public String cancellationReason;
	public Datetime communicatedAt;

	/**
	 * @creation date: 29/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Comunicacion que llego por el canal de pagos (aviso de estado o recibo que
	 *               ademas informa el estado de su poliza).
	 * @param rec: Pago inbound.
	 * @param policyId: Poliza identificada.
	 * @return: CarrierStatusCommunication Comunicacion.
	 * @exception:
	 * @throws:
	 */
	public static CarrierStatusCommunication fromPayment(
		InboundInsurancePayment__c rec,
		Id policyId
	) {
		CarrierStatusCommunication c = new CarrierStatusCommunication();
		c.sourceRecordId = rec.Id;
		c.policyId = policyId;
		c.source = SOURCE_PAYMENTS;
		c.carrierCode = rec.sourceCarrierCode__c;
		c.rawStatus = rec.sourcePolicyStatusRaw__c;
		c.cancellationDate = rec.sourceCancellationDate__c;
		c.cancellationReason = rec.sourceCancellationReason__c;
		c.communicatedAt = rec.sourceSynchronizedAt__c != null
			? rec.sourceSynchronizedAt__c
			: rec.receivedAt__c;
		return c;
	}

	/**
	 * @creation date: 29/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Comunicacion que llego por el canal de polizas.
	 * @param rec: Comunicacion de poliza.
	 * @param policyId: Poliza identificada.
	 * @return: CarrierStatusCommunication Comunicacion.
	 * @exception:
	 * @throws:
	 */
	public static CarrierStatusCommunication fromPolicyUpdate(
		InboundPolicyUpdate__c rec,
		Id policyId
	) {
		CarrierStatusCommunication c = new CarrierStatusCommunication();
		c.sourceRecordId = rec.Id;
		c.policyId = policyId;
		c.source = SOURCE_POLICIES;
		c.carrierCode = rec.sourceCarrierCode__c;
		c.rawStatus = rec.sourcePolicyStatusRaw__c;
		c.cancellationDate = rec.sourceCancellationDate__c;
		c.cancellationReason = rec.sourceCancellationReason__c;
		c.communicatedAt = rec.sourceSynchronizedAt__c != null
			? rec.sourceSynchronizedAt__c
			: rec.receivedAt__c;
		return c;
	}

	public Boolean fromPolicyChannel() {
		return SOURCE_POLICIES.equals(source);
	}

	/**
	 * @creation date: 29/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Orden de aplicacion: de la mas antigua a la mas reciente, para que la ultima
	 *               que se aplique sea la que manda. Con la misma fecha, la del canal de polizas
	 *               va despues: es el canal dedicado y gana el empate.
	 * @param other: Otra comunicacion.
	 * @return: Integer Negativo si esta va antes.
	 * @exception:
	 * @throws:
	 */
	public Integer compareTo(Object other) {
		CarrierStatusCommunication that = (CarrierStatusCommunication) other;

		if (communicatedAt != that.communicatedAt) {
			if (communicatedAt == null) {
				return -1;
			}

			if (that.communicatedAt == null) {
				return 1;
			}

			return communicatedAt < that.communicatedAt ? -1 : 1;
		}

		if (fromPolicyChannel() == that.fromPolicyChannel()) {
			return 0;
		}

		return fromPolicyChannel() ? 1 : -1;
	}
}
