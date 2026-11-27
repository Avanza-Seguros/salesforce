// portalDashboard/portalDashboard.js
// Dashboard del cliente en el sitio Avanza Seguro: indicadores, pólizas por ramo y aseguradora, pagos de los próximos
// meses, próximos pagos y renovaciones. Usa los mismos permisos y la misma vista previa que «Mis pólizas».
import { LightningElement, api, wire } from 'lwc';
import basePath from '@salesforce/community/basePath';
import dashboard from '@salesforce/apex/PortalPolizasController.dashboard';
import puedeVistaPrevia from '@salesforce/apex/PortalPolizasController.puedeVistaPrevia';
import buscarCuentas from '@salesforce/apex/PortalPolizasController.buscarCuentas';

// El campo Moneda de la póliza es texto libre (MXN, PESOS, USD, UDI...): se lleva a un código ISO para darle formato con $.
const MONEDAS = { MXN: 'MXN', MXP: 'MXN', MN: 'MXN', PESOS: 'MXN', PESO: 'MXN', 'MONEDA NACIONAL': 'MXN',
    USD: 'USD', DLLS: 'USD', DLS: 'USD', DOLARES: 'USD', DOLAR: 'USD', EUR: 'EUR', EUROS: 'EUR' };
function codigoMoneda(codigo) {
    const clave = String(codigo || 'MXN').normalize('NFD').replace(/[\u0300-\u036f.]/g, '').trim().toUpperCase();
    return MONEDAS[clave] || (/^UDIS?$/.test(clave) ? 'UDI' : clave);
}

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
        this.vigentes.forEach((p) => { const m = codigoMoneda(p.moneda); cuenta[m] = (cuenta[m] || 0) + 1; });
        return Object.keys(cuenta).sort((a, b) => cuenta[b] - cuenta[a])[0] || 'MXN';
    }
    get fechaHoy() {
        return new Intl.DateTimeFormat('es-MX', { day: 'numeric', month: 'long', year: 'numeric' }).format(new Date());
    }
    get urlMisPolizas() {
        return `${basePath || ''}/mis-polizas`;
    }
    // Liga al detalle de una póliza en «Mis pólizas» (?poliza= y, si se da, ?pestana=).
    urlPoliza(id, pestana) {
        if (!id) return null;
        return `${this.urlMisPolizas}?poliza=${encodeURIComponent(id)}${pestana ? `&pestana=${pestana}` : ''}`;
    }

    // ---------- Indicadores ----------

    get indicadores() {
        const d = this.datos || {};
        const mon = this.monedaPrincipal;
        const primas = {};
        this.vigentes.forEach((p) => {
            if (p.prima != null) { primas[codigoMoneda(p.moneda)] = (primas[codigoMoneda(p.moneda)] || 0) + p.prima; }
        });
        const otras = Object.keys(primas).filter((k) => k !== mon).map((k) => this.moneda(primas[k], k));
        const renovar = this.renovaciones.length;
        const vencido = d.totalVencido || 0;
        const pendiente = d.totalPendiente || 0;
        const pagado = d.pagadoUltimoAnio || 0;
        // Barra de cada etapa: proporción calculada con los mismos datos (nunca una cifra inventada).
        const pct = (parte, total) => (total > 0 ? Math.min(100, Math.round((parte / total) * 100)) : 0);
        return [
            {
                clave: 'vigentes', etiqueta: 'Pólizas vigentes', valor: String(this.vigentes.length),
                detalle: `de ${this.polizas.length} en total`
            },
            {
                clave: 'prima', etiqueta: 'Prima de pólizas vigentes', valor: this.moneda(primas[mon] || 0, mon),
                detalle: otras.length ? `más ${otras.join(' y ')}` : 'suma de sus primas'
            },
            {
                clave: 'pendiente', etiqueta: 'Por pagar', valor: this.moneda(pendiente, mon),
                detalle: 'cuotas pendientes', color: '#7c3aed', avance: pct(pendiente, pendiente + pagado)
            },
            {
                clave: 'vencido', etiqueta: 'Vencido', valor: this.moneda(vencido, mon),
                detalle: vencido > 0 ? `${d.cuotasVencidas} cuota${d.cuotasVencidas === 1 ? '' : 's'} vencida${d.cuotasVencidas === 1 ? '' : 's'}` : 'Estás al corriente',
                color: vencido > 0 ? '#b42318' : '#15803d', avance: pct(vencido, pendiente)
            },
            {
                clave: 'renovar', etiqueta: 'Por renovar', valor: String(renovar),
                detalle: `en los próximos ${DIAS_RENOVACION} días`, color: '#1d4ed8', avance: pct(renovar, this.vigentes.length)
            },
            {
                clave: 'pagado', etiqueta: 'Pagado en 12 meses', valor: this.moneda(pagado, mon),
                detalle: 'pagos aplicados', color: '#b45309', avance: pct(pagado, pendiente + pagado)
            }
        ];
    }
    // Banda azul: pólizas vigentes y prima.
    get indicadoresHero() {
        return this.indicadores.slice(0, 2);
    }
    // Fila de etapas: por pagar, vencido, por renovar y pagado en 12 meses.
    get etapas() {
        return this.indicadores.slice(2).map((k) => ({
            ...k,
            estiloPunto: `background: ${k.color}`,
            estiloBarra: `width: ${k.avance}%; background: ${k.color}`
        }));
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
            if (codigoMoneda(p.moneda) === mon && p.prima != null) { g[k].prima += p.prima; }
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

    // Columnas por mes (próximos 6 meses o historial de 12).
    columnas(lista) {
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

    get meses() {
        return this.columnas((this.datos && this.datos.pagosPorMes) || []);
    }

    // Historial: lo pagado en cada uno de los últimos 12 meses.
    get historial() {
        return this.columnas((this.datos && this.datos.pagadoPorMes) || []);
    }
    get hayHistorial() {
        return this.historial.some((m) => !m.vacio);
    }
    get totalHistorial() {
        const lista = (this.datos && this.datos.pagadoPorMes) || [];
        return this.moneda(lista.reduce((s, m) => s + (m.monto || 0), 0), this.monedaPrincipal);
    }

    // ---------- Bienes asegurados ----------

    get bienes() {
        const b = (this.datos && this.datos.bienes) || {};
        const uno = (n, singular, plural) => `${n === 1 ? singular : plural}`;
        return [
            { clave: 'personas', icono: 'utility:groups', valor: b.personas || 0,
                etiqueta: uno(b.personas, 'Persona asegurada', 'Personas aseguradas') },
            { clave: 'vehiculos', icono: 'utility:travel_and_places', valor: b.vehiculos || 0,
                etiqueta: uno(b.vehiculos, 'Vehículo asegurado', 'Vehículos asegurados') },
            { clave: 'ubicaciones', icono: 'utility:location', valor: b.ubicaciones || 0,
                etiqueta: uno(b.ubicaciones, 'Ubicación asegurada', 'Ubicaciones aseguradas') }
        ].map((x) => ({
            ...x,
            esPersonas: x.clave === 'personas',
            esVehiculos: x.clave === 'vehiculos',
            esUbicaciones: x.clave === 'ubicaciones',
            claseIcono: `ico${x.valor ? '' : ' ico_cero'}`
        }));
    }

    // ---------- Endosos y movimientos ----------

    get endosos() {
        return ((this.datos && this.datos.endosos) || []).map((e) => ({
            ...e,
            titulo: `Endoso ${e.numero || 's/n'}`,
            meta: [`Póliza ${e.poliza || ''}`.trim(), e.descripcion, this.fecha(e.fecha)].filter(Boolean).join(' · '),
            totalTexto: e.total == null ? '' : this.moneda(e.total, e.moneda),
            totalClase: `money${e.total < 0 ? ' money_negativo' : ''}`
        }));
    }
    get hayEndosos() {
        return this.endosos.length > 0;
    }

    get movimientos() {
        const clases = { Alta: 'badge b-green', Baja: 'badge b-red', Cambio: 'badge b-amber' };
        return ((this.datos && this.datos.movimientos) || []).map((m) => ({
            ...m,
            iniciales: String(m.nombre || '').trim().split(/\s+/).filter(Boolean).slice(0, 2)
                .map((p) => p.charAt(0).toUpperCase()).join('') || '·',
            meta: [`Póliza ${m.poliza || ''}`.trim(), m.endoso ? `endoso ${m.endoso}` : null, this.fecha(m.fecha)]
                .filter(Boolean).join(' · '),
            tipoClase: clases[m.tipo] || 'badge b-gray'
        }));
    }
    get hayMovimientos() {
        return this.movimientos.length > 0;
    }
    get resumenMovimientos() {
        const a = (this.datos && this.datos.movimientosAnio) || {};
        return [
            { clave: 'Alta', texto: `${a.Alta || 0} alta${a.Alta === 1 ? '' : 's'}`, clase: 'badge b-green' },
            { clave: 'Baja', texto: `${a.Baja || 0} baja${a.Baja === 1 ? '' : 's'}`, clase: 'badge b-red' },
            { clave: 'Cambio', texto: `${a.Cambio || 0} cambio${a.Cambio === 1 ? '' : 's'}`, clase: 'badge b-amber' }
        ];
    }
    // Altas, bajas y cambios de cada uno de los últimos 12 meses (tres barras por mes, misma escala).
    get movimientosMes() {
        const lista = (this.datos && this.datos.movimientosPorMes) || [];
        const max = Math.max(1, ...lista.map((m) => Math.max(m.altas || 0, m.bajas || 0, m.cambios || 0)));
        const alto = (n) => `height: ${n > 0 ? Math.max(4, (n / max) * 100) : 0}%`;
        return lista.map((m) => {
            const f = this.mesDe(m.inicio);
            const a = m.altas || 0;
            const b = m.bajas || 0;
            const c = m.cambios || 0;
            return {
                clave: m.inicio, mes: f.corto, mesLargo: f.largo, altas: a, bajas: b, cambios: c,
                estiloAltas: alto(a), estiloBajas: alto(b), estiloCambios: alto(c),
                ayuda: `${f.largo}: ${a} alta${a === 1 ? '' : 's'}, ${b} baja${b === 1 ? '' : 's'}, ${c} cambio${c === 1 ? '' : 's'}`
            };
        });
    }
    get hayMovimientosMes() {
        return this.movimientosMes.some((m) => m.altas || m.bajas || m.cambios);
    }

    // Prima de los endosos por mes (en la moneda principal): lo cobrado y lo devuelto.
    get primasMes() {
        const mon = this.monedaPrincipal;
        const porMes = new Map(((this.datos && this.datos.movimientosPorMes) || [])
            .map((m) => [m.inicio, { cargos: 0, devoluciones: 0, endosos: 0 }]));
        ((this.datos && this.datos.primasPorMes) || []).forEach((p) => {
            if (codigoMoneda(p.moneda) !== mon || !porMes.has(p.inicio)) { return; }
            const x = porMes.get(p.inicio);
            x.cargos += p.cargos || 0;
            x.devoluciones += p.devoluciones || 0;
            x.endosos += p.endosos || 0;
        });
        const max = Math.max(1, ...[...porMes.values()].map((x) => Math.max(x.cargos, x.devoluciones)));
        const alto = (n) => `height: ${n > 0 ? Math.max(4, (n / max) * 100) : 0}%`;
        return [...porMes.entries()].map(([inicio, x]) => {
            const f = this.mesDe(inicio);
            const cobrado = this.moneda(x.cargos, mon);
            const devuelto = this.moneda(x.devoluciones, mon);
            const neto = this.moneda(x.cargos - x.devoluciones, mon);
            return {
                clave: inicio, mes: f.corto, mesLargo: f.largo, cobrado, devuelto, neto, endosos: x.endosos,
                estiloCargos: alto(x.cargos), estiloDevoluciones: alto(x.devoluciones),
                vacio: !x.cargos && !x.devoluciones,
                ayuda: `${f.largo}: cobrado ${cobrado}, devuelto ${devuelto}, neto ${neto}`
            };
        });
    }
    get hayPrimasMes() {
        return this.primasMes.some((m) => !m.vacio);
    }
    get resumenPrimas() {
        const mon = this.monedaPrincipal;
        let c = 0;
        let d = 0;
        ((this.datos && this.datos.primasPorMes) || []).forEach((p) => {
            if (codigoMoneda(p.moneda) === mon) { c += p.cargos || 0; d += p.devoluciones || 0; }
        });
        return [
            { clave: 'cobrado', texto: `Cobrado ${this.moneda(c, mon)}`, clase: 'badge b-blue' },
            { clave: 'devuelto', texto: `Devuelto ${this.moneda(d, mon)}`, clase: 'badge b-red' },
            { clave: 'neto', texto: `Neto ${this.moneda(c - d, mon)}`, clase: 'badge b-gray' }
        ];
    }
    mesDe(inicio) {
        const [a, mm] = String(inicio).split('-').map(Number);
        const fecha = new Date(a, mm - 1, 1);
        return {
            corto: new Intl.DateTimeFormat('es-MX', { month: 'short' }).format(fecha).replace('.', ''),
            largo: new Intl.DateTimeFormat('es-MX', { month: 'long', year: 'numeric' }).format(fecha)
        };
    }

    get hayPagosProximos() {
        return this.meses.some((m) => !m.vacio);
    }

    // ---------- Listas ----------

    get proximasCuotas() {
        return ((this.datos && this.datos.proximasCuotas) || []).map((q) => ({
            ...q,
            // El número abre la póliza en «Mis pólizas», en su pestaña de pagos.
            urlDetalle: this.urlPoliza(q.polizaId, 'pagos'),
            textoDetalle: `Ver detalle de la póliza ${q.numero}`,
            venceTexto: this.fecha(q.vence),
            montoTexto: this.moneda(q.pendiente, q.moneda),
            estadoTexto: q.vencida ? (q.diasMora ? `Vencida · ${q.diasMora} día${q.diasMora === 1 ? '' : 's'}` : 'Vencida') : 'Pendiente',
            estadoClase: `badge ${q.vencida ? 'b-red' : 'b-amber'}`
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
                urlDetalle: this.urlPoliza(p.id),
                textoDetalle: `Ver detalle de la póliza ${p.numero}`,
                venceTexto: this.fecha(p.finVigencia),
                diasTexto: p.dias === 0 ? 'Vence hoy' : `En ${p.dias} día${p.dias === 1 ? '' : 's'}`,
                diasClase: `badge ${p.dias <= 30 ? 'b-amber' : 'b-blue'}`
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
        const iso = codigoMoneda(codigo);
        if (iso === 'UDI') {
            return `${Number(n || 0).toLocaleString('es-MX', { maximumFractionDigits: 0 })} UDIS`;
        }
        try {
            return new Intl.NumberFormat('es-MX', { style: 'currency', currency: iso, maximumFractionDigits: 0 })
                .format(n || 0);
        } catch (e) {
            return `$${Number(n || 0).toLocaleString('es-MX', { maximumFractionDigits: 0 })}`;
        }
    }

    mensaje(error) {
        return (error && error.body && error.body.message) || 'Ocurrió un error al cargar la información.';
    }
}
