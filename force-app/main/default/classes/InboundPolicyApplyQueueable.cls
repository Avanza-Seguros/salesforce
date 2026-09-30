/**
 *   @name: InboundPolicyApplyQueueable
 *   @version: 1.0
 *   @creation date: 25/09/2026
 *   @author: Javier Torres - Volestra
 *   @description: Aplica en segundo plano las comunicaciones de poliza recien recibidas
 *                 (KAN-449), para que la respuesta a MuleSoft no espere a que se actualicen
 *                 las polizas y sus planes.
 */
public with sharing class InboundPolicyApplyQueueable implements Queueable {
	private Set<Id> updateIds;

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Crea el job con las comunicaciones a aplicar.
	 * @param updateIds: Comunicaciones de poliza en estado Recibido.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	public InboundPolicyApplyQueueable(Set<Id> updateIds) {
		this.updateIds = updateIds;
	}

	/**
	 * @creation date: 25/09/2026
	 * @author: Javier Torres - Volestra
	 * @description: Punto de entrada del job.
	 * @param context: Contexto de ejecucion.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	public void execute(QueueableContext context) {
		AppLogger.setJobContext(context == null ? null : context.getJobId());
		InboundPolicyApplyService.apply(updateIds);
	}
}
