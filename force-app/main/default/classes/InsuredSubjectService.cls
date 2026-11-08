/**
 *   @name: InsuredSubjectService
 *   @version: 1.0
 *   @creation date: 08/11/2026
 *   @author: Javier Torres - Volestra
 *   @description: Mantiene el campo «Asegurado o bien» (insuredSubject__c) de la póliza, que
 *                 dice qué asegura para verlo en las vistas sin entrar en ella. Un campo
 *                 fórmula no puede leer los registros hijos, por eso se recalcula aquí cada
 *                 vez que cambian los bienes (InsurancePolicyAsset y los incisos de flotilla)
 *                 o los asegurados (InsurancePolicyParticipant), venga el cambio de donde
 *                 venga: la carga, el canal de pólizas o las pantallas de altas y bajas.
 *                 Reglas:
 *                 - Un bien: el bien, con la serie del vehículo si no viene ya en el texto.
 *                 - Varios bienes vivos: «Flotilla · N incisos».
 *                 - Personas con dos o más certificados distintos: «Colectiva · N certificados».
 *                 - Personas sin certificados: los nombres, con el titular primero.
 *                 - Los dados de baja no cuentan. La casilla de activo de un bien o de un
 *                   asegurado se apaga también cuando vence o se cancela la póliza, así que
 *                   solo indica una baja mientras la póliza sigue viva.
 */
