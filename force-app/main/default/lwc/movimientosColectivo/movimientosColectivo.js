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
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import { fechaVisible, moneda, descargarExcel } from 'c/lectorArchivos';
import { primasPorEndoso } from 'c/clasificadorArchivos';
import getDatos from '@salesforce/apex/MovimientosColectivoController.getDatos';
import datosComponente from '@salesforce/apex/PortalPolizasPestanas.datosComponente';
import aplicar from '@salesforce/apex/MovimientosColectivoController.aplicar';
import compararArchivo from '@salesforce/apex/MovimientosColectivoController.compararArchivo';
import traerDePoliza from '@salesforce/apex/MovimientosColectivoController.traerDePoliza';
import archivosAsegurado from '@salesforce/apex/MovimientosColectivoController.archivosAsegurado';
import asignarArchivos from '@salesforce/apex/MovimientosColectivoController.asignarArchivos';
import subirArchivo from '@salesforce/apex/MovimientosColectivoController.subirArchivo';
import subirDocumentoBaja from '@salesforce/apex/MovimientosColectivoController.subirDocumentoBaja';
import getPlantillas from '@salesforce/apex/ParticipantesPolizaController.getPlantillas';
import enviarCorreo from '@salesforce/apex/ParticipantesPolizaController.enviarCorreo';
import { llamar, fijarPortal } from 'c/portalContexto';
// En el sitio las llamadas pasan por PortalPolizasMovimientos (valida la póliza y al contratante).
const aplicarSitio = (p) => llamar('MovimientosColectivo.aplicar', p, aplicar);
const compararArchivoSitio = (p) => llamar('MovimientosColectivo.compararArchivo', p, compararArchivo);
const subirArchivoSitio = (p) => llamar('MovimientosColectivo.subirArchivo', p, subirArchivo);
const subirDocumentoBajaSitio = (p) => llamar('MovimientosColectivo.subirDocumentoBaja', p, subirDocumentoBaja);
// Asegurados por llamada al enviar correo: menos si van con adjuntos (límite de memoria de Apex).
const LOTE_CORREO = 25;
const LOTE_CORREO_ADJUNTOS = 5;
// Tamaño máximo por archivo al subir en lote (el contenido viaja en base64 a Apex, que admite unos 4 MB por llamada).
const MAX_ARCHIVO_LOTE = 3 * 1024 * 1024;

const POR_PAGINA = 50;
const PARENTESCOS = ['Cónyuge', 'Hijo(a)', 'Padre/Madre', 'Suegro(a)', 'Otro'];

// Datos del archivo que se muestran en las altas (solo las columnas que el archivo trae).
const dato = (a, k) => {
    const v = a.datos && a.datos[k] !== undefined && a.datos[k] !== null ? a.datos[k] : a[k];
    return v === undefined || v === null ? '' : String(v).trim();
};
const COLUMNAS_ALTA = [
    { key: 'categoria', label: 'Categoría', valor: (a) => dato(a, 'categoria') },
    { key: 'fechaNacimiento', label: 'Fecha de nacimiento', valor: (a) => (dato(a, 'fechaNacimiento') ? fechaVisible(dato(a, 'fechaNacimiento')) : '') },
    { key: 'edad', label: 'Edad', num: true, valor: (a) => dato(a, 'edad') },
    { key: 'sexo', label: 'Género', valor: (a) => dato(a, 'sexo') },
    { key: 'numEmpleado', label: 'Núm. empleado', valor: (a) => dato(a, 'numEmpleado') },
    { key: 'rfc', label: 'RFC', valor: (a) => dato(a, 'rfc').toUpperCase() },
    { key: 'email', label: 'Correo', valor: (a) => dato(a, 'email') },
    { key: 'telefono', label: 'Teléfono', valor: (a) => dato(a, 'telefono') },
    { key: 'prima', label: 'Prima', num: true, valor: (a) => (dato(a, 'prima') ? moneda(Number(dato(a, 'prima'))) : '') }
];

