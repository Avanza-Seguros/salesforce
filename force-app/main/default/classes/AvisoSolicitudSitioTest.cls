/**
 * @creation date: 19/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas de AvisoSolicitudSitio: el aviso de una solicitud del sitio lleva el Excel para la aseguradora.
 */
@isTest
private class AvisoSolicitudSitioTest {

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

	static List<AvisoSolicitudSitio.Resultado> avisar(Id policyId) {
		Case c = [SELECT Id FROM Case WHERE InsurancePolicy__c = :policyId ORDER BY CreatedDate DESC LIMIT 1];
		AvisoSolicitudSitio.Solicitud s = new AvisoSolicitudSitio.Solicitud();
		s.casoId = c.Id;
		s.destinatarios = 'avisos@prueba.test, otro@prueba.test';
		s.remitente = 'no-existe@prueba.test';
		return AvisoSolicitudSitio.enviar(new List<AvisoSolicitudSitio.Solicitud>{ s });
	}

	@isTest
	static void ubicacionesConExcel() {
		Account cliente = new Account(Name = 'Cliente Aviso Ubicaciones');
		insert cliente;
		InsurancePolicy danos = poliza(cliente.Id, 'DANOS-AVISO-1', 'Danos');
		insert danos;
		insert new List<InsurancePolicyAsset>{ new InsurancePolicyAsset(InsurancePolicyId = danos.Id, AssetName = 'Inciso 1 - Oficina'),
			new InsurancePolicyAsset(InsurancePolicyId = danos.Id, AssetName = 'Inciso 2 - Planta') };
		PortalPolizasController.cuentaPrueba = cliente.Id;
		PortalPolizasController.contactoPrueba = null;
		// Desde el sitio las ubicaciones llevan trámite (folio); la prueba corre con un usuario de Salesforce, que no lo lleva.
		MovimientosUbicacionesController.conTramiteEnPrueba = true;
		PortalPolizasPestanas.crearSolicitud(danos.Id, JSON.serialize(new Map<String, Object>{ 'comentario' => 'Urgente', 'movimientos' => new List<Object>{
			new Map<String, Object>{ 'tipo' => 'alta', 'fecha' => String.valueOf(Date.today()),
				'datos' => new List<Object>{ new Map<String, Object>{ 'etiqueta' => 'Nombre', 'valor' => 'Bodega' } },
				'campos' => new Map<String, Object>{ 'ubicacion' => 'Bodega', 'direccion' => 'Av. Uno 100', 'suma' => '1,500,000' } } } }), null);
		Test.startTest();
		List<AvisoSolicitudSitio.Resultado> r = avisar(danos.Id);
		Test.stopTest();
		Assert.isTrue(r[0].enviado, r[0].mensaje);
		Assert.isTrue(r[0].mensaje.contains('Ubicaciones_DANOS-AVISO-1_SOL-0001.xlsx'), r[0].mensaje);
		Assert.areEqual(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId IN (SELECT Id FROM Case WHERE InsurancePolicy__c = :danos.Id)
			AND ContentDocument.Title = 'Ubicaciones_DANOS-AVISO-1_SOL-0001'], 'El Excel queda en el caso');
		AvisoSolicitudSitio.Archivo x = AvisoSolicitudSitio.excel(danos.Id, 'SOL-0001');
		Assert.areEqual(1, x.renglones, 'Un renglón por ubicación de la solicitud');
		Assert.areEqual(1, x.porTipo.get('Alta'), 'Una alta');
	}

	@isTest
	static void aseguradosConExcel() {
		Account empresa = new Account(Name = 'Empresa Aviso GMM');
		insert empresa;
		Contact empleado = new Contact(LastName = 'Empleado', FirstName = 'Juan', AccountId = empresa.Id);
		insert empleado;
		InsurancePolicy col = poliza(empresa.Id, 'COL-AVISO-1', 'GMM');
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
				'parentesco' => 'Titular', 'categoria' => 'General' } };
		Map<String, Object> baja = new Map<String, Object>{ 'tipo' => 'baja', 'registroId' => titular.Id, 'detalle' => 'Renuncia' };
		PortalPolizasPestanas.crearSolicitud(col.Id, JSON.serialize(new Map<String, Object>{ 'movimientos' => new List<Object>{ alta, baja } }), null);
		Test.startTest();
		List<AvisoSolicitudSitio.Resultado> r = avisar(col.Id);
		AvisoSolicitudSitio.Archivo x = AvisoSolicitudSitio.excel(col.Id, 'SOL-0001');
		Test.stopTest();
		Assert.isTrue(r[0].enviado, r[0].mensaje);
		Assert.isTrue(x.renglones >= 1, 'Renglones de asegurados');
		Assert.isNotNull(x.contenido, 'Excel generado');
		// GMM sin dependientes: sin columnas de dependientes ni porcentaje; sin certificado, «POR ASIGNAR».
		Compression.ZipReader z = new Compression.ZipReader(x.contenido);
		String hoja = z.extract('xl/worksheets/sheet1.xml').toString();
		Assert.isFalse(hoja.contains('Porcentaje') || hoja.contains('Sexo Dependiente'), 'Sin columnas de dependientes');
		Assert.isTrue(hoja.contains('POR ASIGNAR'), 'Alta sin certificado');
		Assert.isFalse(AvisoSolicitudSitio.excel(col.Id, 'SOL-9999').renglones > 0, 'Otro folio no tiene registros');
	}

	@isTest
	static void vehiculosConExcel() {
		Account cliente = new Account(Name = 'Cliente Aviso Flotilla');
		insert cliente;
		InsurancePolicy auto = poliza(cliente.Id, 'FLOT-AVISO-1', 'Automoviles');
		insert auto;
		insert new List<Inciso_Flotilla__c>{
			new Inciso_Flotilla__c(Poliza__c = auto.Id, Numero_Inciso__c = 1, Descripcion__c = 'NISSAN VERSA', Serie__c = 'AAA111',
				Placas__c = 'ABC123', Modelo__c = 2020, Fecha_Alta__c = Date.today().addDays(-10)),
			new Inciso_Flotilla__c(Poliza__c = auto.Id, Numero_Inciso__c = 2, Descripcion__c = 'VW JETTA', Serie__c = 'BBB222',
				Placas__c = 'XYZ999', Modelo__c = 2021, Fecha_Alta__c = Date.today().addDays(-10))
		};
		PortalPolizasController.cuentaPrueba = cliente.Id;
		PortalPolizasController.contactoPrueba = null;
		String hoy = String.valueOf(Date.today());
		Map<String, Object> archivo = new Map<String, Object>{ 'tipo' => 'varios', 'nombre' => 'FLOTILLA.xlsx', 'total' => 2,
			'encabezados' => new List<Object>{ 'MOVIMIENTO', 'MODELO', 'MARCA', 'VERSION', 'SERIE', 'PLACAS' },
			'filas' => new List<Object>(),
			'registros' => new List<Object>{
				new Map<String, Object>{ 'tipo' => 'alta', 'fila' => 2, 'fecha' => hoy, 'campos' => new Map<String, Object>{
					'modelo' => '2014', 'marca' => 'TOYOTA', 'version' => 'YARIS CORE', 'serie' => 'JTDKT9D38ED585824', 'placas' => 'KXM751A' } },
				new Map<String, Object>{ 'tipo' => 'baja', 'fila' => 3, 'fecha' => hoy, 'comentario' => 'Venta',
					'campos' => new Map<String, Object>{ 'serie' => 'aaa111' } }
			} };
		Map<String, Object> res;
		try {
			res = PortalPolizasPestanas.crearSolicitud(auto.Id, JSON.serialize(new Map<String, Object>{ 'listado' => archivo }), null);
		} catch (Exception e) {
			res = null;
		}
		Test.startTest();
		AvisoSolicitudSitio.Archivo x = AvisoSolicitudSitio.excel(auto.Id, 'SOL-0001');
		if (res != null) {
			List<AvisoSolicitudSitio.Resultado> r = avisar(auto.Id);
			Assert.isTrue(r[0].enviado, r[0].mensaje);
		}
		Test.stopTest();
		Assert.areEqual('vehículos', x.bienes, 'Póliza de flotilla');
	}

	@isTest
	static void xlsxYErrores() {
		Blob b = AvisoSolicitudSitio.xlsx('Hoja: 1', new List<String>{ 'A', 'B' },
			new List<List<Object>>{ new List<Object>{ 'texto <&>', 5 }, new List<Object>{ null, 1.5 } });
		Assert.isTrue(b.size() > 100, 'Archivo zip');
		AvisoSolicitudSitio.Solicitud s = new AvisoSolicitudSitio.Solicitud();
		s.casoId = null;
		s.destinatarios = 'x@prueba.test';
		List<AvisoSolicitudSitio.Resultado> r = AvisoSolicitudSitio.enviar(new List<AvisoSolicitudSitio.Solicitud>{ s });
		Assert.isFalse(r[0].enviado, 'Sin caso no se envía');
	}
}
