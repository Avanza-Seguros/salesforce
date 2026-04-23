trigger InsurancePolicyTrigger on InsurancePolicy (after insert, after update) {
    if (Trigger.isAfter) {
        InsurancePolicyTriggerHandler.handleAfterTrigger(
            Trigger.new,
            Trigger.isInsert ? null : Trigger.oldMap
        );
    }
}
