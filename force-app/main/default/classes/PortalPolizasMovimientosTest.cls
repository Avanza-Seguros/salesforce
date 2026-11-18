/**
 * @creation date: 18/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas unitarias de PortalPolizasMovimientos (acciones del sitio en las pestañas de Salesforce).
 */
@isTest
private class PortalPolizasMovimientosTest {

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma una póliza de prueba con los datos que exige la validación del org.
	 * @param cuenta: Id de la cuenta asegurada
	 * @param numero: Número de póliza
	 * @return Póliza sin insertar
	 */
	static InsurancePolicy poliza(Id cuenta, String numero) {
		String etapa = 'Prospecting';
		for (OpportunityStage s : [
			SELECT MasterLabel FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1
		]) { etapa = s.MasterLabel; }
		Opportunity opp = new Opportunity(Name = 'Opp ' + numero, AccountId = cuenta, StageName = etapa,
			CloseDate = Date.today().addDays(30));
		for (Schema.PicklistEntry pe : Opportunity.Ramo__c.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { opp.Ramo__c = pe.getValue(); break; }
		}
		insert opp;
		InsurancePolicy p = new InsurancePolicy(Name = numero, NameInsuredId = cuenta, Status = 'Inicial', Ramo__c = 'GMM',
			PremiumAmount = 1000, PaymentDueDate = Date.today().addDays(30), SourceOpportunityId = opp.Id,
			EffectiveDate = Datetime.now().addDays(-10), ExpirationDate = Datetime.now().addDays(355));
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { p.PremiumFrequency = pe.getValue(); break; }
		}
		return p;
	}

	static String rolAsegurado() {
		for (Schema.PicklistEntry pe : InsurancePolicyParticipant.Role.getDescribe().getPicklistValues()) {
			if (pe.getValue().toLowerCase().contains('asegurado')) { return pe.getValue(); }
		}
		return InsurancePolicyParticipant.Role.getDescribe().getPicklistValues()[0].getValue();
	}

	static Object ejecutar(Id policyId, String accion, Map<String, Object> params) {
		return PortalPolizasMovimientos.ejecutar(policyId, null, accion, JSON.serialize(params));
	}

	static String error(Id policyId, String accion, Map<String, Object> params) {
		try {
			ejecutar(policyId, accion, params);
			return null;
		} catch (AuraHandledException e) {
			return e.getMessage();
		}
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: El contratante consulta endosos, descarga el documento de un endoso, sube un archivo a la póliza y
	 * busca a un asegurado en otras pólizas (solo ve las suyas). Se rechazan registros de otra póliza, acciones que no
	 * existen, pólizas ajenas y los movimientos de quien no es el contratante.
	 * @return void
	 */
	@isTest
	static void testAccionesDelSitio() {
		Account empresa = new Account(Name = 'Empresa Movimientos');
		Account otra = new Account(Name = 'Otra Movimientos');
		insert new List<Account>{ empresa, otra };
		Contact empleado = new Contact(LastName = 'Empleado', AccountId = empresa.Id);
		insert empleado;
		InsurancePolicy pol = poliza(empresa.Id, 'MOV-001');
		InsurancePolicy anterior = poliza(empresa.Id, 'MOV-000');
		InsurancePolicy ajena = poliza(otra.Id, 'MOV-999');
		insert new List<InsurancePolicy>{ pol, anterior, ajena };
		String rol = rolAsegurado();
		InsurancePolicyParticipant titular = new InsurancePolicyParticipant(InsurancePolicyId = pol.Id,
			PrimaryParticipantContactId = empleado.Id, Role = rol, ParticipantCode = '1', IsActiveParticipant = true);
		InsurancePolicyParticipant enAnterior = new InsurancePolicyParticipant(InsurancePolicyId = anterior.Id,
			PrimaryParticipantContactId = empleado.Id, Role = rol, ParticipantCode = '1', IsActiveParticipant = true);
		InsurancePolicyParticipant enAjena = new InsurancePolicyParticipant(InsurancePolicyId = ajena.Id,
			PrimaryParticipantContactId = empleado.Id, Role = rol, ParticipantCode = '1', IsActiveParticipant = true);
		insert new List<InsurancePolicyParticipant>{ titular, enAnterior, enAjena };
		InsurancePolicyTransaction endoso = new InsurancePolicyTransaction(InsurancePolicyId = pol.Id,
			Name = 'Endoso A0001 - MOV-001', TransactionNumber = 'A0001', Category = 'Endorsement',
			EffectiveFromDate = Date.today().addDays(-3));
		insert endoso;
		ContentVersion cv = new ContentVersion(Title = 'Endoso A0001', PathOnClient = 'Endoso A0001.pdf',
			VersionData = Blob.valueOf('pdf'), FirstPublishLocationId = endoso.Id);
		insert cv;
		Id documentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
		PortalPolizasController.cuentaPrueba = empresa.Id;

		Test.startTest();
		List<Object> endosos = (List<Object>) ejecutar(pol.Id, 'EndosoPoliza.getEndosos', new Map<String, Object>());
		Map<String, Object> doc = (Map<String, Object>) ejecutar(pol.Id, 'Documento.descargar',
			new Map<String, Object>{ 'documentId' => documentId });
		Id subido = (Id) ejecutar(pol.Id, 'MovimientosColectivo.subirArchivo',
			new Map<String, Object>{ 'recordId' => pol.Id, 'nombre' => 'lista.xlsx', 'base64' => EncodingUtil.base64Encode(Blob.valueOf('x')) });
		Map<String, Object> otras = (Map<String, Object>) ejecutar(pol.Id, 'OtrasPolizas.buscar',
			new Map<String, Object>{ 'registroId' => titular.Id, 'contextoId' => pol.Id });
		// Archivos del asegurado: se adjunta a su contacto, se lista y se descarga.
		Id archivoAsegurado = (Id) ejecutar(pol.Id, 'Archivos.subir', new Map<String, Object>{ 'participanteId' => titular.Id,
			'nombre' => 'ine.pdf', 'base64' => EncodingUtil.base64Encode(Blob.valueOf('ine')) });
		Map<String, Object> deAsegurado = (Map<String, Object>) ejecutar(pol.Id, 'MovimientosColectivo.archivosAsegurado',
			new Map<String, Object>{ 'registroId' => titular.Id });
		Map<String, Object> descargaAsegurado = (Map<String, Object>) ejecutar(pol.Id, 'Documento.descargar',
			new Map<String, Object>{ 'documentId' => archivoAsegurado, 'participanteId' => titular.Id });
		String archivoAjeno = error(pol.Id, 'Documento.descargar',
			new Map<String, Object>{ 'documentId' => documentId, 'participanteId' => titular.Id });
		String deOtraPoliza = error(pol.Id, 'MovimientosColectivo.subirDocumentoBaja',
			new Map<String, Object>{ 'participanteId' => enAjena.Id, 'nombre' => 'baja.pdf', 'base64' => 'eA==' });
		String noExiste = error(pol.Id, 'Otra.accion', new Map<String, Object>());
		String polizaAjena = error(ajena.Id, 'EndosoPoliza.getEndosos', new Map<String, Object>());
		// Recorre las demás acciones con datos vacíos: el controlador de Salesforce responde (o rechaza) igual que allá.
		for (String accion : new List<String>{ 'MovimientosColectivo.aplicar', 'MovimientosColectivo.compararArchivo',
			'MovimientosFlotilla.aplicar', 'MovimientosFlotilla.compararArchivo', 'MovimientosUbicaciones.aplicar',
			'MovimientosColectivo.cerrarMovimiento', 'EndosoPoliza.registrarEndoso', 'CensoColectivo.analizarCensoPdf',
			'Flotilla.analizarFlotillaPdf' }) {
			try { ejecutar(pol.Id, accion, new Map<String, Object>()); } catch (Exception e) { System.debug(accion + ': ' + e.getMessage()); }
		}
		// Quien no es el contratante (un empleado asegurado) no puede registrar movimientos.
		PortalPolizasController.cuentaPrueba = null;
		PortalPolizasController.contactoPrueba = empleado.Id;
		String noContratante = error(pol.Id, 'MovimientosColectivo.aplicar', new Map<String, Object>{ 'movimientosJson' => '[]' });
		Test.stopTest();

		System.assertNotEquals(null, endosos);
		System.assertEquals('Endoso A0001.pdf', doc.get('nombre'));
		System.assertEquals('application/pdf', doc.get('mime'));
		System.assertEquals(EncodingUtil.base64Encode(Blob.valueOf('pdf')), doc.get('base64'));
		System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :pol.Id AND ContentDocumentId = :subido]);
		for (Object o : (List<Object>) otras.get('polizas')) {
			System.assertNotEquals(ajena.Id, (Id) ((Map<String, Object>) o).get('polizaId'), 'No muestra pólizas de otros clientes');
		}
		System.assertEquals(true, otras.get('portal'));
		System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :empleado.Id AND ContentDocumentId = :archivoAsegurado],
			'El archivo va al contacto del asegurado');
		System.assertEquals(1, ((List<Object>) deAsegurado.get('archivos')).size());
		System.assertEquals('ine.pdf', descargaAsegurado.get('nombre'));
		System.assertEquals('El documento no existe o no tienes acceso a él.', archivoAjeno, 'Solo archivos de ese asegurado');
		System.assertEquals('El registro no es de esta póliza.', deOtraPoliza);
		System.assertEquals('Acción no disponible en el sitio.', noExiste);
		System.assertNotEquals(null, polizaAjena, 'Rechaza una póliza ajena');
		System.assertEquals('Solo el contratante de la póliza puede registrar movimientos.', noContratante);
	}
}
