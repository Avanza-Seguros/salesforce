/**
 * @creation date: 02/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas unitarias de PolizaNumeroUnico.
 */
@isTest
private class PolizaNumeroUnicoTest {

	private static Id oportunidadId;

	/**
	 * @creation date: 02/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve la oportunidad de prueba de la cuenta (la crea una vez por prueba).
	 * @param cuenta: Id de la cuenta de la oportunidad
	 * @return Id de la oportunidad
	 */
	static Id oportunidad(Id cuenta) {
		if (oportunidadId == null) {
			String etapa = 'Prospecting';
			for (OpportunityStage s : [
				SELECT MasterLabel FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1
			]) { etapa = s.MasterLabel; }
			Opportunity opp = new Opportunity(Name = 'Opp Póliza Única', AccountId = cuenta, StageName = etapa,
				CloseDate = Date.today().addDays(30));
			insert opp;
			oportunidadId = opp.Id;
		}
		return oportunidadId;
	}

	/**
	 * @creation date: 02/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma una póliza de prueba con los datos que exige la validación del org.
	 * @param cuenta: Id de la cuenta asegurada
	 * @param numero: Número de póliza
	 * @return Póliza sin insertar
	 */
	static InsurancePolicy poliza(Id cuenta, String numero) {
		// Las reglas de pólizas solo aplican en las pruebas que lo piden.
		PolizaNumeroUnico.aplicarEnPruebas = true;
		InsurancePolicy p = new InsurancePolicy(Name = numero, NameInsuredId = cuenta, Status = 'Inicial',
			PremiumAmount = 1000, PaymentDueDate = Date.today().addDays(30), SourceOpportunityId = oportunidad(cuenta),
			EffectiveDate = VIGENCIA);
		// Datos que exige la validación del org para activar la póliza.
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { p.PremiumFrequency = pe.getValue(); break; }
		}
		return p;
	}

	private static final Datetime VIGENCIA = Datetime.newInstanceGmt(2026, 1, 1, 12, 0, 0);

	/**
	 * @creation date: 02/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valida la regla número + vigencia: rechaza la misma póliza con la misma vigencia (con otro
	 * formato, en el mismo lote o al cambiar el número o la vigencia), permite la renovación con otra vigencia y no
	 * afecta las actualizaciones que no cambian número ni vigencia.
	 * @return void
	 */
	@isTest
	static void testNoPermiteNumeroYVigenciaRepetidos() {
		Account acc = new Account(Name = 'Cuenta Póliza Única');
		insert acc;
		InsurancePolicy primera = poliza(acc.Id, '2001 M0080479');
		insert primera;
		System.assertEquals('2001M0080479|2026-01-01',
			[SELECT numeroPolizaUnico__c FROM InsurancePolicy WHERE Id = :primera.Id].numeroPolizaUnico__c);

		// Mismo número (otro formato) y misma vigencia: se rechaza.
		Database.SaveResult r = Database.insert(poliza(acc.Id, '2001m0080479'), false);
		System.assert(!r.isSuccess(), 'Debe rechazar el mismo número con la misma vigencia');
		System.assert(r.getErrors()[0].getMessage().contains('Ya existe una póliza'), r.getErrors()[0].getMessage());

		// Renovación: mismo número con otra vigencia, se permite.
		InsurancePolicy renovacion = poliza(acc.Id, '2001 M0080479');
		renovacion.EffectiveDate = Datetime.newInstanceGmt(2027, 1, 1, 12, 0, 0);
		System.assert(Database.insert(renovacion, false).isSuccess(), 'La renovación con otra vigencia se permite');

		// Cambiar la vigencia de la renovación a la de la primera: se rechaza.
		renovacion.EffectiveDate = VIGENCIA;
		System.assert(!Database.update(renovacion, false).isSuccess());

		// Dos en el mismo lote con el mismo número y vigencia: se rechaza la segunda.
		List<Database.SaveResult> lote = Database.insert(new List<InsurancePolicy>{
			poliza(acc.Id, 'VI0002940812'), poliza(acc.Id, 'VI0002940812')
		}, false);
		System.assert(lote[0].isSuccess());
		System.assert(!lote[1].isSuccess());

		// Cambiar el número de otra póliza a uno existente con la misma vigencia: se rechaza.
		InsurancePolicy otra = poliza(acc.Id, '0971273390');
		insert otra;
		otra.Name = '2001 M0080479';
		System.assert(!Database.update(otra, false).isSuccess());

		// Actualizar sin cambiar número ni vigencia no se ve afectado.
		primera.PolicyName = '2001 M0080479';
		System.assert(Database.update(primera, false).isSuccess());

		// Validación previa que usa Crear Póliza al leer el PDF.
		System.assert(PolizaNumeroUnico.validarNumeroPoliza('2001m0080479', '2026-01-01', null).contains('Ya existe una póliza'));
		System.assertEquals(null, PolizaNumeroUnico.validarNumeroPoliza('2001 M0080479', '2028-01-01', null), 'Otra vigencia está libre');
		System.assertEquals(null, PolizaNumeroUnico.validarNumeroPoliza('2001 M0080479', '2026-01-01', primera.Id), 'La propia póliza no cuenta');
		System.assertEquals(null, PolizaNumeroUnico.validarNumeroPoliza('NUEVO-123', null, null));
	}

	/**
	 * @creation date: 02/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valida que una póliza sin oportunidad se pueda guardar y que también reciba su llave única.
	 * @return void
	 */
	@isTest
	static void testPolizaSinOportunidad() {
		Account acc = new Account(Name = 'Cuenta Sin Oportunidad');
		insert acc;
		InsurancePolicy sinOpp = poliza(acc.Id, 'SINOPP-001');
		sinOpp.SourceOpportunityId = null;
		Database.SaveResult r = Database.insert(sinOpp, false);
		System.assert(r.isSuccess(), 'La póliza sin oportunidad se puede guardar');
		System.assertEquals('SINOPP-001|2026-01-01',
			[SELECT numeroPolizaUnico__c FROM InsurancePolicy WHERE Id = :sinOpp.Id].numeroPolizaUnico__c);
	}

	/**
	 * @creation date: 02/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valida la normalización del número y el armado de la llave.
	 * @return void
	 */
	@isTest
	static void testNormalizar() {
		System.assertEquals('ABC123', PolizaNumeroUnico.normalizar(' abc 123 '));
		System.assertEquals(null, PolizaNumeroUnico.normalizar('  '));
		System.assertEquals('ABC123|2026-03-05', PolizaNumeroUnico.llave('abc 123', Date.newInstance(2026, 3, 5)));
		System.assertEquals('ABC123|', PolizaNumeroUnico.llave('abc 123', null));
		System.assertEquals(null, PolizaNumeroUnico.llave(null, Date.today()));
		System.assertEquals(Date.newInstance(2026, 1, 1), PolizaNumeroUnico.fecha(VIGENCIA));
	}
}
