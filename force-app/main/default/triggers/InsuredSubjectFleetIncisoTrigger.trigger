/**
 *   @name: InsuredSubjectFleetIncisoTrigger
 *   @version: 1.0
 *   @creation date: 12/11/2026
 *   @author: Javier Torres - Volestra
 *   @description: Recalcula el campo «Asegurado o bien» de la póliza cuando se da de alta,
 *                 de baja, se cambia o se borra un inciso de flotilla. La lógica vive en
 *                 InsuredSubjectService.
 */
trigger InsuredSubjectFleetIncisoTrigger on Inciso_Flotilla__c(
	after insert,
	after update,
	after delete,
	after undelete
) {
	InsuredSubjectService.onFleetIncisosChanged(
		Trigger.isDelete ? Trigger.old : Trigger.new,
		Trigger.isInsert || Trigger.isUndelete ? null : Trigger.oldMap
	);
}
