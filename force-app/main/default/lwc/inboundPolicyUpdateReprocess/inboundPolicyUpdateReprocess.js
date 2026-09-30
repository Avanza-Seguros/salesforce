import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import reprocess from "@salesforce/apex/InboundPolicyApplyService.reprocess";

const TITLE = "Comunicación de póliza";

// Accion sin pantalla: vuelve a procesar una comunicacion de poliza que esta en revision
// manual y muestra el resultado.
export default class InboundPolicyUpdateReprocess extends LightningElement {
	@api recordId;

	@api async invoke() {
		try {
			const message = await reprocess({ updateId: this.recordId });
			const variant = message.startsWith("Sigue sin") ? "warning" : "success";
			this.dispatchEvent(
				new ShowToastEvent({ title: TITLE, message, variant })
			);
			await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
		} catch (error) {
			const message =
				(error && error.body && error.body.message) ||
				"No se pudo reprocesar la comunicación.";
			this.dispatchEvent(
				new ShowToastEvent({ title: TITLE, message, variant: "error" })
			);
		}
	}
}
