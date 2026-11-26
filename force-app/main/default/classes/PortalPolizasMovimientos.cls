/**
 * @creation date: 18/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Acciones del sitio de empresas en las pestañas Asegurados / Vehículos / Ubicaciones, que usan los
 * mismos componentes de Salesforce (altas, bajas, cambios, carga del archivo de la aseguradora, endosos y «otras
 * pólizas»). Valida que la póliza sea del usuario del sitio; los movimientos solo los puede hacer el contratante. Llama
 * a los mismos controladores de Salesforce (inherited sharing, así que aquí corren sin compartir: el usuario del sitio
 * no tiene acceso directo a los registros). Los archivos adjuntos solo se ven: en el sitio no se cargan.
 */
public without sharing class PortalPolizasMovimientos {

	/** Acciones que solo consultan: cualquier usuario con acceso a la póliza. */
	static final Set<String> CONSULTAS = new Set<String>{ 'EndosoPoliza.getEndosos', 'OtrasPolizas.buscar', 'Documento.descargar' };

	/** Tamaño máximo de un documento que se descarga por Apex (igual que en PortalPolizasController). */
	static final Integer MAX_BYTES = 3 * 1024 * 1024;

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Ejecuta una acción de los componentes de Salesforce para la póliza abierta en el sitio.
	 * @param policyId: Id de la póliza abierta en el sitio
	 * @param cuentaVistaPrevia: Cuenta a simular (solo vista previa de administrador); null para el usuario real
	 * @param accion: Clase.metodo de la acción (ver la lista en el código)
	 * @param parametros: JSON con los parámetros del método original
	 * @return Lo mismo que devuelve el método original
	 */
	@AuraEnabled
	public static Object ejecutar(Id policyId, Id cuentaVistaPrevia, String accion, String parametros) {
		try {
			Map<Id, String> roles = PortalPolizasController.validarAcceso(policyId, cuentaVistaPrevia);
			if (!CONSULTAS.contains(accion) && roles.get(policyId) != 'Titular') {
				throw aviso('Solo el contratante de la póliza puede registrar movimientos.');
			}
			Map<String, Object> p = String.isBlank(parametros) ? new Map<String, Object>()
				: (Map<String, Object>) JSON.deserializeUntyped(parametros);
			switch on accion {
				when 'MovimientosColectivo.aplicar' {
					return casoDelSitio(policyId, cuentaVistaPrevia, MovimientosColectivoController.aplicar(policyId, texto(p, 'movimientosJson')));
				}
				when 'MovimientosColectivo.compararArchivo' {
					return MovimientosColectivoController.compararArchivo(policyId, texto(p, 'miembrosJson'), p.get('censoCompleto') == true);
				}
				when 'MovimientosFlotilla.aplicar' {
					return casoDelSitio(policyId, cuentaVistaPrevia, MovimientosFlotillaController.aplicar(policyId, texto(p, 'movimientosJson')));
				}
				when 'MovimientosFlotilla.compararArchivo' {
					return MovimientosFlotillaController.compararArchivo(policyId, texto(p, 'incisosJson'), p.get('censoCompleto') == true);
				}
				when 'MovimientosUbicaciones.aplicar' {
					return casoDelSitio(policyId, cuentaVistaPrevia, MovimientosUbicacionesController.aplicar(policyId, texto(p, 'movimientosJson')));
				}
				when 'MovimientosColectivo.cerrarMovimiento' {
					Id movimientoId = registro(p, 'movimientoId', policyId);
					return MovimientosColectivoController.cerrarMovimiento(movimientoId);
				}
				when 'EndosoPoliza.getEndosos' {
					return EndosoPoliza.getEndosos(policyId);
				}
				when 'EndosoPoliza.registrarEndoso' {
					return EndosoPoliza.registrarEndoso(policyId, texto(p, 'numero'), texto(p, 'descripcion'), texto(p, 'fecha'),
						texto(p, 'primaJson'));
				}
				when 'CensoColectivo.analizarCensoPdf' {
					return CensoColectivoController.analizarCensoPdf(texto(p, 'textoCenso'));
				}
				when 'Flotilla.analizarFlotillaPdf' {
					return FlotillaController.analizarFlotillaPdf(texto(p, 'textoCotizacion'));
				}
				when 'MovimientosColectivo.archivosAsegurado' {
					Id registroId = registro(p, 'registroId', policyId);
					return MovimientosColectivoController.archivosAsegurado(registroId);
				}
				when 'Documento.descargar' {
					if (p.get('participanteId') == null) {
						return documento(policyId, texto(p, 'documentId'));
					}
					// Archivo de un asegurado: solo el contratante y solo si es de ese asegurado.
					if (roles.get(policyId) != 'Titular') {
						throw aviso('El documento no existe o no tienes acceso a él.');
					}
					Id participanteId = registro(p, 'participanteId', policyId);
					return archivoDeAsegurado(participanteId, texto(p, 'documentId'));
				}
				when 'Participantes.getPlantillas' {
					return ParticipantesPolizaController.getPlantillas();
				}
				when 'RenovacionGmm.enviar' {
					List<Id> ids = new List<Id>();
					for (Object o : (List<Object>) (p.get('participanteIds') == null ? new List<Object>() : p.get('participanteIds'))) {
						try { ids.add(Id.valueOf(String.valueOf(o))); } catch (Exception e) { throw aviso('El registro no es de esta póliza.'); }
					}
					return RenovacionGmmContributoria.enviar(policyId, ids, texto(p, 'fechaLimite'),
						p.get('derecho') == null ? null : Decimal.valueOf(String.valueOf(p.get('derecho'))));
				}
				when 'Participantes.enviarCorreo' {
					// Correo a los asegurados de esta póliza: el controlador solo toma participantes de la póliza.
					List<Id> ids = new List<Id>();
					for (Object o : (List<Object>) (p.get('participanteIds') == null ? new List<Object>() : p.get('participanteIds'))) {
						try { ids.add(Id.valueOf(String.valueOf(o))); } catch (Exception e) { throw aviso('El registro no es de esta póliza.'); }
					}
					return ParticipantesPolizaController.enviarCorreo(policyId, ids, (Id) texto(p, 'plantillaId'),
						p.get('adjuntarArchivos') == true, texto(p, 'correosJson'));
				}
				when 'OtrasPolizas.buscar' {
					Id registroId = registro(p, 'registroId', policyId);
					return soloSuyas(OtrasPolizasController.buscar(registroId, policyId), roles.keySet());
				}
				when else {
					throw aviso('Acción no disponible en el sitio.');
				}
			}
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			throw PortalPolizasController.errorSitio(e);
		}
	}

	/** Error para el usuario del sitio (con el mensaje visible también en las pruebas). */
	static AuraHandledException aviso(String mensaje) {
		AuraHandledException e = new AuraHandledException(mensaje);
		e.setMessage(mensaje);
		return e;
	}

	/** Texto de un parámetro (null si no viene). */
	static String texto(Map<String, Object> p, String nombre) {
		Object v = p.get(nombre);
		return v == null ? null : String.valueOf(v);
	}

	/**
	 * Id de un parámetro que debe ser de la póliza: la póliza misma o un registro ligado a ella (participante, vehículo,
	 * bien, endoso o movimiento). Si no es de la póliza se rechaza.
	 */
	static Id registro(Map<String, Object> p, String nombre, Id policyId) {
		String valor = texto(p, nombre);
		Id rid;
		try {
			rid = Id.valueOf(valor);
		} catch (Exception e) {
			throw aviso('El registro no es de esta póliza.');
		}
		if (rid == policyId) { return rid; }
		Map<SObjectType, String> campos = new Map<SObjectType, String>{
			InsurancePolicyParticipant.SObjectType => 'InsurancePolicyId',
			InsurancePolicyAsset.SObjectType => 'InsurancePolicyId',
			InsurancePolicyTransaction.SObjectType => 'InsurancePolicyId',
			Inciso_Flotilla__c.SObjectType => 'Poliza__c',
			Movimiento_Poliza__c.SObjectType => 'Poliza__c'
		};
		String campo = campos.get(rid.getSObjectType());
		if (campo != null) {
			String objeto = String.valueOf(rid.getSObjectType());
			List<SObject> l = Database.query('SELECT Id FROM ' + objeto + ' WHERE Id = :rid AND ' + campo + ' = :policyId LIMIT 1');
			if (!l.isEmpty()) { return rid; }
		}
		throw aviso('El registro no es de esta póliza.');
	}

	/** Documento de la póliza o de uno de sus endosos (transacciones): nombre, tipo MIME y contenido en base64. */
	static Map<String, Object> documento(Id policyId, String documentId) {
		Set<Id> ligados = new Set<Id>{ policyId };
		for (InsurancePolicyTransaction t : [SELECT Id FROM InsurancePolicyTransaction WHERE InsurancePolicyId = :policyId]) {
			ligados.add(t.Id);
		}
		if (String.isBlank(documentId) || [SELECT COUNT() FROM ContentDocumentLink
			WHERE ContentDocumentId = :documentId AND LinkedEntityId IN :ligados] == 0) {
			throw aviso('El documento no existe o no tienes acceso a él.');
		}
		return contenido(documentId);
	}

	/** Archivo de un asegurado (de su contacto, cuenta o registro): solo si está en su lista de archivos. */
	static Map<String, Object> archivoDeAsegurado(Id participanteId, String documentId) {
		Boolean suyo = false;
		Object lista = MovimientosColectivoController.archivosAsegurado(participanteId).get('archivos');
		for (Object o : lista == null ? new List<Object>() : (List<Object>) lista) {
			if (String.valueOf(((Map<String, Object>) o).get('id')) == documentId) { suyo = true; }
		}
		if (String.isBlank(documentId) || !suyo) {
			throw aviso('El documento no existe o no tienes acceso a él.');
		}
		return contenido(documentId);
	}

	/** Nombre, tipo MIME y contenido en base64 de la última versión de un documento. */
	static Map<String, Object> contenido(String documentId) {
		ContentVersion v = [
			SELECT Title, FileExtension, ContentSize, VersionData
			FROM ContentVersion WHERE ContentDocumentId = :documentId AND IsLatest = true LIMIT 1
		];
		if (v.ContentSize > MAX_BYTES) {
			throw aviso('El documento es demasiado grande para descargarlo aquí. Pídelo a tu asesor.');
		}
		String ext = v.FileExtension == null ? '' : v.FileExtension.toLowerCase();
		Map<String, String> mimes = new Map<String, String>{ 'pdf' => 'application/pdf', 'png' => 'image/png',
			'jpg' => 'image/jpeg', 'jpeg' => 'image/jpeg', 'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
			'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' };
		return new Map<String, Object>{
			'nombre' => String.isBlank(ext) ? v.Title : v.Title + '.' + ext,
			'mime' => mimes.containsKey(ext) ? mimes.get(ext) : 'application/octet-stream',
			'base64' => EncodingUtil.base64Encode(v.VersionData)
		};
	}

	/** «Otras pólizas»: solo las pólizas a las que el usuario del sitio tiene acceso, sin liga a Salesforce. */
	static Map<String, Object> soloSuyas(Map<String, Object> res, Set<Id> suyas) {
		List<Object> polizas = new List<Object>();
		for (Object o : res.get('polizas') == null ? new List<Object>() : (List<Object>) res.get('polizas')) {
			Object id = ((Map<String, Object>) o).get('polizaId');
			if (id != null && suyas.contains((Id) id)) { polizas.add(o); }
		}
		res.put('polizas', polizas);
		res.put('portal', true);
		return res;
	}

	/**
	 * @creation date: 20/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Lo que el contratante registra en Asegurados, Vehículos o Ubicaciones del sitio sigue el mismo proceso
	 * que una solicitud enviada desde Solicitudes: si el folio aún no tiene caso, se crea el caso «Solicitud de
	 * movimientos» (Solicitado, del ejecutivo dueño de la póliza, con aviso a Avanza por el flujo del caso), así aparece
	 * en Salesforce entre las solicitudes del sitio en trámite y en el sitio con su caso.
	 * @param policyId: Id de la póliza
	 * @param cuentaVistaPrevia: Cuenta a simular (vista previa de administrador); null para el usuario real
	 * @param r: resultado de aplicar (solicitud, altas, bajas, cambios)
	 * @return el mismo resultado, con el número de caso
	 */
	@TestVisible
	static Map<String, Object> casoDelSitio(Id policyId, Id cuentaVistaPrevia, Map<String, Object> r) {
		String folio = r == null ? null : (String) r.get('solicitud');
		Id tipoCaso = EndosoPoliza.tipoCaso();
		if (String.isBlank(folio) || tipoCaso == null) { return r; }
		List<Case> existentes = [SELECT CaseNumber FROM Case WHERE RecordTypeId = :tipoCaso AND InsurancePolicy__c = :policyId
			AND Solicitud__c = :folio LIMIT 1];
		if (!existentes.isEmpty()) {
			r.put('caso', existentes[0].CaseNumber);
			return r;
		}
		List<String> resumen = new List<String>();
		Map<String, String> nombres = new Map<String, String>{ 'altas' => 'alta', 'bajas' => 'baja', 'cambios' => 'cambio' };
		String tipoUnico = null;
		Integer tipos = 0;
		for (String k : new List<String>{ 'altas', 'bajas', 'cambios' }) {
			Integer n = r.get(k) == null ? 0 : Integer.valueOf(r.get(k));
			if (n > 0) {
				resumen.add(n + ' ' + nombres.get(k) + (n == 1 ? '' : 's'));
				tipos++;
				tipoUnico = nombres.get(k).capitalize();
			}
		}
		InsurancePolicy p = [SELECT Name, OwnerId FROM InsurancePolicy WHERE Id = :policyId LIMIT 1];
		List<Id> yo = PortalPolizasController.identidad(cuentaVistaPrevia);
		Case c = new Case(RecordTypeId = tipoCaso, InsurancePolicy__c = policyId, AccountId = yo.isEmpty() ? null : yo[0],
			Origin = 'Sitio Web', Solicitud__c = folio, Poliza_Number__c = p.Name,
			Subject = (folio + ' · Póliza ' + p.Name + (resumen.isEmpty() ? '' : ' · ' + String.join(resumen, ', '))).left(255),
			Description = 'Solicitud ' + folio + ' registrada desde el sitio por ' + UserInfo.getName()
				+ (cuentaVistaPrevia == null ? '' : ' (vista previa de administrador)') + ' para la póliza ' + p.Name + '.');
		if (tipos == 1) { c.Reason = tipoUnico; }
		// Queda Solicitado hasta que el ejecutivo la atiende.
		String solicitado = EndosoPoliza.estadoCaso('Solicitado');
		if (solicitado != null) { c.Status = solicitado; }
		// El caso lo atiende el ejecutivo dueño de la póliza.
		if (p.OwnerId != null && p.OwnerId.getSobjectType() == User.SObjectType
				&& [SELECT COUNT() FROM User WHERE Id = :p.OwnerId AND IsActive = true AND ContactId = null] > 0) {
			c.OwnerId = p.OwnerId;
		}
		insert c;
		r.put('caso', [SELECT CaseNumber FROM Case WHERE Id = :c.Id].CaseNumber);
		return r;
	}
}
