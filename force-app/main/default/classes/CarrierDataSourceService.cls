/**
 *   @name: CarrierDataSourceService
 *   @version: 1.0
 *   @creation date: 11/10/2026
 *   @author: Javier Torres - Volestra
 *   @description: Dice de donde toma Salesforce los datos de cada aseguradora, segun
 *                 CarrierDataSource__mdt: de su portal, por la integracion, o de Handle. Cuando
 *                 el origen es Handle, los canales de polizas y de pagos guardan lo que llega de
 *                 esa aseguradora pero no lo aplican, para que dos fuentes no escriban sobre las
 *                 mismas polizas. Una aseguradora sin registro se toma del portal, que es como
 *                 funcionaba todo antes de existir este ajuste.
 */
public with sharing class CarrierDataSourceService {
	public static final String SOURCE_HANDLE = 'Handle';
	public static final String SOURCE_PORTAL = 'Portal';

	private static Map<String, String> sourceByCarrier;

	@TestVisible
	private static Map<String, String> sourceByCarrierForTest;

	/**
	 * @creation date: 11/10/2026
	 * @author: Javier Torres - Volestra
	 * @description: De las polizas dadas, devuelve las de una aseguradora cuyo origen es Handle.
	 *               No consulta nada si ninguna aseguradora tiene ese origen.
	 * @param policyIds: Polizas a revisar.
	 * @return: Set<Id> Polizas cuyos datos se cargan desde Handle.
	 */
	public static Set<Id> handleSourcedPolicies(Set<Id> policyIds) {
		Set<Id> result = new Set<Id>();
		Map<String, String> sources = sources();
		if (
			policyIds == null ||
			policyIds.isEmpty() ||
			!sources.values().contains(SOURCE_HANDLE)
		) {
			return result;
		}
		for (InsurancePolicy policy : [
			SELECT Id, Aseguradora__r.Name
			FROM InsurancePolicy
			WHERE Id IN :policyIds AND Aseguradora__c != NULL
		]) {
			if (SOURCE_HANDLE.equals(sourceOf(policy.Aseguradora__r.Name))) {
				result.add(policy.Id);
			}
		}
		return result;
	}

	/**
	 * @creation date: 11/10/2026
	 * @author: Javier Torres - Volestra
	 * @description: Origen de los datos de una aseguradora por su nombre. Sin registro, Portal.
	 * @param carrierName: Nombre de la aseguradora tal como esta en Aseguradora__c.
	 * @return: String Handle o Portal.
	 */
	public static String sourceOf(String carrierName) {
		String source = String.isBlank(carrierName)
			? null
			: sources().get(key(carrierName));
		return source == null ? SOURCE_PORTAL : source;
	}

	private static Map<String, String> sources() {
		if (sourceByCarrierForTest != null) {
			Map<String, String> normalized = new Map<String, String>();
			for (String name : sourceByCarrierForTest.keySet()) {
				normalized.put(key(name), sourceByCarrierForTest.get(name));
			}
			return normalized;
		}
		if (sourceByCarrier == null) {
			sourceByCarrier = new Map<String, String>();
			for (
				CarrierDataSource__mdt row : CarrierDataSource__mdt.getAll().values()
			) {
				if (String.isNotBlank(row.CarrierName__c)) {
					sourceByCarrier.put(key(row.CarrierName__c), row.DataSource__c);
				}
			}
		}
		return sourceByCarrier;
	}

	private static String key(String carrierName) {
		return carrierName.trim().toLowerCase();
	}
}
