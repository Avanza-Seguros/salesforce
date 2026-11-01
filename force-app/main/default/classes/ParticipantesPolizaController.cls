/**
 * @creation date: 01/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Participantes de una póliza (InsurancePolicyParticipant) de cualquier ramo con su información
 *               relacionada, para el LWC participantesPoliza: contratante (cuenta asegurada), asegurados (titulares) con
 *               sus dependientes, beneficiarios y otros roles (conductor, propietario, pagador…). De cada participante
 *               trae su contacto o cuenta (RFC, correo, teléfono, domicilio), sus coberturas individuales, su vigencia y
 *               baja, y su antigüedad (participante de la vigencia anterior y original). Solo lectura.
 */
public with sharing class ParticipantesPolizaController {

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

			Map<String, String> roles = etiquetas(InsurancePolicyParticipant.Role.getDescribe());
			Map<String, String> parentescos = etiquetas(InsurancePolicyParticipant.RelationshipToInsured.getDescribe());
			Map<String, String> motivos = etiquetas(InsurancePolicyParticipant.Motivo_Baja__c.getDescribe());
			List<Object> res = new List<Object>();
			Map<String, Integer> resumen = new Map<String, Integer>{
				ROL_ASEGURADO => 0, ROL_DEPENDIENTE => 0, ROL_BENEFICIARIO => 0, ROL_OTRO => 0, 'vigentes' => 0, 'bajas' => 0
			};
			for (InsurancePolicyParticipant p : lista) {
				Map<String, Object> m = participante(p, roles, parentescos, motivos);
				m.put('contacto', p.PrimaryParticipantContactId == null ? null : contactos.get(p.PrimaryParticipantContactId));
				m.put('cuenta', p.PrimaryParticipantAccountId == null ? null : cuentas.get(p.PrimaryParticipantAccountId));
				m.put('contactoRelacionado', p.RelatedParticipantContactId == null ? null : contactos.get(p.RelatedParticipantContactId));
				m.put('tutor', p.LegalGuardianId == null ? null : contactos.get(p.LegalGuardianId));
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

	private static List<InsurancePolicyParticipant> participantes(Id policyId) {
		return [
			SELECT Id, Name, ParticipantName, ParticipantCode, Role, RelationshipToInsured, IsPolicyholder, IsActiveParticipant,
				Categoria__c, FechaNacimiento__c, Identificacion__c, Motivo_Baja__c, BeneficiarySharePercentage, IsMinorBeneficiary,
				EffectiveDate, ExpirationDate, EffectiveFromDate, EffectiveToDate, StandardPremiumAmount,
				PrimaryParticipantContactId, PrimaryParticipantAccountId, RelatedParticipantContactId, RelatedParticipantAccountId,
				LegalGuardianId, RelatedInsPolicyParticipantId, RelatedInsPolicyParticipant.ParticipantName,
				PriorParticipantId, PriorParticipant.InsurancePolicy.Name,
				OriginalParticipantId, OriginalParticipant.InsurancePolicy.Name, OriginalParticipant.InsurancePolicy.EffectiveDate
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
		Boolean activo = p.Motivo_Baja__c == null && !(p.IsActiveParticipant == false && p.EffectiveToDate != null);
		// El grupo se decide por el valor y por la etiqueta del rol (el picklist estándar puede traer valores en inglés).
		List<String> llavesRol = new List<String>(rolesLista);
		llavesRol.addAll(rolesTexto);
		Date antiguedad = null;
		if (p.OriginalParticipantId != null && p.OriginalParticipant.InsurancePolicy.EffectiveDate != null) {
			antiguedad = p.OriginalParticipant.InsurancePolicy.EffectiveDate.date();
		}
		return new Map<String, Object>{
			'id' => p.Id, 'folio' => p.Name, 'nombre' => p.ParticipantName, 'certificado' => p.ParticipantCode,
			'roles' => rolesTexto, 'rolesTexto' => String.join(rolesTexto, ', '), 'grupo' => grupo(llavesRol, p),
			'parentesco' => p.RelationshipToInsured == null ? null
				: (parentescos.containsKey(p.RelationshipToInsured) ? parentescos.get(p.RelationshipToInsured) : p.RelationshipToInsured),
			'titularId' => p.RelatedInsPolicyParticipantId,
			'titularNombre' => p.RelatedInsPolicyParticipantId == null ? null : p.RelatedInsPolicyParticipant.ParticipantName,
			'contratante' => p.IsPolicyholder == true, 'activo' => activo, 'categoria' => p.Categoria__c,
			'fechaNacimiento' => p.FechaNacimiento__c, 'identificacion' => p.Identificacion__c,
			'motivoBaja' => p.Motivo_Baja__c == null ? null : motivos.get(p.Motivo_Baja__c),
			'porcentaje' => p.BeneficiarySharePercentage, 'menor' => p.IsMinorBeneficiary == true,
			'desde' => p.EffectiveFromDate != null ? p.EffectiveFromDate : (p.EffectiveDate == null ? null : p.EffectiveDate.date()),
			'hasta' => p.EffectiveToDate != null ? p.EffectiveToDate : (p.ExpirationDate == null ? null : p.ExpirationDate.date()),
			'prima' => p.StandardPremiumAmount,
			'vigenciaAnterior' => p.PriorParticipantId == null ? null : p.PriorParticipant.InsurancePolicy.Name,
			'polizaOriginal' => p.OriginalParticipantId == null ? null : p.OriginalParticipant.InsurancePolicy.Name,
			'aseguradoDesde' => antiguedad
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
				'PersonMailingStreet', 'PersonMailingCity', 'PersonMailingState', 'PersonMailingPostalCode', 'IsPersonAccount' }) {
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
				'fechaNacimiento' => valor(a, campos, 'PersonBirthdate'), 'domicilio' => domicilio
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
