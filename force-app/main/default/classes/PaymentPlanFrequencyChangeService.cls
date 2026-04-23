public with sharing class PaymentPlanFrequencyChangeService {
    private static final String PLAN_STATUS_ACTIVE = 'Activo';
    private static final String PLAN_STATUS_REPLACED = 'Reemplazado';
    private static final String PLAN_TYPE_FREQUENCY_CHANGE = 'Cambio de frecuencia';
    private static final String PLAN_REPLACEMENT_REASON = 'Cambio de frecuencia';

    private static final String INSTALLMENT_STATUS_PENDING = 'Pendiente';
    private static final String INSTALLMENT_STATUS_OVERDUE = 'Vencido';
    private static final String INSTALLMENT_STATUS_RECONCILED = 'Conciliado';
    private static final String INSTALLMENT_STATUS_CANCELED = 'Cancelado';
    private static final String INSTALLMENT_STATUS_FORGIVEN = 'Condonado';

    private static final String FREQUENCY_MONTHLY = 'Mensual';
    private static final String FREQUENCY_QUARTERLY = 'Trimestral';
    private static final String FREQUENCY_BIANNUAL = 'Semestral';
    private static final String FREQUENCY_ANNUAL = 'Anual';
    private static final String FREQUENCY_SINGLE = 'Unico';

    private static final Set<String> OPERATIONAL_POLICY_STATUSES = new Set<String>{
        'Inicial',
        'Vigente'
    };

    private static final Set<String> SUPPORTED_PREMIUM_FREQUENCIES = new Set<String>{
        FREQUENCY_MONTHLY,
        FREQUENCY_QUARTERLY,
        FREQUENCY_BIANNUAL,
        FREQUENCY_ANNUAL,
        FREQUENCY_SINGLE
    };

    private static final Set<String> INSTALLMENT_STATUSES_TO_CANCEL = new Set<String>{
        INSTALLMENT_STATUS_PENDING,
        INSTALLMENT_STATUS_OVERDUE
    };

    private static final Set<String> CLOSED_INSTALLMENT_STATUSES = new Set<String>{
        INSTALLMENT_STATUS_RECONCILED,
        INSTALLMENT_STATUS_CANCELED,
        INSTALLMENT_STATUS_FORGIVEN
    };

    private static Set<Id> processedPolicyIds = new Set<Id>();

    public static void validateBeforeUpdate(List<InsurancePolicy> newPolicies, Map<Id, InsurancePolicy> oldMap) {
        Map<Id, InsurancePolicy> policiesById = getPoliciesWithFrequencyChange(newPolicies, oldMap);

        if (policiesById.isEmpty()) {
            return;
        }

        Map<Id, FrequencyChangeAssessment> assessmentsByPolicyId = assessChanges(policiesById);

        for (Id policyId : policiesById.keySet()) {
            FrequencyChangeAssessment assessment = assessmentsByPolicyId.get(policyId);

            if (assessment == null || assessment.isValid) {
                continue;
            }

            policiesById.get(policyId).addError(assessment.errorMessage);
        }
    }

    public static void processAfterUpdate(List<InsurancePolicy> newPolicies, Map<Id, InsurancePolicy> oldMap) {
        Map<Id, InsurancePolicy> policiesById = getPoliciesWithFrequencyChange(newPolicies, oldMap);

        if (policiesById.isEmpty()) {
            return;
        }

        for (Id policyId : new List<Id>(policiesById.keySet())) {
            if (processedPolicyIds.contains(policyId)) {
                policiesById.remove(policyId);
                continue;
            }

            processedPolicyIds.add(policyId);
        }

        if (policiesById.isEmpty()) {
            return;
        }

        Map<Id, FrequencyChangeAssessment> assessmentsByPolicyId = assessChanges(policiesById);
        List<PaymentPlan__c> oldPlansToUpdate = new List<PaymentPlan__c>();
        List<PaymentPlanInstallment__c> oldInstallmentsToCancel = new List<PaymentPlanInstallment__c>();
        List<PaymentPlan__c> newPlansToInsert = new List<PaymentPlan__c>();

        for (Id policyId : policiesById.keySet()) {
            FrequencyChangeAssessment assessment = assessmentsByPolicyId.get(policyId);

            if (assessment == null || !assessment.isValid) {
                continue;
            }

            PaymentPlan__c oldPlan = assessment.activePlan;
            oldPlan.planStatus__c = PLAN_STATUS_REPLACED;
            oldPlan.replacedOn__c = Date.today();
            oldPlansToUpdate.add(oldPlan);

            for (PaymentPlanInstallment__c installment : assessment.installmentsToCancel) {
                installment.installmentStatus__c = INSTALLMENT_STATUS_CANCELED;
                oldInstallmentsToCancel.add(installment);
            }

            newPlansToInsert.add(buildReplacementPlan(policiesById.get(policyId), assessment));
        }

        if (!oldPlansToUpdate.isEmpty()) {
            update oldPlansToUpdate;
        }

        if (!oldInstallmentsToCancel.isEmpty()) {
            update oldInstallmentsToCancel;
        }

        if (!newPlansToInsert.isEmpty()) {
            insert newPlansToInsert;
        }
    }

    private static Map<Id, InsurancePolicy> getPoliciesWithFrequencyChange(
        List<InsurancePolicy> newPolicies,
        Map<Id, InsurancePolicy> oldMap
    ) {
        Map<Id, InsurancePolicy> policiesById = new Map<Id, InsurancePolicy>();

        if (newPolicies == null || newPolicies.isEmpty() || oldMap == null) {
            return policiesById;
        }

        for (InsurancePolicy policy : newPolicies) {
            InsurancePolicy oldPolicy = oldMap.get(policy.Id);

            if (policy == null || oldPolicy == null || policy.Id == null) {
                continue;
            }

            if (!isOperational(policy) || !isOperational(oldPolicy)) {
                continue;
            }

            if (policy.PremiumFrequency == oldPolicy.PremiumFrequency) {
                continue;
            }

            policiesById.put(policy.Id, policy);
        }

        return policiesById;
    }

    private static Map<Id, FrequencyChangeAssessment> assessChanges(Map<Id, InsurancePolicy> policiesById) {
        Map<Id, FrequencyChangeAssessment> assessmentsByPolicyId = new Map<Id, FrequencyChangeAssessment>();
        Map<Id, List<PaymentPlan__c>> activePlansByPolicyId = getActivePlansByPolicyId(policiesById.keySet());
        Map<Id, List<PaymentPlanInstallment__c>> installmentsByPlanId = getInstallmentsByPlanId(activePlansByPolicyId);

        for (Id policyId : policiesById.keySet()) {
            InsurancePolicy policy = policiesById.get(policyId);
            List<PaymentPlan__c> activePlans = activePlansByPolicyId.get(policyId);
            FrequencyChangeAssessment assessment = new FrequencyChangeAssessment(policy);
            assessmentsByPolicyId.put(policyId, assessment);

            if (!SUPPORTED_PREMIUM_FREQUENCIES.contains(policy.PremiumFrequency)) {
                assessment.reject('La nueva frecuencia de pago no esta soportada para cobranza.');
                continue;
            }

            if (activePlans == null || activePlans.isEmpty()) {
                assessment.reject('No existe un plan activo para reemplazar.');
                continue;
            }

            if (activePlans.size() > 1) {
                assessment.reject('La poliza tiene mas de un plan activo; no se puede determinar cual reemplazar.');
                continue;
            }

            PaymentPlan__c activePlan = activePlans[0];
            List<PaymentPlanInstallment__c> installments = installmentsByPlanId.get(activePlan.Id);

            assessment.activePlan = activePlan;

            if (activePlan.premiumFrequency__c == policy.PremiumFrequency) {
                assessment.reject('El plan activo ya tiene la frecuencia solicitada.');
                continue;
            }

            if (!SUPPORTED_PREMIUM_FREQUENCIES.contains(activePlan.premiumFrequency__c)) {
                assessment.reject('La frecuencia actual del plan no esta soportada para reemplazo.');
                continue;
            }

            populateInstallmentAssessment(assessment, installments);

            if (!assessment.isValid) {
                continue;
            }

            assessment.replacementInstallmentCount = calculateInstallmentCount(
                policy.PremiumFrequency,
                assessment.firstReplacementDueDate,
                assessment.remainingPeriodEndDate
            );

            if (assessment.replacementInstallmentCount == null || assessment.replacementInstallmentCount <= 0) {
                assessment.reject('La nueva frecuencia no permite generar una cuota valida en la vigencia pendiente.');
                continue;
            }

            assessment.isValid = true;
        }

        return assessmentsByPolicyId;
    }

    private static void populateInstallmentAssessment(
        FrequencyChangeAssessment assessment,
        List<PaymentPlanInstallment__c> installments
    ) {
        if (installments == null || installments.isEmpty()) {
            assessment.reject('El plan activo no tiene cuotas para evaluar el saldo pendiente.');
            return;
        }

        Date remainingPeriodEndDate;

        for (PaymentPlanInstallment__c installment : installments) {
            if (installment.expectedAmount__c == null) {
                continue;
            }

            if (hasPartialPayment(installment)) {
                assessment.reject('Existen cuotas con pago parcial; el cambio de frecuencia requiere revision manual.');
                return;
            }

            if (INSTALLMENT_STATUSES_TO_CANCEL.contains(installment.installmentStatus__c)) {
                assessment.installmentsToCancel.add(installment);
                assessment.pendingAmount += installment.expectedAmount__c;

                if (
                    assessment.firstReplacementDueDate == null ||
                    installment.dueDate__c < assessment.firstReplacementDueDate
                ) {
                    assessment.firstReplacementDueDate = installment.dueDate__c;
                }

                Date installmentPeriodEnd = getInstallmentPeriodEnd(assessment.activePlan, installment);
                remainingPeriodEndDate = maxDate(remainingPeriodEndDate, installmentPeriodEnd);
                continue;
            }

            if (!CLOSED_INSTALLMENT_STATUSES.contains(installment.installmentStatus__c)) {
                assessment.reject('Existe una cuota en estado no soportado para cambio de frecuencia.');
                return;
            }
        }

        if (assessment.installmentsToCancel.isEmpty() || assessment.pendingAmount <= 0) {
            assessment.reject('El plan no tiene saldo pendiente para recalendariar.');
            return;
        }

        if (assessment.firstReplacementDueDate == null) {
            assessment.reject('No se pudo determinar la proxima fecha de cobro pendiente.');
            return;
        }

        if (assessment.firstReplacementDueDate > Date.today()) {
            assessment.reject('El cambio de frecuencia solo se permite desde la proxima fecha de cobro pendiente.');
            return;
        }

        assessment.remainingPeriodEndDate = remainingPeriodEndDate;
        assessment.isValid = true;
    }

    private static Map<Id, List<PaymentPlan__c>> getActivePlansByPolicyId(Set<Id> policyIds) {
        Map<Id, List<PaymentPlan__c>> activePlansByPolicyId = new Map<Id, List<PaymentPlan__c>>();

        for (PaymentPlan__c plan : [
            SELECT Id,
                insurancePolicy__c,
                planStatus__c,
                planType__c,
                premiumFrequency__c,
                expectedTotalAmount__c,
                firstDueDate__c,
                installmentCount__c
            FROM PaymentPlan__c
            WHERE insurancePolicy__c IN :policyIds
                AND planStatus__c = :PLAN_STATUS_ACTIVE
            ORDER BY CreatedDate DESC
        ]) {
            if (!activePlansByPolicyId.containsKey(plan.insurancePolicy__c)) {
                activePlansByPolicyId.put(plan.insurancePolicy__c, new List<PaymentPlan__c>());
            }

            activePlansByPolicyId.get(plan.insurancePolicy__c).add(plan);
        }

        return activePlansByPolicyId;
    }

    private static Map<Id, List<PaymentPlanInstallment__c>> getInstallmentsByPlanId(
        Map<Id, List<PaymentPlan__c>> activePlansByPolicyId
    ) {
        Set<Id> activePlanIds = new Set<Id>();

        for (List<PaymentPlan__c> plans : activePlansByPolicyId.values()) {
            for (PaymentPlan__c plan : plans) {
                activePlanIds.add(plan.Id);
            }
        }

        Map<Id, List<PaymentPlanInstallment__c>> installmentsByPlanId =
            new Map<Id, List<PaymentPlanInstallment__c>>();

        if (activePlanIds.isEmpty()) {
            return installmentsByPlanId;
        }

        for (PaymentPlanInstallment__c installment : [
            SELECT Id,
                paymentPlan__c,
                sequenceNumber__c,
                dueDate__c,
                periodEndDate__c,
                expectedAmount__c,
                matchedAmount__c,
                installmentStatus__c
            FROM PaymentPlanInstallment__c
            WHERE paymentPlan__c IN :activePlanIds
            ORDER BY dueDate__c ASC, sequenceNumber__c ASC
        ]) {
            if (!installmentsByPlanId.containsKey(installment.paymentPlan__c)) {
                installmentsByPlanId.put(installment.paymentPlan__c, new List<PaymentPlanInstallment__c>());
            }

            installmentsByPlanId.get(installment.paymentPlan__c).add(installment);
        }

        return installmentsByPlanId;
    }

    private static PaymentPlan__c buildReplacementPlan(
        InsurancePolicy policy,
        FrequencyChangeAssessment assessment
    ) {
        return new PaymentPlan__c(
            insurancePolicy__c = policy.Id,
            previousPlan__c = assessment.activePlan.Id,
            initialPlanKey__c = buildReplacementPlanKey(policy.Id, assessment.activePlan.Id, policy.PremiumFrequency),
            planType__c = PLAN_TYPE_FREQUENCY_CHANGE,
            planStatus__c = PLAN_STATUS_ACTIVE,
            premiumFrequency__c = policy.PremiumFrequency,
            expectedTotalAmount__c = assessment.pendingAmount.setScale(2),
            firstDueDate__c = assessment.firstReplacementDueDate,
            effectiveFromDate__c = assessment.firstReplacementDueDate,
            replacementReason__c = PLAN_REPLACEMENT_REASON,
            installmentCount__c = assessment.replacementInstallmentCount
        );
    }

    private static String buildReplacementPlanKey(Id policyId, Id previousPlanId, String premiumFrequency) {
        return String.valueOf(policyId) +
            ':FREQUENCY_CHANGE:' +
            String.valueOf(previousPlanId) +
            ':' +
            premiumFrequency;
    }

    private static Boolean hasPartialPayment(PaymentPlanInstallment__c installment) {
        return installment.matchedAmount__c != null &&
            installment.matchedAmount__c > 0 &&
            installment.expectedAmount__c != null &&
            installment.matchedAmount__c < installment.expectedAmount__c &&
            installment.installmentStatus__c != INSTALLMENT_STATUS_RECONCILED;
    }

    private static Date getInstallmentPeriodEnd(
        PaymentPlan__c plan,
        PaymentPlanInstallment__c installment
    ) {
        Integer monthsBetweenInstallments = getMonthsBetweenInstallments(plan.premiumFrequency__c);

        if (monthsBetweenInstallments == null || installment.dueDate__c == null) {
            return installment.periodEndDate__c;
        }

        return installment.dueDate__c.addMonths(monthsBetweenInstallments).addDays(-1);
    }

    private static Integer calculateInstallmentCount(
        String premiumFrequency,
        Date firstDueDate,
        Date remainingPeriodEndDate
    ) {
        if (premiumFrequency == FREQUENCY_SINGLE) {
            return firstDueDate != null && remainingPeriodEndDate != null && firstDueDate <= remainingPeriodEndDate
                ? 1
                : 0;
        }

        Integer monthsBetweenInstallments = getMonthsBetweenInstallments(premiumFrequency);

        if (monthsBetweenInstallments == null || firstDueDate == null || remainingPeriodEndDate == null) {
            return null;
        }

        Integer count = 0;
        Date dueDate = firstDueDate;

        while (dueDate.addMonths(monthsBetweenInstallments).addDays(-1) <= remainingPeriodEndDate) {
            count++;
            dueDate = dueDate.addMonths(monthsBetweenInstallments);
        }

        return count;
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

        if (premiumFrequency == FREQUENCY_ANNUAL) {
            return 12;
        }

        if (premiumFrequency == FREQUENCY_SINGLE) {
            return 0;
        }

        return null;
    }

    private static Boolean isOperational(InsurancePolicy policy) {
        return policy != null && OPERATIONAL_POLICY_STATUSES.contains(policy.Status);
    }

    private static Date maxDate(Date firstDate, Date secondDate) {
        if (firstDate == null) {
            return secondDate;
        }

        if (secondDate == null) {
            return firstDate;
        }

        return firstDate > secondDate ? firstDate : secondDate;
    }

    private class FrequencyChangeAssessment {
        InsurancePolicy policy;
        PaymentPlan__c activePlan;
        Boolean isValid = false;
        String errorMessage;
        Decimal pendingAmount = 0;
        Date firstReplacementDueDate;
        Date remainingPeriodEndDate;
        Integer replacementInstallmentCount;
        List<PaymentPlanInstallment__c> installmentsToCancel = new List<PaymentPlanInstallment__c>();

        FrequencyChangeAssessment(InsurancePolicy policy) {
            this.policy = policy;
        }

        void reject(String message) {
            this.isValid = false;
            this.errorMessage = message;
        }
    }
}
