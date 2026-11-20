/**
 * @creation date: 16/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas de OportunidadesPanelController: oportunidades del panel, ranking del mes,
 *   meta del usuario, racha de días emitiendo y logro Rey de Autos.
 */
@IsTest
private class OportunidadesPanelControllerTest {

	/**
	 * @creation date: 16/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Crea una cuenta, dos oportunidades (individual de autos y colectiva de GMM) y dos pólizas
	 *   emitidas desde la de autos más una cancelada que no debe contar.
	 * @return void
	 */
	@TestSetup
	static void setup() {
		Account cuenta = CollectionsTestDataFactory.createInsuredAccount();
		Id agenteId = CollectionsTestDataFactory.getOrCreateAgenteId();
		Producer productor = new Producer(Name = 'Agente Panel Prueba');
		insert productor;
		Opportunity autos = new Opportunity(
			Name = 'Panel Autos',
			AccountId = cuenta.Id,
			StageName = 'Gestion Comercial',
			CloseDate = Date.today().addDays(10),
			Agente_Relacionado__c = agenteId,
			Ramo__c = 'Automoviles',
			Tipo_Contratacion__c = 'Individual',
			Producer__c = productor.Id,
			Prima_neta__c = 1500
		);
		Opportunity gmm = new Opportunity(
			Name = 'Panel GMM',
			AccountId = cuenta.Id,
			StageName = 'Gestion Comercial',
			CloseDate = Date.today().addDays(-5),
			Agente_Relacionado__c = agenteId,
			Ramo__c = 'GMM',
			Tipo_Contratacion__c = 'Colectiva',
			Prima_Total__c = 9000
		);
		insert new List<Opportunity>{ autos, gmm };

		InsurancePolicy p1 = CollectionsTestDataFactory.buildCompletePolicy(cuenta.Id, 'Inicial', 'Mensual', 1200, Date.today());
		p1.SourceOpportunityId = autos.Id;
		p1.Ramo__c = 'Automoviles';
		InsurancePolicy p2 = CollectionsTestDataFactory.buildCompletePolicy(cuenta.Id, 'Inicial', 'Mensual', 1200, Date.today());
		p2.SourceOpportunityId = autos.Id;
		InsurancePolicy cancelada = CollectionsTestDataFactory.buildCompletePolicy(cuenta.Id, 'Cancelado', 'Mensual', 1200, Date.today());
		cancelada.SourceOpportunityId = gmm.Id;
		insert new List<InsurancePolicy>{ p1, p2, cancelada };
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: El panel trae las oportunidades con prima, tipo y propietario, y calcula ranking, meta, racha y Rey de Autos.
	 * @return void
	 */
	@IsTest
	static void obtenerPanelCalculaDatos() {
		Test.startTest();
		OportunidadesPanelController.Panel p = OportunidadesPanelController.obtenerPanel();
		Test.stopTest();

		Assert.areEqual(UserInfo.getUserId(), p.usuarioId, 'El panel es del usuario actual');
		Assert.isNotNull(p.nombreUsuario, 'Debe traer el nombre del usuario');
		Assert.areEqual(2, p.oportunidades.size(), 'Debe traer las dos oportunidades abiertas');
		// Se buscan por nombre: en algunas orgs una automatización ajusta la fecha de cierre y cambia el orden.
		OportunidadesPanelController.Oportunidad gmm;
		OportunidadesPanelController.Oportunidad autos;
		for (OportunidadesPanelController.Oportunidad o : p.oportunidades) {
			if (o.nombre == 'Panel GMM') { gmm = o; }
			if (o.nombre == 'Panel Autos') { autos = o; }
		}
		Assert.isNotNull(gmm, 'Debe traer la oportunidad GMM');
		Assert.isNotNull(autos, 'Debe traer la oportunidad Autos');
		Assert.areEqual('Colectiva', gmm.tipoContratacion, 'Tipo de contratación colectiva');
		Assert.areEqual(9000, gmm.prima, 'Sin prima neta usa la prima total');
		Assert.areEqual(1500, autos.prima, 'Usa la prima neta');
		Assert.areEqual(0, autos.cotizaciones, 'Sin cotizaciones');
		Producer productor = [SELECT Id FROM Producer WHERE Name = 'Agente Panel Prueba' LIMIT 1];
		Assert.areEqual(productor.Id, autos.agenteId, 'Trae el agente (Producer) de la oportunidad');
		Assert.areEqual('Agente Panel Prueba', autos.agente, 'Trae el nombre del agente');
		Assert.isNull(gmm.agenteId, 'Sin Producer no hay agente');
		InsurancePolicy cancelada = [SELECT Id FROM InsurancePolicy WHERE SourceOpportunityId = :gmm.id LIMIT 1];
		Assert.areEqual(cancelada.Id, gmm.polizaId, 'Trae la póliza de la oportunidad (aunque esté cancelada)');
		Set<Id> deAutos = new Map<Id, InsurancePolicy>([SELECT Id FROM InsurancePolicy WHERE SourceOpportunityId = :autos.id]).keySet();
		Assert.isTrue(deAutos.contains(autos.polizaId), 'Con varias pólizas trae una de la oportunidad');
		Boolean listado = false;
		for (OportunidadesPanelController.Opcion a : p.agentes) {
			if (a.id == productor.Id) { listado = true; }
		}
		Assert.isTrue(listado, 'El agente aparece en la lista del filtro');

		Assert.areEqual(2, p.polizasMesUsuario, 'Las dos pólizas no canceladas cuentan en el mes');
		Assert.areEqual(2, p.polizasHoyUsuario, 'Las dos pólizas se emitieron hoy');
		Assert.areEqual(1, p.rachaDias, 'Racha de un día (hoy)');
		Assert.areEqual(1, p.ranking.size(), 'Un agente en el ranking');
		Assert.isTrue(p.ranking[0].esUsuarioActual, 'El agente es el usuario actual');
		Assert.isNotNull(p.reyAutos, 'Hay Rey de Autos');
		Assert.areEqual(2, p.reyAutos.autosSemana, 'Una póliza de autos directa y otra por el ramo de la oportunidad');
	}

	/**
	 * @creation date: 20/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Sin póliza por origen ni por cotización, la oportunidad toma la póliza con su número de póliza
	 *   (Poliza__c): la del mismo cliente si la hay; si no, la que tenga ese número. Sin número no toma ninguna.
	 * @return void
	 */
	@IsTest
	static void buscarPolizasPorNumeroDePoliza() {
		Account cuenta = [SELECT Id FROM Account LIMIT 1];
		// Otro nombre: con el mismo, la regla de duplicados de cuentas de algunas orgs rechaza el alta.
		Account otra = new Account(Name = 'Otro Cliente Panel Prueba', AnnualRevenue = 1000000);
		insert otra;
		InsurancePolicy deOtro = CollectionsTestDataFactory.buildCompletePolicy(otra.Id, 'Inicial', 'Mensual', 1200, Date.today());
		deOtro.Name = 'NUM-PANEL-1';
		InsurancePolicy delCliente = CollectionsTestDataFactory.buildCompletePolicy(cuenta.Id, 'Inicial', 'Mensual', 1200, Date.today());
		delCliente.Name = 'NUM-PANEL-1';
		InsurancePolicy soloOtro = CollectionsTestDataFactory.buildCompletePolicy(otra.Id, 'Inicial', 'Mensual', 1200, Date.today());
		soloOtro.Name = 'NUM-PANEL-2';
		InsurancePolicy conEspacios = CollectionsTestDataFactory.buildCompletePolicy(cuenta.Id, 'Inicial', 'Mensual', 1200, Date.today());
		conEspacios.Name = 'GE 4300805';
		insert new List<InsurancePolicy>{ deOtro, delCliente, soloOtro, conEspacios };
		Opportunity a = new Opportunity(Id = '006000000000001AAA', AccountId = cuenta.Id, Poliza__c = ' num-panel-1 ');
		Opportunity b = new Opportunity(Id = '006000000000002AAA', AccountId = cuenta.Id, Poliza__c = 'NUM-PANEL-2');
		Opportunity c = new Opportunity(Id = '006000000000003AAA', AccountId = cuenta.Id);
		Opportunity d = new Opportunity(Id = '006000000000004AAA', AccountId = cuenta.Id, Poliza__c = 'ge-4300805');
		Opportunity e = new Opportunity(Id = '006000000000005AAA', AccountId = otra.Id, Poliza__c = 'GE4300805');
		Map<Id, Id> res = new Map<Id, Id>();

		Test.startTest();
		OportunidadesPanelController.buscarPolizasPorNumero(new List<Opportunity>{ a, b, c, d, e }, res);
		Test.stopTest();

		Assert.areEqual(delCliente.Id, res.get(a.Id), 'Con varias del mismo número toma la del cliente de la oportunidad');
		Assert.areEqual(soloOtro.Id, res.get(b.Id), 'Sin una del cliente toma la que tiene ese número');
		Assert.isFalse(res.containsKey(c.Id), 'Sin número de póliza no toma ninguna');
		Assert.areEqual(conEspacios.Id, res.get(d.Id), 'Escrito distinto (espacios, guiones, ceros) toma la del cliente');
		Assert.isFalse(res.containsKey(e.Id), 'Escrito distinto solo se compara con las pólizas del mismo cliente');
		Assert.areEqual('573371010', OportunidadesPanelController.numeroNormalizado('00000573371010'), 'Sin ceros al inicio');
		Assert.isNull(OportunidadesPanelController.numeroNormalizado(' - '), 'Sin letras ni números no hay número');
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: La racha cuenta días consecutivos y sigue viva si hoy aún no hay emisión.
	 * @return void
	 */
	@IsTest
	static void calcularRachaDiasConsecutivos() {
		Date hoy = Date.today();
		Set<Date> dias = new Set<Date>{ hoy.addDays(-1), hoy.addDays(-2), hoy.addDays(-4) };
		Assert.areEqual(2, OportunidadesPanelController.calcularRacha(dias, hoy), 'Ayer y antier');
		dias.add(hoy);
		Assert.areEqual(3, OportunidadesPanelController.calcularRacha(dias, hoy), 'Hoy, ayer y antier');
		Assert.areEqual(0, OportunidadesPanelController.calcularRacha(new Set<Date>(), hoy), 'Sin emisiones');
		Assert.isTrue(OportunidadesPanelController.esAutos('Automoviles'), 'Automoviles es autos');
		Assert.isFalse(OportunidadesPanelController.esAutos('GMM'), 'GMM no es autos');
		Assert.isFalse(OportunidadesPanelController.esAutos(null), 'Vacío no es autos');
		Assert.areEqual(700, OportunidadesPanelController.primaDe(new Opportunity(Prima_neta__c = 0, Amount = 700)), 'Prima neta en cero usa Amount');
	}
}
