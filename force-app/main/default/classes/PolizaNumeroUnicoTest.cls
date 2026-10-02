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
			PremiumAmount = 1000, PaymentDueDate = Date.today().addDays(30), SourceOpportunityId = oportunidad(cuenta));
		// Datos que exige la validación del org para activar la póliza.
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { p.PremiumFrequency = pe.getValue(); break; }
		}
		return p;
	}

	/**
	 * @creation date: 02/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valida que no se permitan números repetidos: con otro formato, en el mismo lote o al cambiar el
	 * número; y que actualizar sin cambiar el número funcione.
	 * @return void
	 */
	@isTest
	static void testNoPermiteNumeroRepetido() {
		Account acc = new Account(Name = 'Cuenta Póliza Única');
		insert acc;
		InsurancePolicy primera = poliza(acc.Id, '2001 M0080479');
		insert primera;
		System.assertEquals('2001M0080479',
			[SELECT numeroPolizaUnico__c FROM InsurancePolicy WHERE Id = :primera.Id].numeroPolizaUnico__c);

		// Mismo número con otro formato (sin espacio, minúsculas): se rechaza.
		Database.SaveResult r = Database.insert(poliza(acc.Id, '2001m0080479'), false);
		System.assert(!r.isSuccess(), 'Debe rechazar el número repetido');
		System.assert(r.getErrors()[0].getMessage().contains('Ya existe una póliza'), r.getErrors()[0].getMessage());

		// Dos en el mismo lote con el mismo número: se rechaza la segunda.
		List<Database.SaveResult> lote = Database.insert(new List<InsurancePolicy>{
			poliza(acc.Id, 'VI0002940812'), poliza(acc.Id, 'VI0002940812')
		}, false);
		System.assert(lote[0].isSuccess());
		System.assert(!lote[1].isSuccess());

		// Cambiar el número de otra póliza a uno existente: se rechaza.
		InsurancePolicy otra = poliza(acc.Id, '0971273390');
		insert otra;
		otra.Name = '2001 M0080479';
		System.assert(!Database.update(otra, false).isSuccess());

		// Actualizar sin cambiar el número no se ve afectado.
		primera.PolicyName = '2001 M0080479';
		System.assert(Database.update(primera, false).isSuccess());

		// Validación previa que usa Crear Póliza al leer el PDF.
		System.assert(PolizaNumeroUnico.validarNumeroPoliza('2001m0080479', null).contains('Ya existe una póliza'));
		System.assertEquals(null, PolizaNumeroUnico.validarNumeroPoliza('2001 M0080479', primera.Id), 'La propia póliza no cuenta');
		System.assertEquals(null, PolizaNumeroUnico.validarNumeroPoliza('NUEVO-123', null));
	}

	/**
	 * @creation date: 02/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valida que no se pueda crear una póliza sin oportunidad ni quitarle la oportunidad.
	 * @return void
	 */
	@isTest
	static void testNoPermitePolizaSinOportunidad() {
		Account acc = new Account(Name = 'Cuenta Sin Oportunidad');
		insert acc;
		InsurancePolicy sinOpp = poliza(acc.Id, 'SINOPP-001');
		sinOpp.SourceOpportunityId = null;
		Database.SaveResult r = Database.insert(sinOpp, false);
		System.assert(!r.isSuccess(), 'Debe rechazar la póliza sin oportunidad');
		System.assertEquals(PolizaNumeroUnico.SIN_OPORTUNIDAD, r.getErrors()[0].getMessage());

		InsurancePolicy conOpp = poliza(acc.Id, 'CONOPP-001');
		insert conOpp;
		conOpp.SourceOpportunityId = null;
		System.assert(!Database.update(conOpp, false).isSuccess(), 'No se le puede quitar la oportunidad');
	}

	/**
	 * @creation date: 02/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valida la normalización del número de póliza.
	 * @return void
	 */
	@isTest
	static void testNormalizar() {
		System.assertEquals('ABC123', PolizaNumeroUnico.normalizar(' abc 123 '));
		System.assertEquals(null, PolizaNumeroUnico.normalizar('  '));
	}
}
