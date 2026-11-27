// portalInicio/portalInicio.js
// Página de Inicio del sitio Avanza Seguro (diseño Avanza Empresas): portada con saludo y tarjetas de vidrio, indicadores
// (pólizas vigentes, próximo pago, renovaciones y pagado en 12 meses), mis pólizas, movimientos, ejecutivo, accesos rápidos
// y lo que el portal hace por él. Usa el mismo Apex que el Dashboard.
import { LightningElement, api, wire } from 'lwc';
import basePath from '@salesforce/community/basePath';
import USER_ID from '@salesforce/user/Id';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import FIRST_NAME from '@salesforce/schema/User.FirstName';
import dashboard from '@salesforce/apex/PortalPolizasController.dashboard';
import pagos from '@salesforce/apex/PortalPolizasPestanas.pagos';
import ejecutivo from '@salesforce/apex/PortalSitioController.ejecutivo';

// El campo Moneda de la póliza es texto libre (MXN, PESOS, USD, UDI...): se lleva a un código ISO para darle formato con $.
const MONEDAS = { MXN: 'MXN', MXP: 'MXN', MN: 'MXN', PESOS: 'MXN', PESO: 'MXN', 'MONEDA NACIONAL': 'MXN',
    USD: 'USD', DLLS: 'USD', DLS: 'USD', DOLARES: 'USD', DOLAR: 'USD', EUR: 'EUR', EUROS: 'EUR' };
function codigoMoneda(codigo) {
    const clave = String(codigo || 'MXN').normalize('NFD').replace(/[̀-ͯ.]/g, '').trim().toUpperCase();
    return MONEDAS[clave] || (/^UDIS?$/.test(clave) ? 'UDI' : clave);
}

const DIAS_RENOVACION = 90;
const DURACION_CONTEO = 1100;
const MAX_POLIZAS = 4;
const MAX_MOVIMIENTOS = 5;

const FUNCIONES = [
    { clave: 'f1', icono: 'utility:clock', titulo: 'Disponible 24/7',
        texto: 'Consulta tus pólizas, documentos y coberturas a cualquier hora y desde cualquier dispositivo.' },
    { clave: 'f2', icono: 'utility:einstein', titulo: 'Lectura inteligente',
        texto: 'Leemos tus pólizas y endosos con inteligencia artificial para que tu información esté siempre al día.' },
    { clave: 'f3', icono: 'utility:lock', titulo: 'Información protegida',
        texto: 'Acceso cifrado y personal: solo tú y tu asesor ven los datos de tus seguros.' },
    { clave: 'f4', icono: 'utility:notification', titulo: 'Alertas a tiempo',
        texto: 'Ve de un vistazo qué pólizas están por renovarse.' },
    { clave: 'f5', icono: 'utility:download', titulo: 'Documentos digitales',
        texto: 'Descarga la carátula y los endosos sin esperar correos ni papeles.' },
    { clave: 'f6', icono: 'utility:chart', titulo: 'Tu historial completo',
        texto: 'Endosos, altas y bajas de asegurados, vehículos y ubicaciones en un solo lugar.' }
];

const PASOS = [
    { clave: 'p1', numero: '01', titulo: 'Entra a tu portal', texto: 'Con tu usuario, desde la computadora o el celular.' },
    { clave: 'p2', numero: '02', titulo: 'Revisa tus pólizas', texto: 'Coberturas, vigencias, asegurados y documentos al instante.' },
    { clave: 'p3', numero: '03', titulo: 'Mantente al corriente', texto: 'Renovaciones y movimientos siempre a la vista.' }
];

export default class PortalInicio extends LightningElement {
    @api titulo = 'Tus seguros, en un solo lugar';
    @api subtitulo = 'Consulta tus pólizas y documentos en tiempo real, con la tecnología de Avanza Seguro.';

    datos;
    cargando = true;
    progreso = 0;
    funciones = FUNCIONES;
    pasos = PASOS;
    animacion;
    polizaPago;
    plan;
    asesor;

    @wire(getRecord, { recordId: USER_ID, fields: [FIRST_NAME] })
    usuario;

    @wire(dashboard, { cuentaVistaPrevia: null })
    recibirDashboard({ data, error }) {
        if (data) {
            this.datos = data;
            this.cargando = false;
            const q = (data.proximasCuotas || [])[0];
            this.polizaPago = q ? q.polizaId : undefined;
            this.contar();
        } else if (error) {
            this.datos = undefined;
            this.cargando = false;
        }
    }

