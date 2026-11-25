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
import { sePuedeEliminar, eliminarRegistro, eliminarSolicitud } from 'c/eliminarMovimiento';
import { fechaVisible, tiempoEntre, moneda, descargarExcel } from 'c/lectorArchivos';
import getDatos from '@salesforce/apex/MovimientosFlotillaController.getDatos';
import datosComponente from '@salesforce/apex/PortalPolizasPestanas.datosComponente';
import cerrarMovimiento from '@salesforce/apex/MovimientosColectivoController.cerrarMovimiento';
import aplicar from '@salesforce/apex/MovimientosFlotillaController.aplicar';
import compararArchivo from '@salesforce/apex/MovimientosFlotillaController.compararArchivo';
import subirArchivo from '@salesforce/apex/MovimientosColectivoController.subirArchivo';
import traerDePoliza from '@salesforce/apex/MovimientosFlotillaController.traerDePoliza';
import { llamar, fijarPortal } from 'c/portalContexto';
// En el sitio las llamadas pasan por PortalPolizasMovimientos (valida la póliza y al contratante).
const aplicarSitio = (p) => llamar('MovimientosFlotilla.aplicar', p, aplicar);
const compararArchivoSitio = (p) => llamar('MovimientosFlotilla.compararArchivo', p, compararArchivo);
const subirArchivoSitio = (p) => llamar('MovimientosColectivo.subirArchivo', p, subirArchivo);
const cerrarMovimientoSitio = (p) => llamar('MovimientosColectivo.cerrarMovimiento', p, cerrarMovimiento);

const POR_PAGINA = 50;
const TIPOS = ['Automóviles', 'Pick-up de carga', 'Camiones', 'Tractocamiones', 'Remolques', 'Autobuses', 'Motocicletas'];

export default class MovimientosFlotilla extends LightningElement {
    @api readOnly = false;
    @track datos = null;
    @track revision = null;
    // Endoso leído del documento de la aseguradora: prima y documento para c-datos-endoso.
    endosoLeido = null;
    documentoEndoso = null;
    @track form = {};
    cargando = false;
    errorMensaje = '';
    vista = 'lista';
    // Filtro de la lista: en la póliza (Salesforce) abre en «Pendientes» (lo que falta por atender); en el sitio y en la
    // oportunidad, en los vigentes.
    filtroElegido = null;
    get filtroInicial() { return this.enPoliza && this.interno ? 'pendientes' : 'vigentes'; }
    get filtro() { return this.filtroElegido || this.filtroInicial; }
    busqueda = '';
    busquedaHistorial = '';
    pagina = 1;
    modal = null;
    solicitudesExcel = [];
    seleccion = new Set();
    archivoNombre = '';
    // Endosos leídos de sus PDF en la carga del archivo (cada uno es un endoso con su número, fecha, prima y documento).
    _endososLeidos = [];
    @track comun = {};
    abierto = false;
    _recordId;
    // Sitio de empresas (portalPolizas): igual que en Salesforce; los datos vienen de PortalPolizasPestanas y las acciones
    // pasan por PortalPolizasMovimientos. No se muestran archivos, correos, Generar Excel ni enlaces a registros de Salesforce.
    @api portal = false;
    @api cuentaVistaPrevia;
    get interno() { return !this.portal; }
    // Sitio, contratante de una póliza empresarial: Nueva solicitud abre el formulario de solicitudes
    // (c-portal-solicitudes, lo muestra c-portal-polizas).
    get conFormulario() { return this.portal && this.puedeEditar && !!this.datos && this.datos.puedeSolicitar === true; }
    get conCarga() { return !this.conFormulario; }
    handleNuevaSolicitud() { this.pedir(null, []); }
    pedir(tipo, ids) { this.dispatchEvent(new CustomEvent('nuevasolicitud', { detail: { tipo, ids } })); }
    // En el sitio de empresas se agrega «mov-portal» para tomar el estilo del sitio (igual que movimientosColectivo).
    get claseRaiz() { return this.portal ? 'mov mov-portal' : 'mov'; }
    // El seguimiento se cambia con un clic solo en Salesforce (en el sitio el cliente solo lo ve).
    // Folio de la aseguradora de cada movimiento: solo en Salesforce.
    get conFolioAseguradora() { return !this.portal; }
    get cambiaSeguimiento() { return this.enPoliza && !this.portal && this.puedeEditar; }

    @api
    get recordId() { return this._recordId; }
    set recordId(v) {
        const cambio = v !== this._recordId;
        this._recordId = v;
        if (cambio) { this.volteadas = new Set(); }
        if (cambio && v) { this.cargar(); }
    }

    @api
    recargar() {
        return this.cargar();
    }

