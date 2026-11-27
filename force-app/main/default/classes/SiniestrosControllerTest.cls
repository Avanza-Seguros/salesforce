/**
 * @creation date: 26/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas de SiniestrosController: búsqueda de pólizas y asegurados, siniestro de un dependiente (con su
 *               titular, su cobertura y su primera solicitud), reembolso complementario y pago de la aseguradora;
 *               siniestros de vehículos y ubicaciones, y pestaña Siniestros de la póliza.
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
		List<Map<String, Object>> hijos = SiniestrosController.buscarAsegurados(pol.Id, 'HIJA', null);
		System.assertEquals('TITULAR PRUEBA', hijos[0].get('titular'), 'Dice de quién es dependiente');
		System.assertEquals(2, SiniestrosController.buscarAsegurados(pol.Id, '', null).size());
		List<Map<String, Object>> elegido = SiniestrosController.buscarAsegurados(pol.Id, 'HIJA', [SELECT Id FROM InsurancePolicyParticipant WHERE ParticipantName = 'TITULAR PRUEBA'].Id);
		System.assertEquals('TITULAR PRUEBA', elegido[0].get('nombre'), 'El que viene elegido va primero');
		System.assertEquals(2, elegido.size());

		Map<String, Object> r = SiniestrosController.crearSiniestro(JSON.serialize(datos(pol.Id, (Id) hijos[0].get('id'), coberturaId, 15000)));
		Id claimId = (Id) r.get('claimId');
		Map<String, Object> comp = SiniestrosController.crearSolicitud(claimId,
			JSON.serialize(new Map<String, Object>{ 'monto' => 5000, 'documentacion' => 'Facturas' }));
		Map<String, Object> ds = SiniestrosController.datosSiniestro(claimId);
		List<Object> sols = (List<Object>) ds.get('solicitudes');
		SiniestrosController.registrarPago(claimId, JSON.serialize(new Map<String, Object>{
			'solicitudId' => (Id) ((Map<String, Object>) sols[0]).get('id'), 'monto' => 12000, 'fecha' => '2026-04-01', 'identificador' => 'SPEI-1' }));
		Test.stopTest();

		Claim c = [SELECT Name, LossType, ClaimReason, VisitSite, EstimatedAmount, ActualAmount, AccountId, Afectado__c,
			(SELECT Roles, InsurancePolicyParticipant.ParticipantName FROM ClaimParticipants ORDER BY CreatedDate),
			(SELECT Name, InsurancePolicyCoverageId FROM ClaimCoverages)
			FROM Claim WHERE Id = :claimId];
		System.assertEquals(r.get('folio'), c.Name);
		System.assertEquals('Apendicitis', c.ClaimReason);
		System.assertEquals('HIJA PRUEBA', c.Afectado__c);
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
		System.assertEquals('Automóviles', SiniestrosController.ramoDe('Automoviles'));
		System.assertEquals('Daños', SiniestrosController.ramoDe('Empresarial'));
		System.assertEquals(null, SiniestrosController.ramoDe('Dental'));
		System.assertEquals('personas', SiniestrosController.familiaDe('GMM'));
		System.assertEquals('danos', SiniestrosController.familiaDe('Daños'));
	}

	static InsurancePolicy polizaDe(String numero, String ramo, Id cuentaId) {
		InsurancePolicy pol = new InsurancePolicy(Name = numero, NameInsuredId = cuentaId, Status = 'Inicial', PremiumAmount = 50000,
			PaymentDueDate = Date.today().addDays(30), EffectiveDate = INICIO, ExpirationDate = INICIO.addYears(1));
		pol.put('Ramo__c', ramo);
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { pol.PremiumFrequency = pe.getValue(); break; }
		}
		return pol;
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Siniestro de un vehículo (desde su inciso) y de una ubicación; pestaña Siniestros de la póliza con su
	 *               siniestralidad y los folios anteriores de Control de Folios.
	 * @return void
	 */
	@isTest
	static void testBienesYPestana() {
		Account empresa = [SELECT Id FROM Account WHERE Name = 'Empresa Reembolsos'];
		InsurancePolicy autos = polizaDe('AUT-FLOT-1', 'Automoviles', empresa.Id);
		autos.put('Subtotal__c', 40000);
		InsurancePolicy danos = polizaDe('DAN-UBIC-1', 'Danos', empresa.Id);
		insert new List<InsurancePolicy>{ autos, danos };
		CustomerProperty vehiculo = new CustomerProperty(PrimaryOwnerId = empresa.Id, Make = 'NISSAN', Vin = 'SERIEPRUEBA00001');
		CustomerProperty domicilio = new CustomerProperty(PrimaryOwnerId = empresa.Id, Street = 'Av. Industria 10', City = 'Zapopan');
		insert new List<CustomerProperty>{ vehiculo, domicilio };
		InsurancePolicyAsset bien = new InsurancePolicyAsset(InsurancePolicyId = autos.Id, AssetName = 'NISSAN VERSA', CustomerPropertyId = vehiculo.Id);
		InsurancePolicyAsset bodega = new InsurancePolicyAsset(InsurancePolicyId = danos.Id, AssetName = 'Inciso 2 - Bodega Norte',
			CustomerPropertyId = domicilio.Id, Suma_Asegurada__c = 1000000);
		// Sin bien del cliente: no se ofrece (como en la pestaña Ubicaciones).
		InsurancePolicyAsset suelto = new InsurancePolicyAsset(InsurancePolicyId = danos.Id, AssetName = 'Bodega sin domicilio');
		insert new List<InsurancePolicyAsset>{ bien, bodega, suelto };
		Inciso_Flotilla__c inciso = new Inciso_Flotilla__c(Poliza__c = autos.Id, Vehiculo__c = vehiculo.Id, Numero_Inciso__c = 1,
			Serie__c = 'SERIEPRUEBA00001', Placas__c = 'ABC123', Descripcion__c = 'VERSA SENSE', Modelo__c = 2024);
		insert inciso;
		// Folio de siniestro anterior, ligado a la póliza del objeto anterior con el mismo número.
		Polizas__c anterior = new Polizas__c(Name = 'AUT-FLOT-1');
		insert anterior;
		insert new Control_de_Folios__c(Poliza__c = anterior.Id, Folio__c = 'F-100', Fecha__c = Date.newInstance(2025, 5, 1),
			RecordTypeId = Schema.SObjectType.Control_de_Folios__c.getRecordTypeInfosByDeveloperName().get('Siniestros').getRecordTypeId());

		Test.startTest();
		Map<String, Object> dp = SiniestrosController.datosPoliza(autos.Id);
		System.assertEquals('autos', dp.get('familia'));
		System.assertEquals('Automóviles', dp.get('ramo'));
		List<Map<String, Object>> porPlacas = SiniestrosController.buscarBienes(autos.Id, 'abc123', null);
		System.assertEquals(1, porPlacas.size(), 'Busca por placas');
		System.assertEquals(inciso.Id, porPlacas[0].get('incisoId'));
		System.assertEquals(bien.Id, SiniestrosController.buscarBienes(autos.Id, 'nada', inciso.Id)[0].get('id'), 'Desde el renglón del inciso');
		List<Map<String, Object>> ubicaciones = SiniestrosController.buscarBienes(danos.Id, '', null);
		System.assertEquals(1, ubicaciones.size(), 'Solo la ubicación con su bien del cliente');
		System.assert(((String) ubicaciones[0].get('detalle')).contains('Zapopan'), (String) ubicaciones[0].get('detalle'));
		Map<String, Object> datos = new Map<String, Object>{
			'policyId' => autos.Id, 'bienId' => bien.Id, 'ramo' => 'Automóviles', 'causa' => 'Colisión', 'tipo' => 'Pérdida parcial',
			'fecha' => '2026-03-10', 'diagnostico' => 'Golpe en la defensa', 'lugar' => 'Av. Reforma 100', 'correo' => 'flotilla@prueba.com',
			'solicitud' => new Map<String, Object>{ 'monto' => 8000 }
		};
		Id claimId = (Id) SiniestrosController.crearSiniestro(JSON.serialize(datos)).get('claimId');
		Id solicitudId = (Id) ((Map<String, Object>) ((List<Object>) SiniestrosController.datosSiniestro(claimId).get('solicitudes'))[0]).get('id');
		SiniestrosController.registrarPago(claimId, JSON.serialize(new Map<String, Object>{ 'solicitudId' => solicitudId, 'monto' => 6000 }));
		List<String> errores = new List<String>();
		for (Map<String, Object> malo : new List<Map<String, Object>>{
			new Map<String, Object>{ 'policyId' => danos.Id, 'fecha' => '2026-02-01' },
			new Map<String, Object>{ 'policyId' => danos.Id, 'bienId' => bien.Id, 'fecha' => '2026-02-01' }
		}) {
			try { SiniestrosController.crearSiniestro(JSON.serialize(malo)); } catch (AuraHandledException e) { errores.add(e.getMessage()); }
		}
		SiniestrosController.crearSiniestro(JSON.serialize(new Map<String, Object>{ 'policyId' => danos.Id, 'bienId' => bodega.Id,
			'ramo' => 'Daños', 'causa' => 'Incendio', 'tipo' => 'Pérdida total', 'fecha' => '2026-02-01' }));
		Map<String, Object> tab = SiniestrosController.siniestrosDePoliza(autos.Id);
		Map<String, Object> sitio = SiniestrosController.siniestrosDelSitio(autos.Id);
		Test.stopTest();

		Claim c = [SELECT RecordType.DeveloperName, InsuredAssetId, IncidentSiteStreet, ClaimReason, Afectado__c, Correo_Avisos__c,
			(SELECT Roles, ParticipantAccountId, InsurancePolicyParticipantId FROM ClaimParticipants),
			(SELECT InsurancePolicyAssetId FROM InsuranceClaimAssets), (SELECT InsurancePolicyAssetId FROM ClaimCoverages)
			FROM Claim WHERE Id = :claimId];
		System.assertEquals('Autos', c.RecordType.DeveloperName);
		System.assertEquals(bien.Id, c.InsuredAssetId);
		System.assertEquals('Av. Reforma 100', c.IncidentSiteStreet);
		System.assertEquals('VERSA SENSE', c.Afectado__c);
		System.assertEquals('flotilla@prueba.com', c.Correo_Avisos__c);
		System.assertEquals(bien.Id, c.InsuranceClaimAssets[0].InsurancePolicyAssetId);
		System.assertEquals(bien.Id, c.ClaimCoverages[0].InsurancePolicyAssetId);
		System.assertEquals(1, c.ClaimParticipants.size(), 'El contratante como reclamante');
		System.assertEquals(empresa.Id, c.ClaimParticipants[0].ParticipantAccountId);
		System.assertEquals('Danos', [SELECT RecordType.DeveloperName FROM Claim WHERE PolicyNumberId = :danos.Id].RecordType.DeveloperName);
		System.assertEquals(2, errores.size(), String.valueOf(errores));
		System.assert(errores[0].contains('ubicación'), errores[0]);

		List<Object> siniestros = (List<Object>) tab.get('siniestros');
		System.assertEquals(1, siniestros.size());
		Map<String, Object> s = (Map<String, Object>) siniestros[0];
		System.assertEquals('VERSA SENSE', s.get('afectado'));
		System.assert(((String) s.get('afectadoDetalle')).contains('Inciso 1'), (String) s.get('afectadoDetalle'));
		Map<String, Object> resumen = (Map<String, Object>) tab.get('resumen');
		System.assertEquals(6000, (Decimal) resumen.get('pagado'));
		System.assertEquals(8000, (Decimal) resumen.get('reclamado'));
		System.assertEquals(15.0, (Decimal) resumen.get('siniestralidad'), '6,000 de 40,000 de prima neta');
		Map<String, Object> enSitio = (Map<String, Object>) ((List<Object>) sitio.get('siniestros'))[0];
		System.assertEquals('VERSA SENSE', enSitio.get('afectado'), 'En el sitio, el afectado guardado');
		System.assertEquals(false, enSitio.containsKey('descripcion'), 'Sin la descripción');
		List<Object> folios = (List<Object>) tab.get('folios');
		System.assertEquals(1, folios.size(), 'Folio anterior del mismo número');
		System.assertEquals('F-100', ((Map<String, Object>) folios[0]).get('folio'));
	}
}
