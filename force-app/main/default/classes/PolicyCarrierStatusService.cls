/**
 *   @name: PolicyCarrierStatusService
 *   @version: 1.0
 *   @creation date: 16/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Guarda en la poliza el estado que comunica la aseguradora, tal cual y
 *                 normalizado, sin inferir nada. Procesa las comunicaciones de estado de poliza
 *                 (registros sin folio que llegan por el canal de pagos) y los recibos que
 *                 ademas informan el estado de su poliza. Solo guarda lo que dijo la
 *                 aseguradora: no cambia el estado operativo de la poliza (Status).
 */
public with sharing class PolicyCarrierStatusService {
	public static final String STATUS_POLICY_NOTICE = 'Estado de poliza';
	private static final String STATUS_MANUAL_REVIEW = 'Revision Manual';
	private static final String STATUS_REJECTED = 'Rechazado';
	private static final String REASON_NO_POLICY = 'SIN_POLIZA';
	private static final String REASON_AMBIGUOUS_TERM = 'VIGENCIA_AMBIGUA';
	private static final Set<String> NORMALIZED_VALUES = new Set<String>{
		'Vigente',
		'Cancelado',
		'Vencido'
	};
	private static final Integer RAW_STATUS_LENGTH = 50;

	// Sustituye las equivalencias configuradas: la metadata no se puede crear desde una prueba.
	@TestVisible
	private static Map<String, String> mappingsForTest;

	// Fuerza el fallo del guardado de estas polizas para probar que el fallo queda registrado.
	@TestVisible
	private static Set<Id> failForTest = new Set<Id>();

	/**
	 * @creation date: 16/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Procesa comunicaciones de estado de poliza y recibos que informan el estado
	 *               de su poliza. Identifica la poliza con la misma regla del circuito: por numero
	 *               y, si varias vigencias lo comparten, por la que contiene la fecha de referencia
	 *               (la de cancelacion en una comunicacion, la del recibo en un pago). Una
	 *               comunicacion cuya poliza no se identifica va a revision manual; un pago que
	 *               no la identifica sigue su curso sin mas, porque de su poliza se ocupa el
	 *               circuito.
	 * @param inboundIds: Registros a procesar.
	 * @return
	 */
	public static void process(Set<Id> inboundIds) {
		if (inboundIds == null || inboundIds.isEmpty()) {
			return;
		}
		List<InboundInsurancePayment__c> notices = new List<InboundInsurancePayment__c>();
		List<InboundInsurancePayment__c> payments = new List<InboundInsurancePayment__c>();
		for (InboundInsurancePayment__c rec : [
			SELECT
				Id,
				policyStatusNotice__c,
				inboundStatus__c,
				sourcePolicyNumber__c,
				sourceCarrierCode__c,
				sourcePolicyStatusRaw__c,
				sourceCancellationDate__c,
				sourceSynchronizedAt__c,
				receivedAt__c,
				sourceDueDate__c,
				sourcePaymentDate__c
			FROM InboundInsurancePayment__c
			WHERE Id IN :inboundIds AND sourcePolicyStatusRaw__c != NULL
		]) {
			if (rec.policyStatusNotice__c) {
				if (STATUS_POLICY_NOTICE.equals(rec.inboundStatus__c)) {
					notices.add(rec);
				}
			} else if (!STATUS_REJECTED.equals(rec.inboundStatus__c)) {
				payments.add(rec);
			}
		}
		List<InboundInsurancePayment__c> all = new List<InboundInsurancePayment__c>(
			notices
		);
		all.addAll(payments);
		if (all.isEmpty()) {
			return;
		}

		Map<Id, InboundPolicyCandidateQueueable.PolicyMatchResult> matches = InboundPolicyCandidateQueueable.resolveAll(
			forResolution(all)
		);
		Map<Id, Id> policyByCommunication = new Map<Id, Id>();
		List<InboundInsurancePayment__c> communications = new List<InboundInsurancePayment__c>();
		List<InboundInsurancePayment__c> noticeUpdates = new List<InboundInsurancePayment__c>();

		for (InboundInsurancePayment__c notice : notices) {
			InboundPolicyCandidateQueueable.PolicyMatchResult match = matches.get(
				notice.Id
			);
			InboundInsurancePayment__c upd = new InboundInsurancePayment__c(
				Id = notice.Id,
				candidatePolicy__c = match.policyId,
				policyMatchReason__c = match.reason
			);
			if (match.policyId == null) {
				upd.inboundStatus__c = STATUS_MANUAL_REVIEW;
				upd.manualReviewRequired__c = true;
				CobranzaLog.warn(
						CobranzaLog.STAGE_ESTADO_POLIZA,
						CobranzaLog.EVENT_POLICY_STATUS_NOTICE_TO_REVIEW,
						'La aseguradora comunicó el estado "' +
							notice.sourcePolicyStatusRaw__c +
							'" de la póliza ' +
							notice.sourcePolicyNumber__c +
							', pero ' +
							describeReason(match.reason) +
							'. Queda para revisión manual.'
					)
					.onInbound(notice.Id);
			} else {
				policyByCommunication.put(notice.Id, match.policyId);
				communications.add(notice);
			}
			noticeUpdates.add(upd);
		}
		for (InboundInsurancePayment__c payment : payments) {
			InboundPolicyCandidateQueueable.PolicyMatchResult match = matches.get(
				payment.Id
			);
			if (match != null && match.policyId != null) {
				policyByCommunication.put(payment.Id, match.policyId);
				communications.add(payment);
			}
		}

		saveNotices(noticeUpdates);
		applyCarrierStatus(communications, policyByCommunication);
	}

	/**
	 * @creation date: 16/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Vuelve a evaluar una comunicacion de estado de poliza que esta en revision
	 *               manual, por ejemplo despues de crear la poliza que faltaba.
	 * @param inboundId: Comunicacion a reprocesar.
	 * @return Mensaje para el analista con el resultado.
	 */
	@AuraEnabled
	public static String reprocessNotice(Id inboundId) {
		List<InboundInsurancePayment__c> found = [
			SELECT Id, policyStatusNotice__c, inboundStatus__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inboundId
		];
		if (found.isEmpty() || !found[0].policyStatusNotice__c) {
			throw fail(
				'Esta acción solo aplica a comunicaciones de estado de póliza.'
			);
		}
		if (!STATUS_MANUAL_REVIEW.equals(found[0].inboundStatus__c)) {
			throw fail(
				'Solo se reprocesa una comunicación de estado de póliza que está en revisión manual.'
			);
		}
		update new InboundInsurancePayment__c(
			Id = inboundId,
			inboundStatus__c = STATUS_POLICY_NOTICE,
			manualReviewRequired__c = false
		);
		process(new Set<Id>{ inboundId });
		AppLogger.flush();

		InboundInsurancePayment__c result = [
			SELECT inboundStatus__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inboundId
		];
		return STATUS_POLICY_NOTICE.equals(result.inboundStatus__c)
			? 'La comunicación quedó asociada a su póliza y su estado se guardó en ella.'
			: 'La póliza sigue sin identificarse: la comunicación vuelve a revisión manual.';
	}

	/**
	 * @creation date: 16/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Guarda en cada poliza la comunicacion mas reciente. Una comunicacion anterior
	 *               a la ultima guardada no cambia nada (entrega tardia). Una igual a la guardada
	 *               tampoco, salvo que su equivalencia haya cambiado: asi, al configurar una
	 *               equivalencia que faltaba, la siguiente comunicacion la aplica.
	 * @param communications: Comunicaciones y pagos con su poliza identificada.
	 * @param policyByCommunication: Poliza de cada registro.
	 * @return
	 */
	private static void applyCarrierStatus(
		List<InboundInsurancePayment__c> communications,
		Map<Id, Id> policyByCommunication
	) {
		if (communications.isEmpty()) {
			return;
		}
		List<Communication> ordered = new List<Communication>();
		for (InboundInsurancePayment__c rec : communications) {
			ordered.add(new Communication(rec, policyByCommunication.get(rec.Id)));
		}
		ordered.sort();

		Map<Id, InsurancePolicy> current = new Map<Id, InsurancePolicy>(
			[
				SELECT
					Id,
					carrierPolicyStatus__c,
					carrierPolicyStatusRaw__c,
					carrierStatusSyncedAt__c
				FROM InsurancePolicy
				WHERE Id IN :policyByCommunication.values()
			]
		);
		Map<String, String> mappings = loadMappings();
		Map<Id, InsurancePolicy> toUpdate = new Map<Id, InsurancePolicy>();

		for (Communication c : ordered) {
			InsurancePolicy policy = current.get(c.policyId);
			if (policy == null) {
				continue;
			}
			String raw = c.record.sourcePolicyStatusRaw__c.trim()
				.left(RAW_STATUS_LENGTH);
			String normalized = mappings.get(
				mappingKey(c.record.sourceCarrierCode__c, raw)
			);
			if (normalized == null) {
				CobranzaLog.warn(
						CobranzaLog.STAGE_ESTADO_POLIZA,
						CobranzaLog.EVENT_CARRIER_POLICY_STATUS_UNMAPPED,
						'La aseguradora ' +
							c.record.sourceCarrierCode__c +
							' comunicó el estado de póliza "' +
							raw +
							'", que no tiene equivalencia configurada. Se guarda el estado original ' +
							'y el normalizado queda vacío hasta configurar la equivalencia.'
					)
					.onInbound(c.record.Id);
			}
			if (
				policy.carrierStatusSyncedAt__c != null &&
				c.communicatedAt != null &&
				c.communicatedAt < policy.carrierStatusSyncedAt__c
			) {
				continue;
			}
			Boolean sameRaw =
				policy.carrierPolicyStatusRaw__c != null &&
				raw.equalsIgnoreCase(policy.carrierPolicyStatusRaw__c);
			if (sameRaw && normalized == policy.carrierPolicyStatus__c) {
				continue;
			}
			policy.carrierPolicyStatus__c = normalized;
			policy.carrierPolicyStatusRaw__c = raw;
			policy.carrierStatusSyncedAt__c = c.communicatedAt;
			toUpdate.put(
				policy.Id,
				new InsurancePolicy(
					Id = policy.Id,
					carrierPolicyStatus__c = normalized,
					carrierPolicyStatusRaw__c = raw,
					carrierStatusSyncedAt__c = c.communicatedAt,
					carrierStatusNotice__c = c.record.Id
				)
			);
		}
		Set<Id> saved = savePolicies(toUpdate.values());
		// El estado operativo lo calcula un unico servicio a partir de lo que quedo guardado.
		PolicyStatusService.applyCommunicatedStatus(saved);
	}

	/**
	 * @creation date: 16/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Llave de equivalencia: aseguradora y estado original, sin espacios extremos ni
	 *               distincion de mayusculas.
	 * @param carrier: Codigo de aseguradora.
	 * @param raw: Estado original.
	 * @return Llave.
	 */
	@TestVisible
	private static String mappingKey(String carrier, String raw) {
		return (carrier == null ? '' : carrier.trim().toUpperCase()) +
			'|' +
			(raw == null ? '' : raw.trim().toUpperCase());
	}

	private static Map<String, String> loadMappings() {
		if (mappingsForTest != null) {
			return mappingsForTest;
		}
		Map<String, String> result = new Map<String, String>();
		for (
			CarrierPolicyStatusMapping__mdt mapping : CarrierPolicyStatusMapping__mdt.getAll()
				.values()
		) {
			if (
				String.isBlank(mapping.RawStatus__c) ||
				!NORMALIZED_VALUES.contains(mapping.NormalizedPolicyStatus__c)
			) {
				continue;
			}
			result.put(
				mappingKey(mapping.CarrierCode__c, mapping.RawStatus__c),
				mapping.NormalizedPolicyStatus__c
			);
		}
		return result;
	}

	private static List<InboundInsurancePayment__c> forResolution(
		List<InboundInsurancePayment__c> records
	) {
		List<InboundInsurancePayment__c> result = new List<InboundInsurancePayment__c>();
		for (InboundInsurancePayment__c rec : records) {
			Date reference = rec.policyStatusNotice__c
				? noticeReferenceDate(rec)
				: (rec.sourceDueDate__c != null
						? rec.sourceDueDate__c
						: rec.sourcePaymentDate__c);
			result.add(
				new InboundInsurancePayment__c(
					Id = rec.Id,
					sourcePolicyNumber__c = rec.sourcePolicyNumber__c,
					sourceDueDate__c = reference
				)
			);
		}
		return result;
	}

	private static Date noticeReferenceDate(InboundInsurancePayment__c notice) {
		if (notice.sourceCancellationDate__c != null) {
			return notice.sourceCancellationDate__c;
		}
		DateTime moment = timestampOf(notice);
		return moment == null ? null : moment.date();
	}

	private static DateTime timestampOf(InboundInsurancePayment__c rec) {
		return rec.sourceSynchronizedAt__c != null
			? rec.sourceSynchronizedAt__c
			: rec.receivedAt__c;
	}

	private static String describeReason(String reason) {
		if (REASON_NO_POLICY.equals(reason)) {
			return 'esa póliza no existe en Salesforce';
		}
		if (REASON_AMBIGUOUS_TERM.equals(reason)) {
			return 'hay varias vigencias con ese número y la fecha no permite elegir una';
		}
		return 'no se pudo identificar la póliza';
	}

	private static void saveNotices(List<InboundInsurancePayment__c> notices) {
		if (notices.isEmpty()) {
			return;
		}
		List<Database.SaveResult> results = Database.update(notices, false);
		for (Integer i = 0; i < results.size(); i++) {
			if (!results[i].isSuccess()) {
				CobranzaLog.error(
						CobranzaLog.STAGE_ESTADO_POLIZA,
						CobranzaLog.EVENT_CARRIER_POLICY_STATUS_FAILED,
						'No se pudo guardar el resultado de la comunicación: ' +
						describeErrors(results[i].getErrors())
					)
					.onInbound(notices[i].Id);
			}
		}
	}

	private static Set<Id> savePolicies(List<InsurancePolicy> policies) {
		Set<Id> saved = new Set<Id>();
		if (policies.isEmpty()) {
			return saved;
		}
		if (Test.isRunningTest()) {
			for (InsurancePolicy policy : policies) {
				if (failForTest.contains(policy.Id)) {
					policy.Name = null;
				}
			}
		}
		List<Database.SaveResult> results = Database.update(policies, false);
		for (Integer i = 0; i < results.size(); i++) {
			if (results[i].isSuccess()) {
				saved.add(policies[i].Id);
				continue;
			}
			CobranzaLog.error(
					CobranzaLog.STAGE_ESTADO_POLIZA,
					CobranzaLog.EVENT_CARRIER_POLICY_STATUS_FAILED,
					'No se pudo guardar en la póliza el estado comunicado por la aseguradora. ' +
						'Las demás pólizas se actualizaron. Motivo: ' +
						describeErrors(results[i].getErrors())
				)
				.onRecord(policies[i].Id);
		}
		return saved;
	}

	private static String describeErrors(List<Database.Error> errors) {
		List<String> messages = new List<String>();
		for (Database.Error error : errors) {
			messages.add(error.getMessage());
		}
		return String.join(messages, '; ');
	}

	private static AuraHandledException fail(String message) {
		AuraHandledException e = new AuraHandledException(message);
		e.setMessage(message);
		return e;
	}

	private class Communication implements Comparable {
		InboundInsurancePayment__c record;
		Id policyId;
		DateTime communicatedAt;

		Communication(InboundInsurancePayment__c record, Id policyId) {
			this.record = record;
			this.policyId = policyId;
			this.communicatedAt = timestampOf(record);
		}

		public Integer compareTo(Object other) {
			DateTime mine = communicatedAt;
			DateTime theirs = ((Communication) other).communicatedAt;
			if (mine == theirs) {
				return 0;
			}
			if (mine == null) {
				return -1;
			}
			if (theirs == null) {
				return 1;
			}
			return mine < theirs ? -1 : 1;
		}
	}
}
