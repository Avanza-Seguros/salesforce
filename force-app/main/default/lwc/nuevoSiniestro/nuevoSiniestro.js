// nuevoSiniestro/nuevoSiniestro.js
// Nuevo siniestro (Claim de FSC) en un solo paso: la póliza (o la que se abrió), el asegurado afectado del censo, los
// datos del siniestro (ramo, causa, tipo, fecha, diagnóstico, hospital), la cobertura y, para un reembolso, su primera
// solicitud de pago; al terminar se adjuntan los documentos sin salir de aquí. Reemplaza el botón Nuevo de los
// siniestros (c:nuevoSiniestroOverride) y se abre desde la póliza con su número ya elegido.
import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import CLAIM from '@salesforce/schema/Claim';
import inicio from '@salesforce/apex/SiniestrosController.inicio';
import buscarPolizas from '@salesforce/apex/SiniestrosController.buscarPolizas';
import datosPoliza from '@salesforce/apex/SiniestrosController.datosPoliza';
import buscarAsegurados from '@salesforce/apex/SiniestrosController.buscarAsegurados';
import crearSiniestro from '@salesforce/apex/SiniestrosController.crearSiniestro';

const ESPERA_BUSQUEDA = 350;
const COLUMNAS_ASEGURADOS = [
    { label: 'Asegurado', fieldName: 'nombre' },
    { label: 'Certificado', fieldName: 'certificado', initialWidth: 130 },
    { label: 'Titular o dependiente', fieldName: 'parentesco' },
    { label: 'Estatus', fieldName: 'estatus', initialWidth: 110 }
];

const fechaTxt = (d) => (d ? d.split('-').reverse().join('/') : '');

export default class NuevoSiniestro extends NavigationMixin(LightningElement) {
    // Desde la póliza (acción) llega su Id; como botón Nuevo de los siniestros, nada.
    @api recordId;
    @api objectApiName;

    recordTypeId;
    picklists = {};
    columnasAsegurados = COLUMNAS_ASEGURADOS;

    // Póliza
    textoPoliza = '';
    polizas = [];
    buscandoPolizas = false;
    poliza = null;
    coberturas = [];
    // Asegurado
    textoAsegurado = '';
    asegurados = [];
    buscandoAsegurados = false;
    participanteId = null;
    // Siniestro
    form = { ramo: null, causa: null, tipo: null, fecha: null, diagnostico: '', hospital: '', fechaAtencion: null, medio: null,
        numeroAseguradora: '', observaciones: '', coberturaId: '' };
    conSolicitud = false;
    guardando = false;
    error = '';
    // Resultado
    creado = null;

    connectedCallback() {
        inicio().then((r) => { this.recordTypeId = r.recordTypeId; }).catch((e) => { this.error = this.mensaje(e); });
        if (this.objectApiName === 'InsurancePolicy' && this.recordId) { this.elegirPoliza(this.recordId); }
    }

    @wire(getPicklistValuesByRecordType, { objectApiName: CLAIM, recordTypeId: '$recordTypeId' })
    cargarPicklists({ data }) {
        if (!data) { return; }
        const op = (f) => ((data.picklistFieldValues[f] || {}).values || []).map((v) => ({ label: v.label, value: v.value }));
        this.picklists = { ramo: op('ClaimType'), causa: op('ClaimReasonType'), tipo: op('LossType'), medio: op('FnolChannel') };
    }

    // ===== Póliza =====
    handleBuscarPoliza(e) {
        this.textoPoliza = e.target.value || '';
        clearTimeout(this._tPoliza);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._tPoliza = setTimeout(() => this.buscarPolizas(), ESPERA_BUSQUEDA);
    }
    async buscarPolizas() {
        const t = this.textoPoliza.trim();
        if (t.length < 3) { this.polizas = []; return; }
        this.buscandoPolizas = true;
        try {
            const l = await buscarPolizas({ texto: t });
            if (t !== this.textoPoliza.trim()) { return; }
            this.polizas = l.map((p) => ({ ...p, detalle: this.detallePoliza(p) }));
        } catch (e) {
            this.error = this.mensaje(e);
        } finally {
            this.buscandoPolizas = false;
        }
    }
    detallePoliza(p) {
        return [p.contratante, p.aseguradora, p.ramo, p.inicio ? `${fechaTxt(p.inicio)} al ${fechaTxt(p.fin)}` : '', p.estatus]
            .filter((x) => x).join(' · ');
    }
    handleElegirPoliza(e) { this.elegirPoliza(e.currentTarget.dataset.id); }
    async elegirPoliza(id) {
        this.error = '';
        try {
            const r = await datosPoliza({ policyId: id });
            this.poliza = { ...r.poliza, detalle: this.detallePoliza(r.poliza) };
            this.coberturas = r.coberturas || [];
            this.form = { ...this.form, ramo: r.ramo || this.form.ramo, coberturaId: this.coberturas.length === 1 ? this.coberturas[0].id : '' };
            this.polizas = [];
            this.participanteId = null;
            this.textoAsegurado = '';
            await this.buscarAsegurados();
        } catch (e) {
            this.error = this.mensaje(e);
        }
    }
    cambiarPoliza() {
        this.poliza = null;
        this.asegurados = [];
        this.participanteId = null;
    }
    get sinPoliza() { return !this.poliza; }
    get hayPolizas() { return this.polizas.length > 0; }
    get sinResultadosPoliza() { return !this.buscandoPolizas && this.textoPoliza.trim().length >= 3 && !this.polizas.length; }
    get desdePoliza() { return this.objectApiName === 'InsurancePolicy'; }
    // Abierto desde una póliza, la póliza no se cambia.
    get puedeCambiarPoliza() { return !this.desdePoliza; }

