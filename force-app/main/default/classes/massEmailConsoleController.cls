/**
 *   @name: massEmailConsoleController
 *   @version: 1.0
 *   @creation date: 02/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Controlador de la consola de envío masivo de correos. Provee métricas del dashboard (pendientes y enviados hoy), la lista de casos disponibles y el disparo del proceso batch de envío según el modo de selección (manual o todos).
 */
public with sharing class massEmailConsoleController {

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Obtiene las métricas principales para la pantalla de consola: total de items en proceso (pendientes) y total de items concluidos hoy.
	 * @return Mapa con las claves 'pending' y 'sentToday' y sus conteos.
	 */
	@AuraEnabled(cacheable=true)
	public static Map<String, Object> getDashboardData() {
		System.debug('getDashboardData');
		Map<String, Object> data = new Map<String, Object>();

		// Total pendientes
		Integer pending = [
			SELECT COUNT()
			FROM Items_Cases__c
			WHERE Estatus__c = 'En proceso'
		];

		// Total concluidos hoy
		Integer todaySent = [
			SELECT COUNT()
			FROM Items_Cases__c
			WHERE Estatus__c = 'Concluido'
			  AND LastModifiedDate = TODAY
		];

		System.debug('pending: ' + pending);
		System.debug('todaySent: ' + todaySent);
		data.put('pending', pending);
		data.put('sentToday', todaySent);

		return data;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Obtiene los casos que tienen items pendientes de enviar (estatus "En proceso"), ordenados por fecha de creación descendente y limitados a 100.
	 * @return Lista de registros Case disponibles.
	 */
	@AuraEnabled(cacheable=true)
	public static List<Case> getAvailableCases() {
		// Obtener casos que tienen items pendientes de enviar
		return [
			SELECT Id, CaseNumber, Subject, Status, CreatedDate
			FROM Case
			WHERE Status = 'En proceso'
			ORDER BY CreatedDate DESC
			LIMIT 100
		];
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Ejecuta el proceso batch de envío de correos según el modo de selección recibido en el JSON de parámetros: 'manual' (por caso, uno o lista) o 'all' (todos los pendientes hasta 200). Recolecta los Ids de items en proceso y delega en Invocable_EnviarEmails.
	 * @param params: Cadena JSON con los parámetros de selección (selectionMode y caseIds).
	 * @return Cadena de estado con el resultado del disparo (OK, INFO o ERROR).
	 */
	@AuraEnabled(cacheable=false)
	public static String runMassEmailFlow(String params) {
		System.debug('runMassEmailFlow iniciado');
		try {
			Map<String, Object> paramsMap = (Map<String, Object>)JSON.deserializeUntyped(params);
			String selectionMode = (String)paramsMap.get('selectionMode');
			System.debug('selectionMode: ' + selectionMode);

			List<Id> itemIds = new List<Id>();

			if (selectionMode == 'manual') {
				Object caseIdsObj = paramsMap.get('caseIds');

				if (caseIdsObj instanceof String) {
					String caseId = (String)caseIdsObj;
					if (String.isNotBlank(caseId)) {
						// Buscar Items_Cases para este Caso
						for (Items_Cases__c item : [
							SELECT Id
							FROM Items_Cases__c
							WHERE Caso__c = :caseId
							AND Estatus__c = 'En proceso'
						]) {
							itemIds.add(item.Id);
						}
					}
				} else if (caseIdsObj instanceof List<Object>) {
					// Si es una lista, tomar el primero
					List<Object> caseList = (List<Object>)caseIdsObj;
					if (!caseList.isEmpty()) {
						String caseId = String.valueOf(caseList[0]);
						for (Items_Cases__c item : [
							SELECT Id
							FROM Items_Cases__c
							WHERE Caso__c = :caseId
							AND Estatus__c = 'En proceso'
						]) {
							itemIds.add(item.Id);
						}
					}
				}
			} else if (selectionMode == 'all') {
				// Si es "todos", obtener todos los pendientes
				for (Items_Cases__c item : [
					SELECT Id
					FROM Items_Cases__c
					WHERE Estatus__c = 'En proceso'
					ORDER BY CreatedDate DESC
					LIMIT 200
				]) {
					itemIds.add(item.Id);
				}
			}

			System.debug('Items a procesar: ' + itemIds.size());

			if (itemIds.isEmpty()) {
				return 'INFO: No hay items pendientes para procesar';
			}

			// Ejecutar batch usando el nuevo método único
			// Pasar como List<Object> para compatibilidad
			Invocable_EnviarEmails.ejecutarBatch(itemIds);

			return 'OK - Procesando ' + itemIds.size() + ' items';

		} catch (Exception e) {
			System.debug('Error: ' + e.getMessage() + ' - ' + e.getStackTraceString());
			return 'ERROR: ' + e.getMessage();
		}
	}
}
