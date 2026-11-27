/**
 * @creation date: 14/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pólizas (InsurancePolicy) del cliente que entra al sitio Avanza Seguro.
 *   El usuario del sitio ve solo las pólizas de su cuenta: donde su cuenta es el asegurado titular
 *   (NameInsuredId) o donde él aparece como participante activo (por cuenta o por contacto).
 *   El filtro por cuenta/contacto del usuario es la frontera de seguridad: se aplica siempre en el
 *   servidor, por eso la clase no depende de reglas de compartición del sitio.
 *   Vista previa: un usuario interno con el permiso personalizado Portal_Polizas_Vista_Previa puede elegir
 *   una cuenta y ver la página como la vería un usuario de esa cuenta.
 */
public without sharing class PortalPolizasController {

	/** En pruebas no se puede crear fácilmente un usuario de sitio: se fija aquí la cuenta/contacto. */
	@TestVisible static Id cuentaPrueba;
	@TestVisible static Id contactoPrueba;
	/** En pruebas se fija si el usuario tiene el permiso de vista previa. */
	@TestVisible static Boolean permisoVistaPreviaPrueba;

	static final String PERMISO_VISTA_PREVIA = 'Portal_Polizas_Vista_Previa';

	public class Poliza {
		@AuraEnabled public Id id;
		@AuraEnabled public String numero;
		@AuraEnabled public String ramo;
		@AuraEnabled public String tipo;
		@AuraEnabled public String aseguradora;
		@AuraEnabled public String estado;
		@AuraEnabled public Boolean vigente;
		@AuraEnabled public Date inicioVigencia;
		@AuraEnabled public Date finVigencia;
		@AuraEnabled public Decimal prima;
		@AuraEnabled public String moneda;
		@AuraEnabled public String formaPago;
		@AuraEnabled public Date proximoPago;
		@AuraEnabled public Decimal montoVencido;
		@AuraEnabled public Decimal montoPorPagar;
		@AuraEnabled public String bienAsegurado;
		@AuraEnabled public String descripcion;
		@AuraEnabled public String titular;
		@AuraEnabled public String miRol;
		/** Pestaña Siniestros: solo el contratante de una póliza empresarial (se llena en el detalle). */
		@AuraEnabled public Boolean conSiniestros = false;
	}

	public class Documento {
		@AuraEnabled public Id id;
		@AuraEnabled public String titulo;
		@AuraEnabled public String extension;
		@AuraEnabled public Integer tamano;
		@AuraEnabled public Datetime fecha;
	}

	public class Detalle {
		@AuraEnabled public Poliza poliza;
		@AuraEnabled public List<Documento> documentos = new List<Documento>();
	}

	public class Cuenta {
		@AuraEnabled public Id id;
		@AuraEnabled public String nombre;
		@AuraEnabled public Integer polizas;
	}

	public class CuotaDashboard {
		@AuraEnabled public Id id;
		@AuraEnabled public Id polizaId;
		@AuraEnabled public String numero;
		@AuraEnabled public String ramo;
		@AuraEnabled public String moneda;
		@AuraEnabled public Date vence;
		@AuraEnabled public Decimal pendiente;
		@AuraEnabled public Boolean vencida;
		@AuraEnabled public Integer diasMora;
	}

	public class MesDashboard {
		@AuraEnabled public Date inicio;
		@AuraEnabled public Decimal monto = 0;
		@AuraEnabled public Integer cuotas = 0;
	}

	public class EndosoDashboard {
		@AuraEnabled public Id id;
		@AuraEnabled public String numero;
		@AuraEnabled public String poliza;
		@AuraEnabled public String ramo;
		@AuraEnabled public String moneda;
		@AuraEnabled public Date fecha;
		@AuraEnabled public Decimal total;
		@AuraEnabled public String descripcion;
	}

	public class MovimientoDashboard {
		@AuraEnabled public Id id;
		@AuraEnabled public String tipo;
		@AuraEnabled public String nombre;
		@AuraEnabled public String poliza;
		@AuraEnabled public String endoso;
		@AuraEnabled public Date fecha;
	}

	/** Altas, bajas y cambios registrados en un mes (pólizas donde el usuario es el contratante). */
	public class MovimientosMes {
		@AuraEnabled public Date inicio;
		@AuraEnabled public Integer altas = 0;
		@AuraEnabled public Integer bajas = 0;
		@AuraEnabled public Integer cambios = 0;
	}

	/** Prima de los endosos de un mes en una moneda: lo que se cobra (importes positivos) y lo que se devuelve (negativos). */
	public class PrimaMes {
		@AuraEnabled public Date inicio;
		@AuraEnabled public String moneda;
		@AuraEnabled public Decimal cargos = 0;
		@AuraEnabled public Decimal devoluciones = 0;
		@AuraEnabled public Integer endosos = 0;
	}

	public class Dashboard {
		@AuraEnabled public List<Poliza> polizas = new List<Poliza>();
		@AuraEnabled public Map<String, Integer> bienes = new Map<String, Integer>();
		@AuraEnabled public List<MesDashboard> pagadoPorMes = new List<MesDashboard>();
		@AuraEnabled public List<EndosoDashboard> endosos = new List<EndosoDashboard>();
		@AuraEnabled public List<MovimientoDashboard> movimientos = new List<MovimientoDashboard>();
		@AuraEnabled public Map<String, Integer> movimientosAnio = new Map<String, Integer>{ 'Alta' => 0, 'Baja' => 0, 'Cambio' => 0 };
		@AuraEnabled public List<MovimientosMes> movimientosPorMes = new List<MovimientosMes>();
		@AuraEnabled public List<PrimaMes> primasPorMes = new List<PrimaMes>();
		@AuraEnabled public List<CuotaDashboard> proximasCuotas = new List<CuotaDashboard>();
		@AuraEnabled public List<MesDashboard> pagosPorMes = new List<MesDashboard>();
		@AuraEnabled public Decimal totalPendiente = 0;
		@AuraEnabled public Decimal totalVencido = 0;
		@AuraEnabled public Integer cuotasVencidas = 0;
		@AuraEnabled public Decimal pagadoUltimoAnio = 0;
	}

	/**
	 * @creation date: 15/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Datos del Dashboard del sitio: las pólizas del usuario y, de sus cuotas (sin las reemplazadas por
	 * un recibo nuevo ni las canceladas o condonadas), lo pendiente, lo vencido, las próximas a pagar, lo que se
	 * pagará en cada uno de los próximos 6 meses y lo pagado en los últimos 12.
	 * @param cuentaVistaPrevia: Cuenta a simular (solo vista previa de administrador); null para el usuario real
	 * @return Dashboard
	 */
	static final String ESTADO_CANCELADO = 'Cancelado';

	@AuraEnabled(cacheable=true)
	public static Dashboard dashboard(Id cuentaVistaPrevia) {
		return dashboardInterno(cuentaVistaPrevia);
	}

	/**
	 * @creation date: 15/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Endosos y movimientos recientes del Dashboard. Endosos: los últimos de todas las pólizas del
	 * usuario. Movimientos (altas, bajas y cambios de asegurados, vehículos y ubicaciones): solo de las pólizas donde
	 * es el contratante, para no mostrar datos de otras personas; los últimos y el conteo de los últimos 12 meses.
	 * @param d: Dashboard a completar
	 * @param roles: Póliza → rol del usuario
	 * @param porId: Pólizas del usuario por Id
	 * @return void
	 */
	static void movimientosYEndosos(Dashboard d, Map<Id, String> roles, Map<Id, Poliza> porId) {
		Set<Id> ids = roles.keySet();
		// Últimos 12 meses (el actual incluido): movimientos por mes y prima de los endosos por mes.
		Date primerMes = Date.today().toStartOfMonth().addMonths(-11);
		for (Integer i = 0; i < 12; i++) {
			MovimientosMes mm = new MovimientosMes();
			mm.inicio = primerMes.addMonths(i);
			d.movimientosPorMes.add(mm);
		}
		primasPorMes(d, ids, porId, primerMes);
		for (InsurancePolicyTransaction t : [
			SELECT Id, Name, TransactionNumber, InsurancePolicyId, EffectiveFromDate, TransactionEffectiveDate, TotalTransactionAmount
			FROM InsurancePolicyTransaction
			WHERE InsurancePolicyId IN :ids AND Category = 'Endorsement'
			ORDER BY EffectiveFromDate DESC NULLS LAST, CreatedDate DESC
			LIMIT 6
		]) {
			Poliza p = porId.get(t.InsurancePolicyId);
			EndosoDashboard e = new EndosoDashboard();
			e.id = t.Id;
			e.numero = t.TransactionNumber;
			e.poliza = p?.numero;
			e.ramo = p?.ramo;
			e.moneda = p == null ? 'MXN' : p.moneda;
			e.fecha = t.EffectiveFromDate != null ? t.EffectiveFromDate
				: (t.TransactionEffectiveDate == null ? null : t.TransactionEffectiveDate.date());
			e.total = t.TotalTransactionAmount;
			// "Endoso A0002 - Alta de ubicación - 5-43599": lo de en medio es la descripción.
			String n = t.Name == null ? '' : t.Name;
			n = n.replaceFirst('(?i)^Endoso\\s+\\S+\\s*-?\\s*', '');
			if (p != null && n.endsWith(p.numero)) { n = n.substring(0, n.length() - p.numero.length()); }
			e.descripcion = n.replaceAll('[\\s-]+$', '').trim();
			d.endosos.add(e);
		}
		Set<Id> propias = new Set<Id>();
		for (Id pid : roles.keySet()) {
			if (roles.get(pid) == 'Titular') { propias.add(pid); }
		}
		if (propias.isEmpty()) { return; }
		Date haceUnAnio = Date.today().addYears(-1);
		for (AggregateResult ar : [
			SELECT Tipo__c tipo, COUNT(Id) n FROM Movimiento_Poliza__c
			WHERE Poliza__c IN :propias AND Fecha_Movimiento__c >= :haceUnAnio GROUP BY Tipo__c
		]) {
			String tipo = (String) ar.get('tipo');
			if (d.movimientosAnio.containsKey(tipo)) { d.movimientosAnio.put(tipo, (Integer) ar.get('n')); }
		}
		for (AggregateResult ar : [
			SELECT CALENDAR_YEAR(Fecha_Movimiento__c) anio, CALENDAR_MONTH(Fecha_Movimiento__c) mes, Tipo__c tipo, COUNT(Id) n
			FROM Movimiento_Poliza__c
			WHERE Poliza__c IN :propias AND Fecha_Movimiento__c >= :primerMes
			GROUP BY CALENDAR_YEAR(Fecha_Movimiento__c), CALENDAR_MONTH(Fecha_Movimiento__c), Tipo__c
		]) {
			Integer i = primerMes.monthsBetween(Date.newInstance((Integer) ar.get('anio'), (Integer) ar.get('mes'), 1));
			if (i < 0 || i >= 12) { continue; }
			MovimientosMes mm = d.movimientosPorMes[i];
			Integer n = (Integer) ar.get('n');
			String tipo = (String) ar.get('tipo');
			if (tipo == 'Alta') { mm.altas += n; } else if (tipo == 'Baja') { mm.bajas += n; } else if (tipo == 'Cambio') { mm.cambios += n; }
		}
		for (Movimiento_Poliza__c m : [
			SELECT Id, Tipo__c, Asegurado__c, Numero_Endoso__c, Fecha_Movimiento__c, Poliza__c
			FROM Movimiento_Poliza__c WHERE Poliza__c IN :propias
			ORDER BY Fecha_Movimiento__c DESC NULLS LAST, CreatedDate DESC
			LIMIT 8
		]) {
			MovimientoDashboard x = new MovimientoDashboard();
			x.id = m.Id;
			x.tipo = m.Tipo__c;
			x.nombre = m.Asegurado__c;
			x.poliza = porId.get(m.Poliza__c)?.numero;
			x.endoso = m.Numero_Endoso__c;
			x.fecha = m.Fecha_Movimiento__c;
			d.movimientos.add(x);
		}
	}

	/**
	 * @creation date: 19/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Prima de los endosos de las pólizas del usuario en cada uno de los últimos 12 meses, por moneda:
	 * lo cobrado (endosos con importe positivo, p. ej. altas) y lo devuelto (importe negativo, p. ej. bajas).
	 * @param d: Dashboard a completar
	 * @param ids: Pólizas del usuario
	 * @param porId: Pólizas del usuario por Id (para la moneda)
	 * @param primerMes: Primer día del primer mes
	 * @return void
	 */
	static void primasPorMes(Dashboard d, Set<Id> ids, Map<Id, Poliza> porId, Date primerMes) {
		Map<String, PrimaMes> porClave = new Map<String, PrimaMes>();
		Datetime desde = Datetime.newInstance(primerMes, Time.newInstance(0, 0, 0, 0));
		for (InsurancePolicyTransaction t : [
			SELECT InsurancePolicyId, EffectiveFromDate, TransactionEffectiveDate, TotalTransactionAmount, TransactionAmount
			FROM InsurancePolicyTransaction
			WHERE InsurancePolicyId IN :ids AND Category = 'Endorsement'
				AND (EffectiveFromDate >= :primerMes OR (EffectiveFromDate = null AND TransactionEffectiveDate >= :desde))
			LIMIT 5000
		]) {
			// Total del endoso (prima con derechos e IVA); si no lo hay, la prima neta.
			Decimal monto = t.TotalTransactionAmount != null ? t.TotalTransactionAmount : t.TransactionAmount;
			if (monto == null || monto == 0) { continue; }
			Date f = t.EffectiveFromDate != null ? t.EffectiveFromDate : t.TransactionEffectiveDate.date();
			Integer i = primerMes.monthsBetween(f.toStartOfMonth());
			if (i < 0 || i >= 12) { continue; }
			Poliza p = porId.get(t.InsurancePolicyId);
			String moneda = p == null || String.isBlank(p.moneda) ? 'MXN' : p.moneda;
			String clave = i + '|' + moneda;
			PrimaMes pm = porClave.get(clave);
			if (pm == null) {
				pm = new PrimaMes();
				pm.inicio = primerMes.addMonths(i);
				pm.moneda = moneda;
				porClave.put(clave, pm);
				d.primasPorMes.add(pm);
			}
			if (monto > 0) { pm.cargos += monto; } else { pm.devoluciones -= monto; }
			pm.endosos++;
		}
	}

	static Dashboard dashboardInterno(Id cuentaVistaPrevia) {
		try {
			Dashboard d = new Dashboard();
			Map<Id, String> roles = polizasDelUsuario(cuentaVistaPrevia);
			if (roles.isEmpty()) { return d; }
			Set<Id> ids = roles.keySet();
			Map<Id, Poliza> porId = new Map<Id, Poliza>();
			for (InsurancePolicy p : Database.query(consulta() + ' WHERE Id IN :ids ORDER BY ExpirationDate DESC NULLS LAST, Name')) {
				Poliza o = convertir(p, roles.get(p.Id));
				d.polizas.add(o);
				porId.put(o.id, o);
			}
			Date hoy = Date.today();
			Date primerMes = hoy.toStartOfMonth();
			for (Integer i = 0; i < 6; i++) {
				MesDashboard m = new MesDashboard();
				m.inicio = primerMes.addMonths(i);
				d.pagosPorMes.add(m);
			}
			// Historial: lo pagado en cada uno de los últimos 12 meses (el actual incluido).
			Date primerHistorial = primerMes.addMonths(-11);
			for (Integer i = 0; i < 12; i++) {
				MesDashboard m = new MesDashboard();
				m.inicio = primerHistorial.addMonths(i);
				d.pagadoPorMes.add(m);
			}
			// Estado (valor, no etiqueta), fin de vigencia y renovaciones de cada póliza.
			Map<Id, InsurancePolicy> estados = new Map<Id, InsurancePolicy>([
				SELECT Id, Status, ExpirationDate, PriorPolicyId, RenewedFromPolicyId FROM InsurancePolicy WHERE Id IN :ids
			]);
			Set<Id> renovadas = new Set<Id>();
			for (InsurancePolicy e : estados.values()) {
				if (e.PriorPolicyId != null) { renovadas.add(e.PriorPolicyId); }
				if (e.RenewedFromPolicyId != null) { renovadas.add(e.RenewedFromPolicyId); }
			}
			// Bienes asegurados, como en Salesforce: también los de pólizas vencidas, sin las canceladas ni las que ya
			// se renovaron en otra póliza del cliente (para no contar dos veces lo mismo).
			Map<Id, String> ramosBienes = new Map<Id, String>();
			for (Poliza o : d.polizas) {
				InsurancePolicy e = estados.get(o.id);
				if (e != null && e.Status == ESTADO_CANCELADO) { continue; }
				if (o.vigente != true && renovadas.contains(o.id)) { continue; }
				ramosBienes.put(o.id, o.ramo);
			}
			d.bienes = PortalPolizasPestanas.contarBienes(ramosBienes, roles, cuentaVistaPrevia);
			movimientosYEndosos(d, roles, porId);
			List<PaymentPlanInstallment__c> cuotas = [
				SELECT Id, dueDate__c, expectedAmount__c, matchedAmount__c, outstandingAmount__c, installmentStatus__c,
					daysOverdue__c, replacesInstallment__c, paymentPlan__r.insurancePolicy__c, matchedReceipt__r.receiptDate__c
				FROM PaymentPlanInstallment__c
				WHERE paymentPlan__r.insurancePolicy__c IN :ids
				ORDER BY dueDate__c ASC NULLS LAST
				LIMIT 5000
			];
			Set<Id> reemplazadas = new Set<Id>();
			for (PaymentPlanInstallment__c c : cuotas) {
				if (c.replacesInstallment__c != null) { reemplazadas.add(c.replacesInstallment__c); }
			}
			Date haceUnAnio = hoy.addYears(-1);
			for (PaymentPlanInstallment__c c : cuotas) {
				if (reemplazadas.contains(c.Id)) { continue; }
				String estado = c.installmentStatus__c;
				if (estado == 'Conciliado') {
					Date pago = c.matchedReceipt__r?.receiptDate__c;
					if (pago != null && pago >= haceUnAnio && c.matchedAmount__c != null) { d.pagadoUltimoAnio += c.matchedAmount__c; }
					if (pago != null && c.matchedAmount__c != null) {
						Integer mes = primerHistorial.monthsBetween(pago.toStartOfMonth());
						if (mes >= 0 && mes < 12) {
							d.pagadoPorMes[mes].monto += c.matchedAmount__c;
							d.pagadoPorMes[mes].cuotas++;
						}
					}
					continue;
				}
				if (estado != 'Pendiente' && estado != 'Vencido') { continue; }
				// No se cobran cuotas de pólizas canceladas ni las que vencen después de que terminó la póliza.
				InsurancePolicy e = estados.get(c.paymentPlan__r.insurancePolicy__c);
				if (e != null && (e.Status == ESTADO_CANCELADO || (e.ExpirationDate != null && c.dueDate__c != null
						&& c.dueDate__c > e.ExpirationDate.date()))) { continue; }
				Decimal pendiente = c.outstandingAmount__c == null ? 0 : c.outstandingAmount__c;
				if (pendiente <= 0) { continue; }
				Boolean vencida = estado == 'Vencido' || (c.dueDate__c != null && c.dueDate__c < hoy);
				d.totalPendiente += pendiente;
				if (vencida) {
					d.totalVencido += pendiente;
					d.cuotasVencidas++;
				} else if (c.dueDate__c != null) {
					Integer mes = primerMes.monthsBetween(c.dueDate__c.toStartOfMonth());
					if (mes >= 0 && mes < 6) {
						d.pagosPorMes[mes].monto += pendiente;
						d.pagosPorMes[mes].cuotas++;
					}
				}
				if (d.proximasCuotas.size() < 8) {
					Poliza p = porId.get(c.paymentPlan__r.insurancePolicy__c);
					CuotaDashboard q = new CuotaDashboard();
					q.id = c.Id;
					q.polizaId = p?.id;
					q.numero = p?.numero;
					q.ramo = p?.ramo;
					q.moneda = p == null ? 'MXN' : p.moneda;
					q.vence = c.dueDate__c;
					q.pendiente = pendiente;
					q.vencida = vencida;
					q.diasMora = c.daysOverdue__c != null && c.daysOverdue__c > 0 ? c.daysOverdue__c.intValue() : null;
					d.proximasCuotas.add(q);
				}
			}
			return d;
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			throw error(e);
		}
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Indica si el usuario puede usar la vista previa de administrador.
	 * @return true si es usuario interno con el permiso Portal_Polizas_Vista_Previa
	 */
	@AuraEnabled(cacheable=true)
	public static Boolean puedeVistaPrevia() {
		return tieneVistaPrevia();
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Busca cuentas titulares de pólizas para la vista previa de administrador.
	 * @param texto: Parte del nombre de la cuenta (mínimo 2 letras)
	 * @return Hasta 20 cuentas con su número de pólizas como titular
	 */
	@AuraEnabled(cacheable=true)
	public static List<Cuenta> buscarCuentas(String texto) {
		if (!tieneVistaPrevia()) {
			throw new AuraHandledException('No tienes permiso para la vista previa.');
		}
		List<Cuenta> salida = new List<Cuenta>();
		if (String.isBlank(texto) || texto.trim().length() < 2) { return salida; }
		String patron = '%' + texto.trim().replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%';
		for (AggregateResult ar : [
			SELECT NameInsuredId cuenta, NameInsured.Name nombre, COUNT(Id) n
			FROM InsurancePolicy
			WHERE NameInsuredId != null AND NameInsured.Name LIKE :patron
			GROUP BY NameInsuredId, NameInsured.Name
			ORDER BY NameInsured.Name
			LIMIT 20
		]) {
			Cuenta c = new Cuenta();
			c.id = (Id) ar.get('cuenta');
			c.nombre = (String) ar.get('nombre');
			c.polizas = (Integer) ar.get('n');
			salida.add(c);
		}
		return salida;
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Pólizas del usuario del sitio, de la vigencia más reciente a la más antigua.
	 * @param cuentaVistaPrevia: Cuenta a simular (solo vista previa de administrador); null para el usuario real
	 * @return Lista de pólizas
	 */
	@AuraEnabled(cacheable=true)
	public static List<Poliza> misPolizas(Id cuentaVistaPrevia) {
		try {
			Map<Id, String> roles = polizasDelUsuario(cuentaVistaPrevia);
			List<Poliza> salida = new List<Poliza>();
			if (roles.isEmpty()) { return salida; }
			Set<Id> ids = roles.keySet();
			for (InsurancePolicy p : Database.query(consulta() + ' WHERE Id IN :ids ORDER BY ExpirationDate DESC NULLS LAST, Name')) {
				salida.add(convertir(p, roles.get(p.Id)));
			}
			return salida;
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			throw error(e);
		}
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Detalle de una póliza del usuario y sus archivos publicados para el sitio.
	 * @param policyId: Id de la póliza
	 * @param cuentaVistaPrevia: Cuenta a simular (solo vista previa de administrador); null para el usuario real
	 * @return Póliza y documentos
	 */
	@AuraEnabled(cacheable=true)
	public static Detalle detallePoliza(Id policyId, Id cuentaVistaPrevia) {
		try {
			Map<Id, String> roles = polizasDelUsuario(cuentaVistaPrevia);
			if (policyId == null || !roles.containsKey(policyId)) {
				throw new AuraHandledException('La póliza no existe o no tienes acceso a ella.');
			}
			Detalle d = new Detalle();
			InsurancePolicy p = Database.query(consulta() + ' WHERE Id = :policyId LIMIT 1');
			d.poliza = convertir(p, roles.get(policyId));
			d.poliza.conSiniestros = roles.get(policyId) == 'Titular' && PortalPolizasPestanas.polizaEmpresarial(policyId);
			// Solo los archivos que se publicaron para usuarios externos.
			for (ContentDocumentLink l : [
				SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension,
					ContentDocument.ContentSize, ContentDocument.LastModifiedDate
				FROM ContentDocumentLink
				WHERE LinkedEntityId = :policyId AND Visibility = 'AllUsers'
				ORDER BY ContentDocument.LastModifiedDate DESC LIMIT 50
			]) {
				Documento doc = new Documento();
				doc.id = l.ContentDocumentId;
				doc.titulo = l.ContentDocument.Title;
				doc.extension = l.ContentDocument.FileExtension;
				doc.tamano = l.ContentDocument.ContentSize;
				doc.fecha = l.ContentDocument.LastModifiedDate;
				d.documentos.add(doc);
			}
			return d;
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			throw error(e);
		}
	}

	/** Tope del archivo que se entrega por Apex (la respuesta va en base64 y crece ~33%). */
	@TestVisible static final Integer MAX_BYTES_DESCARGA = 3 * 1024 * 1024;

	public class Archivo {
		@AuraEnabled public String nombre;
		@AuraEnabled public String tipo;
		@AuraEnabled public String base64;
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Entrega un documento publicado de una póliza del usuario. No depende de que el usuario del
	 * sitio tenga acceso al archivo por compartición: se valida que la póliza sea suya y que el archivo esté
	 * ligado a ella con visibilidad para usuarios externos.
	 * @param policyId: Id de la póliza
	 * @param documentId: Id del ContentDocument
	 * @param cuentaVistaPrevia: Cuenta a simular (solo vista previa de administrador); null para el usuario real
	 * @return Nombre, tipo y contenido en base64
	 */
	@AuraEnabled
	public static Archivo descargarDocumento(Id policyId, Id documentId, Id cuentaVistaPrevia) {
		try {
			if (policyId == null || documentId == null || !polizasDelUsuario(cuentaVistaPrevia).containsKey(policyId)) {
				throw new AuraHandledException('El documento no existe o no tienes acceso a él.');
			}
			if ([SELECT COUNT() FROM ContentDocumentLink
				WHERE LinkedEntityId = :policyId AND ContentDocumentId = :documentId AND Visibility = 'AllUsers'] == 0) {
				throw new AuraHandledException('El documento no existe o no tienes acceso a él.');
			}
			ContentVersion v = [
				SELECT Title, FileExtension, FileType, ContentSize, VersionData
				FROM ContentVersion WHERE ContentDocumentId = :documentId AND IsLatest = true LIMIT 1
			];
			if (v.ContentSize > MAX_BYTES_DESCARGA) {
				throw new AuraHandledException('El documento es demasiado grande para descargarlo aquí. Pídelo a tu asesor.');
			}
			Archivo a = new Archivo();
			a.nombre = String.isBlank(v.FileExtension) ? v.Title : v.Title + '.' + v.FileExtension;
			a.tipo = v.FileType;
			a.base64 = EncodingUtil.base64Encode(v.VersionData);
			return a;
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			throw error(e);
		}
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valida que la póliza sea del usuario (o de la cuenta en vista previa). Lo usan las pestañas
	 * del detalle (PortalPolizasPestanas) antes de leer cualquier dato.
	 * @param policyId: Id de la póliza
	 * @param cuentaVistaPrevia: Cuenta a simular; null para el usuario real
	 * @return Mapa póliza → rol del usuario, con todas sus pólizas (sirve para filtrar vigencias)
	 */
	public static Map<Id, String> validarAcceso(Id policyId, Id cuentaVistaPrevia) {
		Map<Id, String> roles = polizasDelUsuario(cuentaVistaPrevia);
		if (policyId == null || !roles.containsKey(policyId)) {
			throw new AuraHandledException('La póliza no existe o no tienes acceso a ella.');
		}
		return roles;
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Error genérico para el cliente del sitio (el detalle técnico va al log).
	 * @param e: Excepción original
	 * @return AuraHandledException con mensaje genérico
	 */
	public static AuraHandledException errorSitio(Exception e) {
		return error(e);
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cuenta y contacto del usuario del sitio; en vista previa, la cuenta elegida y sin contacto.
	 * @param cuentaVistaPrevia: Cuenta a simular; null para el usuario real
	 * @return [cuenta, contacto] (cualquiera puede ser null)
	 */
	public static List<Id> identidad(Id cuentaVistaPrevia) {
		if (cuentaVistaPrevia != null) {
			if (!tieneVistaPrevia()) {
				throw new AuraHandledException('No tienes permiso para la vista previa.');
			}
			return new List<Id>{ cuentaVistaPrevia, null };
		}
		if (Test.isRunningTest()) {
			return new List<Id>{ cuentaPrueba, contactoPrueba };
		}
		User u = [SELECT ContactId, Contact.AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
		return new List<Id>{ u.Contact?.AccountId, u.ContactId };
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Pólizas donde la cuenta del usuario es titular o donde él es participante activo. En vista
	 * previa se usa la cuenta elegida por el administrador, sin contacto.
	 * @param cuentaVistaPrevia: Cuenta a simular; null para el usuario real
	 * @return Mapa póliza → rol del usuario
	 */
	@TestVisible
	static Map<Id, String> polizasDelUsuario(Id cuentaVistaPrevia) {
		List<Id> yo = identidad(cuentaVistaPrevia);
		Id cuenta = yo[0];
		Id contacto = yo[1];
		Map<Id, String> roles = new Map<Id, String>();
		if (cuenta == null && contacto == null) { return roles; }

		if (cuenta != null) {
			for (InsurancePolicy p : [SELECT Id FROM InsurancePolicy WHERE NameInsuredId = :cuenta LIMIT 2000]) {
				roles.put(p.Id, 'Titular');
			}
		}
		for (InsurancePolicyParticipant pp : [
			SELECT InsurancePolicyId, toLabel(Role)
			FROM InsurancePolicyParticipant
			WHERE IsActiveParticipant != false
				AND ((PrimaryParticipantAccountId != null AND PrimaryParticipantAccountId = :cuenta)
					OR (PrimaryParticipantContactId != null AND PrimaryParticipantContactId = :contacto))
			LIMIT 2000
		]) {
			if (!roles.containsKey(pp.InsurancePolicyId)) {
				roles.put(pp.InsurancePolicyId, String.isBlank(pp.Role) ? 'Asegurado' : pp.Role);
			}
		}
		return roles;
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Vista previa: solo usuarios internos con el permiso personalizado.
	 * @return true si el usuario puede simular una cuenta
	 */
	static Boolean tieneVistaPrevia() {
		if (permisoVistaPreviaPrueba != null) { return permisoVistaPreviaPrueba; }
		return UserInfo.getUserType() == 'Standard' && FeatureManagement.checkPermission(PERMISO_VISTA_PREVIA);
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Campos de la póliza que se muestran en el sitio.
	 * @return SOQL sin WHERE
	 */
	static String consulta() {
		return 'SELECT Id, Name, toLabel(Ramo__c), toLabel(PolicyType), Aseguradora__r.Name, toLabel(Status), IsActive, '
			+ 'EffectiveDate, ExpirationDate, PremiumAmount, Moneda__c, toLabel(PremiumFrequency), PaymentDueDate, '
			+ 'PastDueAmount, CurrentDueAmount, insuredAssetDescription__c, PolicyDescription, NameInsured.Name '
			+ 'FROM InsurancePolicy';
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Convierte la póliza al formato del componente.
	 * @param p: Póliza consultada
	 * @param rol: Rol del usuario en la póliza
	 * @return Poliza
	 */
	static Poliza convertir(InsurancePolicy p, String rol) {
		Poliza o = new Poliza();
		o.id = p.Id;
		o.numero = p.Name;
		o.ramo = p.Ramo__c;
		o.tipo = p.PolicyType;
		o.aseguradora = p.Aseguradora__r?.Name;
		o.estado = p.Status;
		o.inicioVigencia = p.EffectiveDate == null ? null : p.EffectiveDate.date();
		o.finVigencia = p.ExpirationDate == null ? null : p.ExpirationDate.date();
		o.vigente = p.IsActive == true && (o.finVigencia == null || o.finVigencia >= Date.today());
		o.prima = p.PremiumAmount;
		o.moneda = String.isBlank(p.Moneda__c) ? 'MXN' : p.Moneda__c;
		o.formaPago = p.PremiumFrequency;
		o.proximoPago = p.PaymentDueDate == null ? null : p.PaymentDueDate.date();
		o.montoVencido = p.PastDueAmount;
		o.montoPorPagar = p.CurrentDueAmount;
		o.bienAsegurado = p.insuredAssetDescription__c;
		o.descripcion = p.PolicyDescription;
		o.titular = p.NameInsured?.Name;
		o.miRol = rol;
		return o;
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Error para el cliente del sitio; el detalle técnico queda en el log, no en pantalla.
	 * @param e: Excepción original
	 * @return AuraHandledException con mensaje genérico
	 */
	static AuraHandledException error(Exception e) {
		System.debug(LoggingLevel.ERROR, 'PortalPolizasController: ' + e.getMessage() + ' | ' + e.getStackTraceString());
		String msg = 'No se pudieron cargar tus pólizas. Intenta de nuevo más tarde.';
		AuraHandledException a = new AuraHandledException(msg);
		a.setMessage(msg);
		return a;
	}
}
