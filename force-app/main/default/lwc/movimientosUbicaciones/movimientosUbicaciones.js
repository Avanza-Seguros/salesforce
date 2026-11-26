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
import { sePuedeEliminar, eliminarRegistro, eliminarSolicitud } from 'c/eliminarMovimiento';
import { fold, fechaVisible, tiempoEntre, moneda, descargarExcel, paginasPdf, abrirTabla } from 'c/lectorArchivos';
import { endosoDeTexto, especificacionUbicacion, mapeoComo, ubicacionesDesdeTabla, TIPOS } from 'c/clasificadorArchivos';
import getDatos from '@salesforce/apex/MovimientosUbicacionesController.getDatos';
import datosComponente from '@salesforce/apex/PortalPolizasPestanas.datosComponente';
import cerrarMovimiento from '@salesforce/apex/MovimientosColectivoController.cerrarMovimiento';
import aplicar from '@salesforce/apex/MovimientosUbicacionesController.aplicar';
import traerDePoliza from '@salesforce/apex/MovimientosUbicacionesController.traerDePoliza';
import { llamar, fijarPortal } from 'c/portalContexto';
// En el sitio las llamadas pasan por PortalPolizasMovimientos (valida la póliza y al contratante).
const aplicarSitio = (p) => llamar('MovimientosUbicaciones.aplicar', p, aplicar);
const cerrarMovimientoSitio = (p) => llamar('MovimientosColectivo.cerrarMovimiento', p, cerrarMovimiento);

const POR_PAGINA = 50;

// Domicilio comparable: sin acentos, signos, "C.P." ni palabras de relleno ("No.", "Num.", "Col.").
function llaveDomicilio(v) {
    return fold(v).replace(/\b(c p|cp|codigo postal|no|num|numero|col|colonia|int|ext|interior|exterior)\b/g, ' ')
        .replace(/\s+/g, '');
}

// Ubicaciones de un PDF de póliza de Daños de Afirme: una "ESPECIFICACIÓN UBICACIÓN n" por inciso.
function ubicacionesDePdf(texto) {
    const numeros = [...new Set([...String(texto || '').matchAll(/ESPECIFICACI[OÓ]N\s+UBICACI[OÓ]N\s+(\d+)/gi)].map((m) => m[1]))];
    return numeros.map((n) => ({ inciso: n, ...especificacionUbicacion(texto, n) })).filter((u) => u.direccion);
}

