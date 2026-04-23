@IsTest
public class CollectionsTestDataFactory {
    public static final String DEFAULT_ACCOUNT_NAME = 'Collections Test Insured';

    public static Account createInsuredAccount() {
        Account insured = new Account(Name = DEFAULT_ACCOUNT_NAME);
        insert insured;
        return insured;
    }

    public static Id getDefaultInsuredAccountId() {
        return [
            SELECT Id
            FROM Account
            WHERE Name = :DEFAULT_ACCOUNT_NAME
            LIMIT 1
        ].Id;
    }

    public static InsurancePolicy buildPolicy(Id insuredAccountId, String status) {
        return new InsurancePolicy(
            Name = 'POL-TEST-' + String.valueOf(Crypto.getRandomInteger()).replace('-', ''),
            PolicyName = 'Test policy',
            NameInsuredId = insuredAccountId,
            Status = status
        );
    }

    public static InsurancePolicy buildCompletePolicy(
        Id insuredAccountId,
        String status,
        String premiumFrequency,
        Decimal premiumAmount,
        Date firstDueDate
    ) {
        InsurancePolicy policy = buildPolicy(insuredAccountId, status);
        policy.PremiumAmount = premiumAmount;
        policy.PremiumFrequency = premiumFrequency;
        policy.PaymentDueDate = firstDueDate;
        return policy;
    }

    public static InsurancePolicy createPolicy(Id insuredAccountId, String status) {
        InsurancePolicy policy = buildPolicy(insuredAccountId, status);
        insert policy;
        return policy;
    }

    public static InsurancePolicy createOperationalPolicy(
        Id insuredAccountId,
        String premiumFrequency,
        Decimal premiumAmount,
        Date firstDueDate
    ) {
        InsurancePolicy policy = buildCompletePolicy(
            insuredAccountId,
            'Inicial',
            premiumFrequency,
            premiumAmount,
            firstDueDate
        );
        insert policy;
        return policy;
    }

    public static PaymentPlan__c buildPlan(
        Id policyId,
        String planStatus,
        String premiumFrequency,
        Decimal expectedTotalAmount,
        Date firstDueDate,
        Integer installmentCount
    ) {
        return new PaymentPlan__c(
            insurancePolicy__c = policyId,
            planType__c = 'Inicial',
            planStatus__c = planStatus,
            premiumFrequency__c = premiumFrequency,
            expectedTotalAmount__c = expectedTotalAmount,
            firstDueDate__c = firstDueDate,
            installmentCount__c = installmentCount
        );
    }

    public static PaymentPlan__c createPlan(
        Id policyId,
        String planStatus,
        String premiumFrequency,
        Decimal expectedTotalAmount,
        Date firstDueDate,
        Integer installmentCount
    ) {
        PaymentPlan__c plan = buildPlan(
            policyId,
            planStatus,
            premiumFrequency,
            expectedTotalAmount,
            firstDueDate,
            installmentCount
        );
        insert plan;
        return plan;
    }

    public static PaymentPlan__c getActivePlan(Id policyId) {
        return [
            SELECT Id, planStatus__c
            FROM PaymentPlan__c
            WHERE insurancePolicy__c = :policyId
                AND planStatus__c = 'Activo'
            LIMIT 1
        ];
    }

    public static List<PaymentPlanInstallment__c> getInstallmentsByPolicy(Id policyId) {
        return [
            SELECT Id,
                paymentPlan__c,
                sequenceNumber__c,
                dueDate__c,
                expectedAmount__c,
                installmentStatus__c,
                periodStartDate__c,
                periodEndDate__c,
                paymentPlan__r.insurancePolicy__c
            FROM PaymentPlanInstallment__c
            WHERE paymentPlan__r.insurancePolicy__c = :policyId
            ORDER BY sequenceNumber__c
        ];
    }

    public static List<PaymentPlanInstallment__c> getInstallmentsByPlan(Id planId) {
        return [
            SELECT Id,
                paymentPlan__c,
                sequenceNumber__c,
                dueDate__c,
                expectedAmount__c,
                installmentStatus__c,
                periodStartDate__c,
                periodEndDate__c
            FROM PaymentPlanInstallment__c
            WHERE paymentPlan__c = :planId
            ORDER BY sequenceNumber__c
        ];
    }

    public static Decimal sumExpectedAmounts(List<PaymentPlanInstallment__c> installments) {
        Decimal total = 0;

        for (PaymentPlanInstallment__c installment : installments) {
            total += installment.expectedAmount__c == null ? 0 : installment.expectedAmount__c;
        }

        return total.setScale(2);
    }
}
