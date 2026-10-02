/**
 * @creation date: 02/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Reglas de alta de pólizas (InsurancePolicy): toda póliza debe tener oportunidad origen y no
 * puede haber dos pólizas con el mismo número. La lógica vive en PolizaNumeroUnico; es independiente del
 * trigger de cobranza (InsurancePolicyTrigger).
 */
trigger PolizaReglasTrigger on InsurancePolicy(before insert, before update) {
	PolizaNumeroUnico.asignarLlave(Trigger.new, Trigger.oldMap);
}