    async cargar() {
        if (!this._recordId) { return; }
        // Espera a que lleguen todas las propiedades (portal, cuentaVistaPrevia) antes de la primera carga.
        await Promise.resolve();
        if (this.portal) { fijarPortal(this._recordId, this.cuentaVistaPrevia); }
        this.cargando = true;
        try {
            this.datos = await (this.portal
                ? datosComponente({ policyId: this._recordId, cuentaVistaPrevia: this.cuentaVistaPrevia || null, tipo: 'vehiculos' })
                : getDatos({ recordId: this._recordId }));
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
    // Petición desde archivo en Salesforce (póliza): no se pide fecha, número de endoso ni comentario; cada movimiento
    // lleva la fecha y el endoso que trae el archivo (sin fecha, la de hoy).
    get pideDatosArchivo() { return !(this.interno && this.enPoliza); }
    get pideEndosoArchivo() { return this.interno && !this.enPoliza; }
    get enOportunidad() { return !!this.datos && this.datos.contexto === 'oportunidad'; }
    // Póliza individual: sin fecha de movimiento ni de cierre (solo las empresariales las muestran). El tipo sale de la
    // oportunidad de origen; si la póliza no viene de una, es individual cuando tiene un solo registro.
    get esIndividual() {
        if (!this.enPoliza) { return false; }
        const t = this.datos.tipoContratacion;
        if (t) { return t !== 'Colectiva'; }
        return (this.datos.vehiculos || []).length <= 1;
    }
    get conFechasMovimiento() { return !this.esIndividual; }
    get conFechaCierre() { return this.enPoliza && !this.esIndividual; }
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
    get enEndosos() { return this.vista === 'endosos'; }
    verLista() { this.vista = 'lista'; this.revision = null; }
    verHistorial() { this.vista = 'historial'; }
    verEndosos() { this.vista = 'endosos'; }
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
            this.interno ? { label: `Pendientes (${this.totalPendientes})`, value: 'pendientes' } : { label: `Vigentes (${this.totalVigentes})`, value: 'vigentes' },
            { label: `Dados de baja (${this.totalBajas})`, value: 'bajas' },
            { label: `Todos (${this.vehiculos.length})`, value: 'todos' }
        ];
    }
    handleFiltro(e) { this.filtroElegido = e.detail.value; this.pagina = 1; }
    // Movimiento por atender: Solicitado o En proceso, de una solicitud que tampoco está concluida ni rechazada.
    esPendiente(x, info) {
        const s = info.get(x.solicitud);
        if (s && s.seguimiento !== 'Solicitado' && s.seguimiento !== 'En proceso') { return false; }
        const seg = this.seguimientoDe(x, info);
        // El estatus de la solicitud es manual: sigue pendiente aunque todos sus registros estén concluidos.
        return seg === 'Solicitado' || seg === 'En proceso' || (this.agrupado && !!s && !s.abiertos);
    }
    tienePendiente(x, info) { return this.esPendiente(x, info) || (x.movimientos || []).some((y) => this.esPendiente(y, info)); }
    // Pendientes como se ven en la tabla: solicitudes (agrupada) o registros.
    get totalPendientes() {
        const info = this.infoSolicitudes;
        if (!this.agrupado) { return this.vehiculos.filter((x) => this.tienePendiente(x, info)).length; }
        const folios = new Set(this.solicitudes.filter((x) => x.portal && !x.total && (x.seguimiento === 'Solicitado' || x.seguimiento === 'En proceso')).map((x) => x.folio));
        this.vehiculos.forEach((x) => {
            const movs = (x.movimientos || []).filter((y) => info.has(y.solicitud));
            (movs.length ? movs : [x]).filter((y) => this.esPendiente(y, info)).forEach((y) => folios.add(movs.length ? y.solicitud : ''));
        });
        return folios.size;
    }
    get sinResultados() { return this.agrupado ? !this.filtradosAgrupados.length : !this.filtrados.length; }
    get textoSinResultados() {
        return this.filtro === 'pendientes' && !this.fold(this.busqueda).trim() ? 'No hay movimientos pendientes por atender.'
            : 'No hay registros con este filtro.' + (this.filtro === 'todos' ? '' : ' Elige «Todos» para buscar en toda la póliza.');
    }
    handleBusqueda(e) {
        const antes = !!this.fold(this.busqueda).trim();
        this.busqueda = e.target.value || '';
        if (antes !== !!this.fold(this.busqueda).trim()) { this.volteadas = new Set(); }
        this.pagina = 1;
    }

