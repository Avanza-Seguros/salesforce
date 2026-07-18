/**
 *   @name: PaymentReconciliationManualServiceTest
 *   @version: 1.0
 *   @creation date: 18/07/2026
 *   @author: Javier Torres - Volestra
 *   @description: Valida la aprobacion manual de conciliaciones (H193): sellado de la
 *                 decision manual y trazabilidad, creacion del recibo reutilizando el
 *                 motor, cascada al inbound, las validaciones de bloqueo, la consulta de
 *                 cuotas abiertas y el guardail anti-reentrada que protege la decision
 *                 manual frente a una re-corrida del pipeline.
 */
@IsTest
private class PaymentReconciliationManualServiceTest {
	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
	}

	@IsTest
	static void approveSealsDecisionAndCreatesReceipt() {
		Scenario sc = buildScenario('POL-193-001', 'Requiere revision');

		Test.startTest();
		PaymentReconciliationManualService.approveReconciliation(
			sc.recon.Id,
			sc.policy.Id,
			sc.installment.Id,
			'Comprobante validado por el analista'
		);
		Test.stopTest();

		PaymentReconciliation__c recon = [
			SELECT
				reconciliationStatus__c,
				matchMethod__c,
				manualResolvedBy__c,
				manualResolvedAt__c,
				paymentPlanInstallment__c,
				paymentPlan__c,
				insurancePolicy__c,
				resultingReceipt__c,
				decisionNotes__c
			FROM PaymentReconciliation__c
			WHERE Id = :sc.recon.Id
		];
		Assert.areEqual('Conciliado', recon.reconciliationStatus__c);
		Assert.areEqual('Decision manual', recon.matchMethod__c);
		Assert.areEqual(UserInfo.getUserId(), recon.manualResolvedBy__c);
		Assert.isNotNull(recon.manualResolvedAt__c);
		Assert.areEqual(sc.installment.Id, recon.paymentPlanInstallment__c);
		Assert.areEqual(sc.policy.Id, recon.insurancePolicy__c);
		Assert.isNotNull(recon.resultingReceipt__c, 'Debe generarse el recibo');
		Assert.isTrue(
			recon.decisionNotes__c.contains('Comprobante validado'),
			'Las notas deben conservar la justificacion'
		);

		List<PolicyPaymentReceipt__c> receipts = [
			SELECT receiptStatus__c, receiptAmount__c
			FROM PolicyPaymentReceipt__c
			WHERE paymentReconciliation__c = :sc.recon.Id
		];
		Assert.areEqual(1, receipts.size());
		Assert.areEqual('Reconocido', receipts[0].receiptStatus__c);

		InboundInsurancePayment__c inbound = [
			SELECT inboundStatus__c
			FROM InboundInsurancePayment__c
			WHERE Id = :sc.inbound.Id
		];
		Assert.areEqual('Conciliado', inbound.inboundStatus__c);
	}

	@IsTest
	static void approveFailsWhenPolicyMissing() {
		Scenario sc = buildScenario('POL-193-002', 'Requiere revision');
		assertBlocked(sc.recon.Id, null, sc.installment.Id, 'póliza');
	}

	@IsTest
	static void approveFailsWhenInstallmentMissing() {
		Scenario sc = buildScenario('POL-193-003', 'Requiere revision');
		assertBlocked(sc.recon.Id, sc.policy.Id, null, 'cuota');
	}

	@IsTest
	static void approveFailsWhenAlreadyClosed() {
		Scenario sc = buildScenario('POL-193-004', 'Conciliado');
		assertBlocked(sc.recon.Id, sc.policy.Id, sc.installment.Id, 'cerrada');
	}

	@IsTest
	static void approveFailsWhenReceiptAlreadyExists() {
		Scenario sc = buildScenario('POL-193-005', 'Requiere revision');
		PolicyPaymentReceipt__c receipt = new PolicyPaymentReceipt__c(
			insurancePolicy__c = sc.policy.Id,
			paymentReconciliation__c = sc.recon.Id,
			receiptAmount__c = 400,
			receiptDate__c = Date.today(),
			receiptStatus__c = 'Reconocido'
		);
		insert receipt;
		sc.recon.resultingReceipt__c = receipt.Id;
		update sc.recon;

		assertBlocked(sc.recon.Id, sc.policy.Id, sc.installment.Id, 'recibo');
	}

	@IsTest
	static void approveFailsWhenInstallmentNotInPolicy() {
		Scenario sc = buildScenario('POL-193-006', 'Requiere revision');
		Scenario other = buildScenario('POL-193-006B', 'Requiere revision');
		assertBlocked(
			sc.recon.Id,
			sc.policy.Id,
			other.installment.Id,
			'no pertenece'
		);
	}

	@IsTest
	static void approveFailsWhenInstallmentNotOpen() {
		Scenario sc = buildScenario('POL-193-007', 'Requiere revision');
		sc.installment.installmentStatus__c = 'Conciliado';
		update sc.installment;
		assertBlocked(sc.recon.Id, sc.policy.Id, sc.installment.Id, 'abierta');
	}

	@IsTest
	static void approveFailsWhenInstallmentAlreadyHasReceipt() {
		Scenario sc = buildScenario('POL-193-008', 'Requiere revision');
		PolicyPaymentReceipt__c receipt = new PolicyPaymentReceipt__c(
			insurancePolicy__c = sc.policy.Id,
			paymentReconciliation__c = sc.recon.Id,
			receiptAmount__c = 400,
			receiptDate__c = Date.today(),
			receiptStatus__c = 'Reconocido'
		);
		insert receipt;
		sc.installment.matchedReceipt__c = receipt.Id;
		update sc.installment;

		assertBlocked(sc.recon.Id, sc.policy.Id, sc.installment.Id, 'vinculado');
	}

	@IsTest
	static void publicApproveWrapsErrorAsAuraHandled() {
		Scenario sc = buildScenario('POL-193-009', 'Requiere revision');
		Boolean thrown = false;
		try {
			PaymentReconciliationManualService.approve(
				sc.recon.Id,
				null,
				sc.installment.Id,
				'x'
			);
		} catch (AuraHandledException e) {
			thrown = true;
		}
		Assert.isTrue(
			thrown,
			'El wrapper AuraEnabled debe lanzar AuraHandledException'
		);
	}

	@IsTest
	static void getOpenInstallmentsReturnsOnlyOpen() {
		Scenario sc = buildScenario('POL-193-010', 'Requiere revision');
		// Una segunda cuota conciliada no debe aparecer.
		PaymentPlanInstallment__c closed = new PaymentPlanInstallment__c(
			paymentPlan__c = sc.plan.Id,
			sequenceNumber__c = 2,
			dueDate__c = Date.today().addDays(60),
			expectedAmount__c = 400,
			installmentStatus__c = 'Conciliado'
		);
		insert closed;

		Test.startTest();
		List<PaymentPlanInstallment__c> open = PaymentReconciliationManualService.getOpenInstallments(
			sc.policy.Id
		);
		List<PaymentPlanInstallment__c> none = PaymentReconciliationManualService.getOpenInstallments(
			null
		);
		Test.stopTest();

		Assert.areEqual(1, open.size(), 'Solo la cuota abierta debe listarse');
		Assert.areEqual(sc.installment.Id, open[0].Id);
		Assert.areEqual(0, none.size());
	}

	@IsTest
	static void guardrailProtectsManualDecisionOnReprocess() {
		Scenario sc = buildScenario('POL-193-011', 'Requiere revision');
		// Simula una conciliacion ya resuelta manualmente.
		sc.recon.reconciliationStatus__c = 'Conciliado';
		sc.recon.matchMethod__c = 'Decision manual';
		sc.recon.manualResolvedBy__c = UserInfo.getUserId();
		sc.recon.manualResolvedAt__c = System.now();
		update sc.recon;

		// El inbound quedaria en Requiere revision si el pipeline lo re-corriera.
		sc.inbound.inboundStatus__c = 'Revision Manual';
		sc.inbound.reconciliationMethod__c = 'POLICY_ONLY';
		update sc.inbound;

		Test.startTest();
		System.enqueueJob(
			new PaymentReconciliationQueueable(new Set<Id>{ sc.inbound.Id })
		);
		Test.stopTest();

		PaymentReconciliation__c recon = [
			SELECT reconciliationStatus__c, matchMethod__c
			FROM PaymentReconciliation__c
			WHERE Id = :sc.recon.Id
		];
		Assert.areEqual(
			'Conciliado',
			recon.reconciliationStatus__c,
			'El pipeline no debe pisar la decision manual'
		);
		Assert.areEqual('Decision manual', recon.matchMethod__c);
	}

	@IsTest
	static void appendManualNoteKeepsHistory() {
		String fromBlank = PaymentReconciliationManualService.appendManualNote(
			null,
			'Aprobación manual',
			'nota'
		);
		String appended = PaymentReconciliationManualService.appendManualNote(
			fromBlank,
			'Aprobación manual',
			null
		);
		Assert.isTrue(fromBlank.contains('nota'));
		Assert.isTrue(
			appended.contains(fromBlank),
			'Debe conservar el historico previo'
		);
		Assert.isTrue(appended.length() > fromBlank.length());
	}

	// ---------- H194: rechazo manual ----------

	@IsTest
	static void rejectSealsDecisionAndCascadesInbound() {
		Scenario sc = buildScenario('POL-194-001', 'Requiere revision');

		Test.startTest();
		PaymentReconciliationManualService.rejectReconciliation(
			sc.recon.Id,
			'Sin coincidencia de poliza',
			'No corresponde a ninguna póliza vigente'
		);
		Test.stopTest();

		PaymentReconciliation__c recon = [
			SELECT
				reconciliationStatus__c,
				rejectedReason__c,
				manualResolvedBy__c,
				manualResolvedAt__c,
				resultingReceipt__c,
				decisionNotes__c
			FROM PaymentReconciliation__c
			WHERE Id = :sc.recon.Id
		];
		Assert.areEqual('Rechazado', recon.reconciliationStatus__c);
		Assert.areEqual('Sin coincidencia de poliza', recon.rejectedReason__c);
		Assert.areEqual(UserInfo.getUserId(), recon.manualResolvedBy__c);
		Assert.isNotNull(recon.manualResolvedAt__c);
		Assert.isNull(
			recon.resultingReceipt__c,
			'El rechazo no debe generar recibo'
		);
		Assert.isTrue(recon.decisionNotes__c.contains('No corresponde'));

		InboundInsurancePayment__c inbound = [
			SELECT inboundStatus__c, rejectionReason__c
			FROM InboundInsurancePayment__c
			WHERE Id = :sc.inbound.Id
		];
		Assert.areEqual('Rechazado', inbound.inboundStatus__c);
		Assert.areEqual('Rechazado por negocio', inbound.rejectionReason__c);

		List<PolicyPaymentReceipt__c> receipts = [
			SELECT Id
			FROM PolicyPaymentReceipt__c
			WHERE paymentReconciliation__c = :sc.recon.Id
		];
		Assert.areEqual(0, receipts.size());
	}

	@IsTest
	static void rejectFailsWhenReasonMissing() {
		Scenario sc = buildScenario('POL-194-002', 'Requiere revision');
		assertRejectBlocked(sc.recon.Id, null, 'notas', 'motivo');
	}

	@IsTest
	static void rejectFailsWhenNotesMissing() {
		Scenario sc = buildScenario('POL-194-003', 'Requiere revision');
		assertRejectBlocked(sc.recon.Id, 'Duplicado', '', 'notas');
	}

	@IsTest
	static void rejectFailsWhenAlreadyClosed() {
		Scenario sc = buildScenario('POL-194-004', 'Rechazado');
		assertRejectBlocked(sc.recon.Id, 'Duplicado', 'x', 'cerrada');
	}

	@IsTest
	static void rejectFailsWhenReceiptExists() {
		Scenario sc = buildScenario('POL-194-005', 'Requiere revision');
		PolicyPaymentReceipt__c receipt = new PolicyPaymentReceipt__c(
			insurancePolicy__c = sc.policy.Id,
			paymentReconciliation__c = sc.recon.Id,
			receiptAmount__c = 400,
			receiptDate__c = Date.today(),
			receiptStatus__c = 'Reconocido'
		);
		insert receipt;
		sc.recon.resultingReceipt__c = receipt.Id;
		update sc.recon;
		assertRejectBlocked(sc.recon.Id, 'Duplicado', 'x', 'recibo');
	}

	@IsTest
	static void publicRejectWrapsErrorAsAuraHandled() {
		Scenario sc = buildScenario('POL-194-006', 'Requiere revision');
		Boolean thrown = false;
		try {
			PaymentReconciliationManualService.reject(sc.recon.Id, null, 'x');
		} catch (AuraHandledException e) {
			thrown = true;
		}
		Assert.isTrue(thrown);
	}

	@IsTest
	static void guardrailProtectsRejectionOnReprocess() {
		Scenario sc = buildScenario('POL-194-007', 'Requiere revision');
		PaymentReconciliationManualService.rejectReconciliation(
			sc.recon.Id,
			'Ambiguo',
			'Rechazo de prueba'
		);
		sc.inbound.inboundStatus__c = 'Revision Manual';
		sc.inbound.reconciliationMethod__c = 'POLICY_ONLY';
		update sc.inbound;

		Test.startTest();
		System.enqueueJob(
			new PaymentReconciliationQueueable(new Set<Id>{ sc.inbound.Id })
		);
		Test.stopTest();

		PaymentReconciliation__c recon = [
			SELECT reconciliationStatus__c
			FROM PaymentReconciliation__c
			WHERE Id = :sc.recon.Id
		];
		Assert.areEqual(
			'Rechazado',
			recon.reconciliationStatus__c,
			'El pipeline no debe reabrir un rechazo manual'
		);
	}

	// ---------- helpers ----------

	private static void assertBlocked(
		Id reconId,
		Id policyId,
		Id installmentId,
		String fragment
	) {
		Boolean thrown = false;
		try {
			PaymentReconciliationManualService.approveReconciliation(
				reconId,
				policyId,
				installmentId,
				'x'
			);
		} catch (PaymentReconciliationManualService.ManualResolutionException e) {
			thrown = true;
			Assert.isTrue(
				e.getMessage().toLowerCase().contains(fragment.toLowerCase()),
				'Mensaje inesperado: ' + e.getMessage()
			);
		}
		Assert.isTrue(thrown, 'Debia bloquear la aprobacion (' + fragment + ')');
	}

	private static void assertRejectBlocked(
		Id reconId,
		String reason,
		String notes,
		String fragment
	) {
		Boolean thrown = false;
		try {
			PaymentReconciliationManualService.rejectReconciliation(
				reconId,
				reason,
				notes
			);
		} catch (PaymentReconciliationManualService.ManualResolutionException e) {
			thrown = true;
			Assert.isTrue(
				e.getMessage().toLowerCase().contains(fragment.toLowerCase()),
				'Mensaje inesperado: ' + e.getMessage()
			);
		}
		Assert.isTrue(thrown, 'Debia bloquear el rechazo (' + fragment + ')');
	}

	private class Scenario {
		InsurancePolicy policy;
		PaymentPlan__c plan;
		PaymentPlanInstallment__c installment;
		InboundInsurancePayment__c inbound;
		PaymentReconciliation__c recon;
	}

	private static Scenario buildScenario(String policyName, String reconStatus) {
		Id accountId = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		Scenario sc = new Scenario();

		sc.policy = new InsurancePolicy(
			Name = policyName,
			PolicyName = policyName,
			NameInsuredId = accountId,
			Status = 'Inicial',
			PremiumAmount = 1200,
			PremiumFrequency = 'Mensual',
			PaymentDueDate = Date.today()
		);
		insert sc.policy;

		// Descarta el plan/cuotas auto-generados por el trigger para controlar el escenario.
		List<PaymentPlan__c> autoPlans = [
			SELECT Id
			FROM PaymentPlan__c
			WHERE insurancePolicy__c = :sc.policy.Id
		];
		if (!autoPlans.isEmpty()) {
			Set<Id> planIds = new Map<Id, PaymentPlan__c>(autoPlans).keySet();
			delete [
				SELECT Id
				FROM PaymentPlanInstallment__c
				WHERE paymentPlan__c IN :planIds
			];
			delete autoPlans;
		}

		sc.plan = new PaymentPlan__c(
			insurancePolicy__c = sc.policy.Id,
			planStatus__c = 'Activo',
			premiumFrequency__c = 'Mensual',
			expectedTotalAmount__c = 1200,
			firstDueDate__c = Date.today()
		);
		insert sc.plan;

		sc.installment = new PaymentPlanInstallment__c(
			paymentPlan__c = sc.plan.Id,
			sequenceNumber__c = 1,
			dueDate__c = Date.today().addDays(30),
			expectedAmount__c = 400,
			installmentStatus__c = 'Pendiente'
		);
		insert sc.installment;

		sc.inbound = new InboundInsurancePayment__c(
			externalPaymentId__c = 'EXT-' + policyName,
			inboundStatus__c = 'Revision Manual',
			candidatePolicy__c = sc.policy.Id,
			sourceAmount__c = 400,
			sourcePaymentDate__c = Date.today(),
			sourcePolicyNumber__c = policyName,
			sourceReceiptNumber__c = 'REC-' + policyName,
			sourceSystem__c = 'MuleSoft',
			receivedAt__c = System.now()
		);
		insert sc.inbound;

		sc.recon = new PaymentReconciliation__c(
			inboundPayment__c = sc.inbound.Id,
			insurancePolicy__c = sc.policy.Id,
			reconciliationStatus__c = reconStatus,
			matchMethod__c = 'Asistido por candidato',
			confidenceScore__c = 40,
			candidateCount__c = 2
		);
		insert sc.recon;

		return sc;
	}
}
