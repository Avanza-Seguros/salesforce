import { LightningElement, api, wire } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from "lightning/actions";
import { RefreshEvent } from "lightning/refresh";
import POLICY_FIELD from "@salesforce/schema/PaymentReconciliation__c.insurancePolicy__c";
import STATUS_FIELD from "@salesforce/schema/PaymentReconciliation__c.reconciliationStatus__c";
import getOpenInstallments from "@salesforce/apex/PaymentReconciliationManualService.getOpenInstallments";
import approve from "@salesforce/apex/PaymentReconciliationManualService.approve";

export default class ReconciliationManualApprove extends LightningElement {
	@api recordId;

	policyId;
	installmentId;
	notes = "";
	installmentOptions = [];
	loading = false;

	@wire(getRecord, {
		recordId: "$recordId",
		fields: [POLICY_FIELD, STATUS_FIELD]
	})
	wiredRecon({ data }) {
		if (data) {
			const pol = getFieldValue(data, POLICY_FIELD);
			if (pol && !this.policyId) {
				this.policyId = pol;
				this.loadInstallments();
			}
		}
	}

	handlePolicyChange(event) {
		this.policyId = event.detail && event.detail.recordId;
		this.installmentId = undefined;
		this.loadInstallments();
	}

	async loadInstallments() {
		if (!this.policyId) {
			this.installmentOptions = [];
			return;
		}
		try {
			const rows = await getOpenInstallments({ policyId: this.policyId });
			this.installmentOptions = (rows || []).map((i) => ({
				label: `#${i.sequenceNumber__c} · vence ${i.dueDate__c} · $${i.expectedAmount__c} · ${i.installmentStatus__c}`,
				value: i.Id
			}));
		} catch (e) {
			this.installmentOptions = [];
			this.toast("Error al cargar cuotas", this.reduceError(e), "error");
		}
	}

	handleInstallmentChange(event) {
		this.installmentId = event.detail.value;
	}

	handleNotesChange(event) {
		this.notes = event.target.value;
	}

	get disableApprove() {
		return this.loading || !this.policyId || !this.installmentId;
	}

	get noInstallments() {
		return this.policyId && this.installmentOptions.length === 0;
	}

	async handleApprove() {
		this.loading = true;
		try {
			await approve({
				reconciliationId: this.recordId,
				finalPolicyId: this.policyId,
				finalInstallmentId: this.installmentId,
				notes: this.notes
			});
			this.toast(
				"Conciliación aprobada",
				"Se aprobó manualmente. El recibo se genera en unos segundos.",
				"success"
			);
			this.dispatchEvent(new RefreshEvent());
			this.close();
		} catch (e) {
			this.toast("No se pudo aprobar", this.reduceError(e), "error");
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
