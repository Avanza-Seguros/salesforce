/**
 *   @name: AllPoliciesControllerTest
 *   @version: 1.0
 *   @creation date: 13/11/2026
 *   @author: Javier Torres - Volestra
 *   @description: Valida que la pantalla «Todas las pólizas» recorra la cartera página a
 *                 página sin repetir ni saltar filas, en los dos sentidos, con valores
 *                 vacíos en el campo de orden, con la búsqueda y los filtros, y que el
 *                 total y las opciones de los filtros salgan bien.
 */
@IsTest
private class AllPoliciesControllerTest {
	private static final Integer POLICY_COUNT = 13;
	private static final Integer PAGE_SIZE = 5;
	private static final String SEARCHABLE_INSURED = 'Juana Buscable Prueba';
	private static final List<String> RAMOS = new List<String>{
		'Automoviles',
		'GMM',
		'Danos'
	};

	@TestSetup
	static void setupData() {
		CollectionsTestDataFactory.createInsuredAccount();
		Account searchable = new Account(
			Name = SEARCHABLE_INSURED,
			AnnualRevenue = 1000000
		);
		insert searchable;
		Aseguradora__c first = new Aseguradora__c(Name = 'Zeta Seguros Prueba');
		Aseguradora__c second = new Aseguradora__c(Name = 'Alfa Seguros Prueba');
		insert new List<Aseguradora__c>{ first, second };

		Id defaultInsured = CollectionsTestDataFactory.getDefaultInsuredAccountId();
		List<InsurancePolicy> policies = new List<InsurancePolicy>();
		for (Integer i = 1; i <= POLICY_COUNT; i++) {
			// Tres pólizas operativas y el resto vencidas; varios valores repetidos y
			// vacíos para que el orden tenga que desempatar por Id.
			InsurancePolicy policy = CollectionsTestDataFactory.buildCompletePolicy(
				i <= 3 ? searchable.Id : defaultInsured,
				i <= 3 ? 'Inicial' : 'Vencido',
				'Mensual',
				Math.mod(i, 2) == 0 ? 1000 : 500 + i,
				Date.newInstance(2026, 1, 15)
			);
			policy.Name = 'APT-' + String.valueOf(1000 + i);
			policy.Aseguradora__c = Math.mod(i, 2) == 0 ? first.Id : second.Id;
			policy.Ramo__c = Math.mod(i, 4) == 0 ? null : RAMOS[Math.mod(i, 3)];
			policy.insuredSubject__c = Math.mod(i, 3) == 0
				? null
				: 'Bien ' + String.valueOf(Math.mod(i, 4));
			policy.EffectiveDate = Math.mod(i, 5) == 0
				? null
				: Datetime.newInstanceGmt(2026, 1 + Math.mod(i, 3), 15);
			policies.add(policy);
		}
		insert policies;
	}

	/** Pide páginas hasta que llega una incompleta, como hace la pantalla. */
	private static List<InsurancePolicy> readAll(
		String sortField,
		String direction,
		String searchTerm,
		Id carrierId,
		String status
	) {
		List<InsurancePolicy> rows = new List<InsurancePolicy>();
		String cursorValue = null;
		Id cursorId = null;
		String field = sortField;
		for (Integer guard = 0; guard < 20; guard++) {
			List<InsurancePolicy> page = AllPoliciesController.getPage(
				sortField,
				direction,
				searchTerm,
				carrierId,
				status,
				cursorValue,
				cursorId,
				PAGE_SIZE
			);
			rows.addAll(page);
			if (page.size() < PAGE_SIZE) {
				break;
			}
			InsurancePolicy last = page[page.size() - 1];
			Object value = last.get(field);
			cursorValue = value == null ? null : cursorText(value);
			cursorId = last.Id;
		}
		return rows;
	}

	/** El cursor viaja como texto, igual que lo envía el componente. */
	private static String cursorText(Object value) {
		if (value instanceof Datetime) {
			return JSON.serialize(value).replace('"', '');
		}
		return String.valueOf(value);
	}

	private static List<Id> ids(List<InsurancePolicy> rows) {
		List<Id> result = new List<Id>();
		for (InsurancePolicy row : rows) {
			result.add(row.Id);
		}
		return result;
	}

