// portalPolizas/portalPolizas.js
// Pólizas del cliente en el sitio Avanza Seguro: listado con búsqueda y filtro, y detalle con documentos.
import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import basePath from '@salesforce/community/basePath';
import misPolizas from '@salesforce/apex/PortalPolizasController.misPolizas';
import detallePoliza from '@salesforce/apex/PortalPolizasController.detallePoliza';
import descargarDocumento from '@salesforce/apex/PortalPolizasController.descargarDocumento';
import puedeVistaPrevia from '@salesforce/apex/PortalPolizasController.puedeVistaPrevia';
import buscarCuentas from '@salesforce/apex/PortalPolizasController.buscarCuentas';
import informacion from '@salesforce/apex/PortalPolizasPestanas.informacion';
import pagos from '@salesforce/apex/PortalPolizasPestanas.pagos';
import vigencias from '@salesforce/apex/PortalPolizasPestanas.vigencias';
import asegurados from '@salesforce/apex/PortalPolizasPestanas.asegurados';
import participantes from '@salesforce/apex/PortalPolizasPestanas.participantes';

// El campo Moneda de la póliza es texto libre (MXN, PESOS, USD, UDI...): se lleva a un código ISO para darle formato con $.
const MONEDAS = { MXN: 'MXN', MXP: 'MXN', MN: 'MXN', PESOS: 'MXN', PESO: 'MXN', 'MONEDA NACIONAL': 'MXN',
    USD: 'USD', DLLS: 'USD', DLS: 'USD', DOLARES: 'USD', DOLAR: 'USD', EUR: 'EUR', EUROS: 'EUR' };
function codigoMoneda(codigo) {
    const clave = String(codigo || 'MXN').normalize('NFD').replace(/[\u0300-\u036f.]/g, '').trim().toUpperCase();
    return MONEDAS[clave] || (/^UDIS?$/.test(clave) ? 'UDI' : clave);
}

// Pestañas del detalle (las mismas que la página de la póliza en Salesforce) y su método Apex.
const PESTANAS = {
    info: informacion,
    pagos: pagos,
    vigencias: vigencias,
    asegurados: asegurados,
    participantes: participantes
};
const PAGINA = 100;
const FILTROS_ESTADO = [
    { label: 'Vigentes', value: 'vigentes' },
    { label: 'Dados de baja', value: 'bajas' },
    { label: 'Todos', value: 'todos' }
];
const FILTROS_GRUPO = [
    { label: 'Todos', value: 'todos' },
    { label: 'Asegurados', value: 'asegurados' },
    { label: 'Beneficiarios', value: 'beneficiario' },
    { label: 'Otros roles', value: 'otro' }
];
const ESTADOS_CERRADOS = ['Cancelado', 'Condonado'];

// Igual que PortalPolizasController.MAX_BYTES_DESCARGA: arriba de esto se usa el enlace directo del archivo.
const MAX_BYTES_DESCARGA = 3 * 1024 * 1024;

const FILTROS = [
    { label: 'Vigentes', value: 'vigentes' },
    { label: 'Todas', value: 'todas' },
    { label: 'No vigentes', value: 'novigentes' }
];

export default class PortalPolizas extends LightningElement {
    @api titulo = 'Mis pólizas';
    @api mensajeVacio = 'Aún no tienes pólizas registradas. Si crees que es un error, contacta a tu asesor.';

    polizas = [];
    cargando = true;
    error;
    busqueda = '';
    filtro = 'vigentes';
    filtros = FILTROS;

    seleccionadaId;
    detalle;
    cargandoDetalle = false;
    errorDetalle;
    descargandoId;
    errorDescarga;

    // Pestañas del detalle: cada una se carga la primera vez que se abre.
    pestana = 'info';
    pestanas = this.pestanasVacias();
    filtrosEstado = FILTROS_ESTADO;
    filtrosGrupo = FILTROS_GRUPO;
    busquedaAsegurados = '';
    filtroAsegurados = 'vigentes';
    limiteAsegurados = PAGINA;
    busquedaParticipantes = '';
    filtroParticipantes = 'todos';
    limiteParticipantes = PAGINA;

