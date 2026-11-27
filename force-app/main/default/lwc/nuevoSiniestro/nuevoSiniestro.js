// nuevoSiniestro/nuevoSiniestro.js
// Nuevo siniestro (Claim de FSC) en un solo paso: la póliza (o la que se abrió), lo afectado, los datos del siniestro
// (ramo, causa, tipo, fecha y descripción), la cobertura y, si aplica, su primera solicitud de pago; al terminar se
// adjuntan los documentos sin salir de aquí. Lo afectado depende del ramo de la póliza, como sus pestañas:
// - Personas (Asegurados): el asegurado del censo, titular o dependiente; diagnóstico, hospital y fecha de atención.
// - Automóviles (Vehículos) y Daños (Ubicaciones): el bien de la póliza; descripción del daño y lugar del siniestro.
// Reemplaza el botón Nuevo de los siniestros (c:nuevoSiniestroOverride); desde la póliza se abre en una ventana
// (c-siniestro-modal) con la póliza fija y, desde un renglón de Asegurados, Vehículos o Ubicaciones, con lo afectado
// ya elegido.
import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import CLAIM from '@salesforce/schema/Claim';
import buscarPolizas from '@salesforce/apex/SiniestrosController.buscarPolizas';
import datosPoliza from '@salesforce/apex/SiniestrosController.datosPoliza';
import buscarAsegurados from '@salesforce/apex/SiniestrosController.buscarAsegurados';
import buscarBienes from '@salesforce/apex/SiniestrosController.buscarBienes';
import crearSiniestro from '@salesforce/apex/SiniestrosController.crearSiniestro';

const ESPERA_BUSQUEDA = 350;
const COLUMNAS_ASEGURADOS = [
    { label: 'Asegurado', fieldName: 'nombre' },
    { label: 'Certificado', fieldName: 'certificado', initialWidth: 130 },
    { label: 'Titular o dependiente', fieldName: 'parentesco' },
    { label: 'Estatus', fieldName: 'estatus', initialWidth: 110 }
];
const COLUMNAS_BIENES = {
    autos: [
        { label: 'Vehículo', fieldName: 'nombre' },
        { label: 'Inciso, modelo, serie y placas', fieldName: 'detalle' },
        { label: 'Estatus', fieldName: 'estatus', initialWidth: 110 }
    ],
    danos: [
        { label: 'Ubicación', fieldName: 'nombre' },
        { label: 'Detalle', fieldName: 'detalle' },
        { label: 'Estatus', fieldName: 'estatus', initialWidth: 110 }
    ]
};
const SUBTITULOS = {
    personas: 'Siniestro de personas: Gastos médicos mayores, Vida y Accidentes personales.',
    autos: 'Siniestro de automóviles: el vehículo de la póliza.',
    danos: 'Siniestro de daños: la ubicación de la póliza.'
};
const FORM_VACIO = { ramo: null, causa: null, tipo: null, fecha: null, diagnostico: '', hospital: '', fechaAtencion: null, lugar: '',
    medio: null, numeroAseguradora: '', observaciones: '', coberturaId: '', correo: '' };

const fechaTxt = (d) => (d ? d.split('-').reverse().join('/') : '');

export default class NuevoSiniestro extends NavigationMixin(LightningElement) {
    // Como acción de la póliza llega su Id; como botón Nuevo de los siniestros, nada.
    @api recordId;
    @api objectApiName;
    // En la ventana de la póliza: la póliza fija y, desde un renglón, el asegurado o el bien (o su inciso) ya elegido.
    @api policyId;
    @api participanteId;
    @api bienId;
    @api enModal = false;

    recordTypeId;
    familia = 'personas';
    picklists = {};
    columnasAsegurados = COLUMNAS_ASEGURADOS;

