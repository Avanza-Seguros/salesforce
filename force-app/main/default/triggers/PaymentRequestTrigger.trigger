/**
 * @creation date: 26/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Solicitudes de pago de un siniestro: póliza y folio consecutivo (ver Siniestros).
 */
trigger PaymentRequestTrigger on PaymentRequest (before insert) {
	Siniestros.antesDeCrearSolicitudes(Trigger.new);
}
