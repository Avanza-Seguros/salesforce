/**
 *   @name: InboundPolicyService
 *   @version: 1.0
 *   @creation date: 25/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Recibe y guarda las comunicaciones de poliza que manda la aseguradora por
 *                 MuleSoft (canal de polizas). Solo recibe y guarda: aplicar los
 *                 datos a la poliza es trabajo de otras historias.
 *                 Cada fila queda en un InboundPolicyUpdate__c con sus datos, el JSON tal
 *                 como llego y su huella. Nada se descarta: una fila que no se puede aceptar
 *                 se guarda como Rechazado con su motivo.
 *                 La aseguradora manda la cartera completa en cada sincronizacion, asi que la
 *                 misma comunicacion llega muchas veces. Se reconoce por la huella de su
 *                 contenido, que deja fuera la fecha de sincronizacion: un reenvio sin
 *                 cambios solo suma un reenvio, no crea otro registro.
 */
public with sharing class InboundPolicyService {
	public static final Integer MAX_ROWS = 200;

	private static final String STATUS_RECEIVED = 'Recibido';
	private static final String STATUS_REJECTED = 'Rechazado';
	private static final String STATUS_REVIEW = 'Revision Manual';
	private static final String SOURCE_SYSTEM = 'MuleSoft';

	private static final String CODE_RECEIVED = 'RECEIVED';
	private static final String CODE_RESENT = 'RESENT';
	private static final String CODE_REJECTED = 'REJECTED';
	private static final String CODE_WRITE_FAILED = 'WRITE_FAILED';
	private static final String CODE_BATCH_PROCESSED = 'BATCH_PROCESSED';
	private static final String CODE_EMPTY_BODY = 'EMPTY_BODY';
	private static final String CODE_INVALID_JSON = 'INVALID_JSON';
	private static final String CODE_BATCH_TOO_LARGE = 'BATCH_TOO_LARGE';

	private static final String REASON_NOT_AN_OBJECT = 'Cada elemento del arreglo debe ser un objeto JSON.';
	private static final String REASON_MALFORMED_BODY = 'El cuerpo no es un arreglo JSON valido.';
	private static final String REASON_MISSING_NUMBER = 'Falta el numero de poliza (sourcePolicyNumber__c).';
	private static final String REASON_NUMERIC_NUMBER = 'El numero de poliza llego como numero: debe llegar como texto, o pierde los ceros a la izquierda.';
	private static final String REASON_MISSING_START = 'Falta el inicio de vigencia (sourcePolicyStartDate__c).';
	private static final String REASON_INVALID_START = 'El inicio de vigencia no es una fecha valida (aaaa-mm-dd o dd/mm/aaaa).';

	// Deja las comunicaciones en Recibido, sin aplicarlas: para probar la recepcion sola.
	@TestVisible
	private static Boolean applyDisabledForTest = false;

	private static final String KEY_POLICY_NUMBER = 'sourcePolicyNumber__c';
	private static final String KEY_START_DATE = 'sourcePolicyStartDate__c';
	private static final String KEY_SYNCHRONIZED_AT = 'sourceSynchronizedAt__c';
	// Zona de las horas que llegan sin zona (la del usuario de integracion en todas las orgs).
	private static final String MEXICO_TIME_ZONE = 'America/Mexico_City';

	// Claves de texto que se copian tal cual al registro.
	private static final List<String> TEXT_KEYS = new List<String>{
		'sourcePolicyId__c',
		'sourcePolicyStatusRaw__c',
		'sourceCancellationReason__c',
		'sourcePolicyBranch__c',
		'sourcePremiumFrequency__c',
		'sourceCustomerName__c',
		'sourceCustomerTaxId__c',
		'sourceCustomerType__c',
		'sourceCustomerAddress__c',
		'sourceProductName__c',
		'sourceInsuredAssetDescription__c',
		'sourcePaymentMode__c',
		'sourceIntermediaryName__c',
		'sourceRenewalFlag__c',
		'sourceCarrierCode__c',
		'sourceCurrency__c'
	};

	// Claves de fecha: se aceptan ISO (aaaa-mm-dd) y dd/mm/aaaa.
	private static final List<String> DATE_KEYS = new List<String>{
		'sourcePolicyEndDate__c',
		'sourceCancellationDate__c',
		'sourcePolicyIssueDate__c',
		'sourcePolicyRenewalDate__c',
		'sourceLastPaymentDate__c',
		'sourceNextDueDate__c'
	};

	// Claves numericas: se aceptan como numero JSON o como texto numerico.
	private static final List<String> NUMBER_KEYS = new List<String>{
		'sourceTotalPremium__c',
		'sourceNetPremium__c',
		'sourcePolicyFee__c',
		'sourceFinancingCharge__c',
		'sourceTaxAmount__c',
		'sourceDiscountPercent__c',
		'sourcePaidPremium__c',
		'sourceOutstandingPremium__c'
	};

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Punto de entrada. Valida el cuerpo y guarda cada fila. Un cuerpo que no
	 *               es un arreglo JSON se guarda como un registro rechazado, para que quede
	 *               constancia de lo que llego.
	 * @param requestBody: Cuerpo crudo recibido en el endpoint.
	 * @return: EndpointResult Codigo HTTP y cuerpo de la respuesta.
	 * @exception:
	 * @throws:
	 */
	public static EndpointResult receive(String requestBody) {
		if (String.isBlank(requestBody)) {
			return errorResult(
				400,
				CODE_EMPTY_BODY,
				'El cuerpo de la solicitud es requerido.',
				null
			);
		}

		Object rawPayload;

		try {
			rawPayload = JSON.deserializeUntyped(requestBody);
		} catch (Exception e) {
			rawPayload = null;
		}

		if (!(rawPayload instanceof List<Object>)) {
			InboundPolicyUpdate__c rejected = persistMalformedBody(requestBody);
			return errorResult(
				400,
				CODE_INVALID_JSON,
				'El cuerpo de la solicitud debe ser un arreglo JSON de polizas.',
				rejected == null ? null : rejected.Id
			);
		}

		List<Object> rows = (List<Object>) rawPayload;

		if (rows.isEmpty()) {
			return errorResult(
				400,
				CODE_EMPTY_BODY,
				'El cuerpo de la solicitud debe incluir al menos una poliza.',
				null
			);
		}

		if (rows.size() > MAX_ROWS) {
			return errorResult(
				400,
				CODE_BATCH_TOO_LARGE,
				'El lote trae ' +
					rows.size() +
					' polizas; el maximo es ' +
					MAX_ROWS +
					'. Parta el envio en lotes mas chicos.',
				null
			);
		}

		return processRows(rows);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Guarda las filas del lote. Las que ya teniamos (misma huella) solo suman
	 *               un reenvio. Una fila que no se puede guardar no tumba a las demas.
	 * @param rows: Filas del arreglo JSON.
	 * @return: EndpointResult Resumen del lote y resultado por fila.
	 * @exception:
	 * @throws:
	 */
	private static EndpointResult processRows(List<Object> rows) {
		List<RowContext> contexts = new List<RowContext>();
		Set<String> fingerprints = new Set<String>();

		for (Object raw : rows) {
			RowContext ctx = parseRow(raw);
			contexts.add(ctx);
			fingerprints.add(ctx.record.contentFingerprint__c);
		}

		Map<String, InboundPolicyUpdate__c> existingByFingerprint = new Map<String, InboundPolicyUpdate__c>();

		for (InboundPolicyUpdate__c existing : [
			SELECT
				Id,
				contentFingerprint__c,
				resendCount__c,
				inboundStatus__c,
				candidatePolicy__c
			FROM InboundPolicyUpdate__c
			WHERE contentFingerprint__c IN :fingerprints
		]) {
			existingByFingerprint.put(existing.contentFingerprint__c, existing);
		}

		Map<String, RowContext> ownerByFingerprint = new Map<String, RowContext>();
		List<RowContext> toInsert = new List<RowContext>();
		List<RowContext> toUpdate = new List<RowContext>();
		// Un reenvio no se vuelve a aplicar, pero la poliza si se reporto hoy.
		List<CarrierStatusCommunication> seen = new List<CarrierStatusCommunication>();
		Datetime now = System.now();

		for (RowContext ctx : contexts) {
			String fingerprint = ctx.record.contentFingerprint__c;
			RowContext owner = ownerByFingerprint.get(fingerprint);

			if (owner != null) {
				// La misma comunicacion dos veces en el lote: se guarda una sola vez.
				ctx.owner = owner;
				ctx.resent = true;
				owner.record.resendCount__c =
					nullToZero(owner.record.resendCount__c) + 1;
				continue;
			}

			ctx.owner = ctx;
			ownerByFingerprint.put(fingerprint, ctx);
			InboundPolicyUpdate__c existing = existingByFingerprint.get(fingerprint);

			if (existing != null) {
				ctx.resent = true;
				InboundPolicyUpdate__c resend = new InboundPolicyUpdate__c(
					Id = existing.Id,
					resendCount__c = nullToZero(existing.resendCount__c) + 1,
					lastReceivedAt__c = now
				);

				if (ctx.record.sourceSynchronizedAt__c != null) {
					resend.sourceSynchronizedAt__c = ctx.record.sourceSynchronizedAt__c;
				}

				// Si la anterior no llego a aplicarse, el reenvio le da otra oportunidad. Tambien si
				// estaba en revision: si ya se creo la poliza que faltaba, se aplica sola sin que
				// nadie la reprocese a mano; si no, vuelve a revision con su motivo.
				ctx.pendingApply =
					existing.inboundStatus__c == STATUS_RECEIVED ||
					existing.inboundStatus__c == STATUS_REVIEW;

				if (existing.inboundStatus__c == STATUS_REVIEW) {
					resend.inboundStatus__c = STATUS_RECEIVED;
				}

				if (existing.candidatePolicy__c != null) {
					seen.add(
						seenOn(
							existing,
							ctx.record.sourceSynchronizedAt__c != null
								? ctx.record.sourceSynchronizedAt__c
								: now
						)
					);
				}

				ctx.record = resend;
				toUpdate.add(ctx);
				continue;
			}

			ctx.record.receivedAt__c = now;
			ctx.record.lastReceivedAt__c = now;
			ctx.record.resendCount__c = 0;
			ctx.pendingApply = ctx.rejectionReason == null;
			toInsert.add(ctx);
		}

		write(toInsert, true);
		write(toUpdate, false);
		PolicyCarrierStatusService.applyCarrierStatus(seen);
		enqueueApply(contexts);
		AppLogger.flush();

		return batchResult(rows.size(), contexts);
	}

	/**
	 * @creation date: 29/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Comunicacion que solo dice que la aseguradora volvio a reportar la poliza:
	 *               sin estado, no cambia nada mas que la fecha en que se la vio por ultima vez.
	 * @param existing: Comunicacion ya guardada, con su poliza.
	 * @param reportedAt: Fecha de la sincronizacion que la reenvio.
	 * @return: CarrierStatusCommunication Comunicacion.
	 * @exception:
	 * @throws:
	 */
	private static CarrierStatusCommunication seenOn(
		InboundPolicyUpdate__c existing,
		Datetime reportedAt
	) {
		CarrierStatusCommunication c = new CarrierStatusCommunication();
		c.sourceRecordId = existing.Id;
		c.policyId = existing.candidatePolicy__c;
		c.source = CarrierStatusCommunication.SOURCE_POLICIES;
		c.communicatedAt = reportedAt;
		return c;
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Encola la aplicacion a la poliza de las comunicaciones aceptadas
	 *               que quedaron pendientes. Si no se puede encolar, quedan en Recibido y se
	 *               registra: el siguiente reenvio las vuelve a intentar.
	 * @param contexts: Filas del lote ya guardadas.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	private static void enqueueApply(List<RowContext> contexts) {
		if (Test.isRunningTest() && applyDisabledForTest) {
			return;
		}

		Set<Id> pending = new Set<Id>();

		for (RowContext ctx : contexts) {
			if (
				ctx.owner == ctx &&
				ctx.pendingApply &&
				ctx.writeError == null &&
				ctx.record.Id != null
			) {
				pending.add(ctx.record.Id);
			}
		}

		if (pending.isEmpty()) {
			return;
		}

		try {
			System.enqueueJob(new InboundPolicyApplyQueueable(pending));
		} catch (Exception e) {
			CobranzaLog.chainBreak(
				CobranzaLog.STAGE_RECEPCION_POLIZAS,
				e,
				'aplicar las comunicaciones a la poliza',
				pending
			);
		}
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Convierte una fila en el registro que se guarda, con su huella y, si no
	 *               se puede aceptar, su motivo de rechazo.
	 * @param raw: Elemento del arreglo JSON.
	 * @return: RowContext Fila lista para guardar.
	 * @exception:
	 * @throws:
	 */
	private static RowContext parseRow(Object raw) {
		RowContext ctx = new RowContext();
		String itemJson = JSON.serialize(raw);
		ctx.itemJson = itemJson;
		InboundPolicyUpdate__c record = new InboundPolicyUpdate__c(
			sourcePayloadJson__c = itemJson,
			sourcePayloadHash__c = sha256(itemJson),
			sourceSystem__c = SOURCE_SYSTEM,
			inboundStatus__c = STATUS_RECEIVED
		);
		ctx.record = record;

		if (!(raw instanceof Map<String, Object>)) {
			reject(ctx, REASON_NOT_AN_OBJECT);
			record.contentFingerprint__c = sha256('fila:' + itemJson);
			return ctx;
		}

		Map<String, Object> row = (Map<String, Object>) raw;
		Object rawNumber = row.get(KEY_POLICY_NUMBER);
		record.sourcePolicyNumber__c = textOf(rawNumber);
		ctx.policyNumber = record.sourcePolicyNumber__c;

		for (String key : TEXT_KEYS) {
			record.put(key, textOf(row.get(key)));
		}

		for (String key : DATE_KEYS) {
			record.put(key, parseDate(row.get(key)));
		}

		for (String key : NUMBER_KEYS) {
			record.put(key, numberOf(row.get(key)));
		}

		record.sourceSynchronizedAt__c = parseDatetime(
			row.get(KEY_SYNCHRONIZED_AT)
		);
		record.sourcePolicyStartDate__c = parseDate(row.get(KEY_START_DATE));

		if (record.sourceCarrierCode__c != null) {
			record.sourceCarrierCode__c = record.sourceCarrierCode__c.toUpperCase();
		}

		if (record.sourcePolicyNumber__c == null) {
			reject(ctx, REASON_MISSING_NUMBER);
		} else if (!(rawNumber instanceof String)) {
			reject(ctx, REASON_NUMERIC_NUMBER);
		} else if (textOf(row.get(KEY_START_DATE)) == null) {
			reject(ctx, REASON_MISSING_START);
		} else if (record.sourcePolicyStartDate__c == null) {
			reject(ctx, REASON_INVALID_START);
		} else {
			record.identityKey__c = identityKey(record);
		}

		record.contentFingerprint__c = contentFingerprint(record);
		return ctx;
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Marca la fila como rechazada con su motivo. Se guarda igual.
	 * @param ctx: Fila.
	 * @param reason: Motivo.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	private static void reject(RowContext ctx, String reason) {
		ctx.rejectionReason = reason;
		ctx.record.inboundStatus__c = STATUS_REJECTED;
		ctx.record.rejectionReason__c = reason;
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Llave de la vigencia: numero de poliza, inicio de vigencia y codigo de
	 *               aseguradora. Agrupa las comunicaciones de una misma vigencia.
	 * @param record: Comunicacion.
	 * @return: String Llave.
	 * @exception:
	 * @throws:
	 */
	private static String identityKey(InboundPolicyUpdate__c record) {
		return record.sourcePolicyNumber__c +
			'|' +
			String.valueOf(record.sourcePolicyStartDate__c) +
			'|' +
			(record.sourceCarrierCode__c == null ? '' : record.sourceCarrierCode__c);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Huella del contenido: todos los datos de la aseguradora salvo la fecha de
	 *               sincronizacion, que cambia en cada envio. Los importes se comparan por su
	 *               valor (450 y 450.00 dan la misma huella) y los textos sin espacios extremos.
	 * @param record: Comunicacion ya poblada.
	 * @return: String Huella SHA-256 en hexadecimal.
	 * @exception:
	 * @throws:
	 */
	private static String contentFingerprint(InboundPolicyUpdate__c record) {
		List<String> keys = new List<String>{ KEY_POLICY_NUMBER, KEY_START_DATE };
		keys.addAll(TEXT_KEYS);
		keys.addAll(DATE_KEYS);
		keys.addAll(NUMBER_KEYS);
		List<String> parts = new List<String>();

		for (String key : keys) {
			Object value = record.get(key);

			if (value instanceof Decimal) {
				parts.add(((Decimal) value).stripTrailingZeros().toPlainString());
			} else {
				parts.add(value == null ? '' : String.valueOf(value));
			}
		}

		// Una fila rechazada entra con su motivo: si mas adelante llega igual pero valida,
		// es otra comunicacion.
		parts.add(
			record.rejectionReason__c == null ? '' : record.rejectionReason__c
		);
		return sha256(String.join(parts, '|'));
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Guarda los registros uno a uno, de modo que un fallo no tumbe al resto.
	 *               Los textos demasiado largos se recortan en vez de fallar: el JSON crudo
	 *               sigue guardando el valor completo.
	 * @param owners: Filas duenas de un registro.
	 * @param isInsert: Alta o actualizacion.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	private static void write(List<RowContext> owners, Boolean isInsert) {
		if (owners.isEmpty()) {
			return;
		}

		List<InboundPolicyUpdate__c> records = new List<InboundPolicyUpdate__c>();

		for (RowContext owner : owners) {
			records.add(owner.record);
		}

		Database.DMLOptions options = new Database.DMLOptions();
		options.optAllOrNone = false;
		options.allowFieldTruncation = true;
		List<Database.SaveResult> results = isInsert
			? Database.insert(records, options)
			: Database.update(records, options);

		for (Integer i = 0; i < results.size(); i++) {
			if (results[i].isSuccess()) {
				continue;
			}

			List<String> errors = new List<String>();

			for (Database.Error error : results[i].getErrors()) {
				errors.add(error.getMessage());
			}

			RowContext owner = owners[i];
			owner.writeError = String.join(errors, '; ');
			CobranzaLog.error(
					CobranzaLog.STAGE_RECEPCION_POLIZAS,
					CobranzaLog.EVENT_POLICY_INBOUND_WRITE_FAILED,
					'No se pudo guardar la comunicacion de la poliza ' +
						owner.policyNumber +
						'. El resto del envio se proceso normalmente. Motivo: ' +
						owner.writeError
				)
				.appendDetails('JSON recibido: ' + owner.itemJson);
		}
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Guarda un cuerpo que no es un arreglo JSON, para que quede constancia de
	 *               lo que llego. El mismo cuerpo reenviado suma un reenvio.
	 * @param requestBody: Cuerpo recibido.
	 * @return: InboundPolicyUpdate__c Registro guardado, o null si no se pudo guardar.
	 * @exception:
	 * @throws:
	 */
	private static InboundPolicyUpdate__c persistMalformedBody(
		String requestBody
	) {
		String fingerprint = sha256('cuerpo:' + requestBody);
		List<InboundPolicyUpdate__c> previous = [
			SELECT Id, resendCount__c
			FROM InboundPolicyUpdate__c
			WHERE contentFingerprint__c = :fingerprint
			LIMIT 1
		];
		Datetime now = System.now();
		InboundPolicyUpdate__c record;

		if (previous.isEmpty()) {
			record = new InboundPolicyUpdate__c(
				sourcePayloadJson__c = requestBody,
				sourcePayloadHash__c = sha256(requestBody),
				contentFingerprint__c = fingerprint,
				sourceSystem__c = SOURCE_SYSTEM,
				inboundStatus__c = STATUS_REJECTED,
				rejectionReason__c = REASON_MALFORMED_BODY,
				receivedAt__c = now,
				lastReceivedAt__c = now,
				resendCount__c = 0
			);
		} else {
			record = new InboundPolicyUpdate__c(
				Id = previous[0].Id,
				resendCount__c = nullToZero(previous[0].resendCount__c) + 1,
				lastReceivedAt__c = now
			);
		}

		Database.DMLOptions options = new Database.DMLOptions();
		options.allowFieldTruncation = true;
		options.optAllOrNone = false;
		Database.SaveResult result = record.Id == null
			? Database.insert(record, options)
			: Database.update(record, options);

		if (!result.isSuccess()) {
			CobranzaLog.error(
					CobranzaLog.STAGE_RECEPCION_POLIZAS,
					CobranzaLog.EVENT_POLICY_INBOUND_WRITE_FAILED,
					'No se pudo guardar el cuerpo malformado. Motivo: ' +
					result.getErrors()[0].getMessage()
				)
				.appendDetails('Cuerpo recibido: ' + requestBody.left(30000));
			AppLogger.flush();
			return null;
		}

		return record;
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Arma la respuesta del lote: 202 si se acepto al menos una fila, 400 si
	 *               no se acepto ninguna.
	 * @param totalRecords: Filas recibidas.
	 * @param contexts: Filas procesadas.
	 * @return: EndpointResult Respuesta.
	 * @exception:
	 * @throws:
	 */
	private static EndpointResult batchResult(
		Integer totalRecords,
		List<RowContext> contexts
	) {
		Integer received = 0;
		Integer resent = 0;
		Integer rejected = 0;
		List<ItemResult> results = new List<ItemResult>();

		for (RowContext ctx : contexts) {
			ItemResult item = itemResult(ctx);
			results.add(item);

			if (!item.success) {
				rejected++;
			} else if (item.code == CODE_RESENT) {
				resent++;
			} else {
				received++;
			}
		}

		return new EndpointResult(
			received + resent > 0 ? 202 : 400,
			new ResponseBody(
				rejected == 0,
				CODE_BATCH_PROCESSED,
				'Lote de polizas procesado.',
				null,
				totalRecords,
				received,
				resent,
				rejected,
				results
			)
		);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Resultado de una fila para la respuesta.
	 * @param ctx: Fila procesada.
	 * @return: ItemResult Resultado.
	 * @exception:
	 * @throws:
	 */
	private static ItemResult itemResult(RowContext ctx) {
		RowContext owner = ctx.owner == null ? ctx : ctx.owner;
		Id recordId = owner.record == null ? null : owner.record.Id;
		String policyNumber = ctx.policyNumber;

		if (owner.writeError != null) {
			return new ItemResult(
				false,
				CODE_WRITE_FAILED,
				'No se pudo guardar la comunicacion: ' + owner.writeError,
				policyNumber,
				recordId
			);
		}

		if (ctx.rejectionReason != null) {
			return new ItemResult(
				false,
				CODE_REJECTED,
				ctx.rejectionReason,
				policyNumber,
				recordId
			);
		}

		if (ctx.resent) {
			return new ItemResult(
				true,
				CODE_RESENT,
				'La comunicacion ya se habia recibido sin cambios: se cuenta como reenvio.',
				policyNumber,
				recordId
			);
		}

		return new ItemResult(
			true,
			CODE_RECEIVED,
			'Comunicacion de poliza recibida.',
			policyNumber,
			recordId
		);
	}

	private static EndpointResult errorResult(
		Integer statusCode,
		String code,
		String message,
		Id recordId
	) {
		return new EndpointResult(
			statusCode,
			new ResponseBody(
				false,
				code,
				message,
				recordId,
				0,
				0,
				0,
				0,
				new List<ItemResult>()
			)
		);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Texto sin espacios extremos, o null si llega vacio. Un numero JSON se
	 *               convierte a texto tal cual (sin ceros a la izquierda: ya los perdio).
	 * @param value: Valor crudo.
	 * @return: String Texto.
	 * @exception:
	 * @throws:
	 */
	private static String textOf(Object value) {
		if (value == null) {
			return null;
		}

		String text = value instanceof Decimal
			? ((Decimal) value).toPlainString()
			: String.valueOf(value).trim();
		return String.isBlank(text) ? null : text;
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Numero desde un numero JSON o un texto numerico. Lo que no es numero
	 *               queda vacio (el JSON crudo conserva el valor original).
	 * @param value: Valor crudo.
	 * @return: Decimal Numero.
	 * @exception:
	 * @throws:
	 */
	private static Decimal numberOf(Object value) {
		String text = textOf(value);

		if (text == null) {
			return null;
		}

		try {
			return Decimal.valueOf(text);
		} catch (Exception e) {
			return null;
		}
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Fecha en formato ISO (aaaa-mm-dd, con o sin hora) o dd/mm/aaaa. Se toma
	 *               el dia tal como viene escrito, sin convertir zonas horarias. Una fecha
	 *               imposible (31/02) queda vacia.
	 * @param value: Valor crudo.
	 * @return: Date Fecha, o null.
	 * @exception:
	 * @throws:
	 */
	@TestVisible
	private static Date parseDate(Object value) {
		String text = textOf(value);

		if (text == null) {
			return null;
		}

		Integer year;
		Integer month;
		Integer day;
		Matcher iso = Pattern.compile('^(\\d{4})-(\\d{2})-(\\d{2}).*$')
			.matcher(text);
		Matcher local = Pattern.compile('^(\\d{2})/(\\d{2})/(\\d{4}).*$')
			.matcher(text);

		if (iso.matches()) {
			year = Integer.valueOf(iso.group(1));
			month = Integer.valueOf(iso.group(2));
			day = Integer.valueOf(iso.group(3));
		} else if (local.matches()) {
			day = Integer.valueOf(local.group(1));
			month = Integer.valueOf(local.group(2));
			year = Integer.valueOf(local.group(3));
		} else {
			return null;
		}

		if (
			month < 1 ||
			month > 12 ||
			day < 1 ||
			day > Date.daysInMonth(year, month)
		) {
			return null;
		}

		return Date.newInstance(year, month, day);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Fecha y hora en ISO-8601 (2025-12-06T10:57:14Z) o dd/mm/aaaa hh:mm:ss.
	 *               Con zona (Z o +hh:mm) se respeta; sin zona es hora de Ciudad de Mexico, como
	 *               la lee el canal de pagos (su usuario de integracion esta en esa zona): asi el
	 *               mismo texto es el mismo instante en los dos canales y la regla «gana la mas
	 *               reciente» compara bien entre ellos. Lo que no se entiende queda vacio.
	 * @param value: Valor crudo.
	 * @return: Datetime Fecha y hora, o null.
	 * @exception:
	 * @throws:
	 */
	@TestVisible
	private static Datetime parseDatetime(Object value) {
		String text = textOf(value);

		if (text == null) {
			return null;
		}

		if (text.contains('T')) {
			if (!Pattern.matches('.*T.*(Z|[+-]\\d{2}:?\\d{2})$', text)) {
				// ISO sin zona: hora de Ciudad de Mexico.
				Matcher local = Pattern.compile(
						'^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})(\\.\\d+)?$'
					)
					.matcher(text);

				if (!local.matches()) {
					return null;
				}

				return mexicoTime(
					Date.newInstance(
						Integer.valueOf(local.group(1)),
						Integer.valueOf(local.group(2)),
						Integer.valueOf(local.group(3))
					),
					Time.newInstance(
						Integer.valueOf(local.group(4)),
						Integer.valueOf(local.group(5)),
						Integer.valueOf(local.group(6)),
						0
					)
				);
			}

			try {
				return (Datetime) JSON.deserialize('"' + text + '"', Datetime.class);
			} catch (Exception e) {
				return null;
			}
		}

		Date day = parseDate(text);

		if (day == null) {
			return null;
		}

		Matcher clock = Pattern.compile('^.* (\\d{2}):(\\d{2}):(\\d{2})$')
			.matcher(text);
		Time moment = clock.matches()
			? Time.newInstance(
					Integer.valueOf(clock.group(1)),
					Integer.valueOf(clock.group(2)),
					Integer.valueOf(clock.group(3)),
					0
			  )
			: Time.newInstance(0, 0, 0, 0);
		return mexicoTime(day, moment);
	}

	/**
	 * @creation date: 30/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: El instante que corresponde a esa fecha y hora en Ciudad de Mexico.
	 * @param day: Fecha.
	 * @param moment: Hora local de Ciudad de Mexico.
	 * @return: Datetime Instante.
	 * @exception:
	 * @throws:
	 */
	private static Datetime mexicoTime(Date day, Time moment) {
		Datetime asGmt = Datetime.newInstanceGmt(day, moment);
		Integer offsetMillis = TimeZone.getTimeZone(MEXICO_TIME_ZONE)
			.getOffset(asGmt);
		return asGmt.addSeconds(-offsetMillis / 1000);
	}

	private static String sha256(String value) {
		return EncodingUtil.convertToHex(
			Crypto.generateDigest('SHA-256', Blob.valueOf(value == null ? '' : value))
		);
	}

	private static Decimal nullToZero(Decimal value) {
		return value == null ? 0 : value;
	}

	private class RowContext {
		InboundPolicyUpdate__c record;
		// El numero y el JSON se guardan aparte: en un reenvio, el registro que se escribe
		// solo lleva el Id y los contadores.
		String policyNumber;
		String itemJson;
		String rejectionReason;
		String writeError;
		Boolean resent = false;
		Boolean pendingApply = false;
		// Fila que guarda el registro. Las repetidas del mismo lote apuntan a la primera.
		RowContext owner;
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
		public Id inboundPolicyUpdateId;
		public Integer totalRecords;
		public Integer receivedCount;
		public Integer updatedCount;
		public Integer rejectedCount;
		public List<ItemResult> results;

		public ResponseBody(
			Boolean success,
			String code,
			String message,
			Id inboundPolicyUpdateId,
			Integer totalRecords,
			Integer receivedCount,
			Integer updatedCount,
			Integer rejectedCount,
			List<ItemResult> results
		) {
			this.success = success;
			this.code = code;
			this.message = message;
			this.inboundPolicyUpdateId = inboundPolicyUpdateId;
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
		public String sourcePolicyNumber;
		public Id inboundPolicyUpdateId;

		public ItemResult(
			Boolean success,
			String code,
			String message,
			String sourcePolicyNumber,
			Id inboundPolicyUpdateId
		) {
			this.success = success;
			this.code = code;
			this.message = message;
			this.sourcePolicyNumber = sourcePolicyNumber;
			this.inboundPolicyUpdateId = inboundPolicyUpdateId;
		}
	}
}
