import { LightningElement } from "lwc";
import TIME_ZONE from "@salesforce/i18n/timeZone";
import getPage from "@salesforce/apex/AllPoliciesController.getPage";
import getTotal from "@salesforce/apex/AllPoliciesController.getTotal";
import getFilterOptions from "@salesforce/apex/AllPoliciesController.getFilterOptions";
import {
	PAGE_SIZE,
	SEARCH_DELAY_MS,
	SORT_FIELD_BY_COLUMN,
	buildRow,
	columnForSortField,
	cursorFor,
	errorMessage,
	formatCount
} from "./policyRows";

const DEFAULT_SORT_FIELD = "Name";

const RIGHT = { alignment: "right" };

const COLUMNS = [
	{
		label: "Número de póliza",
		fieldName: "policyUrl",
		type: "url",
		sortable: true,
		initialWidth: 160,
		typeAttributes: { label: { fieldName: "policyNumber" }, target: "_self" }
	},
	{ label: "Aseguradora", fieldName: "carrierName", initialWidth: 160 },
	{ label: "Ramo", fieldName: "ramoLabel", sortable: true, initialWidth: 140 },
	{ label: "Asegurado", fieldName: "insuredName", initialWidth: 220 },
	{
		label: "Frecuencia de pago",
		fieldName: "frequencyLabel",
		sortable: true,
		initialWidth: 140
	},
	{
		label: "Inicio de vigencia",
		fieldName: "effectiveLabel",
		sortable: true,
		initialWidth: 130
	},
	{
		label: "Fin de vigencia",
		fieldName: "expirationLabel",
		sortable: true,
		initialWidth: 130
	},
	{
		label: "Prima",
		fieldName: "premiumLabel",
		sortable: true,
		initialWidth: 140,
		cellAttributes: RIGHT
	},
	{
		label: "Estado",
		fieldName: "statusLabel",
		sortable: true,
		initialWidth: 110
	},
	{
		label: "Asegurado o bien",
		fieldName: "insuredSubject",
		sortable: true,
		initialWidth: 260,
		wrapText: false
	},
	{
		label: "Fecha de creación",
		fieldName: "createdLabel",
		sortable: true,
		initialWidth: 130
	}
];

export default class AllPolicies extends LightningElement {
	columns = COLUMNS;
	rows = [];
	total = null;
	error;
	isLoading = false;
	hasMore = true;

	searchTerm = "";
	carrierId = "";
	status = "";
	sortField = DEFAULT_SORT_FIELD;
	sortDirection = "asc";

	carrierOptions = [{ label: "Todas", value: "" }];
	statusOptions = [{ label: "Todos", value: "" }];
	picklistLabels = {};

	searchTimer;
	// Cada reinicio invalida las respuestas que aún estén en camino.
	requestId = 0;

	connectedCallback() {
		this.loadOptions();
		this.reload();
	}

	disconnectedCallback() {
		clearTimeout(this.searchTimer);
	}

	get sortedBy() {
		return columnForSortField(this.sortField);
	}

	get headerTitle() {
		if (this.total === null) {
			return "Todas las pólizas";
		}
		return `${formatCount(this.total)} ${this.total === 1 ? "póliza" : "pólizas"}`;
	}

	get loadedLabel() {
		const loaded = formatCount(this.rows.length);
		if (this.isLoading && this.hasMore) {
			return `${loaded} cargadas · cargando más…`;
		}
		return this.hasMore
			? `${loaded} cargadas · baja para ver más`
			: `${loaded} cargadas · todas a la vista`;
	}

	get isEmpty() {
		return !this.isLoading && !this.error && this.rows.length === 0;
	}

	get hasFilters() {
		return Boolean(this.searchTerm || this.carrierId || this.status);
	}

	get clearDisabled() {
		return !this.hasFilters;
	}

	async loadOptions() {
		try {
			const options = await getFilterOptions();
			this.picklistLabels = options.picklistLabels || {};
			this.carrierOptions = [
				{ label: "Todas", value: "" },
				...(options.carriers || [])
			];
			this.statusOptions = [
				{ label: "Todos", value: "" },
				...(options.statuses || [])
			];
			// Las filas que ya llegaron se vuelven a pintar con las etiquetas.
			this.rows = this.rows.map((row) =>
				buildRow(row.record, this.picklistLabels, TIME_ZONE)
			);
		} catch (error) {
			this.error = errorMessage(error);
		}
	}

	reload() {
		this.requestId += 1;
		this.rows = [];
		this.hasMore = true;
		this.error = undefined;
		this.loadTotal(this.requestId);
		this.loadNextPage();
	}

	async loadTotal(requestId) {
		this.total = null;
		try {
			const total = await getTotal(this.filterParams());
			if (requestId === this.requestId) {
				this.total = total;
			}
		} catch (error) {
			if (requestId === this.requestId) {
				this.error = errorMessage(error);
			}
		}
	}

	filterParams() {
		return {
			searchTerm: this.searchTerm || null,
			carrierId: this.carrierId || null,
			status: this.status || null
		};
	}

	async loadNextPage() {
		if (this.isLoading || !this.hasMore) {
			return;
		}
		const requestId = this.requestId;
		const last = this.rows.length
			? this.rows[this.rows.length - 1].record
			: null;
		this.isLoading = true;
		try {
			const page = await getPage({
				sortField: this.sortField,
				sortDirection: this.sortDirection.toUpperCase(),
				...this.filterParams(),
				...cursorFor(last, this.sortField),
				pageSize: PAGE_SIZE
			});
			if (requestId !== this.requestId) {
				return;
			}
			const known = new Set(this.rows.map((row) => row.Id));
			const fresh = (page || [])
				.filter((policy) => !known.has(policy.Id))
				.map((policy) => buildRow(policy, this.picklistLabels, TIME_ZONE));
			this.rows = [...this.rows, ...fresh];
			this.hasMore = (page || []).length === PAGE_SIZE;
		} catch (error) {
			if (requestId === this.requestId) {
				this.error = errorMessage(error);
				this.hasMore = false;
			}
		} finally {
			this.isLoading = false;
			if (requestId !== this.requestId) {
				// La respuesta era de una carga anterior: se pide la primera página de la nueva.
				this.loadNextPage();
			}
		}
	}

	handleLoadMore() {
		this.loadNextPage();
	}

	handleSort(event) {
		const { fieldName, sortDirection } = event.detail;
		const sortField = SORT_FIELD_BY_COLUMN[fieldName];
		if (!sortField) {
			return;
		}
		this.sortField = sortField;
		this.sortDirection = sortDirection === "desc" ? "desc" : "asc";
		this.reload();
	}

	handleSearchChange(event) {
		const value = (event.detail.value || "").trim();
		clearTimeout(this.searchTimer);
		// eslint-disable-next-line @lwc/lwc/no-async-operation
		this.searchTimer = setTimeout(() => {
			if (value !== this.searchTerm) {
				this.searchTerm = value;
				this.reload();
			}
		}, SEARCH_DELAY_MS);
	}

	handleCarrierChange(event) {
		this.carrierId = event.detail.value;
		this.reload();
	}

	handleStatusChange(event) {
		this.status = event.detail.value;
		this.reload();
	}

	handleClear() {
		clearTimeout(this.searchTimer);
		this.searchTerm = "";
		this.carrierId = "";
		this.status = "";
		const search = this.template.querySelector("lightning-input");
		if (search) {
			search.value = "";
		}
		this.reload();
	}
}
