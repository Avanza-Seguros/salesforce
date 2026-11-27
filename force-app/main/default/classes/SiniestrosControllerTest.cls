/**
 * @creation date: 26/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas de SiniestrosController: búsqueda de pólizas y asegurados, siniestro de un dependiente (con su
 *               titular, su cobertura y su primera solicitud), reembolso complementario y pago de la aseguradora.
 */
@isTest
private class SiniestrosControllerTest {

	private static final Datetime INICIO = Datetime.newInstanceGmt(2026, 1, 1, 12, 0, 0);

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Póliza de Gastos médicos con una cobertura, un titular y su dependiente.
	 * @return void
	 */
	@testSetup
	static void setup() {
		Account empresa = new Account(Name = 'Empresa Reembolsos');
		insert empresa;
		InsurancePolicy pol = new InsurancePolicy(Name = 'GMM-REEMB-1', NameInsuredId = empresa.Id, Status = 'Inicial', PremiumAmount = 1000,
			PaymentDueDate = Date.today().addDays(30), EffectiveDate = INICIO, ExpirationDate = INICIO.addYears(1));
		pol.put('Ramo__c', 'Gastos medicos');
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { pol.PremiumFrequency = pe.getValue(); break; }
		}
		insert pol;
		insert new InsurancePolicyCoverage(InsurancePolicyId = pol.Id, CoverageName = 'Gastos médicos mayores', LimitAmount = 1000000);
		String rol = InsurancePolicyParticipant.Role.getDescribe().getPicklistValues()[0].getValue();
		InsurancePolicyParticipant titular = new InsurancePolicyParticipant(InsurancePolicyId = pol.Id, ParticipantName = 'TITULAR PRUEBA',
			ParticipantCode = '100', Role = rol, IsActiveParticipant = true);
		insert titular;
		insert new InsurancePolicyParticipant(InsurancePolicyId = pol.Id, ParticipantName = 'HIJA PRUEBA', ParticipantCode = '100-1',
			Role = rol, IsActiveParticipant = true, RelatedInsPolicyParticipantId = titular.Id);
	}

	static Map<String, Object> datos(Id policyId, Id participanteId, Id coberturaId, Decimal monto) {
		return new Map<String, Object>{
			'policyId' => policyId, 'participanteId' => participanteId, 'ramo' => 'Gastos médicos mayores', 'causa' => 'Enfermedad',
			'tipo' => 'Reembolso', 'fecha' => '2026-03-10', 'diagnostico' => 'Apendicitis', 'hospital' => 'Hospital Ángeles',
			'fechaAtencion' => '2026-03-11', 'medio' => 'Web', 'coberturaId' => coberturaId,
			'solicitud' => monto == null ? null : new Map<String, Object>{ 'fechaRecepcion' => '2026-03-15', 'monto' => monto,
				'documentacion' => 'Facturas;Informe médico', 'referencia' => 'R-1' }
		};
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Reembolso completo: siniestro de un dependiente, complementario y pago de la aseguradora.
	 * @return void
	 */
	@isTest
	static void testReembolsoCompleto() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'GMM-REEMB-1'];
		Test.startTest();
		System.assertEquals(1, SiniestrosController.buscarPolizas('REEMB').size(), 'Busca por número');
		System.assertEquals(1, SiniestrosController.buscarPolizas('Empresa Reemb').size(), 'Busca por contratante');
		System.assertEquals(0, SiniestrosController.buscarPolizas('RE').size(), 'Mínimo 3 letras');
		Map<String, Object> dp = SiniestrosController.datosPoliza(pol.Id);
		System.assertEquals('Gastos médicos mayores', dp.get('ramo'));
		Id coberturaId = (Id) ((Map<String, Object>) ((List<Object>) dp.get('coberturas'))[0]).get('id');
		List<Map<String, Object>> hijos = SiniestrosController.buscarAsegurados(pol.Id, 'HIJA');
		System.assertEquals('TITULAR PRUEBA', hijos[0].get('titular'), 'Dice de quién es dependiente');
		System.assertEquals(2, SiniestrosController.buscarAsegurados(pol.Id, '').size());

		Map<String, Object> r = SiniestrosController.crearSiniestro(JSON.serialize(datos(pol.Id, (Id) hijos[0].get('id'), coberturaId, 15000)));
		Id claimId = (Id) r.get('claimId');
		Map<String, Object> comp = SiniestrosController.crearSolicitud(claimId,
			JSON.serialize(new Map<String, Object>{ 'monto' => 5000, 'documentacion' => 'Facturas' }));
		Map<String, Object> ds = SiniestrosController.datosSiniestro(claimId);
		List<Object> sols = (List<Object>) ds.get('solicitudes');
		SiniestrosController.registrarPago(claimId, JSON.serialize(new Map<String, Object>{
			'solicitudId' => (Id) ((Map<String, Object>) sols[0]).get('id'), 'monto' => 12000, 'fecha' => '2026-04-01', 'identificador' => 'SPEI-1' }));
		Test.stopTest();

		Claim c = [SELECT Name, LossType, ClaimReason, VisitSite, EstimatedAmount, ActualAmount, AccountId,
			(SELECT Roles, InsurancePolicyParticipant.ParticipantName FROM ClaimParticipants ORDER BY CreatedDate),
			(SELECT Name, InsurancePolicyCoverageId FROM ClaimCoverages)
			FROM Claim WHERE Id = :claimId];
		System.assertEquals(r.get('folio'), c.Name);
		System.assertEquals('Apendicitis', c.ClaimReason);
		System.assertEquals('Hospital Ángeles', c.VisitSite);
		System.assertEquals(2, c.ClaimParticipants.size(), 'La afectada y su titular');
		System.assertEquals('Paciente', c.ClaimParticipants[0].Roles);
		System.assertEquals('Reclamante', c.ClaimParticipants[1].Roles);
		System.assertEquals('TITULAR PRUEBA', c.ClaimParticipants[1].InsurancePolicyParticipant.ParticipantName);
		System.assertEquals(coberturaId, c.ClaimCoverages[0].InsurancePolicyCoverageId);
		System.assertEquals(20000, c.EstimatedAmount, 'Reclamado: 15,000 + 5,000');
		System.assertEquals(12000, c.ActualAmount, 'Pagado por la aseguradora');
		System.assertEquals(c.Name + '-02', comp.get('folio'));
		PaymentRequest pagada = [SELECT Status, ReferenceNumber, (SELECT Status, ServiceAmount FROM PaymentRequestLines) FROM PaymentRequest
			WHERE ClaimId = :claimId AND Name = :(c.Name + '-01')];
		System.assertEquals('Pagado', pagada.Status);
		System.assertEquals('R-1', pagada.ReferenceNumber);
		System.assertEquals('Pagado parcialmente', pagada.PaymentRequestLines[0].Status, '12,000 de 15,000');
		System.assertEquals(1, [SELECT COUNT() FROM ClaimCoveragePaymentDetail WHERE ClaimCoverage.ClaimId = :claimId AND Status = 'Pagado']);
		System.assertEquals('SPEI-1', [SELECT PaymentIdentifier FROM ClaimPaymentSummary WHERE ClaimId = :claimId].PaymentIdentifier);
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Titular sin solicitud y sin cobertura de la póliza; errores de captura.
	 * @return void
	 */
	@isTest
	static void testTitularYErrores() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'GMM-REEMB-1'];
		Id titular = [SELECT Id FROM InsurancePolicyParticipant WHERE ParticipantName = 'TITULAR PRUEBA'].Id;
		Map<String, Object> d = datos(pol.Id, titular, null, null);
		d.put('tipo', 'Programación de cirugía');
		Test.startTest();
		Id claimId = (Id) SiniestrosController.crearSiniestro(JSON.serialize(d)).get('claimId');
		Map<String, Object> fuera = datos(pol.Id, titular, null, null);
		fuera.put('fecha', '2028-01-01');
		List<String> errores = new List<String>();
		for (Map<String, Object> malo : new List<Map<String, Object>>{ fuera, new Map<String, Object>{ 'policyId' => pol.Id } }) {
			try { SiniestrosController.crearSiniestro(JSON.serialize(malo)); } catch (AuraHandledException e) { errores.add(e.getMessage()); }
		}
		try { SiniestrosController.registrarPago(claimId, JSON.serialize(new Map<String, Object>{ 'monto' => 0 })); }
		catch (AuraHandledException e) { errores.add(e.getMessage()); }
		Test.stopTest();
		Claim c = [SELECT (SELECT Roles FROM ClaimParticipants), (SELECT Name FROM ClaimCoverages), (SELECT Id FROM PaymentRequests) FROM Claim WHERE Id = :claimId];
		System.assertEquals(1, c.ClaimParticipants.size(), 'El titular es paciente y reclamante');
		System.assert(c.ClaimParticipants[0].Roles.contains('Reclamante'));
		System.assertEquals('Programación de cirugía', c.ClaimCoverages[0].Name, 'Sin cobertura de la póliza toma el tipo');
		System.assertEquals(0, c.PaymentRequests.size());
		System.assertEquals(3, errores.size(), String.valueOf(errores));
		System.assertEquals('Vida', SiniestrosController.ramoDe('VIDA GRUPO'));
		System.assertEquals('Accidentes personales', SiniestrosController.ramoDe('Accidentes personales'));
		System.assertEquals(null, SiniestrosController.ramoDe('Automoviles'));
	}
}
