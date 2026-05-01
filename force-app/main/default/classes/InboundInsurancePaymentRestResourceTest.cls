/**
 *   @name: InboundInsurancePaymentRestResourceTest
 *   @version: 1.0
 *   @creation date: 24/04/2026
 *   @author: Javier Torres - Volestra
 *   @description: Valida la recepcion tecnica de pagos inbound por lote,
 *                 incluyendo escenarios validos, invalidos, duplicados y
 *                 verificacion de bulkificacion contra limites de gobernador.
 */
@IsTest
private class InboundInsurancePaymentRestResourceTest {
  @TestSetup
  static void setupData() {
    CollectionsTestDataFactory.createInsuredAccount();
  }

  @IsTest
  static void receivesValidInboundPaymentBatch() {
    InsurancePolicy policy = CollectionsTestDataFactory.buildCompletePolicy(
      CollectionsTestDataFactory.getDefaultInsuredAccountId(),
      'Inicial',
      'Mensual',
      1200,
      Date.today()
    );
    policy.Name = 'POL-REST-001';
    policy.PolicyName = 'POL-REST-001';
    insert policy;

    Test.startTest();
    invokeEndpoint(
      '[' +
        '{' +
        '"externalPaymentId__c":"EXT-1001",' +
        '"sourcePolicyNumber__c":"POL-REST-001",' +
        '"sourceAmount__c":1200.50,' +
        '"sourcePaymentDate__c":"24/04/2026",' +
        '"sourceDueDate__c":"30/04/2026",' +
        '"sourceReceiptNumber__c":"REC-1001",' +
        '"sourceCollectionChannel__c":"Domiciliacion",' +
        '"sourcePaymentStatusRaw__c":"PAGADO",' +
        '"sourcePaymentStatus__c":"Pagado",' +
        '"sourceCurrency__c":"MXN",' +
        '"sourceInsuranceCarrier__c":"GNP",' +
        '"sourcePolicyBranch__c":"Autos",' +
        '"sourceInstallmentNumber__c":"1",' +
        '"sourceCustomerExternalId__c":"CLI-001",' +
        '"sourceSynchronizedAt__c":"24/04/2026 11:30:00",' +
        '"sourceGrossCommission__c":100.25,' +
        '"sourceVatCommission__c":16.04' +
        '}' +
        ']'
    );
    Test.stopTest();

    Assert.areEqual(202, RestContext.response.statusCode);

    Map<String, Object> responseBody = getResponseBody();
    Assert.areEqual(true, responseBody.get('success'));
    Assert.areEqual('BATCH_PROCESSED', responseBody.get('code'));
    Assert.areEqual(1, toInteger(responseBody.get('totalRecords')));
    Assert.areEqual(1, toInteger(responseBody.get('receivedCount')));
    Assert.areEqual(0, toInteger(responseBody.get('updatedCount')));
    Assert.areEqual(0, toInteger(responseBody.get('rejectedCount')));

    InboundInsurancePayment__c inboundPayment = [
      SELECT
        externalPaymentId__c,
        inboundStatus__c,
        receivedAt__c,
        parsedAt__c,
        sourceAmount__c,
        sourceDueDate__c,
        sourcePayloadHash__c,
        sourcePayloadJson__c,
        sourcePaymentDate__c,
        sourcePolicyNumber__c,
        sourceReceiptNumber__c,
        sourceSystem__c,
        candidatePolicy__c,
        rejectionReason__c,
        sourceCollectionChannel__c,
        sourcePaymentStatusRaw__c,
        sourcePaymentStatus__c,
        sourceCurrency__c,
        sourceInsuranceCarrier__c,
        sourcePolicyBranch__c,
        sourceInstallmentNumber__c,
        sourceCustomerExternalId__c,
        sourceSynchronizedAt__c,
        sourceGrossCommission__c,
        sourceVatCommission__c
      FROM InboundInsurancePayment__c
      WHERE externalPaymentId__c = 'EXT-1001'
      LIMIT 1
    ];

    Assert.areEqual('Parseado', inboundPayment.inboundStatus__c);
    Assert.areEqual(1200.50, inboundPayment.sourceAmount__c);
    Assert.areEqual(
      Date.newInstance(2026, 4, 24),
      inboundPayment.sourcePaymentDate__c
    );
    Assert.areEqual(
      Date.newInstance(2026, 4, 30),
      inboundPayment.sourceDueDate__c
    );
    Assert.areEqual('REC-1001', inboundPayment.sourceReceiptNumber__c);
    Assert.areEqual('MuleSoft', inboundPayment.sourceSystem__c);
    Assert.areEqual('Domiciliacion', inboundPayment.sourceCollectionChannel__c);
    Assert.areEqual('PAGADO', inboundPayment.sourcePaymentStatusRaw__c);
    Assert.areEqual('Pagado', inboundPayment.sourcePaymentStatus__c);
    Assert.areEqual('MXN', inboundPayment.sourceCurrency__c);
    Assert.areEqual('GNP', inboundPayment.sourceInsuranceCarrier__c);
    Assert.areEqual('Autos', inboundPayment.sourcePolicyBranch__c);
    Assert.areEqual('1', inboundPayment.sourceInstallmentNumber__c);
    Assert.areEqual('CLI-001', inboundPayment.sourceCustomerExternalId__c);
    Assert.areEqual(100.25, inboundPayment.sourceGrossCommission__c);
    Assert.areEqual(16.04, inboundPayment.sourceVatCommission__c);
    Assert.areEqual(policy.Id, inboundPayment.candidatePolicy__c);
    Assert.isNotNull(inboundPayment.receivedAt__c);
    Assert.isNotNull(inboundPayment.parsedAt__c);
    Assert.isNotNull(inboundPayment.sourcePayloadHash__c);
    Assert.isTrue(inboundPayment.sourcePayloadJson__c.contains('EXT-1001'));
    Assert.areEqual(null, inboundPayment.rejectionReason__c);
  }

