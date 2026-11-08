/**
 *   @name: InsuredSubjectParticipantTrigger
 *   @version: 1.0
 *   @creation date: 08/11/2026
 *   @author: Javier Torres - Volestra
 *   @description: Recalcula el campo «Asegurado o bien» de la póliza cuando se da de alta,
 *                 de baja, se cambia o se borra uno de sus asegurados. La lógica vive en
 *                 InsuredSubjectService.
 */
trigger InsuredSubjectParticipantTrigger on InsurancePolicyParticipant(
	after insert,
	after update,
	after delete,
	after undelete
) {
	InsuredSubjectService.onParticipantsChanged(
		Trigger.isDelete ? Trigger.old : Trigger.new,
		Trigger.isInsert || Trigger.isUndelete ? null : Trigger.oldMap
	);
}
