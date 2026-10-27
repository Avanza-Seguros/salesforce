/**
 * Arma las filas de la pestaña Pagos a partir de las cuotas de la póliza.
 *
 * Una cuota es la obligación de un periodo; el recibo es el documento con el que la aseguradora la
 * cobra, y puede cambiar sin que cambie la obligación: si cancela un recibo y emite otro para el
 * mismo periodo, la cuota nueva apunta a la anterior. Aquí se muestra una fila por cuota viva, con
 * los recibos a los que reemplaza colgando de ella, plegados.
 *
 * Una cuota estimada se calculó con la prima y la forma de pago porque la aseguradora todavía no
 * informó su recibo: su importe y su fecha pueden no ser los reales. Se marca para que nadie la tome
 * por un dato de la aseguradora, pero su mora se muestra igual, para que alguien la revise.
 */

// La emisión original llega como endoso vacío o en ceros ("0", "000000"), según la fuente.
const EMISSION_ENDORSEMENT = /^0+$/;
const CLOSED_STATUSES = ["Cancelado", "Condonado"];

function endorsementOf(record) {
	const endorsement = record.carrierEndorsementNumber__c;
	return endorsement && !EMISSION_ENDORSEMENT.test(endorsement.trim())
		? endorsement
		: null;
}

/**
 * La numeración de la aseguradora solo sirve si distingue a cada cuota viva: numera por documento (la
 * emisión y cada endoso empiezan en 1, y hay fuentes que no la mandan), así que con huecos o repetidos
 * dos cuotas distintas saldrían como "Cuota 1". En ese caso se numera con la secuencia del plan.
 */
function carrierNumberingIsUsable(origins) {
	const keys = origins.map(
		(origin) =>
			`${origin.carrierInstallmentNumber__c}|${endorsementOf(origin) || ""}`
	);
	return (
		origins.every((origin) => !!origin.carrierInstallmentNumber__c) &&
		new Set(keys).size === keys.length
	);
}

/** Etiqueta de la cuota: su número y, si viene de un endoso, cuál. */
function labelFor(origin, live, useCarrierNumber) {
	const endorsement = endorsementOf(origin);
	const suffix = endorsement ? ` · Endoso ${endorsement}` : "";
	if (useCarrierNumber && origin.carrierInstallmentNumber__c) {
		return `Cuota ${origin.carrierInstallmentNumber__c}${suffix}`;
	}
	return live.sequenceNumber__c
		? `Cuota ${live.sequenceNumber__c}${suffix}`
		: live.Name;
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
		receiptLabel:
			record.carrierReceiptNumber__c ||
			(record.isEstimated__c ? "Sin recibo aún" : null),
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
	const totals = {
		expected: 0,
		matched: 0,
		outstanding: 0,
		estimated: 0,
		count: 0
	};

	// Una estimada cancelada la sustituyó su recibo real (o ya no hacía falta): nunca existió en la
	// aseguradora y mostrarla duplicaría la cuota.
	const entries = list
		.filter((record) => !replaced.has(record.Id))
		.filter(
			(record) =>
				!(
					record.isEstimated__c &&
					CLOSED_STATUSES.includes(record.installmentStatus__c)
				)
		)
		.map((live) => {
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
			return { live, chain, origin };
		});
	const useCarrierNumber = carrierNumberingIsUsable(
		entries
			.filter(
				({ live }) => !CLOSED_STATUSES.includes(live.installmentStatus__c)
			)
			.map(({ origin }) => origin)
	);

	entries.forEach(({ live, chain, origin }) => {
		const row = baseRow(live);
		row.sequenceLabel =
			labelFor(origin, live, useCarrierNumber) +
			(live.isEstimated__c ? " · Estimada" : "");
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
			if (live.isEstimated__c) {
				totals.estimated += live.expectedAmount__c || 0;
			}
		}
	});

	return { rows, totals };
}
