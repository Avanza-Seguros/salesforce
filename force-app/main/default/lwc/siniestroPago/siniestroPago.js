// siniestroPago/siniestroPago.js
// Acción «Registrar pago» del siniestro: lo que pagó la aseguradora a una de sus solicitudes de pago (monto, fecha y
// número de transferencia o cheque). La solicitud queda Pagada y el siniestro suma su total pagado.
import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import datosSiniestro from '@salesforce/apex/SiniestrosController.datosSiniestro';
import registrarPago from '@salesforce/apex/SiniestrosController.registrarPago';

// Fecha de hoy en la hora local (toISOString daría la de UTC: de noche, el día siguiente).
const hoy = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; };
const moneda = (v) => (v === null || v === undefined ? '—'
    : new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN' }).format(v));

export default class SiniestroPago extends LightningElement {
    _recordId;
    siniestro = null;
    solicitudId = null;
    monto = null;
    fecha = hoy();
    identificador = '';
    guardando = false;
    error = '';

    @api
    get recordId() { return this._recordId; }
    set recordId(v) {
        this._recordId = v;
        if (v) { this.cargar(); }
    }
    async cargar() {
        try {
            this.siniestro = await datosSiniestro({ claimId: this._recordId });
            // Propone la primera solicitud sin pagar.
            const pendiente = this.solicitudes.find((s) => s.estatus !== 'Pagado') || this.solicitudes[0];
            if (pendiente) { this.elegir(pendiente.id); }
        } catch (e) {
            this.error = this.mensaje(e);
        }
    }
    get solicitudes() { return (this.siniestro && this.siniestro.solicitudes) || []; }
    get haySolicitudes() { return this.solicitudes.length > 0; }
    get titulo() { return this.siniestro ? `Registrar pago · ${this.siniestro.folio}` : 'Registrar pago'; }
    get opciones() {
        return this.solicitudes.map((s) => ({
            label: `${s.nombre} · ${s.estatus || 'Recibido'} · reclamado ${moneda(s.reclamado)}${s.pagado ? ` · pagado ${moneda(s.pagado)}` : ''}`,
            value: s.id
        }));
    }
    elegir(id) {
        this.solicitudId = id;
        const s = this.solicitudes.find((x) => x.id === id);
        // Propone lo que falta por pagar de lo reclamado.
        this.monto = s && s.reclamado ? Math.max(0, s.reclamado - (s.pagado || 0)) : null;
    }
    handleSolicitud(e) { this.elegir(e.detail.value); }
    handleCampo(e) { this[e.target.dataset.campo] = e.detail.value; }

    async guardar() {
        this.error = '';
        const campos = [...this.template.querySelectorAll('lightning-input, lightning-combobox')];
        if (!campos.reduce((v, c) => c.reportValidity() && v, true)) { return; }
        this.guardando = true;
        try {
            await registrarPago({ claimId: this._recordId, datosJson: JSON.stringify({
                solicitudId: this.solicitudId, monto: Number(this.monto), fecha: this.fecha, identificador: this.identificador || null
            }) });
            notifyRecordUpdateAvailable([{ recordId: this._recordId }]);
            this.dispatchEvent(new ShowToastEvent({ title: 'Pago', variant: 'success', message: `Se registró el pago de ${moneda(Number(this.monto))}.` }));
            this.cerrar();
        } catch (e) {
            this.error = this.mensaje(e);
        } finally {
            this.guardando = false;
        }
    }
    cerrar() { this.dispatchEvent(new CloseActionScreenEvent()); }

    mensaje(e) { return (e && e.body && e.body.message) || (e && e.message) || 'Ocurrió un error.'; }
}
