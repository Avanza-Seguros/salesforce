/**
 *   @name: PolicyPaymentReceiptTriggerHandler
 *   @version: 1.0
 *   @creation date: 15/06/2026
 *   @author: Javier Torres - Volestra
 *   @description: Cierra la Opportunity vinculada a la poliza cuando se registra
 *                 un PolicyPaymentReceipt__c reconocido. Navega la cadena
 *                 PolicyPaymentReceipt__c -> InsurancePolicy.SourceOpportunityId -> Opportunity
 *                 y actualiza StageName a Closed Won si la oportunidad esta en
 *                 un estado elegible. La actualizacion es best-effort (allOrNone=false)
 *                 para no bloquear la creacion del recibo ante un fallo comercial.
 */
public with sharing class PolicyPaymentReceiptTriggerHandler {
	private static final String RECEIPT_STATUS_RECOGNIZED = 'Reconocido';
	private static final String STAGE_CLOSED_WON = 'Closed Won';
	private static final String STAGE_CLOSED_LOST = 'Closed Lost';

	// Fuerza el fallo de la actualizacion de la oportunidad para poder probar el registro
	// del error tecnico (H200). Mismo patron que forceFailureForTest en los eslabones del
	// pipeline: es la unica forma de provocar ese fallo de plataforma desde una prueba.
	@TestVisible
	private static Boolean forceOpportunityFailureForTest = false;

	/**
	 * @creation date: 15/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Procesa recibos recien insertados buscando los reconocidos
	 *               para cerrar la oportunidad vinculada.
	 * @param newReceipts: Recibos insertados en la transaccion actual.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	public static void handleAfterInsert(
		List<PolicyPaymentReceipt__c> newReceipts
	) {
		processRecognizedReceipts(newReceipts, null);
	}

	/**
	 * @creation date: 15/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Procesa recibos actualizados detectando transiciones hacia
	 *               estado Reconocido para cerrar la oportunidad vinculada.
	 * @param newReceipts: Valores actualizados de los recibos.
	 * @param oldMap: Valores anteriores de los recibos.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	public static void handleAfterUpdate(
		List<PolicyPaymentReceipt__c> newReceipts,
		Map<Id, PolicyPaymentReceipt__c> oldMap
	) {
		processRecognizedReceipts(newReceipts, oldMap);
	}

	/**
	 * @creation date: 15/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Filtra los recibos que acaban de adquirir estado Reconocido
	 *               y delega el cierre de las oportunidades correspondientes.
	 * @param receipts: Recibos de la transaccion actual.
	 * @param oldMap: Valores anteriores; null en contexto de insert.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	private static void processRecognizedReceipts(
		List<PolicyPaymentReceipt__c> receipts,
		Map<Id, PolicyPaymentReceipt__c> oldMap
	) {
		Map<Id, Id> receiptByPolicy = new Map<Id, Id>();

		for (PolicyPaymentReceipt__c receipt : receipts) {
			if (!isNewlyRecognized(receipt, oldMap)) {
				continue;
			}

			if (receipt.insurancePolicy__c == null) {
				continue;
			}

			receiptByPolicy.put(receipt.insurancePolicy__c, receipt.Id);
		}

		if (receiptByPolicy.isEmpty()) {
			return;
		}

		closeOpportunitiesForPolicies(receiptByPolicy);
		AppLogger.flush();
	}

	/**
	 * @creation date: 15/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Indica si el recibo acaba de pasar a estado Reconocido en
	 *               esta transaccion, tanto en insert como en update.
	 * @param receipt: Recibo actual.
	 * @param oldMap: Valores anteriores; null en contexto de insert.
	 * @return: Boolean true si el estado acaba de ser Reconocido.
	 * @exception:
	 * @throws:
	 */
	private static Boolean isNewlyRecognized(
		PolicyPaymentReceipt__c receipt,
		Map<Id, PolicyPaymentReceipt__c> oldMap
	) {
		if (receipt.receiptStatus__c != RECEIPT_STATUS_RECOGNIZED) {
			return false;
		}

		if (oldMap == null) {
			return true;
		}

		PolicyPaymentReceipt__c oldReceipt = oldMap.get(receipt.Id);
		return oldReceipt == null ||
			oldReceipt.receiptStatus__c != RECEIPT_STATUS_RECOGNIZED;
	}

	/**
	 * @creation date: 15/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Navega InsurancePolicy.SourceOpportunityId y actualiza a
	 *               Closed Won las oportunidades en estado elegible. Excluye
	 *               oportunidades ya en Closed Won (idempotencia) y Closed Lost
	 *               (no reabrir negocios perdidos). La actualizacion es best-effort.
	 *               Deja traza (H200) de los casos en que la oportunidad NO se cierra: la
	 *               poliza sin oportunidad de origen y la oportunidad en Closed Lost son
	 *               decisiones de negocio invisibles en los datos, y el fallo tecnico de la
	 *               actualizacion se descartaba en silencio por ser best-effort. El cierre
	 *               exitoso no se registra: ya es visible en la propia oportunidad.
	 * @param receiptByPolicy: Mapa de poliza al recibo recien reconocido que la origina.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	private static void closeOpportunitiesForPolicies(
		Map<Id, Id> receiptByPolicy
	) {
		Map<Id, Id> receiptByOpportunity = new Map<Id, Id>();

		for (InsurancePolicy policy : [
			SELECT Id, SourceOpportunityId
			FROM InsurancePolicy
			WHERE Id IN :receiptByPolicy.keySet()
		]) {
			if (policy.SourceOpportunityId == null) {
				CobranzaLog.warn(
						CobranzaLog.STAGE_OPORTUNIDAD,
						CobranzaLog.EVENT_OPPORTUNITY_MISSING,
						'La póliza no tiene oportunidad de origen: no hay oportunidad comercial que cerrar.'
					)
					.onRecord(receiptByPolicy.get(policy.Id));
				continue;
			}
			receiptByOpportunity.put(
				policy.SourceOpportunityId,
				receiptByPolicy.get(policy.Id)
			);
		}

		if (receiptByOpportunity.isEmpty()) {
			return;
		}

		List<Opportunity> toUpdate = new List<Opportunity>();

		for (Opportunity opp : [
			SELECT Id, StageName
			FROM Opportunity
			WHERE Id IN :receiptByOpportunity.keySet()
		]) {
			if (STAGE_CLOSED_LOST.equals(opp.StageName)) {
				CobranzaLog.warn(
						CobranzaLog.STAGE_OPORTUNIDAD,
						CobranzaLog.EVENT_OPPORTUNITY_LOST,
						'La oportunidad está en Closed Lost: un cobro reconocido no reabre un negocio perdido.'
					)
					.onRecord(receiptByOpportunity.get(opp.Id));
				continue;
			}
			// Ya en Closed Won: no se registra. Es el resultado esperado de la idempotencia
			// y registrarlo generaria ruido en cada recibo posterior de la misma poliza.
			if (STAGE_CLOSED_WON.equals(opp.StageName)) {
				continue;
			}
			Opportunity toClose = new Opportunity(
				Id = opp.Id,
				StageName = STAGE_CLOSED_WON
			);
			if (forceOpportunityFailureForTest) {
				// Vaciar un campo obligatorio produce un fallo de plataforma devuelto como
				// resultado (no como excepcion), que es exactamente el caso que el registro
				// tiene que capturar.
				toClose.CloseDate = null;
			}
			toUpdate.add(toClose);
		}

		if (toUpdate.isEmpty()) {
			return;
		}

		List<Database.SaveResult> results = Database.update(toUpdate, false);
		for (Integer i = 0; i < results.size(); i++) {
			if (results[i].isSuccess()) {
				continue;
			}
			CobranzaLog.error(
					CobranzaLog.STAGE_OPORTUNIDAD,
					CobranzaLog.EVENT_OPPORTUNITY_UPDATE_FAILED,
					'No se pudo cerrar la oportunidad: ' +
					describeErrors(results[i].getErrors())
				)
				.onRecord(receiptByOpportunity.get(toUpdate[i].Id))
				.appendDetails('Oportunidad: ' + toUpdate[i].Id);
		}
	}

	/**
	 * @creation date: 30/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Resume los errores devueltos por la plataforma al actualizar la
	 *               oportunidad, para que el mensaje del registro sea accionable.
	 * @param errors: Errores del resultado de la actualizacion.
	 * @return: Texto con los mensajes concatenados.
	 * @exception:
	 * @throws:
	 */
	private static String describeErrors(List<Database.Error> errors) {
		List<String> messages = new List<String>();
		for (Database.Error err : errors) {
			messages.add(err.getStatusCode() + ' - ' + err.getMessage());
		}
		return String.join(messages, ' | ');
	}
}
