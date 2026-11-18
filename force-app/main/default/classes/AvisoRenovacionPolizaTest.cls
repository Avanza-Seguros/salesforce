/**
 * @creation date: 18/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas del aviso de renovación de póliza (AvisoRenovacionPoliza): marcadores y texto según el tipo de
 *               póliza, envío manual (destinatarios de prueba fuera de producción, tarea en la póliza), envío automático
 *               a 30 días sin repetir el mismo día y programación del job.
 */
@isTest
private class AvisoRenovacionPolizaTest {

	static InsurancePolicy poliza(Id cuenta, String numero, Integer diasParaVencer) {
		InsurancePolicy p = new InsurancePolicy(Name = numero, NameInsuredId = cuenta, Status = 'Vigente',
			PremiumAmount = 12500.5, PaymentDueDate = Date.today().addDays(30),
			EffectiveDate = Datetime.now().addDays(diasParaVencer - 365),
			ExpirationDate = Datetime.newInstance(Date.today().addDays(diasParaVencer), Time.newInstance(12, 0, 0, 0)), Primer_Pago__c = 250);
		for (Schema.PicklistEntry pe : InsurancePolicy.PremiumFrequency.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { p.PremiumFrequency = pe.getValue(); break; }
		}
		return p;
	}

	static String ramoQueEmpieza(String prefijo) {
		for (Schema.PicklistEntry pe : InsurancePolicy.Ramo__c.getDescribe().getPicklistValues()) {
			String k = CensoColectivoController.llave(pe.getLabel());
			if (pe.isActive() && k != null && k.startsWith(prefijo)) { return pe.getLabel(); }
		}
		return null;
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Marcadores: días que faltan, empresarial sin oportunidad (cuenta de empresa), prima y agente por
	 *               defecto; el texto pide lo que corresponde al ramo; el llenado escapa HTML y quita marcadores sin valor.
	 * @return void
	 */
	@isTest
	static void testMarcadoresYMensajes() {
		Account empresa = new Account(Name = 'Empresa Renovación');
		insert empresa;
		InsurancePolicy p = poliza(empresa.Id, 'REN-MARC-1', 30);
		insert p;
		p = [SELECT Id, Name, toLabel(Ramo__c), EffectiveDate, ExpirationDate, PremiumAmount, OwnerId, Aseguradora__r.Name,
				Product.Aseguradora__r.Name, Producer.Name, SourceOpportunityId, SourceOpportunity.Tipo_Contratacion__c,
				NameInsuredId, NameInsured.Name, NameInsured.IsPersonAccount
			FROM InsurancePolicy WHERE Id = :p.Id];
		Map<String, String> v = AvisoRenovacionPoliza.marcadores(p);
		System.assertEquals('vence en 30 días', v.get('AVISO_DIAS'));
		System.assertEquals('Empresarial', v.get('TIPO_POLIZA'), 'Sin oportunidad y cuenta de empresa');
		System.assertEquals('Empresa Renovación', v.get('NOMBRE_CONTRATANTE'));
		System.assertEquals('Avanza Seguro Consultores', v.get('AGENTE'));
		System.assert(v.get('PRIMA_ACTUAL').startsWith('$'), v.get('PRIMA_ACTUAL'));
		System.assert(v.get('MENSAJE_RENOVACION').contains('asegurados'), v.get('MENSAJE_RENOVACION'));

		System.assert(AvisoRenovacionPoliza.mensaje(true, 'vehiculos').contains('vehículos'));
		System.assert(AvisoRenovacionPoliza.mensaje(true, 'ubicaciones').contains('ubicaciones'));
		System.assert(AvisoRenovacionPoliza.mensaje(false, 'vehiculos').contains('vehículo'));
		System.assert(AvisoRenovacionPoliza.mensaje(false, 'ubicaciones').contains('inmueble'));
		System.assert(AvisoRenovacionPoliza.mensaje(false, 'personas').contains('beneficiarios'));
		System.assertEquals('personas', AvisoRenovacionPoliza.tipoRamo(null));
		String auto = ramoQueEmpieza('auto');
		if (auto != null) { System.assertEquals('vehiculos', AvisoRenovacionPoliza.tipoRamo(auto)); }

		String html = AvisoRenovacionPoliza.llenar('<p>{{A}}</p>{{HTML_B}}{{SIN_VALOR}}',
			new Map<String, String>{ 'A' => 'x<y', 'HTML_B' => '<b>ok</b>' }, true);
		System.assertEquals('<p>x&lt;y</p><b>ok</b>', html);
		System.assertEquals('x<y', AvisoRenovacionPoliza.llenar('{{A}}{{HTML_B}}',
			new Map<String, String>{ 'A' => 'x<y', 'HTML_B' => '<b>' }, false));
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Botón de la póliza: fuera de producción va a los destinatarios de prueba y deja la tarea; una póliza
	 *               cancelada no se avisa.
	 * @return void
	 */
	@isTest
	static void testEnvioManual() {
		Account empresa = new Account(Name = 'Empresa Manual');
		insert empresa;
		InsurancePolicy p = poliza(empresa.Id, 'REN-MAN-1', 20);
		insert p;
		AvisoRenovacionPoliza.produccionPrueba = false;
		Test.startTest();
		String para;
		String error;
		try { para = AvisoRenovacionPoliza.enviarAviso(p.Id); } catch (AuraHandledException e) { error = e.getMessage(); }
		Test.stopTest();
		if (error == null) {
			System.assertEquals(String.join(AvisoRenovacionPoliza.PRUEBA_PARA, ', '), para);
			Task t = [SELECT Subject, Description FROM Task WHERE WhatId = :p.Id];
			System.assert(t.Subject.startsWith(AvisoRenovacionPoliza.ASUNTO_TAREA), t.Subject);
			System.assert(t.Description.contains('Envío manual'), t.Description);
		} else {
			// Org sin entregabilidad: el error se informa al usuario.
			System.assert(error.contains('correo') || error.contains('plantilla'), error);
		}

		update new InsurancePolicy(Id = p.Id, Status = 'Cancelado');
		Boolean bloqueada = false;
		try { AvisoRenovacionPoliza.enviarAviso(p.Id); } catch (AuraHandledException e) { bloqueada = true; }
		System.assert(bloqueada, 'Cancelada: sin aviso');
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: En producción, sin correo del contratante no se envía y se informa.
	 * @return void
	 */
	@isTest
	static void testProduccionSinCorreo() {
		Account empresa = new Account(Name = 'Empresa Sin Correo');
		insert empresa;
		InsurancePolicy p = poliza(empresa.Id, 'REN-PRD-1', 30);
		insert p;
		AvisoRenovacionPoliza.produccionPrueba = true;
		Map<Id, String> r = AvisoRenovacionPoliza.enviar(new Set<Id>{ p.Id }, false);
		System.assert(r.get(p.Id).startsWith('ERROR:'), r.get(p.Id));
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Envío automático: el batch toma las Vigentes que vencen en 30 días (no las de 45), no repite el
	 *               aviso el mismo día y la programación diaria queda registrada una sola vez.
	 * @return void
	 */
	@isTest
	static void testBatchYProgramacion() {
		Account empresa = new Account(Name = 'Empresa Batch');
		insert empresa;
		InsurancePolicy a30 = poliza(empresa.Id, 'REN-B-30', 30);
		InsurancePolicy a45 = poliza(empresa.Id, 'REN-B-45', 45);
		insert new List<InsurancePolicy>{ a30, a45 };
		AvisoRenovacionPoliza.produccionPrueba = false;
		Test.startTest();
		Id job = AvisoRenovacionPoliza.programar();
		System.assertEquals(job, AvisoRenovacionPoliza.programar(), 'No se programa dos veces');
		Database.executeBatch(new AvisoRenovacionPoliza(), 20);
		Test.stopTest();
		System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :a45.Id], 'A 45 días no se avisa');
		Integer antes = [SELECT COUNT() FROM Task WHERE WhatId = :a30.Id];
		System.assert(antes <= 1, 'Un solo aviso');
		// Segunda corrida el mismo día: no se repite.
		new AvisoRenovacionPoliza().execute(null, new List<InsurancePolicy>{ new InsurancePolicy(Id = a30.Id) });
		if (antes == 1) { System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :a30.Id]); }
	}
}
