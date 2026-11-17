/**
 * @creation date: 14/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas unitarias de PortalPolizasPestanas.
 */
@isTest
private class PortalPolizasPestanasTest {

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma una póliza de prueba con los datos que exige la validación del org.
	 * @param cuenta: Id de la cuenta asegurada
	 * @param numero: Número de póliza
	 * @param ramo: Valor del ramo
	 * @return Póliza sin insertar
	 */
	static InsurancePolicy poliza(Id cuenta, String numero, String ramo) {
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
		InsurancePolicy p = new InsurancePolicy(Name = numero, NameInsuredId = cuenta, Status = 'Inicial', Ramo__c = ramo,
			PremiumAmount = 1000, PaymentDueDate = Date.today().addDays(30), SourceOpportunityId = opp.Id,
			EffectiveDate = Datetime.now().addDays(-10), ExpirationDate = Datetime.now().addDays(355), Primer_Pago__c = 250);
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { p.PremiumFrequency = pe.getValue(); break; }
		}
		return p;
	}

	static String rol(String contiene) {
		for (Schema.PicklistEntry pe : InsurancePolicyParticipant.Role.getDescribe().getPicklistValues()) {
			if (pe.getValue().toLowerCase().contains(contiene)) { return pe.getValue(); }
		}
		return InsurancePolicyParticipant.Role.getDescribe().getPicklistValues()[0].getValue();
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Información, Pagos y Vigencias de una póliza del titular: secciones con datos, cuotas sin las
	 * reemplazadas y la cadena de renovaciones; una póliza ajena se rechaza.
	 * @return void
	 */
	@isTest
	static void testInformacionPagosVigencias() {
		Account mia = new Account(Name = 'Cliente Pestañas');
		Account otra = new Account(Name = 'Otra Pestañas');
		insert new List<Account>{ mia, otra };
		InsurancePolicy anterior = poliza(mia.Id, 'PEST-001', 'GMM');
		insert anterior;
		InsurancePolicy actual = poliza(mia.Id, 'PEST-002', 'GMM');
		actual.PriorPolicyId = anterior.Id;
		InsurancePolicy ajena = poliza(otra.Id, 'PEST-003', 'GMM');
		insert new List<InsurancePolicy>{ actual, ajena };

		PaymentPlan__c plan = new PaymentPlan__c(insurancePolicy__c = actual.Id, planStatus__c = 'Cancelado',
			premiumFrequency__c = 'Mensual', expectedTotalAmount__c = 1200, firstDueDate__c = Date.today());
		insert plan;
		PaymentPlanInstallment__c vieja = new PaymentPlanInstallment__c(paymentPlan__c = plan.Id, sequenceNumber__c = 9,
			dueDate__c = Date.today(), expectedAmount__c = 500, installmentStatus__c = 'Pendiente');
		insert vieja;
		insert new PaymentPlanInstallment__c(paymentPlan__c = plan.Id, sequenceNumber__c = 9, dueDate__c = Date.today(),
			expectedAmount__c = 500, installmentStatus__c = 'Pendiente', replacesInstallment__c = vieja.Id,
			carrierReceiptNumber__c = 'R-9');

		PortalPolizasController.cuentaPrueba = mia.Id;

		Test.startTest();
		PortalPolizasPestanas.Informacion info = PortalPolizasPestanas.informacion(actual.Id, null);
		PortalPolizasPestanas.Pagos pagos = PortalPolizasPestanas.pagos(actual.Id, null);
		PortalPolizasPestanas.Vigencias vig = PortalPolizasPestanas.vigencias(actual.Id, null);
		Boolean rechazada = false;
		try {
			PortalPolizasPestanas.informacion(ajena.Id, null);
		} catch (AuraHandledException e) {
			rechazada = true;
		}
		Test.stopTest();

		System.assert(!info.secciones.isEmpty());
		System.assertEquals('Detalles de la póliza', info.secciones[0].titulo);
		Boolean hayPrimerPago = false;
		for (PortalPolizasPestanas.Seccion s : info.secciones) {
			for (PortalPolizasPestanas.Campo c : s.campos) {
				if (c.etiqueta == 'Primer pago') { hayPrimerPago = c.numero == 250 && c.tipo == 'moneda'; }
			}
		}
		System.assert(hayPrimerPago, 'Debe mostrar el primer pago como moneda');

		PortalPolizasPestanas.Cuota nueva;
		for (PortalPolizasPestanas.Cuota q : pagos.cuotas) {
			System.assertNotEquals(vieja.Id, q.id, 'La cuota reemplazada no se lista');
			if (q.recibo == 'R-9') { nueva = q; }
		}
		System.assertNotEquals(null, nueva);
		System.assertEquals('Cuota 9', nueva.etiqueta);
		System.assertEquals(1, nueva.recibosReemplazados);

		System.assertEquals(2, vig.vigencias.size());
		System.assertEquals(true, vig.vigencias[0].actual);
		System.assertEquals('Renumerada · antes PEST-001', vig.vigencias[0].renovacion);
		System.assertEquals('Primera registrada', vig.vigencias[1].renovacion);
		System.assert(rechazada, 'No debe entregar pestañas de una póliza ajena');
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Personas: el contratante ve a todos, titular seguido de sus dependientes, y Participantes
	 * incluye al beneficiario; un asegurado (por contacto) solo ve a su grupo.
	 * @return void
	 */
	@isTest
	static void testAseguradosYParticipantes() {
		Account empresa = new Account(Name = 'Empresa Colectivo');
		insert empresa;
		Contact empleado = new Contact(LastName = 'Empleado', AccountId = empresa.Id);
		Contact otroEmpleado = new Contact(LastName = 'Otro', AccountId = empresa.Id);
		insert new List<Contact>{ empleado, otroEmpleado };
		InsurancePolicy col = poliza(empresa.Id, 'COL-001', 'GMM');
		insert col;
		String rolAsegurado = rol('asegurado');
		InsurancePolicyParticipant titular = new InsurancePolicyParticipant(InsurancePolicyId = col.Id,
			PrimaryParticipantContactId = empleado.Id, Role = rolAsegurado, ParticipantCode = '1', IsActiveParticipant = true);
		InsurancePolicyParticipant otro = new InsurancePolicyParticipant(InsurancePolicyId = col.Id,
			PrimaryParticipantContactId = otroEmpleado.Id, Role = rolAsegurado, ParticipantCode = '2', IsActiveParticipant = true);
		insert new List<InsurancePolicyParticipant>{ titular, otro };
		insert new List<InsurancePolicyParticipant>{
			new InsurancePolicyParticipant(InsurancePolicyId = col.Id, PrimaryParticipantContactId = empleado.Id,
				Role = rolAsegurado, ParticipantCode = '1-1', RelatedInsPolicyParticipantId = titular.Id, IsActiveParticipant = true),
			new InsurancePolicyParticipant(InsurancePolicyId = col.Id, PrimaryParticipantContactId = otroEmpleado.Id,
				Role = rol('benefic'), RelatedInsPolicyParticipantId = otro.Id, BeneficiarySharePercentage = 100,
				IsActiveParticipant = true)
		};

		Test.startTest();
		PortalPolizasController.cuentaPrueba = empresa.Id;
		PortalPolizasPestanas.Bienes todos = PortalPolizasPestanas.asegurados(col.Id, null);
		PortalPolizasPestanas.Bienes partTodos = PortalPolizasPestanas.participantes(col.Id, null);

		// Un empleado sin la cuenta de la empresa: es participante, no contratante.
		PortalPolizasController.cuentaPrueba = null;
		PortalPolizasController.contactoPrueba = otroEmpleado.Id;
		PortalPolizasPestanas.Bienes suyos = PortalPolizasPestanas.asegurados(col.Id, null);
		Test.stopTest();

		System.assertEquals('personas', todos.tipo);
		System.assertEquals(false, todos.soloMiGrupo);
		System.assertEquals(3, todos.filas.size(), 'El beneficiario no es asegurado');
		System.assertEquals('Titular', todos.filas[0].parentesco);
		System.assertEquals(true, todos.filas[1].dependiente, 'El dependiente va debajo de su titular');
		System.assertEquals(4, partTodos.filas.size());
		Boolean hayBeneficiario = false;
		for (PortalPolizasPestanas.Fila f : partTodos.filas) {
			if (f.porcentaje == 100) { hayBeneficiario = true; }
		}
		System.assert(hayBeneficiario);
		System.assertEquals(true, suyos.soloMiGrupo);
		System.assertEquals(1, suyos.filas.size(), 'Solo se ve a sí mismo (su beneficiario no es asegurado)');
		System.assertEquals('2', suyos.filas[0].clave);
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Vehículos y ubicaciones: incisos de la flotilla y bienes ordenados por inciso; Participantes
	 * no aplica en esos ramos.
	 * @return void
	 */
	@isTest
	static void testVehiculosYUbicaciones() {
		Account cliente = new Account(Name = 'Cliente Bienes');
		insert cliente;
		InsurancePolicy auto = poliza(cliente.Id, 'AUTO-001', 'Automoviles');
		InsurancePolicy danos = poliza(cliente.Id, 'DANOS-001', 'Danos');
		insert new List<InsurancePolicy>{ auto, danos };
		insert new Inciso_Flotilla__c(Poliza__c = auto.Id, Numero_Inciso__c = 1, Descripcion__c = 'Sedán', Placas__c = 'ABC123',
			Modelo__c = 2024, Prima__c = 300);
		insert new List<InsurancePolicyAsset>{
			new InsurancePolicyAsset(InsurancePolicyId = danos.Id, AssetName = 'Inciso 2 - Bodega'),
			new InsurancePolicyAsset(InsurancePolicyId = danos.Id, AssetName = 'Inciso 1 - Oficina')
		};
		PortalPolizasController.cuentaPrueba = cliente.Id;

		Test.startTest();
		PortalPolizasPestanas.Bienes vehiculos = PortalPolizasPestanas.asegurados(auto.Id, null);
		PortalPolizasPestanas.Bienes ubicaciones = PortalPolizasPestanas.asegurados(danos.Id, null);
		PortalPolizasPestanas.Bienes partAuto = PortalPolizasPestanas.participantes(auto.Id, null);
		Test.stopTest();

		System.assertEquals('vehiculos', vehiculos.tipo);
		System.assertEquals(1, vehiculos.filas.size());
		System.assertEquals('Sedán', vehiculos.filas[0].nombre);
		System.assert(vehiculos.filas[0].detalle.contains('Placas ABC123'));
		System.assertEquals('ubicaciones', ubicaciones.tipo);
		System.assertEquals('1', ubicaciones.filas[0].clave);
		System.assertEquals('2', ubicaciones.filas[1].clave);
		System.assertEquals('vehiculos', partAuto.tipo);
		System.assertEquals(0, partAuto.filas.size());
		System.assertEquals('personas', PortalPolizasPestanas.tipoRamo(null));
		System.assertEquals('ubicaciones', PortalPolizasPestanas.tipoRamo('Empresarial'));
	}

	/**
	 * @creation date: 17/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Solicitudes de movimientos del sitio: el contratante envía un alta y una baja con un archivo; se crea
	 * el caso «Solicitud de movimientos» con el folio SOL-0001, ligado a la póliza, y aparece como Recibida. Se validan
	 * los datos; quien no es el contratante no puede enviar. Al rechazarla, el cliente ve el motivo.
	 * @return void
	 */
	@isTest
	static void testSolicitudesDelSitio() {
		Account empresa = new Account(Name = 'Empresa Solicitudes');
		insert empresa;
		Contact empleado = new Contact(LastName = 'Empleado', AccountId = empresa.Id);
		insert empleado;
		InsurancePolicy col = poliza(empresa.Id, 'COL-SOL-1', 'GMM');
		insert col;
		InsurancePolicyParticipant titular = new InsurancePolicyParticipant(InsurancePolicyId = col.Id,
			PrimaryParticipantContactId = empleado.Id, Role = rol('asegurado'), ParticipantCode = '1', IsActiveParticipant = true);
		insert titular;
		PortalPolizasController.cuentaPrueba = empresa.Id;
		PortalPolizasController.contactoPrueba = null;

		Map<String, Object> alta = new Map<String, Object>{ 'tipo' => 'alta', 'fecha' => '2026-12-01', 'datos' => new List<Object>{
			new Map<String, Object>{ 'etiqueta' => 'Nombre(s)', 'valor' => 'Ana' },
			new Map<String, Object>{ 'etiqueta' => 'Apellido paterno', 'valor' => 'Ruiz' } } };
		Map<String, Object> baja = new Map<String, Object>{ 'tipo' => 'baja', 'registroId' => titular.Id, 'detalle' => 'Renuncia' };
		Test.startTest();
		Map<String, Object> r = PortalPolizasPestanas.crearSolicitud(col.Id, JSON.serialize(new Map<String, Object>{
			'movimientos' => new List<Object>{ alta, baja }, 'comentario' => 'Urgente',
			'archivos' => new List<Object>{ new Map<String, Object>{ 'nombre' => 'altas.xlsx', 'base64' => EncodingUtil.base64Encode(Blob.valueOf('x')) } }
		}));
		Integer errores = 0;
		for (Object m : new List<Object>{
			new List<Object>(),
			new List<Object>{ new Map<String, Object>{ 'tipo' => 'cambio', 'registroId' => titular.Id } },
			new List<Object>{ new Map<String, Object>{ 'tipo' => 'baja' } },
			new List<Object>{ new Map<String, Object>{ 'tipo' => 'alta' } }
		}) {
			try { PortalPolizasPestanas.crearSolicitud(col.Id, JSON.serialize(new Map<String, Object>{ 'movimientos' => m })); }
			catch (AuraHandledException e) { errores++; }
		}
		Map<String, Object> vista = PortalPolizasPestanas.solicitudes(col.Id, null);
		Test.stopTest();

		System.assertEquals('SOL-0001', r.get('folio'));
		Case c = [SELECT RecordType.DeveloperName, InsurancePolicy__c, Solicitud__c, Origin, AccountId, Description, IsClosed FROM Case WHERE InsurancePolicy__c = :col.Id];
		System.assertEquals('Solicitud_Movimientos', c.RecordType.DeveloperName);
		System.assertEquals('SOL-0001', c.Solicitud__c);
		System.assertEquals('Sitio Web', c.Origin);
		System.assertEquals(empresa.Id, c.AccountId);
		System.assert(c.Description.contains('1. ALTA') && c.Description.contains('2. BAJA · 1 · ') && c.Description.contains('Motivo: Renuncia'), c.Description);
		System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :c.Id], 'El archivo queda en el caso');
		System.assertEquals(4, errores, 'Sin movimientos, cambio sin detalle, baja sin registro y alta sin datos no son válidos');
		System.assertEquals(true, vista.get('puedeSolicitar'));
		System.assertEquals(1, ((List<Object>) vista.get('registros')).size());
		List<Object> sols = (List<Object>) vista.get('solicitudes');
		System.assertEquals(1, sols.size());
		System.assertEquals('Recibida', ((Map<String, Object>) sols[0]).get('estado'));
		System.assertEquals(1, ((Map<String, Object>) sols[0]).get('documentos'));

		// Rechazo del ejecutivo: el cliente ve el motivo.
		EndosoPoliza.rechazarSolicitud(c.Id, 'Falta el acta de nacimiento');
		Map<String, Object> s = (Map<String, Object>) ((List<Object>) PortalPolizasPestanas.solicitudes(col.Id, null).get('solicitudes'))[0];
		System.assertEquals('Rechazada', s.get('estado'));
		System.assert(String.valueOf(s.get('respuesta')).contains('Falta el acta'), s.get('respuesta'));

		// Quien no es el contratante no envía solicitudes.
		PortalPolizasController.cuentaPrueba = null;
		PortalPolizasController.contactoPrueba = empleado.Id;
		Boolean bloqueado = false;
		try { PortalPolizasPestanas.crearSolicitud(col.Id, JSON.serialize(new Map<String, Object>{ 'movimientos' => new List<Object>{ alta } })); }
		catch (AuraHandledException e) { bloqueado = true; }
		System.assert(bloqueado, 'Solo el contratante');
		System.assertEquals(false, PortalPolizasPestanas.solicitudes(col.Id, null).get('puedeSolicitar'));
	}
}
