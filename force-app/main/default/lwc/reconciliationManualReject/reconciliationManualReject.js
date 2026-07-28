import { LightningElement, api, wire } from "lwc";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from "lightning/actions";
import { RefreshEvent } from "lightning/refresh";
import RECON_OBJECT from "@salesforce/schema/PaymentReconciliation__c";
import REJECTED_REASON_FIELD from "@salesforce/schema/PaymentReconciliation__c.rejectedReason__c";
import reject from "@salesforce/apex/PaymentReconciliationManualService.reject";

export default class ReconciliationManualReject extends LightningElement {
	@api recordId;

	rejectedReason;
	notes = "";
	loading = false;
	reasonOptions = [];

	@wire(getObjectInfo, { objectApiName: RECON_OBJECT })
	objectInfo;

	@wire(getPicklistValues, {
		recordTypeId: "$objectInfo.data.defaultRecordTypeId",
		fieldApiName: REJECTED_REASON_FIELD
	})
	wiredReasons({ data }) {
		if (data) {
			this.reasonOptions = data.values.map((v) => ({
				label: v.label,
				value: v.value
			}));
		}
	}

	handleReasonChange(event) {
		this.rejectedReason = event.detail.value;
	}

	handleNotesChange(event) {
		this.notes = event.target.value;
	}

	get disableReject() {
		return this.loading || !this.rejectedReason || !this.notes.trim();
	}

	async handleReject() {
		this.loading = true;
		try {
			await reject({
				reconciliationId: this.recordId,
				rejectedReason: this.rejectedReason,
				notes: this.notes
			});
			this.toast(
				"Conciliación rechazada",
				"El caso quedó cerrado como Rechazado.",
				"success"
			);
			this.dispatchEvent(new RefreshEvent());
			this.close();
		} catch (e) {
			this.toast("No se pudo rechazar", this.reduceError(e), "error");
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
