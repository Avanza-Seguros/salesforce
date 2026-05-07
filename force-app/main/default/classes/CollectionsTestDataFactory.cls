/**
 *   @name: CollectionsTestDataFactory
 *   @version: 1.0
 *   @creation date: 23/04/2026
 *   @author: Javier Torres - Volestra
 *   @description: Centraliza la creacion de datos de prueba para los tests de cobranza.
 */
@IsTest
public class CollectionsTestDataFactory {
	public static final String DEFAULT_ACCOUNT_NAME = 'Collections Test Insured';

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Crea la cuenta asegurada por defecto usada por los tests de cobranza.
	 * @param:
	 * @return: Account Cuenta creada.
	 * @exception:
	 * @throws:
	 */
	public static Account createInsuredAccount() {
		Account insured = new Account(
			Name = DEFAULT_ACCOUNT_NAME,
			AnnualRevenue = 1000000
		);
		insert insured;
		return insured;
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Obtiene el Id de la cuenta asegurada por defecto creada en test setup.
	 * @param:
	 * @return: Id Identificador de cuenta.
	 * @exception:
	 * @throws:
	 */
	public static Id getDefaultInsuredAccountId() {
		return [
			SELECT Id
			FROM Account
			WHERE Name = :DEFAULT_ACCOUNT_NAME
			LIMIT 1
		]
		.Id;
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Construye una InsurancePolicy minima sin insertarla.
	 * @param insuredAccountId: Identificador del asegurado.
	 * @param status: Estado de la poliza.
	 * @return: InsurancePolicy Poliza construida.
	 * @exception:
	 * @throws:
	 */
	public static InsurancePolicy buildPolicy(
		Id insuredAccountId,
		String status
	) {
		return new InsurancePolicy(
			Name = 'POL-TEST-' +
				String.valueOf(Crypto.getRandomInteger()).replace('-', ''),
			PolicyName = 'Test policy',
			NameInsuredId = insuredAccountId,
			Status = status
		);
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Construye una InsurancePolicy con datos de prima para escenarios operativos.
	 * @param insuredAccountId: Identificador del asegurado.
	 * @param status: Estado de la poliza.
	 * @param premiumFrequency: Frecuencia de prima.
	 * @param premiumAmount: Monto de prima.
	 * @param firstDueDate: Primera fecha de vencimiento.
	 * @return: InsurancePolicy Poliza construida.
	 * @exception:
	 * @throws:
	 */
	public static InsurancePolicy buildCompletePolicy(
		Id insuredAccountId,
		String status,
		String premiumFrequency,
		Decimal premiumAmount,
		Date firstDueDate
	) {
		InsurancePolicy policy = buildPolicy(insuredAccountId, status);
		policy.PremiumAmount = premiumAmount;
		policy.PremiumFrequency = premiumFrequency;
		policy.PaymentDueDate = firstDueDate;
		return policy;
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Crea e inserta una poliza minima para escenarios de prueba.
	 * @param insuredAccountId: Identificador del asegurado.
	 * @param status: Estado de la poliza.
	 * @return: InsurancePolicy Poliza insertada.
	 * @exception:
	 * @throws:
	 */
	public static InsurancePolicy createPolicy(
		Id insuredAccountId,
		String status
	) {
		InsurancePolicy policy = buildPolicy(insuredAccountId, status);
		insert policy;
		return policy;
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Crea e inserta una poliza operativa lista para generar plan y cuotas.
	 * @param insuredAccountId: Identificador del asegurado.
	 * @param premiumFrequency: Frecuencia de prima.
	 * @param premiumAmount: Monto de prima.
	 * @param firstDueDate: Primera fecha de vencimiento.
	 * @return: InsurancePolicy Poliza insertada.
	 * @exception:
	 * @throws:
	 */
	public static InsurancePolicy createOperationalPolicy(
		Id insuredAccountId,
		String premiumFrequency,
		Decimal premiumAmount,
		Date firstDueDate
	) {
		InsurancePolicy policy = buildCompletePolicy(
			insuredAccountId,
			'Inicial',
			premiumFrequency,
			premiumAmount,
			firstDueDate
		);
		insert policy;
		return policy;
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Construye un PaymentPlan__c sin insertarlo.
	 * @param policyId: Identificador de la poliza.
	 * @param planStatus: Estado del plan.
	 * @param premiumFrequency: Frecuencia del plan.
	 * @param expectedTotalAmount: Monto total esperado.
	 * @param firstDueDate: Primera fecha de vencimiento.
	 * @param installmentCount: Cantidad de cuotas.
	 * @return: PaymentPlan__c Plan construido.
	 * @exception:
	 * @throws:
	 */
	public static PaymentPlan__c buildPlan(
		Id policyId,
		String planStatus,
		String premiumFrequency,
		Decimal expectedTotalAmount,
		Date firstDueDate,
		Integer installmentCount
	) {
		return new PaymentPlan__c(
			insurancePolicy__c = policyId,
			planType__c = 'Inicial',
			planStatus__c = planStatus,
			premiumFrequency__c = premiumFrequency,
			expectedTotalAmount__c = expectedTotalAmount,
			firstDueDate__c = firstDueDate,
			installmentCount__c = installmentCount
		);
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Crea e inserta un plan de pago para tests que requieren setup directo.
	 * @param policyId: Identificador de la poliza.
	 * @param planStatus: Estado del plan.
	 * @param premiumFrequency: Frecuencia del plan.
	 * @param expectedTotalAmount: Monto total esperado.
	 * @param firstDueDate: Primera fecha de vencimiento.
	 * @param installmentCount: Cantidad de cuotas.
	 * @return: PaymentPlan__c Plan insertado.
	 * @exception:
	 * @throws:
	 */
	public static PaymentPlan__c createPlan(
		Id policyId,
		String planStatus,
		String premiumFrequency,
		Decimal expectedTotalAmount,
		Date firstDueDate,
		Integer installmentCount
	) {
		PaymentPlan__c plan = buildPlan(
			policyId,
			planStatus,
			premiumFrequency,
			expectedTotalAmount,
			firstDueDate,
			installmentCount
		);
		insert plan;
		return plan;
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Obtiene el plan activo de una poliza.
	 * @param policyId: Identificador de la poliza.
	 * @return: PaymentPlan__c Plan activo.
	 * @exception:
	 * @throws:
	 */
	public static PaymentPlan__c getActivePlan(Id policyId) {
		return [
			SELECT Id, planStatus__c
			FROM PaymentPlan__c
			WHERE insurancePolicy__c = :policyId AND planStatus__c = 'Activo'
			LIMIT 1
		];
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Obtiene las cuotas de una poliza ordenadas por secuencia.
	 * @param policyId: Identificador de la poliza.
	 * @return: List<PaymentPlanInstallment__c> Cuotas obtenidas.
	 * @exception:
	 * @throws:
	 */
	public static List<PaymentPlanInstallment__c> getInstallmentsByPolicy(
		Id policyId
	) {
		return [
			SELECT
				Id,
				paymentPlan__c,
				sequenceNumber__c,
				dueDate__c,
				expectedAmount__c,
				installmentStatus__c,
				periodStartDate__c,
				periodEndDate__c,
				paymentPlan__r.insurancePolicy__c
			FROM PaymentPlanInstallment__c
			WHERE paymentPlan__r.insurancePolicy__c = :policyId
			ORDER BY sequenceNumber__c
		];
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Obtiene las cuotas de un plan ordenadas por secuencia.
	 * @param planId: Identificador del plan.
	 * @return: List<PaymentPlanInstallment__c> Cuotas obtenidas.
	 * @exception:
	 * @throws:
	 */
	public static List<PaymentPlanInstallment__c> getInstallmentsByPlan(
		Id planId
	) {
		return [
			SELECT
				Id,
				paymentPlan__c,
				sequenceNumber__c,
				dueDate__c,
				expectedAmount__c,
				installmentStatus__c,
				periodStartDate__c,
				periodEndDate__c
			FROM PaymentPlanInstallment__c
			WHERE paymentPlan__c = :planId
			ORDER BY sequenceNumber__c
		];
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Suma los montos esperados de las cuotas con precision monetaria.
	 * @param installments: Lista de cuotas.
	 * @return: Decimal Suma total.
	 * @exception:
	 * @throws:
	 */
	public static Decimal sumExpectedAmounts(
		List<PaymentPlanInstallment__c> installments
	) {
		Decimal total = 0;

		for (PaymentPlanInstallment__c installment : installments) {
			total += installment.expectedAmount__c == null
				? 0
				: installment.expectedAmount__c;
		}

		return total.setScale(2);
	}
}
