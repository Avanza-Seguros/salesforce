/**
 *   @name: PolicyTermsController
 *   @version: 1.0
 *   @creation date: 02/11/2026
 *   @author: Javier Torres - Volestra
 *   @description: Controlador de la pestaña Vigencias de la página de InsurancePolicy.
 *                 Cada vigencia es una póliza propia enlazada con la anterior por
 *                 PriorPolicyId; la lista relacionada estándar solo enseña un nivel, así
 *                 que la cadena se recorre aquí en los dos sentidos.
 */
public with sharing class PolicyTermsController {
	// Las cadenas reales son de pocas vigencias; el tope evita un bucle si un enlace
	// quedara circular por un error de carga.
	private static final Integer MAX_LEVELS = 30;
	private static final Set<String> CLOSED_STATUSES = new Set<String>{
		'Cancelado',
		'Condonado'
	};

	/**
	 * @description: Una vigencia tal como la pinta el componente.
	 */
	public class Term {
		@AuraEnabled
		public Id policyId;
		@AuraEnabled
		public String policyNumber;
		@AuraEnabled
		public String period;
		@AuraEnabled
		public Datetime effectiveDate;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public Decimal premium;
		@AuraEnabled
		public Decimal paid = 0;
		@AuraEnabled
		public Decimal outstanding = 0;
		@AuraEnabled
		public Integer documentCount = 0;
		@AuraEnabled
		public Boolean isCurrent = false;
		@AuraEnabled
		public Boolean hasPrevious = false;
		@AuraEnabled
		public Boolean renumbered = false;
		@AuraEnabled
		public String previousNumber;
	}

	/**
	 * @creation date: 02/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Devuelve todas las vigencias de la cadena de la póliza indicada, las
	 *               anteriores y las posteriores, de la más reciente a la más antigua, con
	 *               lo pagado, lo pendiente y cuántos documentos tiene cada una.
	 * @param policyId: Id de la InsurancePolicy que se está viendo.
	 * @return Lista de vigencias; vacía si no hay póliza.
	 */
	@AuraEnabled(cacheable=true)
	public static List<Term> getTermsByPolicy(Id policyId) {
		if (policyId == null) {
			return new List<Term>();
		}
		Map<Id, InsurancePolicy> chain = loadChain(policyId);
		if (chain.isEmpty()) {
			return new List<Term>();
		}

		Map<Id, Term> terms = new Map<Id, Term>();
		for (InsurancePolicy policy : chain.values()) {
			terms.put(policy.Id, toTerm(policy, policyId));
		}
		addAmounts(terms);
		addDocumentCounts(terms);

		List<TermSorter> sorters = new List<TermSorter>();
		for (Term term : terms.values()) {
			sorters.add(new TermSorter(term));
		}
		sorters.sort();
		List<Term> ordered = new List<Term>();
		for (TermSorter sorter : sorters) {
			ordered.add(sorter.term);
		}
		return ordered;
	}

	/** Sube por PriorPolicyId y baja por las pólizas que tienen a la actual como anterior. */
	private static Map<Id, InsurancePolicy> loadChain(Id policyId) {
		Map<Id, InsurancePolicy> chain = new Map<Id, InsurancePolicy>();
		List<InsurancePolicy> current = queryPolicies(
			new Set<Id>{ policyId },
			null
		);
		if (current.isEmpty()) {
			return chain;
		}
		chain.put(current[0].Id, current[0]);

		Id previousId = current[0].PriorPolicyId;
		for (
			Integer level = 0;
			previousId != null &&
			!chain.containsKey(previousId) &&
			level < MAX_LEVELS;
			level++
		) {
			List<InsurancePolicy> previous = queryPolicies(
				new Set<Id>{ previousId },
				null
			);
			if (previous.isEmpty()) {
				break;
			}
			chain.put(previous[0].Id, previous[0]);
			previousId = previous[0].PriorPolicyId;
		}

		Set<Id> frontier = new Set<Id>{ policyId };
		for (
			Integer level = 0; !frontier.isEmpty() && level < MAX_LEVELS; level++
		) {
			List<InsurancePolicy> next = queryPolicies(null, frontier);
			frontier = new Set<Id>();
			for (InsurancePolicy policy : next) {
				if (!chain.containsKey(policy.Id)) {
					chain.put(policy.Id, policy);
					frontier.add(policy.Id);
				}
			}
		}
		return chain;
	}

	private static List<InsurancePolicy> queryPolicies(
		Set<Id> ids,
		Set<Id> previousIds
	) {
		if (ids != null) {
			return [
				SELECT
					Id,
					Name,
					termPeriod__c,
					EffectiveDate,
					Status,
					PremiumAmount,
					PriorPolicyId,
					PriorPolicy.Name
				FROM InsurancePolicy
				WHERE Id IN :ids
			];
		}
		return [
			SELECT
				Id,
				Name,
				termPeriod__c,
				EffectiveDate,
				Status,
				PremiumAmount,
				PriorPolicyId,
				PriorPolicy.Name
			FROM InsurancePolicy
			WHERE PriorPolicyId IN :previousIds
		];
	}

	private static Term toTerm(InsurancePolicy policy, Id currentId) {
		Term term = new Term();
		term.policyId = policy.Id;
		term.policyNumber = policy.Name;
		term.period = policy.termPeriod__c;
		term.effectiveDate = policy.EffectiveDate;
		term.status = policy.Status;
		term.premium = policy.PremiumAmount;
		term.isCurrent = policy.Id == currentId;
		term.hasPrevious = policy.PriorPolicyId != null;
		if (policy.PriorPolicyId != null && policy.PriorPolicy != null) {
			term.previousNumber = policy.PriorPolicy.Name;
			term.renumbered = policy.PriorPolicy.Name != policy.Name;
		}
		return term;
	}

	/**
	 * Suma lo mismo que los totales de la pestaña Pagos: las cuotas vivas, sin las
	 * canceladas, las condonadas ni los recibos que otra cuota reemplaza.
	 */
	private static void addAmounts(Map<Id, Term> terms) {
		List<PaymentPlanInstallment__c> installments = [
			SELECT
				Id,
				installmentStatus__c,
				matchedAmount__c,
				outstandingAmount__c,
				replacesInstallment__c,
				paymentPlan__r.insurancePolicy__c
			FROM PaymentPlanInstallment__c
			WHERE paymentPlan__r.insurancePolicy__c IN :terms.keySet()
		];
		Set<Id> replaced = new Set<Id>();
		for (PaymentPlanInstallment__c installment : installments) {
			if (installment.replacesInstallment__c != null) {
				replaced.add(installment.replacesInstallment__c);
			}
		}
		for (PaymentPlanInstallment__c installment : installments) {
			if (
				replaced.contains(installment.Id) ||
				CLOSED_STATUSES.contains(installment.installmentStatus__c)
			) {
				continue;
			}
			Term term = terms.get(installment.paymentPlan__r.insurancePolicy__c);
			term.paid += installment.matchedAmount__c == null
				? 0
				: installment.matchedAmount__c;
			term.outstanding += installment.outstandingAmount__c == null
				? 0
				: installment.outstandingAmount__c;
		}
	}

	private static void addDocumentCounts(Map<Id, Term> terms) {
		for (ContentDocumentLink link : [
			SELECT LinkedEntityId
			FROM ContentDocumentLink
			WHERE LinkedEntityId IN :terms.keySet()
		]) {
			terms.get(link.LinkedEntityId).documentCount += 1;
		}
	}

	/** De la vigencia más reciente a la más antigua; sin fecha de inicio, al final. */
	private class TermSorter implements Comparable {
		Term term;

		TermSorter(Term term) {
			this.term = term;
		}

		public Integer compareTo(Object other) {
			Datetime mine = term.effectiveDate;
			Datetime theirs = ((TermSorter) other).term.effectiveDate;
			if (mine == theirs) {
				return 0;
			}
			if (mine == null) {
				return 1;
			}
			if (theirs == null) {
				return -1;
			}
			return mine > theirs ? -1 : 1;
		}
	}
}
