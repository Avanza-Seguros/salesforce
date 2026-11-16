// portalDashboard/portalDashboard.js
// Dashboard del cliente en el sitio Avanza Seguro: indicadores, pólizas por ramo y aseguradora, pagos de los próximos
// meses, próximos pagos y renovaciones. Usa los mismos permisos y la misma vista previa que «Mis pólizas».
import { LightningElement, api, wire } from 'lwc';
import basePath from '@salesforce/community/basePath';
import dashboard from '@salesforce/apex/PortalPolizasController.dashboard';
import puedeVistaPrevia from '@salesforce/apex/PortalPolizasController.puedeVistaPrevia';
import buscarCuentas from '@salesforce/apex/PortalPolizasController.buscarCuentas';

const DIAS_RENOVACION = 90;
const MAX_BARRAS = 6;

export default class PortalDashboard extends LightningElement {
    @api titulo = 'Dashboard';
    @api mensajeVacio = 'Aún no tienes pólizas registradas. Si crees que es un error, contacta a tu asesor.';

    datos;
    cargando = true;
    error;

    // Vista previa de administrador. null (no undefined) para que el wire sí se ejecute sin cuenta elegida.
    puedeVista = false;
    cuentaVistaPrevia = null;
    nombreVistaPrevia;
    textoCuenta = '';
    cuentasEncontradas = [];
    buscandoCuentas = false;
    errorCuentas;
    temporizadorBusqueda;

    @wire(puedeVistaPrevia)
    recibirPermiso({ data }) {
        this.puedeVista = data === true;
    }

    @wire(dashboard, { cuentaVistaPrevia: '$cuentaVistaPrevia' })
    recibirDashboard({ data, error }) {
        if (data) {
            this.datos = data;
            this.error = undefined;
            this.cargando = false;
        } else if (error) {
            this.datos = undefined;
            this.error = this.mensaje(error);
            this.cargando = false;
        }
    }

    // ---------- Estado de la pantalla ----------

    get esperandoCuenta() {
        return this.puedeVista && !this.cuentaVistaPrevia && this.sinPolizas;
    }
    get polizas() {
        return (this.datos && this.datos.polizas) || [];
    }
    get sinPolizas() {
        return this.polizas.length === 0;
    }
    get hayPolizas() {
        return !this.cargando && !this.error && !this.sinPolizas;
    }
    get vigentes() {
        return this.polizas.filter((p) => p.vigente);
    }
    get monedaPrincipal() {
        const cuenta = {};
        this.vigentes.forEach((p) => { cuenta[p.moneda || 'MXN'] = (cuenta[p.moneda || 'MXN'] || 0) + 1; });
        return Object.keys(cuenta).sort((a, b) => cuenta[b] - cuenta[a])[0] || 'MXN';
    }
    get fechaHoy() {
        return new Intl.DateTimeFormat('es-MX', { day: 'numeric', month: 'long', year: 'numeric' }).format(new Date());
    }
    get urlMisPolizas() {
        return `${basePath || ''}/mis-polizas`;
    }

    // ---------- Indicadores ----------

