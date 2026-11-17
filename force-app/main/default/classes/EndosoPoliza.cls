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
public with sharing class EndosoPoliza {

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
			// El caso del sitio pasa a En proceso al aplicar sus primeros movimientos.
			String enProceso = estadoCaso('En proceso');
			List<Case> cambiar = new List<Case>();
			for (Case c : casos) {
				if (!c.IsClosed && enProceso != null && c.Status != enProceso) { cambiar.add(new Case(Id = c.Id, Status = enProceso)); }
			}
			new SinCompartir().actualizar(cambiar);
		}
		if (folio == null) { folio = siguienteFolio(policyId); }
		for (Movimiento_Poliza__c m : l) { m.Solicitud__c = folio; }
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
	 *               'En proceso' (abierto que no es el inicial) o 'Concluido' (cerrado, sin contar Merged).
	 * @param buscado: 'Creado', 'En proceso' o 'Concluido'.
	 * @return el valor del org, o null.
	 */
	public static String estadoCaso(String buscado) {
		String inicial;
		String abierto;
		String cerrado;
		for (CaseStatus s : [SELECT ApiName, IsClosed, IsDefault FROM CaseStatus ORDER BY SortOrder]) {
			if (s.ApiName == buscado) { return s.ApiName; }
			if (s.IsDefault && inicial == null) { inicial = s.ApiName; }
			else if (!s.IsClosed && abierto == null) { abierto = s.ApiName; }
			else if (s.IsClosed && s.ApiName != 'Merged' && cerrado == null) { cerrado = s.ApiName; }
		}
		return buscado == 'Creado' ? inicial : (buscado == 'Concluido' ? cerrado : abierto);
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
			String t = m.Tipo__c == 'Alta' ? 'altas' : (m.Tipo__c == 'Baja' ? 'bajas' : 'cambios');
			s.put(t, (Integer) s.get(t) + 1);
			if (m.Fecha_Cierre__c == null) { s.put('abiertos', (Integer) s.get('abiertos') + 1); }
			List<String> e = (List<String>) s.get('endosos');
			if (String.isNotBlank(m.Numero_Endoso__c) && !e.contains(m.Numero_Endoso__c.trim())) { e.add(m.Numero_Endoso__c.trim()); }
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
			if (s == null) {
				s = nuevaSolicitud(c.Solicitud__c, c.CreatedDate, null);
				porFolio.put(c.Solicitud__c, s);
			}
			Integer total = (Integer) s.get('total');
			Integer abiertos = (Integer) s.get('abiertos');
			String estado = c.IsClosed ? (total == 0 ? 'Rechazada' : 'Cerrada') : (total == 0 ? 'Recibida' : (abiertos > 0 ? 'En proceso' : 'Cerrada'));
			s.putAll(new Map<String, Object>{
				'fecha' => c.CreatedDate, 'portal' => true, 'casoId' => c.Id, 'caso' => c.CaseNumber, 'estadoPortal' => estado,
				'pendiente' => estado == 'Recibida', 'enviadaPor' => c.CreatedBy == null ? null : c.CreatedBy.Name,
				'usuario' => c.CreatedBy == null ? null : c.CreatedBy.Name,
				'asunto' => c.Subject, 'descripcion' => c.Description, 'comentario' => c.Comentarios__c,
				'respuesta' => comentarios.get(c.Id),
				'documentos' => docs.containsKey(c.Id) ? docs.get(c.Id) : new List<Map<String, Object>>()
			});
		}
		// Más reciente primero.
		List<SolicitudOrden> orden = new List<SolicitudOrden>();
		for (Map<String, Object> s : porFolio.values()) { orden.add(new SolicitudOrden(s)); }
		orden.sort();
		List<Map<String, Object>> res = new List<Map<String, Object>>();
		for (SolicitudOrden o : orden) { res.add(o.s); }
		return res;
	}

	private static Map<String, Object> nuevaSolicitud(String folio, Datetime fecha, String usuario) {
		return new Map<String, Object>{
			'folio' => folio, 'fecha' => fecha, 'usuario' => usuario, 'portal' => false,
			'total' => 0, 'altas' => 0, 'bajas' => 0, 'cambios' => 0, 'abiertos' => 0, 'endosos' => new List<String>()
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
	 * @creation date: 17/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: El ejecutivo rechaza una solicitud que el cliente envió desde el sitio: el motivo queda como
	 *               comentario público del caso (el cliente lo ve en el sitio) y el caso se concluye.
	 * @param casoId: caso de la solicitud.
	 * @param motivo: por qué no procede.
	 */
	@AuraEnabled(cacheable=false)
	public static void rechazarSolicitud(Id casoId, String motivo) {
		if (casoId == null || String.isBlank(motivo)) { throw new AuraHandledException('Escribe el motivo del rechazo.'); }
		try {
			new SinCompartir().rechazar(casoId, motivo.trim(), estadoCaso('Concluido'));
		} catch (Exception e) {
			AuraHandledException ex = new AuraHandledException('No se pudo rechazar la solicitud: ' + e.getMessage());
			ex.setMessage('No se pudo rechazar la solicitud: ' + e.getMessage());
			throw ex;
		}
	}

	// Casos del sitio: el ejecutivo los ve y los atiende aunque no sea su dueño.
	private without sharing class SinCompartir {
		List<Case> casosDe(Id policyId, String folio) {
			Id rt = tipoCaso();
			if (rt == null) { return new List<Case>(); }
			String q = 'SELECT Id, CaseNumber, Solicitud__c, Status, IsClosed, Subject, Description, Comentarios__c, CreatedDate,'
				+ ' CreatedBy.Name FROM Case WHERE RecordTypeId = :rt AND InsurancePolicy__c = :policyId AND Solicitud__c != null'
				+ (folio == null ? '' : ' AND Solicitud__c = :folio') + ' ORDER BY CreatedDate DESC LIMIT 500';
			return Database.queryWithBinds(q, new Map<String, Object>{ 'rt' => rt, 'policyId' => policyId, 'folio' => folio }, AccessLevel.SYSTEM_MODE);
		}
		List<Movimiento_Poliza__c> movimientos(Id policyId) {
			return [
				SELECT Solicitud__c, Tipo__c, Numero_Endoso__c, CreatedDate, CreatedBy.Name, Fecha_Cierre__c, Participante__c, Inciso__c
				FROM Movimiento_Poliza__c WHERE Poliza__c = :policyId AND Solicitud__c != null ORDER BY CreatedDate, Id LIMIT 10000
			];
		}
		List<Case> casos(Id policyId) { return casosDe(policyId, null); }
		List<Case> casosDeFolio(Id policyId, String folio) { return casosDe(policyId, folio); }
		void actualizar(List<Case> l) { if (!l.isEmpty()) { update l; } }
		List<ContentDocumentLink> archivos(Set<Id> ids) {
			return [SELECT LinkedEntityId, ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension
				FROM ContentDocumentLink WHERE LinkedEntityId IN :ids];
		}
		List<CaseComment> comentarios(Set<Id> ids) {
			return [SELECT ParentId, CommentBody FROM CaseComment WHERE ParentId IN :ids AND IsPublished = true ORDER BY CreatedDate DESC];
		}
		void rechazar(Id casoId, String motivo, String cerrado) {
			insert new CaseComment(ParentId = casoId, IsPublished = true, CommentBody = ('Solicitud rechazada: ' + motivo).left(4000));
			update new Case(Id = casoId, Status = cerrado);
		}
		// Al cerrar los movimientos de una solicitud del sitio, su caso se concluye.
		void concluir(Set<Id> movimientoIds) {
			Map<Id, Set<String>> folios = new Map<Id, Set<String>>();
			for (Movimiento_Poliza__c m : [SELECT Poliza__c, Solicitud__c FROM Movimiento_Poliza__c WHERE Id IN :movimientoIds AND Solicitud__c != null AND Poliza__c != null]) {
				if (!folios.containsKey(m.Poliza__c)) { folios.put(m.Poliza__c, new Set<String>()); }
				folios.get(m.Poliza__c).add(m.Solicitud__c);
			}
			Id rt = tipoCaso();
			if (folios.isEmpty() || rt == null) { return; }
			Set<String> todos = new Set<String>();
			for (Set<String> s : folios.values()) { todos.addAll(s); }
			Set<String> abiertos = new Set<String>();
			for (Movimiento_Poliza__c m : [
				SELECT Poliza__c, Solicitud__c FROM Movimiento_Poliza__c
				WHERE Poliza__c IN :folios.keySet() AND Solicitud__c IN :todos AND Fecha_Cierre__c = null
			]) { abiertos.add(m.Poliza__c + '|' + m.Solicitud__c); }
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
			SELECT Id, Name, Tipo__c, Fecha_Movimiento__c, Numero_Endoso__c, Asegurado__c, Certificado__c, Participante__c,
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
			for (Movimiento_Poliza__c m : grupos.get(k)) {
				if (m.Fecha_Movimiento__c != null && (fecha == null || m.Fecha_Movimiento__c < fecha)) { fecha = m.Fecha_Movimiento__c; }
			}
			if (fecha == null) { fecha = Date.today(); }
			String numero = k == '' ? null : k;
			InsurancePolicyTransaction t = numero == null ? null : existentes.get(numero);
			esNueva.add(t == null);
			if (t == null) {
				t = new InsurancePolicyTransaction(InsurancePolicyId = policyId, TransactionNumber = numero, Category = categoria);
				t.Name = ('Endoso ' + (numero != null ? numero : fechaTexto(fecha)) + ' - ' + poliza).left(80);
				t.Status = pendiente;
				t.TransactionEffectiveDate = Datetime.newInstance(fecha, Time.newInstance(12, 0, 0, 0));
				t.EffectiveFromDate = fecha;
			} else if (t.Status != pendiente) {
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
		// Solicitudes del sitio cuyos movimientos ya están todos cerrados: su caso se concluye.
		new SinCompartir().concluir(movimientoIds);
		Set<Id> trans = new Set<Id>();
		for (Movimiento_Poliza__c m : [SELECT Transaccion__c FROM Movimiento_Poliza__c WHERE Id IN :movimientoIds AND Transaccion__c != null]) {
			trans.add(m.Transaccion__c);
		}
		if (trans.isEmpty()) { return; }
		for (AggregateResult ar : [
			SELECT Transaccion__c t FROM Movimiento_Poliza__c WHERE Transaccion__c IN :trans AND Fecha_Cierre__c = null GROUP BY Transaccion__c
		]) { trans.remove((Id) ar.get('t')); }
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
