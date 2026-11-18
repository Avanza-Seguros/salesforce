/**
 * @creation date: 02/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Reglas de pólizas (InsurancePolicy): no puede haber dos pólizas con el mismo número (PolizaNumeroUnico)
 * y, si cambia el vencimiento, sus bienes de póliza pasan al nuevo fin de vigencia (BienVigencia). Es independiente
 * del trigger de cobranza (InsurancePolicyTrigger). Las pólizas con el mismo número y otra vigencia se ligan como
 * historial de vigencias (PolizaVigencias).
 */
trigger PolizaReglasTrigger on InsurancePolicy(before insert, before update, after insert, after update) {
	if (Trigger.isBefore) {
		PolizaNumeroUnico.asignarLlave(Trigger.new, Trigger.oldMap);
	} else {
		if (Trigger.isUpdate) { BienVigencia.alinearFinDeVigencia(Trigger.new, Trigger.oldMap); }
		PolizaVigencias.ligar(Trigger.new, Trigger.oldMap);
	}
}