    get indicadores() {
        const d = this.datos || {};
        const mon = this.monedaPrincipal;
        const primas = {};
        this.vigentes.forEach((p) => {
            if (p.prima != null) { primas[p.moneda || 'MXN'] = (primas[p.moneda || 'MXN'] || 0) + p.prima; }
        });
        const otras = Object.keys(primas).filter((k) => k !== mon).map((k) => this.moneda(primas[k], k));
        const renovar = this.renovaciones.length;
        const vencido = d.totalVencido || 0;
        return [
            {
                clave: 'vigentes', etiqueta: 'Pólizas vigentes', valor: String(this.vigentes.length),
                detalle: `de ${this.polizas.length} en total`, clase: 'kpi kpi_acento', icono: 'utility:shield'
            },
            {
                clave: 'prima', etiqueta: 'Prima de pólizas vigentes', valor: this.moneda(primas[mon] || 0, mon),
                detalle: otras.length ? `más ${otras.join(' y ')}` : 'suma de sus primas', clase: 'kpi', icono: 'utility:moneybag'
            },
            {
                clave: 'pendiente', etiqueta: 'Por pagar', valor: this.moneda(d.totalPendiente || 0, mon),
                detalle: 'cuotas pendientes', clase: 'kpi', icono: 'utility:date_time'
            },
            {
                clave: 'vencido', etiqueta: 'Vencido', valor: this.moneda(vencido, mon),
                detalle: vencido > 0 ? `${d.cuotasVencidas} cuota${d.cuotasVencidas === 1 ? '' : 's'} vencida${d.cuotasVencidas === 1 ? '' : 's'}` : 'Estás al corriente',
                clase: vencido > 0 ? 'kpi kpi_alerta' : 'kpi kpi_ok', icono: vencido > 0 ? 'utility:warning' : 'utility:success'
            },
            {
                clave: 'renovar', etiqueta: 'Por renovar', valor: String(renovar),
                detalle: `en los próximos ${DIAS_RENOVACION} días`, clase: 'kpi', icono: 'utility:refresh'
            },
            {
                clave: 'pagado', etiqueta: 'Pagado en 12 meses', valor: this.moneda(d.pagadoUltimoAnio || 0, mon),
                detalle: 'pagos aplicados', clase: 'kpi', icono: 'utility:check'
            }
        ];
    }

    // ---------- Gráficas de barras (una sola serie: un solo tono) ----------

    barras(grupos, formato) {
        const lista = Object.keys(grupos).map((k) => ({ nombre: k, ...grupos[k] }))
            .sort((a, b) => b.valor - a.valor || a.nombre.localeCompare(b.nombre));
        let filas = lista.slice(0, MAX_BARRAS);
        if (lista.length > MAX_BARRAS) {
            const resto = lista.slice(MAX_BARRAS);
            filas.push({ nombre: 'Otros', valor: resto.reduce((s, x) => s + x.valor, 0),
                prima: resto.reduce((s, x) => s + (x.prima || 0), 0) });
        }
        const max = Math.max(1, ...filas.map((f) => f.valor));
        return filas.map((f) => {
            const texto = formato(f);
            return {
                ...f,
                texto,
                estilo: `width: ${Math.max(2, (f.valor / max) * 100)}%`,
                ayuda: `${f.nombre}: ${texto}`
            };
        });
    }

    get porRamo() {
        const g = {};
        const mon = this.monedaPrincipal;
        this.vigentes.forEach((p) => {
            const k = p.ramo || p.tipo || 'Sin ramo';
            g[k] = g[k] || { valor: 0, prima: 0 };
            g[k].valor++;
            if ((p.moneda || 'MXN') === mon && p.prima != null) { g[k].prima += p.prima; }
        });
        return this.barras(g, (f) => `${f.valor} · ${this.moneda(f.prima || 0, mon)}`);
    }
    get hayPorRamo() {
        return this.porRamo.length > 0;
    }

    get porAseguradora() {
        const g = {};
        this.vigentes.forEach((p) => {
            const k = p.aseguradora || 'Sin aseguradora';
            g[k] = g[k] || { valor: 0 };
            g[k].valor++;
        });
        return this.barras(g, (f) => `${f.valor} póliza${f.valor === 1 ? '' : 's'}`);
    }
    get hayPorAseguradora() {
        return this.porAseguradora.length > 0;
    }

