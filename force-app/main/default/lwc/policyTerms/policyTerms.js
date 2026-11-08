import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getTermsByPolicy from "@salesforce/apex/PolicyTermsController.getTermsByPolicy";
import { buildRows } from "./termRows";

const COLUMNS = [
	{
		label: "Vigencia",
		fieldName: "policyUrl",
		type: "url",
		initialWidth: 220,
		typeAttributes: { label: { fieldName: "periodLabel" }, target: "_self" },
		cellAttributes: { class: { fieldName: "currentClass" } }
	},
	{
		label: "Número de póliza",
		fieldName: "policyNumber",
		type: "text",
		initialWidth: 170,
		cellAttributes: { class: { fieldName: "currentClass" } }
	},
	{
		label: "Renovación",
		fieldName: "renewalLabel",
		type: "text",
		initialWidth: 230,
		cellAttributes: { class: { fieldName: "renewalClass" } }
	},
	{
		label: "Estado",
		fieldName: "status",
		type: "text",
		initialWidth: 110
	},
	{
		label: "Prima",
		fieldName: "premium",
		type: "currency",
		cellAttributes: { alignment: "right" }
	},
	{
		label: "Pagado",
		fieldName: "paid",
		type: "currency",
		cellAttributes: { alignment: "right" }
	},
	{
		label: "Pendiente",
		fieldName: "outstanding",
		type: "currency",
		cellAttributes: { alignment: "right" }
	},
	{
		label: "Documentos",
		type: "button",
		initialWidth: 150,
		typeAttributes: {
			label: { fieldName: "documentsLabel" },
			name: "documents",
			variant: "base",
			disabled: { fieldName: "hasNoDocuments" }
		}
	}
];

export default class PolicyTerms extends NavigationMixin(LightningElement) {
	@api recordId;

	columns = COLUMNS;
	rows = [];
	error;

	@wire(getTermsByPolicy, { policyId: "$recordId" })
	wiredTerms({ data, error }) {
		if (data) {
			this.rows = buildRows(data);
			this.error = undefined;
		} else if (error) {
			this.error =
				(error.body && error.body.message) ||
				"No se pudieron cargar las vigencias.";
			this.rows = [];
		}
	}

	get hasRows() {
		return this.rows.length > 0;
	}

	get isOnlyTerm() {
		return this.rows.length === 1;
	}

	get cardTitle() {
		return this.hasRows ? `Vigencias (${this.rows.length})` : "Vigencias";
	}

	/** Los documentos de cada vigencia cuelgan de su propia póliza: se abre su lista de archivos. */
	handleRowAction(event) {
		if (event.detail.action.name !== "documents") {
			return;
		}
		this[NavigationMixin.Navigate]({
			type: "standard__recordRelationshipPage",
			attributes: {
				recordId: event.detail.row.policyId,
				objectApiName: "InsurancePolicy",
				relationshipApiName: "AttachedContentDocuments",
				actionName: "view"
			}
		});
	}
}
