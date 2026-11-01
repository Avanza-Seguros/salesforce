/**
 * @creation date: 01/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Altas, bajas y cambios de ubicaciones de una póliza colectiva de Daños / Empresarial. Mismas reglas que
 *               MovimientosFlotillaController para vehículos, en dos contextos:
 *               - Póliza (endoso durante la vigencia): cada ubicación es un bien de la póliza (InsurancePolicyAsset ligado
 *                 al CustomerProperty del domicilio). La baja no borra: deja el bien con su fecha y motivo de baja y lo
 *                 apaga con la fecha de baja como fin de vigencia. El alta crea el bien del cliente y el bien de póliza
 *                 (PolicyController.guardarUbicacionesDesdePdf); si el domicilio ya estuvo en la póliza, se reactiva.
 *               - Oportunidad de renovación: las ubicaciones son el listado de la oportunidad (Categoria_Colectiva__c sin
 *                 cotización, una por ubicación), que se llena con las vigentes de la póliza anterior. La baja quita la
 *                 ubicación del listado. Al emitir, si la cotización aceptada no trae ubicaciones, se usa este listado.
 *               Cada movimiento queda en Movimiento_Poliza__c.
 */
public with sharing class MovimientosUbicacionesController {

	private static final String ALTA = 'alta';
	private static final String BAJA = 'baja';
	private static final String CAMBIO = 'cambio';
	private static final String CONTEXTO_ENDOSO = 'Endoso';
	private static final String CONTEXTO_RENOVACION = 'Renovacion';
	private static final String CONCEPTO_GIRO = 'Giro';
	private static final Integer MAX_UBICACIONES = 1000;

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Datos de una ubicación (alta) o datos nuevos (cambio; solo se aplican los que vienen llenos).
	 */
	public class Ubicacion {
		public Integer inciso;
		public String nombre;
		public String direccion;
		public String giro;
		public Decimal sumaAsegurada;
		public Decimal prima;
	}

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Movimiento que envía el LWC.
	 */
	public class Movimiento {
		// alta | baja | cambio
		public String tipo;
		// Bien de la póliza (InsurancePolicyAsset) o renglón del listado de la oportunidad, para baja y cambio.
		public String id;
		public Ubicacion datos;
		// Fecha en que surte efecto (YYYY-MM-DD).
		public String fecha;
		// Motivo de baja (valor del picklist Motivo_Baja_Ubicacion).
		public String motivo;
		public String endoso;
		public String comentario;
	}

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Ramo de ubicaciones (Daños / Empresarial).
	 * @param ramo: Ramo__c de la póliza u oportunidad.
	 * @return true si asegura ubicaciones.
	 */
	public static Boolean esUbicaciones(String ramo) {
		String k = CensoColectivoController.llave(ramo);
		return k.startsWith('dano') || k.startsWith('empresarial');
	}

	// ============================================================
	// Consulta
	// ============================================================

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Datos para el LWC: ubicaciones (vigentes y dadas de baja), motivos de baja, historial y, en una
	 *               oportunidad, la póliza anterior que se renueva.
	 * @param recordId: póliza (InsurancePolicy) u oportunidad.
	 * @return mapa con contexto, aplica, ubicaciones, motivos, movimientos y datos de la póliza.
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> getDatos(Id recordId) {
		try {
			Map<String, Object> res = new Map<String, Object>{ 'motivos' => motivos() };
			if (MovimientosColectivoController.esPoliza(recordId)) {
				InsurancePolicy pol = poliza(recordId);
				res.put('contexto', 'poliza');
				res.put('aplica', esUbicaciones(pol.Ramo__c));
				res.put('nombre', pol.Name);
				res.put('inicio', pol.EffectiveDate == null ? null : pol.EffectiveDate.date());
				res.put('fin', pol.ExpirationDate == null ? null : pol.ExpirationDate.date());
				res.put('ubicaciones', ubicacionesPoliza(bienes(recordId, false, null)));
			} else {
				Opportunity opp = MovimientosColectivoController.oportunidad(recordId);
				InsurancePolicy anterior = MovimientosColectivoController.polizaAnteriorDe(opp);
				res.put('contexto', 'oportunidad');
				res.put('aplica', esUbicaciones(opp.Ramo__c));
				res.put('nombre', opp.Name);
				res.put('polizaAnteriorId', anterior == null ? null : anterior.Id);
				res.put('polizaAnteriorNombre', anterior == null ? null : anterior.Name);
				res.put('polizaAnteriorFin', anterior == null || anterior.ExpirationDate == null ? null : anterior.ExpirationDate.date());
				res.put('ubicacionesAnterior', anterior == null ? 0 : bienes(anterior.Id, true, null).size());
				res.put('ubicaciones', ubicacionesCenso(censo(recordId, null)));
			}
			res.put('movimientos', MovimientosColectivoController.historial(recordId));
			return res;
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			throw CensoColectivoController.error('No se pudieron leer las ubicaciones: ' + e.getMessage());
		}
	}

	// ============================================================
	// Movimientos
	// ============================================================

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Aplica altas, bajas y cambios de ubicaciones. Todo o nada. Orden: bajas, cambios y altas.
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
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Renovación armada por el ejecutivo: llena el listado de ubicaciones de la oportunidad con las
	 *               ubicaciones vigentes de la póliza anterior (domicilio, giro, suma asegurada y prima).
	 * @param opportunityId: oportunidad de renovación.
	 * @param reemplazar: true para reemplazar el listado actual.
	 * @return ubicaciones del listado después de copiar.
	 */
	@AuraEnabled(cacheable=false)
	public static Integer traerDePoliza(Id opportunityId, Boolean reemplazar) {
		Opportunity opp = MovimientosColectivoController.oportunidad(opportunityId);
		InsurancePolicy anterior = MovimientosColectivoController.polizaAnteriorDe(opp);
		if (anterior == null) { throw CensoColectivoController.error('El cliente no tiene una póliza anterior de este ramo.'); }
		List<InsurancePolicyAsset> vigentes = bienes(anterior.Id, true, null);
		if (vigentes.isEmpty()) { throw CensoColectivoController.error('La póliza ' + anterior.Name + ' no tiene ubicaciones vigentes.'); }
		Savepoint sp = Database.setSavepoint();
		try {
			List<Categoria_Colectiva__c> actuales = censo(opportunityId, null);
			Set<String> ya = new Set<String>();
			if (reemplazar == true) {
				if (!actuales.isEmpty()) { delete actuales; }
			} else {
				for (Categoria_Colectiva__c c : actuales) { ya.add(PolicyController.llaveDireccion(c.Direccion__c)); }
			}
			List<Categoria_Colectiva__c> nuevas = new List<Categoria_Colectiva__c>();
			for (InsurancePolicyAsset a : vigentes) {
				Map<String, Object> u = ubicacion(a);
				String dir = (String) u.get('direccion');
				if (String.isBlank(dir) || !ya.add(PolicyController.llaveDireccion(dir))) { continue; }
				Ubicacion d = new Ubicacion();
				d.nombre = 'Ubicación ' + (u.get('inciso') == null ? String.valueOf(nuevas.size() + 1) : String.valueOf(u.get('inciso')));
				d.direccion = dir;
				d.giro = (String) u.get('giro');
				d.sumaAsegurada = (Decimal) u.get('sumaAsegurada');
				d.prima = (Decimal) u.get('prima');
				Categoria_Colectiva__c c = new Categoria_Colectiva__c(Oportunidad__c = opportunityId);
				llenar(c, d);
				nuevas.add(c);
			}
			if (!nuevas.isEmpty()) { insert nuevas; }
			return censo(opportunityId, null).size();
		} catch (Exception e) {
			Database.rollback(sp);
			throw CensoColectivoController.error('No se trajeron las ubicaciones: ' + MovimientosColectivoController.mensaje(e));
		}
	}

	// ============================================================
	// Póliza (endoso)
	// ============================================================

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Endoso: bajas (bien con fecha y motivo, inactivo), cambios (suma asegurada, prima, giro, inciso) y
	 *               altas (bien del cliente y bien de póliza nuevos; si el domicilio ya estuvo y se dio de baja, se reactiva).
	 * @param policyId: póliza.
	 * @param movs: movimientos validados.
	 * @return altas, bajas y cambios.
	 */
	private static Map<String, Object> aplicarPoliza(Id policyId, List<Movimiento> movs) {
		InsurancePolicy pol = poliza(policyId);
		Date inicio = pol.EffectiveDate == null ? null : pol.EffectiveDate.date();
		Date fin = pol.ExpirationDate == null ? null : pol.ExpirationDate.date();
		List<InsurancePolicyAsset> todos = bienes(policyId, false, null);
		Map<Id, InsurancePolicyAsset> porId = new Map<Id, InsurancePolicyAsset>(todos);
		for (Movimiento m : movs) {
			if (m.tipo != ALTA && !porId.containsKey(Id.valueOf(m.id))) {
				throw CensoColectivoController.error('Una de las ubicaciones no pertenece a esta póliza.');
			}
		}
		List<Movimiento_Poliza__c> registro = new List<Movimiento_Poliza__c>();
		Map<Id, InsurancePolicyAsset> actualizar = new Map<Id, InsurancePolicyAsset>();
		Map<Id, CustomerProperty> propiedades = new Map<Id, CustomerProperty>();
		Integer bajas = 0;
		Integer cambios = 0;
		Integer altas = 0;

		for (Movimiento m : movs) {
			if (m.tipo == ALTA) { continue; }
			InsurancePolicyAsset a = porId.get(Id.valueOf(m.id));
			Date f = CensoColectivoController.fecha(m.fecha);
			if (m.tipo == BAJA) {
				if (a.Fecha_Baja__c != null) { throw CensoColectivoController.error(nombre(a) + ' ya está dada de baja.'); }
				if (inicio != null && f < inicio) {
					throw CensoColectivoController.error(nombre(a) + ': la fecha de baja es anterior al inicio de la póliza.');
				}
				a.Fecha_Baja__c = f;
				a.Motivo_Baja__c = m.motivo;
				a.IsActive = false;
				a.EffectiveToDate = f;
				actualizar.put(a.Id, a);
				registro.add(registro(m, BAJA, CONTEXTO_ENDOSO, policyId, null, ubicacion(a)));
				bajas++;
				continue;
			}
			if (a.Fecha_Baja__c != null) { throw CensoColectivoController.error(nombre(a) + ' está dada de baja: no se puede cambiar.'); }
			Map<String, Object> antes = ubicacion(a);
			List<String> detalle = cambiarBien(a, m.datos, propiedades);
			if (detalle.isEmpty()) { continue; }
			actualizar.put(a.Id, a);
			Movimiento_Poliza__c r = registro(m, CAMBIO, CONTEXTO_ENDOSO, policyId, null, antes);
			r.Detalle__c = String.join(detalle, '\n');
			registro.add(r);
			cambios++;
		}

		// Altas: el domicilio identifica a la ubicación. Si ya estuvo en la póliza y se dio de baja, se reactiva.
		Map<String, InsurancePolicyAsset> porLlave = new Map<String, InsurancePolicyAsset>();
		Integer ultimo = 0;
		for (InsurancePolicyAsset a : todos) {
			if (a.CustomerProperty != null) { porLlave.put(PolicyController.llaveBien(a.CustomerProperty), a); }
			Integer n = inciso(a);
			if (n != null && n > ultimo) { ultimo = n; }
		}
		Map<String, Movimiento> nuevas = new Map<String, Movimiento>();
		List<Object> datosNuevos = new List<Object>();
		for (Movimiento m : movs) {
			if (m.tipo != ALTA) { continue; }
			String k = PolicyController.llaveDireccion(m.datos.direccion);
			if (nuevas.containsKey(k)) { throw CensoColectivoController.error('El domicilio ' + m.datos.direccion + ' viene repetido en las altas.'); }
			Date f = CensoColectivoController.fecha(m.fecha);
			if ((inicio != null && f < inicio) || (fin != null && f > fin)) {
				throw CensoColectivoController.error(m.datos.direccion + ': la fecha de alta está fuera de la vigencia de la póliza.');
			}
			InsurancePolicyAsset ya = porLlave.get(k);
			if (ya != null && actualizar.containsKey(ya.Id)) {
				throw CensoColectivoController.error('La ubicación ' + m.datos.direccion + ' tiene otro movimiento en esta misma carga.');
			}
			if (ya != null && ya.Fecha_Baja__c == null) {
				throw CensoColectivoController.error('La ubicación ' + m.datos.direccion + ' ya está vigente en la póliza (' + nombre(ya) + ').');
			}
			if (ya != null) {
				// Reingreso de una ubicación que se había dado de baja.
				m.datos.direccion = null;
				cambiarBien(ya, m.datos, propiedades);
				ya.Fecha_Baja__c = null;
				ya.Motivo_Baja__c = null;
				ya.IsActive = true;
				ya.EffectiveFromDate = f;
				ya.EffectiveToDate = fin;
				actualizar.put(ya.Id, ya);
				Movimiento_Poliza__c r = registro(m, ALTA, CONTEXTO_ENDOSO, policyId, null, ubicacion(ya));
				r.Detalle__c = ('Reingreso de la ubicación\n' + detalleAlta(m.datos)).trim();
				registro.add(r);
				altas++;
				continue;
			}
			if (m.datos.inciso == null) { ultimo++; m.datos.inciso = ultimo; }
			nuevas.put(k, m);
			datosNuevos.add(new Map<String, Object>{
				'inciso' => String.valueOf(m.datos.inciso), 'direccion' => m.datos.direccion.normalizeSpace(), 'giro' => m.datos.giro,
				'sumaAsegurada' => m.datos.sumaAsegurada, 'primaTotal' => m.datos.prima
			});
		}
		if (!actualizar.isEmpty()) { update actualizar.values(); }
		if (!propiedades.isEmpty()) { update propiedades.values(); }

		if (!nuevas.isEmpty()) {
			if (pol.NameInsuredId == null) { throw CensoColectivoController.error('La póliza no tiene asegurado (cliente) para registrar las ubicaciones.'); }
			PolicyController.guardarUbicacionesDesdePdf(policyId, pol.NameInsuredId, datosNuevos);
			List<InsurancePolicyAsset> desde = new List<InsurancePolicyAsset>();
			for (InsurancePolicyAsset a : bienes(policyId, false, null)) {
				if (porId.containsKey(a.Id) || a.CustomerProperty == null) { continue; }
				Movimiento m = nuevas.get(PolicyController.llaveBien(a.CustomerProperty));
				if (m == null) { continue; }
				a.EffectiveFromDate = CensoColectivoController.fecha(m.fecha);
				desde.add(a);
				Movimiento_Poliza__c r = registro(m, ALTA, CONTEXTO_ENDOSO, policyId, null, ubicacion(a));
				r.Detalle__c = detalleAlta(m.datos);
				registro.add(r);
				altas++;
			}
			if (!desde.isEmpty()) { update desde; }
		}
		if (!registro.isEmpty()) { insert registro; }
		return new Map<String, Object>{ 'altas' => altas, 'bajas' => bajas, 'cambios' => cambios };
	}

	// ============================================================
	// Oportunidad (renovación)
	// ============================================================

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Renovación: la baja quita la ubicación del listado (queda registrada contra la póliza anterior), el
	 *               cambio actualiza el listado y el alta la agrega.
	 * @param oppId: oportunidad.
	 * @param movs: movimientos validados.
	 * @return altas, bajas y cambios.
	 */
	private static Map<String, Object> aplicarOportunidad(Id oppId, List<Movimiento> movs) {
		Opportunity opp = MovimientosColectivoController.oportunidad(oppId);
		InsurancePolicy anterior = MovimientosColectivoController.polizaAnteriorDe(opp);
		Id polizaId = anterior == null ? null : anterior.Id;
		List<Categoria_Colectiva__c> lista = censo(oppId, null);
		Map<Id, Categoria_Colectiva__c> porId = new Map<Id, Categoria_Colectiva__c>(lista);
		Map<Id, Integer> posicion = new Map<Id, Integer>();
		for (Integer i = 0; i < lista.size(); i++) { posicion.put(lista[i].Id, i + 1); }
		for (Movimiento m : movs) {
			if (m.tipo != ALTA && !porId.containsKey(Id.valueOf(m.id))) {
				throw CensoColectivoController.error('Una de las ubicaciones ya no está en el listado de la renovación.');
			}
		}
		List<Movimiento_Poliza__c> registro = new List<Movimiento_Poliza__c>();
		List<Categoria_Colectiva__c> borrar = new List<Categoria_Colectiva__c>();
		List<Categoria_Colectiva__c> actualizar = new List<Categoria_Colectiva__c>();
		Integer cambios = 0;
		for (Movimiento m : movs) {
			if (m.tipo == ALTA) { continue; }
			Categoria_Colectiva__c c = porId.get(Id.valueOf(m.id));
			Map<String, Object> antes = ubicacion(c, posicion.get(c.Id));
			if (m.tipo == BAJA) {
				borrar.add(c);
				registro.add(registro(m, BAJA, CONTEXTO_RENOVACION, polizaId, oppId, antes));
				continue;
			}
			List<String> detalle = cambiarRenglon(c, m.datos);
			if (detalle.isEmpty()) { continue; }
			actualizar.add(c);
			Movimiento_Poliza__c r = registro(m, CAMBIO, CONTEXTO_RENOVACION, polizaId, oppId, antes);
			r.Detalle__c = String.join(detalle, '\n');
			registro.add(r);
			cambios++;
		}
		if (!borrar.isEmpty()) { delete borrar; }
		if (!actualizar.isEmpty()) { update actualizar; }

		// Altas al listado (sin domicilio repetido).
		Set<String> ya = new Set<String>();
		for (Categoria_Colectiva__c c : censo(oppId, null)) { ya.add(PolicyController.llaveDireccion(c.Direccion__c)); }
		Integer siguiente = ya.size();
		List<Categoria_Colectiva__c> nuevas = new List<Categoria_Colectiva__c>();
		List<Movimiento> movNuevos = new List<Movimiento>();
		List<Integer> numeros = new List<Integer>();
		for (Movimiento m : movs) {
			if (m.tipo != ALTA) { continue; }
			if (!ya.add(PolicyController.llaveDireccion(m.datos.direccion))) {
				throw CensoColectivoController.error('La ubicación ' + m.datos.direccion + ' ya está en el listado de la renovación.');
			}
			siguiente++;
			numeros.add(siguiente);
			if (String.isBlank(m.datos.nombre)) { m.datos.nombre = 'Ubicación ' + siguiente; }
			Categoria_Colectiva__c c = new Categoria_Colectiva__c(Oportunidad__c = oppId);
			llenar(c, m.datos);
			nuevas.add(c);
			movNuevos.add(m);
		}
		if (!nuevas.isEmpty()) { insert nuevas; }
		for (Integer i = 0; i < nuevas.size(); i++) {
			Movimiento_Poliza__c r = registro(movNuevos[i], ALTA, CONTEXTO_RENOVACION, polizaId, oppId, ubicacion(nuevas[i], numeros[i]));
			r.Detalle__c = detalleAlta(movNuevos[i].datos);
			registro.add(r);
		}
		if (!registro.isEmpty()) { insert registro; }
		return new Map<String, Object>{ 'altas' => nuevas.size(), 'bajas' => borrar.size(), 'cambios' => cambios };
	}

	// ============================================================
	// Helpers
	// ============================================================

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Ubicaciones de la póliza: sus bienes ligados a un bien del cliente, por número de inciso.
	 * @param policyId: póliza.
	 * @param soloVigentes: true para excluir las dadas de baja.
	 * @param ids: solo estos bienes (null = todos).
	 * @return bienes de la póliza ordenados por inciso.
	 */
	private static List<InsurancePolicyAsset> bienes(Id policyId, Boolean soloVigentes, Set<Id> ids) {
		List<InsurancePolicyAsset> l = Database.query('SELECT Id, AssetName, IsActive, EffectiveFromDate, EffectiveToDate, '
			+ 'StandardPremiumAmount, Suma_Asegurada__c, Fecha_Baja__c, Motivo_Baja__c, CustomerPropertyId, CustomerProperty.Name, '
			+ 'CustomerProperty.Street, CustomerProperty.City, CustomerProperty.PostalCode, CustomerProperty.Uso__c, '
			+ 'CustomerProperty.FairMarketValue FROM InsurancePolicyAsset WHERE InsurancePolicyId = :policyId AND CustomerPropertyId != null'
			+ (soloVigentes ? ' AND Fecha_Baja__c = null' : '') + (ids == null ? '' : ' AND Id IN :ids')
			+ ' ORDER BY CreatedDate ASC, Id ASC LIMIT ' + MAX_UBICACIONES);
		// Por número de inciso (va al inicio del nombre del bien: «Inciso 3 - domicilio»).
		List<InsurancePolicyAsset> conInciso = new List<InsurancePolicyAsset>();
		List<InsurancePolicyAsset> sinInciso = new List<InsurancePolicyAsset>();
		Map<Integer, List<InsurancePolicyAsset>> porInciso = new Map<Integer, List<InsurancePolicyAsset>>();
		for (InsurancePolicyAsset a : l) {
			Integer n = inciso(a);
			if (n == null) { sinInciso.add(a); continue; }
			if (!porInciso.containsKey(n)) { porInciso.put(n, new List<InsurancePolicyAsset>()); }
			porInciso.get(n).add(a);
		}
		List<Integer> numeros = new List<Integer>(porInciso.keySet());
		numeros.sort();
		for (Integer n : numeros) { conInciso.addAll(porInciso.get(n)); }
		conInciso.addAll(sinInciso);
		return conInciso;
	}

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Listado de ubicaciones de la oportunidad (renglones sin cotización con domicilio). Lo usa también
	 *               la emisión cuando la cotización aceptada no trae ubicaciones.
	 * @param oppId: oportunidad.
	 * @param ids: solo estos renglones (null = todos).
	 * @return renglones en el orden en que se agregaron.
	 */
	public static List<Categoria_Colectiva__c> censo(Id oppId, Set<Id> ids) {
		if (oppId == null) { return new List<Categoria_Colectiva__c>(); }
		return Database.query('SELECT Id, Name, Direccion__c, Suma_Asegurada_Total__c, Prima_Neta__c, Parametros__c FROM Categoria_Colectiva__c '
			+ 'WHERE Oportunidad__c = :oppId AND Cotizacion__c = null AND Direccion__c != null' + (ids == null ? '' : ' AND Id IN :ids')
			+ ' ORDER BY CreatedDate ASC, Id ASC LIMIT ' + MAX_UBICACIONES);
	}

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Giro de un renglón de ubicación (se guarda como parámetro «Giro», igual que en las cotizaciones).
	 * @param c: renglón (Categoria_Colectiva__c).
	 * @return giro o null.
	 */
	public static String giro(Categoria_Colectiva__c c) {
		if (String.isBlank(c.Parametros__c)) { return null; }
		try {
			for (Object o : (List<Object>) JSON.deserializeUntyped(c.Parametros__c)) {
				Map<String, Object> p = (Map<String, Object>) o;
				if (CensoColectivoController.llave(String.valueOf(p.get('concepto'))) == CensoColectivoController.llave(CONCEPTO_GIRO)) {
					return (String) p.get('valor');
				}
			}
		} catch (Exception e) {
			System.debug(LoggingLevel.WARN, 'Parámetros de la ubicación sin formato: ' + e.getMessage());
		}
		return null;
	}

	private static void ponerGiro(Categoria_Colectiva__c c, String giro) {
		List<Object> params = new List<Object>();
		if (String.isNotBlank(c.Parametros__c)) {
			try {
				for (Object o : (List<Object>) JSON.deserializeUntyped(c.Parametros__c)) {
					Map<String, Object> p = (Map<String, Object>) o;
					if (CensoColectivoController.llave(String.valueOf(p.get('concepto'))) != CensoColectivoController.llave(CONCEPTO_GIRO)) { params.add(p); }
				}
			} catch (Exception e) {
				System.debug(LoggingLevel.WARN, 'Parámetros de la ubicación sin formato: ' + e.getMessage());
			}
		}
		if (String.isNotBlank(giro)) { params.add(new Map<String, Object>{ 'concepto' => CONCEPTO_GIRO, 'valor' => giro.normalizeSpace() }); }
		c.Parametros__c = params.isEmpty() ? null : JSON.serialize(params);
	}

	private static void llenar(Categoria_Colectiva__c c, Ubicacion d) {
		c.Name = (String.isBlank(d.nombre) ? 'Ubicación' : d.nombre.normalizeSpace()).left(80);
		c.Direccion__c = d.direccion.normalizeSpace().left(255);
		c.Suma_Asegurada_Total__c = d.sumaAsegurada;
		c.Prima_Neta__c = d.prima;
		ponerGiro(c, d.giro);
	}

	// Inciso al inicio del nombre del bien («Inciso 3 - …» o «Inciso 3, 4 - …»).
	private static Integer inciso(InsurancePolicyAsset a) {
		if (a.AssetName == null) { return null; }
		Matcher mt = Pattern.compile('^Inciso\\s+(\\d+)').matcher(a.AssetName);
		return mt.find() ? Integer.valueOf(mt.group(1)) : null;
	}

	// Domicilio del bien: el del nombre («Inciso N - domicilio») o el del bien del cliente.
	private static String direccion(InsurancePolicyAsset a) {
		if (a.AssetName != null && a.AssetName.startsWith('Inciso') && a.AssetName.contains(' - ')) {
			return a.AssetName.substringAfter(' - ');
		}
		CustomerProperty c = a.CustomerProperty;
		if (c == null) { return a.AssetName; }
		List<String> l = new List<String>();
		for (String s : new List<String>{ c.Street == null ? null : c.Street.replace('\n', ', '), c.City, c.PostalCode == null ? null : 'CP ' + c.PostalCode }) {
			if (String.isNotBlank(s)) { l.add(s); }
		}
		return l.isEmpty() ? a.AssetName : String.join(l, ', ');
	}

	private static Decimal suma(InsurancePolicyAsset a) {
		return a.Suma_Asegurada__c != null ? a.Suma_Asegurada__c : (a.CustomerProperty == null ? null : a.CustomerProperty.FairMarketValue);
	}

	private static Map<String, Object> ubicacion(InsurancePolicyAsset a) {
		return new Map<String, Object>{
			'id' => a.Id, 'inciso' => inciso(a), 'nombre' => a.CustomerProperty == null ? null : a.CustomerProperty.Name,
			'direccion' => direccion(a), 'giro' => a.CustomerProperty == null ? null : a.CustomerProperty.Uso__c,
			'sumaAsegurada' => suma(a), 'prima' => a.StandardPremiumAmount, 'activo' => a.Fecha_Baja__c == null,
			'fechaAlta' => a.EffectiveFromDate, 'fechaBaja' => a.Fecha_Baja__c, 'motivoBaja' => a.Motivo_Baja__c
		};
	}

	private static Map<String, Object> ubicacion(Categoria_Colectiva__c c, Integer inciso) {
		return new Map<String, Object>{
			'id' => c.Id, 'inciso' => inciso, 'nombre' => c.Name, 'direccion' => c.Direccion__c, 'giro' => giro(c),
			'sumaAsegurada' => c.Suma_Asegurada_Total__c, 'prima' => c.Prima_Neta__c, 'activo' => true
		};
	}

	private static List<Object> ubicacionesPoliza(List<InsurancePolicyAsset> l) {
		Map<String, String> motivos = MovimientosColectivoController.etiquetas(InsurancePolicyAsset.Motivo_Baja__c.getDescribe());
		List<Object> res = new List<Object>();
		for (InsurancePolicyAsset a : l) {
			Map<String, Object> u = ubicacion(a);
			u.put('motivoBaja', a.Motivo_Baja__c == null ? null : motivos.get(a.Motivo_Baja__c));
			res.add(u);
		}
		return res;
	}

	private static List<Object> ubicacionesCenso(List<Categoria_Colectiva__c> l) {
		List<Object> res = new List<Object>();
		for (Integer i = 0; i < l.size(); i++) { res.add(ubicacion(l[i], i + 1)); }
		return res;
	}

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Aplica al bien de la póliza los datos que vienen llenos y son distintos: suma asegurada y prima del
	 *               bien, inciso (en su nombre) y giro (en el bien del cliente). El domicilio no se cambia: es otra ubicación.
	 * @param a: bien de la póliza.
	 * @param d: datos nuevos.
	 * @param propiedades: bienes del cliente a actualizar (giro).
	 * @return detalle «Campo: antes → después» de lo que cambió.
	 */
	private static List<String> cambiarBien(InsurancePolicyAsset a, Ubicacion d, Map<Id, CustomerProperty> propiedades) {
		List<String> l = new List<String>();
		if (d == null) { return l; }
		if (String.isNotBlank(d.direccion) && PolicyController.llaveDireccion(d.direccion) != PolicyController.llaveDireccion(direccion(a))) {
			throw CensoColectivoController.error('El domicilio de ' + nombre(a) + ' no se cambia: da de baja la ubicación y da de alta la nueva.');
		}
		Integer n = inciso(a);
		if (d.inciso != null && d.inciso != n) {
			l.add('Inciso: ' + MovimientosColectivoController.texto(n == null ? null : String.valueOf(n)) + ' → ' + d.inciso);
			a.AssetName = ('Inciso ' + d.inciso + ' - ' + direccion(a)).left(255);
		}
		Decimal sumaAntes = suma(a);
		if (d.sumaAsegurada != null && d.sumaAsegurada != sumaAntes) {
			l.add('Suma asegurada: ' + MovimientosColectivoController.texto(sumaAntes) + ' → ' + MovimientosColectivoController.texto(d.sumaAsegurada));
			a.Suma_Asegurada__c = d.sumaAsegurada;
		}
		if (d.prima != null && d.prima != a.StandardPremiumAmount) {
			l.add('Prima: ' + MovimientosColectivoController.texto(a.StandardPremiumAmount) + ' → ' + MovimientosColectivoController.texto(d.prima));
			a.StandardPremiumAmount = d.prima;
		}
		String giroAntes = a.CustomerProperty == null ? null : a.CustomerProperty.Uso__c;
		if (String.isNotBlank(d.giro) && a.CustomerPropertyId != null
				&& CensoColectivoController.llave(d.giro) != CensoColectivoController.llave(giroAntes)) {
			l.add('Giro: ' + MovimientosColectivoController.texto(giroAntes) + ' → ' + d.giro.normalizeSpace());
			propiedades.put(a.CustomerPropertyId, new CustomerProperty(Id = a.CustomerPropertyId, Uso__c = d.giro.normalizeSpace().left(40)));
			a.CustomerProperty.Uso__c = d.giro.normalizeSpace().left(40);
		}
		return l;
	}

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Aplica al renglón del listado los datos que vienen llenos y son distintos.
	 * @param c: renglón.
	 * @param d: datos nuevos.
	 * @return detalle «Campo: antes → después» de lo que cambió.
	 */
	private static List<String> cambiarRenglon(Categoria_Colectiva__c c, Ubicacion d) {
		List<String> l = new List<String>();
		if (d == null) { return l; }
		if (String.isNotBlank(d.nombre) && d.nombre.normalizeSpace() != c.Name) {
			l.add('Nombre: ' + MovimientosColectivoController.texto(c.Name) + ' → ' + d.nombre.normalizeSpace());
			c.Name = d.nombre.normalizeSpace().left(80);
		}
		if (String.isNotBlank(d.direccion) && PolicyController.llaveDireccion(d.direccion) != PolicyController.llaveDireccion(c.Direccion__c)) {
			l.add('Domicilio: ' + MovimientosColectivoController.texto(c.Direccion__c) + ' → ' + d.direccion.normalizeSpace());
			c.Direccion__c = d.direccion.normalizeSpace().left(255);
		}
		String giroAntes = giro(c);
		if (String.isNotBlank(d.giro) && CensoColectivoController.llave(d.giro) != CensoColectivoController.llave(giroAntes)) {
			l.add('Giro: ' + MovimientosColectivoController.texto(giroAntes) + ' → ' + d.giro.normalizeSpace());
			ponerGiro(c, d.giro);
		}
		if (d.sumaAsegurada != null && d.sumaAsegurada != c.Suma_Asegurada_Total__c) {
			l.add('Suma asegurada: ' + MovimientosColectivoController.texto(c.Suma_Asegurada_Total__c) + ' → ' + MovimientosColectivoController.texto(d.sumaAsegurada));
			c.Suma_Asegurada_Total__c = d.sumaAsegurada;
		}
		if (d.prima != null && d.prima != c.Prima_Neta__c) {
			l.add('Prima: ' + MovimientosColectivoController.texto(c.Prima_Neta__c) + ' → ' + MovimientosColectivoController.texto(d.prima));
			c.Prima_Neta__c = d.prima;
		}
		return l;
	}

	/**
	 * @creation date: 01/11/2026
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
				throw CensoColectivoController.error('Movimiento ' + (i + 1) + ': falta la ubicación.');
			}
			if (m.tipo == BAJA && String.isBlank(m.motivo)) {
				throw CensoColectivoController.error('Indica el motivo de baja de cada ubicación.');
			}
			if (m.tipo != BAJA && m.datos == null) {
				throw CensoColectivoController.error('Movimiento ' + (i + 1) + ': faltan los datos de la ubicación.');
			}
			if (m.tipo == ALTA && String.isBlank(m.datos.direccion)) {
				throw CensoColectivoController.error('Movimiento ' + (i + 1) + ': indica el domicilio de la ubicación que se da de alta.');
			}
		}
	}

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Registro del movimiento de una ubicación.
	 * @param u: ubicación (inciso y domicilio) como la devuelve ubicacion().
	 * @return Movimiento_Poliza__c sin insertar.
	 */
	private static Movimiento_Poliza__c registro(Movimiento m, String tipo, String contexto, Id polizaId, Id oppId, Map<String, Object> u) {
		Movimiento_Poliza__c r = new Movimiento_Poliza__c(Poliza__c = polizaId, Oportunidad__c = oppId, Contexto__c = contexto,
			Asegurado__c = u.get('direccion') == null ? null : ((String) u.get('direccion')).left(255),
			Certificado__c = u.get('inciso') == null ? null : 'Inciso ' + u.get('inciso'),
			Fecha_Movimiento__c = CensoColectivoController.fecha(m.fecha),
			Numero_Endoso__c = String.isBlank(m.endoso) ? null : m.endoso.trim().left(80),
			Comentario__c = String.isBlank(m.comentario) ? null : m.comentario.trim().left(255));
		r.Tipo__c = tipo == ALTA ? 'Alta' : (tipo == BAJA ? 'Baja' : 'Cambio');
		if (tipo == BAJA) { r.Motivo_Baja_Ubicacion__c = m.motivo; }
		return r;
	}

	private static String detalleAlta(Ubicacion d) {
		List<String> l = new List<String>();
		if (String.isNotBlank(d.giro)) { l.add('Giro: ' + d.giro.normalizeSpace()); }
		if (d.sumaAsegurada != null) { l.add('Suma asegurada: ' + MovimientosColectivoController.texto(d.sumaAsegurada)); }
		if (d.prima != null) { l.add('Prima: ' + MovimientosColectivoController.texto(d.prima)); }
		return String.join(l, '\n');
	}

	private static String nombre(InsurancePolicyAsset a) {
		Integer n = inciso(a);
		return (n == null ? 'La ubicación ' : 'El inciso ' + n + ' (') + direccion(a) + (n == null ? '' : ')');
	}

	private static InsurancePolicy poliza(Id policyId) {
		return [
			SELECT Id, Name, NameInsuredId, EffectiveDate, ExpirationDate, Ramo__c FROM InsurancePolicy WHERE Id = :policyId LIMIT 1
		];
	}

	private static List<Object> motivos() {
		List<Object> l = new List<Object>();
		for (Schema.PicklistEntry pe : InsurancePolicyAsset.Motivo_Baja__c.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { l.add(new Map<String, Object>{ 'label' => pe.getLabel(), 'value' => pe.getValue() }); }
		}
		return l;
	}
}
