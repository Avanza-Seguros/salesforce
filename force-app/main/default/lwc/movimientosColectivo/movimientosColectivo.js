/**
 * @creation date: 31/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Altas, bajas y cambios de asegurados de una póliza colectiva de personas.
 *               - En la póliza (endosos): lista de asegurados vigentes y dados de baja, baja con fecha y motivo, alta de
 *                 titulares o dependientes, cambio de datos y carga del endoso o censo de la aseguradora para compararlo.
 *               - En la oportunidad de renovación: llena el censo con los asegurados vigentes de la póliza anterior y
 *                 permite los mismos movimientos sobre el censo (la baja lo quita de la renovación con su motivo).
 *               Usa MovimientosColectivoController; el archivo se lee con c-censo-colectivo en modo "lector".
 */
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import { fechaVisible, moneda } from 'c/lectorArchivos';
import getDatos from '@salesforce/apex/MovimientosColectivoController.getDatos';
import aplicar from '@salesforce/apex/MovimientosColectivoController.aplicar';
import compararArchivo from '@salesforce/apex/MovimientosColectivoController.compararArchivo';
import traerDePoliza from '@salesforce/apex/MovimientosColectivoController.traerDePoliza';

const POR_PAGINA = 50;
const PARENTESCOS = ['Cónyuge', 'Hijo(a)', 'Padre/Madre', 'Suegro(a)', 'Otro'];

export default class MovimientosColectivo extends LightningElement {
    @api readOnly = false;
    @track datos = null;
    @track revision = null;
    @track form = {};
    cargando = false;
    errorMensaje = '';
    vista = 'lista';
    filtro = 'vigentes';
    busqueda = '';
    pagina = 1;
    modal = null;
    seleccion = new Set();
    censoCompleto = 'completo';
    archivoNombre = '';
    // Fecha, endoso, motivo y comentario comunes de la revisión del archivo.
    @track comun = {};
    abierto = false;
    _recordId;

    @api
    get recordId() { return this._recordId; }
    set recordId(v) {
        const cambio = v !== this._recordId;
        this._recordId = v;
        if (cambio && v) { this.cargar(); }
    }

    @api
    recargar() {
        return this.cargar();
    }

    async cargar() {
        if (!this._recordId) { return; }
        this.cargando = true;
        try {
            this.datos = await getDatos({ recordId: this._recordId });
            this.seleccion = new Set();
            this.errorMensaje = '';
        } catch (e) {
            this.mostrarError(e);
        } finally {
            this.cargando = false;
        }
    }

    // ============================================================
    // Estado general
    // ============================================================
    get enPoliza() { return !!this.datos && this.datos.contexto === 'poliza'; }
    get enOportunidad() { return !!this.datos && this.datos.contexto === 'oportunidad'; }
    // En la oportunidad solo aplica cuando el cliente ya tiene una póliza del ramo (renovación).
    get visible() { return !!this.datos && this.datos.aplica !== false && (this.enPoliza || (this.enOportunidad && !!this.datos.polizaAnteriorId)); }
    get noAplica() { return this.enPoliza && this.datos.aplica === false; }
    get puedeEditar() { return !this.readOnly && this.visible; }
    get titulo() { return this.enPoliza ? 'Asegurados de la póliza' : 'Renovación: altas, bajas y cambios'; }
    get subtitulo() {
        if (this.enPoliza) { return 'Endosos durante la vigencia: alta, baja (con motivo) y cambios de datos.'; }
        const fin = this.datos.polizaAnteriorFin ? ` (vence el ${fechaVisible(this.datos.polizaAnteriorFin)})` : '';
        return `Renueva la póliza ${this.datos.polizaAnteriorNombre}${fin}. Ajusta aquí el censo de la nueva vigencia.`;
    }
    // En la oportunidad el panel se abre y cierra para no ocupar espacio en la pantalla de la oportunidad.
    get mostrarCuerpo() { return this.enPoliza || this.abierto; }
    get textoAbrir() { return this.abierto ? 'Ocultar' : 'Abrir'; }
    toggleAbierto() { this.abierto = !this.abierto; }