	private static void assertNoRepeatsNoGaps(
		List<InsurancePolicy> rows,
		Integer expected
	) {
		Assert.areEqual(expected, rows.size(), 'Lee todas las filas');
		Assert.areEqual(
			expected,
			new Set<Id>(ids(rows)).size(),
			'No repite ninguna fila'
		);
	}

	/** Orden esperado de un campo que no es lista de valores, tal como lo da SOQL. */
	private static List<Id> expectedOrder(String field, String direction) {
		List<Id> result = new List<Id>();
		for (
			InsurancePolicy policy : Database.query(
				'SELECT Id FROM InsurancePolicy ORDER BY ' +
					field +
					' ' +
					direction +
					' NULLS LAST, Id ASC'
			)
		) {
			result.add(policy.Id);
		}
		return result;
	}

	@IsTest
	static void walksTextFieldBothWaysWithEmptyValues() {
		Test.startTest();
		List<InsurancePolicy> ascending = readAll(
			'insuredSubject__c',
			'ASC',
			null,
			null,
			null
		);
		List<InsurancePolicy> descending = readAll(
			'insuredSubject__c',
			'DESC',
			null,
			null,
			null
		);
		Test.stopTest();

		assertNoRepeatsNoGaps(ascending, POLICY_COUNT);
		assertNoRepeatsNoGaps(descending, POLICY_COUNT);
		Assert.areEqual(
			expectedOrder('insuredSubject__c', 'ASC'),
			ids(ascending),
			'Sigue el orden ascendente con los vacíos al final'
		);
		Assert.areEqual(
			expectedOrder('insuredSubject__c', 'DESC'),
			ids(descending),
			'Sigue el orden descendente con los vacíos al final'
		);
		Assert.isNull(
			ascending[POLICY_COUNT - 1].insuredSubject__c,
			'Los vacíos van al final'
		);
		Assert.isNotNull(ascending[0].Aseguradora__r, 'Trae la aseguradora');
		Assert.isNotNull(ascending[0].NameInsured, 'Trae el asegurado');
	}

	@IsTest
	static void walksDatetimeNumberAndNameFields() {
		Test.startTest();
		List<InsurancePolicy> byDate = readAll(
			'EffectiveDate',
			'DESC',
			null,
			null,
			null
		);
		List<InsurancePolicy> byAmount = readAll(
			'PremiumAmount',
			'ASC',
			null,
			null,
			null
		);
		List<InsurancePolicy> byName = readAll('Name', 'DESC', null, null, null);
		List<InsurancePolicy> byCreated = readAll(
			'CreatedDate',
			'ASC',
			null,
			null,
			null
		);
		Test.stopTest();

		Assert.areEqual(expectedOrder('EffectiveDate', 'DESC'), ids(byDate));
		Assert.areEqual(expectedOrder('PremiumAmount', 'ASC'), ids(byAmount));
		Assert.areEqual(expectedOrder('Name', 'DESC'), ids(byName));
		Assert.areEqual(expectedOrder('CreatedDate', 'ASC'), ids(byCreated));
		assertNoRepeatsNoGaps(byDate, POLICY_COUNT);
	}

	@IsTest
	static void walksPicklistByLabelWithEmptyValuesLast() {
		Test.startTest();
		List<InsurancePolicy> ascending = readAll(
			'Ramo__c',
			'ASC',
			null,
			null,
			null
		);
		List<InsurancePolicy> descending = readAll(
			'Ramo__c',
			'DESC',
			null,
			null,
			null
		);
		Test.stopTest();

		assertNoRepeatsNoGaps(ascending, POLICY_COUNT);
		assertNoRepeatsNoGaps(descending, POLICY_COUNT);
		assertGroupedInOrder(ascending, false);
		assertGroupedInOrder(descending, true);
	}

	/** Cada valor sale junto, en orden de etiqueta, y los vacíos al final. */
	private static void assertGroupedInOrder(
		List<InsurancePolicy> rows,
		Boolean descending
	) {
		Map<String, String> labels = new Map<String, String>();
		for (
			Schema.PicklistEntry entry : InsurancePolicy.Ramo__c.getDescribe()
				.getPicklistValues()
		) {
			labels.put(entry.getValue(), entry.getLabel().toLowerCase());
		}
		Boolean inEmpty = false;
		String previous = null;
		for (InsurancePolicy row : rows) {
			if (row.Ramo__c == null) {
				inEmpty = true;
				continue;
			}
			Assert.isFalse(inEmpty, 'Ningún valor después de los vacíos');
			String current = labels.get(row.Ramo__c);
			if (previous != null) {
				Integer comparison = current.compareTo(previous);
				Assert.isTrue(
					descending ? comparison <= 0 : comparison >= 0,
					'Ordena por la etiqueta del valor'
				);
			}
			previous = current;
		}
		Assert.isTrue(inEmpty, 'Incluye las pólizas sin ramo');
	}

