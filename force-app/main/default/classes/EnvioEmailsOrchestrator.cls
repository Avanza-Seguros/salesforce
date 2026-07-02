/**
 *   @name: EnvioEmailsOrchestrator
 *   @version: 1.0
 *   @creation date: 02/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Clase de diagnostico y reporteria del sistema de envio de emails sobre Items_Cases__c. Provee metodos para verificar el estado de los items por estatus, contar items con/sin correo y pendientes de envio, inspeccionar el campo Email_Enviado__c, revisar jobs asincronos recientes y generar un reporte de texto del sistema.
 */
public class EnvioEmailsOrchestrator {

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Verifica el estado del sistema agrupando Items_Cases__c por Estatus__c y mostrando totales y conteo con correo, y luego dispara la verificacion detallada.
	 * @return void
	 */
	public static void verificarEstado() {
		System.debug('=== VERIFICACIÓN DEL SISTEMA ===');

		// Contar items en cada estado - FORMA CORRECTA EN SOQL
		List<AggregateResult> resultados = [SELECT
			Estatus__c,
			COUNT(Id) total,
			COUNT(Correo_electronico__c) conCorreo
			FROM Items_Cases__c
			GROUP BY Estatus__c];

		for (AggregateResult ar : resultados) {
			System.debug('Estatus: ' + ar.get('Estatus__c'));
			System.debug('  Total: ' + ar.get('total'));
			System.debug('  Con correo: ' + ar.get('conCorreo'));
		}

		// Mejor forma: Consultas separadas para mayor precisión
		verificarEstadoDetallado();
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Verificacion detallada del estado del sistema: items por estatus, conteo con/sin correo, concluidos pendientes de email, concluidos ya procesados, desglose por RecordType de los pendientes y ultimos items procesados. Todo se registra en debug.
	 * @return void
	 */
	public static void verificarEstadoDetallado() {
		System.debug('=== VERIFICACIÓN DETALLADA ===');

		// 1. Total items por estado
		List<AggregateResult> porEstatus = [SELECT
			Estatus__c, COUNT(Id) total
			FROM Items_Cases__c
			GROUP BY Estatus__c
			ORDER BY Estatus__c];

		System.debug('📊 ITEMS POR ESTATUS:');
		for (AggregateResult ar : porEstatus) {
			System.debug('  ' + ar.get('Estatus__c') + ': ' + ar.get('total'));
		}

		// 2. Items con correo vs sin correo
		Integer conCorreo = [SELECT COUNT() FROM Items_Cases__c
							WHERE Correo_electronico__c != null];
		Integer sinCorreo = [SELECT COUNT() FROM Items_Cases__c
							WHERE Correo_electronico__c = null];

		System.debug('📧 CORREOS:');
		System.debug('  Con correo: ' + conCorreo);
		System.debug('  Sin correo: ' + sinCorreo);

		// 3. Items Concluidos que necesitan email (Email_Enviado__c = false/null)
		Integer concluidosPendientes = [SELECT COUNT() FROM Items_Cases__c
									   WHERE Estatus__c = 'Concluido'
									   AND (Email_Enviado__c = false OR Email_Enviado__c = null)
									   AND Correo_electronico__c != null];

		System.debug('📨 PENDIENTES DE EMAIL:');
		System.debug('  Concluidos pendientes de email: ' + concluidosPendientes);

		// 4. Items Concluidos ya procesados
		Integer concluidosProcesados = [SELECT COUNT() FROM Items_Cases__c
									   WHERE Estatus__c = 'Concluido'
									   AND Email_Enviado__c = true];

		System.debug('✅ PROCESADOS:');
		System.debug('  Concluidos con email enviado: ' + concluidosProcesados);

		// 5. Desglose por RecordType para Concluidos pendientes
		List<AggregateResult> porRecordType = [SELECT
			RecordType.Name tipo, COUNT(Id) cantidad
			FROM Items_Cases__c
			WHERE Estatus__c = 'Concluido'
			AND (Email_Enviado__c = false OR Email_Enviado__c = null)
			AND Correo_electronico__c != null
			GROUP BY RecordType.Name
			ORDER BY COUNT(Id) DESC];

		System.debug('🏷️ PENDIENTES POR RECORD TYPE:');
		for (AggregateResult ar : porRecordType) {
			System.debug('  ' + ar.get('tipo') + ': ' + ar.get('cantidad'));
		}

		// 6. Últimos items procesados
		List<Items_Cases__c> ultimosProcesados = [SELECT
			Id, Name, Estatus__c, Email_Enviado__c,
			 RecordType.Name
			FROM Items_Cases__c
			WHERE Email_Enviado__c = true
			LIMIT 5];

		System.debug('⏰ ÚLTIMOS PROCESADOS:');
		for (Items_Cases__c item : ultimosProcesados) {
			System.debug(item.Name + item.RecordType.Name);
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Metodo alternativo para contar los Items_Cases__c segun el valor del campo checkbox Email_Enviado__c (true, false y null) usando consultas AggregateResult separadas, registrando los conteos en debug.
	 * @return void
	 */
	public static void verificarCheckboxEnviado() {
		// Para campos checkbox, necesitamos contarlos de manera diferente
		System.debug('=== VERIFICACIÓN CAMPO CHECKBOX ===');

		// Opción 1: Si Email_Enviado__c es checkbox
		Integer enviadosTrue = 0;
		Integer enviadosFalse = 0;
		Integer enviadosNull = 0;

		// Usar AggregateResult con WHERE clauses separadas
		try {
			// Contar true
			AggregateResult arTrue = [SELECT COUNT(Id) total
									 FROM Items_Cases__c
									 WHERE Email_Enviado__c = true];
			enviadosTrue = (Integer)arTrue.get('total');

			// Contar false
			AggregateResult arFalse = [SELECT COUNT(Id) total
									  FROM Items_Cases__c
									  WHERE Email_Enviado__c = false];
			enviadosFalse = (Integer)arFalse.get('total');

			// Contar null
			AggregateResult arNull = [SELECT COUNT(Id) total
									 FROM Items_Cases__c
									 WHERE Email_Enviado__c = null];
			enviadosNull = (Integer)arNull.get('total');

			System.debug('📊 ESTADO EMAIL_ENVIADO__C:');
			System.debug('  true: ' + enviadosTrue);
			System.debug('  false: ' + enviadosFalse);
			System.debug('  null: ' + enviadosNull);

		} catch (Exception e) {
			System.debug('⚠️ Error verificando checkbox: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Genera un reporte de texto del sistema de envio de emails con totales generales, items pendientes de email (hasta 20) y los jobs asincronos recientes (BatchEnvioEmails/QueueEnvioEmails) de los ultimos 7 dias. Registra el reporte en debug y lo devuelve.
	 * @return Cadena con el reporte completo del sistema
	 */
	public static String generarReporte() {
		String reporte = '=== REPORTE SISTEMA ENVÍO EMAILS ===\n\n';

		try {
			// Totales generales
			Integer totalItems = [SELECT COUNT() FROM Items_Cases__c];
			Integer concluidos = [SELECT COUNT() FROM Items_Cases__c WHERE Estatus__c = 'Concluido'];

			reporte += '📊 TOTALES:\n';
			reporte += '  Total items: ' + totalItems + '\n';
			reporte += '  Items Concluidos: ' + concluidos + '\n\n';

			// Pendientes de email
			List<Items_Cases__c> pendientes = [SELECT Id, Name, RecordType.Name,
											  Correo_electronico__c, Correo_Copia__c, CreatedDate
											  FROM Items_Cases__c
											  WHERE Estatus__c = 'Concluido'
											  AND (Email_Enviado__c = false OR Email_Enviado__c = null)
											  AND Correo_electronico__c != null
											  ORDER BY CreatedDate DESC
											  LIMIT 20];

			reporte += '📨 PENDIENTES DE EMAIL (' + pendientes.size() + '):\n';
			for (Items_Cases__c item : pendientes) {
				reporte += '  • ' + item.Name + ' - ' + item.RecordType.Name +
						  ' (' + item.CreatedDate.date() + ')\n';
			}

			// Errores recientes (si tienes objeto de logs)
			try {
				List<AsyncApexJob> jobsRecientes = [SELECT Id, Status, NumberOfErrors,
												   CreatedDate, ApexClass.Name
												   FROM AsyncApexJob
												   WHERE ApexClass.Name IN ('BatchEnvioEmails', 'QueueEnvioEmails')
												   AND CreatedDate = LAST_N_DAYS:7
												   ORDER BY CreatedDate DESC
												   LIMIT 5];

				if (!jobsRecientes.isEmpty()) {
					reporte += '\n⚠️ JOBS RECIENTES:\n';
					for (AsyncApexJob job : jobsRecientes) {
						reporte += '  • ' + job.ApexClass.Name + ' - ' + job.Status +
								  ' (Errores: ' + job.NumberOfErrors + ')\n';
					}
				}
			} catch (Exception e) {
				// Ignorar si no hay jobs
			}

		} catch (Exception e) {
			reporte += '❌ Error generando reporte: ' + e.getMessage();
		}

		System.debug(reporte);
		return reporte;
	}
}
