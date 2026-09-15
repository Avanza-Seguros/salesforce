/**
 *   @name: InboundRefundQueueable
 *   @version: 1.0
 *   @creation date: 15/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Procesa en segundo plano las devoluciones que deja la recepcion. Lo hace por
 *                 tandas: aplicar una devolucion anula recibos y reabre cuotas, y cada una
 *                 arrastra la cascada de plan y poliza, asi que muchas en una sola transaccion
 *                 agotarian los limites de la plataforma. Lo que no cabe en una tanda se
 *                 encola en la siguiente.
 */
public with sharing class InboundRefundQueueable implements Queueable {
	@TestVisible
	private static Integer maxPerJob = 10;

	private Set<Id> refundIds;

	/**
	 * @creation date: 15/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Inicializa el job con las devoluciones a procesar.
	 * @param refundIds: Pagos inbound con importe negativo en estado Devolucion.
	 * @return
	 */
	public InboundRefundQueueable(Set<Id> refundIds) {
		this.refundIds = refundIds == null ? new Set<Id>() : refundIds;
	}

	/**
	 * @creation date: 15/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Procesa una tanda y encola el resto.
	 * @param context: Contexto de ejecucion del Queueable.
	 * @return
	 */
	public void execute(QueueableContext context) {
		AppLogger.setJobContext(context == null ? null : context.getJobId());
		System.attachFinalizer(
			CobranzaLog.finalizerFor(CobranzaLog.STAGE_DEVOLUCION, refundIds)
		);

		Set<Id> batch = new Set<Id>();
		Set<Id> remaining = new Set<Id>();
		for (Id refundId : refundIds) {
			if (batch.size() < maxPerJob) {
				batch.add(refundId);
			} else {
				remaining.add(refundId);
			}
		}

		InboundRefundService.process(batch);

		if (!remaining.isEmpty()) {
			try {
				System.enqueueJob(new InboundRefundQueueable(remaining));
			} catch (System.AsyncException e) {
				CobranzaLog.chainBreak(
					CobranzaLog.STAGE_DEVOLUCION,
					e,
					'InboundRefundQueueable',
					remaining
				);
			}
		}
		AppLogger.flush();
	}
}
