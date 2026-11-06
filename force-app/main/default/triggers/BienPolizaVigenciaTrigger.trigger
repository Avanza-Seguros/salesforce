/**
 * @creation date: 30/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Vigencia de los bienes del cliente (CustomerProperty): al crear, cambiar o borrar un bien de póliza se
 * recalculan las pólizas activas y la vigencia del bien. La lógica vive en BienVigencia.
 */
trigger BienPolizaVigenciaTrigger on InsurancePolicyAsset(after insert, after update, after delete, after undelete) {
	BienVigencia.alCambiarBienesDePoliza(Trigger.new, Trigger.oldMap);
}
