/**
 *   @name: InsurancePolicyTrigger
 *   @version: 1.0
 *   @creation date: 23/04/2026
 *   @author: Javier Torres - Volestra
 *   @description: Orquesta las validaciones previas y procesos posteriores para
 *                 la generacion inicial de planes y el cambio de frecuencia.
 */
trigger InsurancePolicyTrigger on InsurancePolicy(
  before update,
  after insert,
  after update
) {
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
