/**
 * @creation date: 14/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas unitarias de ColectivoController y ColectivoComparativoPdfController: alta de cotizaciones
 * colectivas de personas (Quote + categorías) y de ubicaciones (Daños), consulta, comparativo (con y sin IVA,
 * cuota al millar, coberturas por ramo), PDF, resumen para la lista, eliminación, validaciones y lectura con IA.
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
		String guardado = [SELECT Descripcion__c FROM Opportunity WHERE Id = :opp.Id].Descripcion__c;
		System.assert(guardado != null && guardado.startsWith(ColectivoController.MARCA_COMPARATIVO) && !guardado.contains('<body>'),
			'El comparativo vigente queda en la oportunidad para Análisis IA');
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
		System.assertEquals(null, [SELECT Descripcion__c FROM Opportunity WHERE Id = :opp.Id].Descripcion__c,
			'Sin cotizaciones se quita el comparativo colectivo');
		update new Opportunity(Id = opp.Id, Descripcion__c = '<p>Comparativo de la IA</p>');
		ColectivoController.guardarComparativoEnOportunidad(opp.Id, '');
		System.assertEquals('<p>Comparativo de la IA</p>', [SELECT Descripcion__c FROM Opportunity WHERE Id = :opp.Id].Descripcion__c,
			'No borra un comparativo que no es colectivo');
		String frag = ColectivoController.aFragmento('<html><head><style>x</style></head><body><h2>T</h2><table class="resumen"><tr><td>1</td></tr></table></body></html>');
		System.assert(frag.contains('<h2 style=') && frag.contains('<table style=') && !frag.contains('<style>'), 'Fragmento con estilos en línea: ' + frag);
		System.assertEquals('<h3>A</h3>x<h3>C</h3>z', ColectivoController.quitarSeccion('<h3>A</h3>x<h3>B</h3>y<h3>C</h3>z', 'B'), 'Quita la sección intermedia');
		System.assertEquals('<h3>A</h3>x', ColectivoController.quitarSeccion('<h3>A</h3>x<h3>B</h3>y', 'B'), 'Quita la última sección');
		System.assertEquals('<h3>A</h3>x', ColectivoController.quitarSeccion('<h3>A</h3>x', 'B'), 'Sin la sección no cambia');
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
	 * @description: Cotización solo con aseguradora y primas: se crea sin categorías, aparece en la lista y no
	 *               genera comparativo.
	 */
	@isTest
	static void testSinDetalle() {
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
		Aseguradora__c gnp = [SELECT Id FROM Aseguradora__c WHERE Name = 'GNP Colectivo Test'];
		String c = JSON.serialize(new Map<String, Object>{
			'aseguradoraId' => gnp.Id, 'vigenciaDesde' => '2026-08-01', 'primaNeta' => 1000000, 'iva' => 160000, 'archivo' => 'gnp.pdf'
		});
		Test.startTest();
		Id q = ColectivoController.guardarCotizacionColectiva(opp.Id, c);
		Test.stopTest();
		Quote qt = [SELECT Name, Prima_Neta__c, Prima_Total__c FROM Quote WHERE Id = :q];
		System.assertEquals(1160000, qt.Prima_Total__c, 'Prima total = neta + IVA');
		System.assert(!qt.Name.contains('('), 'Sin asegurados en el nombre: ' + qt.Name);
		System.assertEquals(0, [SELECT COUNT() FROM Categoria_Colectiva__c], 'Sin categorías');
		List<Map<String, Object>> cot = ColectivoController.getCotizacionesColectivas(opp.Id);
		System.assertEquals(1, cot.size(), 'Aparece en la lista');
		System.assertEquals(0, ((List<Object>) cot[0].get('categorias')).size(), 'Sin categorías en la lista');
		Opportunity o = [SELECT Descripcion__c FROM Opportunity WHERE Id = :opp.Id];
		System.assert(String.isBlank(o.Descripcion__c), 'No se genera comparativo');
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
		System.assertEquals('{"categorias":[]}', ColectivoController.analizarCotizacionColectiva('COTIZACION GMM COLECTIVO', 'GMM'));
		Boolean vacio = false;
		try { ColectivoController.analizarCotizacionColectiva(' ', 'Danos'); } catch (AuraHandledException e) { vacio = true; }
		Test.stopTest();
		System.assert(vacio, 'Texto vacío se rechaza');
		System.assertEquals('Semestral', ColectivoController.frecuencia('SEMESTRAL'));
		System.assertEquals('Trimestral', ColectivoController.frecuencia('trimestral'));
		System.assertEquals('Mensual', ColectivoController.frecuencia('Mensual'));
		System.assertEquals('Anual', ColectivoController.frecuencia('Contado'));
		Id cuenta = [SELECT Id FROM Account LIMIT 1].Id;
		System.assertEquals(false, ColectivoController.tienePolizaDelRamo(null, 'GMM'), 'Sin cuenta no hay póliza');
		System.assertEquals(false, ColectivoController.tienePolizaDelRamo(cuenta, ''), 'La cuenta de prueba no tiene pólizas');
		System.assertEquals(false, ColectivoController.tienePolizaDelRamo(cuenta, 'GMM'), 'Ni del ramo');
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
		System.assert(ColectivoController.esUbicaciones('Danos') && ColectivoController.esUbicaciones('Empresarial'), 'Ramos de ubicaciones');
		System.assert(!ColectivoController.esUbicaciones('Vida') && !ColectivoController.esUbicaciones(null), 'Ramos de personas');
		System.assertEquals('Daños', ColectivoController.etiquetaRamo('Danos'));
		System.assertEquals('Visión', ColectivoController.etiquetaRamo('Vision'));
		System.assertEquals('Automóviles', ColectivoController.etiquetaRamo('Automoviles'));
		System.assertEquals('perdidasorganicas', ColectivoComparativoPdfController.llaveConcepto('Pérdidas orgánicas'));
		System.assertEquals('', ColectivoComparativoPdfController.llaveConcepto(null));
		Map<String, Object> qv = new Map<String, Object>{ 'primaNeta' => null, 'categorias' => new List<Object>{
			new Map<String, Object>{ 'nombre' => 'A', 'primaNeta' => 1500, 'parametros' => new List<Object>{
				new Map<String, Object>{ 'concepto' => 'Fallecimiento', 'valor' => '$500,000' } } },
			new Map<String, Object>{ 'nombre' => 'B', 'primaNeta' => 500, 'parametros' => new List<Object>{
				new Map<String, Object>{ 'concepto' => 'FALLECIMIENTO', 'valor' => '$250,000' } } }
		} };
		System.assertEquals('A: $500,000 / B: $250,000', ColectivoComparativoPdfController.valorParametro(qv, 'fallecimiento'), 'Cobertura por categoría');
		System.assertEquals('', ColectivoComparativoPdfController.valorParametro(qv, 'gastosfunerarios'), 'Sin la cobertura');
		System.assertEquals(2, ColectivoComparativoPdfController.cuotaAlMillar(qv, 1000000), 'Neta de las categorías / SA x 1000');
		System.assertEquals(null, ColectivoComparativoPdfController.cuotaAlMillar(qv, 0), 'Sin suma asegurada no hay cuota');
		Map<String, Object> qa = new Map<String, Object>{ 'id' => 'A', 'aseguradora' => 'A', 'primaNeta' => 1000, 'categorias' => new List<Object>() };
		Map<String, Object> qb = new Map<String, Object>{ 'id' => 'B', 'aseguradora' => 'B', 'primaNeta' => 1500, 'categorias' => new List<Object>() };
		List<Map<String, Object>> par = new List<Map<String, Object>>{ qa, qb };
		String nota = ColectivoComparativoPdfController.notaCuota(par, new Map<Object, Decimal>{ 'A' => 1, 'B' => 2 },
			new Map<Object, Decimal>{ 'A' => 1000000, 'B' => 1000000 }, 'ubicaciones');
		System.assert(nota.contains('mismas ubicaciones') && nota.contains('también es la más barata'), 'La más barata también por peso: ' + nota);
		System.assertEquals('', ColectivoComparativoPdfController.notaCuota(par, new Map<Object, Decimal>{ 'A' => 1, 'B' => 1 },
			new Map<Object, Decimal>{ 'A' => 1000000, 'B' => 1000000 }, 'ubicaciones'), 'Mismo tamaño y suma: sin nota');
		System.assertEquals('', ColectivoComparativoPdfController.notaCuota(par, new Map<Object, Decimal>{ 'A' => 1, 'B' => 2 },
			new Map<Object, Decimal>{ 'A' => 0, 'B' => 1000000 }, 'ubicaciones'), 'Sin suma asegurada en alguna: sin nota');
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Oportunidad colectiva del ramo indicado con la misma cuenta y agente del setup.
	 * @param ramo: valor del picklist Ramo.
	 * @return oportunidad insertada.
	 */
	static Opportunity oportunidad(String ramo) {
		Opportunity base = [SELECT AccountId, StageName, CloseDate, Agente_Relacionado__c FROM Opportunity LIMIT 1];
		Opportunity o = new Opportunity(Name = 'Opp ' + ramo + ' Colectivo Test', AccountId = base.AccountId, StageName = base.StageName,
			CloseDate = base.CloseDate, Agente_Relacionado__c = base.Agente_Relacionado__c);
		o.put('Ramo__c', ramo);
		o.put('Tipo_Contratacion__c', 'Colectiva');
		insert o;
		return o;
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Vida Grupo: coberturas en "parametros", suma asegurada total y cuota al millar en el comparativo.
	 * @return void
	 */
	@isTest
	static void testVidaCuotaAlMillar() {
		Opportunity opp = oportunidad('Vida');
		Aseguradora__c gnp = [SELECT Id FROM Aseguradora__c WHERE Name = 'GNP Colectivo Test'];
		Aseguradora__c smnyl = [SELECT Id FROM Aseguradora__c WHERE Name = 'SMNYL Colectivo Test'];
		List<Object> params = new List<Object>{
			new Map<String, Object>{ 'concepto' => 'Fallecimiento', 'valor' => '24 meses de sueldo' },
			new Map<String, Object>{ 'concepto' => 'Muerte accidental', 'valor' => 'Amparada' },
			new Map<String, Object>{ 'concepto' => '', 'valor' => 'sin concepto' }
		};
		String c1 = JSON.serialize(new Map<String, Object>{ 'aseguradoraId' => gnp.Id, 'primaNeta' => 120000, 'primaTotal' => 120000,
			'categorias' => new List<Object>{ new Map<String, Object>{ 'nombre' => 'General', 'asegurados' => 120, 'primaNeta' => 120000,
				'sumaAseguradaTotal' => 60000000, 'parametros' => params } } });
		String c2 = JSON.serialize(new Map<String, Object>{ 'aseguradoraId' => smnyl.Id, 'primaNeta' => 150000, 'primaTotal' => 150000,
			'categorias' => new List<Object>{ new Map<String, Object>{ 'nombre' => 'General', 'asegurados' => 120, 'primaNeta' => 150000,
				'sumaAseguradaTotal' => 90000000, 'parametros' => new List<Object>{
					new Map<String, Object>{ 'concepto' => 'FALLECIMIENTO', 'valor' => 'Suma fija $500,000' } } } } });
		Test.startTest();
		Id q1 = ColectivoController.guardarCotizacionColectiva(opp.Id, c1);
		ColectivoController.guardarCotizacionColectiva(opp.Id, c2);
		String html = ColectivoComparativoPdfController.construirHtml(opp.Id);
		Test.stopTest();
		Categoria_Colectiva__c cat = [SELECT Parametros__c, Suma_Asegurada_Total__c FROM Categoria_Colectiva__c WHERE Cotizacion__c = :q1];
		System.assertEquals(60000000, cat.Suma_Asegurada_Total__c, 'Suma asegurada total');
		System.assert(cat.Parametros__c.contains('Fallecimiento') && !cat.Parametros__c.contains('sin concepto'), 'Solo coberturas con concepto y valor');
		System.assert(html.contains('Vida Grupo'), 'Título del ramo');
		System.assert(html.contains('Cuota al millar') && html.contains('2.000'), 'Cuota al millar de GNP: 120,000 / 60,000,000 x 1000');
		System.assert(html.contains('Fallecimiento') && html.contains('24 meses de sueldo') && html.contains('Suma fija $500,000'),
			'Coberturas lado a lado agrupadas por nombre');
		System.assert(html.contains('Suma asegurada total'), 'Renglón de suma asegurada');
		System.assert(html.contains('cobra menos por cada peso asegurado'),
			'SMNYL es más cara pero asegura más: mejor cuota al millar (1.667 contra 2.000)');
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Daños: cada renglón es una ubicación (dirección y valor asegurado); el comparativo habla de ubicaciones.
	 * @return void
	 */
	@isTest
	static void testDanosUbicaciones() {
		Opportunity opp = oportunidad('Danos');
		Aseguradora__c gnp = [SELECT Id FROM Aseguradora__c WHERE Name = 'GNP Colectivo Test'];
		String c1 = JSON.serialize(new Map<String, Object>{ 'aseguradoraId' => gnp.Id, 'primaNeta' => 45000, 'derechos' => 800, 'iva' => 7328,
			'categorias' => new List<Object>{
				new Map<String, Object>{ 'nombre' => 'Planta Querétaro', 'direccion' => 'Av. 5 de Febrero 100, Querétaro', 'sumaAseguradaTotal' => 25000000,
					'primaNeta' => 30000, 'parametros' => new List<Object>{
						new Map<String, Object>{ 'concepto' => 'Incendio edificio', 'valor' => '$20,000,000 · Ded. 1%' } } },
				new Map<String, Object>{ 'nombre' => 'Bodega CDMX', 'sumaAseguradaTotal' => 10000000, 'primaNeta' => 15000 }
			} });
		Test.startTest();
		Id q = ColectivoController.guardarCotizacionColectiva(opp.Id, c1);
		String html = ColectivoComparativoPdfController.construirHtml(opp.Id);
		Map<Id, Map<String, Object>> res = ColectivoController.getResumenOportunidades(new List<Id>{ opp.Id });
		Test.stopTest();
		Quote qt = [SELECT Name, Prima_Total__c FROM Quote WHERE Id = :q];
		System.assert(qt.Name.contains('2 ubicaciones') && qt.Name.contains('Daños'), 'Nombre con ubicaciones: ' + qt.Name);
		System.assertEquals(45000 + 800 + 7328, qt.Prima_Total__c, 'Total calculado');
		System.assertEquals('Av. 5 de Febrero 100, Querétaro',
			[SELECT Direccion__c FROM Categoria_Colectiva__c WHERE Name = 'Planta Querétaro'].Direccion__c, 'Dirección');
		System.assert(html.contains('Coberturas cotizadas') && html.contains('Ubicaciones') && html.contains('Valor asegurado'), 'Secciones de ubicaciones');
		System.assert(html.contains('Incendio edificio'), 'Coberturas de la ubicación');
		System.assert(html.contains('2 ubicaciones'), 'Tamaño en ubicaciones');
		System.assertEquals(2, res.get(opp.Id).get('ubicaciones'), 'Resumen con ubicaciones');
		System.assertEquals(1, res.get(opp.Id).get('cotizaciones'), 'Resumen con cotizaciones');
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Resumen para la lista: asegurados de las cotizaciones (sin censo) y conteo de cotizaciones; lista vacía.
	 * @return void
	 */
	@isTest
	static void testResumenOportunidades() {
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
		Aseguradora__c gnp = [SELECT Id FROM Aseguradora__c WHERE Name = 'GNP Colectivo Test'];
		Aseguradora__c smnyl = [SELECT Id FROM Aseguradora__c WHERE Name = 'SMNYL Colectivo Test'];
		ColectivoController.guardarCotizacionColectiva(opp.Id, cotizacionGnp(gnp.Id));
		ColectivoController.guardarCotizacionColectiva(opp.Id, cotizacionSmnyl(smnyl.Id));
		Test.startTest();
		Map<Id, Map<String, Object>> res = ColectivoController.getResumenOportunidades(new List<Id>{ opp.Id });
		Map<Id, Map<String, Object>> vacio = ColectivoController.getResumenOportunidades(new List<Id>());
		Test.stopTest();
		System.assertEquals(356, res.get(opp.Id).get('asegurados'), 'Mayor número de asegurados cotizados');
		System.assertEquals(2, res.get(opp.Id).get('cotizaciones'), 'Dos cotizaciones');
		System.assertEquals(0, res.get(opp.Id).get('unidades'), 'Sin flotilla');
		System.assert(vacio.isEmpty(), 'Sin oportunidades no hay resumen');
	}
}
