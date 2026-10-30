/**
 * @creation date: 02/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Reglas de pólizas (InsurancePolicy): no puede haber dos pólizas con el mismo número (PolizaNumeroUnico)
 * y, si cambia el vencimiento, sus bienes de póliza pasan al nuevo fin de vigencia (BienVigencia). Es independiente
 * del trigger de cobranza (InsurancePolicyTrigger).
 */
trigger PolizaReglasTrigger on InsurancePolicy(before insert, before update, after update) {
	if (Trigger.isBefore) {
		PolizaNumeroUnico.asignarLlave(Trigger.new, Trigger.oldMap);
	} else {
		BienVigencia.alinearFinDeVigencia(Trigger.new, Trigger.oldMap);
	}
}
