/**
 * @creation date: 31/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Altas, bajas y cambios de vehículos de una flotilla (colectiva de Automóviles). Mismas reglas que
 *               MovimientosColectivoController para personas, en dos contextos:
 *               - Póliza (endoso durante la vigencia): los vehículos son los incisos de la póliza (Inciso_Flotilla__c con
 *                 Poliza__c). La baja no borra: deja el inciso con su fecha y motivo de baja y apaga su bien de póliza
 *                 (InsurancePolicyAsset) con la fecha de baja como fin de vigencia. El alta crea el vehículo del cliente,
 *                 el bien de póliza y el inciso (PolicyController.guardarVehiculosDesdePdf) con su fecha de alta.
 *               - Oportunidad de renovación: los vehículos son el censo de vehículos de la oportunidad (que se puede llenar
 *                 con los vehículos vigentes de la póliza anterior). La baja quita el vehículo del censo de la renovación.
 *               Cada movimiento queda en Movimiento_Poliza__c. También compara el archivo de la aseguradora (leído por
 *               c-censo-vehiculos en modo lector) contra los vehículos actuales, por serie (o placas si no trae serie).
 */
public with sharing class MovimientosFlotillaController {

	private static final String ALTA = 'alta';
	private static final String BAJA = 'baja';
	private static final String CAMBIO = 'cambio';
	private static final String CONTEXTO_ENDOSO = 'Endoso';
	private static final String CONTEXTO_RENOVACION = 'Renovacion';
	private static final Integer MAX_VEHICULOS = 3000;

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Movimiento que envía el LWC.
	 */
	public class Movimiento {
		// alta | baja | cambio
		public String tipo;
		// Inciso (póliza o censo) para baja y cambio.
		public String id;
		// Datos del vehículo (alta) o datos nuevos (cambio; solo se aplican los que vienen llenos).
		public FlotillaController.IncisoEntrada datos;
		// Fecha en que surte efecto (YYYY-MM-DD).
		public String fecha;
		// Motivo de baja (valor del picklist Motivo_Baja_Vehiculo).
		public String motivo;
		public String endoso;
		public String comentario;
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Ramo de autos (flotilla).
	 * @param ramo: Ramo__c de la póliza u oportunidad.
	 * @return true si es Automóviles.
	 */
	public static Boolean esFlotilla(String ramo) {
		return CensoColectivoController.llave(ramo).startsWith('auto');
	}

	// ============================================================
	// Consulta
	// ============================================================

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Datos para el LWC: vehículos (vigentes y dados de baja), motivos de baja, historial y, en una
	 *               oportunidad, la póliza anterior que se renueva.
	 * @param recordId: póliza (InsurancePolicy) u oportunidad de flotilla.
	 * @return mapa con contexto, aplica, vehiculos, motivos, movimientos y datos de la póliza.
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> getDatos(Id recordId) {
		try {
			Map<String, Object> res = new Map<String, Object>{ 'motivos' => motivos() };
			if (MovimientosColectivoController.esPoliza(recordId)) {
				InsurancePolicy pol = poliza(recordId);
				res.put('contexto', 'poliza');
				res.put('aplica', esFlotilla(pol.Ramo__c));
				res.put('nombre', pol.Name);
				res.put('inicio', pol.EffectiveDate == null ? null : pol.EffectiveDate.date());
				res.put('fin', pol.ExpirationDate == null ? null : pol.ExpirationDate.date());
				res.put('vehiculos', vehiculos(incisosPoliza(recordId, false, null)));
			} else {
				Opportunity opp = MovimientosColectivoController.oportunidad(recordId);
				InsurancePolicy anterior = MovimientosColectivoController.polizaAnteriorDe(opp);
				res.put('contexto', 'oportunidad');
				res.put('aplica', esFlotilla(opp.Ramo__c));
				res.put('nombre', opp.Name);
				res.put('polizaAnteriorId', anterior == null ? null : anterior.Id);
				res.put('polizaAnteriorNombre', anterior == null ? null : anterior.Name);
				res.put('polizaAnteriorFin', anterior == null || anterior.ExpirationDate == null ? null : anterior.ExpirationDate.date());
				res.put('vehiculosAnterior', anterior == null ? 0
					: [SELECT COUNT() FROM Inciso_Flotilla__c WHERE Poliza__c = :anterior.Id AND Fecha_Baja__c = null]);
				res.put('vehiculos', vehiculos(incisosCenso(recordId, null)));
			}
			res.put('movimientos', MovimientosColectivoController.historial(recordId));
			return res;
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			throw CensoColectivoController.error('No se pudieron leer los vehículos: ' + e.getMessage());
		}
	}

	// ============================================================
	// Movimientos
	// ============================================================

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Aplica altas, bajas y cambios de vehículos. Todo o nada. Orden: bajas, cambios y altas.
	 * @param recordId: póliza (endoso) u oportunidad (renovación).
	 * @param movimientosJson: lista de Movimiento en JSON.
	 * @return número de altas, bajas y cambios aplicados.
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> aplicar(Id recordId, String movimientosJson) {
		List<Movimiento> movs;
		try {
			movs = (List<Movimiento>) JSON.deserialize(String.isBlank(movimientosJson) ? '[]' : movimientosJson, List<Movimiento>.class);
		} catch (Exception e) {
			throw CensoColectivoController.error('Los movimientos no tienen un formato válido: ' + e.getMessage());
		}
		if (movs.isEmpty()) { throw CensoColectivoController.error('No hay movimientos para aplicar.'); }
		validar(movs);
		Savepoint sp = Database.setSavepoint();
		try {
			return MovimientosColectivoController.esPoliza(recordId) ? aplicarPoliza(recordId, movs) : aplicarOportunidad(recordId, movs);
		} catch (AuraHandledException e) {
			Database.rollback(sp);
			throw e;
		} catch (Exception e) {
			Database.rollback(sp);
			throw CensoColectivoController.error('No se aplicaron los movimientos: ' + MovimientosColectivoController.mensaje(e));
		}
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Compara el archivo de la aseguradora (ya leído y normalizado por c-censo-vehiculos) contra los
	 *               vehículos vigentes. Reconoce el vehículo por serie o, si el renglón no trae serie, por placas.
	 * @param recordId: póliza u oportunidad.
	 * @param incisosJson: lista de FlotillaController.IncisoEntrada.
	 * @param censoCompleto: true si el archivo es el censo completo (los que no vienen se proponen como baja).
	 * @return altas (ref = posición en el archivo), bajas, cambios (con diferencias) y sinCambios.
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> compararArchivo(Id recordId, String incisosJson, Boolean censoCompleto) {
		List<FlotillaController.IncisoEntrada> entrada;
		try {
			entrada = (List<FlotillaController.IncisoEntrada>) JSON.deserialize(
				String.isBlank(incisosJson) ? '[]' : incisosJson, List<FlotillaController.IncisoEntrada>.class);
		} catch (Exception e) {
			throw CensoColectivoController.error('El archivo no tiene un formato válido: ' + e.getMessage());
		}
		try {
			List<Inciso_Flotilla__c> actuales = MovimientosColectivoController.esPoliza(recordId)
				? incisosPoliza(recordId, true, null) : incisosCenso(recordId, null);
			Map<String, Inciso_Flotilla__c> porSerie = new Map<String, Inciso_Flotilla__c>();
			Map<String, Inciso_Flotilla__c> porPlacas = new Map<String, Inciso_Flotilla__c>();
			for (Inciso_Flotilla__c i : actuales) {
				if (String.isNotBlank(i.Serie__c)) { porSerie.put(serie(i.Serie__c), i); }
				if (String.isNotBlank(i.Placas__c)) { porPlacas.put(placas(i.Placas__c), i); }
			}
			Set<Id> usados = new Set<Id>();
			List<Object> altas = new List<Object>();
			List<Object> cambios = new List<Object>();
			Integer sinCambios = 0;
			for (Integer ref = 0; ref < entrada.size(); ref++) {
				FlotillaController.IncisoEntrada e = entrada[ref];
				String s = serie(e.serie);
				Inciso_Flotilla__c actual = String.isNotBlank(s) ? porSerie.get(s)
					: (String.isNotBlank(e.placas) ? porPlacas.get(placas(e.placas)) : null);
				if (actual != null && usados.contains(actual.Id)) { actual = null; }
				// El tipo lo deduce el lector y la descripción la redacta cada fuente a su modo: no se toman como cambio.
				if (actual != null) {
					e.tipoVehiculo = null;
					e.descripcion = null;
				}
				if (actual == null) {
					altas.add(new Map<String, Object>{
						'ref' => ref, 'inciso' => e.inciso, 'serie' => s, 'descripcion' => e.descripcion, 'modelo' => e.modelo,
						'placas' => e.placas, 'valor' => e.valor, 'prima' => e.prima, 'datos' => MovimientosColectivoController.comoMapa(e)
					});
					continue;
				}
				usados.add(actual.Id);
				List<Object> difs = diferencias(actual, e);
				if (difs.isEmpty()) { sinCambios++; continue; }
				cambios.add(new Map<String, Object>{
					'id' => actual.Id, 'inciso' => actual.Numero_Inciso__c, 'serie' => actual.Serie__c, 'descripcion' => actual.Descripcion__c,
					'diferencias' => difs, 'datos' => MovimientosColectivoController.comoMapa(e)
				});
			}
			List<Object> bajas = new List<Object>();
			if (censoCompleto == true) {
				for (Inciso_Flotilla__c i : actuales) {
					if (usados.contains(i.Id)) { continue; }
					bajas.add(new Map<String, Object>{
						'id' => i.Id, 'inciso' => i.Numero_Inciso__c, 'serie' => i.Serie__c, 'descripcion' => i.Descripcion__c, 'placas' => i.Placas__c
					});
				}
			}
			return new Map<String, Object>{ 'altas' => altas, 'bajas' => bajas, 'cambios' => cambios, 'sinCambios' => sinCambios };
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			throw CensoColectivoController.error('No se pudo comparar el archivo: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Renovación armada por el ejecutivo: llena el censo de vehículos de la oportunidad con los vehículos
	 *               vigentes de la póliza anterior (con sus coberturas y primas).
	 * @param opportunityId: oportunidad de renovación.
	 * @param reemplazar: true para reemplazar el censo actual.
	 * @return vehículos del censo después de copiar.
	 */
	@AuraEnabled(cacheable=false)
	public static Integer traerDePoliza(Id opportunityId, Boolean reemplazar) {
		Opportunity opp = MovimientosColectivoController.oportunidad(opportunityId);
		InsurancePolicy anterior = MovimientosColectivoController.polizaAnteriorDe(opp);
		if (anterior == null) { throw CensoColectivoController.error('El cliente no tiene una póliza anterior de este ramo.'); }
		List<FlotillaController.IncisoEntrada> l = new List<FlotillaController.IncisoEntrada>();
		for (Inciso_Flotilla__c i : incisosPoliza(anterior.Id, true, null)) {
			FlotillaController.IncisoEntrada e = new FlotillaController.IncisoEntrada();
			e.inciso = i.Numero_Inciso__c == null ? null : i.Numero_Inciso__c.intValue();
			e.serie = i.Serie__c;
			e.claveVehicular = i.Clave_Vehicular__c;
			e.descripcion = i.Descripcion__c;
			e.modelo = i.Modelo__c == null ? null : i.Modelo__c.intValue();
			e.placas = i.Placas__c;
			e.uso = i.Uso__c;
			e.tipoVehiculo = i.Tipo_Vehiculo__c;
			e.paquete = i.Paquete__c;
			e.tipoValor = i.Tipo_Valor__c;
			e.valor = i.Valor__c;
			e.dedDM = i.Deducible_DM__c;
			e.dedRT = i.Deducible_RT__c;
			e.rc = i.Responsabilidad_Civil__c;
			e.gm = i.Gastos_Medicos__c;
			e.muerte = i.Muerte_Conductor__c;
			e.prima = i.Prima__c;
			e.primaNeta = i.Prima_Neta__c;
			l.add(e);
		}
		if (l.isEmpty()) { throw CensoColectivoController.error('La póliza ' + anterior.Name + ' no tiene vehículos vigentes.'); }
		return CensoVehiculosController.guardarCensoVehiculos(opportunityId, JSON.serialize(l), reemplazar == true);
	}

	// ============================================================
	// Póliza (endoso)
	// ============================================================

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Endoso: bajas (inciso con fecha y motivo, bien de póliza inactivo), cambios y altas (vehículo, bien
	 *               de póliza e inciso nuevos; si la serie ya estuvo en la póliza y se dio de baja, se reactiva).
	 * @param policyId: póliza.
	 * @param movs: movimientos validados.
	 * @return altas, bajas y cambios.
	 */
	private static Map<String, Object> aplicarPoliza(Id policyId, List<Movimiento> movs) {
		InsurancePolicy pol = poliza(policyId);
		Date inicio = pol.EffectiveDate == null ? null : pol.EffectiveDate.date();
		Date fin = pol.ExpirationDate == null ? null : pol.ExpirationDate.date();
		Set<Id> ids = new Set<Id>();
		for (Movimiento m : movs) { if (m.tipo != ALTA) { ids.add(Id.valueOf(m.id)); } }
		Map<Id, Inciso_Flotilla__c> incisos = new Map<Id, Inciso_Flotilla__c>(incisosPoliza(policyId, false, ids));
		for (Id i : ids) {
			if (!incisos.containsKey(i)) { throw CensoColectivoController.error('Uno de los vehículos no pertenece a esta póliza.'); }
		}
		Map<Id, InsurancePolicyAsset> bienes = new Map<Id, InsurancePolicyAsset>();
		for (InsurancePolicyAsset a : [
			SELECT Id, CustomerPropertyId, IsActive, EffectiveFromDate, EffectiveToDate, StandardPremiumAmount
			FROM InsurancePolicyAsset WHERE InsurancePolicyId = :policyId AND CustomerPropertyId != null
		]) { bienes.put(a.CustomerPropertyId, a); }

		List<Movimiento_Poliza__c> registro = new List<Movimiento_Poliza__c>();
		Map<Id, Inciso_Flotilla__c> actualizar = new Map<Id, Inciso_Flotilla__c>();
		Map<Id, InsurancePolicyAsset> actualizarBienes = new Map<Id, InsurancePolicyAsset>();
		List<CustomerProperty> vehiculos = new List<CustomerProperty>();
		Integer bajas = 0;
		Integer cambios = 0;
		Integer altas = 0;

		for (Movimiento m : movs) {
			Date f = CensoColectivoController.fecha(m.fecha);
			if (m.tipo == BAJA) {
				Inciso_Flotilla__c inc = incisos.get(Id.valueOf(m.id));
				if (inc.Fecha_Baja__c != null) { throw CensoColectivoController.error(nombre(inc) + ' ya está dado de baja.'); }
				if (inicio != null && f < inicio) {
					throw CensoColectivoController.error(nombre(inc) + ': la fecha de baja es anterior al inicio de la póliza.');
				}
				inc.Fecha_Baja__c = f;
				inc.Motivo_Baja__c = m.motivo;
				actualizar.put(inc.Id, inc);
				InsurancePolicyAsset a = bienes.get(inc.Vehiculo__c);
				if (a != null) {
					a.IsActive = false;
					a.EffectiveToDate = f;
					actualizarBienes.put(a.Id, a);
				}
				registro.add(registro(m, BAJA, CONTEXTO_ENDOSO, policyId, null, inc));
				bajas++;
			} else if (m.tipo == CAMBIO) {
				Inciso_Flotilla__c inc = incisos.get(Id.valueOf(m.id));
				if (inc.Fecha_Baja__c != null) { throw CensoColectivoController.error(nombre(inc) + ' está dado de baja: no se puede cambiar.'); }
				String placasAntes = inc.Placas__c;
				List<String> detalle = cambiarInciso(inc, m.datos);
				if (detalle.isEmpty()) { continue; }
				actualizar.put(inc.Id, inc);
				InsurancePolicyAsset a = bienes.get(inc.Vehiculo__c);
				if (a != null && m.datos.prima != null && a.StandardPremiumAmount != m.datos.prima) {
					a.StandardPremiumAmount = m.datos.prima;
					actualizarBienes.put(a.Id, a);
				}
				if (inc.Vehiculo__c != null && inc.Placas__c != placasAntes) {
					vehiculos.add(new CustomerProperty(Id = inc.Vehiculo__c, RegistrationNumber = inc.Placas__c));
				}
				Movimiento_Poliza__c r = registro(m, CAMBIO, CONTEXTO_ENDOSO, policyId, null, inc);
				r.Detalle__c = String.join(detalle, '\n');
				registro.add(r);
				cambios++;
			}
		}

		// Altas: la serie identifica al vehículo. Si ya estuvo en la póliza y se dio de baja, se reactiva.
		Map<String, Inciso_Flotilla__c> porSerie = new Map<String, Inciso_Flotilla__c>();
		Decimal ultimo = 0;
		for (Inciso_Flotilla__c i : incisosPoliza(policyId, false, null)) {
			if (String.isNotBlank(i.Serie__c)) { porSerie.put(serie(i.Serie__c), i); }
			if (i.Numero_Inciso__c != null && i.Numero_Inciso__c > ultimo) { ultimo = i.Numero_Inciso__c; }
		}
		Map<String, Movimiento> nuevos = new Map<String, Movimiento>();
		List<Object> datosNuevos = new List<Object>();
		for (Movimiento m : movs) {
			if (m.tipo != ALTA) { continue; }
			String s = serie(m.datos.serie);
			if (String.isBlank(s)) { throw CensoColectivoController.error('Indica la serie (VIN) de cada vehículo que se da de alta.'); }
			if (nuevos.containsKey(s)) { throw CensoColectivoController.error('La serie ' + s + ' viene repetida en las altas.'); }
			Date f = CensoColectivoController.fecha(m.fecha);
			if ((inicio != null && f < inicio) || (fin != null && f > fin)) {
				throw CensoColectivoController.error('Serie ' + s + ': la fecha de alta está fuera de la vigencia de la póliza.');
			}
			Inciso_Flotilla__c ya = porSerie.get(s);
			if (ya != null && ya.Fecha_Baja__c == null) {
				throw CensoColectivoController.error('La serie ' + s + ' ya está vigente en la póliza (' + nombre(ya) + ').');
			}
			if (ya != null) {
				// Reactivación de un vehículo que se había dado de baja.
				if (actualizar.containsKey(ya.Id)) { ya = actualizar.get(ya.Id); }
				cambiarInciso(ya, m.datos);
				ya.Fecha_Baja__c = null;
				ya.Motivo_Baja__c = null;
				ya.Fecha_Alta__c = f;
				actualizar.put(ya.Id, ya);
				InsurancePolicyAsset a = bienes.get(ya.Vehiculo__c);
				if (a != null) {
					a.IsActive = true;
					a.EffectiveFromDate = f;
					a.EffectiveToDate = fin;
					if (m.datos.prima != null) { a.StandardPremiumAmount = m.datos.prima; }
					actualizarBienes.put(a.Id, a);
				}
				Movimiento_Poliza__c r = registro(m, ALTA, CONTEXTO_ENDOSO, policyId, null, ya);
				r.Detalle__c = ('Reingreso del vehículo\n' + detalleAlta(m.datos)).trim();
				registro.add(r);
				altas++;
				continue;
			}
			if (m.datos.inciso == null) { ultimo++; m.datos.inciso = ultimo.intValue(); }
			nuevos.put(s, m);
			datosNuevos.add(vehiculoPdf(m.datos, s));
		}
		if (!actualizar.isEmpty()) { update actualizar.values(); }
		if (!actualizarBienes.isEmpty()) { update actualizarBienes.values(); }
		if (!vehiculos.isEmpty()) { update vehiculos; }

		if (!nuevos.isEmpty()) {
			if (pol.NameInsuredId == null) { throw CensoColectivoController.error('La póliza no tiene asegurado (cliente) para registrar los vehículos.'); }
			PolicyController.guardarVehiculosDesdePdf(policyId, pol.NameInsuredId, null, datosNuevos);
			Set<String> series = nuevos.keySet();
			List<Inciso_Flotilla__c> creados = [
				SELECT Id, Name, Numero_Inciso__c, Serie__c, Descripcion__c, Vehiculo__c FROM Inciso_Flotilla__c
				WHERE Poliza__c = :policyId AND Serie__c IN :series
			];
			Map<Id, Date> fechaPorVehiculo = new Map<Id, Date>();
			for (Inciso_Flotilla__c i : creados) {
				Movimiento m = nuevos.get(serie(i.Serie__c));
				i.Fecha_Alta__c = CensoColectivoController.fecha(m.fecha);
				// Lo que guardarVehiculosDesdePdf no lleva (viene del PDF de la póliza, no de un censo).
				if (m.datos.valor != null) { i.Valor__c = m.datos.valor; }
				if (String.isNotBlank(m.datos.paquete)) { i.Paquete__c = m.datos.paquete.trim().left(60); }
				if (i.Vehiculo__c != null) { fechaPorVehiculo.put(i.Vehiculo__c, i.Fecha_Alta__c); }
				Movimiento_Poliza__c r = registro(m, ALTA, CONTEXTO_ENDOSO, policyId, null, i);
				r.Detalle__c = detalleAlta(m.datos);
				registro.add(r);
				altas++;
			}
			update creados;
			List<InsurancePolicyAsset> desde = new List<InsurancePolicyAsset>();
			for (InsurancePolicyAsset a : [
				SELECT Id, CustomerPropertyId FROM InsurancePolicyAsset
				WHERE InsurancePolicyId = :policyId AND CustomerPropertyId IN :fechaPorVehiculo.keySet()
			]) { desde.add(new InsurancePolicyAsset(Id = a.Id, EffectiveFromDate = fechaPorVehiculo.get(a.CustomerPropertyId))); }
			if (!desde.isEmpty()) { update desde; }
		}
		if (!registro.isEmpty()) { insert registro; }
		return new Map<String, Object>{ 'altas' => altas, 'bajas' => bajas, 'cambios' => cambios };
	}

	// ============================================================
	// Oportunidad (renovación)
	// ============================================================

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Renovación: la baja quita el vehículo del censo (queda registrada contra la póliza anterior y su
	 *               inciso), el cambio actualiza el censo y el alta lo agrega.
	 * @param oppId: oportunidad.
	 * @param movs: movimientos validados.
	 * @return altas, bajas y cambios.
	 */
	private static Map<String, Object> aplicarOportunidad(Id oppId, List<Movimiento> movs) {
		Opportunity opp = MovimientosColectivoController.oportunidad(oppId);
		InsurancePolicy anterior = MovimientosColectivoController.polizaAnteriorDe(opp);
		Id polizaId = anterior == null ? null : anterior.Id;
		Map<String, Id> anteriores = new Map<String, Id>();
		if (anterior != null) {
			for (Inciso_Flotilla__c i : [SELECT Id, Serie__c FROM Inciso_Flotilla__c WHERE Poliza__c = :anterior.Id AND Serie__c != null]) {
				anteriores.put(serie(i.Serie__c), i.Id);
			}
		}
		Set<Id> ids = new Set<Id>();
		for (Movimiento m : movs) { if (m.tipo != ALTA) { ids.add(Id.valueOf(m.id)); } }
		Map<Id, Inciso_Flotilla__c> incisos = new Map<Id, Inciso_Flotilla__c>(incisosCenso(oppId, ids));
		for (Id i : ids) {
			if (!incisos.containsKey(i)) { throw CensoColectivoController.error('Uno de los vehículos ya no está en el censo.'); }
		}
		List<Movimiento_Poliza__c> registro = new List<Movimiento_Poliza__c>();
		List<Inciso_Flotilla__c> borrar = new List<Inciso_Flotilla__c>();
		List<Inciso_Flotilla__c> actualizar = new List<Inciso_Flotilla__c>();
		Integer cambios = 0;
		for (Movimiento m : movs) {
			if (m.tipo == ALTA) { continue; }
			Inciso_Flotilla__c inc = incisos.get(Id.valueOf(m.id));
			if (m.tipo == BAJA) {
				borrar.add(inc);
				// El movimiento apunta al inciso de la póliza anterior (el del censo se borra).
				Movimiento_Poliza__c r = registro(m, BAJA, CONTEXTO_RENOVACION, polizaId, oppId, inc);
				r.Inciso__c = String.isBlank(inc.Serie__c) ? null : anteriores.get(serie(inc.Serie__c));
				registro.add(r);
				continue;
			}
			List<String> detalle = cambiarInciso(inc, m.datos);
			if (detalle.isEmpty()) { continue; }
			actualizar.add(inc);
			Movimiento_Poliza__c r = registro(m, CAMBIO, CONTEXTO_RENOVACION, polizaId, oppId, inc);
			r.Detalle__c = String.join(detalle, '\n');
			registro.add(r);
			cambios++;
		}
		if (!borrar.isEmpty()) { delete borrar; }
		if (!actualizar.isEmpty()) { update actualizar; }

		// Altas al censo (sin serie repetida).
		Set<String> series = new Set<String>();
		Decimal ultimo = 0;
		for (Inciso_Flotilla__c i : incisosCenso(oppId, null)) {
			if (String.isNotBlank(i.Serie__c)) { series.add(serie(i.Serie__c)); }
			if (i.Numero_Inciso__c != null && i.Numero_Inciso__c > ultimo) { ultimo = i.Numero_Inciso__c; }
		}
		List<Inciso_Flotilla__c> nuevos = new List<Inciso_Flotilla__c>();
		List<Movimiento> movNuevos = new List<Movimiento>();
		for (Movimiento m : movs) {
			if (m.tipo != ALTA) { continue; }
			String s = serie(m.datos.serie);
			if (String.isNotBlank(s) && series.contains(s)) {
				throw CensoColectivoController.error('La serie ' + s + ' ya está en el censo de la renovación.');
			}
			if (String.isNotBlank(s)) { series.add(s); }
			if (m.datos.inciso == null) { ultimo++; m.datos.inciso = ultimo.intValue(); }
			Inciso_Flotilla__c inc = new Inciso_Flotilla__c(Oportunidad__c = oppId);
			CensoVehiculosController.llenar(inc, m.datos, String.isBlank(s) ? null : s);
			inc.Fecha_Alta__c = CensoColectivoController.fecha(m.fecha);
			nuevos.add(inc);
			movNuevos.add(m);
		}
		if (!nuevos.isEmpty()) { insert nuevos; }
		for (Integer i = 0; i < nuevos.size(); i++) {
			Movimiento_Poliza__c r = registro(movNuevos[i], ALTA, CONTEXTO_RENOVACION, polizaId, oppId, nuevos[i]);
			r.Detalle__c = detalleAlta(movNuevos[i].datos);
			registro.add(r);
		}
		if (!registro.isEmpty()) { insert registro; }
		return new Map<String, Object>{ 'altas' => nuevos.size(), 'bajas' => borrar.size(), 'cambios' => cambios };
	}

	// ============================================================
	// Helpers
	// ============================================================

	private static final String CAMPOS_INCISO = 'SELECT Id, Name, Numero_Inciso__c, Serie__c, Placas__c, Descripcion__c, Modelo__c, '
		+ 'Tipo_Vehiculo__c, Uso__c, Paquete__c, Tipo_Valor__c, Clave_Vehicular__c, Valor__c, Prima__c, Prima_Neta__c, '
		+ 'Deducible_DM__c, Deducible_RT__c, Responsabilidad_Civil__c, Gastos_Medicos__c, Muerte_Conductor__c, Vehiculo__c, '
		+ 'Fecha_Alta__c, Fecha_Baja__c, Motivo_Baja__c FROM Inciso_Flotilla__c ';

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Incisos de la póliza.
	 * @param policyId: póliza.
	 * @param soloVigentes: true para excluir los dados de baja.
	 * @param ids: solo estos incisos (null = todos).
	 * @return incisos ordenados por número de inciso.
	 */
	private static List<Inciso_Flotilla__c> incisosPoliza(Id policyId, Boolean soloVigentes, Set<Id> ids) {
		return Database.query(CAMPOS_INCISO + 'WHERE Poliza__c = :policyId' + (soloVigentes ? ' AND Fecha_Baja__c = null' : '')
			+ (ids == null ? '' : ' AND Id IN :ids') + ' ORDER BY Numero_Inciso__c ASC NULLS LAST, Name ASC LIMIT ' + MAX_VEHICULOS);
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Censo de vehículos de la oportunidad (sin cotización ni póliza).
	 * @param oppId: oportunidad.
	 * @param ids: solo estos incisos (null = todos).
	 * @return incisos ordenados por número de inciso.
	 */
	private static List<Inciso_Flotilla__c> incisosCenso(Id oppId, Set<Id> ids) {
		return Database.query(CAMPOS_INCISO + 'WHERE Oportunidad__c = :oppId AND Cotizacion__c = null AND Poliza__c = null'
			+ (ids == null ? '' : ' AND Id IN :ids') + ' ORDER BY Numero_Inciso__c ASC NULLS LAST, Name ASC LIMIT ' + MAX_VEHICULOS);
	}

	private static List<Object> vehiculos(List<Inciso_Flotilla__c> incisos) {
		Map<String, String> motivos = MovimientosColectivoController.etiquetas(Inciso_Flotilla__c.Motivo_Baja__c.getDescribe());
		List<Object> l = new List<Object>();
		for (Inciso_Flotilla__c i : incisos) {
			l.add(new Map<String, Object>{
				'id' => i.Id, 'nombre' => i.Name, 'inciso' => i.Numero_Inciso__c, 'serie' => i.Serie__c, 'placas' => i.Placas__c,
				'descripcion' => i.Descripcion__c, 'modelo' => i.Modelo__c, 'tipoVehiculo' => i.Tipo_Vehiculo__c, 'uso' => i.Uso__c,
				'paquete' => i.Paquete__c, 'valor' => i.Valor__c, 'prima' => i.Prima__c, 'vehiculoId' => i.Vehiculo__c,
				'activo' => i.Fecha_Baja__c == null, 'fechaAlta' => i.Fecha_Alta__c, 'fechaBaja' => i.Fecha_Baja__c,
				'motivoBaja' => i.Motivo_Baja__c == null ? null : motivos.get(i.Motivo_Baja__c)
			});
		}
		return l;
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Aplica al inciso los datos que vienen llenos y son distintos.
	 * @param inc: inciso.
	 * @param d: datos nuevos.
	 * @return detalle «Campo: antes → después» de lo que cambió.
	 */
	private static List<String> cambiarInciso(Inciso_Flotilla__c inc, FlotillaController.IncisoEntrada d) {
		List<String> l = new List<String>();
		if (d == null) { return l; }
		if (d.inciso != null && d.inciso != inc.Numero_Inciso__c) {
			l.add('Inciso: ' + MovimientosColectivoController.texto(inc.Numero_Inciso__c == null ? null : String.valueOf(inc.Numero_Inciso__c.intValue())) + ' → ' + d.inciso);
			inc.Numero_Inciso__c = d.inciso;
		}
		if (String.isNotBlank(d.serie) && serie(d.serie) != serie(inc.Serie__c)) {
			l.add('Serie: ' + MovimientosColectivoController.texto(inc.Serie__c) + ' → ' + serie(d.serie));
			inc.Serie__c = serie(d.serie).left(30);
		}
		if (String.isNotBlank(d.placas) && placas(d.placas) != placas(inc.Placas__c)) {
			l.add('Placas: ' + MovimientosColectivoController.texto(inc.Placas__c) + ' → ' + placas(d.placas));
			inc.Placas__c = placas(d.placas).left(20);
		}
		if (String.isNotBlank(d.descripcion) && CensoColectivoController.llave(d.descripcion) != CensoColectivoController.llave(inc.Descripcion__c)) {
			l.add('Descripción: ' + MovimientosColectivoController.texto(inc.Descripcion__c) + ' → ' + d.descripcion.normalizeSpace());
			inc.Descripcion__c = d.descripcion.normalizeSpace().left(255);
		}
		if (d.modelo != null && d.modelo != inc.Modelo__c) {
			l.add('Modelo: ' + MovimientosColectivoController.texto(inc.Modelo__c == null ? null : String.valueOf(inc.Modelo__c.intValue())) + ' → ' + d.modelo);
			inc.Modelo__c = d.modelo;
		}
		l.addAll(cambioTexto(inc, 'Uso__c', 'Uso', d.uso, 60));
		l.addAll(cambioTexto(inc, 'Tipo_Vehiculo__c', 'Tipo de vehículo', d.tipoVehiculo, 80));
		l.addAll(cambioTexto(inc, 'Paquete__c', 'Paquete', d.paquete, 60));
		l.addAll(cambioMonto(inc, 'Valor__c', 'Valor', d.valor));
		l.addAll(cambioMonto(inc, 'Prima__c', 'Prima', d.prima));
		l.addAll(cambioMonto(inc, 'Prima_Neta__c', 'Prima neta', d.primaNeta));
		return l;
	}

	private static List<String> cambioTexto(Inciso_Flotilla__c inc, String campo, String etiqueta, String v, Integer largo) {
		String antes = (String) inc.get(campo);
		if (String.isBlank(v) || CensoColectivoController.llave(v) == CensoColectivoController.llave(antes)) { return new List<String>(); }
		inc.put(campo, v.normalizeSpace().left(largo));
		return new List<String>{ etiqueta + ': ' + MovimientosColectivoController.texto(antes) + ' → ' + v.normalizeSpace() };
	}

	private static List<String> cambioMonto(Inciso_Flotilla__c inc, String campo, String etiqueta, Decimal v) {
		Decimal antes = (Decimal) inc.get(campo);
		if (v == null || v == antes) { return new List<String>(); }
		inc.put(campo, v);
		return new List<String>{ etiqueta + ': ' + MovimientosColectivoController.texto(antes) + ' → ' + MovimientosColectivoController.texto(v) };
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Diferencias entre el vehículo actual y el renglón del archivo (solo los campos que trae el archivo).
	 * @param inc: inciso actual.
	 * @param e: renglón del archivo.
	 * @return lista de {campo, antes, despues}.
	 */
	@TestVisible
	private static List<Object> diferencias(Inciso_Flotilla__c inc, FlotillaController.IncisoEntrada e) {
		// Se aplica sobre una copia para no tocar el inciso.
		List<Object> l = new List<Object>();
		for (String d : cambiarInciso(inc.clone(true, true), e)) {
			Integer dos = d.indexOf(': ');
			Integer flecha = d.lastIndexOf(' → ');
			l.add(MovimientosColectivoController.dif(d.substring(0, dos), d.substring(dos + 2, flecha), d.substring(flecha + 3)));
		}
		return l;
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Revisa que cada movimiento traiga lo necesario.
	 * @param movs: movimientos.
	 */
	private static void validar(List<Movimiento> movs) {
		for (Integer i = 0; i < movs.size(); i++) {
			Movimiento m = movs[i];
			if (m.tipo != ALTA && m.tipo != BAJA && m.tipo != CAMBIO) {
				throw CensoColectivoController.error('Movimiento ' + (i + 1) + ': tipo no válido.');
			}
			if (CensoColectivoController.fecha(m.fecha) == null) {
				throw CensoColectivoController.error('Movimiento ' + (i + 1) + ': falta la fecha del movimiento.');
			}
			if (m.tipo != ALTA && String.isBlank(m.id)) {
				throw CensoColectivoController.error('Movimiento ' + (i + 1) + ': falta el vehículo.');
			}
			if (m.tipo == BAJA && String.isBlank(m.motivo)) {
				throw CensoColectivoController.error('Indica el motivo de baja de cada vehículo.');
			}
			if (m.tipo != BAJA && m.datos == null) {
				throw CensoColectivoController.error('Movimiento ' + (i + 1) + ': faltan los datos del vehículo.');
			}
			if (m.tipo == ALTA && String.isBlank(m.datos.serie) && String.isBlank(m.datos.descripcion)) {
				throw CensoColectivoController.error('Movimiento ' + (i + 1) + ': el alta no tiene serie ni descripción.');
			}
		}
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Registro del movimiento de un vehículo.
	 * @return Movimiento_Poliza__c sin insertar.
	 */
	private static Movimiento_Poliza__c registro(Movimiento m, String tipo, String contexto, Id polizaId, Id oppId, Inciso_Flotilla__c inc) {
		Movimiento_Poliza__c r = new Movimiento_Poliza__c(Poliza__c = polizaId, Oportunidad__c = oppId, Inciso__c = inc.Id,
			Contexto__c = contexto, Asegurado__c = nombre(inc).left(255),
			Certificado__c = inc.Numero_Inciso__c == null ? null : 'Inciso ' + inc.Numero_Inciso__c.intValue(),
			Fecha_Movimiento__c = CensoColectivoController.fecha(m.fecha),
			Numero_Endoso__c = String.isBlank(m.endoso) ? null : m.endoso.trim().left(80),
			Comentario__c = String.isBlank(m.comentario) ? null : m.comentario.trim().left(255));
		r.Tipo__c = tipo == ALTA ? 'Alta' : (tipo == BAJA ? 'Baja' : 'Cambio');
		if (tipo == BAJA) { r.Motivo_Baja_Vehiculo__c = m.motivo; }
		return r;
	}

	private static String detalleAlta(FlotillaController.IncisoEntrada d) {
		List<String> l = new List<String>();
		if (String.isNotBlank(d.placas)) { l.add('Placas: ' + placas(d.placas)); }
		if (d.modelo != null) { l.add('Modelo: ' + d.modelo); }
		if (String.isNotBlank(d.uso)) { l.add('Uso: ' + d.uso); }
		if (String.isNotBlank(d.paquete)) { l.add('Paquete: ' + d.paquete); }
		if (d.valor != null) { l.add('Valor: ' + MovimientosColectivoController.texto(d.valor)); }
		if (d.prima != null) { l.add('Prima: ' + MovimientosColectivoController.texto(d.prima)); }
		return String.join(l, '\n');
	}

	// Vehículo en el formato que recibe PolicyController.guardarVehiculosDesdePdf.
	private static Map<String, Object> vehiculoPdf(FlotillaController.IncisoEntrada d, String s) {
		return new Map<String, Object>{
			'inciso' => d.inciso, 'serie' => s, 'descripcion' => d.descripcion, 'anio' => d.modelo, 'placas' => d.placas,
			'uso' => d.uso, 'tipoVehiculo' => d.tipoVehiculo, 'clave' => d.claveVehicular, 'tipoValor' => d.tipoValor,
			'deducibleDM' => d.dedDM, 'deducibleRT' => d.dedRT, 'responsabilidadCivil' => d.rc, 'gastosMedicos' => d.gm,
			'muerteConductor' => d.muerte, 'primaNeta' => d.primaNeta, 'primaTotal' => d.prima
		};
	}

	private static String nombre(Inciso_Flotilla__c i) {
		String n = String.isNotBlank(i.Descripcion__c) ? i.Descripcion__c : 'Vehículo';
		return n + (String.isNotBlank(i.Serie__c) ? ' · ' + i.Serie__c : '');
	}

	private static InsurancePolicy poliza(Id policyId) {
		return [
			SELECT Id, Name, NameInsuredId, EffectiveDate, ExpirationDate, Ramo__c FROM InsurancePolicy WHERE Id = :policyId LIMIT 1
		];
	}

	private static List<Object> motivos() {
		List<Object> l = new List<Object>();
		for (Schema.PicklistEntry pe : Inciso_Flotilla__c.Motivo_Baja__c.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { l.add(new Map<String, Object>{ 'label' => pe.getLabel(), 'value' => pe.getValue() }); }
		}
		return l;
	}

	private static String serie(String s) {
		return String.isBlank(s) ? null : s.deleteWhitespace().toUpperCase();
	}

	private static String placas(String s) {
		return String.isBlank(s) ? null : s.deleteWhitespace().toUpperCase();
	}
}
