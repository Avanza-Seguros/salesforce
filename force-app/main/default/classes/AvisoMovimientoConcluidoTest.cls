/**
 * @creation date: 23/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas de AvisoMovimientoConcluido: al concluir una solicitud se envía el resumen al cliente; también la
 *               prima de cada movimiento (complemento) y la de la solicitud.
 */
@isTest
private class AvisoMovimientoConcluidoTest {

	@TestSetup
	static void setup() {
		Account cliente = new Account(Name = 'Cliente Concluido', Correo_electronico__c = 'cliente@prueba.test');
		insert cliente;
		String etapa = 'Prospecting';
		for (OpportunityStage s : [
			SELECT MasterLabel FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1
		]) { etapa = s.MasterLabel; }
		Opportunity opp = new Opportunity(Name = 'Opp concluido', AccountId = cliente.Id, StageName = etapa, CloseDate = Date.today().addDays(30));
		for (Schema.PicklistEntry pe : Opportunity.Ramo__c.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { opp.Ramo__c = pe.getValue(); break; }
		}
		insert opp;
		InsurancePolicy p = new InsurancePolicy(Name = 'GMG-CONCLUIDO', NameInsuredId = cliente.Id, Status = 'Inicial', Ramo__c = 'GMM',
			PremiumAmount = 1000, PaymentDueDate = Date.today().addDays(30), SourceOpportunityId = opp.Id,
			EffectiveDate = Datetime.now().addDays(-10), ExpirationDate = Datetime.now().addDays(355), Primer_Pago__c = 250);
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { p.PremiumFrequency = pe.getValue(); break; }
		}
		insert p;
		Contact c = new Contact(LastName = 'Prueba', FirstName = 'Ana', AccountId = cliente.Id);
		insert c;
		InsurancePolicyParticipant ana = new InsurancePolicyParticipant(InsurancePolicyId = p.Id, PrimaryParticipantContactId = c.Id,
			Role = InsurancePolicyParticipant.Role.getDescribe().getPicklistValues()[0].getValue(), ParticipantCode = 'ASIGNAR', IsActiveParticipant = true);
		insert ana;
		insert new List<Movimiento_Poliza__c>{
			new Movimiento_Poliza__c(Poliza__c = p.Id, Solicitud__c = 'SOL-0001', Tipo__c = 'Alta', Asegurado__c = 'Ana Prueba',
				Participante__c = ana.Id, Fecha_Movimiento__c = Date.newInstance(2026, 11, 16)),
			new Movimiento_Poliza__c(Poliza__c = p.Id, Solicitud__c = 'SOL-0001', Tipo__c = 'Baja', Asegurado__c = 'Luis Baja',
				Certificado__c = '0000005154', Prima__c = -1506.63, Fecha_Movimiento__c = Date.newInstance(2026, 11, 2)),
			new Movimiento_Poliza__c(Poliza__c = p.Id, Solicitud__c = 'SOL-0002', Tipo__c = 'Cambio', Asegurado__c = 'Eva Cambio',
				Detalle__c = 'RFC:  → EVCA900101AAA\nCategoría: 00 → 01')
		};
	}

	static InsurancePolicy poliza() { return [SELECT Id, Name, NameInsured.Name FROM InsurancePolicy WHERE Name = 'GMG-CONCLUIDO']; }

	@isTest
	static void primaDeCadaMovimiento() {
		InsurancePolicy p = poliza();
		Id ana = [SELECT Id FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :p.Id LIMIT 1].Id;
		Test.startTest();
		Map<String, Object> r = MovimientosColectivoController.guardarPrimas(p.Id, JSON.serialize(new List<Object>{
			new Map<String, Object>{ 'registroId' => ana, 'nombre' => 'Ana', 'tipo' => 'Alta', 'fecha' => '2026-11-16', 'prima' => 337.18 },
			new Map<String, Object>{ 'registroId' => ana, 'nombre' => 'Ana', 'tipo' => 'Baja', 'fecha' => '2026-11-16', 'prima' => 10 } }));
		System.assertEquals(1, r.get('guardadas'));
		System.assertEquals(1, ((List<String>) r.get('avisos')).size(), 'Ana no tiene una baja');
		System.assertEquals(337.18, [SELECT Prima__c FROM Movimiento_Poliza__c WHERE Participante__c = :ana].Prima__c);
		for (Map<String, Object> s : EndosoPoliza.solicitudes(p.Id, null)) {
			if (s.get('folio') == 'SOL-0001') { System.assertEquals(-1169.45, s.get('prima'), 'La prima de la solicitud es la suma'); }
		}
		System.assertEquals(null, MovimientosColectivoController.contenidoPdf(null));
		Test.stopTest();
	}

	@isTest
	static void resumenAlConcluir() {
		InsurancePolicy p = poliza();
		Id baja = [SELECT Id FROM Movimiento_Poliza__c WHERE Poliza__c = :p.Id AND Tipo__c = 'Baja'].Id;
		String rechazo = MovimientosColectivoController.cambiarSeguimiento(p.Id, 'SOL-0001', baja, 'Rechazado', 'No procede');
		System.assertEquals(null, rechazo, 'Aún tiene un movimiento abierto');
		AvisoRenovacionPoliza.produccionPrueba = false;
		Test.startTest();
		String aviso = MovimientosColectivoController.cambiarSeguimiento(p.Id, 'SOL-0001', null, 'Concluido', null);
		Test.stopTest();
		System.assert(aviso.contains('cliente@prueba.test'), aviso);
		String html = AvisoMovimientoConcluido.cuerpo(p, 'SOL-0001', '');
		for (String t : new List<String>{ 'Ana Prueba', 'POR ASIGNAR', 'Rechazado: No procede', '16/11/2026', '1 alta, 1 rechazado', '-$1,506.63' }) {
			System.assert(html.contains(t), t + ' en ' + html);
		}
		System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :p.Id AND Subject LIKE '%0001%'], 'Queda la tarea del envío');
		String cambio = AvisoMovimientoConcluido.cuerpo(p, 'SOL-0002', '');
		System.assert(cambio.contains('EVCA900101AAA') && cambio.contains('00 ') && cambio.contains('1 cambio'), cambio);
	}

	@isTest
	static void aQuienSeEnvia() {
		InsurancePolicy p = poliza();
		System.assertEquals('cliente@prueba.test', AvisoMovimientoConcluido.correoCliente(p.Id, 'SOL-0001'));
		// El correo de Avanza no es del cliente.
		update new Account(Id = [SELECT NameInsuredId FROM InsurancePolicy WHERE Id = :p.Id].NameInsuredId, Correo_electronico__c = 'info@avanzaseguro.com');
		System.assertEquals(null, AvisoMovimientoConcluido.correoCliente(p.Id, 'SOL-0001'));
		AvisoRenovacionPoliza.produccionPrueba = true;
		System.assert(AvisoMovimientoConcluido.programar(p.Id, 'SOL-0001').contains('no tiene correo'));
		System.assertEquals(null, AvisoMovimientoConcluido.programar(p.Id, 'SOL-0001'), 'Una vez por transacción');
		AvisoMovimientoConcluido.enviar(p.Id, 'SOL-0001');
		System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :p.Id], 'Sin correo no se envía');
	}
}
