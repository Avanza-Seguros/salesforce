/**
 * @creation date: 12/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas unitarias de FlotillaController: alta de cotizaciones de flotilla (Quote + incisos +
 * vehículos sin duplicar por VIN), consulta para el comparativo, eliminación, validaciones y lectura de PDF.
 */
@isTest
private class FlotillaControllerTest {

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Crea la empresa, la oportunidad colectiva de Automóviles, dos aseguradoras y un producto de Auto.
	 * @return void
	 */
	@testSetup
	static void setup() {
		Account acc = new Account(Name = 'Empresa Flotilla Test', AnnualRevenue = 100);
		insert acc;
		String etapa = 'Prospecting';
		for (OpportunityStage s : [
			SELECT MasterLabel FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1
		]) { etapa = s.MasterLabel; }
		List<Agente__c> agentes = [SELECT Id FROM Agente__c LIMIT 1];
		if (agentes.isEmpty()) {
			Agente__c ag = new Agente__c(Name = 'Agente Flotilla Test', Status__c = 'Nuevo', Estado_Civil__c = 'Casado');
			insert ag;
			agentes.add(ag);
		}
		Opportunity o = new Opportunity(Name = 'Opp Flotilla Test', AccountId = acc.Id, StageName = etapa,
			CloseDate = Date.today().addDays(30), Agente_Relacionado__c = agentes[0].Id);
		o.put('Ramo__c', 'Automoviles');
		o.put('Tipo_Contratacion__c', 'Colectiva');
		insert o;
		Aseguradora__c q = new Aseguradora__c(Name = 'Qualitas Flotilla Test');
		Aseguradora__c g = new Aseguradora__c(Name = 'GNP Flotilla Test');
		insert new List<Aseguradora__c>{ q, g };
		Product2 p = new Product2(Name = 'Auto Flotilla Qualitas', IsActive = true, Family = 'Automoviles');
		p.put('Aseguradora__c', q.Id);
		insert p;
		// Vehículo que ya existe en la empresa: debe reutilizarse por VIN.
		insert new CustomerProperty(PrimaryOwnerId = acc.Id, Vin = 'MR0EX32G9F0265961');
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cotización de ejemplo con 3 incisos (2 pick-up de carga y 1 automóvil).
	 * @param asegId: aseguradora.
	 * @param factor: multiplica las primas para simular otra aseguradora.
	 * @return JSON de CotizacionEntrada
	 */
	static String cotizacion(Id asegId, Decimal factor) {
		return JSON.serialize(new Map<String, Object>{
			'aseguradoraId' => asegId, 'vigenciaDesde' => '2026-08-11', 'vigenciaHasta' => '2027-08-11',
			'formaPago' => 'Contado', 'archivo' => 'cotizacion.xlsx',
			'incisos' => new List<Object>{
				new Map<String, Object>{ 'fila' => 14, 'inciso' => 1, 'serie' => 'mr0ex32g9f0265961', 'claveVehicular' => '17519',
					'descripcion' => 'TY TOYOTA HILUX PICK-UP DOBLE CABINA', 'modelo' => 2015, 'uso' => 'CARGA',
					'tipoVehiculo' => 'Pick-up de carga', 'paquete' => 'AMPLIA', 'tipoValor' => 'CONVENIDO', 'valor' => 242000,
					'dedDM' => 0.05, 'dedRT' => 10, 'rc' => 4700000, 'gm' => 500000, 'muerte' => 650000, 'prima' => 15527.81 * factor },
				new Map<String, Object>{ 'fila' => 15, 'inciso' => 2, 'serie' => '8AFER5AD7C6002543', 'descripcion' => 'FORD RANGER XL',
					'modelo' => 2012, 'uso' => 'CARGA', 'tipoVehiculo' => 'Pick-up de carga', 'valor' => 130000, 'prima' => 12067.20 * factor,
					'placas' => 'jal 12 34' },
				new Map<String, Object>{ 'fila' => 16, 'inciso' => 3, 'descripcion' => 'AUDI SQ5 3.0L', 'modelo' => 2020, 'uso' => 'NORMAL',
					'tipoVehiculo' => 'Automóviles', 'valor' => 570000, 'prima' => 21301.39 * factor }
			}
		});
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Guarda dos cotizaciones (dos aseguradoras) y valida Quote, incisos, vehículos y la consulta.
	 * @return void
	 */
	@isTest
	static void testGuardarYConsultar() {
		Opportunity opp = [SELECT Id, AccountId FROM Opportunity LIMIT 1];
		Aseguradora__c qualitas = [SELECT Id FROM Aseguradora__c WHERE Name = 'Qualitas Flotilla Test'];
		Aseguradora__c gnp = [SELECT Id FROM Aseguradora__c WHERE Name = 'GNP Flotilla Test'];
		Test.startTest();
		Id q1 = FlotillaController.guardarCotizacionFlotilla(opp.Id, cotizacion(qualitas.Id, 1));
		Id q2 = FlotillaController.guardarCotizacionFlotilla(opp.Id, cotizacion(gnp.Id, 1.1));
		List<Map<String, Object>> flotilla = FlotillaController.getFlotilla(opp.Id);
		Test.stopTest();

		Quote q = [SELECT Name, Prima_Total__c, ExpirationDate, Product__c, Frecuencia_de_prima__c FROM Quote WHERE Id = :q1];
		System.assertEquals(48896.40, q.Prima_Total__c, 'Prima total = suma de incisos');
		System.assertEquals(Date.newInstance(2027, 8, 11), q.ExpirationDate, 'Fin de vigencia');
		System.assertNotEquals(null, q.Product__c, 'Producto de Auto de la aseguradora');
		System.assertEquals('Anual', q.Frecuencia_de_prima__c, 'Contado = pago anual');
		System.assertEquals('Anual', FlotillaController.valorPicklist(Quote.Frecuencia_de_prima__c, 'No existe', 'Anual'), 'Respaldo');
		System.assert(q.Name.contains('3 unidades'), 'Nombre con unidades: ' + q.Name);

		System.assertEquals(2, flotilla.size(), 'Dos cotizaciones de flotilla');
		System.assertEquals(3, ((List<Object>) flotilla[0].get('incisos')).size(), 'Tres incisos por cotización');
		System.assertEquals(2, [SELECT COUNT() FROM CustomerProperty WHERE PrimaryOwnerId = :opp.AccountId],
			'Reutiliza el vehículo existente por VIN, crea el otro y no duplica entre cotizaciones');

		Inciso_Flotilla__c i1 = [SELECT Vehiculo__c, Serie__c, Deducible_DM__c, Deducible_RT__c FROM Inciso_Flotilla__c
			WHERE Cotizacion__c = :q1 AND Numero_Inciso__c = 1];
		System.assertEquals('MR0EX32G9F0265961', i1.Serie__c, 'Serie en mayúsculas');
		System.assertNotEquals(null, i1.Vehiculo__c, 'Inciso ligado al vehículo');
		System.assertEquals(5, i1.Deducible_DM__c, '0.05 se guarda como 5%');
		System.assertEquals(10, i1.Deducible_RT__c, '10 se respeta');
		System.assertEquals(null, [SELECT Vehiculo__c FROM Inciso_Flotilla__c WHERE Cotizacion__c = :q2 AND Numero_Inciso__c = 3].Vehiculo__c,
			'Sin serie no se crea vehículo');
		CustomerProperty ranger = [SELECT Make, MakeYear, RegistrationNumber FROM CustomerProperty WHERE Vin = '8AFER5AD7C6002543'];
		System.assertEquals('FORD', ranger.Make, 'Marca desde la descripción');
		System.assertEquals('JAL1234', ranger.RegistrationNumber, 'Placas normalizadas');
	}

	/**
	 * @creation date: 13/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Comparativo PDF: el HTML trae resumen, tipos, coberturas, detalle y recomendación; el archivo se
	 * liga a la oportunidad y a las cotizaciones, y al regenerarlo se agrega una versión (no otro archivo).
	 * @return void
	 */
	@isTest
	static void testComparativoPdf() {
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
		Aseguradora__c qualitas = [SELECT Id FROM Aseguradora__c WHERE Name = 'Qualitas Flotilla Test'];
		Aseguradora__c gnp = [SELECT Id FROM Aseguradora__c WHERE Name = 'GNP Flotilla Test'];
		Id q1 = FlotillaController.guardarCotizacionFlotilla(opp.Id, cotizacion(qualitas.Id, 1));
		Id q2 = FlotillaController.guardarCotizacionFlotilla(opp.Id, cotizacion(gnp.Id, 1.1));
		Test.startTest();
		Test.setCurrentPage(Page.FlotillaComparativoPdf);
		ApexPages.currentPage().getParameters().put('oppId', opp.Id);
		String html = new FlotillaComparativoPdfController().htmlBody;
		Id doc1 = FlotillaController.generarComparativoPdf(opp.Id);
		Id doc2 = FlotillaController.generarComparativoPdf(opp.Id);
		Test.stopTest();

		System.assert(html.contains('Comparativo de Seguro de Flotilla'), 'Título');
		System.assert(html.contains('Qualitas Flotilla Test') && html.contains('GNP Flotilla Test'), 'Una columna por aseguradora');
		System.assert(html.contains('$48,896'), 'Prima total de la mejor cotización: ' + html.substringBetween('Prima total', '</tr>'));
		System.assert(html.contains('Pick-up de carga') && html.contains('Autom&oacute;viles'), 'Prima por tipo de vehículo');
		System.assert(html.contains('Mejor prima'), 'Marca la mejor prima');
		System.assert(html.contains('5%') && html.contains('$4,700,000'), 'Coberturas y deducibles');
		System.assert(html.contains('MR0EX32G9F0265961'), 'Detalle por vehículo');
		System.assert(html.contains('menor prima total'), 'Recomendación');
		System.assertEquals(doc1, doc2, 'Al regenerar se agrega versión al mismo archivo');
		System.assertEquals(2, [SELECT COUNT() FROM ContentVersion WHERE ContentDocumentId = :doc1], 'Dos versiones');
		System.assertEquals(3, [SELECT COUNT() FROM ContentDocumentLink WHERE ContentDocumentId = :doc1 AND LinkedEntityId IN (:opp.Id, :q1, :q2)],
			'Ligado a la oportunidad y a las dos cotizaciones');
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Desglose de primas: una aseguradora da solo la prima neta por vehículo y derechos/IVA de la póliza
	 * (estilo Mapfre) y otra da la prima total por vehículo (estilo Chubb). La prima total de la cotización y la prima
	 * comparable de cada vehículo quedan en la misma base, y el PDF muestra el desglose.
	 * @return void
	 */
	@isTest
	static void testPrimaNetaYTotal() {
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
		Aseguradora__c qualitas = [SELECT Id FROM Aseguradora__c WHERE Name = 'Qualitas Flotilla Test'];
		Aseguradora__c gnp = [SELECT Id FROM Aseguradora__c WHERE Name = 'GNP Flotilla Test'];
		// Solo prima neta por inciso; derechos e IVA a nivel póliza.
		Id qNeta = FlotillaController.guardarCotizacionFlotilla(opp.Id, JSON.serialize(new Map<String, Object>{
			'aseguradoraId' => gnp.Id, 'derechos' => 200, 'iva' => 352,
			'incisos' => new List<Object>{
				new Map<String, Object>{ 'fila' => 1, 'serie' => 'MR0EX32G9F0265961', 'descripcion' => 'TOYOTA HILUX', 'primaNeta' => 1000 },
				new Map<String, Object>{ 'fila' => 2, 'descripcion' => 'NISSAN VERSA', 'primaNeta' => 1000 }
			}
		}));
		// Prima total por inciso y total de la póliza explícita.
		Id qTotal = FlotillaController.guardarCotizacionFlotilla(opp.Id, JSON.serialize(new Map<String, Object>{
			'aseguradoraId' => qualitas.Id, 'primaNeta' => 1700, 'derechos' => 100, 'recargo' => 0, 'iva' => 288, 'primaTotal' => 2088,
			'incisos' => new List<Object>{
				new Map<String, Object>{ 'fila' => 1, 'serie' => 'MR0EX32G9F0265961', 'descripcion' => 'TOYOTA HILUX', 'primaNeta' => 1000, 'prima' => 1229 },
				new Map<String, Object>{ 'fila' => 2, 'descripcion' => 'NISSAN VERSA', 'primaNeta' => 700, 'prima' => 859 }
			}
		}));
		Test.startTest();
		List<Map<String, Object>> flotilla = FlotillaController.getFlotilla(opp.Id);
		String html = FlotillaComparativoPdfController.construirHtml(opp.Id);
		Test.stopTest();

		Quote neta = [SELECT Prima_Total__c, Prima_Neta__c, Derechos_Poliza__c, IVA__c FROM Quote WHERE Id = :qNeta];
		System.assertEquals(2552, neta.Prima_Total__c, 'Total = neta (suma de incisos) + derechos + IVA');
		System.assertEquals(2000, neta.Prima_Neta__c, 'Prima neta = suma de incisos');
		Quote total = [SELECT Prima_Total__c, Prima_Neta__c, Recargo_Fraccionado__c FROM Quote WHERE Id = :qTotal];
		System.assertEquals(2088, total.Prima_Total__c, 'Respeta la prima total del archivo');

		for (Map<String, Object> q : flotilla) {
			Decimal suma = 0;
			for (Object o : (List<Object>) q.get('incisos')) { suma += (Decimal) ((Map<String, Object>) o).get('primaComparable'); }
			System.assertEquals((Decimal) q.get('primaTotal'), suma, 'La prima comparable suma la prima total de ' + q.get('aseguradora'));
			System.assertEquals(q.get('id') == qNeta, q.get('prorrateo'), 'Solo se reparte en la cotización que trae prima neta por vehículo');
		}
		System.assert(html.contains('Prima neta') && html.contains('Derechos / gastos de expedici'), 'El PDF muestra el desglose');
		System.assert(html.contains('parte proporcional de derechos e IVA'), 'El PDF explica el reparto');
		System.assert(html.indexOf('NISSAN VERSA') != html.lastIndexOf('NISSAN VERSA'), 'Los vehículos sin serie no se juntan entre aseguradoras');
	}

	/**
	 * @creation date: 13/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Sin cotizaciones de flotilla no se genera el PDF; con una sola, la recomendación pide comparar.
	 * @return void
	 */
	@isTest
	static void testComparativoSinCotizaciones() {
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
		Boolean rechazado = false;
		try { FlotillaController.generarComparativoPdf(opp.Id); } catch (AuraHandledException e) { rechazado = true; }
		System.assert(rechazado, 'Sin cotizaciones se rechaza');
		System.assertEquals('', FlotillaComparativoPdfController.construirHtml(opp.Id), 'Sin cotizaciones no hay HTML');
		Aseguradora__c qualitas = [SELECT Id FROM Aseguradora__c WHERE Name = 'Qualitas Flotilla Test'];
		FlotillaController.guardarCotizacionFlotilla(opp.Id, cotizacion(qualitas.Id, 1));
		System.assert(FlotillaComparativoPdfController.construirHtml(opp.Id).contains('Agrega las cotizaciones de otras aseguradoras'),
			'Con una sola cotización invita a comparar');
		System.assertEquals('$1,234,568', FlotillaComparativoPdfController.moneda(1234567.6));
		System.assertEquals('—', FlotillaComparativoPdfController.moneda(null));
		System.assertEquals('4.4%', FlotillaComparativoPdfController.porcentaje(4.44));
		System.assertEquals('5%', FlotillaComparativoPdfController.porcentaje(5));
		System.assertEquals('01/02/2026', FlotillaComparativoPdfController.fechaTxt(Date.newInstance(2026, 2, 1)));
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Elimina una cotización de flotilla con sus incisos y conserva los vehículos.
	 * @return void
	 */
	@isTest
	static void testEliminar() {
		Opportunity opp = [SELECT Id, AccountId FROM Opportunity LIMIT 1];
		Aseguradora__c qualitas = [SELECT Id FROM Aseguradora__c WHERE Name = 'Qualitas Flotilla Test'];
		Id q1 = FlotillaController.guardarCotizacionFlotilla(opp.Id, cotizacion(qualitas.Id, 1));
		Test.startTest();
		FlotillaController.eliminarCotizacionFlotilla(q1);
		FlotillaController.eliminarCotizacionFlotilla(null);
		Test.stopTest();
		System.assertEquals(0, [SELECT COUNT() FROM Quote WHERE Id = :q1], 'Se elimina la cotización');
		System.assertEquals(0, [SELECT COUNT() FROM Inciso_Flotilla__c], 'Se eliminan los incisos');
		System.assertEquals(2, [SELECT COUNT() FROM CustomerProperty WHERE PrimaryOwnerId = :opp.AccountId], 'Los vehículos se conservan');
		System.assertEquals(0, FlotillaController.getFlotilla(opp.Id).size(), 'Sin cotizaciones de flotilla');
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Rechaza datos inválidos sin dejar registros a medias.
	 * @return void
	 */
	@isTest
	static void testValidaciones() {
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
		Aseguradora__c qualitas = [SELECT Id FROM Aseguradora__c WHERE Name = 'Qualitas Flotilla Test'];
		List<String> casos = new List<String>{
			'{no es json',
			JSON.serialize(new Map<String, Object>{ 'incisos' => new List<Object>() }),
			JSON.serialize(new Map<String, Object>{ 'aseguradoraId' => qualitas.Id, 'incisos' => new List<Object>() }),
			JSON.serialize(new Map<String, Object>{ 'aseguradoraId' => qualitas.Id,
				'incisos' => new List<Object>{ new Map<String, Object>{ 'fila' => 9, 'prima' => 100 } } })
		};
		Integer errores = 0;
		Test.startTest();
		for (String c : casos) {
			try { FlotillaController.guardarCotizacionFlotilla(opp.Id, c); } catch (AuraHandledException e) { errores++; }
		}
		opp.AccountId = null;
		update opp;
		try {
			FlotillaController.guardarCotizacionFlotilla(opp.Id, cotizacion(qualitas.Id, 1));
		} catch (AuraHandledException e) {
			errores++;
		}
		Test.stopTest();
		System.assertEquals(5, errores, 'Todos los casos inválidos se rechazan');
		System.assertEquals(0, [SELECT COUNT() FROM Inciso_Flotilla__c], 'No quedan incisos a medias');
		System.assertEquals(0, [SELECT COUNT() FROM Quote], 'No quedan cotizaciones a medias');
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Lectura de PDF (sin llamar a Einstein en pruebas), aseguradoras y helpers.
	 * @return void
	 */
	@isTest
	static void testIaYHelpers() {
		Test.startTest();
		System.assertEquals('{"incisos":[]}', FlotillaController.analizarFlotillaPdf('INCISO 1 TOYOTA HILUX'));
		Boolean vacio = false;
		try { FlotillaController.analizarFlotillaPdf(' '); } catch (AuraHandledException e) { vacio = true; }
		Test.stopTest();
		System.assert(vacio, 'Texto vacío se rechaza');
		System.assertEquals(2, FlotillaController.getAseguradoras().size(), 'Lista de aseguradoras');
		System.assertEquals('TOYOTA', FlotillaController.marcaDe('TY TOYOTA HILUX'));
		System.assertEquals('AUDI', FlotillaController.marcaDe('AUDI SQ5'));
		System.assertEquals(null, FlotillaController.marcaDe(''));
		System.assertEquals('Semestral', FlotillaController.frecuencia('Semestral'));
		System.assertEquals('Mensual', FlotillaController.frecuencia('mensual'));
		System.assertEquals('Trimestral', FlotillaController.frecuencia('Trimestral'));
		System.assertEquals('Anual', FlotillaController.frecuencia(null));
		System.assertEquals(null, FlotillaController.porcentaje(null));
		System.assertEquals(null, FlotillaController.fecha('11/08/2026'));
		System.assertEquals('{"a":1}', FlotillaController.limpiarJson('```json {"a":1} ```'));
		System.assertEquals('{"incisos":[]}', FlotillaController.limpiarJson('nada'));
		System.assertEquals('{"incisos":[]}', FlotillaController.limpiarJson(null));
	}

	/**
	 * @creation date: 15/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Coberturas lado a lado con las de cada cotización (Quote_Coverage__c): agrupa nombres equivalentes,
	 *               toma el valor de la cobertura o de los incisos, marca "No incluida" y omite la que repite el producto.
	 * @return void
	 */
	@isTest
	static void testCoberturasComparadas() {
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
		Aseguradora__c q = [SELECT Id FROM Aseguradora__c WHERE Name = 'Qualitas Flotilla Test'];
		Aseguradora__c g = [SELECT Id FROM Aseguradora__c WHERE Name = 'GNP Flotilla Test'];
		Id q1 = FlotillaController.guardarCotizacionFlotilla(opp.Id, cotizacion(q.Id, 1));
		Id q2 = FlotillaController.guardarCotizacionFlotilla(opp.Id, cotizacion(g.Id, 1.1));
		insert new List<Quote_Coverage__c>{
			new Quote_Coverage__c(Quote__c = q1, Name = 'Daños Materiales', Coverage_Name__c = 'Daños Materiales'),
			new Quote_Coverage__c(Quote__c = q1, Name = 'Gastos Médicos Ocupantes', Coverage_Name__c = 'Gastos Médicos Ocupantes'),
			new Quote_Coverage__c(Quote__c = q1, Name = 'Asistencia Legal Cds *', Coverage_Name__c = 'Asistencia Legal Cds *', Sum_Insured__c = 50000),
			new Quote_Coverage__c(Quote__c = q1, Name = 'Auto Flotilla', Coverage_Name__c = 'Auto Flotilla'),
			new Quote_Coverage__c(Quote__c = q2, Name = 'Gastos Médicos a Ocupantes', Coverage_Name__c = 'Gastos Médicos a Ocupantes', Deductible__c = 5)
		};
		Test.startTest();
		List<Map<String, Object>> filas = FlotillaController.getCoberturasFlotilla(opp.Id);
		String html = FlotillaComparativoPdfController.construirHtml(opp.Id);
		Test.stopTest();
		Map<String, Map<String, String>> porEtiqueta = new Map<String, Map<String, String>>();
		for (Map<String, Object> f : filas) { porEtiqueta.put((String) f.get('etiqueta'), (Map<String, String>) f.get('valores')); }
		System.assert(porEtiqueta.containsKey('Paquete'), 'Paquete de los incisos: ' + porEtiqueta.keySet());
		System.assert(porEtiqueta.containsKey('Gastos Médicos Ocupantes') && !porEtiqueta.containsKey('Gastos Médicos a Ocupantes'),
			'Nombres equivalentes en un solo renglón: ' + porEtiqueta.keySet());
		System.assertEquals('Ded. 5%', porEtiqueta.get('Gastos Médicos Ocupantes').get(String.valueOf(q2)), 'Valor de la cobertura');
		System.assertEquals('$50,000', porEtiqueta.get('Asistencia Legal Cds').get(String.valueOf(q1)), 'Suma asegurada de la cobertura');
		System.assertEquals('No incluida', porEtiqueta.get('Asistencia Legal Cds').get(String.valueOf(q2)), 'La otra aseguradora no la tiene');
		System.assert(porEtiqueta.containsKey('Daños Materiales'), 'Cobertura de la cotización');
		System.assert(!porEtiqueta.containsKey('Auto Flotilla'), 'Se omite la que repite el nombre del producto');
		System.assert(html.contains('Coberturas y deducibles') && html.contains('Asistencia Legal Cds'), 'El PDF usa las coberturas reales');
		System.assertEquals('gastos medicos ocupantes', FlotillaController.normalizarCobertura('Gastos Médicos a Ocupantes'));
		System.assertEquals('rc', FlotillaController.conceptoInciso('responsabilidad civil danos terceros'));
		System.assertEquals('muerte', FlotillaController.conceptoInciso('accidentes automovilisticos conductor'));
		System.assertEquals('dedRT', FlotillaController.conceptoInciso('robo total'));
		System.assertEquals(null, FlotillaController.conceptoInciso('asistencia vial'));
		System.assertEquals('', FlotillaController.normalizarCobertura(null));
	}
}
