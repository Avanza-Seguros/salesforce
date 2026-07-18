/**
 *   @name: PaymentReconciliationManualService
 *   @version: 1.0
 *   @creation date: 18/07/2026
 *   @author: Javier Torres - Volestra
 *   @description: Servicio de resolucion manual de conciliaciones en revision (historias
 *                 193 aprobar, 194 rechazar, 195 reprocesar). Esta version implementa la
 *                 aprobacion manual (H193): valida que el caso tenga la informacion minima
 *                 (poliza y cuota final abiertas), sella la decision manual con trazabilidad
 *                 (manualResolvedBy__c / manualResolvedAt__c / matchMethod__c = Decision
 *                 manual), deja la conciliacion en Conciliado, cascada el estado al inbound
 *                 y reutiliza PolicyPaymentReceiptQueueable para crear el recibo (idempotente
 *                 por resultingReceipt__c). El sello manualResolvedBy__c actua como candado
 *                 del guardail anti-reentrada en PaymentReconciliationQueueable.
 */
public with sharing class PaymentReconciliationManualService {
	private static final String STATUS_RECONCILED = 'Conciliado';
	private static final String STATUS_REJECTED = 'Rechazado';
	private static final String STATUS_DUPLICATE = 'Duplicado';
	private static final String MATCH_METHOD_MANUAL = 'Decision manual';
	private static final String INBOUND_STATUS_RECONCILED = 'Conciliado';
	private static final String PLAN_STATUS_ACTIVE = 'Activo';

	private static final Set<String> CLOSED_STATUSES = new Set<String>{
		STATUS_RECONCILED,
		STATUS_REJECTED,
		STATUS_DUPLICATE
	};
	private static final Set<String> OPEN_INSTALLMENT_STATUSES = new Set<String>{
		'Pendiente',
		'Vencido'
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
