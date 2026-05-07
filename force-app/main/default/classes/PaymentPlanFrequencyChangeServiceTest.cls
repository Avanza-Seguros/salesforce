@IsTest
private class PaymentPlanFrequencyChangeServiceTest {
  @IsTest
  static void replacesSemiannualPlanWithMonthlyPlanForPendingBalance() {
    Account insured = createInsuredAccount();
    Date firstDueDate = Date.today().addMonths(-6);
    InsurancePolicy policy = createOperationalPolicy(
      insured.Id,
      'Semestral',
      1200,
      firstDueDate
    );
    PaymentPlan__c originalPlan = getActivePlan(policy.Id);
    List<PaymentPlanInstallment__c> originalInstallments = getInstallments(
      originalPlan.Id
    );
    originalInstallments[0].installmentStatus__c = 'Conciliado';
    update originalInstallments[0];

    Test.startTest();
    policy.PremiumFrequency = 'Mensual';
    update policy;
    Test.stopTest();

    PaymentPlan__c replacedPlan = [
      SELECT planStatus__c, replacedOn__c
      FROM PaymentPlan__c
      WHERE Id = :originalPlan.Id
    ];
    PaymentPlan__c replacementPlan = [
      SELECT
        previousPlan__c,
        planType__c,
        planStatus__c,
        premiumFrequency__c,
        expectedTotalAmount__c,
        firstDueDate__c,
        effectiveFromDate__c,
        replacementReason__c,
        installmentCount__c
      FROM PaymentPlan__c
      WHERE
        insurancePolicy__c = :policy.Id
        AND previousPlan__c = :originalPlan.Id
      LIMIT 1
    ];
    List<PaymentPlanInstallment__c> replacementInstallments = getInstallments(
      replacementPlan.Id
    );
    List<PaymentPlanInstallment__c> oldInstallments = getInstallments(
      originalPlan.Id
    );

    Assert.areEqual('Reemplazado', replacedPlan.planStatus__c);
    Assert.areEqual(Date.today(), replacedPlan.replacedOn__c);
    Assert.areEqual('Conciliado', oldInstallments[0].installmentStatus__c);
    Assert.areEqual('Cancelado', oldInstallments[1].installmentStatus__c);
    Assert.areEqual(originalPlan.Id, replacementPlan.previousPlan__c);
    Assert.areEqual('Cambio de frecuencia', replacementPlan.planType__c);
    Assert.areEqual('Activo', replacementPlan.planStatus__c);
    Assert.areEqual('Mensual', replacementPlan.premiumFrequency__c);
    Assert.areEqual(
      Decimal.valueOf('600.00'),
      replacementPlan.expectedTotalAmount__c
    );
    Assert.areEqual(Date.today(), replacementPlan.firstDueDate__c);
    Assert.areEqual(Date.today(), replacementPlan.effectiveFromDate__c);
    Assert.areEqual(
      'Cambio de frecuencia',
      replacementPlan.replacementReason__c
    );
    Assert.areEqual(6, replacementPlan.installmentCount__c);
    Assert.areEqual(6, replacementInstallments.size());
    Assert.areEqual(Date.today(), replacementInstallments[0].dueDate__c);
    Assert.areEqual(
      Date.today().addMonths(5),
      replacementInstallments[5].dueDate__c
    );
    Assert.areEqual(
      Decimal.valueOf('600.00'),
      sumExpectedAmounts(replacementInstallments)
    );
  }

