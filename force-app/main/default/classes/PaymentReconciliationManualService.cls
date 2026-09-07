/**
 *   @name: PaymentReconciliationManualService
 *   @version: 1.0
 *   @creation date: 18/07/2026
 *   @author: Javier Torres - Volestra
 *   @description: Servicio de resolucion manual de conciliaciones en revision.
 *                 - H193 (approve): valida poliza y cuota final abiertas, sella la decision
 *                   manual, deja la conciliacion en Conciliado, cascada el inbound y reutiliza
 *                   PolicyPaymentReceiptQueueable (idempotente por resultingReceipt__c).
 *                 - H194 (reject): captura motivo y notas, deja Rechazado, cascada el inbound
 *                   a Rechazado y no genera recibo.
 *                 - H195 (reprocess): libera el candado manual (manualResolvedBy__c), resetea
 *                   el inbound a Normalizado y re-encola el pipeline desde la identificacion de
 *                   poliza candidata, dejando traza (reprocessCount__c / lastReprocessedAt__c /
 *                   lastReprocessedBy__c en el inbound, y reprocessLog__c append-only en la
 *                   conciliacion). El doble cobro es imposible por diseno: externalPaymentId__c
 *                   es Unique External Id (un inbound por pago) y solo se reprocesan casos sin
 *                   recibo, por lo que un pago no puede generar dos recibos Reconocido.
 *                 El sello manualResolvedBy__c actua como candado del guardail anti-reentrada
 *                 en PaymentReconciliationQueueable; el reproceso es la unica via que lo libera.
 */