    get filtrados() {
        const q = this.fold(this.busqueda);
        const pendientes = this.filtro === 'pendientes';
        const info = pendientes ? this.infoSolicitudes : null;
        return this.vehiculos.filter((v) => {
            if (pendientes && !this.tienePendiente(v, info)) { return false; }
            if (this.filtro === 'vigentes' && !v.activo) { return false; }
            if (this.filtro === 'bajas' && v.activo) { return false; }
            if (!q) { return true; }
            return this.fold(`${v.inciso || ''} ${v.serie || ''} ${v.placas || ''} ${v.descripcion || ''}`).includes(q);
        });
    }
    // ============================================================
    // Solicitudes del cliente: cada registro de movimientos (un archivo, una baja, un alta o un cambio) queda en una
    // solicitud con folio (SOL-0001...). La tabla se agrupa por solicitud, con todos los movimientos de cada registro.
    // ============================================================
    agruparSolicitud = true;
    // Solicitud del sitio que el ejecutivo está atendiendo: los movimientos que registre llevan su folio.
    handleCambioSeguimiento() { this.cargar(); }
    // ===== Eliminar (solo en Salesforce): un registro o toda la solicitud =====
    async handleEliminarRegistro(e) {
        const id = e.currentTarget.dataset.mov;
        const r = this.vehiculos.flatMap((x) => [x, ...this.movimientosDe(x)]).find((x) => x.movimientoId === id);
        if (!r) { return; }
        await this.eliminar(() => eliminarRegistro({ policyId: this._recordId, folio: r.solicitud, movimientoId: id, tipo: r.tipoMovimiento,
            nombre: r.descripcion || 'el registro' }));
    }
    async handleEliminarSolicitud(e) {
        const { folio } = e.currentTarget.dataset;
        await this.eliminar(() => eliminarSolicitud({ policyId: this._recordId, folio, registros: this.registrosDe(folio) }));
    }
    async eliminar(accion) {
        try {
            const hecho = await accion();
            if (!hecho) { return; }
            this.toast('Eliminar', hecho, 'success');
            await this.cargar();
            this.avisarCambio();
        } catch (err) {
            this.mostrarError(err);
        }
    }
    // Las solicitudes salen sin desplegar; al buscar se despliegan para ver los resultados. Aquí van las que el usuario
    // cambió (desplegó o, al buscar, ocultó).
    volteadas = new Set();
    estaColapsada(folio) { return this.volteadas.has(folio) === !!this.fold(this.busqueda).trim(); }
    get solicitudes() { return (this.datos && this.datos.solicitudes) || []; }
    get infoSolicitudes() { return new Map(this.solicitudes.map((x) => [x.folio, x])); }
    // Seguimiento del trámite del registro: Concluido al cerrarse su movimiento; si no, el que se le eligió a mano o el de
    // su solicitud (Solicitado o En proceso). Sin movimiento registrado, nada.
    seguimientoDe(r, info) {
        if (!r.fechaCreacion) { return ''; }
        if (r.seguimientoMov === 'Rechazado') { return 'Rechazado'; }
        if (r.fechaCierre) { return 'Concluido'; }
        if (r.seguimientoMov) { return r.seguimientoMov; }
        const s = (info || this.infoSolicitudes).get(r.solicitud);
        return s && s.seguimiento === 'Solicitado' ? 'Solicitado' : 'En proceso';
    }
    claseSeguimiento(v) {
        return `estado seg-${{ Solicitado: 'solicitado', 'En proceso': 'proceso', Concluido: 'concluido', Rechazado: 'rechazada', Rechazada: 'rechazada' }[v] || 'sin'}`;
    }
    // Encabezados de la tabla: arriba de la tabla sin agrupar y, agrupada, dentro de cada solicitud desplegada
    // (arriba de sus registros).
    get columnasDetalle() {
        const col = (key, label, clase = '') => ({ key, label, clase });
        const l = [col('inciso', 'Inciso'), col('serie', 'Serie'), col('vehiculo', 'Vehículo'), col('modelo', 'Modelo'),
            col('placas', 'Placas'), col('uso', 'Uso'), col('vigencia', 'Vigencia')];
        if (this.conFechasMovimiento) { l.push(col('movimiento', 'Fecha de movimiento')); }
        if (this.enPoliza) { l.push(col('creacion', 'Fecha de creación')); }
        if (this.conFechaCierre) { l.push(col('cierre', 'Fecha de cierre')); }
        l.push(col('valor', 'Valor', 'num'), col('prima', 'Prima', 'num'), col('estado', 'Estado'));
        if (this.enPoliza) { l.push(col('seguimiento', 'Seguimiento')); }
        return l;
    }
    get hayAgrupacion() { return this.enPoliza && this.solicitudes.length > 0; }
    get agrupado() { return this.hayAgrupacion && this.agruparSolicitud; }
    toggleAgrupar(e) { this.agruparSolicitud = e.target.checked; this.pagina = 1; }
    toggleSolicitud(e) {
        const k = e.currentTarget.dataset.folio || '';
        const c = new Set(this.volteadas);
        if (c.has(k)) { c.delete(k); } else { c.add(k); }
        this.volteadas = c;
        if (this.pagina > this.paginas) { this.pagina = this.paginas; }
    }
    // Opciones al registrar: una solicitud nueva o una reciente de la póliza (para agregarle movimientos).
    get opcionesSolicitud() {
        // Sin las rechazadas; las del sitio que siguen por atender van primero.
        const lista = this.solicitudes.filter((x) => x.estadoPortal !== 'Rechazada');
        const orden = [...lista.filter((x) => x.pendiente), ...lista.filter((x) => !x.pendiente).slice(0, 20)];
        return [{ label: 'Nueva solicitud', value: 'nueva' }].concat(orden.map((x) => ({
            label: x.pendiente ? `${x.folio} · del sitio · caso ${x.caso}` : `${x.folio} · ${this.fechaHoraTxt(x.fecha)} · ${x.total} mov.${x.abiertos ? '' : ' · cerrada'}`,
            value: x.folio
        })));
    }
    // Asegurados por solicitud (la más reciente primero; sin solicitud al final) y, dentro, por la columna elegida.
    // Un renglón por cada movimiento del registro que tiene solicitud: la solicitud muestra todo lo que se pidió en ella
    // (altas, bajas y cambios) aunque el registro tenga después otro movimiento.
    movimientosDe(v) {
        return (v.movimientos || []).map((x) => ({ ...v, ...x, esMovimiento: true, filaKey: `${v.id}-${x.movimientoId}`,
            motivoBaja: x.tipoMovimiento === 'Baja' ? v.motivoBaja : null }));
    }
    // Filtro de la tabla para los movimientos de una solicitud («Vigentes» no oculta sus bajas).
    pasaMovimiento(v, info) {
        if (this.filtro === 'pendientes') { return this.esPendiente(v, info); }
        if (this.filtro === 'bajas') { return v.tipoMovimiento === 'Baja'; }
        return true;
    }
    // Registros de una solicitud (o, sin folio, los que no tienen) para el Excel.
    registrosDe(folio) {
        const folios = this.infoSolicitudes;
        return this.vehiculos.flatMap((v) => {
            const movs = this.movimientosDe(v).filter((x) => folios.has(x.solicitud));
            return folio ? movs.filter((x) => x.solicitud === folio) : (movs.length ? [] : [v]);
        });
    }
    // Solicitud del sitio que aún no tiene registros (sin buscar ni filtrar): también sale, para poder atenderla.
    vacia(s) {
        return !!s && s.portal && !s.total && !this.fold(this.busqueda).trim() && this.filtro === this.filtroInicial
            && (s.seguimiento === 'Solicitado' || s.seguimiento === 'En proceso' || (this.portal && s.seguimiento === 'Rechazada'));
    }
    get filtradosAgrupados() {
        const infoVacias = this.infoSolicitudes;
        const porFolio = new Map(this.solicitudes.map((x) => [x.folio, []]));
        porFolio.set('', []);
        const q = this.fold(this.busqueda);
        const sinSolicitud = new Set(this.filtrados.map((v) => v.id));
        this.vehiculos.forEach((v) => {
            const movs = this.movimientosDe(v).filter((x) => porFolio.has(x.solicitud));
            if (!movs.length) {
                if (sinSolicitud.has(v.id)) { porFolio.get('').push(v); }
                return;
            }
            if (q && !this.fold(`${v.inciso || ''} ${v.serie || ''} ${v.placas || ''} ${v.descripcion || ''}`).includes(q)) { return; }
            movs.filter((x) => this.pasaMovimiento(x, infoVacias)).forEach((x) => porFolio.get(x.solicitud).push(x));
        });
        return [...porFolio.entries()].filter(([k, l]) => l.length || this.vacia(infoVacias.get(k))).map(([k, l]) => ({ folio: k, lista: l }));
    }
    // Página actual en bloques: encabezado de la solicitud y sus asegurados (una solicitud colapsada solo muestra el
    // encabezado). Sin agrupar, un solo bloque sin encabezado.
    get bloques() {
        const ini = (this.pagina - 1) * POR_PAGINA;
        const fin = ini + POR_PAGINA;
        if (!this.agrupado) {
            return [{ key: 'todos', encabezado: false, filas: this.filtrados.slice(ini, fin).map((v) => this.decorar(v)) }];
        }
        const info = this.infoSolicitudes;
        const paginas = this.paginas;
        const res = [];
        let n = 0;
        this.filtradosAgrupados.forEach((g) => {
            const colapsada = this.estaColapsada(g.folio);
            const filas = colapsada ? [] : g.lista;
            const visibles = filas.filter((x, i) => n + i >= ini && n + i < fin);
            // Colapsada: el encabezado va en la página donde le toca.
            const pagEnc = Math.min(Math.floor(n / POR_PAGINA) + 1, paginas);
            if (visibles.length || ((colapsada || !filas.length) && pagEnc === this.pagina)) {
                res.push(this.encabezadoSolicitud(g, info.get(g.folio), colapsada, visibles.map((v) => this.decorar(v, info, g.lista)), n < ini && !colapsada));
            }
            n += filas.length;
        });
        return res;
    }
    encabezadoSolicitud(g, s, colapsada, filas, continua) {
        const cuenta = { Alta: 0, Baja: 0, Cambio: 0 };
        g.lista.forEach((v) => {
            const t = v.tipoMovimiento || (v.activo ? 'Alta' : 'Baja');
            cuenta[t] = (cuenta[t] || 0) + 1;
        });
        const partes = [];
        if (cuenta.Alta) { partes.push(`${cuenta.Alta} ${cuenta.Alta === 1 ? 'alta' : 'altas'}`); }
        if (cuenta.Baja) { partes.push(`${cuenta.Baja} ${cuenta.Baja === 1 ? 'baja' : 'bajas'}`); }
        if (cuenta.Cambio) { partes.push(`${cuenta.Cambio} ${cuenta.Cambio === 1 ? 'cambio' : 'cambios'}`); }
        const endosos = [...new Set(g.lista.map((v) => v.numeroEndoso).filter((x) => x))];
        const abiertos = g.lista.filter((v) => v.fechaCreacion && !v.fechaCierre).length;
        const sin = !g.folio;
        // Fecha de apertura (la de la solicitud), fecha de cierre (cuando ya no tiene movimientos abiertos) y seguimiento.
        const creaciones = g.lista.map((v) => v.fechaCreacion).filter((y) => y).sort();
        const cierres = g.lista.map((v) => v.fechaCierre).filter((y) => y).sort();
        const apertura = s && s.fecha ? s.fecha : creaciones[0];
        const cierre = s ? s.cierre : (!abiertos && cierres.length ? cierres[cierres.length - 1] : null);
        const seguimiento = s && s.seguimiento ? s.seguimiento : (abiertos ? 'En proceso' : (creaciones.length ? 'Concluido' : ''));
        return {
            key: 'sol-' + (g.folio || 'sin'),
            encabezado: true,
            folio: g.folio,
            // Número de movimiento solo numérico (SOL-0004 → 0004); los registros sin solicitud son la carga inicial.
            titulo: sin ? 'Carga inicial' : String(g.folio).replace(/^SOL-/i, ''),
            poliza: (this.datos && this.datos.nombre) || '',
            aperturaTxt: this.fechaHoraTxt(apertura) || '—',
            cierreTxt: this.fechaHoraTxt(cierre) || '—',
            // Cuánto tardó en concluirse: de la apertura al cierre.
            respuestaTxt: tiempoEntre(apertura, cierre) || '—',
            seguimiento,
            claseSeguimiento: this.claseSeguimiento(seguimiento),
            // Prima del movimiento: la suma de lo que cobra la aseguradora por cada registro (o el total de sus endosos).
            primaTxt: s && s.prima !== null && s.prima !== undefined ? moneda(s.prima) : '—',
            // Encabezados de los registros, dentro de la solicitud desplegada.
            conEncabezadoDetalle: !colapsada && filas.length > 0,
            sub: sin ? 'Registrados antes de las solicitudes'
                : [s && s.fecha ? this.fechaHoraTxt(s.fecha) : '', s && s.portal ? `Del sitio · caso ${s.caso}${s.usuario ? ' · envió ' + s.usuario : ''}` : (s && s.usuario ? `Registró ${s.usuario}` : '')].filter((x) => x).join(' · '),
            resumen: g.lista.length ? `${g.lista.length} ${g.lista.length === 1 ? 'registro' : 'registros'}${partes.length ? ' · ' + partes.join(', ') : ''}`
                : 'Sin movimientos registrados',
            endososTxt: endosos.length ? `Endoso ${endosos.join(', ')}` : '',
            estadoTxt: sin ? '' : (abiertos ? `Abierta · ${abiertos} sin cerrar` : 'Cerrada'),
            claseEstado: `sol-estado ${abiertos ? 'sol-abierta' : 'sol-cerrada'}`,
            continua,
            icono: colapsada ? 'utility:chevronright' : 'utility:chevrondown',
            textoColapsar: colapsada ? 'Mostrar la solicitud' : 'Ocultar la solicitud',
            // Excel de la solicitud para la aseguradora: solo en Salesforce.
            folioExcel: this.portal || !g.lista.length ? null : g.folio,
            // Seguimiento de toda la solicitud (clic para cambiarlo) y el caso de la que envió el cliente.
            puedeSeguimiento: this.cambiaSeguimiento && !!s && !!seguimiento,
            sinMovimientos: !!s && !s.total,
            puedeEliminar: this.cambiaSeguimiento && !!s && sePuedeEliminar(g.folio, s.seguimiento),
            editaFolioAseguradora: this.cambiaSeguimiento && !!s && !!g.folio,
            folioAseguradora: (s && s.folioAseguradora) || '',
            folioAseguradoraTxt: (s && s.folioAseguradora) || '—',
            ligaCaso: !this.portal && s && s.casoId ? `/lightning/r/Case/${s.casoId}/view` : null,
            casoTxt: s && s.caso ? `Caso ${s.caso}` : '',
            // Respuesta del ejecutivo (motivo del rechazo): la ve el cliente en el sitio.
            respuesta: this.portal && s && s.respuesta ? s.respuesta : '',
            filas
        };
    }
    get columnasTabla() {
        return 12 + (this.conFechasMovimiento ? 1 : 0) + (this.enPoliza ? 4 : 0) + (this.conFechaCierre ? 1 : 0);
    }