    // Cuotas de la póliza del próximo pago, para la barra de avance.
    @wire(pagos, { policyId: '$polizaPago', cuentaVistaPrevia: null })
    recibirPlan({ data, error }) {
        if (data) this.plan = data;
        else if (error) this.plan = undefined;
    }

    @wire(ejecutivo, { cuentaVistaPrevia: null })
    recibirEjecutivo({ data, error }) {
        if (data) this.asesor = data;
        else if (error) this.asesor = undefined;
    }

    disconnectedCallback() {
        if (this.animacion) cancelAnimationFrame(this.animacion);
    }

    // Los números del resumen suben de 0 a su valor (sin animación si el usuario pidió menos movimiento).
    contar() {
        const reducir = typeof window !== 'undefined' && window.matchMedia
            && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        if (reducir || typeof requestAnimationFrame === 'undefined') {
            this.progreso = 1;
            return;
        }
        const inicio = performance.now();
        const paso = (t) => {
            const x = Math.min(1, (t - inicio) / DURACION_CONTEO);
            this.progreso = 1 - Math.pow(1 - x, 3);
            if (x < 1) this.animacion = requestAnimationFrame(paso);
        };
        this.animacion = requestAnimationFrame(paso);
    }

    // ---------- Encabezado ----------

    get saludo() {
        const h = new Date().getHours();
        const parte = h < 12 ? 'Buenos días' : h < 19 ? 'Buenas tardes' : 'Buenas noches';
        const nombre = this.usuario && this.usuario.data ? getFieldValue(this.usuario.data, FIRST_NAME) : null;
        return nombre ? `${parte}, ${nombre}` : parte;
    }
    // Título de la portada como primera frase del párrafo (con punto final si no lo trae).
    get tituloTexto() {
        const t = String(this.titulo || '').trim();
        return t && !/[.!?…]$/.test(t) ? `${t}.` : t;
    }
    get urlMisPolizas() {
        return `${basePath || ''}/mis-polizas`;
    }
    get urlDashboard() {
        return `${basePath || ''}/mi-dashboard`;
    }

    // ---------- Resumen del cliente ----------

    get polizas() {
        return (this.datos && this.datos.polizas) || [];
    }
    get vigentes() {
        return this.polizas.filter((p) => p.vigente);
    }
    get hayPolizas() {
        return this.polizas.length > 0;
    }
    get numVigentes() {
        return Math.round(this.vigentes.length * this.progreso);
    }
    get renovacionesProximas() {
        const hoy = new Date();
        hoy.setHours(0, 0, 0, 0);
        return this.vigentes.filter((p) => {
            if (!p.finVigencia) return false;
            const dias = Math.round((this.aFecha(p.finVigencia) - hoy) / 86400000);
            return dias >= 0 && dias <= DIAS_RENOVACION;
        }).length;
    }

    get proximaCuota() {
        const lista = (this.datos && this.datos.proximasCuotas) || [];
        return lista.length ? lista[0] : null;
    }

    get textoTotalPolizas() {
        return this.polizas.length ? `de ${this.polizas.length} en total` : this.cargando ? 'Cargando…' : 'Aún sin pólizas';
    }

    // Tarjeta ancha de la portada: personas aseguradas; si las pólizas no cubren personas, vehículos o ubicaciones
    // (conteo real de bienes asegurados que ya calcula el Dashboard).
    get asegurados() {
        const b = (this.datos && this.datos.bienes) || {};
        const opciones = [
            { n: b.personas, etiqueta: 'Asegurados', uno: 'persona cubierta', varios: 'personas cubiertas' },
            { n: b.vehiculos, etiqueta: 'Vehículos asegurados', uno: 'vehículo cubierto', varios: 'vehículos cubiertos' },
            { n: b.ubicaciones, etiqueta: 'Ubicaciones aseguradas', uno: 'ubicación cubierta', varios: 'ubicaciones cubiertas' }
        ];
        const o = opciones.find((x) => x.n > 0) || opciones[0];
        const n = o.n || 0;
        return {
            etiqueta: o.etiqueta,
            valor: Math.round(n * this.progreso).toLocaleString('es-MX'),
            detalle: `${n === 1 ? o.uno : o.varios} en tus pólizas`
        };
    }

