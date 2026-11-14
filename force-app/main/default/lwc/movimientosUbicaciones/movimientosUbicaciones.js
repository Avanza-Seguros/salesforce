/**
 * @creation date: 01/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Altas, bajas y cambios de ubicaciones de una póliza colectiva de Daños / Empresarial.
 *               - En la póliza (endosos): ubicaciones vigentes y dadas de baja, baja con fecha y motivo, alta de una
 *                 ubicación (o reingreso de una dada de baja) y cambio de suma asegurada, prima, giro o inciso.
 *               - En la oportunidad de renovación: llena el listado de ubicaciones con las vigentes de la póliza anterior
 *                 y permite los mismos movimientos sobre el listado (la baja la quita de la renovación con su motivo).
 *               Usa MovimientosUbicacionesController.
 */
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import { fechaVisible, moneda, descargarExcel } from 'c/lectorArchivos';
import getDatos from '@salesforce/apex/MovimientosUbicacionesController.getDatos';
import cerrarMovimiento from '@salesforce/apex/MovimientosColectivoController.cerrarMovimiento';
import aplicar from '@salesforce/apex/MovimientosUbicacionesController.aplicar';
import traerDePoliza from '@salesforce/apex/MovimientosUbicacionesController.traerDePoliza';

const POR_PAGINA = 50;

export default class MovimientosUbicaciones extends LightningElement {
    @api readOnly = false;
    @track datos = null;
    @track form = {};
    cargando = false;
    errorMensaje = '';
    vista = 'lista';
    filtro = 'vigentes';
    busqueda = '';
    busquedaHistorial = '';
    pagina = 1;
    modal = null;
    fechasExcel = [];
    seleccion = new Set();
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
    get visible() { return !!this.datos && this.datos.aplica === true && (this.enPoliza || !!this.datos.polizaAnteriorId); }
    get puedeEditar() { return !this.readOnly && this.visible; }
    get titulo() { return this.enPoliza ? 'Ubicaciones de la póliza' : 'Renovación: altas, bajas y cambios de ubicaciones'; }
    get subtitulo() {
        if (this.enPoliza) { return 'Endosos durante la vigencia: alta, baja (con motivo) y cambios de suma asegurada, prima o giro.'; }
        const fin = this.datos.polizaAnteriorFin ? ` (vence el ${fechaVisible(this.datos.polizaAnteriorFin)})` : '';
        return `Renueva la póliza ${this.datos.polizaAnteriorNombre}${fin}. Ajusta aquí las ubicaciones de la nueva vigencia; `
            + 'si la cotización aceptada no trae ubicaciones, la póliza se emite con este listado.';
    }
    get mostrarCuerpo() { return this.enPoliza || this.abierto; }
    get textoAbrir() { return this.abierto ? 'Ocultar' : 'Abrir'; }
    toggleAbierto() { this.abierto = !this.abierto; }

    get enLista() { return this.vista === 'lista'; }
    get enHistorial() { return this.vista === 'historial'; }
    verLista() { this.vista = 'lista'; }
    verHistorial() { this.vista = 'historial'; }

    get ubicaciones() { return (this.datos && this.datos.ubicaciones) || []; }
    get vigentes() { return this.ubicaciones.filter((u) => u.activo); }
    get totalVigentes() { return this.vigentes.length; }
    get totalBajas() { return this.ubicaciones.length - this.totalVigentes; }
    get sumaVigentes() { return moneda(this.vigentes.reduce((s, u) => s + (u.sumaAsegurada || 0), 0)) || '—'; }
    get primaVigentes() { return moneda(this.vigentes.reduce((s, u) => s + (u.prima || 0), 0)) || '—'; }
    get totalMovimientos() { return ((this.datos && this.datos.movimientos) || []).length; }
    get textoHistorial() { return `Historial (${this.totalMovimientos})`; }
    get sinUbicaciones() { return this.ubicaciones.length === 0; }
    get puedeTraer() { return this.puedeEditar && this.enOportunidad && this.datos.ubicacionesAnterior > 0; }
    get textoTraer() { return `Traer ${this.datos.ubicacionesAnterior} ubicaciones vigentes de ${this.datos.polizaAnteriorNombre}`; }

    // ============================================================
    // Lista
    // ============================================================
    get opcionesFiltro() {
        return [
            { label: `Vigentes (${this.totalVigentes})`, value: 'vigentes' },
            { label: `Dadas de baja (${this.totalBajas})`, value: 'bajas' },
            { label: `Todas (${this.ubicaciones.length})`, value: 'todos' }
        ];
    }
    handleFiltro(e) { this.filtro = e.detail.value; this.pagina = 1; }
    handleBusqueda(e) { this.busqueda = e.target.value || ''; this.pagina = 1; }

