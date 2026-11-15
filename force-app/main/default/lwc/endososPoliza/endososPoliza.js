/**
 * @creation date: 15/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Endosos de una póliza (transacciones de FSC, categoría Endorsement): número, fecha en que surte
 *               efecto, estado, prima de la aseguradora (neta, derechos, IVA y total), movimientos (altas, bajas y
 *               cambios de asegurados, vehículos o ubicaciones) y el documento del endoso. Cada endoso se abre para ver
 *               sus movimientos. Lo usan los movimientos de asegurados, vehículos y ubicaciones. Usa
 *               EndosoPoliza.getEndosos.
 */
import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { fechaVisible, moneda } from 'c/lectorArchivos';
import getEndosos from '@salesforce/apex/EndosoPoliza.getEndosos';

export default class EndososPoliza extends NavigationMixin(LightningElement) {
    @track endosos = [];
    @track abiertos = new Set();
    cargando = false;
    errorMensaje = '';
    busqueda = '';
    _recordId;

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
