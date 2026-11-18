/**
 * @creation date: 15/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Busca si un asegurado, vehículo o ubicación ya existe en otras pólizas (de cualquier aseguradora). Lo
 *               usan las pestañas Asegurados, Vehículos y Ubicaciones de la póliza y de la oportunidad.
 *               - Asegurado (participante de póliza o integrante del censo): mismo contacto, mismo RFC o mismo nombre y
 *                 fecha de nacimiento.
 *               - Vehículo (inciso de flotilla): misma serie (o mismas placas si no tiene serie) o mismo bien del cliente.
 *               - Ubicación (bien de la póliza o renglón de la oportunidad): mismo bien del cliente o mismo domicilio.
 */
public inherited sharing class OtrasPolizasController {

	private static final Integer MAXIMO = 50;

	/**
	 * @creation date: 15/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Pólizas donde ya existe el registro, sin contar la póliza donde está.
	 * @param registroId: participante, integrante del censo, inciso de flotilla, bien de póliza o renglón de ubicaciones.
	 * @param contextoId: póliza u oportunidad donde se está viendo (para comparar la aseguradora).
	 * @return { registro, criterio, aseguradoraActual, polizas: [{ polizaId, poliza, aseguradora, otraAseguradora, ramo,
	 *         vigenciaInicio, vigenciaFin, estadoPoliza, detalle, vigente, fechaBaja, coincide }] }.
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> buscar(Id registroId, Id contextoId) {
		if (registroId == null) { throw CensoColectivoController.error('No se indicó el registro.'); }
		try {
			String tipo = registroId.getSObjectType().getDescribe().getName();
			Map<String, Object> res;
			if (tipo == 'InsurancePolicyParticipant') { res = deParticipante(registroId); }
			else if (tipo == 'GroupCensusMember') { res = deCenso(registroId); }
			else if (tipo == 'Inciso_Flotilla__c') { res = deVehiculo(registroId); }
			else if (tipo == 'InsurancePolicyAsset') { res = deBien(registroId); }
			else if (tipo == 'Categoria_Colectiva__c') { res = deRenglon(registroId); }
			else { throw CensoColectivoController.error('Este registro no se puede buscar en otras pólizas.'); }
			completar(res, contextoId);
			return res;
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			throw CensoColectivoController.error('No se pudo buscar en otras pólizas: ' + e.getMessage());
		}
	}

	// ============================================================
	// Asegurados
	// ============================================================

	private static Map<String, Object> deParticipante(Id id) {
		InsurancePolicyParticipant p = [
			SELECT Id, ParticipantName, InsurancePolicyId, PrimaryParticipantContactId, Identificacion__c, FechaNacimiento__c
			FROM InsurancePolicyParticipant WHERE Id = :id
		];
		return asegurado(p.ParticipantName, p.PrimaryParticipantContactId, p.Identificacion__c, p.FechaNacimiento__c,
			p.InsurancePolicyId, p.Id);
	}

	private static Map<String, Object> deCenso(Id id) {
		GroupCensusMember m = [SELECT Id, Name, ContactId, RFC__c, Birthdate FROM GroupCensusMember WHERE Id = :id];
		return asegurado(m.Name, m.ContactId, m.RFC__c, m.Birthdate, null, null);
	}

	private static Map<String, Object> asegurado(String nombre, Id contactoId, String rfc, Date nacimiento, Id polizaPropia, Id propio) {
		List<String> filtros = new List<String>();
		String rfcLimpio = String.isBlank(rfc) ? null : rfc.deleteWhitespace().toUpperCase();
		if (contactoId != null) { filtros.add('PrimaryParticipantContactId = :contactoId'); }
		if (rfcLimpio != null && rfcLimpio.length() >= 10) { filtros.add('Identificacion__c = :rfcLimpio'); }
		if (String.isNotBlank(nombre) && nacimiento != null) { filtros.add('(ParticipantName = :nombre AND FechaNacimiento__c = :nacimiento)'); }
		List<Map<String, Object>> polizas = new List<Map<String, Object>>();
		if (!filtros.isEmpty()) {
			String q = 'SELECT Id, ParticipantName, ParticipantCode, InsurancePolicyId, PrimaryParticipantContactId, Identificacion__c,'
				+ ' FechaNacimiento__c, IsActiveParticipant, EffectiveToDate FROM InsurancePolicyParticipant WHERE ('
				+ String.join(filtros, ' OR ') + ') AND InsurancePolicyId != :polizaPropia AND Id != :propio'
				+ ' ORDER BY CreatedDate DESC LIMIT ' + (MAXIMO * 2);
			Set<Id> vistas = new Set<Id>();
			for (InsurancePolicyParticipant x : (List<InsurancePolicyParticipant>) Database.query(q)) {
				if (vistas.contains(x.InsurancePolicyId)) { continue; }
				vistas.add(x.InsurancePolicyId);
				String coincide = contactoId != null && x.PrimaryParticipantContactId == contactoId ? 'Mismo contacto'
					: (rfcLimpio != null && x.Identificacion__c == rfcLimpio ? 'Mismo RFC' : 'Mismo nombre y fecha de nacimiento');
				polizas.add(new Map<String, Object>{
					'polizaId' => x.InsurancePolicyId, 'coincide' => coincide,
					'detalle' => x.ParticipantName + (String.isBlank(x.ParticipantCode) ? '' : ' · certificado ' + x.ParticipantCode),
					'vigente' => x.IsActiveParticipant != false, 'fechaBaja' => x.IsActiveParticipant == false ? x.EffectiveToDate : null
				});
			}
		}
		return new Map<String, Object>{
			'registro' => nombre, 'polizas' => polizas,
			'criterio' => 'Se buscó por contacto, RFC y nombre con fecha de nacimiento.'
				+ (filtros.isEmpty() ? ' Este asegurado no tiene contacto, RFC ni fecha de nacimiento para buscarlo.' : '')
		};
	}

	// ============================================================
	// Vehículos
	// ============================================================

	private static Map<String, Object> deVehiculo(Id id) {
		Inciso_Flotilla__c v = [
			SELECT Id, Serie__c, Placas__c, Descripcion__c, Modelo__c, Vehiculo__c, Poliza__c FROM Inciso_Flotilla__c WHERE Id = :id
		];
		Id polizaPropia = v.Poliza__c;
		String serie = String.isBlank(v.Serie__c) ? null : v.Serie__c.deleteWhitespace().toUpperCase();
		String placas = String.isBlank(v.Placas__c) ? null : v.Placas__c.trim().toUpperCase();
		Id bien = v.Vehiculo__c;
		List<String> filtros = new List<String>();
		if (serie != null) { filtros.add('Serie__c = :serie'); }
		else if (placas != null) { filtros.add('Placas__c = :placas'); }
		if (bien != null) { filtros.add('Vehiculo__c = :bien'); }
		List<Map<String, Object>> polizas = new List<Map<String, Object>>();
		Set<Id> vistas = new Set<Id>();
		if (!filtros.isEmpty()) {
			String q = 'SELECT Id, Numero_Inciso__c, Serie__c, Placas__c, Descripcion__c, Poliza__c, Fecha_Baja__c, Vehiculo__c'
				+ ' FROM Inciso_Flotilla__c WHERE (' + String.join(filtros, ' OR ') + ') AND Poliza__c != null'
				+ ' AND Poliza__c != :polizaPropia AND Id != :id ORDER BY CreatedDate DESC LIMIT ' + (MAXIMO * 2);
			for (Inciso_Flotilla__c x : (List<Inciso_Flotilla__c>) Database.query(q)) {
				if (vistas.contains(x.Poliza__c)) { continue; }
				vistas.add(x.Poliza__c);
				String coincide = serie != null && String.isNotBlank(x.Serie__c) && x.Serie__c.deleteWhitespace().toUpperCase() == serie
					? 'Misma serie' : (bien != null && x.Vehiculo__c == bien ? 'Mismo vehículo del cliente' : 'Mismas placas');
				polizas.add(new Map<String, Object>{
					'polizaId' => x.Poliza__c, 'coincide' => coincide,
					'detalle' => (x.Numero_Inciso__c == null ? '' : 'Inciso ' + x.Numero_Inciso__c + ' · ')
						+ (String.isBlank(x.Descripcion__c) ? 'Vehículo' : x.Descripcion__c)
						+ (String.isBlank(x.Placas__c) ? '' : ' · placas ' + x.Placas__c),
					'vigente' => x.Fecha_Baja__c == null, 'fechaBaja' => x.Fecha_Baja__c
				});
			}
		}
		// Pólizas que tienen el mismo vehículo como bien asegurado (sin inciso de flotilla).
		if (bien != null) {
			for (InsurancePolicyAsset a : [
				SELECT Id, AssetName, InsurancePolicyId, Fecha_Baja__c FROM InsurancePolicyAsset
				WHERE CustomerPropertyId = :bien AND InsurancePolicyId != :polizaPropia AND InsurancePolicyId NOT IN :vistas
				ORDER BY CreatedDate DESC LIMIT :MAXIMO
			]) {
				if (vistas.contains(a.InsurancePolicyId)) { continue; }
				vistas.add(a.InsurancePolicyId);
				polizas.add(new Map<String, Object>{
					'polizaId' => a.InsurancePolicyId, 'coincide' => 'Mismo vehículo del cliente', 'detalle' => a.AssetName,
					'vigente' => a.Fecha_Baja__c == null, 'fechaBaja' => a.Fecha_Baja__c
				});
			}
		}
		return new Map<String, Object>{
			'registro' => (String.isBlank(v.Descripcion__c) ? 'Vehículo' : v.Descripcion__c) + (serie == null ? '' : ' · ' + serie),
			'polizas' => polizas,
			'criterio' => serie != null ? 'Se buscó por número de serie.'
				: (placas != null ? 'El vehículo no tiene serie: se buscó por placas.' : 'El vehículo no tiene serie ni placas para buscarlo.')
		};
	}

	// ============================================================
	// Ubicaciones
	// ============================================================

	private static Map<String, Object> deBien(Id id) {
		InsurancePolicyAsset a = [
			SELECT Id, AssetName, InsurancePolicyId, CustomerPropertyId, CustomerProperty.Street, CustomerProperty.City,
				CustomerProperty.PostalCode
			FROM InsurancePolicyAsset WHERE Id = :id
		];
		String dir = a.CustomerProperty == null ? a.AssetName : unir(a.CustomerProperty.Street, a.CustomerProperty.City, a.CustomerProperty.PostalCode);
		return ubicacion(dir, a.CustomerPropertyId, a.CustomerProperty == null ? null : a.CustomerProperty.PostalCode, a.InsurancePolicyId, a.Id);
	}

	private static Map<String, Object> deRenglon(Id id) {
		Categoria_Colectiva__c c = [SELECT Id, Name, Direccion__c FROM Categoria_Colectiva__c WHERE Id = :id];
		return ubicacion(String.isBlank(c.Direccion__c) ? c.Name : c.Direccion__c, null, null, null, null);
	}

	private static Map<String, Object> ubicacion(String dir, Id bien, String cp, Id polizaPropia, Id propio) {
		String llave = llaveDomicilio(dir);
		if (String.isBlank(cp)) {
			Matcher m = Pattern.compile('\\b(\\d{5})\\b').matcher(dir == null ? '' : dir);
			if (m.find()) { cp = m.group(1); }
		}
		List<Map<String, Object>> polizas = new List<Map<String, Object>>();
		if (bien != null || String.isNotBlank(llave)) {
			String q = 'SELECT Id, AssetName, InsurancePolicyId, CustomerPropertyId, CustomerProperty.Street, CustomerProperty.City,'
				+ ' CustomerProperty.PostalCode, Fecha_Baja__c FROM InsurancePolicyAsset WHERE InsurancePolicyId != :polizaPropia'
				+ ' AND Id != :propio AND CustomerPropertyId != null'
				+ (String.isNotBlank(cp) ? ' AND (CustomerPropertyId = :bien OR CustomerProperty.PostalCode = :cp OR CustomerProperty.Street LIKE :cpLike)'
					: (bien != null ? ' AND CustomerPropertyId = :bien' : ''))
				+ ' ORDER BY CreatedDate DESC LIMIT 2000';
			String cpLike = '%' + cp + '%';
			Set<Id> vistas = new Set<Id>();
			for (InsurancePolicyAsset x : (List<InsurancePolicyAsset>) Database.query(q)) {
				if (vistas.contains(x.InsurancePolicyId) || polizas.size() >= MAXIMO) { continue; }
				String otra = llaveDomicilio(unir(x.CustomerProperty.Street, x.CustomerProperty.City, x.CustomerProperty.PostalCode));
				Boolean mismoBien = bien != null && x.CustomerPropertyId == bien;
				if (!mismoBien && !mismoDomicilio(llave, otra, llaveDomicilio(x.CustomerProperty.Street))) { continue; }
				vistas.add(x.InsurancePolicyId);
				polizas.add(new Map<String, Object>{
					'polizaId' => x.InsurancePolicyId, 'coincide' => mismoBien ? 'Mismo bien del cliente' : 'Mismo domicilio',
					'detalle' => x.AssetName, 'vigente' => x.Fecha_Baja__c == null, 'fechaBaja' => x.Fecha_Baja__c
				});
			}
		}
		return new Map<String, Object>{
			'registro' => dir, 'polizas' => polizas,
			'criterio' => 'Se buscó por domicilio' + (String.isNotBlank(cp) ? ' (código postal ' + cp + ')' : '') + '.'
		};
	}

	// El domicilio coincide completo o uno empieza con el otro (la calle y número contra el domicilio completo).
	private static Boolean mismoDomicilio(String llave, String otra, String calle) {
		if (String.isBlank(llave) || String.isBlank(otra)) { return false; }
		if (llave == otra || llave.startsWith(otra) || otra.startsWith(llave)) { return true; }
		return String.isNotBlank(calle) && calle.length() >= 8 && llave.startsWith(calle);
	}

	private static String unir(String a, String b, String c) {
		List<String> l = new List<String>();
		for (String x : new List<String>{ a, b, c }) { if (String.isNotBlank(x) && (l.isEmpty() || !l[0].contains(x))) { l.add(x.trim()); } }
		return String.join(l, ', ');
	}

	// Domicilio comparable: sin acentos, signos, "C.P." ni palabras de relleno ("No.", "Num.", "Col.").
	@TestVisible
	private static String llaveDomicilio(String v) {
		if (String.isBlank(v)) { return ''; }
		String s = v.toLowerCase();
		Map<String, String> acentos = new Map<String, String>{ 'á' => 'a', 'é' => 'e', 'í' => 'i', 'ó' => 'o', 'ú' => 'u', 'ü' => 'u', 'ñ' => 'n' };
		for (String k : acentos.keySet()) { s = s.replace(k, acentos.get(k)); }
		s = s.replaceAll('[^a-z0-9]+', ' ');
		s = (' ' + s + ' ').replaceAll(' (c p|cp|codigo postal|no|num|numero|col|colonia|int|ext|interior|exterior) ', ' ');
		s = s.replaceAll(' (c p|cp|codigo postal|no|num|numero|col|colonia|int|ext|interior|exterior) ', ' ');
		return s.replaceAll('\\s+', '');
	}

	// ============================================================
	// Datos de las pólizas
	// ============================================================

	private static void completar(Map<String, Object> res, Id contextoId) {
		Id aseguradoraActual = null;
		String nombreActual = null;
		if (contextoId != null && contextoId.getSObjectType() == InsurancePolicy.SObjectType) {
			for (InsurancePolicy p : [SELECT Aseguradora__c, Aseguradora__r.Name FROM InsurancePolicy WHERE Id = :contextoId]) {
				aseguradoraActual = p.Aseguradora__c;
				nombreActual = p.Aseguradora__c == null ? null : p.Aseguradora__r.Name;
			}
		}
		res.put('aseguradoraActual', nombreActual);
		List<Map<String, Object>> l = (List<Map<String, Object>>) res.get('polizas');
		Set<Id> ids = new Set<Id>();
		for (Map<String, Object> x : l) { ids.add((Id) x.get('polizaId')); }
		Map<Id, InsurancePolicy> pols = new Map<Id, InsurancePolicy>([
			SELECT Id, Name, Aseguradora__c, Aseguradora__r.Name, toLabel(Ramo__c), EffectiveDate, ExpirationDate, Status
			FROM InsurancePolicy WHERE Id IN :ids
		]);
		List<Map<String, Object>> salida = new List<Map<String, Object>>();
		for (Map<String, Object> x : l) {
			InsurancePolicy p = pols.get((Id) x.get('polizaId'));
			if (p == null) { continue; }
			x.put('poliza', p.Name);
			x.put('aseguradora', p.Aseguradora__c == null ? null : p.Aseguradora__r.Name);
			x.put('otraAseguradora', aseguradoraActual != null && p.Aseguradora__c != null && p.Aseguradora__c != aseguradoraActual);
			x.put('ramo', p.Ramo__c);
			x.put('vigenciaInicio', p.EffectiveDate == null ? null : p.EffectiveDate.date());
			x.put('vigenciaFin', p.ExpirationDate == null ? null : p.ExpirationDate.date());
			x.put('estadoPoliza', p.Status);
			x.put('orden', p.EffectiveDate);
			salida.add(x);
		}
		// Más reciente primero.
		List<Ordenable> o = new List<Ordenable>();
		for (Map<String, Object> x : salida) { o.add(new Ordenable(x)); }
		o.sort();
		List<Map<String, Object>> ordenadas = new List<Map<String, Object>>();
		for (Ordenable x : o) {
			x.fila.remove('orden');
			if (ordenadas.size() < MAXIMO) { ordenadas.add(x.fila); }
		}
		res.put('polizas', ordenadas);
	}

	private class Ordenable implements Comparable {
		Map<String, Object> fila;
		Ordenable(Map<String, Object> f) { fila = f; }
		public Integer compareTo(Object other) {
			Datetime a = (Datetime) fila.get('orden');
			Datetime b = (Datetime) ((Ordenable) other).fila.get('orden');
			if (a == b) { return 0; }
			if (a == null) { return 1; }
			if (b == null) { return -1; }
			return a > b ? -1 : 1;
		}
	}
}