    // Póliza
    textoPoliza = '';
    polizas = [];
    buscandoPolizas = false;
    poliza = null;
    coberturas = [];
    // Lo afectado: asegurado (personas) o bien (vehículo o ubicación)
    texto = '';
    opciones = [];
    buscando = false;
    elegidoId = null;
    preElegido = null;
    // Siniestro
    form = { ...FORM_VACIO };
    // Correo para avisos: se propone el del titular (o el del contratante en un bien) hasta que el ejecutivo lo cambie.
    correoContratante = '';
    correoEditado = false;
    conSolicitud = false;
    guardando = false;
    error = '';
    // Resultado
    creado = null;

    connectedCallback() {
        this.preElegido = this.participanteId || this.bienId || null;
        const fija = this.polizaFija;
        if (fija) { this.elegirPoliza(fija); }
    }

    @wire(getPicklistValuesByRecordType, { objectApiName: CLAIM, recordTypeId: '$recordTypeId' })
    cargarPicklists({ data }) {
        if (!data) { return; }
        const op = (f) => ((data.picklistFieldValues[f] || {}).values || []).map((v) => ({ label: v.label, value: v.value }));
        this.picklists = { ramo: op('ClaimType'), causa: op('ClaimReasonType'), tipo: op('LossType'), medio: op('FnolChannel') };
        // Un ramo con un solo valor (Automóviles, Daños) queda elegido.
        if (!this.form.ramo && this.picklists.ramo.length === 1) { this.form = { ...this.form, ramo: this.picklists.ramo[0].value }; }
    }

