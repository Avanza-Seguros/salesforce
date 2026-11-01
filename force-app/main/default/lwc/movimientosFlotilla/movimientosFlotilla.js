/**
 * @creation date: 31/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Altas, bajas y cambios de vehículos de una flotilla (colectiva de Automóviles).
 *               - En la póliza (endosos): vehículos vigentes y dados de baja, baja con fecha y motivo, alta de un vehículo
 *                 (o reingreso de uno dado de baja), cambio de datos y carga del archivo de la aseguradora para compararlo.
 *               - En la oportunidad de renovación: llena el censo de vehículos con los vigentes de la póliza anterior y
 *                 permite los mismos movimientos sobre el censo (la baja lo quita de la renovación con su motivo).
 *               Usa MovimientosFlotillaController; el archivo se lee con c-censo-vehiculos en modo "lector".
 */
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import { fechaVisible, moneda } from 'c/lectorArchivos';
import getDatos from '@salesforce/apex/MovimientosFlotillaController.getDatos';
import aplicar from '@salesforce/apex/MovimientosFlotillaController.aplicar';
import compararArchivo from '@salesforce/apex/MovimientosFlotillaController.compararArchivo';
import traerDePoliza from '@salesforce/apex/MovimientosFlotillaController.traerDePoliza';

const POR_PAGINA = 50;
const TIPOS = ['Automóviles', 'Pick-up de carga', 'Camiones', 'Tractocamiones', 'Remolques', 'Autobuses', 'Motocicletas'];

export default class MovimientosFlotilla extends LightningElement {
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
    // En la oportunidad solo aplica cuando el cliente ya tiene una póliza de autos (renovación).
    get visible() { return !!this.datos && this.datos.aplica === true && (this.enPoliza || !!this.datos.polizaAnteriorId); }
    // Póliza individual: el vehículo se lee del bien ligado a la póliza y solo se consulta.
    get soloLectura() { return !!this.datos && this.datos.soloLectura === true; }
    get puedeEditar() { return !this.readOnly && this.visible && !this.soloLectura; }
    get titulo() {
        if (this.soloLectura) { return this.vehiculos.length === 1 ? 'Vehículo de la póliza' : 'Vehículos de la póliza'; }
        return this.enPoliza ? 'Vehículos de la póliza' : 'Renovación: altas, bajas y cambios de vehículos';
    }
    get subtitulo() {
        if (this.soloLectura) { return 'Póliza individual: vehículo asegurado según la póliza emitida.'; }
        if (this.enPoliza) { return 'Endosos durante la vigencia: alta, baja (con motivo) y cambios de datos de los vehículos.'; }
        const fin = this.datos.polizaAnteriorFin ? ` (vence el ${fechaVisible(this.datos.polizaAnteriorFin)})` : '';
        return `Renueva la póliza ${this.datos.polizaAnteriorNombre}${fin}. Ajusta aquí el censo de vehículos de la nueva vigencia.`;
    }
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

    get vehiculos() { return (this.datos && this.datos.vehiculos) || []; }
    get vigentes() { return this.vehiculos.filter((v) => v.activo); }
    get totalVigentes() { return this.vigentes.length; }
    get totalBajas() { return this.vehiculos.length - this.totalVigentes; }
    get valorVigentes() { return moneda(this.vigentes.reduce((s, v) => s + (v.valor || 0), 0)) || '—'; }
    get primaVigentes() { return moneda(this.vigentes.reduce((s, v) => s + (v.prima || 0), 0)) || '—'; }
    get totalMovimientos() { return ((this.datos && this.datos.movimientos) || []).length; }
    get textoHistorial() { return `Historial (${this.totalMovimientos})`; }
    get sinVehiculos() { return this.vehiculos.length === 0; }
    get puedeTraer() { return this.puedeEditar && this.enOportunidad && this.datos.vehiculosAnterior > 0; }
    get textoTraer() { return `Traer ${this.datos.vehiculosAnterior} vehículos vigentes de ${this.datos.polizaAnteriorNombre}`; }

