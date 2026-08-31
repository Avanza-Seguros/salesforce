/**
 *   @name: PolicyPaymentReceiptReversalService
 *   @version: 1.0
 *   @creation date: 30/07/2026
 *   @author: Javier Torres - Volestra
 *   @description: Reversa de un recibo reconocido (H201). Deshace el lado del pago cuando un
 *                 cobro deja de ser valido: devuelve la conciliacion a la bandeja de revision
 *                 y el pago inbound al circuito, sin eliminar nunca el recibo.
 *                 La cascada se dispara por la TRANSICION de estado (Reconocido -> Reversado),
 *                 no por la accion de usuario. Esa es la decision de diseno central: cualquier
 *                 via que produzca esa transicion -la accion del analista, una carga de datos,
 *                 la API o el reproceso a la baja de una historia futura- genera exactamente
 *                 los mismos efectos, sin duplicar logica. La accion de usuario solo captura
 *                 motivo y notas y cambia el estado.
 *                 El vinculo de la conciliacion al recibo reversado se CONSERVA: borrarlo
 *                 perderia la evidencia que esta historia existe para preservar. Lo que indica
 *                 que el caso volvio a estar abierto es el estado de la conciliacion.
 *                 Reabre ademas la cuota que el recibo cubria (H202), con lo que la obligacion
 *                 vuelve a existir. El plan y la poliza NO requieren codigo aqui: actualizar la
 *                 cuota dispara el manejador de cuotas, que recalcula el plan e invoca el
 *                 resumen de cobranza de la poliza.
 *                 La senalizacion comercial es la historia 203. Las tres se despliegan juntas:
 *                 un recibo reversado cuya cuota siguiera conciliada dejaria el sistema peor
 *                 que antes, porque la contradiccion pasaria a ser explicita.
 */
