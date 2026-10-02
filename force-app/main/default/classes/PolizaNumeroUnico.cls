/**
 * @creation date: 02/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Reglas de alta de pólizas (InsurancePolicy): toda póliza debe tener oportunidad origen y no
 * puede haber dos pólizas con el mismo número. La póliza se crea en Crear Póliza al subir el PDF, cuando ya se
 * conoce su número real; la llave numeroPolizaUnico__c (campo único) guarda ese número normalizado.
 */
public with sharing class PolizaNumeroUnico {

	@TestVisible
	private static final String SIN_OPORTUNIDAD = 'No se pueden crear pólizas sin oportunidad. Crea la póliza desde '
		+ 'la oportunidad (Crear Póliza).';

	// En pruebas las reglas solo aplican cuando la prueba lo pide: las pruebas de cobranza crean pólizas sin
	// oportunidad y con números repetidos (vigencias) como datos de prueba. Fuera de pruebas siempre aplican.
	@TestVisible
	private static Boolean aplicarEnPruebas = false;

	/**
	 * @creation date: 02/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valida las pólizas antes de guardarse: rechaza las que se crean sin oportunidad (o a las que
	 * se les quita), asigna la llave del número al crearlas o al cambiarles el número, y marca error si el número
	 * ya pertenece a otra póliza o se repite en el mismo lote.
	 * @param nuevas: Trigger.new de InsurancePolicy
	 * @param anteriores: Trigger.oldMap (null en inserción)
	 * @return void
	 */
	public static void asignarLlave(List<InsurancePolicy> nuevas, Map<Id, InsurancePolicy> anteriores) {
		if (Test.isRunningTest() && !aplicarEnPruebas) { return; }
		Map<String, InsurancePolicy> porLlave = new Map<String, InsurancePolicy>();
		for (InsurancePolicy p : nuevas) {
			InsurancePolicy ant = anteriores == null ? null : anteriores.get(p.Id);
			// Sin oportunidad no hay póliza (las existentes sin oportunidad se pueden seguir editando).
			if (p.SourceOpportunityId == null && (ant == null || ant.SourceOpportunityId != null)) {
				p.SourceOpportunityId.addError(SIN_OPORTUNIDAD);
				continue;
			}
			// La llave cambia solo al crear la póliza o al cambiarle el número.
			if (ant != null && ant.Name == p.Name) { continue; }
			String llave = normalizar(p.Name);
			if (ant != null && llave == ant.numeroPolizaUnico__c) { continue; }
			p.numeroPolizaUnico__c = llave;
			if (llave == null) { continue; }
			if (porLlave.containsKey(llave)) {
				p.Name.addError(mensaje(p.Name, null));
				continue;
			}
			porLlave.put(llave, p);
		}
		if (porLlave.isEmpty()) { return; }

		// Otra póliza ya registrada con ese número (sin importar quién la pueda ver).
		for (InsurancePolicy ex : new SinCompartir().existentes(porLlave.keySet())) {
			InsurancePolicy p = porLlave.get(ex.numeroPolizaUnico__c.toUpperCase());
			if (p != null && p.Id != ex.Id) { p.Name.addError(mensaje(p.Name, ex)); }
		}
	}

	/**
	 * @creation date: 02/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Revisa, antes de guardar, si el número de póliza leído del PDF ya pertenece a otra póliza. Lo
	 * usa Crear Póliza para avisar y no modificar la póliza cuando el número está repetido.
	 * @param numero: Número de póliza leído del PDF
	 * @param policyId: Id de la póliza que se está editando (se excluye de la búsqueda; puede ser null)
	 * @return Mensaje de error si el número ya existe; null si está libre
	 */
	@AuraEnabled
	public static String validarNumeroPoliza(String numero, Id policyId) {
		String llave = normalizar(numero);
		if (llave == null) { return null; }
		for (InsurancePolicy ex : new SinCompartir().existentes(new Set<String>{ llave })) {
			if (ex.Id != policyId) { return mensaje(numero, ex); }
		}
		return null;
	}

	/**
	 * @creation date: 02/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Normaliza el número de póliza: sin espacios y en mayúsculas ("2001 m0080479" → "2001M0080479").
	 * @param numero: Número de póliza
	 * @return Número normalizado; null si está vacío
	 */
	@TestVisible
	private static String normalizar(String numero) {
		if (String.isBlank(numero)) { return null; }
		return numero.replaceAll('\\s+', '').toUpperCase().left(255);
	}

	/**
	 * @creation date: 02/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma el mensaje de error para un número de póliza repetido.
	 * @param numero: Número de póliza
	 * @param existente: Póliza que ya tiene ese número (puede ser null)
	 * @return Mensaje para el usuario
	 */
	private static String mensaje(String numero, InsurancePolicy existente) {
		String m = 'Ya existe una póliza con el número ' + numero.normalizeSpace();
		if (existente != null && existente.NameInsured != null) { m += ' (asegurado: ' + existente.NameInsured.Name + ')'; }
		return m + '. No puede haber dos pólizas con el mismo número.';
	}

	/**
	 * @creation date: 02/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Consulta sin sharing para que la búsqueda de duplicados vea todas las pólizas, no solo las
	 * compartidas con el usuario.
	 */
	private without sharing class SinCompartir {
		/**
		 * @creation date: 02/10/2026
		 * @author: Sergio Uribe Toledo - Volestra
		 * @description: Busca las pólizas que ya tienen alguna de las llaves.
		 * @param llaves: Números de póliza normalizados
		 * @return Pólizas encontradas
		 */
		List<InsurancePolicy> existentes(Set<String> llaves) {
			return [
				SELECT Id, Name, numeroPolizaUnico__c, NameInsured.Name
				FROM InsurancePolicy WHERE numeroPolizaUnico__c IN :llaves
			];
		}
	}
}
