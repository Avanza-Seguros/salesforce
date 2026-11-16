import { LightningElement, api, wire } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import getInstallmentsByPolicy from "@salesforce/apex/PolicyInstallmentsController.getInstallmentsByPolicy";
import PREMIUM_FIELD from "@salesforce/schema/InsurancePolicy.PremiumAmount";
import INSURED_SUBJECT_FIELD from "@salesforce/schema/InsurancePolicy.insuredSubject__c";
import { buildRows, isFleet } from "./installmentRows";

const COLUMNS = [
	{
		label: "Cuota",
		fieldName: "installmentUrl",
		type: "url",
		initialWidth: 170,
		typeAttributes: { label: { fieldName: "sequenceLabel" }, target: "_self" },
		cellAttributes: { class: { fieldName: "statusClass" } }
	},
	{
		label: "Recibo",
		fieldName: "receiptLabel",
		type: "text",
		initialWidth: 115,
		cellAttributes: { class: { fieldName: "statusClass" } }
	},
	{
		label: "Vence",
		fieldName: "dueDate__c",
		type: "date-local",
		initialWidth: 105
	},
	{
		label: "Fecha de pago",
		fieldName: "paymentDate",
		type: "date-local",
		initialWidth: 115
	},
	{
		label: "Esperado",
		fieldName: "expectedAmount__c",
		type: "currency",
		initialWidth: 125,
		cellAttributes: { alignment: "right" }
	},
	{
		label: "Conciliado",
		fieldName: "matchedAmount__c",
		type: "currency",
		initialWidth: 125,
		cellAttributes: { alignment: "right" }
	},
	{
		label: "Pendiente",
		fieldName: "outstandingAmount__c",
		type: "currency",
		initialWidth: 125,
		cellAttributes: { alignment: "right" }
	},
	{
		label: "Estado",
		fieldName: "installmentStatus__c",
		type: "text",
		initialWidth: 110,
		cellAttributes: { class: { fieldName: "statusClass" } }
	},
	{
		label: "Días mora",
		fieldName: "daysOverdue",
		type: "number",
		initialWidth: 80,
		cellAttributes: {
			alignment: "right",
			class: { fieldName: "overdueClass" }
		}
	},
	{
		label: "Período que cubre el recibo",
		fieldName: "coveragePeriod",
		type: "text",
		initialWidth: 215
	}
];

// En una flotilla o colectiva el primer nivel es la fecha o el inciso, no una cuota: la primera
// columna es texto y el enlace a la cuota va en el número de recibo.
const FLEET_COLUMNS = [
	{
		label: "Fecha / inciso",
		fieldName: "sequenceLabel",
		type: "text",
		initialWidth: 230,
		wrapText: true,
		cellAttributes: { class: { fieldName: "statusClass" } }
	},
	{
		label: "Bien o asegurado",
		fieldName: "subjectUrl",
		type: "url",
		initialWidth: 230,
		wrapText: true,
		typeAttributes: { label: { fieldName: "subjectLabel" }, target: "_self" },
		cellAttributes: { class: { fieldName: "subjectClass" } }
	},
	{
		label: "Recibo",
		fieldName: "installmentUrl",
		type: "url",
		initialWidth: 115,
		typeAttributes: { label: { fieldName: "receiptLabel" }, target: "_self" },
		cellAttributes: { class: { fieldName: "statusClass" } }
	},
	...COLUMNS.slice(2)
];

const GROUP_OPTIONS = [
	{ label: "Por fecha", value: "fecha" },
	{ label: "Por inciso", value: "inciso" }
];

export default class PolicyInstallments extends LightningElement {
	@api recordId;

	rows = [];
	records = [];
	groupBy = "fecha";
	groupOptions = GROUP_OPTIONS;
	fleet = false;
	expandedRows = [];
	totals = { expected: 0, matched: 0, outstanding: 0, estimated: 0, count: 0 };
	error;
	loaded = false;

