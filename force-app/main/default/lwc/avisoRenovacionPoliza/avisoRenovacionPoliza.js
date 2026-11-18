/**
 * Botón «Enviar aviso de renovación» de la póliza (acción sin pantalla): envía en ese momento el aviso con la
 * plantilla Aviso Renovación Póliza y avisa a quién se mandó.
 */
import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import enviarAviso from '@salesforce/apex/AvisoRenovacionPoliza.enviarAviso';

export default class AvisoRenovacionPoliza extends LightningElement {
    @api recordId;
    enviando = false;

    @api async invoke() {
        if (this.enviando) { return; }
        this.enviando = true;
        try {
            const para = await enviarAviso({ policyId: this.recordId });
            this.toast('Aviso de renovación enviado', `Se envió a ${para}. Quedó registrado como tarea en la póliza.`, 'success');
        } catch (e) {
            const msg = (e && e.body && e.body.message) || (e && e.message) || 'No se pudo enviar el aviso.';
            this.toast('No se envió el aviso', msg, 'error');
        } finally {
            this.enviando = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