    get filas() {
        const ini = (this.pagina - 1) * POR_PAGINA;
        return this.filtrados.slice(ini, ini + POR_PAGINA).map((v) => this.decorar(v));
    }
    // Prima del registro: lo que cobra la aseguradora por su movimiento; en una solicitud sin ese dato, la de la póliza.
    primaDe(x, grupo) {
        const tiene = (y) => y.primaMovimiento !== null && y.primaMovimiento !== undefined;
        if (tiene(x)) { return x.primaMovimiento; }
        return grupo && grupo.some(tiene) ? null : x.prima;
    }
    decorar(v, info, grupo) {
        const seguimiento = this.enPoliza ? this.seguimientoDe(v, info) : '';
        return ({
            ...v,
            filaKey: v.filaKey || v.id,
            seguimiento,
            claseSeguimiento: this.claseSeguimiento(seguimiento),
            // Clic para cambiar el estado del registro (en una solicitud rechazada se cambia el de la solicitud).
            puedeSeguimiento: this.cambiaSeguimiento && !!seguimiento && !!v.movimientoId
                && ((info || this.infoSolicitudes).get(v.solicitud) || {}).seguimiento !== 'Rechazada',
            puedeEliminar: this.cambiaSeguimiento && !!v.movimientoId && sePuedeEliminar(v.solicitud, seguimiento),
            seleccionado: this.seleccion.has(v.id),
            // En el sitio las bajas se piden en Nueva solicitud: no se seleccionan registros.
            noSeleccionable: this.portal || !v.activo || !this.puedeEditar,
            claseFila: (v.esMovimiento ? v.tipoMovimiento !== 'Baja' : v.activo) ? '' : 'fila-baja',
            valorTxt: moneda(v.valor),
            primaTxt: moneda(this.primaDe(v, grupo)),
            vigenciaTxt: this.vigenciaTxt(v),
            fechaMovimientoTxt: fechaVisible(v.fechaMovimiento),
            // Creación del movimiento y su cierre (botón «Cerrar movimiento»).
            fechaCreacionTxt: this.fechaHoraTxt(v.fechaCreacion),
            fechaCierreTxt: this.fechaHoraTxt(v.fechaCierre),
            // Estado = último movimiento: Alta, Baja o Cambio (igual que en asegurados).
            estado: v.tipoMovimiento || (v.activo ? 'Alta' : 'Baja'),
            claseEstado: `estado estado-${String(v.tipoMovimiento || (v.activo ? 'Alta' : 'Baja')).toLowerCase()}`,
            puedeCerrar: this.enPoliza && this.puedeEditar && !!v.movimientoId && !v.fechaCierre,
            puedeMover: v.activo && this.puedeEditar
        });
    }
    get totalPaginable() {
        if (!this.agrupado) { return this.filtrados.length; }
        return this.filtradosAgrupados.reduce((t, g) => t + (this.estaColapsada(g.folio) ? 0 : g.lista.length), 0);
    }
    get paginas() { return Math.max(1, Math.ceil(this.totalPaginable / POR_PAGINA)); }
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
    get etiquetaFecha() {
        if (!this.enPoliza) { return 'Fecha (inicio de la renovación)'; }
        return this.portal ? 'Fecha de movimiento' : 'Fecha en que surte efecto';
    }
    get opcionesTipo() { return TIPOS.map((t) => ({ label: t, value: t })); }