    get enLista() { return this.vista === 'lista'; }
    get enArchivo() { return this.vista === 'archivo'; }
    get enRevision() { return this.vista === 'revision'; }
    get enHistorial() { return this.vista === 'historial'; }
    verLista() { this.vista = 'lista'; this.revision = null; }
    verHistorial() { this.vista = 'historial'; }
    verArchivo() { this.vista = 'archivo'; this.revision = null; }

    get miembros() { return (this.datos && this.datos.miembros) || []; }
    get vigentes() { return this.miembros.filter((m) => m.activo); }
    get totalVigentes() { return this.vigentes.length; }
    get totalTitulares() { return this.vigentes.filter((m) => m.esTitular).length; }
    get totalDependientes() { return this.totalVigentes - this.totalTitulares; }
    get totalBajas() { return this.miembros.length - this.totalVigentes; }
    get totalMovimientos() { return ((this.datos && this.datos.movimientos) || []).length; }
    get textoHistorial() { return `Historial (${this.totalMovimientos})`; }
    get sinAsegurados() { return this.miembros.length === 0; }
    get puedeTraer() { return this.puedeEditar && this.enOportunidad && this.datos.aseguradosAnterior > 0; }
    get textoTraer() { return `Traer ${this.datos.aseguradosAnterior} asegurados vigentes de ${this.datos.polizaAnteriorNombre}`; }

    // ============================================================
    // Lista
    // ============================================================
    get opcionesFiltro() {
        return [
            { label: `Vigentes (${this.totalVigentes})`, value: 'vigentes' },
            { label: `Dados de baja (${this.totalBajas})`, value: 'bajas' },
            { label: `Todos (${this.miembros.length})`, value: 'todos' }
        ];
    }
    handleFiltro(e) { this.filtro = e.detail.value; this.pagina = 1; }
    handleBusqueda(e) { this.busqueda = e.target.value || ''; this.pagina = 1; }

    get filtrados() {
        const q = this.fold(this.busqueda);
        return this.miembros.filter((m) => {
            if (this.filtro === 'vigentes' && !m.activo) { return false; }
            if (this.filtro === 'bajas' && m.activo) { return false; }
            if (!q) { return true; }
            return this.fold(`${m.nombre} ${m.certificado || ''} ${m.titularNombre || ''} ${m.categoria || ''}`).includes(q);
        });
    }
    get filas() {
        const ini = (this.pagina - 1) * POR_PAGINA;
        return this.filtrados.slice(ini, ini + POR_PAGINA).map((m) => ({
            ...m,
            seleccionado: this.seleccion.has(m.id),
            noSeleccionable: !m.activo || !this.puedeEditar,
            claseFila: (m.esTitular ? '' : 'fila-dependiente') + (m.activo ? '' : ' fila-baja'),
            nacimientoTxt: fechaVisible(m.fechaNacimiento),
            altaTxt: fechaVisible(m.fechaAlta),
            sumaTxt: moneda(m.sumaAsegurada),
            primaTxt: moneda(m.prima),
            estado: m.activo ? 'Vigente' : `Baja ${fechaVisible(m.fechaBaja)}`,
            claseEstado: m.activo ? 'estado estado-vigente' : 'estado estado-baja',
            puedeMover: m.activo && this.puedeEditar
        }));
    }
    get paginas() { return Math.max(1, Math.ceil(this.filtrados.length / POR_PAGINA)); }
    get textoPagina() { return `Página ${this.pagina} de ${this.paginas} · ${this.filtrados.length} asegurados`; }
    get sinAnterior() { return this.pagina <= 1; }
    get sinSiguiente() { return this.pagina >= this.paginas; }
    anterior() { if (this.pagina > 1) { this.pagina--; } }
    siguiente() { if (this.pagina < this.paginas) { this.pagina++; } }