public with sharing class PolicyPaymentReceiptReversalService {
	private static final String RECEIPT_STATUS_RECOGNIZED = 'Reconocido';
	private static final String RECEIPT_STATUS_REVERSED = 'Reversado';
	private static final String RECON_STATUS_REVIEW = 'Requiere revision';
	private static final String INBOUND_STATUS_MANUAL_REVIEW = 'Revision Manual';

	private static final String INSTALLMENT_STATUS_PENDING = 'Pendiente';
	private static final String INSTALLMENT_STATUS_OVERDUE = 'Vencido';

	// Estados de cuota que una reversa NO revive: se anularon por una decision de negocio
	// deliberada y resucitarlos crearia una obligacion que nadie decidio volver a exigir.
	private static final Set<String> PROTECTED_INSTALLMENT_STATUSES = new Set<String>{
		'Cancelado',
		'Condonado'
	};

	@TestVisible
	private static Boolean forceFailureForTest = false;

	private class ReversalException extends Exception {
	}

	public class ReversalValidationException extends Exception {
	}

	/**
	 * @creation date: 30/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Punto de entrada AuraEnabled para la accion de reversa. Delega en
	 *               reverseReceipt y traduce las excepciones de negocio a AuraHandledException
	 *               para mostrarlas en el componente.
	 * @param receiptId: Id del PolicyPaymentReceipt__c a reversar.
	 * @param reversalReason: Motivo de la reversa (picklist reversalReason__c).
	 * @param notes: Notas del analista, obligatorias.
	 * @return
	 */
	@AuraEnabled
	public static void reverse(
		Id receiptId,
		String reversalReason,
		String notes
	) {
		try {
			reverseReceipt(receiptId, reversalReason, notes);
		} catch (ReversalValidationException e) {
			throw new AuraHandledException(e.getMessage());
		}
	}

	/**
	 * @creation date: 30/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Aplica la reversa sobre el recibo: valida que sea reversable y que venga
	 *               justificada, y cambia el estado a Reversado. NO ejecuta la cascada: eso lo
	 *               hace el trigger al detectar la transicion, de modo que este metodo y una
	 *               carga de datos produzcan exactamente el mismo resultado.
	 * @param receiptId: Id del recibo a reversar.
	 * @param reversalReason: Motivo de la reversa.
	 * @param notes: Notas del analista.
	 * @return
	 */
	@TestVisible
	private static void reverseReceipt(
		Id receiptId,
		String reversalReason,
		String notes
	) {
		if (receiptId == null) {
			throw new ReversalValidationException('Falta el recibo a reversar.');
		}
		if (String.isBlank(reversalReason)) {
			throw new ReversalValidationException(
				'Debe seleccionar un motivo de reversa.'
			);
		}
		if (String.isBlank(notes)) {
			throw new ReversalValidationException(
				'Debe capturar notas que expliquen la reversa.'
			);
		}

		List<PolicyPaymentReceipt__c> receipts = [
			SELECT Id, receiptStatus__c
			FROM PolicyPaymentReceipt__c
			WHERE Id = :receiptId
			LIMIT 1
		];
		if (receipts.isEmpty()) {
			throw new ReversalValidationException('El recibo no existe.');
		}

		String currentStatus = receipts[0].receiptStatus__c;
		if (RECEIPT_STATUS_REVERSED.equals(currentStatus)) {
			throw new ReversalValidationException(
				'El recibo ya está reversado. La reversa es definitiva y no se repite.'
			);
		}
		if (!RECEIPT_STATUS_RECOGNIZED.equals(currentStatus)) {
			throw new ReversalValidationException(
				'Solo puede reversarse un recibo reconocido. Este recibo está en estado ' +
					currentStatus +
					'.'
			);
		}

		update new PolicyPaymentReceipt__c(
			Id = receiptId,
			receiptStatus__c = RECEIPT_STATUS_REVERSED,
			reversalReason__c = reversalReason,
			reversalNotes__c = notes
		);
	}

	// El catalogo de motivos lo resuelve el componente con la API de interfaz de Salesforce
	// (getPicklistValues), igual que las acciones manuales de las historias 193 a 195. No se
	// expone un metodo Apex para eso: seria duplicar el catalogo y quedaria desincronizado.

	/**
	 * @creation date: 30/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Sella quien reverso y cuando, antes de guardar. Vive en el before update
	 *               para que la evidencia quede completa cualquiera sea la via de la reversa:
	 *               ni la carga de datos ni la API tienen por que acordarse de poblar esos
	 *               campos, y hacerlo aqui evita un DML adicional sobre los mismos registros.
	 *               Respeta un valor ya informado, por si una migracion necesita conservar la
	 *               autoria original.
	 * @param newReceipts: Recibos del contexto del trigger.
	 * @param oldMap: Valores anteriores de los recibos.
	 * @return
	 */
	public static void stampReversalAudit(
		List<PolicyPaymentReceipt__c> newReceipts,
		Map<Id, PolicyPaymentReceipt__c> oldMap
	) {
		if (newReceipts == null || oldMap == null) {
			return;
		}
		Datetime now = System.now();
		for (PolicyPaymentReceipt__c receipt : newReceipts) {
			if (!isNewlyReversed(receipt, oldMap)) {
				continue;
			}
			if (receipt.reversedBy__c == null) {
				receipt.reversedBy__c = UserInfo.getUserId();
			}
			if (receipt.reversedAt__c == null) {
				receipt.reversedAt__c = now;
			}
		}
	}

	/**
	 * @creation date: 30/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Punto de entrada de la cascada. Detecta los recibos que acaban de pasar a
	 *               Reversado y devuelve su conciliacion y su pago inbound al circuito de
	 *               revision, para que el analista pueda retomar el caso.
	 *               Un recibo sin conciliacion asociada -por ejemplo uno creado por una carga
	 *               masiva de cartera historica- se reversa con normalidad: simplemente no hay
	 *               nada que devolver al circuito.
	 * @param newReceipts: Recibos del contexto del trigger.
	 * @param oldMap: Valores anteriores de los recibos.
	 * @return
	 */
	public static void handleReversals(
		List<PolicyPaymentReceipt__c> newReceipts,
		Map<Id, PolicyPaymentReceipt__c> oldMap
	) {
		if (newReceipts == null || oldMap == null) {
			return;
		}

		Set<Id> reversedReceiptIds = new Set<Id>();
		for (PolicyPaymentReceipt__c receipt : newReceipts) {
			if (isNewlyReversed(receipt, oldMap)) {
				reversedReceiptIds.add(receipt.Id);
			}
		}

		if (reversedReceiptIds.isEmpty()) {
			return;
		}

		reopenReconciliations(reversedReceiptIds);
		reopenInstallments(reversedReceiptIds);
		signalOpportunities(reversedReceiptIds);
		AppLogger.flush();
	}

	/**
	 * @creation date: 30/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Señala la oportunidad comercial cuando la poliza queda SIN ningun cobro
	 *               valido tras la reversa (H203).
	 *               NO cambia la etapa, a proposito. La etapa pertenece al proceso comercial:
	 *               cobranza es dueña del estado de cobro y puede informar que su condicion
	 *               cambio, pero decidir que pasa con la venta no le corresponde. Ademas el
	 *               cambio automatico seria irreversible, porque el sistema no conserva la
	 *               etapa que la oportunidad tenia antes de cerrarse y no tendria a donde
	 *               devolverla. Y una venta no se pierde porque un cobro se caiga: el motivo
	 *               de una reversa suele ser transitorio.
	 *               Si la poliza conserva otros recibos reconocidos, no se toca nada: la
	 *               condicion que cerro la oportunidad sigue siendo cierta.
	 * @param reversedReceiptIds: Recibos que acaban de reversarse.
	 * @return
	 */
	private static void signalOpportunities(Set<Id> reversedReceiptIds) {
		Map<Id, PolicyPaymentReceipt__c> receiptByPolicy = new Map<Id, PolicyPaymentReceipt__c>();
		for (PolicyPaymentReceipt__c receipt : [
			SELECT Id, insurancePolicy__c, reversalReason__c
			FROM PolicyPaymentReceipt__c
			WHERE Id IN :reversedReceiptIds AND insurancePolicy__c != NULL
		]) {
			receiptByPolicy.put(receipt.insurancePolicy__c, receipt);
		}

		if (receiptByPolicy.isEmpty()) {
			return;
		}

		// Las polizas que conservan al menos un recibo reconocido quedan fuera: su oportunidad
		// sigue sostenida por un cobro valido.
		Set<Id> policiesWithoutValidReceipt = new Set<Id>(receiptByPolicy.keySet());
		for (AggregateResult ar : [
			SELECT insurancePolicy__c policyId
			FROM PolicyPaymentReceipt__c
			WHERE
				insurancePolicy__c IN :receiptByPolicy.keySet()
				AND receiptStatus__c = :RECEIPT_STATUS_RECOGNIZED
			GROUP BY insurancePolicy__c
		]) {
			policiesWithoutValidReceipt.remove((Id) ar.get('policyId'));
		}

		if (policiesWithoutValidReceipt.isEmpty()) {
			return;
		}

		Datetime now = System.now();
		List<Opportunity> toSignal = new List<Opportunity>();

		for (InsurancePolicy policy : [
			SELECT Id, SourceOpportunityId
			FROM InsurancePolicy
			WHERE Id IN :policiesWithoutValidReceipt
		]) {
			PolicyPaymentReceipt__c receipt = receiptByPolicy.get(policy.Id);
			if (policy.SourceOpportunityId == null) {
				CobranzaLog.warn(
						CobranzaLog.STAGE_REVERSA,
						CobranzaLog.EVENT_REVERSAL_OPPORTUNITY_MISSING,
						'La póliza quedó sin cobros válidos, pero no tiene oportunidad de origen que señalar.'
					)
					.onRecord(receipt.Id);
				continue;
			}
			toSignal.add(
				new Opportunity(
					Id = policy.SourceOpportunityId,
					collectionReversedFlag__c = true,
					collectionReversedOn__c = now,
					collectionReversalReason__c = receipt.reversalReason__c,
					collectionReversedReceipt__c = receipt.Id
				)
			);
		}

		updateOrLog(
			toSignal,
			CobranzaLog.EVENT_REVERSAL_OPPORTUNITY_FAILED,
			'No se pudo señalar la oportunidad tras quedar la póliza sin cobros válidos'
		);
	}

	/**
	 * @creation date: 30/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Retira la señal de la oportunidad cuando la poliza vuelve a tener un cobro
	 *               reconocido (H203). Es el reverso exacto de signalOpportunities y evita que
	 *               la vista de lista del responsable comercial acumule casos ya resueltos.
	 *               Se invoca tanto al crear un recibo reconocido como al pasar uno existente a
	 *               ese estado, porque ambas vias devuelven la validez del cobro.
	 * @param newReceipts: Recibos del contexto del trigger.
	 * @param oldMap: Valores anteriores, o null en contexto de insercion.
	 * @return
	 */
	public static void clearSignalOnRecognition(
		List<PolicyPaymentReceipt__c> newReceipts,
		Map<Id, PolicyPaymentReceipt__c> oldMap
	) {
		if (newReceipts == null) {
			return;
		}

		Set<Id> policyIds = new Set<Id>();
		for (PolicyPaymentReceipt__c receipt : newReceipts) {
			if (
				!RECEIPT_STATUS_RECOGNIZED.equals(receipt.receiptStatus__c) ||
				receipt.insurancePolicy__c == null
			) {
				continue;
			}
			if (oldMap != null) {
				PolicyPaymentReceipt__c oldReceipt = oldMap.get(receipt.Id);
				if (
					oldReceipt != null &&
					RECEIPT_STATUS_RECOGNIZED.equals(oldReceipt.receiptStatus__c)
				) {
					continue;
				}
			}
			policyIds.add(receipt.insurancePolicy__c);
		}

		if (policyIds.isEmpty()) {
			return;
		}

		Set<Id> opportunityIds = new Set<Id>();
		for (InsurancePolicy policy : [
			SELECT SourceOpportunityId
			FROM InsurancePolicy
			WHERE Id IN :policyIds AND SourceOpportunityId != NULL
		]) {
			opportunityIds.add(policy.SourceOpportunityId);
		}

		if (opportunityIds.isEmpty()) {
			return;
		}

		List<Opportunity> toClear = new List<Opportunity>();
		for (Opportunity opp : [
			SELECT Id
			FROM Opportunity
			WHERE Id IN :opportunityIds AND collectionReversedFlag__c = TRUE
		]) {
			toClear.add(
				new Opportunity(
					Id = opp.Id,
					collectionReversedFlag__c = false,
					collectionReversedOn__c = null,
					collectionReversalReason__c = null,
					collectionReversedReceipt__c = null
				)
			);
		}

		if (toClear.isEmpty()) {
			return;
		}

		updateOrLog(
			toClear,
			CobranzaLog.EVENT_REVERSAL_OPPORTUNITY_FAILED,
			'No se pudo retirar la señal de la oportunidad tras recuperarse el cobro'
		);
		AppLogger.flush();
	}

	/**
	 * @creation date: 30/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Reabre las cuotas que cubria el recibo reversado (H202). Desvincula el
	 *               recibo y devuelve la cuota a un estado abierto, con lo que la obligacion
	 *               vuelve a existir y puede volver a cobrarse.
	 *               El estado de retorno se calcula por FECHA y no se recupera el anterior:
	 *               recuperarlo daria un resultado equivocado si la reversa ocurre meses
	 *               despues de la conciliacion, porque una cuota que entonces estaba Pendiente
	 *               hoy puede estar vencida.
	 *               Los importes NO se escriben: el importe conciliado y el saldo pendiente son
	 *               formula sobre el recibo vinculado, asi que al desvincular se recalculan
	 *               solos. Intentar asignarlos fallaria.
	 *               El plan y la poliza tampoco requieren codigo: actualizar la cuota dispara
	 *               el manejador de cuotas, que recalcula el plan e invoca el resumen de la
	 *               poliza. La cascada existente hace ese trabajo.
	 *               La consulta filtra por matchedReceipt__c, de modo que una cuota que ya fue
	 *               vinculada a OTRO recibo no entra en el lote y queda intacta.
	 * @param reversedReceiptIds: Recibos que acaban de reversarse.
	 * @return
	 */
	private static void reopenInstallments(Set<Id> reversedReceiptIds) {
		List<PaymentPlanInstallment__c> installments = [
			SELECT Id, installmentStatus__c, dueDate__c, matchedReceipt__c
			FROM PaymentPlanInstallment__c
			WHERE matchedReceipt__c IN :reversedReceiptIds
		];

		if (installments.isEmpty()) {
			// Recibo sin cuota vinculada: caso valido. La reversa se completa igual.
			return;
		}

		Date today = Date.today();
		List<PaymentPlanInstallment__c> toUpdate = new List<PaymentPlanInstallment__c>();

		for (PaymentPlanInstallment__c inst : installments) {
			PaymentPlanInstallment__c reopened = new PaymentPlanInstallment__c(
				Id = inst.Id,
				matchedReceipt__c = null,
				matchedOn__c = null
			);
			// Una cuota cancelada o condonada se desvincula del recibo, pero conserva su
			// estado: la reversa deshace un cobro, no revierte la decision de anular la deuda.
			if (!PROTECTED_INSTALLMENT_STATUSES.contains(inst.installmentStatus__c)) {
				reopened.installmentStatus__c = isOverdue(inst.dueDate__c, today)
					? INSTALLMENT_STATUS_OVERDUE
					: INSTALLMENT_STATUS_PENDING;
			}
			toUpdate.add(reopened);
		}

		updateOrLog(
			toUpdate,
			CobranzaLog.EVENT_REVERSAL_INSTALLMENT_FAILED,
			'No se pudo reabrir la cuota tras reversar su recibo'
		);
	}

	/**
	 * @creation date: 30/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Indica si la cuota reabierta ya esta vencida. Una cuota sin fecha de
	 *               vencimiento se trata como no vencida: sin fecha no hay incumplimiento que
	 *               afirmar.
	 * @param dueDate: Fecha de vencimiento de la cuota.
	 * @param today: Fecha de referencia.
	 * @return true si la cuota debe volver a Vencido.
	 */
	private static Boolean isOverdue(Date dueDate, Date today) {
		return dueDate != null && dueDate < today;
	}

	/**
	 * @creation date: 30/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Devuelve a la bandeja las conciliaciones cuyo recibo fue reversado y sus
	 *               pagos inbound al circuito de revision manual. Ademas libera el sello de
	 *               resolucion manual: sin eso la conciliacion quedaria candada por el
	 *               guardail anti-reentrada y el caso no podria reprocesarse.
	 *               Se resuelve con un numero constante de consultas y actualizaciones,
	 *               independiente de la cantidad de recibos reversados.
	 * @param reversedReceiptIds: Recibos que acaban de reversarse.
	 * @return
	 */
	private static void reopenReconciliations(Set<Id> reversedReceiptIds) {
		List<PaymentReconciliation__c> reconciliations = [
			SELECT Id, inboundPayment__c, resultingReceipt__c
			FROM PaymentReconciliation__c
			WHERE resultingReceipt__c IN :reversedReceiptIds
		];

		if (reconciliations.isEmpty()) {
			// Recibo sin conciliacion: caso valido (carga masiva de cartera historica). No hay
			// nada que devolver al circuito y la reversa se completa igual.
			return;
		}

		List<PaymentReconciliation__c> reconsToUpdate = new List<PaymentReconciliation__c>();
		List<InboundInsurancePayment__c> inboundsToUpdate = new List<InboundInsurancePayment__c>();

		for (PaymentReconciliation__c recon : reconciliations) {
			reconsToUpdate.add(
				new PaymentReconciliation__c(
					Id = recon.Id,
					reconciliationStatus__c = RECON_STATUS_REVIEW,
					// Se suelta el puntero al recibo vigente: dejo de tener uno. Si no se
					// limpia, un reproceso posterior volveria a conciliar el caso pero el
					// motor NO generaria el recibo nuevo, porque solo crea recibo para las
					// conciliaciones con resultingReceipt__c vacio; la cuota quedaria
					// abierta para siempre.
					// Esto NO pierde evidencia: el recibo reversado conserva su propio
					// vinculo paymentReconciliation__c, por lo que sigue apareciendo en la
					// lista relacionada de la conciliacion.
					resultingReceipt__c = null,
					manualResolvedBy__c = null,
					manualResolvedAt__c = null
				)
			);
			if (recon.inboundPayment__c != null) {
				inboundsToUpdate.add(
					new InboundInsurancePayment__c(
						Id = recon.inboundPayment__c,
						inboundStatus__c = INBOUND_STATUS_MANUAL_REVIEW
					)
				);
			}
		}

		updateOrLog(
			reconsToUpdate,
			CobranzaLog.EVENT_REVERSAL_RECONCILIATION_FAILED,
			'No se pudo devolver la conciliación a la bandeja de revisión'
		);
		updateOrLog(
			inboundsToUpdate,
			CobranzaLog.EVENT_REVERSAL_INBOUND_FAILED,
			'No se pudo devolver el pago inbound al circuito de revisión'
		);
	}

	/**
	 * @creation date: 30/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Actualiza los registros en modo tolerante a fallos parciales y deja traza
	 *               de los que fallaron. Un registro que no se pueda actualizar no debe impedir
	 *               que el resto del lote se reverse, pero tampoco puede desaparecer en
	 *               silencio: si la conciliacion no vuelve a la bandeja, el caso queda perdido.
	 * @param records: Registros a actualizar.
	 * @param eventCode: Codigo de evento a registrar ante fallo.
	 * @param message: Mensaje legible del fallo.
	 * @return
	 */
	private static void updateOrLog(
		List<SObject> records,
		String eventCode,
		String message
	) {
		if (records.isEmpty()) {
			return;
		}
		try {
			if (forceFailureForTest) {
				throw new ReversalException('Forced failure for test');
			}
			List<Database.SaveResult> results = Database.update(records, false);
			for (Integer i = 0; i < results.size(); i++) {
				if (results[i].isSuccess()) {
					continue;
				}
				CobranzaLog.error(
						CobranzaLog.STAGE_REVERSA,
						eventCode,
						message + ': ' + describeErrors(results[i].getErrors())
					)
					.onRecord(records[i].Id);
			}
		} catch (Exception e) {
			CobranzaLog.error(CobranzaLog.STAGE_REVERSA, eventCode, e)
				.onRecord(records[0].Id);
		}
	}

	/**
	 * @creation date: 30/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Indica si el recibo acaba de pasar a Reversado en esta transaccion.
	 *               La reversa solo tiene sentido desde Reconocido: es el unico estado que
	 *               produjo efectos que haya que deshacer.
	 * @param receipt: Recibo actual.
	 * @param oldMap: Valores anteriores.
	 * @return true si el recibo transiciono de Reconocido a Reversado.
	 */
	private static Boolean isNewlyReversed(
		PolicyPaymentReceipt__c receipt,
		Map<Id, PolicyPaymentReceipt__c> oldMap
	) {
		if (receipt.receiptStatus__c != RECEIPT_STATUS_REVERSED) {
			return false;
		}
		PolicyPaymentReceipt__c oldReceipt = oldMap.get(receipt.Id);
		return oldReceipt != null &&
			RECEIPT_STATUS_RECOGNIZED.equals(oldReceipt.receiptStatus__c);
	}

	/**
	 * @creation date: 30/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Resume los errores devueltos por la plataforma para que el mensaje del
	 *               registro sea accionable.
	 * @param errors: Errores del resultado de la actualizacion.
	 * @return Texto con los mensajes concatenados.
	 */
	private static String describeErrors(List<Database.Error> errors) {
		List<String> messages = new List<String>();
		for (Database.Error err : errors) {
			messages.add(err.getStatusCode() + ' - ' + err.getMessage());
		}
		return String.join(messages, ' | ');
	}
}
