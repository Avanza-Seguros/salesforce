/**
 * @creation date: 26/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Captura de siniestros en Claims (FSC) para los componentes nuevoSiniestro, siniestroSolicitud y
 *               siniestroPago. Un siniestro (Claim) se liga a su póliza (InsurancePolicy), a su asegurado del censo
 *               (ClaimParticipant → InsurancePolicyParticipant; si es dependiente, también su titular como reclamante) y a
 *               una cobertura (ClaimCoverage, ligada a la de la póliza si la tiene). Cada folio de reembolso, inicial o
 *               complementario, es una solicitud de pago (PaymentRequest con su línea de monto reclamado), y lo que paga
 *               la aseguradora queda como pago por cobertura (ClaimCoveragePaymentDetail) dentro de un pago agrupado
 *               (ClaimPaymentSummary). El siniestro lleva el total reclamado (EstimatedAmount) y el pagado (ActualAmount).
 */
public with sharing class SiniestrosController {

	private static final Integer MAX_RESULTADOS = 50;

	/** Datos capturados en Nuevo siniestro. */
	public class DatosSiniestro {
		public Id policyId;
		public Id participanteId;
		public String ramo;
		public String causa;
		public String tipo;
		public String fecha;
		public String diagnostico;
		public String hospital;
		public String fechaAtencion;
		public String medio;
		public String numeroAseguradora;
		public String observaciones;
		public Id coberturaId;
		public DatosSolicitud solicitud;
	}

	/** Solicitud de pago (folio de reembolso). */
	public class DatosSolicitud {
		public String fechaRecepcion;
		public Decimal monto;
		public String documentacion;
		public Id proveedorId;
		public String referencia;
	}

	/** Pago de la aseguradora a una solicitud. */
	public class DatosPago {
		public Id solicitudId;
		public Decimal monto;
		public String fecha;
		public String identificador;
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Tipo de registro de los siniestros de personas (para los valores de sus listas).
	 * @return recordTypeId
	 */
	@AuraEnabled(cacheable=true)
	public static Map<String, Object> inicio() {
		return new Map<String, Object>{
			'recordTypeId' => Schema.SObjectType.Claim.getRecordTypeInfosByDeveloperName().get('Personas').getRecordTypeId()
		};
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Pólizas por número o por contratante (las más recientes primero).
	 * @param texto: número de póliza o nombre del contratante (al menos 3 caracteres).
	 * @return pólizas con su contratante, ramo, aseguradora y vigencia.
	 */
	@AuraEnabled(cacheable=false)
	public static List<Map<String, Object>> buscarPolizas(String texto) {
		List<Map<String, Object>> res = new List<Map<String, Object>>();
		String t = String.isBlank(texto) ? '' : texto.trim();
		if (t.length() < 3) { return res; }
		String patron = '%' + t + '%';
		for (InsurancePolicy p : [
			SELECT Id, Name, NameInsured.Name, Ramo__c, Status, EffectiveDate, ExpirationDate, Aseguradora__r.Name, Product.Aseguradora__r.Name
			FROM InsurancePolicy WHERE Name LIKE :patron OR NameInsured.Name LIKE :patron
			ORDER BY EffectiveDate DESC NULLS LAST LIMIT :MAX_RESULTADOS
		]) { res.add(poliza(p)); }
		return res;
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Póliza elegida: sus datos, el ramo que le toca al siniestro y sus coberturas.
	 * @param policyId: póliza.
	 * @return poliza, ramo y coberturas.
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> datosPoliza(Id policyId) {
		List<InsurancePolicy> l = [
			SELECT Id, Name, NameInsured.Name, Ramo__c, Status, EffectiveDate, ExpirationDate, Aseguradora__r.Name, Product.Aseguradora__r.Name
			FROM InsurancePolicy WHERE Id = :policyId LIMIT 1
		];
		if (l.isEmpty()) { throw CensoColectivoController.error('No tienes acceso a la póliza.'); }
		List<Map<String, Object>> coberturas = new List<Map<String, Object>>();
		for (InsurancePolicyCoverage c : [
			SELECT Id, CoverageName, LimitAmount FROM InsurancePolicyCoverage WHERE InsurancePolicyId = :policyId ORDER BY CoverageName LIMIT 200
		]) { coberturas.add(new Map<String, Object>{ 'id' => c.Id, 'nombre' => c.CoverageName, 'suma' => c.LimitAmount }); }
		return new Map<String, Object>{ 'poliza' => poliza(l[0]), 'ramo' => ramoDe(l[0].Ramo__c), 'coberturas' => coberturas };
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Asegurados de la póliza por nombre o certificado (los vigentes primero).
	 * @param policyId: póliza.
	 * @param texto: nombre o certificado; vacío = los primeros.
	 * @return asegurados con su certificado, si es titular o de quién es dependiente y si sigue vigente.
	 */
	@AuraEnabled(cacheable=false)
	public static List<Map<String, Object>> buscarAsegurados(Id policyId, String texto) {
		String patron = '%' + (String.isBlank(texto) ? '' : texto.trim()) + '%';
		List<Map<String, Object>> res = new List<Map<String, Object>>();
		for (InsurancePolicyParticipant p : [
			SELECT Id, ParticipantName, ParticipantCode, IsActiveParticipant, RelatedInsPolicyParticipantId,
				RelatedInsPolicyParticipant.ParticipantName
			FROM InsurancePolicyParticipant
			WHERE InsurancePolicyId = :policyId AND (ParticipantName LIKE :patron OR ParticipantCode LIKE :patron)
			ORDER BY IsActiveParticipant DESC, ParticipantName ASC LIMIT :MAX_RESULTADOS
		]) {
			res.add(new Map<String, Object>{
				'id' => p.Id, 'nombre' => p.ParticipantName, 'certificado' => p.ParticipantCode, 'vigente' => p.IsActiveParticipant,
				'titular' => p.RelatedInsPolicyParticipantId == null ? null : p.RelatedInsPolicyParticipant.ParticipantName
			});
		}
		return res;
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Registra el siniestro con su asegurado (y su titular, si es dependiente), su cobertura y, si se
	 *               capturó, su primera solicitud de pago. Todo o nada.
	 * @param datosJson: DatosSiniestro en JSON.
	 * @return claimId, folio y solicitudId (si hubo solicitud).
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> crearSiniestro(String datosJson) {
		DatosSiniestro d;
		try {
			d = (DatosSiniestro) JSON.deserialize(datosJson, DatosSiniestro.class);
		} catch (Exception e) {
			throw CensoColectivoController.error('Los datos del siniestro no tienen un formato válido.');
		}
		if (d.policyId == null) { throw CensoColectivoController.error('Elige la póliza.'); }
		if (d.participanteId == null) { throw CensoColectivoController.error('Elige al asegurado afectado.'); }
		if (String.isBlank(d.fecha)) { throw CensoColectivoController.error('Indica la fecha del siniestro.'); }
		List<InsurancePolicyParticipant> asegurados = [
			SELECT Id, ParticipantName, InsurancePolicyId, PrimaryParticipantContactId, PrimaryParticipantAccountId,
				RelatedInsPolicyParticipantId, RelatedInsPolicyParticipant.PrimaryParticipantContactId,
				RelatedInsPolicyParticipant.PrimaryParticipantAccountId
			FROM InsurancePolicyParticipant WHERE Id = :d.participanteId LIMIT 1
		];
		if (asegurados.isEmpty() || asegurados[0].InsurancePolicyId != d.policyId) {
			throw CensoColectivoController.error('El asegurado no pertenece a la póliza.');
		}
		InsurancePolicyParticipant a = asegurados[0];
		Savepoint sp = Database.setSavepoint();
		try {
			Claim c = new Claim(Name = 'Nuevo siniestro', RecordTypeId = (Id) inicio().get('recordTypeId'), PolicyNumberId = d.policyId,
				Status = 'Abierto', ClaimType = d.ramo, ClaimReasonType = d.causa, LossType = d.tipo, LossDate = mediodia(d.fecha),
				ReportDate = Datetime.now(), ClaimReason = texto(d.diagnostico, 255), VisitSite = texto(d.hospital, 32000),
				VisitDate = mediodia(d.fechaAtencion), FnolChannel = d.medio, SourceSystemIdentifier = texto(d.numeroAseguradora, 255),
				Summary = texto(d.observaciones, 32000));
			insert c;
			// Afectado (paciente) y, si es dependiente, su titular como reclamante.
			ClaimParticipant afectado = new ClaimParticipant(ClaimId = c.Id, InsurancePolicyParticipantId = a.Id, Roles = 'Paciente',
				IsInjured = true, ParticipantContactId = a.PrimaryParticipantContactId, ParticipantAccountId = a.PrimaryParticipantAccountId);
			List<ClaimParticipant> participantes = new List<ClaimParticipant>{ afectado };
			if (a.RelatedInsPolicyParticipantId != null) {
				participantes.add(new ClaimParticipant(ClaimId = c.Id, InsurancePolicyParticipantId = a.RelatedInsPolicyParticipantId,
					Roles = 'Reclamante', IsInjured = false, ParticipantContactId = a.RelatedInsPolicyParticipant.PrimaryParticipantContactId,
					ParticipantAccountId = a.RelatedInsPolicyParticipant.PrimaryParticipantAccountId));
			} else {
				afectado.Roles = 'Paciente;Reclamante';
			}
			insert participantes;
			// Cobertura del siniestro: la de la póliza que se eligió o, si la póliza no las tiene, una con el tipo de siniestro.
			String nombreCobertura = String.isNotBlank(d.tipo) ? d.tipo : 'Siniestro';
			if (d.coberturaId != null) {
				for (InsurancePolicyCoverage pc : [SELECT CoverageName FROM InsurancePolicyCoverage WHERE Id = :d.coberturaId AND InsurancePolicyId = :d.policyId]) {
					nombreCobertura = pc.CoverageName;
				}
			}
			insert new ClaimCoverage(ClaimId = c.Id, Name = nombreCobertura.left(80), InternalReserveMode = 'ReserveInapplicable', Status = 'Abierto',
				ClaimParticipantId = afectado.Id, InsurancePolicyParticipantId = a.Id, InsurancePolicyCoverageId = d.coberturaId);
			Id solicitudId = d.solicitud == null ? null : nuevaSolicitud(c.Id, d.policyId, a.Id, d.solicitud);
			totales(new Set<Id>{ c.Id });
			return new Map<String, Object>{ 'claimId' => c.Id, 'folio' => [SELECT Name FROM Claim WHERE Id = :c.Id].Name, 'solicitudId' => solicitudId };
		} catch (Exception e) {
			Database.rollback(sp);
			throw CensoColectivoController.error('No se registró el siniestro: ' + mensaje(e));
		}
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Datos del siniestro para sus acciones: folio y sus solicitudes de pago con lo reclamado y lo pagado.
	 * @param claimId: siniestro.
	 * @return folio, estatus y solicitudes.
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> datosSiniestro(Id claimId) {
		List<Claim> l = [SELECT Id, Name, Status, IsClosed, PolicyNumberId FROM Claim WHERE Id = :claimId LIMIT 1];
		if (l.isEmpty()) { throw CensoColectivoController.error('No tienes acceso al siniestro.'); }
		Map<Id, Decimal> pagado = new Map<Id, Decimal>();
		for (ClaimCoveragePaymentDetail p : [
			SELECT AdjustedAmount, PaymentRequestLine.PaymentRequestId FROM ClaimCoveragePaymentDetail
			WHERE ClaimCoverage.ClaimId = :claimId AND PaymentRequestLineId != null AND Status = 'Pagado'
		]) {
			Id r = p.PaymentRequestLine.PaymentRequestId;
			pagado.put(r, (pagado.containsKey(r) ? pagado.get(r) : 0) + (p.AdjustedAmount == null ? 0 : p.AdjustedAmount));
		}
		List<Map<String, Object>> solicitudes = new List<Map<String, Object>>();
		for (PaymentRequest r : [
			SELECT Id, Name, Status, ReceivedDate, TotalRequestedAmount FROM PaymentRequest WHERE ClaimId = :claimId ORDER BY Name
		]) {
			solicitudes.add(new Map<String, Object>{ 'id' => r.Id, 'nombre' => r.Name, 'estatus' => r.Status, 'recibida' => r.ReceivedDate,
				'reclamado' => r.TotalRequestedAmount, 'pagado' => pagado.get(r.Id) });
		}
		return new Map<String, Object>{ 'folio' => l[0].Name, 'estatus' => l[0].Status, 'cerrado' => l[0].IsClosed, 'solicitudes' => solicitudes };
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Reembolso complementario: otra solicitud de pago del mismo siniestro, para el mismo asegurado.
	 * @param claimId: siniestro.
	 * @param datosJson: DatosSolicitud en JSON.
	 * @return solicitudId y su folio.
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> crearSolicitud(Id claimId, String datosJson) {
		DatosSolicitud d;
		try {
			d = (DatosSolicitud) JSON.deserialize(datosJson, DatosSolicitud.class);
		} catch (Exception e) {
			throw CensoColectivoController.error('Los datos de la solicitud no tienen un formato válido.');
		}
		List<Claim> l = [SELECT Id, PolicyNumberId, IsClosed FROM Claim WHERE Id = :claimId LIMIT 1];
		if (l.isEmpty()) { throw CensoColectivoController.error('No tienes acceso al siniestro.'); }
		if (l[0].IsClosed) { throw CensoColectivoController.error('El siniestro está cerrado: reábrelo para registrar otro reembolso.'); }
		Savepoint sp = Database.setSavepoint();
		try {
			Id solicitudId = nuevaSolicitud(claimId, l[0].PolicyNumberId, afectadoDe(claimId), d);
			totales(new Set<Id>{ claimId });
			return new Map<String, Object>{ 'solicitudId' => solicitudId, 'folio' => [SELECT Name FROM PaymentRequest WHERE Id = :solicitudId].Name };
		} catch (Exception e) {
			Database.rollback(sp);
			throw CensoColectivoController.error('No se registró la solicitud: ' + mensaje(e));
		}
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Pago de la aseguradora a una solicitud: pago agrupado (ClaimPaymentSummary) y pago por cobertura
	 *               (ClaimCoveragePaymentDetail, ligado a la línea de la solicitud). La solicitud queda Pagada y el
	 *               siniestro actualiza su total pagado.
	 * @param claimId: siniestro.
	 * @param datosJson: DatosPago en JSON.
	 * @return pagoId.
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> registrarPago(Id claimId, String datosJson) {
		DatosPago d;
		try {
			d = (DatosPago) JSON.deserialize(datosJson, DatosPago.class);
		} catch (Exception e) {
			throw CensoColectivoController.error('Los datos del pago no tienen un formato válido.');
		}
		if (d.monto == null || d.monto <= 0) { throw CensoColectivoController.error('Indica el monto que pagó la aseguradora.'); }
		List<PaymentRequest> rs = [
			SELECT Id, Name, ClaimId, TotalRequestedAmount, (SELECT Id, RequestedAmount FROM PaymentRequestLines ORDER BY CreatedDate LIMIT 1)
			FROM PaymentRequest WHERE Id = :d.solicitudId LIMIT 1
		];
		if (rs.isEmpty() || rs[0].ClaimId != claimId) { throw CensoColectivoController.error('Elige una solicitud de este siniestro.'); }
		PaymentRequest r = rs[0];
		List<ClaimCoverage> coberturas = [SELECT Id, ClaimParticipantId FROM ClaimCoverage WHERE ClaimId = :claimId ORDER BY CreatedDate LIMIT 1];
		Savepoint sp = Database.setSavepoint();
		try {
			ClaimCoverage cob = coberturas.isEmpty() ? null : coberturas[0];
			if (cob == null) {
				cob = new ClaimCoverage(ClaimId = claimId, Name = 'Siniestro', InternalReserveMode = 'ReserveInapplicable', Status = 'Abierto');
				insert cob;
			}
			Date fecha = String.isBlank(d.fecha) ? Date.today() : Date.valueOf(d.fecha);
			ClaimPaymentSummary resumen = new ClaimPaymentSummary(ClaimId = claimId, Name = (r.Name + ' · Pago').left(80), PaymentAmount = d.monto,
				PaymentDate = fecha, PaymentIdentifier = texto(d.identificador, 255), PaymentStatus = 'Pagado');
			insert resumen;
			Id linea = r.PaymentRequestLines.isEmpty() ? null : r.PaymentRequestLines[0].Id;
			insert new ClaimCoveragePaymentDetail(ClaimCoverageId = cob.Id, Name = r.Name.left(80), ClaimedAmount = r.TotalRequestedAmount,
				AdjustedAmount = d.monto, Status = 'Pagado', Type = 'Loss', ClaimPaymentSummaryId = resumen.Id, PaymentRequestLineId = linea,
				ClaimParticipantRecipientId = cob.ClaimParticipantId, ScheduledPaymentDate = fecha);
			update new PaymentRequest(Id = r.Id, Status = 'Pagado');
			if (linea != null) {
				Boolean completo = r.TotalRequestedAmount == null || d.monto >= r.TotalRequestedAmount;
				update new PaymentRequestLine(Id = linea, Status = completo ? 'Pagado' : 'Pagado parcialmente', ServiceAmount = d.monto);
			}
			totales(new Set<Id>{ claimId });
			return new Map<String, Object>{ 'pagoId' => resumen.Id };
		} catch (Exception e) {
			Database.rollback(sp);
			throw CensoColectivoController.error('No se registró el pago: ' + mensaje(e));
		}
	}

	// Solicitud de pago con su línea de monto reclamado (el total de la solicitud lo calcula FSC con sus líneas).
	private static Id nuevaSolicitud(Id claimId, Id policyId, Id participanteId, DatosSolicitud d) {
		PaymentRequest r = new PaymentRequest(Name = 'Nueva solicitud', ClaimId = claimId, InsurancePolicyId = policyId, Status = 'Recibido',
			ReceivedDate = String.isBlank(d.fechaRecepcion) ? Date.today() : Date.valueOf(d.fechaRecepcion), SubmissionType = 'Factura',
			ServiceRecipientId = participanteId, ServiceProviderId = d.proveedorId, ReferenceNumber = texto(d.referencia, 255),
			Documentacion_Ingresada__c = String.isBlank(d.documentacion) ? null : d.documentacion);
		insert r;
		if (d.monto != null && d.monto > 0) {
			insert new PaymentRequestLine(PaymentRequestId = r.Id, Name = 'Monto reclamado', RequestedAmount = d.monto, Status = 'Recibido',
				ServiceProviderId = d.proveedorId);
		}
		return r.Id;
	}

	// Asegurado afectado del siniestro (su participante paciente).
	private static Id afectadoDe(Id claimId) {
		for (ClaimParticipant p : [
			SELECT InsurancePolicyParticipantId, Roles FROM ClaimParticipant WHERE ClaimId = :claimId AND InsurancePolicyParticipantId != null
			ORDER BY CreatedDate
		]) {
			if (p.Roles != null && p.Roles.contains('Paciente')) { return p.InsurancePolicyParticipantId; }
		}
		return null;
	}

	// Totales del siniestro: lo reclamado en sus solicitudes y lo pagado por la aseguradora.
	private static void totales(Set<Id> claimIds) {
		Map<Id, Claim> cambios = new Map<Id, Claim>();
		for (Id i : claimIds) { cambios.put(i, new Claim(Id = i, EstimatedAmount = 0, ActualAmount = 0)); }
		for (AggregateResult ar : [SELECT ClaimId c, SUM(TotalRequestedAmount) s FROM PaymentRequest WHERE ClaimId IN :claimIds GROUP BY ClaimId]) {
			cambios.get((Id) ar.get('c')).EstimatedAmount = (Decimal) ar.get('s');
		}
		for (AggregateResult ar : [
			SELECT ClaimId c, SUM(PaymentAmount) s FROM ClaimPaymentSummary WHERE ClaimId IN :claimIds AND PaymentStatus = 'Pagado' GROUP BY ClaimId
		]) {
			cambios.get((Id) ar.get('c')).ActualAmount = (Decimal) ar.get('s');
		}
		update cambios.values();
	}

	private static Map<String, Object> poliza(InsurancePolicy p) {
		String aseguradora = p.Aseguradora__r != null ? p.Aseguradora__r.Name
			: (p.Product != null && p.Product.Aseguradora__r != null ? p.Product.Aseguradora__r.Name : null);
		return new Map<String, Object>{
			'id' => p.Id, 'numero' => p.Name, 'contratante' => p.NameInsured == null ? null : p.NameInsured.Name, 'ramo' => p.Ramo__c,
			'estatus' => p.Status, 'aseguradora' => aseguradora,
			'inicio' => p.EffectiveDate == null ? null : p.EffectiveDate.dateGmt(), 'fin' => p.ExpirationDate == null ? null : p.ExpirationDate.dateGmt()
		};
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Ramo del siniestro (ClaimType) según el ramo de la póliza.
	 * @param ramo: Ramo__c de la póliza.
	 * @return valor de ClaimType; null si no es de personas.
	 */
	@TestVisible
	private static String ramoDe(String ramo) {
		String r = ramo == null ? '' : ramo.toLowerCase();
		if (r.contains('gasto') || r.contains('gmm') || r.contains('salud')) { return 'Gastos médicos mayores'; }
		if (r.contains('accidente')) { return 'Accidentes personales'; }
		if (r.contains('vida')) { return 'Vida'; }
		return null;
	}

	// Fecha capturada (AAAA-MM-DD) a mediodía GMT, como las fechas de las pólizas.
	private static Datetime mediodia(String fecha) {
		if (String.isBlank(fecha)) { return null; }
		Date d = Date.valueOf(fecha.left(10));
		return Datetime.newInstanceGmt(d.year(), d.month(), d.day(), 12, 0, 0);
	}

	private static String texto(String v, Integer largo) {
		return String.isBlank(v) ? null : v.trim().left(largo);
	}

	// Mensaje legible de un error de DML (el de la validación, sin el prefijo técnico).
	private static String mensaje(Exception e) {
		if (e instanceof DmlException) { return ((DmlException) e).getDmlMessage(0); }
		return e.getMessage();
	}
}
