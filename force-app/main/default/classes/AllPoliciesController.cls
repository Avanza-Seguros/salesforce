/**
 *   @name: AllPoliciesController
 *   @version: 1.0
 *   @creation date: 13/11/2026
 *   @author: Javier Torres - Volestra
 *   @description: Controlador de la pantalla «Todas las pólizas». Las vistas de lista y los
 *                 informes solo enseñan 2.000 filas y OFFSET no pasa de ahí, así que las
 *                 páginas se piden por cursor: el valor del campo de orden de la última fila
 *                 y su Id. Así se recorre la cartera entera sin tope.
 */
public with sharing class AllPoliciesController {
	private static final Integer DEFAULT_PAGE_SIZE = 200;
	private static final Integer MAX_PAGE_SIZE = 500;
	private static final String DEFAULT_SORT_FIELD = 'Name';
	private static final String SELECT_FIELDS =
		'Id, Name, Aseguradora__c, Aseguradora__r.Name, Ramo__c, NameInsuredId, ' +
		'NameInsured.Name, PremiumFrequency, EffectiveDate, ExpirationDate, ' +
		'PremiumAmount, Status, insuredSubject__c, CreatedDate';

	// Solo se ordena por campos de la propia póliza; el nombre del campo es lo único que
	// se escribe dentro de la consulta y siempre sale de esta lista.
	private static final Set<String> SORTABLE_FIELDS = new Set<String>{
		'Name',
		'Ramo__c',
		'PremiumFrequency',
		'EffectiveDate',
		'ExpirationDate',
		'PremiumAmount',
		'Status',
		'insuredSubject__c',
		'CreatedDate'
	};

	/**
	 * @description: Opción de un combo de la pantalla.
	 */
	public class Option {
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String value;

		public Option(String label, String value) {
			this.label = label;
			this.value = value;
		}
	}

	/**
	 * @description: Lo que necesitan los filtros y las columnas de lista de valores.
	 */
	public class FilterOptions {
		@AuraEnabled
		public List<Option> carriers = new List<Option>();
		@AuraEnabled
		public List<Option> statuses = new List<Option>();
		@AuraEnabled
		public Map<String, Map<String, String>> picklistLabels = new Map<String, Map<String, String>>();
	}

	/**
	 * @creation date: 13/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Devuelve la página siguiente a la fila indicada por el cursor, con el
	 *               orden y los filtros pedidos. Sin cursor devuelve la primera página.
	 *               Orden: campo pedido con los vacíos al final y, a igual valor, por Id.
	 * @param sortField: Campo de orden; si no está permitido se ordena por número de póliza.
	 * @param sortDirection: ASC o DESC; cualquier otro valor se toma como ASC.
	 * @param searchTerm: Texto a buscar en el número de póliza o en el nombre del asegurado.
	 * @param carrierId: Aseguradora por la que filtrar; vacío para todas.
	 * @param status: Estado por el que filtrar; vacío para todos.
	 * @param cursorValue: Valor del campo de orden de la última fila cargada (como texto).
	 * @param cursorId: Id de la última fila cargada; vacío para la primera página.
	 * @param pageSize: Filas por página: 200 por defecto, 500 como máximo.
	 * @return Pólizas de la página; menos que pageSize cuando ya no quedan más.
	 */
	@AuraEnabled(cacheable=false)
	public static List<InsurancePolicy> getPage(
		String sortField,
		String sortDirection,
		String searchTerm,
		Id carrierId,
		String status,
		String cursorValue,
		Id cursorId,
		Integer pageSize
	) {
		String field = normalizeSortField(sortField);
		Boolean descending = 'DESC'.equalsIgnoreCase(sortDirection);
		Integer size = normalizePageSize(pageSize);
		try {
			if (isPicklist(field)) {
				return picklistPage(
					field,
					descending,
					searchTerm,
					carrierId,
					status,
					cursorValue,
					cursorId,
					size
				);
			}
			return keysetPage(
				field,
				descending,
				searchTerm,
				carrierId,
				status,
				cursorValue,
				cursorId,
				size
			);
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			throw auraError('No se pudieron cargar las pólizas: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 13/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Cuenta las pólizas que cumplen los filtros, sin tope.
	 * @param searchTerm: Texto a buscar en el número de póliza o en el nombre del asegurado.
	 * @param carrierId: Aseguradora por la que filtrar; vacío para todas.
	 * @param status: Estado por el que filtrar; vacío para todos.
	 * @return Número de pólizas.
	 */
	@AuraEnabled(cacheable=false)
	public static Integer getTotal(
		String searchTerm,
		Id carrierId,
		String status
	) {
		Map<String, Object> binds = new Map<String, Object>();
		List<String> conditions = filterConditions(
			searchTerm,
			carrierId,
			status,
			binds
		);
		try {
			return Database.countQueryWithBinds(
				'SELECT COUNT() FROM InsurancePolicy' + whereClause(conditions),
				binds,
				AccessLevel.USER_MODE
			);
		} catch (Exception e) {
			throw auraError('No se pudo contar las pólizas: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 13/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Devuelve las aseguradoras que tienen pólizas (por nombre), los estados
	 *               posibles y las etiquetas de los campos de lista de valores que se ven en
	 *               la tabla.
	 * @return Opciones de los filtros.
	 */
	@AuraEnabled(cacheable=true)
	public static FilterOptions getFilterOptions() {
		FilterOptions options = new FilterOptions();
		try {
			Set<Id> carrierIds = new Set<Id>();
			for (
				AggregateResult row : (List<AggregateResult>) Database.queryWithBinds(
					'SELECT Aseguradora__c carrierId FROM InsurancePolicy ' +
					'WHERE Aseguradora__c != null GROUP BY Aseguradora__c',
					new Map<String, Object>(),
					AccessLevel.USER_MODE
				)
			) {
				carrierIds.add((Id) row.get('carrierId'));
			}
			if (!carrierIds.isEmpty()) {
				for (
					Aseguradora__c carrier : (List<Aseguradora__c>) Database.queryWithBinds(
						'SELECT Id, Name FROM Aseguradora__c WHERE Id IN :carrierIds ORDER BY Name',
						new Map<String, Object>{ 'carrierIds' => carrierIds },
						AccessLevel.USER_MODE
					)
				) {
					options.carriers.add(new Option(carrier.Name, carrier.Id));
				}
			}
		} catch (Exception e) {
			throw auraError(
				'No se pudieron cargar las aseguradoras: ' + e.getMessage()
			);
		}

		for (
			Schema.PicklistEntry entry : InsurancePolicy.Status.getDescribe()
				.getPicklistValues()
		) {
			if (entry.isActive()) {
				options.statuses.add(new Option(entry.getLabel(), entry.getValue()));
			}
		}
		for (
			String field : new List<String>{ 'Ramo__c', 'PremiumFrequency', 'Status' }
		) {
			options.picklistLabels.put(field, picklistLabels(field));
		}
		return options;
	}

	/** Página de un campo de texto, fecha o número: el cursor va en la propia consulta. */
	private static List<InsurancePolicy> keysetPage(
		String field,
		Boolean descending,
		String searchTerm,
		Id carrierId,
		String status,
		String cursorValue,
		Id cursorId,
		Integer size
	) {
		Map<String, Object> binds = new Map<String, Object>();
		List<String> conditions = filterConditions(
			searchTerm,
			carrierId,
			status,
			binds
		);
		if (cursorId != null) {
			binds.put('cursorId', cursorId);
			Object value = convertCursor(field, cursorValue);
			if (value == null) {
				// La última fila ya estaba entre los vacíos, que van al final.
				conditions.add('(' + field + ' = null AND Id > :cursorId)');
			} else {
				binds.put('cursorValue', value);
				conditions.add(
					'(' +
						field +
						(descending ? ' < ' : ' > ') +
						':cursorValue OR (' +
						field +
						' = :cursorValue AND Id > :cursorId) OR ' +
						field +
						' = null)'
				);
			}
		}
		binds.put('pageSize', size);
		String soql =
			'SELECT ' +
			SELECT_FIELDS +
			' FROM InsurancePolicy' +
			whereClause(conditions) +
			' ORDER BY ' +
			field +
			(descending ? ' DESC' : ' ASC') +
			' NULLS LAST, Id ASC LIMIT :pageSize';
		return (List<InsurancePolicy>) Database.queryWithBinds(
			soql,
			binds,
			AccessLevel.USER_MODE
		);
	}

	/**
	 * Página de un campo de lista de valores. SOQL ordena estos campos por el orden de
	 * definición de los valores y no por texto, así que «mayor que» no casa con ese orden:
	 * se agrupan los valores presentes, se ordenan aquí por su etiqueta y se lee grupo a
	 * grupo por Id hasta llenar la página.
	 */
	private static List<InsurancePolicy> picklistPage(
		String field,
		Boolean descending,
		String searchTerm,
		Id carrierId,
		String status,
		String cursorValue,
		Id cursorId,
		Integer size
	) {
		Map<String, String> labels = picklistLabels(field);
		List<String> groups = picklistGroups(
			field,
			descending,
			labels,
			searchTerm,
			carrierId,
			status
		);

		Integer start = 0;
		if (cursorId != null) {
			String cursor = String.isBlank(cursorValue) ? null : cursorValue;
			start = groups.size();
			for (Integer i = 0; i < groups.size(); i++) {
				if (
					groups[i] == cursor ||
					comesBefore(cursor, groups[i], descending, labels)
				) {
					start = i;
					break;
				}
			}
		}

		List<InsurancePolicy> page = new List<InsurancePolicy>();
		for (Integer i = start; i < groups.size() && page.size() < size; i++) {
			String groupValue = groups[i];
			Map<String, Object> binds = new Map<String, Object>();
			List<String> conditions = filterConditions(
				searchTerm,
				carrierId,
				status,
				binds
			);
			binds.put('groupValue', groupValue);
			conditions.add(field + ' = :groupValue');
			String cursor = String.isBlank(cursorValue) ? null : cursorValue;
			if (cursorId != null && groupValue == cursor) {
				binds.put('cursorId', cursorId);
				conditions.add('Id > :cursorId');
			}
			binds.put('pageSize', size - page.size());
			page.addAll(
				(List<InsurancePolicy>) Database.queryWithBinds(
					'SELECT ' +
						SELECT_FIELDS +
						' FROM InsurancePolicy' +
						whereClause(conditions) +
						' ORDER BY Id ASC LIMIT :pageSize',
					binds,
					AccessLevel.USER_MODE
				)
			);
		}
		return page;
	}

	/** Valores presentes con los filtros, ordenados por etiqueta y con el vacío al final. */
	private static List<String> picklistGroups(
		String field,
		Boolean descending,
		Map<String, String> labels,
		String searchTerm,
		Id carrierId,
		String status
	) {
		Map<String, Object> binds = new Map<String, Object>();
		List<String> conditions = filterConditions(
			searchTerm,
			carrierId,
			status,
			binds
		);
		Map<String, String> valueBySortKey = new Map<String, String>();
		Boolean hasEmpty = false;
		for (
			AggregateResult row : (List<AggregateResult>) Database.queryWithBinds(
				'SELECT ' +
					field +
					' groupValue FROM InsurancePolicy' +
					whereClause(conditions) +
					' GROUP BY ' +
					field,
				binds,
				AccessLevel.USER_MODE
			)
		) {
			String value = (String) row.get('groupValue');
			if (String.isBlank(value)) {
				hasEmpty = true;
			} else {
				valueBySortKey.put(sortKey(value, labels), value);
			}
		}
		List<String> keys = new List<String>(valueBySortKey.keySet());
		keys.sort();
		List<String> groups = new List<String>();
		for (Integer i = 0; i < keys.size(); i++) {
			groups.add(
				valueBySortKey.get(keys[descending ? keys.size() - 1 - i : i])
			);
		}
		if (hasEmpty) {
			groups.add(null);
		}
		return groups;
	}

	/** Si el valor del cursor va antes que el grupo en el orden de la tabla. */
	private static Boolean comesBefore(
		String cursor,
		String groupValue,
		Boolean descending,
		Map<String, String> labels
	) {
		if (cursor == null) {
			return false;
		}
		if (groupValue == null) {
			return true;
		}
		Integer comparison = sortKey(cursor, labels)
			.compareTo(sortKey(groupValue, labels));
		return descending ? comparison > 0 : comparison < 0;
	}

	private static String sortKey(String value, Map<String, String> labels) {
		String label = labels.containsKey(value) ? labels.get(value) : value;
		return label.toLowerCase() + '|' + value;
	}

	private static Map<String, String> picklistLabels(String field) {
		Map<String, String> labels = new Map<String, String>();
		for (
			Schema.PicklistEntry entry : fieldDescribe(field).getPicklistValues()
		) {
			labels.put(entry.getValue(), entry.getLabel());
		}
		return labels;
	}

	private static List<String> filterConditions(
		String searchTerm,
		Id carrierId,
		String status,
		Map<String, Object> binds
	) {
		List<String> conditions = new List<String>();
		if (String.isNotBlank(searchTerm)) {
			binds.put('searchPattern', '%' + escapeLike(searchTerm.trim()) + '%');
			conditions.add(
				'(Name LIKE :searchPattern OR NameInsured.Name LIKE :searchPattern)'
			);
		}
		if (carrierId != null) {
			binds.put('carrierId', carrierId);
			conditions.add('Aseguradora__c = :carrierId');
		}
		if (String.isNotBlank(status)) {
			binds.put('status', status);
			conditions.add('Status = :status');
		}
		return conditions;
	}

	private static String whereClause(List<String> conditions) {
		return conditions.isEmpty()
			? ''
			: ' WHERE ' + String.join(conditions, ' AND ');
	}

	/** Los comodines de LIKE escritos por el usuario se buscan como texto literal. */
	private static String escapeLike(String value) {
		return value.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
	}

	private static String normalizeSortField(String sortField) {
		for (String allowed : SORTABLE_FIELDS) {
			if (allowed.equalsIgnoreCase(sortField)) {
				return allowed;
			}
		}
		return DEFAULT_SORT_FIELD;
	}

	private static Integer normalizePageSize(Integer pageSize) {
		if (pageSize == null || pageSize <= 0) {
			return DEFAULT_PAGE_SIZE;
		}
		return Math.min(pageSize, MAX_PAGE_SIZE);
	}

	private static Schema.DescribeFieldResult fieldDescribe(String field) {
		return Schema.SObjectType.InsurancePolicy.fields.getMap()
			.get(field)
			.getDescribe();
	}

	private static Boolean isPicklist(String field) {
		return fieldDescribe(field).getType() == Schema.DisplayType.PICKLIST;
	}

	/** Pasa el valor del cursor, que llega como texto, al tipo del campo de orden. */
	private static Object convertCursor(String field, String cursorValue) {
		if (String.isBlank(cursorValue)) {
			return null;
		}
		try {
			switch on fieldDescribe(field).getType() {
				when DATETIME {
					return (Datetime) JSON.deserialize(
						JSON.serialize(cursorValue),
						Datetime.class
					);
				}
				when DATE {
					return Date.valueOf(cursorValue);
				}
				when CURRENCY, DOUBLE, PERCENT, INTEGER, LONG {
					return Decimal.valueOf(cursorValue);
				}
				when else {
					return cursorValue;
				}
			}
		} catch (Exception e) {
			throw auraError(
				'El valor «' + cursorValue + '» no sirve para continuar la lista.'
			);
		}
	}

	private static AuraHandledException auraError(String message) {
		AuraHandledException error = new AuraHandledException(message);
		error.setMessage(message);
		return error;
	}
}