    get filtrados() {
        const q = this.fold(this.busqueda);
        return this.ubicaciones.filter((u) => {
            if (this.filtro === 'vigentes' && !u.activo) { return false; }
            if (this.filtro === 'bajas' && u.activo) { return false; }
            if (!q) { return true; }
            return this.fold(`${u.inciso || ''} ${u.nombre || ''} ${u.direccion || ''} ${u.giro || ''}`).includes(q);
        });
    }
    get filas() {
        const ini = (this.pagina - 1) * POR_PAGINA;
        return this.filtrados.slice(ini, ini + POR_PAGINA).map((u) => ({
            ...u,
            seleccionado: this.seleccion.has(u.id),
            noSeleccionable: !u.activo || !this.puedeEditar,
            claseFila: u.activo ? '' : 'fila-baja',
            sumaTxt: moneda(u.sumaAsegurada),
            primaTxt: moneda(u.prima),
            altaTxt: fechaVisible(u.fechaAlta),
            fechaMovimientoTxt: fechaVisible(u.fechaMovimiento),
            // Creación del movimiento y su cierre (botón «Cerrar movimiento»).
            fechaCreacionTxt: this.fechaHoraTxt(u.fechaCreacion),
            fechaCierreTxt: this.fechaHoraTxt(u.fechaCierre),
            // Estado = último movimiento: Alta, Baja o Cambio (igual que en asegurados).
            estado: u.tipoMovimiento || (u.activo ? 'Alta' : 'Baja'),
            claseEstado: `estado estado-${String(u.tipoMovimiento || (u.activo ? 'Alta' : 'Baja')).toLowerCase()}`,
            puedeCerrar: this.enPoliza && this.puedeEditar && !!u.movimientoId && !u.fechaCierre,
            puedeMover: u.activo && this.puedeEditar
        }));
    }
    get paginas() { return Math.max(1, Math.ceil(this.filtrados.length / POR_PAGINA)); }
    get textoPagina() { return `Página ${this.pagina} de ${this.paginas} · ${this.filtrados.length} ubicaciones`; }
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
        if (this.ubicaciones.length) {
            const ok = await LightningConfirm.open({
                message: 'El listado de ubicaciones de la oportunidad se reemplazará con las ubicaciones vigentes de la póliza anterior. ¿Continuar?',
                variant: 'header', label: 'Traer ubicaciones', theme: 'warning'
            });
            if (!ok) { return; }
        }
        this.cargando = true;
        try {
            const n = await traerDePoliza({ opportunityId: this._recordId, reemplazar: true });
            this.toast('Renovación', `Listado de la renovación: ${n} ubicaciones de la póliza anterior.`, 'success');
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
    // En la póliza el domicilio no se cambia (es otra ubicación); en el listado de la renovación sí.
    get domicilioBloqueado() { return this.enPoliza; }

    abrirBaja(e) {
        const ids = e && e.target && e.target.dataset && e.target.dataset.id ? [e.target.dataset.id] : [...this.seleccion];
        if (!ids.length) { return; }
        this.form = { ids, fecha: this.fechaDefault, motivo: '', endoso: '', comentario: '' };
        this.modal = 'baja';
    }
    get bajaNombres() {
        const ids = new Set(this.form.ids || []);
        return this.ubicaciones.filter((u) => ids.has(u.id)).map((u) => ({ id: u.id, texto: this.nombre(u) }));
    }
    get textoBaja() { return `Se darán de baja ${this.bajaNombres.length} ubicaciones.`; }

    abrirAlta() {
        this.form = { nombre: '', direccion: '', giro: '', sumaAsegurada: null, prima: null, inciso: null, fecha: this.fechaDefault, endoso: '' };
        this.modal = 'alta';
    }

    abrirCambio(e) {
        const u = this.ubicaciones.find((x) => x.id === e.target.dataset.id);
        if (!u) { return; }
        this.form = {
            id: u.id, nombreActual: this.nombre(u), original: { ...u }, inciso: u.inciso, nombre: u.nombre || '',
            direccion: u.direccion || '', giro: u.giro || '', sumaAsegurada: u.sumaAsegurada, prima: u.prima,
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
        const campos = [...this.template.querySelectorAll('.modal-form lightning-input, .modal-form lightning-combobox, .modal-form lightning-textarea')];
        return campos.reduce((ok, c) => c.reportValidity() && ok, true);
    }

    async guardarBaja() {
        if (!this.validarForm()) { return; }
        const f = this.form;
        await this.enviar(f.ids.map((id) => ({ tipo: 'baja', id, fecha: f.fecha, motivo: f.motivo || null, endoso: f.endoso, comentario: f.comentario })));
    }

    async guardarAlta() {
        if (!this.validarForm()) { return; }
        const f = this.form;
        const datos = { inciso: f.inciso, nombre: f.nombre, direccion: f.direccion, giro: f.giro, sumaAsegurada: f.sumaAsegurada, prima: f.prima };
        await this.enviar([{ tipo: 'alta', datos, fecha: f.fecha, endoso: f.endoso }]);
    }

    async guardarCambio() {
        if (!this.validarForm()) { return; }
        const f = this.form;
        const o = f.original;
        // Solo se mandan los datos que cambiaron.
        const datos = {};
        const vacio = (a) => (a === '' || a === undefined ? null : a);
        const campos = this.enPoliza ? ['inciso', 'giro', 'sumaAsegurada', 'prima'] : ['nombre', 'direccion', 'giro', 'sumaAsegurada', 'prima'];
        campos.forEach((k) => {
            if (vacio(f[k]) !== vacio(o[k])) { datos[k] = f[k]; }
        });
        if (!Object.keys(datos).length) {
            this.toast('Cambio', 'No modificaste ningún dato.', 'info');
            return;
        }
        await this.enviar([{ tipo: 'cambio', id: f.id, datos, fecha: f.fecha, endoso: f.endoso, comentario: f.comentario }]);
    }

    async enviar(movs) {
        // Endoso de la aseguradora (prima y documento): solo en la póliza.
        const endoso = this.enPoliza ? this.template.querySelector('c-datos-endoso') : null;
        const prima = endoso ? endoso.prima : null;
        this.cargando = true;
        try {
            const r = await aplicar({
                recordId: this._recordId,
                movimientosJson: this.enPoliza ? JSON.stringify({ movimientos: movs, endoso: prima }) : JSON.stringify(movs)
            });
            if (endoso && endoso.tieneArchivo && r.transaccionId) {
                try {
                    await endoso.subir(r.transaccionId);
                } catch (err) {
                    this.dispatchEvent(new ShowToastEvent({ title: 'Endoso', variant: 'warning',
                        message: 'Los movimientos se aplicaron, pero no se pudo adjuntar el documento del endoso. Adjúntalo en la transacción del endoso.' }));
                }
            }
            const partes = [];
            if (r.altas) { partes.push(`${r.altas} altas`); }
            if (r.bajas) { partes.push(`${r.bajas} bajas`); }
            if (r.cambios) { partes.push(`${r.cambios} cambios`); }
            this.toast('Movimientos', (partes.length ? `Aplicados: ${partes.join(', ')}.` : 'No hubo cambios que aplicar.')
                + (r.transaccionId ? ' Quedaron en el endoso de la póliza.' : ''), 'success');
            this.cerrarModal();
            this.vista = 'lista';
            await this.cargar();
            this.avisarCambio();
        } catch (e) {
            this.mostrarError(e);
        } finally {
            this.cargando = false;
        }
    }

    // ============================================================
    // Historial
    // ============================================================
    get historialCompleto() {
        return ((this.datos && this.datos.movimientos) || []).map((m) => ({
            ...m,
            fechaTxt: fechaVisible(m.fecha),
            claseTipo: 'tipo tipo-' + (m.tipo || '').toLowerCase(),
            detalleTxt: [m.motivo, m.detalle, m.comentario].filter((x) => x).join(' · ')
        }));
    }
    // Buscador del historial: folio, tipo, fecha, ubicación, inciso, endoso, detalle o usuario.
    get historial() {
        const q = this.fold(this.busquedaHistorial);
        if (!q) { return this.historialCompleto; }
        return this.historialCompleto.filter((h) => this.fold([h.nombre, h.tipo, h.fechaTxt, h.asegurado, h.certificado, h.endoso,
            h.detalleTxt, h.usuario].filter((x) => x).join(' ')).includes(q));
    }
    handleBusquedaHistorial(e) { this.busquedaHistorial = e.target.value || ''; }
    get sinHistorial() { return this.historialCompleto.length === 0; }
    get sinResultadosHistorial() { return !this.sinHistorial && this.historial.length === 0; }
    get textoResultadosHistorial() {
        return this.busquedaHistorial ? `${this.historial.length} de ${this.historialCompleto.length} movimientos` : '';
    }

    // ============================================================
    // Excel por fecha de movimiento
    // ============================================================
    get enModalExcel() { return this.modal === 'excel'; }
    // Fechas de movimiento que hay (más reciente primero) con cuántos registros tiene cada una.
    abrirExcel() {
        const cuenta = new Map();
        this.ubicaciones.forEach((r) => {
            const k = r.fechaMovimiento ? String(r.fechaMovimiento).substring(0, 10) : '';
            cuenta.set(k, (cuenta.get(k) || 0) + 1);
        });
        this.fechasExcel = [...cuenta.entries()]
            .sort((a, b) => (a[0] === b[0] ? 0 : (a[0] < b[0] ? 1 : -1)))
            .map(([fecha, n]) => ({ key: fecha || 'sin-fecha', fecha, n, sel: false,
                texto: `${fecha ? fechaVisible(fecha) : 'Sin fecha de movimiento'} (${n})` }));
        this.modal = 'excel';
    }
    marcarFechaExcel(e) {
        const key = e.target.dataset.key;
        this.fechasExcel = this.fechasExcel.map((f) => (f.key === key ? { ...f, sel: e.target.checked } : f));
    }
    marcarTodasFechasExcel(e) {
        this.fechasExcel = this.fechasExcel.map((f) => ({ ...f, sel: e.target.checked }));
    }
    get todasFechasExcel() { return this.fechasExcel.length > 0 && this.fechasExcel.every((f) => f.sel); }
    get sinFechasExcel() { return !this.fechasExcel.some((f) => f.sel); }
    get sinFechasMovimiento() { return this.fechasExcel.length === 0; }
    generarExcel() {
        const fechas = new Set(this.fechasExcel.filter((f) => f.sel).map((f) => f.fecha));
        const registros = this.ubicaciones.filter((r) => fechas.has(r.fechaMovimiento ? String(r.fechaMovimiento).substring(0, 10) : ''));
        // Formato de la solicitud de movimientos a la aseguradora (el mismo orden que en asegurados).
        const poliza = (this.datos && this.datos.nombre) || '';
        const columnas = [
                ['Número de movimiento', (r) => r.movimientoNumero || ''], ['Nombre', (r) => r.nombre],
                ['Dirección', (r) => r.direccion], ['Giro', (r) => r.giro],
                ['Movimiento interno', (r) => r.numeroEndoso || ''], ['Tipo de petición', (r) => r.tipoMovimiento || (r.activo ? 'Alta' : 'Baja')],
                ['Fecha de petición', (r) => fechaVisible(r.fechaMovimiento)], ['Poliza', () => poliza],
                ['Inciso', (r) => (r.inciso == null || isNaN(Number(r.inciso)) ? r.inciso : Number(r.inciso))],
                ['Fecha de alta', (r) => fechaVisible(r.fechaAlta)],
                ['Suma asegurada', (r) => (r.sumaAsegurada == null ? null : Number(r.sumaAsegurada))],
                ['Prima', (r) => (r.prima == null ? null : Number(r.prima))],
                ['Descripción', (r) => r.motivoBaja || '']
            ];
        const elegidas = this.fechasExcel.filter((f) => f.sel).map((f) => f.fecha).filter((f) => f).sort();
        const sufijo = elegidas.length === 1 ? elegidas[0] : (elegidas.length ? `${elegidas[0]}_a_${elegidas[elegidas.length - 1]}` : 'sin_fecha');
        descargarExcel(`Ubicaciones_${String(this.datos && this.datos.nombre || '').replace(/[^A-Za-z0-9-]+/g, '_')}_${sufijo}`, 'Ubicaciones',
            columnas.map((c) => c[0]), registros.map((r) => columnas.map((c) => c[1](r))));
        this.cerrarModal();
    }
    fechaHoraTxt(v) {
        if (!v) { return ''; }
        const d = new Date(v);
        return isNaN(d) ? '' : d.toLocaleString('es-MX', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
    }

    // Cierra el movimiento del registro (vehículos y ubicaciones no envían correo): guarda la fecha de cierre.
    async cerrarMov(e) {
        const id = e.currentTarget.dataset.mov;
        this.cargando = true;
        try {
            await cerrarMovimiento({ movimientoId: id });
            this.toast('Movimiento', 'Movimiento cerrado.', 'success');
            await this.cargar();
        } catch (err) {
            this.mostrarError(err);
        } finally {
            this.cargando = false;
        }
    }

    // ============================================================
    // Utilidades
    // ============================================================
    nombre(u) {
        return `${u.inciso ? 'Inciso ' + u.inciso + ' · ' : ''}${u.direccion || u.nombre || 'Ubicación'}`;
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
        this.dispatchEvent(new ShowToastEvent({ title: 'Ubicaciones', message: msg, variant: 'error' }));
    }
    toast(title, message, variant) {
        this.errorMensaje = '';
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
