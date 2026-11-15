/**
 * @creation date: 14/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas unitarias de PortalPolizasController.
 */
@isTest
private class PortalPolizasControllerTest {

	/**
	 * @creation date: 14/11/2026
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
		InsurancePolicy p = new InsurancePolicy(Name = numero, NameInsuredId = cuenta, Status = 'Inicial',
			PremiumAmount = 1000, PaymentDueDate = Date.today().addDays(30), SourceOpportunityId = opp.Id,
			EffectiveDate = Datetime.now().addDays(-10), ExpirationDate = Datetime.now().addDays(355));
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { p.PremiumFrequency = pe.getValue(); break; }
		}
		return p;
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: El usuario ve las pólizas donde su cuenta es titular y donde su contacto es participante,
	 * y no ve las de otra cuenta; el detalle solo se entrega para sus pólizas.
	 * @return void
	 */
	@isTest
	static void testSoloVeSusPolizas() {
		Account mia = new Account(Name = 'Cliente Portal');
		Account otra = new Account(Name = 'Otro Cliente');
		insert new List<Account>{ mia, otra };
		Contact yo = new Contact(LastName = 'Portal', AccountId = mia.Id);
		insert yo;

		InsurancePolicy titular = poliza(mia.Id, 'PORTAL-001');
		InsurancePolicy colectiva = poliza(otra.Id, 'PORTAL-002');
		InsurancePolicy ajena = poliza(otra.Id, 'PORTAL-003');
		insert new List<InsurancePolicy>{ titular, colectiva, ajena };
		insert new InsurancePolicyParticipant(InsurancePolicyId = colectiva.Id, PrimaryParticipantContactId = yo.Id,
			IsActiveParticipant = true, Role = InsurancePolicyParticipant.Role.getDescribe().getPicklistValues()[0].getValue());

		ContentVersion cv = new ContentVersion(Title = 'Caratula', PathOnClient = 'caratula.pdf',
			VersionData = Blob.valueOf('pdf'));
		insert cv;
		Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
		insert new ContentDocumentLink(ContentDocumentId = docId, LinkedEntityId = titular.Id,
			ShareType = 'V', Visibility = 'AllUsers');

		PortalPolizasController.cuentaPrueba = mia.Id;
		PortalPolizasController.contactoPrueba = yo.Id;

		Test.startTest();
		List<PortalPolizasController.Poliza> lista = PortalPolizasController.misPolizas(null);
		PortalPolizasController.Detalle d = PortalPolizasController.detallePoliza(titular.Id, null);
		Boolean bloqueada = false;
		try {
			PortalPolizasController.detallePoliza(ajena.Id, null);
		} catch (AuraHandledException e) {
			bloqueada = true;
		}
		PortalPolizasController.Archivo archivo = PortalPolizasController.descargarDocumento(titular.Id, docId, null);
		Boolean archivoBloqueado = false;
		try {
			// El archivo no está ligado a la póliza colectiva aunque esa póliza sí sea del usuario.
			PortalPolizasController.descargarDocumento(colectiva.Id, docId, null);
		} catch (AuraHandledException e) {
			archivoBloqueado = true;
		}
		Test.stopTest();

		System.assertEquals('Caratula.pdf', archivo.nombre);
		System.assertEquals(EncodingUtil.base64Encode(Blob.valueOf('pdf')), archivo.base64);
		System.assert(archivoBloqueado, 'Solo entrega archivos ligados a la póliza indicada');

		Set<String> numeros = new Set<String>();
		for (PortalPolizasController.Poliza p : lista) { numeros.add(p.numero); }
		System.assertEquals(new Set<String>{ 'PORTAL-001', 'PORTAL-002' }, numeros);
		System.assertEquals('Titular', d.poliza.miRol);
		System.assertEquals(1, d.documentos.size());
		System.assertEquals('Caratula', d.documentos[0].titulo);
		System.assert(bloqueada, 'No debe entregar el detalle de una póliza ajena');
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Un usuario sin cuenta ni contacto (interno) no ve pólizas.
	 * @return void
	 */
	@isTest
	static void testSinCuentaNoVeNada() {
		Test.startTest();
		System.assertEquals(0, PortalPolizasController.misPolizas(null).size());
		Test.stopTest();
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Con el permiso, el administrador busca una cuenta y ve sus pólizas; sin el permiso se rechaza.
	 * @return void
	 */
	@isTest
	static void testVistaPrevia() {
		Account cliente = new Account(Name = 'Cliente Vista Previa');
		insert cliente;
		InsurancePolicy p = poliza(cliente.Id, 'PREVIA-001');
		insert p;

		Test.startTest();
		PortalPolizasController.permisoVistaPreviaPrueba = true;
		Boolean puede = PortalPolizasController.puedeVistaPrevia();
		List<PortalPolizasController.Cuenta> cuentas = PortalPolizasController.buscarCuentas('Vista Previa');
		List<PortalPolizasController.Poliza> lista = PortalPolizasController.misPolizas(cliente.Id);
		PortalPolizasController.Detalle d = PortalPolizasController.detallePoliza(p.Id, cliente.Id);
		Integer cortas = PortalPolizasController.buscarCuentas('V').size();

		PortalPolizasController.permisoVistaPreviaPrueba = false;
		Boolean rechazada = false;
		try {
			PortalPolizasController.misPolizas(cliente.Id);
		} catch (AuraHandledException e) {
			rechazada = true;
		}
		Boolean busquedaRechazada = false;
		try {
			PortalPolizasController.buscarCuentas('Vista');
		} catch (AuraHandledException e) {
			busquedaRechazada = true;
		}
		Test.stopTest();

		System.assert(puede);
		System.assertEquals(1, cuentas.size());
		System.assertEquals(cliente.Id, cuentas[0].id);
		System.assertEquals(1, cuentas[0].polizas);
		System.assertEquals(1, lista.size());
		System.assertEquals('PREVIA-001', d.poliza.numero);
		System.assertEquals(0, cortas);
		System.assert(rechazada, 'Sin permiso no se puede simular otra cuenta');
		System.assert(busquedaRechazada, 'Sin permiso no se pueden buscar cuentas');
	}
}