    handleSeleccion(e) {
        const id = e.target.dataset.id;
        const s = new Set(this.seleccion);
        if (e.target.checked) { s.add(id); } else { s.delete(id); }
        this.seleccion = s;
    }
    get totalSeleccion() { return this.seleccion.size; }
    get sinSeleccion() { return this.seleccion.size === 0; }
    get textoBajaSeleccion() { return `Dar de baja (${this.seleccion.size})`; }

    async handleTraer() {
        if (this.miembros.length) {
            const ok = await LightningConfirm.open({
                message: 'El censo actual de la oportunidad se reemplazará con los asegurados vigentes de la póliza anterior. ¿Continuar?',
                variant: 'header', label: 'Traer asegurados', theme: 'warning'
            });
            if (!ok) { return; }
        }
        this.cargando = true;
        try {
            const n = await traerDePoliza({ opportunityId: this._recordId, reemplazar: true });
            this.toast('Renovación', `Censo de la renovación: ${n} asegurados de la póliza anterior.`, 'success');
            await this.cargar();
            this.avisarCambio();
        } catch (e) {
            this.mostrarError(e);
        } finally {
            this.cargando = false;
        }
    }

    // ============================================================
    // Modales: baja, alta y cambio
    // ============================================================
    get enModalBaja() { return this.modal === 'baja'; }
    get enModalAlta() { return this.modal === 'alta'; }
    get enModalCambio() { return this.modal === 'cambio'; }
    get hayModal() { return !!this.modal; }
    cerrarModal() { this.modal = null; this.form = {}; }

    get hoy() {
        const d = new Date();
        return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    }
    // Fecha propuesta: hoy en un endoso; el inicio de la nueva vigencia (fin de la anterior) en la renovación.
    get fechaDefault() { return this.enOportunidad && this.datos.polizaAnteriorFin ? this.datos.polizaAnteriorFin : this.hoy; }
    get motivos() { return (this.datos && this.datos.motivos) || []; }
    get etiquetaFecha() { return this.enPoliza ? 'Fecha en que surte efecto' : 'Fecha (inicio de la renovación)'; }

    abrirBaja(e) {
        const ids = e && e.target && e.target.dataset && e.target.dataset.id ? [e.target.dataset.id] : [...this.seleccion];
        if (!ids.length) { return; }
        this.form = { ids, fecha: this.fechaDefault, motivo: '', endoso: '', comentario: '' };
        this.modal = 'baja';
    }
    get bajaNombres() {
        const ids = new Set(this.form.ids || []);
        const titulares = new Set(this.miembros.filter((m) => ids.has(m.id) && m.esTitular).map((m) => m.id));
        return this.miembros
            .filter((m) => m.activo && (ids.has(m.id) || titulares.has(m.titularId)))
            .map((m) => ({ id: m.id, texto: m.nombre + (ids.has(m.id) ? '' : ` (dependiente de ${m.titularNombre})`) }));
    }
    get textoBaja() { return `Se darán de baja ${this.bajaNombres.length} asegurados. Los dependientes de un titular se dan de baja con él.`; }

    abrirAlta() {
        this.form = {
            tipo: 'titular', titularId: '', parentesco: 'Cónyuge', nombre: '', apellidos: '', fechaNacimiento: '', sexo: '',
            certificado: '', categoria: '', sumaAsegurada: null, prima: null, rfc: '', email: '', fecha: this.fechaDefault, endoso: ''
        };
        this.modal = 'alta';
    }
    get esAltaDependiente() { return this.form.tipo === 'dependiente'; }
    get opcionesTipoAlta() { return [{ label: 'Titular', value: 'titular' }, { label: 'Dependiente', value: 'dependiente' }]; }
    get opcionesTitulares() {
        return this.vigentes.filter((m) => m.esTitular)
            .map((m) => ({ label: `${m.nombre}${m.certificado ? ' · ' + m.certificado : ''}`, value: m.id }));
    }
    get opcionesParentesco() { return PARENTESCOS.map((p) => ({ label: p, value: p })); }
    get opcionesSexo() { return [{ label: 'Mujer', value: 'Mujer' }, { label: 'Hombre', value: 'Hombre' }]; }
    get listaCategorias() { return ((this.datos && this.datos.categorias) || []).join(', '); }
    get ayudaCategoria() { return this.listaCategorias ? `Existentes: ${this.listaCategorias}` : ''; }