    // ===== Asegurado =====
    handleBuscarAsegurado(e) {
        this.textoAsegurado = e.target.value || '';
        clearTimeout(this._tAsegurado);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._tAsegurado = setTimeout(() => this.buscarAsegurados(), ESPERA_BUSQUEDA);
    }
    async buscarAsegurados() {
        if (!this.poliza) { return; }
        const t = this.textoAsegurado;
        this.buscandoAsegurados = true;
        try {
            const l = await buscarAsegurados({ policyId: this.poliza.id, texto: t });
            if (t !== this.textoAsegurado) { return; }
            this.asegurados = l.map((a) => ({
                ...a,
                parentesco: a.titular ? `Dependiente de ${a.titular}` : 'Titular',
                estatus: a.vigente ? 'Vigente' : 'Baja'
            }));
        } catch (e) {
            this.error = this.mensaje(e);
        } finally {
            this.buscandoAsegurados = false;
        }
    }
    handleElegirAsegurado(e) {
        const sel = e.detail.selectedRows || [];
        this.participanteId = sel.length ? sel[0].id : null;
    }
    get seleccionAsegurado() { return this.participanteId ? [this.participanteId] : []; }
    get aseguradoElegido() { return this.asegurados.find((a) => a.id === this.participanteId); }
    get sinAsegurados() { return !this.buscandoAsegurados && !this.asegurados.length; }

    // ===== Siniestro =====
    handleCampo(e) {
        const campo = e.target.dataset.campo;
        const valor = e.detail.value;
        this.form = { ...this.form, [campo]: valor };
        // Un reembolso trae su solicitud de pago; los demás tipos, solo si se pide.
        if (campo === 'tipo') { this.conSolicitud = valor === 'Reembolso'; }
    }
    handleConSolicitud(e) { this.conSolicitud = e.target.checked; }
    get opcionesCobertura() {
        return [{ label: 'Sin cobertura de la póliza (se usa el tipo de siniestro)', value: '' }]
            .concat(this.coberturas.map((c) => ({ label: c.nombre, value: c.id })));
    }
    get fechaMin() { return this.poliza ? this.poliza.inicio : null; }
    get fechaMax() { return this.poliza ? this.poliza.fin : null; }

    // ===== Guardar =====
    async guardar() {
        this.error = '';
        if (!this.poliza) { this.error = 'Elige la póliza.'; return; }
        if (!this.participanteId) { this.error = 'Elige al asegurado afectado.'; return; }
        const campos = [...this.template.querySelectorAll('.siniestro lightning-input, .siniestro lightning-combobox, .siniestro lightning-textarea')];
        if (!campos.reduce((v, c) => c.reportValidity() && v, true)) { return; }
        let solicitud = null;
        if (this.conSolicitud) {
            solicitud = this.template.querySelector('c-datos-solicitud-pago').valores();
            if (!solicitud) { return; }
        }
        this.guardando = true;
        try {
            const r = await crearSiniestro({ datosJson: JSON.stringify({
                ...this.form, coberturaId: this.form.coberturaId || null, policyId: this.poliza.id,
                participanteId: this.participanteId, solicitud
            }) });
            this.creado = r;
            this.dispatchEvent(new ShowToastEvent({ title: 'Siniestro', variant: 'success', message: `Se registró el siniestro ${r.folio}.` }));
        } catch (e) {
            this.error = this.mensaje(e);
        } finally {
            this.guardando = false;
        }
    }
    get destinoArchivos() { return this.creado ? (this.creado.solicitudId || this.creado.claimId) : null; }
    get textoArchivos() {
        return this.creado && this.creado.solicitudId ? 'Adjunta los documentos del reembolso (facturas, informe médico, estudios…).'
            : 'Adjunta los documentos del siniestro.';
    }
    handleArchivos(e) {
        const n = (e.detail.files || []).length;
        this.dispatchEvent(new ShowToastEvent({ title: 'Documentos', variant: 'success', message: `${n} archivo(s) adjuntado(s).` }));
    }
    abrirSiniestro() {
        const id = this.creado.claimId;
        if (this.desdePoliza) { this.dispatchEvent(new CloseActionScreenEvent()); }
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: id, objectApiName: 'Claim', actionName: 'view' } });
    }
    otro() {
        this.creado = null;
        this.participanteId = null;
        this.form = { ...this.form, tipo: null, causa: null, fecha: null, diagnostico: '', hospital: '', fechaAtencion: null,
            numeroAseguradora: '', observaciones: '' };
        this.conSolicitud = false;
    }
    cancelar() {
        if (this.desdePoliza) { this.dispatchEvent(new CloseActionScreenEvent()); return; }
        this[NavigationMixin.Navigate]({ type: 'standard__objectPage', attributes: { objectApiName: 'Claim', actionName: 'home' } });
    }
    get enCaptura() { return !this.creado; }

    mensaje(e) { return (e && e.body && e.body.message) || (e && e.message) || 'Ocurrió un error.'; }
}
