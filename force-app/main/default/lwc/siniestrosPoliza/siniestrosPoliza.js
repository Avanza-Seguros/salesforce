// siniestrosPoliza/siniestrosPoliza.js
// Pestaña Siniestros de la póliza: sus siniestros (Claims) con lo afectado, el estatus, lo reclamado y lo pagado; los
// indicadores de siniestralidad (pagado contra la prima neta de la póliza y sus endosos); el botón «Nuevo siniestro»
// (c-siniestro-modal con la póliza fija) y, de solo consulta, los folios de siniestro anteriores de ese número de póliza
// en Control de Folios.
import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import siniestrosDePoliza from '@salesforce/apex/SiniestrosController.siniestrosDePoliza';
import { abrirNuevoSiniestro } from 'c/siniestroModal';

const POR_PAGINA = 20;
const FILTROS = [
    { label: 'Todos', value: 'todos' },
    { label: 'Abiertos', value: 'abiertos' },
    { label: 'Cerrados', value: 'cerrados' }
];
// Color del estatus del siniestro.
const CLASE_ESTATUS = {
    Abierto: 'estado estado-abierto', Reabierto: 'estado estado-abierto', 'Bajo evaluación': 'estado estado-proceso',
    Pendiente: 'estado estado-proceso', Concedido: 'estado estado-concedido', Rechazado: 'estado estado-rechazado',
    Cerrado: 'estado estado-cerrado', Anulado: 'estado estado-cerrado'
};
const TITULO_AFECTADO = { personas: 'Asegurado afectado', autos: 'Vehículo', danos: 'Ubicación' };