    abrirCambio(e) {
        const m = this.miembros.find((x) => x.id === e.target.dataset.id);
        if (!m) { return; }
        this.form = {
            id: m.id, nombreActual: m.nombre, original: { ...m }, nombreCompleto: m.nombre, certificado: m.certificado || '',
            fechaNacimiento: m.fechaNacimiento || '', categoria: m.categoria || '', sumaAsegurada: m.sumaAsegurada, prima: m.prima,
            rfc: m.rfc || '', sexo: m.sexo || '', fecha: this.fechaDefault, endoso: '', comentario: ''
        };
        this.modal = 'cambio';
    }

    handleForm(e) {
        const campo = e.target.dataset.campo;
        let v = e.detail && e.detail.value !== undefined ? e.detail.value : e.target.value;
        if (e.target.type === 'number') { v = v === '' || v === null || v === undefined ? null : Number(v); }
        this.form = { ...this.form, [campo]: v };
    }

    validarForm() {
        const campos = [...this.template.querySelectorAll('.modal-form lightning-input, .modal-form lightning-combobox, .modal-form lightning-textarea')];
        return campos.reduce((ok, c) => c.reportValidity() && ok, true);
    }

    async guardarBaja() {
        if (!this.validarForm()) { return; }
        const f = this.form;
        const movs = f.ids.map((id) => ({ tipo: 'baja', id, fecha: f.fecha, motivo: f.motivo, endoso: f.endoso, comentario: f.comentario }));
        await this.enviar(movs);
    }

    async guardarAlta() {
        if (!this.validarForm()) { return; }
        const f = this.form;
        const dep = f.tipo === 'dependiente';
        const datos = {
            nombre: f.nombre, apellidos: f.apellidos, nombreCompleto: `${f.nombre || ''} ${f.apellidos || ''}`.trim(),
            fechaNacimiento: f.fechaNacimiento || null, sexo: f.sexo, parentesco: dep ? f.parentesco : 'Titular',
            certificado: f.certificado, categoria: f.categoria, sumaAsegurada: f.sumaAsegurada, prima: f.prima,
            rfc: f.rfc, email: f.email, fechaAlta: dep ? null : f.fecha
        };
        await this.enviar([{ tipo: 'alta', datos, titularId: dep ? f.titularId : null, fecha: f.fecha, endoso: f.endoso }]);
    }

    async guardarCambio() {
        if (!this.validarForm()) { return; }
        const f = this.form;
        const o = f.original;
        // Solo se mandan los datos que cambiaron.
        const datos = {};
        const distinto = (a, b) => (a === '' || a === undefined ? null : a) !== (b === '' || b === undefined ? null : b);
        if (distinto(f.nombreCompleto, o.nombre)) { datos.nombreCompleto = f.nombreCompleto; }
        if (distinto(f.certificado, o.certificado)) { datos.certificado = f.certificado; }
        if (distinto(f.fechaNacimiento, o.fechaNacimiento)) { datos.fechaNacimiento = f.fechaNacimiento; }
        if (distinto(f.categoria, o.categoria)) { datos.categoria = f.categoria; }
        if (distinto(f.sumaAsegurada, o.sumaAsegurada)) { datos.sumaAsegurada = f.sumaAsegurada; }
        if (distinto(f.prima, o.prima)) { datos.prima = f.prima; }
        if (distinto(f.rfc, o.rfc)) { datos.rfc = f.rfc; }
        if (distinto(f.sexo, o.sexo)) { datos.sexo = f.sexo; }
        if (!Object.keys(datos).length) {
            this.toast('Cambio', 'No modificaste ningún dato.', 'info');
            return;
        }
        await this.enviar([{ tipo: 'cambio', id: f.id, datos, fecha: f.fecha, endoso: f.endoso, comentario: f.comentario }]);
    }