    abrirBaja(e) {
        const ids = e && e.target && e.target.dataset && e.target.dataset.id ? [e.target.dataset.id] : [...this.seleccion];
        if (!ids.length) { return; }
        this.form = { ids, fecha: this.fechaDefault, motivo: '', endoso: '', comentario: '', solicitud: 'nueva' };
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
            inciso: null, fecha: this.fechaDefault, endoso: '', solicitud: 'nueva'
        };
        this.modal = 'alta';
    }

    abrirCambio(e) {
        const v = this.vehiculos.find((x) => x.id === e.target.dataset.id);
        if (!v) { return; }
        // En Salesforce la edición corrige el dato; en el sitio, solo si el movimiento sigue Solicitado.
        const corrige = this.enPoliza && (this.interno || (!!v.movimientoId && this.seguimientoDe(v) === 'Solicitado'));
        this.form = {
            id: v.id, nombreActual: this.nombre(v), original: { ...v }, inciso: v.inciso, serie: v.serie || '',
            descripcion: v.descripcion || '', modelo: v.modelo, placas: v.placas || '', uso: v.uso || '',
            tipoVehiculo: v.tipoVehiculo || '', paquete: v.paquete || '', valor: v.valor, prima: v.prima,
            fecha: this.fechaDefault, endoso: '', comentario: '', solicitud: corrige ? 'correccion' : 'nueva', corrige,
            movimientoId: v.movimientoId || null
        };
        this.modal = 'cambio';
    }

    get opcionesSolicitudCambio() {
        return (this.form.corrige ? [{ label: 'Solo corregir (sin movimiento nuevo)', value: 'correccion' }] : []).concat(this.opcionesSolicitud);
    }
    get registraCambio() { return this.form.solicitud !== 'correccion'; }

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
        await this.enviar(f.ids.map((id) => ({ tipo: 'baja', id, fecha: f.fecha, motivo: f.motivo || null, endoso: f.endoso, comentario: f.comentario })));
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
        const sinMovimiento = this.enPoliza && f.solicitud === 'correccion';
        await this.enviar([{ tipo: 'cambio', id: f.id, datos, fecha: f.fecha, endoso: f.endoso, comentario: f.comentario,
            sinMovimiento, movimientoId: sinMovimiento ? f.movimientoId : null }]);
    }

    async enviar(movs) {
        // Endoso de la aseguradora (prima y documento): solo en la póliza.
        const endoso = this.enPoliza ? this.template.querySelector('c-datos-endoso') : null;
        const prima = endoso ? endoso.prima : null;
        // Endosos leídos de sus PDF: solo en la revisión del archivo.
        if (this.vista !== 'revision') { this._endososLeidos = []; }
        this.cargando = true;
        try {
            const r = await aplicarSitio({
                recordId: this._recordId,
                movimientosJson: this.enPoliza
                    ? JSON.stringify({ movimientos: movs, endoso: prima, endosos: this.primasEndososLeidos(),
                        solicitud: (this.vista === 'revision' ? (this.comun || {}).solicitud : (this.form || {}).solicitud) || 'nueva' })
                    : JSON.stringify(movs)
            });
            if (this.enPoliza) { await this.subirDocumentosEndosos(r.transacciones); }
            this._endososLeidos = [];
            // El documento capturado abajo va al endoso del número general (o al primero, si no hay número general).
            const destino = (r.transacciones && this.comun && this.comun.endoso && r.transacciones[this.comun.endoso.trim()]) || r.transaccionId;
            if (endoso && endoso.tieneArchivo && destino) {
                try {
                    await endoso.subir(destino);
                } catch (err) {
                    this.dispatchEvent(new ShowToastEvent({ title: 'Endoso', variant: 'warning',
                        message: 'Los movimientos se aplicaron, pero no se pudo adjuntar el documento del endoso. Adjúntalo en la transacción del endoso.' }));
                }
            }
            const partes = [];
            if (r.altas) { partes.push(`${r.altas} altas`); }
            if (r.bajas) { partes.push(`${r.bajas} bajas`); }
            if (r.cambios) { partes.push(`${r.cambios} cambios`); }
            this.toast('Movimientos', movs.some((x) => x.sinMovimiento) ? 'Datos corregidos, sin registrar un movimiento nuevo.' : (partes.length ? `Aplicados: ${partes.join(', ')}.` : 'No hubo cambios que aplicar.')
                + (r.transaccionId ? ' Quedaron en el endoso de la póliza.' : '')
                + (r.solicitud ? ` Solicitud ${r.solicitud}.` : ''), 'success');
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

    async handleLeido(e) {
        this.archivoNombre = e.detail.archivo;
        const incisos = e.detail.incisos || [];
        const endosos = e.detail.endosos || [];
        // Cada PDF de endoso es un endoso: sus movimientos llevan su número, fecha y prima, y se le adjunta su PDF.
        // Lo que viene del listado (sin endoso) no es un endoso.
        this._endososLeidos = endosos.filter((x) => x.numero);
        const porFila = e.detail.endososPorFila || {};
        const endosoDeFila = (fila) => (fila === null || fila === undefined ? null : porFila[fila] || null);
        this.cargando = true;
        try {
            const r = incisos.length
                ? await compararArchivoSitio({
                    recordId: this._recordId,
                    incisosJson: JSON.stringify(incisos),
                    // Los vehículos que no vienen en el archivo no se tocan (abajo se quitan las bajas que propone el servidor).
                    censoCompleto: true
                })
                : { altas: [], bajas: [], cambios: [], sinCambios: 0, duplicados: [] };
            this.agregarEndosos(r, endosos);
            this.revision = {
                altas: r.altas.map((a) => ({ ...a, key: 'a' + a.ref, sel: true,
                    endoso: a.endoso || endosoDeFila(incisos[a.ref] ? incisos[a.ref].fila : null) })),
                bajas: r.bajas.filter((b) => !b.faltante).map((b) => ({ ...b, key: 'b' + b.id + (b.endoso || ''), sel: true, motivo: '' })),
                cambios: r.cambios.map((c) => ({ ...c, key: 'c' + c.id, sel: true, endoso: c.endoso || endosoDeFila(c.fila) })),
                sinCambios: r.sinCambios,
                duplicados: (r.duplicados || []).map((d, i) => this.rechazo(d, i))
            };
            // Los datos generales (número, fecha, prima y documento) solo aplican a los movimientos sin endoso propio.
            this.comun = { fecha: this.fechaDefault, endoso: '', motivo: '', comentario: '', solicitud: 'nueva' };
            this.endosoLeido = null;
            this.documentoEndoso = null;
            this.vista = 'revision';
        } catch (err) {
            this.mostrarError(err);
        } finally {
            this.cargando = false;
        }
    }

    // Endosos que no son alta (cambio de datos, baja): el inciso se busca por número entre los vehículos vigentes. Uno
    // de aplicación general (no menciona incisos) es un cambio en cada vehículo vigente.
    agregarEndosos(r, endosos) {
        const vigentes = this.vehiculos.filter((v) => v.activo !== false);
        const porInciso = new Map();
        vigentes.filter((v) => v.inciso !== null && v.inciso !== undefined).forEach((v) => porInciso.set(String(Number(v.inciso)), v));
        const faltan = [];
        endosos.filter((x) => x.movimiento !== 'alta').forEach((x) => {
            const afectados = [];
            if (x.general) {
                afectados.push(...vigentes);
            } else {
                (x.incisos || []).forEach((i) => {
                    const v = porInciso.get(String(Number(i.inciso)));
                    if (v) { afectados.push(v); } else { faltan.push(`inciso ${i.inciso} (endoso ${x.numero || 's/n'})`); }
                });
            }
            afectados.forEach((v) => {
                if (x.movimiento === 'baja') {
                    if (!r.bajas.some((b) => b.id === v.id && b.endoso === x.numero)) {
                        r.bajas.push({ id: v.id, inciso: v.inciso, serie: v.serie, descripcion: v.descripcion, placas: v.placas, faltante: false,
                            endoso: x.numero || null });
                    }
                } else if (!r.cambios.some((c) => c.id === v.id && c.endoso === x.numero)) {
                    r.cambios.push({
                        id: v.id + '|' + (x.numero || ''), registroId: v.id, endoso: x.numero || null,
                        inciso: v.inciso, serie: v.serie, descripcion: v.descripcion, datos: null, diferencias: [],
                        textoEndoso: `Endoso ${x.numero || ''} · ${x.tipo || 'Cambio'}: ${x.detalle || 'sin detalle'}`.replace(/\s+·/, ' ·')
                    });
                }
            });
        });
        if (faltan.length) {
            this.toast(faltan.length === 1 ? 'Movimiento no aplicado' : 'Movimientos no aplicados',
                `${faltan.length === 1 ? 'El siguiente inciso no corresponde' : 'Los siguientes incisos no corresponden'} a ningún vehículo `
                + `vigente de la póliza, por lo que no ${faltan.length === 1 ? 'será procesado' : 'serán procesados'}: ${faltan.join('; ')}. `
                + 'Se recomienda validar la información con la aseguradora.', 'warning');
        }
    }

    // Alta rechazada: viene repetido en el archivo o el vehículo ya está vigente. Se muestra con qué registro choca.
    rechazo(d, i) {
        const base = { ...d, key: 'd' + i, nombre: this.nombre(d), filaTxt: d.fila ? `Registro ${d.fila}` : '—' };
        if (d.repetidoEnArchivo) {
            return { ...base, motivo: 'Viene repetido en el archivo (misma serie o placas)',
                existenteTxt: `Igual al registro ${d.filaOriginal} del archivo: se toma una sola vez.` };
        }
        const datos = [
            d.incisoExistente ? `Inciso ${d.incisoExistente}` : null,
            d.descripcionExistente,
            d.modeloExistente ? `modelo ${d.modeloExistente}` : null,
            d.serieExistente ? `serie ${d.serieExistente}` : null,
            d.placasExistente ? `placas ${d.placasExistente}` : null,
            d.fechaAlta ? `alta ${fechaVisible(d.fechaAlta)}` : null
        ].filter((x) => x);
        return { ...base, motivo: `Ya está vigente en ${this.enPoliza ? 'la póliza' : 'el censo'} con los mismos datos`,
            existenteTxt: datos.join(' · ') };
    }

    get altasRev() {
        return (this.revision ? this.revision.altas : []).map((a) => ({ ...a, valorTxt: moneda(a.valor), primaTxt: moneda(a.prima) }));
    }
    get bajasRev() { return this.revision ? this.revision.bajas : []; }
    get cambiosRev() {
        return (this.revision ? this.revision.cambios : []).map((c) => ({
            ...c,
            difs: c.textoEndoso
                ? [{ key: c.key + 'e', texto: c.textoEndoso }]
                : c.diferencias.map((d, i) => ({ key: c.key + i, texto: `${d.campo}: ${d.antes} → ${d.despues}` }))
        }));
    }
    get hayAltas() { return this.altasRev.length > 0; }
    get hayBajas() { return this.bajasRev.length > 0; }
    get hayCambios() { return this.cambiosRev.length > 0; }
    get sinDiferencias() { return !this.hayAltas && !this.hayBajas && !this.hayCambios; }
    get textoAltas() { return `Altas (${this.altasRev.length})`; }
    get duplicadosRev() { return this.revision ? this.revision.duplicados || [] : []; }
    get hayDuplicados() { return this.duplicadosRev.length > 0; }
    get textoDuplicados() {
        return `Altas rechazadas (${this.duplicadosRev.length}): ya existen.`;
    }
    get textoBajas() { return `Bajas (${this.bajasRev.length})`; }
    get todasBajas() { return this.bajasRev.length > 0 && this.bajasRev.every((b) => b.sel); }
    get hayFaltantes() { return this.bajasRev.some((b) => b.faltante); }
    get textoFaltantes() {
        const n = this.bajasRev.filter((b) => b.faltante).length;
        return `${n} vehículos vigentes no vienen en el archivo. Están desmarcados: marca solo los que sí se dan de baja `
            + '(si el archivo es el censo completo, usa la casilla del encabezado para marcarlos todos).';
    }
    get textoCambios() { return `Cambios (${this.cambiosRev.length})`; }
    get textoSinCambios() { return `${this.revision ? this.revision.sinCambios : 0} vehículos del archivo ya existen igual y no se tocan.`; }

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
            // El motivo es opcional.
            movs.push({ tipo: 'baja', id: b.id, motivo: b.motivo || c.motivo || null, ...this.datosDeEndoso(b.endoso) });
        });
        this.revision.cambios.filter((x) => x.sel).forEach((x) => {
            movs.push({ tipo: 'cambio', id: x.registroId || x.id, datos: x.datos, ...this.datosDeEndoso(x.endoso) });
        });
        this.revision.altas.filter((a) => a.sel).forEach((a) => {
            movs.push({ tipo: 'alta', datos: a.datos, ...this.datosDeEndoso(a.endoso) });
        });
        if (!movs.length) {
            this.toast('Movimientos', 'No seleccionaste ningún movimiento.', 'info');
            return;
        }
        await this.enviar(movs);
    }

    // Número, fecha y comentario del movimiento: los de su endoso (leído de su PDF) o, sin endoso, los generales.
    datosDeEndoso(numero) {
        const c = this.comun;
        const x = numero ? (this._endososLeidos || []).find((y) => y.numero === numero) : null;
        if (!x) { return { fecha: c.fecha, endoso: c.endoso, comentario: c.comentario }; }
        return {
            fecha: x.fecha || c.fecha,
            endoso: x.numero,
            comentario: c.comentario || [x.tipo, x.detalle].filter((y) => y).join(': ').substring(0, 255)
        };
    }
    get hayEndososLeidos() { return (this._endososLeidos || []).length > 0; }
    get textoEndososLeidos() {
        const l = (this._endososLeidos || []).map((x) => `${x.numero} (${x.archivo})`);
        return `Se registra un endoso por cada PDF, con su fecha, prima y documento: ${l.join(', ')}. `
            + 'Los movimientos del listado no son endosos: solo llevan número si lo capturas abajo.';
    }
    // Prima de cada endoso leído, por número.
    primasEndososLeidos() {
        const res = {};
        (this._endososLeidos || []).forEach((x) => {
            if ([x.primaNeta, x.derechos, x.iva, x.total].some((v) => v !== null && v !== undefined)) {
                res[x.numero] = { primaNeta: x.primaNeta, derechos: x.derechos, iva: x.iva, total: x.total };
            }
        });
        return res;
    }
    // Sube el PDF de cada endoso leído a su endoso (transacción).
    async subirDocumentosEndosos(transacciones) {
        const fallas = [];
        for (const x of this._endososLeidos || []) {
            const tId = transacciones && transacciones[x.numero];
            if (!x.documento || !tId) { continue; }
            try {
                // eslint-disable-next-line no-await-in-loop
                const base64 = await new Promise((resolve, reject) => {
                    const lector = new FileReader();
                    lector.onload = () => resolve(String(lector.result).split(',')[1]);
                    lector.onerror = () => reject(lector.error);
                    lector.readAsDataURL(x.documento);
                });
                // eslint-disable-next-line no-await-in-loop
                await subirArchivoSitio({ recordId: tId, nombre: x.documento.name, base64 });
            } catch (err) {
                fallas.push(x.numero);
            }
        }
        if (fallas.length) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Endoso', variant: 'warning',
                message: `Los movimientos se aplicaron, pero no se pudo adjuntar el PDF del endoso ${fallas.join(', ')}. Adjúntalo en el endoso.` }));
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
    // Buscador del historial: folio, tipo, fecha, vehículo, inciso, endoso, detalle o usuario.
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
    // Solicitudes (folio) que tienen registros, la más reciente primero, con cuántos registros tiene cada una.
    abrirExcel() {
        const porFolio = new Map();
        const folios = this.infoSolicitudes;
        this.vehiculos.flatMap((r) => {
            const movs = this.movimientosDe(r).filter((x) => folios.has(x.solicitud));
            return movs.length ? movs : [{ ...r, solicitud: '' }];
        }).forEach((r) => {
            const folio = r.solicitud || '';
            const fecha = r.fechaMovimiento ? String(r.fechaMovimiento).substring(0, 10) : '';
            const s = porFolio.get(folio) || { n: 0, fecha: '' };
            s.n += 1;
            if (fecha > s.fecha) { s.fecha = fecha; }
            porFolio.set(folio, s);
        });
        this.solicitudesExcel = [...porFolio.entries()]
            .sort((a, b) => {
                if (!a[0] !== !b[0]) { return a[0] ? -1 : 1; }          // "Sin solicitud" al final
                return b[0].localeCompare(a[0], 'es', { numeric: true });  // folio más reciente primero
            })
            .map(([folio, s]) => ({
                key: folio || 'sin-solicitud',
                folio,
                sel: false,
                titulo: folio || 'Sin solicitud',
                detalle: `${s.n} ${s.n === 1 ? 'registro' : 'registros'}${s.fecha ? ' · último movimiento ' + fechaVisible(s.fecha) : ''}`
            }));
        if (this.solicitudesExcel.length === 1) { this.solicitudesExcel[0].sel = true; }
        this.modal = 'excel';
    }
    elegirSolicitudExcel(e) {
        const key = e.target.dataset.key;
        this.solicitudesExcel = this.solicitudesExcel.map((s) => ({ ...s, sel: s.key === key }));
    }
    get sinSolicitudElegida() { return !this.solicitudesExcel.some((s) => s.sel); }
    get sinSolicitudesExcel() { return this.solicitudesExcel.length === 0; }
    generarExcel() {
        const elegida = this.solicitudesExcel.find((s) => s.sel);
        if (!elegida) { return; }
        const registros = this.registrosDe(elegida.folio);
        this.excelDe(registros, elegida.folio || 'sin_solicitud');
        this.cerrarModal();
    }
    // Excel solo con los registros de una solicitud (el que se envía a la aseguradora): desde el encabezado de la
    // solicitud en la tabla o desde las solicitudes del sitio.
    handleExcelSolicitud(e) {
        const folio = (e.detail && e.detail.folio) || (e.currentTarget && e.currentTarget.dataset.folio);
        const registros = this.registrosDe(folio);
        if (!registros.length) {
            this.toast('Excel', `La solicitud ${folio} no tiene registros.`, 'info');
            return;
        }
        this.excelDe(registros, folio);
    }
    excelDe(registros, sufijo) {
        // Formato de la solicitud de movimientos a la aseguradora (el mismo orden que en asegurados).
        const poliza = (this.datos && this.datos.nombre) || '';
        const columnas = [
                ['Vehículo', (r) => r.descripcion], ['Serie', (r) => r.serie],
                ['Modelo', (r) => (r.modelo == null ? null : Number(r.modelo))], ['Placas', (r) => r.placas], ['Uso', (r) => r.uso],
                ['Tipo de petición', (r) => r.tipoMovimiento || (r.activo ? 'Alta' : 'Baja')],
                ['Fecha de petición', (r) => fechaVisible(r.fechaMovimiento)], ['Poliza', () => poliza], ['Paquete', (r) => r.paquete],
                ['Inciso', (r) => (r.inciso == null ? null : Number(r.inciso))], ['Vigencia desde', (r) => fechaVisible(this.vigenciaDesde(r))],
                ['Vigencia hasta', (r) => fechaVisible(this.vigenciaHasta(r))],
                ['Valor', (r) => (r.valor == null ? null : Number(r.valor))], ['Prima', (r) => (r.prima == null ? null : Number(r.prima))],
                ['Descripción', (r) => r.motivoBaja || '']
            ];
        descargarExcel(`Vehiculos_${String(this.datos && this.datos.nombre || '').replace(/[^A-Za-z0-9-]+/g, '_')}_${sufijo}`, 'Vehículos',
            columnas.map((c) => c[0]), registros.map((r) => columnas.map((c) => c[1](r))));
    }
    // Vigencia del vehículo: desde su alta (o el inicio de la póliza) hasta su baja (o el fin de la póliza).
    vigenciaDesde(v) { return v.fechaAlta || (this.datos && this.datos.inicio) || null; }
    vigenciaHasta(v) { return v.fechaBaja || (this.datos && this.datos.fin) || null; }
    vigenciaTxt(v) {
        const d = fechaVisible(this.vigenciaDesde(v));
        const h = fechaVisible(this.vigenciaHasta(v));
        return d && h ? `${d} – ${h}` : (d || h || '');
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
            await cerrarMovimientoSitio({ movimientoId: id });
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

    // Abre la ventana con las otras pólizas (de cualquier aseguradora) donde ya existe el registro.
    verOtrasPolizas(e) {
        const { id, titulo } = e.currentTarget.dataset;
        const v = this.template.querySelector('c-otras-polizas');
        if (v && id) { v.abrir(id, this._recordId, titulo); }
    }
}
