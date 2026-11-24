/**
 * @creation date: 31/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Altas, bajas y cambios de asegurados de una póliza colectiva de personas (GMM, Vida, Accidentes).
 *               Trabaja en dos contextos con las mismas reglas:
 *               - Póliza (endoso durante la vigencia): los asegurados son los participantes de la póliza. La baja no
 *                 borra: deja al participante inactivo con su fecha de baja («Vigente hasta») y su motivo.
 *               - Oportunidad de renovación: los asegurados son el censo de la oportunidad (que se puede llenar con los
 *                 asegurados vigentes de la póliza anterior). La baja quita al asegurado del censo de la renovación.
 *               Cada movimiento queda registrado en Movimiento_Poliza__c. También compara un archivo de la aseguradora
 *               (censo completo o endoso) contra los asegurados actuales y propone las altas, bajas y cambios.
 */
public inherited sharing class MovimientosColectivoController {

	private static final String ALTA = 'alta';
	private static final String BAJA = 'baja';
	private static final String CAMBIO = 'cambio';
	private static final String CONTEXTO_ENDOSO = 'Endoso';
	private static final String CONTEXTO_RENOVACION = 'Renovacion';
	// Roles de la póliza que no son asegurados (contratante, beneficiarios, pagador).
	private static final List<String> ROLES_NO_ASEGURADO = new List<String>{ 'contrat', 'benefic', 'pagador', 'owner', 'policyholder' };

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Movimiento que envía el LWC.
	 */
	public class Movimiento {
		// alta | baja | cambio
		public String tipo;
		// Participante (póliza) o asegurado del censo (oportunidad) para baja y cambio.
		public String id;
		// Datos del asegurado (alta) o datos nuevos (cambio; solo se aplican los que vienen llenos).
		public CensoColectivoController.MiembroEntrada datos;
		// Alta de un dependiente: su titular ya existente...
		public String titularId;
		// ...o la posición, en la misma lista, del alta de su titular.
		public Integer titularRef;
		// Fecha en que surte efecto (YYYY-MM-DD).
		public String fecha;
		// Motivo de baja (valor del picklist Motivo_Baja_Colectivo).
		public String motivo;
		public String endoso;
		public String comentario;
		// Alta que el archivo marcó como cambio (la persona no existía): se aplica como alta pero se registra y muestra como cambio.
		public Boolean comoCambio;
		// Baja en la póliza: correo personal del asegurado (el corporativo suele dejar de existir).
		public String correoPersonal;
		// Lo que cobra o devuelve la aseguradora por el movimiento (complemento del archivo).
		public Decimal prima;
	}

	// ============================================================
	// Consulta
	// ============================================================

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Datos para el LWC: asegurados (activos y dados de baja), motivos de baja, categorías de la empresa,
	 *               historial de movimientos y, en una oportunidad, la póliza anterior que se renueva.
	 * @param recordId: póliza (InsurancePolicy) u oportunidad colectiva.
	 * @return mapa con contexto, miembros, motivos, categorias, movimientos y datos de la póliza.
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> getDatos(Id recordId) {
		try {
			Map<String, Object> res = new Map<String, Object>{ 'motivos' => motivos() };
			Id accountId;
			if (esPoliza(recordId)) {
				InsurancePolicy pol = [
					SELECT Id, Name, NameInsuredId, EffectiveDate, ExpirationDate, Ramo__c, PriorPolicyId, PriorPolicy.Name
					FROM InsurancePolicy WHERE Id = :recordId LIMIT 1
				];
				accountId = pol.NameInsuredId;
				res.put('contexto', 'poliza');
				res.put('aplica', aplicaRamo(pol.Ramo__c));
				res.put('ramo', pol.Ramo__c);
				res.put('flotilla', MovimientosFlotillaController.esFlotilla(pol.Ramo__c));
				res.put('ubicaciones', MovimientosUbicacionesController.esUbicaciones(pol.Ramo__c));
				res.put('nombre', pol.Name);
				res.put('tipoContratacion', tipoContratacion(recordId));
				res.put('inicio', pol.EffectiveDate == null ? null : pol.EffectiveDate.date());
				res.put('fin', pol.ExpirationDate == null ? null : pol.ExpirationDate.date());
				res.put('polizaAnteriorId', pol.PriorPolicyId);
				res.put('polizaAnteriorNombre', pol.PriorPolicyId == null ? null : pol.PriorPolicy.Name);
				List<Map<String, Object>> miembros = aseguradosPoliza(recordId, false);
				contarArchivos(miembros);
				res.put('miembros', miembros);
				res.put('solicitudes', EndosoPoliza.solicitudes(recordId, 'asegurados'));
			} else {
				Opportunity opp = oportunidad(recordId);
				accountId = opp.AccountId;
				InsurancePolicy anterior = polizaAnteriorDe(opp);
				res.put('contexto', 'oportunidad');
				res.put('aplica', aplicaRamo(opp.Ramo__c));
				res.put('ramo', opp.Ramo__c);
				res.put('nombre', opp.Name);
				res.put('esRenovacion', String.isNotBlank(opp.Type) && opp.Type.containsIgnoreCase('renewal'));
				res.put('polizaAnteriorId', anterior == null ? null : anterior.Id);
				res.put('polizaAnteriorNombre', anterior == null ? null : anterior.Name);
				res.put('polizaAnteriorFin', anterior == null || anterior.ExpirationDate == null ? null : anterior.ExpirationDate.date());
				res.put('aseguradosAnterior', anterior == null ? 0 : aseguradosPoliza(anterior.Id, true).size());
				List<Map<String, Object>> miembros = aseguradosCenso(recordId);
				contarArchivos(miembros);
				res.put('miembros', miembros);
			}
			res.put('categorias', categorias(accountId));
			res.put('movimientos', historial(recordId));
			return res;
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			throw CensoColectivoController.error('No se pudieron leer los asegurados: ' + e.getMessage());
		}
	}

	// ============================================================
	// Movimientos
	// ============================================================

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Aplica altas, bajas y cambios. Todo o nada: si uno falla no se aplica ninguno.
	 *               Orden: bajas, cambios, altas de titulares y altas de dependientes.
	 * @param recordId: póliza (endoso) u oportunidad (renovación).
	 * @param movimientosJson: lista de Movimiento en JSON.
	 * @return número de altas, bajas y cambios aplicados.
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> aplicar(Id recordId, String movimientosJson) {
		List<Movimiento> movs;
		// Prima del endoso (de la aseguradora) cuando viene { movimientos, endoso }; con { endosos: { número: prima } }
		// cada número de endoso lleva su prima (soporte de recibo con varios endosos).
		EndosoPoliza.Prima primaEndoso;
		// Solicitud del cliente a la que se agregan (null = nueva).
		String solicitudPedida;
		Map<String, EndosoPoliza.Prima> primasEndosos;
		try {
			primaEndoso = EndosoPoliza.prima(movimientosJson);
			solicitudPedida = EndosoPoliza.solicitud(movimientosJson);
			primasEndosos = EndosoPoliza.primas(movimientosJson);
			movimientosJson = EndosoPoliza.movimientos(movimientosJson);
			movs = (List<Movimiento>) JSON.deserialize(String.isBlank(movimientosJson) ? '[]' : movimientosJson, List<Movimiento>.class);
		} catch (Exception e) {
			throw CensoColectivoController.error('Los movimientos no tienen un formato válido: ' + e.getMessage());
		}
		if (movs.isEmpty()) { throw CensoColectivoController.error('No hay movimientos para aplicar.'); }
		// «ASIGNAR» y similares no son un certificado: el registro queda sin él hasta que llegan sus documentos.
		for (Movimiento m : movs) {
			if (m.datos != null) { m.datos.certificado = CensoColectivoController.certificadoLimpio(m.datos.certificado); }
		}
		validar(movs);
		Savepoint sp = Database.setSavepoint();
		try {
			Map<String, Object> r = esPoliza(recordId) ? aplicarPoliza(recordId, movs) : aplicarOportunidad(recordId, movs);
			// Endoso de la póliza (transacción de FSC) con los movimientos aplicados.
			if (esPoliza(recordId)) {
				r.put('solicitud', EndosoPoliza.asignarSolicitud(recordId, solicitudPedida));
				List<Id> endosos = EndosoPoliza.registrarTodos(recordId, primaEndoso, primasEndosos);
				r.put('transaccionId', endosos.isEmpty() ? null : endosos[0]);
				r.put('endosos', endosos.size());
			}
			// Registro de cada movimiento, en su orden (el sitio adjunta ahí los documentos del alta).
			List<String> ids = new List<String>();
			for (Movimiento m : movs) { ids.add(m.id); }
			r.put('ids', ids);
			// Las altas que vienen de un cambio se cuentan como cambios.
			Integer comoCambio = 0;
			for (Movimiento m : movs) { if (m.tipo == ALTA && m.comoCambio == true) { comoCambio++; } }
			comoCambio = Math.min(comoCambio, (Integer) r.get('altas'));
			r.put('altas', (Integer) r.get('altas') - comoCambio);
			r.put('cambios', (Integer) r.get('cambios') + comoCambio);
			return r;
		} catch (AuraHandledException e) {
			Database.rollback(sp);
			throw e;
		} catch (Exception e) {
			Database.rollback(sp);
			throw CensoColectivoController.error('No se aplicaron los movimientos: ' + mensaje(e));
		}
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Compara un archivo (ya leído por el LWC del censo) contra los asegurados activos y propone movimientos.
	 *               El asegurado se reconoce por certificado y nombre, por nombre y fecha de nacimiento o solo por nombre.
	 * @param recordId: póliza u oportunidad.
	 * @param miembrosJson: lista de MiembroEntrada (titularIndex = posición del titular en la misma lista).
	 * @param censoCompleto: true si el archivo trae a todos los asegurados (los que no vienen se proponen como baja);
	 *                       false si solo trae movimientos (altas y cambios).
	 * @return altas (con ref = posición en el archivo y titularId o titularRef), bajas, cambios y sinCambios.
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> compararArchivo(Id recordId, String miembrosJson, Boolean censoCompleto) {
		List<CensoColectivoController.MiembroEntrada> entrada;
		try {
			entrada = (List<CensoColectivoController.MiembroEntrada>) JSON.deserialize(
				String.isBlank(miembrosJson) ? '[]' : miembrosJson, List<CensoColectivoController.MiembroEntrada>.class);
		} catch (Exception e) {
			throw CensoColectivoController.error('El archivo no tiene un formato válido: ' + e.getMessage());
		}
		for (CensoColectivoController.MiembroEntrada e : entrada) { e.certificado = CensoColectivoController.certificadoLimpio(e.certificado); }
		List<Map<String, Object>> base = new List<Map<String, Object>>();
		for (Map<String, Object> a : esPoliza(recordId) ? aseguradosPoliza(recordId, true) : aseguradosCenso(recordId)) {
			if (a.get('activo') != false) { base.add(a); }
		}

		// Índices de los asegurados actuales.
		Map<String, Map<String, Object>> porCertNombre = new Map<String, Map<String, Object>>();
		Map<String, Map<String, Object>> porNombreFecha = new Map<String, Map<String, Object>>();
		Map<String, Map<String, Object>> porNombre = new Map<String, Map<String, Object>>();
		Map<String, Map<String, Object>> porRfc = new Map<String, Map<String, Object>>();
		Map<String, List<Map<String, Object>>> porCert = new Map<String, List<Map<String, Object>>>();
		for (Map<String, Object> a : base) {
			String n = llaveNombre((String) a.get('nombre'));
			porCertNombre.put(cert((String) a.get('certificado')) + '|' + n, a);
			porNombreFecha.put(n + '|' + String.valueOf(a.get('fechaNacimiento')), a);
			porNombre.put(n, a);
			if (String.isNotBlank((String) a.get('rfc'))) { porRfc.put(((String) a.get('rfc')).deleteWhitespace().toUpperCase(), a); }
			String c = cert((String) a.get('certificado'));
			if (String.isNotBlank(c)) {
				if (!porCert.containsKey(c)) { porCert.put(c, new List<Map<String, Object>>()); }
				porCert.get(c).add(a);
			}
		}

		// Un archivo con tipo de movimiento (alta/baja/cambio) solo trae movimientos: los que no vienen no son baja.
		for (CensoColectivoController.MiembroEntrada e : entrada) {
			if (String.isNotBlank(e.movimiento)) { censoCompleto = false; break; }
		}

		Set<String> usados = new Set<String>();
		Map<Integer, String> encontrado = new Map<Integer, String>();
		List<Object> altas = new List<Object>();
		List<Object> cambios = new List<Object>();
		List<Object> bajas = new List<Object>();
		// Bajas del archivo de personas que no son asegurados (no se puede hacer nada con ellas; solo se avisa).
		List<Object> noEncontrados = new List<Object>();
		// Altas del archivo de personas que ya están aseguradas (no se duplican; solo se avisa).
		List<Object> duplicados = new List<Object>();
		Integer sinCambios = 0;
		// Renglones ya leídos (nombre, nacimiento, certificado y movimiento): uno repetido no se da de alta dos veces.
		Map<String, Integer> vistos = new Map<String, Integer>();
		for (Integer i = 0; i < entrada.size(); i++) {
			CensoColectivoController.MiembroEntrada e = entrada[i];
			String n = llaveNombre(nombreDe(e));
			if (String.isBlank(n)) { continue; }
			Integer fila = e.fila != null ? e.fila : i + 1;
			String llaveFila = n + '|' + (String.isBlank(e.fechaNacimiento) ? '' : e.fechaNacimiento.left(10)) + '|'
				+ cert(e.certificado) + '|' + (e.movimiento == null ? '' : e.movimiento);
			if (vistos.containsKey(llaveFila)) {
				duplicados.add(new Map<String, Object>{
					'fila' => fila, 'nombre' => nombreDe(e), 'repetidoEnArchivo' => true, 'filaOriginal' => vistos.get(llaveFila)
				});
				continue;
			}
			vistos.put(llaveFila, fila);
			Map<String, Object> a = porCertNombre.get(cert(e.certificado) + '|' + n);
			if (a == null && String.isNotBlank(e.fechaNacimiento)) { a = porNombreFecha.get(n + '|' + e.fechaNacimiento.left(10)); }
			if (a == null) { a = porNombre.get(n); }
			if (a != null && usados.contains((String) a.get('id'))) { a = null; }
			// Baja o cambio con otro nombre (p. ej. se corrigen nombre o apellidos): se busca por RFC o por certificado.
			if (a == null && (e.movimiento == 'Cambio' || e.movimiento == 'Baja')) { a = porOtroDato(e, porRfc, porCert, usados); }
			// Baja indicada en el archivo: se propone la baja del asegurado que ya existe.
			if (e.movimiento == 'Baja') {
				if (a == null) {
					noEncontrados.add(new Map<String, Object>{ 'fila' => e.fila, 'nombre' => nombreDe(e), 'certificado' => e.certificado });
					continue;
				}
				usados.add((String) a.get('id'));
				bajas.add(new Map<String, Object>{
					'id' => a.get('id'), 'nombre' => a.get('nombre'), 'parentesco' => a.get('parentesco'),
					'certificado' => a.get('certificado'), 'titularId' => a.get('titularId'), 'titularNombre' => a.get('titularNombre'),
					'fechaMovimiento' => e.fechaAlta, 'numeroEndoso' => e.numeroEndoso, 'primaMovimiento' => e.primaMovimiento
				});
				continue;
			}
			if (a == null) {
				altas.add(i);
				continue;
			}
			usados.add((String) a.get('id'));
			encontrado.put(i, (String) a.get('id'));
			List<Object> diferencias = diferencias(a, e);
			// Cambio de nombre o apellidos: la misma persona con otro nombre (no un alta nueva).
			Boolean otroNombre = e.movimiento == 'Cambio' && llaveNombre((String) a.get('nombre')) != n;
			if (otroNombre) {
				Map<String, Object> dn = dif('Nombre', a.get('nombre'), nombreDe(e));
				if (diferencias.isEmpty()) { diferencias.add(dn); } else { diferencias.add(0, dn); }
			}
			// Alta indicada en el archivo de alguien que ya es asegurado: no se duplica y se avisa.
			if (e.movimiento == 'Alta') {
				duplicados.add(new Map<String, Object>{
					'fila' => fila, 'nombre' => nombreDe(e), 'existente' => a.get('nombre'),
					'certificado' => a.get('certificado'), 'conCambios' => !diferencias.isEmpty(),
					'parentesco' => a.get('parentesco'), 'titularNombre' => a.get('titularNombre'),
					'fechaNacimiento' => a.get('fechaNacimiento'), 'categoria' => a.get('categoria'),
					'sumaAsegurada' => a.get('sumaAsegurada'), 'fechaAlta' => a.get('fechaAlta'), 'repetidoEnArchivo' => false
				});
			}
			if (diferencias.isEmpty()) {
				if (e.movimiento != 'Alta') { sinCambios++; }
				continue;
			}
			if (otroNombre) {
				e.nombreCompleto = nombreDe(e);
			} else {
				// El nombre no se cambia (se reconoció aunque venga sin acentos o en otro orden).
				e.nombreCompleto = null;
			}
			e.nombre = null;
			e.apellidos = null;
			cambios.add(new Map<String, Object>{
				'id' => a.get('id'), 'nombre' => a.get('nombre'), 'parentesco' => a.get('parentesco'),
				'certificado' => a.get('certificado'), 'diferencias' => diferencias, 'datos' => comoMapa(e),
				'fechaMovimiento' => e.movimiento == null ? null : e.fechaAlta, 'numeroEndoso' => e.numeroEndoso
			});
		}

		List<Object> altasRes = new List<Object>();
		for (Object o : altas) {
			Integer i = (Integer) o;
			CensoColectivoController.MiembroEntrada e = entrada[i];
			Map<String, Object> alta = new Map<String, Object>{
				'ref' => i, 'nombre' => nombreDe(e), 'parentesco' => String.isBlank(e.parentesco) ? 'Titular' : e.parentesco,
				'certificado' => e.certificado, 'categoria' => e.categoria, 'fechaNacimiento' => e.fechaNacimiento,
				'sumaAsegurada' => e.sumaAsegurada, 'prima' => e.prima, 'datos' => comoMapa(e),
				'fechaMovimiento' => e.fechaAlta, 'numeroEndoso' => e.numeroEndoso
			};
			// El archivo lo marcó como cambio pero la persona no existe: internamente es alta, el usuario lo ve como cambio.
			if (e.movimiento == 'Cambio') {
				alta.put('comoCambio', true);
				alta.put('diferencias', diferencias(new Map<String, Object>(), e));
			}
			if (e.titularIndex != null && e.titularIndex >= 0 && e.titularIndex < entrada.size()) {
				alta.put('titularNombre', nombreDe(entrada[e.titularIndex]));
				if (encontrado.containsKey(e.titularIndex)) { alta.put('titularId', encontrado.get(e.titularIndex)); }
				else { alta.put('titularRef', e.titularIndex); }
			}
			altasRes.add(alta);
		}

		if (censoCompleto == true) {
			for (Map<String, Object> a : base) {
				if (usados.contains((String) a.get('id'))) { continue; }
				bajas.add(new Map<String, Object>{
					'id' => a.get('id'), 'nombre' => a.get('nombre'), 'parentesco' => a.get('parentesco'),
					'certificado' => a.get('certificado'), 'titularId' => a.get('titularId'), 'titularNombre' => a.get('titularNombre'),
					// No viene en el archivo: se propone, pero el usuario decide si es baja.
					'faltante' => true
				});
			}
		}
		return new Map<String, Object>{ 'altas' => altasRes, 'bajas' => bajas, 'cambios' => cambios, 'sinCambios' => sinCambios,
			'noEncontrados' => noEncontrados, 'duplicados' => duplicados };
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Llena el censo de la oportunidad de renovación con los asegurados vigentes de la póliza anterior
	 *               (titulares con sus dependientes, certificado, categoría, suma asegurada, prima y fecha de alta).
	 * @param opportunityId: oportunidad de renovación.
	 * @param reemplazar: true reemplaza el censo actual; false falla si ya tiene asegurados.
	 * @return número de asegurados del censo.
	 */
	@AuraEnabled(cacheable=false)
	public static Integer traerDePoliza(Id opportunityId, Boolean reemplazar) {
		Opportunity opp = oportunidad(opportunityId);
		InsurancePolicy anterior = polizaAnteriorDe(opp);
		if (anterior == null) {
			throw CensoColectivoController.error('El cliente no tiene una póliza anterior de este ramo para renovar.');
		}
		if (reemplazar != true && [SELECT COUNT() FROM GroupCensusMember WHERE GroupCensus.Oportunidad__c = :opportunityId] > 0) {
			throw CensoColectivoController.error('La oportunidad ya tiene censo. Confirma que quieres reemplazarlo.');
		}
		List<CensoColectivoController.MiembroEntrada> lista = new List<CensoColectivoController.MiembroEntrada>();
		Map<String, Integer> posicion = new Map<String, Integer>();
		for (Map<String, Object> a : aseguradosPoliza(anterior.Id, true)) {
			if (a.get('activo') == false) { continue; }
			CensoColectivoController.MiembroEntrada e = new CensoColectivoController.MiembroEntrada();
			e.fila = lista.size() + 1;
			e.nombreCompleto = (String) a.get('nombre');
			e.certificado = (String) a.get('certificado');
			e.fechaNacimiento = a.get('fechaNacimiento') == null ? null : String.valueOf(a.get('fechaNacimiento'));
			e.sexo = (String) a.get('sexo');
			e.categoria = (String) a.get('categoria');
			e.sumaAsegurada = (Decimal) a.get('sumaAsegurada');
			e.prima = (Decimal) a.get('prima');
			e.rfc = (String) a.get('rfc');
			e.fechaAlta = a.get('fechaAlta') == null ? null : String.valueOf(a.get('fechaAlta'));
			if (a.get('titularId') != null) {
				Integer t = posicion.get((String) a.get('titularId'));
				// Dependiente cuyo titular ya no está vigente: no pasa a la renovación.
				if (t == null) { continue; }
				e.titularIndex = t;
				e.parentesco = parentescoCenso((String) a.get('parentesco'));
			} else {
				e.parentesco = 'Titular';
				posicion.put((String) a.get('id'), lista.size());
			}
			lista.add(e);
		}
		if (lista.isEmpty()) {
			throw CensoColectivoController.error('La póliza ' + anterior.Name + ' no tiene asegurados vigentes.');
		}
		return CensoColectivoController.guardarCenso(opportunityId, JSON.serialize(lista), true);
	}

	// ============================================================
	// Póliza (endosos)
	// ============================================================

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Aplica los movimientos a los participantes de la póliza.
	 * @param policyId: póliza.
	 * @param movs: movimientos validados.
	 * @return conteo por tipo.
	 */
	private static Map<String, Object> aplicarPoliza(Id policyId, List<Movimiento> movs) {
		InsurancePolicy pol = [SELECT Id, Name, NameInsuredId, EffectiveDate, ExpirationDate FROM InsurancePolicy WHERE Id = :policyId LIMIT 1];
		List<Movimiento_Poliza__c> registro = new List<Movimiento_Poliza__c>();
		Integer bajas = 0;
		Integer cambios = 0;

		// Participantes de bajas y cambios (con los dependientes de los titulares que se dan de baja).
		Map<Id, Movimiento> porId = new Map<Id, Movimiento>();
		Set<Id> idsBaja = new Set<Id>();
		for (Movimiento m : movs) {
			if (m.tipo == ALTA) { continue; }
			porId.put(Id.valueOf(m.id), m);
			if (m.tipo == BAJA) { idsBaja.add(Id.valueOf(m.id)); }
		}
		Set<Id> ids = porId.keySet();
		Map<Id, InsurancePolicyParticipant> participantes = new Map<Id, InsurancePolicyParticipant>();
		if (!ids.isEmpty()) {
			for (InsurancePolicyParticipant p : (List<InsurancePolicyParticipant>) Database.query(
				'SELECT ' + camposParticipante() + ' FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :policyId'
				+ ' AND (Id IN :ids OR (RelatedInsPolicyParticipantId IN :idsBaja AND IsActiveParticipant != false))')) {
				participantes.put(p.Id, p);
			}
		}
		for (Id i : ids) {
			if (!participantes.containsKey(i)) { throw CensoColectivoController.error('Uno de los asegurados ya no está en la póliza.'); }
		}

		// 1) Bajas: el participante queda inactivo con su fecha y motivo (no se borra).
		Map<Id, InsurancePolicyParticipant> actualizar = new Map<Id, InsurancePolicyParticipant>();
		for (InsurancePolicyParticipant p : participantes.values()) {
			Movimiento m = porId.get(p.Id);
			Boolean conTitular = false;
			if ((m == null || m.tipo != BAJA) && idsBaja.contains(p.RelatedInsPolicyParticipantId)) {
				m = porId.get(p.RelatedInsPolicyParticipantId);
				conTitular = true;
			}
			if (m == null || m.tipo != BAJA || p.IsActiveParticipant == false) { continue; }
			Date f = CensoColectivoController.fecha(m.fecha);
			if (p.EffectiveFromDate != null && f < p.EffectiveFromDate) {
				throw CensoColectivoController.error('La fecha de baja de ' + p.ParticipantName + ' es anterior a su alta ('
					+ p.EffectiveFromDate.format() + ').');
			}
			p.IsActiveParticipant = false;
			p.EffectiveToDate = f;
			p.ExpirationDate = Datetime.newInstance(f, Time.newInstance(12, 0, 0, 0));
			p.Motivo_Baja__c = m.motivo;
			// El correo del movimiento se envía después: queda pendiente.
			p.Correo_Enviado__c = false;
			if (!conTitular && String.isNotBlank(m.correoPersonal)) { p.Correo_Personal__c = m.correoPersonal.trim(); }
			actualizar.put(p.Id, p);
			Movimiento_Poliza__c r = registro(m, BAJA, CONTEXTO_ENDOSO, policyId, null, p.Id, p.ParticipantName, p.ParticipantCode);
			if (conTitular) { r.Comentario__c = ('Baja junto con su titular. ' + (m.comentario == null ? '' : m.comentario)).trim().left(255); }
			registro.add(r);
			bajas++;
		}

		// 2) Cambios de datos.
		Map<String, Id> cats = categoriasDe(pol.NameInsuredId, movs);
		Map<Id, Decimal> sumasActuales = sumasDe(policyId, ids);
		Map<Id, Decimal> sumas = new Map<Id, Decimal>();
		// Correo: vive en el contacto o en la cuenta del asegurado, no en el participante.
		List<InsurancePolicyParticipant> conCorreo = new List<InsurancePolicyParticipant>();
		for (Movimiento m : movs) {
			if (m.tipo == CAMBIO && m.datos != null && String.isNotBlank(m.datos.email)) { conCorreo.add(participantes.get(Id.valueOf(m.id))); }
		}
		Map<Id, String> correosActuales = conCorreo.isEmpty() ? new Map<Id, String>() : ParticipantesPolizaController.correosDe(conCorreo);
		Set<Id> cuentasPersona = new Set<Id>();
		Set<Id> cuentasCorreo = new Set<Id>();
		for (InsurancePolicyParticipant p : conCorreo) {
			if (p.PrimaryParticipantContactId == null && p.PrimaryParticipantAccountId != null) { cuentasCorreo.add(p.PrimaryParticipantAccountId); }
		}
		if (!cuentasCorreo.isEmpty() && Schema.SObjectType.Account.fields.getMap().containsKey('ispersonaccount')) {
			for (SObject a : Database.query('SELECT Id FROM Account WHERE Id IN :cuentasCorreo AND IsPersonAccount = true')) { cuentasPersona.add(a.Id); }
		}
		List<SObject> correosNuevos = new List<SObject>();
		for (Movimiento m : movs) {
			if (m.tipo != CAMBIO) { continue; }
			InsurancePolicyParticipant p = participantes.get(Id.valueOf(m.id));
			// Dependiente que salió con su titular en esta misma carga: ya no se cambia.
			if (p.IsActiveParticipant == false) { continue; }
			List<String> detalle = cambiarParticipante(p, m.datos, cats);
			if (String.isNotBlank(m.datos.email)) {
				String nuevo = m.datos.email.trim();
				String antes = correosActuales.get(p.Id);
				if (antes == null || !antes.equalsIgnoreCase(nuevo)) {
					correosNuevos.add(registroCorreo(p, nuevo, cuentasPersona));
					detalle.add('Correo: ' + texto(antes) + ' → ' + nuevo);
				}
			}
			if (m.datos.sumaAsegurada != null) {
				Decimal antes = sumasActuales.get(p.Id);
				if (antes != m.datos.sumaAsegurada) {
					detalle.add('Suma asegurada: ' + texto(antes) + ' → ' + texto(m.datos.sumaAsegurada));
					sumas.put(p.Id, m.datos.sumaAsegurada);
				}
			}
			if (detalle.isEmpty()) { continue; }
			// El correo del cambio se envía después: queda pendiente.
			p.Correo_Enviado__c = false;
			actualizar.put(p.Id, p);
			Movimiento_Poliza__c r = registro(m, CAMBIO, CONTEXTO_ENDOSO, policyId, null, p.Id, p.ParticipantName, p.ParticipantCode);
			r.Detalle__c = String.join(detalle, '\n');
			registro.add(r);
			cambios++;
		}
		if (!actualizar.isEmpty()) { update actualizar.values(); }
		if (!correosNuevos.isEmpty()) {
			Map<Id, SObject> unicos = new Map<Id, SObject>();
			for (SObject s : correosNuevos) { unicos.put(s.Id, s); }
			List<SObject> l = unicos.values();
			l.sort();
			update l;
		}
		guardarSumas(policyId, sumas);

		// 3) Altas.
		Integer altas = altasPoliza(pol, movs, cats, registro);
		insert registro;
		EndosoPoliza.agregar(registro);
		return new Map<String, Object>{ 'altas' => altas, 'bajas' => bajas, 'cambios' => cambios };
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Altas en la póliza: titulares primero y luego dependientes ligados a su titular, con el mismo armado
	 *               que la emisión (rol, parentesco por sexo, certificado, categoría, contacto y suma asegurada).
	 *               Su vigencia empieza en la fecha del movimiento.
	 * @param pol: póliza.
	 * @param movs: movimientos (se toman las altas).
	 * @param cats: categorías de la empresa.
	 * @param registro: movimientos a registrar (se agregan los de las altas).
	 * @return número de altas.
	 */
	private static Integer altasPoliza(InsurancePolicy pol, List<Movimiento> movs, Map<String, Id> cats, List<Movimiento_Poliza__c> registro) {
		Map<String, Id> activos = new Map<String, Id>();
		Map<String, String> categoriaTitular = new Map<String, String>();
		for (InsurancePolicyParticipant p : [
			SELECT Id, ParticipantName, ParticipantCode, Categoria__c FROM InsurancePolicyParticipant
			WHERE InsurancePolicyId = :pol.Id AND IsActiveParticipant != false
		]) {
			activos.put(CensoColectivoController.llaveParticipante(p.ParticipantCode, p.ParticipantName), p.Id);
			categoriaTitular.put((String) p.Id, p.Categoria__c);
		}

		Schema.DescribeFieldResult rol = InsurancePolicyParticipant.Role.getDescribe();
		String rolTitular = CensoColectivoController.valorPicklist(rol, new List<String>{ 'Asegurado', 'Insured' });
		String rolDependiente = CensoColectivoController.valorPicklist(rol, new List<String>{ 'Miembro familiar', 'Asegurado', 'Insured' });
		Schema.DescribeFieldResult relacion = InsurancePolicyParticipant.RelationshipToInsured.getDescribe();

		Map<Integer, InsurancePolicyParticipant> creados = new Map<Integer, InsurancePolicyParticipant>();
		Map<Integer, GroupCensusMember> miembros = new Map<Integer, GroupCensusMember>();
		for (Boolean dependientes : new List<Boolean>{ false, true }) {
			List<GroupCensusMember> nuevosTitulares = new List<GroupCensusMember>();
			List<Integer> posiciones = new List<Integer>();
			for (Integer i = 0; i < movs.size(); i++) {
				Movimiento m = movs[i];
				Boolean esDependiente = m.titularId != null || m.titularRef != null;
				if (m.tipo != ALTA || esDependiente != dependientes) { continue; }
				m.datos.titularIndex = dependientes ? 0 : null;
				GroupCensusMember gm = CensoColectivoController.miembro(m.datos, null, cats);
				if (dependientes && gm.GroupClassId == null) {
					// El dependiente sin categoría toma la de su titular.
					gm.GroupClassId = m.titularRef != null && miembros.containsKey(m.titularRef) ? miembros.get(m.titularRef).GroupClassId : null;
				}
				miembros.put(i, gm);
				if (!dependientes) {
					nuevosTitulares.add(gm);
					posiciones.add(i);
				}
			}
			if (!dependientes) { CensoColectivoController.ligarContactosTitulares(nuevosTitulares, pol.NameInsuredId); }

			List<InsurancePolicyParticipant> insertar = new List<InsurancePolicyParticipant>();
			Map<Integer, InsurancePolicyParticipant> deEstaVuelta = new Map<Integer, InsurancePolicyParticipant>();
			for (Integer i = 0; i < movs.size(); i++) {
				Movimiento m = movs[i];
				Boolean esDependiente = m.titularId != null || m.titularRef != null;
				if (m.tipo != ALTA || esDependiente != dependientes) { continue; }
				GroupCensusMember gm = miembros.get(i);
				InsurancePolicyParticipant p = CensoColectivoController.participante(gm, pol.Id, dependientes ? rolDependiente : rolTitular, pol);
				String llave = CensoColectivoController.llaveParticipante(p.ParticipantCode, p.ParticipantName);
				if (activos.containsKey(llave)) {
					throw CensoColectivoController.error(p.ParticipantName + ' ya está vigente en la póliza.');
				}
				activos.put(llave, null);
				Date f = CensoColectivoController.fecha(m.fecha);
				p.EffectiveFromDate = f;
				p.Fecha_Antiguedad__c = CensoColectivoController.fecha(m.datos.fechaAntiguedad);
				// Categoría: la del alta o, en un dependiente, la de su titular.
				String categoria = String.isNotBlank(m.datos.categoria) ? m.datos.categoria.normalizeSpace()
					: (dependientes && m.titularRef != null && creados.containsKey(m.titularRef) ? creados.get(m.titularRef).Categoria__c
						: (dependientes && m.titularId != null ? categoriaTitular.get(m.titularId) : null));
				if (String.isNotBlank(categoria)) { p.Categoria__c = categoria.left(80); }
				p.EffectiveDate = Datetime.newInstance(f, Time.newInstance(12, 0, 0, 0));
				if (dependientes) {
					Id titular = m.titularId != null ? Id.valueOf(m.titularId)
						: (creados.containsKey(m.titularRef) ? creados.get(m.titularRef).Id : null);
					if (titular == null) {
						throw CensoColectivoController.error(p.ParticipantName + ': su titular no está en la póliza ni en las altas.');
					}
					p.RelatedInsPolicyParticipantId = titular;
					String rel = CensoColectivoController.valorPicklist(relacion,
						CensoColectivoController.parentescoPoliza(gm.RelationshipToPrimaryMember, gm.Gender));
					if (String.isNotBlank(rel)) { p.RelationshipToInsured = rel; }
				}
				insertar.add(p);
				deEstaVuelta.put(i, p);
			}
			if (!insertar.isEmpty()) { insert insertar; }
			creados.putAll(deEstaVuelta);
		}

		Map<Id, Decimal> sumas = new Map<Id, Decimal>();
		for (Integer i : creados.keySet()) {
			Movimiento m = movs[i];
			InsurancePolicyParticipant p = creados.get(i);
			m.id = p.Id;
			if (m.datos.sumaAsegurada != null) { sumas.put(p.Id, m.datos.sumaAsegurada); }
			Movimiento_Poliza__c r = registro(m, ALTA, CONTEXTO_ENDOSO, pol.Id, null, p.Id, p.ParticipantName, p.ParticipantCode);
			r.Detalle__c = detalleAlta(m.datos);
			registro.add(r);
		}
		guardarSumas(pol.Id, sumas);
		return creados.size();
	}

	/**
	 * @creation date: 11/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Registro donde se guarda el correo del asegurado: su contacto o, si no tiene, su cuenta (correo
	 *               personal si es persona; si no, el correo de la cuenta).
	 * @param p: participante.
	 * @param correo: correo nuevo.
	 * @return Contact o Account con el correo nuevo.
	 */
	private static SObject registroCorreo(InsurancePolicyParticipant p, String correo, Set<Id> cuentasPersona) {
		if (p.PrimaryParticipantContactId != null) { return new Contact(Id = p.PrimaryParticipantContactId, Email = correo); }
		if (p.PrimaryParticipantAccountId == null) {
			throw CensoColectivoController.error(p.ParticipantName + ' no tiene contacto ni cuenta donde guardar el correo.');
		}
		Map<String, Schema.SObjectField> fm = Schema.SObjectType.Account.fields.getMap();
		Account a = new Account(Id = p.PrimaryParticipantAccountId);
		if (cuentasPersona.contains(a.Id)) { a.put('PersonEmail', correo); }
		else if (fm.containsKey('correo_electronico__c')) { a.put('Correo_electronico__c', correo); }
		else { throw CensoColectivoController.error('No hay un campo de correo en la cuenta de ' + p.ParticipantName + '.'); }
		return a;
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Aplica al participante los datos que vienen llenos y distintos; regresa la lista de cambios.
	 * @param p: participante (se modifica).
	 * @param d: datos nuevos.
	 * @param cats: categorías de la empresa.
	 * @return renglones "Campo: antes → después".
	 */
	private static List<String> cambiarParticipante(InsurancePolicyParticipant p, CensoColectivoController.MiembroEntrada d, Map<String, Id> cats) {
		List<String> detalle = new List<String>();
		if (String.isNotBlank(d.nombreCompleto) && d.nombreCompleto.normalizeSpace() != p.ParticipantName) {
			detalle.add('Nombre: ' + p.ParticipantName + ' → ' + d.nombreCompleto.normalizeSpace());
			p.ParticipantName = d.nombreCompleto.normalizeSpace().left(255);
		}
		if (String.isNotBlank(d.certificado) && d.certificado.trim() != p.ParticipantCode) {
			detalle.add('Certificado: ' + texto(p.ParticipantCode) + ' → ' + d.certificado.trim());
			p.ParticipantCode = d.certificado.trim().left(255);
		}
		Date fn = CensoColectivoController.fecha(d.fechaNacimiento);
		if (fn != null && fn != p.FechaNacimiento__c) {
			detalle.add('Fecha de nacimiento: ' + texto(p.FechaNacimiento__c) + ' → ' + fn.format());
			p.FechaNacimiento__c = fn;
		}
		String sx = CensoColectivoController.sexo(d.sexo);
		if (sx != null && sx != p.Sexo__c) {
			if (p.Sexo__c != null || sx != CensoColectivoController.sexo(sexoDe(p.RelationshipToInsured))) { detalle.add('Sexo: ' + texto(p.Sexo__c) + ' → ' + sx); }
			p.Sexo__c = sx;
		}
		Date fa = CensoColectivoController.fecha(d.fechaAntiguedad);
		if (fa != null && fa != p.Fecha_Antiguedad__c) {
			detalle.add('Fecha de antigüedad: ' + texto(p.Fecha_Antiguedad__c) + ' → ' + fa.format());
			p.Fecha_Antiguedad__c = fa;
		}
		if (String.isNotBlank(d.rfc) && d.rfc.deleteWhitespace().toUpperCase() != p.Identificacion__c) {
			detalle.add('RFC: ' + texto(p.Identificacion__c) + ' → ' + d.rfc.deleteWhitespace().toUpperCase());
			p.Identificacion__c = d.rfc.deleteWhitespace().toUpperCase().left(50);
		}
		if (d.prima != null && d.prima != p.TermPremiumAmount) {
			detalle.add('Prima: ' + texto(p.TermPremiumAmount) + ' → ' + texto(d.prima));
			p.TermPremiumAmount = d.prima;
		}
		if (String.isNotBlank(d.categoria)
				&& CensoColectivoController.llave(d.categoria) != CensoColectivoController.llave(nombreClase(p))) {
			detalle.add('Categoría: ' + texto(nombreClase(p)) + ' → ' + d.categoria.normalizeSpace());
			p.Categoria__c = d.categoria.normalizeSpace().left(80);
			Id nueva = cats.get(CensoColectivoController.llave(d.categoria));
			if (TIENE_CLASE && nueva != null) { p.put('GroupClassId', nueva); }
		}
		return detalle;
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Suma asegurada individual: actualiza la cobertura del participante o la crea.
	 * @param policyId: póliza.
	 * @param sumas: participante -> suma asegurada.
	 */
	private static void guardarSumas(Id policyId, Map<Id, Decimal> sumas) {
		if (sumas.isEmpty()) { return; }
		Set<Id> ids = sumas.keySet();
		Map<Id, InsurancePolicyCoverage> existentes = new Map<Id, InsurancePolicyCoverage>();
		for (InsurancePolicyCoverage c : [
			SELECT Id, InsurancePolicyParticipantId, LimitAmount FROM InsurancePolicyCoverage
			WHERE InsurancePolicyId = :policyId AND InsurancePolicyParticipantId IN :ids ORDER BY CreatedDate ASC
		]) {
			if (!existentes.containsKey(c.InsurancePolicyParticipantId)) { existentes.put(c.InsurancePolicyParticipantId, c); }
		}
		Map<Id, String> nombres = new Map<Id, String>();
		for (InsurancePolicyParticipant p : [SELECT Id, ParticipantName FROM InsurancePolicyParticipant WHERE Id IN :ids]) {
			nombres.put(p.Id, p.ParticipantName);
		}
		List<InsurancePolicyCoverage> guardar = new List<InsurancePolicyCoverage>();
		for (Id pid : ids) {
			InsurancePolicyCoverage c = existentes.get(pid);
			if (c == null) {
				c = new InsurancePolicyCoverage(InsurancePolicyId = policyId, InsurancePolicyParticipantId = pid,
					CoverageName = ('Suma asegurada - ' + nombres.get(pid)).left(255));
			}
			c.LimitAmount = sumas.get(pid);
			guardar.add(c);
		}
		upsert guardar;
	}

	// ============================================================
	// Oportunidad (renovación)
	// ============================================================

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Aplica los movimientos al censo de la oportunidad de renovación. Las bajas quitan al asegurado (y a sus
	 *               dependientes) del censo y quedan registradas contra la póliza anterior con su motivo.
	 * @param oppId: oportunidad.
	 * @param movs: movimientos validados.
	 * @return conteo por tipo.
	 */
	private static Map<String, Object> aplicarOportunidad(Id oppId, List<Movimiento> movs) {
		Opportunity opp = oportunidad(oppId);
		if (opp.AccountId == null) {
			throw CensoColectivoController.error('La oportunidad no tiene cliente (la empresa contratante).');
		}
		InsurancePolicy anterior = polizaAnteriorDe(opp);
		Map<String, Id> participantesAnteriores = new Map<String, Id>();
		if (anterior != null) {
			for (InsurancePolicyParticipant p : [
				SELECT Id, ParticipantName, ParticipantCode FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :anterior.Id LIMIT 10000
			]) {
				participantesAnteriores.put(CensoColectivoController.llaveParticipante(p.ParticipantCode, p.ParticipantName), p.Id);
				participantesAnteriores.put(CensoColectivoController.llaveParticipante(null, p.ParticipantName), p.Id);
			}
		}
		Id polizaId = anterior == null ? null : anterior.Id;
		GroupCensus censo = CensoColectivoController.asegurarCenso(opp);
		List<Movimiento_Poliza__c> registro = new List<Movimiento_Poliza__c>();

		Map<Id, Movimiento> porId = new Map<Id, Movimiento>();
		Set<Id> idsBaja = new Set<Id>();
		Set<Id> titularesAlta = new Set<Id>();
		for (Movimiento m : movs) {
			if (m.tipo == ALTA) {
				if (m.titularId != null) { titularesAlta.add(Id.valueOf(m.titularId)); }
				continue;
			}
			porId.put(Id.valueOf(m.id), m);
			if (m.tipo == BAJA) { idsBaja.add(Id.valueOf(m.id)); }
		}
		Set<Id> ids = porId.keySet();
		Map<Id, GroupCensusMember> miembros = new Map<Id, GroupCensusMember>([
			SELECT Id, Name, FirstName, LastName, Certificado__c, Birthdate, RFC__c, Prima__c, Suma_Asegurada__c, GroupClassId,
				GroupClass.Name, Gender, PrimaryGroupCensusMemberId
			FROM GroupCensusMember
			WHERE GroupCensusId = :censo.Id AND (Id IN :ids OR PrimaryGroupCensusMemberId IN :idsBaja OR Id IN :titularesAlta)
		]);
		for (Id i : ids) {
			if (!miembros.containsKey(i)) { throw CensoColectivoController.error('Uno de los asegurados ya no está en el censo.'); }
		}

		// 1) Bajas (dependientes primero: apuntan a su titular).
		List<GroupCensusMember> borrarDependientes = new List<GroupCensusMember>();
		List<GroupCensusMember> borrarTitulares = new List<GroupCensusMember>();
		for (GroupCensusMember gm : miembros.values()) {
			Movimiento m = porId.get(gm.Id);
			Boolean conTitular = false;
			if ((m == null || m.tipo != BAJA) && idsBaja.contains(gm.PrimaryGroupCensusMemberId)) {
				m = porId.get(gm.PrimaryGroupCensusMemberId);
				conTitular = true;
			}
			if (m == null || m.tipo != BAJA) { continue; }
			(gm.PrimaryGroupCensusMemberId == null ? borrarTitulares : borrarDependientes).add(gm);
			Id anteriorP = participantesAnteriores.get(CensoColectivoController.llaveParticipante(gm.Certificado__c, gm.Name));
			if (anteriorP == null) { anteriorP = participantesAnteriores.get(CensoColectivoController.llaveParticipante(null, gm.Name)); }
			Movimiento_Poliza__c r = registro(m, BAJA, CONTEXTO_RENOVACION, polizaId, oppId, anteriorP, gm.Name, gm.Certificado__c);
			if (conTitular) { r.Comentario__c = ('Baja junto con su titular. ' + (m.comentario == null ? '' : m.comentario)).trim().left(255); }
			registro.add(r);
		}
		Set<Id> borrados = new Map<Id, GroupCensusMember>(borrarDependientes).keySet().clone();
		borrados.addAll(new Map<Id, GroupCensusMember>(borrarTitulares).keySet());
		if (!borrarDependientes.isEmpty()) { delete borrarDependientes; }
		if (!borrarTitulares.isEmpty()) { delete borrarTitulares; }

		// 2) Cambios.
		Map<String, Id> cats = categoriasDe(opp.AccountId, movs);
		List<GroupCensusMember> actualizar = new List<GroupCensusMember>();
		Integer cambios = 0;
		for (Movimiento m : movs) {
			if (m.tipo != CAMBIO) { continue; }
			// Dependiente que salió con su titular en esta misma carga: ya no está en el censo.
			if (borrados.contains(Id.valueOf(m.id))) { continue; }
			GroupCensusMember gm = miembros.get(Id.valueOf(m.id));
			List<String> detalle = cambiarMiembro(gm, m.datos, cats);
			if (detalle.isEmpty()) { continue; }
			actualizar.add(gm);
			Movimiento_Poliza__c r = registro(m, CAMBIO, CONTEXTO_RENOVACION, polizaId, oppId, null, gm.Name, gm.Certificado__c);
			r.Detalle__c = String.join(detalle, '\n');
			registro.add(r);
			cambios++;
		}
		if (!actualizar.isEmpty()) { update actualizar; }

		// 3) Altas: titulares y luego dependientes.
		Map<Integer, GroupCensusMember> creados = new Map<Integer, GroupCensusMember>();
		for (Boolean dependientes : new List<Boolean>{ false, true }) {
			Map<Integer, GroupCensusMember> vuelta = new Map<Integer, GroupCensusMember>();
			for (Integer i = 0; i < movs.size(); i++) {
				Movimiento m = movs[i];
				Boolean esDependiente = m.titularId != null || m.titularRef != null;
				if (m.tipo != ALTA || esDependiente != dependientes) { continue; }
				m.datos.titularIndex = dependientes ? 0 : null;
				if (!dependientes && String.isBlank(m.datos.fechaAlta)) { m.datos.fechaAlta = m.fecha; }
				GroupCensusMember gm = CensoColectivoController.miembro(m.datos, censo.Id, cats);
				if (dependientes) {
					GroupCensusMember titular = m.titularId == null ? creados.get(m.titularRef)
						: (miembros.containsKey(Id.valueOf(m.titularId)) ? miembros.get(Id.valueOf(m.titularId)) : new GroupCensusMember(Id = Id.valueOf(m.titularId)));
					if (titular == null || titular.Id == null) {
						throw CensoColectivoController.error(gm.Name + ': su titular no está en el censo ni en las altas.');
					}
					gm.PrimaryGroupCensusMemberId = titular.Id;
					if (gm.GroupClassId == null) { gm.GroupClassId = titular.GroupClassId; }
					if (String.isBlank(gm.Certificado__c)) { gm.Certificado__c = titular.Certificado__c; }
				}
				vuelta.put(i, gm);
			}
			if (!vuelta.isEmpty()) { insert vuelta.values(); }
			creados.putAll(vuelta);
		}
		for (Integer i : creados.keySet()) {
			GroupCensusMember gm = creados.get(i);
			Movimiento_Poliza__c r = registro(movs[i], ALTA, CONTEXTO_RENOVACION, polizaId, oppId, null, gm.Name, gm.Certificado__c);
			r.Detalle__c = detalleAlta(movs[i].datos);
			registro.add(r);
		}
		insert registro;
		return new Map<String, Object>{
			'altas' => creados.size(), 'bajas' => borrarTitulares.size() + borrarDependientes.size(), 'cambios' => cambios
		};
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Aplica al asegurado del censo los datos que vienen llenos y distintos.
	 * @param gm: asegurado del censo (se modifica).
	 * @param d: datos nuevos.
	 * @param cats: categorías de la empresa.
	 * @return renglones "Campo: antes → después".
	 */
	private static List<String> cambiarMiembro(GroupCensusMember gm, CensoColectivoController.MiembroEntrada d, Map<String, Id> cats) {
		List<String> detalle = new List<String>();
		if (String.isNotBlank(d.nombreCompleto) && d.nombreCompleto.normalizeSpace() != gm.Name) {
			GroupCensusMember nuevo = CensoColectivoController.miembro(d, null, cats);
			detalle.add('Nombre: ' + gm.Name + ' → ' + nuevo.Name);
			gm.Name = nuevo.Name;
			gm.FirstName = nuevo.FirstName;
			gm.LastName = nuevo.LastName;
		}
		if (String.isNotBlank(d.certificado) && d.certificado.trim() != gm.Certificado__c) {
			detalle.add('Certificado: ' + texto(gm.Certificado__c) + ' → ' + d.certificado.trim());
			gm.Certificado__c = d.certificado.trim();
		}
		Date fn = CensoColectivoController.fecha(d.fechaNacimiento);
		if (fn != null && fn != gm.Birthdate) {
			detalle.add('Fecha de nacimiento: ' + texto(gm.Birthdate) + ' → ' + fn.format());
			gm.Birthdate = fn;
		}
		if (String.isNotBlank(d.rfc) && d.rfc.deleteWhitespace().toUpperCase() != gm.RFC__c) {
			detalle.add('RFC: ' + texto(gm.RFC__c) + ' → ' + d.rfc.deleteWhitespace().toUpperCase());
			gm.RFC__c = d.rfc.deleteWhitespace().toUpperCase();
		}
		if (d.prima != null && d.prima != gm.Prima__c) {
			detalle.add('Prima: ' + texto(gm.Prima__c) + ' → ' + texto(d.prima));
			gm.Prima__c = d.prima;
		}
		if (d.sumaAsegurada != null && d.sumaAsegurada != gm.Suma_Asegurada__c) {
			detalle.add('Suma asegurada: ' + texto(gm.Suma_Asegurada__c) + ' → ' + texto(d.sumaAsegurada));
			gm.Suma_Asegurada__c = d.sumaAsegurada;
		}
		if (String.isNotBlank(d.categoria)) {
			Id nueva = cats.get(CensoColectivoController.llave(d.categoria));
			if (nueva != null && nueva != gm.GroupClassId) {
				detalle.add('Categoría: ' + texto(gm.GroupClass == null ? null : gm.GroupClass.Name) + ' → ' + d.categoria.normalizeSpace());
				gm.GroupClassId = nueva;
			}
		}
		if (String.isNotBlank(d.sexo)) {
			String antes = gm.Gender;
			CensoColectivoController.setPicklist(gm, 'Gender', d.sexo);
			if (gm.Gender != antes) { detalle.add('Sexo: ' + texto(antes) + ' → ' + d.sexo); }
		}
		return detalle;
	}

	// ============================================================
	// Lectura de asegurados
	// ============================================================

	// GroupClassId existe en InsurancePolicyParticipant solo en versiones recientes de FSC.
	private static final Boolean TIENE_CLASE = Schema.SObjectType.InsurancePolicyParticipant.fields.getMap().containsKey('groupclassid');

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Campos del participante que se consultan (la categoría solo si el campo existe).
	 * @return lista de campos para SOQL dinámico.
	 */
	private static String camposParticipante() {
		return 'Id, ParticipantName, ParticipantCode, RelatedInsPolicyParticipantId, RelatedInsPolicyParticipant.ParticipantName,'
			+ ' RelationshipToInsured, Role, FechaNacimiento__c, Fecha_Antiguedad__c, Sexo__c, Identificacion__c, TermPremiumAmount, EffectiveFromDate,'
			+ ' EffectiveToDate, IsActiveParticipant, Motivo_Baja__c, Categoria__c, PrimaryParticipantContactId, PrimaryParticipantAccountId,'
			+ ' Correo_Enviado__c, Fecha_Envio_Correo__c, Plantilla_Correo__c, Correo_Personal__c, CreatedDate'
			+ (TIENE_CLASE ? ', GroupClassId, GroupClass.Name' : '');
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Asegurados de la póliza (sin contratante ni beneficiarios), cada titular seguido de sus dependientes.
	 * @param policyId: póliza.
	 * @param soloActivos: true omite a los dados de baja.
	 * @return asegurados como mapas para el LWC.
	 */
	private static List<Map<String, Object>> aseguradosPoliza(Id policyId, Boolean soloActivos) {
		List<InsurancePolicyParticipant> ps = (List<InsurancePolicyParticipant>) Database.query(
			'SELECT ' + camposParticipante() + ' FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :policyId'
			+ (soloActivos ? ' AND IsActiveParticipant != false' : '') + ' ORDER BY ParticipantCode NULLS LAST, ParticipantName LIMIT 10000');
		Map<Id, Decimal> sumas = sumasDe(policyId, new Map<Id, InsurancePolicyParticipant>(ps).keySet());
		Map<String, String> motivos = etiquetas(Movimiento_Poliza__c.Motivo_Baja__c.getDescribe());
		Map<String, String> relaciones = etiquetas(InsurancePolicyParticipant.RelationshipToInsured.getDescribe());
		Map<Id, List<Movimiento_Poliza__c>> conSolicitud = new Map<Id, List<Movimiento_Poliza__c>>();
		Map<Id, Movimiento_Poliza__c> ultimos = ultimosMovimientos(policyId, conSolicitud);
		Map<Id, String> correos = ParticipantesPolizaController.correosDe(ps);
		Map<Id, Contact> contactos = contactosDe(ps);
		List<Map<String, Object>> lista = new List<Map<String, Object>>();
		for (InsurancePolicyParticipant p : ps) {
			if (!esAsegurado(p.Role)) { continue; }
			Boolean esTitular = p.RelatedInsPolicyParticipantId == null;
			String parentesco = esTitular ? 'Titular'
				: (p.RelationshipToInsured == null ? 'Dependiente' : CensoColectivoController.parentescoPolizaVisible(p.RelationshipToInsured, relaciones));
			lista.add(new Map<String, Object>{
				'id' => (String) p.Id, 'nombre' => p.ParticipantName, 'esTitular' => esTitular,
				'titularId' => esTitular ? null : (String) p.RelatedInsPolicyParticipantId,
				'titularNombre' => esTitular ? null : p.RelatedInsPolicyParticipant.ParticipantName,
				'parentesco' => parentesco, 'sexo' => p.Sexo__c != null ? (p.Sexo__c == 'Femenino' ? 'Mujer' : 'Hombre') : sexoDe(p.RelationshipToInsured),
				'certificado' => CensoColectivoController.certificadoLimpio(p.ParticipantCode),
				'categoria' => nombreClase(p), 'fechaNacimiento' => p.FechaNacimiento__c, 'rfc' => p.Identificacion__c,
				'fechaAntiguedad' => p.Fecha_Antiguedad__c, 'sumaAsegurada' => sumas.get(p.Id), 'prima' => p.TermPremiumAmount, 'fechaAlta' => p.EffectiveFromDate,
				'activo' => p.IsActiveParticipant != false,
				'fechaBaja' => p.IsActiveParticipant == false ? p.EffectiveToDate : null,
				'motivoBaja' => p.Motivo_Baja__c == null ? null : motivos.get(p.Motivo_Baja__c),
				'contactoId' => (String) p.PrimaryParticipantContactId, 'cuentaId' => (String) p.PrimaryParticipantAccountId,
				'correo' => correos.get(p.Id), 'correoEnviado' => p.Correo_Enviado__c == true,
				'fechaCorreo' => p.Fecha_Envio_Correo__c, 'plantillaCorreo' => p.Plantilla_Correo__c,
				'correoPersonal' => p.Correo_Personal__c
			});
			Map<String, Object> fila = lista[lista.size() - 1];
			ponerMovimiento(fila, ultimos.get(p.Id), p.IsActiveParticipant != false, p.EffectiveFromDate, p.EffectiveToDate);
			ponerSolicitudes(fila, conSolicitud.get(p.Id));
			ponerNombre(fila, contactos.get(p.PrimaryParticipantContactId));
			// Sin registro de movimiento (carga inicial): se crea con el participante y se cierra con el primer correo.
			if (fila.get('fechaCreacion') == null) {
				fila.put('fechaCreacion', p.CreatedDate);
				fila.put('fechaCierre', p.Fecha_Envio_Correo__c);
			}
		}
		return porFamilia(lista);
	}

	/**
	 * @creation date: 10/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Archivos de un asegurado (participante de la póliza o asegurado del censo): los de su contacto, su
	 *               cuenta y el propio registro. Los archivos nuevos se adjuntan al contacto (o, sin contacto, al registro).
	 * @param registroId: InsurancePolicyParticipant o GroupCensusMember.
	 * @return {destinoId, archivos: [{id, titulo, tipo, tamano, fecha}]}.
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> archivosAsegurado(Id registroId) {
		if (registroId == null) { throw CensoColectivoController.error('Falta el asegurado.'); }
		try {
			Id contacto;
			Id cuenta;
			if (registroId.getSObjectType() == InsurancePolicyParticipant.SObjectType) {
				InsurancePolicyParticipant p = [SELECT PrimaryParticipantContactId, PrimaryParticipantAccountId FROM InsurancePolicyParticipant
					WHERE Id = :registroId LIMIT 1];
				contacto = p.PrimaryParticipantContactId;
				cuenta = p.PrimaryParticipantAccountId;
			} else if (registroId.getSObjectType() == GroupCensusMember.SObjectType) {
				contacto = [SELECT ContactId FROM GroupCensusMember WHERE Id = :registroId LIMIT 1].ContactId;
			}
			Map<Id, List<Map<String, Object>>> a = ParticipantesPolizaController.archivosDe(new Set<Id>{ registroId, contacto, cuenta });
			return new Map<String, Object>{
				'destinoId' => contacto != null ? contacto : (cuenta != null ? cuenta : registroId),
				'archivos' => ParticipantesPolizaController.unirArchivos(a, new List<Id>{ contacto, cuenta, registroId })
			};
		} catch (Exception e) {
			throw CensoColectivoController.error('No se pudieron leer los archivos: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 11/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Guarda el documento de baja en el último movimiento de baja del asegurado. Es el único archivo que se
	 *               adjunta en el correo de baja.
	 * @param policyId: póliza.
	 * @param participanteId: asegurado dado de baja.
	 * @param nombre: nombre del archivo con extensión.
	 * @param base64: contenido del archivo.
	 * @return Id del documento (ContentDocument).
	 */
	@AuraEnabled(cacheable=false)
	public static Id subirDocumentoBaja(Id policyId, Id participanteId, String nombre, String base64) {
		List<Movimiento_Poliza__c> movs = [
			SELECT Id FROM Movimiento_Poliza__c
			WHERE Poliza__c = :policyId AND Participante__c = :participanteId AND Tipo__c = 'Baja'
			ORDER BY CreatedDate DESC, Id DESC LIMIT 1
		];
		if (movs.isEmpty()) { throw CensoColectivoController.error('No se encontró el movimiento de baja del asegurado.'); }
		return subirArchivo(movs[0].Id, nombre, base64);
	}

	/**
	 * @creation date: 11/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Sube un archivo (en base64) a la póliza u oportunidad. El LWC lo llama una vez por archivo, así que no
	 *               hay límite en la cantidad de archivos (el componente estándar de carga solo admite 10 a la vez).
	 * @param recordId: póliza u oportunidad.
	 * @param nombre: nombre del archivo con extensión.
	 * @param base64: contenido del archivo.
	 * @return Id del documento (ContentDocument).
	 */
	@AuraEnabled(cacheable=false)
	public static Id subirArchivo(Id recordId, String nombre, String base64) {
		if (recordId == null || String.isBlank(nombre) || String.isBlank(base64)) {
			throw CensoColectivoController.error('El archivo está vacío.');
		}
		try {
			String titulo = String.isBlank(nombre.substringBeforeLast('.')) ? nombre : nombre.substringBeforeLast('.');
			ContentVersion cv = new ContentVersion(Title = titulo.left(255), PathOnClient = nombre,
				VersionData = EncodingUtil.base64Decode(base64), FirstPublishLocationId = recordId);
			insert cv;
			return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
		} catch (Exception e) {
			throw CensoColectivoController.error('No se pudo subir ' + nombre + ': ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 10/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Carga de varios archivos a la vez: los archivos se suben primero a la póliza (u oportunidad) y aquí
	 *               se pasan a la persona que les toca (su contacto, su cuenta o el propio registro del asegurado). El
	 *               archivo deja de estar en la póliza. Los que no se asignan se quedan en la póliza.
	 * @param recordId: póliza u oportunidad donde se subieron.
	 * @param asignacionesJson: lista de {documentId, registroId}.
	 * @return número de archivos adjuntados.
	 */
	@AuraEnabled(cacheable=false)
	public static Integer asignarArchivos(Id recordId, String asignacionesJson) {
		List<Object> lista;
		try {
			lista = (List<Object>) JSON.deserializeUntyped(String.isBlank(asignacionesJson) ? '[]' : asignacionesJson);
		} catch (Exception e) {
			throw CensoColectivoController.error('Las asignaciones no tienen un formato válido.');
		}
		Map<Id, Id> registroPorDocumento = new Map<Id, Id>();
		for (Object o : lista) {
			Map<String, Object> a = (Map<String, Object>) o;
			if (a.get('documentId') == null || a.get('registroId') == null) { continue; }
			registroPorDocumento.put(Id.valueOf((String) a.get('documentId')), Id.valueOf((String) a.get('registroId')));
		}
		if (registroPorDocumento.isEmpty()) { return 0; }
		Savepoint sp = Database.setSavepoint();
		try {
			Map<Id, Id> destino = destinosArchivo(new Set<Id>(registroPorDocumento.values()));
			Set<Id> docs = registroPorDocumento.keySet();
			// Enlaces que ya existen (no se duplican).
			Set<String> existentes = new Set<String>();
			Set<Id> destinos = new Set<Id>(destino.values());
			for (ContentDocumentLink l : [SELECT ContentDocumentId, LinkedEntityId FROM ContentDocumentLink
					WHERE ContentDocumentId IN :docs AND LinkedEntityId IN :destinos]) {
				existentes.add(l.ContentDocumentId + '|' + l.LinkedEntityId);
			}
			List<ContentDocumentLink> nuevos = new List<ContentDocumentLink>();
			for (Id doc : docs) {
				Id d = destino.get(registroPorDocumento.get(doc));
				if (d == null || existentes.contains(doc + '|' + d)) { continue; }
				nuevos.add(new ContentDocumentLink(ContentDocumentId = doc, LinkedEntityId = d, ShareType = 'V'));
			}
			if (!nuevos.isEmpty()) { insert nuevos; }
			// Ya no quedan en la póliza u oportunidad.
			if (recordId != null) {
				List<ContentDocumentLink> quitar = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :recordId AND ContentDocumentId IN :docs];
				if (!quitar.isEmpty()) { delete quitar; }
			}
			return docs.size();
		} catch (Exception e) {
			Database.rollback(sp);
			throw CensoColectivoController.error('No se pudieron adjuntar los archivos: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 23/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Pone el número de certificado que trae el nombre de los documentos (certificado, tarjeta) a los
	 *               asegurados que no lo tienen («ASIGNAR» o vacío), y a sus movimientos. No cambia el de quien ya lo tiene
	 *               ni usa uno que ya es de otro asegurado.
	 * @param recordId: póliza u oportunidad.
	 * @param certificadosJson: lista de {registroId, certificado}.
	 * @return { actualizados: [«Nombre: certificado»], avisos: [texto] }
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> completarCertificados(Id recordId, String certificadosJson) {
		if (UserInfo.getUserType() != 'Standard') { throw CensoColectivoController.error('Solo un ejecutivo puede completar el certificado.'); }
		List<String> actualizados = new List<String>();
		List<String> avisos = new List<String>();
		try {
			Map<Id, Set<String>> pedidos = new Map<Id, Set<String>>();
			for (Object o : (List<Object>) JSON.deserializeUntyped(String.isBlank(certificadosJson) ? '[]' : certificadosJson)) {
				Map<String, Object> a = (Map<String, Object>) o;
				String c = CensoColectivoController.certificadoLimpio((String) a.get('certificado'));
				if (a.get('registroId') == null || c == null || !Pattern.matches('[A-Za-z0-9-]{3,30}', c)) { continue; }
				Id r = Id.valueOf((String) a.get('registroId'));
				if (!pedidos.containsKey(r)) { pedidos.put(r, new Set<String>()); }
				pedidos.get(r).add(c);
			}
			Boolean poliza = esPoliza(recordId);
			Set<Id> ids = pedidos.keySet();
			Set<String> certs = new Set<String>();
			for (Set<String> s : pedidos.values()) { certs.addAll(s); }
			// Dueño de cada certificado en la póliza u oportunidad (el titular y sus dependientes pueden compartirlo).
			Map<String, Set<Id>> duenos = new Map<String, Set<Id>>();
			List<SObject> registros = poliza
				? (List<SObject>) [SELECT Id, ParticipantName, ParticipantCode, RelatedInsPolicyParticipantId FROM InsurancePolicyParticipant
					WHERE InsurancePolicyId = :recordId AND (Id IN :ids OR ParticipantCode IN :certs)]
				: (List<SObject>) [SELECT Id, Name, Certificado__c, PrimaryGroupCensusMemberId FROM GroupCensusMember
					WHERE GroupCensus.Oportunidad__c = :recordId AND (Id IN :ids OR Certificado__c IN :certs)];
			String campo = poliza ? 'ParticipantCode' : 'Certificado__c';
			String campoTitular = poliza ? 'RelatedInsPolicyParticipantId' : 'PrimaryGroupCensusMemberId';
			String campoNombre = poliza ? 'ParticipantName' : 'Name';
			for (SObject x : registros) {
				String c = CensoColectivoController.certificadoLimpio((String) x.get(campo));
				if (c == null) { continue; }
				if (!duenos.containsKey(c)) { duenos.put(c, new Set<Id>()); }
				duenos.get(c).add(x.get(campoTitular) == null ? x.Id : (Id) x.get(campoTitular));
			}
			List<SObject> cambiar = new List<SObject>();
			Map<Id, String> nuevos = new Map<Id, String>();
			for (SObject x : registros) {
				if (!ids.contains(x.Id) || CensoColectivoController.certificadoLimpio((String) x.get(campo)) != null) { continue; }
				String nombre = (String) x.get(campoNombre);
				if (pedidos.get(x.Id).size() > 1) {
					avisos.add(nombre + ': sus documentos traen certificados distintos (' + String.join(new List<String>(pedidos.get(x.Id)), ', ') + '); captúralo a mano.');
					continue;
				}
				String c = new List<String>(pedidos.get(x.Id))[0];
				Id titular = x.get(campoTitular) == null ? x.Id : (Id) x.get(campoTitular);
				Set<Id> otros = duenos.containsKey(c) ? duenos.get(c).clone() : new Set<Id>();
				otros.remove(titular);
				if (!otros.isEmpty()) {
					avisos.add(nombre + ': el certificado ' + c + ' ya es de otro asegurado; no se actualizó.');
					continue;
				}
				if (!duenos.containsKey(c)) { duenos.put(c, new Set<Id>()); }
				duenos.get(c).add(titular);
				SObject n = x.getSObjectType().newSObject(x.Id);
				n.put(campo, c);
				cambiar.add(n);
				nuevos.put(x.Id, c);
				actualizados.add(nombre + ': ' + c);
			}
			Savepoint sp = Database.setSavepoint();
			try {
				update cambiar;
				if (poliza && !nuevos.isEmpty()) {
					List<Movimiento_Poliza__c> movs = new List<Movimiento_Poliza__c>();
					for (Movimiento_Poliza__c m : [
						SELECT Id, Participante__c, Certificado__c FROM Movimiento_Poliza__c WHERE Poliza__c = :recordId AND Participante__c IN :nuevos.keySet()
					]) {
						if (CensoColectivoController.certificadoLimpio(m.Certificado__c) == null) {
							movs.add(new Movimiento_Poliza__c(Id = m.Id, Certificado__c = nuevos.get(m.Participante__c).left(80)));
						}
					}
					update movs;
				}
			} catch (Exception e) {
				Database.rollback(sp);
				throw e;
			}
		} catch (Exception e) {
			throw CensoColectivoController.error('No se pudo completar el certificado: ' + mensaje(e));
		}
		return new Map<String, Object>{ 'actualizados' => actualizados, 'avisos' => avisos };
	}

	/**
	 * @creation date: 23/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Guarda en cada movimiento lo que cobra la aseguradora por él (el complemento del listado de
	 *               movimientos, PDF). Se toma el movimiento del asegurado del mismo tipo y la misma fecha; si no hay uno
	 *               con esa fecha, el más reciente de ese tipo.
	 * @param policyId: póliza.
	 * @param primasJson: lista de {registroId, tipo: Alta|Baja|Cambio, fecha: AAAA-MM-DD, prima}.
	 * @return { guardadas: número, avisos: [texto] }
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> guardarPrimas(Id policyId, String primasJson) {
		if (UserInfo.getUserType() != 'Standard') { throw CensoColectivoController.error('Solo un ejecutivo puede guardar la prima.'); }
		List<String> avisos = new List<String>();
		Map<Id, Movimiento_Poliza__c> cambiar = new Map<Id, Movimiento_Poliza__c>();
		try {
			List<Object> filas = (List<Object>) JSON.deserializeUntyped(String.isBlank(primasJson) ? '[]' : primasJson);
			Set<Id> ids = new Set<Id>();
			for (Object o : filas) { ids.add(Id.valueOf((String) ((Map<String, Object>) o).get('registroId'))); }
			Map<Id, List<Movimiento_Poliza__c>> movs = new Map<Id, List<Movimiento_Poliza__c>>();
			for (Movimiento_Poliza__c m : [
				SELECT Id, Participante__c, Asegurado__c, Tipo__c, Fecha_Movimiento__c FROM Movimiento_Poliza__c
				WHERE Poliza__c = :policyId AND Participante__c IN :ids ORDER BY CreatedDate DESC, Id DESC LIMIT 10000
			]) {
				if (!movs.containsKey(m.Participante__c)) { movs.put(m.Participante__c, new List<Movimiento_Poliza__c>()); }
				movs.get(m.Participante__c).add(m);
			}
			for (Object o : filas) {
				Map<String, Object> f = (Map<String, Object>) o;
				if (f.get('prima') == null) { continue; }
				Id r = Id.valueOf((String) f.get('registroId'));
				String tipo = f.get('tipo') == null ? 'Alta' : (String) f.get('tipo');
				Date fecha = CensoColectivoController.fecha((String) f.get('fecha'));
				Movimiento_Poliza__c elegido;
				if (movs.containsKey(r)) {
					for (Movimiento_Poliza__c m : movs.get(r)) {
						if (m.Tipo__c != tipo) { continue; }
						if (elegido == null) { elegido = m; }
						if (fecha != null && m.Fecha_Movimiento__c == fecha) { elegido = m; break; }
					}
				}
				if (elegido == null) {
					avisos.add((f.get('nombre') == null ? 'Un asegurado' : String.valueOf(f.get('nombre'))) + ': no tiene un movimiento de ' + tipo.toLowerCase() + '.');
					continue;
				}
				cambiar.put(elegido.Id, new Movimiento_Poliza__c(Id = elegido.Id, Prima__c = Decimal.valueOf(String.valueOf(f.get('prima')))));
			}
			update cambiar.values();
		} catch (Exception e) {
			throw CensoColectivoController.error('No se pudo guardar la prima: ' + mensaje(e));
		}
		return new Map<String, Object>{ 'guardadas' => cambiar.size(), 'avisos' => avisos };
	}

	/**
	 * @creation date: 23/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Contenido de un PDF ya subido (hasta 3 MB), para reconocer a quién corresponde por lo que dice.
	 * @param documentId: ContentDocument que el usuario puede ver.
	 * @return base64, o null si no es PDF o pesa más.
	 */
	@AuraEnabled(cacheable=false)
	public static String contenidoPdf(Id documentId) {
		for (ContentVersion v : [SELECT FileExtension, ContentSize FROM ContentVersion WHERE ContentDocumentId = :documentId AND IsLatest = true LIMIT 1]) {
			if (v.FileExtension == null || v.FileExtension.toLowerCase() != 'pdf' || v.ContentSize > 3 * 1024 * 1024) { return null; }
			return EncodingUtil.base64Encode([SELECT VersionData FROM ContentVersion WHERE Id = :v.Id].VersionData);
		}
		return null;
	}

	// Registro donde se guardan los archivos de cada asegurado: su contacto, si no su cuenta, si no el propio registro.
	private static Map<Id, Id> destinosArchivo(Set<Id> registros) {
		Map<Id, Id> r = new Map<Id, Id>();
		Set<Id> participantes = new Set<Id>();
		Set<Id> miembros = new Set<Id>();
		for (Id i : registros) {
			r.put(i, i);
			if (i.getSObjectType() == InsurancePolicyParticipant.SObjectType) { participantes.add(i); }
			if (i.getSObjectType() == GroupCensusMember.SObjectType) { miembros.add(i); }
		}
		for (InsurancePolicyParticipant p : [SELECT Id, PrimaryParticipantContactId, PrimaryParticipantAccountId
				FROM InsurancePolicyParticipant WHERE Id IN :participantes]) {
			r.put(p.Id, p.PrimaryParticipantContactId != null ? p.PrimaryParticipantContactId
				: (p.PrimaryParticipantAccountId != null ? p.PrimaryParticipantAccountId : p.Id));
		}
		for (GroupCensusMember m : [SELECT Id, ContactId FROM GroupCensusMember WHERE Id IN :miembros]) {
			if (m.ContactId != null) { r.put(m.Id, m.ContactId); }
		}
		return r;
	}

	/**
	 * @creation date: 10/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Número de archivos por asegurado (de su contacto, su cuenta o el propio registro).
	 * @param filas: asegurados con 'id', 'contactoId' y 'cuentaId'.
	 */
	private static void contarArchivos(List<Map<String, Object>> filas) {
		Set<Id> ids = new Set<Id>();
		for (Map<String, Object> f : filas) {
			for (String k : new List<String>{ 'id', 'contactoId', 'cuentaId' }) {
				if (f.get(k) != null) { ids.add(Id.valueOf((String) f.get(k))); }
			}
		}
		Map<Id, List<Map<String, Object>>> a = ParticipantesPolizaController.archivosDe(ids);
		for (Map<String, Object> f : filas) {
			List<Id> de = new List<Id>();
			for (String k : new List<String>{ 'contactoId', 'cuentaId', 'id' }) {
				if (f.get(k) != null) { de.add(Id.valueOf((String) f.get(k))); }
			}
			f.put('archivos', ParticipantesPolizaController.unirArchivos(a, de).size());
		}
	}

	/**
	 * @creation date: 15/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Tipo de contratación de la póliza (Individual / Colectiva) según su oportunidad de origen.
	 * @param policyId: póliza.
	 * @return 'Individual', 'Colectiva' o null si la póliza no viene de una oportunidad.
	 */
	public static String tipoContratacion(Id policyId) {
		List<InsurancePolicy> l = [SELECT SourceOpportunityId, SourceOpportunity.Tipo_Contratacion__c FROM InsurancePolicy WHERE Id = :policyId LIMIT 1];
		return l.isEmpty() || l[0].SourceOpportunityId == null ? null : l[0].SourceOpportunity.Tipo_Contratacion__c;
	}

	/**
	 * @creation date: 10/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Último movimiento registrado (alta, baja o cambio) de cada participante de la póliza.
	 * @param policyId: póliza.
	 * @return movimiento más reciente por participante.
	 */
	public static Map<Id, Movimiento_Poliza__c> ultimosMovimientos(Id policyId) {
		return ultimosMovimientos(policyId, null);
	}

	// Igual; además junta en «todos» los movimientos de cada participante que tienen solicitud (el más reciente primero).
	private static Map<Id, Movimiento_Poliza__c> ultimosMovimientos(Id policyId, Map<Id, List<Movimiento_Poliza__c>> todos) {
		Map<Id, Movimiento_Poliza__c> r = new Map<Id, Movimiento_Poliza__c>();
		if (policyId == null) { return r; }
		for (Movimiento_Poliza__c m : [
			SELECT Participante__c, Name, Numero_Endoso__c, Solicitud__c, Seguimiento__c, Motivo_Rechazo__c, Prima__c, Tipo__c, Fecha_Movimiento__c, CreatedDate, Fecha_Cierre__c FROM Movimiento_Poliza__c
			WHERE Poliza__c = :policyId AND Participante__c != null
			ORDER BY CreatedDate DESC, Id DESC LIMIT 10000
		]) {
			if (!r.containsKey(m.Participante__c)) { r.put(m.Participante__c, m); }
			if (todos != null && String.isNotBlank(m.Solicitud__c)) {
				if (!todos.containsKey(m.Participante__c)) { todos.put(m.Participante__c, new List<Movimiento_Poliza__c>()); }
				todos.get(m.Participante__c).add(m);
			}
		}
		return r;
	}

	/**
	 * @creation date: 23/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Agrega a la fila todos los movimientos del registro que tienen solicitud, para que cada solicitud
	 *               muestre los suyos aunque el registro tenga otro movimiento posterior (asegurados, vehículos y ubicaciones).
	 * @param fila: registro como mapa.
	 * @param movs: movimientos del registro con solicitud (o null).
	 */
	public static void ponerSolicitudes(Map<String, Object> fila, List<Movimiento_Poliza__c> movs) {
		if (movs == null || movs.isEmpty()) { return; }
		List<Map<String, Object>> l = new List<Map<String, Object>>();
		for (Movimiento_Poliza__c m : movs) {
			l.add(new Map<String, Object>{ 'movimientoId' => m.Id, 'movimientoNumero' => m.Name, 'solicitud' => m.Solicitud__c,
				'tipoMovimiento' => m.Tipo__c, 'fechaMovimiento' => m.Fecha_Movimiento__c, 'fechaCreacion' => m.CreatedDate,
				'fechaCierre' => m.Fecha_Cierre__c, 'seguimientoMov' => m.Seguimiento__c, 'motivoRechazo' => m.Motivo_Rechazo__c,
				'numeroEndoso' => m.Numero_Endoso__c, 'primaMovimiento' => m.Prima__c });
		}
		fila.put('movimientos', l);
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Contactos de los asegurados (nombre, apellidos y sexo por separado, para el Excel de movimientos).
	 */
	private static Map<Id, Contact> contactosDe(List<InsurancePolicyParticipant> ps) {
		Set<Id> ids = new Set<Id>();
		for (InsurancePolicyParticipant p : ps) { if (p.PrimaryParticipantContactId != null) { ids.add(p.PrimaryParticipantContactId); } }
		if (ids.isEmpty()) { return new Map<Id, Contact>(); }
		return new Map<Id, Contact>([
			SELECT Id, FirstName, LastName, Apellido_paterno__c, Apellido_materno__c, Sexo__c FROM Contact WHERE Id IN :ids
		]);
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Agrega 'nombres', 'apellidoPaterno', 'apellidoMaterno' y 'sexoContacto' del contacto del asegurado.
	 *               Sin apellidos en el contacto, los apellidos son su LastName (paterno y materno separados por espacio).
	 */
	private static void ponerNombre(Map<String, Object> fila, Contact c) {
		if (c == null) { return; }
		String paterno = c.Apellido_paterno__c;
		String materno = c.Apellido_materno__c;
		if (String.isBlank(paterno) && String.isNotBlank(c.LastName)) {
			List<String> partes = c.LastName.trim().split('\\s+');
			paterno = partes[0];
			if (String.isBlank(materno) && partes.size() > 1) { partes.remove(0); materno = String.join(partes, ' '); }
		}
		fila.put('nombres', c.FirstName);
		fila.put('apellidoPaterno', paterno);
		fila.put('apellidoMaterno', materno);
		fila.put('sexoContacto', c.Sexo__c);
	}

	/**
	 * @creation date: 10/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Agrega 'tipoMovimiento', 'fechaMovimiento', 'movimientoNumero' y 'numeroEndoso' a la fila. Sin registro de movimiento se deduce:
	 *               baja (fecha de fin) si no está activo, alta (fecha de inicio) si lo está.
	 */
	public static void ponerMovimiento(Map<String, Object> fila, Movimiento_Poliza__c ultimo, Boolean activo, Date desde, Date hasta) {
		String tipo;
		Date fecha;
		if (ultimo != null && (activo || ultimo.Tipo__c == 'Baja')) {
			tipo = ultimo.Tipo__c;
			fecha = ultimo.Fecha_Movimiento__c;
			// Creación del movimiento y su cierre (al enviar el correo al asegurado).
			fila.put('fechaCreacion', ultimo.CreatedDate);
			fila.put('fechaCierre', ultimo.Fecha_Cierre__c);
			// Número del movimiento y de endoso (para el Excel), si se consultaron.
			Map<String, Object> campos = ultimo.getPopulatedFieldsAsMap();
			if (campos.containsKey('Name')) { fila.put('movimientoNumero', ultimo.Name); }
			if (campos.containsKey('Numero_Endoso__c')) { fila.put('numeroEndoso', ultimo.Numero_Endoso__c); }
			// Solicitud del cliente con la que se registró (agrupa la tabla).
			if (campos.containsKey('Solicitud__c')) { fila.put('solicitud', ultimo.Solicitud__c); }
			// Seguimiento elegido a mano en el movimiento (vacío = el de su solicitud).
			if (campos.containsKey('Seguimiento__c')) { fila.put('seguimientoMov', ultimo.Seguimiento__c); }
			if (campos.containsKey('Motivo_Rechazo__c')) { fila.put('motivoRechazo', ultimo.Motivo_Rechazo__c); }
			// Lo que cobra la aseguradora por el movimiento (complemento de su listado).
			if (campos.containsKey('Prima__c')) { fila.put('primaMovimiento', ultimo.Prima__c); }
		} else if (!activo) {
			tipo = 'Baja';
			fecha = hasta;
		} else {
			tipo = 'Alta';
			fecha = desde;
		}
		fila.put('tipoMovimiento', tipo);
		fila.put('fechaMovimiento', fecha);
		if (fila.get('fechaCreacion') != null && ultimo != null && ultimo.Id != null) { fila.put('movimientoId', ultimo.Id); }
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cierra un movimiento (vehículos y ubicaciones, que no envían correo): guarda la fecha de cierre.
	 * @param movimientoId: Movimiento_Poliza__c.
	 * @return fecha de cierre (la que ya tenía si estaba cerrado).
	 */
	@AuraEnabled(cacheable=false)
	public static Datetime cerrarMovimiento(Id movimientoId) {
		List<Movimiento_Poliza__c> l = [SELECT Id, Fecha_Cierre__c FROM Movimiento_Poliza__c WHERE Id = :movimientoId LIMIT 1];
		if (l.isEmpty()) { throw CensoColectivoController.error('El movimiento ya no existe.'); }
		if (l[0].Fecha_Cierre__c != null) { return l[0].Fecha_Cierre__c; }
		try {
			// Al segundo, como se guarda (así la fecha devuelta es igual a la que se lee después).
			l[0].Fecha_Cierre__c = Datetime.newInstance((Datetime.now().getTime() / 1000) * 1000);
			update l[0];
			EndosoPoliza.aprobarCerrados(new Set<Id>{ l[0].Id });
			return l[0].Fecha_Cierre__c;
		} catch (Exception e) {
			throw CensoColectivoController.error('No se pudo cerrar el movimiento: ' + mensaje(e));
		}
	}

	/**
	 * @creation date: 23/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: El ejecutivo cambia el seguimiento de un registro (su movimiento) o de toda una solicitud.
	 * @param policyId: póliza.
	 * @param folio: solicitud (null si el movimiento no tiene).
	 * @param movimientoId: movimiento, o null para toda la solicitud.
	 * @param valor: Solicitado, En proceso, Concluido o Rechazado (este, solo en un registro).
	 * @param motivo: motivo del rechazo.
	 * @return aviso del correo al cliente cuando la solicitud quedó concluida, o null.
	 */
	@AuraEnabled(cacheable=false)
	public static String cambiarSeguimiento(Id policyId, String folio, Id movimientoId, String valor, String motivo) {
		try {
			return EndosoPoliza.cambiarSeguimiento(policyId, folio, movimientoId, valor, motivo);
		} catch (Exception e) {
			throw CensoColectivoController.error('No se pudo cambiar el seguimiento: ' + mensaje(e));
		}
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Asegurados del censo de la oportunidad, cada titular seguido de sus dependientes.
	 * @param oppId: oportunidad.
	 * @return asegurados como mapas para el LWC (mismas claves que los de la póliza).
	 */
	private static List<Map<String, Object>> aseguradosCenso(Id oppId) {
		Map<String, String> sexos = etiquetas(GroupCensusMember.Gender.getDescribe());
		// Último movimiento de la oportunidad por certificado y por nombre.
		Map<String, Movimiento_Poliza__c> ultimos = new Map<String, Movimiento_Poliza__c>();
		for (Movimiento_Poliza__c mv : [
			SELECT Tipo__c, Fecha_Movimiento__c, Certificado__c, Asegurado__c, CreatedDate, Fecha_Cierre__c FROM Movimiento_Poliza__c
			WHERE Oportunidad__c = :oppId ORDER BY CreatedDate DESC, Id DESC LIMIT 10000
		]) {
			for (String k : new List<String>{ String.isBlank(mv.Certificado__c) ? null : 'c:' + mv.Certificado__c.trim().toLowerCase(),
					String.isBlank(mv.Asegurado__c) ? null : 'n:' + llaveNombre(mv.Asegurado__c) }) {
				if (k != null && !ultimos.containsKey(k)) { ultimos.put(k, mv); }
			}
		}
		List<Map<String, Object>> lista = new List<Map<String, Object>>();
		for (GroupCensusMember m : [
			SELECT Id, Name, PrimaryGroupCensusMemberId, PrimaryGroupCensusMember.Name, AssociationWithPrimaryMbr, Gender, Birthdate,
				Certificado__c, GroupClass.Name, Suma_Asegurada__c, Prima__c, RFC__c, JoinDate, ContactId
			FROM GroupCensusMember WHERE GroupCensus.Oportunidad__c = :oppId
			ORDER BY Certificado__c NULLS LAST, Name LIMIT 10000
		]) {
			Boolean esTitular = m.PrimaryGroupCensusMemberId == null;
			lista.add(new Map<String, Object>{
				'id' => (String) m.Id, 'nombre' => m.Name, 'esTitular' => esTitular,
				'titularId' => esTitular ? null : (String) m.PrimaryGroupCensusMemberId,
				'titularNombre' => esTitular ? null : m.PrimaryGroupCensusMember.Name,
				'parentesco' => CensoColectivoController.parentescoVisible(m.AssociationWithPrimaryMbr, esTitular),
				'sexo' => m.Gender == null ? null : sexoVisible(sexos.get(m.Gender)),
				'certificado' => CensoColectivoController.certificadoLimpio(m.Certificado__c),
				'categoria' => m.GroupClass == null ? null : m.GroupClass.Name, 'fechaNacimiento' => m.Birthdate, 'rfc' => m.RFC__c,
				'sumaAsegurada' => m.Suma_Asegurada__c, 'prima' => m.Prima__c, 'fechaAlta' => m.JoinDate, 'activo' => true,
				'contactoId' => (String) m.ContactId
			});
			Movimiento_Poliza__c ult = String.isBlank(m.Certificado__c) ? null : ultimos.get('c:' + m.Certificado__c.trim().toLowerCase());
			if (ult == null && String.isNotBlank(m.Name)) { ult = ultimos.get('n:' + llaveNombre(m.Name)); }
			ponerMovimiento(lista[lista.size() - 1], ult, true, m.JoinDate, null);
		}
		return porFamilia(lista);
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Ordena por familia: cada titular seguido de sus dependientes (los huérfanos al final).
	 * @param lista: asegurados.
	 * @return asegurados ordenados.
	 */
	private static List<Map<String, Object>> porFamilia(List<Map<String, Object>> lista) {
		Map<String, List<Map<String, Object>>> deps = new Map<String, List<Map<String, Object>>>();
		for (Map<String, Object> a : lista) {
			String t = (String) a.get('titularId');
			if (t == null) { continue; }
			if (!deps.containsKey(t)) { deps.put(t, new List<Map<String, Object>>()); }
			deps.get(t).add(a);
		}
		List<Map<String, Object>> res = new List<Map<String, Object>>();
		for (Map<String, Object> a : lista) {
			if (a.get('titularId') != null) { continue; }
			res.add(a);
			if (deps.containsKey((String) a.get('id'))) { res.addAll(deps.remove((String) a.get('id'))); }
		}
		for (List<Map<String, Object>> h : deps.values()) { res.addAll(h); }
		return res;
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Últimos movimientos registrados de la póliza u oportunidad.
	 * @param recordId: póliza u oportunidad.
	 * @return movimientos como mapas.
	 */
	public static List<Object> historial(Id recordId) {
		// Cada lista de motivos tiene sus etiquetas (algunos valores se repiten entre personas, vehículos y ubicaciones).
		Map<String, String> motivos = etiquetas(Movimiento_Poliza__c.Motivo_Baja__c.getDescribe());
		Map<String, String> motivosVehiculo = etiquetas(Movimiento_Poliza__c.Motivo_Baja_Vehiculo__c.getDescribe());
		Map<String, String> motivosUbicacion = etiquetas(Movimiento_Poliza__c.Motivo_Baja_Ubicacion__c.getDescribe());
		List<Object> res = new List<Object>();
		for (Movimiento_Poliza__c m : [
			SELECT Id, Name, Tipo__c, Contexto__c, Asegurado__c, Certificado__c, Fecha_Movimiento__c, Motivo_Baja__c, Motivo_Baja_Vehiculo__c, Motivo_Baja_Ubicacion__c,
				Numero_Endoso__c, Detalle__c, Comentario__c, CreatedBy.Name, CreatedDate
			FROM Movimiento_Poliza__c
			WHERE Poliza__c = :recordId OR Oportunidad__c = :recordId
			ORDER BY CreatedDate DESC, Name DESC LIMIT 500
		]) {
			res.add(new Map<String, Object>{
				'id' => m.Id, 'nombre' => m.Name, 'tipo' => m.Tipo__c, 'asegurado' => m.Asegurado__c,
				'certificado' => CensoColectivoController.certificadoLimpio(m.Certificado__c),
				'fecha' => m.Fecha_Movimiento__c, 'motivo' => m.Motivo_Baja__c != null ? motivos.get(m.Motivo_Baja__c)
					: (m.Motivo_Baja_Vehiculo__c != null ? motivosVehiculo.get(m.Motivo_Baja_Vehiculo__c) : motivosUbicacion.get(m.Motivo_Baja_Ubicacion__c)),
				'endoso' => m.Numero_Endoso__c, 'detalle' => m.Detalle__c, 'comentario' => m.Comentario__c,
				'usuario' => m.CreatedBy.Name, 'creado' => m.CreatedDate
			});
		}
		return res;
	}

	// ============================================================
	// Helpers
	// ============================================================

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Revisa que cada movimiento traiga lo necesario (fecha, motivo en bajas, asegurado, titular).
	 * @param movs: movimientos.
	 */
	private static void validar(List<Movimiento> movs) {
		Set<String> bajas = new Set<String>();
		for (Movimiento m : movs) { if (m.tipo == BAJA && m.id != null) { bajas.add(m.id); } }
		for (Integer i = 0; i < movs.size(); i++) {
			Movimiento m = movs[i];
			if (m.tipo != ALTA && m.tipo != BAJA && m.tipo != CAMBIO) {
				throw CensoColectivoController.error('Movimiento ' + (i + 1) + ': tipo no válido.');
			}
			if (CensoColectivoController.fecha(m.fecha) == null) {
				throw CensoColectivoController.error('Movimiento ' + (i + 1) + ': falta la fecha del movimiento.');
			}
			if (m.tipo != ALTA && String.isBlank(m.id)) {
				throw CensoColectivoController.error('Movimiento ' + (i + 1) + ': falta el asegurado.');
			}
			// El motivo de baja es opcional: si viene vacío se guarda sin motivo.
			if (String.isBlank(m.motivo)) { m.motivo = null; }
			if (m.tipo != BAJA && m.datos == null) {
				throw CensoColectivoController.error('Movimiento ' + (i + 1) + ': faltan los datos del asegurado.');
			}
			if (m.tipo == ALTA && String.isBlank(nombreDe(m.datos))) {
				throw CensoColectivoController.error('Movimiento ' + (i + 1) + ': el alta no tiene nombre.');
			}
			if (m.tipo == ALTA && m.titularId != null && bajas.contains(m.titularId)) {
				throw CensoColectivoController.error('Movimiento ' + (i + 1) + ': el titular del dependiente se está dando de baja.');
			}
			if (m.titularRef != null && (m.titularRef < 0 || m.titularRef >= movs.size() || movs[m.titularRef].tipo != ALTA)) {
				throw CensoColectivoController.error('Movimiento ' + (i + 1) + ': el titular del dependiente no es válido.');
			}
		}
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Registro del movimiento con los datos comunes.
	 * @return Movimiento_Poliza__c sin insertar.
	 */
	private static Movimiento_Poliza__c registro(Movimiento m, String tipo, String contexto, Id polizaId, Id oppId, Id participanteId,
			String asegurado, String certificado) {
		Movimiento_Poliza__c r = new Movimiento_Poliza__c(Poliza__c = polizaId, Oportunidad__c = oppId, Participante__c = participanteId,
			Contexto__c = contexto, Asegurado__c = asegurado == null ? null : asegurado.left(255),
			Certificado__c = CensoColectivoController.certificadoLimpio(certificado) == null ? null : certificado.left(80), Fecha_Movimiento__c = CensoColectivoController.fecha(m.fecha),
			Numero_Endoso__c = String.isBlank(m.endoso) ? null : m.endoso.trim().left(80),
			Comentario__c = String.isBlank(m.comentario) ? null : m.comentario.trim().left(255));
		r.Tipo__c = tipo == ALTA && m.comoCambio != true ? 'Alta' : (tipo == BAJA ? 'Baja' : 'Cambio');
		if (tipo == BAJA) { r.Motivo_Baja__c = m.motivo; }
		r.Prima__c = m.prima != null ? m.prima : (m.datos == null ? null : m.datos.primaMovimiento);
		return r;
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Texto del detalle de un alta.
	 * @param d: datos del asegurado.
	 * @return detalle.
	 */
	private static String detalleAlta(CensoColectivoController.MiembroEntrada d) {
		List<String> l = new List<String>{ 'Parentesco: ' + (String.isBlank(d.parentesco) ? 'Titular' : d.parentesco) };
		if (String.isNotBlank(d.categoria)) { l.add('Categoría: ' + d.categoria); }
		if (String.isNotBlank(d.fechaNacimiento)) { l.add('Fecha de nacimiento: ' + texto(CensoColectivoController.fecha(d.fechaNacimiento))); }
		if (d.sumaAsegurada != null) { l.add('Suma asegurada: ' + texto(d.sumaAsegurada)); }
		if (d.prima != null) { l.add('Prima: ' + texto(d.prima)); }
		return String.join(l, '\n');
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Diferencias entre el asegurado actual y el renglón del archivo (solo campos que el archivo trae).
	 * @param a: asegurado actual.
	 * @param e: renglón del archivo.
	 * @return lista de {campo, antes, despues}.
	 */
	@TestVisible
	private static List<Object> diferencias(Map<String, Object> a, CensoColectivoController.MiembroEntrada e) {
		List<Object> l = new List<Object>();
		if (String.isNotBlank(e.certificado) && cert(e.certificado) != cert((String) a.get('certificado'))) {
			l.add(dif('Certificado', a.get('certificado'), e.certificado.trim()));
		}
		Date fn = CensoColectivoController.fecha(e.fechaNacimiento);
		if (fn != null && fn != (Date) a.get('fechaNacimiento')) { l.add(dif('Fecha de nacimiento', texto((Date) a.get('fechaNacimiento')), fn.format())); }
		if (String.isNotBlank(e.categoria) && CensoColectivoController.llave(e.categoria) != CensoColectivoController.llave((String) a.get('categoria'))) {
			l.add(dif('Categoría', a.get('categoria'), e.categoria.normalizeSpace()));
		}
		if (e.sumaAsegurada != null && e.sumaAsegurada != (Decimal) a.get('sumaAsegurada')) {
			l.add(dif('Suma asegurada', texto((Decimal) a.get('sumaAsegurada')), texto(e.sumaAsegurada)));
		}
		if (e.prima != null && e.prima != (Decimal) a.get('prima')) { l.add(dif('Prima', texto((Decimal) a.get('prima')), texto(e.prima))); }
		if (String.isNotBlank(e.rfc) && e.rfc.deleteWhitespace().toUpperCase() != (String) a.get('rfc')) {
			l.add(dif('RFC', a.get('rfc'), e.rfc.deleteWhitespace().toUpperCase()));
		}
		// Correo: solo en la póliza (ahí el asegurado trae su correo del contacto o cuenta).
		if (String.isNotBlank(e.email) && a.containsKey('correo')
				&& (a.get('correo') == null || !e.email.trim().equalsIgnoreCase((String) a.get('correo')))) {
			l.add(dif('Correo', a.get('correo'), e.email.trim()));
		}
		return l;
	}

	/**
	 * @creation date: 10/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Asegurado de un renglón cuyo nombre no coincide: por RFC o, si el certificado deja una sola persona
	 *               posible (por fecha de nacimiento o por ser titular/dependiente), por certificado.
	 * @return asegurado o null si no se puede asegurar quién es.
	 */
	private static Map<String, Object> porOtroDato(CensoColectivoController.MiembroEntrada e, Map<String, Map<String, Object>> porRfc,
			Map<String, List<Map<String, Object>>> porCert, Set<String> usados) {
		if (String.isNotBlank(e.rfc)) {
			Map<String, Object> a = porRfc.get(e.rfc.deleteWhitespace().toUpperCase());
			if (a != null && !usados.contains((String) a.get('id'))) { return a; }
		}
		String c = cert(e.certificado);
		if (String.isBlank(c) || !porCert.containsKey(c)) { return null; }
		Boolean titular = String.isBlank(e.parentesco) || e.parentesco == 'Titular';
		Date fn = CensoColectivoController.fecha(e.fechaNacimiento);
		// Primero por fecha de nacimiento; si el cambio también corrige la fecha, por titular/dependiente (y parentesco).
		List<Map<String, Object>> porFecha = new List<Map<String, Object>>();
		List<Map<String, Object>> porRol = new List<Map<String, Object>>();
		for (Map<String, Object> a : porCert.get(c)) {
			if (usados.contains((String) a.get('id'))) { continue; }
			if (fn != null && a.get('fechaNacimiento') != null && fn == (Date) a.get('fechaNacimiento')) { porFecha.add(a); }
			if (a.get('esTitular') == titular) { porRol.add(a); }
		}
		if (porFecha.size() == 1) { return porFecha[0]; }
		if (!porFecha.isEmpty()) { return null; }
		if (porRol.size() > 1 && !titular) {
			String par = CensoColectivoController.llave(e.parentesco).left(3);
			List<Map<String, Object>> mismo = new List<Map<String, Object>>();
			for (Map<String, Object> a : porRol) {
				if (CensoColectivoController.llave((String) a.get('parentesco')).left(3) == par) { mismo.add(a); }
			}
			porRol = mismo;
		}
		return porRol.size() == 1 ? porRol[0] : null;
	}

	public static Map<String, Object> dif(String campo, Object antes, Object despues) {
		return new Map<String, Object>{ 'campo' => campo, 'antes' => antes == null ? '—' : String.valueOf(antes), 'despues' => String.valueOf(despues) };
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Categorías de las altas y cambios (crea en la empresa las que no existan).
	 * @param accountId: empresa.
	 * @param movs: movimientos.
	 * @return llave de categoría -> GroupClass.
	 */
	private static Map<String, Id> categoriasDe(Id accountId, List<Movimiento> movs) {
		List<CensoColectivoController.MiembroEntrada> datos = new List<CensoColectivoController.MiembroEntrada>();
		for (Movimiento m : movs) { if (m.datos != null && String.isNotBlank(m.datos.categoria)) { datos.add(m.datos); } }
		if (accountId == null || datos.isEmpty()) { return new Map<String, Id>(); }
		return CensoColectivoController.categoriasDe(accountId, datos);
	}

	private static List<String> categorias(Id accountId) {
		List<String> l = new List<String>();
		if (accountId == null) { return l; }
		for (GroupClass gc : [SELECT Name FROM GroupClass WHERE AccountId = :accountId ORDER BY Name LIMIT 500]) { l.add(gc.Name); }
		return l;
	}

	private static List<Object> motivos() {
		List<Object> l = new List<Object>();
		for (Schema.PicklistEntry pe : Movimiento_Poliza__c.Motivo_Baja__c.getDescribe().getPicklistValues()) {
			if (pe.isActive()) { l.add(new Map<String, Object>{ 'label' => pe.getLabel(), 'value' => pe.getValue() }); }
		}
		return l;
	}

	public static Map<String, String> etiquetas(Schema.DescribeFieldResult f) {
		Map<String, String> m = new Map<String, String>();
		for (Schema.PicklistEntry pe : f.getPicklistValues()) { m.put(pe.getValue(), pe.getLabel()); }
		return m;
	}

	public static Boolean esPoliza(Id recordId) {
		if (recordId == null) { throw CensoColectivoController.error('Falta el registro.'); }
		return recordId.getSObjectType() == InsurancePolicy.SObjectType;
	}

	public static Opportunity oportunidad(Id oppId) {
		List<Opportunity> l = [SELECT Id, Name, AccountId, Ramo__c, Type FROM Opportunity WHERE Id = :oppId LIMIT 1];
		if (l.isEmpty()) { throw CensoColectivoController.error('No se encontró la oportunidad.'); }
		return l[0];
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Póliza que renueva la oportunidad: la más reciente del cliente y ramo que no salió de esta oportunidad.
	 * @param opp: oportunidad.
	 * @return póliza o null.
	 */
	public static InsurancePolicy polizaAnteriorDe(Opportunity opp) {
		Set<Id> propias = new Map<Id, InsurancePolicy>([SELECT Id FROM InsurancePolicy WHERE SourceOpportunityId = :opp.Id]).keySet();
		return CensoColectivoController.polizaAnterior(opp.AccountId, opp.Ramo__c, propias, null);
	}

	private static Map<Id, Decimal> sumasDe(Id policyId, Set<Id> participantes) {
		Map<Id, Decimal> res = new Map<Id, Decimal>();
		for (InsurancePolicyCoverage c : [
			SELECT InsurancePolicyParticipantId, LimitAmount FROM InsurancePolicyCoverage
			WHERE InsurancePolicyId = :policyId AND InsurancePolicyParticipantId IN :participantes ORDER BY CreatedDate ASC
		]) {
			if (!res.containsKey(c.InsurancePolicyParticipantId)) { res.put(c.InsurancePolicyParticipantId, c.LimitAmount); }
		}
		return res;
	}

	// Categoría del participante: la del campo Categoría (llenado desde el censo) o, si no, la de su GroupClass.
	private static String nombreClase(InsurancePolicyParticipant p) {
		if (String.isNotBlank(p.Categoria__c)) { return p.Categoria__c; }
		if (!TIENE_CLASE) { return null; }
		SObject gc = p.getSObject('GroupClass');
		return gc == null ? null : (String) gc.get('Name');
	}

	// Autos (flotilla) y ramos de ubicaciones aseguran bienes, no personas: sus movimientos son de vehículos o ubicaciones.
	private static Boolean aplicaRamo(String ramo) {
		return !ColectivoController.esUbicaciones(ramo) && (ramo == null || !ramo.startsWithIgnoreCase('Automovil'));
	}

	private static Boolean esAsegurado(String rol) {
		String r = rol == null ? '' : rol.toLowerCase();
		for (String x : ROLES_NO_ASEGURADO) { if (r.contains(x)) { return false; } }
		return true;
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Sexo que se deduce del parentesco de la póliza (Mujer, Hija, Madre... / Marido, Hijo, Padre...).
	 * @param relacion: valor de RelationshipToInsured.
	 * @return Mujer, Hombre o null.
	 */
	@TestVisible
	private static String sexoDe(String relacion) {
		String r = CensoColectivoController.llave(relacion);
		if (String.isBlank(r)) { return null; }
		if (r.startsWith('mujer') || r.startsWith('esposa') || r.startsWith('hija') || r.startsWith('madre') || r.startsWith('suegra')) { return 'Mujer'; }
		if (r.startsWith('marido') || r.startsWith('esposo') || r.startsWith('hijo') || r.startsWith('padre') || r.startsWith('suegro')) { return 'Hombre'; }
		return null;
	}

	private static String sexoVisible(String etiqueta) {
		String s = CensoColectivoController.llave(etiqueta);
		if (s.startsWith('m') && !s.startsWith('mas') && s != 'male') { return 'Mujer'; }
		if (s.startsWith('f')) { return 'Mujer'; }
		return String.isBlank(s) ? null : 'Hombre';
	}

	/**
	 * @creation date: 31/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Parentesco del censo (Cónyuge, Hijo(a), Padre/Madre, Suegro(a), Otro) a partir del de la póliza.
	 * @param parentesco: parentesco visible de la póliza.
	 * @return parentesco del censo.
	 */
	@TestVisible
	private static String parentescoCenso(String parentesco) {
		String p = CensoColectivoController.llave(parentesco);
		if (p.startsWith('mujer') || p.startsWith('marido') || p.startsWith('espos') || p.startsWith('cony') || p.startsWith('conyu')) { return 'Cónyuge'; }
		if (p.startsWith('hij')) { return 'Hijo(a)'; }
		if (p.startsWith('suegr')) { return 'Suegro(a)'; }
		if (p.startsWith('padre') || p.startsWith('madre')) { return 'Padre/Madre'; }
		return 'Otro';
	}

	private static String nombreDe(CensoColectivoController.MiembroEntrada e) {
		if (e == null) { return null; }
		if (String.isNotBlank(e.nombreCompleto)) { return e.nombreCompleto.normalizeSpace(); }
		return ((e.nombre == null ? '' : e.nombre) + ' ' + (e.apellidos == null ? '' : e.apellidos)).normalizeSpace();
	}

	// Nombre para reconocer a la persona: sin acentos, mayúsculas, palabras ordenadas (el archivo puede traer
	// "APELLIDOS NOMBRES" y la póliza "Nombres Apellidos").
	@TestVisible
	private static String llaveNombre(String nombre) {
		String n = CensoColectivoController.llave(nombre).replaceAll('[^a-z0-9 ]', ' ').normalizeSpace();
		if (String.isBlank(n)) { return ''; }
		List<String> partes = n.split(' ');
		partes.sort();
		return String.join(partes, ' ');
	}

	// Los objetos Apex dentro de un Map no se serializan hacia el LWC: se convierten a mapa.
	public static Object comoMapa(Object o) {
		return JSON.deserializeUntyped(JSON.serialize(o, true));
	}

	private static String cert(String c) {
		return c == null ? '' : c.trim().replaceFirst('^0+(?=.)', '').toUpperCase();
	}

	public static String texto(Object v) {
		if (v == null) { return '—'; }
		if (v instanceof Date) { return ((Date) v).format(); }
		if (v instanceof Decimal) { return '$' + ((Decimal) v).setScale(2).format(); }
		return String.valueOf(v);
	}

	public static String mensaje(Exception e) {
		if (e instanceof DmlException) { return ((DmlException) e).getDmlMessage(0); }
		return e.getMessage();
	}
}