  @IsTest
  static void handlesMixedBatchWithUpdateAndRejected() {
    Test.startTest();
    invokeEndpoint(
      '[' +
        '{' +
        '"externalPaymentId__c":"EXT-2001",' +
        '"sourcePolicyNumber__c":"POL-DUP-001",' +
        '"sourceAmount__c":980.00,' +
        '"sourcePaymentDate__c":"24/04/2026"' +
        '},' +
        '{' +
        '"externalPaymentId__c":"EXT-2001",' +
        '"sourcePolicyNumber__c":"POL-DUP-001",' +
        '"sourceAmount__c":980.00,' +
        '"sourcePaymentDate__c":"24/04/2026"' +
        '},' +
        '{' +
        '"externalPaymentId__c":"EXT-2003",' +
        '"sourcePolicyNumber__c":"POL-INVALID-001",' +
        '"sourceAmount__c":0,' +
        '"sourcePaymentDate__c":"24/04/2026"' +
        '}' +
        ']'
    );
    Test.stopTest();

    Assert.areEqual(202, RestContext.response.statusCode);

    Map<String, Object> responseBody = getResponseBody();
    Assert.areEqual(false, responseBody.get('success'));
    Assert.areEqual(3, toInteger(responseBody.get('totalRecords')));
    Assert.areEqual(1, toInteger(responseBody.get('receivedCount')));
    Assert.areEqual(1, toInteger(responseBody.get('updatedCount')));
    Assert.areEqual(1, toInteger(responseBody.get('rejectedCount')));

    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM InboundInsurancePayment__c
        WHERE externalPaymentId__c = 'EXT-2001'
      ]
    );

    InboundInsurancePayment__c rejected = [
      SELECT externalPaymentId__c, inboundStatus__c, rejectionReason__c
      FROM InboundInsurancePayment__c
      WHERE externalPaymentId__c = 'EXT-2003'
      LIMIT 1
    ];
    Assert.areEqual('Rechazado', rejected.inboundStatus__c);
    Assert.areEqual('Importe invalido', rejected.rejectionReason__c);
  }

  @IsTest
  static void usesCancellationDateAsPaymentFallback() {
    Test.startTest();
    invokeEndpoint(
      '[' +
        '{' +
        '"externalPaymentId__c":"EXT-3001",' +
        '"sourcePolicyNumber__c":"POL-CANCEL-001",' +
        '"sourceAmount__c":450.00,' +
        '"sourceCancellationDate__c":"20/04/2026"' +
        '}' +
        ']'
    );
    Test.stopTest();

    Assert.areEqual(202, RestContext.response.statusCode);

    InboundInsurancePayment__c inboundPayment = [
      SELECT sourcePaymentDate__c, sourceCancellationDate__c, inboundStatus__c
      FROM InboundInsurancePayment__c
      WHERE externalPaymentId__c = 'EXT-3001'
      LIMIT 1
    ];

    Assert.areEqual('Parseado', inboundPayment.inboundStatus__c);
    Assert.areEqual(
      Date.newInstance(2026, 4, 20),
      inboundPayment.sourceCancellationDate__c
    );
    Assert.areEqual(
      Date.newInstance(2026, 4, 20),
      inboundPayment.sourcePaymentDate__c
    );
  }

  @IsTest
  static void rejectsMalformedJson() {
    Test.startTest();
    invokeEndpoint('[{"externalPaymentId__c":"EXT-4001"');
    Test.stopTest();

    Assert.areEqual(400, RestContext.response.statusCode);

    Map<String, Object> responseBody = getResponseBody();
    Assert.areEqual(false, responseBody.get('success'));
    Assert.areEqual('INVALID_JSON', responseBody.get('code'));
  }

  @IsTest
  static void rejectsEmptyBody() {
    Test.startTest();
    invokeEndpoint(null);
    Test.stopTest();

    Assert.areEqual(400, RestContext.response.statusCode);

    Map<String, Object> responseBody = getResponseBody();
    Assert.areEqual(false, responseBody.get('success'));
    Assert.areEqual('EMPTY_BODY', responseBody.get('code'));
  }

  @IsTest
  static void returns500WhenServiceThrowsUnexpectedly() {
    InboundInsurancePaymentRestResource.forceServiceException = true;

    Test.startTest();
    invokeEndpoint('[]');
    Test.stopTest();

    InboundInsurancePaymentRestResource.forceServiceException = false;

    Assert.areEqual(500, RestContext.response.statusCode);

    Map<String, Object> responseBody = getResponseBody();
    Assert.areEqual(false, responseBody.get('success'));
    Assert.areEqual('INTERNAL_ERROR', responseBody.get('code'));
  }

  @IsTest
  static void processesLargeBatchWithinGovernorLimits() {
    Integer batchSize = 100;
    List<String> rows = new List<String>();
    for (Integer i = 0; i < batchSize; i++) {
      rows.add(
        '{' +
          '"externalPaymentId__c":"EXT-BULK-' +
          i +
          '",' +
          '"sourcePolicyNumber__c":"POL-BULK-' +
          i +
          '",' +
          '"sourceAmount__c":100.00,' +
          '"sourcePaymentDate__c":"24/04/2026"' +
          '}'
      );
    }

    Test.startTest();
    Integer queriesBefore = Limits.getQueries();
    Integer dmlBefore = Limits.getDmlStatements();
    invokeEndpoint('[' + String.join(rows, ',') + ']');
    Integer queriesUsed = Limits.getQueries() - queriesBefore;
    Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
    Test.stopTest();

    Assert.areEqual(202, RestContext.response.statusCode);
    Map<String, Object> responseBody = getResponseBody();
    Assert.areEqual(batchSize, toInteger(responseBody.get('receivedCount')));
    Assert.areEqual(0, toInteger(responseBody.get('rejectedCount')));
    Assert.areEqual(
      batchSize,
      [
        SELECT COUNT()
        FROM InboundInsurancePayment__c
        WHERE externalPaymentId__c LIKE 'EXT-BULK-%'
      ]
    );
    Assert.isTrue(
      queriesUsed <= 5,
      'Se esperaban a lo sumo 5 SOQL para todo el lote, se usaron ' +
      queriesUsed
    );
    Assert.isTrue(
      dmlUsed <= 2,
      'Se esperaban a lo sumo 2 DML para todo el lote, se usaron ' + dmlUsed
    );
  }

  private static void invokeEndpoint(String requestBody) {
    RestRequest request = new RestRequest();
    request.requestUri = '/services/apexrest/collections/v1/inbound-payments';
    request.httpMethod = 'POST';
    if (requestBody != null) {
      request.requestBody = Blob.valueOf(requestBody);
    }

    RestContext.request = request;
    RestContext.response = new RestResponse();

    InboundInsurancePaymentRestResource.receive();
  }

  private static Map<String, Object> getResponseBody() {
    return (Map<String, Object>) JSON.deserializeUntyped(
      RestContext.response.responseBody.toString()
    );
  }

  private static Integer toInteger(Object value) {
    return value == null
      ? 0
      : Decimal.valueOf(String.valueOf(value)).intValue();
  }
}
