@IsTest
private class PolicyAssetActivationServiceTest {
	private static final String EVENT_FAILED = 'POLICY_ASSET_SYNC_FAILED';

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Crea la cuenta asegurada compartida usada por todos los tests de la clase.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Cuando la poliza vence, sus activos dejan de estar activos.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void deactivatesAssetsWhenPolicyExpires() {
		InsurancePolicy policy = createPolicy();
		InsurancePolicyAsset asset = createAsset(policy.Id, true);

		Test.startTest();
		update new InsurancePolicy(Id = policy.Id, Status = 'Vencido');
		Test.stopTest();

		Assert.isFalse(loadAsset(asset.Id).IsActive);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Cuando la aseguradora cancela, los activos dejan de estar activos; si la
	 *               rehabilita, vuelven a estarlo.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void followsCancellationAndReinstatement() {
		InsurancePolicy policy = createPolicy();
		InsurancePolicyAsset asset = createAsset(policy.Id, true);

		Test.startTest();
		update new InsurancePolicy(Id = policy.Id, Status = 'Cancelado');
		Boolean afterCancellation = loadAsset(asset.Id).IsActive;
		update new InsurancePolicy(Id = policy.Id, Status = 'Vigente');
		Test.stopTest();

		Assert.isFalse(afterCancellation);
		Assert.isTrue(loadAsset(asset.Id).IsActive);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Pasar de Inicial a Vigente no cambia nada: la poliza sigue viva y los
	 *               activos se quedan como estaban.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void doesNotTouchAssetsWhilePolicyStaysLive() {
		InsurancePolicy policy = createPolicy();
		InsurancePolicyAsset inactive = createAsset(policy.Id, false);

		Test.startTest();
		update new InsurancePolicy(Id = policy.Id, Status = 'Vigente');
		Test.stopTest();

		Assert.isFalse(
			loadAsset(inactive.Id).IsActive,
			'Sin salir de un estado vivo, el activo no se toca'
		);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Si los activos de una poliza no se pueden guardar, los de las demas se
	 *               alinean y el fallo queda en el registro de la aplicacion.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void failureOnOnePolicyDoesNotStopTheOthers() {
		InsurancePolicy failing = createPolicy();
		InsurancePolicy healthy = createPolicy();
		InsurancePolicyAsset failingAsset = createAsset(failing.Id, true);
		InsurancePolicyAsset healthyAsset = createAsset(healthy.Id, true);
		PolicyAssetActivationService.failForTest.add(failing.Id);

		Test.startTest();
		update new List<InsurancePolicy>{
			new InsurancePolicy(Id = failing.Id, Status = 'Vencido'),
			new InsurancePolicy(Id = healthy.Id, Status = 'Vencido')
		};
		Test.stopTest();

		Assert.isTrue(loadAsset(failingAsset.Id).IsActive);
		Assert.isFalse(loadAsset(healthyAsset.Id).IsActive);
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM AppLog__c
				WHERE recordId__c = :failingAsset.Id AND eventCode__c = :EVENT_FAILED
			]
		);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: La correccion de datos solo guarda los activos con el valor equivocado y
	 *               devuelve cuantos corrigio.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void syncAssetsOnlyFixesMisalignedAssets() {
		InsurancePolicy policy = createPolicy();
		createAsset(policy.Id, true);
		createAsset(policy.Id, false);

		Test.startTest();
		Integer fixed = PolicyAssetActivationService.syncAssets(
			new Map<Id, Boolean>{ policy.Id => false }
		);
		Test.stopTest();

		Assert.areEqual(1, fixed);
		Assert.areEqual(
			0,
			[
				SELECT COUNT()
				FROM InsurancePolicyAsset
				WHERE InsurancePolicyId = :policy.Id AND IsActive = TRUE
			]
		);
		Assert.isFalse(PolicyAssetActivationService.isLive(null));
	}

	private static InsurancePolicy createPolicy() {
		return CollectionsTestDataFactory.createOperationalPolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Anual',
			1200,
			Date.today().addDays(10)
		);
	}

	private static InsurancePolicyAsset createAsset(Id policyId, Boolean active) {
		InsurancePolicyAsset asset = new InsurancePolicyAsset(
			InsurancePolicyId = policyId,
			AssetName = 'Vehiculo de prueba',
			IsActive = active
		);
		insert asset;
		return asset;
	}

	private static InsurancePolicyAsset loadAsset(Id assetId) {
		return [SELECT IsActive FROM InsurancePolicyAsset WHERE Id = :assetId];
	}
}
