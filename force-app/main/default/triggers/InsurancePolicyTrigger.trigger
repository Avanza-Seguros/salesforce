trigger InsurancePolicyTrigger on InsurancePolicy (before update, after insert, after update) {
    if (Trigger.isBefore) {
        InsurancePolicyTriggerHandler.handleBeforeTrigger(
            Trigger.new,
            Trigger.oldMap
        );
    }

    if (Trigger.isAfter) {
        InsurancePolicyTriggerHandler.handleAfterTrigger(
            Trigger.new,
            Trigger.isInsert ? null : Trigger.oldMap
        );
    }
}