    // Indicadores bajo la portada (punto de color y barra), todos con datos reales del Dashboard.
    get etapas() {
        const d = this.datos || {};
        const q = this.proximaCuota;
        const ren = this.renovacionesProximas;
        const total = this.polizas.length;
        const nVig = this.vigentes.length;
        const pagado = d.pagadoUltimoAnio || 0;
        const pendiente = d.totalPendiente || 0;
        const pctPagado = pagado + pendiente > 0 ? (pagado / (pagado + pendiente)) * 100 : 0;
        const plan = this.pago;
        const pctPlan = plan && plan.hayAvance ? plan.pct : q ? 100 : 0;
        return [
            {
                clave: 'vigentes', etiqueta: 'Pólizas vigentes', color: '#1d4ed8',
                valor: String(this.numVigentes), detalle: this.textoTotalPolizas,
                pct: total ? (nVig / total) * 100 : 0
            },
            {
                clave: 'pago', etiqueta: q && q.vencida ? 'Pago vencido' : 'Próximo pago', color: q && q.vencida ? '#b42318' : '#7c3aed',
                valor: q ? this.fecha(q.vence, true) : 'Al corriente',
                detalle: q ? `Póliza ${q.numero} · ${this.moneda(q.pendiente, q.moneda, 2)}` : 'No tienes pagos pendientes',
                pct: pctPlan
            },
            {
                clave: 'renovar', etiqueta: 'Por renovar', color: '#15803d',
                valor: String(Math.round(ren * this.progreso)), detalle: `en los próximos ${DIAS_RENOVACION} días`,
                pct: nVig ? (ren / nVig) * 100 : 0
            },
            {
                clave: 'pagado', etiqueta: 'Pagado en 12 meses', color: '#b45309',
                valor: this.moneda(pagado * this.progreso, this.monedaPrincipal), detalle: 'pagos aplicados',
                pct: pctPagado
            }
        ].map((x) => ({
            ...x,
            estiloPunto: `background: ${x.color}`,
            estiloBarra: `width: ${Math.round(Math.min(100, x.pct) * this.progreso)}%; background: ${x.color}`
        })).filter((x) => this.conPagos || (x.clave !== 'pago' && x.clave !== 'pagado'));
    }

    // Liberación sin Cobranza: el Dashboard manda conPagos en false y no se muestra nada de pagos.
    get conPagos() {
        return !!(this.datos && this.datos.conPagos);
    }

    get monedaPrincipal() {
        const cuenta = {};
        this.vigentes.forEach((p) => { const m = codigoMoneda(p.moneda); cuenta[m] = (cuenta[m] || 0) + 1; });
        return Object.keys(cuenta).sort((a, b) => cuenta[b] - cuenta[a])[0] || 'MXN';
    }

    // ---------- Mis pólizas (tarjetas) ----------

    get tarjetasPolizas() {
        const hoy = new Date();
        hoy.setHours(0, 0, 0, 0);
        return [...this.vigentes]
            .sort((a, b) => String(a.finVigencia || '9999').localeCompare(String(b.finVigencia || '9999')))
            .slice(0, MAX_POLIZAS)
            .map((p) => {
                const dias = p.finVigencia ? Math.round((this.aFecha(p.finVigencia) - hoy) / 86400000) : null;
                const renovar = dias !== null && dias >= 0 && dias <= DIAS_RENOVACION;
                return {
                    id: p.id,
                    ramo: p.ramo || p.tipo || 'Póliza',
                    numero: `Póliza ${p.numero}`,
                    aseguradora: p.aseguradora || '',
                    bien: p.bienAsegurado || p.descripcion || '',
                    vigencia: `Vigente hasta ${this.fecha(p.finVigencia, true)}`,
                    chip: renovar ? `Renueva en ${dias} día${dias === 1 ? '' : 's'}` : 'Vigente',
                    chipClase: `badge ${renovar ? 'b-amber' : 'b-green'}`,
                    url: `${basePath || ''}/mis-polizas?poliza=${p.id}`
                };
            });
    }
    get hayTarjetas() {
        return this.tarjetasPolizas.length > 0;
    }
    get masPolizas() {
        const resto = this.vigentes.length - MAX_POLIZAS;
        return resto > 0 ? `Ver ${resto} póliza${resto === 1 ? '' : 's'} más` : 'Ver todas mis pólizas';
    }

    // ---------- Próximo pago (tarjeta con avance) ----------

