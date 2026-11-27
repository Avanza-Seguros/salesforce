/**
 * @creation date: 26/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Siniestros (Claim): datos de la póliza, fecha de cierre y folio como nombre (ver Siniestros).
 */
trigger ClaimTrigger on Claim (before insert, before update, after insert) {
	if (Trigger.isBefore) {
		Siniestros.antesDeGuardar(Trigger.new, Trigger.oldMap);
	} else {
		Siniestros.despuesDeCrear(Trigger.new);
	}
}
