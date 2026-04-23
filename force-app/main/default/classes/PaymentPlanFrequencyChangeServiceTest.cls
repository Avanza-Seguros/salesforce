@IsTest
private class PaymentPlanFrequencyChangeServiceTest {
    @TestSetup
    static void setupData() {
        CollectionsTestDataFactory.createInsuredAccount();
    }

    @IsTest
    static void replacesSemiannualPlanWithMonthlyPlanForPendingBalance() {
        Date firstDueDate = Date.today().addMonths(-6);
        InsurancePolicy policy = CollectionsTestDataFactory.createOperationalPolicy(
            CollectionsTestDataFactory.getDefaultInsuredAccountId(),
            'Semestral',
            1200,
            firstDueDate
        );
        PaymentPlan__c originalPlan = CollectionsTestDataFactory.getActivePlan(policy.Id);
        List<PaymentPlanInstallment__c> originalInstallments =
            CollectionsTestDataFactory.getInstallmentsByPlan(originalPlan.Id);
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
            SELECT previousPlan__c,
                planType__c,
                planStatus__c,
                premiumFrequency__c,
                expectedTotalAmount__c,
                firstDueDate__c,
                effectiveFromDate__c,
                replacementReason__c,
                installmentCount__c
            FROM PaymentPlan__c
            WHERE insurancePolicy__c = :policy.Id
                AND previousPlan__c = :originalPlan.Id
            LIMIT 1
        ];
        List<PaymentPlanInstallment__c> replacementInstallments =
            CollectionsTestDataFactory.getInstallmentsByPlan(replacementPlan.Id);
        List<PaymentPlanInstallment__c> oldInstallments =
            CollectionsTestDataFactory.getInstallmentsByPlan(originalPlan.Id);

        Assert.areEqual('Reemplazado', replacedPlan.planStatus__c);
        Assert.areEqual(Date.today(), replacedPlan.replacedOn__c);
        Assert.areEqual('Conciliado', oldInstallments[0].installmentStatus__c);
        Assert.areEqual('Cancelado', oldInstallments[1].installmentStatus__c);
        Assert.areEqual(originalPlan.Id, replacementPlan.previousPlan__c);
        Assert.areEqual('Cambio de frecuencia', replacementPlan.planType__c);
        Assert.areEqual('Activo', replacementPlan.planStatus__c);
        Assert.areEqual('Mensual', replacementPlan.premiumFrequency__c);
        Assert.areEqual(Decimal.valueOf('600.00'), replacementPlan.expectedTotalAmount__c);
        Assert.areEqual(Date.today(), replacementPlan.firstDueDate__c);
        Assert.areEqual(Date.today(), replacementPlan.effectiveFromDate__c);
        Assert.areEqual('Cambio de frecuencia', replacementPlan.replacementReason__c);
        Assert.areEqual(6, replacementPlan.installmentCount__c);
        Assert.areEqual(6, replacementInstallments.size());
        Assert.areEqual(Date.today(), replacementInstallments[0].dueDate__c);
        Assert.areEqual(Date.today().addMonths(5), replacementInstallments[5].dueDate__c);
        Assert.areEqual(Decimal.valueOf('600.00'), CollectionsTestDataFactory.sumExpectedAmounts(replacementInstallments));
    }

    @IsTest
    static void doesNotAllowFrequencyChangeBeforeNextPendingDueDate() {
        Date firstDueDate = Date.today().addMonths(-4);
        InsurancePolicy policy = CollectionsTestDataFactory.createOperationalPolicy(
            CollectionsTestDataFactory.getDefaultInsuredAccountId(),
            'Semestral',
            1200,
            firstDueDate
        );
        PaymentPlan__c originalPlan = CollectionsTestDataFactory.getActivePlan(policy.Id);
        List<PaymentPlanInstallment__c> originalInstallments =
            CollectionsTestDataFactory.getInstallmentsByPlan(originalPlan.Id);
        originalInstallments[0].installmentStatus__c = 'Conciliado';
        update originalInstallments[0];

        Test.startTest();
        policy.PremiumFrequency = 'Mensual';
        Boolean threwException = false;

        try {
            update policy;
        } catch (DmlException e) {
            threwException = true;
            Assert.isTrue(e.getMessage().contains('proxima fecha de cobro pendiente'));
        }

        Test.stopTest();

        Assert.isTrue(threwException);
        Assert.areEqual(1, [SELECT COUNT() FROM PaymentPlan__c WHERE insurancePolicy__c = :policy.Id]);
    }

    @IsTest
    static void doesNotAllowFrequencyChangeWhenPlanHasNoPendingBalance() {
        Date firstDueDate = Date.today().addMonths(-6);
        InsurancePolicy policy = CollectionsTestDataFactory.createOperationalPolicy(
            CollectionsTestDataFactory.getDefaultInsuredAccountId(),
            'Semestral',
            1200,
            firstDueDate
        );
        PaymentPlan__c originalPlan = CollectionsTestDataFactory.getActivePlan(policy.Id);
        List<PaymentPlanInstallment__c> originalInstallments =
            CollectionsTestDataFactory.getInstallmentsByPlan(originalPlan.Id);

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
        Assert.areEqual('Activo', CollectionsTestDataFactory.getActivePlan(policy.Id).planStatus__c);
    }

    @IsTest
    static void doesNotAllowFrequencyChangeWhenNewFrequencyDoesNotFitRemainingTerm() {
        Date firstDueDate = Date.today().addMonths(-7);
        InsurancePolicy policy = CollectionsTestDataFactory.createOperationalPolicy(
            CollectionsTestDataFactory.getDefaultInsuredAccountId(),
            'Mensual',
            1200,
            firstDueDate
        );
        PaymentPlan__c originalPlan = CollectionsTestDataFactory.getActivePlan(policy.Id);
        List<PaymentPlanInstallment__c> originalInstallments =
            CollectionsTestDataFactory.getInstallmentsByPlan(originalPlan.Id);

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
        Assert.areEqual(1, [SELECT COUNT() FROM PaymentPlan__c WHERE insurancePolicy__c = :policy.Id]);
    }
}
