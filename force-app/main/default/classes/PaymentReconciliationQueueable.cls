/**
 *   @name: PaymentReconciliationQueueable
 *   @version: 1.0
 *   @creation date: 20/05/2026
 *   @author: Javier Torres - Volestra
 *   @description: Sexto eslabon del pipeline de normalizacion de pagos inbound.
 *                 Crea o actualiza un registro PaymentReconciliation__c para cada
 *                 inbound evaluado, independientemente del resultado (Conciliado,
 *                 Revision Manual, Sin Match). Es reentrante: si el inbound ya tiene
 *                 una conciliacion (reproceso), la actualiza con el ultimo resultado
 *                 en lugar de omitirla. Encadena a PolicyPaymentReceiptQueueable los
 *                 registros que quedan en Conciliado (nuevos o actualizados); la
 *                 creacion del recibo es idempotente y no duplica si ya existe.
 */
public with sharing class PaymentReconciliationQueueable implements Queueable {
	private static final String STATUS_RECONCILED = 'Conciliado';

	private static final String METHOD_EXACT_POLICY_AND_SEQUENCE = 'EXACT_POLICY_AND_SEQUENCE';
	private static final String METHOD_POLICY_DATE_AMOUNT = 'POLICY_DATE_AMOUNT';
	private static final String METHOD_POLICY_AMOUNT = 'POLICY_AMOUNT';
	private static final String METHOD_POLICY_ONLY = 'POLICY_ONLY';
	private static final String METHOD_AMBIGUOUS = 'AMBIGUOUS';

	private static final String MATCH_EXACT_INSTALLMENT = 'Cuota exacta';
	private static final String MATCH_POLICY_AMOUNT = 'Poliza e importe';
	private static final String MATCH_ASSISTED = 'Asistido por candidato';
	private static final String MATCH_MANUAL = 'Decision manual';

	private static final String RECON_STATUS_RECONCILED = 'Conciliado';
	private static final String RECON_STATUS_PROBABLE = 'Probable';
	private static final String RECON_STATUS_REVIEW = 'Requiere revision';
	private static final String RECON_STATUS_NO_MATCH = 'Sin Match';

	private static final String INBOUND_STATUS_NO_MATCH = 'Sin Match';

	@TestVisible
	private static Boolean forceFailureForTest = false;

	private class ReconciliationException extends Exception {
	}

	private Set<Id> inboundPaymentIds;

	/**
	 * @creation date: 20/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Inicializa el job con los IDs de los inbounds evaluados.
	 * @param inboundPaymentIds: Conjunto de IDs de InboundInsurancePayment__c ya evaluados.
	 * @return
	 */
	public PaymentReconciliationQueueable(Set<Id> inboundPaymentIds) {
		this.inboundPaymentIds = inboundPaymentIds;
	}

	/**
	 * @creation date: 20/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Punto de entrada del job. Consulta los inbounds evaluados, carga las
	 *               conciliaciones existentes y los datos de cuota candidata, y hace
	 *               upsert de PaymentReconciliation__c: inserta una nueva para los
	 *               inbounds sin conciliacion previa y actualiza la existente cuando el
	 *               inbound se reproceso, manteniendo score, estado y metodo alineados
	 *               con el ultimo resultado. Encadena a PolicyPaymentReceiptQueueable
	 *               todos los registros en Conciliado (nuevos o actualizados); el recibo
	 *               no se duplica porque su creacion filtra por resultingReceipt__c =
	 *               null. Si ocurre una excepcion en un registro individual ese registro
	 *               se omite sin afectar al resto.
	 * @param context: Contexto de ejecucion del Queueable proporcionado por la plataforma.
	 * @return
	 */
	public void execute(QueueableContext context) {
		List<InboundInsurancePayment__c> payments = [
			SELECT
				Id,
				candidatePolicy__c,
				candidateInstallment__c,
				reconciliationMethod__c,
				reconciliationResult__c,
				confidenceScore__c,
				confidenceBand__c,
				candidateCount__c,
				manualReviewRequired__c,
				inboundStatus__c,
				sourceReceiptNumber__c
			FROM InboundInsurancePayment__c
			WHERE Id IN :inboundPaymentIds
		];

		if (payments.isEmpty()) {
			return;
		}

		Map<Id, PaymentReconciliation__c> existingByInbound = new Map<Id, PaymentReconciliation__c>();
		for (PaymentReconciliation__c existing : [
			SELECT Id, inboundPayment__c
			FROM PaymentReconciliation__c
			WHERE inboundPayment__c IN :inboundPaymentIds
		]) {
			existingByInbound.put(existing.inboundPayment__c, existing);
		}

		Set<Id> installmentIds = new Set<Id>();
		for (InboundInsurancePayment__c p : payments) {
			if (p.candidateInstallment__c != null) {
				installmentIds.add(p.candidateInstallment__c);
			}
		}

		Map<Id, PaymentPlanInstallment__c> installmentsById = new Map<Id, PaymentPlanInstallment__c>();
		if (!installmentIds.isEmpty()) {
			for (PaymentPlanInstallment__c inst : [
				SELECT Id, paymentPlan__c
				FROM PaymentPlanInstallment__c
				WHERE Id IN :installmentIds
			]) {
				installmentsById.put(inst.Id, inst);
			}
		}

		List<PaymentReconciliation__c> toInsert = new List<PaymentReconciliation__c>();
		List<PaymentReconciliation__c> toUpdate = new List<PaymentReconciliation__c>();
		List<PaymentReconciliation__c> reconciledNewRecs = new List<PaymentReconciliation__c>();
		Set<Id> reconciledReconciliationIds = new Set<Id>();

		for (InboundInsurancePayment__c p : payments) {
			try {
				if (forceFailureForTest) {
					throw new ReconciliationException('Forced failure for test');
				}
				PaymentPlanInstallment__c inst = p.candidateInstallment__c != null
					? installmentsById.get(p.candidateInstallment__c)
					: null;

				PaymentReconciliation__c existing = existingByInbound.get(p.Id);
				PaymentReconciliation__c rec = existing != null
					? new PaymentReconciliation__c(Id = existing.Id)
					: new PaymentReconciliation__c(inboundPayment__c = p.Id);
				populateReconciliation(rec, p, inst);

				Boolean reconciled = STATUS_RECONCILED.equals(p.inboundStatus__c);
				if (existing != null) {
					toUpdate.add(rec);
					if (reconciled) {
						reconciledReconciliationIds.add(existing.Id);
					}
				} else {
					toInsert.add(rec);
					if (reconciled) {
						reconciledNewRecs.add(rec);
					}
				}
			} catch (Exception e) {
			}
		}

		if (!toInsert.isEmpty()) {
			insert toInsert;
		}
		if (!toUpdate.isEmpty()) {
			update toUpdate;
		}

		for (PaymentReconciliation__c rec : reconciledNewRecs) {
			reconciledReconciliationIds.add(rec.Id);
		}

		if (!reconciledReconciliationIds.isEmpty()) {
			try {
				System.enqueueJob(
					new PolicyPaymentReceiptQueueable(reconciledReconciliationIds)
				);
			} catch (System.AsyncException e) {
			}
		}
	}

	/**
	 * @creation date: 08/06/2026
	 * @author: Javier Torres - Volestra
	 * @description: Popula los campos de una PaymentReconciliation__c a partir del
	 *               inbound evaluado y su cuota candidata. Se usa tanto para registros
	 *               nuevos (INSERT) como para la actualizacion de la conciliacion
	 *               existente cuando el inbound se reprocesa, garantizando que score,
	 *               estado y metodo reflejen siempre el ultimo resultado del pipeline.
	 *               No setea inboundPayment__c: es un master-detail no reparentable y
	 *               reescribirlo en el UPDATE haria fallar el DML; el vinculo se asigna
	 *               solo al insertar el registro nuevo.
	 * @param rec: Conciliacion a poblar (nueva, o existente con solo Id preestablecido).
	 * @param p: Registro inbound evaluado.
	 * @param inst: Cuota candidata cargada, o null.
	 * @return
	 */
	private static void populateReconciliation(
		PaymentReconciliation__c rec,
		InboundInsurancePayment__c p,
		PaymentPlanInstallment__c inst
	) {
		rec.insurancePolicy__c = p.candidatePolicy__c;
		rec.paymentPlanInstallment__c = p.candidateInstallment__c;
		rec.paymentPlan__c = inst != null ? inst.paymentPlan__c : null;
		rec.reconciliationStatus__c = deriveReconciliationStatus(p);
		rec.matchMethod__c = deriveMatchMethod(p.reconciliationMethod__c);
		rec.confidenceScore__c = p.confidenceScore__c;
		rec.candidateCount__c = p.candidateCount__c;
		rec.decisionNotes__c = buildDecisionNotes(p);
	}

	/**
	 * @creation date: 20/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Deriva reconciliationStatus__c a partir del inboundStatus__c y
	 *               reconciliationMethod__c. Conciliado -> Conciliado; Sin Match ->
	 *               Sin Match; metodo POLICY_AMOUNT (poliza + importe) -> Probable;
	 *               cualquier otro metodo en revision (POLICY_ONLY, AMBIGUOUS, ERROR)
	 *               -> Requiere revision. El estado Probable se reserva exclusivamente
	 *               para POLICY_AMOUNT: POLICY_ONLY, aunque produce Match Probable,
	 *               cae a Requiere revision por su menor confianza.
	 * @param payment: Registro inbound evaluado.
	 * @return Valor del picklist reconciliationStatus__c.
	 */
	private static String deriveReconciliationStatus(
		InboundInsurancePayment__c payment
	) {
		if (STATUS_RECONCILED.equals(payment.inboundStatus__c)) {
			return RECON_STATUS_RECONCILED;
		}
		if (INBOUND_STATUS_NO_MATCH.equals(payment.inboundStatus__c)) {
			return RECON_STATUS_NO_MATCH;
		}
		if (METHOD_POLICY_AMOUNT.equals(payment.reconciliationMethod__c)) {
			return RECON_STATUS_PROBABLE;
		}
		return RECON_STATUS_REVIEW;
	}

	/**
	 * @creation date: 20/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Mapea reconciliationMethod__c al picklist restringido matchMethod__c.
	 *               EXACT_POLICY_AND_SEQUENCE -> Cuota exacta;
	 *               POLICY_DATE_AMOUNT y POLICY_AMOUNT -> Poliza e importe;
	 *               POLICY_ONLY y AMBIGUOUS -> Asistido por candidato;
	 *               NO_MATCH y ERROR -> Decision manual.
	 * @param method: Valor de reconciliationMethod__c.
	 * @return Valor del picklist matchMethod__c.
	 */
	private static String deriveMatchMethod(String method) {
		if (METHOD_EXACT_POLICY_AND_SEQUENCE.equals(method)) {
			return MATCH_EXACT_INSTALLMENT;
		}
		if (
			METHOD_POLICY_DATE_AMOUNT.equals(method) ||
			METHOD_POLICY_AMOUNT.equals(method)
		) {
			return MATCH_POLICY_AMOUNT;
		}
		if (METHOD_POLICY_ONLY.equals(method) || METHOD_AMBIGUOUS.equals(method)) {
			return MATCH_ASSISTED;
		}
		return MATCH_MANUAL;
	}

	/**
	 * @creation date: 20/05/2026
	 * @author: Javier Torres - Volestra
	 * @description: Construye el texto de notas de decision que resume el resultado
	 *               del proceso de conciliacion para auditoria.
	 * @param payment: Registro inbound evaluado.
	 * @return Texto de notas de decision.
	 */
	private static String buildDecisionNotes(InboundInsurancePayment__c payment) {
		return 'Estado: ' +
			payment.inboundStatus__c +
			'. Metodo: ' +
			payment.reconciliationMethod__c +
			'. Resultado: ' +
			payment.reconciliationResult__c +
			'. Score: ' +
			payment.confidenceScore__c +
			'. Banda: ' +
			payment.confidenceBand__c +
			'.';
	}
}