    async enviar(movs) {
        this.cargando = true;
        try {
            const r = await aplicar({ recordId: this._recordId, movimientosJson: JSON.stringify(movs) });
            const partes = [];
            if (r.altas) { partes.push(`${r.altas} altas`); }
            if (r.bajas) { partes.push(`${r.bajas} bajas`); }
            if (r.cambios) { partes.push(`${r.cambios} cambios`); }
            this.toast('Movimientos', partes.length ? `Aplicados: ${partes.join(', ')}.` : 'No hubo cambios que aplicar.', 'success');
            this.cerrarModal();
            this.vista = 'lista';
            this.revision = null;
            await this.cargar();
            this.avisarCambio();
        } catch (e) {
            this.mostrarError(e);
        } finally {
            this.cargando = false;
        }
    }

    // ============================================================
    // Archivo de la aseguradora
    // ============================================================
    get opcionesCenso() {
        return [
            { label: 'Censo completo (los que no vienen se dan de baja)', value: 'completo' },
            { label: 'Solo movimientos (altas y cambios)', value: 'movimientos' }
        ];
    }
    handleCensoCompleto(e) { this.censoCompleto = e.detail.value; }

    async handleLeido(e) {
        this.archivoNombre = e.detail.archivo;
        this.cargando = true;
        try {
            const r = await compararArchivo({
                recordId: this._recordId,
                miembrosJson: JSON.stringify(e.detail.miembros),
                censoCompleto: this.censoCompleto === 'completo'
            });
            this.revision = {
                altas: r.altas.map((a) => ({ ...a, key: 'a' + a.ref, sel: true })),
                bajas: r.bajas.map((b) => ({ ...b, key: 'b' + b.id, sel: true, motivo: '' })),
                cambios: r.cambios.map((c) => ({ ...c, key: 'c' + c.id, sel: true })),
                sinCambios: r.sinCambios
            };
            this.comun = { fecha: this.fechaDefault, endoso: '', motivo: '', comentario: '' };
            this.vista = 'revision';
        } catch (err) {
            this.mostrarError(err);
        } finally {
            this.cargando = false;
        }
    }

    get altasRev() {
        return (this.revision ? this.revision.altas : []).map((a) => ({
            ...a,
            esDependiente: a.titularId || a.titularRef !== undefined && a.titularRef !== null,
            nacimientoTxt: fechaVisible(a.fechaNacimiento),
            sumaTxt: moneda(a.sumaAsegurada),
            primaTxt: moneda(a.prima)
        }));
    }
    get bajasRev() { return this.revision ? this.revision.bajas : []; }
    get cambiosRev() {
        return (this.revision ? this.revision.cambios : []).map((c) => ({
            ...c,
            difs: c.diferencias.map((d, i) => ({ key: c.key + i, texto: `${d.campo}: ${d.antes} → ${d.despues}` }))
        }));
    }
    get hayAltas() { return this.altasRev.length > 0; }
    get hayBajas() { return this.bajasRev.length > 0; }
    get hayCambios() { return this.cambiosRev.length > 0; }
    get sinDiferencias() { return !this.hayAltas && !this.hayBajas && !this.hayCambios; }
    get textoAltas() { return `Altas (${this.altasRev.length})`; }
    get textoBajas() { return `Bajas (${this.bajasRev.length})`; }
    get textoCambios() { return `Cambios (${this.cambiosRev.length})`; }
    get textoSinCambios() { return `${this.revision ? this.revision.sinCambios : 0} asegurados sin cambios.`; }
    get bajasSeleccionadas() { return this.bajasRev.some((b) => b.sel); }

