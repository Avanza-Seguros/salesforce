/**
 * @creation date: 26/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Captura de siniestros en Claims (FSC) para los componentes nuevoSiniestro, siniestroSolicitud,
 *               siniestroPago y siniestrosPoliza. Un siniestro (Claim) se liga a su póliza (InsurancePolicy) y a lo
 *               afectado, según la familia del ramo de la póliza (la misma regla que muestra las pestañas Asegurados,
 *               Vehículos y Ubicaciones):
 *               - Personas (tipo de registro Personas): su asegurado del censo (ClaimParticipant → InsurancePolicyParticipant;
 *                 si es dependiente, también su titular como reclamante).
 *               - Automóviles (Autos) y Daños (Danos): el bien de la póliza (InsurancePolicyAsset del vehículo o de la
 *                 ubicación) en Claim.InsuredAssetId y en InsuranceClaimAsset, con el contratante como reclamante.
 *               La cobertura (ClaimCoverage) se liga a la de la póliza si la tiene. Cada folio de reembolso, inicial o
 *               complementario, es una solicitud de pago (PaymentRequest con su línea de monto reclamado), y lo que paga
 *               la aseguradora queda como pago por cobertura (ClaimCoveragePaymentDetail) dentro de un pago agrupado
 *               (ClaimPaymentSummary). El siniestro lleva el total reclamado (EstimatedAmount) y el pagado (ActualAmount).
 *               La pestaña Siniestros de la póliza muestra sus siniestros, su siniestralidad (pagado contra prima neta)
 *               y, de solo consulta, los folios de siniestro anteriores de ese número de póliza en Control de Folios.
 */
