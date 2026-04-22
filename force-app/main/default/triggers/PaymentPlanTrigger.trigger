trigger PaymentPlanTrigger on PaymentPlan__c (after insert, after update) {
    if (Trigger.isAfter) {
        PaymentPlanTriggerHandler.handleAfterTrigger(
            Trigger.new,
            Trigger.isInsert ? null : Trigger.oldMap
        );
    }
}
