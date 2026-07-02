/**
 *   @name: QueueEnvioEmails
 *   @version: 1.0
 *   @creation date: 02/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Job Queueable que procesa por lotes el envío de correos para registros Items_Cases__c concluidos, respetando límites de gobernador mediante encadenamiento de Queueables y marcando masivamente los items enviados o fallidos.
 */
public class QueueEnvioEmails implements Queueable {
	private Set<Id> itemIds;
	private String tipoEmail; // 'ALTA' o 'BAJA'

	// =========================================================================
	// 📦 LOTE MÁXIMO POR EJECUCIÓN
	// -------------------------------------------------------------------------
	// Cada ejecución de Apex en Salesforce tiene un tope de 150 operaciones DML.
	// El Flow "Procesamiento de polizas" se dispara con cada actualización de
	// Items_Cases__c y consume DML adicional, por lo que mantenemos lotes
	// pequeños para garantizar margen suficiente. Si llegan más items que el
	// tope, se encadena automáticamente un nuevo Queueable con los restantes.
	// =========================================================================
	private static final Integer LOTE_MAXIMO = 25;

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Construye el Queueable con el conjunto de items a procesar y el tipo de correo a enviar.
	 * @param itemIds: Conjunto de Ids de Items_Cases__c a procesar.
	 * @param tipoEmail: Tipo de correo a enviar ('ALTA' o 'BAJA').
	 * @return void
	 */
	public QueueEnvioEmails(Set<Id> itemIds, String tipoEmail) {
		System.debug('=== QUEUEENVIOEMAILS CREADO ===');
		this.itemIds = itemIds;
		this.tipoEmail = tipoEmail;
		System.debug('📨 QueueEnvioEmails creado para ' + itemIds.size() + ' items de tipo: ' + tipoEmail);
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Ejecuta el job: divide en lote actual y pendientes, consulta los items desde BD, filtra los que califican para envío, construye y envía los correos, marca masivamente los enviados/fallidos y encadena el siguiente lote si es necesario.
	 * @param context: Contexto de ejecución del Queueable provisto por la plataforma.
	 * @return void
	 */
	public void execute(QueueableContext context) {
		System.debug('=== QUEUEENVIOEMAILS EJECUTANDO ===');
		System.debug('Tipo: ' + tipoEmail);
		System.debug('Items recibidos: ' + itemIds.size());

		// Verificar contexto de envío
		if (!EmailContextControl.canBatchSend()) {
			System.debug('🚫 Envío desactivado por contexto');
			return;
		}

		if (itemIds == null || itemIds.isEmpty()) {
			System.debug('⚠️ No hay items para procesar');
			return;
		}

		// =====================================================================
		// 📦 DIVIDIR EN LOTE ACTUAL + PENDIENTES
		// Si vienen más items de los que un job puede procesar con seguridad,
		// tomamos solo LOTE_MAXIMO en esta ejecución y encolamos el resto.
		// Cada Queueable encadenado arranca con un presupuesto fresco de DML.
		// =====================================================================
		Set<Id> itemsPendientes = new Set<Id>();
		if (itemIds.size() > LOTE_MAXIMO) {
			Set<Id> loteActual = new Set<Id>();
			Integer i = 0;
			for (Id id : itemIds) {
				if (i < LOTE_MAXIMO) {
					loteActual.add(id);
				} else {
					itemsPendientes.add(id);
				}
				i++;
			}
			System.debug('📦 Procesando lote de ' + loteActual.size() +
			             ' items. Pendientes para siguiente ejecución: ' + itemsPendientes.size());
			this.itemIds = loteActual;
		}

		// Obtener items actualizados desde BD
		List<Items_Cases__c> items = [
			SELECT Id, Estatus__c, Correo_electronico__c, Correo_Copia__c,
			       Nombre_cuenta__c, RecordTypeId, Contacto__c, Tipo_de_peticion__c,
			       Baja_Por_Defuncion__c, Categorias__c, Asegurado__c
			FROM Items_Cases__c
			WHERE Id IN :itemIds
		];

		System.debug('Items en BD: ' + items.size());

		// Filtrar solo los que pueden recibir email
		List<Items_Cases__c> itemsParaEmail = new List<Items_Cases__c>();
		for (Items_Cases__c item : items) {
			System.debug('🔍 Evaluando item ' + item.Id + ' con Estatus: ' + item.Estatus__c);
			if (item.Estatus__c == 'Concluido' && EmailProcessingControl.canSendEmail(item.Id, 'QUEUEABLE')) {
				System.debug('✅ Item ' + item.Id + ' califica para email');
				itemsParaEmail.add(item);
			} else {
				System.debug('⚠️ Item ' + item.Id + ' no califica (Estatus: ' + item.Estatus__c + ')');
			}
		}

		if (itemsParaEmail.isEmpty()) {
			System.debug('⚠️ No hay items válidos para enviar email');
			// Aunque este lote no tenga nada que enviar, encolamos los pendientes
			encolarSiguienteLote(itemsPendientes);
			return;
		}

		System.debug('Items válidos para email: ' + itemsParaEmail.size());

		try {
			// Construir y enviar emails
			Set<String> templateIds = EmailTemplateResolver.getRequiredTemplateIds(itemsParaEmail);
			System.debug('Templates requeridos: ' + templateIds);

			Map<String, EmailTemplate> templates = EnvioPlantillas.getTemplatesById(templateIds);
			System.debug('Templates obtenidos: ' + templates.keySet());

			List<Messaging.SingleEmailMessage> emails = EnvioPlantillas.construirEmails(itemsParaEmail, templates);
			System.debug('Emails construidos: ' + emails.size());

			if (!emails.isEmpty() && EmailContextControl.canBatchSend()) {
				System.debug('🚀 Enviando ' + emails.size() + ' emails...');
				EnvioPlantillas.enviarEmails(emails);
				System.debug('✅ ' + emails.size() + ' emails enviados');

				// =====================================================
				// 🔑 CAMBIO CLAVE: marcado MASIVO en una sola operación
				// -----------------------------------------------------
				// Antes: por cada item se llamaba markAsSent(), y cada
				// llamada consumía 2 DML (campo Email_Enviado__c +
				// campo Estado_Envio_Email__c). 40 items = 80 DML.
				//
				// Ahora: se acumulan los Ids y se actualiza todo de
				// una sola vez con markAsSentBulk(), que consume 1 DML
				// total sin importar la cantidad de items.
				// =====================================================
				Set<Id> idsEnviados = new Set<Id>();
				for (Items_Cases__c item : itemsParaEmail) {
					idsEnviados.add(item.Id);
				}
				EmailProcessingControl.markAsSentBulk(idsEnviados);
			} else {
				System.debug('⚠️ No se enviaron emails');
			}

		} catch (Exception e) {
			System.debug('❌ Error: ' + e.getMessage());
			System.debug('Stack: ' + e.getStackTraceString());

			// Marcado masivo de fallidos (1 DML total para todos)
			Set<Id> idsFallidos = new Set<Id>();
			for (Items_Cases__c item : itemsParaEmail) {
				idsFallidos.add(item.Id);
			}
			EmailProcessingControl.markAsFailedBulk(idsFallidos);
		}

		// Encadenar el siguiente lote si quedaron pendientes
		encolarSiguienteLote(itemsPendientes);
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Encola un nuevo Queueable con los items que no cupieron en este lote. Cada ejecución encadenada arranca con su propio presupuesto de governor limits (150 DML, 200 SOQL, etc.). No encadena en contexto de test.
	 * @param pendientes: Conjunto de Ids de items pendientes de procesar en la siguiente ejecución.
	 * @return void
	 */
	private void encolarSiguienteLote(Set<Id> pendientes) {
		if (pendientes == null || pendientes.isEmpty()) return;

		// En contexto de test no se pueden encadenar Queueables
		if (Test.isRunningTest()) {
			System.debug('🧪 Test mode: no se encadena el siguiente lote');
			return;
		}

		try {
			System.enqueueJob(new QueueEnvioEmails(pendientes, tipoEmail));
			System.debug('🔗 Encadenado siguiente lote con ' + pendientes.size() + ' items');
		} catch (Exception e) {
			// Salesforce limita la profundidad de encadenamiento; si no se
			// puede encolar, dejamos rastro para reintento manual.
			System.debug('⚠️ No se pudo encadenar siguiente lote: ' + e.getMessage());
		}
	}
}
