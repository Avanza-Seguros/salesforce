/**
 *   @name: PolicyAssetActivationService
 *   @version: 1.0
 *   @creation date: 25/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Mantiene la casilla «Activa» de los activos de la poliza (vehiculos y demas
 *                 bienes asegurados) de acuerdo con el estado de su poliza: activos mientras
 *                 la poliza esta Inicial o Vigente, inactivos cuando vence o se cancela, y
 *                 activos otra vez si se rehabilita.
 *                 Antes solo la escribia la carga, con el estado que traia el extracto, y se
 *                 quedaba congelada. Reacciona al cambio de estado venga de donde venga: el
 *                 proceso diario de vencimiento, la cancelacion o rehabilitacion de la
 *                 aseguradora, el cierre de la oportunidad o la pantalla.
 *                 La casilla «Activa» de la POLIZA no se toca: la calcula la plataforma y
 *                 solo la apaga el estado Cancelado.
 */
public with sharing class PolicyAssetActivationService {
	private static final Set<String> LIVE_POLICY_STATUSES = new Set<String>{
		'Inicial',
		'Vigente'
	};

	// Fuerza el fallo del guardado de los activos de estas polizas para probar que el fallo
	// queda registrado y no detiene a los demas.
	@TestVisible
	private static Set<Id> failForTest = new Set<Id>();

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Despues del guardado, alinea los activos de las polizas que entraron o
	 *               salieron de un estado vivo. Un activo que ya tiene el valor correcto no se
	 *               vuelve a guardar.
	 * @param newPolicies: Registros nuevos del trigger.
	 * @param oldMap: Valores anteriores de las polizas.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	public static void syncAfterUpdate(
		List<InsurancePolicy> newPolicies,
		Map<Id, InsurancePolicy> oldMap
	) {
		if (newPolicies == null || oldMap == null) {
			return;
		}

		Map<Id, Boolean> activeByPolicyId = new Map<Id, Boolean>();

		for (InsurancePolicy policy : newPolicies) {
			InsurancePolicy oldPolicy = policy == null ? null : oldMap.get(policy.Id);

			if (oldPolicy == null) {
				continue;
			}

			Boolean liveNow = isLive(policy);

			if (liveNow != isLive(oldPolicy)) {
				activeByPolicyId.put(policy.Id, liveNow);
			}
		}

		if (!activeByPolicyId.isEmpty()) {
			syncAssets(activeByPolicyId);
		}
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Pone la casilla «Activa» de los activos de cada poliza en el valor
	 *               indicado. Lo usa tambien el script de correccion de datos.
	 * @param activeByPolicyId: Valor que deben tener los activos de cada poliza.
	 * @return: Integer Cantidad de activos que se corrigieron.
	 * @exception:
	 * @throws:
	 */
	public static Integer syncAssets(Map<Id, Boolean> activeByPolicyId) {
		List<InsurancePolicyAsset> toUpdate = new List<InsurancePolicyAsset>();

		for (InsurancePolicyAsset asset : [
			SELECT Id, InsurancePolicyId, IsActive
			FROM InsurancePolicyAsset
			WHERE InsurancePolicyId IN :activeByPolicyId.keySet()
		]) {
			Boolean target = activeByPolicyId.get(asset.InsurancePolicyId);

			if (asset.IsActive == target) {
				continue;
			}

			InsurancePolicyAsset changed = new InsurancePolicyAsset(
				Id = asset.Id,
				IsActive = target
			);

			if (
				Test.isRunningTest() && failForTest.contains(asset.InsurancePolicyId)
			) {
				changed.OwnerId = null;
			}

			toUpdate.add(changed);
		}

		if (toUpdate.isEmpty()) {
			return 0;
		}

		Integer saved = 0;
		List<Database.SaveResult> results = Database.update(toUpdate, false);

		for (Integer i = 0; i < results.size(); i++) {
			if (results[i].isSuccess()) {
				saved++;
				continue;
			}

			List<String> errors = new List<String>();

			for (Database.Error error : results[i].getErrors()) {
				errors.add(error.getMessage());
			}

			CobranzaLog.error(
					CobranzaLog.STAGE_ESTADO_POLIZA,
					CobranzaLog.EVENT_POLICY_ASSET_SYNC_FAILED,
					'No se pudo alinear la casilla Activa del activo con el estado de su ' +
						'poliza. Motivo: ' +
						String.join(errors, '; ')
				)
				.onRecord(toUpdate[i].Id);
		}

		AppLogger.flush();
		return saved;
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Indica si la poliza esta viva. Tolera registros sin el campo Status: el
	 *               manejador del trigger tambien se invoca con polizas incompletas.
	 * @param policy: Poliza a evaluar.
	 * @return: Boolean Verdadero si esta Inicial o Vigente.
	 * @exception:
	 * @throws:
	 */
	public static Boolean isLive(InsurancePolicy policy) {
		try {
			return policy != null && LIVE_POLICY_STATUSES.contains(policy.Status);
		} catch (SObjectException e) {
			return false;
		}
	}
}
