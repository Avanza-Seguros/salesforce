/**
 *   @name: FleetIncisoServiceTest
 *   @version: 1.0
 *   @creation date: 08/11/2026
 *   @author: Javier Torres - Volestra
 *   @description: Valida que el pago de un certificado de flotilla encuentre su póliza madre y la
 *                 cuota de su inciso, y que un recibo quede ligado a su bien o a su persona.
 */
@IsTest
private class FleetIncisoServiceTest {
	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
		insert new List<Aseguradora__c>{
			new Aseguradora__c(Name = 'HDI Seguros'),
			new Aseguradora__c(Name = 'Otra Aseguradora')
		};
	}

	private static Id carrier(String name) {
		return [SELECT Id FROM Aseguradora__c WHERE Name = :name].Id;
	}

	private static InsurancePolicy policy(String num, String carrierName) {
		InsurancePolicy p = new InsurancePolicy(
			Name = num,
			PolicyName = 'Flotilla ' + num,
			NameInsuredId = CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			Aseguradora__c = carrier(carrierName),
			Status = 'Inicial',
			PremiumAmount = 1000,
			PremiumFrequency = 'Mensual',
			PaymentDueDate = Date.today(),
			EffectiveDate = Datetime.now().addDays(-30),
			ExpirationDate = Datetime.now().addDays(335)
		);
		insert p;
		return p;
	}

	private static InboundInsurancePayment__c inbound(
		String externalId,
		String policyNumber,
		Id candidatePolicyId,
		Date dueDate
	) {
		InboundInsurancePayment__c rec = new InboundInsurancePayment__c(
			externalPaymentId__c = externalId,
			inboundStatus__c = 'Normalizado',
			sourceAmount__c = 500,
			sourcePaymentDate__c = Date.today(),
			sourcePolicyNumber__c = policyNumber,
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now(),
			parsedAt__c = System.now(),
			candidatePolicy__c = candidatePolicyId,
			sourceDueDate__c = dueDate
		);
		insert rec;
		return rec;
	}

	private static PaymentPlan__c freshPlan(Id policyId) {
		List<PaymentPlan__c> auto = [
			SELECT Id
			FROM PaymentPlan__c
			WHERE insurancePolicy__c = :policyId
		];
		if (!auto.isEmpty()) {
			delete [
				SELECT Id
				FROM PaymentPlanInstallment__c
				WHERE paymentPlan__c IN :auto
			];
			delete auto;
		}
		PaymentPlan__c plan = new PaymentPlan__c(
			insurancePolicy__c = policyId,
			planStatus__c = 'Activo',
			premiumFrequency__c = 'Mensual',
			expectedTotalAmount__c = 1200,
			firstDueDate__c = Date.today()
		);
		insert plan;
		return plan;
	}

	private static PaymentPlanInstallment__c receipt(
		Id planId,
		Integer seq,
		Date dueDate,
		Id assetId
	) {
		return new PaymentPlanInstallment__c(
			paymentPlan__c = planId,
			sequenceNumber__c = seq,
			dueDate__c = dueDate,
			expectedAmount__c = 500,
			installmentStatus__c = 'Pendiente',
			policyAsset__c = assetId
		);
	}

	@IsTest
	static void readsTheCertificateOfAnHdiNumber() {
		Assert.areEqual('49-4785', FleetIncisoService.fleetNumberOf('49-4785-42'));
		Assert.areEqual('42', FleetIncisoService.certificateOf(' 49-4785-042 '));
		Assert.isNull(FleetIncisoService.certificateOf('3201-00033679-00'));
		Assert.isNull(FleetIncisoService.certificateOf('49-4785'));
		Assert.isNull(FleetIncisoService.fleetNumberOf(null));
		Assert.areEqual('7', FleetIncisoService.normalize('007'));
		Assert.areEqual('0', FleetIncisoService.normalize('000'));
		Assert.areEqual('A-1', FleetIncisoService.normalize(' a-1 '));
		Assert.isNull(FleetIncisoService.normalize('  '));
	}

	@IsTest
	static void theIncisoComesFromAssetCodeOrTheNamePrefix() {
		Assert.areEqual(
			'3',
			FleetIncisoService.incisoOf(
				new InsurancePolicyAsset(
					AssetCode = '03',
					AssetName = 'Inciso 9 - Local'
				)
			),
			'AssetCode manda'
		);
		Assert.areEqual(
			'9',
			FleetIncisoService.incisoOf(
				new InsurancePolicyAsset(AssetName = 'Inciso 9 - Av. Vallarta 1340')
			),
			'Sin AssetCode, el prefijo del nombre'
		);
		Assert.isNull(
			FleetIncisoService.incisoOf(
				new InsurancePolicyAsset(AssetName = 'KIA RIO 2020')
			)
		);
		Assert.isNull(FleetIncisoService.incisoOf((InsurancePolicyAsset) null));
		Assert.isNull(
			FleetIncisoService.incisoOf(new PaymentPlanInstallment__c()),
			'Un recibo sin inciso'
		);
	}

	@IsTest
	static void aCertificatePaymentFindsItsFleetPolicy() {
		InsurancePolicy fleet = policy('49-4785', 'HDI Seguros');
		InsurancePolicy individual = policy('49-43035-1', 'HDI Seguros');
		policy('77-100', 'Otra Aseguradora');
		InboundInsurancePayment__c certificate = inbound(
			'EXT-1',
			'49-4785-42',
			null,
			null
		);
		InboundInsurancePayment__c own = inbound('EXT-2', '49-43035-1', null, null);
		InboundInsurancePayment__c otherCarrier = inbound(
			'EXT-3',
			'77-100-5',
			null,
			null
		);

		Test.startTest();
		System.enqueueJob(
			new InboundPolicyCandidateQueueable(
				new Set<Id>{ certificate.Id, own.Id, otherCarrier.Id }
			)
		);
		Test.stopTest();

		Map<Id, InboundInsurancePayment__c> after = new Map<Id, InboundInsurancePayment__c>(
			[
				SELECT candidatePolicy__c, policyMatchReason__c
				FROM InboundInsurancePayment__c
			]
		);
		Assert.areEqual(fleet.Id, after.get(certificate.Id).candidatePolicy__c);
		Assert.areEqual(
			'CERTIFICADO_DE_FLOTILLA',
			after.get(certificate.Id).policyMatchReason__c
		);
		Assert.areEqual(
			individual.Id,
			after.get(own.Id).candidatePolicy__c,
			'Con el número exacto, su propia póliza'
		);
		Assert.areEqual('UNICO_GANADOR', after.get(own.Id).policyMatchReason__c);
		Assert.isNull(
			after.get(otherCarrier.Id).candidatePolicy__c,
			'Solo HDI separa el certificado'
		);
	}

	@IsTest
	static void aCertificatePaymentTakesTheReceiptOfItsInciso() {
		InsurancePolicy fleet = policy('49-5277', 'HDI Seguros');
		List<InsurancePolicyAsset> assets = new List<InsurancePolicyAsset>{
			new InsurancePolicyAsset(
				InsurancePolicyId = fleet.Id,
				AssetName = 'Local 1',
				AssetCode = '1',
				IsActive = true
			),
			new InsurancePolicyAsset(
				InsurancePolicyId = fleet.Id,
				AssetName = 'Local 2',
				AssetCode = '2',
				IsActive = true
			)
		};
		insert assets;
		PaymentPlan__c plan = freshPlan(fleet.Id);
		Date due = Date.today().addDays(10);
		List<PaymentPlanInstallment__c> receipts = new List<PaymentPlanInstallment__c>{
			receipt(plan.Id, 1, due, assets[0].Id),
			receipt(plan.Id, 2, due, assets[1].Id)
		};
		insert receipts;
		InboundInsurancePayment__c second = inbound(
			'EXT-4',
			'49-5277-2',
			fleet.Id,
			due
		);
		InboundInsurancePayment__c whole = inbound(
			'EXT-5',
			'49-5277',
			fleet.Id,
			due
		);

		Test.startTest();
		System.enqueueJob(
			new InboundInstallmentCandidateQueueable(
				new Set<Id>{ second.Id, whole.Id }
			)
		);
		Test.stopTest();

		Map<Id, InboundInsurancePayment__c> after = new Map<Id, InboundInsurancePayment__c>(
			[
				SELECT candidateInstallment__c
				FROM InboundInsurancePayment__c
			]
		);
		Assert.areEqual(
			receipts[1].Id,
			after.get(second.Id).candidateInstallment__c,
			'Toma el recibo del inciso 2'
		);
		Assert.isNull(
			after.get(whole.Id).candidateInstallment__c,
			'Sin certificado, los dos recibos empatan como siempre'
		);
	}

	@IsTest
	static void aReceiptBelongsToAnAssetOrAPersonNotBoth() {
		InsurancePolicy fleet = policy('49-5240', 'HDI Seguros');
		InsurancePolicyAsset asset = new InsurancePolicyAsset(
			InsurancePolicyId = fleet.Id,
			AssetName = 'Local 1',
			IsActive = true
		);
		insert asset;
		InsurancePolicyParticipant person = new InsurancePolicyParticipant(
			InsurancePolicyId = fleet.Id,
			PrimaryParticipantAccountId = CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			Role = 'Asegurado'
		);
		insert person;
		PaymentPlan__c plan = freshPlan(fleet.Id);
		PaymentPlanInstallment__c both = receipt(
			plan.Id,
			1,
			Date.today(),
			asset.Id
		);
		both.policyParticipant__c = person.Id;

		Test.startTest();
		Database.SaveResult saved = Database.insert(both, false);
		Test.stopTest();

		Assert.isFalse(saved.isSuccess(), 'No puede apuntar a los dos');
	}

	@IsTest
	static void anAssetWithReceiptsCannotBeDeleted() {
		InsurancePolicy fleet = policy('49-5227', 'HDI Seguros');
		InsurancePolicyAsset asset = new InsurancePolicyAsset(
			InsurancePolicyId = fleet.Id,
			AssetName = 'Local 1',
			IsActive = true
		);
		insert asset;
		insert receipt(freshPlan(fleet.Id).Id, 1, Date.today(), asset.Id);

		Test.startTest();
		Database.DeleteResult result = Database.delete(asset, false);
		Test.stopTest();

		Assert.isFalse(
			result.isSuccess(),
			'Un bien con recibos se da de baja, no se borra'
		);
	}
}