  @IsTest
  static void doesNotAllowFrequencyChangeBeforeNextPendingDueDate() {
    Account insured = createInsuredAccount();
    Date firstDueDate = Date.today().addMonths(-4);
    InsurancePolicy policy = createOperationalPolicy(
      insured.Id,
      'Semestral',
      1200,
      firstDueDate
    );
    PaymentPlan__c originalPlan = getActivePlan(policy.Id);
    List<PaymentPlanInstallment__c> originalInstallments = getInstallments(
      originalPlan.Id
    );
    originalInstallments[0].installmentStatus__c = 'Conciliado';
    update originalInstallments[0];

    Test.startTest();
    policy.PremiumFrequency = 'Mensual';
    Boolean threwException = false;

    try {
      update policy;
    } catch (DmlException e) {
      threwException = true;
      Assert.isTrue(
        e.getMessage().contains('proxima fecha de cobro pendiente')
      );
    }

    Test.stopTest();

    Assert.isTrue(threwException);
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM PaymentPlan__c WHERE insurancePolicy__c = :policy.Id]
    );
  }

  @IsTest
  static void doesNotAllowFrequencyChangeWhenPlanHasNoPendingBalance() {
    Account insured = createInsuredAccount();
    Date firstDueDate = Date.today().addMonths(-6);
    InsurancePolicy policy = createOperationalPolicy(
      insured.Id,
      'Semestral',
      1200,
      firstDueDate
    );
    PaymentPlan__c originalPlan = getActivePlan(policy.Id);
    List<PaymentPlanInstallment__c> originalInstallments = getInstallments(
      originalPlan.Id
    );

    for (PaymentPlanInstallment__c installment : originalInstallments) {
      installment.installmentStatus__c = 'Conciliado';
    }

    update originalInstallments;

    Test.startTest();
    policy.PremiumFrequency = 'Mensual';
    Boolean threwException = false;

    try {
      update policy;
    } catch (DmlException e) {
      threwException = true;
      Assert.isTrue(e.getMessage().contains('saldo pendiente'));
    }

    Test.stopTest();

    Assert.isTrue(threwException);
    Assert.areEqual('Activo', getActivePlan(policy.Id).planStatus__c);
  }

  @IsTest
  static void doesNotAllowFrequencyChangeWhenNewFrequencyDoesNotFitRemainingTerm() {
    Account insured = createInsuredAccount();
    Date firstDueDate = Date.today().addMonths(-7);
    InsurancePolicy policy = createOperationalPolicy(
      insured.Id,
      'Mensual',
      1200,
      firstDueDate
    );
    PaymentPlan__c originalPlan = getActivePlan(policy.Id);
    List<PaymentPlanInstallment__c> originalInstallments = getInstallments(
      originalPlan.Id
    );

    for (PaymentPlanInstallment__c installment : originalInstallments) {
      if (installment.dueDate__c < Date.today()) {
        installment.installmentStatus__c = 'Conciliado';
      }
    }

    update originalInstallments;

    Test.startTest();
    policy.PremiumFrequency = 'Semestral';
    Boolean threwException = false;

    try {
      update policy;
    } catch (DmlException e) {
      threwException = true;
      Assert.isTrue(e.getMessage().contains('cuota valida'));
    }

    Test.stopTest();

    Assert.isTrue(threwException);
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM PaymentPlan__c WHERE insurancePolicy__c = :policy.Id]
    );
  }

  private static Account createInsuredAccount() {
    Account insured = new Account(Name = 'Test Insured');
    insert insured;
    return insured;
  }

  private static InsurancePolicy createOperationalPolicy(
    Id insuredAccountId,
    String premiumFrequency,
    Decimal premiumAmount,
    Date firstDueDate
  ) {
    InsurancePolicy policy = new InsurancePolicy(
      Name = 'POL-TEST-' +
        String.valueOf(Crypto.getRandomInteger()).replace('-', ''),
      PolicyName = 'Test policy',
      NameInsuredId = insuredAccountId,
      Status = 'Inicial',
      PremiumFrequency = premiumFrequency,
      PremiumAmount = premiumAmount,
      PaymentDueDate = firstDueDate
    );
    insert policy;
    return policy;
  }

  private static PaymentPlan__c getActivePlan(Id policyId) {
    return [
      SELECT Id, planStatus__c
      FROM PaymentPlan__c
      WHERE insurancePolicy__c = :policyId AND planStatus__c = 'Activo'
      LIMIT 1
    ];
  }

  private static List<PaymentPlanInstallment__c> getInstallments(Id planId) {
    return [
      SELECT
        sequenceNumber__c,
        dueDate__c,
        expectedAmount__c,
        installmentStatus__c
      FROM PaymentPlanInstallment__c
      WHERE paymentPlan__c = :planId
      ORDER BY sequenceNumber__c
    ];
  }

  private static Decimal sumExpectedAmounts(
    List<PaymentPlanInstallment__c> installments
  ) {
    Decimal total = 0;

    for (PaymentPlanInstallment__c installment : installments) {
      total += installment.expectedAmount__c == null
        ? 0
        : installment.expectedAmount__c;
    }

    return total.setScale(2);
  }
}