    // Vista previa de administrador. null (no undefined) para que los wires sí se ejecuten sin cuenta elegida.
    puedeVista = false;
    cuentaVistaPrevia = null;
    nombreVistaPrevia;
    textoCuenta = '';
    cuentasEncontradas = [];
    buscandoCuentas = false;
    errorCuentas;
    temporizadorBusqueda;

    // Parámetros de la URL: ?buscar= (búsqueda del encabezado), ?poliza= (abre una póliza) y ?pestana= (pestaña del detalle).
    estadoUrl;
    @wire(CurrentPageReference)
    recibirPagina(ref) {
        const estado = (ref && ref.state) || {};
        const clave = JSON.stringify([estado.buscar, estado.poliza, estado.pestana]);
        if (clave === this.estadoUrl) return;
        this.estadoUrl = clave;
        if (estado.buscar) {
            this.busqueda = estado.buscar;
            this.filtro = 'todas';
        }
        if (estado.poliza) {
            this.abrirPoliza(estado.poliza, estado.pestana);
        }
    }

    @wire(puedeVistaPrevia)
    recibirPermiso({ data }) {
        this.puedeVista = data === true;
    }

    @wire(misPolizas, { cuentaVistaPrevia: '$cuentaVistaPrevia' })
    recibirPolizas({ data, error }) {
        if (data) {
            this.polizas = data.map((p) => this.decorar(p));
            this.error = undefined;
            // Si no hay vigentes, se muestran todas para no dejar la pantalla vacía.
            if (!this.polizas.some((p) => p.vigente)) {
                this.filtro = 'todas';
            }
            this.cargando = false;
        } else if (error) {
            this.error = this.mensaje(error);
            this.cargando = false;
        }
    }

    @wire(detallePoliza, { policyId: '$seleccionadaId', cuentaVistaPrevia: '$cuentaVistaPrevia' })
    recibirDetalle({ data, error }) {
        if (!this.seleccionadaId) {
            return;
        }
        if (data) {
            const raiz = (basePath || '').replace(/\/s$/, '');
            this.detalle = {
                poliza: this.decorar(data.poliza),
                documentos: (data.documentos || []).map((d) => ({
                    ...d,
                    nombre: d.extension ? `${d.titulo}.${d.extension}` : d.titulo,
                    tamanoTexto: this.tamano(d.tamano),
                    porApex: !d.tamano || d.tamano <= MAX_BYTES_DESCARGA,
                    url: `${raiz}/sfc/servlet.shepherd/document/download/${d.id}`
                }))
            };
            this.errorDetalle = undefined;
            // La pestaña activa se carga al abrir la póliza (antes lo hacía lightning-tabset al mostrarse).
            this.cargarPestana(this.pestana);
            this.cargandoDetalle = false;
        } else if (error) {
            this.errorDetalle = this.mensaje(error);
            this.cargandoDetalle = false;
        }
    }

    // ---------- Vista previa de administrador ----------

    get esperandoCuenta() {
        return this.puedeVista && !this.cuentaVistaPrevia;
    }

    get hayCuentasEncontradas() {
        return this.cuentasEncontradas.length > 0;
    }

    get sinCuentasEncontradas() {
        return !this.buscandoCuentas && !this.errorCuentas && this.textoCuenta.trim().length >= 2
            && this.cuentasEncontradas.length === 0;
    }

    handleTextoCuenta(event) {
        this.textoCuenta = event.target.value || '';
        clearTimeout(this.temporizadorBusqueda);
        const texto = this.textoCuenta.trim();
        if (texto.length < 2) {
            this.cuentasEncontradas = [];
            this.buscandoCuentas = false;
            return;
        }
        this.buscandoCuentas = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.temporizadorBusqueda = setTimeout(() => this.buscar(texto), 300);
    }

