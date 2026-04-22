@IsTest
private class InsurancePolicyTriggerHandlerTest {
    @IsTest
    static void createsInitialPlanWhenPolicyIsInsertedAsOperational() {
        Account insured = createInsuredAccount();

        InsurancePolicy policy = buildPolicy(insured.Id, 'Vigente');
        policy.PremiumAmount = 1200;
        policy.PremiumFrequency = 'Mensual';
        policy.PaymentDueDate = Date.today().addDays(30);

        Test.startTest();
        insert policy;
        Test.stopTest();

        PaymentPlan__c plan = [
            SELECT insurancePolicy__c,
                planType__c,
                planStatus__c,
                premiumFrequency__c,
                expectedTotalAmount__c,
                firstDueDate__c,
                installmentCount__c
            FROM PaymentPlan__c
            WHERE insurancePolicy__c = :policy.Id
            LIMIT 1
        ];

        Assert.areEqual(policy.Id, plan.insurancePolicy__c);
        Assert.areEqual('Inicial', plan.planType__c);
        Assert.areEqual('Activo', plan.planStatus__c);
        Assert.areEqual('Mensual', plan.premiumFrequency__c);
        Assert.areEqual(Decimal.valueOf('1200'), plan.expectedTotalAmount__c);
        Assert.areEqual(policy.PaymentDueDate, plan.firstDueDate__c);
        Assert.areEqual(12, plan.installmentCount__c);
    }

    @IsTest
    static void createsOnlyOnePlanWhenOperationalPolicyIsUpdatedAgain() {
        Account insured = createInsuredAccount();

        InsurancePolicy policy = buildPolicy(insured.Id, 'Vigente');

        insert policy;

        Test.startTest();
        policy.PolicyName = 'Updated policy name';
        update policy;
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM PaymentPlan__c WHERE insurancePolicy__c = :policy.Id]
        );
    }

    @IsTest
    static void keepsOnePlanWhenPolicyTransitionsFromInitialToVigente() {
        Account insured = createInsuredAccount();

        InsurancePolicy policy = buildPolicy(insured.Id, 'Inicial');

        insert policy;

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM PaymentPlan__c WHERE insurancePolicy__c = :policy.Id]
        );

        Test.startTest();
        policy.Status = 'Vigente';
        update policy;
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM PaymentPlan__c WHERE insurancePolicy__c = :policy.Id]
        );
    }

    @IsTest
    static void mapsPremiumFrequencies() {
        Account insured = createInsuredAccount();

        List<InsurancePolicy> policies = new List<InsurancePolicy>{
            buildCompletePolicy(insured.Id, 'Trimestral', 300),
            buildCompletePolicy(insured.Id, 'Semestral', 600),
            buildCompletePolicy(insured.Id, 'Anual', 1200),
            buildCompletePolicy(insured.Id, 'Unico', 1200)
        };

        Test.startTest();
        insert policies;
        Test.stopTest();

        Map<Id, PaymentPlan__c> plansByPolicyId = new Map<Id, PaymentPlan__c>();
        Set<Id> policyIds = new Map<Id, InsurancePolicy>(policies).keySet();
        for (PaymentPlan__c plan : [
            SELECT insurancePolicy__c,
                premiumFrequency__c,
                installmentCount__c
            FROM PaymentPlan__c
            WHERE insurancePolicy__c IN :policyIds
        ]) {
            plansByPolicyId.put(plan.insurancePolicy__c, plan);
        }

        Assert.areEqual(4, plansByPolicyId.size());
        Assert.areEqual('Trimestral', plansByPolicyId.get(policies[0].Id).premiumFrequency__c);
        Assert.areEqual(4, plansByPolicyId.get(policies[0].Id).installmentCount__c);
        Assert.areEqual('Semestral', plansByPolicyId.get(policies[1].Id).premiumFrequency__c);
        Assert.areEqual(2, plansByPolicyId.get(policies[1].Id).installmentCount__c);
        Assert.areEqual('Anual', plansByPolicyId.get(policies[2].Id).premiumFrequency__c);
        Assert.areEqual(1, plansByPolicyId.get(policies[2].Id).installmentCount__c);
        Assert.areEqual('Unico', plansByPolicyId.get(policies[3].Id).premiumFrequency__c);
        Assert.areEqual(1, plansByPolicyId.get(policies[3].Id).installmentCount__c);
    }

    @IsTest
    static void reusesExistingInitialPlanForPolicy() {
        Account insured = createInsuredAccount();

        InsurancePolicy policy = buildPolicy(insured.Id, 'Cancelado');
        insert policy;

        PaymentPlan__c existingPlan = new PaymentPlan__c(
            insurancePolicy__c = policy.Id,
            planType__c = 'Inicial',
            planStatus__c = 'Borrador'
        );
        insert existingPlan;

        Test.startTest();
        policy.Status = 'Inicial';
        update policy;
        Test.stopTest();

        List<PaymentPlan__c> plans = [
            SELECT Id, initialPlanKey__c
            FROM PaymentPlan__c
            WHERE insurancePolicy__c = :policy.Id
        ];

        Assert.areEqual(1, plans.size());
        Assert.areEqual(existingPlan.Id, plans[0].Id);
    }

    private static Account createInsuredAccount() {
        Account insured = new Account(Name = 'Test Insured');
        insert insured;
        return insured;
    }

    private static InsurancePolicy buildPolicy(Id insuredAccountId, String status) {
        return new InsurancePolicy(
            Name = 'POL-TEST-' + String.valueOf(Crypto.getRandomInteger()).replace('-', ''),
            PolicyName = 'Test policy',
            NameInsuredId = insuredAccountId,
            Status = status
        );
    }

    private static InsurancePolicy buildCompletePolicy(
        Id insuredAccountId,
        String premiumFrequency,
        Decimal premiumAmount
    ) {
        InsurancePolicy policy = buildPolicy(insuredAccountId, 'Vigente');
        policy.PremiumAmount = premiumAmount;
        policy.PremiumFrequency = premiumFrequency;
        policy.PaymentDueDate = Date.today().addDays(30);
        return policy;
    }
}
