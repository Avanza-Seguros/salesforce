public with sharing class InsurancePolicyTriggerHandler {
    private static final Set<String> OPERATIONAL_POLICY_STATUSES = new Set<String>{
        'Inicial',
        'Vigente'
    };

    private static final String INITIAL_PLAN_EVENT = 'INITIAL_PAYMENT_PLAN';

    private static final String PLAN_TYPE_INITIAL = 'Inicial';
    private static final String PLAN_STATUS_ACTIVE = 'Activo';
    private static final String PLAN_STATUS_DRAFT = 'Borrador';
    private static final Set<String> OPEN_INITIAL_PLAN_STATUSES = new Set<String>{
        PLAN_STATUS_ACTIVE,
        PLAN_STATUS_DRAFT
    };

    private static final String FREQUENCY_MONTHLY = 'Mensual';
    private static final String FREQUENCY_QUARTERLY = 'Trimestral';
    private static final String FREQUENCY_BIANNUAL = 'Semestral';
    private static final String FREQUENCY_ANNUAL = 'Anual';
    private static final String FREQUENCY_SINGLE = 'Unico';
    private static final Set<String> SUPPORTED_PREMIUM_FREQUENCIES = new Set<String>{
        FREQUENCY_MONTHLY,
        FREQUENCY_QUARTERLY,
        FREQUENCY_BIANNUAL,
        FREQUENCY_ANNUAL,
        FREQUENCY_SINGLE
    };

    private static Set<Id> processedPolicyIds = new Set<Id>();

    public static void handleBeforeTrigger(List<InsurancePolicy> newPolicies, Map<Id, InsurancePolicy> oldMap) {
        PaymentPlanFrequencyChangeService.validateBeforeUpdate(newPolicies, oldMap);
    }

    public static void handleAfterTrigger(List<InsurancePolicy> newPolicies, Map<Id, InsurancePolicy> oldMap) {
        if (newPolicies == null || newPolicies.isEmpty()) {
            return;
        }

        List<InsurancePolicy> policiesToProcess = new List<InsurancePolicy>();

        for (InsurancePolicy policy : newPolicies) {
            if (policy == null || policy.Id == null || processedPolicyIds.contains(policy.Id)) {
                continue;
            }

            InsurancePolicy oldPolicy = oldMap == null ? null : oldMap.get(policy.Id);

            if (shouldCreateInitialPlan(policy, oldPolicy)) {
                policiesToProcess.add(policy);
                processedPolicyIds.add(policy.Id);
            }
        }

        if (!policiesToProcess.isEmpty()) {
            upsertInitialPlans(policiesToProcess);
        }

        PaymentPlanFrequencyChangeService.processAfterUpdate(newPolicies, oldMap);
    }

    public static void handleIsAfterTrigger(List<InsurancePolicy> newPolicies, Map<Id, InsurancePolicy> oldMap) {
        handleAfterTrigger(newPolicies, oldMap);
    }

    private static Boolean shouldCreateInitialPlan(InsurancePolicy policy, InsurancePolicy oldPolicy) {
        Boolean isOperationalNow = isValidForOperation(policy);
        Boolean wasOperationalBefore = oldPolicy != null && isValidForOperation(oldPolicy);

        return isOperationalNow && !wasOperationalBefore;
    }

    private static Boolean isValidForOperation(InsurancePolicy policy) {
        return policy != null && OPERATIONAL_POLICY_STATUSES.contains(policy.Status);
    }

    private static void upsertInitialPlans(List<InsurancePolicy> policies) {
        Set<Id> policyIds = new Set<Id>();
        Set<String> initialPlanKeys = new Set<String>();

        for (InsurancePolicy policy : policies) {
            policyIds.add(policy.Id);
            initialPlanKeys.add(buildInitialPlanKey(policy.Id));
        }

        Map<String, PaymentPlan__c> existingByKey = new Map<String, PaymentPlan__c>();
        Map<Id, PaymentPlan__c> existingByPolicy = new Map<Id, PaymentPlan__c>();

        for (PaymentPlan__c plan : [
            SELECT Id, insurancePolicy__c, initialPlanKey__c
            FROM PaymentPlan__c
            WHERE initialPlanKey__c IN :initialPlanKeys
                OR (
                    insurancePolicy__c IN :policyIds
                    AND planType__c = :PLAN_TYPE_INITIAL
                    AND planStatus__c IN :OPEN_INITIAL_PLAN_STATUSES
                )
        ]) {
            if (String.isNotBlank(plan.initialPlanKey__c)) {
                existingByKey.put(plan.initialPlanKey__c, plan);
            }

            if (plan.insurancePolicy__c != null && !existingByPolicy.containsKey(plan.insurancePolicy__c)) {
                existingByPolicy.put(plan.insurancePolicy__c, plan);
            }
        }

        List<PaymentPlan__c> plansToUpsert = new List<PaymentPlan__c>();

        for (InsurancePolicy policy : policies) {
            String initialPlanKey = buildInitialPlanKey(policy.Id);
            PaymentPlan__c plan = existingByKey.containsKey(initialPlanKey)
                ? existingByKey.get(initialPlanKey)
                : existingByPolicy.get(policy.Id);

            if (plan == null) {
                plan = new PaymentPlan__c();
            }

            populateInitialPlan(plan, policy, initialPlanKey);
            plansToUpsert.add(plan);
        }

        if (plansToUpsert.isEmpty()) {
            return;
        }

        Database.UpsertResult[] results = Database.upsert(
            plansToUpsert,
            PaymentPlan__c.Fields.initialPlanKey__c,
            false
        );

        logUpsertErrors(plansToUpsert, results);
    }

    private static void populateInitialPlan(PaymentPlan__c plan, InsurancePolicy policy, String initialPlanKey) {
        String premiumFrequency = getSupportedPremiumFrequency(policy);
        Decimal expectedTotalAmount = deriveExpectedTotalAmount(policy);
        Date firstDueDate = getDate(policy, 'PaymentDueDate');
        Integer installmentCount = deriveInstallmentCount(premiumFrequency);
        Boolean isComplete = expectedTotalAmount != null
            && String.isNotBlank(premiumFrequency)
            && firstDueDate != null
            && installmentCount != null;

        plan.initialPlanKey__c = initialPlanKey;
        plan.insurancePolicy__c = policy.Id;
        plan.planType__c = PLAN_TYPE_INITIAL;
        plan.planStatus__c = isComplete ? PLAN_STATUS_ACTIVE : PLAN_STATUS_DRAFT;
        plan.premiumFrequency__c = premiumFrequency;
        plan.expectedTotalAmount__c = expectedTotalAmount;
        plan.firstDueDate__c = firstDueDate;
        plan.installmentCount__c = installmentCount;

        if (!isComplete) {
            logWarning('PaymentPlan creado en borrador para poliza ' + policy.Id + ': ' + getMissingDataSummary(
                expectedTotalAmount,
                premiumFrequency,
                firstDueDate,
                installmentCount
            ));
        }
    }

    private static Decimal deriveExpectedTotalAmount(InsurancePolicy policy) {
        return nullIfZero(getDecimal(policy, 'PremiumAmount'));
    }

    private static String getSupportedPremiumFrequency(InsurancePolicy policy) {
        String policyFrequency = getString(policy, 'PremiumFrequency');
        return SUPPORTED_PREMIUM_FREQUENCIES.contains(policyFrequency) ? policyFrequency : null;
    }

    private static Integer deriveInstallmentCount(String premiumFrequency) {
        if (premiumFrequency == FREQUENCY_MONTHLY) {
            return 12;
        }

        if (premiumFrequency == FREQUENCY_QUARTERLY) {
            return 4;
        }

        if (premiumFrequency == FREQUENCY_BIANNUAL) {
            return 2;
        }

        if (premiumFrequency == FREQUENCY_ANNUAL || premiumFrequency == FREQUENCY_SINGLE) {
            return 1;
        }

        return null;
    }

    private static String buildInitialPlanKey(Id policyId) {
        return String.valueOf(policyId) + ':' + INITIAL_PLAN_EVENT;
    }

    private static String getMissingDataSummary(
        Decimal expectedTotalAmount,
        String premiumFrequency,
        Date firstDueDate,
        Integer installmentCount
    ) {
        List<String> missing = new List<String>();

        if (expectedTotalAmount == null) {
            missing.add('expectedTotalAmount__c');
        }

        if (String.isBlank(premiumFrequency)) {
            missing.add('premiumFrequency__c');
        }

        if (firstDueDate == null) {
            missing.add('firstDueDate__c');
        }

        if (installmentCount == null) {
            missing.add('installmentCount__c');
        }

        return String.join(missing, ', ');
    }

    private static Decimal nullIfZero(Decimal value) {
        return value == null || value == 0 ? null : value;
    }

    private static Decimal getDecimal(SObject record, String fieldApiName) {
        Object value = getValue(record, fieldApiName);
        if (value == null) {
            return null;
        }

        if (value instanceof Decimal) {
            return (Decimal) value;
        }

        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            logWarning('No se pudo convertir ' + fieldApiName + ' a Decimal: ' + String.valueOf(value));
            return null;
        }
    }

    private static Date getDate(SObject record, String fieldApiName) {
        Object value = getValue(record, fieldApiName);
        if (value == null) {
            return null;
        }

        if (value instanceof Date) {
            return (Date) value;
        }

        try {
            return Date.valueOf(String.valueOf(value));
        } catch (Exception e) {
            logWarning('No se pudo convertir ' + fieldApiName + ' a Date: ' + String.valueOf(value));
            return null;
        }
    }

    private static String getString(SObject record, String fieldApiName) {
        Object value = getValue(record, fieldApiName);
        return value == null ? null : String.valueOf(value);
    }

    private static Object getValue(SObject record, String fieldApiName) {
        if (record == null || String.isBlank(fieldApiName)) {
            return null;
        }

        try {
            return record.get(fieldApiName);
        } catch (Exception e) {
            logWarning('No se pudo leer ' + fieldApiName + ': ' + e.getMessage());
            return null;
        }
    }

    private static void logUpsertErrors(List<PaymentPlan__c> plans, Database.UpsertResult[] results) {
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                continue;
            }

            for (Database.Error error : results[i].getErrors()) {
                logError(
                    'Error al guardar PaymentPlan para poliza ' +
                    plans[i].insurancePolicy__c +
                    ': ' +
                    error.getMessage()
                );
            }
        }
    }

    private static void logWarning(String message) {
        System.debug(LoggingLevel.WARN, message);
    }

    private static void logError(String message) {
        System.debug(LoggingLevel.ERROR, message);
    }
}
