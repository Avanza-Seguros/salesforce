/**
 * @creation date: 27/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Datos de prueba de cuentas, agentes y pólizas para la liberación sin Cobranza. Hace lo mismo que los
 *   métodos de CollectionsTestDataFactory que usan las pruebas de pólizas y oportunidades, sin planes de pago.
 */
@IsTest
public class DatosPruebaPolizas {
	public static final String NOMBRE_CUENTA = 'Collections Test Insured';

	private static Id agenteId;

	/**
	 * @creation date: 27/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Crea la cuenta asegurada de las pruebas.
	 * @return Cuenta creada
	 */
	public static Account createInsuredAccount() {
		Account cuenta = new Account(Name = NOMBRE_CUENTA, AnnualRevenue = 1000000);
		insert cuenta;
		return cuenta;
	}

	/**
	 * @creation date: 27/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Crea una vez por transacción un Agente__c válido, para el lookup requerido
	 *   Opportunity.Agente_Relacionado__c.
	 * @return Id del agente
	 */
	public static Id getOrCreateAgenteId() {
		if (agenteId == null) {
			Agente__c agente = new Agente__c(Name = 'Collections Test Agente', Status__c = 'Nuevo', Estado_Civil__c = 'Casado');
			insert agente;
			agenteId = agente.Id;
		}
		return agenteId;
	}

	/**
	 * @creation date: 27/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma, sin insertarla, una póliza con prima, frecuencia y fecha de pago.
	 * @param cuentaId: Asegurado
	 * @param estatus: Estado de la póliza
	 * @param frecuencia: Frecuencia de prima
	 * @param prima: Monto de prima
	 * @param primerPago: Fecha del primer pago
	 * @return Póliza sin insertar
	 */
	public static InsurancePolicy buildCompletePolicy(Id cuentaId, String estatus, String frecuencia, Decimal prima, Date primerPago) {
		return new InsurancePolicy(
			Name = 'POL-TEST-' + String.valueOf(Crypto.getRandomInteger()).replace('-', ''),
			PolicyName = 'Test policy',
			NameInsuredId = cuentaId,
			Status = estatus,
			PremiumAmount = prima,
			PremiumFrequency = frecuencia,
			PaymentDueDate = primerPago
		);
	}
}