    get pago() {
        const q = this.proximaCuota;
        if (!q) return null;
        const p = this.plan || null;
        const total = (p && p.totalImporte) || 0;
        const pct = total ? Math.min(100, Math.round(((p.totalPagado || 0) / total) * 100)) : 0;
        return {
            titulo: q.vencida ? 'Pago vencido' : 'Próximo pago',
            monto: this.moneda(q.pendiente, q.moneda, 2),
            detalle: `Póliza ${q.numero}${q.ramo ? ` · ${q.ramo}` : ''}`,
            vence: `${q.vencida ? 'Venció' : 'Vence'} el ${this.fecha(q.vence, true)}`,
            clase: `pago${q.vencida ? ' pago_vencido' : ''}`,
            hayAvance: !!p && total > 0,
            pagado: p ? this.moneda(p.totalPagado, p.moneda) : '',
            pendiente: p ? this.moneda(p.totalPendiente, p.moneda) : '',
            pct,
            pctTexto: `${pct}% de la póliza pagado`,
            estilo: `width: ${Math.max(pct, 2)}%`
        };
    }
    get urlPagos() {
        return `${basePath || ''}/mis-pagos`;
    }

    // ---------- Movimientos recientes ----------

    get movimientos() {
        const iconos = { Alta: 'utility:add', Baja: 'utility:dash', Cambio: 'utility:edit' };
        return ((this.datos && this.datos.movimientos) || []).slice(0, MAX_MOVIMIENTOS).map((m) => ({
            id: m.id,
            icono: iconos[m.tipo] || 'utility:change_record_type',
            iconoClase: `chip mov_${String(m.tipo || 'otro').toLowerCase()}`,
            titulo: `${m.tipo || 'Movimiento'} · ${m.nombre || 'Sin nombre'}`,
            meta: [`Póliza ${m.poliza || ''}`.trim(), m.endoso ? `endoso ${m.endoso}` : null].filter(Boolean).join(' · '),
            fecha: this.fecha(m.fecha)
        }));
    }
    get hayMovimientos() {
        return this.movimientos.length > 0;
    }

    // ---------- Ejecutivo ----------

    get ejecutivoInfo() {
        const e = this.asesor;
        if (!e) return null;
        const partes = String(e.nombre || '').trim().split(/\s+/);
        return {
            ...e,
            iniciales: ((partes[0] || '').charAt(0) + (partes.length > 1 ? partes[partes.length - 1].charAt(0) : '')).toUpperCase(),
            puestoTexto: e.puesto || 'Ejecutivo de cuenta',
            mailto: e.correo ? `mailto:${e.correo}` : null,
            tel: e.telefono ? `tel:${String(e.telefono).replace(/[^\d+]/g, '')}` : null
        };
    }

    // ---------- Accesos rápidos ----------

    get accesos() {
        return [
            { clave: 'a1', icono: 'utility:description', titulo: 'Mis pólizas', url: this.urlMisPolizas,
                texto: 'Coberturas, vigencias, asegurados y documentos de cada póliza.' },
            { clave: 'a2', icono: 'utility:moneybag', titulo: 'Pagos y recibos', url: this.urlPagos,
                texto: 'Próximo pago, cuotas por póliza y recibos ya aplicados.' },
            { clave: 'a3', icono: 'utility:groups', titulo: 'Personas de tu empresa', url: `${basePath || ''}/contactos-empresa`,
                texto: 'Colaboradores, su cobertura y cómo contactarlos.' },
            { clave: 'a4', icono: 'utility:metrics', titulo: 'Dashboard', url: this.urlDashboard,
                texto: 'Indicadores, endosos y movimientos de un vistazo.' }
        ].filter((a) => this.conPagos || a.clave !== 'a2');
    }

    // ---------- Formatos ----------

    aFecha(valor) {
        const [a, m, d] = String(valor).substring(0, 10).split('-').map(Number);
        return new Date(a, m - 1, d);
    }

    fecha(valor, conAnio) {
        if (!valor) return '—';
        const opciones = conAnio ? { day: 'numeric', month: 'short', year: 'numeric' } : { day: 'numeric', month: 'short' };
        return new Intl.DateTimeFormat('es-MX', opciones).format(this.aFecha(valor));
    }

    moneda(n, codigo, decimales = 0) {
        const iso = codigoMoneda(codigo);
        const opciones = { minimumFractionDigits: decimales, maximumFractionDigits: decimales };
        if (iso === 'UDI') {
            return `${Number(n || 0).toLocaleString('es-MX', opciones)} UDIS`;
        }
        try {
            return new Intl.NumberFormat('es-MX', { style: 'currency', currency: iso, ...opciones }).format(n || 0);
        } catch (e) {
            return `$${Number(n || 0).toLocaleString('es-MX', opciones)}`;
        }
    }
}
