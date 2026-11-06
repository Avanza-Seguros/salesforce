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
public with sharing class MovimientosColectivoController {

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
				res.put('flotilla', MovimientosFlotillaController.esFlotilla(pol.Ramo__c));
				res.put('ubicaciones', MovimientosUbicacionesController.esUbicaciones(pol.Ramo__c));
				res.put('nombre', pol.Name);
				res.put('inicio', pol.EffectiveDate == null ? null : pol.EffectiveDate.date());
				res.put('fin', pol.ExpirationDate == null ? null : pol.ExpirationDate.date());
				res.put('polizaAnteriorId', pol.PriorPolicyId);
				res.put('polizaAnteriorNombre', pol.PriorPolicyId == null ? null : pol.PriorPolicy.Name);
				res.put('miembros', aseguradosPoliza(recordId, false));
			} else {
				Opportunity opp = oportunidad(recordId);
				accountId = opp.AccountId;
				InsurancePolicy anterior = polizaAnteriorDe(opp);
				res.put('contexto', 'oportunidad');
				res.put('aplica', aplicaRamo(opp.Ramo__c));
				res.put('nombre', opp.Name);
				res.put('esRenovacion', String.isNotBlank(opp.Type) && opp.Type.containsIgnoreCase('renewal'));
				res.put('polizaAnteriorId', anterior == null ? null : anterior.Id);
				res.put('polizaAnteriorNombre', anterior == null ? null : anterior.Name);
				res.put('polizaAnteriorFin', anterior == null || anterior.ExpirationDate == null ? null : anterior.ExpirationDate.date());
				res.put('aseguradosAnterior', anterior == null ? 0 : aseguradosPoliza(anterior.Id, true).size());
				res.put('miembros', aseguradosCenso(recordId));
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
		try {
			movs = (List<Movimiento>) JSON.deserialize(String.isBlank(movimientosJson) ? '[]' : movimientosJson, List<Movimiento>.class);
		} catch (Exception e) {
			throw CensoColectivoController.error('Los movimientos no tienen un formato válido: ' + e.getMessage());
		}
		if (movs.isEmpty()) { throw CensoColectivoController.error('No hay movimientos para aplicar.'); }
		validar(movs);
		Savepoint sp = Database.setSavepoint();
		try {
			return esPoliza(recordId) ? aplicarPoliza(recordId, movs) : aplicarOportunidad(recordId, movs);
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
		List<Map<String, Object>> base = new List<Map<String, Object>>();
		for (Map<String, Object> a : esPoliza(recordId) ? aseguradosPoliza(recordId, true) : aseguradosCenso(recordId)) {
			if (a.get('activo') != false) { base.add(a); }
		}

		// Índices de los asegurados actuales.
		Map<String, Map<String, Object>> porCertNombre = new Map<String, Map<String, Object>>();
		Map<String, Map<String, Object>> porNombreFecha = new Map<String, Map<String, Object>>();
		Map<String, Map<String, Object>> porNombre = new Map<String, Map<String, Object>>();
		for (Map<String, Object> a : base) {
			String n = llaveNombre((String) a.get('nombre'));
			porCertNombre.put(cert((String) a.get('certificado')) + '|' + n, a);
			porNombreFecha.put(n + '|' + String.valueOf(a.get('fechaNacimiento')), a);
			porNombre.put(n, a);
		}

		Set<String> usados = new Set<String>();
		Map<Integer, String> encontrado = new Map<Integer, String>();
		List<Object> altas = new List<Object>();
		List<Object> cambios = new List<Object>();
		Integer sinCambios = 0;
		for (Integer i = 0; i < entrada.size(); i++) {
			CensoColectivoController.MiembroEntrada e = entrada[i];
			String n = llaveNombre(nombreDe(e));
			if (String.isBlank(n)) { continue; }
			Map<String, Object> a = porCertNombre.get(cert(e.certificado) + '|' + n);
			if (a == null && String.isNotBlank(e.fechaNacimiento)) { a = porNombreFecha.get(n + '|' + e.fechaNacimiento.left(10)); }
			if (a == null) { a = porNombre.get(n); }
			if (a != null && usados.contains((String) a.get('id'))) { a = null; }
			if (a == null) {
				altas.add(i);
				continue;
			}
			usados.add((String) a.get('id'));
			encontrado.put(i, (String) a.get('id'));
			List<Object> diferencias = diferencias(a, e);
			if (diferencias.isEmpty()) {
				sinCambios++;
				continue;
			}
			// El nombre no se cambia desde el archivo (se reconoció aunque venga sin acentos o en otro orden).
			e.nombreCompleto = null;
			e.nombre = null;
			e.apellidos = null;
			cambios.add(new Map<String, Object>{
				'id' => a.get('id'), 'nombre' => a.get('nombre'), 'parentesco' => a.get('parentesco'),
				'certificado' => a.get('certificado'), 'diferencias' => diferencias, 'datos' => comoMapa(e)
			});
		}

		List<Object> altasRes = new List<Object>();
		for (Object o : altas) {
			Integer i = (Integer) o;
			CensoColectivoController.MiembroEntrada e = entrada[i];
			Map<String, Object> alta = new Map<String, Object>{
				'ref' => i, 'nombre' => nombreDe(e), 'parentesco' => String.isBlank(e.parentesco) ? 'Titular' : e.parentesco,
				'certificado' => e.certificado, 'categoria' => e.categoria, 'fechaNacimiento' => e.fechaNacimiento,
				'sumaAsegurada' => e.sumaAsegurada, 'prima' => e.prima, 'datos' => comoMapa(e)
			};
			if (e.titularIndex != null && e.titularIndex >= 0 && e.titularIndex < entrada.size()) {
				alta.put('titularNombre', nombreDe(entrada[e.titularIndex]));
				if (encontrado.containsKey(e.titularIndex)) { alta.put('titularId', encontrado.get(e.titularIndex)); }
				else { alta.put('titularRef', e.titularIndex); }
			}
			altasRes.add(alta);
		}

		List<Object> bajas = new List<Object>();
		if (censoCompleto == true) {
			for (Map<String, Object> a : base) {
				if (usados.contains((String) a.get('id'))) { continue; }
				bajas.add(new Map<String, Object>{
					'id' => a.get('id'), 'nombre' => a.get('nombre'), 'parentesco' => a.get('parentesco'),
					'certificado' => a.get('certificado'), 'titularId' => a.get('titularId'), 'titularNombre' => a.get('titularNombre')
				});
			}
		}
		return new Map<String, Object>{ 'altas' => altasRes, 'bajas' => bajas, 'cambios' => cambios, 'sinCambios' => sinCambios };
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
		for (Movimiento m : movs) {
			if (m.tipo != CAMBIO) { continue; }
			InsurancePolicyParticipant p = participantes.get(Id.valueOf(m.id));
			// Dependiente que salió con su titular en esta misma carga: ya no se cambia.
			if (p.IsActiveParticipant == false) { continue; }
			List<String> detalle = cambiarParticipante(p, m.datos, cats);
			if (m.datos.sumaAsegurada != null) {
				Decimal antes = sumasActuales.get(p.Id);
				if (antes != m.datos.sumaAsegurada) {
					detalle.add('Suma asegurada: ' + texto(antes) + ' → ' + texto(m.datos.sumaAsegurada));
					sumas.put(p.Id, m.datos.sumaAsegurada);
				}
			}
			if (detalle.isEmpty()) { continue; }
			actualizar.put(p.Id, p);
			Movimiento_Poliza__c r = registro(m, CAMBIO, CONTEXTO_ENDOSO, policyId, null, p.Id, p.ParticipantName, p.ParticipantCode);
			r.Detalle__c = String.join(detalle, '\n');
			registro.add(r);
			cambios++;
		}
		if (!actualizar.isEmpty()) { update actualizar.values(); }
		guardarSumas(policyId, sumas);

		// 3) Altas.
		Integer altas = altasPoliza(pol, movs, cats, registro);
		insert registro;
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
			if (m.datos.sumaAsegurada != null) { sumas.put(p.Id, m.datos.sumaAsegurada); }
			Movimiento_Poliza__c r = registro(m, ALTA, CONTEXTO_ENDOSO, pol.Id, null, p.Id, p.ParticipantName, p.ParticipantCode);
			r.Detalle__c = detalleAlta(m.datos);
			registro.add(r);
		}
		guardarSumas(pol.Id, sumas);
		return creados.size();
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
			+ ' RelationshipToInsured, Role, FechaNacimiento__c, Identificacion__c, TermPremiumAmount, EffectiveFromDate,'
			+ ' EffectiveToDate, IsActiveParticipant, Motivo_Baja__c, Categoria__c' + (TIENE_CLASE ? ', GroupClassId, GroupClass.Name' : '');
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
				'parentesco' => parentesco, 'sexo' => sexoDe(p.RelationshipToInsured), 'certificado' => p.ParticipantCode,
				'categoria' => nombreClase(p), 'fechaNacimiento' => p.FechaNacimiento__c, 'rfc' => p.Identificacion__c,
				'sumaAsegurada' => sumas.get(p.Id), 'prima' => p.TermPremiumAmount, 'fechaAlta' => p.EffectiveFromDate,
				'activo' => p.IsActiveParticipant != false,
				'fechaBaja' => p.IsActiveParticipant == false ? p.EffectiveToDate : null,
				'motivoBaja' => p.Motivo_Baja__c == null ? null : motivos.get(p.Motivo_Baja__c)
			});
		}
		return porFamilia(lista);
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
		List<Map<String, Object>> lista = new List<Map<String, Object>>();
		for (GroupCensusMember m : [
			SELECT Id, Name, PrimaryGroupCensusMemberId, PrimaryGroupCensusMember.Name, AssociationWithPrimaryMbr, Gender, Birthdate,
				Certificado__c, GroupClass.Name, Suma_Asegurada__c, Prima__c, RFC__c, JoinDate
			FROM GroupCensusMember WHERE GroupCensus.Oportunidad__c = :oppId
			ORDER BY Certificado__c NULLS LAST, Name LIMIT 10000
		]) {
			Boolean esTitular = m.PrimaryGroupCensusMemberId == null;
			lista.add(new Map<String, Object>{
				'id' => (String) m.Id, 'nombre' => m.Name, 'esTitular' => esTitular,
				'titularId' => esTitular ? null : (String) m.PrimaryGroupCensusMemberId,
				'titularNombre' => esTitular ? null : m.PrimaryGroupCensusMember.Name,
				'parentesco' => CensoColectivoController.parentescoVisible(m.AssociationWithPrimaryMbr, esTitular),
				'sexo' => m.Gender == null ? null : sexoVisible(sexos.get(m.Gender)), 'certificado' => m.Certificado__c,
				'categoria' => m.GroupClass == null ? null : m.GroupClass.Name, 'fechaNacimiento' => m.Birthdate, 'rfc' => m.RFC__c,
				'sumaAsegurada' => m.Suma_Asegurada__c, 'prima' => m.Prima__c, 'fechaAlta' => m.JoinDate, 'activo' => true
			});
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
				'id' => m.Id, 'nombre' => m.Name, 'tipo' => m.Tipo__c, 'asegurado' => m.Asegurado__c, 'certificado' => m.Certificado__c,
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
			if (m.tipo == BAJA && String.isBlank(m.motivo)) {
				throw CensoColectivoController.error('Indica el motivo de baja de cada asegurado.');
			}
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
			Certificado__c = certificado == null ? null : certificado.left(80), Fecha_Movimiento__c = CensoColectivoController.fecha(m.fecha),
			Numero_Endoso__c = String.isBlank(m.endoso) ? null : m.endoso.trim().left(80),
			Comentario__c = String.isBlank(m.comentario) ? null : m.comentario.trim().left(255));
		r.Tipo__c = tipo == ALTA ? 'Alta' : (tipo == BAJA ? 'Baja' : 'Cambio');
		if (tipo == BAJA) { r.Motivo_Baja__c = m.motivo; }
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
		return l;
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
