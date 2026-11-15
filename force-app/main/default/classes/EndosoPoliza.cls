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
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Registra (o completa) el endoso con los movimientos insertados en esta transacción de Apex.
	 * @param policyId: póliza.
	 * @param p: prima del endoso (opcional).
	 * @return Id de la transacción del endoso, o null si no hubo movimientos.
	 */
	public static Id registrar(Id policyId, Prima p) {
		Set<Id> ids = new Map<Id, Movimiento_Poliza__c>(insertados).keySet();
		insertados = new List<Movimiento_Poliza__c>();
		if (ids.isEmpty() || policyId == null) { return null; }
		List<Movimiento_Poliza__c> movs = [
			SELECT Id, Name, Tipo__c, Fecha_Movimiento__c, Numero_Endoso__c, Asegurado__c, Certificado__c, Participante__c,
				Participante__r.StandardPremiumAmount, Inciso__c, Inciso__r.Vehiculo__c, Inciso__r.Prima__c
			FROM Movimiento_Poliza__c WHERE Id IN :ids ORDER BY CreatedDate, Id
		];
		String numero = null;
		Date fecha = null;
		for (Movimiento_Poliza__c m : movs) {
			if (numero == null && String.isNotBlank(m.Numero_Endoso__c)) { numero = m.Numero_Endoso__c.trim(); }
			if (m.Fecha_Movimiento__c != null && (fecha == null || m.Fecha_Movimiento__c < fecha)) { fecha = m.Fecha_Movimiento__c; }
		}
		if (fecha == null) { fecha = Date.today(); }
		String categoria = valor(InsurancePolicyTransaction.Category.getDescribe(), 'Endorsement');

		// Mismo número de endoso en la póliza: se completa ese endoso.
		InsurancePolicyTransaction t = null;
		if (numero != null) {
			for (InsurancePolicyTransaction ex : [
				SELECT Id, Name, Status, TransactionEffectiveDate, EffectiveFromDate FROM InsurancePolicyTransaction
				WHERE InsurancePolicyId = :policyId AND TransactionNumber = :numero AND Category = :categoria
				ORDER BY CreatedDate LIMIT 1
			]) { t = ex; }
		}
		if (t == null) {
			InsurancePolicy pol = [SELECT Name FROM InsurancePolicy WHERE Id = :policyId];
			t = new InsurancePolicyTransaction(InsurancePolicyId = policyId, TransactionNumber = numero, Category = categoria);
			t.Name = ('Endoso ' + (numero != null ? numero : fechaTexto(fecha)) + ' - ' + pol.Name).left(80);
			t.Status = valor(InsurancePolicyTransaction.Status.getDescribe(), 'Pendiente');
			t.TransactionEffectiveDate = Datetime.newInstance(fecha, Time.newInstance(12, 0, 0, 0));
			t.EffectiveFromDate = fecha;
			// El endoso sigue a la transacción anterior de la póliza (la emisión u otro endoso).
			for (InsurancePolicyTransaction anterior : [
				SELECT Id FROM InsurancePolicyTransaction WHERE InsurancePolicyId = :policyId ORDER BY CreatedDate DESC, Id DESC LIMIT 1
			]) { t.PriorTransactionId = anterior.Id; }
		} else if (t.Status != valor(InsurancePolicyTransaction.Status.getDescribe(), 'Pendiente')) {
			// Se le agregan movimientos abiertos: vuelve a quedar pendiente.
			t.Status = valor(InsurancePolicyTransaction.Status.getDescribe(), 'Pendiente');
		}
		// Prima de la aseguradora: la que viene en el documento del endoso (no se calcula).
		if (p != null) {
			if (p.primaNeta != null) { t.TransactionAmount = p.primaNeta; }
			if (p.derechos != null) { t.TransactionFeeAmount = p.derechos; }
			if (p.iva != null) { t.TransactionTaxAmount = p.iva; }
			if (p.total != null) {
				try { t.put('TotalTransactionAmount', p.total); } catch (Exception ignore) { /* Calculado por la plataforma en algunos orgs. */ }
			}
		}
		upsert t;

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
		for (Movimiento_Poliza__c m : movs) {
			m.Transaccion__c = t.Id;
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
			InsPolicyTransactionDetail d = new InsPolicyTransactionDetail(InsurancePolicyTransactionId = t.Id,
				Name = ((m.Tipo__c == null ? 'Movimiento' : m.Tipo__c) + ' - ' + (m.Asegurado__c == null ? m.Name : m.Asegurado__c)).left(80));
			if (ref != null) { d.ReferenceObjectId = ref; }
			// La baja no suma prima: lo que devuelve la aseguradora va en la prima del endoso.
			if (m.Tipo__c != 'Baja' && prima != null) { d.Premium = prima; }
			detalles.add(d);
		}
		if (!detalles.isEmpty()) { insert detalles; }
		update movs;
		return t.Id;
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
