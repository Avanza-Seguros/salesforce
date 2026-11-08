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

import LOCALE from "@salesforce/i18n/locale";

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

// Las fechas llegan como "AAAA-MM-DD" sin hora: se formatean en UTC para que la zona horaria del
// usuario no las corra un día.
const DATE_FORMAT = new Intl.DateTimeFormat(LOCALE, {
	day: "numeric",
	month: "short",
	year: "numeric",
	timeZone: "UTC"
});

function formatDate(value) {
	return value ? DATE_FORMAT.format(new Date(`${value}T00:00:00Z`)) : null;
}

/** Inicio y fin del periodo del recibo en una sola columna; si falta un extremo, se dice cuál hay. */
function coveragePeriodOf(record) {
	const start = formatDate(record.periodStartDate__c);
	const end = formatDate(record.periodEndDate__c);
	if (start && end) {
		return `${start} – ${end}`;
	}
	if (start) {
		return `Desde ${start}`;
	}
	return end ? `Hasta ${end}` : null;
}

function baseRow(record) {
	return {
		...record,
		coveragePeriod: coveragePeriodOf(record),
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

/** Cuotas vivas, cada una con la cadena de recibos a los que reemplaza. */
function liveEntries(list) {
	const byId = new Map(list.map((r) => [r.Id, r]));
	// Una cuota está reemplazada si otra dice que la reemplaza a ella.
	const replaced = new Set(
		list.map((r) => r.replacesInstallment__c).filter((id) => !!id)
	);
	// Una estimada cancelada la sustituyó su recibo real (o ya no hacía falta): nunca existió en la
	// aseguradora y mostrarla duplicaría la cuota.
	return list
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
}

/** Fila de una cuota viva, con sus recibos reemplazados colgando. */
function liveRow({ live, chain }, label) {
	const row = baseRow(live);
	row.sequenceLabel = label;
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
	return row;
}

function emptyTotals() {
	return { expected: 0, matched: 0, outstanding: 0, estimated: 0, count: 0 };
}

/** Suma lo que cuenta para el cobro: las canceladas y condonadas ya no se deben. */
function addToTotals(totals, live) {
	totals.count += 1;
	if (!CLOSED_STATUSES.includes(live.installmentStatus__c)) {
		totals.expected += live.expectedAmount__c || 0;
		totals.matched += live.matchedAmount__c || 0;
		totals.outstanding += live.outstandingAmount__c || 0;
		if (live.isEstimated__c) {
			totals.estimated += live.expectedAmount__c || 0;
		}
	}
}

// Flotillas y colectivas: la aseguradora emite un recibo por inciso, así que no hay «cuotas de la
// póliza» sino recibos de cada vehículo, ubicación o persona.

const LIVE_POLICY_STATUSES = ["Inicial", "Vigente"];
const INCISO_PREFIX = /^inciso\s+(\d+)\s*-\s*/i;
const NO_INCISO = "sin-inciso";
const NO_DATE = "sin fecha";

/** Quita espacios y ceros a la izquierda, como el motor: «007» y «7» son el mismo inciso. */
function normalizeCode(code) {
	if (code === null || code === undefined || `${code}`.trim() === "") {
		return null;
	}
	const trimmed = `${code}`.trim();
	return /^\d+$/.test(trimmed) ? `${parseInt(trimmed, 10)}` : trimmed;
}

function addDays(isoDate, days) {
	const date = new Date(`${isoDate.slice(0, 10)}T00:00:00Z`);
	date.setUTCDate(date.getUTCDate() + days);
	return date.toISOString().slice(0, 10);
}

/**
 * Un inciso está de baja si tiene fecha o motivo de baja, si su cobertura termina antes que la
 * póliza, o si está apagado con la póliza viva (al vencer la póliza se apagan todos y no es baja).
 * Es la misma regla que usa el campo «Asegurado o bien» de la póliza.
 */
function droppedOn(endDate, isActive, explicitDate, reason, policy) {
	if (explicitDate) {
		return explicitDate;
	}
	if (reason) {
		return endDate || NO_DATE;
	}
	const policyEnd = policy && policy.ExpirationDate;
	if (endDate && policyEnd && endDate < addDays(policyEnd, -1)) {
		return endDate;
	}
	if (
		isActive === false &&
		policy &&
		LIVE_POLICY_STATUSES.includes(policy.Status)
	) {
		return endDate || NO_DATE;
	}
	return null;
}

function assetInciso(record, asset, policy) {
	const name = asset.AssetName || "";
	const prefix = name.match(INCISO_PREFIX);
	const code = normalizeCode(asset.AssetCode) || (prefix && prefix[1]);
	let subject = name.replace(INCISO_PREFIX, "");
	const vin = asset.CustomerProperty && asset.CustomerProperty.Vin;
	if (vin && !subject.toUpperCase().includes(vin.toUpperCase())) {
		subject = subject ? `${subject} · serie ${vin}` : `Serie ${vin}`;
	}
	return {
		key: `bien-${record.policyAsset__c}`,
		recordId: record.policyAsset__c,
		code,
		label: code ? `Inciso ${code}` : "Bien sin número",
		subject,
		dropped: droppedOn(
			asset.EffectiveToDate,
			asset.IsActive,
			asset.Fecha_Baja__c,
			asset.Motivo_Baja__c,
			policy
		)
	};
}

function personInciso(record, person, policy) {
	const code = normalizeCode(person.ParticipantCode);
	return {
		key: `persona-${record.policyParticipant__c}`,
		recordId: record.policyParticipant__c,
		code,
		label: code ? `Certificado ${code}` : "Asegurado sin certificado",
		subject: person.ParticipantName || "",
		dropped: droppedOn(
			person.EffectiveToDate,
			person.IsActiveParticipant,
			null,
			person.Motivo_Baja__c,
			policy
		)
	};
}

/** Qué inciso es un recibo: número, nombre del bien o de la persona y si está de baja. */
function incisoOf(record) {
	const policy =
		record.paymentPlan__r && record.paymentPlan__r.insurancePolicy__r;
	if (record.policyAsset__c && record.policyAsset__r) {
		return assetInciso(record, record.policyAsset__r, policy);
	}
	if (record.policyParticipant__c && record.policyParticipant__r) {
		return personInciso(record, record.policyParticipant__r, policy);
	}
	return {
		key: NO_INCISO,
		code: null,
		label: "Sin inciso",
		subject: "",
		dropped: null
	};
}

/** Orden de los incisos: vivos antes que los de baja, los sin inciso al final, y por número. */
function compareIncisos(a, b) {
	if (!!a.dropped !== !!b.dropped) {
		return a.dropped ? 1 : -1;
	}
	if ((a.key === NO_INCISO) !== (b.key === NO_INCISO)) {
		return a.key === NO_INCISO ? 1 : -1;
	}
	const na = Number(a.code);
	const nb = Number(b.code);
	if (a.code && b.code && !Number.isNaN(na) && !Number.isNaN(nb)) {
		return na - nb;
	}
	return `${a.code || a.subject}`.localeCompare(`${b.code || b.subject}`);
}

function droppedSuffix(inciso) {
	if (!inciso.dropped) {
		return "";
	}
	return inciso.dropped === NO_DATE
		? " · Baja"
		: ` · Baja ${formatDate(inciso.dropped)}`;
}

/** Pinta en gris una fila de un inciso dado de baja, y lo que cuelga de ella. */
function greyOut(row) {
	row.statusClass = "slds-text-color_weak";
	row.overdueClass = "slds-text-color_weak";
	row.subjectClass = "slds-text-color_weak";
	(row._children || []).forEach(greyOut);
	return row;
}

function plural(count, one, many) {
	return `${count} ${count === 1 ? one : many}`;
}

/** Resumen de un grupo: cuánto cuenta y cómo van sus recibos. */
function groupSummary(entries) {
	const totals = emptyTotals();
	let paid = 0;
	let cancelled = 0;
	let pending = 0;
	entries.forEach(({ live }) => {
		addToTotals(totals, live);
		if (live.installmentStatus__c === "Conciliado") {
			paid += 1;
		} else if (CLOSED_STATUSES.includes(live.installmentStatus__c)) {
			cancelled += 1;
		} else {
			pending += 1;
		}
	});
	const parts = [];
	if (paid) {
		parts.push(plural(paid, "pagado", "pagados"));
	}
	if (pending) {
		parts.push(plural(pending, "pendiente", "pendientes"));
	}
	if (cancelled) {
		parts.push(plural(cancelled, "cancelado", "cancelados"));
	}
	return { totals, text: parts.length ? ` · ${parts.join(" · ")}` : "" };
}

function groupRow(id, label, summary) {
	return {
		Id: id,
		isGroup: true,
		sequenceLabel: label,
		expectedAmount__c: summary.totals.expected,
		matchedAmount__c: summary.totals.matched,
		outstandingAmount__c: summary.totals.outstanding,
		statusClass: "slds-text-title_bold",
		overdueClass: "",
		daysOverdue: null
	};
}

/** Fila de un recibo de un inciso: dice el inciso y su bien o su persona; las bajas, en gris. */
function incisoReceiptRow(entry, inciso, label) {
	const row = liveRow(entry, label + droppedSuffix(inciso));
	setSubject(row, inciso);
	return inciso.dropped ? greyOut(row) : row;
}

/** El bien o la persona del inciso, con enlace a su ficha para ver su detalle. */
function setSubject(row, inciso) {
	row.subjectLabel = inciso.subject || (inciso.recordId ? "Ver ficha" : "");
	row.subjectUrl = inciso.recordId ? `/${inciso.recordId}` : null;
}

/** Primer nivel la fecha de vencimiento; debajo, un recibo por inciso. */
function rowsByDate(entries) {
	const byDate = new Map();
	entries.forEach((entry) => {
		const key = entry.live.dueDate__c || NO_DATE;
		if (!byDate.has(key)) {
			byDate.set(key, []);
		}
		byDate.get(key).push({ ...entry, inciso: incisoOf(entry.live) });
	});
	return [...byDate.entries()].map(([date, group]) => {
		group.sort((a, b) => compareIncisos(a.inciso, b.inciso));
		const incisos = new Set(group.map((e) => e.inciso.key)).size;
		const summary = groupSummary(group);
		const when = date === NO_DATE ? "Sin fecha" : formatDate(date);
		const row = groupRow(
			`fecha-${date}`,
			`${when} · ${plural(incisos, "inciso", "incisos")}${summary.text}`,
			summary
		);
		row._children = group.map((e) =>
			incisoReceiptRow(e, e.inciso, e.inciso.label)
		);
		return row;
	});
}

/** Primer nivel el inciso; debajo, sus recibos por fecha. Sirve para las flotillas mensuales. */
function rowsByInciso(entries) {
	const byInciso = new Map();
	entries.forEach((entry) => {
		const inciso = incisoOf(entry.live);
		if (!byInciso.has(inciso.key)) {
			byInciso.set(inciso.key, { inciso, entries: [] });
		}
		byInciso.get(inciso.key).entries.push(entry);
	});
	return [...byInciso.values()]
		.sort((a, b) => compareIncisos(a.inciso, b.inciso))
		.map(({ inciso, entries: group }) => {
			const summary = groupSummary(group);
			const row = groupRow(
				`inciso-${inciso.key}`,
				`${inciso.label}${droppedSuffix(inciso)} · ${plural(group.length, "recibo", "recibos")}${summary.text}`,
				summary
			);
			setSubject(row, inciso);
			row._children = group.map((e) =>
				incisoReceiptRow(
					e,
					inciso,
					e.live.dueDate__c ? formatDate(e.live.dueDate__c) : "Sin fecha"
				)
			);
			return inciso.dropped ? greyOut(row) : row;
		});
}

/**
 * Es una flotilla o colectiva si al menos un recibo apunta a un inciso. Sin ninguno, la pestaña es
 * la de siempre.
 */
export function isFleet(records) {
	return (records || []).some(
		(r) => !!(r.policyAsset__c || r.policyParticipant__c)
	);
}

/**
 * @param {Array} records cuotas tal como las devuelve el controlador
 * @param {string} groupBy en una flotilla, "fecha" (por defecto) o "inciso"
 * @returns {{rows: Array, totals: Object, fleet: boolean}} filas para el tree-grid y totales de lo
 *          que cuenta; los totales no dependen de cómo se agrupe
 */
export function buildRows(records, groupBy) {
	const list = records || [];
	const entries = liveEntries(list);
	const totals = emptyTotals();
	entries.forEach(({ live }) => addToTotals(totals, live));

	if (isFleet(list)) {
		const rows =
			groupBy === "inciso" ? rowsByInciso(entries) : rowsByDate(entries);
		return { rows, totals, fleet: true };
	}

	const useCarrierNumber = carrierNumberingIsUsable(
		entries
			.filter(
				({ live }) => !CLOSED_STATUSES.includes(live.installmentStatus__c)
			)
			.map(({ origin }) => origin)
	);
	const rows = entries.map((entry) =>
		liveRow(
			entry,
			labelFor(entry.origin, entry.live, useCarrierNumber) +
				(entry.live.isEstimated__c ? " · Estimada" : "")
		)
	);
	return { rows, totals, fleet: false };
}
