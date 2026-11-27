/**
 * @creation date: 01/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Participantes de una póliza (InsurancePolicyParticipant) de cualquier ramo con su información
 *               relacionada, para el LWC participantesPoliza: contratante (cuenta asegurada), asegurados (titulares) con
 *               sus dependientes, beneficiarios y otros roles (conductor, propietario, pagador…). De cada participante
 *               trae su contacto o cuenta (RFC, correo, teléfono, domicilio), sus coberturas individuales, su vigencia y
 *               baja, y su antigüedad (participante de la vigencia anterior y original). Solo lectura.
 */
public inherited sharing class ParticipantesPolizaController {

	private static final Integer MAX_PARTICIPANTES = 5000;
	private static final String ROL_ASEGURADO = 'asegurado';
	private static final String ROL_DEPENDIENTE = 'dependiente';
	private static final String ROL_BENEFICIARIO = 'beneficiario';
	private static final String ROL_OTRO = 'otro';

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Datos de la póliza y de todos sus participantes.
	 * @param policyId: póliza (InsurancePolicy).
	 * @return mapa con poliza (datos generales y contratante), participantes y resumen.
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> getDatos(Id policyId) {
		try {
			InsurancePolicy pol = [
				SELECT Id, Name, Ramo__c, PolicyType, Status, EffectiveDate, ExpirationDate, NameInsuredId, NameInsured.Name, PriorPolicyId, PriorPolicy.Name
				FROM InsurancePolicy WHERE Id = :policyId LIMIT 1
			];
			List<InsurancePolicyParticipant> lista = participantes(policyId);
			Set<Id> cuentaIds = new Set<Id>();
			Set<Id> contactoIds = new Set<Id>();
			if (pol.NameInsuredId != null) { cuentaIds.add(pol.NameInsuredId); }
			for (InsurancePolicyParticipant p : lista) {
				for (String campo : new List<String>{ 'PrimaryParticipantAccountId', 'RelatedParticipantAccountId' }) {
					if (p.get(campo) != null) { cuentaIds.add((Id) p.get(campo)); }
				}
				for (String campo : new List<String>{ 'PrimaryParticipantContactId', 'RelatedParticipantContactId', 'LegalGuardianId' }) {
					if (p.get(campo) != null) { contactoIds.add((Id) p.get(campo)); }
				}
			}
			Map<Id, Map<String, Object>> cuentas = cuentas(cuentaIds);
			Map<Id, Map<String, Object>> contactos = contactos(contactoIds);
			Map<Id, List<Object>> coberturas = coberturas(policyId);
			// Archivos adjuntos al contacto, a la cuenta (persona) o al propio participante.
			Set<Id> conArchivos = new Set<Id>(contactoIds);
			for (InsurancePolicyParticipant p : lista) {
				conArchivos.add(p.Id);
				if (p.PrimaryParticipantAccountId != null) { conArchivos.add(p.PrimaryParticipantAccountId); }
			}
			// Los archivos de la póliza (carátula, endosos) se muestran también en el contratante.
			conArchivos.add(pol.Id);
			Map<Id, List<Map<String, Object>>> archivos = archivosDe(conArchivos);

			Map<String, String> roles = etiquetas(InsurancePolicyParticipant.Role.getDescribe());
			Map<String, String> parentescos = etiquetas(InsurancePolicyParticipant.RelationshipToInsured.getDescribe());
			Map<String, String> motivos = etiquetas(InsurancePolicyParticipant.Motivo_Baja__c.getDescribe());
			Map<Id, Movimiento_Poliza__c> ultimos = MovimientosColectivoController.ultimosMovimientos(policyId);
			List<Object> res = new List<Object>();
			Map<String, Integer> resumen = new Map<String, Integer>{
				ROL_ASEGURADO => 0, ROL_DEPENDIENTE => 0, ROL_BENEFICIARIO => 0, ROL_OTRO => 0, 'vigentes' => 0, 'bajas' => 0
			};
			for (InsurancePolicyParticipant p : lista) {
				Map<String, Object> m = participante(p, roles, parentescos, motivos);
				if (m.get('antiguedad') == null && pol.EffectiveDate != null) {
					m.put('antiguedad', pol.EffectiveDate.date());
					m.put('antiguedadOrigen', 'Inicio');
				}
				// Tipo y fecha del último movimiento (alta, baja o cambio).
				MovimientosColectivoController.ponerMovimiento(m, ultimos.get(p.Id), m.get('activo') == true, (Date) m.get('desde'),
					p.EffectiveToDate != null ? p.EffectiveToDate : (Date) m.get('hasta'));
				m.put('contacto', p.PrimaryParticipantContactId == null ? null : contactos.get(p.PrimaryParticipantContactId));
				m.put('cuenta', p.PrimaryParticipantAccountId == null ? null : cuentas.get(p.PrimaryParticipantAccountId));
				m.put('contactoRelacionado', p.RelatedParticipantContactId == null ? null : contactos.get(p.RelatedParticipantContactId));
				m.put('tutor', p.LegalGuardianId == null ? null : contactos.get(p.LegalGuardianId));
				Boolean esContratante = lista.size() == 1
					|| (pol.NameInsuredId != null && p.PrimaryParticipantAccountId == pol.NameInsuredId);
				m.put('archivos', unirArchivos(archivos, new List<Id>{ p.PrimaryParticipantContactId, p.PrimaryParticipantAccountId, p.Id,
					esContratante ? pol.Id : null }));
				List<Object> cob = coberturas.containsKey(p.Id) ? coberturas.get(p.Id) : new List<Object>();
				m.put('coberturas', cob);
				Decimal suma = null;
				for (Object o : cob) {
					Decimal l = (Decimal) ((Map<String, Object>) o).get('suma');
					if (l != null && (suma == null || l > suma)) { suma = l; }
				}
				m.put('sumaAsegurada', suma);
				String grupo = (String) m.get('grupo');
				resumen.put(grupo, resumen.get(grupo) + 1);
				resumen.put(m.get('activo') == true ? 'vigentes' : 'bajas', resumen.get(m.get('activo') == true ? 'vigentes' : 'bajas') + 1);
				res.add(m);
			}
			return new Map<String, Object>{
				'poliza' => new Map<String, Object>{
					'id' => pol.Id, 'nombre' => pol.Name, 'ramo' => pol.Ramo__c, 'tipo' => pol.PolicyType, 'estado' => pol.Status,
					'inicio' => pol.EffectiveDate == null ? null : pol.EffectiveDate.date(),
					'fin' => pol.ExpirationDate == null ? null : pol.ExpirationDate.date(),
					'anterior' => pol.PriorPolicyId == null ? null : pol.PriorPolicy.Name,
					'contratante' => pol.NameInsuredId == null ? null : cuentas.get(pol.NameInsuredId)
				},
				'participantes' => res,
				'resumen' => resumen,
				'limite' => lista.size() >= MAX_PARTICIPANTES
			};
		} catch (Exception e) {
			throw CensoColectivoController.error('No se pudieron leer los participantes: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 10/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Archivos (Salesforce Files) adjuntos a cada registro, del más reciente al más antiguo.
	 * @param ids: contactos, cuentas y participantes.
	 * @return Id del registro -> archivos {id, titulo, tipo, tamano, fecha}.
	 */
	public static Map<Id, List<Map<String, Object>>> archivosDe(Set<Id> ids) {
		Map<Id, List<Map<String, Object>>> r = new Map<Id, List<Map<String, Object>>>();
		ids.remove(null);
		if (ids.isEmpty()) { return r; }
		for (ContentDocumentLink l : [
			SELECT LinkedEntityId, ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension,
				ContentDocument.ContentSize, ContentDocument.LastModifiedDate, ContentDocument.CreatedDate, ContentDocument.Description
			FROM ContentDocumentLink WHERE LinkedEntityId IN :ids
			ORDER BY ContentDocument.LastModifiedDate DESC LIMIT 2000
		]) {
			if (!r.containsKey(l.LinkedEntityId)) { r.put(l.LinkedEntityId, new List<Map<String, Object>>()); }
			r.get(l.LinkedEntityId).add(new Map<String, Object>{
				'id' => l.ContentDocumentId, 'titulo' => l.ContentDocument.Title, 'tipo' => l.ContentDocument.FileExtension,
				'tamano' => l.ContentDocument.ContentSize, 'creado' => l.ContentDocument.CreatedDate, 'descripcion' => l.ContentDocument.Description,
				'fecha' => l.ContentDocument.LastModifiedDate == null ? null : l.ContentDocument.LastModifiedDate.date()
			});
		}
		return r;
	}

	// Archivos de varios registros sin repetir el mismo documento.
	public static List<Object> unirArchivos(Map<Id, List<Map<String, Object>>> archivos, List<Id> ids) {
		List<Object> l = new List<Object>();
		Set<Object> vistos = new Set<Object>();
		for (Id i : ids) {
			if (i == null || !archivos.containsKey(i)) { continue; }
			for (Map<String, Object> a : archivos.get(i)) {
				if (vistos.add(a.get('id'))) { l.add(a); }
			}
		}
		return l;
	}

	/**
	 * @creation date: 11/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Plantillas de correo activas para enviar a los participantes (sin las de ejemplo ni las del sistema).
	 * @return lista {id, nombre, carpeta}.
	 */
	@AuraEnabled(cacheable=true)
	public static List<Map<String, Object>> getPlantillas() {
		List<Map<String, Object>> r = new List<Map<String, Object>>();
		for (EmailTemplate t : [
			SELECT Id, Name, DeveloperName, Folder.Name FROM EmailTemplate
			WHERE IsActive = true AND TemplateType IN ('custom', 'html', 'text')
			ORDER BY Folder.Name NULLS LAST, Name LIMIT 1000
		]) {
			if (t.Name.startsWith('SAMPLE') || t.Name.startsWith('SUPPORT') || t.Name.startsWith('Experience Cloud')
				|| t.DeveloperName.startsWith('Community') || t.DeveloperName.endsWith('_OOTB_1')) { continue; }
			r.add(new Map<String, Object>{ 'id' => t.Id, 'nombre' => t.Name, 'clave' => t.DeveloperName, 'carpeta' => t.Folder == null ? null : t.Folder.Name });
		}
		return r;
	}

	/**
	 * @creation date: 11/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Envía la plantilla a cada participante (al correo de su contacto o cuenta), desde info@avanzaseguro.com,
	 *               opcionalmente con sus archivos adjuntos, y marca al participante como «correo enviado».
	 * @param policyId: póliza.
	 * @param participanteIds: participantes a los que se envía (máximo 50 por llamada).
	 * @param plantillaId: plantilla de correo.
	 * @param adjuntarArchivos: adjunta los archivos del participante (contacto, cuenta o participante).
	 * @param correosJson: { participanteId: correo } de los dados de baja a los que se les cambió el correo (opcional). Sin
	 *        cambio, el de un dependiente dado de baja le llega a su titular.
	 * @param copias: correos que reciben copia de cada correo (separados por coma o punto y coma; opcional, máximo 5).
	 * @return {enviados, errores}. A quien se le envió, su registro queda Concluido (el estatus del movimiento no cambia).
	 */
	@AuraEnabled
	public static Map<String, Object> enviarCorreo(Id policyId, List<Id> participanteIds, Id plantillaId, Boolean adjuntarArchivos,
			String correosJson, String copias) {
		if (participanteIds == null || participanteIds.isEmpty()) { throw CensoColectivoController.error('Selecciona al menos un participante.'); }
		if (participanteIds.size() > 50) { throw CensoColectivoController.error('Envía máximo 50 correos a la vez.'); }
		List<String> cc = RenovacionGmmContributoria.correos(copias);
		List<EmailTemplate> tpls = [SELECT Id, Name FROM EmailTemplate WHERE Id = :plantillaId AND IsActive = true LIMIT 1];
		if (tpls.isEmpty()) { throw CensoColectivoController.error('Selecciona una plantilla de correo activa.'); }
		EmailTemplate tpl = tpls[0];
		Map<Id, String> correosBaja = correosDeBaja(correosJson);
		List<InsurancePolicyParticipant> ps = [
			SELECT Id, ParticipantName, ParticipantCode, PrimaryParticipantContactId, PrimaryParticipantAccountId,
				IsActiveParticipant, Correo_Personal__c, Motivo_Baja__c, EffectiveToDate, RelatedInsPolicyParticipantId
			FROM InsurancePolicyParticipant WHERE Id IN :participanteIds AND InsurancePolicyId = :policyId
		];
		// Datos de la póliza para las plantillas con marcadores {{...}}.
		InsurancePolicy pol = [SELECT Id, Name, EffectiveDate, ExpirationDate FROM InsurancePolicy WHERE Id = :policyId LIMIT 1];
		String vigencia = pol.EffectiveDate == null ? '' : pol.EffectiveDate.format('dd/MM/yyyy')
			+ (pol.ExpirationDate == null ? '' : ' al ' + pol.ExpirationDate.format('dd/MM/yyyy'));
		String aseguradora = aseguradoraDe(policyId);
		Set<Id> cIds = new Set<Id>();
		Set<Id> aIds = new Set<Id>();
		// Titulares de los dependientes dados de baja: a ellos les llega el correo.
		Set<Id> titularIds = new Set<Id>();
		for (InsurancePolicyParticipant p : ps) {
			if (p.RelatedInsPolicyParticipantId != null && esBaja(p)) { titularIds.add(p.RelatedInsPolicyParticipantId); }
		}
		Map<Id, InsurancePolicyParticipant> titulares = titularesDe(titularIds);
		List<InsurancePolicyParticipant> conTitulares = new List<InsurancePolicyParticipant>(ps);
		conTitulares.addAll(titulares.values());
		for (InsurancePolicyParticipant p : conTitulares) {
			if (p.PrimaryParticipantContactId != null) { cIds.add(p.PrimaryParticipantContactId); }
			if (p.PrimaryParticipantAccountId != null) { aIds.add(p.PrimaryParticipantAccountId); }
		}
		Map<Id, Map<String, Object>> contactosM = contactos(cIds);
		Map<Id, Map<String, Object>> cuentasM = cuentas(aIds);
		List<OrgWideEmailAddress> owe = [SELECT Id FROM OrgWideEmailAddress WHERE Address = 'info@avanzaseguro.com' LIMIT 1];
		// A los dados de baja siempre se les adjunta su documento de baja (el subido o una constancia generada).
		Map<Id, List<Messaging.EmailFileAttachment>> adjuntos = adjuntos(ps, adjuntarArchivos == true, pol, aseguradora);

		List<String> errores = new List<String>();
		List<Messaging.SingleEmailMessage> mensajes = new List<Messaging.SingleEmailMessage>();
		List<InsurancePolicyParticipant> destinos = new List<InsurancePolicyParticipant>();
		for (InsurancePolicyParticipant p : ps) {
			Map<String, Object> c = p.PrimaryParticipantContactId != null ? contactosM.get(p.PrimaryParticipantContactId)
				: (p.PrimaryParticipantAccountId != null ? cuentasM.get(p.PrimaryParticipantAccountId) : null);
			String correo = c == null ? null : (String) c.get('correo');
			InsurancePolicyParticipant titular = esBaja(p) ? titulares.get(p.RelatedInsPolicyParticipantId) : null;
			Map<String, Object> ct = titular == null ? null : (titular.PrimaryParticipantContactId != null
				? contactosM.get(titular.PrimaryParticipantContactId) : cuentasM.get(titular.PrimaryParticipantAccountId));
			if (esBaja(p)) {
				// Dado de baja: el que se capturó al enviar, su correo personal (el corporativo suele dejar de existir) o, si es
				// dependiente, el de su titular.
				if (String.isNotBlank(correosBaja.get(p.Id))) { correo = correosBaja.get(p.Id); }
				else if (String.isNotBlank(p.Correo_Personal__c)) { correo = p.Correo_Personal__c; }
				else if (titular != null) {
					String suyo = esBaja(titular) && String.isNotBlank(titular.Correo_Personal__c) ? titular.Correo_Personal__c
						: (ct == null ? null : (String) ct.get('correo'));
					if (String.isNotBlank(suyo)) { correo = suyo; }
				}
			}
			if (String.isBlank(correo)) { errores.add(p.ParticipantName + ': no tiene correo.'); continue; }
			if (adjuntos.containsKey(p.Id) && adjuntos.get(p.Id) == null) {
				errores.add(p.ParticipantName + ': sus archivos pesan más de 4 MB; envíalo sin adjuntos.');
				continue;
			}
			Id whoId = p.PrimaryParticipantContactId != null ? p.PrimaryParticipantContactId : (c == null ? null : (Id) c.get('personContactId'));
			// El dependiente sin contacto: la plantilla se dirige a su titular.
			if (whoId == null && titular != null) {
				whoId = titular.PrimaryParticipantContactId != null ? titular.PrimaryParticipantContactId : (ct == null ? null : (Id) ct.get('personContactId'));
			}
			Messaging.SingleEmailMessage m;
			try {
				m = renderizar(tpl.Id, whoId, policyId);
			} catch (Exception e) {
				errores.add(p.ParticipantName + ': no se pudo armar el correo (' + e.getMessage() + ').');
				continue;
			}
			llenarMarcadores(m, new Map<String, String>{
				'NOMBRE_ASEGURADO' => p.ParticipantName, 'POLIZA' => pol.Name, 'CERTIFICADO' => CensoColectivoController.certificadoLimpio(p.ParticipantCode),
				'ASEGURADORA' => aseguradora, 'VIGENCIA' => vigencia, 'CORREO_SERVICIO' => 'info@avanzaseguro.com'
			});
			m.setToAddresses(new List<String>{ correo });
			if (!cc.isEmpty()) { m.setCcAddresses(cc); }
			if (!owe.isEmpty()) { m.setOrgWideEmailAddressId(owe[0].Id); }
			m.setSaveAsActivity(false);
			if (adjuntos.containsKey(p.Id)) { m.setFileAttachments(adjuntos.get(p.Id)); }
			mensajes.add(m);
			destinos.add(p);
		}
		Integer enviados = 0;
		if (!mensajes.isEmpty()) {
			List<Messaging.SendEmailResult> res;
			try {
				res = Messaging.sendEmail(mensajes, false);
			} catch (Exception e) {
				throw CensoColectivoController.error('No se pudo enviar el correo: ' + e.getMessage()
					+ ' Revisa en Configuración › Entregabilidad que el acceso esté en «Todo el email».');
			}
			List<InsurancePolicyParticipant> marcar = new List<InsurancePolicyParticipant>();
			for (Integer i = 0; i < res.size(); i++) {
				if (res[i].isSuccess()) {
					InsurancePolicyParticipant x = new InsurancePolicyParticipant(Id = destinos[i].Id, Correo_Enviado__c = true,
						Fecha_Envio_Correo__c = Datetime.now(), Plantilla_Correo__c = tpl.Name.left(255));
					// El correo que se cambió al enviar la baja queda como su correo personal.
					if (esBaja(destinos[i]) && String.isNotBlank(correosBaja.get(destinos[i].Id))) { x.Correo_Personal__c = correosBaja.get(destinos[i].Id); }
					marcar.add(x);
				} else {
					errores.add(destinos[i].ParticipantName + ': ' + res[i].getErrors()[0].getMessage());
				}
			}
			update marcar;
			enviados = marcar.size();
			// Con el correo enviado, el registro de cada uno queda Concluido (solo el ejecutivo; el estatus del movimiento no cambia).
			if (!marcar.isEmpty() && UserInfo.getUserType() == 'Standard') {
				try {
					EndosoPoliza.concluirConCorreo(policyId, new Map<Id, InsurancePolicyParticipant>(marcar).keySet());
				} catch (Exception e) {
					errores.add('El correo se envió, pero no se pudo concluir el registro: ' + e.getMessage());
				}
			}
		}
		return new Map<String, Object>{ 'enviados' => enviados, 'errores' => errores };
	}

	// Titulares (con su correo) de los dependientes.
	private static Map<Id, InsurancePolicyParticipant> titularesDe(Set<Id> ids) {
		if (ids.isEmpty()) { return new Map<Id, InsurancePolicyParticipant>(); }
		return new Map<Id, InsurancePolicyParticipant>([
			SELECT Id, PrimaryParticipantContactId, PrimaryParticipantAccountId, IsActiveParticipant, Correo_Personal__c, Motivo_Baja__c, EffectiveToDate
			FROM InsurancePolicyParticipant WHERE Id IN :ids
		]);
	}

	// Correos cambiados al enviar, validados.
	private static Map<Id, String> correosDeBaja(String json) {
		Map<Id, String> r = new Map<Id, String>();
		if (String.isBlank(json)) { return r; }
		Map<String, Object> m = (Map<String, Object>) System.JSON.deserializeUntyped(json);
		for (String k : m.keySet()) {
			String correo = m.get(k) == null ? '' : String.valueOf(m.get(k)).trim();
			if (correo == '') { continue; }
			if (correo.length() > 80 || !Pattern.matches('[^@\\s,;]+@[^@\\s,;]+\\.[^@\\s,;]+', correo)) {
				throw CensoColectivoController.error('El correo «' + correo + '» no es válido.');
			}
			r.put(Id.valueOf(k), correo);
		}
		return r;
	}

	// Reemplaza los marcadores {{NOMBRE}} de la plantilla. Los enlaces {{LINK_...}} sin valor quedan como «#» y cualquier
	// otro marcador sin valor se quita.
	@TestVisible
	private static void llenarMarcadores(Messaging.SingleEmailMessage m, Map<String, String> valores) {
		m.setSubject(llenar(m.getSubject(), valores, false));
		if (m.getHtmlBody() != null) { m.setHtmlBody(llenar(m.getHtmlBody(), valores, true)); }
		if (m.getPlainTextBody() != null) { m.setPlainTextBody(llenar(m.getPlainTextBody(), valores, false)); }
	}

	@TestVisible
	private static String llenar(String texto, Map<String, String> valores, Boolean html) {
		if (String.isBlank(texto) || !texto.contains('{{')) { return texto; }
		String r = texto;
		for (String k : valores.keySet()) {
			String v = valores.get(k) == null ? '' : valores.get(k);
			if (html) { v = v.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;'); }
			r = r.replace('{{' + k + '}}', v);
		}
		r = r.replaceAll('\\{\\{LINK_[A-Z0-9_]+\\}\\}', '#');
		return r.replaceAll('\\{\\{[A-Z0-9_]+\\}\\}', '');
	}

	// Nombre de la aseguradora: la de la póliza o, si no tiene, la de su producto.
	private static String aseguradoraDe(Id policyId) {
		try {
			SObject p = Database.query('SELECT Aseguradora__r.Name, Product.Aseguradora__r.Name FROM InsurancePolicy WHERE Id = :policyId LIMIT 1');
			SObject a = p.getSObject('Aseguradora__r');
			if (a == null && p.getSObject('Product') != null) { a = p.getSObject('Product').getSObject('Aseguradora__r'); }
			return a == null ? '' : (String) a.get('Name');
		} catch (Exception e) {
			System.debug('Sin aseguradora en la póliza: ' + e.getMessage());
			return '';
		}
	}

	// Correo de cada participante: el de su contacto o, si no tiene, el de su cuenta.
	public static Map<Id, String> correosDe(List<InsurancePolicyParticipant> ps) {
		Set<Id> cIds = new Set<Id>();
		Set<Id> aIds = new Set<Id>();
		for (InsurancePolicyParticipant p : ps) {
			if (p.PrimaryParticipantContactId != null) { cIds.add(p.PrimaryParticipantContactId); }
			if (p.PrimaryParticipantAccountId != null) { aIds.add(p.PrimaryParticipantAccountId); }
		}
		Map<Id, Map<String, Object>> cs = contactos(cIds);
		Map<Id, Map<String, Object>> as2 = cuentas(aIds);
		Map<Id, String> r = new Map<Id, String>();
		for (InsurancePolicyParticipant p : ps) {
			Map<String, Object> c = p.PrimaryParticipantContactId != null ? cs.get(p.PrimaryParticipantContactId)
				: (p.PrimaryParticipantAccountId != null ? as2.get(p.PrimaryParticipantAccountId) : null);
			if (c != null && String.isNotBlank((String) c.get('correo'))) { r.put(p.Id, (String) c.get('correo')); }
		}
		return r;
	}

	// Asunto y cuerpo de la plantilla con los datos del destinatario y de la póliza (o solo del destinatario si la
	// plantilla es de otro objeto).
	private static Messaging.SingleEmailMessage renderizar(Id plantillaId, Id whoId, Id whatId) {
		Messaging.SingleEmailMessage r;
		try {
			r = Messaging.renderStoredEmailTemplate(plantillaId, whoId, whatId);
		} catch (Exception e) {
			r = Messaging.renderStoredEmailTemplate(plantillaId, whoId, null);
		}
		Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
		m.setSubject(r.getSubject());
		if (r.getHtmlBody() != null) { m.setHtmlBody(r.getHtmlBody()); }
		if (r.getPlainTextBody() != null) { m.setPlainTextBody(r.getPlainTextBody()); }
		return m;
	}

	// Archivos de cada participante (contacto, cuenta o participante) como adjuntos. A un dado de baja solo se le adjunta
	// el documento de su último movimiento de baja; si no se subió ninguno se genera una constancia de baja en PDF.
	// Los activos solo llevan archivos si se pidió adjuntarlos (en un cambio, solo los del cambio). Si pasan de 4 MB en total se deja null para avisar.
	@TestVisible
	private static Map<Id, List<Messaging.EmailFileAttachment>> adjuntos(List<InsurancePolicyParticipant> ps, Boolean todos,
		InsurancePolicy pol, String aseguradora) {
		Set<Id> ids = new Set<Id>();
		Set<Id> inactivos = new Set<Id>();
		for (InsurancePolicyParticipant p : ps) {
			if (esBaja(p)) { inactivos.add(p.Id); continue; }
			if (!todos) { continue; }
			ids.add(p.Id);
			ids.add(p.PrimaryParticipantContactId);
			ids.add(p.PrimaryParticipantAccountId);
		}
		Map<Id, Id> bajaDe = new Map<Id, Id>();
		Map<Id, Movimiento_Poliza__c> movBaja = new Map<Id, Movimiento_Poliza__c>();
		Map<Id, InsurancePolicyParticipant> datosBaja = new Map<Id, InsurancePolicyParticipant>();
		if (!inactivos.isEmpty()) {
			for (Movimiento_Poliza__c m : [
				SELECT Id, Participante__c, Fecha_Movimiento__c, toLabel(Motivo_Baja__c), Numero_Endoso__c, Certificado__c, Comentario__c, CreatedDate
				FROM Movimiento_Poliza__c
				WHERE Participante__c IN :inactivos AND Tipo__c = 'Baja' ORDER BY CreatedDate DESC, Id DESC LIMIT 10000
			]) {
				if (!bajaDe.containsKey(m.Participante__c)) { bajaDe.put(m.Participante__c, m.Id); movBaja.put(m.Participante__c, m); ids.add(m.Id); }
			}
			datosBaja = new Map<Id, InsurancePolicyParticipant>([
				SELECT Id, ParticipantName, ParticipantCode, Role, RelationshipToInsured, EffectiveToDate, toLabel(Motivo_Baja__c)
				FROM InsurancePolicyParticipant WHERE Id IN :inactivos
			]);
		}
		ids.remove(null);
		Map<Id, List<Map<String, Object>>> archivos = archivosDe(ids);
		Map<Id, Datetime> cambios = cambiosDe(ps, inactivos);
		Map<Id, List<Object>> porParticipante = new Map<Id, List<Object>>();
		Set<Id> docIds = new Set<Id>();
		Long total = 0;
		Map<Id, List<Messaging.EmailFileAttachment>> r = new Map<Id, List<Messaging.EmailFileAttachment>>();
		for (InsurancePolicyParticipant p : ps) {
			Boolean deBaja = inactivos.contains(p.Id);
			if (!deBaja && !todos) { continue; }
			List<Object> suyos = deBaja
				? (bajaDe.containsKey(p.Id) ? unirArchivos(archivos, new List<Id>{ bajaDe.get(p.Id) }) : new List<Object>())
				: unirArchivos(archivos, new List<Id>{ p.PrimaryParticipantContactId, p.PrimaryParticipantAccountId, p.Id });
			if (!deBaja && cambios.containsKey(p.Id)) { suyos = soloDelCambio(suyos, cambios.get(p.Id)); }
			if (suyos.isEmpty() && deBaja) {
				Messaging.EmailFileAttachment c = constanciaBaja(datosBaja.get(p.Id), movBaja.get(p.Id), pol, aseguradora);
				if (c != null) { r.put(p.Id, new List<Messaging.EmailFileAttachment>{ c }); }
				continue;
			}
			if (suyos.isEmpty()) { continue; }
			Long peso = 0;
			for (Object o : suyos) {
				Object t = ((Map<String, Object>) o).get('tamano');
				if (t != null) { peso += (Integer) t; }
			}
			if (total + peso > 4 * 1024 * 1024) { r.put(p.Id, null); continue; }
			total += peso;
			porParticipante.put(p.Id, suyos);
			for (Object o : suyos) { docIds.add((Id) ((Map<String, Object>) o).get('id')); }
		}
		if (docIds.isEmpty()) { return r; }
		Map<Id, ContentVersion> versiones = new Map<Id, ContentVersion>();
		for (ContentVersion v : [
			SELECT ContentDocumentId, Title, FileExtension, PathOnClient, VersionData
			FROM ContentVersion WHERE ContentDocumentId IN :docIds AND IsLatest = true
		]) { versiones.put(v.ContentDocumentId, v); }
		for (Id pid : porParticipante.keySet()) {
			List<Messaging.EmailFileAttachment> l = new List<Messaging.EmailFileAttachment>();
			for (Object o : porParticipante.get(pid)) {
				ContentVersion v = versiones.get((Id) ((Map<String, Object>) o).get('id'));
				if (v == null) { continue; }
				Messaging.EmailFileAttachment a = new Messaging.EmailFileAttachment();
				a.setFileName(String.isNotBlank(v.FileExtension) && !v.Title.endsWithIgnoreCase('.' + v.FileExtension) ? v.Title + '.' + v.FileExtension : v.Title);
				a.setBody(v.VersionData);
				l.add(a);
			}
			r.put(pid, l);
		}
		return r;
	}

	// Asegurados cuyo último movimiento es un cambio: cuándo se registró.
	private static Map<Id, Datetime> cambiosDe(List<InsurancePolicyParticipant> ps, Set<Id> inactivos) {
		Set<Id> ids = new Map<Id, InsurancePolicyParticipant>(ps).keySet().clone();
		ids.removeAll(inactivos);
		Map<Id, Datetime> r = new Map<Id, Datetime>();
		if (ids.isEmpty()) { return r; }
		Set<Id> vistos = new Set<Id>();
		for (Movimiento_Poliza__c m : [
			SELECT Participante__c, Tipo__c, CreatedDate FROM Movimiento_Poliza__c WHERE Participante__c IN :ids ORDER BY CreatedDate DESC, Id DESC LIMIT 10000
		]) {
			if (vistos.add(m.Participante__c) && m.Tipo__c == 'Cambio') { r.put(m.Participante__c, m.CreatedDate); }
		}
		return r;
	}

	// Archivos del cambio: los que dicen «cambio» en su nombre (o en su contenido, al adjuntarlos) desde que se registró; si
	// ninguno es de después, los que dicen «cambio». Si ninguno lo dice, los adjuntados después que no son de alta ni de baja.
	@TestVisible
	private static List<Object> soloDelCambio(List<Object> archivos, Datetime registrado) {
		List<Object> delCambio = new List<Object>();
		List<Object> recientes = new List<Object>();
		List<Object> otros = new List<Object>();
		for (Object o : archivos) {
			Map<String, Object> a = (Map<String, Object>) o;
			Boolean despues = a.get('creado') != null && (Datetime) a.get('creado') >= registrado;
			String tipo = movimientoDeArchivo((String) a.get('titulo'), (String) a.get('descripcion'));
			if (tipo == 'Cambio') {
				delCambio.add(o);
				if (despues) { recientes.add(o); }
			} else if (tipo == null && despues) {
				otros.add(o);
			}
		}
		return !recientes.isEmpty() ? recientes : (!delCambio.isEmpty() ? delCambio : otros);
	}

	// Alta, Baja o Cambio según el nombre del archivo («0000000364_CAMBIO_CERT_...») o lo que se leyó de él al adjuntarlo
	// («Movimiento: Cambio» en su descripción); null si no lo dice.
	@TestVisible
	private static String movimientoDeArchivo(String titulo, String descripcion) {
		String d = descripcion == null ? '' : descripcion;
		for (String t : new List<String>{ 'Cambio', 'Alta', 'Baja' }) { if (d.startsWith(MARCA_MOVIMIENTO + t)) { return t; } }
		Set<String> palabras = new Set<String>(CensoColectivoController.llave(titulo == null ? '' : titulo.replace('_', ' ')).split(' '));
		if (palabras.contains('cambio') || palabras.contains('cambios') || palabras.contains('modificacion')) { return 'Cambio'; }
		if (palabras.contains('baja') || palabras.contains('bajas')) { return 'Baja'; }
		return palabras.contains('alta') || palabras.contains('altas') ? 'Alta' : null;
	}
	public static final String MARCA_MOVIMIENTO = 'Movimiento: ';

	// Dado de baja: tiene motivo de baja, o está inactivo con fecha de fin.
	private static Boolean esBaja(InsurancePolicyParticipant p) {
		return p.Motivo_Baja__c != null || (p.IsActiveParticipant == false && p.EffectiveToDate != null);
	}

	// Constancia de baja en PDF armada con los datos del participante y de su movimiento de baja.
	@TestVisible
	private static Messaging.EmailFileAttachment constanciaBaja(InsurancePolicyParticipant p, Movimiento_Poliza__c m,
		InsurancePolicy pol, String aseguradora) {
		if (p == null) { return null; }
		Date fecha = m != null && m.Fecha_Movimiento__c != null ? m.Fecha_Movimiento__c
			: (p.EffectiveToDate != null ? p.EffectiveToDate :(m != null ? m.CreatedDate.date() : Date.today()));
		String motivo = m != null && String.isNotBlank(m.Motivo_Baja__c) ? m.Motivo_Baja__c : p.Motivo_Baja__c;
		String certificado = CensoColectivoController.certificadoLimpio(m != null && String.isNotBlank(m.Certificado__c) ? m.Certificado__c : p.ParticipantCode);
		List<List<String>> filas = new List<List<String>>{
			new List<String>{ 'Asegurado', p.ParticipantName },
			new List<String>{ 'Póliza', pol.Name },
			new List<String>{ 'Aseguradora', aseguradora },
			new List<String>{ 'Certificado', certificado },
			new List<String>{ 'Parentesco', p.RelationshipToInsured },
			new List<String>{ 'Fecha de baja', fecha.format() },
			new List<String>{ 'Motivo de baja', motivo },
			new List<String>{ 'Número de endoso', m == null ? null : m.Numero_Endoso__c },
			new List<String>{ 'Comentario', m == null ? null : m.Comentario__c }
		};
		String tabla = '';
		for (List<String> f : filas) {
			if (String.isBlank(f[1])) { continue; }
			tabla += '<tr><td style="padding:6px 10px;border:1px solid #D5DEEE;background:#EEF3FB;color:#1F4E9C;font-weight:bold;width:35%;">'
				+ f[0].escapeHtml4() + '</td><td style="padding:6px 10px;border:1px solid #D5DEEE;">' + f[1].escapeHtml4() + '</td></tr>';
		}
		String html = '<html><head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/></head>'
			+ '<body style="font-family:Arial,Helvetica,sans-serif;font-size:12px;color:#1a1a1a;">'
			+ '<div style="background:#1F4E9C;color:#ffffff;padding:16px;text-align:center;">'
			+ '<div style="font-size:20px;font-weight:bold;">Constancia de baja</div>'
			+ '<div style="font-size:12px;">Avanza Seguro Consultores</div></div>'
			+ '<p style="margin-top:18px;">Se hace constar que la persona indicada fue dada de baja de la póliza empresarial con los siguientes datos:</p>'
			+ '<table style="width:100%;border-collapse:collapse;">' + tabla + '</table>'
			+ '<p style="margin-top:18px;">A partir de la fecha de baja ya no cuenta con la cobertura de esta póliza. '
			+ 'Conserve este documento para cualquier aclaración.</p>'
			+ '<p style="margin-top:30px;font-size:10px;color:#777777;">Documento generado el ' + Date.today().format()
			+ ' por Avanza Seguro Consultores · info@avanzaseguro.com</p></body></html>';
		Messaging.EmailFileAttachment a = new Messaging.EmailFileAttachment();
		a.setFileName(('Baja ' + p.ParticipantName).replaceAll('[\\\\/:*?"<>|]', '').left(120) + '.pdf');
		a.setContentType('application/pdf');
		a.setBody(Blob.toPdf(html));
		return a;
	}

	private static List<InsurancePolicyParticipant> participantes(Id policyId) {
		return [
			SELECT Id, Name, ParticipantName, ParticipantCode, Role, RelationshipToInsured, IsPolicyholder, IsActiveParticipant,
				Categoria__c, FechaNacimiento__c, Sexo__c, Identificacion__c, Motivo_Baja__c, BeneficiarySharePercentage, IsMinorBeneficiary,
				EffectiveDate, ExpirationDate, EffectiveFromDate, EffectiveToDate, StandardPremiumAmount,
				PrimaryParticipantContactId, PrimaryParticipantAccountId, RelatedParticipantContactId, RelatedParticipantAccountId,
				LegalGuardianId, RelatedInsPolicyParticipantId, RelatedInsPolicyParticipant.ParticipantName,
				PriorParticipantId, PriorParticipant.InsurancePolicy.Name,
				OriginalParticipantId, OriginalParticipant.InsurancePolicy.Name, OriginalParticipant.InsurancePolicy.EffectiveDate,
				OriginalParticipant.EffectiveFromDate, OriginalParticipant.Fecha_Antiguedad__c, PriorParticipant.Fecha_Antiguedad__c, Fecha_Antiguedad__c,
				Correo_Enviado__c, Fecha_Envio_Correo__c, Plantilla_Correo__c
			FROM InsurancePolicyParticipant
			WHERE InsurancePolicyId = :policyId
			ORDER BY ParticipantCode NULLS LAST, CreatedDate ASC
			LIMIT :MAX_PARTICIPANTES
		];
	}

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Participante para el LWC. El grupo sale del rol: beneficiario, dependiente (miembro familiar o ligado
	 *               a otro participante), asegurado (asegurado, miembro de plan, suscriptor) u otro.
	 */
	private static Map<String, Object> participante(InsurancePolicyParticipant p, Map<String, String> roles,
			Map<String, String> parentescos, Map<String, String> motivos) {
		List<String> rolesLista = String.isBlank(p.Role) ? new List<String>() : p.Role.split(';');
		List<String> rolesTexto = new List<String>();
		for (String r : rolesLista) { rolesTexto.add(roles.containsKey(r) ? roles.get(r) : r); }
		// Dado de baja por endoso: con motivo de baja, o inactivo con fecha de baja (vigente hasta). Los participantes que
		// se crean sin marcar «activo» (beneficiarios, asegurado de bienes) no traen fecha de baja y siguen vigentes.
		Boolean activo = !esBaja(p);
		// El grupo se decide por el valor y por la etiqueta del rol (el picklist estándar puede traer valores en inglés).
		List<String> llavesRol = new List<String>(rolesLista);
		llavesRol.addAll(rolesTexto);
		// Antigüedad: la reconocida (RA, de esta vigencia o de la anterior); si no, la de su primera póliza; si no, su alta.
		Date reconocida = p.Fecha_Antiguedad__c;
		if (reconocida == null && p.PriorParticipantId != null) { reconocida = p.PriorParticipant.Fecha_Antiguedad__c; }
		if (reconocida == null && p.OriginalParticipantId != null) { reconocida = p.OriginalParticipant.Fecha_Antiguedad__c; }
		Date primera = null;
		if (p.OriginalParticipantId != null) {
			primera = p.OriginalParticipant.EffectiveFromDate;
			if (primera == null && p.OriginalParticipant.InsurancePolicy.EffectiveDate != null) { primera = p.OriginalParticipant.InsurancePolicy.EffectiveDate.date(); }
		}
		Date alta = p.EffectiveFromDate != null ? p.EffectiveFromDate : (p.EffectiveDate == null ? null : p.EffectiveDate.date());
		return new Map<String, Object>{
			'id' => p.Id, 'folio' => p.Name, 'nombre' => p.ParticipantName, 'certificado' => CensoColectivoController.certificadoLimpio(p.ParticipantCode),
			'roles' => rolesTexto, 'rolesTexto' => String.join(rolesTexto, ', '), 'grupo' => grupo(llavesRol, p),
			'parentesco' => CensoColectivoController.parentescoPolizaVisible(p.RelationshipToInsured, parentescos),
			'titularId' => p.RelatedInsPolicyParticipantId,
			'titularNombre' => p.RelatedInsPolicyParticipantId == null ? null : p.RelatedInsPolicyParticipant.ParticipantName,
			'contratante' => p.IsPolicyholder == true, 'activo' => activo, 'categoria' => p.Categoria__c,
			'fechaNacimiento' => p.FechaNacimiento__c, 'sexo' => p.Sexo__c, 'identificacion' => p.Identificacion__c,
			'motivoBaja' => p.Motivo_Baja__c == null ? null : motivos.get(p.Motivo_Baja__c),
			'porcentaje' => p.BeneficiarySharePercentage, 'menor' => p.IsMinorBeneficiary == true,
			'desde' => p.EffectiveFromDate != null ? p.EffectiveFromDate : (p.EffectiveDate == null ? null : p.EffectiveDate.date()),
			'hasta' => p.EffectiveToDate != null ? p.EffectiveToDate : (p.ExpirationDate == null ? null : p.ExpirationDate.date()),
			'prima' => p.StandardPremiumAmount,
			'vigenciaAnterior' => p.PriorParticipantId == null ? null : p.PriorParticipant.InsurancePolicy.Name,
			'polizaOriginal' => p.OriginalParticipantId == null ? null : p.OriginalParticipant.InsurancePolicy.Name,
			'antiguedad' => reconocida != null ? reconocida : (primera != null ? primera : alta),
			'antiguedadOrigen' => reconocida != null ? 'Reconocida' : (primera != null ? 'Poliza' : 'Alta'),
			'correoEnviado' => p.Correo_Enviado__c == true, 'fechaCorreo' => p.Fecha_Envio_Correo__c,
			'plantillaCorreo' => p.Plantilla_Correo__c
		};
	}

	@TestVisible
	private static String grupo(List<String> roles, InsurancePolicyParticipant p) {
		Set<String> r = new Set<String>();
		for (String x : roles) { r.add(CensoColectivoController.llave(x)); }
		Boolean asegurado = r.contains('asegurado') || r.contains('insured') || r.contains('miembro') || r.contains('suscriptor')
			|| r.contains('miembro de plan de salud') || r.contains('miembro de plan de vida');
		if (r.contains('miembro familiar') || r.contains('familymember') || (p.RelatedInsPolicyParticipantId != null && !r.contains('beneficiario'))) { return ROL_DEPENDIENTE; }
		if (asegurado) { return ROL_ASEGURADO; }
		if (r.contains('beneficiario') || r.contains('beneficiary')) { return ROL_BENEFICIARIO; }
		return ROL_OTRO;
	}

	/**
	 * @creation date: 01/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cuentas (contratante y participantes que son empresas o personas cuenta). Los campos opcionales del
	 *               org (RFC, correo, datos de cuenta persona) solo se piden si existen.
	 */
	private static Map<Id, Map<String, Object>> cuentas(Set<Id> ids) {
		Map<Id, Map<String, Object>> res = new Map<Id, Map<String, Object>>();
		if (ids.isEmpty()) { return res; }
		Map<String, Schema.SObjectField> fm = Schema.SObjectType.Account.fields.getMap();
		List<String> campos = new List<String>{ 'Id', 'Name', 'Phone', 'BillingStreet', 'BillingCity', 'BillingState', 'BillingPostalCode' };
		for (String c : new List<String>{ 'RFC__c', 'Correo_electronico__c', 'PersonEmail', 'PersonMobilePhone', 'PersonBirthdate',
				'PersonMailingStreet', 'PersonMailingCity', 'PersonMailingState', 'PersonMailingPostalCode', 'IsPersonAccount', 'PersonContactId' }) {
			if (fm.containsKey(c.toLowerCase())) { campos.add(c); }
		}
		for (SObject a : Database.query('SELECT ' + String.join(campos, ', ') + ' FROM Account WHERE Id IN :ids')) {
			Boolean persona = campos.contains('IsPersonAccount') && a.get('IsPersonAccount') == true;
			String correo = (String) valor(a, campos, 'PersonEmail');
			if (String.isBlank(correo)) { correo = (String) valor(a, campos, 'Correo_electronico__c'); }
			String domicilio = persona && valor(a, campos, 'PersonMailingStreet') != null
				? domicilio((String) a.get('PersonMailingStreet'), (String) a.get('PersonMailingCity'), (String) a.get('PersonMailingState'), (String) a.get('PersonMailingPostalCode'))
				: domicilio((String) a.get('BillingStreet'), (String) a.get('BillingCity'), (String) a.get('BillingState'), (String) a.get('BillingPostalCode'));
			res.put(a.Id, new Map<String, Object>{
				'id' => a.Id, 'nombre' => a.get('Name'), 'tipo' => persona ? 'Persona' : 'Empresa', 'rfc' => valor(a, campos, 'RFC__c'),
				'correo' => correo, 'telefono' => a.get('Phone'), 'celular' => valor(a, campos, 'PersonMobilePhone'),
				'fechaNacimiento' => valor(a, campos, 'PersonBirthdate'), 'domicilio' => domicilio,
				'personContactId' => valor(a, campos, 'PersonContactId')
			});
		}
		return res;
	}

	private static Map<Id, Map<String, Object>> contactos(Set<Id> ids) {
		Map<Id, Map<String, Object>> res = new Map<Id, Map<String, Object>>();
		if (ids.isEmpty()) { return res; }
		Map<String, String> sexos = etiquetas(Contact.Sexo__c.getDescribe());
		for (Contact c : [
			SELECT Id, Name, Email, Phone, MobilePhone, Birthdate, RFC__c, Sexo__c, Title, AccountId, Account.Name,
				MailingStreet, MailingCity, MailingState, MailingPostalCode
			FROM Contact WHERE Id IN :ids
		]) {
			res.put(c.Id, new Map<String, Object>{
				'id' => c.Id, 'nombre' => c.Name, 'correo' => c.Email, 'telefono' => c.Phone, 'celular' => c.MobilePhone,
				'fechaNacimiento' => c.Birthdate, 'rfc' => c.RFC__c, 'sexo' => c.Sexo__c == null ? null : sexos.get(c.Sexo__c),
				'puesto' => c.Title, 'cuentaId' => c.AccountId, 'cuentaNombre' => c.AccountId == null ? null : c.Account.Name,
				'domicilio' => domicilio(c.MailingStreet, c.MailingCity, c.MailingState, c.MailingPostalCode)
			});
		}
		return res;
	}

	// Coberturas individuales (ligadas a un participante), por participante.
	private static Map<Id, List<Object>> coberturas(Id policyId) {
		Map<Id, List<Object>> res = new Map<Id, List<Object>>();
		for (InsurancePolicyCoverage c : [
			SELECT Id, CoverageName, LimitAmount, DeductibleAmount, StandardPremiumAmount, InsurancePolicyParticipantId
			FROM InsurancePolicyCoverage
			WHERE InsurancePolicyId = :policyId AND InsurancePolicyParticipantId != null
			ORDER BY CreatedDate ASC LIMIT 10000
		]) {
			if (!res.containsKey(c.InsurancePolicyParticipantId)) { res.put(c.InsurancePolicyParticipantId, new List<Object>()); }
			res.get(c.InsurancePolicyParticipantId).add(new Map<String, Object>{
				'id' => c.Id, 'nombre' => c.CoverageName, 'suma' => c.LimitAmount, 'deducible' => c.DeductibleAmount, 'prima' => c.StandardPremiumAmount
			});
		}
		return res;
	}

	private static Object valor(SObject s, List<String> campos, String campo) {
		return campos.contains(campo) ? s.get(campo) : null;
	}

	private static String domicilio(String calle, String ciudad, String estado, String cp) {
		List<String> l = new List<String>();
		for (String s : new List<String>{ calle == null ? null : calle.replace('\n', ', '), ciudad, estado, cp == null ? null : 'CP ' + cp }) {
			if (String.isNotBlank(s)) { l.add(s); }
		}
		return l.isEmpty() ? null : String.join(l, ', ');
	}

	private static Map<String, String> etiquetas(Schema.DescribeFieldResult f) {
		Map<String, String> res = new Map<String, String>();
		for (Schema.PicklistEntry pe : f.getPicklistValues()) { res.put(pe.getValue(), pe.getLabel()); }
		return res;
	}
}
