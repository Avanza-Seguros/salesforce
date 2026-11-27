/**
 * @creation date: 26/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Solicitudes de pago de un siniestro: póliza y folio consecutivo al crearse; aviso de reembolso al
 *               pagarse (ver Siniestros).
 */
trigger PaymentRequestTrigger on PaymentRequest (before insert, after update) {
	if (Trigger.isBefore) {
		Siniestros.antesDeCrearSolicitudes(Trigger.new);
	} else {
		Siniestros.despuesDeActualizarSolicitudes(Trigger.new, Trigger.oldMap);
	}
}
