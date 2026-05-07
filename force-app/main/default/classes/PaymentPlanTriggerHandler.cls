/**
 *   @name: PaymentPlanTriggerHandler
 *   @version: 1.0
 *   @creation date: 23/04/2026
 *   @author: Javier Torres - Volestra
 *   @description: Genera cuotas de PaymentPlan cuando un plan activo cuenta con
 *                 la informacion necesaria para construir su calendario.
 */
public with sharing class PaymentPlanTriggerHandler {
  private static final String PLAN_STATUS_ACTIVE = 'Activo';
  private static final String INSTALLMENT_STATUS_PENDING = 'Pendiente';

  private static final String FREQUENCY_MONTHLY = 'Mensual';
  private static final String FREQUENCY_QUARTERLY = 'Trimestral';
  private static final String FREQUENCY_BIANNUAL = 'Semestral';
  private static final String FREQUENCY_ANNUAL = 'Anual';
  private static final String FREQUENCY_SINGLE = 'Unico';

  private static Set<Id> processedPlanIds = new Set<Id>();

  /**
   * @creation date: 23/04/2026
   * @author: Javier Torres - Volestra
   * @description: Procesa planes despues del insert/update y crea cuotas faltantes
   *               cuando el plan ya esta listo.
   * @param newPlans: Registros nuevos del trigger.
   * @param oldMap: Valores anteriores de los planes.
   * @return:
   * @exception:
   * @throws:
   */
  public static void handleAfterTrigger(
    List<PaymentPlan__c> newPlans,
    Map<Id, PaymentPlan__c> oldMap
  ) {
    if (newPlans == null || newPlans.isEmpty()) {
      return;
    }

    Map<Id, PaymentPlan__c> readyPlansById = new Map<Id, PaymentPlan__c>();

    for (PaymentPlan__c plan : newPlans) {
      if (
        plan == null ||
        plan.Id == null ||
        processedPlanIds.contains(plan.Id)
      ) {
        continue;
      }

      PaymentPlan__c oldPlan = oldMap == null ? null : oldMap.get(plan.Id);

      if (shouldGenerateInstallments(plan, oldPlan)) {
        readyPlansById.put(plan.Id, plan);
        processedPlanIds.add(plan.Id);
      }
    }

    if (!readyPlansById.isEmpty()) {
      createMissingInstallments(readyPlansById);
    }
  }

  /**
   * @creation date: 23/04/2026
   * @author: Javier Torres - Volestra
   * @description: Indica si el plan esta listo ahora y antes no lo estaba.
   * @param plan: Plan nuevo.
   * @param oldPlan: Plan anterior.
   * @return: Boolean Indica si se deben generar cuotas.
   * @exception:
   * @throws:
   */
  private static Boolean shouldGenerateInstallments(
    PaymentPlan__c plan,
    PaymentPlan__c oldPlan
  ) {
    Boolean isReadyNow = isReadyForInstallments(plan);

    if (!isReadyNow) {
      return false;
    }

    return oldPlan == null || !isReadyForInstallments(oldPlan);
  }

  /**
   * @creation date: 23/04/2026
   * @author: Javier Torres - Volestra
   * @description: Valida si el plan tiene la informacion minima para generar cuotas.
   * @param plan: Plan a validar.
   * @return: Boolean Resultado de la validacion.
   * @exception:
   * @throws:
   */
  private static Boolean isReadyForInstallments(PaymentPlan__c plan) {
    return plan != null &&
      plan.planStatus__c == PLAN_STATUS_ACTIVE &&
      String.isNotBlank(plan.premiumFrequency__c) &&
      plan.expectedTotalAmount__c != null &&
      plan.expectedTotalAmount__c > 0 &&
      plan.firstDueDate__c != null &&
      plan.installmentCount__c != null &&
      plan.installmentCount__c > 0 &&
      getMonthsBetweenInstallments(plan.premiumFrequency__c) != null;
  }

  /**
   * @creation date: 23/04/2026
   * @author: Javier Torres - Volestra
   * @description: Crea cuotas solo para planes que aun no tienen calendario valido.
   * @param readyPlansById: Planes listos para calendarizar.
   * @return:
   * @exception:
   * @throws:
   */
  private static void createMissingInstallments(
    Map<Id, PaymentPlan__c> readyPlansById
  ) {
    Set<Id> planIdsWithInstallments = new Set<Id>();

    for (AggregateResult result : [
      SELECT paymentPlan__c planId
      FROM PaymentPlanInstallment__c
      WHERE paymentPlan__c IN :readyPlansById.keySet()
      GROUP BY paymentPlan__c
    ]) {
      planIdsWithInstallments.add((Id) result.get('planId'));
    }

    List<PaymentPlanInstallment__c> installmentsToInsert = new List<PaymentPlanInstallment__c>();

    for (PaymentPlan__c plan : readyPlansById.values()) {
      if (planIdsWithInstallments.contains(plan.Id)) {
        continue;
      }

      installmentsToInsert.addAll(buildInstallments(plan));
    }

    if (installmentsToInsert.isEmpty()) {
      return;
    }

    Database.SaveResult[] results = Database.insert(
      installmentsToInsert,
      false
    );
    logInsertErrors(installmentsToInsert, results);
  }

  /**
   * @creation date: 23/04/2026
   * @author: Javier Torres - Volestra
   * @description: Construye el calendario de cuotas para un plan especifico.
   * @param plan: Plan origen.
   * @return: List<PaymentPlanInstallment__c> Cuotas generadas.
   * @exception:
   * @throws:
   */
  private static List<PaymentPlanInstallment__c> buildInstallments(
    PaymentPlan__c plan
  ) {
    Integer installmentCount = plan.installmentCount__c.intValue();
    Integer monthsBetweenInstallments = getMonthsBetweenInstallments(
      plan.premiumFrequency__c
    );
    Decimal assignedAmount = 0;
    List<PaymentPlanInstallment__c> installments = new List<PaymentPlanInstallment__c>();

    for (Integer sequence = 1; sequence <= installmentCount; sequence++) {
      Boolean isLastInstallment = sequence == installmentCount;
      Date dueDate = plan.firstDueDate__c.addMonths(
        monthsBetweenInstallments * (sequence - 1)
      );
      Date periodEndDate = plan.firstDueDate__c
        .addMonths(monthsBetweenInstallments * sequence)
        .addDays(-1);
      Decimal expectedAmount = isLastInstallment
        ? (plan.expectedTotalAmount__c - assignedAmount).setScale(2)
        : calculateRegularInstallmentAmount(
            plan.expectedTotalAmount__c,
            installmentCount
          );

      assignedAmount += expectedAmount;

      installments.add(
        new PaymentPlanInstallment__c(
          paymentPlan__c = plan.Id,
          sequenceNumber__c = sequence,
          dueDate__c = dueDate,
          expectedAmount__c = expectedAmount,
          installmentStatus__c = INSTALLMENT_STATUS_PENDING,
          periodStartDate__c = dueDate,
          periodEndDate__c = periodEndDate
        )
      );
    }

    return installments;
  }

  /**
   * @creation date: 23/04/2026
   * @author: Javier Torres - Volestra
   * @description: Calcula el monto repetido de las cuotas dejando el redondeo para la ultima.
   * @param expectedTotalAmount: Monto total esperado.
   * @param installmentCount: Cantidad de cuotas.
   * @return: Decimal Monto regular de cuota.
   * @exception:
   * @throws:
   */
  private static Decimal calculateRegularInstallmentAmount(
    Decimal expectedTotalAmount,
    Integer installmentCount
  ) {
    return (expectedTotalAmount / installmentCount)
      .setScale(2, RoundingMode.HALF_UP);
  }

  /**
   * @creation date: 23/04/2026
   * @author: Javier Torres - Volestra
   * @description: Mapea la frecuencia del plan al incremento en meses del calendario.
   * @param premiumFrequency: Frecuencia de prima.
   * @return: Integer Incremento en meses.
   * @exception:
   * @throws:
   */
  private static Integer getMonthsBetweenInstallments(String premiumFrequency) {
    if (premiumFrequency == FREQUENCY_MONTHLY) {
      return 1;
    }

    if (premiumFrequency == FREQUENCY_QUARTERLY) {
      return 3;
    }

    if (premiumFrequency == FREQUENCY_BIANNUAL) {
      return 6;
    }

    if (
      premiumFrequency == FREQUENCY_ANNUAL ||
      premiumFrequency == FREQUENCY_SINGLE
    ) {
      return 12;
    }

    return null;
  }

  /**
   * @creation date: 23/04/2026
   * @author: Javier Torres - Volestra
   * @description: Registra errores de insercion por fila sin detener la transaccion.
   * @param installments: Cuotas intentadas.
   * @param results: Resultados del insert.
   * @return:
   * @exception:
   * @throws:
   */
  private static void logInsertErrors(
    List<PaymentPlanInstallment__c> installments,
    Database.SaveResult[] results
  ) {
    for (Integer i = 0; i < results.size(); i++) {
      if (results[i].isSuccess()) {
        continue;
      }

      for (Database.Error error : results[i].getErrors()) {
        System.debug(
          LoggingLevel.ERROR,
          'Error al crear cuota para plan ' +
            installments[i].paymentPlan__c +
            ': ' +
            error.getMessage()
        );
      }
    }
  }
}
