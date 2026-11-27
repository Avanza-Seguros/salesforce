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
    vigencias: vigencias
    // Asegurados / Vehículos / Ubicaciones y Participantes usan los componentes de Salesforce (cargan sus datos).
};
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

    // Control segmentado (filtros y pestañas): la opción activa va en blanco («on»).
    opciones(lista, valor, cuentas) {
        return lista.map((o) => ({
            ...o,
            clase: o.value === valor ? 'on' : '',
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

    // ---------- Banda azul del listado ----------

    get totalVigentes() {
        return this.polizas.filter((p) => p.vigente).length;
    }

    get textoVigentesHero() {
        const v = this.totalVigentes;
        return `${v} póliza${v === 1 ? '' : 's'} vigente${v === 1 ? '' : 's'} de ${this.polizas.length}`;
    }

    get textoDePolizas() {
        const t = this.polizas.length;
        return `de ${t} póliza${t === 1 ? '' : 's'}`;
    }

    // Empresa en el renglón superior: la de la vista previa o, si todas las pólizas son del mismo titular, ese titular.
    get eyebrowListado() {
        const titulares = [...new Set(this.polizas.map((p) => p.titular).filter(Boolean))];
        const empresa = this.nombreVistaPrevia || (titulares.length === 1 ? titulares[0] : null);
        return [this.titulo, empresa].filter(Boolean).join(' · ');
    }

    // Suma de las primas vigentes, solo si todas están en la misma moneda (si no, no se muestra).
    get primaEnVigorTexto() {
        const vigentes = this.polizas.filter((p) => p.vigente && p.prima != null);
        if (!vigentes.length) return null;
        const monedas = new Set(vigentes.map((p) => codigoMoneda(p.moneda)));
        if (monedas.size !== 1) return null;
        const total = vigentes.reduce((s, p) => s + Number(p.prima || 0), 0);
        return this.moneda(total, vigentes[0].moneda);
    }

    get claseGlassVigentes() {
        return this.primaEnVigorTexto ? 'glass' : 'glass wide';
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
            // Las solicitudes se ven y se piden en Asegurados, Vehículos o Ubicaciones.
            this.pestana = pestana === 'solicitudes' ? 'asegurados' : pestana;
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
        this.quitarSolicitud();
    }

    get pestanaInfo() { return this.pestanas.info; }
    get pestanaPagos() { return this.pestanas.pagos; }
    get pestanaVigencias() { return this.pestanas.vigencias; }

    handlePestana(event) {
        const clave = event.currentTarget.dataset.value;
        this.pestana = clave;
        this.quitarSolicitud();
        this.cargarPestana(clave);
    }

    // Pestañas del detalle con el mismo estilo que los filtros (botones de color, la activa rellena).
    get opcionesPestanas() {
        const colores = { info: '#1d4ed8', pagos: '#0e9488', vigencias: '#7c3aed', asegurados: '#d97706', participantes: '#4f46e5',
            siniestros: '#e11d48' };
        const lista = [
            { label: 'Información Póliza', value: 'info' },
            { label: 'Pagos', value: 'pagos' },
            { label: 'Vigencias', value: 'vigencias' },
            { label: this.tituloBienes, value: 'asegurados' },
            { label: 'Participantes', value: 'participantes' }
        ];
        // Siniestros: solo el contratante de una póliza empresarial.
        if (this.detalle && this.detalle.poliza && this.detalle.poliza.conSiniestros) { lista.push({ label: 'Siniestros', value: 'siniestros' }); }
        return this.opciones(lista, this.pestana).map((o) => ({ ...o, estiloPunto: `background:${colores[o.value]}` }));
    }

    // Banda azul del detalle: la prima ocupa todo el ancho si no hay segundo indicador (vencido o por pagar).
    get claseGlassPrima() {
        const p = this.detalle && this.detalle.poliza;
        return p && (p.tieneVencido || p.montoPorPagarTexto) ? 'glass' : 'glass wide';
    }

    get chipDetalle() {
        return (this.detalle && this.detalle.poliza && this.detalle.poliza.chip) || 'P';
    }

    get textoCuotas() {
        const datos = this.pestanaPagos.datos;
        const n = datos ? datos.cuotas.length : 0;
        const forma = this.detalle && this.detalle.poliza && this.detalle.poliza.formaPago;
        return [`${n} cuota${n === 1 ? '' : 's'}`, forma ? `forma de pago ${String(forma).toLowerCase()}` : null].filter(Boolean).join(' · ');
    }

    get verInfo() { return this.pestana === 'info'; }
    get verPagos() { return this.pestana === 'pagos'; }
    get verVigencias() { return this.pestana === 'vigencias'; }
    get verAsegurados() { return this.pestana === 'asegurados'; }
    get verParticipantes() { return this.pestana === 'participantes'; }
    get verSiniestros() { return this.pestana === 'siniestros'; }

    // Solicitud nueva (Nueva solicitud, Alta o Baja): el formulario toma el lugar de la tabla hasta enviarlo o cancelar.
    solicitudNueva = null;
    avisoSolicitud = '';
    handleNuevaSolicitud(event) {
        const d = event.detail || {};
        this.avisoSolicitud = '';
        this.solicitudNueva = { tipo: d.tipo || null, ids: d.ids || [] };
    }
    handleCerrarSolicitud(event) {
        this.solicitudNueva = null;
        this.avisoSolicitud = (event.detail && event.detail.exito) || '';
    }
    quitarSolicitud() {
        this.solicitudNueva = null;
        this.avisoSolicitud = '';
    }

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
                        clase: c.ancho ? 'field field_ancho' : 'field',
                        valor: c.tipo === 'moneda' ? m(c.numero)
                            : c.tipo === 'fecha' ? this.fecha(c.fecha)
                                : c.tipo === 'numero' ? Number(c.numero).toLocaleString('es-MX')
                                    : c.texto
                    }))
                }))
            };
        }
        if (clave === 'pagos') {
            const total = Number(datos.totalImporte || 0);
            const pct = (n) => `width:${total > 0 ? Math.max(0, Math.min(100, Math.round((Number(n || 0) / total) * 100))) : 0}%`;
            return {
                barraTotal: `width:${total > 0 ? 100 : 0}%`,
                barraPagado: pct(datos.totalPagado),
                barraPendiente: pct(datos.totalPendiente),
                hayCuotas: datos.cuotas.length > 0,
                hayEstimadas: datos.cuotas.some((q) => q.estimada),
                totalImporteTexto: m(datos.totalImporte),
                totalPagadoTexto: m(datos.totalPagado),
                totalPendienteTexto: m(datos.totalPendiente),
                cuotas: datos.cuotas.map((q, i) => ({
                    ...q,
                    numero: i + 1,
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
                    estadoClase: v.actual && this.detalle && this.detalle.poliza.vigente ? 'badge b-green' : 'badge b-gray',
                    primaTexto: m(v.prima),
                    pagadoTexto: m(v.pagado),
                    pendienteTexto: m(v.pendiente)
                }))
            };
        }
        return datos;
    }

    claseEstadoCuota(estado) {
        if (estado === 'Conciliado') return 'badge b-green';
        if (estado === 'Vencido') return 'badge b-red';
        if (ESTADOS_CERRADOS.includes(estado)) return 'badge b-gray';
        return 'badge b-amber';
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

    get bienesVehiculos() { return this.tituloBienes === 'Vehículos'; }
    get bienesUbicaciones() { return this.tituloBienes === 'Ubicaciones'; }
    // Para pasar true a las propiedades booleanas de los componentes de Salesforce (portal, read-only).
    get siempre() { return true; }
    // Quien no es el contratante (titular) solo ve a su grupo familiar.
    get soloMiGrupo() {
        const p = this.detalle && this.detalle.poliza;
        return !!p && !!p.miRol && p.miRol !== 'Titular';
    }
    get notaMiGrupoAsegurados() { return this.soloMiGrupo && this.tituloBienes === 'Asegurados'; }
    get notaMiGrupoParticipantes() { return this.soloMiGrupo; }
    // Solo el contratante registra movimientos en las pestañas de Salesforce; los demás solo consultan.
    get soloConsulta() {
        const p = this.detalle && this.detalle.poliza;
        return !p || p.miRol !== 'Titular';
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
            estadoClase: p.vigente ? 'badge b-green' : 'badge b-gray',
            heroPunto: p.vigente ? 'dot dot_vigente' : 'dot dot_inactiva',
            chip: this.iniciales(p.ramo || p.tipo || 'Póliza'),
            ramoTexto: p.ramo || p.tipo || 'Póliza',
            subPoliza: p.tipo && p.tipo !== p.ramo ? p.tipo : p.bienAsegurado,
            lineaHero: [p.tipo, p.titular ? `Titular: ${p.titular}` : null].filter(Boolean).join(' · '),
            formaPagoMoneda: [p.formaPago, p.moneda].filter(Boolean).join(' · '),
            textoAbrir: `Ver detalle de la póliza ${p.numero}`,
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

    // Dos letras del ramo para el cuadrito de la tabla (p. ej. «Gastos Médicos» → GM).
    iniciales(texto) {
        const palabras = String(texto).normalize('NFD').replace(/[̀-ͯ]/g, '').split(/[^A-Za-z0-9]+/)
            .filter((w) => w.length > 2 || /^[A-Z0-9]+$/.test(w));
        const letras = palabras.length > 1 ? palabras[0][0] + palabras[1][0] : (palabras[0] || 'P').substring(0, 2);
        return letras.toUpperCase();
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