    // Columnas de los próximos 6 meses.
    get meses() {
        const lista = (this.datos && this.datos.pagosPorMes) || [];
        const mon = this.monedaPrincipal;
        const max = Math.max(1, ...lista.map((m) => m.monto || 0));
        const fmtMes = new Intl.DateTimeFormat('es-MX', { month: 'short' });
        return lista.map((m) => {
            const [a, mm] = String(m.inicio).split('-').map(Number);
            const fecha = new Date(a, mm - 1, 1);
            const monto = m.monto || 0;
            const texto = this.moneda(monto, mon);
            const mesLargo = new Intl.DateTimeFormat('es-MX', { month: 'long', year: 'numeric' }).format(fecha);
            return {
                clave: m.inicio,
                mes: fmtMes.format(fecha).replace('.', ''),
                mesLargo,
                texto,
                cuotas: m.cuotas,
                vacio: monto === 0,
                estilo: `height: ${monto > 0 ? Math.max(4, (monto / max) * 100) : 0}%`,
                ayuda: `${mesLargo}: ${texto}${m.cuotas ? ` (${m.cuotas} cuota${m.cuotas === 1 ? '' : 's'})` : ''}`
            };
        });
    }
    get hayPagosProximos() {
        return this.meses.some((m) => !m.vacio);
    }

    // ---------- Listas ----------

    get proximasCuotas() {
        return ((this.datos && this.datos.proximasCuotas) || []).map((q) => ({
            ...q,
            venceTexto: this.fecha(q.vence),
            montoTexto: this.moneda(q.pendiente, q.moneda),
            estadoTexto: q.vencida ? (q.diasMora ? `Vencida · ${q.diasMora} día${q.diasMora === 1 ? '' : 's'}` : 'Vencida') : 'Pendiente',
            estadoClase: `estado ${q.vencida ? 'estado_vencido' : 'estado_pendiente'}`
        }));
    }
    get hayProximasCuotas() {
        return this.proximasCuotas.length > 0;
    }

    get renovaciones() {
        const hoy = new Date();
        hoy.setHours(0, 0, 0, 0);
        return this.vigentes
            .filter((p) => p.finVigencia)
            .map((p) => {
                const [a, m, d] = String(p.finVigencia).split('-').map(Number);
                const dias = Math.round((new Date(a, m - 1, d) - hoy) / 86400000);
                return { ...p, dias };
            })
            .filter((p) => p.dias >= 0 && p.dias <= DIAS_RENOVACION)
            .sort((x, y) => x.dias - y.dias)
            .map((p) => ({
                ...p,
                titulo: [p.ramo, p.aseguradora].filter(Boolean).join(' · ') || 'Póliza',
                venceTexto: this.fecha(p.finVigencia),
                diasTexto: p.dias === 0 ? 'Vence hoy' : `En ${p.dias} día${p.dias === 1 ? '' : 's'}`,
                diasClase: `estado ${p.dias <= 30 ? 'estado_pendiente' : 'estado_inactiva'}`
            }));
    }
    get hayRenovaciones() {
        return this.renovaciones.length > 0;
    }

    // ---------- Vista previa de administrador ----------

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
        this.cargando = true;
        this.datos = undefined;
        this.nombreVistaPrevia = nombre;
        this.cuentaVistaPrevia = id;
    }

    handleCambiarCuenta() {
        this.cargando = true;
        this.datos = undefined;
        this.nombreVistaPrevia = undefined;
        this.cuentaVistaPrevia = null;
        this.textoCuenta = '';
        this.cuentasEncontradas = [];
    }

    // ---------- Formatos ----------

    fecha(valor) {
        if (!valor) return '—';
        const [a, m, d] = String(valor).substring(0, 10).split('-').map(Number);
        return new Intl.DateTimeFormat('es-MX', { day: '2-digit', month: 'short', year: 'numeric' })
            .format(new Date(a, m - 1, d));
    }

    moneda(n, codigo) {
        try {
            return new Intl.NumberFormat('es-MX', { style: 'currency', currency: codigo || 'MXN', maximumFractionDigits: 0 })
                .format(n || 0);
        } catch (e) {
            return `${Number(n || 0).toLocaleString('es-MX', { maximumFractionDigits: 0 })} ${codigo || ''}`.trim();
        }
    }

    mensaje(error) {
        return (error && error.body && error.body.message) || 'Ocurrió un error al cargar la información.';
    }
}
