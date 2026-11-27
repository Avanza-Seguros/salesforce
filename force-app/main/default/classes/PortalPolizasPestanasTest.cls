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
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Pestañas del sitio con los componentes de Salesforce: el contratante recibe los datos completos de
	 * asegurados y participantes (sin archivos ni solicitudes); un empleado solo ve a su grupo; vehículos y ubicaciones
	 * responden; una pestaña inválida o una póliza ajena se rechazan.
	 * @return void
	 */
	@isTest
	static void testDatosComponente() {
		Account empresa = new Account(Name = 'Empresa Componentes');
		Account ajenaCta = new Account(Name = 'Ajena Componentes');
		insert new List<Account>{ empresa, ajenaCta };
		Contact empleado = new Contact(LastName = 'Empleado', AccountId = empresa.Id);
		Contact otroEmpleado = new Contact(LastName = 'Otro', AccountId = empresa.Id);
		insert new List<Contact>{ empleado, otroEmpleado };
		InsurancePolicy col = poliza(empresa.Id, 'COMP-001', 'GMM');
		InsurancePolicy auto = poliza(empresa.Id, 'COMP-002', 'Automoviles');
		InsurancePolicy danos = poliza(empresa.Id, 'COMP-003', 'Danos');
		InsurancePolicy ajena = poliza(ajenaCta.Id, 'COMP-004', 'GMM');
		insert new List<InsurancePolicy>{ col, auto, danos, ajena };
		String rolAsegurado = rol('asegurado');
		insert new List<InsurancePolicyParticipant>{
			new InsurancePolicyParticipant(InsurancePolicyId = col.Id, PrimaryParticipantContactId = empleado.Id,
				Role = rolAsegurado, ParticipantCode = '1', IsActiveParticipant = true),
			new InsurancePolicyParticipant(InsurancePolicyId = col.Id, PrimaryParticipantContactId = otroEmpleado.Id,
				Role = rolAsegurado, ParticipantCode = '2', IsActiveParticipant = true)
		};

		Test.startTest();
		PortalPolizasController.cuentaPrueba = empresa.Id;
		Map<String, Object> aseg = PortalPolizasPestanas.datosComponente(col.Id, null, 'asegurados');
		Map<String, Object> part = PortalPolizasPestanas.datosComponente(col.Id, null, 'participantes');
		Map<String, Object> veh = PortalPolizasPestanas.datosComponente(auto.Id, null, 'vehiculos');
		Map<String, Object> ubi = PortalPolizasPestanas.datosComponente(danos.Id, null, 'ubicaciones');
		Boolean invalida = false;
		try {
			PortalPolizasPestanas.datosComponente(col.Id, null, 'otra');
		} catch (AuraHandledException e) {
			invalida = true;
		}
		Boolean rechazada = false;
		try {
			PortalPolizasPestanas.datosComponente(ajena.Id, null, 'asegurados');
		} catch (AuraHandledException e) {
			rechazada = true;
		}

		PortalPolizasController.cuentaPrueba = null;
		PortalPolizasController.contactoPrueba = otroEmpleado.Id;
		Map<String, Object> asegSuyos = PortalPolizasPestanas.datosComponente(col.Id, null, 'asegurados');
		Map<String, Object> partSuyos = PortalPolizasPestanas.datosComponente(col.Id, null, 'participantes');
		Test.stopTest();

		System.assertEquals(false, aseg.get('soloMiGrupo'));
		System.assertEquals(true, aseg.get('portal'));
		System.assertEquals(true, aseg.get('puedeSolicitar'), 'Contratante de una póliza empresarial: Nueva solicitud');
		System.assertEquals(false, asegSuyos.get('puedeSolicitar'), 'Un empleado no envía solicitudes');
		// Al contratante le llegan las solicitudes para agrupar (sin datos internos del caso); a un empleado, ninguna.
		System.assertEquals(0, ((List<Object>) asegSuyos.get('solicitudes')).size(), 'Un empleado no ve las solicitudes');
		List<Object> agrupar = PortalPolizasPestanas.solicitudesParaAgrupar(new List<Object>{ new Map<String, Object>{
			'folio' => 'SOL-0001', 'total' => 2, 'altas' => 2, 'casoId' => col.Id, 'descripcion' => 'interno', 'pendiente' => true } });
		Map<String, Object> sol = (Map<String, Object>) agrupar[0];
		System.assertEquals('SOL-0001', sol.get('folio'));
		System.assertEquals(2, sol.get('altas'));
		System.assertEquals(false, sol.get('pendiente'));
		System.assert(!sol.containsKey('casoId') && !sol.containsKey('descripcion'), 'Sin datos internos del caso');
		System.assertEquals(0, PortalPolizasPestanas.solicitudesParaAgrupar(null).size());
		System.assertEquals(2, ((List<Object>) aseg.get('miembros')).size());
		List<Object> participantes = (List<Object>) part.get('participantes');
		System.assert(!participantes.isEmpty());
		for (Object o : participantes) {
			System.assertEquals(0, ((List<Object>) ((Map<String, Object>) o).get('archivos')).size(), 'No tienen archivos');
		}
		System.assertNotEquals(null, veh);
		System.assertEquals(false, veh.get('soloMiGrupo'));
		System.assertNotEquals(null, ubi);
		System.assert(invalida, 'Pestaña no válida');
		System.assert(rechazada, 'No debe entregar datos de una póliza ajena');
		System.assertEquals(true, asegSuyos.get('soloMiGrupo'));
		System.assertEquals(1, ((List<Object>) asegSuyos.get('miembros')).size(), 'El empleado solo se ve a sí mismo');
		System.assertEquals(true, partSuyos.get('soloMiGrupo'));
		System.assert(((List<Object>) partSuyos.get('participantes')).size() < participantes.size());
	}

	/**
	 * @creation date: 17/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Solicitudes de movimientos del sitio: el contratante envía un alta y una baja con un archivo; se crea
	 * el caso «Solicitud de movimientos» con el folio SOL-0001, ligado a la póliza, y los movimientos quedan registrados
	 * en la póliza con ese folio (En proceso). Se validan los datos; quien no es el contratante no puede enviar. Una
	 * solicitud sin movimientos que registrar queda Recibida; al rechazarla, el cliente ve el motivo.
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
		Contact otro = new Contact(LastName = 'Otro empleado', AccountId = empresa.Id);
		insert otro;
		insert new InsurancePolicyParticipant(InsurancePolicyId = col.Id, PrimaryParticipantContactId = otro.Id, Role = rol('asegurado'),
			ParticipantCode = '2', IsActiveParticipant = true);
		PortalPolizasController.cuentaPrueba = empresa.Id;
		PortalPolizasController.contactoPrueba = null;

		Map<String, Object> alta = new Map<String, Object>{ 'tipo' => 'alta', 'fecha' => String.valueOf(Date.today()), 'datos' => new List<Object>{
			new Map<String, Object>{ 'etiqueta' => 'Nombre(s)', 'valor' => 'Ana' },
			new Map<String, Object>{ 'etiqueta' => 'Apellido paterno', 'valor' => 'Ruiz' } },
			'campos' => new Map<String, Object>{ 'nombre' => 'Ana', 'paterno' => 'Ruiz', 'nacimiento' => '1990-05-04', 'sexo' => 'Mujer',
				'parentesco' => 'Titular', 'categoria' => '00' } };
		Map<String, Object> baja = new Map<String, Object>{ 'tipo' => 'baja', 'registroId' => titular.Id, 'detalle' => 'Renuncia' };
		Test.startTest();
		Map<String, Object> r = PortalPolizasPestanas.crearSolicitud(col.Id, JSON.serialize(new Map<String, Object>{
			'movimientos' => new List<Object>{ alta, baja }, 'comentario' => 'Urgente',
			'archivos' => new List<Object>{ new Map<String, Object>{ 'nombre' => 'altas.xlsx', 'base64' => EncodingUtil.base64Encode(Blob.valueOf('x')) } }
		}), null);
		Integer errores = 0;
		for (Object m : new List<Object>{
			new List<Object>(),
			new List<Object>{ new Map<String, Object>{ 'tipo' => 'cambio', 'registroId' => titular.Id } },
			new List<Object>{ new Map<String, Object>{ 'tipo' => 'baja' } },
			new List<Object>{ new Map<String, Object>{ 'tipo' => 'alta' } }
		}) {
			try { PortalPolizasPestanas.crearSolicitud(col.Id, JSON.serialize(new Map<String, Object>{ 'movimientos' => m }), null); }
			catch (AuraHandledException e) { errores++; }
		}
		Map<String, Object> vista = PortalPolizasPestanas.solicitudes(col.Id, null);
		Test.stopTest();

		System.assertEquals('SOL-0001', r.get('folio'));
		Case c = [SELECT RecordType.DeveloperName, InsurancePolicy__c, Solicitud__c, Origin, AccountId, Description, Poliza_Number__c, IsClosed FROM Case WHERE InsurancePolicy__c = :col.Id];
		System.assertEquals('Solicitud_Movimientos', c.RecordType.DeveloperName);
		System.assertEquals('SOL-0001', c.Solicitud__c);
		System.assertEquals('Sitio Web', c.Origin);
		System.assertEquals(empresa.Id, c.AccountId);
		System.assertEquals('Solicitud SOL-0001 enviada desde el sitio por ' + UserInfo.getName() + ' para la póliza ' + col.Name + '.', c.Description);
		System.assertEquals(col.Name, c.Poliza_Number__c);
		System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :c.Id], 'El archivo queda en el caso');
		System.assertEquals(4, errores, 'Sin movimientos, cambio sin detalle, baja sin registro y alta sin datos no son válidos');
		System.assertEquals(2, r.get('registrados'));
		System.assertEquals(2, [SELECT COUNT() FROM Movimiento_Poliza__c WHERE Poliza__c = :col.Id AND Solicitud__c = 'SOL-0001'],
			'El alta y la baja quedan registradas con el folio');
		System.assertEquals(false, [SELECT IsActiveParticipant FROM InsurancePolicyParticipant WHERE Id = :titular.Id].IsActiveParticipant);
		System.assertEquals(true, vista.get('puedeSolicitar'));
		System.assertEquals(2, ((List<Object>) vista.get('registros')).size(), 'Vigentes: el otro asegurado y el alta (el titular se dio de baja)');
		List<Object> sols = (List<Object>) vista.get('solicitudes');
		System.assertEquals(1, sols.size());
		System.assertEquals('En proceso', ((Map<String, Object>) sols[0]).get('estado'));
		System.assertEquals(2, ((Map<String, Object>) sols[0]).get('aplicados'));
		System.assertEquals(1, ((Map<String, Object>) sols[0]).get('documentos'));

		// Quien no es el contratante no envía solicitudes.
		PortalPolizasController.cuentaPrueba = null;
		PortalPolizasController.contactoPrueba = empleado.Id;
		Boolean bloqueado = false;
		try { PortalPolizasPestanas.crearSolicitud(col.Id, JSON.serialize(new Map<String, Object>{ 'movimientos' => new List<Object>{ alta } }), null); }
		catch (AuraHandledException e) { bloqueado = true; }
		System.assert(bloqueado, 'Solo el contratante');
		// El empleado ya se dio de baja en la solicitud: o no ve la póliza o no puede solicitar.
		Boolean puede = false;
		try { puede = (Boolean) PortalPolizasPestanas.solicitudes(col.Id, null).get('puedeSolicitar'); } catch (AuraHandledException e) { puede = false; }
		System.assertEquals(false, puede);
	}

	/**
	 * @creation date: 17/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Solicitud del sitio con archivo de vehículos, enviada por un usuario del sitio (Partner Community, que
	 * no ve los registros de la póliza): el alta, la baja (por serie) y el cambio de placas (por inciso) quedan
	 * registrados en la flotilla con el folio. Un renglón que no corresponde a ningún vehículo vigente no deja nada
	 * (ni el caso) y el mensaje dice qué renglón es.
	 * @return void
	 */
	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cambio de nombre desde el archivo del sitio (nombre y apellidos por separado, por certificado): se
	 * corrige el apellido materno en el asegurado y en su contacto y queda el movimiento con el detalle. Si el archivo trae
	 * los mismos datos que ya tiene, se avisa en vez de crear una solicitud sin registros.
	 * @return void
	 */
	@isTest
	static void testCambioDeNombreDelArchivo() {
		Account empresa = new Account(Name = 'Empresa Cambio Nombre');
		insert empresa;
		Contact gaddi = new Contact(FirstName = 'GADDI AXEL', LastName = 'AGUIRRE LEDEZMA', AccountId = empresa.Id);
		Contact arturo = new Contact(FirstName = 'ARTURO ALFONSO', LastName = 'GONZALEZ GONZALEZ', AccountId = empresa.Id);
		insert new List<Contact>{ gaddi, arturo };
		InsurancePolicy col = poliza(empresa.Id, 'COL-NOMBRE-1', 'GMM');
		insert col;
		InsurancePolicyParticipant p1 = new InsurancePolicyParticipant(InsurancePolicyId = col.Id, PrimaryParticipantContactId = gaddi.Id,
			Role = rol('asegurado'), ParticipantName = 'GADDI AXEL AGUIRRE LEDEZMA', ParticipantCode = '0000095002', IsActiveParticipant = true);
		InsurancePolicyParticipant p2 = new InsurancePolicyParticipant(InsurancePolicyId = col.Id, PrimaryParticipantContactId = arturo.Id,
			Role = rol('asegurado'), ParticipantName = 'GONZALEZ GONZALEZ ARTURO ALFONSO', ParticipantCode = '0000095003', IsActiveParticipant = true);
		insert new List<InsurancePolicyParticipant>{ p1, p2 };
		PortalPolizasController.cuentaPrueba = empresa.Id;
		PortalPolizasController.contactoPrueba = null;
		String hoy = String.valueOf(Date.today());
		Map<String, Object> archivo = new Map<String, Object>{ 'tipo' => 'varios', 'nombre' => 'CAMBIOS.xlsx', 'total' => 2, 'filas' => new List<Object>(),
			'registros' => new List<Object>{
				new Map<String, Object>{ 'tipo' => 'cambio', 'fila' => 2, 'numero' => 1, 'nombre' => 'GADDI AXEL AGUIRRE LEDESMA', 'fecha' => hoy,
					'comentario' => 'CORRECCION DE APELLIDO MATERNO', 'campos' => new Map<String, Object>{ 'nombre' => 'GADDI AXEL', 'paterno' => 'AGUIRRE',
					'materno' => 'LEDESMA', 'parentesco' => 'TITULAR', 'certificado' => '0000095002' } },
				new Map<String, Object>{ 'tipo' => 'cambio', 'fila' => 3, 'numero' => 2, 'nombre' => 'ARTURO ALFONZO GONZALEZ GONZALEZ', 'fecha' => hoy,
					'campos' => new Map<String, Object>{ 'nombre' => 'ARTURO ALFONZO', 'paterno' => 'GONZALEZ', 'materno' => 'GONZALEZ',
					'certificado' => '0000095003' } }
			} };
		Test.startTest();
		Map<String, Object> r = PortalPolizasPestanas.crearSolicitud(col.Id, JSON.serialize(new Map<String, Object>{ 'listado' => archivo }), null);
		String error;
		try { PortalPolizasPestanas.crearSolicitud(col.Id, JSON.serialize(new Map<String, Object>{ 'listado' => archivo }), null); }
		catch (AuraHandledException e) { error = e.getMessage(); }
		Test.stopTest();

		System.assertEquals(2, r.get('registrados'), 'Los dos cambios de nombre quedan registrados');
		System.assertEquals('GADDI AXEL AGUIRRE LEDESMA', [SELECT ParticipantName FROM InsurancePolicyParticipant WHERE Id = :p1.Id].ParticipantName);
		System.assertEquals('GONZALEZ GONZALEZ ARTURO ALFONZO', [SELECT ParticipantName FROM InsurancePolicyParticipant WHERE Id = :p2.Id].ParticipantName,
			'Conserva el orden «apellidos nombres» que ya tenía');
		Contact c1 = [SELECT FirstName, LastName, Apellido_paterno__c, Apellido_materno__c FROM Contact WHERE Id = :gaddi.Id];
		System.assertEquals('AGUIRRE LEDESMA', c1.LastName);
		System.assertEquals('LEDESMA', c1.Apellido_materno__c);
		System.assertEquals('ARTURO ALFONZO', [SELECT FirstName FROM Contact WHERE Id = :arturo.Id].FirstName);
		Movimiento_Poliza__c m = [SELECT Detalle__c, Tipo__c FROM Movimiento_Poliza__c WHERE Participante__c = :p1.Id AND Tipo__c = 'Cambio' LIMIT 1];
		System.assertEquals('Apellido materno: LEDEZMA → LEDESMA', m.Detalle__c);
		System.assert(error != null && error.contains('los datos son iguales'), 'Los mismos datos otra vez: se avisa (' + error + ')');
		System.assertEquals(1, [SELECT COUNT() FROM Case WHERE InsurancePolicy__c = :col.Id], 'No queda una solicitud sin registros');
	}

	@isTest
	static void testSolicitudRegistraMovimientos() {
		User yo = [SELECT Id, UserRoleId FROM User WHERE Id = :UserInfo.getUserId()];
		if (yo.UserRoleId == null) {
			System.runAs(yo) {
				UserRole rolPrueba = new UserRole(Name = 'Rol prueba solicitudes');
				insert rolPrueba;
				yo.UserRoleId = rolPrueba.Id;
				update yo;
			}
		}
		Account cliente = new Account(Name = 'Cliente Flotilla Sitio');
		insert cliente;
		cliente.IsPartner = true;
		update cliente;
		Contact contacto = new Contact(LastName = 'Contratante', AccountId = cliente.Id, Email = 'contratante@prueba.test');
		insert contacto;
		InsurancePolicy auto = poliza(cliente.Id, 'FLOT-SITIO-1', 'Automoviles');
		insert auto;
		insert new List<Inciso_Flotilla__c>{
			new Inciso_Flotilla__c(Poliza__c = auto.Id, Numero_Inciso__c = 1, Descripcion__c = 'NISSAN VERSA', Serie__c = 'AAA111',
				Placas__c = 'ABC123', Modelo__c = 2020, Fecha_Alta__c = Date.today().addDays(-10)),
			new Inciso_Flotilla__c(Poliza__c = auto.Id, Numero_Inciso__c = 2, Descripcion__c = 'VW JETTA', Serie__c = 'BBB222',
				Placas__c = 'XYZ999', Modelo__c = 2021, Fecha_Alta__c = Date.today().addDays(-10))
		};
		User sitio;
		Boolean comoEnElSitio = EndosoPoliza.estadoCaso('Solicitado') == 'Solicitado';
		System.runAs(yo) {
			// Perfil y permiso de los usuarios del sitio de empresas (en DEV no hay estado «Solicitado» y una regla de los
			// casos no deja usar ese perfil: se usa otro, que no sube archivos).
			Profile perfil = comoEnElSitio ? [SELECT Id FROM Profile WHERE Name = 'Standard Partner Community' LIMIT 1]
				: [SELECT Id FROM Profile WHERE UserLicense.Name = 'Partner Community' ORDER BY Name LIMIT 1];
			for (Network red : [SELECT Id FROM Network WHERE Name = 'Avanza Empresas' LIMIT 1]) { PortalPolizasPestanas.redPrueba = red.Id; }
			sitio = new User(ProfileId = perfil.Id, ContactId = contacto.Id, LastName = 'Contratante', Alias = 'contsit',
				Email = 'contratante@prueba.test', Username = 'contratante.sitio.' + Datetime.now().getTime() + '@prueba.test',
				TimeZoneSidKey = 'America/Mexico_City', LocaleSidKey = 'es_MX', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'es');
			insert sitio;
			for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name = 'Portal_Polizas_Cliente' LIMIT 1]) {
				insert new PermissionSetAssignment(AssigneeId = sitio.Id, PermissionSetId = ps.Id);
			}
		}
		PortalPolizasController.cuentaPrueba = cliente.Id;
		PortalPolizasController.contactoPrueba = null;
		String hoy = String.valueOf(Date.today());
		Map<String, Object> archivo = new Map<String, Object>{ 'tipo' => 'varios', 'nombre' => 'FLOTILLA.xlsx', 'total' => 3,
			'encabezados' => new List<Object>{ 'MOVIMIENTO', 'INCISO', 'MODELO', 'MARCA', 'VERSION', 'SERIE', 'PLACAS' },
			'filas' => new List<Object>(),
			'registros' => new List<Object>{
				new Map<String, Object>{ 'tipo' => 'alta', 'fila' => 2, 'fecha' => hoy, 'campos' => new Map<String, Object>{
					'modelo' => '2014', 'marca' => 'TOYOTA', 'version' => 'YARIS CORE', 'serie' => 'JTDKT9D38ED585824', 'placas' => 'KXM-751-A' } },
				new Map<String, Object>{ 'tipo' => 'baja', 'fila' => 3, 'fecha' => hoy, 'comentario' => 'Venta', 'campos' => new Map<String, Object>{ 'serie' => 'aaa111' } },
				new Map<String, Object>{ 'tipo' => 'cambio', 'fila' => 4, 'fecha' => hoy, 'campos' => new Map<String, Object>{ 'inciso' => '2', 'placas' => 'NEW123' } }
			} };
		Map<String, Object> r;
		String error;
		Test.startTest();
		System.runAs(sitio) {
			((Map<String, Object>) ((List<Object>) archivo.get('registros'))[0]).put('numero', 1);
			r = PortalPolizasPestanas.crearSolicitud(auto.Id, JSON.serialize(new Map<String, Object>{ 'listado' => archivo }), null);
			// El usuario del sitio adjunta la factura al vehículo del alta.
			Map<String, Object> alta1 = (Map<String, Object>) ((List<Object>) r.get('movimientos'))[0];
			if (comoEnElSitio) {
				PortalPolizasPestanas.adjuntarDocumento(auto.Id, 'SOL-0001', (String) alta1.get('registroId'), 'Factura', 'f.pdf',
					EncodingUtil.base64Encode(Blob.valueOf('x')), null);
			}
			// Un renglón que no está en la póliza: no queda nada.
			archivo.put('registros', new List<Object>{
				new Map<String, Object>{ 'tipo' => 'alta', 'fila' => 4, 'campos' => new Map<String, Object>{ 'serie' => 'CCC333', 'descripcion' => 'KIA RIO' } },
				new Map<String, Object>{ 'tipo' => 'baja', 'fila' => 5, 'campos' => new Map<String, Object>{ 'serie' => 'NOEXISTE' } } });
			try { PortalPolizasPestanas.crearSolicitud(auto.Id, JSON.serialize(new Map<String, Object>{ 'listado' => archivo }), null); }
			catch (AuraHandledException e) { error = e.getMessage(); }
		}
		Test.stopTest();

		System.assertEquals('SOL-0001', r.get('folio'));
		System.assertEquals(3, r.get('registrados'));
		System.assertEquals(3, [SELECT COUNT() FROM Movimiento_Poliza__c WHERE Poliza__c = :auto.Id AND Solicitud__c = 'SOL-0001']);
		Inciso_Flotilla__c nuevo = [SELECT Descripcion__c, Modelo__c, Placas__c FROM Inciso_Flotilla__c WHERE Poliza__c = :auto.Id AND Serie__c = 'JTDKT9D38ED585824'];
		System.assert(nuevo.Descripcion__c.startsWith('TOYOTA YARIS CORE'), nuevo.Descripcion__c);
		System.assertEquals(2014, nuevo.Modelo__c);
		System.assertEquals(comoEnElSitio ? 1 : 0, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :nuevo.Id], 'La factura queda en el vehículo');
		System.assertNotEquals(null, [SELECT Fecha_Baja__c FROM Inciso_Flotilla__c WHERE Poliza__c = :auto.Id AND Serie__c = 'AAA111'].Fecha_Baja__c);
		System.assertEquals('NEW123', [SELECT Placas__c FROM Inciso_Flotilla__c WHERE Poliza__c = :auto.Id AND Serie__c = 'BBB222'].Placas__c);
		System.assert(error != null && error.contains('Renglón 5 del archivo'), error);
		System.assertEquals(1, [SELECT COUNT() FROM Case WHERE InsurancePolicy__c = :auto.Id], 'La solicitud con error no queda');
		System.assertEquals(0, [SELECT COUNT() FROM Inciso_Flotilla__c WHERE Poliza__c = :auto.Id AND Serie__c = 'CCC333'], 'Ni su alta');
	}

	/**
	 * @creation date: 17/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Solicitud del sitio de una póliza de ubicaciones: el alta capturada queda como bien de la póliza con
	 * el folio de la solicitud.
	 * @return void
	 */
	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Póliza nueva cargada sin oportunidad, de una cuenta de empresa y aún con un solo registro: es empresarial
	 * y el contratante puede enviar solicitudes.
	 * @return void
	 */
	@isTest
	static void testSinOportunidadEmpresaPuedeSolicitar() {
		Account empresa = new Account(Name = 'Empresa Sin Oportunidad');
		insert empresa;
		InsurancePolicy p = poliza(empresa.Id, 'DANOS-SINOPP-1', 'Danos');
		p.SourceOpportunityId = null;
		insert p;
		insert new InsurancePolicyAsset(InsurancePolicyId = p.Id, AssetName = 'Oficina');
		PortalPolizasController.cuentaPrueba = empresa.Id;
		PortalPolizasController.contactoPrueba = null;
		Test.startTest();
		Map<String, Object> vista = PortalPolizasPestanas.solicitudes(p.Id, null);
		Test.stopTest();
		System.assertEquals(true, vista.get('esEmpresarial'), 'Sin oportunidad y cuenta de empresa: empresarial');
		System.assertEquals(EndosoPoliza.tipoCaso() != null, vista.get('puedeSolicitar'));
	}

	/**
	 * @creation date: 19/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Póliza de automóvil de un solo vehículo (sin incisos de flotilla) de una empresa: no es empresarial y
	 * no puede enviar solicitudes desde el sitio.
	 * @return void
	 */
	@isTest
	static void testAutoIndividualDeEmpresaNoSolicita() {
		Account empresa = new Account(Name = 'Empresa Auto Individual');
		insert empresa;
		InsurancePolicy p = poliza(empresa.Id, 'AUTO-IND-EMP-1', 'Automoviles');
		p.SourceOpportunityId = null;
		insert p;
		CustomerProperty cp = new CustomerProperty(PrimaryOwnerId = empresa.Id, Make = 'NISSAN', MakeYear = 2013, Description = 'ROGUE');
		insert cp;
		insert new InsurancePolicyAsset(InsurancePolicyId = p.Id, AssetName = 'ROGUE', CustomerPropertyId = cp.Id, IsActive = true);
		PortalPolizasController.cuentaPrueba = empresa.Id;
		PortalPolizasController.contactoPrueba = null;
		Test.startTest();
		Map<String, Object> vista = PortalPolizasPestanas.solicitudes(p.Id, null);
		Boolean bloqueada = false;
		try {
			PortalPolizasPestanas.crearSolicitud(p.Id, JSON.serialize(new Map<String, Object>{ 'movimientos' => new List<Object>{
				new Map<String, Object>{ 'tipo' => 'alta', 'datos' => new List<Object>{ new Map<String, Object>{ 'etiqueta' => 'Serie', 'valor' => 'ABC' } },
					'campos' => new Map<String, Object>{ 'serie' => 'ABC' } } } }), null);
		} catch (AuraHandledException e) {
			bloqueada = true;
		}
		Test.stopTest();
		System.assertEquals(false, vista.get('esEmpresarial'), 'Auto de un solo vehículo: no es empresarial');
		System.assertEquals(false, vista.get('puedeSolicitar'), 'No puede solicitar');
		System.assert(bloqueada, 'El servidor también la rechaza');
	}

	@isTest
	static void testSolicitudRegistraUbicacion() {
		Account cliente = new Account(Name = 'Cliente Ubicaciones Sitio');
		insert cliente;
		InsurancePolicy danos = poliza(cliente.Id, 'DANOS-SITIO-1', 'Danos');
		insert danos;
		insert new List<InsurancePolicyAsset>{ new InsurancePolicyAsset(InsurancePolicyId = danos.Id, AssetName = 'Inciso 1 - Oficina'),
			new InsurancePolicyAsset(InsurancePolicyId = danos.Id, AssetName = 'Inciso 2 - Planta') };
		PortalPolizasController.cuentaPrueba = cliente.Id;
		PortalPolizasController.contactoPrueba = null;
		InsurancePolicy individual = poliza(cliente.Id, 'DANOS-IND-1', 'Danos');
		insert individual;
		insert new InsurancePolicyAsset(InsurancePolicyId = individual.Id, AssetName = 'Casa');
		Test.startTest();
		System.assertEquals(false, PortalPolizasPestanas.solicitudes(individual.Id, null).get('puedeSolicitar'), 'Individual: no es empresarial');
		Boolean bloqueada = false;
		try { PortalPolizasPestanas.crearSolicitud(individual.Id, JSON.serialize(new Map<String, Object>{ 'movimientos' => new List<Object>() }), null); }
		catch (AuraHandledException e) { bloqueada = true; }
		System.assert(bloqueada, 'Individual: no envía solicitudes');
		Map<String, Object> ru = PortalPolizasPestanas.crearSolicitud(danos.Id, JSON.serialize(new Map<String, Object>{ 'movimientos' => new List<Object>{
			new Map<String, Object>{ 'tipo' => 'alta', 'fecha' => String.valueOf(Date.today()),
				'datos' => new List<Object>{ new Map<String, Object>{ 'etiqueta' => 'Nombre', 'valor' => 'Bodega' } },
				'campos' => new Map<String, Object>{ 'ubicacion' => 'Bodega', 'direccion' => 'Av. Uno 100', 'suma' => '1,500,000' } } } }), null);
		Test.stopTest();
		System.assertEquals(1, ru.get('registrados'));
		System.assertEquals(3, [SELECT COUNT() FROM InsurancePolicyAsset WHERE InsurancePolicyId = :danos.Id]);
		// Ubicaciones no llevan el trámite de la solicitud: el movimiento queda como historial, sin folio.
		System.assertEquals(1, [SELECT COUNT() FROM Movimiento_Poliza__c WHERE Poliza__c = :danos.Id]);
	}

	/**
	 * @creation date: 17/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Vista previa de administrador (envía como la cuenta elegida) y solicitud solo con archivo, sin
	 * movimientos que registrar: queda Recibida y, al rechazarla, el cliente ve el motivo.
	 * @return void
	 */
	@isTest
	static void testSolicitudesVistaPreviaYArchivo() {
		Account empresa = new Account(Name = 'Empresa Solicitudes');
		insert empresa;
		Contact empleado = new Contact(LastName = 'Empleado', AccountId = empresa.Id);
		insert empleado;
		InsurancePolicy col = poliza(empresa.Id, 'COL-SOL-1', 'GMM');
		insert col;
		InsurancePolicyParticipant titular = new InsurancePolicyParticipant(InsurancePolicyId = col.Id,
			PrimaryParticipantContactId = empleado.Id, Role = rol('asegurado'), ParticipantCode = '1', IsActiveParticipant = true);
		insert titular;
		Contact otro = new Contact(LastName = 'Otro empleado', AccountId = empresa.Id);
		insert otro;
		insert new InsurancePolicyParticipant(InsurancePolicyId = col.Id, PrimaryParticipantContactId = otro.Id, Role = rol('asegurado'),
			ParticipantCode = '2', IsActiveParticipant = true);
		PortalPolizasController.cuentaPrueba = empresa.Id;
		PortalPolizasController.contactoPrueba = null;

		Map<String, Object> alta = new Map<String, Object>{ 'tipo' => 'alta', 'fecha' => String.valueOf(Date.today()), 'datos' => new List<Object>{
			new Map<String, Object>{ 'etiqueta' => 'Nombre(s)', 'valor' => 'Ana' },
			new Map<String, Object>{ 'etiqueta' => 'Apellido paterno', 'valor' => 'Ruiz' } },
			'campos' => new Map<String, Object>{ 'nombre' => 'Ana', 'paterno' => 'Ruiz', 'nacimiento' => '1990-05-04', 'sexo' => 'Mujer',
				'parentesco' => 'Titular', 'categoria' => '00' } };
		Test.startTest();
		// Vista previa de administrador: puede enviar una solicitud de prueba como la cuenta elegida.
		PortalPolizasController.permisoVistaPreviaPrueba = true;
		System.assertEquals(true, PortalPolizasPestanas.solicitudes(col.Id, empresa.Id).get('puedeSolicitar'));
		Map<String, Object> campos = new Map<String, Object>{ 'nombre' => 'Luis', 'paterno' => 'Paz', 'sexo' => 'Hombre', 'parentesco' => 'Titular' };
		alta.put('campos', campos);
		Boolean sinCategoria = false;
		try {
			PortalPolizasPestanas.crearSolicitud(col.Id, JSON.serialize(new Map<String, Object>{ 'movimientos' => new List<Object>{ alta } }), empresa.Id);
		} catch (AuraHandledException e) { sinCategoria = e.getMessage().contains('categoría'); }
		System.assert(sinCategoria, 'La categoría del alta es obligatoria');
		campos.put('categoria', '00');
		Map<String, Object> rp = PortalPolizasPestanas.crearSolicitud(col.Id, JSON.serialize(new Map<String, Object>{
			'movimientos' => new List<Object>{ alta } }), empresa.Id);
		System.assertEquals('SOL-0001', rp.get('folio'));
		System.assertEquals(1, [SELECT COUNT() FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :col.Id AND Categoria__c = '00']);
		Case cp = [SELECT AccountId, Description FROM Case WHERE InsurancePolicy__c = :col.Id AND Solicitud__c = 'SOL-0001'];
		System.assertEquals(empresa.Id, cp.AccountId);
		System.assert(cp.Description.contains('vista previa de administrador'), cp.Description);

		// Solicitud por archivo: sin capturar movimientos, con el Excel y lo que trae.
		Map<String, Object> ra = PortalPolizasPestanas.crearSolicitud(col.Id, JSON.serialize(new Map<String, Object>{
			'movimientos' => new List<Object>(),
			'listado' => new Map<String, Object>{ 'tipo' => 'alta', 'nombre' => 'FLOTILLA.xlsx', 'total' => 2,
				'encabezados' => new List<Object>{ 'MODELO', 'MARCA', 'SERIE' },
				'filas' => new List<Object>{ new List<Object>{ '2014', 'TOYOTA', 'JTDKT9D38ED585824' }, new List<Object>{ '2017', 'SEAT', 'VSSBE75F7LR043409' } } },
			'archivos' => new List<Object>{ new Map<String, Object>{ 'nombre' => 'FLOTILLA.xlsx', 'base64' => EncodingUtil.base64Encode(Blob.valueOf('x')) } }
		}), empresa.Id);
		Case ca = [SELECT Subject, Description, Reason FROM Case WHERE InsurancePolicy__c = :col.Id AND Solicitud__c = :String.valueOf(ra.get('folio'))];
		System.assert(ca.Subject.contains('archivo FLOTILLA.xlsx'), ca.Subject);
		System.assertEquals('Alta', ca.Reason);
		Boolean sinTipo = false;
		try {
			PortalPolizasPestanas.crearSolicitud(col.Id, JSON.serialize(new Map<String, Object>{
				'listado' => new Map<String, Object>{ 'tipo' => 'otro', 'nombre' => 'x.xlsx' } }), empresa.Id);
		} catch (AuraHandledException e) { sinTipo = true; }
		System.assert(sinTipo, 'El archivo indica qué contiene');

		// Sin movimientos que registrar (solo el archivo) queda Recibida. Rechazo del ejecutivo: el cliente ve el motivo.
		Case recibida = [SELECT Id FROM Case WHERE InsurancePolicy__c = :col.Id AND Solicitud__c = :String.valueOf(ra.get('folio'))];
		insert new CaseComment(ParentId = recibida.Id, IsPublished = true, CommentBody = 'Solicitud rechazada: Falta el acta de nacimiento');
		update new Case(Id = recibida.Id, Status = EndosoPoliza.estadoCaso('Concluido'));
		Boolean visto = false;
		for (Object o : (List<Object>) PortalPolizasPestanas.solicitudes(col.Id, empresa.Id).get('solicitudes')) {
			Map<String, Object> s = (Map<String, Object>) o;
			if (s.get('folio') != ra.get('folio')) { continue; }
			visto = true;
			System.assertEquals('Rechazada', s.get('estado'));
			System.assert(String.valueOf(s.get('respuesta')).contains('Falta el acta'), s.get('respuesta'));
		}
		System.assert(visto, 'El cliente ve la solicitud rechazada');
		Test.stopTest();
	}

	/**
	 * @creation date: 20/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Reporte Foxconn: la solicitud del sitio queda «Solicitado» hasta que el ejecutivo la atiende (al
	 * descargar su Excel pasa a «En proceso»), «Ver detalle» trae sus movimientos, la baja de otra póliza del mismo
	 * contratante se registra en esa póliza (su folio y su caso), la carta de antigüedad adjunta marca el RA y un alta de
	 * más de 30 días atrás no se acepta.
	 * @return void
	 */
	@isTest
	static void testSeguimientoDetalleYOtraPoliza() {
		Account empresa = new Account(Name = 'Empresa Pool');
		insert empresa;
		InsurancePolicy uno = poliza(empresa.Id, 'POOL-1', 'GMM');
		InsurancePolicy dos = poliza(empresa.Id, 'POOL-2', 'GMM');
		insert new List<InsurancePolicy>{ uno, dos };
		List<InsurancePolicyParticipant> pps = new List<InsurancePolicyParticipant>();
		for (InsurancePolicy p : new List<InsurancePolicy>{ uno, dos }) {
			for (Integer i = 1; i <= 2; i++) {
				Contact c = new Contact(LastName = 'Empleado ' + p.Name + ' ' + i, AccountId = empresa.Id);
				insert c;
				pps.add(new InsurancePolicyParticipant(InsurancePolicyId = p.Id, PrimaryParticipantContactId = c.Id, Role = rol('asegurado'),
					ParticipantCode = String.valueOf(3 - i), IsActiveParticipant = true));
			}
		}
		insert pps;
		PortalPolizasController.cuentaPrueba = empresa.Id;
		PortalPolizasController.contactoPrueba = null;
		Map<String, Object> alta = new Map<String, Object>{ 'tipo' => 'alta', 'fecha' => String.valueOf(Date.today().addDays(-5)), 'numero' => 1,
			'datos' => new List<Object>{ new Map<String, Object>{ 'etiqueta' => 'Nombre(s)', 'valor' => 'Ana' } },
			'campos' => new Map<String, Object>{ 'nombre' => 'Ana', 'paterno' => 'Ruiz', 'nacimiento' => '1990-05-04', 'sexo' => 'Mujer',
				'parentesco' => 'Titular', 'categoria' => '00' } };
		// Baja de un asegurado de la otra póliza (el certificado 2 de POOL-2).
		Map<String, Object> baja = new Map<String, Object>{ 'tipo' => 'baja', 'registroId' => pps[2].Id, 'polizaId' => dos.Id,
			'detalle' => 'Renuncia', 'numero' => 2 };

		Test.startTest();
		Map<String, Object> r = PortalPolizasPestanas.crearSolicitud(uno.Id, JSON.serialize(new Map<String, Object>{
			'movimientos' => new List<Object>{ alta, baja },
			'archivos' => new List<Object>{ new Map<String, Object>{ 'nombre' => 'Carta de antigüedad.pdf', 'base64' => EncodingUtil.base64Encode(Blob.valueOf('x')) } }
		}), null);
		Map<String, Object> vista = PortalPolizasPestanas.solicitudes(uno.Id, null);
		Map<String, Object> otra = PortalPolizasPestanas.registrosPoliza(dos.Id, null);
		// Alta de hace 40 días: no.
		Map<String, Object> vieja = alta.clone();
		vieja.put('fecha', String.valueOf(Date.today().addDays(-40)));
		String error;
		try { PortalPolizasPestanas.crearSolicitud(uno.Id, JSON.serialize(new Map<String, Object>{ 'movimientos' => new List<Object>{ vieja } }), null); }
		catch (AuraHandledException e) { error = e.getMessage(); }
		Test.stopTest();

		System.assertEquals(2, r.get('solicitudes'), 'Una solicitud por póliza');
		System.assertEquals('SOL-0001, SOL-0001 (póliza POOL-2)', r.get('folio'));
		Case c1 = [SELECT Subject, Description, Status FROM Case WHERE InsurancePolicy__c = :uno.Id];
		System.assert(c1.Subject.endsWith('· con RA'), c1.Subject);
		System.assert(c1.Description.contains('Reconocimiento de antigüedad (RA): 1 movimiento; documentos: Carta de antigüedad.pdf'), c1.Description);
		System.assertEquals(1, [SELECT COUNT() FROM Case WHERE InsurancePolicy__c = :dos.Id AND Solicitud__c = 'SOL-0001']);
		System.assert([SELECT Comentario__c FROM Movimiento_Poliza__c WHERE Poliza__c = :uno.Id].Comentario__c.startsWith('Con RA'));
		System.assertEquals(false, [SELECT IsActiveParticipant FROM InsurancePolicyParticipant WHERE Id = :pps[2].Id].IsActiveParticipant,
			'La baja se registró en POOL-2');
		System.assert(error != null && error.contains('máximo 30 días retroactivos'), error);

		// Pólizas del contratante (la actual primero) y registros de la otra, por certificado.
		List<Object> polizas = (List<Object>) vista.get('polizas');
		System.assertEquals(2, polizas.size());
		System.assertEquals(true, ((Map<String, Object>) polizas[0]).get('actual'));
		List<Object> regs = (List<Object>) otra.get('registros');
		System.assertEquals('1', ((Map<String, Object>) regs[0]).get('clave'), 'Ordenados por certificado');
		// Detalle de la solicitud y su seguimiento: nadie la ha atendido.
		Map<String, Object> s = (Map<String, Object>) ((List<Object>) vista.get('solicitudes'))[0];
		System.assertEquals('Solicitado', s.get('seguimiento'));
		List<Object> movs = (List<Object>) s.get('movimientos');
		System.assertEquals(1, movs.size());
		System.assertEquals('Alta', ((Map<String, Object>) movs[0]).get('tipo'));
		System.assertEquals('Solicitado', ((Map<String, Object>) movs[0]).get('seguimiento'));
		System.assertEquals(new List<Object>{ 'Carta de antigüedad.pdf' }, (List<Object>) s.get('archivos'));
		// El ejecutivo la pasa a mano a En proceso cuando ya está en la aseguradora.
		Case caso = [SELECT Id FROM Case WHERE InsurancePolicy__c = :uno.Id AND Solicitud__c = 'SOL-0001' LIMIT 1];
		caso.Status = EndosoPoliza.estadoCaso('En proceso');
		update caso;
		Map<String, Object> s2 = (Map<String, Object>) ((List<Object>) PortalPolizasPestanas.solicitudes(uno.Id, null).get('solicitudes'))[0];
		System.assertEquals('En proceso', s2.get('seguimiento'));
		System.assertEquals(new List<String>{ 'CARTA ANTIGUEDAD.pdf', 'Caratula poliza.pdf' },
			PortalPolizasPestanas.archivosRA(new List<String>{ 'CARTA ANTIGUEDAD.pdf', 'ine.pdf', 'Caratula poliza.pdf', null }));
		// Caso en el estado «Solicitado»: sigue sin atender.
		System.assertEquals('Solicitado', EndosoPoliza.seguimiento(new Map<String, Object>{ 'portal' => true, 'total' => 2, 'abiertos' => 2,
			'estadoCaso' => 'Solicitado', 'casoCerrado' => false }, 'Creado'));
		// Un renglón del archivo se nombra como el movimiento que ve el cliente en la vista previa.
		System.assertEquals('Movimiento 4 · ALBERTO GOMEZ RODRIGUEZ (ALTA)', PortalPolizasPestanas.movimientoArchivo(
			new Map<String, Object>{ 'numero' => 4, 'fila' => 7, 'nombre' => 'ALBERTO GOMEZ RODRIGUEZ' }, 'alta'));
		System.assertEquals('Renglón 7 del archivo', PortalPolizasPestanas.movimientoArchivo(new Map<String, Object>{ 'fila' => 7 }, 'alta'));
	}

	/**
	 * @creation date: 23/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Documentos del alta: la carta de antigüedad que el cliente identifica con su registro marca solo ese
	 * movimiento con RA y queda en el contacto del asegurado y en el caso; un registro ajeno no se acepta.
	 * @return void
	 */
	@isTest
	static void testDocumentosDelAlta() {
		Account empresa = new Account(Name = 'Empresa Documentos');
		insert empresa;
		InsurancePolicy pol = poliza(empresa.Id, 'DOCS-1', 'GMM');
		insert pol;
		Contact c = new Contact(LastName = 'Empleado docs', AccountId = empresa.Id);
		insert c;
		InsurancePolicyParticipant otro = new InsurancePolicyParticipant(InsurancePolicyId = pol.Id, PrimaryParticipantContactId = c.Id,
			Role = rol('asegurado'), ParticipantCode = '1', IsActiveParticipant = true);
		Contact c2 = new Contact(LastName = 'Empleado docs dos', AccountId = empresa.Id);
		insert c2;
		insert new List<InsurancePolicyParticipant>{ otro, new InsurancePolicyParticipant(InsurancePolicyId = pol.Id,
			PrimaryParticipantContactId = c2.Id, Role = rol('asegurado'), ParticipantCode = '2', IsActiveParticipant = true) };
		PortalPolizasController.cuentaPrueba = empresa.Id;
		PortalPolizasController.contactoPrueba = null;
		List<Object> movs = new List<Object>();
		Integer n = 0;
		for (String nombre : new List<String>{ 'Ana', 'Eva' }) {
			n++;
			movs.add(new Map<String, Object>{ 'tipo' => 'alta', 'fecha' => String.valueOf(Date.today()), 'numero' => n,
				'datos' => new List<Object>{ new Map<String, Object>{ 'etiqueta' => 'Nombre(s)', 'valor' => nombre } },
				'campos' => new Map<String, Object>{ 'nombre' => nombre, 'paterno' => 'Ruiz', 'nacimiento' => '1990-05-04', 'sexo' => 'Mujer',
					'parentesco' => 'Titular', 'categoria' => '00' } });
		}
		String b64 = EncodingUtil.base64Encode(Blob.valueOf('carta'));
		Test.startTest();
		Map<String, Object> r = PortalPolizasPestanas.crearSolicitud(pol.Id, JSON.serialize(new Map<String, Object>{ 'movimientos' => movs,
			'documentos' => new List<Object>{ new Map<String, Object>{ 'movimiento' => 2, 'tipo' => 'Carta de antigüedad', 'nombre' => 'doc1.pdf' } } }), null);
		Map<String, Object> m2 = (Map<String, Object>) ((List<Object>) r.get('movimientos'))[1];
		String folio = (String) m2.get('folio');
		PortalPolizasPestanas.adjuntarDocumento(pol.Id, folio, (String) m2.get('registroId'), 'Carta de antigüedad', 'doc1.pdf', b64, null);
		Integer errores = 0;
		try { PortalPolizasPestanas.adjuntarDocumento(pol.Id, folio, otro.Id, 'Otro', 'x.pdf', b64, null); } catch (AuraHandledException e) { errores++; }
		try { PortalPolizasPestanas.adjuntarDocumento(pol.Id, 'SOL-9999', null, 'Otro', 'x.pdf', b64, null); } catch (AuraHandledException e) { errores++; }
		try { PortalPolizasPestanas.adjuntarDocumento(pol.Id, folio, null, 'Otro', 'x.pdf', '', null); } catch (AuraHandledException e) { errores++; }
		Test.stopTest();
		System.assertEquals(3, errores, 'Registro ajeno, folio que no existe y documento vacío');
		InsurancePolicyParticipant eva = [SELECT ParticipantName, PrimaryParticipantContactId FROM InsurancePolicyParticipant WHERE Id = :(String) m2.get('registroId')];
		System.assert(eva.ParticipantName.contains('Eva'), eva.ParticipantName);
		Id caso = [SELECT Id FROM Case WHERE InsurancePolicy__c = :pol.Id].Id;
		for (Id donde : new List<Id>{ caso, eva.PrimaryParticipantContactId != null ? eva.PrimaryParticipantContactId : eva.Id }) {
			System.assertEquals('Carta de antigüedad - doc1', [SELECT ContentDocument.Title FROM ContentDocumentLink WHERE LinkedEntityId = :donde].ContentDocument.Title);
		}
		Integer conRA = 0;
		for (Movimiento_Poliza__c m : [SELECT Asegurado__c, Comentario__c FROM Movimiento_Poliza__c WHERE Poliza__c = :pol.Id]) {
			if (m.Comentario__c != null && m.Comentario__c.startsWith('Con RA')) { conRA++; System.assert(m.Asegurado__c.contains('Eva')); }
		}
		System.assertEquals(1, conRA, 'RA solo en el registro con su carta');
	}

	static Map<String, Object> renglon(Integer n, String tipo, String nombre, String parentesco, String certificado) {
		return new Map<String, Object>{ 'tipo' => tipo, 'numero' => n, 'nombre' => nombre, 'fecha' => String.valueOf(Date.today()),
			'campos' => new Map<String, Object>{ 'nombre' => nombre.substringBefore(' '), 'paterno' => nombre.substringAfter(' '),
				'parentesco' => parentesco, 'certificado' => certificado, 'nacimiento' => '1990-01-0' + n, 'sexo' => 'Mujer' } };
	}

	/**
	 * @creation date: 23/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Archivo sin columna Titular: el titular de cada dependiente es el del mismo certificado (del archivo o
	 * de la póliza) o, sin certificado («ASIGNAR»), el que está arriba. Con un certificado compartido, la baja es de la
	 * persona que dice el renglón.
	 * @return void
	 */
	@isTest
	static void testTitularDelArchivo() {
		Account empresa = new Account(Name = 'Empresa Titulares');
		insert empresa;
		InsurancePolicy pol = poliza(empresa.Id, 'TIT-1', 'GMM');
		insert pol;
		List<Contact> cs = new List<Contact>{ new Contact(FirstName = 'Luz', LastName = 'Vega', AccountId = empresa.Id),
			new Contact(FirstName = 'Leo', LastName = 'Vega', AccountId = empresa.Id) };
		insert cs;
		InsurancePolicyParticipant luz = new InsurancePolicyParticipant(InsurancePolicyId = pol.Id, PrimaryParticipantContactId = cs[0].Id,
			Role = rol('asegurado'), ParticipantCode = '00900', ParticipantName = 'Luz Vega', IsActiveParticipant = true);
		insert luz;
		InsurancePolicyParticipant leo = new InsurancePolicyParticipant(InsurancePolicyId = pol.Id, PrimaryParticipantContactId = cs[1].Id,
			Role = rol('asegurado'), ParticipantCode = '00900', ParticipantName = 'Leo Vega', IsActiveParticipant = true, RelatedInsPolicyParticipantId = luz.Id);
		insert leo;
		PortalPolizasController.cuentaPrueba = empresa.Id;
		PortalPolizasController.contactoPrueba = null;
		Map<String, Object> archivo = new Map<String, Object>{ 'tipo' => 'varios', 'nombre' => 'LAYOUT.xlsx', 'total' => 7,
			'registros' => new List<Object>{
				renglon(1, 'alta', 'ADRIANA CORTES', 'TITULAR', '00365'), renglon(2, 'alta', 'JAVIER LOMELI', 'CONYUGE', '00365'),
				renglon(3, 'alta', 'FERNANDA ALVARADO', 'TITULAR', 'ASIGNAR'), renglon(4, 'alta', 'DANIEL SOLIS', 'CONYUGE', 'ASIGNAR'),
				renglon(5, 'alta', 'VALENTINA SOLIS', 'HIJA', 'ASIGNAR'), renglon(6, 'alta', 'ANA VEGA', 'HIJA', '00900'),
				renglon(7, 'baja', 'LEO VEGA', 'HIJO', '00900') } };
		Test.startTest();
		Map<String, Object> r = PortalPolizasPestanas.crearSolicitud(pol.Id, JSON.serialize(new Map<String, Object>{ 'listado' => archivo }), null);
		String error;
		archivo.put('registros', new List<Object>{ renglon(1, 'alta', 'OTRA PERSONA', 'TITULAR', '00777'), renglon(2, 'alta', 'SIN TITULAR', 'HIJA', '00778') });
		try { PortalPolizasPestanas.crearSolicitud(pol.Id, JSON.serialize(new Map<String, Object>{ 'listado' => archivo }), null); }
		catch (AuraHandledException e) { error = e.getMessage(); }
		Test.stopTest();
		System.assertEquals(7, r.get('registrados'));
		Map<String, String> titular = new Map<String, String>();
		for (InsurancePolicyParticipant p : [SELECT ParticipantName, RelatedInsPolicyParticipant.ParticipantName FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :pol.Id]) {
			titular.put(p.ParticipantName.toUpperCase(), p.RelatedInsPolicyParticipantId == null ? null : p.RelatedInsPolicyParticipant.ParticipantName.toUpperCase());
		}
		System.assertEquals('ADRIANA CORTES', titular.get('JAVIER LOMELI'), 'Mismo certificado en el archivo');
		// El sexo del archivo queda en el titular, su contacto y sus dependientes.
		for (InsurancePolicyParticipant p : [SELECT ParticipantName, Sexo__c, PrimaryParticipantContact.Sexo__c, PrimaryParticipantContactId FROM InsurancePolicyParticipant
				WHERE InsurancePolicyId = :pol.Id AND ParticipantCode = '00365']) {
			System.assertEquals('Femenino', p.Sexo__c, p.ParticipantName);
			if (p.PrimaryParticipantContactId != null) { System.assertEquals('Femenino', p.PrimaryParticipantContact.Sexo__c, p.ParticipantName); }
		}
		System.assertEquals('FERNANDA ALVARADO', titular.get('DANIEL SOLIS'), 'El que está arriba');
		System.assertEquals('FERNANDA ALVARADO', titular.get('VALENTINA SOLIS'), 'El titular de arriba, no el cónyuge');
		System.assertEquals('LUZ VEGA', titular.get('ANA VEGA'), 'Titular vigente de la póliza con ese certificado');
		System.assertEquals(false, [SELECT IsActiveParticipant FROM InsurancePolicyParticipant WHERE Id = :leo.Id].IsActiveParticipant, 'Baja del dependiente');
		System.assertEquals(true, [SELECT IsActiveParticipant FROM InsurancePolicyParticipant WHERE Id = :luz.Id].IsActiveParticipant, 'Su titular sigue vigente');
		System.assert(error != null && error.contains('no encontramos a su titular'), error);
	}

	/**
	 * @creation date: 24/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Categorías de Nueva solicitud: las de los asegurados, sin repetir y en orden; solo en pólizas de personas.
	 * @return void
	 */
	@isTest
	static void testCategoriasSolicitud() {
		PortalPolizasPestanas.Bienes b = new PortalPolizasPestanas.Bienes();
		b.tipo = 'personas';
		for (String c : new List<String>{ '01', '00', '00', null }) {
			PortalPolizasPestanas.Fila f = new PortalPolizasPestanas.Fila();
			f.detalle = c;
			b.filas.add(f);
		}
		System.assertEquals(new List<String>{ '00', '01' }, PortalPolizasPestanas.categoriasSolicitud(null, b));
		b.tipo = 'vehiculos';
		System.assertEquals(0, PortalPolizasPestanas.categoriasSolicitud(null, b).size());
	}

	/**
	 * @creation date: 27/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Pestaña Siniestros del sitio: el contratante de una póliza empresarial ve sus siniestros sin datos
	 *   internos ni anulados; en una póliza individual no hay pestaña y la consulta se rechaza.
	 * @return void
	 */
	@isTest
	static void testSiniestros() {
		Account empresa = new Account(Name = 'Empresa Siniestros Sitio');
		insert empresa;
		InsurancePolicy col = poliza(empresa.Id, 'SIN-SITIO-1', 'GMM');
		InsurancePolicy ind = poliza(empresa.Id, 'SIN-SITIO-2', 'GMM');
		insert new List<InsurancePolicy>{ col, ind };
		String rolAsegurado = rol('asegurado');
		insert new List<InsurancePolicyParticipant>{
			new InsurancePolicyParticipant(InsurancePolicyId = col.Id, ParticipantName = 'ANA', Role = rolAsegurado, ParticipantCode = '1', IsActiveParticipant = true),
			new InsurancePolicyParticipant(InsurancePolicyId = col.Id, ParticipantName = 'LUIS', Role = rolAsegurado, ParticipantCode = '2', IsActiveParticipant = true),
			new InsurancePolicyParticipant(InsurancePolicyId = ind.Id, ParticipantName = 'SOLO', Role = rolAsegurado, ParticipantCode = '1', IsActiveParticipant = true)
		};
		Id rt = Schema.SObjectType.Claim.getRecordTypeInfosByDeveloperName().get('Personas').getRecordTypeId();
		Claim vigente = new Claim(Name = 'Nuevo', RecordTypeId = rt, PolicyNumberId = col.Id, Status = 'Abierto', ClaimType = 'Gastos médicos mayores',
			ClaimReasonType = 'Enfermedad', LossType = 'Reembolso', LossDate = Datetime.now(), Afectado__c = 'ANA', ClaimReason = 'Diagnóstico privado',
			EstimatedAmount = 1000);
		Claim anulado = vigente.clone(false, true);
		anulado.Status = 'Anulado';
		insert new List<Claim>{ vigente, anulado };
		PortalPolizasController.cuentaPrueba = empresa.Id;
		Test.startTest();
		Map<String, Object> r = PortalPolizasPestanas.siniestros(col.Id, null);
		Boolean conPestana = PortalPolizasController.detallePoliza(col.Id, null).poliza.conSiniestros;
		Boolean sinPestana = PortalPolizasController.detallePoliza(ind.Id, null).poliza.conSiniestros;
		String error;
		try { PortalPolizasPestanas.siniestros(ind.Id, null); } catch (AuraHandledException e) { error = e.getMessage(); }
		Test.stopTest();
		List<Object> l = (List<Object>) r.get('siniestros');
		System.assertEquals(1, l.size(), 'Sin el anulado');
		Map<String, Object> s = (Map<String, Object>) l[0];
		System.assertEquals('ANA', s.get('afectado'));
		System.assertEquals(false, s.containsKey('descripcion'), 'Sin el diagnóstico');
		System.assertEquals(false, s.containsKey('ejecutivo'));
		System.assertEquals(true, r.get('portal'));
		System.assertEquals(false, ((Map<String, Object>) r.get('resumen')).containsKey('siniestralidad'));
		System.assertEquals(true, conPestana, 'Colectiva: con pestaña');
		System.assertEquals(false, sinPestana, 'Un solo asegurado: sin pestaña');
		System.assertNotEquals(null, error);
	}
}
