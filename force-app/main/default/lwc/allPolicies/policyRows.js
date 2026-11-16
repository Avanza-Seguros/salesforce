const MONEY = new Intl.NumberFormat("es-MX", {
	style: "currency",
	currency: "MXN"
});
const COUNT = new Intl.NumberFormat("es-MX");

export const PAGE_SIZE = 200;
// Espera tras la última tecla antes de buscar, para no pedir una página por letra.
export const SEARCH_DELAY_MS = 400;

/** Columna de la tabla → campo de la póliza por el que ordena el servidor. */
export const SORT_FIELD_BY_COLUMN = {
	policyUrl: "Name",
	ramoLabel: "Ramo__c",
	frequencyLabel: "PremiumFrequency",
	effectiveLabel: "EffectiveDate",
	expirationLabel: "ExpirationDate",
	premiumLabel: "PremiumAmount",
	statusLabel: "Status",
	insuredSubject: "insuredSubject__c",
	createdLabel: "CreatedDate"
};

export function columnForSortField(sortField) {
	return Object.keys(SORT_FIELD_BY_COLUMN).find(
		(column) => SORT_FIELD_BY_COLUMN[column] === sortField
	);
}

export function formatCount(value) {
	return COUNT.format(value || 0);
}

export function formatMoney(value) {
	return value === null || value === undefined ? "" : MONEY.format(value);
}

/** Fecha en la zona horaria del usuario; las de la póliza se guardan como fecha y hora. */
export function formatDate(value, timeZone) {
	if (!value) {
		return "";
	}
	const options = { day: "2-digit", month: "2-digit", year: "numeric" };
	if (timeZone) {
		options.timeZone = timeZone;
	}
	try {
		return new Intl.DateTimeFormat("es-MX", options).format(new Date(value));
	} catch {
		delete options.timeZone;
		return new Intl.DateTimeFormat("es-MX", options).format(new Date(value));
	}
}

function label(labels, field, value) {
	if (!value) {
		return "";
	}
	const byValue = labels && labels[field];
	return (byValue && byValue[value]) || value;
}

/** Fila tal como la pinta la tabla, a partir de la póliza que devuelve el servidor. */
export function buildRow(policy, labels, timeZone) {
	return {
		Id: policy.Id,
		record: policy,
		policyUrl: `/lightning/r/InsurancePolicy/${policy.Id}/view`,
		policyNumber: policy.Name,
		carrierName: policy.Aseguradora__r ? policy.Aseguradora__r.Name : "",
		ramoLabel: label(labels, "Ramo__c", policy.Ramo__c),
		insuredName: policy.NameInsured ? policy.NameInsured.Name : "",
		frequencyLabel: label(labels, "PremiumFrequency", policy.PremiumFrequency),
		effectiveLabel: formatDate(policy.EffectiveDate, timeZone),
		expirationLabel: formatDate(policy.ExpirationDate, timeZone),
		premiumLabel: formatMoney(policy.PremiumAmount),
		statusLabel: label(labels, "Status", policy.Status),
		insuredSubject: policy.insuredSubject__c || "",
		createdLabel: formatDate(policy.CreatedDate, timeZone)
	};
}

/** Cursor de la página siguiente: el valor del campo de orden de la última fila y su Id. */
export function cursorFor(policy, sortField) {
	if (!policy) {
		return { cursorValue: null, cursorId: null };
	}
	const value = policy[sortField];
	return {
		cursorValue: value === null || value === undefined ? null : String(value),
		cursorId: policy.Id
	};
}

/** Mensaje legible a partir de un error de Apex o de JavaScript. */
export function errorMessage(error) {
	if (!error) {
		return "Error desconocido.";
	}
	const body = error.body;
	if (body) {
		if (Array.isArray(body)) {
			return body.map((item) => item.message).join(" ");
		}
		if (body.message) {
			return body.message;
		}
		if (body.pageErrors && body.pageErrors.length) {
			return body.pageErrors.map((item) => item.message).join(" ");
		}
	}
	return error.message || "Error desconocido.";
}
