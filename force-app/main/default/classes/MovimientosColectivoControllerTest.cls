/**
 * @creation date: 31/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas de MovimientosColectivoController: endosos en la póliza (baja con motivo y dependientes, cambio,
 *               alta de titular y dependiente), comparación de un archivo, renovación (censo desde la póliza anterior,
 *               movimientos sobre el censo y liga de la nueva vigencia con la anterior) y validaciones.
 */
@isTest
private class MovimientosColectivoControllerTest {

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Empresa, oportunidad original con su censo y póliza vigente (que vence hoy), y oportunidad de renovación.
	 * @return void
	 */
	@testSetup
	static void setup() {
		Account acc = new Account(Name = 'Empresa Movimientos Test', AnnualRevenue = 100);
		insert acc;
		String etapa = 'Prospecting';
		for (OpportunityStage s : [
			SELECT MasterLabel FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1
		]) { etapa = s.MasterLabel; }
		List<Agente__c> agentes = [SELECT Id FROM Agente__c LIMIT 1];
		if (agentes.isEmpty()) {
			Agente__c ag = new Agente__c(Name = 'Agente Movimientos Test', Status__c = 'Nuevo', Estado_Civil__c = 'Casado');
			insert ag;
			agentes.add(ag);
		}
		List<Opportunity> opps = new List<Opportunity>();
		for (String nombre : new List<String>{ 'Opp Original', 'Opp Renovacion' }) {
			Opportunity o = new Opportunity(Name = nombre, AccountId = acc.Id, StageName = etapa,
				CloseDate = Date.today().addDays(30), Agente_Relacionado__c = agentes[0].Id);
			o.put('Ramo__c', 'Vida');
			o.put('Tipo_Contratacion__c', 'Colectiva');
			opps.add(o);
		}
		insert opps;
		CensoColectivoController.guardarCenso(opps[0].Id, JSON.serialize(new List<Object>{
			new Map<String, Object>{ 'fila' => 2, 'nombre' => 'Juan', 'apellidos' => 'Pérez García', 'fechaNacimiento' => '1980-05-10',
				'sexo' => 'Hombre', 'parentesco' => 'Titular', 'categoria' => 'Dirección', 'sumaAsegurada' => 1000000, 'prima' => 5000,
				'certificado' => '001', 'fechaAlta' => '2020-01-15' },
			new Map<String, Object>{ 'fila' => 3, 'nombreCompleto' => 'María López Ruiz', 'fechaNacimiento' => '1982-08-15',
				'sexo' => 'Mujer', 'parentesco' => 'Cónyuge', 'titularIndex' => 0, 'certificado' => '001' },
			new Map<String, Object>{ 'fila' => 4, 'nombreCompleto' => 'Pedro Gómez Díaz', 'fechaNacimiento' => '1990-11-22',
				'sexo' => 'Hombre', 'parentesco' => 'Titular', 'categoria' => 'Empleados', 'sumaAsegurada' => 500000, 'prima' => 2000,
				'certificado' => '002', 'fechaAlta' => '2022-06-15' }
		}), true);
		InsurancePolicy pol = poliza('POL-MOV-1', acc.Id, opps[0].Id, Datetime.now().addDays(-365));
		insert pol;
		CensoColectivoController.copiarCensoAPoliza(opps[0].Id, pol.Id);
	}

