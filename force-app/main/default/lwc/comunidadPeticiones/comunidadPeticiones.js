import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMisPolizas from '@salesforce/apex/ComunidadPeticionController.getMisPolizas';
import getContactosDePoliza from '@salesforce/apex/ComunidadPeticionController.getContactosDePoliza';
import crearPeticion from '@salesforce/apex/ComunidadPeticionController.crearPeticion';

const COLUMNS = [
    { label: 'Contacto', fieldName: 'nombre', type: 'text' },
    { label: 'Certificado', fieldName: 'certificado', type: 'text' },
    { label: 'Parentesco', fieldName: 'parentesco', type: 'text' },
    { label: 'Categoría', fieldName: 'categoria', type: 'text' },
    { label: 'Estatus', fieldName: 'estatusLabel', type: 'text' },
    {
        type: 'button',
        typeAttributes: {
            label: 'Crear petición',
            name: 'crear',
            variant: 'brand',
            iconName: 'utility:add'
        }
    }
];

export default class ComunidadPeticiones extends LightningElement {
    columns = COLUMNS;

    // Pólizas (picklist con autocompletado)
    @track polizaOptions = [];
    @track selectedPolizaId = '';
    @track selectedPolizaLabel = '';
    @track polizaSearch = '';
    @track showPolizaDropdown = false;
    _polizasById = {};
    _blurTimer = null;

    // Contactos + paginado
    @track contactos = [];
    @track isLoading = false;
    @track pageSize = 10;
    @track currentPage = 1;

    // Modal de creación de petición
    @track modalOpen = false;
    @track contactoSel = null;
    @track tipo = 'Cambio';
    @track fechaNacimiento = '';
    @track isSaving = false;

    // ---------- Carga inicial: pólizas para el picklist ----------
    async connectedCallback() {
        try {
            const res = await getMisPolizas();
            this.polizaOptions = (res || []).map(p => ({ label: p.label, value: p.id }));
            this._polizasById = {};
            (res || []).forEach(p => { this._polizasById[p.id] = p; });
        } catch (e) {
            this.toast('Error', this.msg(e, 'No se pudieron cargar las pólizas.'), 'error');
        }
    }

    get tipoOptions() {
        return [
            { label: 'Alta', value: 'Alta' },
            { label: 'Baja', value: 'Baja' },
            { label: 'Cambio', value: 'Cambio' }
        ];
    }
    get pageSizeOptions() {
        return [
            { label: '10', value: '10' },
            { label: '25', value: '25' },
            { label: '50', value: '50' },
            { label: 'Todas', value: 'all' }
        ];
    }
    get pageSizeValue() {
        return this.pageSize > 100000 ? 'all' : String(this.pageSize);
    }
    get hasContactos() {
        return this.contactos && this.contactos.length > 0;
    }
    get sinContactos() {
        return !!this.selectedPolizaId && !this.isLoading && !this.hasContactos;
    }
    get tituloContactos() {
        return this.selectedPolizaLabel ? `Contactos de: ${this.selectedPolizaLabel}` : '';
    }

    // ---------- Paginado ----------
    get totalPages() {
        return Math.max(1, Math.ceil(this.contactos.length / this.pageSize));
    }
    get contactosPagina() {
        const start = (this.currentPage - 1) * this.pageSize;
        return this.contactos.slice(start, start + this.pageSize);
    }
    get isFirstPage() { return this.currentPage <= 1; }
    get isLastPage() { return this.currentPage >= this.totalPages; }
    get pageInfo() {
        return `Página ${this.currentPage} de ${this.totalPages} · ${this.contactos.length} contacto${this.contactos.length === 1 ? '' : 's'}`;
    }
    handlePrevPage() { if (this.currentPage > 1) { this.currentPage -= 1; } }
    handleNextPage() { if (this.currentPage < this.totalPages) { this.currentPage += 1; } }
    handlePageSizeChange(event) {
        const v = event.detail.value;
        this.pageSize = (v === 'all') ? 1000000 : parseInt(v, 10) || 10;
        this.currentPage = 1;
    }