    // ============================================================
    // Lista
    // ============================================================
    get opcionesFiltro() {
        return [
            { label: `Vigentes (${this.totalVigentes})`, value: 'vigentes' },
            { label: `Dados de baja (${this.totalBajas})`, value: 'bajas' },
            { label: `Todos (${this.vehiculos.length})`, value: 'todos' }
        ];
    }
    handleFiltro(e) { this.filtro = e.detail.value; this.pagina = 1; }
    handleBusqueda(e) { this.busqueda = e.target.value || ''; this.pagina = 1; }

    get filtrados() {
        const q = this.fold(this.busqueda);
        return this.vehiculos.filter((v) => {
            if (this.filtro === 'vigentes' && !v.activo) { return false; }
            if (this.filtro === 'bajas' && v.activo) { return false; }
            if (!q) { return true; }
            return this.fold(`${v.inciso || ''} ${v.serie || ''} ${v.placas || ''} ${v.descripcion || ''}`).includes(q);
        });
    }
    get filas() {
        const ini = (this.pagina - 1) * POR_PAGINA;
        return this.filtrados.slice(ini, ini + POR_PAGINA).map((v) => ({
            ...v,
            seleccionado: this.seleccion.has(v.id),
            noSeleccionable: !v.activo || !this.puedeEditar,
            claseFila: v.activo ? '' : 'fila-baja',
            valorTxt: moneda(v.valor),
            primaTxt: moneda(v.prima),
            altaTxt: fechaVisible(v.fechaAlta),
            estado: v.activo ? 'Vigente' : `Baja ${fechaVisible(v.fechaBaja)}`,
            claseEstado: v.activo ? 'estado estado-vigente' : 'estado estado-baja',
            puedeMover: v.activo && this.puedeEditar
        }));
    }
    get paginas() { return Math.max(1, Math.ceil(this.filtrados.length / POR_PAGINA)); }
    get textoPagina() { return `Página ${this.pagina} de ${this.paginas} · ${this.filtrados.length} vehículos`; }
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
    get sinSeleccion() { return this.seleccion.size === 0; }
    get textoBajaSeleccion() { return `Dar de baja (${this.seleccion.size})`; }

