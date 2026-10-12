/**
 * @creation date: 02/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Regla de pólizas (InsurancePolicy): no puede haber dos pólizas con el mismo número y la misma
 * vigencia (fecha de inicio). Una renovación que conserva el número pero tiene otra vigencia sí se permite. La
 * llave numeroPolizaUnico__c (campo único) guarda "NÚMERO|AAAA-MM-DD" con el número normalizado.
 */
public with sharing class PolizaNumeroUnico {

	// En pruebas la regla solo aplica cuando la prueba lo pide: las pruebas de cobranza crean pólizas con números
	// repetidos como datos de prueba. Fuera de pruebas siempre aplica.
	@TestVisible
	private static Boolean aplicarEnPruebas = false;

	/**
	 * @creation date: 02/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valida las pólizas antes de guardarse: asigna la llave (número + inicio de vigencia) al crearlas
	 * o al cambiarles el número o la vigencia, y marca error si esa combinación ya pertenece a otra póliza o se
	 * repite en el mismo lote.
	 * @param nuevas: Trigger.new de InsurancePolicy
	 * @param anteriores: Trigger.oldMap (null en inserción)
	 * @return void
	 */
	public static void asignarLlave(List<InsurancePolicy> nuevas, Map<Id, InsurancePolicy> anteriores) {
		if (Test.isRunningTest() && !aplicarEnPruebas) { return; }
		Map<String, InsurancePolicy> porLlave = new Map<String, InsurancePolicy>();
		for (InsurancePolicy p : nuevas) {
			InsurancePolicy ant = anteriores == null ? null : anteriores.get(p.Id);
			// La llave cambia solo al crear la póliza o al cambiarle el número o el inicio de vigencia.
			if (ant != null && ant.Name == p.Name && fecha(ant.EffectiveDate) == fecha(p.EffectiveDate)) { continue; }
			String llave = llave(p.Name, fecha(p.EffectiveDate));
			if (ant != null && llave == ant.numeroPolizaUnico__c) { continue; }
			p.numeroPolizaUnico__c = llave;
			if (llave == null) { continue; }
			if (porLlave.containsKey(llave)) {
				p.Name.addError(mensaje(p.Name, fecha(p.EffectiveDate), null));
				continue;
			}
			porLlave.put(llave, p);
		}
		if (porLlave.isEmpty()) { return; }

		// Otra póliza ya registrada con ese número y vigencia (sin importar quién la pueda ver).
		for (InsurancePolicy ex : new SinCompartir().existentes(porLlave.keySet())) {
			InsurancePolicy p = porLlave.get(ex.numeroPolizaUnico__c.toUpperCase());
			if (p != null && p.Id != ex.Id) { p.Name.addError(mensaje(p.Name, fecha(p.EffectiveDate), ex)); }
		}
	}

	/**
	 * @creation date: 02/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Revisa, antes de guardar, si el número de póliza leído del PDF con su inicio de vigencia ya
	 * pertenece a otra póliza. Lo usa Crear Póliza para avisar y no modificar la póliza cuando está repetida.
	 * @param numero: Número de póliza leído del PDF
	 * @param vigenciaDesde: Inicio de vigencia (AAAA-MM-DD); puede venir vacío
	 * @param policyId: Id de la póliza que se está editando (se excluye de la búsqueda; puede ser null)
	 * @return Mensaje de error si ya existe; null si está libre
	 */
	@AuraEnabled
	public static String validarNumeroPoliza(String numero, String vigenciaDesde, Id policyId) {
		Date inicio = null;
		if (String.isNotBlank(vigenciaDesde)) {
			try { inicio = Date.valueOf(vigenciaDesde.left(10)); } catch (Exception e) { inicio = null; }
		}
		String llave = llave(numero, inicio);
		if (llave == null) { return null; }
		for (InsurancePolicy ex : new SinCompartir().existentes(new Set<String>{ llave })) {
			if (ex.Id != policyId) { return mensaje(numero, inicio, ex); }
		}
		return null;
	}

	/**
	 * @creation date: 09/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma la llave única de la póliza: número normalizado y fecha de inicio de vigencia
	 * ("VI0002940812|2026-09-30"). Sin vigencia queda "NÚMERO|".
	 * @param numero: Número de póliza
	 * @param inicio: Fecha de inicio de vigencia (puede ser null)
	 * @return Llave; null si no hay número
	 */
	@TestVisible
	private static String llave(String numero, Date inicio) {
		String n = normalizar(numero);
		if (n == null) { return null; }
		return (n + '|' + (inicio == null ? '' : String.valueOf(inicio))).left(255);
	}

	/**
	 * @creation date: 09/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Obtiene la fecha (en GMT) del inicio de vigencia, que en esta org es Fecha/Hora. Crear Póliza
	 * guarda las fechas a mediodía GMT, así el día no cambia por la zona horaria.
	 * @param dt: Inicio de vigencia (EffectiveDate)
	 * @return Fecha; null si no hay
	 */
	@TestVisible
	private static Date fecha(Datetime dt) {
		return dt == null ? null : dt.dateGmt();
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
		return numero.replaceAll('\\s+', '').toUpperCase().left(240);
	}

	/**
	 * @creation date: 02/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma el mensaje de error para una póliza repetida (mismo número y vigencia).
	 * @param numero: Número de póliza
	 * @param inicio: Inicio de vigencia (puede ser null)
	 * @param existente: Póliza que ya tiene ese número y vigencia (puede ser null)
	 * @return Mensaje para el usuario
	 */
	private static String mensaje(String numero, Date inicio, InsurancePolicy existente) {
		String m = 'Ya existe una póliza con el número ' + numero.normalizeSpace();
		if (inicio != null) { m += ' y vigencia desde ' + inicio.format(); }
		if (existente != null && existente.NameInsured != null) { m += ' (asegurado: ' + existente.NameInsured.Name + ')'; }
		return m + '. No puede haber dos pólizas con el mismo número y la misma vigencia.';
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
		 * @param llaves: Llaves (número + vigencia)
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
