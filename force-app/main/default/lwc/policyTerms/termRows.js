/**
 * Arma las filas de la pestaña Vigencias. Cada vigencia es una póliza propia; aquí se dice cuál es
 * la que se está viendo y si la aseguradora cambió el número al renovar, que es lo que hace que una
 * renovación sea difícil de encontrar buscando por número.
 */

function renewalOf(term) {
	if (!term.hasPrevious) {
		return { label: "Primera registrada", className: "slds-text-color_weak" };
	}
	if (term.renumbered) {
		return {
			label: `Renumerada · antes ${term.previousNumber}`,
			className: "slds-text-color_default"
		};
	}
	return { label: "Mismo número", className: "slds-text-color_weak" };
}

function documentsLabelOf(count) {
	if (!count) {
		return "Sin documentos";
	}
	return count === 1 ? "1 documento" : `${count} documentos`;
}

/**
 * @param {Array} terms vigencias tal como las devuelve el controlador, de la más reciente a la más antigua
 * @returns {Array} filas para el datatable
 */
export function buildRows(terms) {
	return (terms || []).map((term) => {
		const renewal = renewalOf(term);
		const period = term.period || "Sin fechas";
		return {
			...term,
			policyUrl: `/${term.policyId}`,
			periodLabel: term.isCurrent ? `${period} · esta` : period,
			currentClass: term.isCurrent ? "slds-text-title_bold" : "",
			renewalLabel: renewal.label,
			renewalClass: renewal.className,
			documentsLabel: documentsLabelOf(term.documentCount),
			hasNoDocuments: !term.documentCount
		};
	});
}
