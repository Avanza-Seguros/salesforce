/**
 *   @name: InsuredSubjectServiceTest
 *   @version: 1.0
 *   @creation date: 08/11/2026
 *   @author: Javier Torres - Volestra
 *   @description: Valida que el campo «Asegurado o bien» de la póliza diga qué asegura y se
 *                 mantenga solo al dar de alta, de baja o cambiar bienes y asegurados.
 */
@IsTest
private class InsuredSubjectServiceTest {
	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	private static Id accountId() {
		return CollectionsTestDataFactory.getDefaultInsuredAccountId();
	}

	private static InsurancePolicy createPolicy(String status) {
		InsurancePolicy policy = CollectionsTestDataFactory.buildCompletePolicy(
			accountId(),
			status,
			'Anual',
			1200,
			Date.today()
		);
		policy.EffectiveDate = Datetime.now().addDays(-30);
		policy.ExpirationDate = Datetime.now().addDays(335);
		insert policy;
		return policy;
	}

	private static String subjectOf(Id policyId) {
		return [SELECT insuredSubject__c FROM InsurancePolicy WHERE Id = :policyId]
		.insuredSubject__c;
	}

	private static InsurancePolicyParticipant person(
		Id policyId,
		String name,
		String relationship
	) {
		return new InsurancePolicyParticipant(
			InsurancePolicyId = policyId,
			PrimaryParticipantAccountId = accountId(),
			ParticipantName = name,
			Role = 'Asegurado',
			RelationshipToInsured = relationship,
			IsActiveParticipant = true
		);
	}

	@IsTest
	static void aVehicleShowsItsDescriptionAndSerial() {
		InsurancePolicy policy = createPolicy('Inicial');
		CustomerProperty car = new CustomerProperty(
			PrimaryOwnerId = accountId(),
			Vin = '3VWFE21C04M000001'
		);
		insert car;

		Test.startTest();
		insert new InsurancePolicyAsset(
			InsurancePolicyId = policy.Id,
			AssetName = 'KIA RIO 2020',
			CustomerPropertyId = car.Id,
			IsActive = true
		);
		Test.stopTest();

		System.assertEquals(
			'KIA RIO 2020 · serie 3VWFE21C04M000001',
			subjectOf(policy.Id),
			'Dice el vehículo con su serie'
		);
	}

	@IsTest
	static void aLocationDropsTheIncisoPrefix() {
		InsurancePolicy policy = createPolicy('Inicial');

		Test.startTest();
		insert new InsurancePolicyAsset(
			InsurancePolicyId = policy.Id,
			AssetName = 'Inciso 3 - Av. Vallarta 1340, Zapopan',
			IsActive = true
		);
		Test.stopTest();

		System.assertEquals(
			'Av. Vallarta 1340, Zapopan',
			subjectOf(policy.Id),
			'Dice el domicilio sin el número de inciso'
		);
	}

	@IsTest
	static void severalAssetsAreAFleetAndADroppedOneDoesNotCount() {
		InsurancePolicy policy = createPolicy('Inicial');
		List<InsurancePolicyAsset> assets = new List<InsurancePolicyAsset>{
			new InsurancePolicyAsset(
				InsurancePolicyId = policy.Id,
				AssetName = 'Local 1',
				IsActive = true
			),
			new InsurancePolicyAsset(
				InsurancePolicyId = policy.Id,
				AssetName = 'Local 2',
				IsActive = true
			),
			new InsurancePolicyAsset(
				InsurancePolicyId = policy.Id,
				AssetName = 'Local 3',
				IsActive = true
			)
		};
		insert assets;
		System.assertEquals(
			'Flotilla · 3 incisos',
			subjectOf(policy.Id),
			'Cuenta los incisos'
		);

		Test.startTest();
		update new InsurancePolicyAsset(
			Id = assets[2].Id,
			IsActive = false,
			EffectiveToDate = Date.today()
		);
		Test.stopTest();

		System.assertEquals(
			'Flotilla · 2 incisos',
			subjectOf(policy.Id),
			'El inciso dado de baja deja de contar'
		);

		delete assets[1];
		System.assertEquals(
			'Local 1',
			subjectOf(policy.Id),
			'Con un solo bien vivo, lo nombra'
		);
	}

