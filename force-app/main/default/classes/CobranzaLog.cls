/**
 *   @name: CobranzaLog
 *   @version: 1.0
 *   @creation date: 29/07/2026
 *   @author: Javier Torres - Volestra
 *   @description: Catalogo de etapas y codigos de evento del modulo de cobranza para el
 *                 registro de aplicacion (H200).
 *                 El objeto AppLog__c mantiene etapa y codigo como texto libre a proposito:
 *                 un catalogo restringido a nivel de organizacion obligaria a mantener un
 *                 valor por cada etapa de cada dominio. Cada modulo define los suyos aqui,
 *                 de modo que los textos no queden dispersos por el codigo y un cambio de
 *                 nombre se haga en un solo lugar.
 *                 Las ETAPAS son ademas los valores del picklist pipelineStage__c del pago
 *                 inbound: deben coincidir exactamente con ese catalogo.
 *                 Convencion: etapas en espanol -las lee soporte-; codigos de evento en
 *                 ingles y mayusculas -se usan para agrupar y reportar-.
 */
public with sharing class CobranzaLog {
	// --- Etapas del pipeline (espejo del picklist pipelineStage__c) ---
	public static final String STAGE_RECEPCION = 'Recepcion';
	public static final String STAGE_NORMALIZACION = 'Normalizacion';
	public static final String STAGE_POLIZA_CANDIDATA = 'Poliza candidata';
	public static final String STAGE_CUOTA_CANDIDATA = 'Cuota candidata';
	public static final String STAGE_REGLAS = 'Reglas de conciliacion';
	public static final String STAGE_SCORE = 'Score de confianza';
	public static final String STAGE_CONCILIACION = 'Conciliacion';
	public static final String STAGE_RECIBO = 'Recibo generado';
	public static final String STAGE_CUOTA = 'Cuota actualizada';
	public static final String STAGE_OPORTUNIDAD = 'Oportunidad';

	// Etapa de operacion, NO del pipeline: la reversa no es un paso del motor sino una accion
	// posterior sobre un cobro ya procesado. Por eso no figura en el picklist pipelineStage__c.
	public static final String STAGE_REVERSA = 'Reversa';

	// --- Codigos de evento: fallos al procesar un pago individual ---
	// Fallo al normalizar los datos del pago. El pago queda Rechazado.
	public static final String EVENT_NORMALIZATION_FAILED = 'NORMALIZATION_FAILED';
	// Fallo al resolver la poliza candidata del pago.
	public static final String EVENT_POLICY_MATCH_FAILED = 'POLICY_MATCH_FAILED';
	// Fallo al resolver la cuota candidata del pago.
	public static final String EVENT_INSTALLMENT_CANDIDATE_FAILED = 'INSTALLMENT_CANDIDATE_FAILED';
	// Fallo al aplicar las reglas de conciliacion sobre el pago.
	public static final String EVENT_RULES_EVALUATION_FAILED = 'RULES_EVALUATION_FAILED';
	// Fallo al calcular el score de confianza del pago.
	public static final String EVENT_SCORE_FAILED = 'SCORE_FAILED';
	// Fallo al crear o actualizar la conciliacion de un pago.
	public static final String EVENT_RECONCILIATION_BUILD_FAILED = 'RECONCILIATION_BUILD_FAILED';
	// Fallo al construir el recibo limpio de una conciliacion.
	public static final String EVENT_RECEIPT_BUILD_FAILED = 'RECEIPT_BUILD_FAILED';
	// Fallo al iniciar el eslabon siguiente. Es el de mayor impacto: el recibo queda creado
	// pero la cuota nunca se actualiza y el plan nunca se completa, sin error visible.
	public static final String EVENT_CHAIN_ENQUEUE_FAILED = 'CHAIN_ENQUEUE_FAILED';
	// Fallo al aplicar un recibo sobre su cuota.
	public static final String EVENT_INSTALLMENT_MATCH_FAILED = 'INSTALLMENT_MATCH_FAILED';
	// Fallo tecnico al actualizar la oportunidad comercial.
	public static final String EVENT_OPPORTUNITY_UPDATE_FAILED = 'OPPORTUNITY_UPDATE_FAILED';
	// Fallo al sellar la etapa alcanzada en el pago. Degrada la visibilidad del pipeline,
	// no el resultado del pago.
	public static final String EVENT_STAGE_STAMP_FAILED = 'STAGE_STAMP_FAILED';
	// Fallo al devolver la conciliacion a la bandeja tras reversar el recibo. Es grave: el
	// caso queda perdido, ni conciliado de verdad ni visible para el analista.
	public static final String EVENT_REVERSAL_RECONCILIATION_FAILED = 'REVERSAL_RECONCILIATION_FAILED';
	// Fallo al devolver el pago inbound al circuito de revision tras la reversa.
	public static final String EVENT_REVERSAL_INBOUND_FAILED = 'REVERSAL_INBOUND_FAILED';
	// Fallo al reabrir la cuota tras reversar su recibo. Es el mas grave de la cascada: la
	// cuota queda figurando como pagada sobre un cobro que ya no existe.
	public static final String EVENT_REVERSAL_INSTALLMENT_FAILED = 'REVERSAL_INSTALLMENT_FAILED';
	// La poliza quedo sin cobros validos pero no tiene oportunidad de origen que señalar.
	public static final String EVENT_REVERSAL_OPPORTUNITY_MISSING = 'REVERSAL_OPPORTUNITY_MISSING';
	// Fallo al señalar o al retirar la señal en la oportunidad comercial.
	public static final String EVENT_REVERSAL_OPPORTUNITY_FAILED = 'REVERSAL_OPPORTUNITY_FAILED';

	// --- Codigos de evento: decisiones no evidentes en los datos ---
	// La poliza del recibo no tiene oportunidad de origen.
	public static final String EVENT_OPPORTUNITY_MISSING = 'OPPORTUNITY_NOT_CLOSED_MISSING';
	// La oportunidad esta en Closed Lost y no se reabre por un cobro.
	public static final String EVENT_OPPORTUNITY_LOST = 'OPPORTUNITY_NOT_CLOSED_LOST';
	// La integracion reenvio un pago ya conciliado con datos distintos a los conciliados.
	public static final String EVENT_INBOUND_RESENT_CHANGED = 'INBOUND_RESENT_WITH_CHANGES';
	// La aseguradora envio un numero de cuota no numerico: el matcher pierde su senal de
	// mayor peso (+6 puntos por secuencia exacta) y el pago tiene mas chance de caer a
	// revision manual. Es calidad de dato de origen, no un fallo del motor.
	public static final String EVENT_INSTALLMENT_NUMBER_NOT_NUMERIC = 'INSTALLMENT_NUMBER_NOT_NUMERIC';

	/**
	 * @creation date: 29/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Registra un error del modulo de cobranza. Atajo sobre AppLogger que fija
	 *               el dominio, para que los puntos de llamada del pipeline no lo repitan.
	 * @param stage: Etapa funcional (constantes STAGE_*).
	 * @param eventCode: Codigo del evento (constantes EVENT_*).
	 * @param e: Excepcion capturada.
	 * @return Entry para encadenar el registro afectado.
	 */
	public static AppLogger.Entry error(
		String stage,
		String eventCode,
		Exception e
	) {
		return AppLogger.error(AppLogger.DOMAIN_COBRANZA, stage, eventCode, e);
	}

	/**
	 * @creation date: 29/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Registra un error del modulo que no proviene de una excepcion, como el
	 *               que devuelve una operacion tolerante a fallos parciales.
	 * @param stage: Etapa funcional.
	 * @param eventCode: Codigo del evento.
	 * @param message: Mensaje legible con el error devuelto.
	 * @return Entry para encadenar el registro afectado.
	 */
	public static AppLogger.Entry error(
		String stage,
		String eventCode,
		String message
	) {
		return AppLogger.error(
			AppLogger.DOMAIN_COBRANZA,
			stage,
			eventCode,
			message
		);
	}

	/**
	 * @creation date: 29/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Registra una advertencia del modulo de cobranza.
	 * @param stage: Etapa funcional.
	 * @param eventCode: Codigo del evento.
	 * @param message: Mensaje legible con el motivo.
	 * @return Entry para encadenar el registro afectado.
	 */
	public static AppLogger.Entry warn(
		String stage,
		String eventCode,
		String message
	) {
		return AppLogger.warn(AppLogger.DOMAIN_COBRANZA, stage, eventCode, message);
	}

	/**
	 * @creation date: 29/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Registra un evento informativo del modulo de cobranza.
	 * @param stage: Etapa funcional.
	 * @param eventCode: Codigo del evento.
	 * @param message: Mensaje legible.
	 * @return Entry para encadenar el registro afectado.
	 */
	public static AppLogger.Entry info(
		String stage,
		String eventCode,
		String message
	) {
		return AppLogger.info(AppLogger.DOMAIN_COBRANZA, stage, eventCode, message);
	}

	/**
	 * @creation date: 29/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Registra que el eslabon siguiente del pipeline no llego a iniciarse.
	 *               Es el fallo mas dificil de detectar sin traza: el eslabon actual termina
	 *               correctamente y los pagos quedan detenidos sin ninguna senal de error.
	 *               Vive aca y no en cada eslabon porque los siete puntos de encadenamiento
	 *               registran exactamente lo mismo.
	 * @param stage: Etapa donde quedaron detenidos los pagos.
	 * @param e: Excepcion devuelta al intentar encolar.
	 * @param nextStep: Nombre del eslabon que no se ejecuto.
	 * @param pendingIds: Registros que quedaron sin continuar.
	 * @return
	 */
	public static void chainBreak(
		String stage,
		Exception e,
		String nextStep,
		Set<Id> pendingIds
	) {
		List<Id> ids = pendingIds == null
			? new List<Id>()
			: new List<Id>(pendingIds);
		AppLogger.Entry entry = error(stage, EVENT_CHAIN_ENQUEUE_FAILED, e)
			.appendDetails(
				'No llegó a iniciarse: ' +
					nextStep +
					'. Registros sin continuar (' +
					ids.size() +
					'): ' +
					String.join(ids, ', ')
			);
		if (!ids.isEmpty()) {
			entry.onRecord(ids[0]);
		}
	}

	/**
	 * @creation date: 29/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Sella la etapa alcanzada en los pagos indicados. Los cinco primeros
	 *               eslabones ya actualizan el pago y escriben la etapa en ese mismo DML;
	 *               del sexto en adelante el pipeline trabaja sobre conciliacion, recibo y
	 *               cuota, por lo que la etapa necesita su propia actualizacion. Es un unico
	 *               DML por eslabon, independiente de la cantidad de pagos.
	 *               Vive junto al catalogo de etapas para que agregar un eslabon signifique
	 *               tocar un solo archivo.
	 *               Si el sellado falla, se registra y se sigue: perder la etapa degrada la
	 *               visibilidad, no el resultado del pago.
	 * @param inboundPaymentIds: Pagos que completaron la etapa.
	 * @param stage: Etapa alcanzada (constantes STAGE_*).
	 * @return
	 */
	public static void markStage(Set<Id> inboundPaymentIds, String stage) {
		if (inboundPaymentIds == null || inboundPaymentIds.isEmpty()) {
			return;
		}
		List<InboundInsurancePayment__c> toStamp = new List<InboundInsurancePayment__c>();
		for (Id inboundId : inboundPaymentIds) {
			toStamp.add(
				new InboundInsurancePayment__c(Id = inboundId, pipelineStage__c = stage)
			);
		}
		try {
			update toStamp;
		} catch (Exception e) {
			error(stage, EVENT_STAGE_STAMP_FAILED, e);
		}
	}

	/**
	 * @creation date: 29/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Construye el finalizador del modulo para un eslabon del pipeline.
	 * @param stage: Etapa funcional del eslabon.
	 * @param recordIds: Registros que el eslabon esta procesando.
	 * @return Finalizador listo para adjuntar con System.attachFinalizer.
	 */
	public static AppLogFinalizer finalizerFor(String stage, Set<Id> recordIds) {
		return new AppLogFinalizer(AppLogger.DOMAIN_COBRANZA, stage, recordIds);
	}
}
