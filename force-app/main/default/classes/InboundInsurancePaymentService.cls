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

	// Situacion del recibo segun la aseguradora. El motor obedece este dato en vez
	// de deducir que hay un cobro por la sola presencia de una fecha.
	private static final String CARRIER_PAID = 'Pagado';
	private static final String CARRIER_PENDING = 'Pendiente';
	private static final String CARRIER_OVERDUE = 'Vencido';
	private static final String CARRIER_CANCELLED = 'Cancelado';
	private static final String CARRIER_UNKNOWN = 'Desconocido';

	private static final String STATUS_MANUAL_REVIEW = 'Revision Manual';
	private static final String STATUS_NOT_RECONCILABLE = 'No Conciliable';

	// La integracion sincroniza recibos, no novedades: un mismo recibo puede
	// llegar muchas veces. Solo se reprocesa si cambio algo que afecta al cobro.
	private static final String RECEIPT_STATUS_RECOGNIZED = 'Reconocido';
	private static final String RECEIPT_STATUS_REVERSED = 'Reversado';
	private static final String REVERSAL_REASON_CARRIER_CORRECTION = 'Correccion de la aseguradora';

	// Vocabulario acordado con la integracion. Deliberadamente estricto: normalizar los
	// nombres de cada aseguradora es responsabilidad de la integracion, no de Salesforce.
	// Cualquier otro valor cae en Desconocido, queda para revision manual y se registra,
	// que es como nos enteramos de que hay que corregirlo aguas arriba.
	private static final Map<String, String> CARRIER_STATUS_BY_SOURCE = new Map<String, String>{
		'PAGADO' => CARRIER_PAID,
		'PENDIENTE' => CARRIER_PENDING,
		'VENCIDO' => CARRIER_OVERDUE,
		'CANCELADO' => CARRIER_CANCELLED
	};

	private static final String OUTCOME_SKIPPED = 'SKIPPED';
	private static final String OUTCOME_REJECTED = 'REJECTED';
	private static final String OUTCOME_RECEIVED = 'RECEIVED';
	private static final String OUTCOME_UPDATED = 'UPDATED';
	private static final String OUTCOME_FAILED = 'FAILED';
	private static final String CODE_WRITE_FAILED = 'WRITE_FAILED';

	// Los rechazados sin folio se agrupan en el lote por la huella de su contenido. El
	// prefijo impide que una huella coincida por azar con un folio.
	private static final String FINGERPRINT_KEY_PREFIX = 'huella:';

	// Provoca un fallo despues de escribir, para probar que la peticion se deshace completa.
	@TestVisible
	private static Boolean forceFailureAfterWritesForTest = false;

	private class InboundProcessingException extends Exception {
	}

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
		Set<String> fingerprints = new Set<String>();
		Set<String> policyNumbers = new Set<String>();
		for (RowContext ctx : contexts) {
			if (ctx.skip) {
				continue;
			}
			if (String.isNotBlank(ctx.data.externalPaymentId)) {
				externalIds.add(ctx.data.externalPaymentId);
			} else {
				fingerprints.add(ctx.data.contentFingerprint);
			}
			if (String.isNotBlank(ctx.data.sourcePolicyNumber)) {
				policyNumbers.add(ctx.data.sourcePolicyNumber);
			}
		}

		Map<String, InboundInsurancePayment__c> existingByExternalId = findExistingInbounds(
			externalIds
		);
		Map<String, InboundInsurancePayment__c> rejectedByFingerprint = findRejectedWithoutId(
			fingerprints
		);
		Map<String, Id> candidatePolicyByNumber = findCandidatePolicies(
			policyNumbers
		);

		// Cada lista guarda la fila DUENA del registro que se escribe, para poder devolverle
		// el resultado de su escritura. Las filas repetidas del mismo lote comparten dueno.
		List<RowContext> toInsert = new List<RowContext>();
		List<RowContext> toUpdate = new List<RowContext>();
		Map<String, RowContext> firstByKey = new Map<String, RowContext>();

		for (RowContext ctx : contexts) {
			if (ctx.skip) {
				ctx.outcome = OUTCOME_SKIPPED;
				continue;
			}

			Id candidatePolicyId = candidatePolicyByNumber.get(
				ctx.data.sourcePolicyNumber
			);

			if (ctx.validationReason != null) {
				classifyRejected(
					ctx,
					candidatePolicyId,
					existingByExternalId,
					rejectedByFingerprint,
					firstByKey,
					toInsert,
					toUpdate
				);
				continue;
			}

			RowContext first = firstByKey.get(ctx.data.externalPaymentId);
			if (first != null && first.record != null) {
				// El mismo recibo vino dos veces en el lote: manda la ultima fila, sobre el
				// mismo registro y con la misma decision que tomaria si llegara sola.
				ctx.owner = first;
				ctx.record = first.record;
				ctx.outcome = OUTCOME_UPDATED;
				if (first.existing != null) {
					applyToExisting(first, ctx.data, ctx, candidatePolicyId);
				} else {
					populateInboundData(
						first.record,
						ctx.data,
						ctx.itemJson,
						ctx.payloadHash,
						resolveInboundStatus(
							ctx.data.carrierReceiptStatus,
							ctx.data.sourcePaymentDate != null,
							null
						),
						null,
						candidatePolicyId,
						true
					);
				}
				continue;
			}

			InboundInsurancePayment__c existing = existingByExternalId.get(
				ctx.data.externalPaymentId
			);
			ctx.owner = ctx;
			firstByKey.put(ctx.data.externalPaymentId, ctx);
			if (existing != null) {
				ctx.existing = existing;
				ctx.record = new InboundInsurancePayment__c(Id = existing.Id);
				applyToExisting(ctx, ctx.data, ctx, candidatePolicyId);
				toUpdate.add(ctx);
				ctx.outcome = OUTCOME_UPDATED;
				continue;
			}

			ctx.record = buildInboundRecord(
				ctx.data,
				ctx.itemJson,
				ctx.payloadHash,
				resolveInboundStatus(
					ctx.data.carrierReceiptStatus,
					ctx.data.sourcePaymentDate != null,
					null
				),
				null,
				candidatePolicyId
			);
			toInsert.add(ctx);
			ctx.outcome = OUTCOME_RECEIVED;
		}

		logResentWithChanges(contexts);

		// ORDEN DELIBERADO. Primero se guardan los pagos y despues se anulan los recibos, y
		// solo los de pagos que se guardaron: si un pago no se pudo guardar, su recibo sigue
		// vigente y no queda nada a medias. Cada pago se guarda por separado, de modo que uno
		// defectuoso se informa en su resultado sin tumbar al resto del envio.
		writeRecords(toInsert, true);
		writeRecords(toUpdate, false);
		propagateWriteOutcomes(contexts);

		Set<Id> stillLive = annulReceiptsOfChangedPayments(contexts);

		if (Test.isRunningTest() && forceFailureAfterWritesForTest) {
			throw new InboundProcessingException('Forced failure after writes');
		}

		// Por Id y desde cualquier fila aceptada, no solo desde la duena: si en el lote llega
		// primero un rechazado y despues su version valida, el registro lo escribio la fila
		// rechazada pero lleva los datos de la valida y tiene que seguir su curso.
		Map<Id, InboundInsurancePayment__c> written = new Map<Id, InboundInsurancePayment__c>();
		for (RowContext ctx : contexts) {
			if (
				(ctx.outcome == OUTCOME_RECEIVED ||
				ctx.outcome == OUTCOME_UPDATED) &&
				ctx.record != null &&
				ctx.record.Id != null &&
				!stillLive.contains(ctx.record.Id)
			) {
				written.put(ctx.record.Id, ctx.record);
			}
		}

		logCarrierStatusOutcomes(contexts);
		enqueueNormalization(written.values());
		enqueueScheduledChargeMatching(written.values());
		AppLogger.flush();

		Integer received = 0;
		Integer updated = 0;
		Integer rejected = 0;
		List<ItemResult> results = new List<ItemResult>();
		for (RowContext ctx : contexts) {
			if (ctx.outcome == OUTCOME_RECEIVED) {
				received++;
			} else if (ctx.outcome == OUTCOME_UPDATED) {
				updated++;
			} else {
				rejected++;
			}
			results.add(toItemResult(ctx));
		}

		return buildBatchResult(rows.size(), received, updated, rejected, results);
	}

	/**
	 * @creation date: 14/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Decide que hacer con una fila que no supera la validacion. Un rechazado
	 *               que vuelve a llegar actualiza su propio registro en vez de crear otro: el
	 *               folio es unico y el segundo alta fallaria. Si no trae folio se reconoce
	 *               por la huella de su contenido. Si lo que ya teniamos es un pago VALIDO, el
	 *               reenvio invalido no se aplica: pisaria datos buenos con datos que no se
	 *               pueden procesar.
	 * @param ctx: Fila rechazada.
	 * @param candidatePolicyId: Poliza candidata resuelta para la fila.
	 * @param existingByExternalId: Pagos existentes por folio.
	 * @param rejectedByFingerprint: Rechazados sin folio existentes por huella.
	 * @param firstByKey: Primera fila del lote por folio o huella.
	 * @param toInsert: Filas duenas de un registro nuevo.
	 * @param toUpdate: Filas duenas de un registro existente.
	 * @return
	 */
	private static void classifyRejected(
		RowContext ctx,
		Id candidatePolicyId,
		Map<String, InboundInsurancePayment__c> existingByExternalId,
		Map<String, InboundInsurancePayment__c> rejectedByFingerprint,
		Map<String, RowContext> firstByKey,
		List<RowContext> toInsert,
		List<RowContext> toUpdate
	) {
		ctx.outcome = OUTCOME_REJECTED;
		Boolean hasId = String.isNotBlank(ctx.data.externalPaymentId);
		String key = hasId
			? ctx.data.externalPaymentId
			: FINGERPRINT_KEY_PREFIX + ctx.data.contentFingerprint;

		RowContext first = firstByKey.get(key);
		if (first != null) {
			// El lote ya trae un registro para este recibo: no se escribe dos veces.
			ctx.record = first.record;
			return;
		}

		InboundInsurancePayment__c existing = hasId
			? existingByExternalId.get(key)
			: rejectedByFingerprint.get(ctx.data.contentFingerprint);

		if (
			existing != null && !STATUS_REJECTED.equals(existing.inboundStatus__c)
		) {
			ctx.record = new InboundInsurancePayment__c(Id = existing.Id);
			CobranzaLog.warn(
					CobranzaLog.STAGE_RECEPCION,
					CobranzaLog.EVENT_INVALID_RESEND_IGNORED,
					'Llego un reenvio de este pago que no supera la validacion (' +
						ctx.validationReason +
						'). No se aplico: el pago conserva los datos que ya tenia.'
				)
				.onInbound(existing.Id)
				.appendDetails('JSON recibido: ' + ctx.itemJson);
			return;
		}

		ctx.owner = ctx;
		firstByKey.put(key, ctx);
		if (existing == null) {
			ctx.record = buildInboundRecord(
				ctx.data,
				ctx.itemJson,
				ctx.payloadHash,
				STATUS_REJECTED,
				ctx.validationReason,
				candidatePolicyId
			);
			toInsert.add(ctx);
			return;
		}

		ctx.existing = existing;
		ctx.record = new InboundInsurancePayment__c(Id = existing.Id);
		populateInboundData(
			ctx.record,
			ctx.data,
			ctx.itemJson,
			ctx.payloadHash,
			STATUS_REJECTED,
			ctx.validationReason,
			candidatePolicyId,
			true
		);
		stampResend(ctx.record, existing, ctx);
		toUpdate.add(ctx);
	}

	/**
	 * @creation date: 14/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Aplica un reenvio sobre el pago que ya teniamos. Solo un cambio material
	 *               devuelve el pago al circuito; sin el, el pago conserva su estado y su
	 *               etapa, y el reenvio solo completa datos y se cuenta. Un rechazado se
	 *               vuelve a evaluar siempre: nunca entro al circuito, asi que no hay nada que
	 *               deshacer y los datos nuevos pueden ser justo los que le faltaban.
	 * @param owner: Fila duena del registro existente.
	 * @param data: Datos del reenvio.
	 * @param ctx: Fila que trae el reenvio (la duena u otra repetida del lote).
	 * @param candidatePolicyId: Poliza candidata resuelta para la fila.
	 * @return
	 */
	private static void applyToExisting(
		RowContext owner,
		ParsedInboundData data,
		RowContext ctx,
		Id candidatePolicyId
	) {
		InboundInsurancePayment__c existing = owner.existing;
		owner.changes = describeMaterialChanges(existing, data);
		owner.materialChange = !owner.changes.isEmpty();
		Boolean reevaluate =
			owner.materialChange || STATUS_REJECTED.equals(existing.inboundStatus__c);

		String resolvedStatus = existing.inboundStatus__c;
		if (reevaluate) {
			resolvedStatus = resolveInboundStatus(
				data.carrierReceiptStatus,
				data.sourcePaymentDate != null,
				existing.inboundStatus__c
			);
		} else {
			// Un reenvio que omite una fecha no borra la que ya teniamos: omitirla no es
			// corregirla, y el pago seguiria vivo con un dato menos.
			if (data.sourcePaymentDate == null) {
				data.sourcePaymentDate = existing.sourcePaymentDate__c;
			}
			if (data.sourceDueDate == null) {
				data.sourceDueDate = existing.sourceDueDate__c;
			}
		}

		populateInboundData(
			owner.record,
			data,
			ctx.itemJson,
			ctx.payloadHash,
			resolvedStatus,
			null,
			candidatePolicyId,
			reevaluate
		);
		stampResend(owner.record, existing, owner);
	}

	/**
	 * @creation date: 14/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Guarda los registros sin que el fallo de uno arrastre a los demas, y deja
	 *               en la fila duena el motivo de cada fallo. Cada fallo queda en el registro
	 *               de la aplicacion con el JSON recibido, que es lo que hace falta para
	 *               reenviarlo una vez corregida la causa.
	 * @param owners: Filas duenas de los registros a guardar.
	 * @param isInsert: true para altas, false para actualizaciones.
	 * @return
	 */
	private static void writeRecords(List<RowContext> owners, Boolean isInsert) {
		if (owners.isEmpty()) {
			return;
		}
		List<InboundInsurancePayment__c> records = new List<InboundInsurancePayment__c>();
		for (RowContext owner : owners) {
			records.add(owner.record);
		}
		List<Database.SaveResult> results = isInsert
			? Database.insert(records, false)
			: Database.update(records, false);

		for (Integer i = 0; i < results.size(); i++) {
			if (results[i].isSuccess()) {
				continue;
			}
			RowContext owner = owners[i];
			owner.writeError = describeErrors(results[i].getErrors());
			CobranzaLog.error(
					CobranzaLog.STAGE_RECEPCION,
					CobranzaLog.EVENT_INBOUND_WRITE_FAILED,
					'No se pudo guardar el pago ' +
						(String.isBlank(owner.data.externalPaymentId)
							? '(sin folio)'
							: owner.data.externalPaymentId) +
						'. El resto del envio se proceso normalmente. Motivo: ' +
						owner.writeError
				)
				.onInbound(isInsert ? null : owner.record.Id)
				.appendDetails('JSON recibido: ' + owner.itemJson);
		}
	}

	/**
	 * @creation date: 14/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Traslada el fallo de escritura de cada registro a todas las filas que lo
	 *               comparten, para que la respuesta informe el error en cada una.
	 * @param contexts: Filas del lote ya escritas.
	 * @return
	 */
	private static void propagateWriteOutcomes(List<RowContext> contexts) {
		for (RowContext ctx : contexts) {
			if (ctx.owner == null || ctx.owner.writeError == null) {
				continue;
			}
			ctx.writeError = ctx.owner.writeError;
			ctx.outcome = OUTCOME_FAILED;
		}
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
			ctx.data.contentFingerprint = calculateContentFingerprint(ctx.data);
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
		Id recordId = ctx.record == null ? null : ctx.record.Id;
		if (ctx.outcome == OUTCOME_FAILED) {
			return new ItemResult(
				false,
				CODE_WRITE_FAILED,
				'No se pudo guardar el pago: ' + ctx.writeError,
				ctx.data.externalPaymentId,
				recordId
			);
		}
		if (ctx.outcome == OUTCOME_REJECTED) {
			return new ItemResult(
				false,
				CODE_REJECTED,
				getValidationMessage(ctx.validationReason),
				ctx.data.externalPaymentId,
				recordId
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
		String payloadHash = calculatePayloadHash(requestBody);
		// El mismo cuerpo malformado puede volver a llegar. Se reconoce por su huella en vez
		// de intentar otra alta, que chocaria con la huella unica y tumbaria la respuesta.
		List<InboundInsurancePayment__c> previous = [
			SELECT Id, externalPaymentId__c
			FROM InboundInsurancePayment__c
			WHERE sourcePayloadHash__c = :payloadHash
			LIMIT 1
		];
		if (!previous.isEmpty()) {
			return previous[0];
		}
		InboundInsurancePayment__c rec = buildInboundRecord(
			new ParsedInboundData(),
			requestBody,
			payloadHash,
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
	 *               e importe. La fecha de pago NO es requerida: un recibo sin
	 *               fecha de pago se acepta y se almacena, y se rutea aparte como
	 *               'Pendiente de Pago'.
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
	 * @creation date: 30/08/2026
	 * @author: Javier Torres - Volestra
	 * @description: Deja constancia de lo que el motor decide NO hacer por el estatus que
	 *               reporta la aseguradora. Sin esto, un recibo que no avanza es
	 *               indistinguible de uno que se quedo trabado: el registro dice cual es y
	 *               por que. Se ejecuta despues del DML porque los registros nuevos no
	 *               tienen Id hasta entonces.
	 * @param contexts: Filas ya procesadas y persistidas del lote.
	 * @return
	 */
	/**
	 * @creation date: 31/08/2026
	 * @author: Javier Torres - Volestra
	 * @description: Compara el reenvio contra lo que ya teniamos y devuelve la lista de cambios
	 *               que afectan al cobro. Solo estos justifican deshacer y rehacer;
	 *               un nombre de cliente corregido o una comision distinta se guardan sin tocar
	 *               nada mas.
	 *               NO se compara el mensaje completo ni su huella, aunque seria mas corto: los
	 *               pagos de la carga inicial no conservan el mensaje original de la integracion,
	 *               de modo que esa comparacion los marcaria a todos como cambiados y anularia
	 *               un cobro valido por cada pago reenviado.
	 *               Una correccion es un dato informado que pasa a OTRO valor informado:
	 *               - El importe se compara como numero: 2979.40 y 2979.4 son el mismo.
	 *               - Un dato vacio que pasa a tener valor, o uno que el reenvio omite, no es
	 *                 una correccion: la integracion completa o recorta campos segun el origen.
	 *               - El numero de cuota y la moneda no se comparan: cambian de formato entre
	 *                 origenes (1 frente a 01/02) sin que cambie el cobro.
	 *               - El estatus se compara por su valor efectivo: un pago sin estatus con fecha
	 *                 de pago ya se daba por pagado, asi que recibir Pagado no cambia nada.
	 * @param existing: Registro tal como estaba antes del reenvio.
	 * @param incoming: Datos que trae el reenvio.
	 * @return Descripcion de cada cambio material; vacia si no cambio nada relevante.
	 */
	private static List<String> describeMaterialChanges(
		InboundInsurancePayment__c existing,
		ParsedInboundData incoming
	) {
		List<String> changes = new List<String>();
		if (!sameAmount(existing.sourceAmount__c, incoming.sourceAmount)) {
			changes.add(
				describeChange(
					'importe',
					existing.sourceAmount__c,
					incoming.sourceAmount
				)
			);
		}
		addChangeIfBothInformed(
			changes,
			'fecha de pago',
			existing.sourcePaymentDate__c,
			incoming.sourcePaymentDate
		);
		addChangeIfBothInformed(
			changes,
			'numero de poliza',
			normalizeText(existing.sourcePolicyNumber__c),
			normalizeText(incoming.sourcePolicyNumber)
		);
		addChangeIfBothInformed(
			changes,
			'fecha de vencimiento',
			existing.sourceDueDate__c,
			incoming.sourceDueDate
		);
		String statusBefore = effectiveCarrierStatus(existing);
		if (!statusBefore.equals(incoming.carrierReceiptStatus)) {
			changes.add(
				describeChange(
					'estatus del recibo',
					statusBefore,
					incoming.carrierReceiptStatus
				)
			);
		}
		return changes;
	}

	/**
	 * @creation date: 14/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Compara dos importes como numeros, sin que importe cuantos decimales traiga
	 *               cada uno.
	 * @param before: Importe guardado.
	 * @param after: Importe recibido.
	 * @return true si son el mismo importe.
	 */
	private static Boolean sameAmount(Decimal before, Decimal after) {
		if (before == null || after == null) {
			return before == null && after == null;
		}
		return !(before < after) && !(before > after);
	}

	/**
	 * @creation date: 14/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Agrega una linea a la bitacora solo si los dos valores estan informados y
	 *               son distintos. Completar un dato vacio, u omitirlo, no es corregirlo.
	 * @param changes: Lista acumuladora.
	 * @param label: Nombre legible del campo.
	 * @param before: Valor anterior.
	 * @param after: Valor nuevo.
	 * @return
	 */
	private static void addChangeIfBothInformed(
		List<String> changes,
		String label,
		Object before,
		Object after
	) {
		if (before == null || after == null || before.equals(after)) {
			return;
		}
		changes.add(describeChange(label, before, after));
	}

	/**
	 * @creation date: 14/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Texto de una linea de la bitacora de reenvios.
	 * @param label: Nombre legible del campo.
	 * @param before: Valor anterior.
	 * @param after: Valor nuevo.
	 * @return Linea con el valor anterior y el nuevo.
	 */
	private static String describeChange(
		String label,
		Object before,
		Object after
	) {
		return label +
			': ' +
			(before == null ? '(vacio)' : String.valueOf(before)) +
			' -> ' +
			(after == null ? '(vacio)' : String.valueOf(after));
	}

	/**
	 * @creation date: 14/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Estatus del recibo tal como el motor lo entendia para el pago guardado. Los
	 *               pagos anteriores al estatus de la aseguradora no lo tienen informado, y el
	 *               motor lo deducia de la fecha de pago; se deduce igual aqui para no tomar
	 *               por cambio lo que solo es completar el dato.
	 * @param existing: Pago guardado.
	 * @return Estatus efectivo del pago guardado.
	 */
	private static String effectiveCarrierStatus(
		InboundInsurancePayment__c existing
	) {
		if (String.isNotBlank(existing.carrierReceiptStatus__c)) {
			return existing.carrierReceiptStatus__c;
		}
		return existing.sourcePaymentDate__c != null
			? CARRIER_PAID
			: CARRIER_PENDING;
	}

	/**
	 * @creation date: 14/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Normaliza un texto para compararlo: sin espacios extremos y en mayusculas.
	 * @param value: Texto a normalizar.
	 * @return Texto normalizado, o null si esta vacio.
	 */
	private static String normalizeText(String value) {
		return String.isBlank(value) ? null : value.trim().toUpperCase();
	}

	/**
	 * @creation date: 31/08/2026
	 * @author: Javier Torres - Volestra
	 * @description: Sella el rastro del reenvio: cuantos van, cuando fue el ultimo y, si hubo
	 *               cambios materiales, que cambio exactamente. La bitacora se agrega al final y
	 *               nunca se sobrescribe, porque el pago se reescribe entero en cada recepcion y
	 *               sin ella no quedaria rastro de lo anterior.
	 * @param rec: Registro que se va a actualizar.
	 * @param existing: Valores previos.
	 * @param ctx: Contexto de la fila, con los cambios detectados.
	 * @return
	 */
	private static void stampResend(
		InboundInsurancePayment__c rec,
		InboundInsurancePayment__c existing,
		RowContext ctx
	) {
		Decimal previous = existing.resendCount__c == null
			? 0
			: existing.resendCount__c;
		rec.resendCount__c = previous + 1;
		rec.lastResendAt__c = System.now();

		if (!ctx.materialChange) {
			// Un reenvio identico no ensucia la bitacora: la integracion repite recibos de
			// forma rutinaria y anotarlos todos la volveria ilegible.
			rec.resendChangeLog__c = existing.resendChangeLog__c;
			return;
		}

		String entry =
			'[' +
			System.now().format('yyyy-MM-dd HH:mm:ss') +
			'] ' +
			String.join(ctx.changes, '; ');
		rec.resendChangeLog__c = String.isBlank(existing.resendChangeLog__c)
			? entry
			: existing.resendChangeLog__c + '\n' + entry;
	}

	/**
	 * @creation date: 31/08/2026
	 * @author: Javier Torres - Volestra
	 * @description: Anula el cobro vigente de los pagos que llegaron con un cambio material.
	 *               No borra nada: cambia el estado del recibo, y esa transicion
	 *               dispara la cascada ya construida, que reabre la cuota, recalcula el plan y
	 *               la poliza, devuelve la conciliacion a la bandeja y señala la oportunidad.
	 *               Reusarla es lo que garantiza que una correccion de la aseguradora y una
	 *               anulacion hecha a mano dejen el sistema exactamente igual.
	 *               Solo se anulan los recibos de pagos que se guardaron: si el guardado fallo,
	 *               el cobro anterior sigue siendo el valido. Mientras dura la anulacion, la
	 *               cascada sabe que esos pagos se estan reprocesando y no los manda a revision
	 *               manual, que es lo que antes obligaba a anular antes de guardar.
	 *               Si un recibo no se puede anular, su pago no se reprocesa: queda en revision
	 *               manual, porque reprocesarlo con el cobro anterior vigente podria cobrar dos
	 *               veces la misma cuota.
	 * @param contexts: Filas del lote ya escritas.
	 * @return Pagos cuyo cobro anterior sigue vigente y que por eso no deben reprocesarse.
	 */
	private static Set<Id> annulReceiptsOfChangedPayments(
		List<RowContext> contexts
	) {
		Set<Id> stillLive = new Set<Id>();
		Set<Id> changedInboundIds = new Set<Id>();
		for (RowContext ctx : contexts) {
			if (
				ctx.owner == ctx &&
				ctx.materialChange &&
				ctx.writeError == null &&
				ctx.record != null &&
				ctx.record.Id != null
			) {
				changedInboundIds.add(ctx.record.Id);
			}
		}
		if (changedInboundIds.isEmpty()) {
			return stillLive;
		}

		List<PolicyPaymentReceipt__c> toReverse = new List<PolicyPaymentReceipt__c>();
		List<Id> inboundOfReceipt = new List<Id>();
		for (PolicyPaymentReceipt__c receipt : [
			SELECT Id, sourceInboundPayment__c
			FROM PolicyPaymentReceipt__c
			WHERE
				sourceInboundPayment__c IN :changedInboundIds
				AND receiptStatus__c = :RECEIPT_STATUS_RECOGNIZED
		]) {
			toReverse.add(
				new PolicyPaymentReceipt__c(
					Id = receipt.Id,
					receiptStatus__c = RECEIPT_STATUS_REVERSED,
					reversalReason__c = REVERSAL_REASON_CARRIER_CORRECTION,
					reversalNotes__c = 'La aseguradora reenvio el recibo con datos distintos a los que se conciliaron.'
				)
			);
			inboundOfReceipt.add(receipt.sourceInboundPayment__c);
		}
		if (toReverse.isEmpty()) {
			return stillLive;
		}

		List<Database.SaveResult> results;
		PolicyPaymentReceiptReversalService.markInboundsInReprocess(
			changedInboundIds
		);
		try {
			results = Database.update(toReverse, false);
		} finally {
			PolicyPaymentReceiptReversalService.clearInboundsInReprocess();
		}

		Map<Id, InboundInsurancePayment__c> toHold = new Map<Id, InboundInsurancePayment__c>();
		for (Integer i = 0; i < results.size(); i++) {
			if (results[i].isSuccess()) {
				continue;
			}
			Id inboundId = inboundOfReceipt[i];
			stillLive.add(inboundId);
			toHold.put(
				inboundId,
				new InboundInsurancePayment__c(
					Id = inboundId,
					inboundStatus__c = STATUS_MANUAL_REVIEW,
					manualReviewRequired__c = true
				)
			);
			CobranzaLog.error(
					CobranzaLog.STAGE_RECEPCION,
					CobranzaLog.EVENT_RESEND_REVERSAL_FAILED,
					'No se pudo anular el cobro anterior de un pago que llego corregido. El ' +
						'pago queda en revision manual y no se reprocesa mientras ese cobro siga ' +
						'vigente. Motivo: ' +
						describeErrors(results[i].getErrors())
				)
				.onRecord(toReverse[i].Id)
				.onInbound(inboundId);
		}
		if (!toHold.isEmpty()) {
			Database.update(toHold.values(), false);
		}
		return stillLive;
	}

	/**
	 * @creation date: 31/08/2026
	 * @author: Javier Torres - Volestra
	 * @description: Resume los errores que devuelve la plataforma. Un registro que dice "no se
	 *               pudo" sin decir por que obliga a reproducir el caso para investigarlo, que
	 *               es justo lo que el registro deberia evitar.
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

	private static void logCarrierStatusOutcomes(List<RowContext> contexts) {
		for (RowContext ctx : contexts) {
			if (
				ctx.skip ||
				ctx.validationReason != null ||
				ctx.record == null ||
				ctx.record.Id == null
			) {
				continue;
			}

			String carrierStatus = ctx.data.carrierReceiptStatus;

			if (CARRIER_UNKNOWN.equals(carrierStatus)) {
				CobranzaLog.warn(
						CobranzaLog.STAGE_RECEPCION,
						CobranzaLog.EVENT_CARRIER_STATUS_UNKNOWN,
						'La aseguradora ' +
							ctx.data.sourceInsuranceCarrier +
							' informo el estatus "' +
							ctx.data.sourcePaymentStatus +
							'", que no corresponde a ninguno de los cuatro acordados. El pago queda ' +
							'para revision manual; hay que corregir la equivalencia en la integracion.'
					)
					.onInbound(ctx.record.Id);
				continue;
			}

			if (String.isBlank(ctx.data.sourcePaymentStatus)) {
				CobranzaLog.info(
						CobranzaLog.STAGE_RECEPCION,
						CobranzaLog.EVENT_CARRIER_STATUS_MISSING,
						'El recibo llego sin estatus de la aseguradora. Se dedujo ' +
							carrierStatus +
							' por la presencia o ausencia de fecha de pago.'
					)
					.onInbound(ctx.record.Id);
			}

			if (CARRIER_PAID.equals(carrierStatus)) {
				if (ctx.data.sourcePaymentDate == null) {
					CobranzaLog.warn(
							CobranzaLog.STAGE_RECEPCION,
							CobranzaLog.EVENT_PAID_WITHOUT_PAYMENT_DATE,
							'La aseguradora reporta el recibo como pagado pero no informa la fecha ' +
								'del pago. Es un dato contradictorio: el pago no se concilia y queda para ' +
								'revision manual.'
						)
						.onInbound(ctx.record.Id);
				}
				continue;
			}

			CobranzaLog.info(
					CobranzaLog.STAGE_RECEPCION,
					CobranzaLog.EVENT_CARRIER_STATUS_NOT_PAID,
					'El recibo no se concilia porque la aseguradora lo reporta como ' +
						carrierStatus +
						'. Volvera a evaluarse si mas adelante lo reporta pagado.'
				)
				.onInbound(ctx.record.Id);
		}
	}

	/**
	 * @creation date: 30/08/2026
	 * @author: Javier Torres - Volestra
	 * @description: Traduce el estatus normalizado que envia la integracion a uno de los
	 *               cinco valores que el motor entiende. El vocabulario es
	 *               estricto a proposito: normalizar los nombres propios de cada
	 *               aseguradora es trabajo de la integracion, y cualquier valor fuera del
	 *               acuerdo cae en Desconocido para que se corrija alli en vez de
	 *               absorberse en silencio. Si el estatus no viene informado se deduce por
	 *               la fecha de pago, para no romper a las aseguradoras que todavia no lo
	 *               envian ni alterar la cartera ya cargada.
	 * @param data: Datos parseados de la fila del payload.
	 * @return Uno de: Pagado, Pendiente, Vencido, Cancelado o Desconocido.
	 */
	private static String resolveCarrierReceiptStatus(ParsedInboundData data) {
		if (String.isBlank(data.sourcePaymentStatus)) {
			// La integracion no informo estatus para este recibo. Se deduce por la fecha de
			// pago, que es lo que el motor hacia siempre, para no romper a las aseguradoras
			// que todavia no lo envian ni alterar la cartera ya cargada. La deduccion queda
			// registrada. Notar que aqui ya NO interviene la fecha de cancelacion, asi que un
			// recibo cancelado sin fecha de pago cae en Pendiente y no se concilia.
			return data.sourcePaymentDate != null ? CARRIER_PAID : CARRIER_PENDING;
		}
		String normalized = data.sourcePaymentStatus.trim().toUpperCase();
		String mapped = CARRIER_STATUS_BY_SOURCE.get(normalized);
		return mapped == null ? CARRIER_UNKNOWN : mapped;
	}

	/**
	 * @creation date: 30/08/2026
	 * @author: Javier Torres - Volestra
	 * @description: Decide en que estado de NUESTRO procesamiento queda el pago, a partir
	 *               de lo que la aseguradora dice del recibo. Solo un recibo que
	 *               ella da por pagado entra al pipeline. Los demas se reflejan sin
	 *               conciliar: Pendiente queda esperando el cobro y Vencido o Cancelado
	 *               quedan No Conciliable, del que salen solos si mas adelante la
	 *               aseguradora los reporta pagados.
	 * @param carrierReceiptStatus: Situacion del recibo segun la aseguradora.
	 * @param hasPaymentDate: Indica si el pago trae fecha de pago efectiva.
	 * @param existingStatus: Estado actual del registro existente, o null si es nuevo.
	 * @return Estado a asignar a inboundStatus__c.
	 */
	private static String resolveInboundStatus(
		String carrierReceiptStatus,
		Boolean hasPaymentDate,
		String existingStatus
	) {
		if (CARRIER_PAID.equals(carrierReceiptStatus)) {
			// Un recibo que se declara pagado y no dice cuando es un dato contradictorio: no
			// deberia presentarse nunca y, si se presenta, lo mira una persona.
			return hasPaymentDate ? STATUS_PARSED : STATUS_MANUAL_REVIEW;
		}
		if (CARRIER_UNKNOWN.equals(carrierReceiptStatus)) {
			return STATUS_MANUAL_REVIEW;
		}
		if (STATUS_REJECTED.equals(existingStatus)) {
			// Un rechazado no pasa a esperar cobro por un reenvio; solo lo saca de ahi un
			// recibo que la aseguradora de por pagado, resuelto en la rama de arriba.
			return STATUS_REJECTED;
		}
		if (CARRIER_PENDING.equals(carrierReceiptStatus)) {
			// Cobro programado: la aseguradora emitio el recibo y todavia no lo cobro.
			return STATUS_PENDING_PAYMENT;
		}
		// Vencido o Cancelado: la aseguradora no lo da por cobrado, asi que no entra al
		// pipeline. Si mas adelante lo reporta pagado, el reenvio lo devuelve a Parseado.
		return STATUS_NOT_RECONCILABLE;
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
			candidatePolicyId,
			true
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
	 * @param restartsPipeline: true si el pago empieza, o vuelve a empezar, el circuito. Un
	 *               reenvio sin cambios va en false: el pago conserva la etapa alcanzada.
	 * @return
	 */
	private static void populateInboundData(
		InboundInsurancePayment__c inboundPayment,
		ParsedInboundData data,
		String requestBody,
		String payloadHash,
		String inboundStatus,
		String rejectionReason,
		Id candidatePolicyId,
		Boolean restartsPipeline
	) {
		inboundPayment.externalPaymentId__c = data.externalPaymentId;
		inboundPayment.inboundStatus__c = inboundStatus;
		// La bandeja de revision manual es una vista de lista que filtra por esta marca, no
		// por el estado. Un pago que la recepcion manda a revisar sin pasar por el pipeline
		// no la tendria poblada y quedaria invisible para el analista.
		inboundPayment.manualReviewRequired__c = STATUS_MANUAL_REVIEW.equals(
			inboundStatus
		);
		if (restartsPipeline) {
			// Primera etapa del pipeline: el pago quedo recibido y persistido. Los eslabones
			// siguientes la van avanzando; junto con el estado permite listar los detenidos.
			// Un reenvio que devuelve el pago al circuito la reinicia, porque el pago va a
			// recorrerlo de nuevo; uno sin cambios no, porque el pago no se mueve.
			inboundPayment.pipelineStage__c = CobranzaLog.STAGE_RECEPCION;
			inboundPayment.parsedAt__c = System.now();
		}
		inboundPayment.contentFingerprint__c = data.contentFingerprint;
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
		inboundPayment.carrierReceiptStatus__c = data.carrierReceiptStatus;
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
	 *               conciliado y ademas trae una correccion real: los mismos cambios que
	 *               justifican anular su cobro. Solo se registra ese caso: la integracion
	 *               reenvia el historico de forma rutinaria, y registrar cada reenvio sin
	 *               cambios inundaria el registro sin aportar nada. Un pago ya conciliado que
	 *               vuelve con otros datos, en cambio, es la senal de que lo conciliado dejo de
	 *               coincidir con lo que informa la aseguradora.
	 * @param contexts: Filas del lote ya clasificadas.
	 * @return
	 */
	private static void logResentWithChanges(List<RowContext> contexts) {
		for (RowContext ctx : contexts) {
			if (
				ctx.owner != ctx ||
				ctx.existing == null ||
				!ctx.materialChange ||
				ctx.existing.inboundStatus__c != INBOUND_STATUS_RECONCILED
			) {
				continue;
			}
			CobranzaLog.info(
					CobranzaLog.STAGE_RECEPCION,
					CobranzaLog.EVENT_INBOUND_RESENT_CHANGED,
					'Pago ya conciliado (' +
						ctx.existing.externalPaymentId__c +
						') reenviado con datos distintos: ' +
						String.join(ctx.changes, '; ') +
						'.'
				)
				.onInbound(ctx.existing.Id);
		}
	}

	/**
	 * @creation date: 02/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Encola un InboundPaymentNormalizerQueueable con los IDs de los
	 *               registros (insertados o actualizados) que quedaron en estado
	 *               Parseado. Los rechazados y los 'Pendiente de Pago' (recibos sin
	 *               fecha de pago) no se encolan: quedan fuera del
	 *               pipeline hasta transicionar a Parseado. Solo ejecuta el enqueue
	 *               si hay al menos un ID elegible.
	 * @param written: Registros de este lote que se guardaron y pueden seguir su curso.
	 * @return
	 */
	private static void enqueueNormalization(
		List<InboundInsurancePayment__c> written
	) {
		Set<Id> candidates = new Set<Id>();
		for (InboundInsurancePayment__c rec : written) {
			if (rec.inboundStatus__c == STATUS_PARSED) {
				candidates.add(rec.Id);
			}
		}
		if (candidates.isEmpty()) {
			return;
		}

		// Se relee de la base en vez de confiar en lo que creemos haber escrito. Entre el
		// guardado y este punto corren triggers -entre ellos la cascada de anulacion- que
		// pueden haber dejado el pago en otro estado. Encolar a ciegas uno que ya no esta
		// Parseado no falla: el eslabon lo ignora y el pago se queda quieto sin que nadie se
		// entere. Comprobarlo aqui convierte ese silencio en una advertencia.
		Set<Id> toNormalize = new Set<Id>();
		for (InboundInsurancePayment__c rec : [
			SELECT Id, inboundStatus__c
			FROM InboundInsurancePayment__c
			WHERE Id IN :candidates AND inboundStatus__c = :STATUS_PARSED
		]) {
			toNormalize.add(rec.Id);
		}

		for (Id candidateId : candidates) {
			if (toNormalize.contains(candidateId)) {
				continue;
			}
			CobranzaLog.error(
					CobranzaLog.STAGE_RECEPCION,
					CobranzaLog.EVENT_RESEND_NOT_REQUEUED,
					'El pago iba a reprocesarse pero quedo en otro estado antes de encolarlo, ' +
						'asi que no entrara al circuito. Suele significar que algo escribio el ' +
						'estado despues de la recepcion.'
				)
				.onInbound(candidateId);
		}

		if (!toNormalize.isEmpty()) {
			System.enqueueJob(new InboundPaymentNormalizerQueueable(toNormalize));
		}
	}

	/**
	 * @creation date: 01/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Manda los cobros programados a identificar su cuota. Un recibo que
	 *               la aseguradora emitio y aun no cobro no entra al pipeline -no hay cobro que
	 *               conciliar- pero si vale la pena saber a que cuota corresponde: permite ver
	 *               que cobros vienen y, sobre todo, contrastar el importe y la fecha que emitio
	 *               la aseguradora contra los de nuestro plan, semanas antes del cobro.
	 *               La poliza ya se resolvio en esta misma recepcion, asi que solo falta la
	 *               cuota: se encola directamente ese eslabon, que sabe detenerse ahi.
	 * @param written: Registros de este lote que se guardaron y pueden seguir su curso.
	 * @return
	 */
	private static void enqueueScheduledChargeMatching(
		List<InboundInsurancePayment__c> written
	) {
		Set<Id> candidates = new Set<Id>();
		for (InboundInsurancePayment__c rec : written) {
			if (rec.inboundStatus__c == STATUS_PENDING_PAYMENT) {
				candidates.add(rec.Id);
			}
		}
		if (candidates.isEmpty()) {
			return;
		}
		try {
			System.enqueueJob(new InboundInstallmentCandidateQueueable(candidates));
		} catch (System.AsyncException e) {
			CobranzaLog.chainBreak(
				CobranzaLog.STAGE_RECEPCION,
				e,
				'InboundInstallmentCandidateQueueable',
				candidates
			);
		}
	}

	/**
	 * @creation date: 24/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Consulta los registros InboundInsurancePayment__c que ya existen
	 *               para los externalPaymentId__c recibidos, con su estado actual.
	 *               Permite detectar duplicados, rutear el registro a UPDATE en lugar
	 *               de INSERT y decidir la transicion de estado (un
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
				carrierReceiptStatus__c,
				resendCount__c,
				resendChangeLog__c,
				sourceAmount__c,
				sourcePaymentDate__c,
				sourcePolicyNumber__c,
				sourceInstallmentNumber__c,
				sourceDueDate__c,
				sourceCurrency__c
			FROM InboundInsurancePayment__c
			WHERE externalPaymentId__c IN :externalIds
		]) {
			result.put(rec.externalPaymentId__c, rec);
		}
		return result;
	}

	/**
	 * @creation date: 14/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Busca por la huella de su contenido los rechazados sin folio que ya
	 *               tenemos. Sin folio no hay otra forma de saber que un recibo ya llego: la
	 *               huella del mensaje completo no sirve, porque incluye la fecha de
	 *               sincronizacion y cambia en cada envio.
	 * @param fingerprints: Huellas de las filas sin folio del lote.
	 * @return Mapa de huella al rechazado mas antiguo con esa huella.
	 */
	private static Map<String, InboundInsurancePayment__c> findRejectedWithoutId(
		Set<String> fingerprints
	) {
		Map<String, InboundInsurancePayment__c> result = new Map<String, InboundInsurancePayment__c>();
		fingerprints.remove(null);
		if (fingerprints.isEmpty()) {
			return result;
		}
		for (InboundInsurancePayment__c rec : [
			SELECT
				Id,
				inboundStatus__c,
				contentFingerprint__c,
				resendCount__c,
				resendChangeLog__c
			FROM InboundInsurancePayment__c
			WHERE
				contentFingerprint__c IN :fingerprints
				AND externalPaymentId__c = NULL
				AND inboundStatus__c = :STATUS_REJECTED
			ORDER BY CreatedDate
		]) {
			if (!result.containsKey(rec.contentFingerprint__c)) {
				result.put(rec.contentFingerprint__c, rec);
			}
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
		// La fecha de cancelacion NO se usa como fecha de pago. Ese atajo venia del
		// modelo anterior, donde solia ser la unica fecha disponible, y convertia todo recibo
		// cancelado en un cobro: generaba recibo, conciliaba la cuota y cerraba la oportunidad.
		data.sourceCancellationDate = getDate(payload, 'sourceCancellationDate__c');
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
		data.carrierReceiptStatus = resolveCarrierReceiptStatus(data);
		return data;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Calcula el identificador de deduplicacion del pago inbound.
	 *               La clave unica entre aseguradoras es {sourceCarrierCode__c}_{sourceReceiptNumber__c},
	 *               de modo que dos aseguradoras con el mismo folio no colisionan.
	 *               Fallback documentado: si el codigo de aseguradora
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
	 * @creation date: 14/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Huella del contenido del recibo: aseguradora, poliza, folio, importe,
	 *               estatus y fechas. Deja fuera la fecha de sincronizacion y los demas datos
	 *               que la integracion cambia en cada envio, de modo que el mismo recibo da la
	 *               misma huella en cualquier sincronizacion. El importe va con dos decimales
	 *               para que 450 y 450.00 den la misma huella.
	 * @param data: Datos parseados de la fila.
	 * @return Huella SHA-256 en hexadecimal.
	 */
	private static String calculateContentFingerprint(ParsedInboundData data) {
		List<String> parts = new List<String>{
			normalizeText(data.sourceCarrierCode),
			normalizeText(data.sourceInsuranceCarrier),
			normalizeText(data.sourcePolicyNumber),
			normalizeText(data.sourceReceiptNumber),
			data.sourceAmount == null
				? null
				: data.sourceAmount.setScale(2).toPlainString(),
			normalizeText(data.sourcePaymentStatus),
			normalizeText(data.sourcePaymentStatusRaw),
			data.sourcePaymentDate == null
				? null
				: String.valueOf(data.sourcePaymentDate),
			data.sourceDueDate == null ? null : String.valueOf(data.sourceDueDate),
			data.sourceCancellationDate == null
				? null
				: String.valueOf(data.sourceCancellationDate)
		};
		List<String> normalized = new List<String>();
		for (String part : parts) {
			normalized.add(part == null ? '' : part);
		}
		return calculatePayloadHash(String.join(normalized, '|'));
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
		String carrierReceiptStatus;
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
		String contentFingerprint;
	}

	private class RowContext {
		Boolean skip = false;
		Boolean materialChange = false;
		List<String> changes = new List<String>();
		String skipMessage;
		ParsedInboundData data;
		String itemJson;
		String payloadHash;
		String validationReason;
		String outcome;
		String writeError;
		// Fila que escribe el registro. Las filas repetidas del mismo lote apuntan a la
		// primera; las que no escriben nada lo dejan vacio.
		RowContext owner;
		// Pago que ya teniamos, tal como estaba antes de este envio.
		InboundInsurancePayment__c existing;
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