    // ===== Póliza =====
    // Póliza que no se cambia: la de la ventana de la póliza o la de la acción de la póliza.
    get polizaFija() {
        if (this.policyId) { return this.policyId; }
        return this.objectApiName === 'InsurancePolicy' && this.recordId ? this.recordId : null;
    }
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
            // Cambiar de familia cambia el tipo de registro y sus listas.
            if (r.familia !== this.familia || r.recordTypeId !== this.recordTypeId) {
                this.picklists = {};
                this.form = { ...this.form, ramo: null, causa: null, tipo: null };
            }
            this.familia = r.familia || 'personas';
            this.recordTypeId = r.recordTypeId;
            this.correoContratante = r.correoContratante || '';
            this.form = { ...this.form, ramo: r.ramo || this.form.ramo, coberturaId: '' };
            this.polizas = [];
            this.elegidoId = null;
            this.texto = '';
            await this.buscar();
            this.ajustarCobertura();
            this.sugerirCorreo();
        } catch (e) {
            this.error = this.mensaje(e);
        }
    }
    cambiarPoliza() {
        this.poliza = null;
        this.opciones = [];
        this.elegidoId = null;
        this.preElegido = null;
    }
    get sinPoliza() { return !this.poliza; }
    get hayPolizas() { return this.polizas.length > 0; }
    get sinResultadosPoliza() { return !this.buscandoPolizas && this.textoPoliza.trim().length >= 3 && !this.polizas.length; }
    get puedeCambiarPoliza() { return !this.polizaFija; }
    get mostrarEncabezado() { return !this.enModal; }
    get subtitulo() { return SUBTITULOS[this.familia] || SUBTITULOS.personas; }

    // ===== Lo afectado =====
    get esPersonas() { return this.familia === 'personas'; }
    get esBien() { return !this.esPersonas; }
    get tituloAfectado() {
        if (this.familia === 'autos') { return 'Vehículo afectado'; }
        if (this.familia === 'danos') { return 'Ubicación afectada'; }
        return 'Asegurado afectado';
    }
    get placeholderAfectado() {
        if (this.familia === 'autos') { return 'Descripción, inciso, serie o placas'; }
        if (this.familia === 'danos') { return 'Nombre o domicilio de la ubicación'; }
        return 'Nombre o certificado';
    }
    get textoSinOpciones() {
        if (this.familia === 'autos') { return 'La póliza no tiene vehículos con esos datos.'; }
        if (this.familia === 'danos') { return 'La póliza no tiene ubicaciones con esos datos.'; }
        return 'La póliza no tiene asegurados con ese nombre o certificado.';
    }
    get ayudaAfectado() {
        return this.esPersonas ? 'Si es dependiente, su titular se agrega como reclamante.' : 'El contratante de la póliza queda como reclamante.';
    }
    get columnas() { return this.esPersonas ? COLUMNAS_ASEGURADOS : (COLUMNAS_BIENES[this.familia] || COLUMNAS_BIENES.danos); }
    handleBuscar(e) {
        this.texto = e.target.value || '';
        clearTimeout(this._tBuscar);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._tBuscar = setTimeout(() => this.buscar(), ESPERA_BUSQUEDA);
    }
    async buscar() {
        if (!this.poliza) { return; }
        const t = this.texto;
        const pre = this.preElegido;
        this.buscando = true;
        try {
            const personas = this.esPersonas;
            const l = personas
                ? await buscarAsegurados({ policyId: this.poliza.id, texto: t, elegidoId: pre })
                : await buscarBienes({ policyId: this.poliza.id, texto: t, elegidoId: pre });
            if (t !== this.texto) { return; }
            this.opciones = l.map((a) => ({
                ...a,
                parentesco: personas ? (a.titular ? `Dependiente de ${a.titular}` : 'Titular') : undefined,
                estatus: a.vigente ? 'Vigente' : 'Baja'
            }));
            // Lo que viene elegido desde su renglón queda seleccionado (una sola vez).
            if (pre) {
                const elegido = this.opciones.find((o) => o.id === pre || o.incisoId === pre);
                if (elegido) { this.elegidoId = elegido.id; }
                this.preElegido = null;
                this.sugerirCorreo();
            }
        } catch (e) {
            this.error = this.mensaje(e);
        } finally {
            this.buscando = false;
        }
    }
    handleElegir(e) {
        const sel = e.detail.selectedRows || [];
        this.elegidoId = sel.length ? sel[0].id : null;
        this.ajustarCobertura();
        this.sugerirCorreo();
    }
    sugerirCorreo() {
        if (this.correoEditado) { return; }
        const o = this.opciones.find((x) => x.id === this.elegidoId);
        const correo = this.esPersonas ? (o && o.correoAvisos) || '' : this.correoContratante;
        this.form = { ...this.form, correo };
    }
    get seleccion() { return this.elegidoId ? [this.elegidoId] : []; }
    get sinOpciones() { return !this.buscando && !this.opciones.length; }

    // ===== Siniestro =====
    handleCampo(e) {
        const campo = e.target.dataset.campo;
        const valor = e.detail.value;
        this.form = { ...this.form, [campo]: valor };
        if (campo === 'correo') { this.correoEditado = true; }
        // Un reembolso trae su solicitud de pago; los demás tipos, solo si se pide.
        if (campo === 'tipo' && this.esPersonas) { this.conSolicitud = valor === 'Reembolso'; }
    }
    handleConSolicitud(e) { this.conSolicitud = e.target.checked; }
    // Coberturas de la póliza y, en un bien, también las de ese bien.
    get coberturasDisponibles() {
        return this.coberturas.filter((c) => !c.bienId || (this.esBien && c.bienId === this.elegidoId));
    }
    ajustarCobertura() {
        const l = this.coberturasDisponibles;
        if (this.form.coberturaId && !l.some((c) => c.id === this.form.coberturaId)) { this.form = { ...this.form, coberturaId: '' }; }
        if (!this.form.coberturaId && l.length === 1) { this.form = { ...this.form, coberturaId: l[0].id }; }
    }
    get opcionesCobertura() {
        return [{ label: 'Sin cobertura de la póliza (se usa el tipo de siniestro)', value: '' }]
            .concat(this.coberturasDisponibles.map((c) => ({ label: c.nombre, value: c.id })));
    }
    get etiquetaDescripcion() { return this.esPersonas ? 'Diagnóstico' : 'Descripción del daño'; }
    get textoSolicitud() {
        return this.esPersonas ? 'Registrar la solicitud de pago (folio del reembolso)' : 'Registrar la solicitud de pago (reclamación a la aseguradora)';
    }
    get fechaMin() { return this.poliza ? this.poliza.inicio : null; }
    get fechaMax() { return this.poliza ? this.poliza.fin : null; }

    // ===== Guardar =====
    async guardar() {
        this.error = '';
        if (!this.poliza) { this.error = 'Elige la póliza.'; return; }
        if (!this.elegidoId) { this.error = `Elige ${this.esPersonas ? 'al asegurado afectado' : (this.familia === 'autos' ? 'el vehículo afectado' : 'la ubicación afectada')}.`; return; }
        const campos = [...this.template.querySelectorAll('.siniestro lightning-input, .siniestro lightning-combobox, .siniestro lightning-textarea')];
        if (!campos.reduce((v, c) => c.reportValidity() && v, true)) { return; }
        let solicitud = null;
        if (this.conSolicitud) {
            solicitud = this.template.querySelector('c-datos-solicitud-pago').valores();
            if (!solicitud) { return; }
        }
        this.guardando = true;
        try {
            const personas = this.esPersonas;
            const r = await crearSiniestro({ datosJson: JSON.stringify({
                ...this.form, coberturaId: this.form.coberturaId || null, policyId: this.poliza.id,
                participanteId: personas ? this.elegidoId : null, bienId: personas ? null : this.elegidoId,
                hospital: personas ? this.form.hospital : null, fechaAtencion: personas ? this.form.fechaAtencion : null,
                lugar: personas ? null : this.form.lugar, solicitud
            }) });
            this.creado = r;
            this.dispatchEvent(new CustomEvent('creado', { detail: { claimId: r.claimId, folio: r.folio } }));
            this.dispatchEvent(new ShowToastEvent({ title: 'Siniestro', variant: 'success', message: `Se registró el siniestro ${r.folio}.` }));
        } catch (e) {
            this.error = this.mensaje(e);
        } finally {
            this.guardando = false;
        }
    }
    get destinoArchivos() { return this.creado ? (this.creado.solicitudId || this.creado.claimId) : null; }
    get textoArchivos() {
        if (this.creado && this.creado.solicitudId) {
            return this.esPersonas ? 'Adjunta los documentos del reembolso (facturas, informe médico, estudios…).'
                : 'Adjunta los documentos de la reclamación (fotos, presupuesto, facturas…).';
        }
        return 'Adjunta los documentos del siniestro.';
    }
    handleArchivos(e) {
        const n = (e.detail.files || []).length;
        this.dispatchEvent(new ShowToastEvent({ title: 'Documentos', variant: 'success', message: `${n} archivo(s) adjuntado(s).` }));
    }
    get enAccion() { return this.objectApiName === 'InsurancePolicy' && !this.enModal; }
    abrirSiniestro() {
        const id = this.creado.claimId;
        // En la ventana de la póliza, quien la abrió navega al siniestro.
        if (this.enModal) { this.dispatchEvent(new CustomEvent('cerrar', { detail: { claimId: id, abrir: true } })); return; }
        if (this.enAccion) { this.dispatchEvent(new CloseActionScreenEvent()); }
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: id, objectApiName: 'Claim', actionName: 'view' } });
    }
    otro() {
        this.creado = null;
        this.elegidoId = null;
        this.form = { ...this.form, tipo: null, causa: null, fecha: null, diagnostico: '', hospital: '', fechaAtencion: null, lugar: '',
            numeroAseguradora: '', observaciones: '' };
        this.conSolicitud = false;
        this.correoEditado = false;
        this.ajustarCobertura();
        this.sugerirCorreo();
    }
    cancelar() {
        if (this.enModal) { this.dispatchEvent(new CustomEvent('cerrar', { detail: { claimId: this.creado ? this.creado.claimId : null } })); return; }
        if (this.enAccion) { this.dispatchEvent(new CloseActionScreenEvent()); return; }
        this[NavigationMixin.Navigate]({ type: 'standard__objectPage', attributes: { objectApiName: 'Claim', actionName: 'home' } });
    }
    get enCaptura() { return !this.creado; }

    mensaje(e) { return (e && e.body && e.body.message) || (e && e.message) || 'Ocurrió un error.'; }
}