	// Lo que asegura es opcional: quien no tenga permiso sobre el campo sigue viendo la tabla.
	@wire(getRecord, {
		recordId: "$recordId",
		fields: [PREMIUM_FIELD],
		optionalFields: [INSURED_SUBJECT_FIELD]
	})
	policy;

	@wire(getInstallmentsByPolicy, { policyId: "$recordId" })
	wiredInstallments({ data, error }) {
		if (data) {
			this.records = data;
			this.fleet = isFleet(data);
			this.rebuild();
			this.error = undefined;
			this.loaded = true;
		} else if (error) {
			this.error =
				(error.body && error.body.message) ||
				"No se pudieron cargar las cuotas.";
			this.rows = [];
			this.loaded = true;
		}
	}

	rebuild() {
		const built = buildRows(this.records, this.groupBy);
		this.rows = built.rows;
		this.totals = built.totals;
		// En una flotilla se abren las fechas (o los incisos) para ver los recibos de entrada; los
		// recibos reemplazados siguen plegados.
		this.expandedRows = this.fleet ? this.rows.map((row) => row.Id) : [];
	}

	handleGroupChange(event) {
		this.groupBy = event.detail.value;
		this.rebuild();
	}

	get columns() {
		return this.fleet ? FLEET_COLUMNS : COLUMNS;
	}

	/** Filas que tienen algo colgando (recibos reemplazados o, en una flotilla, sus recibos). */
	get expandableIds() {
		const ids = [];
		const walk = (rows) =>
			rows.forEach((row) => {
				if (row._children) {
					ids.push(row.Id);
					walk(row._children);
				}
			});
		walk(this.rows);
		return ids;
	}

	get hasReplacedReceipts() {
		return this.expandableIds.length > 0;
	}

	expandAll() {
		this.expandedRows = this.expandableIds;
	}

	collapseAll() {
		this.expandedRows = [];
	}

	/** Filas visibles: las del primer nivel y las de los grupos abiertos. */
	get visibleRowCount() {
		const open = new Set(this.expandedRows);
		const count = (rows) =>
			rows.reduce(
				(total, row) =>
					total +
					1 +
					(row._children && open.has(row.Id) ? count(row._children) : 0),
				0
			);
		return count(this.rows);
	}

	/**
	 * Con muchas filas la tabla tiene su propio alto y se desplaza por dentro: así la barra
	 * horizontal se ve sin bajar hasta el final de la página.
	 */
	get tableClass() {
		return this.visibleRowCount > 12 ? "table-scroll" : "";
	}

	handleToggle(event) {
		const { name, isExpanded } = event.detail;
		const open = new Set(this.expandedRows);
		if (isExpanded) {
			open.add(name);
		} else {
			open.delete(name);
		}
		this.expandedRows = [...open];
	}

	get hasRows() {
		return this.rows.length > 0;
	}

	get isEmpty() {
		return this.loaded && !this.error && this.rows.length === 0;
	}

	get cardTitle() {
		const title = this.fleet ? "Recibos por inciso" : "Cuotas del plan de pago";
		return this.hasRows ? `${title} (${this.totals.count})` : title;
	}

	/** Qué asegura la póliza: el bien o el nombre de cada asegurado, una sola vez y no en cada fila. */
	get insuredSubject() {
		return getFieldValue(this.policy.data, INSURED_SUBJECT_FIELD);
	}

	get premiumAmount() {
		return getFieldValue(this.policy.data, PREMIUM_FIELD);
	}

	/** Lo que cuenta para el cobro: sin las canceladas ni las condonadas. */
	get expectedTotal() {
		return this.totals.expected;
	}

	get matchedTotal() {
		return this.totals.matched;
	}

	get outstandingTotal() {
		return this.totals.outstanding;
	}

	/** Parte de lo esperado que sale de cuotas estimadas: sin recibo de la aseguradora todavía. */
	get hasEstimated() {
		return this.totals.estimated > 0;
	}

	get estimatedTotal() {
		return this.totals.estimated;
	}
}
