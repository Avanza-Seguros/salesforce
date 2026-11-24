/**
 * @creation date: 23/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas de EliminarMovimientos: eliminar un registro o toda una solicitud deshace altas y bajas de
 *               asegurados, vehículos y ubicaciones, y no deja eliminar lo concluido ni lo que tiene movimientos posteriores.
 */
@isTest
private class EliminarMovimientosTest {

	static InsurancePolicy poliza(String numero, String ramo) {
		Account cliente = new Account(Name = 'Cliente ' + numero);
		insert cliente;
		String etapa = 'Prospecting';
		for (OpportunityStage s : [
			SELECT MasterLabel FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1
		]) { etapa = s.MasterLabel; }
		Opportunity opp = new Opportunity(Name = 'Opp ' + numero, AccountId = cliente.Id, StageName = etapa, CloseDate = Date.today().addDays(30));
		for (Schema.PicklistEntry pe : Opportunity.Ramo__c.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { opp.Ramo__c = pe.getValue(); break; }
		}
		insert opp;
		InsurancePolicy p = new InsurancePolicy(Name = numero, NameInsuredId = cliente.Id, Status = 'Inicial', Ramo__c = ramo,
			PremiumAmount = 1000, PaymentDueDate = Date.today().addDays(30), SourceOpportunityId = opp.Id,
			EffectiveDate = Datetime.now().addDays(-10), ExpirationDate = Datetime.now().addDays(355), Primer_Pago__c = 250);
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { p.PremiumFrequency = pe.getValue(); break; }
		}
		insert p;
		return p;
	}

	static Map<String, Object> mov(String tipo, Id id, Map<String, Object> datos) {
		Map<String, Object> m = new Map<String, Object>{ 'tipo' => tipo, 'fecha' => String.valueOf(Date.today()) };
		if (id != null) { m.put('id', id); }
		if (datos != null) { m.put('datos', datos); }
		return m;
	}

	// Titular con un hijo (SOL-0001) y otro titular (SOL-0002).
	static void altas(Id policyId) {
		Map<String, Object> hijo = mov('alta', null, new Map<String, Object>{ 'nombre' => 'Leo', 'apellidos' => 'Vega', 'parentesco' => 'Hijo(a)', 'sexo' => 'Hombre' });
		hijo.put('titularRef', 0);
		MovimientosColectivoController.aplicar(policyId, JSON.serialize(new List<Object>{
			mov('alta', null, new Map<String, Object>{ 'nombre' => 'Luz', 'apellidos' => 'Vega', 'parentesco' => 'Titular', 'sexo' => 'Mujer', 'sumaAsegurada' => 100000 }), hijo }));
		MovimientosColectivoController.aplicar(policyId, JSON.serialize(new List<Object>{
			mov('alta', null, new Map<String, Object>{ 'nombre' => 'Ana', 'apellidos' => 'Ruiz', 'parentesco' => 'Titular', 'sexo' => 'Mujer' }) }));
	}

	static Id participante(Id policyId, String nombre) {
		return [SELECT Id FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :policyId AND ParticipantName LIKE :nombre LIMIT 1].Id;
	}

	static Id movimiento(Id policyId, String nombre, String tipo) {
		return [SELECT Id FROM Movimiento_Poliza__c WHERE Poliza__c = :policyId AND Asegurado__c LIKE :nombre AND Tipo__c = :tipo LIMIT 1].Id;
	}

	static String error(Id policyId, String folio, Id movimientoId) {
		try {
			MovimientosColectivoController.eliminarMovimiento(policyId, folio, movimientoId);
			return null;
		} catch (AuraHandledException e) {
			return e.getMessage();
		}
	}

	@isTest
	static void altaConDependientesYSolicitud() {
		InsurancePolicy p = poliza('GMG-ELIM-1', 'GMM');
		altas(p.Id);
		Id rt = EndosoPoliza.tipoCaso();
		Case c = new Case(RecordTypeId = rt, InsurancePolicy__c = p.Id, Solicitud__c = 'SOL-0002', Subject = 'x', Origin = 'Sitio Web',
			Status = EndosoPoliza.estadoCaso('Solicitado'));
		insert c;
		Test.startTest();
		String r = MovimientosColectivoController.eliminarMovimiento(p.Id, 'SOL-0001', movimiento(p.Id, 'Luz%', 'Alta'));
		System.assert(r.contains('2 registros'), r);
		System.assertEquals(1, [SELECT COUNT() FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :p.Id], 'Se quitan el titular y su hijo');
		System.assertEquals(0, [SELECT COUNT() FROM Movimiento_Poliza__c WHERE Poliza__c = :p.Id AND Solicitud__c = 'SOL-0001']);
		System.assertEquals(1, [SELECT COUNT() FROM Contact WHERE FirstName = 'Luz' AND LastName = 'Vega'], 'El contacto se conserva');
		MovimientosColectivoController.eliminarMovimiento(p.Id, 'SOL-0002', null);
		Test.stopTest();
		System.assertEquals(0, [SELECT COUNT() FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :p.Id]);
		System.assertEquals(true, [SELECT IsClosed FROM Case WHERE Id = :c.Id].IsClosed);
		System.assertEquals(0, EndosoPoliza.solicitudes(p.Id, null).size(), 'Ya no se muestra');
		System.assertEquals('SOL-0003', EndosoPoliza.siguienteFolio(p.Id), 'El folio del caso no se repite');
		System.assertEquals(2, [SELECT COUNT() FROM Task WHERE WhatId = :p.Id AND Subject LIKE '%eliminado%']);
	}

	@isTest
	static void bajaYMovimientosPosteriores() {
		InsurancePolicy p = poliza('GMG-ELIM-2', 'GMM');
		altas(p.Id);
		Id luz = participante(p.Id, 'Luz%');
		MovimientosColectivoController.aplicar(p.Id, JSON.serialize(new List<Object>{ mov('baja', luz, null) }));
		Test.startTest();
		String posterior = error(p.Id, 'SOL-0001', movimiento(p.Id, 'Luz%', 'Alta'));
		System.assert(posterior != null && posterior.contains('movimiento posterior'), posterior);
		String titular = error(p.Id, 'SOL-0003', movimiento(p.Id, 'Leo%', 'Baja'));
		System.assert(titular != null && titular.contains('elimina primero su baja'), titular);
		MovimientosColectivoController.eliminarMovimiento(p.Id, 'SOL-0003', movimiento(p.Id, 'Luz%', 'Baja'));
		Test.stopTest();
		for (InsurancePolicyParticipant x : [SELECT IsActiveParticipant, Motivo_Baja__c, EffectiveToDate FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :p.Id]) {
			System.assertEquals(true, x.IsActiveParticipant, 'El titular y su hijo vuelven a quedar vigentes');
			System.assertEquals(p.ExpirationDate.date(), x.EffectiveToDate);
		}
		System.assertEquals(0, [SELECT COUNT() FROM Movimiento_Poliza__c WHERE Poliza__c = :p.Id AND Tipo__c = 'Baja']);
	}

	@isTest
	static void cambioConcluidoYCargaInicial() {
		InsurancePolicy p = poliza('GMG-ELIM-3', 'GMM');
		altas(p.Id);
		Id ana = participante(p.Id, 'Ana%');
		MovimientosColectivoController.aplicar(p.Id, JSON.serialize(new List<Object>{ mov('cambio', ana, new Map<String, Object>{ 'rfc' => 'RUAA900101AAA' }) }));
		update new Movimiento_Poliza__c(Id = movimiento(p.Id, 'Leo%', 'Alta'), Fecha_Cierre__c = Datetime.now());
		Test.startTest();
		String concluido = error(p.Id, 'SOL-0001', null);
		System.assert(concluido != null && concluido.contains('Concluido'), concluido);
		System.assert(error(p.Id, null, null).contains('solicitud'), 'La carga inicial no se elimina');
		System.assert(error(p.Id, 'SOL-0001', movimiento(p.Id, 'Ana%', 'Alta')).contains('ya no existe'), 'De otra solicitud');
		MovimientosColectivoController.eliminarMovimiento(p.Id, 'SOL-0003', null);
		Test.stopTest();
		System.assertEquals('RUAA900101AAA', [SELECT Identificacion__c FROM InsurancePolicyParticipant WHERE Id = :ana].Identificacion__c, 'El dato se queda');
		System.assertEquals(3, [SELECT COUNT() FROM Movimiento_Poliza__c WHERE Poliza__c = :p.Id]);
	}

	@isTest
	static void vehiculos() {
		InsurancePolicy p = poliza('FLOT-ELIM-1', 'Automoviles');
		insert new Inciso_Flotilla__c(Poliza__c = p.Id, Numero_Inciso__c = 1, Descripcion__c = 'NISSAN VERSA', Serie__c = 'AAA111',
			Modelo__c = 2020, Fecha_Alta__c = Date.today().addDays(-10));
		Id versa = [SELECT Id FROM Inciso_Flotilla__c WHERE Poliza__c = :p.Id].Id;
		MovimientosFlotillaController.aplicar(p.Id, JSON.serialize(new List<Object>{ mov('baja', versa, null),
			mov('alta', null, new Map<String, Object>{ 'serie' => 'JTDKT9D38ED585824', 'descripcion' => 'TOYOTA YARIS', 'modelo' => 2021 }) }));
		Test.startTest();
		MovimientosColectivoController.eliminarMovimiento(p.Id, 'SOL-0001', null);
		Test.stopTest();
		System.assertEquals(1, [SELECT COUNT() FROM Inciso_Flotilla__c WHERE Poliza__c = :p.Id], 'El vehículo del alta se quita');
		System.assertEquals(null, [SELECT Fecha_Baja__c FROM Inciso_Flotilla__c WHERE Id = :versa].Fecha_Baja__c, 'La baja se deshace');
		System.assertEquals(0, [SELECT COUNT() FROM InsurancePolicyAsset WHERE InsurancePolicyId = :p.Id]);
		System.assertEquals(0, [SELECT COUNT() FROM Movimiento_Poliza__c WHERE Poliza__c = :p.Id]);
	}

	@isTest
	static void ubicaciones() {
		InsurancePolicy p = poliza('DANOS-ELIM-1', 'Danos');
		MovimientosUbicacionesController.aplicar(p.Id, JSON.serialize(new List<Object>{
			mov('alta', null, new Map<String, Object>{ 'nombre' => 'Bodega', 'direccion' => 'Av. Uno 100, Col. Centro, CP 06000' }) }));
		Id bien = [SELECT Id FROM InsurancePolicyAsset WHERE InsurancePolicyId = :p.Id].Id;
		MovimientosUbicacionesController.aplicar(p.Id, JSON.serialize(new List<Object>{ mov('baja', bien, null) }));
		Test.startTest();
		MovimientosColectivoController.eliminarMovimiento(p.Id, 'SOL-0002', null);
		InsurancePolicyAsset a = [SELECT IsActive, Fecha_Baja__c FROM InsurancePolicyAsset WHERE Id = :bien];
		System.assert(a.IsActive && a.Fecha_Baja__c == null, 'La baja se deshace');
		MovimientosColectivoController.eliminarMovimiento(p.Id, 'SOL-0001', null);
		Test.stopTest();
		System.assertEquals(0, [SELECT COUNT() FROM InsurancePolicyAsset WHERE InsurancePolicyId = :p.Id], 'La ubicación del alta se quita');
	}
}
