import { LightningElement, api, wire } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from "lightning/actions";
import { RefreshEvent } from "lightning/refresh";
import COUNT_FIELD from "@salesforce/schema/PaymentReconciliation__c.inboundPayment__r.reprocessCount__c";
import reprocess from "@salesforce/apex/PaymentReconciliationManualService.reprocess";

export default class ReconciliationManualReprocess extends LightningElement {
	@api recordId;

	notes = "";
	loading = false;
	reprocessCount = 0;

	@wire(getRecord, { recordId: "$recordId", fields: [COUNT_FIELD] })
	wiredRecon({ data }) {
		if (data) {
			this.reprocessCount = getFieldValue(data, COUNT_FIELD) || 0;
		}
	}

	get hasPriorReprocess() {
		return this.reprocessCount > 0;
	}

	get priorReprocessMessage() {
		const times = this.reprocessCount === 1 ? "vez" : "veces";
		return `Este caso ya se reprocesó ${this.reprocessCount} ${times}.`;
	}

	handleNotesChange(event) {
		this.notes = event.target.value;
	}

	get disableReprocess() {
		return this.loading;
	}

	async handleReprocess() {
		this.loading = true;
		try {
			await reprocess({
				reconciliationId: this.recordId,
				notes: this.notes
			});
			this.toast(
				"Reproceso encolado",
				"El motor volverá a intentar la conciliación en unos segundos.",
				"success"
			);
			this.dispatchEvent(new RefreshEvent());
			this.close();
		} catch (e) {
			this.toast("No se pudo reprocesar", this.reduceError(e), "error");
		} finally {
			this.loading = false;
		}
	}

	close() {
		this.dispatchEvent(new CloseActionScreenEvent());
	}

	toast(title, message, variant) {
		this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
	}

	reduceError(e) {
		return (
			(e && e.body && e.body.message) || (e && e.message) || "Error desconocido"
		);
	}
}
