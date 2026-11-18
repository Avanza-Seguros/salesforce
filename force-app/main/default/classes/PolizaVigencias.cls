/**
 * @creation date: 18/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Historial de vigencias de una póliza: las pólizas con el mismo número y distinta vigencia (la misma
 * póliza renovada) se ligan en orden de inicio de vigencia. Cada una apunta a la vigencia que renueva («Póliza
 * anterior», PriorPolicyId) y a la que la renueva («Vigencia siguiente», nextPolicy__c). No importa el orden en que
 * se carguen los PDF: con cada póliza nueva se reacomoda toda la cadena de ese número. Las ligas a pólizas con otro
 * número (renovaciones de colectivas que cambiaron de número) se respetan.
 */
public with sharing class PolizaVigencias {

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Después de guardar las pólizas, liga las vigencias de los números que se crearon o a los que se
	 * les cambió el número o el inicio de vigencia. La liga es informativa: si falla no impide guardar la póliza.
	 * @param nuevas: Trigger.new de InsurancePolicy (after insert / after update)
	 * @param anteriores: Trigger.oldMap (null en inserción)
	 * @return void
	 */
	public static void ligar(List<InsurancePolicy> nuevas, Map<Id, InsurancePolicy> anteriores) {
		Set<String> numeros = new Set<String>();
		Set<Id> renombradas = new Set<Id>();
		for (InsurancePolicy p : nuevas) {
			InsurancePolicy ant = anteriores == null ? null : anteriores.get(p.Id);
			if (ant != null && ant.numeroPolizaUnico__c == p.numeroPolizaUnico__c) { continue; }
			String n = numero(p.numeroPolizaUnico__c);
			if (n != null) { numeros.add(n); }
			// Si le cambiaron el número, la cadena del número anterior también se reacomoda y sus ligas viejas ya
			// no aplican.
			String nAnt = ant == null ? null : numero(ant.numeroPolizaUnico__c);
			if (nAnt != null && nAnt != n) {
				numeros.add(nAnt);
				renombradas.add(p.Id);
			}
		}
		if (numeros.isEmpty()) { return; }
		try {
			new SinCompartir().ligarNumeros(numeros, renombradas);
		} catch (Exception e) {
			System.debug(LoggingLevel.WARN, 'No se ligaron las vigencias de la póliza: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Liga las vigencias de pólizas ya registradas (carga inicial o corrección manual).
	 * @param policyIds: Pólizas cuyos números se van a ligar
	 * @return Número de pólizas que cambiaron
	 */
	public static Integer ligarExistentes(Set<Id> policyIds) {
		Set<String> numeros = new Set<String>();
		for (InsurancePolicy p : [SELECT numeroPolizaUnico__c FROM InsurancePolicy WHERE Id IN :policyIds]) {
			String n = numero(p.numeroPolizaUnico__c);
			if (n != null) { numeros.add(n); }
		}
		return numeros.isEmpty() ? 0 : new SinCompartir().ligarNumeros(numeros, new Set<Id>());
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Número normalizado de la llave única ("GM0000170455|2025-04-24" → "GM0000170455").
	 * @param llave: numeroPolizaUnico__c
	 * @return Número; null si no hay llave
	 */
	@TestVisible
	private static String numero(String llave) {
		if (String.isBlank(llave) || !llave.contains('|')) { return null; }
		String n = llave.substringBefore('|');
		return String.isBlank(n) ? null : n.toUpperCase();
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Normaliza el número igual que la llave única (PolizaNumeroUnico): sin espacios, en mayúsculas y
	 * sin ceros a la izquierda.
	 * @param nombre: Número de póliza (Name)
	 * @return Número normalizado; null si está vacío
	 */
	@TestVisible
	private static String normalizar(String nombre) {
		if (String.isBlank(nombre)) { return null; }
		return nombre.replaceAll('\\s+', '').toUpperCase().replaceFirst('^0+(?=.)', '').left(240);
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Consulta y actualiza sin sharing: la cadena de vigencias incluye pólizas que el usuario puede no
	 * ver (por ejemplo, una vigencia anterior de otro ejecutivo).
	 */
	private without sharing class SinCompartir {

		/**
		 * @creation date: 18/11/2026
		 * @author: Sergio Uribe Toledo - Volestra
		 * @description: Ordena por inicio de vigencia las pólizas de cada número y liga cada una con la anterior y
		 * la siguiente. Las ligas a pólizas con otro número (renovaciones que cambiaron de número, como las de la
		 * migración de Qualitas) se respetan en la primera y la última vigencia, y una póliza sola en su número no se
		 * toca; solo se quitan si a la póliza (o a la que apunta) le cambiaron el número.
		 * @param numeros: Números normalizados
		 * @param renombradas: Pólizas a las que les cambiaron el número en esta operación
		 * @return Número de pólizas que cambiaron
		 */
		Integer ligarNumeros(Set<String> numeros, Set<Id> renombradas) {
			List<String> patrones = new List<String>();
			List<String> nombres = new List<String>();
			for (String n : numeros) {
				String seguro = n.replace('%', '\\%').replace('_', '\\_');
				patrones.add(seguro + '|%');
				nombres.add('%' + seguro + '%');
			}
			Map<String, List<InsurancePolicy>> porNumero = new Map<String, List<InsurancePolicy>>();
			Map<Id, String> numeroDe = new Map<Id, String>();
			// Las pólizas registradas antes de la regla de número único no tienen llave: se buscan por nombre y se
			// comparan con el número normalizado.
			for (InsurancePolicy p : [
				SELECT Id, Name, numeroPolizaUnico__c, EffectiveDate, PriorPolicyId, nextPolicy__c
				FROM InsurancePolicy
				WHERE EffectiveDate != null
					AND (numeroPolizaUnico__c LIKE :patrones OR (numeroPolizaUnico__c = null AND Name LIKE :nombres))
				ORDER BY EffectiveDate ASC, CreatedDate ASC
			]) {
				String n = p.numeroPolizaUnico__c != null ? numero(p.numeroPolizaUnico__c) : normalizar(p.Name);
				if (!numeros.contains(n)) { continue; }
				if (!porNumero.containsKey(n)) { porNumero.put(n, new List<InsurancePolicy>()); }
				porNumero.get(n).add(p);
				numeroDe.put(p.Id, n);
			}

			List<InsurancePolicy> cambios = new List<InsurancePolicy>();
			for (String n : porNumero.keySet()) {
				List<InsurancePolicy> cadena = porNumero.get(n);
				for (Integer i = 0; i < cadena.size(); i++) {
					InsurancePolicy p = cadena[i];
					Id anterior = i > 0 ? cadena[i - 1].Id : null;
					Id siguiente = i < cadena.size() - 1 ? cadena[i + 1].Id : null;
					InsurancePolicy cambio = new InsurancePolicy(Id = p.Id);
					Boolean cambia = false;
					if (p.PriorPolicyId != anterior && (anterior != null || ligaVieja(p, p.PriorPolicyId, n, numeroDe, renombradas))) {
						cambio.PriorPolicyId = anterior;
						cambia = true;
					}
					if (p.nextPolicy__c != siguiente && (siguiente != null || ligaVieja(p, p.nextPolicy__c, n, numeroDe, renombradas))) {
						cambio.nextPolicy__c = siguiente;
						cambia = true;
					}
					if (cambia) { cambios.add(cambio); }
				}
			}
			if (!cambios.isEmpty()) { update cambios; }
			return cambios.size();
		}

		/**
		 * @creation date: 18/11/2026
		 * @author: Sergio Uribe Toledo - Volestra
		 * @description: Indica si la liga de la primera o la última vigencia ya no aplica y se debe quitar: apunta a
		 * otra vigencia del mismo número (que ya quedó en otro lugar de la cadena) o a la póliza, o desde la póliza, a
		 * la que le cambiaron el número. Una liga a una póliza con otro número se conserva.
		 * @param p: Póliza de la cadena
		 * @param destino: Póliza a la que apunta la liga (puede ser null)
		 * @param n: Número de la cadena
		 * @param numeroDe: Número de cada póliza de las cadenas que se reacomodan
		 * @param renombradas: Pólizas a las que les cambiaron el número
		 * @return true si hay que quitar la liga
		 */
		private Boolean ligaVieja(InsurancePolicy p, Id destino, String n, Map<Id, String> numeroDe, Set<Id> renombradas) {
			if (destino == null) { return false; }
			if (numeroDe.get(destino) == n) { return true; }
			return numeroDe.containsKey(destino) && (renombradas.contains(p.Id) || renombradas.contains(destino));
		}
	}
}
