/**
 * @creation date: 30/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Vigencia de los bienes del cliente (CustomerProperty). Un bien está vigente si tiene al menos un bien
 * de póliza (InsurancePolicyAsset) activo y su vigencia no ha terminado. La casilla «Activo» del bien de póliza la
 * mantiene PolicyAssetActivationService según el estado de la póliza; aquí se guarda en el CustomerProperty el número
 * de pólizas activas (Polizas_Activas__c) y el fin de vigencia más lejano (Vigente_Hasta__c); la fórmula Vigente__c
 * compara esa fecha con hoy. También alinea el fin de vigencia de los bienes de póliza cuando cambia el vencimiento
 * de la póliza.
 * Es without sharing porque son datos calculados: deben quedar bien aunque quien cambia la póliza no pueda editar el
 * bien del cliente.
 */
public without sharing class BienVigencia {

	/**
	 * @creation date: 30/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Trigger de InsurancePolicyAsset: recalcula los bienes del cliente afectados (el actual y, si
	 * cambió o se borró, el anterior). En una actualización solo si cambió el bien, la casilla «Activo» o las fechas.
	 * @param nuevos: Trigger.new (null al borrar)
	 * @param anteriores: Trigger.oldMap (null al crear o restaurar)
	 * @return void
	 */
	public static void alCambiarBienesDePoliza(List<InsurancePolicyAsset> nuevos, Map<Id, InsurancePolicyAsset> anteriores) {
		Set<Id> bienes = new Set<Id>();
		if (nuevos != null) {
			for (InsurancePolicyAsset a : nuevos) {
				InsurancePolicyAsset antes = anteriores == null ? null : anteriores.get(a.Id);
				if (antes != null && antes.CustomerPropertyId == a.CustomerPropertyId && antes.IsActive == a.IsActive
					&& antes.EffectiveFromDate == a.EffectiveFromDate && antes.EffectiveToDate == a.EffectiveToDate) {
					continue;
				}
				agregarBien(bienes, a.CustomerPropertyId);
				if (antes != null) { agregarBien(bienes, antes.CustomerPropertyId); }
			}
		} else if (anteriores != null) {
			for (InsurancePolicyAsset a : anteriores.values()) { agregarBien(bienes, a.CustomerPropertyId); }
		}
		recalcular(bienes);
	}

	/**
	 * @creation date: 30/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Recalcula las pólizas activas y el fin de vigencia de los bienes indicados. Solo guarda los que
	 * cambian y un error en uno no detiene a los demás ni el guardado que lo originó.
	 * @param bienes: Ids de CustomerProperty
	 * @return Número de bienes actualizados
	 */
	public static Integer recalcular(Set<Id> bienes) {
		if (bienes == null || bienes.isEmpty()) { return 0; }
		Map<Id, Integer> activas = new Map<Id, Integer>();
		Map<Id, Date> hasta = new Map<Id, Date>();
		for (AggregateResult r : [
			SELECT CustomerPropertyId bien, COUNT(Id) total, COUNT(EffectiveToDate) conFin, MAX(EffectiveToDate) fin
			FROM InsurancePolicyAsset
			WHERE CustomerPropertyId IN :bienes AND IsActive = true
			GROUP BY CustomerPropertyId
		]) {
			Id bien = (Id) r.get('bien');
			Integer total = (Integer) r.get('total');
			activas.put(bien, total);
			// Si algún bien de póliza activo no tiene fecha de fin, la vigencia queda abierta.
			hasta.put(bien, (Integer) r.get('conFin') == total ? (Date) r.get('fin') : null);
		}
		List<CustomerProperty> cambios = new List<CustomerProperty>();
		for (CustomerProperty cp : [
			SELECT Id, Polizas_Activas__c, Vigente_Hasta__c FROM CustomerProperty WHERE Id IN :bienes
		]) {
			Integer n = activas.containsKey(cp.Id) ? activas.get(cp.Id) : 0;
			Date fin = hasta.get(cp.Id);
			if (cp.Polizas_Activas__c != n || cp.Vigente_Hasta__c != fin) {
				cambios.add(new CustomerProperty(Id = cp.Id, Polizas_Activas__c = n, Vigente_Hasta__c = fin));
			}
		}
		if (cambios.isEmpty()) { return 0; }
		Integer guardados = 0;
		for (Database.SaveResult r : Database.update(cambios, false)) {
			if (r.isSuccess()) {
				guardados++;
			} else {
				System.debug(LoggingLevel.WARN, 'No se pudo actualizar la vigencia del bien ' + r.getId() + ': ' + r.getErrors());
			}
		}
		return guardados;
	}

	/**
	 * @creation date: 30/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Trigger de InsurancePolicy (después de actualizar): si cambia el vencimiento de la póliza, sus
	 * bienes de póliza que terminaban con el vencimiento anterior (o no tenían fecha de fin) pasan al nuevo.
	 * @param nuevas: Trigger.new
	 * @param anteriores: Trigger.oldMap
	 * @return void
	 */
	public static void alinearFinDeVigencia(List<InsurancePolicy> nuevas, Map<Id, InsurancePolicy> anteriores) {
		if (nuevas == null || anteriores == null) { return; }
		Map<Id, Date> nuevoFin = new Map<Id, Date>();
		Map<Id, Date> finAnterior = new Map<Id, Date>();
		for (InsurancePolicy p : nuevas) {
			InsurancePolicy antes = anteriores.get(p.Id);
			if (antes == null || p.ExpirationDate == null || p.ExpirationDate == antes.ExpirationDate) { continue; }
			nuevoFin.put(p.Id, p.ExpirationDate.date());
			finAnterior.put(p.Id, antes.ExpirationDate == null ? null : antes.ExpirationDate.date());
		}
		if (nuevoFin.isEmpty()) { return; }
		List<InsurancePolicyAsset> cambios = new List<InsurancePolicyAsset>();
		for (InsurancePolicyAsset a : [
			SELECT Id, InsurancePolicyId, EffectiveToDate FROM InsurancePolicyAsset WHERE InsurancePolicyId IN :nuevoFin.keySet()
		]) {
			if (a.EffectiveToDate == null || a.EffectiveToDate == finAnterior.get(a.InsurancePolicyId)) {
				cambios.add(new InsurancePolicyAsset(Id = a.Id, EffectiveToDate = nuevoFin.get(a.InsurancePolicyId)));
			}
		}
		if (cambios.isEmpty()) { return; }
		for (Database.SaveResult r : Database.update(cambios, false)) {
			if (!r.isSuccess()) {
				System.debug(LoggingLevel.WARN, 'No se pudo alinear el fin de vigencia del bien de póliza ' + r.getId() + ': ' + r.getErrors());
			}
		}
	}

	/**
	 * @creation date: 30/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Agrega el Id si es un CustomerProperty (el lookup del bien de póliza puede apuntar a otro objeto).
	 * @param bienes: conjunto destino
	 * @param id: Id del bien
	 * @return void
	 */
	private static void agregarBien(Set<Id> bienes, Id id) {
		if (id != null && id.getSObjectType() == CustomerProperty.SObjectType) { bienes.add(id); }
	}
}
