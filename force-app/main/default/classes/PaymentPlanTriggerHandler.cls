public with sharing class PaymentPlanTriggerHandler {
    private static final String PLAN_STATUS_ACTIVE = 'Activo';
    private static final String INSTALLMENT_STATUS_PENDING = 'Pendiente';

    private static final String FREQUENCY_MONTHLY = 'Mensual';
    private static final String FREQUENCY_QUARTERLY = 'Trimestral';
    private static final String FREQUENCY_BIANNUAL = 'Semestral';
    private static final String FREQUENCY_ANNUAL = 'Anual';
    private static final String FREQUENCY_SINGLE = 'Unico';

    private static Set<Id> processedPlanIds = new Set<Id>();

    public static void handleAfterTrigger(List<PaymentPlan__c> newPlans, Map<Id, PaymentPlan__c> oldMap) {
        if (newPlans == null || newPlans.isEmpty()) {
            return;
        }

        Map<Id, PaymentPlan__c> readyPlansById = new Map<Id, PaymentPlan__c>();

        for (PaymentPlan__c plan : newPlans) {
            if (plan == null || plan.Id == null || processedPlanIds.contains(plan.Id)) {
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

    private static Boolean shouldGenerateInstallments(PaymentPlan__c plan, PaymentPlan__c oldPlan) {
        Boolean isReadyNow = isReadyForInstallments(plan);

        if (!isReadyNow) {
            return false;
        }

        return oldPlan == null || !isReadyForInstallments(oldPlan);
    }

    private static Boolean isReadyForInstallments(PaymentPlan__c plan) {
        return plan != null
            && plan.planStatus__c == PLAN_STATUS_ACTIVE
            && String.isNotBlank(plan.premiumFrequency__c)
            && plan.expectedTotalAmount__c != null
            && plan.expectedTotalAmount__c > 0
            && plan.firstDueDate__c != null
            && plan.installmentCount__c != null
            && plan.installmentCount__c > 0
            && getMonthsBetweenInstallments(plan.premiumFrequency__c) != null;
    }

    private static void createMissingInstallments(Map<Id, PaymentPlan__c> readyPlansById) {
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

        Database.SaveResult[] results = Database.insert(installmentsToInsert, false);
        logInsertErrors(installmentsToInsert, results);
    }

    private static List<PaymentPlanInstallment__c> buildInstallments(PaymentPlan__c plan) {
        Integer installmentCount = plan.installmentCount__c.intValue();
        Integer monthsBetweenInstallments = getMonthsBetweenInstallments(plan.premiumFrequency__c);
        Decimal assignedAmount = 0;
        List<PaymentPlanInstallment__c> installments = new List<PaymentPlanInstallment__c>();

        for (Integer sequence = 1; sequence <= installmentCount; sequence++) {
            Boolean isLastInstallment = sequence == installmentCount;
            Date dueDate = plan.firstDueDate__c.addMonths(monthsBetweenInstallments * (sequence - 1));
            Date nextDueDate = isLastInstallment
                ? null
                : plan.firstDueDate__c.addMonths(monthsBetweenInstallments * sequence);
            Decimal expectedAmount = isLastInstallment
                ? (plan.expectedTotalAmount__c - assignedAmount).setScale(2)
                : calculateRegularInstallmentAmount(plan.expectedTotalAmount__c, installmentCount);

            assignedAmount += expectedAmount;

            installments.add(new PaymentPlanInstallment__c(
                paymentPlan__c = plan.Id,
                sequenceNumber__c = sequence,
                dueDate__c = dueDate,
                expectedAmount__c = expectedAmount,
                installmentStatus__c = INSTALLMENT_STATUS_PENDING,
                periodStartDate__c = dueDate,
                periodEndDate__c = nextDueDate == null ? dueDate : nextDueDate.addDays(-1)
            ));
        }

        return installments;
    }

    private static Decimal calculateRegularInstallmentAmount(Decimal expectedTotalAmount, Integer installmentCount) {
        return (expectedTotalAmount / installmentCount).setScale(2, RoundingMode.HALF_UP);
    }

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

        if (premiumFrequency == FREQUENCY_ANNUAL || premiumFrequency == FREQUENCY_SINGLE) {
            return 12;
        }

        return null;
    }

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
