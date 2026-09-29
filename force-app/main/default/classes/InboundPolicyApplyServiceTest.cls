@IsTest
private class InboundPolicyApplyServiceTest {
	private static Integer sequence = 0;

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
	 * @description: CA1/CA2/CA7. Con dos vigencias del mismo numero, los datos van a la que
	 *               contiene el inicio comunicado; las fechas quedan a medianoche de Mexico y
	 *               la otra vigencia no se toca.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void appliesDataToTheTermThatContainsTheStart() {
		InsurancePolicy previous = createPolicy(
			'0971000100',
			Date.newInstance(2025, 1, 15),
			Date.newInstance(2026, 1, 14)
		);
		InsurancePolicy current = createPolicy(
			'0971000100',
			Date.newInstance(2026, 1, 15),
			Date.newInstance(2027, 1, 15)
		);
		InboundPolicyUpdate__c communication = createCommunication(
			'0971000100',
			Date.newInstance(2026, 1, 15),
			System.now()
		);
		communication.sourcePolicyEndDate__c = Date.newInstance(2027, 1, 20);
		communication.sourcePolicyIssueDate__c = Date.newInstance(2026, 1, 10);
		communication.sourcePolicyRenewalDate__c = Date.newInstance(2027, 1, 15);
		communication.sourcePolicyBranch__c = 'Autos';
		communication.sourceNetPremium__c = 10000;
		communication.sourcePolicyFee__c = 500;
		communication.sourceFinancingCharge__c = 300;
		communication.sourceTaxAmount__c = 1600;
		communication.sourceDiscountPercent__c = 10;
		communication.sourceInsuredAssetDescription__c = '(I) VW JETTA 2024';
		communication.sourcePaymentMode__c = 'Tarjeta de credito';
		communication.sourceIntermediaryName__c = 'AVANZA SEGUROS';
		update communication;

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ communication.Id });
		Test.stopTest();

		InsurancePolicy saved = loadPolicy(current.Id);
		Assert.areEqual(
			PolicyStatusService.mexicoMidnight(Date.newInstance(2027, 1, 20)),
			saved.ExpirationDate
		);
		Assert.areEqual(
			PolicyStatusService.mexicoMidnight(Date.newInstance(2026, 1, 10)),
			saved.SaleDate
		);
		Assert.areEqual(
			PolicyStatusService.mexicoMidnight(Date.newInstance(2027, 1, 15)),
			saved.RenewalDate
		);
		Assert.areEqual('Automoviles', saved.Ramo__c);
		Assert.areEqual(Decimal.valueOf('10000.00'), saved.Subtotal__c);
		Assert.areEqual(Decimal.valueOf('500.00'), saved.Derecho_Poliza__c);
		Assert.areEqual(Decimal.valueOf('300.00'), saved.Financiamiento__c);
		Assert.areEqual(Decimal.valueOf('1600.00'), saved.IVA__c);
		Assert.isTrue(saved.Discount == 10, String.valueOf(saved.Discount));
		Assert.areEqual('(I) VW JETTA 2024', saved.insuredAssetDescription__c);
		Assert.areEqual('Tarjeta de credito', saved.carrierPaymentMode__c);
		Assert.areEqual('AVANZA SEGUROS', saved.sourceIntermediaryName__c);
		Assert.areEqual(communication.Id, saved.carrierPolicyUpdate__c);
		Assert.isNotNull(saved.carrierDataSyncedAt__c);

		Assert.areEqual(
			PolicyStatusService.mexicoMidnight(Date.newInstance(2026, 1, 14)),
			loadPolicy(previous.Id).ExpirationDate,
			'La otra vigencia no se toca'
		);

		InboundPolicyUpdate__c result = loadCommunication(communication.Id);
		Assert.areEqual('Aplicado', result.inboundStatus__c);
		Assert.areEqual(current.Id, result.candidatePolicy__c);
		Assert.areEqual('RESUELTO_POR_VIGENCIA', result.policyMatchReason__c);
		Assert.areEqual(1, countLogs(current.Id, 'POLICY_DATA_APPLIED'));
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA1. Sin una vigencia que contenga el inicio comunicado -aunque el numero
	 *               tenga una sola poliza-, o sin poliza, la comunicacion va a revision y no se
	 *               aplica nada.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void sendsToReviewWhenNoTermMatches() {
		InsurancePolicy only = createPolicy(
			'0971000200',
			Date.newInstance(2025, 1, 15),
			Date.newInstance(2026, 1, 14)
		);
		InboundPolicyUpdate__c renewal = createCommunication(
			'0971000200',
			Date.newInstance(2026, 1, 15),
			System.now()
		);
		renewal.sourceTotalPremium__c = 9999;
		update renewal;
		InboundPolicyUpdate__c unknown = createCommunication(
			'0971999999',
			Date.newInstance(2026, 1, 15),
			System.now()
		);

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ renewal.Id, unknown.Id });
		Test.stopTest();

		InboundPolicyUpdate__c renewalResult = loadCommunication(renewal.Id);
		Assert.areEqual('Revision Manual', renewalResult.inboundStatus__c);
		Assert.areEqual('SIN_VIGENCIA', renewalResult.policyMatchReason__c);
		Assert.isTrue(renewalResult.manualReviewRequired__c);
		Assert.isTrue(renewalResult.manualReviewReason__c.contains('renovacion'));
		Assert.areEqual(
			Decimal.valueOf('1200.00'),
			loadPolicy(only.Id).PremiumAmount,
			'La vigencia anterior no se pisa'
		);

		InboundPolicyUpdate__c unknownResult = loadCommunication(unknown.Id);
		Assert.areEqual('Revision Manual', unknownResult.inboundStatus__c);
		Assert.areEqual('SIN_POLIZA', unknownResult.policyMatchReason__c);
	}

	/**
	 * @creation date: 28/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: La renovacion empieza el mismo dia en que termina la vigencia actual (asi
	 *               emiten las aseguradoras). No se aplica a la vigencia que termina: va a
	 *               revision y la vigencia actual conserva sus fechas. Hallado al ensayar la
	 *               coleccion de Postman.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void renewalStartingOnTheEndDateGoesToReview() {
		InsurancePolicy current = createPolicy(
			'0971001400',
			Date.newInstance(2026, 1, 15),
			Date.newInstance(2027, 1, 15)
		);
		InboundPolicyUpdate__c renewal = createCommunication(
			'0971001400',
			Date.newInstance(2027, 1, 15),
			System.now()
		);
		renewal.sourcePolicyEndDate__c = Date.newInstance(2028, 1, 15);
		update renewal;

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ renewal.Id });
		Test.stopTest();

		Assert.areEqual(
			'SIN_VIGENCIA',
			loadCommunication(renewal.Id).policyMatchReason__c
		);
		Assert.areEqual(
			PolicyStatusService.mexicoMidnight(Date.newInstance(2027, 1, 15)),
			loadPolicy(current.Id).ExpirationDate,
			'La vigencia actual no se pisa con las fechas de la renovacion'
		);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA1. Si varias vigencias contienen el inicio, no se elige por descarte.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void sendsToReviewWhenSeveralTermsMatch() {
		createPolicy(
			'0971000300',
			Date.newInstance(2025, 1, 1),
			Date.newInstance(2026, 6, 30)
		);
		createPolicy(
			'0971000300',
			Date.newInstance(2026, 1, 1),
			Date.newInstance(2027, 1, 1)
		);
		InboundPolicyUpdate__c communication = createCommunication(
			'0971000300',
			Date.newInstance(2026, 2, 1),
			System.now()
		);

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ communication.Id });
		Test.stopTest();

		Assert.areEqual(
			'VIGENCIA_AMBIGUA',
			loadCommunication(communication.Id).policyMatchReason__c
		);
	}

	/**
	 * @creation date: 28/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Si MuleSoft manda el Id de la poliza que consulto y es coherente, se usa:
	 *               resuelve incluso dos vigencias que se solapan, donde la regla no elige.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void usesReportedIdWhenConsistent() {
		createPolicy(
			'0971001200',
			Date.newInstance(2025, 1, 1),
			Date.newInstance(2026, 6, 30)
		);
		InsurancePolicy second = createPolicy(
			'0971001200',
			Date.newInstance(2026, 1, 1),
			Date.newInstance(2027, 1, 1)
		);
		InboundPolicyUpdate__c communication = createCommunication(
			'0971001200',
			Date.newInstance(2026, 2, 1),
			System.now()
		);
		communication.sourcePolicyId__c = second.Id;
		communication.sourceNetPremium__c = 555;
		update communication;

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ communication.Id });
		Test.stopTest();

		InboundPolicyUpdate__c result = loadCommunication(communication.Id);
		Assert.areEqual('Aplicado', result.inboundStatus__c);
		Assert.areEqual('RESUELTO_POR_ID', result.policyMatchReason__c);
		Assert.areEqual(second.Id, result.candidatePolicy__c);
		Assert.areEqual(
			Decimal.valueOf('555.00'),
			loadPolicy(second.Id).Subtotal__c
		);
	}

	/**
	 * @creation date: 28/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Un Id que no cuadra con la comunicacion (el de la vigencia anterior cuando
	 *               llega la renovacion) no se usa: decide la regla y la vigencia anterior no
	 *               se toca.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void ignoresReportedIdWhenInconsistent() {
		InsurancePolicy previous = createPolicy(
			'0971001300',
			Date.newInstance(2025, 1, 15),
			Date.newInstance(2026, 1, 14)
		);
		InsurancePolicy current = createPolicy(
			'0971001300',
			Date.newInstance(2026, 1, 15),
			Date.newInstance(2027, 1, 15)
		);
		InboundPolicyUpdate__c communication = createCommunication(
			'0971001300',
			Date.newInstance(2026, 1, 15),
			System.now()
		);
		communication.sourcePolicyId__c = previous.Id;
		communication.sourceNetPremium__c = 777;
		update communication;

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ communication.Id });
		Test.stopTest();

		InboundPolicyUpdate__c result = loadCommunication(communication.Id);
		Assert.areEqual('RESUELTO_POR_VIGENCIA', result.policyMatchReason__c);
		Assert.areEqual(current.Id, result.candidatePolicy__c);
		Assert.isNull(
			loadPolicy(previous.Id).Subtotal__c,
			'La vigencia anterior no se toca'
		);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA3. Lo que calcula el motor (lo pagado, lo pendiente, las fechas de pago)
	 *               se queda en la comunicacion y no se escribe en la poliza.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void doesNotCopyCollectionData() {
		InsurancePolicy policy = createPolicy(
			'0971000400',
			Date.newInstance(2026, 1, 15),
			Date.newInstance(2027, 1, 15)
		);
		Datetime dueBefore = loadPolicy(policy.Id).PaymentDueDate;
		InboundPolicyUpdate__c communication = createCommunication(
			'0971000400',
			Date.newInstance(2026, 1, 15),
			System.now()
		);
		communication.sourcePaidPremium__c = 1200;
		communication.sourceOutstandingPremium__c = 0;
		communication.sourceLastPaymentDate__c = Date.newInstance(2026, 2, 1);
		communication.sourceNextDueDate__c = Date.newInstance(2026, 12, 1);
		update communication;

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ communication.Id });
		Test.stopTest();

		InsurancePolicy saved = loadPolicy(policy.Id);
		Assert.areEqual(dueBefore, saved.PaymentDueDate);
		Assert.areEqual(
			'Aplicado',
			loadCommunication(communication.Id).inboundStatus__c
		);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA4/CA5. «Contado» se traduce a Unico y, como la poliza no ha cobrado, el
	 *               plan se rehace. Una forma de pago sin equivalencia no cambia la poliza y se
	 *               registra.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void translatesPaymentFrequency() {
		InsurancePolicy cash = createPolicy(
			'0971000500',
			Date.newInstance(2026, 1, 15),
			Date.newInstance(2027, 1, 15)
		);
		InsurancePolicy odd = createPolicy(
			'0971000501',
			Date.newInstance(2026, 1, 15),
			Date.newInstance(2027, 1, 15)
		);
		InboundPolicyUpdate__c toCash = createCommunication(
			'0971000500',
			Date.newInstance(2026, 1, 15),
			System.now()
		);
		toCash.sourcePremiumFrequency__c = 'CONTADO';
		InboundPolicyUpdate__c toOdd = createCommunication(
			'0971000501',
			Date.newInstance(2026, 1, 15),
			System.now()
		);
		toOdd.sourcePremiumFrequency__c = 'Bimestral';
		update new List<InboundPolicyUpdate__c>{ toCash, toOdd };

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ toCash.Id, toOdd.Id });
		Test.stopTest();

		Assert.areEqual('Unico', loadPolicy(cash.Id).PremiumFrequency);
		Assert.areEqual(
			1,
			CollectionsTestDataFactory.getInstallmentsByPolicy(cash.Id).size(),
			'El plan sin cobros se rehizo con una sola cuota'
		);
		Assert.areEqual('Semestral', loadPolicy(odd.Id).PremiumFrequency);
		Assert.areEqual(1, countLogs(odd.Id, 'CARRIER_FREQUENCY_UNMAPPED'));
		Assert.areEqual('Aplicado', loadCommunication(toOdd.Id).inboundStatus__c);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA5. En una poliza que ya cobro, la prima nueva se escribe, el plan no se
	 *               toca y la poliza queda marcada (KAN-447).
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void marksPremiumMismatchOnPolicyWithCollections() {
		InsurancePolicy policy = createPolicy(
			'0971000600',
			Date.today().addMonths(-4),
			Date.today().addMonths(8)
		);
		reconcileFirstInstallment(policy.Id);
		InboundPolicyUpdate__c communication = createCommunication(
			'0971000600',
			Date.today().addMonths(-4),
			System.now()
		);
		communication.sourceTotalPremium__c = 1500;
		update communication;

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ communication.Id });
		Test.stopTest();

		InsurancePolicy saved = loadPolicy(policy.Id);
		Assert.areEqual(Decimal.valueOf('1500.00'), saved.PremiumAmount);
		Assert.isTrue(saved.planPremiumMismatch__c);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA6. Una moneda distinta de la de la poliza no escribe importes y manda la
	 *               comunicacion a revision.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void currencyMismatchGoesToReview() {
		InsurancePolicy policy = createPolicy(
			'0971000700',
			Date.newInstance(2026, 1, 15),
			Date.newInstance(2027, 1, 15)
		);
		policy.Moneda__c = 'MXN';
		update policy;
		InboundPolicyUpdate__c communication = createCommunication(
			'0971000700',
			Date.newInstance(2026, 1, 15),
			System.now()
		);
		communication.sourceCurrency__c = 'USD';
		communication.sourceTotalPremium__c = 100;
		update communication;

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ communication.Id });
		Test.stopTest();

		Assert.areEqual(
			Decimal.valueOf('1200.00'),
			loadPolicy(policy.Id).PremiumAmount
		);
		InboundPolicyUpdate__c result = loadCommunication(communication.Id);
		Assert.areEqual('Revision Manual', result.inboundStatus__c);
		Assert.isTrue(result.manualReviewReason__c.contains('moneda'));
		Assert.areEqual(policy.Id, result.candidatePolicy__c);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA8. Una poliza que no se puede guardar (aqui, un cambio de frecuencia que
	 *               el plan con cobros rechaza) no arrastra a las demas: su comunicacion va a
	 *               revision con el motivo y el fallo queda registrado.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void failureOnOnePolicyDoesNotStopTheOthers() {
		InsurancePolicy failing = createPolicy(
			'0971000800',
			Date.today().addMonths(-4),
			Date.today().addMonths(8)
		);
		reconcileFirstInstallment(failing.Id);
		InsurancePolicy healthy = createPolicy(
			'0971000801',
			Date.newInstance(2026, 1, 15),
			Date.newInstance(2027, 1, 15)
		);
		InboundPolicyUpdate__c toFailing = createCommunication(
			'0971000800',
			Date.today().addMonths(-4),
			System.now()
		);
		toFailing.sourcePremiumFrequency__c = 'Mensual';
		InboundPolicyUpdate__c toHealthy = createCommunication(
			'0971000801',
			Date.newInstance(2026, 1, 15),
			System.now()
		);
		toHealthy.sourceNetPremium__c = 1000;
		update new List<InboundPolicyUpdate__c>{ toFailing, toHealthy };

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ toFailing.Id, toHealthy.Id });
		Test.stopTest();

		InboundPolicyUpdate__c failed = loadCommunication(toFailing.Id);
		Assert.areEqual('Revision Manual', failed.inboundStatus__c);
		Assert.isTrue(
			failed.manualReviewReason__c.contains('No se pudo guardar la poliza')
		);
		Assert.areEqual('Semestral', loadPolicy(failing.Id).PremiumFrequency);
		Assert.areEqual(1, countLogs(failing.Id, 'POLICY_DATA_APPLY_FAILED'));
		Assert.areEqual(
			'Aplicado',
			loadCommunication(toHealthy.Id).inboundStatus__c
		);
		Assert.areEqual(
			Decimal.valueOf('1000.00'),
			loadPolicy(healthy.Id).Subtotal__c
		);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA9. Aplicar dos veces la misma comunicacion no cambia nada ni registra.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void applyingTwiceChangesNothing() {
		InsurancePolicy policy = createPolicy(
			'0971000900',
			Date.newInstance(2026, 1, 15),
			Date.newInstance(2027, 1, 15)
		);
		InboundPolicyUpdate__c communication = createCommunication(
			'0971000900',
			Date.newInstance(2026, 1, 15),
			System.now()
		);
		communication.sourceNetPremium__c = 1000;
		update communication;
		InboundPolicyApplyService.apply(new Set<Id>{ communication.Id });
		Datetime modifiedBefore = [
			SELECT LastModifiedDate
			FROM InsurancePolicy
			WHERE Id = :policy.Id
		]
		.LastModifiedDate;

		Test.startTest();
		update new InboundPolicyUpdate__c(
			Id = communication.Id,
			inboundStatus__c = 'Recibido'
		);
		InboundPolicyApplyService.apply(new Set<Id>{ communication.Id });
		Test.stopTest();

		Assert.areEqual(1, countLogs(policy.Id, 'POLICY_DATA_APPLIED'));
		Assert.areEqual(
			modifiedBefore,
			[SELECT LastModifiedDate FROM InsurancePolicy WHERE Id = :policy.Id]
			.LastModifiedDate
		);
		Assert.areEqual(
			'Aplicado',
			loadCommunication(communication.Id).inboundStatus__c
		);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: CA10. Solo gana la mas reciente: una comunicacion anterior a la ya
	 *               aplicada no cambia la poliza, y en un mismo lote se aplica la ultima.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void onlyTheMostRecentWins() {
		InsurancePolicy policy = createPolicy(
			'0971001000',
			Date.newInstance(2026, 1, 15),
			Date.newInstance(2027, 1, 15)
		);
		Datetime now = System.now();
		InboundPolicyUpdate__c older = createCommunication(
			'0971001000',
			Date.newInstance(2026, 1, 15),
			now.addDays(-2)
		);
		older.sourceNetPremium__c = 111;
		InboundPolicyUpdate__c newer = createCommunication(
			'0971001000',
			Date.newInstance(2026, 1, 15),
			now.addDays(-1)
		);
		newer.sourceNetPremium__c = 222;
		update new List<InboundPolicyUpdate__c>{ older, newer };
		InboundPolicyApplyService.apply(new Set<Id>{ older.Id, newer.Id });
		InboundPolicyUpdate__c late = createCommunication(
			'0971001000',
			Date.newInstance(2026, 1, 15),
			now.addDays(-3)
		);
		late.sourceNetPremium__c = 333;
		update late;

		Test.startTest();
		InboundPolicyApplyService.apply(new Set<Id>{ late.Id });
		Test.stopTest();

		Assert.areEqual(
			Decimal.valueOf('222.00'),
			loadPolicy(policy.Id).Subtotal__c
		);
		Assert.areEqual('Superada', loadCommunication(older.Id).inboundStatus__c);
		Assert.areEqual('Aplicado', loadCommunication(newer.Id).inboundStatus__c);
		Assert.areEqual('Superada', loadCommunication(late.Id).inboundStatus__c);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: De punta a punta: lo que entra por el endpoint se aplica solo.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void endpointAppliesWhatItReceives() {
		InsurancePolicy policy = createPolicy(
			'0971001100',
			Date.newInstance(2026, 1, 15),
			Date.newInstance(2027, 1, 15)
		);
		RestRequest request = new RestRequest();
		request.requestBody = Blob.valueOf(
			'[{"sourcePolicyNumber__c":"0971001100","sourceCarrierCode__c":"QUALITAS",' +
			'"sourcePolicyStartDate__c":"2026-01-15","sourceNetPremium__c":987}]'
		);
		RestContext.request = request;
		RestContext.response = new RestResponse();

		Test.startTest();
		InboundPolicyRestResource.receive();
		Test.stopTest();

		Assert.areEqual(202, RestContext.response.statusCode);
		Assert.areEqual(
			Decimal.valueOf('987.00'),
			loadPolicy(policy.Id).Subtotal__c
		);
		Assert.areEqual(
			'Aplicado',
			[SELECT inboundStatus__c FROM InboundPolicyUpdate__c LIMIT 1]
			.inboundStatus__c
		);
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Las equivalencias no distinguen mayusculas, acentos ni separadores.
	 * @param:
	 * @return:
	 * @exception:
	 * @throws:
	 */
	@IsTest
	static void normalizesKeys() {
		Assert.areEqual(
			'GASTOSMEDICOS',
			InboundPolicyApplyService.normalizeKey(' Gastos Médicos ')
		);
		Assert.areEqual('DANOS', InboundPolicyApplyService.normalizeKey('daños'));
	}

	private static InsurancePolicy createPolicy(
		String policyNumber,
		Date startDate,
		Date endDate
	) {
		InsurancePolicy policy = CollectionsTestDataFactory.buildCompletePolicy(
			CollectionsTestDataFactory.getDefaultInsuredAccountId(),
			'Vigente',
			'Semestral',
			1200,
			startDate
		);
		policy.Name = policyNumber;
		policy.EffectiveDate = PolicyStatusService.mexicoMidnight(startDate);
		policy.ExpirationDate = PolicyStatusService.mexicoMidnight(endDate);
		insert policy;
		return policy;
	}

	private static InboundPolicyUpdate__c createCommunication(
		String policyNumber,
		Date startDate,
		Datetime synchronizedAt
	) {
		sequence++;
		InboundPolicyUpdate__c communication = new InboundPolicyUpdate__c(
			sourcePolicyNumber__c = policyNumber,
			sourcePolicyStartDate__c = startDate,
			sourceCarrierCode__c = 'QUALITAS',
			sourceSynchronizedAt__c = synchronizedAt,
			inboundStatus__c = 'Recibido',
			contentFingerprint__c = 'prueba-' + policyNumber + '-' + sequence,
			receivedAt__c = System.now()
		);
		insert communication;
		return communication;
	}

	private static void reconcileFirstInstallment(Id policyId) {
		PaymentPlanInstallment__c first = CollectionsTestDataFactory.getInstallmentsByPolicy(
			policyId
		)[0];
		first.installmentStatus__c = 'Conciliado';
		update first;
	}

	private static InsurancePolicy loadPolicy(Id policyId) {
		return [
			SELECT
				PremiumAmount,
				PremiumFrequency,
				PaymentDueDate,
				EffectiveDate,
				ExpirationDate,
				SaleDate,
				RenewalDate,
				Ramo__c,
				Subtotal__c,
				Derecho_Poliza__c,
				Financiamiento__c,
				IVA__c,
				Discount,
				insuredAssetDescription__c,
				carrierPaymentMode__c,
				sourceIntermediaryName__c,
				carrierDataSyncedAt__c,
				carrierPolicyUpdate__c,
				planPremiumMismatch__c
			FROM InsurancePolicy
			WHERE Id = :policyId
		];
	}

	private static InboundPolicyUpdate__c loadCommunication(Id communicationId) {
		return [
			SELECT
				inboundStatus__c,
				candidatePolicy__c,
				policyMatchReason__c,
				manualReviewRequired__c,
				manualReviewReason__c
			FROM InboundPolicyUpdate__c
			WHERE Id = :communicationId
		];
	}

	private static Integer countLogs(Id recordId, String eventCode) {
		return [
			SELECT COUNT()
			FROM AppLog__c
			WHERE recordId__c = :recordId AND eventCode__c = :eventCode
		];
	}
}
