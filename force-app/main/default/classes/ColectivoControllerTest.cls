/**
 * @creation date: 14/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas unitarias de ColectivoController y ColectivoComparativoPdfController: alta de cotizaciones
 * colectivas de personas (Quote + categorías), consulta, comparativo (con y sin IVA), PDF, eliminación,
 * validaciones y lectura con IA.
 */
@isTest
private class ColectivoControllerTest {

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Crea la empresa, la oportunidad colectiva de GMM, dos aseguradoras y un producto de GMM.
	 * @return void
	 */
	@testSetup
	static void setup() {
		Account acc = new Account(Name = 'Empresa GMM Colectivo Test', AnnualRevenue = 100);
		insert acc;
		String etapa = 'Prospecting';
		for (OpportunityStage s : [
			SELECT MasterLabel FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1
		]) { etapa = s.MasterLabel; }
		List<Agente__c> agentes = [SELECT Id FROM Agente__c LIMIT 1];
		if (agentes.isEmpty()) {
			Agente__c ag = new Agente__c(Name = 'Agente GMM Test', Status__c = 'Nuevo', Estado_Civil__c = 'Casado');
			insert ag;
			agentes.add(ag);
		}
		Opportunity o = new Opportunity(Name = 'Opp GMM Colectivo Test', AccountId = acc.Id, StageName = etapa,
			CloseDate = Date.today().addDays(30), Agente_Relacionado__c = agentes[0].Id);
		o.put('Ramo__c', 'GMM');
		o.put('Tipo_Contratacion__c', 'Colectiva');
		insert o;
		Aseguradora__c gnp = new Aseguradora__c(Name = 'GNP Colectivo Test');
		Aseguradora__c smnyl = new Aseguradora__c(Name = 'SMNYL Colectivo Test');
		insert new List<Aseguradora__c>{ gnp, smnyl };
		Product2 p = new Product2(Name = 'GMM Colectivo GNP', IsActive = true, Family = 'GMM');
		p.put('Aseguradora__c', gnp.Id);
		insert p;
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cotización estilo GNP: dos categorías, sin IVA, con formas de pago y tarifa por edad.
	 * @param asegId: aseguradora.
	 * @return JSON de CotizacionEntrada
	 */
	static String cotizacionGnp(Id asegId) {
		return JSON.serialize(new Map<String, Object>{
			'aseguradoraId' => asegId, 'vigenciaDesde' => '2026-08-01', 'vigenciaHasta' => '2027-08-01', 'formaPago' => 'Anual',
			'derechos' => 50765, 'numeroCotizacion' => 'GIMAME', 'archivo' => 'gnp.xlsm',
			'formasPago' => new List<Object>{
				new Map<String, Object>{ 'forma' => 'Anual', 'recargoPct' => 0, 'numeroPagos' => 1, 'primaTotal' => 2426432.8 },
				new Map<String, Object>{ 'forma' => 'Semestral', 'recargoPct' => 4, 'numeroPagos' => 2, 'primaTotal' => 2523490.11, 'primerPago' => 1261745.06 }
			},
			'categorias' => new List<Object>{
				new Map<String, Object>{ 'nombre' => 'ADM', 'asegurados' => 129, 'hombres' => 62, 'mujeres' => 67, 'titulares' => 129, 'dependientes' => 0,
					'primaNeta' => 864450, 'plan' => 'Premier 300', 'sumaAsegurada' => '281 UMAM', 'deducible' => '2.8 UMAM', 'coaseguro' => '10%',
					'topeCoaseguro' => '$60,000', 'tabulador' => '0004 Omnia', 'territorio' => 'Nacional',
					'coberturasAdicionales' => new List<String>{ 'Médica Móvil', 'Asistencia en viajes' },
					'tarifaEdades' => new List<Object>{
						new Map<String, Object>{ 'rango' => '20-24', 'hombres' => 5, 'mujeres' => 6, 'primaHombre' => 3504, 'primaMujer' => 5387.1 }
					} },
				new Map<String, Object>{ 'nombre' => 'NO ADM', 'asegurados' => 226, 'hombres' => 130, 'mujeres' => 96, 'primaNeta' => 1511217.8,
					'plan' => 'Premier 300', 'sumaAsegurada' => '281 UMAM', 'deducible' => '2.8 UMAM', 'coaseguro' => '10%' }
			}
		});
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cotización estilo SMNYL: una categoría, con IVA y gastos de expedición.
	 * @param asegId: aseguradora.
	 * @return JSON de CotizacionEntrada
	 */
	static String cotizacionSmnyl(Id asegId) {
		return JSON.serialize(new Map<String, Object>{
			'aseguradoraId' => asegId, 'primaNeta' => 3124597, 'derechos' => 46280, 'recargo' => 0, 'iva' => 507340.32,
			'primaTotal' => 3678217.32, 'formaPago' => 'Anual',
			'categorias' => new List<Object>{
				new Map<String, Object>{ 'nombre' => 'Empleados', 'asegurados' => 356, 'hombres' => 193, 'mujeres' => 163,
					'sumaAsegurada' => '$1,000,000', 'deducible' => '$10,000', 'coaseguro' => '10%', 'nivelHospitalario' => 'Estándar',
					'tarifaEdades' => new List<Object>{
						new Map<String, Object>{ 'rango' => '20-24', 'hombres' => 24, 'mujeres' => 22, 'primaTotal' => 207122 }
					} }
			}
		});
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Guarda dos cotizaciones (una sin IVA) y valida Quote, categorías, consulta y comparativo.
	 * @return void
	 */
	@isTest
	static void testGuardarConsultarYComparar() {
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
		Aseguradora__c gnp = [SELECT Id FROM Aseguradora__c WHERE Name = 'GNP Colectivo Test'];
		Aseguradora__c smnyl = [SELECT Id FROM Aseguradora__c WHERE Name = 'SMNYL Colectivo Test'];
		Test.startTest();
		Id q1 = ColectivoController.guardarCotizacionColectiva(opp.Id, cotizacionGnp(gnp.Id));
		Id q2 = ColectivoController.guardarCotizacionColectiva(opp.Id, cotizacionSmnyl(smnyl.Id));
		List<Map<String, Object>> cot = ColectivoController.getCotizacionesColectivas(opp.Id);
		Test.setCurrentPage(Page.ColectivoComparativoPdf);
		ApexPages.currentPage().getParameters().put('oppId', opp.Id);
		String html = new ColectivoComparativoPdfController().htmlBody;
		Id doc1 = ColectivoController.generarComparativoPdf(opp.Id);
		Id doc2 = ColectivoController.generarComparativoPdf(opp.Id);
		Test.stopTest();

		Quote g = [SELECT Name, Prima_Total__c, Prima_Neta__c, Derechos_Poliza__c, IVA__c, Product__c, Ramos__c, Opciones_Pago__c, Vigencia_Inicio__c
			FROM Quote WHERE Id = :q1];
		System.assertEquals(2375667.8 + 50765, g.Prima_Total__c, 'Sin total ni IVA: neta (suma de categorías) + derechos');
		System.assertEquals(2375667.8, g.Prima_Neta__c, 'Prima neta = suma de categorías');
		System.assertEquals(null, g.IVA__c, 'Sin IVA');
		System.assertNotEquals(null, g.Product__c, 'Producto GMM de la aseguradora');
		System.assertEquals('GMM', g.Ramos__c, 'Ramo');
		System.assert(g.Name.contains('355 asegurados'), 'Nombre con asegurados: ' + g.Name);
		System.assert(g.Opciones_Pago__c.contains('Semestral'), 'Formas de pago guardadas');
		System.assertEquals(3678217.32, [SELECT Prima_Total__c FROM Quote WHERE Id = :q2].Prima_Total__c, 'Respeta la prima total');

		System.assertEquals(2, cot.size(), 'Dos cotizaciones colectivas');
		Map<String, Object> primera = cot[0];
		System.assertEquals(2, ((List<Object>) primera.get('categorias')).size(), 'GNP con dos categorías');
		System.assertEquals(2, ((List<Object>) primera.get('formasPago')).size(), 'Formas de pago');
		Map<String, Object> adm = (Map<String, Object>) ((List<Object>) primera.get('categorias'))[0];
		System.assertEquals(2, ((List<Object>) adm.get('coberturasAdicionales')).size(), 'Coberturas adicionales');
		System.assertEquals(1, ((List<Object>) adm.get('tarifaEdades')).size(), 'Tarifa por edad');

		System.assert(html.contains('Gastos M&eacute;dicos Mayores'), 'Título con el ramo');
		System.assert(html.contains('sin IVA'), 'Compara sin IVA cuando una aseguradora no lo incluye');
		System.assert(html.contains('No incluido'), 'Marca el IVA no incluido');
		System.assert(html.contains('Plan cotizado') && html.contains('281 UMAM') && html.contains('$1,000,000'), 'Plan lado a lado');
		System.assert(html.contains('Formas de pago') && html.contains('Semestral'), 'Formas de pago');
		System.assert(html.contains('n por edad') && html.contains('20-24'), 'Distribución por edad');
		System.assert(html.contains('Mejor prima') && html.contains('menor prima'), 'Recomendación');
		System.assert(html.contains('no son id'), 'Avisa que los planes difieren');
		System.assertEquals(doc1, doc2, 'Al regenerar se agrega versión al mismo archivo');
		System.assertEquals(3, [SELECT COUNT() FROM ContentDocumentLink WHERE ContentDocumentId = :doc1 AND LinkedEntityId IN (:opp.Id, :q1, :q2)],
			'Ligado a la oportunidad y a las dos cotizaciones');
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Elimina la cotización con sus categorías; con una sola cotización el comparativo invita a comparar.
	 * @return void
	 */
	@isTest
	static void testEliminarYUnaCotizacion() {
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
		Aseguradora__c gnp = [SELECT Id FROM Aseguradora__c WHERE Name = 'GNP Colectivo Test'];
		Aseguradora__c smnyl = [SELECT Id FROM Aseguradora__c WHERE Name = 'SMNYL Colectivo Test'];
		Id q1 = ColectivoController.guardarCotizacionColectiva(opp.Id, cotizacionGnp(gnp.Id));
		Id q2 = ColectivoController.guardarCotizacionColectiva(opp.Id, cotizacionSmnyl(smnyl.Id));
		Test.startTest();
		ColectivoController.eliminarCotizacionColectiva(q1);
		ColectivoController.eliminarCotizacionColectiva(null);
		String html = ColectivoComparativoPdfController.construirHtml(opp.Id);
		Test.stopTest();
		System.assertEquals(0, [SELECT COUNT() FROM Quote WHERE Id = :q1], 'Se elimina la cotización');
		System.assertEquals(1, [SELECT COUNT() FROM Categoria_Colectiva__c], 'Solo quedan las categorías de la otra');
		System.assert(html.contains('Agrega las cotizaciones de otras aseguradoras'), 'Con una sola invita a comparar');
		ColectivoController.eliminarCotizacionColectiva(q2);
		System.assertEquals('', ColectivoComparativoPdfController.construirHtml(opp.Id), 'Sin cotizaciones no hay HTML');
		Boolean rechazado = false;
		try { ColectivoController.generarComparativoPdf(opp.Id); } catch (AuraHandledException e) { rechazado = true; }
		System.assert(rechazado, 'Sin cotizaciones no se genera el PDF');
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Rechaza datos inválidos sin dejar registros a medias.
	 * @return void
	 */
	@isTest
	static void testValidaciones() {
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
		Aseguradora__c gnp = [SELECT Id FROM Aseguradora__c WHERE Name = 'GNP Colectivo Test'];
		List<String> casos = new List<String>{
			'{no es json',
			JSON.serialize(new Map<String, Object>{ 'categorias' => new List<Object>() }),
			JSON.serialize(new Map<String, Object>{ 'aseguradoraId' => gnp.Id, 'categorias' => new List<Object>() })
		};
		Integer errores = 0;
		Test.startTest();
		for (String c : casos) {
			try { ColectivoController.guardarCotizacionColectiva(opp.Id, c); } catch (AuraHandledException e) { errores++; }
		}
		Test.stopTest();
		System.assertEquals(3, errores, 'Todos los casos inválidos se rechazan');
		System.assertEquals(0, [SELECT COUNT() FROM Quote], 'No quedan cotizaciones a medias');
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Lectura con IA (sin llamar a Einstein en pruebas) y helpers.
	 * @return void
	 */
	@isTest
	static void testIaYHelpers() {
		Test.startTest();
		System.assertEquals('{"categorias":[]}', ColectivoController.analizarCotizacionColectiva('COTIZACION GMM COLECTIVO'));
		Boolean vacio = false;
		try { ColectivoController.analizarCotizacionColectiva(' '); } catch (AuraHandledException e) { vacio = true; }
		Test.stopTest();
		System.assert(vacio, 'Texto vacío se rechaza');
		System.assertEquals('Semestral', ColectivoController.frecuencia('SEMESTRAL'));
		System.assertEquals('Trimestral', ColectivoController.frecuencia('trimestral'));
		System.assertEquals('Mensual', ColectivoController.frecuencia('Mensual'));
		System.assertEquals('Anual', ColectivoController.frecuencia('Contado'));
		System.assertEquals(null, ColectivoController.fecha('01/08/2026'));
		System.assertEquals('{"a":1}', ColectivoController.limpiarJson('```json {"a":1} ```'));
		System.assertEquals('{"categorias":[]}', ColectivoController.limpiarJson(null));
		System.assertEquals('$2,375,668', ColectivoComparativoPdfController.moneda(2375667.8));
		System.assertEquals('5.2%', ColectivoComparativoPdfController.porcentaje(5.17));
		Map<String, Object> q = new Map<String, Object>{ 'categorias' => new List<Object>{
			new Map<String, Object>{ 'nombre' => 'A', 'deducible' => '$10,000' },
			new Map<String, Object>{ 'nombre' => 'B', 'deducible' => '$20,000' }
		} };
		System.assertEquals('A: $10,000 / B: $20,000', ColectivoComparativoPdfController.valorPlan(q, 'deducible'), 'Valor por categoría si cambia');
		System.assertEquals('', ColectivoComparativoPdfController.valorPlan(q, 'plan'), 'Vacío si no viene');
		System.assertEquals(new List<String>{ '0-19', '15-19', '20-24', '80-84', 'Sin edad' },
			ColectivoComparativoPdfController.ordenarRangos(new List<String>{ '20-24', 'Sin edad', '15-19', '80-84', '0-19' }),
			'Rangos ordenados por edad inicial');
	}
}
