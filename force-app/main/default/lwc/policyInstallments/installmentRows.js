/**
 * Arma las filas de la pestaña Pagos a partir de las cuotas de la póliza.
 *
 * Una cuota es la obligación de un periodo; el recibo es el documento con el que la aseguradora la
 * cobra, y puede cambiar sin que cambie la obligación: si cancela un recibo y emite otro para el
 * mismo periodo, la cuota nueva apunta a la anterior. Aquí se muestra una fila por cuota viva, con
 * los recibos a los que reemplaza colgando de ella, plegados.
 */

const EMISSION_ENDORSEMENT = "000000";
const CLOSED_STATUSES = ["Cancelado", "Condonado"];

/** Etiqueta de la cuota: el número que le da la aseguradora y, si viene de un endoso, cuál. */
function labelFor(origin, live) {
	if (!origin.carrierInstallmentNumber__c) {
		return live.sequenceNumber__c
			? `Cuota ${live.sequenceNumber__c}`
			: live.Name;
	}
	const endorsement = origin.carrierEndorsementNumber__c;
	const suffix =
		endorsement && endorsement !== EMISSION_ENDORSEMENT
			? ` · Endoso ${endorsement}`
			: "";
	return `Cuota ${origin.carrierInstallmentNumber__c}${suffix}`;
}

/** Clase de color del estado: verde si está pagada, gris si ya no se debe, rojo si venció. */
function statusClass(status) {
	if (status === "Conciliado") {
		return "slds-text-color_success";
	}
	if (CLOSED_STATUSES.includes(status)) {
		return "slds-text-color_weak";
	}
	if (status === "Vencido") {
		return "slds-text-color_error";
	}
	return "";
}

function baseRow(record) {
	return {
		...record,
		paymentDate: record.matchedReceipt__r
			? record.matchedReceipt__r.receiptDate__c
			: null,
		installmentUrl: `/${record.Id}`,
		statusClass: statusClass(record.installmentStatus__c),
		overdueClass:
			record.daysOverdue__c > 0
				? "slds-text-color_error"
				: "slds-text-color_weak",
		daysOverdue: record.daysOverdue__c > 0 ? record.daysOverdue__c : null
	};
}

/**
 * @param {Array} records cuotas tal como las devuelve el controlador
 * @returns {{rows: Array, totals: Object}} filas para el tree-grid y totales de lo que cuenta
 */
export function buildRows(records) {
	const list = records || [];
	const byId = new Map(list.map((r) => [r.Id, r]));
	// Una cuota está reemplazada si otra dice que la reemplaza a ella.
	const replaced = new Set(
		list.map((r) => r.replacesInstallment__c).filter((id) => !!id)
	);

	const rows = [];
	const totals = { expected: 0, matched: 0, outstanding: 0, count: 0 };

	list
		.filter((record) => !replaced.has(record.Id))
		.forEach((live) => {
			// Cadena de recibos reemplazados, del más reciente al más antiguo.
			const chain = [];
			let previous = byId.get(live.replacesInstallment__c);
			while (previous) {
				chain.push(previous);
				previous = byId.get(previous.replacesInstallment__c);
			}
			// El número de cuota de la aseguradora es el de la emisión original: una reexpedición
			// vuelve a empezar en 1 y mostrarlo confundiría.
			const origin = chain.length ? chain[chain.length - 1] : live;

			const row = baseRow(live);
			row.sequenceLabel = labelFor(origin, live);
			if (chain.length) {
				row.replacedLabel =
					chain.length === 1
						? "1 recibo reemplazado"
						: `${chain.length} recibos reemplazados`;
				row._children = chain.map((old) => {
					const child = baseRow(old);
					child.sequenceLabel = `Recibo ${old.carrierReceiptNumber__c || old.Name}`;
					child.statusClass = "slds-text-color_weak";
					child.overdueClass = "slds-text-color_weak";
					child.daysOverdue = null;
					return child;
				});
			}
			rows.push(row);

			totals.count += 1;
			if (!CLOSED_STATUSES.includes(live.installmentStatus__c)) {
				totals.expected += live.expectedAmount__c || 0;
				totals.matched += live.matchedAmount__c || 0;
				totals.outstanding += live.outstandingAmount__c || 0;
			}
		});

	return { rows, totals };
}
