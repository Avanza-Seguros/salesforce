/**
 *   @name: PaymentPlanTriggerHandlerTest
 *   @version: 1.0
 *   @creation date: 23/04/2026
 *   @author: Javier Torres - Volestra
 *   @description: Valida la generacion de cuotas para planes activos y borrador.
 */
@IsTest
private class PaymentPlanTriggerHandlerTest {
  /**
   * @creation date: 23/04/2026
   * @author: Javier Torres - Volestra
   * @description: Crea la cuenta asegurada compartida usada por todos los tests de la clase.
   * @param:
   * @return:
   * @exception:
   * @throws:
   */
  @TestSetup
  static void setupData() {
    CollectionsTestDataFactory.createInsuredAccount();
  }

  /**
   * @creation date: 23/04/2026
   * @author: Javier Torres - Volestra
   * @description: Verifica que un plan mensual activo cree doce cuotas con el calendario esperado.
   * @param:
   * @return:
   * @exception:
   * @throws:
   */
  @IsTest
  static void createsMonthlyInstallmentsWhenActivePlanIsInserted() {
    InsurancePolicy policy = CollectionsTestDataFactory.createPolicy(
      CollectionsTestDataFactory.getDefaultInsuredAccountId(),
      'Cancelado'
    );
    Date firstDueDate = Date.newInstance(2026, 5, 15);

    Test.startTest();
    insert CollectionsTestDataFactory.buildPlan(
      policy.Id,
      'Activo',
      'Mensual',
      1200,
      firstDueDate,
      12
    );
    Test.stopTest();

    List<PaymentPlanInstallment__c> installments = CollectionsTestDataFactory.getInstallmentsByPolicy(
      policy.Id
    );

    Assert.areEqual(12, installments.size());
    Assert.areEqual(1, installments[0].sequenceNumber__c);
    Assert.areEqual(firstDueDate, installments[0].dueDate__c);
    Assert.areEqual(firstDueDate, installments[0].periodStartDate__c);
    Assert.areEqual(
      firstDueDate.addMonths(1).addDays(-1),
      installments[0].periodEndDate__c
    );
    Assert.areEqual('Pendiente', installments[0].installmentStatus__c);
    Assert.areEqual(
      Decimal.valueOf('100.00'),
      installments[0].expectedAmount__c
    );
    Assert.areEqual(12, installments[11].sequenceNumber__c);
    Assert.areEqual(firstDueDate.addMonths(11), installments[11].dueDate__c);
    Assert.areEqual(
      Decimal.valueOf('1200.00'),
      CollectionsTestDataFactory.sumExpectedAmounts(installments)
    );
  }

  /**
   * @creation date: 23/04/2026
   * @author: Javier Torres - Volestra
   * @description: Verifica que un plan de pago unico cree solo una cuota.
   * @param:
   * @return:
   * @exception:
   * @throws:
   */
  @IsTest
  static void createsSingleInstallmentForUniquePaymentPlan() {
    InsurancePolicy policy = CollectionsTestDataFactory.createPolicy(
      CollectionsTestDataFactory.getDefaultInsuredAccountId(),
      'Cancelado'
    );
    Date firstDueDate = Date.newInstance(2026, 6, 1);

    Test.startTest();
    insert CollectionsTestDataFactory.buildPlan(
      policy.Id,
      'Activo',
      'Unico',
      900,
      firstDueDate,
      1
    );
    Test.stopTest();

    List<PaymentPlanInstallment__c> installments = CollectionsTestDataFactory.getInstallmentsByPolicy(
      policy.Id
    );

    Assert.areEqual(1, installments.size());
    Assert.areEqual(1, installments[0].sequenceNumber__c);
    Assert.areEqual(firstDueDate, installments[0].dueDate__c);
    Assert.areEqual(firstDueDate, installments[0].periodStartDate__c);
    Assert.areEqual(
      firstDueDate.addMonths(12).addDays(-1),
      installments[0].periodEndDate__c
    );
    Assert.areEqual(
      Decimal.valueOf('900.00'),
      installments[0].expectedAmount__c
    );
  }