public with sharing class PaymentReconciliationManualService {
	private static final String STATUS_RECONCILED = 'Conciliado';
	private static final String STATUS_REJECTED = 'Rechazado';
	private static final String STATUS_DUPLICATE = 'Duplicado';
	private static final String MATCH_METHOD_MANUAL = 'Decision manual';
	private static final String STATUS_REVIEW = 'Requiere revision';
	private static final String INBOUND_STATUS_RECONCILED = 'Conciliado';
	private static final String INBOUND_STATUS_REJECTED = 'Rechazado';
	private static final String INBOUND_STATUS_NORMALIZED = 'Normalizado';
	private static final String INBOUND_REJECTION_REASON_BUSINESS = 'Rechazado por negocio';
	private static final String PLAN_STATUS_ACTIVE = 'Activo';
	private static final String RECEIPT_STATUS_REVERSED = 'Reversado';

	private static final Set<String> CLOSED_STATUSES = new Set<String>{
		STATUS_RECONCILED,
		STATUS_REJECTED,
		STATUS_DUPLICATE
	};
	private static final Set<String> OPEN_INSTALLMENT_STATUSES = new Set<String>{
		'Pendiente',
		'Vencido'
	};
	// Estados desde los que un caso puede reprocesarse (H195). El unico no elegible
	// es Conciliado con recibo Reconocido (requiere reversa, fuera de alcance).
	private static final Set<String> REPROCESSABLE_STATUSES = new Set<String>{
		'Requiere revision',
		'Probable',
		'Sin Match',
		'Rechazado',
		'Duplicado'
	};

	public class ManualResolutionException extends Exception {
	}

	/**
	 * @creation date: 18/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Punto de entrada AuraEnabled para la UI de aprobacion manual. Delega
	 *               en approveReconciliation y traduce las excepciones de negocio a
	 *               AuraHandledException para mostrarlas en el componente.
	 * @param reconciliationId: Id de la PaymentReconciliation__c en revision.
	 * @param finalPolicyId: Id de la InsurancePolicy final seleccionada por el analista.
	 * @param finalInstallmentId: Id de la PaymentPlanInstallment__c final seleccionada.
	 * @param notes: Notas/justificacion del analista.
	 * @return
	 */
	@AuraEnabled
	public static void approve(
		Id reconciliationId,
		Id finalPolicyId,
		Id finalInstallmentId,
		String notes
	) {
		try {
			approveReconciliation(
				reconciliationId,
				finalPolicyId,
				finalInstallmentId,
				notes
			);
		} catch (ManualResolutionException e) {
			throw new AuraHandledException(e.getMessage());
		}
	}

	/**
	 * @creation date: 18/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Aplica la aprobacion manual sobre la conciliacion: valida elegibilidad
	 *               y completitud (poliza y cuota final abiertas, caso no cerrado, sin
	 *               recibo previo), sella la decision manual, deja la conciliacion en
	 *               Conciliado, cascada el inbound a Conciliado y encola la creacion del
	 *               recibo. Lanza ManualResolutionException con mensaje claro ante cualquier
	 *               caso incompleto o inconsistente.
	 * @param reconciliationId: Id de la conciliacion a aprobar.
	 * @param finalPolicyId: Id de la poliza final.
	 * @param finalInstallmentId: Id de la cuota final.
	 * @param notes: Notas del analista.
	 * @return
	 */
	@TestVisible
	private static void approveReconciliation(
		Id reconciliationId,
		Id finalPolicyId,
		Id finalInstallmentId,
		String notes
	) {
		if (reconciliationId == null) {
			throw new ManualResolutionException('Falta la conciliación a aprobar.');
		}
		if (finalPolicyId == null) {
			throw new ManualResolutionException(
				'Debe seleccionar una póliza final para aprobar.'
			);
		}
		if (finalInstallmentId == null) {
			throw new ManualResolutionException(
				'Debe seleccionar una cuota final para aprobar.'
			);
		}

		PaymentReconciliation__c recon = loadReconciliation(reconciliationId);

		if (CLOSED_STATUSES.contains(recon.reconciliationStatus__c)) {
			throw new ManualResolutionException(
				'La conciliación ya está cerrada y no puede aprobarse de nuevo.'
			);
		}
		if (recon.resultingReceipt__c != null) {
			throw new ManualResolutionException(
				'La conciliación ya tiene un recibo generado.'
			);
		}

		PaymentPlanInstallment__c inst = loadInstallment(finalInstallmentId);

		if (inst.paymentPlan__r.insurancePolicy__c != finalPolicyId) {
			throw new ManualResolutionException(
				'La cuota seleccionada no pertenece a la póliza seleccionada.'
			);
		}
		if (!OPEN_INSTALLMENT_STATUSES.contains(inst.installmentStatus__c)) {
			throw new ManualResolutionException(
				'La cuota seleccionada no está abierta (Pendiente o Vencido).'
			);
		}
		if (inst.matchedReceipt__c != null) {
			throw new ManualResolutionException(
				'La cuota seleccionada ya tiene un recibo vinculado.'
			);
		}

		recon.insurancePolicy__c = finalPolicyId;
		recon.paymentPlan__c = inst.paymentPlan__c;
		recon.paymentPlanInstallment__c = finalInstallmentId;
		recon.reconciliationStatus__c = STATUS_RECONCILED;
		recon.matchMethod__c = MATCH_METHOD_MANUAL;
		recon.manualResolvedBy__c = UserInfo.getUserId();
		recon.manualResolvedAt__c = System.now();
		recon.decisionNotes__c = appendManualNote(
			recon.decisionNotes__c,
			'Aprobación manual',
			notes
		);
		update recon;

		if (recon.inboundPayment__c != null) {
			update new InboundInsurancePayment__c(
				Id = recon.inboundPayment__c,
				inboundStatus__c = INBOUND_STATUS_RECONCILED
			);
		}

		System.enqueueJob(
			new PolicyPaymentReceiptQueueable(new Set<Id>{ recon.Id })
		);
	}

	/**
	 * @creation date: 18/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Punto de entrada AuraEnabled para la UI de rechazo manual (H194).
	 *               Delega en rejectReconciliation y traduce las excepciones de negocio
	 *               a AuraHandledException.
	 * @param reconciliationId: Id de la PaymentReconciliation__c en revision.
	 * @param rejectedReason: Motivo de rechazo (picklist rejectedReason__c).
	 * @param notes: Notas de decision del analista (obligatorias).
	 * @return
	 */
	@AuraEnabled
	public static void reject(
		Id reconciliationId,
		String rejectedReason,
		String notes
	) {
		try {
			rejectReconciliation(reconciliationId, rejectedReason, notes);
		} catch (ManualResolutionException e) {
			throw new AuraHandledException(e.getMessage());
		}
	}

	/**
	 * @creation date: 18/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Aplica el rechazo manual sobre la conciliacion (H194): valida
	 *               elegibilidad (caso no cerrado, sin recibo) y captura minima (motivo
	 *               y notas), deja la conciliacion en Rechazado con el motivo, sella la
	 *               decision manual y cascada el inbound a Rechazado. No genera recibo.
	 *               El sello manualResolvedBy__c activa el guardail anti-reentrada.
	 * @param reconciliationId: Id de la conciliacion a rechazar.
	 * @param rejectedReason: Motivo de rechazo.
	 * @param notes: Notas de decision.
	 * @return
	 */
	@TestVisible
	private static void rejectReconciliation(
		Id reconciliationId,
		String rejectedReason,
		String notes
	) {
		if (reconciliationId == null) {
			throw new ManualResolutionException('Falta la conciliación a rechazar.');
		}
		if (String.isBlank(rejectedReason)) {
			throw new ManualResolutionException(
				'Debe seleccionar un motivo de rechazo.'
			);
		}
		if (String.isBlank(notes)) {
			throw new ManualResolutionException(
				'Debe capturar notas de decisión para rechazar.'
			);
		}

		PaymentReconciliation__c recon = loadReconciliation(reconciliationId);

		if (CLOSED_STATUSES.contains(recon.reconciliationStatus__c)) {
			throw new ManualResolutionException(
				'La conciliación ya está cerrada y no puede rechazarse de nuevo.'
			);
		}
		if (recon.resultingReceipt__c != null) {
			throw new ManualResolutionException(
				'La conciliación ya tiene un recibo generado y no puede rechazarse.'
			);
		}

		recon.reconciliationStatus__c = STATUS_REJECTED;
		recon.rejectedReason__c = rejectedReason;
		recon.manualResolvedBy__c = UserInfo.getUserId();
		recon.manualResolvedAt__c = System.now();
		recon.decisionNotes__c = appendManualNote(
			recon.decisionNotes__c,
			'Rechazo manual',
			notes
		);
		update recon;

		if (recon.inboundPayment__c != null) {
			update new InboundInsurancePayment__c(
				Id = recon.inboundPayment__c,
				inboundStatus__c = INBOUND_STATUS_REJECTED,
				rejectionReason__c = INBOUND_REJECTION_REASON_BUSINESS
			);
		}
	}

	/**
	 * @creation date: 18/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Punto de entrada AuraEnabled para la UI de reproceso (H195). Delega
	 *               en reprocessReconciliation y traduce las excepciones de negocio a
	 *               AuraHandledException.
	 * @param reconciliationId: Id de la conciliacion a reprocesar.
	 * @param notes: Motivo/notas del reproceso (opcional).
	 * @return
	 */
	@AuraEnabled
	public static void reprocess(Id reconciliationId, String notes) {
		try {
			reprocessReconciliation(reconciliationId, notes);
		} catch (ManualResolutionException e) {
			throw new AuraHandledException(e.getMessage());
		}
	}

	/**
	 * @creation date: 18/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Reintenta la conciliacion sobre el inbound existente (H195): valida
	 *               elegibilidad (no reconocido, sin recibo, estado reprocesable), guarda
	 *               el estado previo en la bitacora append-only reprocessLog__c, libera el
	 *               candado manual y saca el caso del estado terminal (para que el pipeline
	 *               pueda actualizarlo), resetea el inbound a Normalizado con la traza de
	 *               reproceso, y re-encola InboundPolicyCandidateQueueable para re-correr la
	 *               identificacion de poliza/cuota, reglas y score. No re-parsea el payload:
	 *               usa los campos normalizados actuales, respetando correcciones del analista.
	 * @param reconciliationId: Id de la conciliacion a reprocesar.
	 * @param notes: Notas del reproceso.
	 * @return
	 */
	@TestVisible
	private static void reprocessReconciliation(
		Id reconciliationId,
		String notes
	) {
		if (reconciliationId == null) {
			throw new ManualResolutionException(
				'Falta la conciliación a reprocesar.'
			);
		}

		PaymentReconciliation__c recon = loadReconciliationForReprocess(
			reconciliationId
		);

		// H201: un recibo REVERSADO ya no sostiene la conciliacion, asi que deja de bloquear
		// el reproceso. Es exactamente la puerta que anticipaba el mensaje de error original
		// ("requiere reversa"): antes de la 201 no existia forma de atravesarla y el caso
		// quedaba muerto, ni conciliado de verdad ni reprocesable.
		Boolean hasActiveReceipt =
			recon.resultingReceipt__c != null &&
			!RECEIPT_STATUS_REVERSED.equals(
				recon.resultingReceipt__r.receiptStatus__c
			);
		if (hasActiveReceipt) {
			throw new ManualResolutionException(
				'La conciliación tiene un recibo vigente y no puede reprocesarse; primero hay que reversar el recibo.'
			);
		}
		if (STATUS_RECONCILED.equals(recon.reconciliationStatus__c)) {
			throw new ManualResolutionException(
				'La conciliación está reconocida y no puede reprocesarse.'
			);
		}
		if (!REPROCESSABLE_STATUSES.contains(recon.reconciliationStatus__c)) {
			throw new ManualResolutionException(
				'El estado actual de la conciliación no permite reproceso.'
			);
		}
		if (recon.inboundPayment__c == null) {
			throw new ManualResolutionException(
				'La conciliación no tiene un inbound asociado para reprocesar.'
			);
		}

		// Bitacora append-only: el pipeline no toca reprocessLog__c, asi que conserva el
		// historico entre re-corridas. Se calcula antes de resetear estado/motivo.
		recon.reprocessLog__c = appendReprocessLog(recon, notes);
		// Libera el guardail anti-reentrada y saca el caso del estado terminal para que el
		// pipeline reentrante pueda actualizar la conciliacion con el nuevo resultado.
		recon.manualResolvedBy__c = null;
		recon.manualResolvedAt__c = null;
		recon.rejectedReason__c = null;
		recon.reconciliationStatus__c = STATUS_REVIEW;
		update recon;

		InboundInsurancePayment__c inbound = loadInboundForReprocess(
			recon.inboundPayment__c
		);
		Decimal previous = inbound.reprocessCount__c == null
			? 0
			: inbound.reprocessCount__c;
		update new InboundInsurancePayment__c(
			Id = inbound.Id,
			inboundStatus__c = INBOUND_STATUS_NORMALIZED,
			reprocessCount__c = previous + 1,
			lastReprocessedAt__c = System.now(),
			lastReprocessedBy__c = UserInfo.getUserId()
		);

		System.enqueueJob(
			new InboundPolicyCandidateQueueable(new Set<Id>{ inbound.Id })
		);
	}

	/**
	 * @creation date: 18/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Carga la conciliacion con los campos necesarios para validar y reprocesar.
	 * @param reconciliationId: Id de la conciliacion.
	 * @return PaymentReconciliation__c cargada.
	 */
	private static PaymentReconciliation__c loadReconciliationForReprocess(
		Id reconciliationId
	) {
		List<PaymentReconciliation__c> recons = [
			SELECT
				Id,
				reconciliationStatus__c,
				rejectedReason__c,
				resultingReceipt__c,
				resultingReceipt__r.receiptStatus__c,
				inboundPayment__c,
				manualResolvedBy__c,
				reprocessLog__c
			FROM PaymentReconciliation__c
			WHERE Id = :reconciliationId
			LIMIT 1
		];
		if (recons.isEmpty()) {
			throw new ManualResolutionException('La conciliación no existe.');
		}
		return recons[0];
	}

	/**
	 * @creation date: 18/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Carga el inbound con el contador de reprocesos para incrementarlo.
	 * @param inboundId: Id del inbound.
	 * @return InboundInsurancePayment__c cargado.
	 */
	private static InboundInsurancePayment__c loadInboundForReprocess(
		Id inboundId
	) {
		return [
			SELECT Id, reprocessCount__c
			FROM InboundInsurancePayment__c
			WHERE Id = :inboundId
			LIMIT 1
		];
	}

	/**
	 * @creation date: 18/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Construye la entrada de bitacora del reproceso (sello, estado previo,
	 *               motivo y notas) y la agrega al historico existente sin perderlo.
	 * @param recon: Conciliacion con el estado previo aun sin resetear.
	 * @param notes: Notas del reproceso, opcionales.
	 * @return Texto de bitacora combinado.
	 */
	@TestVisible
	private static String appendReprocessLog(
		PaymentReconciliation__c recon,
		String notes
	) {
		String stamp =
			'[Reproceso ' +
			System.now().format('yyyy-MM-dd HH:mm') +
			' por ' +
			UserInfo.getName() +
			']';
		String prev =
			'Estado previo: ' +
			recon.reconciliationStatus__c +
			(String.isNotBlank(recon.rejectedReason__c)
				? ' (motivo: ' + recon.rejectedReason__c + ')'
				: '') +
			'.';
		String entry =
			stamp +
			' ' +
			prev +
			(String.isNotBlank(notes) ? ' ' + notes : '');
		if (String.isBlank(recon.reprocessLog__c)) {
			return entry;
		}
		return recon.reprocessLog__c + '\n' + entry;
	}

	/**
	 * @creation date: 18/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Devuelve las cuotas abiertas (Pendiente/Vencido, sin recibo vinculado)
	 *               de los planes activos de una poliza, para que el analista elija la
	 *               cuota final en la UI de aprobacion.
	 * @param policyId: Id de la InsurancePolicy seleccionada.
	 * @return Lista de PaymentPlanInstallment__c elegibles ordenadas por secuencia.
	 */
	@AuraEnabled(cacheable=true)
	public static List<PaymentPlanInstallment__c> getOpenInstallments(
		Id policyId
	) {
		if (policyId == null) {
			return new List<PaymentPlanInstallment__c>();
		}
		return [
			SELECT
				Id,
				Name,
				sequenceNumber__c,
				dueDate__c,
				expectedAmount__c,
				installmentStatus__c,
				paymentPlan__c
			FROM PaymentPlanInstallment__c
			WHERE
				paymentPlan__r.insurancePolicy__c = :policyId
				AND paymentPlan__r.planStatus__c = :PLAN_STATUS_ACTIVE
				AND installmentStatus__c IN :OPEN_INSTALLMENT_STATUSES
				AND matchedReceipt__c = NULL
			ORDER BY sequenceNumber__c
		];
	}

	/**
	 * @creation date: 18/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Carga la conciliacion con los campos necesarios para validar y aprobar.
	 * @param reconciliationId: Id de la conciliacion.
	 * @return PaymentReconciliation__c cargada.
	 */
	private static PaymentReconciliation__c loadReconciliation(
		Id reconciliationId
	) {
		List<PaymentReconciliation__c> recons = [
			SELECT
				Id,
				reconciliationStatus__c,
				resultingReceipt__c,
				inboundPayment__c,
				insurancePolicy__c,
				paymentPlan__c,
				paymentPlanInstallment__c,
				decisionNotes__c
			FROM PaymentReconciliation__c
			WHERE Id = :reconciliationId
			LIMIT 1
		];
		if (recons.isEmpty()) {
			throw new ManualResolutionException('La conciliación no existe.');
		}
		return recons[0];
	}

	/**
	 * @creation date: 18/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Carga la cuota final con su plan y poliza para validar consistencia.
	 * @param installmentId: Id de la cuota.
	 * @return PaymentPlanInstallment__c cargada.
	 */
	private static PaymentPlanInstallment__c loadInstallment(Id installmentId) {
		List<PaymentPlanInstallment__c> insts = [
			SELECT
				Id,
				installmentStatus__c,
				matchedReceipt__c,
				paymentPlan__c,
				paymentPlan__r.insurancePolicy__c
			FROM PaymentPlanInstallment__c
			WHERE Id = :installmentId
			LIMIT 1
		];
		if (insts.isEmpty()) {
			throw new ManualResolutionException('La cuota seleccionada no existe.');
		}
		return insts[0];
	}

	/**
	 * @creation date: 18/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Antepone una entrada con sello (accion, fecha/hora, usuario) a las notas
	 *               de decision existentes, preservando el historico previo.
	 * @param existing: Notas de decision actuales.
	 * @param action: Etiqueta de la accion (p. ej. "Aprobación manual").
	 * @param notes: Notas del analista, opcionales.
	 * @return Texto de notas combinado.
	 */
	@TestVisible
	private static String appendManualNote(
		String existing,
		String action,
		String notes
	) {
		String stamp =
			'[' +
			action +
			' ' +
			System.now().format('yyyy-MM-dd HH:mm') +
			' por ' +
			UserInfo.getName() +
			']';
		String entry = String.isNotBlank(notes) ? stamp + ' ' + notes : stamp;
		if (String.isBlank(existing)) {
			return entry;
		}
		return existing + '\n' + entry;
	}
}
