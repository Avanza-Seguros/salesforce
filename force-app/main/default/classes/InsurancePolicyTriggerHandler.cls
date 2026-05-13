/**
 *   @name: InsurancePolicyTriggerHandler
 *   @version: 1.0
 *   @creation date: 23/04/2026
 *   @author: Javier Torres - Volestra
 *   @description: Gestiona la creacion del plan inicial de pagos y la delegacion
 *                 de validaciones y reemplazos por cambio de frecuencia.
 */
public with sharing class InsurancePolicyTriggerHandler {
	private static final Set<String> OPERATIONAL_POLICY_STATUSES = new Set<String>{
		'Inicial',
		'Vigente'
	};

	private static final String INITIAL_PLAN_EVENT = 'INITIAL_PAYMENT_PLAN';

	private static final String PLAN_TYPE_INITIAL = 'Inicial';
	private static final String PLAN_STATUS_ACTIVE = 'Activo';

	private static final String FREQUENCY_MONTHLY = 'Mensual';
	private static final String FREQUENCY_QUARTERLY = 'Trimestral';
	private static final String FREQUENCY_BIANNUAL = 'Semestral';
	private static final String FREQUENCY_ANNUAL = 'Anual';
	private static final String FREQUENCY_SINGLE = 'Unico';
	private static final Set<String> SUPPORTED_PREMIUM_FREQUENCIES = new Set<String>{
		FREQUENCY_MONTHLY,
		FREQUENCY_QUARTERLY,
		FREQUENCY_BIANNUAL,
		FREQUENCY_ANNUAL,
		FREQUENCY_SINGLE
	};

	private static Set<Id> processedPolicyIds = new Set<Id>();

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Valida antes del guardado los cambios de frecuencia solicitados
	 *               sobre InsurancePolicy.
	 * @param newPolicies: Registros nuevos del trigger.
	 * @param oldMap: Valores anteriores de las polizas.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	public static void handleBeforeTrigger(
		List<InsurancePolicy> newPolicies,
		Map<Id, InsurancePolicy> oldMap
	) {
		PaymentPlanFrequencyChangeService.validateBeforeUpdate(newPolicies, oldMap);
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Crea el plan inicial despues del insert/update y procesa
	 *               reemplazos validos por cambio de frecuencia.
	 * @param newPolicies: Registros nuevos del trigger.
	 * @param oldMap: Valores anteriores de las polizas.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	public static void handleAfterTrigger(
		List<InsurancePolicy> newPolicies,
		Map<Id, InsurancePolicy> oldMap
	) {
		if (newPolicies == null || newPolicies.isEmpty()) {
			return;
		}

		List<InsurancePolicy> policiesToProcess = new List<InsurancePolicy>();

		for (InsurancePolicy policy : newPolicies) {
			if (
				policy == null ||
				policy.Id == null ||
				processedPolicyIds.contains(policy.Id)
			) {
				continue;
			}

			InsurancePolicy oldPolicy = oldMap == null ? null : oldMap.get(policy.Id);

			if (shouldCreateInitialPlan(policy, oldPolicy)) {
				policiesToProcess.add(policy);
				processedPolicyIds.add(policy.Id);
			}
		}

		if (!policiesToProcess.isEmpty()) {
			upsertInitialPlans(policiesToProcess);
		}

		PaymentPlanFrequencyChangeService.processAfterUpdate(newPolicies, oldMap);
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Punto de entrada de compatibilidad para consumidores que
	 *               aun usan el nombre anterior del metodo.
	 * @param newPolicies: Registros nuevos del trigger.
	 * @param oldMap: Valores anteriores de las polizas.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	public static void handleIsAfterTrigger(
		List<InsurancePolicy> newPolicies,
		Map<Id, InsurancePolicy> oldMap
	) {
		handleAfterTrigger(newPolicies, oldMap);
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Determina si la poliza acaba de entrar a estado operativo y
	 *               requiere crear su plan inicial.
	 * @param policy: Poliza nueva.
	 * @param oldPolicy: Poliza anterior.
	 * @return: Boolean Indica si debe crearse el plan inicial.
	 * @exception:
	 * @throws:
	 */
	private static Boolean shouldCreateInitialPlan(
		InsurancePolicy policy,
		InsurancePolicy oldPolicy
	) {
		Boolean isOperationalNow = isValidForOperation(policy);
		Boolean wasOperationalBefore =
			oldPolicy != null && isValidForOperation(oldPolicy);

		return isOperationalNow && !wasOperationalBefore;
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Identifica si la poliza puede participar en el proceso de cobranza.
	 * @param policy: Poliza a evaluar.
	 * @return: Boolean Indica si la poliza es operativa.
	 * @exception:
	 * @throws:
	 */
	private static Boolean isValidForOperation(InsurancePolicy policy) {
		return policy != null &&
			OPERATIONAL_POLICY_STATUSES.contains(policy.Status);
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Inserta o actualiza el PaymentPlan inicial por poliza usando
	 *               la clave tecnica o un plan inicial abierto existente.
	 * @param policies: Polizas operativas a procesar.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	private static void upsertInitialPlans(List<InsurancePolicy> policies) {
		Set<Id> policyIds = new Set<Id>();
		Set<String> initialPlanKeys = new Set<String>();

		for (InsurancePolicy policy : policies) {
			policyIds.add(policy.Id);
			initialPlanKeys.add(buildInitialPlanKey(policy.Id));
		}

		Map<String, PaymentPlan__c> existingByKey = new Map<String, PaymentPlan__c>();

		for (PaymentPlan__c plan : [
			SELECT Id, insurancePolicy__c, initialPlanKey__c
			FROM PaymentPlan__c
			WHERE initialPlanKey__c IN :initialPlanKeys
		]) {
			existingByKey.put(plan.initialPlanKey__c, plan);
		}

		List<PaymentPlan__c> plansToUpsert = new List<PaymentPlan__c>();

		for (InsurancePolicy policy : policies) {
			String initialPlanKey = buildInitialPlanKey(policy.Id);
			PaymentPlan__c plan = existingByKey.containsKey(initialPlanKey)
				? existingByKey.get(initialPlanKey)
				: new PaymentPlan__c();

			populateInitialPlan(plan, policy, initialPlanKey);
			plansToUpsert.add(plan);
		}

		if (plansToUpsert.isEmpty()) {
			return;
		}

		Database.UpsertResult[] results = Database.upsert(
			plansToUpsert,
			PaymentPlan__c.Fields.initialPlanKey__c,
			false
		);

		logUpsertErrors(plansToUpsert, results);
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Mapea los datos de InsurancePolicy hacia la cabecera del plan inicial.
	 * @param plan: Plan de pago a poblar.
	 * @param policy: Poliza origen.
	 * @param initialPlanKey: Clave tecnica del plan inicial.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	private static void populateInitialPlan(
		PaymentPlan__c plan,
		InsurancePolicy policy,
		String initialPlanKey
	) {
		plan.initialPlanKey__c = initialPlanKey;
		plan.insurancePolicy__c = policy.Id;
		plan.planType__c = PLAN_TYPE_INITIAL;
		plan.planStatus__c = PLAN_STATUS_ACTIVE;
		plan.premiumFrequency__c = getSupportedPremiumFrequency(policy);
		plan.expectedTotalAmount__c = deriveExpectedTotalAmount(policy);
		plan.firstDueDate__c = getDate(policy, 'PaymentDueDate');
		plan.installmentCount__c = deriveInstallmentCount(plan.premiumFrequency__c);
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Obtiene el monto total esperado del plan desde la prima de la poliza.
	 * @param policy: Poliza origen.
	 * @return: Decimal Monto esperado total.
	 * @exception:
	 * @throws:
	 */
	private static Decimal deriveExpectedTotalAmount(InsurancePolicy policy) {
		return nullIfZero(getDecimal(policy, 'PremiumAmount'));
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Devuelve la frecuencia de la poliza solo si esta soportada
	 *               por el modelo de cobranza.
	 * @param policy: Poliza origen.
	 * @return: String Frecuencia soportada o null.
	 * @exception:
	 * @throws:
	 */
	private static String getSupportedPremiumFrequency(InsurancePolicy policy) {
		String policyFrequency = getString(policy, 'PremiumFrequency');
		return SUPPORTED_PREMIUM_FREQUENCIES.contains(policyFrequency)
			? policyFrequency
			: null;
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Calcula la cantidad de cuotas por defecto a partir de la frecuencia.
	 * @param premiumFrequency: Frecuencia soportada del plan.
	 * @return: Integer Cantidad de cuotas esperada.
	 * @exception:
	 * @throws:
	 */
	private static Integer deriveInstallmentCount(String premiumFrequency) {
		if (premiumFrequency == FREQUENCY_MONTHLY) {
			return 12;
		}

		if (premiumFrequency == FREQUENCY_QUARTERLY) {
			return 4;
		}

		if (premiumFrequency == FREQUENCY_BIANNUAL) {
			return 2;
		}

		if (
			premiumFrequency == FREQUENCY_ANNUAL ||
			premiumFrequency == FREQUENCY_SINGLE
		) {
			return 1;
		}

		return null;
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Construye la clave de idempotencia del plan inicial.
	 * @param policyId: Identificador de la poliza.
	 * @return: String Clave tecnica del plan inicial.
	 * @exception:
	 * @throws:
	 */
	private static String buildInitialPlanKey(Id policyId) {
		return String.valueOf(policyId) + ':' + INITIAL_PLAN_EVENT;
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Normaliza el valor cero a null para forzar el estado borrador si falta data.
	 * @param value: Valor decimal a evaluar.
	 * @return: Decimal Valor normalizado.
	 * @exception:
	 * @throws:
	 */
	private static Decimal nullIfZero(Decimal value) {
		return value == null || value == 0 ? null : value;
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Lee un campo dinamico y lo convierte a Decimal.
	 * @param record: Registro origen.
	 * @param fieldApiName: API name del campo.
	 * @return: Decimal Valor convertido.
	 * @exception:
	 * @throws:
	 */
	private static Decimal getDecimal(SObject record, String fieldApiName) {
		Object value = getValue(record, fieldApiName);
		if (value == null) {
			return null;
		}

		if (value instanceof Decimal) {
			return (Decimal) value;
		}

		try {
			return Decimal.valueOf(String.valueOf(value));
		} catch (Exception e) {
			logWarning(
				'No se pudo convertir ' +
					fieldApiName +
					' a Decimal: ' +
					String.valueOf(value)
			);
			return null;
		}
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Lee un campo dinamico y lo convierte a Date.
	 * @param record: Registro origen.
	 * @param fieldApiName: API name del campo.
	 * @return: Date Valor convertido.
	 * @exception:
	 * @throws:
	 */
	private static Date getDate(SObject record, String fieldApiName) {
		Object value = getValue(record, fieldApiName);
		if (value == null) {
			return null;
		}

		if (value instanceof Date) {
			return (Date) value;
		}

		try {
			return Date.valueOf(String.valueOf(value));
		} catch (Exception e) {
			logWarning(
				'No se pudo convertir ' +
					fieldApiName +
					' a Date: ' +
					String.valueOf(value)
			);
			return null;
		}
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Lee un campo dinamico y lo convierte a String.
	 * @param record: Registro origen.
	 * @param fieldApiName: API name del campo.
	 * @return: String Valor convertido.
	 * @exception:
	 * @throws:
	 */
	private static String getString(SObject record, String fieldApiName) {
		Object value = getValue(record, fieldApiName);
		return value == null ? null : String.valueOf(value);
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Devuelve de forma segura el valor de un campo dinamico.
	 * @param record: Registro origen.
	 * @param fieldApiName: API name del campo.
	 * @return: Object Valor sin transformar.
	 * @exception:
	 * @throws:
	 */
	private static Object getValue(SObject record, String fieldApiName) {
		if (record == null || String.isBlank(fieldApiName)) {
			return null;
		}

		try {
			return record.get(fieldApiName);
		} catch (Exception e) {
			logWarning('No se pudo leer ' + fieldApiName + ': ' + e.getMessage());
			return null;
		}
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Registra errores parciales del upsert sin interrumpir la transaccion.
	 * @param plans: Planes procesados.
	 * @param results: Resultados del upsert.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	private static void logUpsertErrors(
		List<PaymentPlan__c> plans,
		Database.UpsertResult[] results
	) {
		for (Integer i = 0; i < results.size(); i++) {
			if (results[i].isSuccess()) {
				continue;
			}

			for (Database.Error error : results[i].getErrors()) {
				logError(
					'Error al guardar PaymentPlan para poliza ' +
						plans[i].insurancePolicy__c +
						': ' +
						error.getMessage()
				);
			}
		}
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Registra una advertencia tecnica no fatal.
	 * @param message: Mensaje a registrar.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	private static void logWarning(String message) {
		System.debug(LoggingLevel.WARN, message);
	}

	/**
	 * @creation date: 23/04/2026
	 * @author: Javier Torres - Volestra
	 * @description: Registra un error tecnico asociado a DML fallido.
	 * @param message: Mensaje a registrar.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	private static void logError(String message) {
		System.debug(LoggingLevel.ERROR, message);
	}
}
