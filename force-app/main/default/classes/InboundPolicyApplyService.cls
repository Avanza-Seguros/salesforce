/**
 *   @name: InboundPolicyApplyService
 *   @version: 1.0
 *   @creation date: 25/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Aplica a la poliza de FSC lo que comunica la aseguradora por el canal de
 *                 polizas (KAN-449).
 *                 Reparto acordado: la aseguradora es duena de la identidad, la vigencia, la
 *                 prima y el estado; el motor es dueno del estado de cobranza. Por eso lo que el
 *                 portal manda sobre lo pagado, lo pendiente y las fechas de pago se queda en la
 *                 comunicacion y no se copia a la poliza. El estado de la poliza lo aplica otra
 *                 historia (KAN-450).
 *                 La vigencia se elige por el inicio de vigencia comunicado, tambien cuando el
 *                 numero tiene una sola poliza: si su periodo no lo contiene, la comunicacion es
 *                 de otra vigencia (por ejemplo, la renovacion) y aplicarla pisaria las fechas de
 *                 la anterior. Sin una vigencia clara, va a revision.
 */
public with sharing class InboundPolicyApplyService {
	private static final String STATUS_RECEIVED = 'Recibido';
	private static final String STATUS_APPLIED = 'Aplicado';
	private static final String STATUS_REVIEW = 'Revision Manual';
	private static final String STATUS_SUPERSEDED = 'Superada';

	private static final String REASON_BY_TERM = 'RESUELTO_POR_VIGENCIA';
	private static final String REASON_BY_ID = 'RESUELTO_POR_ID';
	private static final String REASON_NO_POLICY = 'SIN_POLIZA';
	private static final String REASON_NO_TERM = 'SIN_VIGENCIA';
	private static final String REASON_AMBIGUOUS_TERM = 'VIGENCIA_AMBIGUA';

	private static final Map<String, String> FREQUENCY_BY_CARRIER = new Map<String, String>{
		'MENSUAL' => 'Mensual',
		'TRIMESTRAL' => 'Trimestral',
		'SEMESTRAL' => 'Semestral',
		'ANUAL' => 'Anual',
		'CONTADO' => 'Unico',
		'UNICO' => 'Unico'
	};

	private static final Map<String, String> BRANCH_BY_CARRIER = new Map<String, String>{
		'AUTOMOVILES' => 'Automoviles',
		'AUTOS' => 'Automoviles',
		'AUTO' => 'Automoviles',
		'DANOS' => 'Danos',
		'DENTAL' => 'Dental',
		'EMPRESARIAL' => 'Empresarial',
		'FIANZAS' => 'Fianzas',
		'GMM' => 'GMM',
		'GASTOSMEDICOS' => 'GMM',
		'GASTOSMEDICOSMAYORES' => 'GMM',
		'RC' => 'RC',
		'RESPONSABILIDADCIVIL' => 'RC',
		'VIAJES' => 'Viajes',
		'VIDA' => 'Vida',
		'VISION' => 'Vision'
	};

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Aplica las comunicaciones indicadas que sigan en estado Recibido. Cada
	 *               poliza se guarda por separado: una que falla no arrastra a las demas.
	 * @param updateIds: Comunicaciones de poliza a aplicar.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	public static void apply(Set<Id> updateIds) {
		if (updateIds == null || updateIds.isEmpty()) {
			return;
		}

		List<InboundPolicyUpdate__c> updates = [
			SELECT
				Id,
				Name,
				sourcePolicyId__c,
				sourcePolicyNumber__c,
				sourcePolicyStartDate__c,
				sourcePolicyEndDate__c,
				sourcePolicyIssueDate__c,
				sourcePolicyRenewalDate__c,
				sourcePolicyBranch__c,
				sourcePremiumFrequency__c,
				sourceTotalPremium__c,
				sourceNetPremium__c,
				sourcePolicyFee__c,
				sourceFinancingCharge__c,
				sourceTaxAmount__c,
				sourceDiscountPercent__c,
				sourceInsuredAssetDescription__c,
				sourcePaymentMode__c,
				sourceIntermediaryName__c,
				sourceCurrency__c,
				sourceSynchronizedAt__c,
				receivedAt__c
			FROM InboundPolicyUpdate__c
			WHERE Id IN :updateIds AND inboundStatus__c = :STATUS_RECEIVED
		];

		if (updates.isEmpty()) {
			return;
		}

		Map<String, List<InsurancePolicy>> policiesByNumber = selectPolicies(
			updates
		);
		Map<Id, InsurancePolicy> policyById = new Map<Id, InsurancePolicy>();
		Map<Id, List<InboundPolicyUpdate__c>> updatesByPolicyId = new Map<Id, List<InboundPolicyUpdate__c>>();
		Map<Id, String> matchReasonByUpdateId = new Map<Id, String>();
		List<InboundPolicyUpdate__c> toSave = new List<InboundPolicyUpdate__c>();

		for (InboundPolicyUpdate__c communication : updates) {
			InsurancePolicy byId = policyByReportedId(
				communication,
				policiesByNumber
			);

			if (byId != null) {
				// MuleSoft mando el Id de la poliza que consulto y es coherente: es esa.
				policyById.put(byId.Id, byId);
				matchReasonByUpdateId.put(communication.Id, REASON_BY_ID);

				if (!updatesByPolicyId.containsKey(byId.Id)) {
					updatesByPolicyId.put(byId.Id, new List<InboundPolicyUpdate__c>());
				}

				updatesByPolicyId.get(byId.Id).add(communication);
				continue;
			}

			List<InsurancePolicy> candidates = policiesByNumber.get(
				normalizeNumber(communication.sourcePolicyNumber__c)
			);
			List<InsurancePolicy> containing = new List<InsurancePolicy>();
			List<InsurancePolicy> startingThatDay = new List<InsurancePolicy>();

			for (
				InsurancePolicy policy : candidates == null
					? new List<InsurancePolicy>()
					: candidates
			) {
				if (startsOn(policy, communication.sourcePolicyStartDate__c)) {
					startingThatDay.add(policy);
				}

				if (termContains(policy, communication.sourcePolicyStartDate__c)) {
					containing.add(policy);
				}
			}

			// La vigencia que empieza justo ese dia es la prueba mas fuerte.
			if (startingThatDay.size() == 1) {
				containing = startingThatDay;
			}

			if (candidates == null || candidates.isEmpty()) {
				toSave.add(
					review(
						communication,
						REASON_NO_POLICY,
						'No existe ninguna poliza con el numero ' +
							communication.sourcePolicyNumber__c +
							'.'
					)
				);
			} else if (containing.isEmpty()) {
				toSave.add(
					review(
						communication,
						REASON_NO_TERM,
						'Ninguna vigencia de la poliza ' +
							communication.sourcePolicyNumber__c +
							' contiene el inicio comunicado ' +
							communication.sourcePolicyStartDate__c.format() +
							' (puede ser una renovacion).'
					)
				);
			} else if (containing.size() > 1) {
				toSave.add(
					review(
						communication,
						REASON_AMBIGUOUS_TERM,
						containing.size() +
							' vigencias de la poliza ' +
							communication.sourcePolicyNumber__c +
							' contienen el inicio comunicado: no se elige por descarte.'
					)
				);
			} else {
				InsurancePolicy policy = containing[0];
				policyById.put(policy.Id, policy);

				if (!updatesByPolicyId.containsKey(policy.Id)) {
					updatesByPolicyId.put(policy.Id, new List<InboundPolicyUpdate__c>());
				}

				updatesByPolicyId.get(policy.Id).add(communication);
			}
		}

		List<InsurancePolicy> policiesToUpdate = new List<InsurancePolicy>();
		Map<Id, InboundPolicyUpdate__c> appliedByPolicyId = new Map<Id, InboundPolicyUpdate__c>();
		Map<Id, List<String>> changesByPolicyId = new Map<Id, List<String>>();

		for (Id policyId : updatesByPolicyId.keySet()) {
			InsurancePolicy policy = policyById.get(policyId);
			InboundPolicyUpdate__c latest = null;

			for (
				InboundPolicyUpdate__c communication : updatesByPolicyId.get(policyId)
			) {
				if (latest == null || syncOf(communication) > syncOf(latest)) {
					latest = communication;
				}
			}

			for (
				InboundPolicyUpdate__c communication : updatesByPolicyId.get(policyId)
			) {
				if (communication !== latest) {
					toSave.add(
						supersede(
							communication,
							policyId,
							'En el mismo envio llego una comunicacion mas reciente de esta poliza.'
						)
					);
				}
			}

			if (
				policy.carrierDataSyncedAt__c != null &&
				syncOf(latest) < policy.carrierDataSyncedAt__c
			) {
				toSave.add(
					supersede(
						latest,
						policyId,
						'La poliza ya tiene aplicada una comunicacion mas reciente (' +
							policy.carrierDataSyncedAt__c.format() +
							'): esta llego tarde y no se aplica.'
					)
				);
				continue;
			}

			if (currencyMismatch(latest, policy)) {
				InboundPolicyUpdate__c inReview = review(
					latest,
					REASON_BY_TERM,
					'La moneda comunicada (' +
						latest.sourceCurrency__c +
						') no es la de la poliza (' +
						policy.Moneda__c +
						'): no se escriben importes.'
				);
				inReview.candidatePolicy__c = policyId;
				toSave.add(inReview);
				continue;
			}

			List<String> changes = new List<String>();
			InsurancePolicy changed = buildPolicyUpdate(latest, policy, changes);
			changesByPolicyId.put(policyId, changes);
			appliedByPolicyId.put(policyId, latest);

			if (changed != null) {
				policiesToUpdate.add(changed);
			}
		}

		Set<Id> failedPolicyIds = savePolicies(policiesToUpdate, appliedByPolicyId);

		for (Id policyId : appliedByPolicyId.keySet()) {
			InboundPolicyUpdate__c communication = appliedByPolicyId.get(policyId);

			if (failedPolicyIds.contains(policyId)) {
				continue;
			}

			toSave.add(
				new InboundPolicyUpdate__c(
					Id = communication.Id,
					inboundStatus__c = STATUS_APPLIED,
					candidatePolicy__c = policyId,
					policyMatchReason__c = matchReasonByUpdateId.containsKey(
							communication.Id
						)
						? matchReasonByUpdateId.get(communication.Id)
						: REASON_BY_TERM,
					manualReviewRequired__c = false,
					manualReviewReason__c = null
				)
			);

			List<String> changes = changesByPolicyId.get(policyId);

			if (changes != null && !changes.isEmpty()) {
				CobranzaLog.info(
						CobranzaLog.STAGE_RECEPCION_POLIZAS,
						CobranzaLog.EVENT_POLICY_DATA_APPLIED,
						'Comunicacion ' +
							communication.Name +
							' aplicada. Cambio: ' +
							String.join(changes, ', ') +
							'.'
					)
					.onRecord(policyId);
			}
		}

		saveCommunications(toSave);
		AppLogger.flush();
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Arma la actualizacion de la poliza con lo que la comunicacion trae y
	 *               difiere de lo que ya tiene. Un dato que no llega no borra el de la poliza.
	 *               Devuelve null si no hay nada que cambiar.
	 * @param communication: Comunicacion a aplicar.
	 * @param policy: Poliza tal como esta.
	 * @param changes: Lista donde se anotan los datos que cambian.
	 * @return: InsurancePolicy Actualizacion, o null.
	 * @exception:
	 * @throws:
	 */
	private static InsurancePolicy buildPolicyUpdate(
		InboundPolicyUpdate__c communication,
		InsurancePolicy policy,
		List<String> changes
	) {
		InsurancePolicy changed = new InsurancePolicy(Id = policy.Id);
		Boolean dirty = false;

		dirty |= setDate(
			changed,
			policy,
			'EffectiveDate',
			communication.sourcePolicyStartDate__c,
			'inicio de vigencia',
			changes
		);
		dirty |= setDate(
			changed,
			policy,
			'ExpirationDate',
			communication.sourcePolicyEndDate__c,
			'fin de vigencia',
			changes
		);
		dirty |= setDate(
			changed,
			policy,
			'SaleDate',
			communication.sourcePolicyIssueDate__c,
			'fecha de emision',
			changes
		);
		dirty |= setDate(
			changed,
			policy,
			'RenewalDate',
			communication.sourcePolicyRenewalDate__c,
			'fecha de renovacion',
			changes
		);
		dirty |= setAmount(
			changed,
			policy,
			'PremiumAmount',
			communication.sourceTotalPremium__c,
			'prima total',
			changes
		);
		dirty |= setAmount(
			changed,
			policy,
			'Subtotal__c',
			communication.sourceNetPremium__c,
			'prima neta',
			changes
		);
		dirty |= setAmount(
			changed,
			policy,
			'Derecho_Poliza__c',
			communication.sourcePolicyFee__c,
			'derecho de poliza',
			changes
		);
		dirty |= setAmount(
			changed,
			policy,
			'Financiamiento__c',
			communication.sourceFinancingCharge__c,
			'recargo fraccionado',
			changes
		);
		dirty |= setAmount(
			changed,
			policy,
			'IVA__c',
			communication.sourceTaxAmount__c,
			'IVA',
			changes
		);
		dirty |= setAmount(
			changed,
			policy,
			'Discount',
			communication.sourceDiscountPercent__c,
			'descuento',
			changes
		);
		dirty |= setText(
			changed,
			policy,
			'insuredAssetDescription__c',
			communication.sourceInsuredAssetDescription__c,
			'bien asegurado',
			changes,
			255
		);
		dirty |= setText(
			changed,
			policy,
			'carrierPaymentMode__c',
			communication.sourcePaymentMode__c,
			'modo de pago',
			changes,
			100
		);
		dirty |= setText(
			changed,
			policy,
			'sourceIntermediaryName__c',
			communication.sourceIntermediaryName__c,
			'intermediario',
			changes,
			255
		);

		if (communication.sourcePremiumFrequency__c != null) {
			String frequency = FREQUENCY_BY_CARRIER.get(
				normalizeKey(communication.sourcePremiumFrequency__c)
			);

			if (frequency == null) {
				CobranzaLog.warn(
						CobranzaLog.STAGE_RECEPCION_POLIZAS,
						CobranzaLog.EVENT_CARRIER_FREQUENCY_UNMAPPED,
						'La forma de pago comunicada «' +
							communication.sourcePremiumFrequency__c +
							'» no tiene equivalencia: la poliza conserva la que tenia (' +
							policy.PremiumFrequency +
							').'
					)
					.onRecord(policy.Id);
			} else {
				dirty |= setText(
					changed,
					policy,
					'PremiumFrequency',
					frequency,
					'frecuencia',
					changes,
					50
				);
			}
		}

		if (communication.sourcePolicyBranch__c != null) {
			String branch = BRANCH_BY_CARRIER.get(
				normalizeKey(communication.sourcePolicyBranch__c)
			);

			if (branch == null) {
				CobranzaLog.warn(
						CobranzaLog.STAGE_RECEPCION_POLIZAS,
						CobranzaLog.EVENT_CARRIER_BRANCH_UNMAPPED,
						'El ramo comunicado «' +
							communication.sourcePolicyBranch__c +
							'» no tiene equivalencia: la poliza conserva el que tenia.'
					)
					.onRecord(policy.Id);
			} else {
				dirty |= setText(
					changed,
					policy,
					'Ramo__c',
					branch,
					'ramo',
					changes,
					50
				);
			}
		}

		// La marca de la comunicacion aplicada se guarda aunque los datos no cambien, para
		// que una entrega tardia se reconozca como tal.
		Datetime synchronizedAt = syncOf(communication);

		if (policy.carrierDataSyncedAt__c != synchronizedAt) {
			changed.carrierDataSyncedAt__c = synchronizedAt;
			dirty = true;
		}

		if (policy.carrierPolicyUpdate__c != communication.Id) {
			changed.carrierPolicyUpdate__c = communication.Id;
			dirty = true;
		}

		return dirty ? changed : null;
	}

	private static Boolean setDate(
		InsurancePolicy changed,
		InsurancePolicy policy,
		String field,
		Date value,
		String label,
		List<String> changes
	) {
		if (value == null) {
			return false;
		}

		Datetime current = (Datetime) policy.get(field);

		if (current != null && current.dateGmt() == value) {
			return false;
		}

		changed.put(field, PolicyStatusService.mexicoMidnight(value));
		changes.add(label);
		return true;
	}

	private static Boolean setAmount(
		InsurancePolicy changed,
		InsurancePolicy policy,
		String field,
		Decimal value,
		String label,
		List<String> changes
	) {
		if (value == null) {
			return false;
		}

		Object current = policy.get(field);
		// Discount es un campo double; los importes, Decimal.
		Decimal currentValue = current == null
			? null
			: current instanceof Double
					? Decimal.valueOf((Double) current)
					: (Decimal) current;

		if (currentValue != null && currentValue.setScale(4) == value.setScale(4)) {
			return false;
		}

		changed.put(
			field,
			current instanceof Double || field == 'Discount'
				? (Object) value.doubleValue()
				: (Object) value
		);
		changes.add(label);
		return true;
	}

	private static Boolean setText(
		InsurancePolicy changed,
		InsurancePolicy policy,
		String field,
		String value,
		String label,
		List<String> changes,
		Integer maxLength
	) {
		if (String.isBlank(value)) {
			return false;
		}

		String text = value.left(maxLength);

		if (text == (String) policy.get(field)) {
			return false;
		}

		changed.put(field, text);
		changes.add(label);
		return true;
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Guarda las polizas una a una. Una que falla (por ejemplo, por una regla de
	 *               validacion o por el cambio de frecuencia de un plan con cobros) deja su
	 *               comunicacion en revision con el motivo, y el fallo queda registrado.
	 * @param policies: Actualizaciones de poliza.
	 * @param appliedByPolicyId: Comunicacion que se aplicaba a cada poliza.
	 * @return: Set<Id> Polizas que no se pudieron guardar.
	 * @exception:
	 * @throws:
	 */
	private static Set<Id> savePolicies(
		List<InsurancePolicy> policies,
		Map<Id, InboundPolicyUpdate__c> appliedByPolicyId
	) {
		Set<Id> failed = new Set<Id>();

		if (policies.isEmpty()) {
			return failed;
		}

		List<Database.SaveResult> results = Database.update(policies, false);
		List<InboundPolicyUpdate__c> toReview = new List<InboundPolicyUpdate__c>();

		for (Integer i = 0; i < results.size(); i++) {
			if (results[i].isSuccess()) {
				continue;
			}

			Id policyId = policies[i].Id;
			List<String> errors = new List<String>();

			for (Database.Error error : results[i].getErrors()) {
				errors.add(error.getMessage());
			}

			String reason =
				'No se pudo guardar la poliza: ' + String.join(errors, '; ');
			failed.add(policyId);
			InboundPolicyUpdate__c inReview = review(
				appliedByPolicyId.get(policyId),
				REASON_BY_TERM,
				reason
			);
			inReview.candidatePolicy__c = policyId;
			toReview.add(inReview);
			CobranzaLog.error(
					CobranzaLog.STAGE_RECEPCION_POLIZAS,
					CobranzaLog.EVENT_POLICY_DATA_APPLY_FAILED,
					reason
				)
				.onRecord(policyId);
		}

		saveCommunications(toReview);
		return failed;
	}

	private static void saveCommunications(
		List<InboundPolicyUpdate__c> communications
	) {
		if (communications.isEmpty()) {
			return;
		}

		Database.DMLOptions options = new Database.DMLOptions();
		options.optAllOrNone = false;
		options.allowFieldTruncation = true;
		List<Database.SaveResult> results = Database.update(
			communications,
			options
		);

		for (Integer i = 0; i < results.size(); i++) {
			if (!results[i].isSuccess()) {
				CobranzaLog.error(
						CobranzaLog.STAGE_RECEPCION_POLIZAS,
						CobranzaLog.EVENT_POLICY_INBOUND_WRITE_FAILED,
						'No se pudo guardar el resultado de la comunicacion. Motivo: ' +
						results[i].getErrors()[0].getMessage()
					)
					.onRecord(communications[i].Id);
			}
		}
	}

	private static InboundPolicyUpdate__c review(
		InboundPolicyUpdate__c communication,
		String matchReason,
		String reviewReason
	) {
		return new InboundPolicyUpdate__c(
			Id = communication.Id,
			inboundStatus__c = STATUS_REVIEW,
			policyMatchReason__c = matchReason,
			manualReviewRequired__c = true,
			manualReviewReason__c = reviewReason
		);
	}

	private static InboundPolicyUpdate__c supersede(
		InboundPolicyUpdate__c communication,
		Id policyId,
		String reason
	) {
		return new InboundPolicyUpdate__c(
			Id = communication.Id,
			inboundStatus__c = STATUS_SUPERSEDED,
			candidatePolicy__c = policyId,
			policyMatchReason__c = REASON_BY_TERM,
			manualReviewReason__c = reason
		);
	}

	/**
	 * @creation date: 28/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Devuelve la poliza del Id que informo MuleSoft, solo si es coherente: tiene
	 *               el numero comunicado y su vigencia contiene el inicio comunicado. Si no (Id
	 *               invalido, de otra poliza, o de la vigencia anterior cuando llega una
	 *               renovacion) devuelve null y decide la regla de numero + inicio de vigencia.
	 * @param communication: Comunicacion.
	 * @param policiesByNumber: Polizas del lote por numero.
	 * @return: InsurancePolicy Poliza, o null.
	 * @exception:
	 * @throws:
	 */
	private static InsurancePolicy policyByReportedId(
		InboundPolicyUpdate__c communication,
		Map<String, List<InsurancePolicy>> policiesByNumber
	) {
		if (String.isBlank(communication.sourcePolicyId__c)) {
			return null;
		}

		List<InsurancePolicy> sameNumber = policiesByNumber.get(
			normalizeNumber(communication.sourcePolicyNumber__c)
		);

		if (sameNumber == null) {
			return null;
		}

		for (InsurancePolicy policy : sameNumber) {
			if (
				String.valueOf(policy.Id).left(15) ==
				communication.sourcePolicyId__c.trim().left(15) &&
				termContains(policy, communication.sourcePolicyStartDate__c)
			) {
				return policy;
			}
		}

		return null;
	}

	private static Map<String, List<InsurancePolicy>> selectPolicies(
		List<InboundPolicyUpdate__c> updates
	) {
		Set<String> numbers = new Set<String>();

		for (InboundPolicyUpdate__c communication : updates) {
			String num = normalizeNumber(communication.sourcePolicyNumber__c);

			if (num != null) {
				numbers.add(num);
			}
		}

		Map<String, List<InsurancePolicy>> result = new Map<String, List<InsurancePolicy>>();

		for (InsurancePolicy policy : [
			SELECT
				Id,
				Name,
				EffectiveDate,
				ExpirationDate,
				SaleDate,
				RenewalDate,
				Ramo__c,
				PremiumFrequency,
				PremiumAmount,
				Subtotal__c,
				Derecho_Poliza__c,
				Financiamiento__c,
				IVA__c,
				Discount,
				insuredAssetDescription__c,
				carrierPaymentMode__c,
				sourceIntermediaryName__c,
				Moneda__c,
				carrierDataSyncedAt__c,
				carrierPolicyUpdate__c
			FROM InsurancePolicy
			WHERE Name IN :numbers
		]) {
			String num = normalizeNumber(policy.Name);

			if (!result.containsKey(num)) {
				result.put(num, new List<InsurancePolicy>());
			}

			result.get(num).add(policy);
		}

		return result;
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Indica si el periodo de la poliza contiene la fecha, comparando por dia. El
	 *               ultimo dia NO cuenta: en las aseguradoras una vigencia termina el mismo dia
	 *               en que empieza la siguiente, y contarlo aplicaria la renovacion sobre la
	 *               vigencia que acaba. Una poliza sin ninguno de los dos extremos no aporta
	 *               evidencia y no gana.
	 * @param policy: Poliza con su periodo.
	 * @param day: Inicio de vigencia comunicado.
	 * @return: Boolean Verdadero si la fecha cae en el periodo.
	 * @exception:
	 * @throws:
	 */
	private static Boolean termContains(InsurancePolicy policy, Date day) {
		if (
			day == null ||
			(policy.EffectiveDate == null &&
			policy.ExpirationDate == null)
		) {
			return false;
		}

		if (policy.EffectiveDate != null && day < policy.EffectiveDate.dateGmt()) {
			return false;
		}

		if (
			policy.ExpirationDate != null &&
			day >= policy.ExpirationDate.dateGmt()
		) {
			return false;
		}

		return true;
	}

	private static Boolean startsOn(InsurancePolicy policy, Date day) {
		return day != null &&
			policy.EffectiveDate != null &&
			policy.EffectiveDate.dateGmt() == day;
	}

	private static Boolean currencyMismatch(
		InboundPolicyUpdate__c communication,
		InsurancePolicy policy
	) {
		return String.isNotBlank(communication.sourceCurrency__c) &&
			String.isNotBlank(policy.Moneda__c) &&
			!communication.sourceCurrency__c.trim()
				.equalsIgnoreCase(policy.Moneda__c.trim());
	}

	private static Datetime syncOf(InboundPolicyUpdate__c communication) {
		return communication.sourceSynchronizedAt__c != null
			? communication.sourceSynchronizedAt__c
			: communication.receivedAt__c;
	}

	private static String normalizeNumber(String value) {
		return String.isBlank(value) ? null : value.trim().toUpperCase();
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Clave para buscar una equivalencia: mayusculas, sin acentos y solo letras.
	 *               «Gastos Médicos», «GASTOS MEDICOS» y «gastos-medicos» dan lo mismo.
	 * @param value: Texto comunicado.
	 * @return: String Clave.
	 * @exception:
	 * @throws:
	 */
	@TestVisible
	private static String normalizeKey(String value) {
		String text = value.trim().toUpperCase();
		Map<String, String> accents = new Map<String, String>{
			'Á' => 'A',
			'É' => 'E',
			'Í' => 'I',
			'Ó' => 'O',
			'Ú' => 'U',
			'Ü' => 'U',
			'Ñ' => 'N'
		};

		for (String accent : accents.keySet()) {
			text = text.replace(accent, accents.get(accent));
		}

		return text.replaceAll('[^A-Z]', '');
	}
}
