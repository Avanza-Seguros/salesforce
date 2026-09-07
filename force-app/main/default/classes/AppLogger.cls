/**
 *   @name: AppLogger
 *   @version: 1.0
 *   @creation date: 29/07/2026
 *   @author: Javier Torres - Volestra
 *   @description: Servicio de registro de aplicacion de alcance organizacional (H200).
 *                 Expone tres operaciones separadas -error, warn e info- y cada una fija
 *                 su severidad: no existe una operacion que permita elegirla libremente,
 *                 de modo que la severidad no puede quedar mal puesta desde el codigo.
 *                 Las entradas se acumulan en un buffer estatico y se escriben con un
 *                 unico DML por transaccion al invocar flush(), para que registrar dentro
 *                 de un bucle no consuma una operacion por evento.
 *                 La escritura es tolerante a fallos parciales y esta envuelta en try:
 *                 un fallo al registrar nunca interrumpe el proceso de negocio que lo invoco.
 *                 La clase y el metodo de origen se derivan del rastro de la excepcion y no
 *                 se pasan como texto, para que no queden desactualizados al refactorizar.
 *                 Convencion de idioma: codigos de evento en ingles y mayusculas
 *                 (RECEIPT_INSERT_FAILED), etapas y mensajes en espanol.
 */
public without sharing class AppLogger {
	// Dominios (picklist restringido domain__c).
	public static final String DOMAIN_COBRANZA = 'Cobranza';
	public static final String DOMAIN_INTEGRACIONES = 'Integraciones';
	public static final String DOMAIN_CORREOS = 'Correos';
	public static final String DOMAIN_COMISIONES = 'Comisiones';
	public static final String DOMAIN_OTRO = 'Otro';

	private static final String SEVERITY_ERROR = 'Error';
	private static final String SEVERITY_WARNING = 'Advertencia';
	private static final String SEVERITY_INFO = 'Informacion';

	private static final Integer MESSAGE_MAX_LENGTH = 255;
	private static final Integer STACK_TRACE_MAX_LENGTH = 32768;
	private static final Integer TEXT_MAX_LENGTH = 80;

	// Tope de entradas acumuladas antes de forzar un volcado intermedio. Acota el consumo
	// de memoria de un proceso que registre miles de eventos sin dejar de escribirlos.
	private static final Integer BUFFER_LIMIT = 500;

	private static List<AppLog__c> buffer = new List<AppLog__c>();
	private static Id currentJobId;

	@TestVisible
	private static Boolean forceFlushFailureForTest = false;

	private class AppLoggerException extends Exception {
	}

	/**
	 * @creation date: 29/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Registra un error a partir de una excepcion. El mensaje, el rastro,
	 *               la clase y el metodo de origen se toman de la propia excepcion.
	 * @param domain: Dominio funcional que origina el evento (constantes DOMAIN_*).
	 * @param stage: Etapa funcional del proceso, en lenguaje de negocio.
	 * @param eventCode: Codigo estable del evento para agrupar y reportar.
	 * @param e: Excepcion capturada.
	 * @return Entry para encadenar el registro afectado (onRecord/onInbound/onReconciliation).
	 */
	public static Entry error(
		String domain,
		String stage,
		String eventCode,
		Exception e
	) {
		String stackTrace = e == null ? null : e.getStackTraceString();
		Entry entry = buildEntry(
			SEVERITY_ERROR,
			domain,
			stage,
			eventCode,
			e == null ? null : e.getMessage(),
			stackTrace
		);
		applyOrigin(entry.record, stackTrace);
		return entry;
	}

	/**
	 * @creation date: 29/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Registra un error que no proviene de una excepcion. Es el caso de las
	 *               operaciones tolerantes a fallos parciales, donde la plataforma devuelve
	 *               el error como resultado y no lo lanza: sin esta variante habria que
	 *               fabricar una excepcion solo para poder registrarlo.
	 * @param domain: Dominio funcional que origina el evento.
	 * @param stage: Etapa funcional del proceso.
	 * @param eventCode: Codigo estable del evento.
	 * @param message: Mensaje legible con el error devuelto.
	 * @return Entry para encadenar el registro afectado.
	 */
	public static Entry error(
		String domain,
		String stage,
		String eventCode,
		String message
	) {
		Entry entry = buildEntry(
			SEVERITY_ERROR,
			domain,
			stage,
			eventCode,
			message,
			null
		);
		applyOrigin(entry.record, currentStackTrace());
		return entry;
	}

	/**
	 * @creation date: 29/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Registra una advertencia: una decision de negocio que el proceso tomo
	 *               y que no es evidente en los datos (p. ej. no cerrar una oportunidad).
	 * @param domain: Dominio funcional que origina el evento.
	 * @param stage: Etapa funcional del proceso.
	 * @param eventCode: Codigo estable del evento.
	 * @param message: Mensaje legible con el motivo.
	 * @return Entry para encadenar el registro afectado.
	 */
	public static Entry warn(
		String domain,
		String stage,
		String eventCode,
		String message
	) {
		Entry entry = buildEntry(
			SEVERITY_WARNING,
			domain,
			stage,
			eventCode,
			message,
			null
		);
		applyOrigin(entry.record, currentStackTrace());
		return entry;
	}

	/**
	 * @creation date: 29/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Registra un evento informativo. Se reserva para situaciones puntuales
	 *               que soporte necesita ver; el camino exitoso no se registra, porque ya
	 *               esta reflejado en los campos de estado de cada objeto de negocio.
	 * @param domain: Dominio funcional que origina el evento.
	 * @param stage: Etapa funcional del proceso.
	 * @param eventCode: Codigo estable del evento.
	 * @param message: Mensaje legible.
	 * @return Entry para encadenar el registro afectado.
	 */
	public static Entry info(
		String domain,
		String stage,
		String eventCode,
		String message
	) {
		Entry entry = buildEntry(
			SEVERITY_INFO,
			domain,
			stage,
			eventCode,
			message,
			null
		);
		applyOrigin(entry.record, currentStackTrace());
		return entry;
	}

	/**
	 * @creation date: 29/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Fija el identificador del proceso asincrono en curso para todas las
	 *               entradas de la transaccion. Cada eslabon del pipeline lo invoca al
	 *               arrancar con el id de su job.
	 * @param jobId: Identificador del job asincrono.
	 * @return
	 */
	public static void setJobContext(Id jobId) {
		currentJobId = jobId;
	}

	/**
	 * @creation date: 29/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Escribe con un unico DML todas las entradas acumuladas y vacia el
	 *               buffer. La insercion es tolerante a fallos parciales y esta envuelta
	 *               en try: un fallo al registrar nunca propaga al proceso llamador.
	 *               El buffer se vacia antes de intentar la insercion, de modo que un
	 *               fallo no deja entradas que se reintenten indefinidamente.
	 * @return
	 */
	public static void flush() {
		if (buffer.isEmpty()) {
			return;
		}
		List<AppLog__c> toInsert = buffer;
		buffer = new List<AppLog__c>();
		try {
			if (forceFlushFailureForTest) {
				throw new AppLoggerException('Forced flush failure for test');
			}
			Database.insert(toInsert, false);
		} catch (Exception e) {
			// Intencional: el registro de aplicacion es infraestructura de soporte y no
			// puede tumbar el proceso de negocio. Si falla, se pierde la traza, no el pago.
		}
	}

	/**
	 * @creation date: 29/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Cantidad de entradas acumuladas sin escribir. Solo para pruebas.
	 * @return Numero de entradas en el buffer.
	 */
	@TestVisible
	private static Integer pendingCount() {
		return buffer.size();
	}

	/**
	 * @creation date: 29/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Construye la entrada con el contexto comun (severidad, dominio, etapa,
	 *               codigo, mensaje, momento del evento, usuario, transaccion y job) y la
	 *               agrega al buffer. Si el buffer alcanza su tope, fuerza un volcado
	 *               intermedio para acotar la memoria sin perder entradas.
	 * @param severity: Severidad ya resuelta por la operacion publica.
	 * @param domain: Dominio funcional.
	 * @param stage: Etapa funcional.
	 * @param eventCode: Codigo del evento.
	 * @param message: Mensaje legible.
	 * @param stackTrace: Detalle tecnico, o null.
	 * @return Entry que envuelve el registro recien agregado.
	 */
	private static Entry buildEntry(
		String severity,
		String domain,
		String stage,
		String eventCode,
		String message,
		String stackTrace
	) {
		AppLog__c log = new AppLog__c(
			severity__c = severity,
			domain__c = domain,
			stage__c = truncate(stage, TEXT_MAX_LENGTH),
			eventCode__c = truncate(eventCode, TEXT_MAX_LENGTH),
			message__c = truncate(message, MESSAGE_MAX_LENGTH),
			stackTrace__c = truncate(stackTrace, STACK_TRACE_MAX_LENGTH),
			occurredAt__c = System.now(),
			runningUser__c = UserInfo.getUserId(),
			transactionId__c = Request.getCurrent().getRequestId(),
			jobId__c = currentJobId
		);

		if (buffer.size() >= BUFFER_LIMIT) {
			flush();
		}
		buffer.add(log);
		return new Entry(log);
	}

	/**
	 * @creation date: 29/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Obtiene el rastro del punto de llamada actual construyendo una
	 *               excepcion que no se lanza. Se usa en warn e info, donde no hay una
	 *               excepcion de la que derivar el origen.
	 * @return Rastro de ejecucion del punto de llamada.
	 */
	private static String currentStackTrace() {
		return new AppLoggerException().getStackTraceString();
	}

	/**
	 * @creation date: 29/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Deriva la clase y el metodo de origen del primer marco del rastro que
	 *               no pertenezca a esta clase, de modo que el registro apunte al codigo
	 *               que lo invoco y no al servicio. Si el rastro no puede interpretarse,
	 *               los campos quedan vacios sin afectar al registro.
	 * @param log: Registro a completar.
	 * @param stackTrace: Rastro de ejecucion.
	 * @return
	 */
	@TestVisible
	private static void applyOrigin(AppLog__c log, String stackTrace) {
		if (String.isBlank(stackTrace)) {
			return;
		}
		for (String line : stackTrace.split('\n')) {
			String frame = line.trim();
			if (!frame.startsWith('Class.')) {
				continue;
			}
			// "Class.Outer.Inner.metodo: line 12, column 1" -> "Outer.Inner.metodo"
			String signature = frame.substringAfter('Class.').substringBefore(':');
			if (signature.startsWith('AppLogger.')) {
				continue;
			}
			Integer lastDot = signature.lastIndexOf('.');
			if (lastDot <= 0) {
				continue;
			}
			log.className__c = truncate(
				signature.substring(0, lastDot),
				TEXT_MAX_LENGTH
			);
			log.methodName__c = truncate(
				signature.substring(lastDot + 1),
				TEXT_MAX_LENGTH
			);
			return;
		}
	}

	/**
	 * @creation date: 29/07/2026
	 * @author: Javier Torres - Volestra
	 * @description: Recorta un texto a la longitud del campo destino. Un mensaje largo
	 *               nunca debe impedir que el registro se guarde.
	 * @param value: Texto a recortar.
	 * @param maxLength: Longitud maxima admitida.
	 * @return Texto recortado, o el original si ya cabe.
	 */
	private static String truncate(String value, Integer maxLength) {
		if (String.isBlank(value) || value.length() <= maxLength) {
			return value;
		}
		return value.substring(0, maxLength);
	}

	/**
	 *   @name: AppLogger.Entry
	 *   @description: Envuelve la entrada recien acumulada para encadenar a que registro
	 *                 de negocio se refiere. Permite que el punto de llamada se lea como
	 *                 una frase y evita multiplicar sobrecargas del metodo publico.
	 */
	public class Entry {
		private AppLog__c record;

		private Entry(AppLog__c record) {
			this.record = record;
		}

		/**
		 * @description: Asocia el registro afectado de forma generica, resolviendo tambien
		 *               a que objeto pertenece.
		 * @param recordId: Identificador del registro afectado.
		 * @return La misma Entry, para encadenar.
		 */
		public Entry onRecord(Id recordId) {
			if (recordId == null) {
				return this;
			}
			this.record.recordId__c = String.valueOf(recordId);
			this.record.recordObject__c = truncate(
				String.valueOf(recordId.getSObjectType()),
				TEXT_MAX_LENGTH
			);
			return this;
		}

		/**
		 * @description: Asocia el pago inbound afectado. Ademas del lookup -que habilita la
		 *               lista relacionada en el registro de negocio- completa el registro
		 *               afectado generico si aun no se indico otro.
		 * @param inboundPaymentId: Identificador del pago inbound.
		 * @return La misma Entry, para encadenar.
		 */
		public Entry onInbound(Id inboundPaymentId) {
			if (inboundPaymentId == null) {
				return this;
			}
			this.record.inboundPayment__c = inboundPaymentId;
			if (String.isBlank(this.record.recordId__c)) {
				onRecord(inboundPaymentId);
			}
			return this;
		}

		/**
		 * @description: Asocia la conciliacion de pagos afectada, con el mismo criterio que
		 *               onInbound.
		 * @param reconciliationId: Identificador de la conciliacion.
		 * @return La misma Entry, para encadenar.
		 */
		public Entry onReconciliation(Id reconciliationId) {
			if (reconciliationId == null) {
				return this;
			}
			this.record.paymentReconciliation__c = reconciliationId;
			if (String.isBlank(this.record.recordId__c)) {
				onRecord(reconciliationId);
			}
			return this;
		}

		/**
		 * @description: Agrega detalle tecnico a una advertencia o a un evento informativo,
		 *               que no traen excepcion de la cual derivarlo.
		 * @param details: Texto con el detalle.
		 * @return La misma Entry, para encadenar.
		 */
		public Entry withDetails(String details) {
			this.record.stackTrace__c = truncate(details, STACK_TRACE_MAX_LENGTH);
			return this;
		}

		/**
		 * @description: Agrega contexto al detalle tecnico sin pisar lo que ya tenga. Se usa
		 *               cuando hace falta sumar informacion -por ejemplo que registros se
		 *               estaban procesando- conservando el rastro de la excepcion.
		 * @param details: Texto a agregar.
		 * @return La misma Entry, para encadenar.
		 */
		public Entry appendDetails(String details) {
			if (String.isBlank(details)) {
				return this;
			}
			String combined = String.isBlank(this.record.stackTrace__c)
				? details
				: this.record.stackTrace__c + '\n\n' + details;
			this.record.stackTrace__c = truncate(combined, STACK_TRACE_MAX_LENGTH);
			return this;
		}
	}
}
