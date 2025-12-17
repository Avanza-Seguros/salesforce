/**
 * @description       : Trigger on Pago_poliza__c to handle status updates for related payments.
 * @author            : josemisa@outlook.com
 * @group             : 
 * @last modified on  : 07-24-2024
 * @last modified by  : Uriel Tejeiro
**/
trigger PolizasPendientes on Pago_poliza__c (after insert, after update) {
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        PolizasPendientesHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
}