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
  private static final String REJECTION_REASON_MALFORMED_PAYLOAD = 'Payload malformado';
  private static final String REJECTION_REASON_INCOMPLETE_PAYLOAD = 'Payload incompleto';
  private static final String REJECTION_REASON_INVALID_AMOUNT = 'Importe invalido';
  private static final String REJECTION_REASON_INVALID_DATE = 'Fecha invalida';
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

    Map<String, Id> existingIdByExternalId = findExistingInboundIds(
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

      if (firstByExternalId.containsKey(ctx.data.externalPaymentId)) {
        RowContext first = firstByExternalId.get(ctx.data.externalPaymentId);
        populateInboundData(
          first.record,
          ctx.data,
          ctx.itemJson,
          ctx.payloadHash,
          STATUS_PARSED,
          null,
          candidatePolicyId
        );
        ctx.record = first.record;
        ctx.outcome = OUTCOME_UPDATED;
        updated++;
        continue;
      }

      Id existingId = existingIdByExternalId.get(ctx.data.externalPaymentId);
      if (existingId != null) {
        InboundInsurancePayment__c rec = new InboundInsurancePayment__c(
          Id = existingId
        );
        populateInboundData(
          rec,
          ctx.data,
          ctx.itemJson,
          ctx.payloadHash,
          STATUS_PARSED,
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
        STATUS_PARSED,
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

    List<ItemResult> results = new List<ItemResult>();
    for (RowContext ctx : contexts) {
      results.add(toItemResult(ctx));
    }

    return buildBatchResult(rows.size(), received, updated, rejected, results);
  }

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
      Boolean hasPaymentDateField =
        rowPayload.containsKey('sourcePaymentDate__c') ||
        rowPayload.containsKey('sourceCancellationDate__c');
      ctx.validationReason = validatePayload(
        ctx.data.externalPaymentId,
        ctx.data.sourcePolicyNumber,
        ctx.data.sourceAmount,
        hasAmountField,
        ctx.data.sourcePaymentDate,
        hasPaymentDateField
      );
      contexts.add(ctx);
    }
    return contexts;
  }

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

  private static EndpointResult buildErrorResult(
    Integer statusCode,
    String code,
    String message
  ) {
    return buildErrorResult(statusCode, code, message, null);
  }

  private static String validatePayload(
    String externalPaymentId,
    String sourcePolicyNumber,
    Decimal sourceAmount,
    Boolean hasAmountField,
    Date sourcePaymentDate,
    Boolean hasPaymentDateField
  ) {
    if (
      String.isBlank(externalPaymentId) || String.isBlank(sourcePolicyNumber)
    ) {
      return REJECTION_REASON_INCOMPLETE_PAYLOAD;
    }

    if (!hasAmountField || sourceAmount == null || sourceAmount <= 0) {
      return REJECTION_REASON_INVALID_AMOUNT;
    }

    if (!hasPaymentDateField || sourcePaymentDate == null) {
      return REJECTION_REASON_INVALID_DATE;
    }

    return null;
  }

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
  }

  private static Map<String, Id> findExistingInboundIds(
    Set<String> externalIds
  ) {
    Map<String, Id> result = new Map<String, Id>();
    if (externalIds.isEmpty()) {
      return result;
    }
    for (InboundInsurancePayment__c rec : [
      SELECT Id, externalPaymentId__c
      FROM InboundInsurancePayment__c
      WHERE externalPaymentId__c IN :externalIds
    ]) {
      result.put(rec.externalPaymentId__c, rec.Id);
    }
    return result;
  }

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

  private static ParsedInboundData parseInboundData(
    Map<String, Object> payload
  ) {
    ParsedInboundData data = new ParsedInboundData();
    data.externalPaymentId = getString(payload, 'externalPaymentId__c');
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
    return data;
  }

  private static String calculatePayloadHash(String requestBody) {
    return EncodingUtil.convertToHex(
      Crypto.generateDigest('SHA-256', Blob.valueOf(requestBody))
    );
  }

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

  private static Date getDate(Map<String, Object> payload, String fieldName) {
    DateTime dt = parseDateTime(payload.get(fieldName));
    return dt == null ? null : dt.date();
  }

  private static DateTime getDateTime(
    Map<String, Object> payload,
    String fieldName
  ) {
    return parseDateTime(payload.get(fieldName));
  }

  // Acepta 'dd/MM/yyyy' y 'dd/MM/yyyy HH:mm:ss'. Campos Date usan .date() sobre el resultado.
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

  private static String getValidationMessage(String validationReason) {
    if (validationReason == REJECTION_REASON_INCOMPLETE_PAYLOAD) {
      return 'Faltan campos requeridos.';
    }

    if (validationReason == REJECTION_REASON_INVALID_AMOUNT) {
      return 'El campo sourceAmount debe ser mayor que cero.';
    }

    if (validationReason == REJECTION_REASON_INVALID_DATE) {
      return 'El campo sourcePaymentDate debe ser una fecha valida.';
    }

    return 'La solicitud es invalida.';
  }

  private class ParsedInboundData {
    String externalPaymentId;
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
  }

  private class RowContext {
    Boolean skip = false;
    String skipMessage;
    ParsedInboundData data;
    String itemJson;
    String payloadHash;
    String validationReason;
    String outcome;
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
