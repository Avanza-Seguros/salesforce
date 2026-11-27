// datosSolicitudPago/datosSolicitudPago.js
// Datos de una solicitud de pago de un siniestro (PaymentRequest: el folio de un reembolso, inicial o complementario):
// fecha en que se recibió, monto reclamado, documentación entregada, proveedor y número de referencia. Lo usan
// c-nuevo-siniestro (primera solicitud) y c-siniestro-solicitud (reembolso complementario).
import { LightningElement, api, wire } from 'lwc';
import { getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import PAYMENT_REQUEST from '@salesforce/schema/PaymentRequest';

// Tipo de registro maestro (PaymentRequest no tiene tipos de registro propios).
const MAESTRO = '012000000000000AAA';
// Fecha de hoy en la hora local (toISOString daría la de UTC: de noche, el día siguiente).
const hoy = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; };

export default class DatosSolicitudPago extends LightningElement {
    fechaRecepcion = hoy();
    monto = null;
    documentacion = [];
    proveedorId = null;
    referencia = '';
    opcionesDocumentacion = [];

    @wire(getPicklistValuesByRecordType, { objectApiName: PAYMENT_REQUEST, recordTypeId: MAESTRO })
    picklists({ data }) {
        const f = data && data.picklistFieldValues && data.picklistFieldValues.Documentacion_Ingresada__c;
        this.opcionesDocumentacion = f ? f.values.map((v) => ({ label: v.label, value: v.value })) : [];
    }

    handleCampo(e) {
        const campo = e.target.dataset.campo;
        this[campo] = e.detail.value;
    }
    handleProveedor(e) { this.proveedorId = e.detail.recordId || null; }

    // Valida los campos y regresa los datos (null si falta algo).
    @api
    valores() {
        const campos = [...this.template.querySelectorAll('lightning-input')];
        const ok = campos.reduce((v, c) => c.reportValidity() && v, true);
        if (!ok) { return null; }
        return {
            fechaRecepcion: this.fechaRecepcion || null,
            monto: this.monto === null || this.monto === '' ? null : Number(this.monto),
            documentacion: (this.documentacion || []).join(';'),
            proveedorId: this.proveedorId,
            referencia: this.referencia || null
        };
    }
}
