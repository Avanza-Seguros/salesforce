/**
 * @creation date: 18/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas unitarias de PolizaVigencias (historial de vigencias por número de póliza).
 */
@isTest
private class PolizaVigenciasTest {

	private static Id oportunidadId;

	/**
	 * @creation date: 18/11/2026
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
			Opportunity opp = new Opportunity(Name = 'Opp Vigencias', AccountId = cuenta, StageName = etapa,
				CloseDate = Date.today().addDays(30));
			// En UAT el ramo de la oportunidad es obligatorio.
			for (Schema.PicklistEntry pe : Opportunity.Ramo__c.getDescribe().getPicklistValues()) {
				if (pe.isActive()) { opp.Ramo__c = pe.getValue(); break; }
			}
			insert opp;
			oportunidadId = opp.Id;
		}
		return oportunidadId;
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma una póliza de prueba con un año de vigencia.
	 * @param cuenta: Id de la cuenta asegurada
	 * @param numero: Número de póliza
	 * @param anio: Año de inicio de vigencia (24 de abril)
	 * @return Póliza sin insertar
	 */
	static InsurancePolicy poliza(Id cuenta, String numero, Integer anio) {
		// La llave número + vigencia (que usa la liga) solo se arma en las pruebas que lo piden.
		PolizaNumeroUnico.aplicarEnPruebas = true;
		InsurancePolicy p = new InsurancePolicy(Name = numero, NameInsuredId = cuenta, Status = 'Inicial',
			PremiumAmount = 1000, PaymentDueDate = Date.today().addDays(30), SourceOpportunityId = oportunidad(cuenta),
			EffectiveDate = Datetime.newInstanceGmt(anio, 4, 24, 12, 0, 0),
			ExpirationDate = Datetime.newInstanceGmt(anio + 1, 4, 24, 12, 0, 0));
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { p.PremiumFrequency = pe.getValue(); break; }
		}
		return p;
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Lee las ligas de una póliza.
	 * @param id: Id de la póliza
	 * @return Póliza con PriorPolicyId y nextPolicy__c
	 */
	static InsurancePolicy ligas(Id id) {
		return [SELECT Id, PriorPolicyId, nextPolicy__c FROM InsurancePolicy WHERE Id = :id];
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Tres vigencias del mismo número cargadas en desorden (2026, 2024 y 2025, con otro formato del
	 * número) quedan ligadas en orden de vigencia; otro número no se mezcla.
	 * @return void
	 */
	@isTest
	static void testLigaVigenciasEnDesorden() {
		Account acc = new Account(Name = 'Cuenta Vigencias');
		insert acc;
		Test.startTest();
		InsurancePolicy v2026 = poliza(acc.Id, 'GM0000170455', 2026);
		insert v2026;
		InsurancePolicy v2024 = poliza(acc.Id, 'GM0000170455', 2024);
		insert v2024;
		InsurancePolicy otra = poliza(acc.Id, 'GM0000999999', 2025);
		InsurancePolicy v2025 = poliza(acc.Id, 'gm 0000170455', 2025);
		insert new List<InsurancePolicy>{ otra, v2025 };
		Test.stopTest();

		InsurancePolicy a = ligas(v2024.Id), b = ligas(v2025.Id), c = ligas(v2026.Id), o = ligas(otra.Id);
		System.assertEquals(null, a.PriorPolicyId, 'La primera vigencia no tiene anterior');
		System.assertEquals(v2025.Id, a.nextPolicy__c);
		System.assertEquals(v2024.Id, b.PriorPolicyId);
		System.assertEquals(v2026.Id, b.nextPolicy__c);
		System.assertEquals(v2025.Id, c.PriorPolicyId);
		System.assertEquals(null, c.nextPolicy__c, 'La última vigencia no tiene siguiente');
		System.assertEquals(null, o.PriorPolicyId, 'Otro número no se liga');
		System.assertEquals(null, o.nextPolicy__c, 'Otro número no se liga');
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Una vigencia registrada antes de la regla de número único (sin llave y con el número escrito con
	 * espacios y ceros) también entra en la cadena: la nueva vigencia se liga con ella y no se la salta.
	 * @return void
	 */
	@isTest
	static void testIncluyeVigenciasSinLlave() {
		Account acc = new Account(Name = 'Cuenta Vigencias Sin Llave');
		insert acc;
		InsurancePolicy v2024 = poliza(acc.Id, '121306120', 2024);
		insert v2024;
		InsurancePolicy v2025 = poliza(acc.Id, '0 121306120', 2025);
		PolizaNumeroUnico.aplicarEnPruebas = false;
		insert v2025;
		System.assertEquals(null, [SELECT numeroPolizaUnico__c FROM InsurancePolicy WHERE Id = :v2025.Id].numeroPolizaUnico__c);

		Test.startTest();
		InsurancePolicy v2026 = poliza(acc.Id, '121306120', 2026);
		insert v2026;
		Test.stopTest();

		System.assertEquals(v2025.Id, ligas(v2026.Id).PriorPolicyId, 'No se salta la vigencia sin llave');
		System.assertEquals(v2024.Id, ligas(v2025.Id).PriorPolicyId);
		System.assertEquals(v2026.Id, ligas(v2025.Id).nextPolicy__c);
		System.assertEquals(v2025.Id, ligas(v2024.Id).nextPolicy__c);
		System.assertEquals('121306120', PolizaVigencias.normalizar(' 00121 306120'));
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: La primera vigencia conserva su liga a una póliza con otro número; al cambiarle el número a una
	 * vigencia, sale de la cadena y las demás se vuelven a ligar entre sí.
	 * @return void
	 */
	@isTest
	static void testRespetaOtroNumeroYReacomodaAlCambiarNumero() {
		Account acc = new Account(Name = 'Cuenta Vigencias 2');
		insert acc;
		InsurancePolicy previa = poliza(acc.Id, 'COL-ANTERIOR', 2023);
		insert previa;
		InsurancePolicy v2024 = poliza(acc.Id, 'COL-NUEVA', 2024);
		v2024.PriorPolicyId = previa.Id;
		insert v2024;
		InsurancePolicy v2025 = poliza(acc.Id, 'COL-NUEVA', 2025);
		InsurancePolicy v2026 = poliza(acc.Id, 'COL-NUEVA', 2026);
		insert new List<InsurancePolicy>{ v2025, v2026 };
		System.assertEquals(previa.Id, ligas(v2024.Id).PriorPolicyId, 'Se respeta la liga a otro número');
		System.assertEquals(v2025.Id, ligas(v2024.Id).nextPolicy__c);

		Test.startTest();
		update new InsurancePolicy(Id = v2025.Id, Name = 'COL-OTRA');
		Test.stopTest();

		System.assertEquals(v2026.Id, ligas(v2024.Id).nextPolicy__c, 'Sin la de 2025 la siguiente es la de 2026');
		System.assertEquals(v2024.Id, ligas(v2026.Id).PriorPolicyId);
		System.assertEquals(null, ligas(v2025.Id).PriorPolicyId, 'La de otro número sale de la cadena');
		System.assertEquals(null, ligas(v2025.Id).nextPolicy__c, 'La de otro número sale de la cadena');
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: ligarExistentes liga pólizas ya registradas cuyas ligas se borraron, no cambia nada si ya
	 * estaban ligadas y respeta las ligas entre números distintos (renovación de Qualitas que cambió de número) aunque
	 * se reacomoden todos los números a la vez.
	 * @return void
	 */
	@isTest
	static void testLigarExistentes() {
		Account acc = new Account(Name = 'Cuenta Vigencias 3');
		insert acc;
		InsurancePolicy v1 = poliza(acc.Id, 'VI0001', 2024);
		InsurancePolicy v2 = poliza(acc.Id, 'VI0001', 2025);
		InsurancePolicy qAnterior = poliza(acc.Id, 'QL-100', 2023);
		insert new List<InsurancePolicy>{ v1, v2, qAnterior };
		InsurancePolicy qRenovada = poliza(acc.Id, 'QL-200', 2024);
		qRenovada.PriorPolicyId = qAnterior.Id;
		insert qRenovada;
		update new InsurancePolicy(Id = qAnterior.Id, nextPolicy__c = qRenovada.Id);
		update new List<InsurancePolicy>{
			new InsurancePolicy(Id = v1.Id, nextPolicy__c = null),
			new InsurancePolicy(Id = v2.Id, PriorPolicyId = null)
		};

		Test.startTest();
		Integer cambiadas = PolizaVigencias.ligarExistentes(new Set<Id>{ v1.Id });
		Integer otraVez = PolizaVigencias.ligarExistentes(new Set<Id>{ v1.Id, v2.Id, qAnterior.Id, qRenovada.Id });
		Test.stopTest();

		System.assertEquals(2, cambiadas);
		System.assertEquals(0, otraVez, 'Si ya están ligadas no cambia nada');
		System.assertEquals(qAnterior.Id, ligas(qRenovada.Id).PriorPolicyId, 'Se respeta la liga a otro número');
		System.assertEquals(qRenovada.Id, ligas(qAnterior.Id).nextPolicy__c, 'Se respeta la liga a otro número');
		System.assertEquals(v1.Id, ligas(v2.Id).PriorPolicyId);
		System.assertEquals(v2.Id, ligas(v1.Id).nextPolicy__c);
		System.assertEquals(null, PolizaVigencias.numero(null));
		System.assertEquals(null, PolizaVigencias.numero('SINLLAVE'));
	}
}