    marcar(e) {
        const { lista, key } = e.target.dataset;
        const r = { ...this.revision };
        r[lista] = r[lista].map((x) => (x.key === key ? { ...x, sel: e.target.checked } : x));
        this.revision = r;
    }
    marcarTodos(e) {
        const { lista } = e.target.dataset;
        const r = { ...this.revision };
        r[lista] = r[lista].map((x) => ({ ...x, sel: e.target.checked }));
        this.revision = r;
    }
    motivoBaja(e) {
        const key = e.target.dataset.key;
        const r = { ...this.revision };
        r.bajas = r.bajas.map((x) => (x.key === key ? { ...x, motivo: e.detail.value } : x));
        this.revision = r;
    }
    handleComun(e) {
        this.comun = { ...this.comun, [e.target.dataset.campo]: e.detail.value };
    }

    async aplicarRevision() {
        if (!this.validarForm()) { return; }
        const c = this.comun;
        const movs = [];
        this.revision.bajas.filter((b) => b.sel).forEach((b) => {
            movs.push({ tipo: 'baja', id: b.id, fecha: c.fecha, motivo: b.motivo || c.motivo, endoso: c.endoso, comentario: c.comentario });
        });
        if (movs.some((m) => !m.motivo)) {
            this.toast('Bajas', 'Indica el motivo de baja (general o por asegurado).', 'warning');
            return;
        }
        this.revision.cambios.filter((x) => x.sel).forEach((x) => {
            movs.push({ tipo: 'cambio', id: x.id, datos: x.datos, fecha: c.fecha, endoso: c.endoso, comentario: c.comentario });
        });
        // Altas: titulares primero; el dependiente apunta a la posición del alta de su titular.
        const altas = this.revision.altas.filter((a) => a.sel);
        const posicion = new Map();
        let omitidos = 0;
        altas.filter((a) => !a.titularId && (a.titularRef === undefined || a.titularRef === null)).forEach((a) => {
            posicion.set(a.ref, movs.length);
            movs.push({ tipo: 'alta', datos: a.datos, fecha: c.fecha, endoso: c.endoso, comentario: c.comentario });
        });
        altas.filter((a) => a.titularId || (a.titularRef !== undefined && a.titularRef !== null)).forEach((a) => {
            const ref = a.titularId ? null : posicion.get(a.titularRef);
            if (!a.titularId && ref === undefined) { omitidos++; return; }
            movs.push({ tipo: 'alta', datos: a.datos, titularId: a.titularId || null, titularRef: a.titularId ? null : ref,
                fecha: c.fecha, endoso: c.endoso, comentario: c.comentario });
        });
        if (!movs.length) {
            this.toast('Movimientos', 'No seleccionaste ningún movimiento.', 'info');
            return;
        }
        if (omitidos) {
            const ok = await LightningConfirm.open({
                message: `${omitidos} dependientes no se darán de alta porque su titular no está seleccionado. ¿Continuar?`,
                variant: 'header', label: 'Altas de dependientes', theme: 'warning'
            });
            if (!ok) { return; }
        }
        await this.enviar(movs);
    }

    // ============================================================
    // Historial
    // ============================================================
    get historial() {
        return ((this.datos && this.datos.movimientos) || []).map((m) => ({
            ...m,
            fechaTxt: fechaVisible(m.fecha),
            claseTipo: 'tipo tipo-' + (m.tipo || '').toLowerCase(),
            detalleTxt: [m.motivo, m.detalle, m.comentario].filter((x) => x).join(' · ')
        }));
    }
    get sinHistorial() { return this.historial.length === 0; }

    // ============================================================
    // Utilidades
    // ============================================================
    avisarCambio() {
        this.dispatchEvent(new CustomEvent('movimientos', { detail: { total: this.totalVigentes } }));
    }
    fold(v) {
        return String(v || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
    }
    mostrarError(e) {
        const msg = (e && e.body && e.body.message) || (e && e.message) || 'Ocurrió un error inesperado.';
        this.errorMensaje = msg;
        this.dispatchEvent(new ShowToastEvent({ title: 'Asegurados', message: msg, variant: 'error' }));
    }
    toast(title, message, variant) {
        this.errorMensaje = '';
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