    async handleTraer() {
        if (this.vehiculos.length) {
            const ok = await LightningConfirm.open({
                message: 'El censo de vehículos de la oportunidad se reemplazará con los vehículos vigentes de la póliza anterior. ¿Continuar?',
                variant: 'header', label: 'Traer vehículos', theme: 'warning'
            });
            if (!ok) { return; }
        }
        this.cargando = true;
        try {
            const n = await traerDePoliza({ opportunityId: this._recordId, reemplazar: true });
            this.toast('Renovación', `Censo de la renovación: ${n} vehículos de la póliza anterior.`, 'success');
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
    get fechaDefault() { return this.enOportunidad && this.datos.polizaAnteriorFin ? this.datos.polizaAnteriorFin : this.hoy; }
    get motivos() { return (this.datos && this.datos.motivos) || []; }
    get etiquetaFecha() { return this.enPoliza ? 'Fecha en que surte efecto' : 'Fecha (inicio de la renovación)'; }
    get opcionesTipo() { return TIPOS.map((t) => ({ label: t, value: t })); }

    abrirBaja(e) {
        const ids = e && e.target && e.target.dataset && e.target.dataset.id ? [e.target.dataset.id] : [...this.seleccion];
        if (!ids.length) { return; }
        this.form = { ids, fecha: this.fechaDefault, motivo: '', endoso: '', comentario: '' };
        this.modal = 'baja';
    }
    get bajaNombres() {
        const ids = new Set(this.form.ids || []);
        return this.vehiculos.filter((v) => ids.has(v.id)).map((v) => ({ id: v.id, texto: this.nombre(v) }));
    }
    get textoBaja() { return `Se darán de baja ${this.bajaNombres.length} vehículos.`; }

    abrirAlta() {
        this.form = {
            serie: '', descripcion: '', modelo: null, placas: '', uso: '', tipoVehiculo: '', paquete: '', valor: null, prima: null,
            inciso: null, fecha: this.fechaDefault, endoso: ''
        };
        this.modal = 'alta';
    }

    abrirCambio(e) {
        const v = this.vehiculos.find((x) => x.id === e.target.dataset.id);
        if (!v) { return; }
        this.form = {
            id: v.id, nombreActual: this.nombre(v), original: { ...v }, inciso: v.inciso, serie: v.serie || '',
            descripcion: v.descripcion || '', modelo: v.modelo, placas: v.placas || '', uso: v.uso || '',
            tipoVehiculo: v.tipoVehiculo || '', paquete: v.paquete || '', valor: v.valor, prima: v.prima,
            fecha: this.fechaDefault, endoso: '', comentario: ''
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
        const campos = [...this.template.querySelectorAll('.modal-form lightning-input, .modal-form lightning-combobox')];
        return campos.reduce((ok, c) => c.reportValidity() && ok, true);
    }

    async guardarBaja() {
        if (!this.validarForm()) { return; }
        const f = this.form;
        await this.enviar(f.ids.map((id) => ({ tipo: 'baja', id, fecha: f.fecha, motivo: f.motivo, endoso: f.endoso, comentario: f.comentario })));
    }

    async guardarAlta() {
        if (!this.validarForm()) { return; }
        const f = this.form;
        const datos = {
            inciso: f.inciso, serie: f.serie, descripcion: f.descripcion, modelo: f.modelo, placas: f.placas, uso: f.uso,
            tipoVehiculo: f.tipoVehiculo, paquete: f.paquete, valor: f.valor, prima: f.prima
        };
        await this.enviar([{ tipo: 'alta', datos, fecha: f.fecha, endoso: f.endoso }]);
    }

    async guardarCambio() {
        if (!this.validarForm()) { return; }
        const f = this.form;
        const o = f.original;
        // Solo se mandan los datos que cambiaron.
        const datos = {};
        const vacio = (a) => (a === '' || a === undefined ? null : a);
        ['inciso', 'serie', 'descripcion', 'modelo', 'placas', 'uso', 'tipoVehiculo', 'paquete', 'valor', 'prima'].forEach((k) => {
            if (vacio(f[k]) !== vacio(o[k])) { datos[k] = f[k]; }
        });
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
                incisosJson: JSON.stringify(e.detail.incisos),
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
        return (this.revision ? this.revision.altas : []).map((a) => ({ ...a, valorTxt: moneda(a.valor), primaTxt: moneda(a.prima) }));
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
    get textoSinCambios() { return `${this.revision ? this.revision.sinCambios : 0} vehículos sin cambios.`; }

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
            this.toast('Bajas', 'Indica el motivo de baja (general o por vehículo).', 'warning');
            return;
        }
        this.revision.cambios.filter((x) => x.sel).forEach((x) => {
            movs.push({ tipo: 'cambio', id: x.id, datos: x.datos, fecha: c.fecha, endoso: c.endoso, comentario: c.comentario });
        });
        this.revision.altas.filter((a) => a.sel).forEach((a) => {
            movs.push({ tipo: 'alta', datos: a.datos, fecha: c.fecha, endoso: c.endoso, comentario: c.comentario });
        });
        if (!movs.length) {
            this.toast('Movimientos', 'No seleccionaste ningún movimiento.', 'info');
            return;
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
    nombre(v) {
        return `${v.inciso ? 'Inciso ' + v.inciso + ' · ' : ''}${v.descripcion || 'Vehículo'}${v.serie ? ' · ' + v.serie : ''}`;
    }
    avisarCambio() {
        this.dispatchEvent(new CustomEvent('movimientos', { detail: { total: this.totalVigentes } }));
    }
    fold(v) {
        return String(v || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
    }
    mostrarError(e) {
        const msg = (e && e.body && e.body.message) || (e && e.message) || 'Ocurrió un error inesperado.';
        this.errorMensaje = msg;
        this.dispatchEvent(new ShowToastEvent({ title: 'Vehículos', message: msg, variant: 'error' }));
    }
    toast(title, message, variant) {
        this.errorMensaje = '';
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
