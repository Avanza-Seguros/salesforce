/**
 * @creation date: 15/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Endosos de una póliza (transacciones de FSC, categoría Endorsement): número, fecha en que surte
 *               efecto, estado, prima de la aseguradora (neta, derechos, IVA y total), movimientos (altas, bajas y
 *               cambios de asegurados, vehículos o ubicaciones) y el documento del endoso. Cada endoso se abre para ver
 *               sus movimientos. Lo usan los movimientos de asegurados, vehículos y ubicaciones. Usa
 *               EndosoPoliza.getEndosos.
 *               «Registrar endoso»: endoso de la aseguradora que no mueve registros (p. ej. una cláusula o beneficio
 *               adicional de GMM), con su número, fecha, descripción, prima y documento; si se elige el PDF se
 *               proponen sus datos (EndosoPoliza.registrarEndoso).
 */
import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { fechaVisible, moneda, paginasPdf } from 'c/lectorArchivos';
import { clausulaDeTexto, endosoDeTexto } from 'c/clasificadorArchivos';
import getEndosos from '@salesforce/apex/EndosoPoliza.getEndosos';
import registrarEndoso from '@salesforce/apex/EndosoPoliza.registrarEndoso';

const hoy = () => {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

export default class EndososPoliza extends NavigationMixin(LightningElement) {
    @track endosos = [];
    @track abiertos = new Set();
    cargando = false;
    errorMensaje = '';
    busqueda = '';
    _recordId;
    // Se puede registrar un endoso sin movimientos (lo decide el componente que lo usa).
    @api puedeEditar = false;
    enRegistro = false;
    leyendo = false;
    @track reg = {};
    regValores = null;
    regArchivo = null;
    regAviso = '';

    @api
    get recordId() { return this._recordId; }
    set recordId(v) {
        const cambio = v !== this._recordId;
        this._recordId = v;
        if (cambio && v) { this.cargar(); }
    }

    @api
    async cargar() {
        if (!this._recordId) { return; }
        this.cargando = true;
        this.errorMensaje = '';
        try {
            this.endosos = (await getEndosos({ policyId: this._recordId })) || [];
        } catch (e) {
            this.errorMensaje = (e && e.body && e.body.message) || (e && e.message) || 'No se pudieron leer los endosos.';
        } finally {
            this.cargando = false;
        }
    }

    get hayEndosos() { return this.endosos.length > 0; }
    get sinEndosos() { return !this.cargando && !this.errorMensaje && this.endosos.length === 0; }
    get textoTotal() {
        const n = this.filas.length;
        return this.busqueda ? `${n} de ${this.endosos.length} endosos` : `${this.endosos.length} endosos`;
    }
    handleBusqueda(e) { this.busqueda = e.target.value || ''; }

    fold(v) {
        return String(v == null ? '' : v).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
    }

    get filas() {
        const q = this.fold(this.busqueda).trim();
        return this.endosos
            .filter((x) => !q || this.fold([x.numero, x.nombre, x.estado, fechaVisible(x.fecha), x.usuario,
                ...(x.movimientos || []).map((m) => [m.tipo, m.registro, m.certificado, m.detalle, m.comentario].join(' '))].join(' ')).includes(q))
            .map((x) => {
                const abierto = this.abiertos.has(x.id);
                const movs = x.movimientos || [];
                const cuenta = {};
                movs.forEach((m) => { cuenta[m.tipo || 'Movimiento'] = (cuenta[m.tipo || 'Movimiento'] || 0) + 1; });
                return {
                    ...x,
                    numeroTxt: x.numero || 'Sin número',
                    fechaTxt: fechaVisible(x.fecha),
                    creadoTxt: x.creado ? new Date(x.creado).toLocaleString('es-MX', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '',
                    primaNetaTxt: moneda(x.primaNeta) || '—',
                    derechosTxt: moneda(x.derechos) || '—',
                    ivaTxt: moneda(x.iva) || '—',
                    totalTxt: moneda(x.total) || '—',
                    claseEstado: 'estado ' + (x.abiertos > 0 ? 'estado-pendiente' : 'estado-cerrado'),
                    movimientosTxt: Object.keys(cuenta).map((k) => `${cuenta[k]} ${k.toLowerCase()}`).join(', ') || 'Sin movimientos',
                    pendientesTxt: x.abiertos > 0 ? `${x.abiertos} sin cerrar` : '',
                    hayDocumentos: (x.documentos || []).length > 0,
                    abierto,
                    keyDetalle: x.id + '-movs',
                    iconoAbrir: abierto ? 'utility:chevrondown' : 'utility:chevronright',
                    textoAbrir: abierto ? 'Ocultar movimientos' : 'Ver movimientos',
                    movs: movs.map((m) => ({
                        ...m,
                        fechaTxt: fechaVisible(m.fecha),
                        cierreTxt: m.cierre ? new Date(m.cierre).toLocaleString('es-MX', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : 'Abierto',
                        claseTipo: 'tipo tipo-' + this.fold(m.tipo),
                        detalleTxt: [m.detalle, m.comentario].filter((y) => y).join(' · ')
                    }))
                };
            });
    }
    get sinResultados() { return this.hayEndosos && this.filas.length === 0; }

    // ============================================================
    // Registrar endoso sin movimientos
    // ============================================================
    abrirRegistro() {
        this.reg = { numero: '', fecha: hoy(), descripcion: '' };
        this.regValores = null;
        this.regArchivo = null;
        this.regAviso = '';
        this.enRegistro = true;
    }
    cerrarRegistro() {
        this.enRegistro = false;
        this.regArchivo = null;
        this.regValores = null;
    }
    handleReg(e) {
        this.reg = { ...this.reg, [e.target.dataset.campo]: e.detail.value };
    }
    elegirPdf() {
        const i = this.template.querySelector('input.reg-pdf');
        if (i) { i.click(); }
    }
    // PDF del endoso: se proponen número, fecha, descripción y prima; el archivo queda adjunto.
    async handlePdf(e) {
        const file = e.target.files && e.target.files[0];
        e.target.value = null;
        if (!file) { return; }
        this.regArchivo = file;
        this.regAviso = '';
        if (!file.name.toLowerCase().endsWith('.pdf')) { return; }
        this.leyendo = true;
        try {
            const texto = (await paginasPdf(this, file, () => {})).join('\n');
            const c = clausulaDeTexto(texto);
            const x = c ? null : endosoDeTexto(texto, file.name);
            if (c) {
                this.reg = { ...this.reg, descripcion: c.descripcion || this.reg.descripcion, fecha: c.fecha || this.reg.fecha };
                this.regAviso = 'Datos tomados del PDF: revisa la descripción y captura el número de endoso si lo tiene.';
            } else if (x) {
                this.reg = { ...this.reg, numero: x.numero || this.reg.numero, fecha: x.fecha || this.reg.fecha,
                    descripcion: [x.tipo, x.detalle].filter((y) => y).join(' · ').substring(0, 200) || this.reg.descripcion };
                this.regValores = { primaNeta: x.primaNeta ?? null, derechos: x.derechos ?? null, iva: x.iva ?? null, total: x.total ?? null };
                this.regAviso = (x.incisos || []).length || x.general
                    ? 'Este endoso mueve registros: cárgalo desde «Cargar endoso» o «Cargar archivo» para aplicar sus movimientos.'
                    : 'Datos tomados del PDF: revísalos antes de registrar.';
            } else {
                this.regAviso = 'No se reconocieron los datos del PDF: captúralos; el archivo queda adjunto.';
            }
        } catch (err) {
            this.regAviso = 'No se pudo leer el PDF: captura los datos; el archivo queda adjunto.';
        } finally {
            this.leyendo = false;
        }
    }
    get textoArchivoReg() { return this.regArchivo ? this.regArchivo.name : 'Sin documento'; }

    async guardarRegistro() {
        const campos = [...this.template.querySelectorAll('.reg-form lightning-input, .reg-form lightning-textarea')];
        if (!campos.reduce((ok, c) => c.reportValidity() && ok, true)) { return; }
        const datos = this.template.querySelector('c-datos-endoso');
        const prima = datos ? datos.prima : null;
        this.cargando = true;
        try {
            const id = await registrarEndoso({
                policyId: this._recordId, numero: this.reg.numero, descripcion: this.reg.descripcion,
                fecha: this.reg.fecha, primaJson: prima ? JSON.stringify(prima) : null
            });
            let sinDocumento = false;
            if (datos && datos.tieneArchivo) {
                try { await datos.subir(id); } catch (err) { sinDocumento = true; }
            }
            this.dispatchEvent(new ShowToastEvent({
                title: 'Endoso', variant: sinDocumento ? 'warning' : 'success',
                message: sinDocumento ? 'El endoso se registró, pero no se pudo adjuntar el documento: adjúntalo en la transacción del endoso.'
                    : 'Endoso registrado.'
            }));
            this.cerrarRegistro();
            await this.cargar();
            this.dispatchEvent(new CustomEvent('registrado', { detail: { id } }));
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Endoso', variant: 'error',
                message: (e && e.body && e.body.message) || (e && e.message) || 'No se pudo registrar el endoso.' }));
        } finally {
            this.cargando = false;
        }
    }

    toggle(e) {
        const id = e.currentTarget.dataset.id;
        const s = new Set(this.abiertos);
        if (s.has(id)) { s.delete(id); } else { s.add(id); }
        this.abiertos = s;
    }

    verDocumento(e) {
        e.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'filePreview' },
            state: { selectedRecordId: e.currentTarget.dataset.id }
        });
    }

    verEndoso(e) {
        e.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: e.currentTarget.dataset.id, objectApiName: 'InsurancePolicyTransaction', actionName: 'view' }
        });
    }
}
