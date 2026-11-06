/**
 * @creation date: 30/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas unitarias de BienVigencia y de su trigger en InsurancePolicyAsset.
 */
@isTest
private class BienVigenciaTest {

	/**
	 * @creation date: 30/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma una póliza de prueba con los datos que exige la validación del org.
	 * @param cuenta: Id de la cuenta asegurada
	 * @param numero: Número de póliza
	 * @param vence: Fin de vigencia
	 * @return Póliza insertada
	 */
	static InsurancePolicy poliza(Id cuenta, String numero, Date vence) {
		InsurancePolicy p = new InsurancePolicy(Name = numero, NameInsuredId = cuenta, Status = 'Inicial',
			PremiumAmount = 1000, PaymentDueDate = Date.today().addDays(30),
			EffectiveDate = Datetime.newInstance(Date.today().addDays(-10), Time.newInstance(12, 0, 0, 0)),
			ExpirationDate = Datetime.newInstance(vence, Time.newInstance(12, 0, 0, 0)));
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { p.PremiumFrequency = pe.getValue(); break; }
		}
		insert p;
		return p;
	}

	/**
	 * @creation date: 30/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Lee la vigencia guardada del bien del cliente.
	 * @param cpId: Id del CustomerProperty
	 * @return CustomerProperty con pólizas activas, vigente hasta y vigente
	 */
	static CustomerProperty bien(Id cpId) {
		return [SELECT Polizas_Activas__c, Vigente_Hasta__c, Vigente__c FROM CustomerProperty WHERE Id = :cpId];
	}

	/**
	 * @creation date: 30/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: El bien queda vigente con un bien de póliza activo; con uno sin fecha de fin la vigencia queda
	 * abierta; al cambiar el vencimiento de la póliza se alinean las fechas; al desactivarlos o borrarlos deja de estar
	 * vigente; y con la fecha de fin vencida tampoco está vigente.
	 * @return void
	 */
	@isTest
	static void testVigenciaDelBien() {
		Account acc = new Account(Name = 'Cuenta Vigencia');
		insert acc;
		CustomerProperty cp = new CustomerProperty(PrimaryOwnerId = acc.Id, Make = 'CHEVROLET', Vin = 'VINVIGENCIA000001');
		insert cp;
		Date vence = Date.today().addDays(100);
		InsurancePolicy pol = poliza(acc.Id, 'VIG-001', vence);

		Test.startTest();
		InsurancePolicyAsset uno = new InsurancePolicyAsset(InsurancePolicyId = pol.Id, AssetName = 'Uno', IsActive = true,
			CustomerPropertyId = cp.Id, EffectiveFromDate = Date.today().addDays(-10), EffectiveToDate = vence);
		insert uno;
		CustomerProperty r = bien(cp.Id);
		System.assertEquals(1, r.Polizas_Activas__c);
		System.assertEquals(vence, r.Vigente_Hasta__c);
		System.assertEquals(true, r.Vigente__c);

		// Otro bien de póliza activo sin fecha de fin: la vigencia queda abierta.
		InsurancePolicyAsset dos = new InsurancePolicyAsset(InsurancePolicyId = pol.Id, AssetName = 'Dos', IsActive = true,
			CustomerPropertyId = cp.Id);
		insert dos;
		r = bien(cp.Id);
		System.assertEquals(2, r.Polizas_Activas__c);
		System.assertEquals(null, r.Vigente_Hasta__c);
		System.assertEquals(true, r.Vigente__c);

		// Cambia el vencimiento de la póliza: los dos bienes de póliza pasan al nuevo fin.
		Date nuevo = Date.today().addDays(200);
		update new InsurancePolicy(Id = pol.Id, ExpirationDate = Datetime.newInstance(nuevo, Time.newInstance(12, 0, 0, 0)));
		System.assertEquals(2, [SELECT COUNT() FROM InsurancePolicyAsset WHERE InsurancePolicyId = :pol.Id AND EffectiveToDate = :nuevo]);
		System.assertEquals(nuevo, bien(cp.Id).Vigente_Hasta__c);

		// Vigencia ya terminada: sigue activo pero no vigente.
		update new List<InsurancePolicyAsset>{
			new InsurancePolicyAsset(Id = uno.Id, EffectiveToDate = Date.today().addDays(-1)),
			new InsurancePolicyAsset(Id = dos.Id, IsActive = false)
		};
		r = bien(cp.Id);
		System.assertEquals(1, r.Polizas_Activas__c);
		System.assertEquals(false, r.Vigente__c);

		// Sin bienes de póliza activos.
		delete uno;
		Test.stopTest();
		r = bien(cp.Id);
		System.assertEquals(0, r.Polizas_Activas__c);
		System.assertEquals(null, r.Vigente_Hasta__c);
		System.assertEquals(false, r.Vigente__c);
		System.assertEquals(0, BienVigencia.recalcular(new Set<Id>()));
	}
}