    // ---------- Selección de póliza (autocompletado) ----------
    get filteredPolizas() {
        const t = this._norm(this.polizaSearch);
        if (!t) { return this.polizaOptions.slice(0, 50); }
        return this.polizaOptions
            .filter(o => this._norm(o.label).includes(t))
            .slice(0, 50);
    }
    get hasPolizaResults() {
        return this.filteredPolizas && this.filteredPolizas.length > 0;
    }
    handlePolizaFocus() {
        this.showPolizaDropdown = true;
    }
    handlePolizaInput(event) {
        this.polizaSearch = event.target.value;
        // Si borra o cambia el texto, se deselecciona hasta que elija de la lista.
        this.selectedPolizaId = '';
        this.selectedPolizaLabel = '';
        this.showPolizaDropdown = true;
    }
    handlePolizaBlur() {
        // Retraso para permitir el click en una opción antes de cerrar.
        clearTimeout(this._blurTimer);
        this._blurTimer = setTimeout(() => { this.showPolizaDropdown = false; }, 200);
    }
    async selectPolizaOption(event) {
        const id = event.currentTarget.dataset.id;
        const p = this._polizasById[id];
        if (!p) { return; }
        this.selectedPolizaId = id;
        this.selectedPolizaLabel = p.label;
        this.polizaSearch = p.label;
        this.showPolizaDropdown = false;
        await this.cargarContactos(id);
    }
    _norm(s) {
        return (s || '').toString().toLowerCase()
            .normalize('NFD').replace(/[̀-ͯ]/g, '');
    }
    async cargarContactos(polizaId) {
        this.isLoading = true;
        this.contactos = [];
        this.currentPage = 1;
        try {
            const res = await getContactosDePoliza({ polizaId });
            this.contactos = (res || []).map(c => ({
                ...c,
                estatusLabel: c.activo ? 'Activo' : 'Baja'
            }));
        } catch (e) {
            this.toast('Error', this.msg(e, 'No se pudieron cargar los contactos.'), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ---------- Crear petición ----------
    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        if (action.name === 'crear') {
            this.contactoSel = row;
            this.tipo = 'Cambio';
            this.fechaNacimiento = row.fechaNacimiento || '';
            this.modalOpen = true;
        }
    }
    get contactoNombreSel() { return this.contactoSel ? this.contactoSel.nombre : ''; }
    get certificadoSel() { return this.contactoSel ? this.contactoSel.certificado : ''; }
    get hoyTexto() {
        return new Date().toLocaleDateString('es-MX', { day: '2-digit', month: 'long', year: 'numeric' });
    }
    handleTipoChange(event) { this.tipo = event.detail.value; }
    handleFechaNacChange(event) { this.fechaNacimiento = event.target.value; }
    closeModal() {
        this.modalOpen = false;
        this.contactoSel = null;
    }
    async confirmarPeticion() {
        if (!this.contactoSel || !this.selectedPolizaId) { return; }
        if (!this.fechaNacimiento) {
            this.toast('Falta un dato', 'Captura la fecha de nacimiento del contacto.', 'warning');
            return;
        }
        this.isSaving = true;
        try {
            await crearPeticion({
                polizaId: this.selectedPolizaId,
                certificadoId: this.contactoSel.id,
                tipo: this.tipo,
                fechaNacimiento: this.fechaNacimiento
            });
            this.toast('Petición creada',
                `Se generó la petición de ${this.tipo} para ${this.contactoSel.nombre}.`, 'success');
            this.modalOpen = false;
            this.contactoSel = null;
        } catch (e) {
            this.toast('No se pudo crear', this.msg(e, 'Revisa los datos de la petición.'), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    // ---------- Utilerías ----------
    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    msg(e, fallback) {
        return (e && e.body && e.body.message) || (e && e.message) || fallback;
    }
}
