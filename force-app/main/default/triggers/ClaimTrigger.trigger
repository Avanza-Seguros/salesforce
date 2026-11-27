/**
 * @creation date: 26/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Siniestros (Claim): datos de la póliza, fechas de acuse y de cierre, folio como nombre, avisos por
 *               correo y conteo de la encuesta (ver Siniestros).
 */
trigger ClaimTrigger on Claim (before insert, before update, after insert, after update) {
	if (Trigger.isBefore) {
		Siniestros.antesDeGuardar(Trigger.new, Trigger.oldMap);
	} else if (Trigger.isInsert) {
		Siniestros.despuesDeCrear(Trigger.new);
	} else {
		Siniestros.despuesDeActualizar(Trigger.new, Trigger.oldMap);
	}
}
