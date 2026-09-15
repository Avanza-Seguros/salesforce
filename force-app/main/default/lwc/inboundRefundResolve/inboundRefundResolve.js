import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from "lightning/actions";
import { RefreshEvent } from "lightning/refresh";
import getInstallmentOptions from "@salesforce/apex/InboundRefundService.getInstallmentOptions";
import resolve from "@salesforce/apex/InboundRefundService.resolve";

const RESOLUTION_INSTALLMENT = "CUOTA";

export default class InboundRefundResolve extends LightningElement {
	_recordId;
	resolution;
	installmentId;
	notes = "";
	loading = false;
	installmentOptions = [];

	resolutionOptions = [
		{ label: "Devolución de una cuota", value: RESOLUTION_INSTALLMENT },
		{ label: "Devolución sin cuota", value: "SIN_CUOTA" },
		{ label: "Sin efecto", value: "SIN_EFECTO" }
	];

	// En las acciones rápidas el Id del registro llega después de crear el componente, así
	// que las cuotas se cargan cuando llega y no al conectarse.
	@api
	get recordId() {
		return this._recordId;
	}
	set recordId(value) {
		this._recordId = value;
		if (value) {
			this.loadInstallments();
		}
	}

	async loadInstallments() {
		try {
			const options = await getInstallmentOptions({ refundId: this._recordId });
			this.installmentOptions = (options || []).map((o) => ({
				label: o.label,
				value: o.value
			}));
		} catch (e) {
			this.toast(
				"No se pudieron cargar las cuotas",
				this.reduceError(e),
				"error"
			);
		}
	}

	get isInstallment() {
		return this.resolution === RESOLUTION_INSTALLMENT;
	}

	get hasInstallments() {
		return this.installmentOptions.length > 0;
	}

	get disableResolve() {
		return (
			this.loading ||
			!this.resolution ||
			!this.notes.trim() ||
			(this.isInstallment && !this.installmentId)
		);
	}

	handleResolutionChange(event) {
		this.resolution = event.detail.value;
	}

	handleInstallmentChange(event) {
		this.installmentId = event.detail.value;
	}

	handleNotesChange(event) {
		this.notes = event.target.value;
	}

	async handleResolve() {
		this.loading = true;
		try {
			await resolve({
				refundId: this._recordId,
				resolution: this.resolution,
				installmentId: this.isInstallment ? this.installmentId : null,
				notes: this.notes
			});
			this.toast(
				"Devolución resuelta",
				"La devolución quedó resuelta y salió de la bandeja de revisión.",
				"success"
			);
			this.dispatchEvent(new RefreshEvent());
			this.close();
		} catch (e) {
			this.toast("No se pudo resolver", this.reduceError(e), "error");
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
