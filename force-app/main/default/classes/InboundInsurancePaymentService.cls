/**
 *   @name: InboundInsurancePaymentService
 *   @version: 1.0
 *   @creation date: 24/04/2026
 *   @author: Javier Torres - Volestra
 *   @description: Recibe, valida y registra tecnicamente pagos inbound enviados
 *                 por MuleSoft antes de cualquier conciliacion de negocio.
 *                 Convencion de idioma: codigos tecnicos en ingles
 *                 (RECEIVED, REJECTED, BATCH_PROCESSED) y valores funcionales
 *                 que se persisten o muestran al usuario en espanol
 *                 (Parseado, Rechazado, motivos de rechazo, mensajes).
 */
public with sharing class InboundInsurancePaymentService {
	private static final String STATUS_PARSED = 'Parseado';
	private static final String STATUS_REJECTED = 'Rechazado';
	private static final String STATUS_PENDING_PAYMENT = 'Pendiente de Pago';
	private static final String INBOUND_STATUS_RECONCILED = 'Conciliado';
	private static final String REJECTION_REASON_MALFORMED_PAYLOAD = 'Payload malformado';
	private static final String REJECTION_REASON_INCOMPLETE_PAYLOAD = 'Payload incompleto';
	private static final String REJECTION_REASON_INVALID_AMOUNT = 'Importe invalido';
	private static final String CODE_RECEIVED = 'RECEIVED';
	private static final String CODE_UPDATED = 'UPDATED';
	private static final String CODE_REJECTED = 'REJECTED';
	private static final String CODE_BATCH_PROCESSED = 'BATCH_PROCESSED';
	private static final String CODE_EMPTY_BODY = 'EMPTY_BODY';
	private static final String CODE_INVALID_JSON = 'INVALID_JSON';
	private static final String SOURCE_SYSTEM = 'MuleSoft';
	private static final Boolean USE_CANCELLATION_DATE_AS_PAYMENT_FALLBACK = true;

	private static final String OUTCOME_SKIPPED = 'SKIPPED';
	private static final String OUTCOME_REJECTED = 'REJECTED';
	private static final String OUTCOME_RECEIVED = 'RECEIVED';
	private static final String OUTCOME_UPDATED = 'UPDATED';

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Punto de entrada del servicio. Valida el cuerpo, lo parsea
	 *               y persiste los pagos inbound de forma bulkificada (una sola
	 *               SOQL por dependencia y un unico DML por operacion).
	 *               Si el JSON esta malformado o no es un arreglo, persiste un
	 *               registro rechazado antes de retornar el error.
	 * @param requestBody: Cuerpo crudo recibido en el endpoint REST.
	 * @return EndpointResult con statusCode y body listos para serializar.
	 */
	public static EndpointResult receive(String requestBody) {
		if (String.isBlank(requestBody)) {
			return buildErrorResult(
				400,
				CODE_EMPTY_BODY,
				'El cuerpo de la solicitud es requerido.'
			);
		}

		Object rawPayload;
		try {
			rawPayload = JSON.deserializeUntyped(requestBody);
		} catch (Exception e) {
			InboundInsurancePayment__c rejected = persistSingleRejected(
				requestBody,
				REJECTION_REASON_MALFORMED_PAYLOAD
			);
			return buildErrorResult(
				400,
				CODE_INVALID_JSON,
				'El cuerpo de la solicitud no es un arreglo JSON valido.',
				rejected
			);
		}

		if (!(rawPayload instanceof List<Object>)) {
			InboundInsurancePayment__c rejected = persistSingleRejected(
				requestBody,
				REJECTION_REASON_MALFORMED_PAYLOAD
			);
			return buildErrorResult(
				400,
				CODE_INVALID_JSON,
				'El cuerpo de la solicitud debe ser un arreglo JSON de pagos.',
				rejected
			);
		}

		List<Object> rows = (List<Object>) rawPayload;
		if (rows.isEmpty()) {
			return buildErrorResult(
				400,
				CODE_EMPTY_BODY,
				'El cuerpo de la solicitud debe incluir al menos un pago.'
			);
		}

		return processRows(rows);
	}

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Procesa el lote de filas ya parseadas del payload. Resuelve IDs
	 *               existentes y polizas candidatas en una sola ronda de SOQLs, clasifica
	 *               cada fila como nueva, actualizada o rechazada, ejecuta los DMLs
	 *               bulkificados y encola la normalizacion asincrona.
	 * @param rows: Lista de objetos crudos del payload JSON a procesar.
	 * @return EndpointResult con el resumen del lote y el detalle por fila.
	 */
	private static EndpointResult processRows(List<Object> rows) {
		List<RowContext> contexts = parseAllRows(rows);

		Set<String> externalIds = new Set<String>();
		Set<String> policyNumbers = new Set<String>();
		for (RowContext ctx : contexts) {
			if (ctx.skip) {
				continue;
			}
			if (String.isNotBlank(ctx.data.externalPaymentId)) {
				externalIds.add(ctx.data.externalPaymentId);
			}
			if (String.isNotBlank(ctx.data.sourcePolicyNumber)) {
				policyNumbers.add(ctx.data.sourcePolicyNumber);
			}
		}

		Map<String, InboundInsurancePayment__c> existingByExternalId = findExistingInbounds(
			externalIds
		);
		Map<String, Id> candidatePolicyByNumber = findCandidatePolicies(
			policyNumbers
		);

		List<InboundInsurancePayment__c> toInsert = new List<InboundInsurancePayment__c>();
		List<InboundInsurancePayment__c> toUpdate = new List<InboundInsurancePayment__c>();
		Map<String, RowContext> firstByExternalId = new Map<String, RowContext>();

		Integer received = 0;
		Integer updated = 0;
		Integer rejected = 0;

		for (RowContext ctx : contexts) {
			if (ctx.skip) {
				rejected++;
				ctx.outcome = OUTCOME_SKIPPED;
				continue;
			}

			Id candidatePolicyId = candidatePolicyByNumber.get(
				ctx.data.sourcePolicyNumber
			);

			if (ctx.validationReason != null) {
				ctx.record = buildInboundRecord(
					ctx.data,
					ctx.itemJson,
					ctx.payloadHash,
					STATUS_REJECTED,
					ctx.validationReason,
					candidatePolicyId
				);
				toInsert.add(ctx.record);
				ctx.outcome = OUTCOME_REJECTED;
				rejected++;
				continue;
			}

			Boolean hasPaymentDate = ctx.data.sourcePaymentDate != null;

			if (firstByExternalId.containsKey(ctx.data.externalPaymentId)) {
				RowContext first = firstByExternalId.get(ctx.data.externalPaymentId);
				ctx.existingStatus = first.existingStatus;
				populateInboundData(
					first.record,
					ctx.data,
					ctx.itemJson,
					ctx.payloadHash,
					resolveInboundStatus(hasPaymentDate, first.existingStatus),
					null,
					candidatePolicyId
				);
				ctx.record = first.record;
				ctx.outcome = OUTCOME_UPDATED;
				updated++;
				continue;
			}

			InboundInsurancePayment__c existing = existingByExternalId.get(
				ctx.data.externalPaymentId
			);
			if (existing != null) {
				ctx.existingStatus = existing.inboundStatus__c;
				logResentWithChanges(existing, ctx.data);
				InboundInsurancePayment__c rec = new InboundInsurancePayment__c(
					Id = existing.Id
				);
				populateInboundData(
					rec,
					ctx.data,
					ctx.itemJson,
					ctx.payloadHash,
					resolveInboundStatus(hasPaymentDate, existing.inboundStatus__c),
					null,
					candidatePolicyId
				);
				ctx.record = rec;
				toUpdate.add(rec);
				ctx.outcome = OUTCOME_UPDATED;
				firstByExternalId.put(ctx.data.externalPaymentId, ctx);
				updated++;
				continue;
			}

			ctx.record = buildInboundRecord(
				ctx.data,
				ctx.itemJson,
				ctx.payloadHash,
				resolveInboundStatus(hasPaymentDate, null),
				null,
				candidatePolicyId
			);
			toInsert.add(ctx.record);
			ctx.outcome = OUTCOME_RECEIVED;
			firstByExternalId.put(ctx.data.externalPaymentId, ctx);
			received++;
		}

		if (!toInsert.isEmpty()) {
			insert toInsert;
		}
		if (!toUpdate.isEmpty()) {
			update toUpdate;
		}

		enqueueNormalization(toInsert, toUpdate);
		AppLogger.flush();

		List<ItemResult> results = new List<ItemResult>();
		for (RowContext ctx : contexts) {
			results.add(toItemResult(ctx));
		}

		return buildBatchResult(rows.size(), received, updated, rejected, results);
	}

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Convierte cada elemento del arreglo JSON en un RowContext con
	 *               los datos parseados, el JSON serializado, el hash del payload
	 *               y el motivo de rechazo si la validacion falla. Filas que no
	 *               son objetos JSON quedan marcadas como skip.
	 * @param rows: Lista de objetos crudos del payload JSON.
	 * @return Lista de RowContext uno por cada elemento del arreglo recibido.
	 */
	private static List<RowContext> parseAllRows(List<Object> rows) {
		List<RowContext> contexts = new List<RowContext>();
		for (Object rawRow : rows) {
			RowContext ctx = new RowContext();
			if (!(rawRow instanceof Map<String, Object>)) {
				ctx.skip = true;
				ctx.skipMessage = 'Cada elemento debe ser un objeto JSON.';
				contexts.add(ctx);
				continue;
			}

			Map<String, Object> rowPayload = (Map<String, Object>) rawRow;
			ctx.data = parseInboundData(rowPayload);
			ctx.itemJson = JSON.serialize(rowPayload);
			ctx.payloadHash = calculatePayloadHash(ctx.itemJson);
			Boolean hasAmountField = rowPayload.containsKey('sourceAmount__c');
			ctx.validationReason = validatePayload(
				ctx.data.externalPaymentId,
				ctx.data.sourcePolicyNumber,
				ctx.data.sourceAmount,
				hasAmountField
			);
			contexts.add(ctx);
		}
		return contexts;
	}

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Convierte un RowContext procesado en un ItemResult serializable
	 *               para incluir en la respuesta del endpoint. El codigo y mensaje
	 *               del resultado dependen del outcome asignado durante el procesamiento.
	 * @param ctx: Contexto de la fila ya procesada con su outcome y record asignados.
	 * @return ItemResult con el codigo, mensaje e IDs correspondientes al outcome.
	 */
	private static ItemResult toItemResult(RowContext ctx) {
		if (ctx.outcome == OUTCOME_SKIPPED) {
			return new ItemResult(false, CODE_REJECTED, ctx.skipMessage, null, null);
		}
		if (ctx.outcome == OUTCOME_REJECTED) {
			return new ItemResult(
				false,
				CODE_REJECTED,
				getValidationMessage(ctx.validationReason),
				ctx.data.externalPaymentId,
				ctx.record.Id
			);
		}
		if (ctx.outcome == OUTCOME_UPDATED) {
			return new ItemResult(
				true,
				CODE_UPDATED,
				'El pago inbound ya existia y fue actualizado.',
				ctx.data.externalPaymentId,
				ctx.record.Id
			);
		}
		return new ItemResult(
			true,
			CODE_RECEIVED,
			'Pago inbound recibido correctamente.',
			ctx.data.externalPaymentId,
			ctx.record.Id
		);
	}

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Persiste un unico registro inbound en estado Rechazado usando
	 *               el cuerpo crudo de la solicitud como payload. Se usa cuando el
	 *               JSON no puede parsearse o no tiene la estructura esperada.
	 * @param requestBody: Cuerpo crudo de la solicitud recibida.
	 * @param rejectionReason: Valor del picklist de motivo de rechazo a asignar.
	 * @return InboundInsurancePayment__c recien insertado con estado Rechazado.
	 */
	private static InboundInsurancePayment__c persistSingleRejected(
		String requestBody,
		String rejectionReason
	) {
		InboundInsurancePayment__c rec = buildInboundRecord(
			new ParsedInboundData(),
			requestBody,
			calculatePayloadHash(requestBody),
			STATUS_REJECTED,
			rejectionReason,
			null
		);
		insert rec;
		return rec;
	}

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Construye el EndpointResult de exito parcial o total para un lote.
	 *               Retorna statusCode 400 si todos los registros fueron rechazados,
	 *               202 si al menos uno fue recibido o actualizado correctamente.
	 * @param totalRecords: Total de elementos recibidos en el payload.
	 * @param receivedCount: Cantidad de registros nuevos insertados correctamente.
	 * @param updatedCount: Cantidad de registros existentes actualizados correctamente.
	 * @param rejectedCount: Cantidad de registros rechazados o saltados.
	 * @param results: Detalle por fila con codigo, mensaje e IDs.
	 * @return EndpointResult con statusCode y ResponseBody del lote.
	 */
	private static EndpointResult buildBatchResult(
		Integer totalRecords,
		Integer receivedCount,
		Integer updatedCount,
		Integer rejectedCount,
		List<ItemResult> results
	) {
		Integer statusCode = rejectedCount > 0 &&
			receivedCount == 0 &&
			updatedCount == 0
			? 400
			: 202;

		return new EndpointResult(
			statusCode,
			new ResponseBody(
				rejectedCount == 0,
				CODE_BATCH_PROCESSED,
				'Lote de pagos inbound procesado.',
				null,
				null,
				totalRecords,
				receivedCount,
				updatedCount,
				rejectedCount,
				results
			)
		);
	}

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Construye un EndpointResult de error con un unico registro inbound
	 *               opcional asociado. Usado para errores estructurales del payload
	 *               donde se persiste un registro rechazado antes de responder.
	 * @param statusCode: Codigo HTTP a retornar (ej. 400).
	 * @param code: Codigo tecnico del error (ej. INVALID_JSON).
	 * @param message: Mensaje descriptivo del error para el integrador.
	 * @param inboundPayment: Registro rechazado persistido, o null si no aplica.
	 * @return EndpointResult con statusCode y ResponseBody de error.
	 */
	private static EndpointResult buildErrorResult(
		Integer statusCode,
		String code,
		String message,
		InboundInsurancePayment__c inboundPayment
	) {
		return new EndpointResult(
			statusCode,
			new ResponseBody(
				false,
				code,
				message,
				inboundPayment == null ? null : inboundPayment.externalPaymentId__c,
				inboundPayment == null ? null : inboundPayment.Id,
				0,
				0,
				0,
				0,
				new List<ItemResult>()
			)
		);
	}

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Sobrecarga de buildErrorResult sin registro inbound asociado.
	 *               Usada para errores donde no se persiste ningun registro (ej. cuerpo vacio).
	 * @param statusCode: Codigo HTTP a retornar (ej. 400).
	 * @param code: Codigo tecnico del error (ej. EMPTY_BODY).
	 * @param message: Mensaje descriptivo del error para el integrador.
	 * @return EndpointResult con statusCode y ResponseBody de error sin inbound asociado.
	 */
	private static EndpointResult buildErrorResult(
		Integer statusCode,
		String code,
		String message
	) {
		return buildErrorResult(statusCode, code, message, null);
	}

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Valida los campos requeridos del payload parseado. Retorna el
	 *               motivo de rechazo si alguna regla falla, o null si el payload
	 *               es valido. Las validaciones son en orden: campos obligatorios
	 *               e importe. La fecha de pago dejo de ser requerida (historia HA):
	 *               un recibo sin fecha de pago se acepta y almacena; su ruteo lo
	 *               define la historia HB.
	 * @param externalPaymentId: Identificador de deduplicacion del pago (carrier_folio).
	 * @param sourcePolicyNumber: Numero de poliza informado.
	 * @param sourceAmount: Importe del pago parseado.
	 * @param hasAmountField: Indica si el campo sourceAmount__c estaba presente en el payload.
	 * @return Motivo de rechazo del picklist, o null si el payload es valido.
	 */
	private static String validatePayload(
		String externalPaymentId,
		String sourcePolicyNumber,
		Decimal sourceAmount,
		Boolean hasAmountField
	) {
		if (
			String.isBlank(externalPaymentId) || String.isBlank(sourcePolicyNumber)
		) {
			return REJECTION_REASON_INCOMPLETE_PAYLOAD;
		}

		if (!hasAmountField || sourceAmount == null || sourceAmount <= 0) {
			return REJECTION_REASON_INVALID_AMOUNT;
		}

		return null;
	}

	/**
	 * @creation date: 05/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Resuelve el estado de un pago inbound valido segun si trae fecha
	 *               de pago (historia HB). Un recibo con fecha de pago se marca
	 *               Parseado y entra al pipeline; uno sin fecha se marca
	 *               'Pendiente de Pago' y queda fuera del pipeline hasta que el mismo
	 *               recibo regrese con fecha. Un registro ya Rechazado no transiciona
	 *               a 'Pendiente de Pago' aunque llegue un reenvio sin fecha.
	 * @param hasPaymentDate: Indica si el pago trae fecha de pago efectiva.
	 * @param existingStatus: Estado actual del registro existente, o null si es nuevo.
	 * @return Estado a asignar: Parseado, Pendiente de Pago o Rechazado.
	 */
	private static String resolveInboundStatus(
		Boolean hasPaymentDate,
		String existingStatus
	) {
		if (hasPaymentDate) {
			return STATUS_PARSED;
		}
		if (existingStatus == STATUS_REJECTED) {
			return STATUS_REJECTED;
		}
		return STATUS_PENDING_PAYMENT;
	}

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Crea una nueva instancia de InboundInsurancePayment__c y la
	 *               popula via populateInboundData. Punto de entrada para construir
	 *               registros nuevos (INSERT), tanto Parseados como Rechazados.
	 * @param data: Datos parseados del payload de la fila.
	 * @param requestBody: JSON serializado de la fila para persistir como payload.
	 * @param payloadHash: Hash SHA-256 del JSON de la fila.
	 * @param inboundStatus: Estado inicial a asignar (Parseado o Rechazado).
	 * @param rejectionReason: Motivo de rechazo del picklist, o null si no aplica.
	 * @param candidatePolicyId: ID de la poliza candidata resuelta, o null.
	 * @return InboundInsurancePayment__c construido y listo para INSERT.
	 */
	private static InboundInsurancePayment__c buildInboundRecord(
		ParsedInboundData data,
		String requestBody,
		String payloadHash,
		String inboundStatus,
		String rejectionReason,
		Id candidatePolicyId
	) {
		InboundInsurancePayment__c inboundPayment = new InboundInsurancePayment__c();
		populateInboundData(
			inboundPayment,
			data,
			requestBody,
			payloadHash,
			inboundStatus,
			rejectionReason,
			candidatePolicyId
		);
		return inboundPayment;
	}

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Popula todos los campos del registro inbound a partir de los
	 *               datos parseados, el payload JSON, el hash y los metadatos de
	 *               estado. Usado tanto para INSERT (registro nuevo) como para
	 *               UPDATE (registro existente recibido nuevamente).
	 * @param inboundPayment: Instancia del registro a poblar (nueva o existente).
	 * @param data: Datos parseados del payload de la fila.
	 * @param requestBody: JSON serializado de la fila a persistir como payload.
	 * @param payloadHash: Hash SHA-256 del JSON de la fila.
	 * @param inboundStatus: Estado a asignar al registro.
	 * @param rejectionReason: Motivo de rechazo del picklist, o null si no aplica.
	 * @param candidatePolicyId: ID de la poliza candidata resuelta, o null.
	 * @return
	 */
	private static void populateInboundData(
		InboundInsurancePayment__c inboundPayment,
		ParsedInboundData data,
		String requestBody,
		String payloadHash,
		String inboundStatus,
		String rejectionReason,
		Id candidatePolicyId
	) {
		inboundPayment.externalPaymentId__c = data.externalPaymentId;
		inboundPayment.inboundStatus__c = inboundStatus;
		// Primera etapa del pipeline: el pago quedo recibido y persistido. Los eslabones
		// siguientes la van avanzando; junto con el estado permite listar los detenidos.
		// En un reenvio se reinicia a proposito: el pago vuelve a Parseado y recorre el
		// pipeline de nuevo, asi que la etapa alcanzada tiene que volver al principio.
		inboundPayment.pipelineStage__c = CobranzaLog.STAGE_RECEPCION;
		inboundPayment.parsedAt__c = System.now();
		inboundPayment.receivedAt__c = System.now();
		inboundPayment.rawBankReference__c = data.rawBankReference;
		inboundPayment.rejectionReason__c = rejectionReason;
		inboundPayment.sourceAmount__c = data.sourceAmount;
		inboundPayment.sourceCarrierCode__c = data.sourceCarrierCode;
		inboundPayment.sourceDueDate__c = data.sourceDueDate;
		inboundPayment.sourcePayloadHash__c = payloadHash;
		inboundPayment.sourcePayloadJson__c = requestBody;
		inboundPayment.sourcePaymentDate__c = data.sourcePaymentDate;
		inboundPayment.sourcePolicyNumber__c = data.sourcePolicyNumber;
		inboundPayment.sourceReceiptNumber__c = data.sourceReceiptNumber;
		inboundPayment.sourceSystem__c = SOURCE_SYSTEM;
		inboundPayment.candidatePolicy__c = candidatePolicyId;
		inboundPayment.sourceCollectionChannel__c = data.sourceCollectionChannel;
		inboundPayment.sourcePaymentStatusRaw__c = data.sourcePaymentStatusRaw;
		inboundPayment.sourcePaymentStatus__c = data.sourcePaymentStatus;
		inboundPayment.sourceCurrency__c = data.sourceCurrency;
		inboundPayment.sourceInsuranceCarrier__c = data.sourceInsuranceCarrier;
		inboundPayment.sourcePolicyBranch__c = data.sourcePolicyBranch;
		inboundPayment.sourceInstallmentNumber__c = data.sourceInstallmentNumber;
		inboundPayment.sourceCustomerExternalId__c = data.sourceCustomerExternalId;
		inboundPayment.sourceSynchronizedAt__c = data.sourceSynchronizedAt;
		inboundPayment.sourceCancellationDate__c = data.sourceCancellationDate;
		inboundPayment.sourceGrossCommission__c = data.sourceGrossCommission;
		inboundPayment.sourceVatCommission__c = data.sourceVatCommission;
		inboundPayment.sourcePolicyStatusRaw__c = data.sourcePolicyStatusRaw;
		inboundPayment.sourceCustomerName__c = data.sourceCustomerName;
		inboundPayment.sourceIsCollective__c = data.sourceIsCollective == null
			? false
			: data.sourceIsCollective;
		inboundPayment.sourceRetryCount__c = data.sourceRetryCount;
		inboundPayment.sourceRejectionReason__c = data.sourceRejectionReason;
		inboundPayment.sourceCancellationReason__c = data.sourceCancellationReason;
		inboundPayment.sourcePolicyStartDate__c = data.sourcePolicyStartDate;
		inboundPayment.sourcePolicyRenewalDate__c = data.sourcePolicyRenewalDate;
		inboundPayment.sourcePolicyIssueDate__c = data.sourcePolicyIssueDate;
	}

	/**
	 * @creation date: 30/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Deja traza cuando la integracion reenvia un pago que ya estaba
	 *               conciliado y ademas trae un importe o una fecha de pago distintos a los
	 *               que se conciliaron. Solo se registra ese caso: la integracion reenvia el
	 *               historico de forma rutinaria, y registrar cada reenvio sin cambios
	 *               inundaria el registro sin aportar nada. Un pago ya conciliado que vuelve
	 *               con otros datos, en cambio, es la senal de que lo conciliado dejo de
	 *               coincidir con lo que informa la aseguradora.
	 * @param existing: Registro inbound ya existente, con sus valores actuales.
	 * @param incoming: Datos parseados del reenvio.
	 * @return
	 */
	private static void logResentWithChanges(
		InboundInsurancePayment__c existing,
		ParsedInboundData incoming
	) {
		if (existing.inboundStatus__c != INBOUND_STATUS_RECONCILED) {
			return;
		}

		List<String> changes = new List<String>();
		if (existing.sourceAmount__c != incoming.sourceAmount) {
			changes.add(
				'importe ' + existing.sourceAmount__c + ' -> ' + incoming.sourceAmount
			);
		}
		if (existing.sourcePaymentDate__c != incoming.sourcePaymentDate) {
			changes.add(
				'fecha de pago ' +
					existing.sourcePaymentDate__c +
					' -> ' +
					incoming.sourcePaymentDate
			);
		}
		if (changes.isEmpty()) {
			return;
		}

		CobranzaLog.info(
				CobranzaLog.STAGE_RECEPCION,
				CobranzaLog.EVENT_INBOUND_RESENT_CHANGED,
				'Pago ya conciliado (' +
					existing.externalPaymentId__c +
					') reenviado con datos distintos: ' +
					String.join(changes, '; ') +
					'.'
			)
			.onInbound(existing.Id);
	}

	/**
	 * @creation date: 02/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Encola un InboundPaymentNormalizerQueueable con los IDs de los
	 *               registros (insertados o actualizados) que quedaron en estado
	 *               Parseado. Los rechazados y los 'Pendiente de Pago' (recibos sin
	 *               fecha de pago, historia HB) no se encolan: quedan fuera del
	 *               pipeline hasta transicionar a Parseado. Solo ejecuta el enqueue
	 *               si hay al menos un ID elegible.
	 * @param inserted: Registros recien insertados por el DML de este lote.
	 * @param updated: Registros recien actualizados por el DML de este lote.
	 * @return
	 */
	private static void enqueueNormalization(
		List<InboundInsurancePayment__c> inserted,
		List<InboundInsurancePayment__c> updated
	) {
		Set<Id> toNormalize = new Set<Id>();
		for (InboundInsurancePayment__c rec : inserted) {
			if (rec.inboundStatus__c == STATUS_PARSED) {
				toNormalize.add(rec.Id);
			}
		}
		for (InboundInsurancePayment__c rec : updated) {
			if (rec.inboundStatus__c == STATUS_PARSED) {
				toNormalize.add(rec.Id);
			}
		}
		if (!toNormalize.isEmpty()) {
			System.enqueueJob(new InboundPaymentNormalizerQueueable(toNormalize));
		}
	}

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Consulta los registros InboundInsurancePayment__c que ya existen
	 *               para los externalPaymentId__c recibidos, con su estado actual.
	 *               Permite detectar duplicados, rutear el registro a UPDATE en lugar
	 *               de INSERT y decidir la transicion de estado (historia HB: un
	 *               'Pendiente de Pago' que llega con fecha pasa a Parseado; un
	 *               Rechazado no transiciona a 'Pendiente de Pago').
	 * @param externalIds: Conjunto de externalPaymentId__c a buscar.
	 * @return Mapa de externalPaymentId__c al registro existente (Id + estado).
	 */
	private static Map<String, InboundInsurancePayment__c> findExistingInbounds(
		Set<String> externalIds
	) {
		Map<String, InboundInsurancePayment__c> result = new Map<String, InboundInsurancePayment__c>();
		if (externalIds.isEmpty()) {
			return result;
		}
		for (InboundInsurancePayment__c rec : [
			SELECT
				Id,
				externalPaymentId__c,
				inboundStatus__c,
				sourceAmount__c,
				sourcePaymentDate__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c IN :externalIds
		]) {
			result.put(rec.externalPaymentId__c, rec);
		}
		return result;
	}

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Busca InsurancePolicy cuyo Name o PolicyName coincida con alguno
	 *               de los numeros de poliza recibidos. Solo asigna la candidata si
	 *               el match es univoco (exactamente 1 poliza por numero). Si hay
	 *               mas de una coincidencia, el numero queda sin candidata.
	 * @param policyNumbers: Conjunto de numeros de poliza a resolver.
	 * @return Mapa de numero de poliza a Id de InsurancePolicy candidata unica.
	 */
	private static Map<String, Id> findCandidatePolicies(
		Set<String> policyNumbers
	) {
		Map<String, Id> result = new Map<String, Id>();
		if (policyNumbers.isEmpty()) {
			return result;
		}

		Map<String, Set<Id>> matchesByNumber = new Map<String, Set<Id>>();
		for (String num : policyNumbers) {
			matchesByNumber.put(num, new Set<Id>());
		}

		for (InsurancePolicy policy : [
			SELECT Id, Name, PolicyName
			FROM InsurancePolicy
			WHERE Name IN :policyNumbers OR PolicyName IN :policyNumbers
		]) {
			if (policy.Name != null && matchesByNumber.containsKey(policy.Name)) {
				matchesByNumber.get(policy.Name).add(policy.Id);
			}
			if (
				policy.PolicyName != null &&
				matchesByNumber.containsKey(policy.PolicyName)
			) {
				matchesByNumber.get(policy.PolicyName).add(policy.Id);
			}
		}

		for (String num : matchesByNumber.keySet()) {
			Set<Id> ids = matchesByNumber.get(num);
			if (ids.size() == 1) {
				result.put(num, new List<Id>(ids)[0]);
			}
		}
		return result;
	}

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Extrae y tipifica todos los campos de un elemento JSON del payload
	 *               en una instancia de ParsedInboundData. Aplica el fallback de
	 *               sourceCancellationDate__c como sourcePaymentDate si este ultimo
	 *               viene ausente y la configuracion lo permite.
	 * @param payload: Mapa con los campos del elemento JSON a parsear.
	 * @return ParsedInboundData con todos los campos del elemento tipificados.
	 */
	private static ParsedInboundData parseInboundData(
		Map<String, Object> payload
	) {
		ParsedInboundData data = new ParsedInboundData();
		data.externalPaymentIdRaw = getString(payload, 'externalPaymentId__c');
		data.sourcePolicyNumber = getString(payload, 'sourcePolicyNumber__c');
		data.sourceAmount = getDecimal(payload, 'sourceAmount__c');
		data.sourceDueDate = getDate(payload, 'sourceDueDate__c');
		data.sourcePaymentDate = getDate(payload, 'sourcePaymentDate__c');
		data.sourceCancellationDate = getDate(payload, 'sourceCancellationDate__c');
		if (
			data.sourcePaymentDate == null &&
			USE_CANCELLATION_DATE_AS_PAYMENT_FALLBACK
		) {
			data.sourcePaymentDate = data.sourceCancellationDate;
		}
		data.sourceReceiptNumber = getString(payload, 'sourceReceiptNumber__c');
		data.sourceCarrierCode = getString(payload, 'sourceCarrierCode__c');
		data.externalPaymentId = resolveExternalPaymentId(data);
		data.rawBankReference = getString(payload, 'rawBankReference__c');
		data.sourceCollectionChannel = getString(
			payload,
			'sourceCollectionChannel__c'
		);
		data.sourcePaymentStatusRaw = getString(
			payload,
			'sourcePaymentStatusRaw__c'
		);
		data.sourcePaymentStatus = getString(payload, 'sourcePaymentStatus__c');
		data.sourceCurrency = getString(payload, 'sourceCurrency__c');
		data.sourceInsuranceCarrier = getString(
			payload,
			'sourceInsuranceCarrier__c'
		);
		data.sourcePolicyBranch = getString(payload, 'sourcePolicyBranch__c');
		data.sourceInstallmentNumber = getString(
			payload,
			'sourceInstallmentNumber__c'
		);
		data.sourceCustomerExternalId = getString(
			payload,
			'sourceCustomerExternalId__c'
		);
		data.sourceSynchronizedAt = getDateTime(payload, 'sourceSynchronizedAt__c');
		data.sourceGrossCommission = getDecimal(
			payload,
			'sourceGrossCommission__c'
		);
		data.sourceVatCommission = getDecimal(payload, 'sourceVatCommission__c');
		data.sourcePolicyStatusRaw = getString(payload, 'sourcePolicyStatusRaw__c');
		data.sourceCustomerName = getString(payload, 'sourceCustomerName__c');
		data.sourceIsCollective = getBoolean(payload, 'sourceIsCollective__c');
		data.sourceRetryCount = getDecimal(payload, 'sourceRetryCount__c');
		data.sourceRejectionReason = getString(payload, 'sourceRejectionReason__c');
		data.sourceCancellationReason = getString(
			payload,
			'sourceCancellationReason__c'
		);
		data.sourcePolicyStartDate = getDate(payload, 'sourcePolicyStartDate__c');
		data.sourcePolicyRenewalDate = getDate(
			payload,
			'sourcePolicyRenewalDate__c'
		);
		data.sourcePolicyIssueDate = getDate(payload, 'sourcePolicyIssueDate__c');
		return data;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Calcula el identificador de deduplicacion del pago inbound.
	 *               La clave unica entre aseguradoras es {sourceCarrierCode__c}_{sourceReceiptNumber__c},
	 *               de modo que dos aseguradoras con el mismo folio no colisionan.
	 *               Fallback documentado (historia HA): si el codigo de aseguradora
	 *               o el folio llegan nulos, se respeta el externalPaymentId__c crudo
	 *               que aun pudiera enviar MuleSoft durante la transicion.
	 * @param data: Datos parseados de la fila con carrier, folio e id crudo.
	 * @return Identificador de deduplicacion, o null si no puede resolverse.
	 */
	private static String resolveExternalPaymentId(ParsedInboundData data) {
		if (
			String.isNotBlank(data.sourceCarrierCode) &&
			String.isNotBlank(data.sourceReceiptNumber)
		) {
			return data.sourceCarrierCode + '_' + data.sourceReceiptNumber;
		}
		return data.externalPaymentIdRaw;
	}

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Genera un hash SHA-256 del cuerpo recibido codificado en
	 *               hexadecimal. Usado para detectar payloads duplicados o
	 *               identificar la version exacta del payload persistido.
	 * @param requestBody: Texto a hashear.
	 * @return Hash SHA-256 en formato hexadecimal.
	 */
	private static String calculatePayloadHash(String requestBody) {
		return EncodingUtil.convertToHex(
			Crypto.generateDigest('SHA-256', Blob.valueOf(requestBody))
		);
	}

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Extrae un campo del payload como String aplicando trim.
	 *               Retorna null si el campo no existe, es null o queda en blanco tras el trim.
	 * @param payload: Mapa con los campos del elemento JSON.
	 * @param fieldName: Nombre del campo a extraer.
	 * @return Valor del campo como String sin espacios extremos, o null.
	 */
	private static String getString(
		Map<String, Object> payload,
		String fieldName
	) {
		Object value = payload.get(fieldName);
		if (value == null) {
			return null;
		}
		String stringValue = String.valueOf(value).trim();
		return String.isBlank(stringValue) ? null : stringValue;
	}

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Extrae un campo del payload como Decimal. Si el valor no puede
	 *               convertirse a Decimal, retorna null sin propagar la excepcion.
	 * @param payload: Mapa con los campos del elemento JSON.
	 * @param fieldName: Nombre del campo a extraer.
	 * @return Valor del campo como Decimal, o null si es invalido o ausente.
	 */
	private static Decimal getDecimal(
		Map<String, Object> payload,
		String fieldName
	) {
		Object value = payload.get(fieldName);
		if (value == null) {
			return null;
		}
		try {
			return Decimal.valueOf(String.valueOf(value));
		} catch (Exception e) {
			return null;
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Extrae un campo del payload como Boolean. Acepta booleanos JSON
	 *               nativos y las representaciones de texto true/false, 1/0 y si/no.
	 *               Retorna null si el campo esta ausente, en blanco o no reconocible.
	 * @param payload: Mapa con los campos del elemento JSON.
	 * @param fieldName: Nombre del campo a extraer.
	 * @return Valor del campo como Boolean, o null si es ausente o no reconocible.
	 */
	private static Boolean getBoolean(
		Map<String, Object> payload,
		String fieldName
	) {
		Object value = payload.get(fieldName);
		if (value == null) {
			return null;
		}
		if (value instanceof Boolean) {
			return (Boolean) value;
		}
		String raw = String.valueOf(value).trim().toLowerCase();
		if (raw == 'true' || raw == '1' || raw == 'si' || raw == 'sí') {
			return true;
		}
		if (raw == 'false' || raw == '0' || raw == 'no') {
			return false;
		}
		return null;
	}

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Extrae un campo del payload como Date delegando el parseo en
	 *               parseDateTime y tomando solo la parte de fecha del resultado.
	 * @param payload: Mapa con los campos del elemento JSON.
	 * @param fieldName: Nombre del campo a extraer.
	 * @return Valor del campo como Date, o null si es invalido o ausente.
	 */
	private static Date getDate(Map<String, Object> payload, String fieldName) {
		DateTime dt = parseDateTime(payload.get(fieldName));
		return dt == null ? null : dt.date();
	}

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Extrae un campo del payload como DateTime delegando el parseo
	 *               completo en parseDateTime.
	 * @param payload: Mapa con los campos del elemento JSON.
	 * @param fieldName: Nombre del campo a extraer.
	 * @return Valor del campo como DateTime, o null si es invalido o ausente.
	 */
	private static DateTime getDateTime(
		Map<String, Object> payload,
		String fieldName
	) {
		return parseDateTime(payload.get(fieldName));
	}

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Parsea un valor crudo del payload a DateTime. Acepta los formatos
	 *               'dd/MM/yyyy' y 'dd/MM/yyyy HH:mm:ss'. Si el valor es null, esta
	 *               en blanco o no puede parsearse, retorna null sin propagar la excepcion.
	 *               Los campos Date invocan .date() sobre el resultado de este metodo.
	 * @param value: Valor crudo del campo tal como viene del payload JSON.
	 * @return DateTime parseado, o null si el formato es invalido o el valor es ausente.
	 */
	private static DateTime parseDateTime(Object value) {
		if (value == null) {
			return null;
		}
		String raw = String.valueOf(value).trim();
		if (String.isBlank(raw)) {
			return null;
		}
		try {
			List<String> parts = raw.split(' ');
			List<String> dateParts = parts[0].split('/');
			if (dateParts.size() != 3) {
				return null;
			}
			Integer day = Integer.valueOf(dateParts[0]);
			Integer month = Integer.valueOf(dateParts[1]);
			Integer year = Integer.valueOf(dateParts[2]);
			if (parts.size() == 1) {
				return DateTime.newInstance(year, month, day, 0, 0, 0);
			}
			List<String> timeParts = parts[1].split(':');
			if (timeParts.size() != 3) {
				return null;
			}
			return DateTime.newInstance(
				year,
				month,
				day,
				Integer.valueOf(timeParts[0]),
				Integer.valueOf(timeParts[1]),
				Integer.valueOf(timeParts[2])
			);
		} catch (Exception e) {
			return null;
		}
	}

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Convierte el motivo de rechazo tecnico del picklist en un mensaje
	 *               descriptivo en espanol para incluir en la respuesta al integrador.
	 * @param validationReason: Valor del picklist de motivo de rechazo.
	 * @return Mensaje descriptivo del motivo de rechazo para el integrador.
	 */
	private static String getValidationMessage(String validationReason) {
		if (validationReason == REJECTION_REASON_INCOMPLETE_PAYLOAD) {
			return 'Faltan campos requeridos.';
		}

		if (validationReason == REJECTION_REASON_INVALID_AMOUNT) {
			return 'El campo sourceAmount debe ser mayor que cero.';
		}

		return 'La solicitud es invalida.';
	}

	private class ParsedInboundData {
		String externalPaymentId;
		String externalPaymentIdRaw;
		String sourcePolicyNumber;
		Decimal sourceAmount;
		Date sourcePaymentDate;
		Date sourceDueDate;
		Date sourceCancellationDate;
		String rawBankReference;
		String sourceReceiptNumber;
		String sourceCarrierCode;
		String sourceCollectionChannel;
		String sourcePaymentStatusRaw;
		String sourcePaymentStatus;
		String sourceCurrency;
		String sourceInsuranceCarrier;
		String sourcePolicyBranch;
		String sourceInstallmentNumber;
		String sourceCustomerExternalId;
		DateTime sourceSynchronizedAt;
		Decimal sourceGrossCommission;
		Decimal sourceVatCommission;
		String sourcePolicyStatusRaw;
		String sourceCustomerName;
		Boolean sourceIsCollective;
		Decimal sourceRetryCount;
		String sourceRejectionReason;
		String sourceCancellationReason;
		Date sourcePolicyStartDate;
		Date sourcePolicyRenewalDate;
		Date sourcePolicyIssueDate;
	}

	private class RowContext {
		Boolean skip = false;
		String skipMessage;
		ParsedInboundData data;
		String itemJson;
		String payloadHash;
		String validationReason;
		String outcome;
		String existingStatus;
		InboundInsurancePayment__c record;
	}

	public class EndpointResult {
		public Integer statusCode;
		public ResponseBody body;

		public EndpointResult(Integer statusCode, ResponseBody body) {
			this.statusCode = statusCode;
			this.body = body;
		}
	}

	public class ResponseBody {
		public Boolean success;
		public String code;
		public String message;
		public String externalPaymentId;
		public Id inboundPaymentId;
		public Integer totalRecords;
		public Integer receivedCount;
		public Integer updatedCount;
		public Integer rejectedCount;
		public List<ItemResult> results;

		public ResponseBody(
			Boolean success,
			String code,
			String message,
			String externalPaymentId,
			Id inboundPaymentId
		) {
			this(
				success,
				code,
				message,
				externalPaymentId,
				inboundPaymentId,
				0,
				0,
				0,
				0,
				new List<ItemResult>()
			);
		}

		public ResponseBody(
			Boolean success,
			String code,
			String message,
			String externalPaymentId,
			Id inboundPaymentId,
			Integer totalRecords,
			Integer receivedCount,
			Integer updatedCount,
			Integer rejectedCount,
			List<ItemResult> results
		) {
			this.success = success;
			this.code = code;
			this.message = message;
			this.externalPaymentId = externalPaymentId;
			this.inboundPaymentId = inboundPaymentId;
			this.totalRecords = totalRecords;
			this.receivedCount = receivedCount;
			this.updatedCount = updatedCount;
			this.rejectedCount = rejectedCount;
			this.results = results;
		}
	}

	public class ItemResult {
		public Boolean success;
		public String code;
		public String message;
		public String externalPaymentId;
		public Id inboundPaymentId;

		public ItemResult(
			Boolean success,
			String code,
			String message,
			String externalPaymentId,
			Id inboundPaymentId
		) {
			this.success = success;
			this.code = code;
			this.message = message;
			this.externalPaymentId = externalPaymentId;
			this.inboundPaymentId = inboundPaymentId;
		}
	}
}