	@IsTest
	static void appliesSearchAndFiltersToPagesAndTotal() {
		Aseguradora__c first = [
			SELECT Id
			FROM Aseguradora__c
			WHERE Name = 'Zeta Seguros Prueba'
		];

		Test.startTest();
		List<InsurancePolicy> byInsured = readAll(
			'Status',
			'ASC',
			'Buscable',
			null,
			null
		);
		List<InsurancePolicy> byNumber = readAll(
			'Name',
			'ASC',
			'APT-1012',
			null,
			null
		);
		List<InsurancePolicy> byCarrier = readAll(
			'Name',
			'ASC',
			null,
			first.Id,
			null
		);
		List<InsurancePolicy> byStatus = readAll(
			'Status',
			'DESC',
			null,
			null,
			'Vencido'
		);
		List<InsurancePolicy> wildcard = readAll('Name', 'ASC', '%', null, null);
		Integer total = AllPoliciesController.getTotal(null, null, null);
		Integer filteredTotal = AllPoliciesController.getTotal(
			'APT',
			first.Id,
			'Vencido'
		);
		Test.stopTest();

		Assert.areEqual(3, byInsured.size(), 'Busca por nombre del asegurado');
		Assert.areEqual(1, byNumber.size(), 'Busca por número de póliza');
		Assert.areEqual('APT-1012', byNumber[0].Name);
		Assert.areEqual(6, byCarrier.size(), 'Filtra por aseguradora');
		for (InsurancePolicy policy : byCarrier) {
			Assert.areEqual(first.Id, policy.Aseguradora__c);
		}
		assertNoRepeatsNoGaps(byStatus, POLICY_COUNT - 3);
		Assert.areEqual(0, wildcard.size(), 'El % se busca como texto');
		Assert.areEqual(POLICY_COUNT, total);
		Assert.areEqual(5, filteredTotal, 'Los pares de 4 a 12 son de Zeta');
	}

	@IsTest
	static void unknownSortFieldFallsBackToPolicyNumber() {
		Test.startTest();
		List<InsurancePolicy> rows = AllPoliciesController.getPage(
			'Id; DELETE',
			'sideways',
			null,
			null,
			null,
			null,
			null,
			null
		);
		Test.stopTest();

		Assert.areEqual(POLICY_COUNT, rows.size(), 'Página por defecto de 200');
		Assert.areEqual(
			expectedOrder('Name', 'ASC'),
			ids(rows),
			'Ordena por número de póliza ascendente'
		);
	}

	@IsTest
	static void rejectsCursorThatDoesNotMatchTheField() {
		InsurancePolicy somePolicy = [SELECT Id FROM InsurancePolicy LIMIT 1];
		Boolean failed = false;
		Test.startTest();
		try {
			AllPoliciesController.getPage(
				'PremiumAmount',
				'ASC',
				null,
				null,
				null,
				'no es un número',
				somePolicy.Id,
				5
			);
		} catch (AuraHandledException e) {
			failed = e.getMessage().contains('no sirve para continuar');
		}
		Test.stopTest();

		Assert.isTrue(failed, 'Un cursor inválido da un mensaje legible');
	}

	@IsTest
	static void filterOptionsListCarriersStatusesAndLabels() {
		Test.startTest();
		AllPoliciesController.FilterOptions options = AllPoliciesController.getFilterOptions();
		Test.stopTest();

		Assert.areEqual(2, options.carriers.size(), 'Solo las que tienen pólizas');
		Assert.areEqual(
			'Alfa Seguros Prueba',
			options.carriers[0].label,
			'Ordenadas por nombre'
		);
		Assert.isFalse(options.statuses.isEmpty(), 'Trae los estados');
		Assert.isTrue(options.picklistLabels.containsKey('Ramo__c'));
		Assert.isTrue(options.picklistLabels.get('Status').containsKey('Vencido'));
	}
}