const fechaTxt = (d) => (d ? String(d).slice(0, 10).split('-').reverse().join('/') : '');
const pesos = new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN' });
const moneda = (v) => (v === null || v === undefined ? '—' : pesos.format(v));
const normal = (v) => String(v || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');

export default class SiniestrosPoliza extends NavigationMixin(LightningElement) {
    @api recordId;

    datos = null;
    cargando = false;
    error = '';
    busqueda = '';
    filtro = 'todos';
    opcionesFiltro = FILTROS;
    pagina = 1;
    paginaFolios = 1;
    foliosAbiertos = false;

    connectedCallback() { this.cargar(); }

    async cargar() {
        this.cargando = true;
        this.error = '';
        try {
            this.datos = await siniestrosDePoliza({ policyId: this.recordId });
        } catch (e) {
            this.error = (e && e.body && e.body.message) || (e && e.message) || 'No se pudieron leer los siniestros.';
        } finally {
            this.cargando = false;
        }
    }

    // ===== Indicadores =====
    get resumen() { return (this.datos && this.datos.resumen) || {}; }
    get totalTxt() { return this.resumen.total || 0; }
    get abiertosTxt() { return this.resumen.abiertos || 0; }
    get reclamadoTxt() { return moneda(this.resumen.reclamado || 0); }
    get pagadoTxt() { return moneda(this.resumen.pagado || 0); }
    get siniestralidadTxt() {
        const s = this.resumen.siniestralidad;
        return s === null || s === undefined ? '—' : `${Number(s).toLocaleString('es-MX', { maximumFractionDigits: 1 })} %`;
    }
    get primaTxt() { return this.resumen.prima ? `de ${moneda(this.resumen.prima)} de prima neta` : 'Sin prima neta'; }
    get subtitulo() {
        const n = this.datos ? this.datos.numero : '';
        return `Siniestros registrados en Claims de la póliza ${n}. La siniestralidad es lo pagado por la aseguradora entre la prima neta (con endosos).`;
    }

    // ===== Siniestros =====
    get conAcceso() { return !!this.datos && this.datos.acceso; }
    get sinAcceso() { return !!this.datos && !this.datos.acceso; }
    get puedeCrear() { return !!this.datos && this.datos.puedeCrear; }
    get tituloAfectado() { return TITULO_AFECTADO[(this.datos && this.datos.familia) || 'personas']; }
    handleBusqueda(e) { this.busqueda = e.target.value || ''; this.pagina = 1; this.paginaFolios = 1; }
    handleFiltro(e) { this.filtro = e.detail.value; this.pagina = 1; }
    coincide(valores) {
        const t = normal(this.busqueda).trim();
        return !t || valores.some((v) => normal(v).includes(t));
    }
    get filtrados() {
        const l = (this.datos && this.datos.siniestros) || [];
        return l.filter((s) => (this.filtro === 'todos' || (this.filtro === 'abiertos' ? !s.cerrado : s.cerrado))
            && this.coincide([s.folio, s.afectado, s.afectadoDetalle, s.descripcion, s.numeroAseguradora, s.tipo, s.causa, s.estatus]));
    }
    get siniestros() {
        const ini = (this.pagina - 1) * POR_PAGINA;
        return this.filtrados.slice(ini, ini + POR_PAGINA).map((s) => ({
            ...s,
            fechaTxt: fechaTxt(s.fecha),
            reporteTxt: s.reporte ? `Reportado el ${fechaTxt(s.reporte)}` : '',
            reclamadoTxt: moneda(s.reclamado),
            pagadoTxt: moneda(s.pagado),
            claseEstatus: CLASE_ESTATUS[s.estatus] || 'estado estado-cerrado'
        }));
    }
    get haySiniestros() { return ((this.datos && this.datos.siniestros) || []).length > 0; }
    get sinSiniestros() { return !!this.datos && this.datos.acceso && !this.haySiniestros; }
    get sinResultados() { return this.haySiniestros && !this.filtrados.length; }
    get paginas() { return Math.max(1, Math.ceil(this.filtrados.length / POR_PAGINA)); }
    get conPaginas() { return this.paginas > 1; }
    get textoPagina() { return `Página ${this.pagina} de ${this.paginas} · ${this.filtrados.length} siniestro(s)`; }
    get sinAnterior() { return this.pagina <= 1; }
    get sinSiguiente() { return this.pagina >= this.paginas; }
    anterior() { if (this.pagina > 1) { this.pagina--; } }
    siguiente() { if (this.pagina < this.paginas) { this.pagina++; } }

    abrirSiniestro(e) { this.abrirRegistro(e.currentTarget.dataset.id, 'Claim'); }
    async nuevoSiniestro() {
        await abrirNuevoSiniestro(this, { policyId: this.recordId });
        this.cargar();
    }

    // ===== Folios anteriores (Control de Folios) =====
    get conFolios() { return !!this.datos && this.datos.conFolios; }
    get todosFolios() { return (this.datos && this.datos.folios) || []; }
    get foliosFiltrados() {
        return this.todosFolios.filter((f) => this.coincide([f.folio, f.afectado, f.titular, f.diagnostico, f.movimiento, f.estatus, f.numeroAseguradora]));
    }
    get folios() {
        const ini = (this.paginaFolios - 1) * POR_PAGINA;
        return this.foliosFiltrados.slice(ini, ini + POR_PAGINA).map((f) => ({
            ...f,
            fechaTxt: fechaTxt(f.fecha),
            cierreTxt: fechaTxt(f.cierre),
            tipoTxt: f.folioInicial ? `${f.tipo || 'Complementario'} de ${f.folioInicial}` : (f.tipo || ''),
            titularTxt: f.titular && f.titular !== f.afectado ? `Titular: ${f.titular}` : ''
        }));
    }
    get tituloFolios() { return `Folios anteriores en Control de Folios (${this.todosFolios.length})`; }
    get iconoFolios() { return this.foliosAbiertos ? 'utility:chevrondown' : 'utility:chevronright'; }
    get hayFolios() { return this.todosFolios.length > 0; }
    get sinFoliosFiltrados() { return this.hayFolios && !this.foliosFiltrados.length; }
    toggleFolios() { this.foliosAbiertos = !this.foliosAbiertos; }
    get paginasFolios() { return Math.max(1, Math.ceil(this.foliosFiltrados.length / POR_PAGINA)); }
    get conPaginasFolios() { return this.paginasFolios > 1; }
    get textoPaginaFolios() { return `Página ${this.paginaFolios} de ${this.paginasFolios} · ${this.foliosFiltrados.length} folio(s)`; }
    get sinAnteriorFolios() { return this.paginaFolios <= 1; }
    get sinSiguienteFolios() { return this.paginaFolios >= this.paginasFolios; }
    anteriorFolios() { if (this.paginaFolios > 1) { this.paginaFolios--; } }
    siguienteFolios() { if (this.paginaFolios < this.paginasFolios) { this.paginaFolios++; } }
    abrirFolio(e) { this.abrirRegistro(e.currentTarget.dataset.id, 'Control_de_Folios__c'); }

    abrirRegistro(id, objeto) {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: id, objectApiName: objeto, actionName: 'view' } });
    }
}