public with sharing class SiniestrosController {

	private static final Integer MAX_RESULTADOS = 50;
	private static final Integer MAX_BIENES = 5000;
	private static final Integer MAX_LISTA = 1000;
	public static final String PERSONAS = 'personas';
	public static final String AUTOS = 'autos';
	public static final String DANOS = 'danos';
	// Tipo de registro de Claim de cada familia.
	private static final Map<String, String> TIPO_POR_FAMILIA = new Map<String, String>{
		PERSONAS => 'Personas', AUTOS => 'Autos', DANOS => 'Danos'
	};

	/** Datos capturados en Nuevo siniestro. */
	public class DatosSiniestro {
		public Id policyId;
		// Personas: el asegurado afectado.
		public Id participanteId;
		// Automóviles y Daños: el bien afectado (InsurancePolicyAsset).
		public Id bienId;
		public String ramo;
		public String causa;
		public String tipo;
		public String fecha;
		public String diagnostico;
		public String hospital;
		public String fechaAtencion;
		public String lugar;
		public String medio;
		public String numeroAseguradora;
		public String observaciones;
		// Correo para avisos (si no se captura, el del titular o, en un bien, el del contratante).
		public String correo;
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

	// Bien de la póliza (vehículo o ubicación) como se muestra al elegirlo; se ordena como en sus pestañas: los vigentes
	// primero y por número de inciso.
	private class Bien implements Comparable {
		Id id;
		Id incisoId;
		String nombre;
		String detalle;
		Boolean vigente;
		Integer inciso;
		String busqueda;
		public Integer compareTo(Object o) {
			Bien b = (Bien) o;
			if (vigente != b.vigente) { return vigente ? -1 : 1; }
			Integer x = inciso == null ? 2147483647 : inciso;
			Integer y = b.inciso == null ? 2147483647 : b.inciso;
			if (x != y) { return x < y ? -1 : 1; }
			return (nombre == null ? '' : nombre).compareTo(b.nombre == null ? '' : b.nombre);
		}
		Map<String, Object> datos() {
			return new Map<String, Object>{ 'id' => id, 'incisoId' => incisoId, 'nombre' => nombre, 'detalle' => detalle, 'vigente' => vigente };
		}
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Tipos de registro de los siniestros por familia (personas, autos, danos).
	 * @return recordTypeId (el de personas) y tipos.
	 */
	@AuraEnabled(cacheable=true)
	public static Map<String, Object> inicio() {
		Map<String, Schema.RecordTypeInfo> rts = Schema.SObjectType.Claim.getRecordTypeInfosByDeveloperName();
		Map<String, Object> tipos = new Map<String, Object>();
		for (String f : TIPO_POR_FAMILIA.keySet()) {
			Schema.RecordTypeInfo i = rts.get(TIPO_POR_FAMILIA.get(f));
			if (i != null) { tipos.put(f, i.getRecordTypeId()); }
		}
		return new Map<String, Object>{ 'recordTypeId' => tipos.get(PERSONAS), 'tipos' => tipos };
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
	 * @description: Póliza elegida: sus datos, su familia (y el tipo de registro del siniestro), el ramo que le toca al
	 *               siniestro y sus coberturas (con el bien al que pertenecen, si es de un bien).
	 * @param policyId: póliza.
	 * @return poliza, familia, recordTypeId, ramo y coberturas.
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> datosPoliza(Id policyId) {
		List<InsurancePolicy> l = [
			SELECT Id, Name, NameInsuredId, NameInsured.Name, Ramo__c, Status, EffectiveDate, ExpirationDate, Aseguradora__r.Name, Product.Aseguradora__r.Name
			FROM InsurancePolicy WHERE Id = :policyId LIMIT 1
		];
		if (l.isEmpty()) { throw CensoColectivoController.error('No tienes acceso a la póliza.'); }
		List<Map<String, Object>> coberturas = new List<Map<String, Object>>();
		for (InsurancePolicyCoverage c : [
			SELECT Id, CoverageName, LimitAmount, InsurancePolicyAssetId FROM InsurancePolicyCoverage
			WHERE InsurancePolicyId = :policyId ORDER BY CoverageName LIMIT 200
		]) {
			coberturas.add(new Map<String, Object>{ 'id' => c.Id, 'nombre' => c.CoverageName, 'suma' => c.LimitAmount, 'bienId' => c.InsurancePolicyAssetId });
		}
		String familia = familiaDe(l[0].Ramo__c);
		return new Map<String, Object>{
			'poliza' => poliza(l[0]), 'familia' => familia, 'recordTypeId' => tipoDe(familia), 'ramo' => ramoDe(l[0].Ramo__c),
			'coberturas' => coberturas, 'correoContratante' => datosCuenta(l[0].NameInsuredId).get('correo')
		};
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Asegurados de la póliza por nombre o certificado (los vigentes primero).
	 * @param policyId: póliza.
	 * @param texto: nombre o certificado; vacío = los primeros.
	 * @param elegidoId: asegurado que ya viene elegido (desde su renglón en Asegurados): va primero.
	 * @return asegurados con su certificado, si es titular o de quién es dependiente y si sigue vigente.
	 */
	@AuraEnabled(cacheable=false)
	public static List<Map<String, Object>> buscarAsegurados(Id policyId, String texto, Id elegidoId) {
		String patron = '%' + (String.isBlank(texto) ? '' : texto.trim()) + '%';
		List<InsurancePolicyParticipant> l = new List<InsurancePolicyParticipant>();
		if (elegidoId != null) {
			l.addAll([
				SELECT Id, ParticipantName, ParticipantCode, IsActiveParticipant, RelatedInsPolicyParticipantId, RelatedInsPolicyParticipant.ParticipantName,
					PrimaryParticipantContactId, PrimaryParticipantAccountId, RelatedInsPolicyParticipant.PrimaryParticipantContactId,
					RelatedInsPolicyParticipant.PrimaryParticipantAccountId
				FROM InsurancePolicyParticipant WHERE Id = :elegidoId AND InsurancePolicyId = :policyId LIMIT 1
			]);
		}
		Integer resto = MAX_RESULTADOS - l.size();
		l.addAll([
			SELECT Id, ParticipantName, ParticipantCode, IsActiveParticipant, RelatedInsPolicyParticipantId, RelatedInsPolicyParticipant.ParticipantName,
					PrimaryParticipantContactId, PrimaryParticipantAccountId, RelatedInsPolicyParticipant.PrimaryParticipantContactId,
					RelatedInsPolicyParticipant.PrimaryParticipantAccountId
			FROM InsurancePolicyParticipant
			WHERE InsurancePolicyId = :policyId AND Id != :elegidoId AND (ParticipantName LIKE :patron OR ParticipantCode LIKE :patron)
			ORDER BY IsActiveParticipant DESC, ParticipantName ASC LIMIT :resto
		]);
		List<InsurancePolicyParticipant> titulares = new List<InsurancePolicyParticipant>();
		for (InsurancePolicyParticipant p : l) { titulares.add(titularDe(p)); }
		Map<Id, String> correos = ParticipantesPolizaController.correosDe(titulares);
		List<Map<String, Object>> res = new List<Map<String, Object>>();
		for (InsurancePolicyParticipant p : l) {
			res.add(new Map<String, Object>{
				'id' => p.Id, 'nombre' => p.ParticipantName, 'certificado' => p.ParticipantCode, 'vigente' => p.IsActiveParticipant,
				'titular' => p.RelatedInsPolicyParticipantId == null ? null : p.RelatedInsPolicyParticipant.ParticipantName,
				'correoAvisos' => correos.get(titularDe(p).Id)
			});
		}
		return res;
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Bienes de la póliza (vehículos con los datos de su inciso, o ubicaciones) por nombre, serie, placas
	 *               o número de inciso (los vigentes primero).
	 * @param policyId: póliza.
	 * @param texto: lo que se busca; vacío = los primeros.
	 * @param elegidoId: bien (InsurancePolicyAsset) o inciso (Inciso_Flotilla__c) que ya viene elegido: va primero.
	 * @return bienes con su id (InsurancePolicyAsset), inciso, nombre, detalle y si sigue vigente.
	 */
	@AuraEnabled(cacheable=false)
	public static List<Map<String, Object>> buscarBienes(Id policyId, String texto, Id elegidoId) {
		List<Bien> bienes = bienesDe(policyId);
		Bien elegido = bienElegido(bienes, elegidoId);
		String t = normal(texto);
		List<Map<String, Object>> res = new List<Map<String, Object>>();
		if (elegido != null) { res.add(elegido.datos()); }
		for (Bien b : bienes) {
			if (res.size() >= MAX_RESULTADOS) { break; }
			if (b !== elegido && (String.isBlank(t) || b.busqueda.contains(t))) { res.add(b.datos()); }
		}
		return res;
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Registra el siniestro con lo afectado (el asegurado y su titular, o el bien y el contratante), su
	 *               cobertura y, si se capturó, su primera solicitud de pago. Todo o nada.
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
		List<InsurancePolicy> pols = [SELECT Id, Ramo__c, NameInsuredId FROM InsurancePolicy WHERE Id = :d.policyId LIMIT 1];
		if (pols.isEmpty()) { throw CensoColectivoController.error('No tienes acceso a la póliza.'); }
		String familia = familiaDe(pols[0].Ramo__c);
		Boolean personas = familia == PERSONAS;
		if (personas && d.participanteId == null) { throw CensoColectivoController.error('Elige al asegurado afectado.'); }
		if (!personas && d.bienId == null) {
			throw CensoColectivoController.error(familia == AUTOS ? 'Elige el vehículo afectado.' : 'Elige la ubicación afectada.');
		}
		if (String.isBlank(d.fecha)) { throw CensoColectivoController.error('Indica la fecha del siniestro.'); }
		InsurancePolicyParticipant a = null;
		if (personas) {
			List<InsurancePolicyParticipant> asegurados = [
				SELECT Id, ParticipantName, InsurancePolicyId, PrimaryParticipantContactId, PrimaryParticipantAccountId,
					RelatedInsPolicyParticipantId, RelatedInsPolicyParticipant.PrimaryParticipantContactId,
					RelatedInsPolicyParticipant.PrimaryParticipantAccountId
				FROM InsurancePolicyParticipant WHERE Id = :d.participanteId LIMIT 1
			];
			if (asegurados.isEmpty() || asegurados[0].InsurancePolicyId != d.policyId) {
				throw CensoColectivoController.error('El asegurado no pertenece a la póliza.');
			}
			a = asegurados[0];
		} else if ([SELECT COUNT() FROM InsurancePolicyAsset WHERE Id = :d.bienId AND InsurancePolicyId = :d.policyId] == 0) {
			throw CensoColectivoController.error(familia == AUTOS ? 'El vehículo no pertenece a la póliza.' : 'La ubicación no pertenece a la póliza.');
		}
		Savepoint sp = Database.setSavepoint();
		try {
			Claim c = new Claim(Name = 'Nuevo siniestro', RecordTypeId = tipoDe(familia), PolicyNumberId = d.policyId,
				Status = 'Abierto', ClaimType = d.ramo, ClaimReasonType = d.causa, LossType = d.tipo, LossDate = mediodia(d.fecha),
				ReportDate = Datetime.now(), ClaimReason = texto(d.diagnostico, 255), FnolChannel = d.medio,
				SourceSystemIdentifier = texto(d.numeroAseguradora, 255), Summary = texto(d.observaciones, 32000));
			if (personas) {
				c.VisitSite = texto(d.hospital, 32000);
				c.VisitDate = mediodia(d.fechaAtencion);
				// Titular (el mismo asegurado o, si es dependiente, su titular): su contacto y su correo.
				InsurancePolicyParticipant t = titularDe(a);
				Map<String, Object> cuenta = datosCuenta(t.PrimaryParticipantAccountId);
				c.Titular__c = t.PrimaryParticipantContactId != null ? t.PrimaryParticipantContactId : (Id) cuenta.get('contactoId');
				c.Correo_Avisos__c = String.isNotBlank(d.correo) ? d.correo.trim()
					: ParticipantesPolizaController.correosDe(new List<InsurancePolicyParticipant>{ t }).get(t.Id);
				c.Afectado__c = texto(a.ParticipantName, 255);
			} else {
				c.InsuredAssetId = d.bienId;
				c.IncidentSiteStreet = texto(d.lugar, 255);
				// Contratante: su contacto (si es persona) y su correo.
				Map<String, Object> cuenta = datosCuenta(pols[0].NameInsuredId);
				c.Titular__c = (Id) cuenta.get('contactoId');
				c.Correo_Avisos__c = String.isNotBlank(d.correo) ? d.correo.trim() : (String) cuenta.get('correo');
				Bien b = bienElegido(bienesDe(d.policyId), d.bienId);
				c.Afectado__c = b == null ? null : texto(b.nombre, 255);
			}
			insert c;
			ClaimParticipant principal;
			if (personas) {
				// Afectado (paciente) y, si es dependiente, su titular como reclamante.
				principal = new ClaimParticipant(ClaimId = c.Id, InsurancePolicyParticipantId = a.Id, Roles = 'Paciente',
					IsInjured = true, ParticipantContactId = a.PrimaryParticipantContactId, ParticipantAccountId = a.PrimaryParticipantAccountId);
				List<ClaimParticipant> participantes = new List<ClaimParticipant>{ principal };
				if (a.RelatedInsPolicyParticipantId != null) {
					participantes.add(new ClaimParticipant(ClaimId = c.Id, InsurancePolicyParticipantId = a.RelatedInsPolicyParticipantId,
						Roles = 'Reclamante', IsInjured = false, ParticipantContactId = a.RelatedInsPolicyParticipant.PrimaryParticipantContactId,
						ParticipantAccountId = a.RelatedInsPolicyParticipant.PrimaryParticipantAccountId));
				} else {
					principal.Roles = 'Paciente;Reclamante';
				}
				insert participantes;
			} else {
				// Bien afectado y el contratante como reclamante.
				insert new InsuranceClaimAsset(ClaimId = c.Id, InsurancePolicyAssetId = d.bienId);
				if (pols[0].NameInsuredId != null) {
					principal = new ClaimParticipant(ClaimId = c.Id, ParticipantAccountId = pols[0].NameInsuredId, Roles = 'Reclamante', IsInjured = false);
					insert principal;
				}
			}
			// Cobertura del siniestro: la de la póliza que se eligió o, si la póliza no las tiene, una con el tipo de siniestro.
			String nombreCobertura = String.isNotBlank(d.tipo) ? d.tipo : 'Siniestro';
			if (d.coberturaId != null) {
				for (InsurancePolicyCoverage pc : [SELECT CoverageName FROM InsurancePolicyCoverage WHERE Id = :d.coberturaId AND InsurancePolicyId = :d.policyId]) {
					nombreCobertura = pc.CoverageName;
				}
			}
			insert new ClaimCoverage(ClaimId = c.Id, Name = nombreCobertura.left(80), InternalReserveMode = 'ReserveInapplicable', Status = 'Abierto',
				ClaimParticipantId = principal == null ? null : principal.Id, InsurancePolicyParticipantId = a == null ? null : a.Id,
				InsurancePolicyAssetId = personas ? null : d.bienId, InsurancePolicyCoverageId = d.coberturaId);
			Id solicitudId = d.solicitud == null ? null : nuevaSolicitud(c.Id, d.policyId, a == null ? null : a.Id, d.solicitud);
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
	 * @description: Pestaña Siniestros de la póliza: sus siniestros con lo afectado, lo reclamado y lo pagado; su
	 *               siniestralidad (pagado contra la prima neta de la póliza y sus endosos) y los folios de siniestro
	 *               anteriores de ese número de póliza en Control de Folios (solo consulta).
	 * @param policyId: póliza.
	 * @return familia, numero, acceso, puedeCrear, siniestros, resumen, conFolios y folios.
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> siniestrosDePoliza(Id policyId) {
		List<InsurancePolicy> pols = [SELECT Id, Name, Ramo__c, PremiumAmount, Subtotal__c FROM InsurancePolicy WHERE Id = :policyId LIMIT 1];
		if (pols.isEmpty()) { throw CensoColectivoController.error('No tienes acceso a la póliza.'); }
		InsurancePolicy p = pols[0];
		String familia = familiaDe(p.Ramo__c);
		Boolean acceso = Schema.SObjectType.Claim.isAccessible();
		List<Map<String, Object>> siniestros = new List<Map<String, Object>>();
		Integer abiertos = 0;
		Decimal reclamado = 0;
		Decimal pagado = 0;
		if (acceso) {
			Map<Id, Bien> bienes = new Map<Id, Bien>();
			if (familia != PERSONAS) {
				for (Bien b : bienesDe(policyId)) { bienes.put(b.id, b); }
			}
			for (Claim c : [
				SELECT Id, Name, Status, IsClosed, LossDate, ReportDate, ClaimType, LossType, ClaimReasonType, ClaimReason,
					EstimatedAmount, ActualAmount, SourceSystemIdentifier, InsuredAssetId, Owner.Name,
					(SELECT Roles, InsurancePolicyParticipant.ParticipantName, ParticipantAccount.Name FROM ClaimParticipants ORDER BY CreatedDate),
					(SELECT InsurancePolicyAssetId FROM InsuranceClaimAssets ORDER BY CreatedDate LIMIT 1)
				FROM Claim WHERE PolicyNumberId = :policyId ORDER BY LossDate DESC NULLS LAST, CreatedDate DESC LIMIT :MAX_LISTA
			]) {
				Map<String, Object> s = new Map<String, Object>{
					'id' => c.Id, 'folio' => c.Name, 'estatus' => c.Status, 'cerrado' => c.IsClosed,
					'fecha' => c.LossDate == null ? null : c.LossDate.dateGmt(), 'reporte' => c.ReportDate == null ? null : c.ReportDate.date(),
					'ramo' => c.ClaimType, 'tipo' => c.LossType, 'causa' => c.ClaimReasonType, 'descripcion' => c.ClaimReason,
					'reclamado' => c.EstimatedAmount, 'pagado' => c.ActualAmount, 'numeroAseguradora' => c.SourceSystemIdentifier,
					'ejecutivo' => c.Owner == null ? null : c.Owner.Name
				};
				afectadoDe(c, bienes, s);
				siniestros.add(s);
				if (!c.IsClosed) { abiertos++; }
				reclamado += c.EstimatedAmount == null ? 0 : c.EstimatedAmount;
				pagado += c.ActualAmount == null ? 0 : c.ActualAmount;
			}
		}
		// Prima neta: la de la póliza (o su prima, si no trae el desglose) más la de sus endosos.
		Decimal prima = p.Subtotal__c != null ? p.Subtotal__c : p.PremiumAmount;
		for (AggregateResult ar : [
			SELECT SUM(TransactionAmount) s FROM InsurancePolicyTransaction WHERE InsurancePolicyId = :policyId AND Category = 'Endorsement'
		]) {
			Decimal e = (Decimal) ar.get('s');
			if (e != null) { prima = (prima == null ? 0 : prima) + e; }
		}
		Map<String, Object> resumen = new Map<String, Object>{
			'total' => siniestros.size(), 'abiertos' => abiertos, 'reclamado' => reclamado, 'pagado' => pagado, 'prima' => prima,
			'siniestralidad' => prima == null || prima <= 0 ? null : (pagado * 100 / prima).setScale(1)
		};
		Boolean conFolios = Schema.SObjectType.Control_de_Folios__c.isAccessible();
		return new Map<String, Object>{
			'familia' => familia, 'numero' => p.Name, 'acceso' => acceso,
			'puedeCrear' => acceso && Schema.SObjectType.Claim.isCreateable(), 'siniestros' => siniestros, 'resumen' => resumen,
			'conFolios' => conFolios, 'folios' => conFolios ? foliosAnteriores(p.Name) : new List<Map<String, Object>>()
		};
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
			Id solicitudId = nuevaSolicitud(claimId, l[0].PolicyNumberId, pacienteDe(claimId), d);
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

	// Asegurado afectado del siniestro (su participante paciente); null en un siniestro de un bien.
	private static Id pacienteDe(Id claimId) {
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

	// Lo afectado en el renglón de la pestaña: el paciente (y su titular, si es otro) o el bien.
	private static void afectadoDe(Claim c, Map<Id, Bien> bienes, Map<String, Object> s) {
		Id bienId = c.InsuredAssetId;
		if (bienId == null && !c.InsuranceClaimAssets.isEmpty()) { bienId = c.InsuranceClaimAssets[0].InsurancePolicyAssetId; }
		if (bienId != null && bienes.containsKey(bienId)) {
			Bien b = bienes.get(bienId);
			s.put('afectado', b.nombre);
			s.put('afectadoDetalle', b.detalle);
			return;
		}
		String paciente;
		String reclamante;
		for (ClaimParticipant p : c.ClaimParticipants) {
			String nombre = p.InsurancePolicyParticipantId != null ? p.InsurancePolicyParticipant.ParticipantName
				: (p.ParticipantAccountId != null ? p.ParticipantAccount.Name : null);
			if (p.Roles != null && p.Roles.contains('Paciente') && paciente == null) { paciente = nombre; }
			else if (p.Roles != null && p.Roles.contains('Reclamante') && reclamante == null) { reclamante = nombre; }
		}
		s.put('afectado', paciente != null ? paciente : reclamante);
		s.put('afectadoDetalle', paciente != null && reclamante != null ? 'Dependiente de ' + reclamante : null);
	}

	// Folios de siniestro de Control de Folios con el mismo número de póliza (ligados al objeto anterior de pólizas).
	private static List<Map<String, Object>> foliosAnteriores(String numero) {
		List<Map<String, Object>> res = new List<Map<String, Object>>();
		if (String.isBlank(numero)) { return res; }
		for (Control_de_Folios__c f : [
			SELECT Id, Name, Folio__c, Fecha__c, Fecha_de_cierre__c, toLabel(Movimiento__c), toLabel(Tipo__c), toLabel(Tipo_de_Evento__c),
				toLabel(Estatus__c), Diagnostico__c, Siniestro__c, Asegurado_afectado__r.Name, Titular__r.Name, Folio_inicial__r.Folio__c
			FROM Control_de_Folios__c
			WHERE RecordType.DeveloperName = 'Siniestros' AND Poliza__r.Name = :numero
			ORDER BY Fecha__c DESC NULLS LAST, CreatedDate DESC LIMIT :MAX_LISTA
		]) {
			res.add(new Map<String, Object>{
				'id' => f.Id, 'folio' => String.isNotBlank(f.Folio__c) ? f.Folio__c : f.Name, 'fecha' => f.Fecha__c, 'cierre' => f.Fecha_de_cierre__c,
				'movimiento' => f.Movimiento__c, 'tipo' => f.Tipo__c, 'evento' => f.Tipo_de_Evento__c, 'estatus' => f.Estatus__c,
				'diagnostico' => f.Diagnostico__c, 'numeroAseguradora' => f.Siniestro__c,
				'afectado' => f.Asegurado_afectado__c == null ? null : f.Asegurado_afectado__r.Name,
				'titular' => f.Titular__c == null ? null : f.Titular__r.Name,
				'folioInicial' => f.Folio_inicial__c == null ? null : f.Folio_inicial__r.Folio__c
			});
		}
		return res;
	}

	// Bienes de la póliza (los ligados a un bien del cliente, como en Vehículos y Ubicaciones): los vehículos toman los
	// datos de su inciso (por el vehículo del cliente, CustomerProperty).
	private static List<Bien> bienesDe(Id policyId) {
		Map<Id, Inciso_Flotilla__c> incisos = new Map<Id, Inciso_Flotilla__c>();
		for (Inciso_Flotilla__c i : [
			SELECT Id, Vehiculo__c, Numero_Inciso__c, Serie__c, Placas__c, Descripcion__c, Modelo__c FROM Inciso_Flotilla__c
			WHERE Poliza__c = :policyId AND Vehiculo__c != null ORDER BY CreatedDate LIMIT :MAX_BIENES
		]) { incisos.put(i.Vehiculo__c, i); }
		List<Bien> res = new List<Bien>();
		for (InsurancePolicyAsset a : [
			SELECT Id, Name, AssetName, AssetCode, CustomerPropertyId, IsActive, Fecha_Baja__c, Suma_Asegurada__c, CustomerProperty.Name,
				CustomerProperty.Make, CustomerProperty.ModelName, CustomerProperty.MakeYear, CustomerProperty.Vin,
				CustomerProperty.RegistrationNumber, CustomerProperty.Street, CustomerProperty.City, CustomerProperty.PostalCode
			FROM InsurancePolicyAsset
			WHERE InsurancePolicyId = :policyId AND CustomerPropertyId != null ORDER BY CreatedDate ASC LIMIT :MAX_BIENES
		]) {
			Inciso_Flotilla__c i = a.CustomerPropertyId == null ? null : incisos.get(a.CustomerPropertyId);
			CustomerProperty cp = a.CustomerProperty;
			Bien b = new Bien();
			b.id = a.Id;
			b.vigente = a.IsActive && a.Fecha_Baja__c == null;
			List<String> partes = new List<String>();
			if (i != null) {
				// Vehículo de una flotilla: los datos de su inciso.
				b.incisoId = i.Id;
				b.nombre = primero(new List<String>{ i.Descripcion__c, a.AssetName, a.Name });
				if (i.Numero_Inciso__c != null) {
					b.inciso = i.Numero_Inciso__c.intValue();
					partes.add('Inciso ' + String.valueOf(b.inciso));
				}
				if (i.Modelo__c != null) { partes.add(String.valueOf(i.Modelo__c.intValue())); }
				if (String.isNotBlank(i.Serie__c)) { partes.add('Serie ' + i.Serie__c); }
				if (String.isNotBlank(i.Placas__c)) { partes.add('Placas ' + i.Placas__c); }
			} else if (cp != null && (String.isNotBlank(cp.Vin) || String.isNotBlank(cp.Make))) {
				// Vehículo sin inciso (póliza individual): los datos del vehículo del cliente.
				b.nombre = primero(new List<String>{ String.join(new List<String>{ cp.Make == null ? '' : cp.Make, cp.ModelName == null ? '' : cp.ModelName }, ' ').trim(),
					a.AssetName, cp.Name, a.Name });
				if (String.isNotBlank(a.AssetCode)) {
					partes.add('Inciso ' + a.AssetCode);
					if (a.AssetCode.isNumeric()) { b.inciso = Integer.valueOf(a.AssetCode); }
				}
				if (cp.MakeYear != null) { partes.add(String.valueOf(cp.MakeYear)); }
				if (String.isNotBlank(cp.Vin)) { partes.add('Serie ' + cp.Vin); }
				if (String.isNotBlank(cp.RegistrationNumber)) { partes.add('Placas ' + cp.RegistrationNumber); }
			} else {
				// Ubicación: su nombre y su domicilio; el inciso va al inicio del nombre («Inciso 3 - domicilio»).
				b.nombre = primero(new List<String>{ a.AssetName, cp == null ? null : cp.Name, a.Name });
				Matcher mt = Pattern.compile('^Inciso\\s+(\\d+)').matcher(b.nombre == null ? '' : b.nombre);
				if (mt.find()) { b.inciso = Integer.valueOf(mt.group(1)); }
				if (cp != null) {
					for (String s : new List<String>{ cp.Street == null ? null : cp.Street.replace('\n', ', '), cp.City,
						cp.PostalCode == null ? null : 'CP ' + cp.PostalCode }) {
						if (String.isNotBlank(s) && (b.nombre == null || !b.nombre.contains(s))) { partes.add(s); }
					}
				}
				if (a.Suma_Asegurada__c != null) { partes.add('Suma asegurada $' + a.Suma_Asegurada__c.setScale(2).format()); }
			}
			b.detalle = String.join(partes, ' · ');
			b.busqueda = normal(b.nombre + ' ' + b.detalle);
			res.add(b);
		}
		res.sort();
		return res;
	}

	// Titular de un asegurado: él mismo o, si es dependiente, su titular (con su contacto y su cuenta).
	private static InsurancePolicyParticipant titularDe(InsurancePolicyParticipant p) {
		if (p.RelatedInsPolicyParticipantId == null) { return p; }
		return new InsurancePolicyParticipant(Id = p.RelatedInsPolicyParticipantId,
			PrimaryParticipantContactId = p.RelatedInsPolicyParticipant.PrimaryParticipantContactId,
			PrimaryParticipantAccountId = p.RelatedInsPolicyParticipant.PrimaryParticipantAccountId);
	}

	// Correo de una cuenta (el de la persona o su correo electrónico) y su contacto, si es cuenta personal.
	private static Map<String, Object> datosCuenta(Id cuentaId) {
		Map<String, Object> res = new Map<String, Object>();
		if (cuentaId == null) { return res; }
		Map<String, Schema.SObjectField> fm = Schema.SObjectType.Account.fields.getMap();
		List<String> campos = new List<String>{ 'Id' };
		for (String c : new List<String>{ 'PersonEmail', 'Correo_electronico__c', 'PersonContactId' }) {
			if (fm.containsKey(c.toLowerCase())) { campos.add(c); }
		}
		for (SObject a : Database.query('SELECT ' + String.join(campos, ', ') + ' FROM Account WHERE Id = :cuentaId LIMIT 1')) {
			String correo = campos.contains('PersonEmail') ? (String) a.get('PersonEmail') : null;
			if (String.isBlank(correo) && campos.contains('Correo_electronico__c')) { correo = (String) a.get('Correo_electronico__c'); }
			res.put('correo', correo);
			res.put('contactoId', campos.contains('PersonContactId') ? a.get('PersonContactId') : null);
		}
		return res;
	}

	// Bien que viene elegido: por su Id (InsurancePolicyAsset) o por el de su inciso (Inciso_Flotilla__c).
	private static Bien bienElegido(List<Bien> bienes, Id elegidoId) {
		if (elegidoId == null) { return null; }
		for (Bien b : bienes) {
			if (b.id == elegidoId || b.incisoId == elegidoId) { return b; }
		}
		return null;
	}

	private static Map<String, Object> poliza(InsurancePolicy p) {
		String aseguradora = p.Aseguradora__r != null ? p.Aseguradora__r.Name
			: (p.Product != null && p.Product.Aseguradora__r != null ? p.Product.Aseguradora__r.Name : null);
		return new Map<String, Object>{
			'id' => p.Id, 'numero' => p.Name, 'contratante' => p.NameInsured == null ? null : p.NameInsured.Name, 'ramo' => p.Ramo__c,
			'estatus' => p.Status, 'aseguradora' => aseguradora, 'familia' => familiaDe(p.Ramo__c),
			'inicio' => p.EffectiveDate == null ? null : p.EffectiveDate.dateGmt(), 'fin' => p.ExpirationDate == null ? null : p.ExpirationDate.dateGmt()
		};
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Familia del siniestro según el ramo de la póliza, con la regla de las pestañas de la póliza:
	 *               Automóviles (Vehículos), Daños y Empresarial (Ubicaciones); los demás ramos, personas (Asegurados).
	 * @param ramo: Ramo__c de la póliza.
	 * @return personas, autos o danos.
	 */
	@TestVisible
	private static String familiaDe(String ramo) {
		String r = normal(ramo);
		if (r.startsWith('automovil') || r == 'autos' || r == 'auto') { return AUTOS; }
		if (r.startsWith('danos') || r.startsWith('empresarial')) { return DANOS; }
		return PERSONAS;
	}

	// Tipo de registro de Claim de la familia.
	private static Id tipoDe(String familia) {
		Schema.RecordTypeInfo i = Schema.SObjectType.Claim.getRecordTypeInfosByDeveloperName().get(TIPO_POR_FAMILIA.get(familia));
		if (i == null) { throw CensoColectivoController.error('No existe el tipo de siniestro de ' + familia + '.'); }
		return i.getRecordTypeId();
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Ramo del siniestro (ClaimType) según el ramo de la póliza.
	 * @param ramo: Ramo__c de la póliza.
	 * @return valor de ClaimType; null si no se deduce (el ejecutivo lo elige).
	 */
	@TestVisible
	private static String ramoDe(String ramo) {
		String f = familiaDe(ramo);
		if (f == AUTOS) { return 'Automóviles'; }
		if (f == DANOS) { return 'Daños'; }
		String r = normal(ramo);
		if (r.contains('gasto') || r.contains('gmm') || r.contains('salud')) { return 'Gastos médicos mayores'; }
		if (r.contains('accidente')) { return 'Accidentes personales'; }
		if (r.contains('vida')) { return 'Vida'; }
		return null;
	}

	// Minúsculas y sin acentos, para comparar.
	private static String normal(String v) {
		if (v == null) { return ''; }
		return v.toLowerCase().replace('á', 'a').replace('é', 'e').replace('í', 'i').replace('ó', 'o').replace('ú', 'u')
			.replace('ü', 'u').replace('ñ', 'n').trim();
	}

	private static String primero(List<String> valores) {
		for (String v : valores) {
			if (String.isNotBlank(v)) { return v; }
		}
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