	@IsTest
	static void fleetIncisosUpdateThePolicyWithoutTouchingItsAssets() {
		InsurancePolicy policy = createPolicy('Inicial');
		List<Inciso_Flotilla__c> incisos = new List<Inciso_Flotilla__c>{
			new Inciso_Flotilla__c(Poliza__c = policy.Id, Numero_Inciso__c = 1),
			new Inciso_Flotilla__c(Poliza__c = policy.Id, Numero_Inciso__c = 2),
			new Inciso_Flotilla__c(Poliza__c = policy.Id, Numero_Inciso__c = 3)
		};

		Test.startTest();
		insert incisos;
		System.assertEquals(
			'Flotilla · 3 incisos',
			subjectOf(policy.Id),
			'El alta de incisos de flotilla se refleja sin bienes de la póliza'
		);
		update new Inciso_Flotilla__c(
			Id = incisos[2].Id,
			Fecha_Baja__c = Date.today()
		);
		System.assertEquals(
			'Flotilla · 2 incisos',
			subjectOf(policy.Id),
			'La baja del inciso deja de contar'
		);
		delete incisos[1];
		Test.stopTest();

		System.assertNotEquals(
			'Flotilla · 2 incisos',
			subjectOf(policy.Id),
			'El borrado del inciso también recalcula'
		);
	}

	@IsTest
	static void anExpiredPolicyKeepsItsAssetEvenIfInactive() {
		InsurancePolicy policy = createPolicy('Vencido');

		Test.startTest();
		insert new InsurancePolicyAsset(
			InsurancePolicyId = policy.Id,
			AssetName = 'NISSAN NP300 2024',
			IsActive = false
		);
		Test.stopTest();

		System.assertEquals(
			'NISSAN NP300 2024',
			subjectOf(policy.Id),
			'Con la póliza vencida, la casilla apagada no es una baja'
		);
	}

	@IsTest
	static void aCancelledPolicyKeepsTheAssetsClosedOnItsCancellation() {
		InsurancePolicy policy = createPolicy('Inicial');
		Date cancelledOn = Date.today().addDays(-10);
		insert new List<InsurancePolicyAsset>{
			new InsurancePolicyAsset(
				InsurancePolicyId = policy.Id,
				AssetName = 'AUTOPISTA MEXICO-ACAPULCO KM 21',
				IsActive = false,
				EffectiveToDate = cancelledOn
			),
			new InsurancePolicyAsset(
				InsurancePolicyId = policy.Id,
				AssetName = 'BODEGA DADA DE BAJA ANTES',
				IsActive = false,
				EffectiveToDate = cancelledOn.addDays(-20)
			)
		};

		Test.startTest();
		update new InsurancePolicy(
			Id = policy.Id,
			Status = 'Cancelado',
			CancellationDate = Datetime.newInstance(
				cancelledOn,
				Time.newInstance(6, 0, 0, 0)
			)
		);
		InsuredSubjectService.recalculate(new Set<Id>{ policy.Id });
		Test.stopTest();

		System.assertEquals(
			'AUTOPISTA MEXICO-ACAPULCO KM 21',
			subjectOf(policy.Id),
			'Lo que se cerró el día de la cancelación sigue a la vista; lo dado de baja antes, no'
		);
	}

	@IsTest
	static void peopleAreListedWithTheHolderFirst() {
		InsurancePolicy policy = createPolicy('Inicial');

		Test.startTest();
		insert new List<InsurancePolicyParticipant>{
			person(policy.Id, 'Ana López', 'Conyugue'),
			person(policy.Id, 'Juan Pérez', null),
			person(policy.Id, 'Luis Pérez', 'Hijo'),
			person(policy.Id, 'Juan  Pérez', null)
		};
		Test.stopTest();

		System.assertEquals(
			'Juan Pérez (titular), Ana López, Luis Pérez',
			subjectOf(policy.Id),
			'Titular primero y sin repetir nombres'
		);
	}

