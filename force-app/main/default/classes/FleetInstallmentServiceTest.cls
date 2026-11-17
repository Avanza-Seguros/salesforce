@IsTest
private class FleetInstallmentServiceTest {
	private static final String EVENT_REVIEW = 'INSTALLMENTS_BY_INCISO_REVIEW';

	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: La pantalla de emisión crea la póliza (y su plan) y después sus incisos: el
	 *               plan sin cobros se rehace con una cuota por inciso y periodo, repartida por la
	 *               prima de cada inciso. El total del periodo no cambia.
	 */
	@IsTest
	static void aPlanWithoutCollectionsIsSplitByIncisoPremium() {
		InsurancePolicy policy = createPolicy('Semestral', 12000);

		Test.startTest();
		insert new List<InsurancePolicyAsset>{
			asset(policy.Id, '1', 8000),
			asset(policy.Id, '2', 4000)
		};
		Test.stopTest();

		List<PaymentPlanInstallment__c> installments = installmentsOf(policy.Id);
		Assert.areEqual(4, installments.size(), 'Dos periodos por dos incisos');
		Assert.areEqual('1', installments[0].policyAsset__r.AssetCode);
		Assert.areEqual(
			Decimal.valueOf('4000.00'),
			installments[0].expectedAmount__c
		);
		Assert.areEqual('2', installments[1].policyAsset__r.AssetCode);
		Assert.areEqual(
			Decimal.valueOf('2000.00'),
			installments[1].expectedAmount__c
		);
		Assert.areEqual(installments[0].dueDate__c, installments[1].dueDate__c);
		Assert.areEqual(
			installments[0].sequenceNumber__c,
			installments[1].sequenceNumber__c
		);
		Assert.areEqual(
			Decimal.valueOf('12000.00'),
			CollectionsTestDataFactory.sumExpectedAmounts(installments)
		);
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Sin la prima de algún inciso, el periodo se reparte en partes iguales y la
	 *               última cuota se queda con el redondeo.
	 */
	@IsTest
	static void withoutPremiumsThePeriodIsSplitEvenly() {
		InsurancePolicy policy = createPolicy('Anual', 10000);

		Test.startTest();
		insert new List<InsurancePolicyAsset>{
			asset(policy.Id, '1', null),
			asset(policy.Id, '2', null),
			asset(policy.Id, '3', null)
		};
		Test.stopTest();

		List<PaymentPlanInstallment__c> installments = installmentsOf(policy.Id);
		Assert.areEqual(3, installments.size());
		Assert.areEqual(
			Decimal.valueOf('3333.33'),
			installments[0].expectedAmount__c
		);
		Assert.areEqual(
			Decimal.valueOf('3333.33'),
			installments[1].expectedAmount__c
		);
		Assert.areEqual(
			Decimal.valueOf('3333.34'),
			installments[2].expectedAmount__c
		);
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Si el bien no trae prima, se usa la del inciso de flotilla con el mismo número
	 *               (la pantalla de flotillas la guarda ahí).
	 */
	@IsTest
	static void theFleetIncisoPremiumFillsTheGap() {
		InsurancePolicy policy = createPolicy('Anual', 9000);
		insert new List<Inciso_Flotilla__c>{
			new Inciso_Flotilla__c(
				Poliza__c = policy.Id,
				Numero_Inciso__c = 1,
				Prima__c = 6000
			),
			new Inciso_Flotilla__c(
				Poliza__c = policy.Id,
				Numero_Inciso__c = 2,
				Prima__c = 3000
			)
		};

		Test.startTest();
		insert new List<InsurancePolicyAsset>{
			asset(policy.Id, '1', null),
			asset(policy.Id, '2', null)
		};
		Test.stopTest();

		List<PaymentPlanInstallment__c> installments = installmentsOf(policy.Id);
		Assert.areEqual(2, installments.size());
		Assert.areEqual(
			Decimal.valueOf('6000.00'),
			installments[0].expectedAmount__c
		);
		Assert.areEqual(
			Decimal.valueOf('3000.00'),
			installments[1].expectedAmount__c
		);
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Una póliza con un solo bien sigue con su plan de siempre, sin inciso.
	 */
	@IsTest
	static void aSingleAssetDoesNotSplitThePlan() {
		InsurancePolicy policy = createPolicy('Semestral', 6000);

		Test.startTest();
		insert asset(policy.Id, '1', 6000);
		Test.stopTest();

		List<PaymentPlanInstallment__c> installments = installmentsOf(policy.Id);
		Assert.areEqual(2, installments.size());
		Assert.isNull(installments[0].policyAsset__c);
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Un inciso dado de alta en una flotilla ya repartida recibe sus cuotas (su
	 *               prima entre el número de cuotas). Cuando la pantalla de endosos le pone
	 *               después la fecha del alta, sobra la cuota del periodo anterior.
	 */
	@IsTest
	static void anAltaGetsItsInstallmentsFromItsPeriod() {
		InsurancePolicy policy = createPolicy('Semestral', 12000);
		insert new List<InsurancePolicyAsset>{
			asset(policy.Id, '1', 6000),
			asset(policy.Id, '2', 6000)
		};
		Date firstDueDate = installmentsOf(policy.Id)[0].dueDate__c;

		Test.startTest();
		InsurancePolicyAsset alta = asset(policy.Id, '3', 1200);
		alta.EffectiveFromDate = firstDueDate;
		insert alta;
		Assert.areEqual(2, installmentsOfAsset(alta.Id).size(), 'Una por periodo');
		Assert.areEqual(
			Decimal.valueOf('600.00'),
			installmentsOfAsset(alta.Id)[0].expectedAmount__c
		);

		alta.EffectiveFromDate = firstDueDate.addMonths(7);
		update alta;
		Test.stopTest();

		List<PaymentPlanInstallment__c> own = installmentsOfAsset(alta.Id);
		Assert.areEqual(
			1,
			own.size(),
			'El primer periodo ya había pasado al darse de alta'
		);
		Assert.areEqual(firstDueDate.addMonths(6), own[0].dueDate__c);
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Un inciso dado de baja cancela sus cuotas sin cobro que vencen después de la
	 *               baja; las de antes no cambian.
	 */
	@IsTest
	static void aBajaCancelsTheInstallmentsAfterIt() {
		InsurancePolicy policy = createPolicy('Semestral', 12000);
		InsurancePolicyAsset first = asset(policy.Id, '1', 6000);
		InsurancePolicyAsset second = asset(policy.Id, '2', 6000);
		insert new List<InsurancePolicyAsset>{ first, second };
		Date firstDueDate = installmentsOf(policy.Id)[0].dueDate__c;

		Test.startTest();
		second.IsActive = false;
		second.EffectiveToDate = firstDueDate.addDays(1);
		update second;
		Test.stopTest();

		List<PaymentPlanInstallment__c> own = installmentsOfAsset(second.Id);
		Assert.areEqual(2, own.size());
		Assert.areEqual('Pendiente', own[0].installmentStatus__c);
		Assert.areEqual('Cancelado', own[1].installmentStatus__c);
		for (PaymentPlanInstallment__c inst : installmentsOfAsset(first.Id)) {
			Assert.areEqual(
				'Pendiente',
				inst.installmentStatus__c,
				'El otro inciso no cambia'
			);
		}
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Las cuotas que vienen de la aseguradora son la fuente de la verdad: no se
	 *               reparten aunque la póliza tenga incisos.
	 */
	@IsTest
	static void carrierInstallmentsAreNotTouched() {
		InsurancePolicy policy = createPolicy('Semestral', 12000);
		List<PaymentPlanInstallment__c> loaded = installmentsOf(policy.Id);
		for (PaymentPlanInstallment__c inst : loaded) {
			inst.dataOrigin__c = 'Handle';
		}
		update loaded;

		Test.startTest();
		insert new List<InsurancePolicyAsset>{
			asset(policy.Id, '1', 6000),
			asset(policy.Id, '2', 6000)
		};
		Test.stopTest();

		List<PaymentPlanInstallment__c> installments = installmentsOf(policy.Id);
		Assert.areEqual(2, installments.size());
		Assert.isNull(installments[0].policyAsset__c);
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Un plan que ya cobró no se rehace: queda un aviso para revisarlo.
	 */
	@IsTest
	static void aPlanWithCollectionsIsLeftForReview() {
		InsurancePolicy policy = createPolicy('Semestral', 12000);
		PaymentPlanInstallment__c paid = installmentsOf(policy.Id)[0];
		paid.installmentStatus__c = 'Conciliado';
		update paid;

		Test.startTest();
		insert new List<InsurancePolicyAsset>{
			asset(policy.Id, '1', 6000),
			asset(policy.Id, '2', 6000)
		};
		Test.stopTest();

		List<PaymentPlanInstallment__c> installments = installmentsOf(policy.Id);
		Assert.areEqual(2, installments.size());
		Assert.isNull(installments[0].policyAsset__c);
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM AppLog__c
				WHERE recordId__c = :policy.Id AND eventCode__c = :EVENT_REVIEW
			]
		);
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: El inciso que manda la aseguradora en su campo propio decide qué cuotas puede
	 *               tomar el pago; sin él se usa el certificado del número de póliza.
	 */
	@IsTest
	static void thePaymentIncisoFieldPicksItsInstallments() {
		PaymentPlanInstallment__c first = installmentOfInciso('1');
		PaymentPlanInstallment__c second = installmentOfInciso('2');
		List<PaymentPlanInstallment__c> both = new List<PaymentPlanInstallment__c>{
			first,
			second
		};

		List<PaymentPlanInstallment__c> byField = FleetIncisoService.onlyItsInciso(
			'3201-00033679-00',
			'002',
			both
		);
		Assert.areEqual(1, byField.size());
		Assert.areEqual(second, byField[0]);

		Assert.areEqual(
			2,
			FleetIncisoService.onlyItsInciso('3201-00033679-00', null, both).size(),
			'Sin inciso no se filtra'
		);
		Assert.areEqual(
			first,
			FleetIncisoService.onlyItsInciso('49-4785-1', ' ', both)[0],
			'Sin campo, manda el certificado de HDI'
		);
	}

	private static InsurancePolicy createPolicy(
		String frequency,
		Decimal premium
	) {
		return CollectionsTestDataFactory.createOperationalPolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			frequency,
			premium,
			Date.today().addDays(10)
		);
	}

	private static InsurancePolicyAsset asset(
		Id policyId,
		String code,
		Decimal premium
	) {
		return new InsurancePolicyAsset(
			InsurancePolicyId = policyId,
			AssetName = 'Inciso ' + code + ' - VEHICULO QA ' + code,
			AssetCode = code,
			IsActive = true,
			StandardPremiumAmount = premium
		);
	}

	private static PaymentPlanInstallment__c installmentOfInciso(String code) {
		String fakeId =
			InsurancePolicyAsset.SObjectType.getDescribe().getKeyPrefix() +
			'00000000000' +
			code;
		return new PaymentPlanInstallment__c(
			policyAsset__c = Id.valueOf(fakeId),
			policyAsset__r = new InsurancePolicyAsset(AssetCode = code)
		);
	}

	private static List<PaymentPlanInstallment__c> installmentsOf(Id policyId) {
		return [
			SELECT
				Id,
				policyAsset__c,
				policyAsset__r.AssetCode,
				dueDate__c,
				sequenceNumber__c,
				expectedAmount__c,
				installmentStatus__c
			FROM PaymentPlanInstallment__c
			WHERE paymentPlan__r.insurancePolicy__c = :policyId
			ORDER BY dueDate__c, policyAsset__r.AssetCode
		];
	}

	private static List<PaymentPlanInstallment__c> installmentsOfAsset(
		Id assetId
	) {
		return [
			SELECT Id, dueDate__c, expectedAmount__c, installmentStatus__c
			FROM PaymentPlanInstallment__c
			WHERE policyAsset__c = :assetId
			ORDER BY dueDate__c
		];
	}
}
