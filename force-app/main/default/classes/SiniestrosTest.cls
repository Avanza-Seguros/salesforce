/**
 * @creation date: 26/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas de Siniestros (Claims): folio, datos de la póliza, fecha de cierre, validaciones de vigencia y
 *               de asegurado, y folio de las solicitudes de pago.
 */
@isTest
private class SiniestrosTest {

	private static final Datetime INICIO = Datetime.newInstanceGmt(2026, 1, 1, 12, 0, 0);

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Empresa contratante, dos pólizas de un año y un asegurado en cada una.
	 * @return void
	 */
	@testSetup
	static void setup() {
		Account empresa = new Account(Name = 'Empresa Siniestros');
		insert empresa;
		Contact empleado = new Contact(LastName = 'Asegurado', AccountId = empresa.Id);
		insert empleado;
		InsurancePolicy pol = poliza(empresa.Id, 'SIN-POL-1');
		InsurancePolicy otra = poliza(empresa.Id, 'SIN-POL-2');
		insert new List<InsurancePolicy>{ pol, otra };
		String rol = InsurancePolicyParticipant.Role.getDescribe().getPicklistValues()[0].getValue();
		insert new List<InsurancePolicyParticipant>{
			new InsurancePolicyParticipant(InsurancePolicyId = pol.Id, PrimaryParticipantContactId = empleado.Id, Role = rol, ParticipantCode = '1'),
			new InsurancePolicyParticipant(InsurancePolicyId = otra.Id, PrimaryParticipantContactId = empleado.Id, Role = rol, ParticipantCode = '1')
		};
	}

	static InsurancePolicy poliza(Id cuenta, String numero) {
		InsurancePolicy p = new InsurancePolicy(Name = numero, NameInsuredId = cuenta, Status = 'Inicial', PremiumAmount = 1000,
			PaymentDueDate = Date.today().addDays(30), EffectiveDate = INICIO, ExpirationDate = INICIO.addYears(1));
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { p.PremiumFrequency = pe.getValue(); break; }
		}
		return p;
	}

	static Claim siniestro(Id policyId, Datetime fecha) {
		return new Claim(Name = 'Nuevo', PolicyNumberId = policyId, Status = 'Abierto', ClaimType = 'Gastos médicos mayores',
			ClaimReasonType = 'Enfermedad', LossType = 'Reembolso', LossDate = fecha,
			RecordTypeId = Schema.SObjectType.Claim.getRecordTypeInfosByDeveloperName().get('Personas').getRecordTypeId());
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: El siniestro toma el folio como nombre y el contratante de su póliza; se cierra y se reabre.
	 * @return void
	 */
	@isTest
	static void testFolioPolizaYCierre() {
		InsurancePolicy pol = [SELECT Id, NameInsuredId FROM InsurancePolicy WHERE Name = 'SIN-POL-1'];
		Test.startTest();
		Claim c = siniestro(pol.Id, INICIO.addMonths(2));
		insert c;
		c = [SELECT Name, Folio__c, AccountId, FinalizedDate FROM Claim WHERE Id = :c.Id];
		System.assert(c.Name.startsWith('SIN-'), 'El nombre es el folio: ' + c.Name);
		System.assertEquals(c.Folio__c, c.Name);
		System.assertEquals(pol.NameInsuredId, c.AccountId, 'Toma el contratante de la póliza');
		System.assertEquals(null, c.FinalizedDate);
		update new Claim(Id = c.Id, Status = 'Cerrado');
		System.assertNotEquals(null, [SELECT FinalizedDate FROM Claim WHERE Id = :c.Id].FinalizedDate, 'Al cerrarse lleva fecha de cierre');
		update new Claim(Id = c.Id, Status = 'Reabierto');
		System.assertEquals(null, [SELECT FinalizedDate FROM Claim WHERE Id = :c.Id].FinalizedDate, 'Al reabrirse vuelve a estar en trámite');
		Test.stopTest();
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: La fecha del siniestro debe caer en la vigencia y el asegurado debe ser de la póliza del siniestro.
	 * @return void
	 */
	@isTest
	static void testValidaciones() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'SIN-POL-1'];
		InsurancePolicyParticipant suyo = [SELECT Id FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :pol.Id];
		InsurancePolicyParticipant ajeno = [SELECT Id FROM InsurancePolicyParticipant WHERE InsurancePolicy.Name = 'SIN-POL-2'];
		Test.startTest();
		Database.SaveResult fuera = Database.insert(siniestro(pol.Id, INICIO.addYears(2)), false);
		Claim c = siniestro(pol.Id, INICIO.addMonths(3));
		insert c;
		Database.SaveResult deOtra = Database.insert(new ClaimParticipant(ClaimId = c.Id, InsurancePolicyParticipantId = ajeno.Id,
			Roles = 'Paciente', IsInjured = true), false);
		Database.SaveResult deLaPoliza = Database.insert(new ClaimParticipant(ClaimId = c.Id, InsurancePolicyParticipantId = suyo.Id,
			Roles = 'Paciente', IsInjured = true), false);
		Test.stopTest();
		System.assertEquals(false, fuera.isSuccess(), 'Fuera de vigencia no se guarda');
		System.assertEquals(false, deOtra.isSuccess(), 'El asegurado de otra póliza no se acepta');
		System.assert(deLaPoliza.isSuccess(), String.valueOf(deLaPoliza.getErrors()));
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cada solicitud de pago (folio de reembolso) toma la póliza del siniestro y un folio consecutivo.
	 * @return void
	 */
	@isTest
	static void testSolicitudesDePago() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'SIN-POL-1'];
		Claim c = siniestro(pol.Id, INICIO.addMonths(4));
		insert c;
		String folio = [SELECT Name FROM Claim WHERE Id = :c.Id].Name;
		Test.startTest();
		insert new PaymentRequest(Name = 'x', ClaimId = c.Id);
		insert new List<PaymentRequest>{ new PaymentRequest(Name = 'x', ClaimId = c.Id), new PaymentRequest(Name = 'x', ClaimId = c.Id) };
		Test.stopTest();
		List<PaymentRequest> l = [SELECT Name, InsurancePolicyId FROM PaymentRequest WHERE ClaimId = :c.Id ORDER BY Name];
		System.assertEquals(3, l.size());
		System.assertEquals(folio + '-01', l[0].Name);
		System.assertEquals(folio + '-03', l[2].Name);
		System.assertEquals(pol.Id, l[0].InsurancePolicyId, 'Toma la póliza del siniestro');
	}
}
