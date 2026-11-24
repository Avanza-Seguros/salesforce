/**
 * @creation date: 23/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Elimina un registro (movimiento) o toda una solicitud de la póliza, solo desde Salesforce y solo lo que no
 *               está Concluido (Solicitado, En proceso o Rechazado). Deshace lo que hizo cada movimiento:
 *               - Alta: el asegurado (con sus dependientes de esa misma solicitud), el vehículo o la ubicación se quita de
 *                 la póliza. El contacto, el bien del cliente y sus documentos se conservan.
 *               - Baja: el registro vuelve a quedar vigente (con los dependientes que salieron con su titular).
 *               - Cambio: solo se borra el movimiento; los datos se quedan como están.
 *               Todo o nada. No se elimina lo que tiene movimientos posteriores, endoso de la aseguradora o renovación. La
 *               solicitud del sitio que se queda sin movimientos se cierra con un comentario y ya no se muestra. Queda una
 *               tarea en la póliza con lo que se eliminó.
 *               Sin sharing: quien la llama (MovimientosColectivoController) valida el acceso a la póliza.
 */
public without sharing class EliminarMovimientos {

	public static final String COMENTARIO_CASO = 'Solicitud eliminada';

	private Id policyId;
	private InsurancePolicy pol;
	// Todos los movimientos de la póliza (el más reciente primero) y los que se eliminan.
	private List<Movimiento_Poliza__c> todos;
	private Map<Id, Movimiento_Poliza__c> elegidos = new Map<Id, Movimiento_Poliza__c>();
	private Map<Id, Integer> orden = new Map<Id, Integer>();

	/**
	 * @creation date: 23/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Elimina un movimiento o todos los de una solicitud.
	 * @param policyId: póliza.
	 * @param folio: solicitud (SOL-0001...).
	 * @param movimientoId: movimiento, o null para toda la solicitud.
	 * @return lo que se hizo, para la pantalla.
	 */
	public static String eliminar(Id policyId, String folio, Id movimientoId) {
		if (UserInfo.getUserType() != 'Standard') { throw new EliminarException('Solo un ejecutivo puede eliminar movimientos.'); }
		// La carga inicial no es una solicitud.
		if (folio == null || !folio.startsWith('SOL-')) { throw new EliminarException('Solo se eliminan los movimientos de una solicitud.'); }
		Savepoint sp = Database.setSavepoint();
		try {
			return new EliminarMovimientos(policyId).ejecutar(folio, movimientoId);
		} catch (Exception e) {
			Database.rollback(sp);
			throw e;
		}
	}

	private EliminarMovimientos(Id policyId) {
		this.policyId = policyId;
		pol = [SELECT Id, Name, ExpirationDate FROM InsurancePolicy WHERE Id = :policyId];
		todos = [
			SELECT Id, Name, Solicitud__c, Tipo__c, Asegurado__c, Detalle__c, Fecha_Cierre__c, Seguimiento__c, Transaccion__c, CreatedDate,
				Inciso__c, Participante__c, Participante__r.RelatedInsPolicyParticipantId
			FROM Movimiento_Poliza__c WHERE Poliza__c = :policyId AND Oportunidad__c = null ORDER BY CreatedDate DESC, Id DESC LIMIT 10000
		];
		for (Integer i = 0; i < todos.size(); i++) { orden.put(todos[i].Id, i); }
	}

	private String ejecutar(String folio, Id movimientoId) {
		for (Movimiento_Poliza__c m : todos) {
			if (m.Solicitud__c == folio && (movimientoId == null || m.Id == movimientoId)) { elegidos.put(m.Id, m); }
		}
		if (movimientoId != null && elegidos.isEmpty()) { throw new EliminarException('El movimiento ya no existe.'); }
		agregarDependientes(folio);
		validar(movimientoId == null);

		Map<String, Set<Id>> participantes = new Map<String, Set<Id>>{ 'Alta' => new Set<Id>(), 'Baja' => new Set<Id>(), 'Cambio' => new Set<Id>() };
		Map<String, Set<Id>> incisos = new Map<String, Set<Id>>{ 'Alta' => new Set<Id>(), 'Baja' => new Set<Id>() };
		Map<String, Set<String>> direcciones = new Map<String, Set<String>>{ 'Alta' => new Set<String>(), 'Baja' => new Set<String>() };
		for (Movimiento_Poliza__c m : elegidos.values()) {
			if (m.Participante__c != null) { participantes.get(m.Tipo__c).add(m.Participante__c); }
			else if (m.Tipo__c == 'Cambio') { continue; }
			else if (m.Inciso__c != null) { incisos.get(m.Tipo__c).add(m.Inciso__c); }
			else if (String.isNotBlank(m.Asegurado__c)) { direcciones.get(m.Tipo__c).add(PolicyController.llaveDireccion(m.Asegurado__c)); }
		}
		// Lo que entra y sale en la misma solicitud (alta y baja) se quita.
		participantes.get('Baja').removeAll(participantes.get('Alta'));
		participantes.get('Cambio').removeAll(participantes.get('Alta'));
		participantes.get('Cambio').removeAll(participantes.get('Baja'));
		incisos.get('Baja').removeAll(incisos.get('Alta'));
		direcciones.get('Baja').removeAll(direcciones.get('Alta'));
		List<String> hechos = new List<String>();
		for (Movimiento_Poliza__c m : elegidos.values()) { hechos.add(m.Tipo__c + ': ' + (m.Asegurado__c == null ? m.Name : m.Asegurado__c)); }

		reactivarPersonas(participantes.get('Baja'));
		correoComoAntes(participantes.get('Cambio'));
		reactivarBienes(incisos.get('Baja'), direcciones.get('Baja'));
		delete elegidos.values();
		quitarPersonas(participantes.get('Alta'));
		quitarBienes(incisos.get('Alta'), direcciones.get('Alta'));
		cerrarSolicitud(folio);
		dejarTarea(folio, movimientoId == null, hechos);

		Integer n = elegidos.size();
		return (movimientoId == null ? 'Se eliminó el movimiento ' + numero(folio) : 'Se eliminó el registro')
			+ (n > 1 || movimientoId == null ? ' (' + n + (n == 1 ? ' registro).' : ' registros).') : '.');
	}

	// El alta o la baja de un titular se elimina con las de sus dependientes en la misma solicitud.
	private void agregarDependientes(String folio) {
		Map<String, Set<Id>> titulares = new Map<String, Set<Id>>{ 'Alta' => new Set<Id>(), 'Baja' => new Set<Id>() };
		for (Movimiento_Poliza__c m : elegidos.values()) {
			if (m.Participante__c != null && titulares.containsKey(m.Tipo__c)) { titulares.get(m.Tipo__c).add(m.Participante__c); }
		}
		for (Movimiento_Poliza__c m : todos) {
			if (m.Solicitud__c != folio || m.Participante__c == null || !titulares.containsKey(m.Tipo__c)) { continue; }
			if (titulares.get(m.Tipo__c).contains(m.Participante__r.RelatedInsPolicyParticipantId)) { elegidos.put(m.Id, m); }
		}
	}

	private void validar(Boolean completa) {
		Integer concluidos = 0;
		for (Movimiento_Poliza__c m : elegidos.values()) {
			if (m.Fecha_Cierre__c != null && m.Seguimiento__c != 'Rechazado') { concluidos++; }
			if (m.Transaccion__c != null) { throw new EliminarException(quien(m) + ' ya tiene el endoso de la aseguradora: no se puede eliminar.'); }
			if (m.Tipo__c == 'Alta' && m.Detalle__c != null && m.Detalle__c.startsWith('Reingreso')) {
				throw new EliminarException(quien(m) + ' es un reingreso: para quitarlo, dalo de baja.');
			}
		}
		if (concluidos > 0) {
			throw new EliminarException(concluidos == 1 && elegidos.size() == 1 ? 'El registro está Concluido: regrésalo primero a En proceso.'
				: 'Tiene ' + concluidos + (concluidos == 1 ? ' registro Concluido' : ' registros Concluidos') + ': regrésalos primero a En proceso'
					+ (completa ? ' o elimina los demás uno por uno.' : '.'));
		}
		// Movimientos posteriores del mismo registro (de otra solicitud): primero se eliminan esos.
		Map<String, Movimiento_Poliza__c> deshacer = new Map<String, Movimiento_Poliza__c>();
		for (Movimiento_Poliza__c m : elegidos.values()) {
			String k = llave(m);
			if (m.Tipo__c == 'Cambio' || k == null) { continue; }
			if (!deshacer.containsKey(k) || anterior(m, deshacer.get(k))) { deshacer.put(k, m); }
		}
		for (Movimiento_Poliza__c m : todos) {
			String k = llave(m);
			if (k == null || elegidos.containsKey(m.Id) || !deshacer.containsKey(k) || anterior(m, deshacer.get(k))) { continue; }
			throw new EliminarException(quien(m) + ' tiene un movimiento posterior (' + m.Tipo__c.toLowerCase()
				+ (m.Solicitud__c == null ? '' : ' del movimiento ' + numero(m.Solicitud__c)) + '): elimínalo primero.');
		}
	}

	// El orden es el de la consulta (el más reciente primero).
	private Boolean anterior(Movimiento_Poliza__c a, Movimiento_Poliza__c b) { return orden.get(a.Id) > orden.get(b.Id); }

	private static String llave(Movimiento_Poliza__c m) {
		if (m.Participante__c != null) { return m.Participante__c; }
		if (m.Inciso__c != null) { return m.Inciso__c; }
		return String.isBlank(m.Asegurado__c) ? null : 'D:' + PolicyController.llaveDireccion(m.Asegurado__c);
	}

	private static String quien(Movimiento_Poliza__c m) { return m.Asegurado__c == null ? 'El registro ' + m.Name : m.Asegurado__c; }

	// ===== Altas =====
	private void quitarPersonas(Set<Id> ids) {
		if (ids.isEmpty()) { return; }
		for (InsurancePolicyParticipant d : [
			SELECT ParticipantName, RelatedInsPolicyParticipant.ParticipantName FROM InsurancePolicyParticipant
			WHERE RelatedInsPolicyParticipantId IN :ids AND Id NOT IN :ids LIMIT 1
		]) {
			throw new EliminarException(d.RelatedInsPolicyParticipant.ParticipantName + ' tiene a ' + d.ParticipantName
				+ ', que no es de este movimiento: quítalo primero.');
		}
		for (InsurancePolicyParticipant r : [
			SELECT ParticipantName, InsurancePolicy.Name FROM InsurancePolicyParticipant
			WHERE (PriorParticipantId IN :ids OR OriginalParticipantId IN :ids) AND Id NOT IN :ids LIMIT 1
		]) {
			throw new EliminarException(r.ParticipantName + ' ya está en la renovación (' + r.InsurancePolicy.Name + '): no se puede eliminar.');
		}
		delete [SELECT Id FROM InsurancePolicyCoverage WHERE InsurancePolicyParticipantId IN :ids];
		delete [SELECT Id FROM InsurancePolicyParticipant WHERE Id IN :ids AND InsurancePolicyId = :policyId AND RelatedInsPolicyParticipantId != null];
		delete [SELECT Id FROM InsurancePolicyParticipant WHERE Id IN :ids AND InsurancePolicyId = :policyId];
	}

	private void quitarBienes(Set<Id> incisos, Set<String> direcciones) {
		Set<Id> bienes = bienesDe(incisos, direcciones);
		if (!bienes.isEmpty()) {
			delete [SELECT Id FROM InsurancePolicyCoverage WHERE InsurancePolicyAssetId IN :bienes];
			delete [SELECT Id FROM InsurancePolicyAsset WHERE Id IN :bienes];
		}
		if (incisos.isEmpty()) { return; }
		List<Inciso_Flotilla__c> desligar = new List<Inciso_Flotilla__c>();
		List<Inciso_Flotilla__c> borrar = new List<Inciso_Flotilla__c>();
		for (Inciso_Flotilla__c i : [SELECT Id, Oportunidad__c FROM Inciso_Flotilla__c WHERE Id IN :incisos AND Poliza__c = :policyId]) {
			// El que también está en el censo de una oportunidad solo sale de la póliza.
			if (i.Oportunidad__c == null) { borrar.add(i); } else { desligar.add(new Inciso_Flotilla__c(Id = i.Id, Poliza__c = null)); }
		}
		delete borrar;
		update desligar;
	}

	// ===== Bajas =====
	private void reactivarPersonas(Set<Id> ids) {
		if (ids.isEmpty()) { return; }
		List<InsurancePolicyParticipant> l = new List<InsurancePolicyParticipant>();
		Set<String> nombres = new Set<String>();
		for (InsurancePolicyParticipant p : [
			SELECT Id, ParticipantName, ParticipantCode, Fecha_Envio_Correo__c, RelatedInsPolicyParticipantId,
				RelatedInsPolicyParticipant.IsActiveParticipant, RelatedInsPolicyParticipant.ParticipantName
			FROM InsurancePolicyParticipant WHERE Id IN :ids AND InsurancePolicyId = :policyId
		]) {
			if (p.RelatedInsPolicyParticipantId != null && p.RelatedInsPolicyParticipant.IsActiveParticipant == false
					&& !ids.contains(p.RelatedInsPolicyParticipantId)) {
				throw new EliminarException('El titular de ' + p.ParticipantName + ' (' + p.RelatedInsPolicyParticipant.ParticipantName
					+ ') está dado de baja: elimina primero su baja.');
			}
			nombres.add(CensoColectivoController.llaveParticipante(p.ParticipantCode, p.ParticipantName));
			l.add(new InsurancePolicyParticipant(Id = p.Id, IsActiveParticipant = true, Motivo_Baja__c = null, Correo_Personal__c = null,
				EffectiveToDate = pol.ExpirationDate == null ? null : pol.ExpirationDate.date(), ExpirationDate = pol.ExpirationDate,
				// El correo vuelve a como estaba antes de la baja.
				Correo_Enviado__c = p.Fecha_Envio_Correo__c != null));
		}
		for (InsurancePolicyParticipant p : [
			SELECT ParticipantName, ParticipantCode FROM InsurancePolicyParticipant
			WHERE InsurancePolicyId = :policyId AND IsActiveParticipant = true AND Id NOT IN :ids LIMIT 10000
		]) {
			if (nombres.contains(CensoColectivoController.llaveParticipante(p.ParticipantCode, p.ParticipantName))) {
				throw new EliminarException(p.ParticipantName + ' ya se volvió a dar de alta en la póliza: su baja no se puede eliminar.');
			}
		}
		update l;
	}

	private void reactivarBienes(Set<Id> incisos, Set<String> direcciones) {
		List<Inciso_Flotilla__c> li = new List<Inciso_Flotilla__c>();
		for (Id i : incisos) { li.add(new Inciso_Flotilla__c(Id = i, Fecha_Baja__c = null, Motivo_Baja__c = null)); }
		update li;
		List<InsurancePolicyAsset> la = new List<InsurancePolicyAsset>();
		for (Id a : bienesDe(incisos, direcciones)) {
			la.add(new InsurancePolicyAsset(Id = a, IsActive = true, Fecha_Baja__c = null, Motivo_Baja__c = null,
				EffectiveToDate = pol.ExpirationDate == null ? null : pol.ExpirationDate.date()));
		}
		update la;
	}

	// ===== Cambios: los datos se quedan; el correo ya enviado deja de estar pendiente por ese cambio. =====
	private void correoComoAntes(Set<Id> ids) {
		if (ids.isEmpty()) { return; }
		List<InsurancePolicyParticipant> l = new List<InsurancePolicyParticipant>();
		for (InsurancePolicyParticipant p : [
			SELECT Id FROM InsurancePolicyParticipant WHERE Id IN :ids AND Correo_Enviado__c = false AND Fecha_Envio_Correo__c != null
		]) { l.add(new InsurancePolicyParticipant(Id = p.Id, Correo_Enviado__c = true)); }
		update l;
	}

	// Bienes de la póliza de los incisos (por su vehículo) o de las ubicaciones (por su domicilio).
	private Set<Id> bienesDe(Set<Id> incisos, Set<String> direcciones) {
		Set<Id> r = new Set<Id>();
		if (incisos.isEmpty() && direcciones.isEmpty()) { return r; }
		Set<Id> vehiculos = new Set<Id>();
		if (!incisos.isEmpty()) {
			for (Inciso_Flotilla__c i : [SELECT Vehiculo__c FROM Inciso_Flotilla__c WHERE Id IN :incisos AND Vehiculo__c != null]) { vehiculos.add(i.Vehiculo__c); }
		}
		for (InsurancePolicyAsset a : [
			SELECT Id, CustomerPropertyId, CustomerProperty.Name, CustomerProperty.Street, CustomerProperty.City, CustomerProperty.PostalCode
			FROM InsurancePolicyAsset WHERE InsurancePolicyId = :policyId AND CustomerPropertyId != null
		]) {
			if (vehiculos.contains(a.CustomerPropertyId) || (!direcciones.isEmpty() && direcciones.contains(PolicyController.llaveBien(a.CustomerProperty)))) {
				r.add(a.Id);
			}
		}
		return r;
	}

	// ===== Solicitud =====
	// Sin movimientos, el caso del sitio se cierra y la solicitud ya no se muestra; con los demás ya cerrados, se concluye.
	private void cerrarSolicitud(String folio) {
		Set<Id> quedan = new Set<Id>();
		Boolean abiertos = false;
		for (Movimiento_Poliza__c m : todos) {
			if (m.Solicitud__c != folio || elegidos.containsKey(m.Id)) { continue; }
			quedan.add(m.Id);
			abiertos = abiertos || m.Fecha_Cierre__c == null;
		}
		if (!quedan.isEmpty()) {
			if (!abiertos && !elegidos.isEmpty()) { EndosoPoliza.aprobarCerrados(quedan); }
			return;
		}
		Id rt = EndosoPoliza.tipoCaso();
		if (rt == null) { return; }
		for (Case c : [SELECT Id, IsClosed FROM Case WHERE RecordTypeId = :rt AND InsurancePolicy__c = :policyId AND Solicitud__c = :folio]) {
			if (!c.IsClosed) { update new Case(Id = c.Id, Status = EndosoPoliza.estadoCaso('Concluido')); }
			insert new CaseComment(ParentId = c.Id, IsPublished = true, CommentBody = COMENTARIO_CASO + ' por ' + UserInfo.getName() + '.');
		}
	}

	private void dejarTarea(String folio, Boolean completa, List<String> hechos) {
		Database.insert(new Task(WhatId = policyId, Status = 'Completed', ActivityDate = Date.today(), Priority = 'Normal',
			Subject = ((completa ? 'Movimiento eliminado' : 'Registro eliminado') + ' · ' + numero(folio) + ' · ' + pol.Name).left(255),
			Description = String.join(hechos, '\n').left(32000)), false);
	}

	private static String numero(String folio) { return folio == null ? '' : folio.replace('SOL-', ''); }

	public class EliminarException extends Exception {}
}
