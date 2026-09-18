import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import reprocessNotice from "@salesforce/apex/PolicyCarrierStatusService.reprocessNotice";

const TITLE = "Estado de póliza";

// Accion sin pantalla: vuelve a evaluar una comunicacion de estado de poliza que esta en
// revision manual y muestra el resultado.
export default class InboundPolicyStatusReprocess extends LightningElement {
	@api recordId;

	@api async invoke() {
		try {
			const message = await reprocessNotice({ inboundId: this.recordId });
			this.dispatchEvent(
				new ShowToastEvent({ title: TITLE, message, variant: "success" })
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
