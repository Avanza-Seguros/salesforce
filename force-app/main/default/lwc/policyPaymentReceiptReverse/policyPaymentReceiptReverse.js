import { LightningElement, api, wire } from "lwc";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from "lightning/actions";
import { RefreshEvent } from "lightning/refresh";
import RECEIPT_OBJECT from "@salesforce/schema/PolicyPaymentReceipt__c";
import REVERSAL_REASON_FIELD from "@salesforce/schema/PolicyPaymentReceipt__c.reversalReason__c";
import reverse from "@salesforce/apex/PolicyPaymentReceiptReversalService.reverse";

export default class PolicyPaymentReceiptReverse extends LightningElement {
	@api recordId;

	reversalReason;
	notes = "";
	loading = false;
	reasonOptions = [];

	@wire(getObjectInfo, { objectApiName: RECEIPT_OBJECT })
	objectInfo;

	@wire(getPicklistValues, {
		recordTypeId: "$objectInfo.data.defaultRecordTypeId",
		fieldApiName: REVERSAL_REASON_FIELD
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
		this.reversalReason = event.detail.value;
	}

	handleNotesChange(event) {
		this.notes = event.target.value;
	}

	get disableReverse() {
		return this.loading || !this.reversalReason || !this.notes.trim();
	}

	async handleReverse() {
		this.loading = true;
		try {
			await reverse({
				receiptId: this.recordId,
				reversalReason: this.reversalReason,
				notes: this.notes
			});
			this.toast(
				"Recibo reversado",
				"El cobro dejó de ser válido. La cuota vuelve a estar abierta y el caso regresa a la bandeja de revisión.",
				"success"
			);
			this.dispatchEvent(new RefreshEvent());
			this.close();
		} catch (e) {
			this.toast("No se pudo reversar", this.reduceError(e), "error");
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