    async buscar(texto) {
        try {
            const cuentas = await buscarCuentas({ texto });
            if (texto !== this.textoCuenta.trim()) return;
            this.cuentasEncontradas = cuentas.map((c) => ({
                ...c,
                detalle: `${c.polizas} póliza${c.polizas === 1 ? '' : 's'} como titular`
            }));
            this.errorCuentas = undefined;
        } catch (error) {
            this.errorCuentas = this.mensaje(error);
        } finally {
            this.buscandoCuentas = false;
        }
    }

    handleElegirCuenta(event) {
        const { id, nombre } = event.currentTarget.dataset;
        this.reiniciarVista();
        this.nombreVistaPrevia = nombre;
        this.cuentaVistaPrevia = id;
    }

    handleCambiarCuenta() {
        this.reiniciarVista();
        this.nombreVistaPrevia = undefined;
        this.cuentaVistaPrevia = null;
    }

    reiniciarVista() {
        this.reiniciarPestanas();
        this.seleccionadaId = undefined;
        this.detalle = undefined;
        this.errorDetalle = undefined;
        this.polizas = [];
        this.error = undefined;
        this.busqueda = '';
        this.filtro = 'vigentes';
        this.cargando = true;
        this.textoCuenta = '';
        this.cuentasEncontradas = [];
    }

    // ---------- Listado ----------

    get hayPolizas() {
        return this.polizas.length > 0;
    }

    get polizasFiltradas() {
        const texto = this.busqueda.trim().toLowerCase();
        return this.polizas.filter((p) => {
            if (this.filtro === 'vigentes' && !p.vigente) return false;
            if (this.filtro === 'novigentes' && p.vigente) return false;
            return !texto || p.textoBusqueda.includes(texto);
        });
    }

    get sinResultados() {
        return this.hayPolizas && this.polizasFiltradas.length === 0;
    }

    get resumen() {
        const total = this.polizas.length;
        const vigentes = this.polizas.filter((p) => p.vigente).length;
        return `${vigentes} vigente${vigentes === 1 ? '' : 's'} de ${total}`;
    }

    get enListado() {
        return !this.seleccionadaId;
    }

    handleBusqueda(event) {
        this.busqueda = event.target.value || '';
    }

    handleFiltro(event) {
        this.filtro = event.currentTarget.dataset.value;
    }

    // Botones de filtro con color: cada opción tiene su tono y el seleccionado va relleno.
    opciones(lista, valor, cuentas) {
        return lista.map((o, i) => ({
            ...o,
            clase: `filtro filtro_tono${(i % 4) + 1}${o.value === valor ? ' filtro_activo' : ''}`,
            presionado: o.value === valor ? 'true' : 'false',
            cuenta: cuentas ? cuentas[o.value] : null,
            hayCuenta: !!cuentas && cuentas[o.value] !== undefined
        }));
    }

    get opcionesFiltro() {
        const total = this.polizas.length;
        const vigentes = this.polizas.filter((p) => p.vigente).length;
        return this.opciones(FILTROS, this.filtro, { vigentes, todas: total, novigentes: total - vigentes });
    }

    get opcionesEstado() {
        const datos = this.pestanas.asegurados.datos;
        const filas = (datos && datos.filas) || [];
        const vigentes = filas.filter((f) => f.activo).length;
        return this.opciones(FILTROS_ESTADO, this.filtroAsegurados, { vigentes, bajas: filas.length - vigentes, todos: filas.length });
    }

    get opcionesGrupo() {
        const datos = this.pestanas.participantes.datos;
        const filas = (datos && datos.filas) || [];
        const cuenta = (g) => filas.filter((f) => f.grupo === g).length;
        return this.opciones(FILTROS_GRUPO, this.filtroParticipantes, {
            todos: filas.length,
            asegurados: cuenta('asegurado') + cuenta('dependiente'),
            beneficiario: cuenta('beneficiario'),
            otro: cuenta('otro')
        });
    }

    handleAbrir(event) {
        this.abrirPoliza(event.currentTarget.dataset.id);
        window.scrollTo({ top: 0, behavior: 'smooth' });
    }