export default class MovimientosUbicaciones extends LightningElement {
    @api readOnly = false;
    @track datos = null;
    @track form = {};
    // Endoso leído del PDF de la aseguradora: tipo, detalle, ubicaciones que toca, prima y el documento.
    @track endosoInfo = null;
    // Revisión del archivo de ubicaciones: altas, bajas, cambios y repetidas.
    @track revision = null;
    @track comun = {};
    archivoNombre = '';
    endosoLeido = null;
    documentoEndoso = null;
    cargando = false;
    errorMensaje = '';
    vista = 'lista';
    // Filtro de la lista: en la póliza (Salesforce) abre en «Pendientes» (lo que falta por atender); en el sitio y en la
    // oportunidad, en los vigentes.
    filtroElegido = null;
    get filtroInicial() { return this.enPoliza && this.interno && !this.sinTramite ? 'pendientes' : 'vigentes'; }
    // Ubicaciones en Salesforce: no siguen el trámite de GMM (solicitudes, seguimiento, pendientes); las altas, bajas,
    // cambios y cargas se aplican y las ubicaciones se van agregando.
    get sinTramite() { return this.enPoliza && this.interno; }
    get filtro() { return this.filtroElegido || this.filtroInicial; }
    busqueda = '';
    busquedaHistorial = '';
    pagina = 1;
    modal = null;
    solicitudesExcel = [];
    seleccion = new Set();
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
    get cambiaSeguimiento() { return this.enPoliza && !this.portal && this.puedeEditar && !this.sinTramite; }

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
                ? datosComponente({ policyId: this._recordId, cuentaVistaPrevia: this.cuentaVistaPrevia || null, tipo: 'ubicaciones' })
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
        return (this.datos.ubicaciones || []).length <= 1;
    }
    get conFechasMovimiento() { return !this.esIndividual; }
    get conFechaCierre() { return this.enPoliza && !this.esIndividual && !this.sinTramite; }
    // Fecha de creación y seguimiento del movimiento: solo con el trámite (el sitio).
    get conTramite() { return this.enPoliza && !this.sinTramite; }
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
    get enEndosos() { return this.vista === 'endosos'; }
    verLista() { this.vista = 'lista'; this.revision = null; }
    verHistorial() { this.vista = 'historial'; }
    verEndosos() { this.vista = 'endosos'; }

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
            this.interno && !this.sinTramite ? { label: `Pendientes (${this.totalPendientes})`, value: 'pendientes' } : { label: `Vigentes (${this.totalVigentes})`, value: 'vigentes' },
            { label: `Dadas de baja (${this.totalBajas})`, value: 'bajas' },
            { label: `Todas (${this.ubicaciones.length})`, value: 'todos' }
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
        if (!this.agrupado) { return this.ubicaciones.filter((x) => this.tienePendiente(x, info)).length; }
        const folios = new Set(this.solicitudes.filter((x) => x.portal && !x.total && (x.seguimiento === 'Solicitado' || x.seguimiento === 'En proceso')).map((x) => x.folio));
        this.ubicaciones.forEach((x) => {
            const movs = (x.movimientos || []).filter((y) => info.has(y.solicitud));
            (movs.length ? movs : [x]).filter((y) => this.esPendiente(y, info)).forEach((y) => folios.add(movs.length ? y.solicitud : ''));
        });
        return folios.size;
    }
    get sinResultados() { return this.agrupado ? !this.filtradosAgrupados.length : !this.filtrados.length; }
    get textoSinResultados() {
        return this.filtro === 'pendientes' && !this.fold(this.busqueda).trim() ? 'No hay movimientos pendientes por atender.'
            : 'No hay registros con este filtro.' + (this.filtro === 'todos' ? '' : ' Elige «Todas» para buscar en toda la póliza.');
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
        return this.ubicaciones.filter((u) => {
            if (pendientes && !this.tienePendiente(u, info)) { return false; }
            if (this.filtro === 'vigentes' && !u.activo) { return false; }
            if (this.filtro === 'bajas' && u.activo) { return false; }
            if (!q) { return true; }
            return this.fold(`${u.inciso || ''} ${u.nombre || ''} ${u.direccion || ''} ${u.giro || ''}`).includes(q);
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
        const r = this.ubicaciones.flatMap((x) => [x, ...this.movimientosDe(x)]).find((x) => x.movimientoId === id);
        if (!r) { return; }
        await this.eliminar(() => eliminarRegistro({ policyId: this._recordId, folio: r.solicitud, movimientoId: id, tipo: r.tipoMovimiento,
            nombre: r.direccion || 'el registro' }));
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
        const l = [col('inciso', 'Inciso'), col('ubicacion', 'Ubicación'), col('giro', 'Giro'), col('alta', 'Fecha de alta')];
        if (this.conFechasMovimiento) { l.push(col('movimiento', 'Fecha de movimiento')); }
        if (this.conTramite) { l.push(col('creacion', 'Fecha de creación')); }
        if (this.conFechaCierre) { l.push(col('cierre', 'Fecha de cierre')); }
        l.push(col('suma', 'Suma asegurada', 'num'), col('prima', 'Prima', 'num'), col('estado', 'Estado'));
        if (this.conTramite) { l.push(col('seguimiento', 'Seguimiento')); }
        return l;
    }
    get hayAgrupacion() { return this.conTramite && this.solicitudes.length > 0; }
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
    movimientosDe(u) {
        return (u.movimientos || []).map((x) => ({ ...u, ...x, esMovimiento: true, filaKey: `${u.id}-${x.movimientoId}`,
            motivoBaja: x.tipoMovimiento === 'Baja' ? u.motivoBaja : null }));
    }
    // Filtro de la tabla para los movimientos de una solicitud («Vigentes» no oculta sus bajas).
    pasaMovimiento(u, info) {
        if (this.filtro === 'pendientes') { return this.esPendiente(u, info); }
        if (this.filtro === 'bajas') { return u.tipoMovimiento === 'Baja'; }
        return true;
    }
    // Registros de una solicitud (o, sin folio, los que no tienen) para el Excel.
    registrosDe(folio) {
        const folios = this.infoSolicitudes;
        return this.ubicaciones.flatMap((u) => {
            const movs = this.movimientosDe(u).filter((x) => folios.has(x.solicitud));
            return folio ? movs.filter((x) => x.solicitud === folio) : (movs.length ? [] : [u]);
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
        const sinSolicitud = new Set(this.filtrados.map((u) => u.id));
        this.ubicaciones.forEach((u) => {
            const movs = this.movimientosDe(u).filter((x) => porFolio.has(x.solicitud));
            if (!movs.length) {
                if (sinSolicitud.has(u.id)) { porFolio.get('').push(u); }
                return;
            }
            if (q && !this.fold(`${u.inciso || ''} ${u.nombre || ''} ${u.direccion || ''} ${u.giro || ''}`).includes(q)) { return; }
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
            return [{ key: 'todos', encabezado: false, filas: this.filtrados.slice(ini, fin).map((u) => this.decorar(u)) }];
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
                res.push(this.encabezadoSolicitud(g, info.get(g.folio), colapsada, visibles.map((u) => this.decorar(u, info, g.lista)), n < ini && !colapsada));
            }
            n += filas.length;
        });
        return res;
    }
    encabezadoSolicitud(g, s, colapsada, filas, continua) {
        const cuenta = { Alta: 0, Baja: 0, Cambio: 0 };
        g.lista.forEach((u) => {
            const t = u.tipoMovimiento || (u.activo ? 'Alta' : 'Baja');
            cuenta[t] = (cuenta[t] || 0) + 1;
        });
        const partes = [];
        if (cuenta.Alta) { partes.push(`${cuenta.Alta} ${cuenta.Alta === 1 ? 'alta' : 'altas'}`); }
        if (cuenta.Baja) { partes.push(`${cuenta.Baja} ${cuenta.Baja === 1 ? 'baja' : 'bajas'}`); }
        if (cuenta.Cambio) { partes.push(`${cuenta.Cambio} ${cuenta.Cambio === 1 ? 'cambio' : 'cambios'}`); }
        const endosos = [...new Set(g.lista.map((u) => u.numeroEndoso).filter((x) => x))];
        const abiertos = g.lista.filter((u) => u.fechaCreacion && !u.fechaCierre).length;
        const sin = !g.folio;
        // Fecha de apertura (la de la solicitud), fecha de cierre (cuando ya no tiene movimientos abiertos) y seguimiento.
        const creaciones = g.lista.map((u) => u.fechaCreacion).filter((y) => y).sort();
        const cierres = g.lista.map((u) => u.fechaCierre).filter((y) => y).sort();
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
        return 9 + (this.conFechasMovimiento ? 1 : 0) + (this.conTramite ? 4 : 0) + (this.conFechaCierre ? 1 : 0);
    }

    get filas() {
        const ini = (this.pagina - 1) * POR_PAGINA;
        return this.filtrados.slice(ini, ini + POR_PAGINA).map((u) => this.decorar(u));
    }
    // Prima del registro: lo que cobra la aseguradora por su movimiento; en una solicitud sin ese dato, la de la póliza.
    primaDe(x, grupo) {
        const tiene = (y) => y.primaMovimiento !== null && y.primaMovimiento !== undefined;
        if (tiene(x)) { return x.primaMovimiento; }
        return grupo && grupo.some(tiene) ? null : x.prima;
    }
    decorar(u, info, grupo) {
        const seguimiento = this.enPoliza ? this.seguimientoDe(u, info) : '';
        return ({
            ...u,
            filaKey: u.filaKey || u.id,
            seguimiento,
            claseSeguimiento: this.claseSeguimiento(seguimiento),
            // Clic para cambiar el estado del registro (en una solicitud rechazada se cambia el de la solicitud).
            puedeSeguimiento: this.cambiaSeguimiento && !!seguimiento && !!u.movimientoId
                && ((info || this.infoSolicitudes).get(u.solicitud) || {}).seguimiento !== 'Rechazada',
            puedeEliminar: this.cambiaSeguimiento && !!u.movimientoId && sePuedeEliminar(u.solicitud, seguimiento),
            seleccionado: this.seleccion.has(u.id),
            // En el sitio las bajas se piden en Nueva solicitud: no se seleccionan registros.
            noSeleccionable: this.portal || !u.activo || !this.puedeEditar,
            claseFila: (u.esMovimiento ? u.tipoMovimiento !== 'Baja' : u.activo) ? '' : 'fila-baja',
            sumaTxt: moneda(u.sumaAsegurada),
            primaTxt: moneda(this.primaDe(u, grupo)),
            altaTxt: fechaVisible(u.fechaAlta),
            fechaMovimientoTxt: fechaVisible(u.fechaMovimiento),
            // Creación del movimiento y su cierre (botón «Cerrar movimiento»).
            fechaCreacionTxt: this.fechaHoraTxt(u.fechaCreacion),
            fechaCierreTxt: this.fechaHoraTxt(u.fechaCierre),
            // Estado = último movimiento: Alta, Baja o Cambio (igual que en asegurados).
            estado: u.tipoMovimiento || (u.activo ? 'Alta' : 'Baja'),
            conDetalleCambio: u.tipoMovimiento === 'Cambio' && !!u.detalleMovimiento,
            claseEstado: `estado estado-${String(u.tipoMovimiento || (u.activo ? 'Alta' : 'Baja')).toLowerCase()}`,
            // Sin trámite los movimientos nacen cerrados; solo los abiertos de antes se cierran aquí.
            puedeCerrar: this.enPoliza && this.puedeEditar && !!u.movimientoId && !u.fechaCierre,
            puedeMover: u.activo && this.puedeEditar
        });
    }
    get totalPaginable() {
        if (!this.agrupado) { return this.filtrados.length; }
        return this.filtradosAgrupados.reduce((t, g) => t + (this.estaColapsada(g.folio) ? 0 : g.lista.length), 0);
    }
    get paginas() { return Math.max(1, Math.ceil(this.totalPaginable / POR_PAGINA)); }
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
    // ============================================================
    // Detalle del cambio (solo consulta): lo que se pidió cambiar, dato por dato.
    // ============================================================
    detalleCambio = null;
    get enModalDetalleCambio() { return this.modal === 'detalleCambio'; }
    verDetalleCambio(e) {
        const { detalle, titulo } = e.currentTarget.dataset;
        const filas = String(detalle || '').split(/\r?\n/).map((x) => x.trim()).filter((x) => x).map((linea, i) => {
            const dp = linea.indexOf(': ');
            const resto = dp > 0 ? linea.slice(dp + 2) : '';
            const fl = resto.indexOf(' → ');
            return fl >= 0
                ? { key: `c${i}`, conFlecha: true, campo: linea.slice(0, dp), antes: resto.slice(0, fl), despues: resto.slice(fl + 3) }
                : { key: `c${i}`, conFlecha: false, texto: linea };
        });
        this.detalleCambio = { titulo: titulo || '', filas };
        this.modal = 'detalleCambio';
    }
    get hayModal() { return !!this.modal; }
    get enModalEndoso() { return this.modal === 'endoso'; }
    cerrarModal() { this.modal = null; this.form = {}; this.endosoInfo = null; this.endosoLeido = null; this.documentoEndoso = null; }

    // ============================================================
    // Endoso de la aseguradora (PDF): se lee sin IA y se aplica como cambio (o baja) de las ubicaciones que toca.
    // Uno de aplicación general (no menciona ubicaciones) es un cambio en cada ubicación vigente.
    // ============================================================
    // Abre el modal del endoso con lo que toca; false si el texto no es un endoso.
    leerEndoso(file, texto) {
        const x = endosoDeTexto(texto, file.name);
        if (!x) { return false; }
        // Lo que toca el endoso: de aplicación general, todas las ubicaciones vigentes; si trae incisos, cada uno con
        // su movimiento (el alta trae los datos de la ubicación nueva; la baja y el cambio se buscan por inciso).
        const vigentes = this.ubicaciones.filter((u) => u.activo !== false);
        const porInciso = new Map();
        vigentes.filter((u) => u.inciso !== null && u.inciso !== undefined).forEach((u) => porInciso.set(String(Number(u.inciso)), u));
        const etiqueta = { alta: 'Alta', baja: 'Baja', cambio: 'Cambio' };
        const objetivos = [];
        const faltan = [];
        if (x.general) {
            vigentes.forEach((u) => objetivos.push({ key: u.id, id: u.id, tipo: x.movimiento === 'baja' ? 'baja' : 'cambio' }));
        } else {
            (x.incisos || []).forEach((i) => {
                const tipo = i.movimiento || x.movimiento;
                if (tipo === 'alta') {
                    objetivos.push({ key: 'a' + i.inciso, tipo, datos: {
                        inciso: Number(i.inciso), direccion: i.direccion || '', giro: i.giro || '',
                        sumaAsegurada: i.sumaAsegurada ?? null, prima: i.prima ?? null } });
                    return;
                }
                const u = porInciso.get(String(Number(i.inciso)));
                if (!u) { faltan.push(i.inciso); return; }
                // Cambio con la especificación de la ubicación: la suma asegurada a quedar se actualiza.
                const nuevaSuma = tipo === 'cambio' && i.sumaAsegurada && Math.abs(Number(u.sumaAsegurada || 0) - i.sumaAsegurada) >= 0.5
                    ? i.sumaAsegurada : null;
                objetivos.push({ key: u.id, id: u.id, tipo, datos: nuevaSuma ? { sumaAsegurada: nuevaSuma } : null,
                    sumaAntes: u.sumaAsegurada });
            });
        }
        if (faltan.length) {
            this.toast(faltan.length === 1 ? 'Movimiento no aplicado' : 'Movimientos no aplicados',
                `${faltan.length === 1 ? 'El inciso' : 'Los incisos'} ${faltan.join(', ')} del endoso ${x.numero || 's/n'} no `
                + `${faltan.length === 1 ? 'corresponde' : 'corresponden'} a ninguna ubicación vigente de la póliza, por lo que no `
                + `${faltan.length === 1 ? 'será procesado' : 'serán procesados'}. Se recomienda validar la información con la aseguradora.`, 'warning');
        }
        const porId = new Map(vigentes.map((u) => [u.id, u]));
        this.endosoInfo = {
            ...x,
            archivo: file.name,
            alcance: x.general
                ? `Aplicación general: se registra ${x.movimiento === 'baja' ? 'la baja de' : 'un cambio en'} cada ubicación vigente.`
                : `Movimientos al inciso: ${(x.incisos || []).map((i) => i.inciso).join(', ')}.`,
            objetivos: objetivos.map((o) => ({
                ...o,
                sel: true,
                texto: o.tipo === 'alta'
                    ? `Alta · Inciso ${o.datos.inciso} · ${o.datos.direccion || 'sin domicilio'}`
                        + (o.datos.sumaAsegurada ? ` · Suma asegurada ${moneda(o.datos.sumaAsegurada)}` : '')
                    : `${etiqueta[o.tipo]} · ${this.nombre(porId.get(o.id))}`
                        + (o.datos && o.datos.sumaAsegurada ? ` · Suma asegurada ${moneda(o.sumaAntes) || '—'} → ${moneda(o.datos.sumaAsegurada)}` : '')
            }))
        };
        this.form = {
            fecha: x.fecha || this.fechaDefault,
            endoso: x.numero || '',
            motivo: '',
            comentario: [x.tipo, x.detalle].filter((y) => y).join(': ').substring(0, 255)
        };
        const conPrima = [x.primaNeta, x.derechos, x.iva, x.total].some((v) => v !== null && v !== undefined);
        this.endosoLeido = conPrima ? { primaNeta: x.primaNeta, derechos: x.derechos, iva: x.iva, total: x.total } : null;
        this.documentoEndoso = file;
        this.modal = 'endoso';
        return true;
    }
    get objetivosEndoso() { return this.endosoInfo ? this.endosoInfo.objetivos : []; }
    get todosObjetivosEndoso() { return this.objetivosEndoso.length > 0 && this.objetivosEndoso.every((o) => o.sel); }
    get textoObjetivosEndoso() {
        const n = this.objetivosEndoso.filter((o) => o.sel).length;
        return `${n} de ${this.objetivosEndoso.length} ubicaciones`;
    }
    get sinObjetivosEndoso() { return !this.objetivosEndoso.some((o) => o.sel); }
    get hayBajasEndoso() { return this.objetivosEndoso.some((o) => o.tipo === 'baja'); }
    marcarObjetivoEndoso(e) {
        const key = e.target.dataset.key;
        this.endosoInfo = { ...this.endosoInfo, objetivos: this.objetivosEndoso.map((o) => (o.key === key ? { ...o, sel: e.target.checked } : o)) };
    }
    marcarTodosObjetivosEndoso(e) {
        this.endosoInfo = { ...this.endosoInfo, objetivos: this.objetivosEndoso.map((o) => ({ ...o, sel: e.target.checked })) };
    }
    async guardarEndoso() {
        if (!this.validarForm()) { return; }
        const f = this.form;
        const sel = this.objetivosEndoso.filter((o) => o.sel);
        if (!sel.length) { return; }
        const comun = { fecha: f.fecha, endoso: f.endoso, comentario: f.comentario };
        await this.enviar(sel.map((o) => {
            if (o.tipo === 'alta') { return { tipo: 'alta', datos: o.datos, ...comun }; }
            if (o.tipo === 'baja') { return { tipo: 'baja', id: o.id, motivo: f.motivo || null, ...comun }; }
            return { tipo: 'cambio', id: o.id, datos: o.datos || null, ...comun };
        }));
    }

    // ============================================================
    // Archivo de la aseguradora (Excel / CSV / PDF): igual que «Cargar vehículos». Se compara contra las ubicaciones
    // vigentes y se revisan las altas, bajas y cambios antes de aplicarlos. Un PDF de endoso se lee como endoso.
    // ============================================================
    get enRevision() { return this.vista === 'revision'; }
    elegirArchivo() {
        const input = this.template.querySelector('input.archivo-input');
        if (input) { input.click(); }
    }
    async handleArchivo(e) {
        const file = e.target.files && e.target.files[0];
        e.target.value = null;
        if (!file) { return; }
        this.cargando = true;
        try {
            let ubicaciones;
            if (/\.pdf$/i.test(file.name)) {
                const paginas = await paginasPdf(this, file);
                const texto = paginas.join('\n');
                if (endosoDeTexto(texto, file.name)) {
                    if (!this.enPoliza) {
                        this.toast('Ubicaciones', `${file.name} es un endoso: los endosos se cargan en la póliza.`, 'warning');
                        return;
                    }
                    this.leerEndoso(file, texto);
                    return;
                }
                ubicaciones = ubicacionesDePdf(texto);
            } else {
                ubicaciones = await this.ubicacionesDeTabla(file);
            }
            if (!ubicaciones.length) {
                this.toast('Ubicaciones', `No se encontraron ubicaciones en ${file.name}. Revisa que tenga la columna de domicilio`
                    + ' (en PDF solo se leen las especificaciones de ubicación de Afirme; si no, usa el Excel).', 'warning');
                return;
            }
            this.archivoNombre = file.name;
            this.revision = this.compararUbicaciones(ubicaciones);
            this.comun = { fecha: this.fechaDefault, endoso: '', motivo: '', comentario: '', solicitud: 'nueva' };
            this.endosoLeido = null;
            this.documentoEndoso = null;
            this.vista = 'revision';
        } catch (err) {
            this.toast('Ubicaciones', (err && (err.body && err.body.message || err.message)) || 'No se pudo leer el archivo.', 'error');
        } finally {
            this.cargando = false;
        }
    }

    // Primera hoja del libro que tiene columnas de ubicaciones (domicilio, giro, suma asegurada...).
    async ubicacionesDeTabla(file) {
        const libro = await abrirTabla(file);
        const hojas = libro.hojas.length ? libro.hojas : [null];
        for (const h of hojas) {
            // eslint-disable-next-line no-await-in-loop
            const filas = await libro.leerHoja(h);
            const m = mapeoComo(TIPOS.UBICACIONES, filas || []);
            if (m.valido) {
                const lista = ubicacionesDesdeTabla(filas, m.encabezado, m.mapeo);
                if (lista.length) { return lista; }
            }
        }
        return [];
    }

    // Ubicaciones del archivo contra las vigentes. Se reconocen por domicilio y, si el domicilio viene escrito distinto,
    // por número de inciso. Las vigentes que no vienen se proponen como baja, desmarcadas.
    compararUbicaciones(lista) {
        const vigentes = this.vigentes;
        const porDir = new Map();
        const porInciso = new Map();
        vigentes.forEach((u) => {
            const k = llaveDomicilio(u.direccion);
            if (k && !porDir.has(k)) { porDir.set(k, u); }
            if (u.inciso !== null && u.inciso !== undefined && u.inciso !== '') { porInciso.set(String(Number(u.inciso)), u); }
        });
        const llavesArchivo = new Set(lista.map((y) => llaveDomicilio(y.direccion)));
        const usados = new Set();
        const vistos = new Map();
        const altas = [];
        const cambios = [];
        const duplicados = [];
        let sinCambios = 0;
        lista.forEach((x, i) => {
            const fila = x.fila || i + 1;
            const k = llaveDomicilio(x.direccion);
            if (vistos.has(k)) {
                const otra = vistos.get(k);
                duplicados.push({ key: 'd' + i, nombre: x.direccion, filaTxt: `Registro ${fila}`, motivo: 'Viene repetida en el archivo',
                    existenteTxt: `Igual al registro ${otra} del archivo: se toma una sola vez.` });
                return;
            }
            vistos.set(k, fila);
            const inciso = x.inciso !== undefined && x.inciso !== null && x.inciso !== '' && !isNaN(Number(x.inciso)) ? Number(x.inciso) : null;
            const datos = {
                inciso, direccion: x.direccion, giro: x.giro || null, sumaAsegurada: x.sumaAsegurada ?? null,
                prima: x.primaNeta ?? x.primaTotal ?? null
            };
            let u = porDir.get(k);
            if (!u && inciso !== null) {
                const c = porInciso.get(String(inciso));
                // Por inciso solo si el domicilio de esa ubicación no viene también en el archivo (sería otra).
                if (c && !llavesArchivo.has(llaveDomicilio(c.direccion))) { u = c; }
            }
            if (u && usados.has(u.id)) {
                // Ya se tomó esa ubicación con otro registro del archivo: la segunda alta se rechaza.
                duplicados.push({ key: 'd' + i, nombre: x.direccion, filaTxt: `Registro ${fila}`,
                    motivo: `Ya está vigente en ${this.enPoliza ? 'la póliza' : 'el censo'}`, existenteTxt: this.datosUbicacion(u) });
                return;
            }
            if (!u) {
                altas.push({ key: 'a' + i, sel: true, ...datos, sumaTxt: moneda(datos.sumaAsegurada), primaTxt: moneda(datos.prima), datos });
                return;
            }
            usados.add(u.id);
            const difs = [];
            const nuevos = {};
            const igualTexto = (a, b) => this.fold(a) === this.fold(b);
            const igualNum = (a, b) => Math.abs(Number(a || 0) - Number(b || 0)) < 0.5;
            if (inciso !== null && Number(u.inciso) !== inciso) {
                difs.push(`Inciso: ${u.inciso ?? '—'} → ${inciso}`);
                nuevos.inciso = inciso;
            }
            if (!this.enPoliza && datos.direccion && !igualTexto(u.direccion, datos.direccion)) {
                difs.push(`Domicilio: ${u.direccion || '—'} → ${datos.direccion}`);
                nuevos.direccion = datos.direccion;
            }
            if (datos.giro && !igualTexto(u.giro, datos.giro)) {
                difs.push(`Giro: ${u.giro || '—'} → ${datos.giro}`);
                nuevos.giro = datos.giro;
            }
            if (datos.sumaAsegurada !== null && !igualNum(u.sumaAsegurada, datos.sumaAsegurada)) {
                difs.push(`Suma asegurada: ${moneda(u.sumaAsegurada) || '—'} → ${moneda(datos.sumaAsegurada)}`);
                nuevos.sumaAsegurada = datos.sumaAsegurada;
            }
            if (datos.prima !== null && !igualNum(u.prima, datos.prima)) {
                difs.push(`Prima: ${moneda(u.prima) || '—'} → ${moneda(datos.prima)}`);
                nuevos.prima = datos.prima;
            }
            if (!difs.length) { sinCambios++; return; }
            cambios.push({ key: 'c' + u.id, sel: true, id: u.id, inciso: u.inciso, direccion: u.direccion, datos: nuevos,
                difs: difs.map((t, j) => ({ key: u.id + j, texto: t })) });
        });
        // Las vigentes que no vienen en el archivo no se tocan.
        return { altas, bajas: [], cambios, duplicados, sinCambios };
    }
    datosUbicacion(u) {
        return [
            u.inciso !== null && u.inciso !== undefined ? `Inciso ${u.inciso}` : null,
            u.direccion,
            u.giro ? `giro ${u.giro}` : null,
            u.sumaAsegurada ? `suma asegurada ${moneda(u.sumaAsegurada)}` : null
        ].filter((x) => x).join(' · ');
    }

    get altasRev() { return this.revision ? this.revision.altas : []; }
    get bajasRev() { return this.revision ? this.revision.bajas : []; }
    get cambiosRev() { return this.revision ? this.revision.cambios : []; }
    get duplicadosRev() { return this.revision ? this.revision.duplicados : []; }
    get hayAltas() { return this.altasRev.length > 0; }
    get hayBajas() { return this.bajasRev.length > 0; }
    get hayCambios() { return this.cambiosRev.length > 0; }
    get hayDuplicados() { return this.duplicadosRev.length > 0; }
    get sinDiferencias() { return !this.hayAltas && !this.hayBajas && !this.hayCambios; }
    get textoAltas() { return `Altas (${this.altasRev.length})`; }
    get textoBajas() { return `Bajas (${this.bajasRev.length})`; }
    get textoCambios() { return `Cambios (${this.cambiosRev.length})`; }
    get textoDuplicados() { return `Altas rechazadas (${this.duplicadosRev.length}): ya existen.`; }
    get textoSinCambios() { return `${this.revision ? this.revision.sinCambios : 0} ubicaciones del archivo ya existen igual y no se tocan.`; }
    get todasBajas() { return this.hayBajas && this.bajasRev.every((b) => b.sel); }
    get todasAltas() { return this.hayAltas && this.altasRev.every((b) => b.sel); }
    get todosCambios() { return this.hayCambios && this.cambiosRev.every((b) => b.sel); }
    get hayFaltantes() { return this.bajasRev.some((b) => b.faltante); }
    get textoFaltantes() {
        const n = this.bajasRev.filter((b) => b.faltante).length;
        return `${n} ubicaciones vigentes no vienen en el archivo. Están desmarcadas: marca solo las que sí se dan de baja `
            + '(si el archivo es el listado completo, usa la casilla del encabezado para marcarlas todas).';
    }
    marcar(e) {
        const { lista, key } = e.target.dataset;
        this.revision = { ...this.revision, [lista]: this.revision[lista].map((x) => (x.key === key ? { ...x, sel: e.target.checked } : x)) };
    }
    marcarTodos(e) {
        const { lista } = e.target.dataset;
        this.revision = { ...this.revision, [lista]: this.revision[lista].map((x) => ({ ...x, sel: e.target.checked })) };
    }
    motivoBaja(e) {
        const key = e.target.dataset.key;
        this.revision = { ...this.revision, bajas: this.revision.bajas.map((x) => (x.key === key ? { ...x, motivo: e.detail.value } : x)) };
    }
    handleComun(e) { this.comun = { ...this.comun, [e.target.dataset.campo]: e.detail.value }; }

    async aplicarRevision() {
        if (!this.validarForm()) { return; }
        const c = this.comun;
        const comun = { fecha: c.fecha, endoso: c.endoso, comentario: c.comentario };
        const movs = [];
        this.revision.bajas.filter((b) => b.sel).forEach((b) => movs.push({ tipo: 'baja', id: b.id, motivo: b.motivo || c.motivo || null, ...comun }));
        this.revision.cambios.filter((x) => x.sel).forEach((x) => movs.push({ tipo: 'cambio', id: x.id, datos: x.datos, ...comun }));
        this.revision.altas.filter((a) => a.sel).forEach((a) => movs.push({ tipo: 'alta', datos: a.datos, ...comun }));
        if (!movs.length) {
            this.toast('Movimientos', 'No seleccionaste ningún movimiento.', 'info');
            return;
        }
        await this.enviar(movs);
    }

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
    // En la póliza el domicilio no se cambia (es otra ubicación); en el listado de la renovación sí.
    get domicilioBloqueado() { return this.enPoliza; }

    abrirBaja(e) {
        const ids = e && e.target && e.target.dataset && e.target.dataset.id ? [e.target.dataset.id] : [...this.seleccion];
        if (!ids.length) { return; }
        this.form = { ids, fecha: this.fechaDefault, motivo: '', endoso: '', comentario: '', solicitud: 'nueva' };
        this.modal = 'baja';
    }
    get bajaNombres() {
        const ids = new Set(this.form.ids || []);
        return this.ubicaciones.filter((u) => ids.has(u.id)).map((u) => ({ id: u.id, texto: this.nombre(u) }));
    }
    get textoBaja() { return `Se darán de baja ${this.bajaNombres.length} ubicaciones.`; }

    abrirAlta() {
        this.form = { nombre: '', direccion: '', giro: '', sumaAsegurada: null, prima: null, inciso: null, fecha: this.fechaDefault, endoso: '', solicitud: 'nueva' };
        this.modal = 'alta';
    }

    abrirCambio(e) {
        const u = this.ubicaciones.find((x) => x.id === e.target.dataset.id);
        if (!u) { return; }
        // En Salesforce la edición corrige el dato; en el sitio, solo si el movimiento sigue Solicitado.
        const corrige = this.enPoliza && (this.interno || (!!u.movimientoId && this.seguimientoDe(u) === 'Solicitado'));
        this.form = {
            id: u.id, nombreActual: this.nombre(u), original: { ...u }, inciso: u.inciso, nombre: u.nombre || '',
            direccion: u.direccion || '', giro: u.giro || '', sumaAsegurada: u.sumaAsegurada, prima: u.prima,
            fecha: this.fechaDefault, endoso: '', comentario: '', solicitud: corrige ? 'correccion' : 'nueva', corrige,
            movimientoId: u.movimientoId || null
        };
        this.modal = 'cambio';
    }

    // Sin trámite (Salesforce): el cambio solo corrige el dato o se registra como movimiento (sin solicitud).
    get etiquetaSolicitudCambio() { return this.sinTramite ? 'Registro' : 'Solicitud'; }
    get opcionesSolicitudCambio() {
        if (this.sinTramite) {
            return [{ label: 'Solo corregir (sin movimiento nuevo)', value: 'correccion' }, { label: 'Registrar el cambio', value: 'nueva' }];
        }
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
        const sinMovimiento = this.enPoliza && f.solicitud === 'correccion';
        await this.enviar([{ tipo: 'cambio', id: f.id, datos, fecha: f.fecha, endoso: f.endoso, comentario: f.comentario,
            sinMovimiento, movimientoId: sinMovimiento ? f.movimientoId : null }]);
    }

    async enviar(movs) {
        // Endoso de la aseguradora (prima y documento): solo en la póliza.
        const endoso = this.enPoliza ? this.template.querySelector('c-datos-endoso') : null;
        const prima = endoso ? endoso.prima : null;
        this.cargando = true;
        try {
            const r = await aplicarSitio({
                recordId: this._recordId,
                movimientosJson: this.enPoliza ? JSON.stringify({ movimientos: movs, endoso: prima,
                        solicitud: (this.vista === 'revision' ? (this.comun || {}).solicitud : (this.form || {}).solicitud) || 'nueva' }) : JSON.stringify(movs)
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
    // Solicitudes (folio) que tienen registros, la más reciente primero, con cuántos registros tiene cada una.
    abrirExcel() {
        const porFolio = new Map();
        const folios = this.infoSolicitudes;
        this.ubicaciones.flatMap((r) => {
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
                ['Nombre', (r) => r.nombre],
                ['Dirección', (r) => r.direccion], ['Giro', (r) => r.giro],
                ['Tipo de petición', (r) => r.tipoMovimiento || (r.activo ? 'Alta' : 'Baja')],
                ['Fecha de petición', (r) => fechaVisible(r.fechaMovimiento)], ['Poliza', () => poliza],
                ['Inciso', (r) => (r.inciso == null || isNaN(Number(r.inciso)) ? r.inciso : Number(r.inciso))],
                ['Fecha de alta', (r) => fechaVisible(r.fechaAlta)],
                ['Suma asegurada', (r) => (r.sumaAsegurada == null ? null : Number(r.sumaAsegurada))],
                ['Prima', (r) => (r.prima == null ? null : Number(r.prima))],
                ['Descripción', (r) => this.descripcionExcel(r)]
            ];
        descargarExcel(`Ubicaciones_${String(this.datos && this.datos.nombre || '').replace(/[^A-Za-z0-9-]+/g, '_')}_${sufijo}`, 'Ubicaciones',
            columnas.map((c) => c[0]), registros.map((r) => columnas.map((c) => c[1](r))));
    }
    // Descripción del Excel a la aseguradora: el motivo de la baja o, en un cambio, lo que se cambió.
    descripcionExcel(r) {
        if (r.motivoBaja) { return r.motivoBaja; }
        if (r.tipoMovimiento !== 'Cambio' || !r.detalleMovimiento) { return ''; }
        return String(r.detalleMovimiento).split(/\r?\n/).map((x) => x.trim()).filter((x) => x).join(' · ');
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

    // Abre la ventana con las otras pólizas (de cualquier aseguradora) donde ya existe el registro.
    verOtrasPolizas(e) {
        const { id, titulo } = e.currentTarget.dataset;
        const v = this.template.querySelector('c-otras-polizas');
        if (v && id) { v.abrir(id, this._recordId, titulo); }
    }
}
