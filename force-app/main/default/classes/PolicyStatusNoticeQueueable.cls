/**
 *   @name: PolicyStatusNoticeQueueable
 *   @version: 1.0
 *   @creation date: 16/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Procesa fuera de la recepcion las comunicaciones de estado de poliza y los
 *                 recibos que informan el estado de su poliza: la recepcion solo los guarda y
 *                 responde, como con cualquier pago.
 */
public with sharing class PolicyStatusNoticeQueueable implements Queueable {
	private Set<Id> inboundIds;

	/**
	 * @creation date: 16/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Inicializa el trabajo con los registros a procesar.
	 * @param inboundIds: Comunicaciones y recibos con estado de poliza.
	 * @return
	 */
	public PolicyStatusNoticeQueueable(Set<Id> inboundIds) {
		this.inboundIds = inboundIds;
	}

	/**
	 * @creation date: 16/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Guarda en cada poliza el estado comunicado por la aseguradora.
	 * @param context: Contexto del trabajo.
	 * @return
	 */
	public void execute(QueueableContext context) {
		AppLogger.setJobContext(context == null ? null : context.getJobId());
		System.attachFinalizer(
			CobranzaLog.finalizerFor(CobranzaLog.STAGE_ESTADO_POLIZA, inboundIds)
		);
		PolicyCarrierStatusService.process(inboundIds);
		AppLogger.flush();
	}
}