public with sharing class InsuredSubjectService {
	public static final Integer MAX_LENGTH = 255;
	private static final String SEPARATOR = ' · ';
	private static final Set<String> LIVE_POLICY_STATUSES = new Set<String>{
		'Inicial',
		'Vigente'
	};
	// Roles de quien está asegurado. Beneficiarios, conductores, pagadores y contratantes
	// no son lo que la póliza asegura.
	private static final Set<String> INSURED_ROLES = new Set<String>{
		'asegurado',
		'insured',
		'miembro',
		'miembro familiar',
		'member'
	};
	// Relaciones con las que se identifica al titular; los dependientes traen su parentesco.
	private static final Set<String> HOLDER_RELATIONSHIPS = new Set<String>{
		'',
		'titular',
		'self',
		'asegurado'
	};
	// Prefijo con el que las pantallas de ubicaciones guardan el número de inciso en el nombre.
	private static final Pattern INCISO_PREFIX = Pattern.compile(
		'^Inciso\\s+\\d+\\s+-\\s+'
	);

	// Fuerza el fallo del guardado de estas pólizas para probar que el fallo queda
	// registrado y no detiene a las demás.
	@TestVisible
	private static Set<Id> failForTest = new Set<Id>();

	/**
	 * @creation date: 08/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Recalcula las pólizas de los bienes que cambiaron. Si un bien pasó de una
	 *               póliza a otra, se recalculan las dos.
	 * @param records: Registros nuevos del trigger, o los borrados.
	 * @param oldMap: Valores anteriores; nulo al insertar.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	public static void onAssetsChanged(
		List<InsurancePolicyAsset> records,
		Map<Id, InsurancePolicyAsset> oldMap
	) {
		Set<Id> policyIds = new Set<Id>();
		for (InsurancePolicyAsset asset : records) {
			policyIds.add(asset.InsurancePolicyId);
			InsurancePolicyAsset previous = oldMap == null
				? null
				: oldMap.get(asset.Id);
			if (previous != null) {
				policyIds.add(previous.InsurancePolicyId);
			}
		}
		recalculate(policyIds);
	}

	/**
	 * @creation date: 08/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Recalcula las pólizas de los asegurados que cambiaron.
	 * @param records: Registros nuevos del trigger, o los borrados.
	 * @param oldMap: Valores anteriores; nulo al insertar.
	 * @return:
	 * @exception:
	 * @throws:
	 */
	public static void onParticipantsChanged(
		List<InsurancePolicyParticipant> records,
		Map<Id, InsurancePolicyParticipant> oldMap
	) {
		Set<Id> policyIds = new Set<Id>();
		for (InsurancePolicyParticipant participant : records) {
			policyIds.add(participant.InsurancePolicyId);
			InsurancePolicyParticipant previous = oldMap == null
				? null
				: oldMap.get(participant.Id);
			if (previous != null) {
				policyIds.add(previous.InsurancePolicyId);
			}
		}
		recalculate(policyIds);
	}

	/**
	 * @creation date: 08/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Calcula el campo de las pólizas indicadas y guarda solo las que cambian.
	 *               Una póliza que no se puede guardar queda registrada y no detiene a las demás.
	 *               Lo usan los triggers y el relleno de las pólizas ya cargadas.
	 * @param policyIds: Pólizas a recalcular.
	 * @return: Integer Cantidad de pólizas cuyo campo cambió y se guardó.
	 * @exception:
	 * @throws:
	 */
	public static Integer recalculate(Set<Id> policyIds) {
		Set<Id> ids = new Set<Id>(policyIds);
		ids.remove(null);
		if (ids.isEmpty()) {
			return 0;
		}

		Map<Id, InsurancePolicy> policies = new Map<Id, InsurancePolicy>(
			[
				SELECT Id, Status, ExpirationDate, insuredSubject__c
				FROM InsurancePolicy
				WHERE Id IN :ids
			]
		);
		Map<Id, String> subjects = describe(policies.values());

		List<InsurancePolicy> toUpdate = new List<InsurancePolicy>();
		for (InsurancePolicy policy : policies.values()) {
			String subject = subjects.get(policy.Id);
			if (subject == policy.insuredSubject__c) {
				continue;
			}
			InsurancePolicy changed = new InsurancePolicy(
				Id = policy.Id,
				insuredSubject__c = subject
			);
			if (Test.isRunningTest() && failForTest.contains(policy.Id)) {
				changed.Name = '';
			}
			toUpdate.add(changed);
		}
		return save(toUpdate);
	}

	/**
	 * @creation date: 08/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Arma el texto de cada póliza a partir de sus bienes, incisos y asegurados.
	 * @param policies: Pólizas con Status y ExpirationDate.
	 * @return: Map<Id, String> Texto por póliza; nulo si no tiene bien ni asegurado.
	 * @exception:
	 * @throws:
	 */
	@TestVisible
	private static Map<Id, String> describe(List<InsurancePolicy> policies) {
		Map<Id, InsurancePolicy> byId = new Map<Id, InsurancePolicy>(policies);
		Map<Id, List<String>> assetsByPolicy = new Map<Id, List<String>>();
		Map<Id, List<String>> incisosByPolicy = new Map<Id, List<String>>();
		Map<Id, List<InsurancePolicyParticipant>> peopleByPolicy = new Map<Id, List<InsurancePolicyParticipant>>();

		for (InsurancePolicyAsset asset : [
			SELECT
				InsurancePolicyId,
				AssetName,
				IsActive,
				EffectiveToDate,
				Fecha_Baja__c,
				CustomerProperty.Vin
			FROM InsurancePolicyAsset
			WHERE InsurancePolicyId IN :byId.keySet()
			ORDER BY AssetName
		]) {
			InsurancePolicy policy = byId.get(asset.InsurancePolicyId);
			if (
				asset.Fecha_Baja__c != null ||
				isDroppedOut(asset.IsActive, asset.EffectiveToDate, policy)
			) {
				continue;
			}
			addUnique(
				assetsByPolicy,
				asset.InsurancePolicyId,
				withSerial(
					stripIncisoPrefix(asset.AssetName),
					asset.CustomerProperty?.Vin
				)
			);
		}

		for (Inciso_Flotilla__c inciso : [
			SELECT Poliza__c, Descripcion__c, Serie__c
			FROM Inciso_Flotilla__c
			WHERE Poliza__c IN :byId.keySet() AND Fecha_Baja__c = NULL
			ORDER BY Numero_Inciso__c
		]) {
			addUnique(
				incisosByPolicy,
				inciso.Poliza__c,
				withSerial(inciso.Descripcion__c, inciso.Serie__c)
			);
		}

		for (InsurancePolicyParticipant participant : [
			SELECT
				InsurancePolicyId,
				ParticipantName,
				PrimaryParticipantAccount.Name,
				PrimaryParticipantContact.Name,
				Role,
				RelationshipToInsured,
				ParticipantCode,
				IsActiveParticipant,
				EffectiveToDate,
				Motivo_Baja__c
			FROM InsurancePolicyParticipant
			WHERE InsurancePolicyId IN :byId.keySet()
			ORDER BY ParticipantName
		]) {
			InsurancePolicy policy = byId.get(participant.InsurancePolicyId);
			if (
				!isInsuredRole(participant.Role) ||
				participant.Motivo_Baja__c != null ||
				isDroppedOut(
					participant.IsActiveParticipant,
					participant.EffectiveToDate,
					policy
				)
			) {
				continue;
			}
			if (!peopleByPolicy.containsKey(participant.InsurancePolicyId)) {
				peopleByPolicy.put(
					participant.InsurancePolicyId,
					new List<InsurancePolicyParticipant>()
				);
			}
			peopleByPolicy.get(participant.InsurancePolicyId).add(participant);
		}

		Map<Id, String> result = new Map<Id, String>();
		for (Id policyId : byId.keySet()) {
			result.put(
				policyId,
				subjectOf(
					assetsByPolicy.get(policyId),
					incisosByPolicy.get(policyId),
					peopleByPolicy.get(policyId)
				)
			);
		}
		return result;
	}

	private static String subjectOf(
		List<String> assets,
		List<String> incisos,
		List<InsurancePolicyParticipant> people
	) {
		Integer assetCount = assets == null ? 0 : assets.size();
		Integer incisoCount = incisos == null ? 0 : incisos.size();
		Integer items = Math.max(assetCount, incisoCount);

		if (items > 1) {
			return 'Flotilla' + SEPARATOR + items + ' incisos';
		}
		if (items == 1) {
			return (assetCount == 1 ? assets[0] : incisos[0]).left(MAX_LENGTH);
		}
		return people == null ? null : describePeople(people);
	}

	private static String describePeople(
		List<InsurancePolicyParticipant> people
	) {
		Set<String> certificates = new Set<String>();
		Set<String> seen = new Set<String>();
		String holder;
		List<String> others = new List<String>();

		for (InsurancePolicyParticipant participant : people) {
			if (String.isNotBlank(participant.ParticipantCode)) {
				certificates.add(participant.ParticipantCode.trim());
			}
			String name = nameOf(participant);
			if (String.isBlank(name) || !seen.add(name.toLowerCase())) {
				continue;
			}
			if (holder == null && isHolder(participant.RelationshipToInsured)) {
				holder = name;
			} else {
				others.add(name);
			}
		}

		if (certificates.size() > 1) {
			return 'Colectiva' + SEPARATOR + certificates.size() + ' certificados';
		}

		List<String> names = new List<String>();
		if (holder != null) {
			names.add(others.isEmpty() ? holder : holder + ' (titular)');
		}
		names.addAll(others);
		return names.isEmpty() ? null : joinWithinLimit(names);
	}

	/**
	 * Une los nombres separados por coma sin pasar de la longitud del campo. Los que no caben
	 * se resumen al final como «y N más».
	 */
	@TestVisible
	private static String joinWithinLimit(List<String> names) {
		String text = '';
		for (Integer i = 0; i < names.size(); i++) {
			String next = (i == 0 ? '' : ', ') + names[i];
			Integer left = names.size() - i - 1;
			String tail = left == 0 ? '' : ' y ' + left + ' más';
			if ((text + next + tail).length() <= MAX_LENGTH) {
				text += next;
				continue;
			}
			String rest = ' y ' + (names.size() - i) + ' más';
			return i == 0
				? names[0].left(MAX_LENGTH)
				: (text + rest).left(MAX_LENGTH);
		}
		return text;
	}

	/**
	 * Un bien o un asegurado está fuera de la póliza si terminó antes que ella (una baja
	 * fija la fecha de fin del día de la baja) o si su casilla de activo está apagada
	 * mientras la póliza sigue viva. Con la póliza vencida o cancelada, la casilla apagada
	 * no dice nada: se apaga con la póliza.
	 */
	private static Boolean isDroppedOut(
		Boolean isActive,
		Date endDate,
		InsurancePolicy policy
	) {
		if (endDate != null && policy?.ExpirationDate != null) {
			// Un día de holgura por la hora con la que se guarda el fin de la póliza.
			if (endDate < policy.ExpirationDate.date().addDays(-1)) {
				return true;
			}
		}
		return isActive == false &&
			policy != null &&
			LIVE_POLICY_STATUSES.contains(policy.Status);
	}

	private static Boolean isInsuredRole(String role) {
		return String.isBlank(role) ||
			INSURED_ROLES.contains(role.trim().toLowerCase());
	}

	private static Boolean isHolder(String relationship) {
		return HOLDER_RELATIONSHIPS.contains(
			relationship == null ? '' : relationship.trim().toLowerCase()
		);
	}

	private static String nameOf(InsurancePolicyParticipant participant) {
		String name = participant.ParticipantName;
		if (String.isBlank(name)) {
			name = participant.PrimaryParticipantAccount?.Name;
		}
		if (String.isBlank(name)) {
			name = participant.PrimaryParticipantContact?.Name;
		}
		return name == null ? null : name.normalizeSpace();
	}

	private static String stripIncisoPrefix(String name) {
		return name == null
			? null
			: INCISO_PREFIX.matcher(name.trim()).replaceFirst('');
	}

	private static String withSerial(String description, String serial) {
		String text = description == null ? '' : description.normalizeSpace();
		String vin = serial == null ? '' : serial.trim();
		if (
			String.isNotBlank(vin) && !text.toUpperCase().contains(vin.toUpperCase())
		) {
			text = String.isBlank(text)
				? 'Serie ' + vin
				: text + SEPARATOR + 'serie ' + vin;
		}
		return String.isBlank(text) ? null : text;
	}

	private static void addUnique(
		Map<Id, List<String>> target,
		Id policyId,
		String text
	) {
		if (String.isBlank(text)) {
			text = '(sin descripción)';
		}
		if (!target.containsKey(policyId)) {
			target.put(policyId, new List<String>());
		}
		List<String> texts = target.get(policyId);
		if (!texts.contains(text)) {
			texts.add(text);
		}
	}

	private static Integer save(List<InsurancePolicy> toUpdate) {
		if (toUpdate.isEmpty()) {
			return 0;
		}
		Integer saved = 0;
		List<Database.SaveResult> results = Database.update(toUpdate, false);
		for (Integer i = 0; i < results.size(); i++) {
			if (results[i].isSuccess()) {
				saved++;
				continue;
			}
			List<String> errors = new List<String>();
			for (Database.Error error : results[i].getErrors()) {
				errors.add(error.getMessage());
			}
			CobranzaLog.error(
					CobranzaLog.STAGE_DATOS_POLIZA,
					CobranzaLog.EVENT_INSURED_SUBJECT_FAILED,
					'No se pudo guardar el campo Asegurado o bien de la poliza. Motivo: ' +
					String.join(errors, '; ')
				)
				.onRecord(toUpdate[i].Id);
		}
		AppLogger.flush();
		return saved;
	}
}