    abrirPoliza(id, pestana) {
        if (!id) return;
        this.detalle = undefined;
        this.errorDetalle = undefined;
        this.cargandoDetalle = true;
        this.reiniciarPestanas();
        if (pestana && ['info', 'pagos', 'vigencias', 'asegurados', 'participantes', 'solicitudes'].includes(pestana)) {
            this.pestana = pestana;
        }
        this.seleccionadaId = id;
    }

    handleTeclaTarjeta(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleAbrir(event);
        }
    }

    handleRegresar() {
        this.reiniciarPestanas();
        this.seleccionadaId = undefined;
        this.detalle = undefined;
        this.errorDetalle = undefined;
    }

    // ---------- Pestañas del detalle ----------

    pestanasVacias() {
        const p = {};
        Object.keys(PESTANAS).forEach((k) => {
            p[k] = { cargando: false, error: undefined, datos: undefined, cargada: false };
        });
        return p;
    }

    reiniciarPestanas() {
        this.pestana = 'info';
        this.pestanas = this.pestanasVacias();
        this.busquedaAsegurados = '';
        this.filtroAsegurados = 'vigentes';
        this.limiteAsegurados = PAGINA;
        this.busquedaParticipantes = '';
        this.filtroParticipantes = 'todos';
        this.limiteParticipantes = PAGINA;
    }

    get pestanaInfo() { return this.pestanas.info; }
    get pestanaPagos() { return this.pestanas.pagos; }
    get pestanaVigencias() { return this.pestanas.vigencias; }
    get pestanaAsegurados() { return this.pestanas.asegurados; }
    get pestanaParticipantes() { return this.pestanas.participantes; }

    handlePestana(event) {
        const clave = event.currentTarget.dataset.value;
        this.pestana = clave;
        this.cargarPestana(clave);
    }

    // Pestañas del detalle con el mismo estilo que los filtros (botones de color, la activa rellena).
    get opcionesPestanas() {
        return this.opciones([
            { label: 'Información Póliza', value: 'info' },
            { label: 'Pagos', value: 'pagos' },
            { label: 'Vigencias', value: 'vigencias' },
            { label: this.tituloBienes, value: 'asegurados' },
            { label: 'Participantes', value: 'participantes' },
            // Altas, bajas y cambios que pide el cliente (c-portal-solicitudes carga sus propios datos).
            { label: 'Solicitudes', value: 'solicitudes' }
        ], this.pestana);
    }

    get verInfo() { return this.pestana === 'info'; }
    get verPagos() { return this.pestana === 'pagos'; }
    get verVigencias() { return this.pestana === 'vigencias'; }
    get verAsegurados() { return this.pestana === 'asegurados'; }
    get verParticipantes() { return this.pestana === 'participantes'; }
    get verSolicitudes() { return this.pestana === 'solicitudes'; }

    async cargarPestana(clave) {
        const actual = this.pestanas[clave];
        const policyId = this.seleccionadaId;
        if (!policyId || !actual || actual.cargada || actual.cargando) return;
        this.ponerPestana(clave, { cargando: true, error: undefined });
        try {
            const datos = await PESTANAS[clave]({ policyId, cuentaVistaPrevia: this.cuentaVistaPrevia });
            if (policyId !== this.seleccionadaId) return; // el usuario ya abrió otra póliza
            this.ponerPestana(clave, { cargando: false, cargada: true, datos: this.decorarPestana(clave, datos) });
        } catch (error) {
            if (policyId !== this.seleccionadaId) return;
            this.ponerPestana(clave, { cargando: false, error: this.mensaje(error) });
        }
    }

    ponerPestana(clave, cambios) {
        this.pestanas = { ...this.pestanas, [clave]: { ...this.pestanas[clave], ...cambios } };
    }

    decorarPestana(clave, datos) {
        const m = (n) => (n == null ? '—' : this.moneda(n, datos.moneda));
        if (clave === 'info') {
            return {
                secciones: datos.secciones.map((s) => ({
                    titulo: s.titulo,
                    campos: s.campos.map((c) => ({
                        etiqueta: c.etiqueta,
                        clase: c.ancho ? 'campo_ancho' : '',
                        valor: c.tipo === 'moneda' ? m(c.numero)
                            : c.tipo === 'fecha' ? this.fecha(c.fecha)
                                : c.tipo === 'numero' ? Number(c.numero).toLocaleString('es-MX')
                                    : c.texto
                    }))
                }))
            };
        }
        if (clave === 'pagos') {
            return {
                hayCuotas: datos.cuotas.length > 0,
                hayEstimadas: datos.cuotas.some((q) => q.estimada),
                totalImporteTexto: m(datos.totalImporte),
                totalPagadoTexto: m(datos.totalPagado),
                totalPendienteTexto: m(datos.totalPendiente),
                cuotas: datos.cuotas.map((q) => ({
                    ...q,
                    reciboTexto: q.recibo || '—',
                    venceTexto: this.fecha(q.vence),
                    fechaPagoTexto: this.fecha(q.fechaPago),
                    importeTexto: m(q.importe),
                    pagadoTexto: m(q.pagado),
                    pendienteTexto: m(q.pendiente),
                    estadoClase: this.claseEstadoCuota(q.estado),
                    moraTexto: q.diasMora ? `${q.diasMora} día${q.diasMora === 1 ? '' : 's'} de atraso` : null,
                    reemplazosTexto: q.recibosReemplazados
                        ? `${q.recibosReemplazados} recibo${q.recibosReemplazados === 1 ? '' : 's'} reemplazado${q.recibosReemplazados === 1 ? '' : 's'}`
                        : null
                }))
            };
        }
        if (clave === 'vigencias') {
            return {
                vigencias: datos.vigencias.map((v) => ({
                    ...v,
                    clase: v.actual ? 'fila_actual' : '',
                    numeroTexto: v.actual ? `${v.numero} · la que estás viendo` : v.numero,
                    primaTexto: m(v.prima),
                    pagadoTexto: m(v.pagado),
                    pendienteTexto: m(v.pendiente)
                }))
            };
        }
        // asegurados y participantes: se filtran y paginan en los getters.
        return datos;
    }

    claseEstadoCuota(estado) {
        if (estado === 'Conciliado') return 'estado estado_vigente';
        if (estado === 'Vencido') return 'estado estado_vencido';
        if (ESTADOS_CERRADOS.includes(estado)) return 'estado estado_inactiva';
        return 'estado estado_pendiente';
    }

    handleAbrirVigencia(event) {
        const id = event.currentTarget.dataset.id;
        this.detalle = undefined;
        this.errorDetalle = undefined;
        this.cargandoDetalle = true;
        this.reiniciarPestanas();
        this.seleccionadaId = id;
        window.scrollTo({ top: 0, behavior: 'smooth' });
    }

    // Asegurados, Vehículos o Ubicaciones, según el ramo (igual que la página de la póliza en Salesforce).
    get tituloBienes() {
        const r = String((this.detalle && this.detalle.poliza && this.detalle.poliza.ramo) || '').toLowerCase()
            .normalize('NFD').replace(/[̀-ͯ]/g, '');
        if (r.startsWith('auto')) return 'Vehículos';
        if (r.startsWith('dano') || r.startsWith('empresarial')) return 'Ubicaciones';
        return 'Asegurados';
    }

    get tablaAsegurados() {
        const datos = this.pestanas.asegurados.datos;
        if (!datos) return undefined;
        const m = (n) => (n == null ? '—' : this.moneda(n, datos.moneda));
        const texto = this.busquedaAsegurados.trim().toLowerCase();
        const todas = datos.filas;
        const filtradas = todas.filter((f) => {
            if (this.filtroAsegurados === 'vigentes' && !f.activo) return false;
            if (this.filtroAsegurados === 'bajas' && f.activo) return false;
            return !texto || [f.clave, f.nombre, f.detalle, f.titular].filter(Boolean).join(' ').toLowerCase().includes(texto);
        });
        const estado = (f) => ({
            clave: 'estado',
            texto: f.activo ? 'Vigente' : 'Baja',
            claseTexto: f.activo ? 'estado estado_vigente' : 'estado estado_inactiva',
            sub: !f.activo ? [this.fechaCorta(f.hasta), f.motivoBaja].filter(Boolean).join(' · ') : null
        });
        const tipos = {
            personas: {
                nombre: 'asegurado', plural: 'asegurados', placeholder: 'Buscar por nombre o certificado',
                vacio: 'No hay asegurados registrados en esta póliza.',
                columnas: ['Certificado', 'Nombre', 'Parentesco', 'Categoría', 'Alta', 'Prima', 'Estado'],
                celdas: (f) => [
                    { clave: 'cert', texto: f.clave || '—' },
                    { clave: 'nombre', texto: f.nombre, claseTexto: 'celda_principal', sub: f.dependiente && f.titular ? `de ${f.titular}` : null },
                    { clave: 'par', texto: f.parentesco || '—' },
                    { clave: 'cat', texto: f.detalle || '—' },
                    { clave: 'alta', texto: this.fecha(f.desde) },
                    { clave: 'prima', texto: m(f.prima), clase: 'num' },
                    estado(f)
                ]
            },
            vehiculos: {
                nombre: 'vehículo', plural: 'vehículos', placeholder: 'Buscar por vehículo, placas o serie',
                vacio: 'No hay vehículos registrados en esta póliza.',
                columnas: ['Inciso', 'Vehículo', 'Alta', 'Valor', 'Prima', 'Estado'],
                celdas: (f) => [
                    { clave: 'inc', texto: f.clave || '—' },
                    { clave: 'nombre', texto: f.nombre, claseTexto: 'celda_principal', sub: f.detalle },
                    { clave: 'alta', texto: this.fecha(f.desde) },
                    { clave: 'valor', texto: m(f.suma), clase: 'num' },
                    { clave: 'prima', texto: m(f.prima), clase: 'num' },
                    estado(f)
                ]
            },
            ubicaciones: {
                nombre: 'ubicación', plural: 'ubicaciones', placeholder: 'Buscar por ubicación o dirección',
                vacio: 'No hay ubicaciones registradas en esta póliza.',
                columnas: ['Inciso', 'Ubicación', 'Alta', 'Suma asegurada', 'Prima', 'Estado'],
                celdas: (f) => [
                    { clave: 'inc', texto: f.clave || '—' },
                    { clave: 'nombre', texto: f.nombre, claseTexto: 'celda_principal', sub: f.detalle },
                    { clave: 'alta', texto: this.fecha(f.desde) },
                    { clave: 'suma', texto: m(f.suma), clase: 'num' },
                    { clave: 'prima', texto: m(f.prima), clase: 'num' },
                    estado(f)
                ]
            }
        };
        const t = tipos[datos.tipo] || tipos.personas;
        const numericas = ['Prima', 'Valor', 'Suma asegurada'];
        const activos = todas.filter((f) => f.activo).length;
        return {
            soloMiGrupo: datos.soloMiGrupo,
            hayFilas: todas.length > 0,
            placeholder: t.placeholder,
            vacio: t.vacio,
            resumen: `${activos} ${activos === 1 ? t.nombre : t.plural} vigente${activos === 1 ? '' : 's'}`
                + (todas.length > activos ? ` · ${todas.length - activos} de baja` : '')
                + (filtradas.length !== todas.length ? ` · mostrando ${filtradas.length}` : ''),
            columnas: t.columnas.map((c) => ({ clave: c, etiqueta: c, clase: numericas.includes(c) ? 'num' : '' })),
            filas: filtradas.slice(0, this.limiteAsegurados).map((f) => ({
                id: f.id,
                clase: [f.dependiente ? 'fila_dependiente' : '', f.activo ? '' : 'fila_baja'].join(' ').trim(),
                celdas: t.celdas(f)
            })),
            hayMas: filtradas.length > this.limiteAsegurados
        };
    }

    handleBusquedaAsegurados(event) {
        this.busquedaAsegurados = event.target.value || '';
        this.limiteAsegurados = PAGINA;
    }

    handleFiltroAsegurados(event) {
        this.filtroAsegurados = event.currentTarget.dataset.value;
        this.limiteAsegurados = PAGINA;
    }

    handleMasAsegurados() {
        this.limiteAsegurados += PAGINA;
    }

    // Participantes

    get tablaParticipantes() {
        const datos = this.pestanas.participantes.datos;
        if (!datos) return undefined;
        // En autos, daños y empresarial se muestran los participantes con una nota de dónde están los bienes.
        const notaBienes = datos.tipo === 'vehiculos'
            ? 'Esta póliza asegura vehículos: están en la pestaña Vehículos.'
            : (datos.tipo === 'ubicaciones' ? 'Esta póliza asegura bienes: las ubicaciones están en la pestaña Ubicaciones.' : null);
        const texto = this.busquedaParticipantes.trim().toLowerCase();
        const todas = datos.filas;
        const filtradas = todas.filter((f) => {
            const g = this.filtroParticipantes;
            if (g === 'asegurados' && f.grupo !== 'asegurado' && f.grupo !== 'dependiente') return false;
            if ((g === 'beneficiario' || g === 'otro') && f.grupo !== g) return false;
            return !texto || [f.nombre, f.roles, f.titular].filter(Boolean).join(' ').toLowerCase().includes(texto);
        });
        const cuenta = (g) => todas.filter((f) => f.grupo === g).length;
        const partes = [
            [cuenta('asegurado'), 'titular', 'titulares'],
            [cuenta('dependiente'), 'dependiente', 'dependientes'],
            [cuenta('beneficiario'), 'beneficiario', 'beneficiarios'],
            [cuenta('otro'), 'otro rol', 'otros roles'],
            [todas.filter((f) => !f.activo).length, 'dado de baja', 'dados de baja']
        ].filter(([n]) => n > 0).map(([n, s, p]) => `${n} ${n === 1 ? s : p}`);
        return {
            soloMiGrupo: datos.soloMiGrupo,
            hayFilas: todas.length > 0,
            resumen: partes.join(' · ') + (filtradas.length !== todas.length ? ` · mostrando ${filtradas.length}` : ''),
            notaBienes,
            // Columnas que ningún participante trae (p. ej. parentesco y porcentaje en daños) no se muestran.
            conParentesco: todas.some((f) => f.parentesco),
            conPorcentaje: todas.some((f) => f.porcentaje != null),
            conVigencia: todas.some((f) => f.desde || f.hasta),
            filas: filtradas.slice(0, this.limiteParticipantes).map((f) => ({
                ...f,
                clase: [f.dependiente ? 'fila_dependiente' : '', f.activo ? '' : 'fila_baja'].join(' ').trim(),
                roles: f.roles || '—',
                parentesco: f.parentesco || '—',
                deTexto: f.titular ? `de ${f.titular}` : null,
                porcentajeTexto: f.porcentaje != null ? `${Number(f.porcentaje).toLocaleString('es-MX')} %` : '—',
                vigenciaTexto: this.rango(f.desde, f.hasta),
                estadoTexto: f.activo ? 'Vigente' : 'Baja',
                estadoClase: f.activo ? 'estado estado_vigente' : 'estado estado_inactiva'
            })),
            hayMas: filtradas.length > this.limiteParticipantes
        };
    }

    handleBusquedaParticipantes(event) {
        this.busquedaParticipantes = event.target.value || '';
        this.limiteParticipantes = PAGINA;
    }

    handleFiltroParticipantes(event) {
        this.filtroParticipantes = event.currentTarget.dataset.value;
        this.limiteParticipantes = PAGINA;
    }

    handleMasParticipantes() {
        this.limiteParticipantes += PAGINA;
    }

    fechaCorta(valor) {
        return valor ? this.fecha(valor) : null;
    }

    // ---------- Detalle ----------

    get hayDocumentos() {
        return this.detalle && this.detalle.documentos.length > 0;
    }

    get documentosVista() {
        return (this.detalle ? this.detalle.documentos : []).map((d) => ({
            ...d,
            descargando: d.id === this.descargandoId,
            textoBoton: d.id === this.descargandoId ? 'Descargando…' : 'Descargar'
        }));
    }

    async handleDescargar(event) {
        const id = event.currentTarget.dataset.id;
        if (this.descargandoId) return;
        this.descargandoId = id;
        this.errorDescarga = undefined;
        try {
            const archivo = await descargarDocumento({
                policyId: this.seleccionadaId,
                documentId: id,
                cuentaVistaPrevia: this.cuentaVistaPrevia
            });
            const bytes = Uint8Array.from(atob(archivo.base64), (c) => c.charCodeAt(0));
            const url = URL.createObjectURL(new Blob([bytes], { type: this.mime(archivo.tipo) }));
            const a = document.createElement('a');
            a.href = url;
            a.download = archivo.nombre;
            this.template.querySelector('.documentos').appendChild(a);
            a.click();
            a.remove();
            setTimeout(() => URL.revokeObjectURL(url), 10000);
        } catch (error) {
            this.errorDescarga = this.mensaje(error);
        } finally {
            this.descargandoId = undefined;
        }
    }

    mime(tipo) {
        const tipos = {
            PDF: 'application/pdf',
            PNG: 'image/png',
            JPG: 'image/jpeg',
            JPEG: 'image/jpeg',
            WORD_X: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            EXCEL_X: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            XML: 'application/xml',
            ZIP: 'application/zip'
        };
        return tipos[(tipo || '').toUpperCase()] || 'application/octet-stream';
    }

    // ---------- Utilidades ----------

    decorar(p) {
        const fmt = (n) => this.moneda(n, p.moneda);
        const tieneVencido = p.montoVencido > 0;
        return {
            ...p,
            titulo: [p.ramo, p.aseguradora].filter(Boolean).join(' · ') || 'Póliza',
            estadoTexto: p.estado || (p.vigente ? 'Vigente' : 'No vigente'),
            estadoClase: `estado ${p.vigente ? 'estado_vigente' : 'estado_inactiva'}`,
            vigencia: this.rango(p.inicioVigencia, p.finVigencia),
            primaTexto: p.prima != null ? fmt(p.prima) : '—',
            proximoPagoTexto: this.fecha(p.proximoPago),
            montoVencidoTexto: tieneVencido ? fmt(p.montoVencido) : null,
            montoPorPagarTexto: p.montoPorPagar > 0 ? fmt(p.montoPorPagar) : null,
            tieneVencido,
            textoBusqueda: [p.numero, p.ramo, p.aseguradora, p.tipo, p.bienAsegurado, p.titular]
                .filter(Boolean)
                .join(' ')
                .toLowerCase()
        };
    }

    fecha(valor) {
        if (!valor) return '—';
        const [a, m, d] = String(valor).substring(0, 10).split('-').map(Number);
        return new Intl.DateTimeFormat('es-MX', { day: '2-digit', month: 'short', year: 'numeric' })
            .format(new Date(a, m - 1, d));
    }

    rango(desde, hasta) {
        if (!desde && !hasta) return '—';
        return `${this.fecha(desde)} – ${this.fecha(hasta)}`;
    }

    moneda(n, codigo) {
        const iso = codigoMoneda(codigo);
        if (iso === 'UDI') {
            return `${Number(n || 0).toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} UDIS`;
        }
        try {
            return new Intl.NumberFormat('es-MX', { style: 'currency', currency: iso }).format(n);
        } catch (e) {
            return `$${Number(n || 0).toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
        }
    }

    tamano(bytes) {
        if (!bytes) return '';
        if (bytes < 1024) return `${bytes} B`;
        if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
        return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    }

    mensaje(error) {
        return (error && error.body && error.body.message) || 'Ocurrió un error al cargar la información.';
    }
}
