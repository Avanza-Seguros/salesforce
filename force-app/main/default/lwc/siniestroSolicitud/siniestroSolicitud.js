// siniestroSolicitud/siniestroSolicitud.js
// Acción «Reembolso complementario» del siniestro: otra solicitud de pago (folio SIN-00001-02…) para el mismo asegurado,
// con su monto reclamado y su documentación; después se adjuntan sus documentos sin salir de la acción.
import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import datosSiniestro from '@salesforce/apex/SiniestrosController.datosSiniestro';
import crearSolicitud from '@salesforce/apex/SiniestrosController.crearSolicitud';

export default class SiniestroSolicitud extends LightningElement {
    _recordId;
    siniestro = null;
    guardando = false;
    error = '';
    creada = null;

    @api
    get recordId() { return this._recordId; }
    set recordId(v) {
        this._recordId = v;
        if (v) {
            datosSiniestro({ claimId: v }).then((r) => { this.siniestro = r; }).catch((e) => { this.error = this.mensaje(e); });
        }
    }

    get titulo() { return this.siniestro ? `Reembolso complementario · ${this.siniestro.folio}` : 'Reembolso complementario'; }
    get anteriores() {
        const n = this.siniestro ? this.siniestro.solicitudes.length : 0;
        return n ? `El siniestro tiene ${n} ${n === 1 ? 'solicitud' : 'solicitudes'} de pago; esta será la siguiente.` : 'Será la primera solicitud de pago del siniestro.';
    }
    get cerrado() { return this.siniestro && this.siniestro.cerrado; }
    get enCaptura() { return !this.creada; }

    async guardar() {
        this.error = '';
        const datos = this.template.querySelector('c-datos-solicitud-pago').valores();
        if (!datos) { return; }
        this.guardando = true;
        try {
            this.creada = await crearSolicitud({ claimId: this._recordId, datosJson: JSON.stringify(datos) });
            notifyRecordUpdateAvailable([{ recordId: this._recordId }]);
            this.dispatchEvent(new ShowToastEvent({ title: 'Reembolso', variant: 'success', message: `Se registró la solicitud ${this.creada.folio}.` }));
        } catch (e) {
            this.error = this.mensaje(e);
        } finally {
            this.guardando = false;
        }
    }
    handleArchivos(e) {
        const n = (e.detail.files || []).length;
        this.dispatchEvent(new ShowToastEvent({ title: 'Documentos', variant: 'success', message: `${n} archivo(s) adjuntado(s).` }));
    }
    cerrar() { this.dispatchEvent(new CloseActionScreenEvent()); }

    mensaje(e) { return (e && e.body && e.body.message) || (e && e.message) || 'Ocurrió un error.'; }
}
