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

		List<Object> movs = new List<Object>{
			mov('baja', juan, null),
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
		System.assertEquals(0, ((List<Object>) parcial.get('bajas')).size(), 'Solo movimientos: no propone bajas');
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
			'[]', JSON.serialize(new List<Object>{ sinMotivo }), JSON.serialize(new List<Object>{ new Map<String, Object>{ 'tipo' => 'otro' } }),
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
}
