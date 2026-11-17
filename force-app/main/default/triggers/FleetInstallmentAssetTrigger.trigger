/**
 *   @name: FleetInstallmentAssetTrigger
 *   @version: 1.0
 *   @creation date: 16/11/2026
 *   @author: Javier Torres - Volestra
 *   @description: Liga las cuotas de una flotilla a sus incisos cuando se da de alta, de baja o
 *                 se cambia uno de sus bienes (pantalla de la póliza o de endosos de flotilla).
 *                 La lógica vive en FleetInstallmentService.
 */
trigger FleetInstallmentAssetTrigger on InsurancePolicyAsset(
	after insert,
	after update
) {
	FleetInstallmentService.onAssetsChanged(
		Trigger.new,
		Trigger.isInsert ? null : Trigger.oldMap
	);
}
