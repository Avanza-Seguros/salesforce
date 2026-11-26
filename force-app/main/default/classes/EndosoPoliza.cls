/**
 * @creation date: 14/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Endosos de una póliza con los objetos estándar de Financial Services Cloud. Cada vez que se aplican
 *               movimientos en la póliza (altas, bajas o cambios de asegurados, vehículos o ubicaciones) se registra
 *               una transacción de póliza (InsurancePolicyTransaction, categoría Endorsement) con el número, la fecha
 *               y la prima del endoso tal como la da la aseguradora, y un detalle (InsPolicyTransactionDetail) por
 *               cada registro que tocó el endoso. Los movimientos (Movimiento_Poliza__c) quedan ligados a ella.
 *               Si el endoso ya existe (mismo número en la póliza), se le agregan los movimientos.
 */
public inherited sharing class EndosoPoliza {

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Prima del endoso como viene en el documento de la aseguradora (todo opcional).
	 */
	public class Prima {
		public Decimal primaNeta;
		public Decimal derechos;
		public Decimal iva;
		public Decimal total;
	}

	// Transacción de cada número de endoso que registró la última llamada a registrarTodos (para adjuntar su documento).
	public static Map<String, Id> ultimosPorNumero = new Map<String, Id>();

	// Movimientos de póliza insertados en la transacción de Apex en curso (los agrega cada controlador).
	@TestVisible
	private static List<Movimiento_Poliza__c> insertados = new List<Movimiento_Poliza__c>();

	public static void agregar(List<Movimiento_Poliza__c> registros) {
		if (registros != null) { insertados.addAll(registros); }
	}

	/**
	 * @description: Los movimientos llegan como lista (forma anterior) o como { movimientos: [...], endoso: {...} }.
	 * @return la lista de movimientos en JSON.
	 */
	public static String movimientos(String json) {
		if (String.isBlank(json) || !json.trim().startsWith('{')) { return json; }
		Map<String, Object> m = (Map<String, Object>) System.JSON.deserializeUntyped(json);
		return System.JSON.serialize(m.containsKey('movimientos') ? m.get('movimientos') : new List<Object>());
	}

	/**
	 * @return la prima del endoso que viene en el JSON, o null.
	 */
	public static Prima prima(String json) {
		if (String.isBlank(json) || !json.trim().startsWith('{')) { return null; }
		Map<String, Object> m = (Map<String, Object>) System.JSON.deserializeUntyped(json);
		if (m.get('endoso') == null) { return null; }
		return (Prima) System.JSON.deserialize(System.JSON.serialize(m.get('endoso')), Prima.class);
	}

	/**
	 * @creation date: 15/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Prima de cada endoso cuando el JSON trae { endosos: { 'número': { primaNeta, derechos, iva, total } } }.
	 * @return mapa número de endoso -> prima (vacío si no viene).
	 */
	public static Map<String, Prima> primas(String json) {
		Map<String, Prima> res = new Map<String, Prima>();
		if (String.isBlank(json) || !json.trim().startsWith('{')) { return res; }
		Map<String, Object> m = (Map<String, Object>) System.JSON.deserializeUntyped(json);
		if (!(m.get('endosos') instanceof Map<String, Object>)) { return res; }
		Map<String, Object> e = (Map<String, Object>) m.get('endosos');
		for (String k : e.keySet()) {
			if (e.get(k) == null || String.isBlank(k)) { continue; }
			res.put(k.trim(), (Prima) System.JSON.deserialize(System.JSON.serialize(e.get(k)), Prima.class));
		}
		return res;
	}

	/**
	 * @creation date: 17/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Solicitud del cliente a la que se agregan los movimientos cuando el JSON trae { solicitud: 'SOL-0003' }
	 *               ('nueva' o vacío = solicitud nueva).
	 * @return el folio pedido, o null.
	 */
	public static String solicitud(String json) {
		if (String.isBlank(json) || !json.trim().startsWith('{')) { return null; }
		Map<String, Object> m = (Map<String, Object>) System.JSON.deserializeUntyped(json);
		Object s = m.get('solicitud');
		return s == null || String.isBlank(String.valueOf(s)) ? null : String.valueOf(s).trim();
	}

	/**
	 * @creation date: 17/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Pone el folio de la solicitud del cliente a los movimientos insertados en esta transacción de Apex
	 *               (llamar antes de registrar/registrarTodos). Si el folio pedido existe en la póliza, se agregan a esa
	 *               solicitud; si no, se abre una nueva con el siguiente folio de la póliza (SOL-0001, SOL-0002...).
	 * @param policyId: póliza.
	 * @param pedida: folio de una solicitud de la póliza, o null / 'nueva'.
	 * @return el folio de la solicitud, o null si no hubo movimientos.
	 */
	public static String asignarSolicitud(Id policyId, String pedida) {
		List<Movimiento_Poliza__c> l = new List<Movimiento_Poliza__c>();
		for (Movimiento_Poliza__c m : insertados) {
			if (m.Id != null) { l.add(new Movimiento_Poliza__c(Id = m.Id)); }
		}
		if (l.isEmpty() || policyId == null) { return null; }
		String folio = null;
		if (String.isNotBlank(pedida) && !pedida.equalsIgnoreCase('nueva')) {
			// Folio de la póliza: de movimientos ya registrados o de un caso que el cliente envió desde el sitio.
			List<Case> casos = new SinCompartir().casosDeFolio(policyId, pedida);
			if (!casos.isEmpty() || [SELECT COUNT() FROM Movimiento_Poliza__c WHERE Poliza__c = :policyId AND Solicitud__c = :pedida] > 0) {
				folio = pedida;
			}
			// El estatus del caso no cambia aquí: el ejecutivo lo cambia a mano en el seguimiento.
		}
		if (folio == null) { folio = siguienteFolio(policyId); }
		Boolean existente = folio == pedida;
		// Agregar registros a un movimiento no le cambia el estatus.
		if (existente) { fijarEstatus(policyId, new Set<String>{ folio }); }
		for (Movimiento_Poliza__c m : l) {
			m.Solicitud__c = folio;
			if (!existente) { m.Seguimiento_Solicitud__c = 'En proceso'; }
		}
		update l;
		return folio;
	}

	/**
	 * @creation date: 17/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Siguiente folio de solicitud de la póliza (SOL-0001, SOL-0002...), contando los de los movimientos y
	 *               los de los casos que el cliente envió desde el sitio.
	 * @param policyId: póliza.
	 * @return folio.
	 */
	public static String siguienteFolio(Id policyId) {
		Integer max = 0;
		List<String> folios = new List<String>();
		for (AggregateResult ar : [
			SELECT Solicitud__c s FROM Movimiento_Poliza__c WHERE Poliza__c = :policyId AND Solicitud__c LIKE 'SOL-%' GROUP BY Solicitud__c
		]) { folios.add((String) ar.get('s')); }
		for (Case c : new SinCompartir().casos(policyId)) { folios.add(c.Solicitud__c); }
		for (String f : folios) {
			String n = f == null ? '' : f.substringAfter('SOL-');
			if (n.isNumeric() && Integer.valueOf(n) > max) { max = Integer.valueOf(n); }
		}
		return 'SOL-' + String.valueOf(max + 1).leftPad(4, '0');
	}

	/**
	 * @creation date: 17/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valor de estado de caso que corresponde (los orgs no tienen los mismos): 'Creado' (el inicial),
	 *               'Solicitado' (o el inicial si el org no lo tiene), 'En proceso' (abierto que no es el inicial) o
	 *               'Concluido' (cerrado, sin contar Merged).
	 * @param buscado: 'Creado', 'Solicitado', 'En proceso' o 'Concluido'.
	 * @return el valor del org, o null.
	 */
	public static String estadoCaso(String buscado) {
		String inicial;
		String abierto;
		String cerrado;
		for (CaseStatus s : [SELECT ApiName, IsClosed, IsDefault FROM CaseStatus ORDER BY SortOrder]) {
			if (s.ApiName == buscado) { return s.ApiName; }
			if (s.IsDefault && inicial == null) { inicial = s.ApiName; }
			else if (!s.IsClosed && s.ApiName != 'Solicitado' && abierto == null) { abierto = s.ApiName; }
			else if (s.IsClosed && s.ApiName != 'Merged' && cerrado == null) { cerrado = s.ApiName; }
		}
		return buscado == 'Creado' || buscado == 'Solicitado' ? inicial : (buscado == 'Concluido' ? cerrado : abierto);
	}

	/**
	 * @creation date: 17/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Solicitudes del cliente de la póliza (más reciente primero): folio, fecha en que se registró,
	 *               quién la registró, cuántos movimientos tiene (altas, bajas y cambios), cuántos siguen abiertos y sus
	 *               números de endoso. Las que el cliente envió desde el sitio (casos) traen además el caso, quién la
	 *               envió, lo que pidió, su comentario, sus archivos y su estado (Recibida, En proceso, Cerrada o Rechazada).
	 * @param policyId: póliza.
	 * @param ramo: 'asegurados', 'vehiculos' o 'ubicaciones' (solo las solicitudes de ese ramo).
	 * @return lista de solicitudes como mapas.
	 */
	public static List<Map<String, Object>> solicitudes(Id policyId, String ramo) {
		Map<String, Map<String, Object>> porFolio = new Map<String, Map<String, Object>>();
		if (policyId == null) { return new List<Map<String, Object>>(); }
		// El folio de la aseguradora solo se muestra en Salesforce.
		Boolean interno = UserInfo.getUserType() == 'Standard';
		// Total de cada endoso y las solicitudes de sus movimientos.
		Map<Id, Decimal> totalEndoso = new Map<Id, Decimal>();
		Map<Id, Set<String>> foliosEndoso = new Map<Id, Set<String>>();
		// Sin compartir: el cliente del sitio también ve el avance de sus solicitudes.
		for (Movimiento_Poliza__c m : new SinCompartir().movimientos(policyId)) {
			String r = m.Participante__c != null ? 'asegurados' : (m.Inciso__c != null ? 'vehiculos' : 'ubicaciones');
			if (String.isNotBlank(ramo) && r != ramo) { continue; }
			Map<String, Object> s = porFolio.get(m.Solicitud__c);
			if (s == null) {
				s = nuevaSolicitud(m.Solicitud__c, m.CreatedDate, m.CreatedBy == null ? null : m.CreatedBy.Name);
				porFolio.put(m.Solicitud__c, s);
			}
			s.put('total', (Integer) s.get('total') + 1);
			if (s.get('estatus') == null) { s.put('estatus', m.Seguimiento_Solicitud__c); }
			if (interno && String.isNotBlank(m.Folio_Aseguradora__c)) { s.put('folioAseguradora', m.Folio_Aseguradora__c); }
			String t = m.Tipo__c == 'Alta' ? 'altas' : (m.Tipo__c == 'Baja' ? 'bajas' : 'cambios');
			s.put(t, (Integer) s.get(t) + 1);
			if (m.Fecha_Cierre__c == null) {
				s.put('abiertos', (Integer) s.get('abiertos') + 1);
				// Seguimiento elegido a mano en el movimiento.
				if (m.Seguimiento__c == 'Solicitado') { s.put('solicitados', (Integer) s.get('solicitados') + 1); }
			}
			else if (s.get('cierre') == null || (Datetime) s.get('cierre') < m.Fecha_Cierre__c) { s.put('cierre', m.Fecha_Cierre__c); }
			// Prima de la solicitud: la suma de lo que cobra la aseguradora por cada movimiento.
			if (m.Transaccion__c != null && m.Transaccion__r.TotalTransactionAmount != null) {
				totalEndoso.put(m.Transaccion__c, m.Transaccion__r.TotalTransactionAmount);
				if (!foliosEndoso.containsKey(m.Transaccion__c)) { foliosEndoso.put(m.Transaccion__c, new Set<String>()); }
				foliosEndoso.get(m.Transaccion__c).add(m.Solicitud__c);
			}
			if (m.Prima__c != null) { s.put('prima', (s.get('prima') == null ? 0 : (Decimal) s.get('prima')) + m.Prima__c); }
			List<String> e = (List<String>) s.get('endosos');
			if (String.isNotBlank(m.Numero_Endoso__c) && !e.contains(m.Numero_Endoso__c.trim())) { e.add(m.Numero_Endoso__c.trim()); }
		}
		// Si la aseguradora no mandó la prima por movimiento: el total de sus endosos (los que son solo de esa solicitud).
		Set<String> conPrima = new Set<String>();
		for (Map<String, Object> s : porFolio.values()) { if (s.get('prima') != null) { conPrima.add((String) s.get('folio')); } }
		for (Id t : totalEndoso.keySet()) {
			Set<String> folios = foliosEndoso.get(t);
			if (folios.size() != 1 || conPrima.containsAll(folios)) { continue; }
			Map<String, Object> s = porFolio.get(new List<String>(folios)[0]);
			s.put('prima', (s.get('prima') == null ? 0 : (Decimal) s.get('prima')) + totalEndoso.get(t));
		}
		// Casos del sitio: la fecha y quién la registró son las del caso.
		List<Case> casos = new SinCompartir().casos(policyId);
		Set<Id> casoIds = new Map<Id, Case>(casos).keySet();
		Map<Id, List<Map<String, Object>>> docs = new Map<Id, List<Map<String, Object>>>();
		Map<Id, String> comentarios = new Map<Id, String>();
		if (!casoIds.isEmpty()) {
			for (ContentDocumentLink l : new SinCompartir().archivos(casoIds)) {
				if (!docs.containsKey(l.LinkedEntityId)) { docs.put(l.LinkedEntityId, new List<Map<String, Object>>()); }
				docs.get(l.LinkedEntityId).add(new Map<String, Object>{ 'id' => l.ContentDocumentId,
					'titulo' => l.ContentDocument.Title + (String.isBlank(l.ContentDocument.FileExtension) ? '' : '.' + l.ContentDocument.FileExtension) });
			}
			for (CaseComment cc : new SinCompartir().comentarios(casoIds)) {
				if (!comentarios.containsKey(cc.ParentId)) { comentarios.put(cc.ParentId, cc.CommentBody); }
			}
		}
		for (Case c : casos) {
			if (String.isBlank(c.Solicitud__c)) { continue; }
			Map<String, Object> s = porFolio.get(c.Solicitud__c);
			// Solicitud que el ejecutivo eliminó (EliminarMovimientos): ya no se muestra.
			if (s == null && c.IsClosed && comentarios.get(c.Id) != null && comentarios.get(c.Id).startsWith(EliminarMovimientos.COMENTARIO_CASO)) { continue; }
			// Caso creado después de los movimientos (registrados en las pestañas del sitio): fecha y autor son los de
			// los movimientos.
			Boolean previos = s != null && (Integer) s.get('total') > 0 && s.get('fecha') != null && (Datetime) s.get('fecha') < c.CreatedDate;
			if (s == null) {
				s = nuevaSolicitud(c.Solicitud__c, c.CreatedDate, null);
				porFolio.put(c.Solicitud__c, s);
			}
			if (interno && s.get('folioAseguradora') == null) { s.put('folioAseguradora', c.Folio_Aseguradora__c); }
			Integer total = (Integer) s.get('total');
			Integer abiertos = (Integer) s.get('abiertos');
			// Rechazada: con el comentario de rechazo (solicitudes anteriores; ahora se rechaza cada registro).
			String respuesta = comentarios.get(c.Id);
			Boolean rechazo = respuesta != null && respuesta.startsWith('Solicitud rechazada:');
			String estado = c.IsClosed ? (rechazo ? 'Rechazada' : 'Cerrada') : (total == 0 ? 'Recibida' : 'En proceso');
			s.putAll(new Map<String, Object>{
				'fecha' => previos ? s.get('fecha') : c.CreatedDate, 'portal' => true, 'casoId' => c.Id, 'caso' => c.CaseNumber,
				'estadoPortal' => estado, 'pendiente' => estado == 'Recibida', 'estadoCaso' => c.Status, 'casoCerrado' => c.IsClosed,
				'enviadaPor' => previos ? s.get('usuario') : (c.CreatedBy == null ? null : c.CreatedBy.Name),
				'usuario' => previos ? s.get('usuario') : (c.CreatedBy == null ? null : c.CreatedBy.Name),
				'asunto' => c.Subject, 'descripcion' => c.Description, 'comentario' => c.Comentarios__c,
				'respuesta' => comentarios.get(c.Id),
				'documentos' => docs.containsKey(c.Id) ? docs.get(c.Id) : new List<Map<String, Object>>()
			});
		}
		// Seguimiento del trámite y fecha de cierre (cuando se concluye).
		String inicial = porFolio.isEmpty() ? null : estadoCaso('Creado');
		for (Map<String, Object> s : porFolio.values()) {
			s.put('seguimiento', seguimiento(s, inicial));
			if (s.get('seguimiento') != 'Concluido' || (Integer) s.get('total') == 0) { s.put('cierre', null); }
		}
		// Más reciente primero.
		List<SolicitudOrden> orden = new List<SolicitudOrden>();
		for (Map<String, Object> s : porFolio.values()) { orden.add(new SolicitudOrden(s)); }
		orden.sort();
		List<Map<String, Object>> res = new List<Map<String, Object>>();
		for (SolicitudOrden o : orden) { res.add(o.s); }
		return res;
	}

	/**
	 * @creation date: 20/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Seguimiento del trámite de una solicitud. Solo cambia a mano: en las del sitio es el estado de su caso
	 *               y en las demás el que eligió el ejecutivo (Seguimiento_Solicitud__c), sin importar el de sus registros.
	 *               Las anteriores a ese campo, mientras nadie lo cambie, lo toman de sus registros.
	 * @param s: solicitud (de solicitudes()).
	 * @param inicial: estado inicial de los casos del org.
	 * @return Solicitado, En proceso, Concluido o Rechazada.
	 */
	@TestVisible
	static String seguimiento(Map<String, Object> s, String inicial) {
		if (s.get('estadoPortal') == 'Rechazada') { return 'Rechazada'; }
		Integer total = (Integer) s.get('total');
		Integer abiertos = (Integer) s.get('abiertos');
		if (s.get('casoCerrado') == true) { return 'Concluido'; }
		Object estado = s.get('estadoCaso');
		Integer solicitados = s.get('solicitados') == null ? 0 : (Integer) s.get('solicitados');
		if (s.get('portal') == true) {
			return estado == 'Solicitado' || (inicial != null && estado == inicial) ? 'Solicitado' : 'En proceso';
		}
		if (s.get('estatus') != null) { return (String) s.get('estatus'); }
		if (total > 0 && abiertos == 0) { return 'Concluido'; }
		if (total > 0 && solicitados == abiertos) { return 'Solicitado'; }
		return 'En proceso';
	}

	private static Map<String, Object> nuevaSolicitud(String folio, Datetime fecha, String usuario) {
		return new Map<String, Object>{
			'folio' => folio, 'fecha' => fecha, 'usuario' => usuario, 'portal' => false,
			'total' => 0, 'altas' => 0, 'bajas' => 0, 'cambios' => 0, 'abiertos' => 0, 'solicitados' => 0, 'endosos' => new List<String>()
		};
	}

	// Orden de las solicitudes: la más reciente primero.
	private class SolicitudOrden implements Comparable {
		Map<String, Object> s;
		SolicitudOrden(Map<String, Object> s) { this.s = s; }
		public Integer compareTo(Object o) {
			Datetime a = (Datetime) s.get('fecha');
			Datetime b = (Datetime) ((SolicitudOrden) o).s.get('fecha');
			if (a == b) { return String.valueOf(((SolicitudOrden) o).s.get('folio')).compareTo(String.valueOf(s.get('folio'))); }
			if (a == null) { return 1; }
			if (b == null) { return -1; }
			return a > b ? -1 : 1;
		}
	}

	/**
	 * @creation date: 23/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: El ejecutivo cambia a mano el seguimiento de un movimiento o de toda una solicitud. Concluido cierra
	 *               el movimiento; Rechazado (solo un movimiento, con su motivo) también; Solicitado o En proceso lo reabren. El
	 *               estatus de la solicitud (y su caso) solo cambia al elegirlo en ella, no con el de sus registros.
	 * @param policyId: póliza.
	 * @param folio: solicitud (null si el movimiento no tiene).
	 * @param movimientoId: movimiento, o null para toda la solicitud.
	 * @param nuevo: Solicitado, En proceso, Concluido o Rechazado.
	 * @param motivo: motivo del rechazo (lo ve el cliente).
	 * @return aviso del correo al cliente cuando la solicitud quedó concluida, o null.
	 */
	public static String cambiarSeguimiento(Id policyId, String folio, Id movimientoId, String nuevo, String motivo) {
		if (UserInfo.getUserType() != 'Standard') { throw new IllegalArgumentException('Solo un ejecutivo puede cambiarlo.'); }
		if (!new Set<String>{ 'Solicitado', 'En proceso', 'Concluido', 'Rechazado' }.contains(nuevo)) { throw new IllegalArgumentException('Estado no válido.'); }
		if (nuevo == 'Rechazado' && movimientoId == null) { throw new IllegalArgumentException('Se rechaza cada registro, no toda la solicitud.'); }
		if (nuevo == 'Rechazado' && String.isBlank(motivo)) { throw new IllegalArgumentException('Escribe el motivo del rechazo.'); }
		if ([SELECT COUNT() FROM InsurancePolicy WHERE Id = :policyId] == 0) { throw new IllegalArgumentException('No tienes acceso a la póliza.'); }
		new SinCompartir().cambiar(policyId, folio, movimientoId, nuevo, motivo);
		return avisosConclusion.isEmpty() ? null : String.join(avisosConclusion, ' ');
	}

	/**
	 * @creation date: 25/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Guarda el folio que dio la aseguradora a un movimiento (toda la solicitud): en sus registros y, si es
	 *               del sitio, en su caso.
	 * @param policyId: póliza.
	 * @param folio: solicitud (SOL-0001).
	 * @param valor: folio de la aseguradora; vacío lo quita.
	 * @return void
	 */
	public static void guardarFolioAseguradora(Id policyId, String folio, String valor) {
		if (UserInfo.getUserType() != 'Standard') { throw new IllegalArgumentException('Solo un ejecutivo puede cambiarlo.'); }
		if (String.isBlank(folio)) { throw new IllegalArgumentException('El folio de la aseguradora es de un movimiento.'); }
		if ([SELECT COUNT() FROM InsurancePolicy WHERE Id = :policyId] == 0) { throw new IllegalArgumentException('No tienes acceso a la póliza.'); }
		new SinCompartir().folioAseguradora(policyId, folio, String.isBlank(valor) ? null : valor.trim().left(80));
	}

	/**
	 * @creation date: 25/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Guarda el estatus que tienen hoy las solicitudes que aún no lo tienen guardado, para que no cambie al
	 *               cerrar, agregar o eliminar sus registros (llamar antes de hacerlo).
	 * @param policyId: póliza.
	 * @param folios: solicitudes.
	 * @return void
	 */
	public static void fijarEstatus(Id policyId, Set<String> folios) {
		new SinCompartir().fijarEstatus(policyId, folios);
	}

	// Avisos de los correos de conclusión que se mandaron en esta transacción (para la pantalla).
	private static List<String> avisosConclusion = new List<String>();

	// Solicitud concluida: se le manda al cliente el resumen de lo realizado.
	private static void avisarConclusion(Id policyId, String folio) {
		String aviso = AvisoMovimientoConcluido.programar(policyId, folio);
		if (aviso != null) { avisosConclusion.add(aviso); }
	}

	// Casos del sitio: el ejecutivo los ve y los atiende aunque no sea su dueño.
	private without sharing class SinCompartir {
		List<Case> casosDe(Id policyId, String folio) {
			Id rt = tipoCaso();
			if (rt == null) { return new List<Case>(); }
			String q = 'SELECT Id, CaseNumber, Solicitud__c, Status, IsClosed, Subject, Description, Comentarios__c, Folio_Aseguradora__c, CreatedDate,'
				+ ' CreatedBy.Name FROM Case WHERE RecordTypeId = :rt AND InsurancePolicy__c = :policyId AND Solicitud__c != null'
				+ (folio == null ? '' : ' AND Solicitud__c = :folio') + ' ORDER BY CreatedDate DESC LIMIT 500';
			return Database.queryWithBinds(q, new Map<String, Object>{ 'rt' => rt, 'policyId' => policyId, 'folio' => folio }, AccessLevel.SYSTEM_MODE);
		}
		List<Movimiento_Poliza__c> movimientos(Id policyId) {
			return [
				SELECT Solicitud__c, Tipo__c, Numero_Endoso__c, CreatedDate, CreatedBy.Name, Fecha_Cierre__c, Seguimiento__c, Participante__c, Inciso__c, Prima__c, Folio_Aseguradora__c, Seguimiento_Solicitud__c,
					Transaccion__c, Transaccion__r.TotalTransactionAmount
				FROM Movimiento_Poliza__c WHERE Poliza__c = :policyId AND Solicitud__c != null ORDER BY CreatedDate, Id LIMIT 10000
			];
		}
		List<Case> casos(Id policyId) { return casosDe(policyId, null); }
		List<Case> casosDeFolio(Id policyId, String folio) { return casosDe(policyId, folio); }
		List<ContentDocumentLink> archivos(Set<Id> ids) {
			return [SELECT LinkedEntityId, ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension
				FROM ContentDocumentLink WHERE LinkedEntityId IN :ids];
		}
		List<CaseComment> comentarios(Set<Id> ids) {
			return [SELECT ParentId, CommentBody FROM CaseComment WHERE ParentId IN :ids AND IsPublished = true ORDER BY CreatedDate DESC];
		}
		void folioAseguradora(Id policyId, String folio, String valor) {
			List<Movimiento_Poliza__c> movs = [SELECT Id FROM Movimiento_Poliza__c WHERE Poliza__c = :policyId AND Solicitud__c = :folio LIMIT 9000];
			List<Case> casos = casosDeFolio(policyId, folio);
			if (movs.isEmpty() && casos.isEmpty()) { throw new IllegalArgumentException('El movimiento ya no existe.'); }
			for (Movimiento_Poliza__c m : movs) { m.Folio_Aseguradora__c = valor; }
			update movs;
			List<Case> cambios = new List<Case>();
			for (Case c : casos) { cambios.add(new Case(Id = c.Id, Folio_Aseguradora__c = valor)); }
			update cambios;
		}
		void fijarEstatus(Id policyId, Set<String> folios) {
			List<Movimiento_Poliza__c> movs = [
				SELECT Id, Solicitud__c FROM Movimiento_Poliza__c
				WHERE Poliza__c = :policyId AND Solicitud__c IN :folios AND Solicitud__c != null AND Seguimiento_Solicitud__c = null LIMIT 9000
			];
			if (movs.isEmpty()) { return; }
			Map<String, String> estatus = new Map<String, String>();
			for (Map<String, Object> s : solicitudes(policyId, null)) { estatus.put((String) s.get('folio'), (String) s.get('seguimiento')); }
			for (Movimiento_Poliza__c m : movs) { m.Seguimiento_Solicitud__c = estatus.get(m.Solicitud__c); }
			update movs;
		}
		void cambiar(Id policyId, String folio, Id movimientoId, String nuevo, String motivo) {
			Boolean completa = movimientoId == null;
			List<Movimiento_Poliza__c> movs = String.isBlank(folio)
				? [SELECT Id, Fecha_Cierre__c, Seguimiento__c, Transaccion__c FROM Movimiento_Poliza__c WHERE Poliza__c = :policyId AND Id = :movimientoId]
				: [SELECT Id, Fecha_Cierre__c, Seguimiento__c, Transaccion__c FROM Movimiento_Poliza__c WHERE Poliza__c = :policyId AND Solicitud__c = :folio LIMIT 9000];
			Map<Id, Movimiento_Poliza__c> porId = new Map<Id, Movimiento_Poliza__c>(movs);
			if (!completa && !porId.containsKey(movimientoId)) { throw new IllegalArgumentException('El movimiento ya no existe.'); }
			List<Case> casos = String.isBlank(folio) ? new List<Case>() : casosDeFolio(policyId, folio);
			Case caso = casos.isEmpty() ? null : casos[0];
			if (movs.isEmpty() && caso == null) { throw new IllegalArgumentException('La solicitud ya no existe.'); }
			List<Movimiento_Poliza__c> elegidos = completa ? movs : new List<Movimiento_Poliza__c>{ porId.get(movimientoId) };
			String actual = null;
			if (String.isNotBlank(folio)) {
				for (Map<String, Object> s : solicitudes(policyId, null)) { if (s.get('folio') == folio) { actual = (String) s.get('seguimiento'); } }
			}
			if (completa) {
				for (Movimiento_Poliza__c m : movs) { m.Seguimiento_Solicitud__c = nuevo; }
				update movs;
			} else if (String.isNotBlank(folio)) {
				fijarEstatus(policyId, new Set<String>{ folio });
			}
			if (nuevo == 'Rechazado') {
				Movimiento_Poliza__c m = elegidos[0];
				if (m.Fecha_Cierre__c == null) { m.Fecha_Cierre__c = ahora(); }
				m.Seguimiento__c = 'Rechazado';
				m.Motivo_Rechazo__c = motivo.trim().left(255);
				update m;
				aprobarCerrados(new Set<Id>{ m.Id });
				return;
			}
			if (nuevo == 'Concluido') {
				// Solicitud sin movimientos: se concluye su caso.
				if (movs.isEmpty()) {
					update new Case(Id = caso.Id, Status = estadoCaso('Concluido'));
					avisarConclusion(policyId, folio);
				}
				else {
					concluirElegidos(elegidos, completa);
					if (completa) { concluir(porId.keySet()); }
				}
				return;
			}
			Boolean cerrado = caso != null && caso.IsClosed;
			// Lo ya concluido solo se reabre si la solicitud estaba Concluida.
			Boolean todosCerrados = actual == 'Concluido';
			for (Movimiento_Poliza__c m : movs) { todosCerrados = todosCerrados && m.Fecha_Cierre__c != null; }
			String base = caso != null && (caso.Status == 'Solicitado' || caso.Status == estadoCaso('Creado')) ? 'Solicitado' : 'En proceso';
			Map<Id, Movimiento_Poliza__c> cambios = new Map<Id, Movimiento_Poliza__c>();
			Set<Id> reabiertas = new Set<Id>();
			for (Movimiento_Poliza__c m : elegidos) {
				// Los rechazados solo cambian en su registro.
				if (completa && m.Seguimiento__c == 'Rechazado') { continue; }
				// Al cambiar toda la solicitud, lo ya concluido solo se reabre si ya estaba todo concluido.
				if (completa && m.Fecha_Cierre__c != null && !todosCerrados) { continue; }
				if (m.Fecha_Cierre__c != null && m.Transaccion__c != null) { reabiertas.add(m.Transaccion__c); }
				m.Fecha_Cierre__c = null;
				m.Motivo_Rechazo__c = null;
				// Con caso, la solicitud completa toma el estado del caso (también si luego se cambia en el caso).
				m.Seguimiento__c = completa && caso != null ? null : nuevo;
				cambios.put(m.Id, m);
			}
			if (completa && cambios.isEmpty() && todosCerrados && !movs.isEmpty()) {
				throw new IllegalArgumentException('Todos sus registros están rechazados: cambia el estado del registro.');
			}
			update cambios.values();
			// El estatus de la solicitud solo cambia si se eligió en ella.
			if (completa && caso != null && (cerrado || nuevo != base)) { update new Case(Id = caso.Id, Status = estadoCaso(nuevo)); }
			String pendiente = valor(InsurancePolicyTransaction.Status.getDescribe(), 'Pendiente');
			if (!reabiertas.isEmpty() && pendiente != null) {
				List<InsurancePolicyTransaction> l = new List<InsurancePolicyTransaction>();
				for (Id i : reabiertas) { l.add(new InsurancePolicyTransaction(Id = i, Status = pendiente)); }
				update l;
			}
		}
		// Al segundo, como se guarda.
		Datetime ahora() { return Datetime.newInstance((Datetime.now().getTime() / 1000) * 1000); }
		void concluirElegidos(List<Movimiento_Poliza__c> elegidos, Boolean completa) {
			List<Movimiento_Poliza__c> l = new List<Movimiento_Poliza__c>();
			for (Movimiento_Poliza__c m : elegidos) {
				// Al concluir toda la solicitud, los rechazados se quedan así.
				Boolean rechazado = m.Seguimiento__c == 'Rechazado';
				if (m.Fecha_Cierre__c != null && (completa || !rechazado)) { continue; }
				if (m.Fecha_Cierre__c == null) { m.Fecha_Cierre__c = ahora(); }
				if (rechazado) { m.Seguimiento__c = null; m.Motivo_Rechazo__c = null; }
				l.add(m);
			}
			update l;
			aprobarCerrados(new Map<Id, Movimiento_Poliza__c>(l).keySet());
		}
		// Al concluir una solicitud se concluye su caso (si es del sitio) y se manda el correo al cliente.
		void concluir(Set<Id> movimientoIds) {
			Map<Id, Set<String>> folios = new Map<Id, Set<String>>();
			for (Movimiento_Poliza__c m : [SELECT Poliza__c, Solicitud__c FROM Movimiento_Poliza__c WHERE Id IN :movimientoIds AND Solicitud__c != null AND Poliza__c != null]) {
				if (!folios.containsKey(m.Poliza__c)) { folios.put(m.Poliza__c, new Set<String>()); }
				folios.get(m.Poliza__c).add(m.Solicitud__c);
			}
			Id rt = tipoCaso();
			if (folios.isEmpty()) { return; }
			Set<String> todos = new Set<String>();
			for (Set<String> s : folios.values()) { todos.addAll(s); }
			Set<String> abiertos = new Set<String>();
			for (Movimiento_Poliza__c m : [
				SELECT Poliza__c, Solicitud__c FROM Movimiento_Poliza__c
				WHERE Poliza__c IN :folios.keySet() AND Solicitud__c IN :todos AND Fecha_Cierre__c = null
			]) { abiertos.add(m.Poliza__c + '|' + m.Solicitud__c); }
			// La solicitud ya no tiene movimientos abiertos: correo al cliente con el resumen.
			for (Id pol : folios.keySet()) {
				for (String folio : folios.get(pol)) { if (!abiertos.contains(pol + '|' + folio)) { avisarConclusion(pol, folio); } }
			}
			if (rt == null) { return; }
			String cerrado = estadoCaso('Concluido');
			List<Case> l = new List<Case>();
			for (Case c : [
				SELECT Id, InsurancePolicy__c, Solicitud__c FROM Case
				WHERE RecordTypeId = :rt AND InsurancePolicy__c IN :folios.keySet() AND Solicitud__c IN :todos AND IsClosed = false
			]) {
				if (folios.get(c.InsurancePolicy__c).contains(c.Solicitud__c) && !abiertos.contains(c.InsurancePolicy__c + '|' + c.Solicitud__c)) {
					l.add(new Case(Id = c.Id, Status = cerrado));
				}
			}
			if (!l.isEmpty() && cerrado != null) { update l; }
		}
	}

	/**
	 * @return Id del tipo de registro de caso «Solicitud de movimientos», o null si el org no lo tiene.
	 */
	public static Id tipoCaso() {
		Schema.RecordTypeInfo i = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Solicitud_Movimientos');
		return i == null ? null : i.getRecordTypeId();
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Registra (o completa) el endoso con los movimientos insertados en esta transacción de Apex.
	 * @param policyId: póliza.
	 * @param p: prima del endoso (opcional).
	 * @return Id de la transacción del endoso, o null si no hubo movimientos.
	 */
	public static Id registrar(Id policyId, Prima p) {
		List<Id> l = registrarTodos(policyId, p, null);
		return l.isEmpty() ? null : l[0];
	}

	/**
	 * @creation date: 15/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Registra (o completa) un endoso por cada número de endoso de los movimientos insertados en esta
	 *               transacción de Apex (p. ej. el soporte de recibo de GMM trae varios: 5, 15, 16...). Los movimientos
	 *               sin número (altas, bajas o cambios de un listado o capturados sin número) no son un endoso de la
	 *               aseguradora: no se registran. Cada endoso toma su prima de "porNumero"; con un solo endoso,
	 *               si no viene ahí, toma "p" (la que se capturó en pantalla).
	 * @param policyId: póliza.
	 * @param p: prima capturada (opcional).
	 * @param porNumero: prima por número de endoso (opcional).
	 * @return Ids de las transacciones, en el orden de los movimientos.
	 */
	public static List<Id> registrarTodos(Id policyId, Prima p, Map<String, Prima> porNumero) {
		Set<Id> ids = new Map<Id, Movimiento_Poliza__c>(insertados).keySet();
		insertados = new List<Movimiento_Poliza__c>();
		ultimosPorNumero = new Map<String, Id>();
		List<Id> res = new List<Id>();
		if (ids.isEmpty() || policyId == null) { return res; }
		// Movimientos por número de endoso ('' = sin número), en el orden en que se registraron.
		Map<String, List<Movimiento_Poliza__c>> grupos = new Map<String, List<Movimiento_Poliza__c>>();
		List<Movimiento_Poliza__c> todos = [
			SELECT Id, Name, Tipo__c, Fecha_Movimiento__c, Fecha_Cierre__c, Numero_Endoso__c, Asegurado__c, Certificado__c, Participante__c,
				Participante__r.StandardPremiumAmount, Inciso__c, Inciso__r.Vehiculo__c, Inciso__r.Prima__c
			FROM Movimiento_Poliza__c WHERE Id IN :ids ORDER BY CreatedDate, Id
		];
		for (Movimiento_Poliza__c m : todos) {
			String k = String.isBlank(m.Numero_Endoso__c) ? '' : m.Numero_Endoso__c.trim();
			if (!grupos.containsKey(k)) { grupos.put(k, new List<Movimiento_Poliza__c>()); }
			grupos.get(k).add(m);
		}
		// Sin número de endoso no hay endoso de la aseguradora.
		grupos.remove('');
		if (grupos.isEmpty()) { return res; }
		String categoria = valor(InsurancePolicyTransaction.Category.getDescribe(), 'Endorsement');
		String pendiente = valor(InsurancePolicyTransaction.Status.getDescribe(), 'Pendiente');
		String aprobado = valor(InsurancePolicyTransaction.Status.getDescribe(), 'Aprobado');

		// Mismo número de endoso en la póliza: se completa ese endoso.
		Map<String, InsurancePolicyTransaction> existentes = new Map<String, InsurancePolicyTransaction>();
		Set<String> numeros = new Set<String>(grupos.keySet());
		numeros.remove('');
		if (!numeros.isEmpty()) {
			for (InsurancePolicyTransaction ex : [
				SELECT Id, Name, Status, TransactionNumber FROM InsurancePolicyTransaction
				WHERE InsurancePolicyId = :policyId AND TransactionNumber IN :numeros AND Category = :categoria
				ORDER BY CreatedDate
			]) {
				if (!existentes.containsKey(ex.TransactionNumber.trim())) { existentes.put(ex.TransactionNumber.trim(), ex); }
			}
		}
		String poliza = [SELECT Name FROM InsurancePolicy WHERE Id = :policyId].Name;
		// El endoso nuevo sigue a la transacción anterior de la póliza (la emisión u otro endoso).
		Id anterior = null;
		for (InsurancePolicyTransaction x : [
			SELECT Id FROM InsurancePolicyTransaction WHERE InsurancePolicyId = :policyId ORDER BY CreatedDate DESC, Id DESC LIMIT 1
		]) { anterior = x.Id; }

		List<String> llaves = new List<String>(grupos.keySet());
		List<InsurancePolicyTransaction> ts = new List<InsurancePolicyTransaction>();
		List<Boolean> esNueva = new List<Boolean>();
		for (String k : llaves) {
			Date fecha = null;
			// Movimientos que ya quedan cerrados al aplicarse (vehículos y ubicaciones en Salesforce, sin trámite).
			Boolean cerrados = true;
			for (Movimiento_Poliza__c m : grupos.get(k)) {
				if (m.Fecha_Movimiento__c != null && (fecha == null || m.Fecha_Movimiento__c < fecha)) { fecha = m.Fecha_Movimiento__c; }
				if (m.Fecha_Cierre__c == null) { cerrados = false; }
			}
			if (fecha == null) { fecha = Date.today(); }
			String numero = k == '' ? null : k;
			InsurancePolicyTransaction t = numero == null ? null : existentes.get(numero);
			esNueva.add(t == null);
			if (t == null) {
				t = new InsurancePolicyTransaction(InsurancePolicyId = policyId, TransactionNumber = numero, Category = categoria);
				t.Name = ('Endoso ' + (numero != null ? numero : fechaTexto(fecha)) + ' - ' + poliza).left(80);
				// Con todos sus movimientos cerrados el endoso nace Aprobado; si no, Pendiente hasta que se cierren.
				t.Status = cerrados && aprobado != null ? aprobado : pendiente;
				t.TransactionEffectiveDate = Datetime.newInstance(fecha, Time.newInstance(12, 0, 0, 0));
				t.EffectiveFromDate = fecha;
			} else if (!cerrados && t.Status != pendiente) {
				// Se le agregan movimientos abiertos: vuelve a quedar pendiente.
				t.Status = pendiente;
			}
			// Prima de la aseguradora: la que viene en el documento del endoso (no se calcula). Con un solo endoso, si
			// no viene por número, la que se capturó.
			Prima pk = porNumero != null && porNumero.containsKey(k) ? porNumero.get(k) : (llaves.size() == 1 ? p : null);
			ponerPrima(t, pk);
			ts.add(t);
		}
		upsert ts;
		// Los endosos nuevos quedan encadenados: cada uno sigue al anterior.
		List<InsurancePolicyTransaction> cadena = new List<InsurancePolicyTransaction>();
		for (Integer i = 0; i < ts.size(); i++) {
			if (!esNueva[i]) { continue; }
			if (anterior != null) { cadena.add(new InsurancePolicyTransaction(Id = ts[i].Id, PriorTransactionId = anterior)); }
			anterior = ts[i].Id;
		}
		if (!cadena.isEmpty()) { update cadena; }

		// Bienes de la póliza: por vehículo (bien del cliente) y por número de inciso (ubicaciones).
		Map<Id, InsurancePolicyAsset> porVehiculo = new Map<Id, InsurancePolicyAsset>();
		Map<String, InsurancePolicyAsset> porInciso = new Map<String, InsurancePolicyAsset>();
		for (InsurancePolicyAsset a : [
			SELECT Id, AssetName, CustomerPropertyId, StandardPremiumAmount FROM InsurancePolicyAsset WHERE InsurancePolicyId = :policyId
		]) {
			if (a.CustomerPropertyId != null) { porVehiculo.put(a.CustomerPropertyId, a); }
			Matcher mt = Pattern.compile('^Inciso\\s+(\\d+)').matcher(a.AssetName == null ? '' : a.AssetName);
			if (mt.find()) { porInciso.put('Inciso ' + Integer.valueOf(mt.group(1)), a); }
		}
		List<InsPolicyTransactionDetail> detalles = new List<InsPolicyTransactionDetail>();
		for (Integer i = 0; i < llaves.size(); i++) {
			Id tId = ts[i].Id;
			res.add(tId);
			ultimosPorNumero.put(llaves[i], tId);
			for (Movimiento_Poliza__c m : grupos.get(llaves[i])) {
				m.Transaccion__c = tId;
				Id ref = null;
				Decimal prima = null;
				if (m.Participante__c != null) {
					ref = m.Participante__c;
					prima = m.Participante__r.StandardPremiumAmount;
				} else if (m.Inciso__c != null) {
					InsurancePolicyAsset a = m.Inciso__r.Vehiculo__c == null ? null : porVehiculo.get(m.Inciso__r.Vehiculo__c);
					ref = a == null ? null : a.Id;
					prima = m.Inciso__r.Prima__c;
				} else if (String.isNotBlank(m.Certificado__c) && porInciso.containsKey(m.Certificado__c.trim())) {
					InsurancePolicyAsset a = porInciso.get(m.Certificado__c.trim());
					ref = a.Id;
					prima = a.StandardPremiumAmount;
				}
				InsPolicyTransactionDetail d = new InsPolicyTransactionDetail(InsurancePolicyTransactionId = tId,
					Name = ((m.Tipo__c == null ? 'Movimiento' : m.Tipo__c) + ' - ' + (m.Asegurado__c == null ? m.Name : m.Asegurado__c)).left(80));
				if (ref != null) { d.ReferenceObjectId = ref; }
				// La baja no suma prima: lo que devuelve la aseguradora va en la prima del endoso.
				if (m.Tipo__c != 'Baja' && prima != null) { d.Premium = prima; }
				detalles.add(d);
			}
		}
		if (!detalles.isEmpty()) { insert detalles; }
		update todos;
		return res;
	}

	// Prima de la aseguradora en la transacción (solo lo que viene).
	private static void ponerPrima(InsurancePolicyTransaction t, Prima p) {
		if (p == null) { return; }
		if (p.primaNeta != null) { t.TransactionAmount = p.primaNeta; }
		if (p.derechos != null) { t.TransactionFeeAmount = p.derechos; }
		if (p.iva != null) { t.TransactionTaxAmount = p.iva; }
		if (p.total != null) {
			try { t.put('TotalTransactionAmount', p.total); } catch (Exception ignore) { /* Calculado por la plataforma en algunos orgs. */ }
		}
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Al cerrar movimientos, el endoso cuyos movimientos ya están todos cerrados pasa a Aprobado.
	 * @param movimientoIds: movimientos que se cerraron.
	 */
	public static void aprobarCerrados(Set<Id> movimientoIds) {
		if (movimientoIds == null || movimientoIds.isEmpty()) { return; }
		Set<Id> trans = new Set<Id>();
		for (Movimiento_Poliza__c m : [SELECT Transaccion__c FROM Movimiento_Poliza__c WHERE Id IN :movimientoIds AND Transaccion__c != null]) {
			trans.add(m.Transaccion__c);
		}
		if (trans.isEmpty()) { return; }
		for (AggregateResult ar : [
			SELECT Transaccion__c t FROM Movimiento_Poliza__c WHERE Transaccion__c IN :trans AND Fecha_Cierre__c = null GROUP BY Transaccion__c
		]) { trans.remove((Id) ar.get('t')); }
		// Un endoso con todos sus movimientos rechazados no se aprueba.
		Set<Id> conProcedentes = new Set<Id>();
		for (AggregateResult ar : [
			SELECT Transaccion__c t FROM Movimiento_Poliza__c WHERE Transaccion__c IN :trans AND Seguimiento__c != 'Rechazado' GROUP BY Transaccion__c
		]) { conProcedentes.add((Id) ar.get('t')); }
		trans.retainAll(conProcedentes);
		String aprobado = valor(InsurancePolicyTransaction.Status.getDescribe(), 'Aprobado');
		if (trans.isEmpty() || aprobado == null) { return; }
		List<InsurancePolicyTransaction> l = new List<InsurancePolicyTransaction>();
		for (Id i : trans) { l.add(new InsurancePolicyTransaction(Id = i, Status = aprobado)); }
		update l;
	}

	// Valor activo del picklist (sin distinguir mayúsculas); null si el org no lo tiene.
	private static String valor(Schema.DescribeFieldResult f, String buscado) {
		for (Schema.PicklistEntry pe : f.getPicklistValues()) {
			if (pe.isActive() && (pe.getValue().equalsIgnoreCase(buscado) || pe.getLabel().equalsIgnoreCase(buscado))) { return pe.getValue(); }
		}
		return null;
	}

	/**
	 * @creation date: 15/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Endosos de la póliza para mostrarlos en pantalla (más reciente primero): número, estado, fecha en
	 *               que surte efecto, prima de la aseguradora (neta, derechos, IVA y total), quién lo registró, sus
	 *               movimientos (tipo, registro, detalle, comentario, fecha y cierre) y los documentos adjuntos.
	 * @param policyId: póliza.
	 * @return lista de endosos como mapas.
	 */
	@AuraEnabled(cacheable=false)
	public static List<Map<String, Object>> getEndosos(Id policyId) {
		return endososDe(policyId);
	}

	/**
	 * @creation date: 15/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Registra un endoso de la aseguradora que no mueve asegurados, vehículos ni ubicaciones (p. ej. una
	 *               cláusula o beneficio adicional de GMM): número, fecha en que surte efecto, descripción y prima. Queda
	 *               aprobado porque no tiene movimientos que cerrar. Si ya hay un endoso con ese número en la póliza, se
	 *               actualiza. El documento se adjunta después (datosEndoso.subir).
	 * @param policyId: póliza.
	 * @param numero: número de endoso (opcional).
	 * @param descripcion: nombre o descripción del endoso (opcional).
	 * @param fecha: fecha en que surte efecto, AAAA-MM-DD (hoy si no viene).
	 * @param primaJson: prima { primaNeta, derechos, iva, total } en JSON (opcional).
	 * @return Id de la transacción del endoso.
	 */
	@AuraEnabled(cacheable=false)
	public static Id registrarEndoso(Id policyId, String numero, String descripcion, String fecha, String primaJson) {
		try {
			if (policyId == null) { throw new AuraHandledException('Falta la póliza.'); }
			String num = String.isBlank(numero) ? null : numero.trim().left(255);
			Date f = String.isBlank(fecha) ? Date.today() : Date.valueOf(fecha.left(10));
			String categoria = valor(InsurancePolicyTransaction.Category.getDescribe(), 'Endorsement');
			String aprobado = valor(InsurancePolicyTransaction.Status.getDescribe(), 'Aprobado');
			InsurancePolicyTransaction t = null;
			if (num != null) {
				for (InsurancePolicyTransaction ex : [
					SELECT Id FROM InsurancePolicyTransaction
					WHERE InsurancePolicyId = :policyId AND TransactionNumber = :num AND Category = :categoria ORDER BY CreatedDate LIMIT 1
				]) { t = ex; }
			}
			String poliza = [SELECT Name FROM InsurancePolicy WHERE Id = :policyId].Name;
			if (t == null) {
				t = new InsurancePolicyTransaction(InsurancePolicyId = policyId, TransactionNumber = num, Category = categoria);
				for (InsurancePolicyTransaction anterior : [
					SELECT Id FROM InsurancePolicyTransaction WHERE InsurancePolicyId = :policyId ORDER BY CreatedDate DESC, Id DESC LIMIT 1
				]) { t.PriorTransactionId = anterior.Id; }
			}
			t.Name = ('Endoso ' + (num != null ? num : fechaTexto(f)) + (String.isBlank(descripcion) ? '' : ' - ' + descripcion.trim())
				+ ' - ' + poliza).left(255);
			t.TransactionEffectiveDate = Datetime.newInstance(f, Time.newInstance(12, 0, 0, 0));
			t.EffectiveFromDate = f;
			if (aprobado != null) { t.Status = aprobado; }
			if (String.isNotBlank(primaJson) && primaJson.trim() != 'null') {
				ponerPrima(t, (Prima) System.JSON.deserialize(primaJson, Prima.class));
			}
			upsert t;
			return t.Id;
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			AuraHandledException ex = new AuraHandledException(e.getMessage());
			ex.setMessage(e.getMessage());
			throw ex;
		}
	}

	private static List<Map<String, Object>> endososDe(Id policyId) {
		try {
			List<Map<String, Object>> res = new List<Map<String, Object>>();
			if (policyId == null) { return res; }
			String categoria = valor(InsurancePolicyTransaction.Category.getDescribe(), 'Endorsement');
			Map<String, String> estados = new Map<String, String>();
			for (Schema.PicklistEntry pe : InsurancePolicyTransaction.Status.getDescribe().getPicklistValues()) {
				estados.put(pe.getValue(), pe.getLabel());
			}
			List<InsurancePolicyTransaction> ts = [
				SELECT Id, Name, TransactionNumber, Status, EffectiveFromDate, TransactionAmount, TransactionFeeAmount,
					TransactionTaxAmount, TotalTransactionAmount, CreatedDate, CreatedBy.Name
				FROM InsurancePolicyTransaction WHERE InsurancePolicyId = :policyId AND Category = :categoria
				ORDER BY EffectiveFromDate DESC NULLS LAST, CreatedDate DESC LIMIT 500
			];
			if (ts.isEmpty()) { return res; }
			Set<Id> ids = new Map<Id, InsurancePolicyTransaction>(ts).keySet();
			Map<Id, List<Map<String, Object>>> movs = new Map<Id, List<Map<String, Object>>>();
			for (Movimiento_Poliza__c m : [
				SELECT Id, Name, Transaccion__c, Tipo__c, Asegurado__c, Certificado__c, Detalle__c, Comentario__c,
					Fecha_Movimiento__c, Fecha_Cierre__c
				FROM Movimiento_Poliza__c WHERE Transaccion__c IN :ids ORDER BY CreatedDate, Id
			]) {
				if (!movs.containsKey(m.Transaccion__c)) { movs.put(m.Transaccion__c, new List<Map<String, Object>>()); }
				movs.get(m.Transaccion__c).add(new Map<String, Object>{
					'id' => m.Id, 'nombre' => m.Name, 'tipo' => m.Tipo__c, 'registro' => m.Asegurado__c,
					'certificado' => m.Certificado__c, 'detalle' => m.Detalle__c, 'comentario' => m.Comentario__c,
					'fecha' => m.Fecha_Movimiento__c, 'cierre' => m.Fecha_Cierre__c
				});
			}
			Map<Id, List<Map<String, Object>>> docs = new Map<Id, List<Map<String, Object>>>();
			for (ContentDocumentLink l : [
				SELECT LinkedEntityId, ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension
				FROM ContentDocumentLink WHERE LinkedEntityId IN :ids
			]) {
				if (!docs.containsKey(l.LinkedEntityId)) { docs.put(l.LinkedEntityId, new List<Map<String, Object>>()); }
				docs.get(l.LinkedEntityId).add(new Map<String, Object>{
					'id' => l.ContentDocumentId,
					'titulo' => l.ContentDocument.Title + (String.isBlank(l.ContentDocument.FileExtension) ? '' : '.' + l.ContentDocument.FileExtension)
				});
			}
			for (InsurancePolicyTransaction t : ts) {
				List<Map<String, Object>> lm = movs.containsKey(t.Id) ? movs.get(t.Id) : new List<Map<String, Object>>();
				Integer abiertos = 0;
				for (Map<String, Object> m : lm) { if (m.get('cierre') == null) { abiertos++; } }
				res.add(new Map<String, Object>{
					'id' => t.Id, 'nombre' => t.Name, 'numero' => t.TransactionNumber,
					'estado' => estados.containsKey(t.Status) ? estados.get(t.Status) : t.Status,
					'fecha' => t.EffectiveFromDate, 'primaNeta' => t.TransactionAmount, 'derechos' => t.TransactionFeeAmount,
					'iva' => t.TransactionTaxAmount, 'total' => t.TotalTransactionAmount, 'creado' => t.CreatedDate,
					'usuario' => t.CreatedBy == null ? null : t.CreatedBy.Name, 'movimientos' => lm, 'abiertos' => abiertos,
					'documentos' => docs.containsKey(t.Id) ? docs.get(t.Id) : new List<Map<String, Object>>()
				});
			}
			return res;
		} catch (Exception e) {
			AuraHandledException ex = new AuraHandledException(e.getMessage());
			ex.setMessage(e.getMessage());
			throw ex;
		}
	}

	private static String fechaTexto(Date d) {
		return String.valueOf(d.day()).leftPad(2, '0') + '/' + String.valueOf(d.month()).leftPad(2, '0') + '/' + d.year();
	}
}