	@IsTest
	static void aSinglePersonIsJustTheName() {
		InsurancePolicy policy = createPolicy('Inicial');
		InsurancePolicyParticipant beneficiary = person(
			policy.Id,
			'Beneficiaria',
			null
		);
		beneficiary.Role = 'Beneficiario';

		Test.startTest();
		insert new List<InsurancePolicyParticipant>{
			person(policy.Id, 'Rocío González', null),
			beneficiary
		};
		Test.stopTest();

		System.assertEquals(
			'Rocío González',
			subjectOf(policy.Id),
			'Un beneficiario no es un asegurado'
		);
	}

	@IsTest
	static void certificatesMakeAGroupPolicyAndDropsUpdateIt() {
		InsurancePolicy policy = createPolicy('Inicial');
		List<InsurancePolicyParticipant> people = new List<InsurancePolicyParticipant>();
		for (Integer i = 1; i <= 3; i++) {
			InsurancePolicyParticipant p = person(policy.Id, 'Empleado ' + i, null);
			p.ParticipantCode = String.valueOf(i);
			people.add(p);
		}
		insert people;
		System.assertEquals(
			'Colectiva · 3 certificados',
			subjectOf(policy.Id),
			'Cuenta los certificados'
		);

		Test.startTest();
		update new InsurancePolicyParticipant(
			Id = people[0].Id,
			IsActiveParticipant = false
		);
		Test.stopTest();

		System.assertEquals(
			'Colectiva · 2 certificados',
			subjectOf(policy.Id),
			'La baja del certificado deja de contar'
		);
	}

	@IsTest
	static void namesThatDoNotFitAreSummarized() {
		List<String> names = new List<String>();
		for (Integer i = 0; i < 20; i++) {
			names.add('Asegurado con un nombre bastante largo ' + i);
		}

		String text = InsuredSubjectService.joinWithinLimit(names);

		System.assert(
			text.length() <= InsuredSubjectService.MAX_LENGTH,
			'Cabe en el campo'
		);
		System.assert(text.endsWith(' más'), 'Resume los que no caben: ' + text);
		System.assert(
			text.startsWith('Asegurado con un nombre bastante largo 0'),
			text
		);
	}

	@IsTest
	static void theBackfillFillsExistingPoliciesAndAFailureIsLogged() {
		InsurancePolicy filled = createPolicy('Inicial');
		InsurancePolicy failing = createPolicy('Inicial');
		insert new List<InsurancePolicyAsset>{
			new InsurancePolicyAsset(
				InsurancePolicyId = filled.Id,
				AssetName = 'Bien A',
				IsActive = true
			),
			new InsurancePolicyAsset(
				InsurancePolicyId = failing.Id,
				AssetName = 'Bien B',
				IsActive = true
			)
		};
		update new List<InsurancePolicy>{
			new InsurancePolicy(Id = filled.Id, insuredSubject__c = null),
			new InsurancePolicy(Id = failing.Id, insuredSubject__c = null)
		};
		InsuredSubjectService.failForTest.add(failing.Id);

		Test.startTest();
		InsuredSubjectBackfillBatch batch = new InsuredSubjectBackfillBatch();
		Database.executeBatch(batch, 200);
		Test.stopTest();

		System.assertEquals(
			'Bien A',
			subjectOf(filled.Id),
			'El relleno llena el campo'
		);
		System.assertEquals(
			null,
			subjectOf(failing.Id),
			'La que falla queda como estaba'
		);
		System.assertEquals(
			1,
			[
				SELECT COUNT()
				FROM AppLog__c
				WHERE eventCode__c = :CobranzaLog.EVENT_INSURED_SUBJECT_FAILED
			],
			'El fallo queda registrado'
		);
	}

	@IsTest
	static void aPolicyWithoutAssetsOrPeopleStaysEmpty() {
		InsurancePolicy policy = createPolicy('Inicial');

		Test.startTest();
		Integer saved = InsuredSubjectService.recalculate(
			new Set<Id>{ policy.Id, null }
		);
		Test.stopTest();

		System.assertEquals(0, saved, 'No hay nada que guardar');
		System.assertEquals(
			null,
			subjectOf(policy.Id),
			'Sin bien ni asegurado, vacío'
		);
	}
}
