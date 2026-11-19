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
import { fold, fechaVisible, moneda, descargarExcel, paginasPdf, abrirTabla } from 'c/lectorArchivos';
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
    filtro = 'vigentes';
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
    // En el sitio de empresas se agrega «mov-portal» para tomar el estilo del sitio (igual que movimientosColectivo).
    get claseRaiz() { return this.portal ? 'mov mov-portal' : 'mov'; }
    // Panel para atender las solicitudes del sitio: solo en Salesforce (en el sitio solo se agrupa por solicitud).
    get conSolicitudesPorAtender() { return this.enPoliza && !this.portal; }

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
    get conFechaCierre() { return this.enPoliza && !this.esIndividual; }
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
    // ============================================================
    // Solicitudes del cliente: cada registro de movimientos (un archivo, una baja, un alta o un cambio) queda en una
    // solicitud con folio (SOL-0001...). La tabla se agrupa por la solicitud del último movimiento de cada registro.
    // ============================================================
    agruparSolicitud = true;
    // Solicitud del sitio que el ejecutivo está atendiendo: los movimientos que registre llevan su folio.
    solicitudAtender = null;
    handleAtenderSolicitud(e) { this.solicitudAtender = e.detail.folio; }
    handleCambioSolicitudes() { this.solicitudAtender = null; this.cargar(); }
    colapsadas = new Set();
    get solicitudes() { return (this.datos && this.datos.solicitudes) || []; }
    get hayAgrupacion() { return this.enPoliza && this.solicitudes.length > 0; }
    get agrupado() { return this.hayAgrupacion && this.agruparSolicitud; }
    toggleAgrupar(e) { this.agruparSolicitud = e.target.checked; this.pagina = 1; }
    toggleSolicitud(e) {
        const k = e.currentTarget.dataset.folio || '';
        const c = new Set(this.colapsadas);
        if (c.has(k)) { c.delete(k); } else { c.add(k); }
        this.colapsadas = c;
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
    get filtradosAgrupados() {
        const porFolio = new Map(this.solicitudes.map((x) => [x.folio, []]));
        porFolio.set('', []);
        this.filtrados.forEach((u) => {
            const k = u.solicitud && porFolio.has(u.solicitud) ? u.solicitud : '';
            porFolio.get(k).push(u);
        });
        return [...porFolio.entries()].filter(([, l]) => l.length).map(([k, l]) => ({ folio: k, lista: l }));
    }
    // Página actual en bloques: encabezado de la solicitud y sus asegurados (una solicitud colapsada solo muestra el
    // encabezado). Sin agrupar, un solo bloque sin encabezado.
    get bloques() {
        const ini = (this.pagina - 1) * POR_PAGINA;
        const fin = ini + POR_PAGINA;
        if (!this.agrupado) {
            return [{ key: 'todos', encabezado: false, filas: this.filtrados.slice(ini, fin).map((u) => this.decorar(u)) }];
        }
        const info = new Map(this.solicitudes.map((x) => [x.folio, x]));
        const paginas = this.paginas;
        const res = [];
        let n = 0;
        this.filtradosAgrupados.forEach((g) => {
            const colapsada = this.colapsadas.has(g.folio);
            const filas = colapsada ? [] : g.lista;
            const visibles = filas.filter((x, i) => n + i >= ini && n + i < fin);
            // Colapsada: el encabezado va en la página donde le toca.
            const pagEnc = Math.min(Math.floor(n / POR_PAGINA) + 1, paginas);
            if (visibles.length || (colapsada && pagEnc === this.pagina)) {
                res.push(this.encabezadoSolicitud(g, info.get(g.folio), colapsada, visibles.map((u) => this.decorar(u)), n < ini && !colapsada));
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
        return {
            key: 'sol-' + (g.folio || 'sin'),
            encabezado: true,
            folio: g.folio,
            titulo: sin ? 'Sin solicitud' : g.folio,
            sub: sin ? 'Registrados antes de las solicitudes'
                : [s && s.fecha ? this.fechaHoraTxt(s.fecha) : '', s && s.portal ? `Del sitio · caso ${s.caso}${s.usuario ? ' · envió ' + s.usuario : ''}` : (s && s.usuario ? `Registró ${s.usuario}` : '')].filter((x) => x).join(' · '),
            resumen: `${g.lista.length} ${g.lista.length === 1 ? 'registro' : 'registros'}${partes.length ? ' · ' + partes.join(', ') : ''}`,
            endososTxt: endosos.length ? `Endoso ${endosos.join(', ')}` : '',
            estadoTxt: sin ? '' : (abiertos ? `Abierta · ${abiertos} sin cerrar` : 'Cerrada'),
            claseEstado: `sol-estado ${abiertos ? 'sol-abierta' : 'sol-cerrada'}`,
            continua,
            icono: colapsada ? 'utility:chevronright' : 'utility:chevrondown',
            textoColapsar: colapsada ? 'Mostrar la solicitud' : 'Ocultar la solicitud',
            // Excel de la solicitud para la aseguradora: solo en Salesforce.
            folioExcel: this.portal ? null : g.folio,
            filas
        };
    }
    get columnasTabla() {
        return 9 + (this.conFechasMovimiento ? 1 : 0) + (this.enPoliza ? 3 : 0) + (this.conFechaCierre ? 1 : 0);
    }

    get filas() {
        const ini = (this.pagina - 1) * POR_PAGINA;
        return this.filtrados.slice(ini, ini + POR_PAGINA).map((u) => this.decorar(u));
    }
    decorar(u) {
        return ({
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
        });
    }
    get totalPaginable() {
        if (!this.agrupado) { return this.filtrados.length; }
        return this.filtradosAgrupados.reduce((t, g) => t + (this.colapsadas.has(g.folio) ? 0 : g.lista.length), 0);
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
            this.comun = { fecha: this.fechaDefault, endoso: '', motivo: '', comentario: '', solicitud: this.solicitudAtender || 'nueva' };
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
        this.form = { ids, fecha: this.fechaDefault, motivo: '', endoso: '', comentario: '', solicitud: this.solicitudAtender || 'nueva' };
        this.modal = 'baja';
    }
    get bajaNombres() {
        const ids = new Set(this.form.ids || []);
        return this.ubicaciones.filter((u) => ids.has(u.id)).map((u) => ({ id: u.id, texto: this.nombre(u) }));
    }
    get textoBaja() { return `Se darán de baja ${this.bajaNombres.length} ubicaciones.`; }

    abrirAlta() {
        this.form = { nombre: '', direccion: '', giro: '', sumaAsegurada: null, prima: null, inciso: null, fecha: this.fechaDefault, endoso: '', solicitud: this.solicitudAtender || 'nueva' };
        this.modal = 'alta';
    }

    abrirCambio(e) {
        const u = this.ubicaciones.find((x) => x.id === e.target.dataset.id);
        if (!u) { return; }
        this.form = {
            id: u.id, nombreActual: this.nombre(u), original: { ...u }, inciso: u.inciso, nombre: u.nombre || '',
            direccion: u.direccion || '', giro: u.giro || '', sumaAsegurada: u.sumaAsegurada, prima: u.prima,
            fecha: this.fechaDefault, endoso: '', comentario: '', solicitud: this.solicitudAtender || 'nueva'
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
            this.toast('Movimientos', (partes.length ? `Aplicados: ${partes.join(', ')}.` : 'No hubo cambios que aplicar.')
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
        this.ubicaciones.forEach((r) => {
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
        const registros = this.ubicaciones.filter((r) => (r.solicitud || '') === elegida.folio);
        this.excelDe(registros, elegida.folio || 'sin_solicitud');
        this.cerrarModal();
    }
    // Excel solo con los registros de una solicitud (el que se envía a la aseguradora): desde el encabezado de la
    // solicitud en la tabla o desde las solicitudes del sitio.
    handleExcelSolicitud(e) {
        const folio = (e.detail && e.detail.folio) || (e.currentTarget && e.currentTarget.dataset.folio);
        const registros = this.ubicaciones.filter((r) => r.solicitud === folio);
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
                ['Descripción', (r) => r.motivoBaja || '']
            ];
        descargarExcel(`Ubicaciones_${String(this.datos && this.datos.nombre || '').replace(/[^A-Za-z0-9-]+/g, '_')}_${sufijo}`, 'Ubicaciones',
            columnas.map((c) => c[0]), registros.map((r) => columnas.map((c) => c[1](r))));
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