export default class MovimientosColectivo extends NavigationMixin(LightningElement) {
    // Ventana de archivos del asegurado.
    @track archivos = { id: null, nombre: '', destinoId: null, lista: [], cargando: false };
    @api readOnly = false;
    @track datos = null;
    @track revision = null;
    @track form = {};
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
    archivoNombre = '';
    // Fecha, endoso, motivo y comentario comunes de la revisión del archivo.
    @track comun = {};
    abierto = false;
    _recordId;
    // Sitio de empresas (portalPolizas): igual que en Salesforce; los datos vienen de PortalPolizasPestanas y las acciones
    // pasan por PortalPolizasMovimientos. No se muestran archivos, correos, Generar Excel ni enlaces a registros de Salesforce.
    @api portal = false;
    @api cuentaVistaPrevia;
    get interno() { return !this.portal; }

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
                ? datosComponente({ policyId: this._recordId, cuentaVistaPrevia: this.cuentaVistaPrevia || null, tipo: 'asegurados' })
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
        return (this.datos.miembros || []).filter((m) => m.esTitular).length <= 1;
    }
    get conFechasMovimiento() { return !this.esIndividual; }
    get conFechaCierre() { return this.enPoliza && !this.esIndividual; }
    // En la oportunidad solo aplica cuando el cliente ya tiene una póliza del ramo (renovación).
    get visible() { return !!this.datos && this.datos.aplica !== false && (this.enPoliza || (this.enOportunidad && !!this.datos.polizaAnteriorId)); }
    get noAplica() { return this.enPoliza && this.datos.aplica === false; }
    // Flotilla: los movimientos son de vehículos (c-movimientos-flotilla).
    get esFlotilla() { return this.noAplica && this.datos.flotilla === true; }
    // Daños / Empresarial: los movimientos son de ubicaciones (c-movimientos-ubicaciones).
    get esUbicaciones() { return this.noAplica && this.datos.ubicaciones === true; }
    get sinMovimientosBienes() { return this.noAplica && !this.esFlotilla && !this.esUbicaciones; }
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
    get enEndosos() { return this.vista === 'endosos'; }
    verLista() { this.vista = 'lista'; this.revision = null; }
    verHistorial() { this.vista = 'historial'; }
    verEndosos() { this.vista = 'endosos'; }

    // PDF de endosos sin asegurados (Vida o GMM): se abre «Registrar endoso» con sus datos, uno tras otro.
    handleEndosoLeido(e) {
        this._endososPendientes = (e.detail && e.detail.endosos) || [];
        this.vista = 'endosos';
    }
    renderedCallback() {
        if (!this._endososPendientes || !this._endososPendientes.length || this.vista !== 'endosos') { return; }
        const c = this.template.querySelector('c-endosos-poliza');
        if (!c) { return; }
        const lista = this._endososPendientes;
        this._endososPendientes = null;
        c.registrarLeidos(lista);
    }
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
    // Los archivos solo se adjuntan a titulares (no a cónyuge, hijos u otros dependientes).
    get titularesArchivo() { return this.miembros.filter((m) => m.esTitular); }
    get sinTitulares() { return this.titularesArchivo.length === 0; }
    get puedeTraer() { return this.puedeEditar && this.enOportunidad && this.datos.aseguradosAnterior > 0; }
    get textoTraer() { return `Traer ${this.datos.aseguradosAnterior} asegurados vigentes de ${this.datos.polizaAnteriorNombre}`; }

    // ============================================================
    // Lista
    // ============================================================
    get opcionesFiltro() {
        return [
            { label: `Vigentes (${this.totalVigentes})`, value: 'vigentes' },
            { label: `Dados de baja (${this.totalBajas})`, value: 'bajas' },
            { label: `Cambios (${this.miembros.filter((m) => m.tipoMovimiento === 'Cambio').length})`, value: 'cambios' },
            { label: `Correo sin enviar (${this.miembros.filter((m) => this.sinEnviar(m)).length})`, value: 'sincorreo' },
            { label: `Correo enviado (${this.miembros.filter((m) => m.correoEnviado).length})`, value: 'concorreo' },
            { label: `Todos (${this.miembros.length})`, value: 'todos' }
        ];
    }
    handleFiltro(e) { this.filtro = e.detail.value; this.pagina = 1; }
    handleBusqueda(e) { this.busqueda = e.target.value || ''; this.pagina = 1; }

    // ============================================================
    // Orden por columna (clic en el título)
    // ============================================================
    orden = { campo: null, asc: true };
    ordenar(e) {
        const campo = e.currentTarget.dataset.campo;
        this.orden = this.orden.campo === campo ? { campo, asc: !this.orden.asc } : { campo, asc: true };
        this.pagina = 1;
    }
    get flechas() {
        const f = {};
        ['certificado', 'nombre', 'parentesco', 'categoria', 'nacimiento', 'alta', 'movimiento', 'creacion', 'cierre', 'prima',
            'estado', 'envio', 'correo'].forEach((c) => { f[c] = this.orden.campo === c ? (this.orden.asc ? '▲' : '▼') : ''; });
        return f;
    }
    valorOrden(m, campo) {
        switch (campo) {
            case 'certificado': return m.certificado;
            case 'nombre': return m.nombre;
            case 'parentesco': return m.parentesco;
            case 'categoria': return m.categoria;
            case 'nacimiento': return m.fechaNacimiento;
            case 'alta': return m.fechaAlta;
            case 'movimiento': return m.fechaMovimiento;
            case 'creacion': return m.fechaCreacion;
            case 'cierre': return m.fechaCierre;
            case 'prima': return m.prima;
            case 'estado': return m.tipoMovimiento || (m.activo ? 'Alta' : 'Baja');
            // Sin correo, pendiente y enviado (por fecha de envío).
            case 'envio': return m.correoEnviado ? `2${m.fechaCorreo || ''}` : (this.correoDe(m) ? '1' : '0');
            case 'correo': return this.correoDe(m);
            default: return null;
        }
    }
    comparar(a, b) {
        const { campo, asc } = this.orden;
        const va = this.valorOrden(a, campo);
        const vb = this.valorOrden(b, campo);
        const vacioA = va === null || va === undefined || va === '';
        const vacioB = vb === null || vb === undefined || vb === '';
        // Los vacíos siempre al final.
        if (vacioA || vacioB) { return vacioA === vacioB ? 0 : (vacioA ? 1 : -1); }
        const r = typeof va === 'number' && typeof vb === 'number'
            ? va - vb
            : String(va).localeCompare(String(vb), 'es', { numeric: true, sensitivity: 'base' });
        return asc ? r : -r;
    }
    // Las familias no se separan: el titular decide la posición y sus dependientes se ordenan debajo de él.
    ordenarLista(lista) {
        if (!this.orden.campo) { return lista; }
        const ids = new Set(lista.map((m) => m.id));
        const grupos = new Map();
        lista.forEach((m) => {
            const k = !m.esTitular && m.titularId && ids.has(m.titularId) ? m.titularId : m.id;
            if (!grupos.has(k)) { grupos.set(k, { cabeza: null, deps: [] }); }
            const g = grupos.get(k);
            if (k === m.id) { g.cabeza = m; } else { g.deps.push(m); }
        });
        return [...grupos.values()]
            .sort((g1, g2) => this.comparar(g1.cabeza, g2.cabeza))
            .flatMap((g) => [g.cabeza, ...g.deps.sort((d1, d2) => this.comparar(d1, d2))]);
    }

    get filtrados() {
        return this.ordenarLista(this.filtradosSinOrden);
    }
    get filtradosSinOrden() {
        const q = this.fold(this.busqueda);
        return this.miembros.filter((m) => {
            if (this.filtro === 'vigentes' && !m.activo) { return false; }
            if (this.filtro === 'bajas' && m.activo) { return false; }
            if (this.filtro === 'cambios' && m.tipoMovimiento !== 'Cambio') { return false; }
            if (this.filtro === 'sincorreo' && !this.sinEnviar(m)) { return false; }
            if (this.filtro === 'concorreo' && !m.correoEnviado) { return false; }
            if (!q) { return true; }
            return this.fold(`${m.nombre} ${m.certificado || ''} ${m.titularNombre || ''} ${m.categoria || ''} ${m.correo || ''}`).includes(q);
        });
    }
    // ============================================================
    // Solicitudes del cliente: cada registro de movimientos (un archivo, una baja, un alta o un cambio) queda en una
    // solicitud con folio (SOL-0001...). La tabla se agrupa por la solicitud del último movimiento de cada asegurado.
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
            label: x.pendiente ? `${x.folio} · del sitio · caso ${x.caso}` : `${x.folio} · ${this.fechaHora(x.fecha)} · ${x.total} mov.${x.abiertos ? '' : ' · cerrada'}`,
            value: x.folio
        })));
    }
    // Asegurados por solicitud (la más reciente primero; sin solicitud al final) y, dentro, por la columna elegida.
    get filtradosAgrupados() {
        const porFolio = new Map(this.solicitudes.map((x) => [x.folio, []]));
        porFolio.set('', []);
        this.filtradosSinOrden.forEach((m) => {
            const k = m.solicitud && porFolio.has(m.solicitud) ? m.solicitud : '';
            porFolio.get(k).push(m);
        });
        return [...porFolio.entries()].filter(([, l]) => l.length).map(([k, l]) => ({ folio: k, lista: this.ordenarLista(l) }));
    }
    // Página actual en bloques: encabezado de la solicitud y sus asegurados (una solicitud colapsada solo muestra el
    // encabezado). Sin agrupar, un solo bloque sin encabezado.
    get bloques() {
        const ini = (this.pagina - 1) * POR_PAGINA;
        const fin = ini + POR_PAGINA;
        if (!this.agrupado) {
            return [{ key: 'todos', encabezado: false, filas: this.filtrados.slice(ini, fin).map((m) => this.decorar(m)) }];
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
                res.push(this.encabezadoSolicitud(g, info.get(g.folio), colapsada, visibles.map((m) => this.decorar(m)), n < ini && !colapsada));
            }
            n += filas.length;
        });
        return res;
    }
    encabezadoSolicitud(g, s, colapsada, filas, continua) {
        const cuenta = { Alta: 0, Baja: 0, Cambio: 0 };
        g.lista.forEach((m) => {
            const t = m.tipoMovimiento || (m.activo ? 'Alta' : 'Baja');
            cuenta[t] = (cuenta[t] || 0) + 1;
        });
        const partes = [];
        if (cuenta.Alta) { partes.push(`${cuenta.Alta} ${cuenta.Alta === 1 ? 'alta' : 'altas'}`); }
        if (cuenta.Baja) { partes.push(`${cuenta.Baja} ${cuenta.Baja === 1 ? 'baja' : 'bajas'}`); }
        if (cuenta.Cambio) { partes.push(`${cuenta.Cambio} ${cuenta.Cambio === 1 ? 'cambio' : 'cambios'}`); }
        const endosos = [...new Set(g.lista.map((m) => m.numeroEndoso).filter((x) => x))];
        const abiertos = g.lista.filter((m) => m.fechaCreacion && !m.fechaCierre).length;
        const sin = !g.folio;
        return {
            key: 'sol-' + (g.folio || 'sin'),
            encabezado: true,
            folio: g.folio,
            titulo: sin ? 'Sin solicitud' : g.folio,
            sub: sin ? 'Registrados antes de las solicitudes'
                : [s && s.fecha ? this.fechaHora(s.fecha) : '', s && s.portal ? `Del sitio · caso ${s.caso}${s.usuario ? ' · envió ' + s.usuario : ''}` : (s && s.usuario ? `Registró ${s.usuario}` : '')].filter((x) => x).join(' · '),
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
        return 10 + (this.conFechasMovimiento ? 1 : 0) + (this.enPoliza ? 3 : 0) + (this.conFechaCierre ? 1 : 0);
    }

    get filas() {
        const ini = (this.pagina - 1) * POR_PAGINA;
        return this.filtrados.slice(ini, ini + POR_PAGINA).map((m) => this.decorar(m));
    }
    decorar(m) {
        return ({
            ...m,
            seleccionado: this.seleccion.has(m.id),
            noSeleccionable: !m.activo || !this.puedeEditar,
            claseFila: (m.esTitular ? '' : 'fila-dependiente') + (m.activo ? '' : ' fila-baja'),
            nacimientoTxt: fechaVisible(m.fechaNacimiento),
            altaTxt: fechaVisible(m.fechaAlta),
            fechaMovimientoTxt: fechaVisible(m.fechaMovimiento),
            sumaTxt: moneda(m.sumaAsegurada),
            primaTxt: moneda(m.prima),
            // Estado = último movimiento: Alta, Baja o Cambio.
            estado: m.tipoMovimiento || (m.activo ? 'Alta' : 'Baja'),
            claseEstado: `estado estado-${String(m.tipoMovimiento || (m.activo ? 'Alta' : 'Baja')).toLowerCase()}`,
            puedeMover: m.activo && this.puedeEditar,
            textoArchivos: m.archivos ? `Archivos (${m.archivos})` : 'Adjuntar archivos',
            // Resaltado cuando ya tiene archivos.
            varianteArchivos: m.archivos ? 'brand' : 'border-filled',
            // Creación del movimiento y su cierre (al enviar el correo).
            fechaCreacionTxt: this.fechaHora(m.fechaCreacion),
            fechaCierreTxt: this.fechaHora(m.fechaCierre),
            // Correo: enviado (con fecha), pendiente o sin correo. Los dados de baja usan su correo personal.
            correoMostrar: this.correoDe(m),
            esCorreoPersonal: !m.activo && !!m.correoPersonal,
            correoTxt: m.correoEnviado ? 'Enviado' : (this.correoDe(m) ? 'Pendiente' : 'Sin correo'),
            claseCorreo: `estado ${m.correoEnviado ? 'correo-enviado' : (this.correoDe(m) ? 'correo-pendiente' : 'correo-sin')}`,
            fechaCorreoTxt: m.correoEnviado ? this.fechaHora(m.fechaCorreo) : '',
            tituloCorreo: m.correoEnviado
                ? `Enviado el ${this.fechaHora(m.fechaCorreo)}${m.plantillaCorreo ? ' · ' + m.plantillaCorreo : ''}`
                : (this.correoDe(m) ? `Aún no se envía el correo a ${this.correoDe(m)}` : 'El asegurado no tiene correo'),
            puedeCorreo: this.enPoliza && !!this.correoDe(m),
            // En el sitio no se adjuntan archivos ni se envían correos.
            muestraArchivos: m.esTitular && !this.portal,
            muestraCorreo: this.enPoliza && !!this.correoDe(m) && !this.portal,
            textoEnviar: m.correoEnviado ? 'Reenviar correo' : 'Enviar correo'
        });
    }

    // ============================================================
    // Envío de correo (solo en la póliza)
    // ============================================================
    @track correo = { ids: [], plantilla: '', adjuntar: true, enviando: false, avance: '', errores: [], reenvio: false };
    plantillas = [];
    get enModalCorreo() { return this.modal === 'correo'; }
    // Pendientes del filtro actual (todas las páginas): vigentes con correo a los que no se les ha enviado.
    // Pendientes: altas, cambios y bajas cuyo correo aún no se envía (a la baja se le escribe a su correo personal).
    // Se toman de todos los asegurados (no del filtro de la tabla), porque las bajas no salen en «Vigentes».
    get pendientesCorreo() { return this.miembros.filter((m) => !m.correoEnviado && this.correoDe(m)); }
    // Sin enviar: vigentes sin correo enviado y bajas con correo personal por enviar.
    sinEnviar(m) { return !m.correoEnviado && (m.activo || !!this.correoDe(m)); }
    // Correo al que se envía: el personal si está dado de baja y lo capturaron; si no, el de su contacto o cuenta.
    correoDe(m) { return (!m.activo && m.correoPersonal) ? m.correoPersonal : m.correo; }
    async cargarPlantillas() {
        if (this.plantillas.length) { return; }
        this.plantillas = (await getPlantillas()).map((t) => ({ value: t.id, label: t.carpeta ? `${t.carpeta} · ${t.nombre}` : t.nombre }));
    }
    get textoEnviarPendientes() { return `Enviar correo a pendientes (${this.pendientesCorreo.length})`; }
    get sinPendientesCorreo() { return this.pendientesCorreo.length === 0; }
    abrirCorreoPendientes() { this.abrirCorreo(this.pendientesCorreo.map((m) => m.id), false); }
    abrirCorreoAsegurado(e) {
        const m = this.miembros.find((x) => x.id === e.currentTarget.dataset.id);
        if (m) { this.abrirCorreo([m.id], m.correoEnviado); }
    }
    async abrirCorreo(ids, reenvio) {
        this.correo = { ...this.correo, ids, reenvio, enviando: false, avance: '', errores: [] };
        this.modal = 'correo';
        try {
            await this.cargarPlantillas();
        } catch (err) {
            this.correo = { ...this.correo, errores: [this.textoError(err)] };
        }
    }
    cambiarPlantilla(e) { this.correo = { ...this.correo, plantilla: e.detail.value }; }
    cambiarAdjuntar(e) { this.correo = { ...this.correo, adjuntar: e.target.checked }; }
    get textoDestinatarios() {
        const ids = new Set(this.correo.ids);
        const d = this.miembros.filter((m) => ids.has(m.id));
        if (d.length === 1) { return `Se enviará a ${d[0].nombre} (${this.correoDe(d[0])}).`; }
        return `Se enviará a ${d.length} asegurados con correo que aún no lo reciben.`;
    }
    get avisoReenvio() { return this.correo.reenvio ? 'A este asegurado ya se le envió un correo; se enviará de nuevo.' : ''; }
    get hayErroresCorreo() { return this.correo.errores.length > 0; }
    get erroresCorreo() { return this.correo.errores.map((t, i) => ({ key: String(i), texto: t })); }
    get sinEnviarCorreo() { return !this.correo.plantilla || !this.correo.ids.length || this.correo.enviando; }
    get textoBotonCorreo() { return this.correo.enviando ? 'Enviando…' : 'Enviar'; }
    async enviarCorreos() {
        const { ids, plantilla, adjuntar } = this.correo;
        const lote = adjuntar ? LOTE_CORREO_ADJUNTOS : LOTE_CORREO;
        let enviados = 0;
        const errores = [];
        this.correo = { ...this.correo, enviando: true, errores: [] };
        for (let i = 0; i < ids.length; i += lote) {
            this.correo = { ...this.correo, avance: `Enviando ${Math.min(i + lote, ids.length)} de ${ids.length}…` };
            try {
                const r = await enviarCorreo({ policyId: this._recordId, participanteIds: ids.slice(i, i + lote), plantillaId: plantilla, adjuntarArchivos: adjuntar });
                enviados += r.enviados || 0;
                errores.push(...(r.errores || []));
            } catch (err) {
                errores.push(this.textoError(err));
                break;
            }
        }
        this.correo = { ...this.correo, enviando: false, avance: '', errores };
        if (enviados) {
            this.toast('Correo enviado', `Se envió a ${enviados} asegurado${enviados === 1 ? '' : 's'}`
                + (errores.length ? `; ${errores.length} no se pudieron enviar.` : '.'), errores.length ? 'warning' : 'success');
            await this.cargar();
        }
        if (!errores.length) { this.modal = null; }
    }
    textoError(e) { return (e && e.body && e.body.message) || (e && e.message) || 'Ocurrió un error inesperado.'; }
    fechaHora(v) {
        if (!v) { return ''; }
        const d = new Date(v);
        return isNaN(d) ? '' : d.toLocaleString('es-MX', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
    }
    get totalPaginable() {
        if (!this.agrupado) { return this.filtrados.length; }
        return this.filtradosAgrupados.reduce((t, g) => t + (this.colapsadas.has(g.folio) ? 0 : g.lista.length), 0);
    }
    get paginas() { return Math.max(1, Math.ceil(this.totalPaginable / POR_PAGINA)); }
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
    get enModalArchivos() { return this.modal === 'archivos'; }

    // ============================================================
    // Archivos del asegurado
    // ============================================================
    async abrirArchivos(e) {
        const id = e.currentTarget.dataset.id;
        const m = this.miembros.find((x) => x.id === id);
        if (!m || !m.esTitular) { return; }
        this.archivos = { id, nombre: m.nombre, destinoId: null, lista: [], cargando: true };
        this.modal = 'archivos';
        await this.cargarArchivos();
    }
    async cargarArchivos() {
        const id = this.archivos.id;
        try {
            const r = await archivosAsegurado({ registroId: id });
            if (this.archivos.id !== id) { return; }
            this.archivos = { ...this.archivos, destinoId: r.destinoId, lista: r.archivos || [], cargando: false };
            // Actualiza el contador del botón en la lista.
            this.datos = { ...this.datos, miembros: this.miembros.map((x) => (x.id === id ? { ...x, archivos: this.archivos.lista.length } : x)) };
        } catch (err) {
            this.archivos = { ...this.archivos, cargando: false };
            this.mostrarError(err);
        }
    }
    async archivosSubidos(e) {
        const n = (e.detail.files || []).length;
        this.toast('Archivos', `${n} archivo(s) adjuntado(s).`, 'success');
        this.archivos = { ...this.archivos, cargando: true };
        await this.cargarArchivos();
    }
    get archivosLista() {
        return this.archivos.lista.map((a) => ({
            ...a,
            titulo: a.titulo + (a.tipo ? '.' + a.tipo : ''),
            icono: this.iconoArchivo(a.tipo),
            detalle: [a.tipo ? a.tipo.toUpperCase() : '', this.tamanoTxt(a.tamano), a.fecha ? fechaVisible(a.fecha) : ''].filter((x) => x).join(' · ')
        }));
    }
    get hayArchivos() { return this.archivos.lista.length > 0; }
    get textoArchivos() { return `Archivos adjuntos (${this.archivos.lista.length})`; }
    // Vista previa de un archivo adjunto (no confundir con verArchivo, que abre la carga del censo).
    previsualizarArchivo(e) {
        e.preventDefault();
        const id = e.currentTarget.dataset.id;
        if (!id) { return; }
        this[NavigationMixin.Navigate]({ type: 'standard__namedPage', attributes: { pageName: 'filePreview' },
            state: { selectedRecordId: id } });
    }
    iconoArchivo(tipo) {
        const t = String(tipo || '').toLowerCase();
        if (t === 'pdf') { return 'doctype:pdf'; }
        if (t === 'csv') { return 'doctype:csv'; }
        if (['xls', 'xlsx'].includes(t)) { return 'doctype:excel'; }
        if (['doc', 'docx'].includes(t)) { return 'doctype:word'; }
        if (['png', 'jpg', 'jpeg', 'gif', 'webp'].includes(t)) { return 'doctype:image'; }
        if (t === 'zip') { return 'doctype:zip'; }
        if (t === 'txt') { return 'doctype:txt'; }
        return 'doctype:unknown';
    }
    tamanoTxt(b) {
        if (b == null) { return ''; }
        if (b < 1024) { return `${b} B`; }
        if (b < 1024 * 1024) { return `${Math.round(b / 1024)} KB`; }
        return `${(b / 1024 / 1024).toFixed(1)} MB`;
    }
    cerrarModal() {
        if (this.modal === 'archivosVarios' && this.subiendoVarios) { return; }
        if (this.modal === 'correo' && this.correo.enviando) { return; }
        if (this.modal === 'archivosVarios' && this.totalSubidos) {
            this.toast('Archivos', 'Los archivos que no se adjuntaron se quedaron en la póliza.', 'info');
        }
        this.modal = null;
        this.form = {};
        this.varios = { filas: [], cargando: false };
    }

    // ============================================================
    // Varios archivos de distintas personas: se detecta a quién va cada uno por el nombre del archivo.
    // ============================================================
    @track varios = { filas: [], cargando: false };
    get enModalArchivosVarios() { return this.modal === 'archivosVarios'; }
    abrirArchivosVarios() {
        this.varios = { filas: [], cargando: false };
        this.modal = 'archivosVarios';
    }
    // Archivos grandes con el componente estándar (máximo 10 por selección).
    archivosVariosSubidos(e) {
        const nuevos = (e.detail.files || []).map((f) => {
            const d = this.detectarPersona(f.name);
            return { key: f.documentId, documentId: f.documentId, nombre: f.name, registroId: d.id, deteccion: d.como, estado: 'listo' };
        });
        this.varios = { ...this.varios, filas: [...this.varios.filas, ...nuevos] };
    }
    // Selección sin límite de cantidad: cada archivo se sube por separado a la póliza.
    elegirArchivosVarios() {
        const input = this.template.querySelector('input.varios-input');
        if (input) { input.value = null; input.click(); }
    }
    archivosElegidos(e) {
        this.subirVarios([...(e.target.files || [])]);
    }
    arrastrarSobre(e) { e.preventDefault(); }
    soltarArchivos(e) {
        e.preventDefault();
        this.subirVarios([...((e.dataTransfer && e.dataTransfer.files) || [])]);
    }
    async subirVarios(archivos) {
        if (!archivos.length) { return; }
        // Los File se guardan fuera del estado reactivo.
        const porKey = new Map();
        const nuevos = archivos.map((f, i) => {
            const d = this.detectarPersona(f.name);
            const grande = f.size > MAX_ARCHIVO_LOTE;
            const key = `n${Date.now()}-${i}`;
            porKey.set(key, f);
            return {
                key, documentId: null, nombre: f.name, registroId: d.id, deteccion: d.como,
                estado: grande ? 'error' : 'pendiente',
                error: grande ? 'Pesa más de 3 MB: súbelo con «Archivos de más de 3 MB».' : ''
            };
        });
        this.varios = { ...this.varios, filas: [...this.varios.filas, ...nuevos] };
        const cola = nuevos.filter((n) => n.estado === 'pendiente');
        // Hasta 3 archivos subiendo a la vez.
        const trabajador = async () => {
            while (cola.length) {
                const n = cola.shift();
                this.actualizarFila(n.key, { estado: 'subiendo' });
                try {
                    const base64 = await this.leerBase64(porKey.get(n.key));
                    const documentId = await subirArchivoSitio({ recordId: this._recordId, nombre: n.nombre, base64 });
                    this.actualizarFila(n.key, { estado: 'listo', documentId });
                } catch (err) {
                    this.actualizarFila(n.key, { estado: 'error',
                        error: (err && err.body && err.body.message) || (err && err.message) || 'No se pudo subir.' });
                }
            }
        };
        await Promise.all([trabajador(), trabajador(), trabajador()]);
    }
    actualizarFila(key, cambios) {
        this.varios = { ...this.varios, filas: this.varios.filas.map((f) => (f.key === key ? { ...f, ...cambios } : f)) };
    }
    leerBase64(archivo) {
        return new Promise((resolve, reject) => {
            const r = new FileReader();
            r.onload = () => resolve(String(r.result).split(',')[1] || '');
            r.onerror = () => reject(new Error('No se pudo leer el archivo.'));
            r.readAsDataURL(archivo);
        });
    }
    get subiendoVarios() { return this.varios.filas.some((f) => f.estado === 'pendiente' || f.estado === 'subiendo'); }
    get textoSubiendo() {
        const total = this.varios.filas.filter((f) => f.estado !== 'error').length;
        const listos = this.varios.filas.filter((f) => f.estado === 'listo').length;
        return `Subiendo archivos: ${listos} de ${total}…`;
    }
    // Busca en el nombre del archivo el RFC, el nombre completo o el certificado de un asegurado.
    detectarPersona(nombreArchivo) {
        const base = this.fold(String(nombreArchivo || '').replace(/\.[^.]+$/, ''));
        const tokens = base.split(/[^a-z0-9]+/).filter((t) => t);
        const pegado = tokens.join('');
        const set = new Set(tokens);
        const ignorar = new Set(['de', 'del', 'la', 'las', 'los', 'y']);
        let mejor = null;
        let empate = false;
        this.titularesArchivo.forEach((m) => {
            let puntos = 0;
            let como = '';
            const rfc = this.fold(m.rfc).replace(/[^a-z0-9]/g, '');
            if (rfc.length >= 10 && pegado.includes(rfc.substring(0, 10))) {
                puntos = 100; como = 'Por RFC';
            } else {
                const partes = this.fold(m.nombre).split(/[^a-z0-9]+/).filter((t) => t.length >= 3 && !ignorar.has(t));
                const hallados = partes.filter((t) => set.has(t)).length;
                if (partes.length >= 2 && hallados === partes.length) { puntos = 90; como = 'Por nombre'; }
                else if (hallados >= 2) { puntos = 60 + hallados; como = 'Por nombre (parcial)'; }
                const c = this.fold(m.certificado).replace(/[^a-z0-9]/g, '');
                if (c.length >= 3 && set.has(c)) {
                    if (puntos) { puntos += 5; } else { puntos = 70; como = 'Por certificado'; }
                }
            }
            // Prefiere a los vigentes sobre los dados de baja con el mismo puntaje.
            if (puntos && m.activo) { puntos += 0.5; }
            if (!puntos) { return; }
            if (!mejor || puntos > mejor.puntos) { mejor = { id: m.id, puntos, como }; empate = false; }
            else if (puntos === mejor.puntos) { empate = true; }
        });
        if (!mejor || empate) { return { id: null, como: empate ? 'Coincide con varias personas' : 'No detectado' }; }
        return { id: mejor.id, como: mejor.como };
    }
    get opcionesPersonas() {
        const ops = [{ label: '— Sin asignar (se queda en la póliza) —', value: '' }];
        [...this.titularesArchivo]
            .sort((a, b) => String(a.nombre).localeCompare(String(b.nombre)))
            .forEach((m) => ops.push({
                label: `${m.nombre}${m.certificado ? ' (' + m.certificado + ')' : ''}${m.activo ? '' : ' · baja'}`,
                value: m.id
            }));
        return ops;
    }
    asignarPersona(e) {
        const doc = e.target.dataset.id;
        const valor = e.detail.value || null;
        this.varios = {
            ...this.varios,
            filas: this.varios.filas.map((f) => (f.key === doc
                ? { ...f, registroId: valor, deteccion: valor ? 'Asignado a mano' : 'Sin asignar' } : f))
        };
    }
    get variosFilas() {
        return this.varios.filas.map((f) => ({
            ...f,
            registroId: f.registroId || '',
            claseDeteccion: f.registroId ? (f.deteccion === 'Asignado a mano' ? 'tipo tipo-cambio' : 'tipo tipo-alta') : 'tipo tipo-baja',
            estadoTxt: { pendiente: 'En espera', subiendo: 'Subiendo…', listo: 'Subido', error: 'No se subió' }[f.estado] || '',
            claseEstado: f.estado === 'error' ? 'sub texto-error' : 'sub',
            conError: f.estado === 'error'
        }));
    }
    get hayVarios() { return this.varios.filas.length > 0; }
    get totalAsignados() { return this.varios.filas.filter((f) => f.registroId && f.documentId).length; }
    get totalSubidos() { return this.varios.filas.filter((f) => f.documentId).length; }
    get textoVarios() { return `${this.varios.filas.length} archivo(s) · ${this.totalAsignados} con persona detectada o asignada`; }
    get sinAsignados() { return this.totalAsignados === 0 || this.varios.cargando || this.subiendoVarios; }
    get textoAdjuntarVarios() { return `Adjuntar ${this.totalAsignados} archivo(s)`; }
    async adjuntarVarios() {
        const asignaciones = this.varios.filas.filter((f) => f.registroId && f.documentId)
            .map((f) => ({ documentId: f.documentId, registroId: f.registroId }));
        if (!asignaciones.length) { return; }
        this.varios = { ...this.varios, cargando: true };
        try {
            const n = await asignarArchivos({ recordId: this._recordId, asignacionesJson: JSON.stringify(asignaciones) });
            const pendientes = this.totalSubidos - asignaciones.length;
            this.toast('Archivos', `${n} archivo(s) adjuntado(s) a cada asegurado.`
                + (pendientes ? ` ${pendientes} sin asignar se quedaron en la póliza.` : ''), 'success');
            this.modal = null;
            this.varios = { filas: [], cargando: false };
            await this.cargar();
        } catch (err) {
            this.varios = { ...this.varios, cargando: false };
            this.mostrarError(err);
        }
    }

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
        const correos = {};
        ids.forEach((id) => {
            const m = this.miembros.find((x) => x.id === id);
            correos[id] = (m && m.correoPersonal) || '';
        });
        this.form = { ids, fecha: this.fechaDefault, motivo: '', endoso: '', comentario: '', correos, documentos: {}, solicitud: this.solicitudAtender || 'nueva' };
        // Los archivos (File) quedan fuera del estado reactivo; en el formulario solo va su nombre.
        this._documentosBaja = new Map();
        this.modal = 'baja';
    }
    // Correo personal de cada asegurado que se da de baja (los dependientes salen con su titular sin correo propio).
    get bajaCorreos() {
        const correos = this.form.correos || {};
        const documentos = this.form.documentos || {};
        return (this.form.ids || []).map((id) => {
            const m = this.miembros.find((x) => x.id === id) || {};
            return { id, etiqueta: `Correo personal de ${m.nombre || 'asegurado'}`, valor: correos[id] || '',
                corporativo: m.correo ? `Correo registrado: ${m.correo}` : 'No tiene correo registrado',
                etiquetaDocumento: `Documento de baja de ${m.nombre || 'asegurado'} (opcional)`,
                documento: documentos[id] || '' };
        });
    }
    // Documento de baja (endoso o constancia): es lo único que se adjunta al correo de baja.
    handleDocumentoBaja(e) {
        const id = e.target.dataset.id;
        const f = e.target.files && e.target.files[0];
        e.target.value = null;
        if (!f) { return; }
        if (f.size > MAX_ARCHIVO_LOTE) {
            this.toast('Documento de baja', `${f.name} pesa más de 3 MB.`, 'warning');
            return;
        }
        this._documentosBaja.set(id, f);
        this.form = { ...this.form, documentos: { ...(this.form.documentos || {}), [id]: f.name } };
    }
    elegirDocumentoBaja(e) {
        const input = this.template.querySelector(`input.doc-baja-input[data-id="${e.target.dataset.id}"]`);
        if (input) { input.click(); }
    }
    handleCorreoPersonal(e) {
        this.form = { ...this.form, correos: { ...(this.form.correos || {}), [e.target.dataset.id]: (e.target.value || '').trim() } };
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
            certificado: '', categoria: '', sumaAsegurada: null, prima: null, rfc: '', email: '', fecha: this.fechaDefault, endoso: '', solicitud: this.solicitudAtender || 'nueva'
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
            rfc: m.rfc || '', sexo: m.sexo || '', email: m.correo || '', fecha: this.fechaDefault, endoso: '', comentario: '', solicitud: this.solicitudAtender || 'nueva'
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
        const enPoliza = this.enPoliza;
        const correos = f.correos || {};
        // El correo de baja no se envía aquí: queda pendiente y se envía después desde «Enviar correo».
        // El documento de baja es opcional y se guarda en el movimiento para adjuntarlo en ese envío.
        const docs = this._documentosBaja || new Map();
        const movs = f.ids.map((id) => ({
            tipo: 'baja', id, fecha: f.fecha, motivo: f.motivo || null, endoso: f.endoso, comentario: f.comentario,
            correoPersonal: enPoliza ? correos[id] || null : null
        }));
        const ok = await this.enviar(movs);
        if (!ok || !enPoliza || !docs.size) { return; }
        await this.subirDocumentosBaja(f.ids, docs);
    }
    // Guarda el documento de baja (si se adjuntó) en el movimiento de cada asegurado.
    async subirDocumentosBaja(ids, docs) {
        this.cargando = true;
        const errores = [];
        try {
            for (const id of ids) {
                const f = docs.get(id);
                if (!f) { continue; }
                try {
                    const base64 = await this.leerBase64(f);
                    await subirDocumentoBajaSitio({ policyId: this._recordId, participanteId: id, nombre: f.name, base64 });
                } catch (err) {
                    errores.push(`${f.name}: ${this.textoError(err)}`);
                }
            }
            if (errores.length) {
                this.toast('Documento de baja', `La baja se aplicó, pero no se guardó el documento: ${errores.join(' · ')}`, 'warning');
            }
        } finally {
            this.cargando = false;
        }
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
        if (this.enPoliza && f.email && distinto(f.email.trim().toLowerCase(), (o.correo || '').toLowerCase())) { datos.email = f.email.trim(); }
        if (!Object.keys(datos).length) {
            this.toast('Cambio', 'No modificaste ningún dato.', 'info');
            return;
        }
        await this.enviar([{ tipo: 'cambio', id: f.id, datos, fecha: f.fecha, endoso: f.endoso, comentario: f.comentario }]);
    }

    // primasEndosos: prima de cada número de endoso que trae el archivo de la aseguradora (soporte de recibo de GMM).
    async enviar(movs, primasEndosos) {
        // Endoso de la aseguradora (prima y documento): solo en la póliza.
        const endoso = this.enPoliza ? this.template.querySelector('c-datos-endoso') : null;
        const prima = endoso ? endoso.prima : null;
        this.cargando = true;
        try {
            const r = await aplicarSitio({
                recordId: this._recordId,
                movimientosJson: this.enPoliza
                    ? JSON.stringify({ movimientos: movs, endoso: prima, endosos: primasEndosos || null,
                        solicitud: (this.vista === 'revision' ? this.comun.solicitud : this.form.solicitud) || 'nueva' })
                    : JSON.stringify(movs)
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
                + (r.endosos > 1 ? ` Quedaron en ${r.endosos} endosos de la póliza.` : (r.transaccionId ? ' Quedaron en el endoso de la póliza.' : ''))
                + (r.solicitud ? ` Solicitud ${r.solicitud}.` : ''), 'success');
            this.cerrarModal();
            this.vista = 'lista';
            this.revision = null;
            await this.cargar();
            this.avisarCambio();
            if (this._endososDespues && this._endososDespues.length) {
                this._endososPendientes = this._endososDespues;
                this._endososDespues = null;
                this.vista = 'endosos';
            }
            return true;
        } catch (e) {
            this.mostrarError(e);
            return false;
        } finally {
            this.cargando = false;
        }
    }

    // ============================================================
    // Archivo de la aseguradora
    // ============================================================

    async handleLeido(e) {
        this.archivoNombre = e.detail.archivo;
        // PDF de endosos sin asegurados que venían junto con el archivo: se registran después de aplicar la revisión.
        this._endososDespues = (e.detail && e.detail.endosos) || [];
        // Soporte de recibo con número de endoso por renglón: cada movimiento va a su endoso, con su prima.
        this.primasArchivo = primasPorEndoso(e.detail.miembros);
        this.endososArchivo = [...new Set((e.detail.miembros || []).map((x) => (x.numeroEndoso ? String(x.numeroEndoso).trim() : '')).filter((x) => x))];
        this.cargando = true;
        try {
            const r = await compararArchivoSitio({
                recordId: this._recordId,
                miembrosJson: JSON.stringify(e.detail.miembros),
                // Solo se muestra lo que el archivo trae: los asegurados que no vienen no se tocan (no se proponen como baja).
                censoCompleto: false
            });
            this.revision = {
                altas: r.altas.map((a) => ({ ...a, key: 'a' + a.ref, sel: true })),
                bajas: r.bajas.filter((b) => !b.faltante).map((b) => ({ ...b, key: 'b' + b.id, sel: true, motivo: '' })),
                cambios: r.cambios.map((c) => ({ ...c, key: 'c' + c.id, sel: true })),
                sinCambios: r.sinCambios,
                duplicados: (r.duplicados || []).map((d, i) => this.rechazo(d, i))
            };
            this.comun = { fecha: this.fechaDefault, endoso: '', motivo: '', comentario: '', solicitud: this.solicitudAtender || 'nueva' };
            this.vista = 'revision';
            // Bajas del archivo de personas que no son asegurados: no se puede hacer nada con ellas, solo se avisa.
            const faltan = r.noEncontrados || [];
            if (faltan.length) {
                const nombres = faltan.slice(0, 5).map((x) => x.nombre).join(', ') + (faltan.length > 5 ? ` y ${faltan.length - 5} más` : '');
                const uno = faltan.length === 1;
                this.dispatchEvent(new ShowToastEvent({
                    title: uno ? 'Baja no aplicada' : 'Bajas no aplicadas',
                    message: (uno
                        ? `La baja de ${nombres} no corresponde a ningún asegurado registrado en la póliza, por lo que no será procesada. `
                        : `${faltan.length} bajas incluidas en el archivo no corresponden a asegurados registrados en la póliza, `
                            + `por lo que no serán procesadas: ${nombres}. `)
                        + 'Se recomienda validar la información con la aseguradora.',
                    variant: 'info', mode: 'sticky'
                }));
            }
        } catch (err) {
            this.mostrarError(err);
        } finally {
            this.cargando = false;
        }
    }

    // Alta rechazada: viene repetida en el archivo o la persona ya está asegurada. Se muestra con qué registro choca.
    rechazo(d, i) {
        const donde = this.enPoliza ? 'la póliza' : 'el censo';
        if (d.repetidoEnArchivo) {
            return { ...d, key: 'd' + i, filaTxt: d.fila ? `Registro ${d.fila}` : '—', motivo: 'Viene repetida en el archivo',
                existenteTxt: `Igual al registro ${d.filaOriginal} del archivo: se toma una sola vez.` };
        }
        const datos = [
            d.existente,
            d.parentesco,
            d.titularNombre ? `dependiente de ${d.titularNombre}` : null,
            d.certificado ? `certificado ${d.certificado}` : null,
            d.fechaNacimiento ? `nacimiento ${fechaVisible(d.fechaNacimiento)}` : null,
            d.categoria ? `categoría ${d.categoria}` : null,
            d.sumaAsegurada ? `suma asegurada ${moneda(d.sumaAsegurada)}` : null,
            d.fechaAlta ? `alta ${fechaVisible(d.fechaAlta)}` : null
        ].filter((x) => x);
        return {
            ...d, key: 'd' + i, filaTxt: d.fila ? `Registro ${d.fila}` : '—',
            motivo: `Ya está asegurada en ${donde}` + (d.conCambios ? ' (con datos distintos: ver Cambios)' : ''),
            existenteTxt: datos.join(' · ')
        };
    }

    get altasRev() {
        const cols = this.columnasAltas;
        return this.altasSinCambio.map((a) => ({
            ...a,
            esDependiente: a.titularId || a.titularRef !== undefined && a.titularRef !== null,
            fechaMovTxt: this.fechaMovTxt(a),
            celdas: cols.map((c) => ({ key: a.key + '-' + c.key, clase: c.clase, valor: c.valor(a) || '—' }))
        }));
    }
    get altasSinCambio() {
        // Las altas que el archivo marcó como cambio se muestran en la sección de cambios.
        return (this.revision ? this.revision.altas : []).filter((a) => !a.comoCambio);
    }
    // Columnas opcionales de las altas: solo las que el archivo trae en al menos un renglón.
    get columnasAltas() {
        const altas = this.altasSinCambio;
        return COLUMNAS_ALTA
            .filter((c) => altas.some((a) => c.valor(a)))
            .map((c) => ({ ...c, clase: c.num ? 'num' : '' }));
    }
    get bajasRev() {
        return (this.revision ? this.revision.bajas : []).map((b) => ({ ...b, fechaMovTxt: this.fechaMovTxt(b) }));
    }
    // Fecha del movimiento que trae el archivo (sin ella se usa la fecha general) y su número de endoso.
    fechaMovTxt(x) {
        return (x.fechaMovimiento ? fechaVisible(x.fechaMovimiento) : 'General') + (x.numeroEndoso ? ` · Endoso ${x.numeroEndoso}` : '');
    }
    get hayEndososArchivo() { return (this.endososArchivo || []).length > 0; }
    get textoEndososArchivo() {
        const l = this.endososArchivo || [];
        const lista = l.slice(0, 12).join(', ') + (l.length > 12 ? ` y ${l.length - 12} más` : '');
        return `El archivo trae ${l.length} ${l.length === 1 ? 'endoso' : 'endosos'} (${lista}): cada movimiento queda en su endoso, `
            + 'con la prima que trae el archivo. El número de endoso y la prima de abajo solo aplican a los movimientos sin número.';
    }
    get cambiosRev() {
        if (!this.revision) { return []; }
        // Cambios reales y altas que el archivo marcó como cambio (la persona no existía): todos se ven como CAMBIO.
        const lista = [
            ...this.revision.cambios.map((c) => ({ ...c, lista: 'cambios' })),
            ...this.revision.altas.filter((a) => a.comoCambio).map((a) => ({ ...a, lista: 'altas' }))
        ];
        return lista.map((c) => {
            const difs = (c.diferencias || []).map((d) => ({ campo: d.campo, antes: d.antes, despues: d.despues }));
            if (c.comoCambio) {
                // La persona no existe en la póliza: no hay dato anterior y se muestran todos los datos que trae el archivo.
                const ya = new Set(difs.map((d) => d.campo));
                COLUMNAS_ALTA.forEach((col) => {
                    const v = col.valor(c);
                    if (v && !ya.has(col.label)) { difs.push({ campo: col.label, despues: v }); }
                });
                difs.forEach((d) => { d.antes = 'Sin registro'; });
            }
            return {
                ...c,
                fechaMovTxt: this.fechaMovTxt(c),
                difs: difs.map((d, i) => ({ ...d, key: c.key + '-' + i })),
                sinDifs: !difs.length
            };
        });
    }
    get hayAltas() { return this.altasRev.length > 0; }
    get hayBajas() { return this.bajasRev.length > 0; }
    get hayCambios() { return this.cambiosRev.length > 0; }
    get sinDiferencias() { return !this.hayAltas && !this.hayBajas && !this.hayCambios; }
    get textoAltas() { return `Altas (${this.altasRev.length})`; }
    get textoBajas() { return `Bajas (${this.bajasRev.length})`; }
    get todasBajas() { return this.bajasRev.length > 0 && this.bajasRev.every((b) => b.sel); }
    get hayFaltantes() { return this.bajasRev.some((b) => b.faltante); }
    get textoFaltantes() {
        const n = this.bajasRev.filter((b) => b.faltante).length;
        return `${n} asegurados vigentes no vienen en el archivo. Están desmarcados: marca solo los que sí se dan de baja `
            + '(si el archivo es el censo completo, usa la casilla del encabezado para marcarlos todos).';
    }
    get textoCambios() { return `Cambios (${this.cambiosRev.length})`; }
    get duplicadosRev() { return this.revision ? this.revision.duplicados || [] : []; }
    get hayDuplicados() { return this.duplicadosRev.length > 0; }
    get textoDuplicados() {
        const n = this.duplicadosRev.length;
        return `Altas rechazadas (${n}): ya existen.`;
    }
    get textoSinCambios() { return `${this.revision ? this.revision.sinCambios : 0} asegurados del archivo ya existen igual y no se tocan.`; }
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
        const marcado = e.target.checked;
        if (lista === 'cambios') {
            r.cambios = r.cambios.map((x) => ({ ...x, sel: marcado }));
            r.altas = r.altas.map((x) => (x.comoCambio ? { ...x, sel: marcado } : x));
        } else if (lista === 'altas') {
            r.altas = r.altas.map((x) => (x.comoCambio ? x : { ...x, sel: marcado }));
        } else {
            r[lista] = r[lista].map((x) => ({ ...x, sel: marcado }));
        }
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
            movs.push({ tipo: 'baja', id: b.id, fecha: b.fechaMovimiento || c.fecha, motivo: b.motivo || c.motivo || null,
                endoso: b.numeroEndoso || c.endoso, comentario: c.comentario });
        });
        this.revision.cambios.filter((x) => x.sel).forEach((x) => {
            movs.push({ tipo: 'cambio', id: x.id, datos: x.datos, fecha: x.fechaMovimiento || c.fecha, endoso: x.numeroEndoso || c.endoso, comentario: c.comentario });
        });
        // Altas: titulares primero; el dependiente apunta a la posición del alta de su titular.
        const altas = this.revision.altas.filter((a) => a.sel);
        const posicion = new Map();
        let omitidos = 0;
        altas.filter((a) => !a.titularId && (a.titularRef === undefined || a.titularRef === null)).forEach((a) => {
            posicion.set(a.ref, movs.length);
            movs.push({ tipo: 'alta', datos: a.datos, fecha: a.fechaMovimiento || c.fecha, endoso: a.numeroEndoso || c.endoso, comentario: c.comentario,
                comoCambio: a.comoCambio === true });
        });
        altas.filter((a) => a.titularId || (a.titularRef !== undefined && a.titularRef !== null)).forEach((a) => {
            const ref = a.titularId ? null : posicion.get(a.titularRef);
            if (!a.titularId && ref === undefined) { omitidos++; return; }
            movs.push({ tipo: 'alta', datos: a.datos, titularId: a.titularId || null, titularRef: a.titularId ? null : ref,
                fecha: a.fechaMovimiento || c.fecha, endoso: a.numeroEndoso || c.endoso, comentario: c.comentario, comoCambio: a.comoCambio === true });
        });
        if (!movs.length) {
            this.toast('Movimientos', 'No seleccionaste ningún movimiento.', 'info');
            return;
        }
        if (omitidos) {
            const ok = await LightningConfirm.open({
                message: `${omitidos} dependientes no se aplicarán porque su titular no está seleccionado. ¿Continuar?`,
                variant: 'header', label: 'Altas de dependientes', theme: 'warning'
            });
            if (!ok) { return; }
        }
        await this.enviar(movs, this.primasArchivo);
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
    // Buscador del historial: folio, tipo, fecha, asegurado, certificado, endoso, detalle o usuario.
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
        this.miembros.forEach((r) => {
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
        const registros = this.miembros.filter((r) => (r.solicitud || '') === elegida.folio);
        this.excelDe(registros, elegida.folio || 'sin_solicitud');
        this.cerrarModal();
    }
    // Excel solo con los registros de una solicitud (el que se envía a la aseguradora): desde el encabezado de la
    // solicitud en la tabla o desde las solicitudes del sitio.
    handleExcelSolicitud(e) {
        const folio = (e.detail && e.detail.folio) || (e.currentTarget && e.currentTarget.dataset.folio);
        const registros = this.miembros.filter((r) => r.solicitud === folio);
        if (!registros.length) {
            this.toast('Excel', `La solicitud ${folio} no tiene registros.`, 'info');
            return;
        }
        this.excelDe(registros, folio);
    }
    excelDe(registros, sufijo) {
        // Formato de la solicitud de movimientos a la aseguradora: un renglón por titular con sus dependientes en columnas.
        const porId = new Map(this.miembros.map((m) => [m.id, m]));
        const familias = new Map();
        registros.forEach((r) => {
            const clave = r.esTitular ? r.id : (r.titularId || r.id);
            if (!familias.has(clave)) { familias.set(clave, { titular: porId.get(clave) || r, enMovimiento: [], dependientes: [] }); }
            const fam = familias.get(clave);
            fam.enMovimiento.push(r);
            if (r.id !== clave) { fam.dependientes.push(r); }
        });
        const grupos = [...familias.values()];
        const numDep = Math.max(3, ...grupos.map((g) => g.dependientes.length));
        const columnas = ['Número de movimiento', 'Nombre', 'Apellido Paterno del Asegurado', 'Apellido Materno del Asegurado',
            'Fecha de nacimiento', 'Sexo', 'Movimiento interno', 'Tipo de petición', 'Fecha de petición', 'Poliza', 'Categorias',
            'Certificado', 'Parentesco'];
        for (let i = 1; i <= numDep; i++) {
            columnas.push('Nombre(s)', 'Apellido paterno', 'Apellido materno', 'Fecha de Nacimiento', 'Parentesco', `Sexo Dependiente ${i}`, 'Porcentaje');
        }
        columnas.push('Descripción', 'Correo electrónico');
        const poliza = (this.datos && this.datos.nombre) || '';
        const filas = grupos.map((g) => {
            const t = g.titular;
            // El movimiento del renglón: el del titular si va en él; si no, el del primer dependiente.
            const mov = g.enMovimiento.find((r) => r.id === t.id) || g.enMovimiento[0];
            const n = this.partesNombre(t);
            const fila = [mov.movimientoNumero || '', n.nombres, n.paterno, n.materno, fechaVisible(t.fechaNacimiento), this.sexoExcel(t),
                mov.numeroEndoso || '', mov.tipoMovimiento || (mov.activo ? 'Alta' : 'Baja'), fechaVisible(mov.fechaMovimiento), poliza,
                t.categoria || '', t.certificado || '', '01 Titular'];
            for (let i = 0; i < numDep; i++) {
                const d = g.dependientes[i];
                if (d) {
                    const nd = this.partesNombre(d);
                    fila.push(nd.nombres, nd.paterno, nd.materno, fechaVisible(d.fechaNacimiento), d.parentesco || '', this.sexoExcel(d), 0);
                } else {
                    fila.push('', '', '', '', '', '', 0);
                }
            }
            const motivos = g.enMovimiento.filter((r) => r.motivoBaja).map((r) => (r.id === t.id ? r.motivoBaja : `${r.nombre}: ${r.motivoBaja}`));
            fila.push(motivos.join(' | '), this.correoDe(t) || '');
            return fila;
        });
        descargarExcel(`Asegurados_${String(poliza).replace(/[^A-Za-z0-9-]+/g, '_')}_${sufijo}`, 'Asegurados', columnas, filas);
    }
    // Nombre(s) y apellidos por separado: los del contacto; si no hay, del nombre completo (los dos últimos son los apellidos).
    partesNombre(r) {
        if (r.nombres || r.apellidoPaterno) {
            return { nombres: r.nombres || '', paterno: r.apellidoPaterno || '', materno: r.apellidoMaterno || '' };
        }
        const p = String(r.nombre || '').trim().split(/\s+/).filter((x) => x);
        if (p.length >= 3) { return { nombres: p.slice(0, -2).join(' '), paterno: p[p.length - 2], materno: p[p.length - 1] }; }
        if (p.length === 2) { return { nombres: p[0], paterno: p[1], materno: '' }; }
        return { nombres: p.join(' '), paterno: '', materno: '' };
    }
    sexoExcel(r) {
        const s = this.fold(r.sexoContacto || r.sexo);
        if (!s) { return ''; }
        if (s.startsWith('f') || s.startsWith('mujer')) { return 'Femenino'; }
        if (s.startsWith('mas') || s.startsWith('h') || s === 'm') { return 'Masculino'; }
        return r.sexoContacto || r.sexo;
    }
    fechaHoraTxt(v) {
        if (!v) { return ''; }
        const d = new Date(v);
        return isNaN(d) ? '' : d.toLocaleString('es-MX', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
    }

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

    // Abre la ventana con las otras pólizas (de cualquier aseguradora) donde ya existe el registro.
    verOtrasPolizas(e) {
        const { id, titulo } = e.currentTarget.dataset;
        const v = this.template.querySelector('c-otras-polizas');
        if (v && id) { v.abrir(id, this._recordId, titulo); }
    }
}