	static InsurancePolicy poliza(String nombre, Id accountId, Id oppId, Datetime inicio) {
		InsurancePolicy pol = new InsurancePolicy(Name = nombre, NameInsuredId = accountId, SourceOpportunityId = oppId,
			Status = 'Inicial', PremiumAmount = 1200, PaymentDueDate = Date.today().addDays(30), EffectiveDate = inicio,
			ExpirationDate = inicio.addDays(365));
		pol.put('Ramo__c', 'Vida');
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { pol.PremiumFrequency = pe.getValue(); break; }
		}
		return pol;
	}

	static String motivo() {
		return Movimiento_Poliza__c.Motivo_Baja__c.getDescribe().getPicklistValues()[0].getValue();
	}

	static Map<String, Object> mov(String tipo, Id id, Map<String, Object> datos) {
		Map<String, Object> m = new Map<String, Object>{ 'tipo' => tipo, 'fecha' => String.valueOf(Date.today()), 'endoso' => 'END-1' };
		if (id != null) { m.put('id', id); }
		if (datos != null) { m.put('datos', datos); }
		if (tipo == 'baja') { m.put('motivo', motivo()); }
		return m;
	}

	static Id participante(Id policyId, String nombre) {
		return [SELECT Id FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :policyId AND ParticipantName LIKE :nombre LIMIT 1].Id;
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Endoso en la póliza: baja del titular (con su cónyuge), cambio de datos y alta de titular con dependiente.
	 * @return void
	 */
	@isTest
	static void testEndososPoliza() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'POL-MOV-1'];
		Id juan = participante(pol.Id, 'Juan%');
		Id pedro = participante(pol.Id, 'Pedro%');
		Map<String, Object> datos = MovimientosColectivoController.getDatos(pol.Id);
		System.assertEquals('poliza', datos.get('contexto'));
		System.assertEquals(true, datos.get('aplica'), 'Vida es de personas');
		System.assertEquals(3, ((List<Object>) datos.get('miembros')).size(), 'Tres asegurados');
		System.assert(!((List<Object>) datos.get('motivos')).isEmpty(), 'Motivos de baja configurados');

		Map<String, Object> bajaJuan = mov('baja', juan, null);
		bajaJuan.put('correoPersonal', 'juan.personal@test.com');
		List<Object> movs = new List<Object>{
			bajaJuan,
			mov('cambio', pedro, new Map<String, Object>{ 'prima' => 2500, 'sumaAsegurada' => 750000, 'categoria' => 'Gerentes',
				'certificado' => '002-B', 'rfc' => 'GODP901122AAA', 'fechaNacimiento' => '1990-11-23', 'nombreCompleto' => 'Pedro Gómez Díaz Jr' }),
			mov('alta', null, new Map<String, Object>{ 'nombre' => 'Ana', 'apellidos' => 'Ruiz Soto', 'parentesco' => 'Titular',
				'sexo' => 'Mujer', 'fechaNacimiento' => '1995-03-03', 'certificado' => '003', 'categoria' => 'Empleados', 'sumaAsegurada' => 300000 })
		};
		Map<String, Object> dep = mov('alta', null, new Map<String, Object>{ 'nombreCompleto' => 'Luis Ruiz', 'parentesco' => 'Hijo(a)', 'sexo' => 'Hombre' });
		dep.put('titularRef', 2);
		movs.add(dep);

		Test.startTest();
		Map<String, Object> r = MovimientosColectivoController.aplicar(pol.Id, JSON.serialize(movs));
		Test.stopTest();

		System.assertEquals(2, r.get('bajas'), 'Baja del titular y de su cónyuge');
		System.assertEquals('juan.personal@test.com', [SELECT Correo_Personal__c FROM InsurancePolicyParticipant WHERE Id = :juan].Correo_Personal__c,
			'Se guarda el correo personal capturado en la baja');
		System.assertEquals(1, r.get('cambios'));
		System.assertEquals(2, r.get('altas'));
		for (InsurancePolicyParticipant p : [SELECT IsActiveParticipant, Motivo_Baja__c, EffectiveToDate FROM InsurancePolicyParticipant
				WHERE InsurancePolicyId = :pol.Id AND (ParticipantName LIKE 'Juan%' OR ParticipantName LIKE 'Mar%')]) {
			System.assertEquals(false, p.IsActiveParticipant, 'Queda inactivo, no se borra');
			System.assertEquals(motivo(), p.Motivo_Baja__c, 'Con su motivo');
			System.assertEquals(Date.today(), p.EffectiveToDate, 'Fecha de baja');
		}
		InsurancePolicyParticipant p = [SELECT TermPremiumAmount, ParticipantCode, ParticipantName, Categoria__c FROM InsurancePolicyParticipant WHERE Id = :pedro];
		System.assertEquals('Gerentes', p.Categoria__c, 'Categoría cambiada');
		System.assertEquals(2500, p.TermPremiumAmount, 'Prima cambiada');
		System.assertEquals('002-B', p.ParticipantCode, 'Certificado cambiado');
		System.assertEquals(750000, [SELECT LimitAmount FROM InsurancePolicyCoverage WHERE InsurancePolicyParticipantId = :pedro LIMIT 1].LimitAmount,
			'Suma asegurada actualizada');
		InsurancePolicyParticipant luis = [SELECT RelatedInsPolicyParticipant.ParticipantName, EffectiveFromDate, IsActiveParticipant
			FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :pol.Id AND ParticipantName = 'Luis Ruiz'];
		System.assertEquals('Ana Ruiz Soto', luis.RelatedInsPolicyParticipant.ParticipantName, 'Dependiente ligado al alta de su titular');
		System.assertEquals(Date.today(), luis.EffectiveFromDate, 'Vigente desde la fecha del endoso');
		System.assertEquals('Empleados', [SELECT Categoria__c FROM InsurancePolicyParticipant WHERE Id = :luis.Id].Categoria__c, 'El dependiente toma la categoría de su titular');
		System.assertEquals(5, [SELECT COUNT() FROM Movimiento_Poliza__c WHERE Poliza__c = :pol.Id AND Contexto__c = 'Endoso'], 'Un registro por asegurado');
		System.assert([SELECT Detalle__c FROM Movimiento_Poliza__c WHERE Poliza__c = :pol.Id AND Tipo__c = 'Cambio'].Detalle__c.contains('Prima'),
			'El cambio guarda el detalle');

		Map<String, Object> despues = MovimientosColectivoController.getDatos(pol.Id);
		System.assertEquals(5, ((List<Object>) despues.get('movimientos')).size(), 'Historial');
		// Cada asegurado muestra su último movimiento con su fecha.
		for (Object o : (List<Object>) despues.get('miembros')) {
			Map<String, Object> a = (Map<String, Object>) o;
			if (a.get('id') == (String) pedro) {
				System.assertEquals('Cambio', a.get('tipoMovimiento'), 'Último movimiento de Pedro');
				System.assertEquals(Date.today(), a.get('fechaMovimiento'), 'Con la fecha del movimiento');
			}
			if (a.get('nombre') == 'Luis Ruiz') { System.assertEquals('Alta', a.get('tipoMovimiento')); }
		}
		// Alta duplicada: la persona ya está vigente.
		try {
			MovimientosColectivoController.aplicar(pol.Id, JSON.serialize(new List<Object>{
				mov('alta', null, new Map<String, Object>{ 'nombre' => 'Ana', 'apellidos' => 'Ruiz Soto', 'certificado' => '003' }) }));
			System.assert(false, 'Debe rechazar el alta duplicada');
		} catch (AuraHandledException e) {
			System.assert(e.getMessage().contains('ya está vigente'), e.getMessage());
		}
	}

	/**
	 * @creation date: 15/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Soporte de recibo de GMM con varios endosos: cada renglón trae su número de endoso (No. Mvto.); cada
	 *               movimiento queda en su endoso con la prima de ese endoso. Endoso sin movimientos (cláusula de GMM).
	 * @return void
	 */
	@isTest
	static void testVariosEndososYEndosoSinMovimientos() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'POL-MOV-1'];
		Id pedro = participante(pol.Id, 'Pedro%');
		// El número de endoso de cada renglón llega a la revisión.
		Map<String, Object> rev = MovimientosColectivoController.compararArchivo(pol.Id, JSON.serialize(new List<Object>{
			new Map<String, Object>{ 'fila' => 1, 'nombreCompleto' => 'Rosa Núñez Vega', 'parentesco' => 'Titular', 'sexo' => 'Mujer',
				'certificado' => '010', 'movimiento' => 'Alta', 'numeroEndoso' => '5', 'primaMovimiento' => 3603.66 },
			new Map<String, Object>{ 'fila' => 2, 'nombreCompleto' => 'Pedro Gómez Díaz', 'certificado' => '002', 'movimiento' => 'Baja',
				'numeroEndoso' => '15' }
		}), false);
		System.assertEquals('5', ((Map<String, Object>) ((List<Object>) rev.get('altas'))[0]).get('numeroEndoso'));
		System.assertEquals('15', ((Map<String, Object>) ((List<Object>) rev.get('bajas'))[0]).get('numeroEndoso'));

		Map<String, Object> alta = mov('alta', null, new Map<String, Object>{ 'nombreCompleto' => 'Rosa Núñez Vega', 'parentesco' => 'Titular',
			'sexo' => 'Mujer', 'certificado' => '010' });
		alta.put('endoso', '5');
		Map<String, Object> baja = mov('baja', pedro, null);
		baja.put('endoso', '15');
		Test.startTest();
		Map<String, Object> r = MovimientosColectivoController.aplicar(pol.Id, JSON.serialize(new Map<String, Object>{
			'movimientos' => new List<Object>{ alta, baja },
			'endoso' => new Map<String, Object>{ 'total' => 999 },
			'endosos' => new Map<String, Object>{
				'5' => new Map<String, Object>{ 'primaNeta' => 3000.5, 'derechos' => 0, 'iva' => 603.16, 'total' => 3603.66 },
				'15' => new Map<String, Object>{ 'primaNeta' => -2000, 'iva' => -320, 'total' => -2320 }
			}
		}));
		Id sinMovs = EndosoPoliza.registrarEndoso(pol.Id, null, 'Beneficio adicional COVID-19 · categorías 00, 01', '2023-12-01',
			JSON.serialize(new Map<String, Object>{ 'total' => 0 }));
		Test.stopTest();

		System.assertEquals(2, r.get('endosos'), 'Un endoso por número');
		Map<String, InsurancePolicyTransaction> porNumero = new Map<String, InsurancePolicyTransaction>();
		for (InsurancePolicyTransaction t : [SELECT TransactionNumber, TransactionAmount, TransactionTaxAmount, PriorTransactionId
				FROM InsurancePolicyTransaction WHERE InsurancePolicyId = :pol.Id AND TransactionNumber != null]) {
			porNumero.put(t.TransactionNumber, t);
		}
		System.assertEquals(3000.5, porNumero.get('5').TransactionAmount, 'Prima del endoso 5');
		System.assertEquals(-320, porNumero.get('15').TransactionTaxAmount, 'IVA del endoso 15 (devolución)');
		// Se aplican primero las bajas: el endoso 5 (alta) sigue al 15 (baja).
		System.assertEquals(porNumero.get('15').Id, porNumero.get('5').PriorTransactionId, 'Los endosos nuevos quedan encadenados');
		System.assertEquals('15', [SELECT Transaccion__r.TransactionNumber FROM Movimiento_Poliza__c
			WHERE Poliza__c = :pol.Id AND Tipo__c = 'Baja' LIMIT 1].Transaccion__r.TransactionNumber, 'La baja quedó en su endoso');

		InsurancePolicyTransaction c = [SELECT Name, EffectiveFromDate, TransactionNumber FROM InsurancePolicyTransaction WHERE Id = :sinMovs];
		System.assert(c.Name.contains('Beneficio adicional COVID-19'), c.Name);
		System.assertEquals(Date.newInstance(2023, 12, 1), c.EffectiveFromDate);
		List<Map<String, Object>> endosos = EndosoPoliza.getEndosos(pol.Id);
		System.assertEquals(3, endosos.size(), 'Los dos del archivo y el de la cláusula');
		for (Map<String, Object> e : endosos) {
			if (e.get('id') == sinMovs) { System.assertEquals(0, ((List<Object>) e.get('movimientos')).size(), 'Sin movimientos'); }
		}
		// Mismo número: se actualiza el endoso existente.
		System.assertEquals(porNumero.get('5').Id, EndosoPoliza.registrarEndoso(pol.Id, '5', 'Alta', null, null));
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Archivo de la aseguradora contra la póliza: reconoce a la persona aunque el nombre venga en otro orden y
	 *               sin acentos, propone cambios, altas (con su titular) y, si es censo completo, bajas.
	 * @return void
	 */
	@isTest
	static void testCompararArchivo() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'POL-MOV-1'];
		String archivo = JSON.serialize(new List<Object>{
			new Map<String, Object>{ 'nombreCompleto' => 'PEREZ GARCIA JUAN', 'certificado' => '001', 'prima' => 5500, 'fechaNacimiento' => '1980-05-10' },
			new Map<String, Object>{ 'nombreCompleto' => 'Maria Lopez Ruiz', 'certificado' => '001', 'parentesco' => 'Cónyuge', 'titularIndex' => 0 },
			new Map<String, Object>{ 'nombreCompleto' => 'Diego Pérez López', 'parentesco' => 'Hijo(a)', 'titularIndex' => 0 },
			new Map<String, Object>{ 'nombreCompleto' => 'Rosa Nava', 'certificado' => '010', 'parentesco' => 'Titular' },
			new Map<String, Object>{ 'nombreCompleto' => 'Leo Nava', 'parentesco' => 'Hijo(a)', 'titularIndex' => 3 }
		});
		Test.startTest();
		Map<String, Object> completo = MovimientosColectivoController.compararArchivo(pol.Id, archivo, true);
		Map<String, Object> parcial = MovimientosColectivoController.compararArchivo(pol.Id, archivo, false);
		Test.stopTest();
		System.assertEquals(1, ((List<Object>) completo.get('cambios')).size(), 'Cambio de prima de Juan');
		System.assertEquals(1, completo.get('sinCambios'), 'María sin cambios');
		List<Object> altas = (List<Object>) completo.get('altas');
		System.assertEquals(3, altas.size(), 'Diego, Rosa y Leo');
		Map<String, Object> diego = (Map<String, Object>) altas[0];
		System.assertNotEquals(null, diego.get('titularId'), 'Diego depende de Juan, que ya está en la póliza');
		Map<String, Object> leo = (Map<String, Object>) altas[2];
		System.assertEquals(3, leo.get('titularRef'), 'Leo depende del alta de Rosa');
		System.assertEquals(1, ((List<Object>) completo.get('bajas')).size(), 'Pedro no viene en el censo completo');
		System.assertEquals(true, ((Map<String, Object>) ((List<Object>) completo.get('bajas'))[0]).get('faltante'),
			'Pedro no viene en el archivo: la baja se propone desmarcada');
		System.assertEquals(0, ((List<Object>) parcial.get('bajas')).size(), 'Solo movimientos: no propone bajas');
	}

	/**
	 * @creation date: 10/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Archivo con tipo de movimiento: una baja de un asegurado existente se propone como baja (aunque se
	 *               marque censo completo, solo trae movimientos) y la de alguien que no existe solo se avisa.
	 * @return void
	 */
	@isTest
	static void testCompararArchivoConBajas() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'POL-MOV-1'];
		String archivo = JSON.serialize(new List<Object>{
			new Map<String, Object>{ 'fila' => 2, 'nombreCompleto' => 'PEREZ GARCIA JUAN', 'certificado' => '001', 'movimiento' => 'Baja' },
			new Map<String, Object>{ 'fila' => 3, 'nombreCompleto' => 'Nadie Existe', 'certificado' => '999', 'movimiento' => 'Baja' }
		});
		Test.startTest();
		Map<String, Object> r = MovimientosColectivoController.compararArchivo(pol.Id, archivo, true);
		Test.stopTest();
		List<Object> bajas = (List<Object>) r.get('bajas');
		System.assertEquals(1, bajas.size(), 'Solo Juan se propone como baja (no Pedro, que no viene): ' + r);
		System.assertEquals(participante(pol.Id, 'Juan%'), Id.valueOf((String) ((Map<String, Object>) bajas[0]).get('id')));
		System.assertEquals(null, ((Map<String, Object>) bajas[0]).get('faltante'), 'La baja la pide el archivo: va marcada');
		System.assertEquals(1, ((List<Object>) r.get('noEncontrados')).size(), 'Nadie Existe solo se avisa');
		System.assertEquals(0, ((List<Object>) r.get('altas')).size(), 'Una baja que no existe no se vuelve alta');
	}

	/**
	 * @creation date: 10/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Un cambio del archivo de alguien que no existe se aplica internamente como alta, pero se propone con sus
	 *               datos nuevos, se cuenta y se registra como cambio.
	 * @return void
	 */
	/**
	 * @creation date: 10/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Archivos del asegurado: se leen los del propio registro y se cuentan en la lista.
	 * @return void
	 */
	@isTest
	static void testArchivosAsegurado() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'POL-MOV-1'];
		Id juan = participante(pol.Id, 'Juan%');
		ContentVersion cv = new ContentVersion(Title = 'Acta', PathOnClient = 'acta.pdf', VersionData = Blob.valueOf('pdf'));
		insert cv;
		Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
		insert new ContentDocumentLink(ContentDocumentId = docId, LinkedEntityId = juan, ShareType = 'V');
		Test.startTest();
		Map<String, Object> r = MovimientosColectivoController.archivosAsegurado(juan);
		Map<String, Object> datos = MovimientosColectivoController.getDatos(pol.Id);
		Test.stopTest();
		System.assertEquals(1, ((List<Object>) r.get('archivos')).size());
		System.assertNotEquals(null, r.get('destinoId'), 'Hay dónde adjuntar');
		for (Object o : (List<Object>) datos.get('miembros')) {
			Map<String, Object> m = (Map<String, Object>) o;
			if (m.get('id') == (String) juan) { System.assertEquals(1, m.get('archivos'), 'El botón muestra cuántos tiene'); }
		}
		try { MovimientosColectivoController.archivosAsegurado(null); System.assert(false); } catch (AuraHandledException e) { System.assert(true); }
	}

	// Subida de archivos uno por uno (sin el límite de 10 del componente estándar).
	@isTest
	static void testSubirArchivo() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'POL-MOV-1'];
		Id doc = MovimientosColectivoController.subirArchivo(pol.Id, 'INE JUAN.pdf', EncodingUtil.base64Encode(Blob.valueOf('pdf')));
		ContentDocument d = [SELECT Title FROM ContentDocument WHERE Id = :doc];
		System.assertEquals('INE JUAN', d.Title);
		System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink WHERE ContentDocumentId = :doc AND LinkedEntityId = :pol.Id]);
		try { MovimientosColectivoController.subirArchivo(pol.Id, 'vacio.pdf', ''); System.assert(false); } catch (AuraHandledException e) { System.assert(true); }
	}

	@isTest
	static void testAsignarArchivos() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'POL-MOV-1'];
		Id juan = participante(pol.Id, 'Juan%');
		ContentVersion cv = new ContentVersion(Title = 'INE Juan', PathOnClient = 'ine juan.pdf', VersionData = Blob.valueOf('pdf'));
		insert cv;
		Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
		// Se subió a la póliza con la carga múltiple.
		insert new ContentDocumentLink(ContentDocumentId = docId, LinkedEntityId = pol.Id, ShareType = 'V');
		String json = JSON.serialize(new List<Object>{
			new Map<String, Object>{ 'documentId' => (String) docId, 'registroId' => (String) juan },
			new Map<String, Object>{ 'documentId' => null, 'registroId' => (String) juan }
		});
		Test.startTest();
		Integer n = MovimientosColectivoController.asignarArchivos(pol.Id, json);
		// Repetirlo no duplica el enlace.
		MovimientosColectivoController.asignarArchivos(pol.Id, json);
		Map<String, Object> r = MovimientosColectivoController.archivosAsegurado(juan);
		Test.stopTest();
		System.assertEquals(1, n);
		System.assertEquals(1, ((List<Object>) r.get('archivos')).size(), 'Quedó en el asegurado');
		System.assertEquals(0, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :pol.Id AND ContentDocumentId = :docId], 'Ya no está en la póliza');
		System.assertEquals(0, MovimientosColectivoController.asignarArchivos(pol.Id, '[]'));
		try { MovimientosColectivoController.asignarArchivos(pol.Id, 'no es json'); System.assert(false); } catch (AuraHandledException e) { System.assert(true); }
	}

	@isTest
	static void testCambioDeNombre() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'POL-MOV-1'];
		String archivo = JSON.serialize(new List<Object>{
			new Map<String, Object>{ 'fila' => 2, 'nombreCompleto' => 'Juan Carlos Pérez García', 'certificado' => '001', 'movimiento' => 'Cambio' }
		});
		Test.startTest();
		Map<String, Object> r = MovimientosColectivoController.compararArchivo(pol.Id, archivo, false);
		Test.stopTest();
		System.assertEquals(0, ((List<Object>) r.get('altas')).size(), 'No se vuelve alta: ' + r);
		List<Object> cambios = (List<Object>) r.get('cambios');
		System.assertEquals(1, cambios.size(), 'Es un cambio de la misma persona');
		Map<String, Object> c = (Map<String, Object>) cambios[0];
		System.assertEquals(participante(pol.Id, 'Juan%'), Id.valueOf((String) c.get('id')));
		Map<String, Object> d = (Map<String, Object>) ((List<Object>) c.get('diferencias'))[0];
		System.assertEquals('Nombre', d.get('campo'));
		System.assertEquals('Juan Carlos Pérez García', d.get('despues'));
		System.assertEquals('Juan Carlos Pérez García', ((Map<String, Object>) c.get('datos')).get('nombreCompleto'), 'Se aplica el nombre nuevo');
	}

	@isTest
	static void testDocumentoBaja() {
		EmailTemplate tpl = new EmailTemplate(Name = 'Baja Test', DeveloperName = 'Baja_Movimientos_Test_X1',
			TemplateType = 'text', FolderId = UserInfo.getUserId(), IsActive = true, Subject = 'Baja', Body = 'Tu baja');
		System.runAs(new User(Id = UserInfo.getUserId())) { insert tpl; }
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'POL-MOV-1'];
		Id pedro = participante(pol.Id, 'Pedro%');
		update new InsurancePolicyParticipant(Id = pedro, Correo_Enviado__c = true);
		Map<String, Object> b = mov('baja', pedro, null);
		b.put('correoPersonal', 'pedro.personal@test.com');
		MovimientosColectivoController.aplicar(pol.Id, JSON.serialize(new List<Object>{ b }));
		System.assertEquals(false, [SELECT Correo_Enviado__c FROM InsurancePolicyParticipant WHERE Id = :pedro].Correo_Enviado__c,
			'La baja queda con correo pendiente (se envía después)');
		// Otro archivo del asegurado que NO debe ir en el correo de baja.
		MovimientosColectivoController.subirArchivo(pedro, 'alta.pdf', EncodingUtil.base64Encode(Blob.valueOf('alta')));

		Test.startTest();
		Id doc = MovimientosColectivoController.subirDocumentoBaja(pol.Id, pedro, 'baja.pdf', EncodingUtil.base64Encode(Blob.valueOf('baja')));
		Map<String, Object> r;
		try {
			r = ParticipantesPolizaController.enviarCorreo(pol.Id, new List<Id>{ pedro }, tpl.Id, true);
		} catch (AuraHandledException e) {
			System.assertNotEquals(null, e.getMessage(), 'Org sin entrega de correo');
		}
		Test.stopTest();
		Id movBaja = [SELECT Id FROM Movimiento_Poliza__c WHERE Participante__c = :pedro AND Tipo__c = 'Baja' LIMIT 1].Id;
		System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :movBaja AND ContentDocumentId = :doc],
			'El documento queda en el movimiento de baja');
		if (r != null) { System.assertNotEquals(null, r.get('enviados')); }
		try {
			MovimientosColectivoController.subirDocumentoBaja(pol.Id, participante(pol.Id, 'Juan%'), 'x.pdf', 'eA==');
			System.assert(false, 'Sin baja no se puede');
		} catch (AuraHandledException e) {
			System.assert(true);
		}
	}

	@isTest
	static void testNombreDelContactoParaExcel() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'POL-MOV-1'];
		InsurancePolicyParticipant pedro = [SELECT Id FROM InsurancePolicyParticipant
			WHERE InsurancePolicyId = :pol.Id AND ParticipantName LIKE 'Pedro%' LIMIT 1];
		Contact c = new Contact(FirstName = 'PEDRO', LastName = 'GOMEZ RUIZ', Sexo__c = 'Masculino');
		insert c;
		update new InsurancePolicyParticipant(Id = pedro.Id, PrimaryParticipantContactId = c.Id);
		Test.startTest();
		Map<String, Object> datos = MovimientosColectivoController.getDatos(pol.Id);
		Test.stopTest();
		Map<String, Object> fila = null;
		for (Object o : (List<Object>) datos.get('miembros')) {
			Map<String, Object> m = (Map<String, Object>) o;
			if (m.get('id') == (String) pedro.Id) { fila = m; }
		}
		System.assertNotEquals(null, fila, 'Pedro está en los asegurados');
		System.assertEquals('PEDRO', fila.get('nombres'), 'Nombre(s) del contacto');
		System.assertEquals('GOMEZ', fila.get('apellidoPaterno'), 'Apellido paterno tomado del LastName');
		System.assertEquals('RUIZ', fila.get('apellidoMaterno'), 'Apellido materno tomado del LastName');
		System.assertEquals('Masculino', fila.get('sexoContacto'), 'Sexo del contacto');
	}

	@isTest
	static void testCambioDeCorreo() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'POL-MOV-1'];
		InsurancePolicyParticipant pedro = [SELECT Id, PrimaryParticipantContactId, PrimaryParticipantAccountId FROM InsurancePolicyParticipant
			WHERE InsurancePolicyId = :pol.Id AND ParticipantName LIKE 'Pedro%' LIMIT 1];
		Boolean dondeGuardar = pedro.PrimaryParticipantContactId != null || pedro.PrimaryParticipantAccountId != null;
		Test.startTest();
		try {
			Map<String, Object> r = MovimientosColectivoController.aplicar(pol.Id, JSON.serialize(new List<Object>{
				mov('cambio', pedro.Id, new Map<String, Object>{ 'email' => 'pedro.nuevo@test.com' })
			}));
			System.assert(dondeGuardar, 'Sin contacto ni cuenta debe avisar');
			System.assertEquals(1, r.get('cambios'), 'El correo cuenta como cambio');
			System.assertEquals(false, [SELECT Correo_Enviado__c FROM InsurancePolicyParticipant WHERE Id = :pedro.Id].Correo_Enviado__c,
				'El cambio queda con correo pendiente');
		} catch (AuraHandledException e) {
			System.assert(!dondeGuardar, 'Solo falla si no hay dónde guardar: ' + e.getMessage());
		}
		Test.stopTest();
		if (dondeGuardar) {
			List<InsurancePolicyParticipant> ps = [SELECT Id, PrimaryParticipantContactId, PrimaryParticipantAccountId FROM InsurancePolicyParticipant WHERE Id = :pedro.Id];
			System.assertEquals('pedro.nuevo@test.com', ParticipantesPolizaController.correosDe(ps).get(pedro.Id), 'Correo actualizado');
			System.assert([SELECT Detalle__c FROM Movimiento_Poliza__c WHERE Participante__c = :pedro.Id AND Tipo__c = 'Cambio' LIMIT 1]
				.Detalle__c.contains('Correo'), 'Queda en el historial');
		}
	}

	@isTest
	static void testAltaDuplicada() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'POL-MOV-1'];
		String archivo = JSON.serialize(new List<Object>{
			new Map<String, Object>{ 'fila' => 2, 'nombreCompleto' => 'Juan Pérez García', 'certificado' => '001',
				'fechaNacimiento' => '1980-05-10', 'movimiento' => 'Alta' }
		});
		Map<String, Object> r = MovimientosColectivoController.compararArchivo(pol.Id, archivo, false);
		System.assertEquals(0, ((List<Object>) r.get('altas')).size(), 'No se duplica: ' + r);
		List<Object> dup = (List<Object>) r.get('duplicados');
		System.assertEquals(1, dup.size(), 'Se avisa el duplicado');
		System.assertEquals(0, r.get('sinCambios'), 'No se cuenta como sin cambios');
	}

	@isTest
	static void testCambioDeNombreYFecha() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'POL-MOV-1'];
		String archivo = JSON.serialize(new List<Object>{
			new Map<String, Object>{ 'fila' => 2, 'nombreCompleto' => 'Claudia Pérez Mendoza', 'certificado' => '0000000001',
				'fechaNacimiento' => '2001-12-27', 'movimiento' => 'Cambio' }
		});
		Map<String, Object> r = MovimientosColectivoController.compararArchivo(pol.Id, archivo, false);
		List<Object> cambios = (List<Object>) r.get('cambios');
		System.assertEquals(1, cambios.size(), 'Se reconoce por certificado aunque cambie la fecha: ' + r);
		Map<String, Object> c = (Map<String, Object>) cambios[0];
		System.assertEquals(participante(pol.Id, 'Juan%'), Id.valueOf((String) c.get('id')));
		Map<String, Object> d = (Map<String, Object>) ((List<Object>) c.get('diferencias'))[0];
		System.assertEquals('Nombre', d.get('campo'));
		System.assertNotEquals('—', d.get('antes'), 'Trae el nombre anterior');
	}

	@isTest
	static void testCambioQueEsAlta() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'POL-MOV-1'];
		String archivo = JSON.serialize(new List<Object>{
			new Map<String, Object>{ 'fila' => 2, 'nombreCompleto' => 'Rosa Nueva Luna', 'certificado' => '050', 'movimiento' => 'Cambio',
				'prima' => 1200, 'categoria' => 'Empleados' }
		});
		Map<String, Object> r = MovimientosColectivoController.compararArchivo(pol.Id, archivo, false);
		List<Object> altas = (List<Object>) r.get('altas');
		System.assertEquals(1, altas.size(), 'Internamente es alta');
		Map<String, Object> a = (Map<String, Object>) altas[0];
		System.assertEquals(true, a.get('comoCambio'), 'Se ve como cambio');
		System.assert(!((List<Object>) a.get('diferencias')).isEmpty(), 'Con sus datos nuevos');

		Map<String, Object> m = mov('alta', null, (Map<String, Object>) a.get('datos'));
		m.put('comoCambio', true);
		Test.startTest();
		Map<String, Object> res = MovimientosColectivoController.aplicar(pol.Id, JSON.serialize(new List<Object>{ m }));
		Test.stopTest();
		System.assertEquals(0, res.get('altas'), 'No se cuenta como alta');
		System.assertEquals(1, res.get('cambios'), 'Se cuenta como cambio');
		System.assertEquals('Cambio', [SELECT Tipo__c FROM Movimiento_Poliza__c WHERE Poliza__c = :pol.Id AND Asegurado__c LIKE 'Rosa%' LIMIT 1].Tipo__c);
		System.assertEquals(1, [SELECT COUNT() FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :pol.Id AND ParticipantName LIKE 'Rosa%'],
			'La persona sí se agrega');
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Renovación: el censo se llena desde la póliza anterior, se aplican baja (con motivo, registrada contra la
	 *               póliza anterior), alta y cambio; al emitir la nueva vigencia queda ligada a la anterior.
	 * @return void
	 */
	@isTest
	static void testRenovacion() {
		InsurancePolicy anterior = [SELECT Id, NameInsuredId, ExpirationDate FROM InsurancePolicy WHERE Name = 'POL-MOV-1'];
		Opportunity renov = [SELECT Id FROM Opportunity WHERE Name = 'Opp Renovacion'];
		Map<String, Object> datos = MovimientosColectivoController.getDatos(renov.Id);
		System.assertEquals('oportunidad', datos.get('contexto'));
		System.assertEquals(anterior.Id, datos.get('polizaAnteriorId'), 'Encuentra la póliza que se renueva');
		System.assertEquals(3, datos.get('aseguradosAnterior'));

		Test.startTest();
		Integer total = MovimientosColectivoController.traerDePoliza(renov.Id, false);
		System.assertEquals(3, total, 'Censo de la renovación con los vigentes');
		try {
			MovimientosColectivoController.traerDePoliza(renov.Id, false);
			System.assert(false, 'Sin confirmar no reemplaza');
		} catch (AuraHandledException e) {
			System.assert(e.getMessage().contains('reemplazar'), e.getMessage());
		}
		Id pedro = [SELECT Id FROM GroupCensusMember WHERE GroupCensus.Oportunidad__c = :renov.Id AND Name LIKE 'Pedro%'].Id;
		Id juan = [SELECT Id FROM GroupCensusMember WHERE GroupCensus.Oportunidad__c = :renov.Id AND Name LIKE 'Juan%'].Id;
		Map<String, Object> hijo = mov('alta', null, new Map<String, Object>{ 'nombreCompleto' => 'Diego Pérez López', 'parentesco' => 'Hijo(a)',
			'sexo' => 'Hombre', 'fechaNacimiento' => '2015-02-02' });
		hijo.put('titularId', juan);
		Map<String, Object> r = MovimientosColectivoController.aplicar(renov.Id, JSON.serialize(new List<Object>{
			mov('baja', pedro, null),
			mov('cambio', juan, new Map<String, Object>{ 'sumaAsegurada' => 1200000, 'sexo' => 'Hombre' }),
			hijo
		}));
		Test.stopTest();
		System.assertEquals(1, r.get('bajas'));
		System.assertEquals(1, r.get('cambios'));
		System.assertEquals(1, r.get('altas'));
		System.assertEquals(3, [SELECT COUNT() FROM GroupCensusMember WHERE GroupCensus.Oportunidad__c = :renov.Id], 'Juan, María y Diego');
		Movimiento_Poliza__c baja = [SELECT Poliza__c, Participante__c, Motivo_Baja__c, Contexto__c FROM Movimiento_Poliza__c
			WHERE Oportunidad__c = :renov.Id AND Tipo__c = 'Baja'];
		System.assertEquals(anterior.Id, baja.Poliza__c, 'La baja de la renovación queda contra la póliza anterior');
		System.assertNotEquals(null, baja.Participante__c, 'Ligada al participante anterior');
		System.assertEquals('Renovacion', baja.Contexto__c);

		// Emisión de la nueva vigencia: queda ligada a la anterior y cada asegurado a su participante anterior.
		InsurancePolicy nueva = poliza('POL-MOV-2', anterior.NameInsuredId, renov.Id, anterior.ExpirationDate);
		insert nueva;
		CensoColectivoController.copiarCensoAPoliza(renov.Id, nueva.Id);
		System.assertEquals(anterior.Id, [SELECT PriorPolicyId FROM InsurancePolicy WHERE Id = :nueva.Id].PriorPolicyId, 'Póliza anterior');
		InsurancePolicyParticipant juanNuevo = [SELECT PriorParticipantId, OriginalParticipantId FROM InsurancePolicyParticipant
			WHERE InsurancePolicyId = :nueva.Id AND ParticipantName LIKE 'Juan%'];
		System.assertEquals(participante(anterior.Id, 'Juan%'), juanNuevo.PriorParticipantId, 'Participante anterior');
		System.assertEquals(juanNuevo.PriorParticipantId, juanNuevo.OriginalParticipantId, 'Antigüedad desde el original');
		System.assertEquals(null, [SELECT PriorParticipantId FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :nueva.Id
			AND ParticipantName = 'Diego Pérez López'].PriorParticipantId, 'El alta nueva no tiene anterior');
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Baja de un titular en la misma carga que un cambio de su dependiente (como llega del archivo): el
	 *               dependiente sale con su titular y su cambio se omite, en la póliza y en la renovación. No se puede dar
	 *               de alta a un dependiente de un titular que se está dando de baja.
	 * @return void
	 */
	@isTest
	static void testBajaTitularConDependientes() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'POL-MOV-1'];
		Id juan = participante(pol.Id, 'Juan%');
		Id maria = participante(pol.Id, 'Mar%');
		Map<String, Object> hijo = mov('alta', null, new Map<String, Object>{ 'nombreCompleto' => 'Diego Pérez', 'parentesco' => 'Hijo(a)' });
		hijo.put('titularId', juan);
		try {
			MovimientosColectivoController.aplicar(pol.Id, JSON.serialize(new List<Object>{ mov('baja', juan, null), hijo }));
			System.assert(false, 'No se da de alta un dependiente de un titular que se da de baja');
		} catch (AuraHandledException e) {
			System.assert(e.getMessage().contains('se está dando de baja'), e.getMessage());
		}
		Test.startTest();
		Map<String, Object> r = MovimientosColectivoController.aplicar(pol.Id, JSON.serialize(new List<Object>{
			mov('baja', juan, null), mov('cambio', maria, new Map<String, Object>{ 'prima' => 999 }) }));
		System.assertEquals(2, r.get('bajas'), 'Juan y María');
		System.assertEquals(0, r.get('cambios'), 'El cambio de María se omite');
		System.assertEquals(false, [SELECT IsActiveParticipant FROM InsurancePolicyParticipant WHERE Id = :maria].IsActiveParticipant);

		Opportunity renov = [SELECT Id FROM Opportunity WHERE Name = 'Opp Renovacion'];
		MovimientosColectivoController.traerDePoliza(renov.Id, true);
		Id pedro = [SELECT Id FROM GroupCensusMember WHERE GroupCensus.Oportunidad__c = :renov.Id AND Name LIKE 'Pedro%'].Id;
		Map<String, Object> dep = mov('alta', null, new Map<String, Object>{ 'nombreCompleto' => 'Sara Gómez', 'parentesco' => 'Cónyuge', 'sexo' => 'Mujer' });
		dep.put('titularId', pedro);
		MovimientosColectivoController.aplicar(renov.Id, JSON.serialize(new List<Object>{ dep }));
		Id sara = [SELECT Id FROM GroupCensusMember WHERE GroupCensus.Oportunidad__c = :renov.Id AND Name = 'Sara Gómez'].Id;
		r = MovimientosColectivoController.aplicar(renov.Id, JSON.serialize(new List<Object>{
			mov('baja', pedro, null), mov('cambio', sara, new Map<String, Object>{ 'prima' => 999 }) }));
		Test.stopTest();
		System.assertEquals(2, r.get('bajas'), 'Pedro y Sara');
		System.assertEquals(0, r.get('cambios'));
		System.assertEquals(0, [SELECT COUNT() FROM GroupCensusMember WHERE GroupCensus.Oportunidad__c = :renov.Id AND (Name LIKE 'Pedro%' OR Name = 'Sara Gómez')]);
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Validaciones de los movimientos y helpers.
	 * @return void
	 */
	@isTest
	static void testValidaciones() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'POL-MOV-1'];
		Id juan = participante(pol.Id, 'Juan%');
		Map<String, Object> sinMotivo = mov('baja', juan, null);
		sinMotivo.remove('motivo');
		Map<String, Object> antes = mov('baja', juan, null);
		antes.put('fecha', '2019-01-01');
		Map<String, Object> malTitular = mov('alta', null, new Map<String, Object>{ 'nombreCompleto' => 'X Y' });
		malTitular.put('titularRef', 5);
		List<Object> casos = new List<Object>{
			'[]', JSON.serialize(new List<Object>{ new Map<String, Object>{ 'tipo' => 'otro' } }),
			JSON.serialize(new List<Object>{ new Map<String, Object>{ 'tipo' => 'baja', 'id' => juan, 'motivo' => motivo() } }),
			JSON.serialize(new List<Object>{ mov('alta', null, new Map<String, Object>()) }), JSON.serialize(new List<Object>{ malTitular }),
			JSON.serialize(new List<Object>{ antes }), 'no es json'
		};
		Integer errores = 0;
		for (Object c : casos) {
			try { MovimientosColectivoController.aplicar(pol.Id, (String) c); } catch (AuraHandledException e) { errores++; }
		}
		System.assertEquals(casos.size(), errores, 'Cada caso inválido se rechaza');
		System.assertEquals(true, [SELECT IsActiveParticipant FROM InsurancePolicyParticipant WHERE Id = :juan].IsActiveParticipant, 'Nada se aplicó');
		try { MovimientosColectivoController.compararArchivo(pol.Id, '{x', true); System.assert(false); } catch (AuraHandledException e) { System.assert(true); }

		// El motivo de baja es opcional.
		MovimientosColectivoController.aplicar(pol.Id, JSON.serialize(new List<Object>{ sinMotivo }));
		InsurancePolicyParticipant sinMotivoAplicada = [SELECT IsActiveParticipant, Motivo_Baja__c FROM InsurancePolicyParticipant WHERE Id = :juan];
		System.assertEquals(false, sinMotivoAplicada.IsActiveParticipant, 'La baja sin motivo se aplica');
		System.assertEquals(null, sinMotivoAplicada.Motivo_Baja__c);
		try { MovimientosColectivoController.getDatos(null); System.assert(false); } catch (AuraHandledException e) { System.assert(true); }

		System.assertEquals('Mujer', MovimientosColectivoController.sexoDe('Hija'));
		System.assertEquals('Hombre', MovimientosColectivoController.sexoDe('Marido'));
		System.assertEquals(null, MovimientosColectivoController.sexoDe(null));
		System.assertEquals('Cónyuge', MovimientosColectivoController.parentescoCenso('Mujer'));
		System.assertEquals('Hijo(a)', MovimientosColectivoController.parentescoCenso('Hijo'));
		System.assertEquals('Suegro(a)', MovimientosColectivoController.parentescoCenso('Suegra'));
		System.assertEquals('Padre/Madre', MovimientosColectivoController.parentescoCenso('Madre'));
		System.assertEquals('Otro', MovimientosColectivoController.parentescoCenso('Primo'));
		System.assertEquals(MovimientosColectivoController.llaveNombre('Juan Pérez García'), MovimientosColectivoController.llaveNombre('PEREZ GARCIA, JUAN'));

		// Una oportunidad sin póliza anterior no puede traer asegurados.
		Opportunity renov = [SELECT Id, AccountId FROM Opportunity WHERE Name = 'Opp Renovacion'];
		InsurancePolicy pol2 = new InsurancePolicy(Id = pol.Id);
		pol2.put('Ramo__c', 'Danos');
		update pol2;
		try { MovimientosColectivoController.traerDePoliza(renov.Id, true); System.assert(false); }
		catch (AuraHandledException e) { System.assert(e.getMessage().contains('póliza anterior'), e.getMessage()); }
	}

	/**
	 * @creation date: 17/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Solicitudes del cliente: cada registro abre una solicitud con folio (SOL-0001...), salvo que se
	 *               pida agregar los movimientos a una existente; un folio que no es de la póliza abre una nueva. La
	 *               tabla recibe la solicitud del último movimiento de cada asegurado y el resumen de las solicitudes.
	 * @return void
	 */
	@isTest
	static void testSolicitudes() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'POL-MOV-1'];
		Id juan = participante(pol.Id, 'Juan%');
		Id pedro = participante(pol.Id, 'Pedro%');
		Test.startTest();
		Map<String, Object> r1 = MovimientosColectivoController.aplicar(pol.Id, JSON.serialize(new List<Object>{
			mov('cambio', pedro, new Map<String, Object>{ 'prima' => 2500 }) }));
		Map<String, Object> r2 = MovimientosColectivoController.aplicar(pol.Id, JSON.serialize(new Map<String, Object>{
			'movimientos' => new List<Object>{ mov('cambio', juan, new Map<String, Object>{ 'prima' => 1800 }) }, 'solicitud' => 'SOL-0001' }));
		Map<String, Object> r3 = MovimientosColectivoController.aplicar(pol.Id, JSON.serialize(new Map<String, Object>{
			'movimientos' => new List<Object>{ mov('cambio', pedro, new Map<String, Object>{ 'prima' => 2600 }) }, 'solicitud' => 'nueva' }));
		Map<String, Object> r4 = MovimientosColectivoController.aplicar(pol.Id, JSON.serialize(new Map<String, Object>{
			'movimientos' => new List<Object>{ mov('cambio', pedro, new Map<String, Object>{ 'prima' => 2700 }) }, 'solicitud' => 'SOL-0099' }));
		Test.stopTest();
		System.assertEquals('SOL-0001', r1.get('solicitud'), 'El primer registro abre la primera solicitud');
		System.assertEquals('SOL-0001', r2.get('solicitud'), 'Se agrega a la solicitud elegida');
		System.assertEquals('SOL-0002', r3.get('solicitud'), 'Nueva solicitud');
		System.assertEquals('SOL-0003', r4.get('solicitud'), 'Un folio que no es de la póliza abre una nueva');
		Map<String, Object> datos = MovimientosColectivoController.getDatos(pol.Id);
		List<Map<String, Object>> sols = (List<Map<String, Object>>) datos.get('solicitudes');
		System.assertEquals(3, sols.size());
		System.assertEquals('SOL-0003', sols[0].get('folio'), 'La más reciente primero');
		System.assertEquals(2, sols[2].get('total'), 'SOL-0001 con dos movimientos');
		System.assertEquals(2, sols[2].get('cambios'));
		System.assertEquals(2, sols[2].get('abiertos'), 'Sin cerrar');
		System.assertEquals(new List<String>{ 'END-1' }, sols[2].get('endosos'));
		for (Object o : (List<Object>) datos.get('miembros')) {
			Map<String, Object> m = (Map<String, Object>) o;
			if (m.get('id') == juan) { System.assertEquals('SOL-0001', m.get('solicitud')); }
			if (m.get('id') == pedro) { System.assertEquals('SOL-0003', m.get('solicitud'), 'La de su último movimiento'); }
		}
	}

	/**
	 * @creation date: 17/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Solicitud del sitio (caso): al aplicar movimientos con su folio el caso sigue Solicitado y la
	 *               solicitud aparece como del sitio; al cerrar sus movimientos, el caso se concluye. El siguiente folio
	 *               cuenta los de los casos.
	 * @return void
	 */
	@isTest
	static void testSolicitudDelSitio() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'POL-MOV-1'];
		Id pedro = participante(pol.Id, 'Pedro%');
		Case c = new Case(RecordTypeId = EndosoPoliza.tipoCaso(), InsurancePolicy__c = pol.Id, Solicitud__c = 'SOL-0001',
			Subject = 'SOL-0001 · prueba', Origin = 'Sitio Web');
		insert c;
		System.assertEquals('SOL-0002', EndosoPoliza.siguienteFolio(pol.Id), 'Cuenta el folio del caso');
		List<Object> pendientes = (List<Object>) MovimientosColectivoController.getDatos(pol.Id).get('solicitudes');
		System.assertEquals(true, ((Map<String, Object>) pendientes[0]).get('pendiente'), 'Recibida, por atender');
		Test.startTest();
		Map<String, Object> r = MovimientosColectivoController.aplicar(pol.Id, JSON.serialize(new Map<String, Object>{
			'movimientos' => new List<Object>{ mov('cambio', pedro, new Map<String, Object>{ 'prima' => 2500 }) }, 'solicitud' => 'SOL-0001' }));
		Test.stopTest();
		System.assertEquals('SOL-0001', r.get('solicitud'), 'Se atiende con el folio del caso');
		System.assertEquals(c.Id, [SELECT Id FROM Case WHERE Id = :c.Id AND Status = :EndosoPoliza.estadoCaso('Creado')].Id,
			'Capturar movimientos no cambia el estatus');
		Map<String, Object> s = (Map<String, Object>) ((List<Object>) MovimientosColectivoController.getDatos(pol.Id).get('solicitudes'))[0];
		System.assertEquals(true, s.get('portal'));
		System.assertEquals('En proceso', s.get('estadoPortal'));
		System.assertEquals('Solicitado', s.get('seguimiento'), 'Nadie la ha atendido');
		MovimientosColectivoController.cerrarMovimiento([SELECT Id FROM Movimiento_Poliza__c WHERE Solicitud__c = 'SOL-0001' LIMIT 1].Id);
		System.assertEquals(true, [SELECT IsClosed FROM Case WHERE Id = :c.Id].IsClosed, 'Movimientos cerrados: caso concluido');
	}

	/**
	 * @creation date: 23/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: «Atender» pasa la solicitud del sitio de Solicitado a En proceso (aunque no tenga movimientos); una
	 *               concluida ya no se atiende.
	 * @return void
	 */
	@isTest
	static void testAtenderSolicitud() {
		InsurancePolicy pol = [SELECT Id FROM InsurancePolicy WHERE Name = 'POL-MOV-1'];
		Case c = new Case(RecordTypeId = EndosoPoliza.tipoCaso(), InsurancePolicy__c = pol.Id, Solicitud__c = 'SOL-0001',
			Subject = 'SOL-0001 · prueba', Origin = 'Sitio Web', Status = EndosoPoliza.estadoCaso('Solicitado'));
		insert c;
		System.assertEquals('Solicitado', EndosoPoliza.solicitudes(pol.Id, null)[0].get('seguimiento'));
		Test.startTest();
		EndosoPoliza.atenderSolicitud(c.Id);
		EndosoPoliza.atenderSolicitud(c.Id);
		System.assertEquals(EndosoPoliza.estadoCaso('En proceso'), [SELECT Status FROM Case WHERE Id = :c.Id].Status);
		System.assertEquals('En proceso', EndosoPoliza.solicitudes(pol.Id, null)[0].get('seguimiento'));
		update new Case(Id = c.Id, Status = EndosoPoliza.estadoCaso('Concluido'));
		Boolean cerrada = false;
		try { EndosoPoliza.atenderSolicitud(c.Id); } catch (AuraHandledException e) { cerrada = true; }
		System.assert(cerrada, 'Una solicitud concluida no se atiende');
		Test.stopTest();
	}
}
