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
		Opportunity autos = new Opportunity(
			Name = 'Panel Autos',
			AccountId = cuenta.Id,
			StageName = 'Gestion Comercial',
			CloseDate = Date.today().addDays(10),
			Agente_Relacionado__c = agenteId,
			Ramo__c = 'Automoviles',
			Tipo_Contratacion__c = 'Individual',
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

		Assert.areEqual(2, p.polizasMesUsuario, 'Las dos pólizas no canceladas cuentan en el mes');
		Assert.areEqual(2, p.polizasHoyUsuario, 'Las dos pólizas se emitieron hoy');
		Assert.areEqual(1, p.rachaDias, 'Racha de un día (hoy)');
		Assert.areEqual(1, p.ranking.size(), 'Un agente en el ranking');
		Assert.isTrue(p.ranking[0].esUsuarioActual, 'El agente es el usuario actual');
		Assert.isNotNull(p.reyAutos, 'Hay Rey de Autos');
		Assert.areEqual(2, p.reyAutos.autosSemana, 'Una póliza de autos directa y otra por el ramo de la oportunidad');
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