  /**
   * @creation date: 23/04/2026
   * @author: Javier Torres - Volestra
   * @description: Verifica que las diferencias de redondeo se absorban en la ultima cuota.
   * @param:
   * @return:
   * @exception:
   * @throws:
   */
  @IsTest
  static void usesLastInstallmentToAbsorbRoundingDifference() {
    InsurancePolicy policy = CollectionsTestDataFactory.createPolicy(
      CollectionsTestDataFactory.getDefaultInsuredAccountId(),
      'Cancelado'
    );

    Test.startTest();
    insert CollectionsTestDataFactory.buildPlan(
      policy.Id,
      'Activo',
      'Mensual',
      100,
      Date.newInstance(2026, 7, 10),
      3
    );
    Test.stopTest();

    List<PaymentPlanInstallment__c> installments = CollectionsTestDataFactory.getInstallmentsByPolicy(
      policy.Id
    );

    Assert.areEqual(3, installments.size());
    Assert.areEqual(
      Decimal.valueOf('33.33'),
      installments[0].expectedAmount__c
    );
    Assert.areEqual(
      Decimal.valueOf('33.33'),
      installments[1].expectedAmount__c
    );
    Assert.areEqual(
      Decimal.valueOf('33.34'),
      installments[2].expectedAmount__c
    );
    Assert.areEqual(
      Decimal.valueOf('100.00'),
      CollectionsTestDataFactory.sumExpectedAmounts(installments)
    );
  }

  /**
   * @creation date: 23/04/2026
   * @author: Javier Torres - Volestra
   * @description: Verifica que un plan en borrador genere cuotas cuando luego pasa a Activo.
   * @param:
   * @return:
   * @exception:
   * @throws:
   */
  @IsTest
  static void generatesInstallmentsWhenDraftPlanBecomesActive() {
    InsurancePolicy policy = CollectionsTestDataFactory.createPolicy(
      CollectionsTestDataFactory.getDefaultInsuredAccountId(),
      'Cancelado'
    );
    PaymentPlan__c plan = CollectionsTestDataFactory.buildPlan(
      policy.Id,
      'Borrador',
      'Trimestral',
      800,
      Date.newInstance(2026, 8, 20),
      4
    );
    insert plan;

    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM PaymentPlanInstallment__c
        WHERE paymentPlan__c = :plan.Id
      ]
    );

    Test.startTest();
    plan.planStatus__c = 'Activo';
    update plan;
    Test.stopTest();

    List<PaymentPlanInstallment__c> installments = [
      SELECT sequenceNumber__c, dueDate__c, expectedAmount__c
      FROM PaymentPlanInstallment__c
      WHERE paymentPlan__c = :plan.Id
      ORDER BY sequenceNumber__c
    ];

    Assert.areEqual(4, installments.size());
    Assert.areEqual(Date.newInstance(2026, 8, 20), installments[0].dueDate__c);
    Assert.areEqual(Date.newInstance(2026, 11, 20), installments[1].dueDate__c);
    Assert.areEqual(
      Decimal.valueOf('800.00'),
      CollectionsTestDataFactory.sumExpectedAmounts(installments)
    );
  }

  /**
   * @creation date: 23/04/2026
   * @author: Javier Torres - Volestra
   * @description: Verifica que una actualizacion posterior de un plan activo no duplique cuotas.
   * @param:
   * @return:
   * @exception:
   * @throws:
   */
  @IsTest
  static void doesNotDuplicateInstallmentsWhenActivePlanIsUpdated() {
    InsurancePolicy policy = CollectionsTestDataFactory.createPolicy(
      CollectionsTestDataFactory.getDefaultInsuredAccountId(),
      'Cancelado'
    );
    PaymentPlan__c plan = CollectionsTestDataFactory.buildPlan(
      policy.Id,
      'Activo',
      'Semestral',
      1000,
      Date.newInstance(2026, 9, 5),
      2
    );
    insert plan;

    Test.startTest();
    plan.planType__c = 'Inicial';
    update plan;
    Test.stopTest();

    Assert.areEqual(
      2,
      [
        SELECT COUNT()
        FROM PaymentPlanInstallment__c
        WHERE paymentPlan__c = :plan.Id
      ]
    );
  }
}
