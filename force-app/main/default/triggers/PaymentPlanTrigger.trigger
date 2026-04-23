/**
 *   @name: PaymentPlanTrigger
 *   @version: 1.0
 *   @creation date: 23/04/2026
 *   @author: Javier Torres - Volestra
 *   @description: Orquesta la generacion automatica de cuotas para PaymentPlan.
 */
trigger PaymentPlanTrigger on PaymentPlan__c(after insert, after update) {
  if (Trigger.isAfter) {
    PaymentPlanTriggerHandler.handleAfterTrigger(
      Trigger.new,
      Trigger.isInsert ? null : Trigger.oldMap
    );
  }
}
