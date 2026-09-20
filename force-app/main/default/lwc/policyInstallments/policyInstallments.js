import { LightningElement, api, wire } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import getInstallmentsByPolicy from "@salesforce/apex/PolicyInstallmentsController.getInstallmentsByPolicy";
import PREMIUM_FIELD from "@salesforce/schema/InsurancePolicy.PremiumAmount";
import { buildRows } from "./installmentRows";

const COLUMNS = [
	{
		label: "Cuota",
		fieldName: "installmentUrl",
		type: "url",
		initialWidth: 190,
		typeAttributes: { label: { fieldName: "sequenceLabel" }, target: "_self" },
		cellAttributes: { class: { fieldName: "statusClass" } }
	},
	{
		label: "Vence",
		fieldName: "dueDate__c",
		type: "date-local",
		initialWidth: 110
	},
	{
		label: "Fecha de pago",
		fieldName: "paymentDate",
		type: "date-local",
		initialWidth: 130
	},
	{
		label: "Esperado",
		fieldName: "expectedAmount__c",
		type: "currency",
		cellAttributes: { alignment: "right" }
	},
	{
		label: "Conciliado",
		fieldName: "matchedAmount__c",
		type: "currency",
		cellAttributes: { alignment: "right" }
	},
	{
		label: "Pendiente",
		fieldName: "outstandingAmount__c",
		type: "currency",
		cellAttributes: { alignment: "right" }
	},
	{
		label: "Estado",
		fieldName: "installmentStatus__c",
		type: "text",
		initialWidth: 120,
		cellAttributes: { class: { fieldName: "statusClass" } }
	},
	{
		label: "Días mora",
		fieldName: "daysOverdue",
		type: "number",
		initialWidth: 100,
		cellAttributes: {
			alignment: "right",
			class: { fieldName: "overdueClass" }
		}
	},
	{
		label: "Recibo",
		fieldName: "carrierReceiptNumber__c",
		type: "text",
		initialWidth: 130,
		cellAttributes: { class: { fieldName: "statusClass" } }
	},
	{ label: "Plan", fieldName: "planName", type: "text", initialWidth: 120 }
];

export default class PolicyInstallments extends LightningElement {
	@api recordId;

	columns = COLUMNS;
	rows = [];
	expandedRows = [];
	totals = { expected: 0, matched: 0, outstanding: 0, count: 0 };
	error;
	loaded = false;

	@wire(getRecord, { recordId: "$recordId", fields: [PREMIUM_FIELD] })
	policy;

	@wire(getInstallmentsByPolicy, { policyId: "$recordId" })
	wiredInstallments({ data, error }) {
		if (data) {
			const built = buildRows(data);
			this.rows = built.rows;
			this.totals = built.totals;
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

	/** Cuotas que esconden recibos reemplazados: son las unicas que se pueden abrir. */
	get expandableIds() {
		return this.rows.filter((row) => row._children).map((row) => row.Id);
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

	get hasRows() {
		return this.rows.length > 0;
	}

	get isEmpty() {
		return this.loaded && !this.error && this.rows.length === 0;
	}

	get cardTitle() {
		return this.hasRows
			? `Cuotas del plan de pago (${this.totals.count})`
			: "Cuotas del plan de pago";
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
}
