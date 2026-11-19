// portalPagos/portalPagos.js
// Página «Pagos» del sitio: resumen de lo pendiente, vencido y pagado; el próximo pago destacado con el avance de su
// póliza; las cuotas de cada póliza (se elige con los botones de pólizas) y los recibos pagados.
import { LightningElement, api, wire } from 'lwc';
import basePath from '@salesforce/community/basePath';
import dashboard from '@salesforce/apex/PortalPolizasController.dashboard';
import pagos from '@salesforce/apex/PortalPolizasPestanas.pagos';
import puedeVistaPrevia from '@salesforce/apex/PortalPolizasController.puedeVistaPrevia';

const MONEDAS = { MXN: 'MXN', MXP: 'MXN', MN: 'MXN', PESOS: 'MXN', PESO: 'MXN', 'MONEDA NACIONAL': 'MXN',
    USD: 'USD', DLLS: 'USD', DLS: 'USD', DOLARES: 'USD', DOLAR: 'USD', EUR: 'EUR', EUROS: 'EUR' };
function codigoMoneda(codigo) {
    const clave = String(codigo || 'MXN').normalize('NFD').replace(/[̀-ͯ.]/g, '').trim().toUpperCase();
    return MONEDAS[clave] || (/^UDIS?$/.test(clave) ? 'UDI' : clave);
}

export default class PortalPagos extends LightningElement {
    @api titulo = 'Pagos y recibos';
    @api subtitulo = 'Lo que llevas pagado, lo pendiente y cada cuota de tus pólizas.';

    datos;
    cargando = true;
    error;
    cuentaVistaPrevia = null;
    polizaId;
    plan;
    cargandoPlan = false;
    errorPlan;

    puede = false;
    @wire(puedeVistaPrevia)
    recibirPermiso({ data }) {
        this.puede = data === true;
    }

    @wire(dashboard, { cuentaVistaPrevia: '$cuentaVistaPrevia' })
    recibir({ data, error }) {
        if (data) {
            this.datos = data;
            this.error = undefined;
            this.cargando = false;
            if (!this.polizaId || !this.polizas.some((p) => p.id === this.polizaId)) {
                const q = (data.proximasCuotas || [])[0];
                const primera = this.polizasOrdenadas[0];
                this.elegir((q && q.polizaId) || (primera && primera.id));
            }
        } else if (error) {
            this.error = (error.body && error.body.message) || 'No se pudo cargar la información.';
            this.cargando = false;
        }
    }

    @wire(pagos, { policyId: '$polizaId', cuentaVistaPrevia: '$cuentaVistaPrevia' })
    recibirPlan({ data, error }) {
        if (!this.polizaId) return;
        if (data) {
            this.plan = data;
            this.errorPlan = undefined;
            this.cargandoPlan = false;
        } else if (error) {
            this.plan = undefined;
            this.errorPlan = (error.body && error.body.message) || 'No se pudieron cargar las cuotas.';
            this.cargandoPlan = false;
        }
    }

    elegir(id) {
        if (!id || id === this.polizaId) return;
        this.plan = undefined;
        this.errorPlan = undefined;
        this.cargandoPlan = true;
        this.polizaId = id;
    }

    handleVistaPrevia(event) {
        this.cargando = true;
        this.datos = undefined;
        this.plan = undefined;
        this.polizaId = undefined;
        this.cuentaVistaPrevia = event.detail.id || null;
    }

    handlePoliza(event) {
        this.elegir(event.currentTarget.dataset.id);
    }

    // ---------- Estado ----------

    get polizas() {
        return (this.datos && this.datos.polizas) || [];
    }
    get polizasOrdenadas() {
        return [...this.polizas].sort((a, b) => (b.vigente === true) - (a.vigente === true));
    }
    get hayPolizas() {
        return !this.cargando && !this.error && this.polizas.length > 0;
    }
    get sinPolizas() {
        return !this.cargando && !this.error && this.polizas.length === 0;
    }
    get mensajeVacio() {
        return this.puede && !this.cuentaVistaPrevia
            ? 'Elige arriba la cuenta del cliente (vista previa de administrador) para ver sus pagos.'
            : 'Aún no tienes pólizas registradas. Si crees que es un error, contacta a tu ejecutivo.';
    }
    get monedaPrincipal() {
        const cuenta = {};
        this.polizas.filter((p) => p.vigente).forEach((p) => { const m = codigoMoneda(p.moneda); cuenta[m] = (cuenta[m] || 0) + 1; });
        return Object.keys(cuenta).sort((a, b) => cuenta[b] - cuenta[a])[0] || 'MXN';
    }
    get seleccionada() {
        return this.polizas.find((p) => p.id === this.polizaId);
    }

    // ---------- Resumen ----------

    get resumen() {
        const d = this.datos || {};
        const mon = this.monedaPrincipal;
        const vencidas = d.cuotasVencidas || 0;
        return [
            { clave: 'pendiente', etiqueta: 'Por pagar', valor: this.moneda(d.totalPendiente, mon), detalle: 'cuotas pendientes', clase: 'glass' },
            { clave: 'vencido', etiqueta: 'Vencido', valor: this.moneda(d.totalVencido, mon),
                detalle: vencidas ? `${vencidas} cuota${vencidas === 1 ? '' : 's'} vencida${vencidas === 1 ? '' : 's'}` : 'Estás al corriente',
                clase: `glass${vencidas ? ' glass_alerta' : ''}` },
            { clave: 'pagado', etiqueta: 'Pagado en 12 meses', valor: this.moneda(d.pagadoUltimoAnio, mon), detalle: 'pagos aplicados', clase: 'glass wide' }
        ];
    }

    get proximo() {
        const q = ((this.datos && this.datos.proximasCuotas) || [])[0];
        if (!q) return null;
        return {
            ...q,
            etiqueta: `${q.vencida ? 'Pago vencido' : 'Próximo pago'} · Póliza ${q.numero}`,
            monto: this.moneda(q.pendiente, q.moneda, 2),
            venceTexto: this.fecha(q.vence),
            verbo: q.vencida ? 'venció el' : 'vence el',
            estadoTexto: q.vencida ? (q.diasMora ? `Vencido · ${q.diasMora} días` : 'Vencido') : 'Pendiente',
            estadoClase: `badge ${q.vencida ? 'b-red' : 'b-amber'}`,
            esSeleccionada: q.polizaId === this.polizaId
        };
    }

    // ---------- Pólizas y plan ----------

    get botonesPolizas() {
        return this.polizasOrdenadas.map((p) => ({
            id: p.id,
            texto: `${p.numero}${p.ramo ? ` · ${p.ramo}` : ''}`,
            detalle: p.vigente ? 'Vigente' : (p.estado || 'No vigente'),
            clase: p.id === this.polizaId ? 'on' : '',
            claseDetalle: `badge ${p.vigente ? 'b-green' : 'b-gray'}`,
            presionado: String(p.id === this.polizaId)
        }));
    }

    get hayPlan() {
        return !this.cargandoPlan && !this.errorPlan && this.plan && (this.plan.cuotas || []).length > 0;
    }
    get sinCuotas() {
        return !this.cargandoPlan && !this.errorPlan && this.plan && (this.plan.cuotas || []).length === 0;
    }
    get monedaPlan() {
        return (this.plan && this.plan.moneda) || 'MXN';
    }
    get cuotas() {
        const forma = (this.seleccionada && this.seleccionada.formaPago) || '';
        return ((this.plan && this.plan.cuotas) || []).map((c, i) => ({
            ...c,
            numeroChip: (String(c.etiqueta || '').match(/\d+/) || [String(i + 1)])[0],
            formaPago: forma,
            venceTexto: this.fecha(c.vence),
            pagoTexto: c.fechaPago ? this.fecha(c.fechaPago) : '—',
            importeTexto: this.moneda(c.importe, this.monedaPlan, 2),
            pagadoTexto: this.moneda(c.pagado, this.monedaPlan, 2),
            pendienteTexto: this.moneda(c.pendiente, this.monedaPlan, 2),
            reciboTexto: c.recibo || '—',
            estadoClase: `badge ${this.claseEstado(c.estado, c.diasMora)}`,
            estadoTexto: c.estado || '—'
        }));
    }
    get totales() {
        const p = this.plan || {};
        const mon = this.monedaPlan;
        return {
            importe: this.moneda(p.totalImporte, mon, 2),
            pagado: this.moneda(p.totalPagado, mon, 2),
            pendiente: this.moneda(p.totalPendiente, mon, 2)
        };
    }
    get avance() {
        const p = this.plan || {};
        const total = p.totalImporte || 0;
        const pct = total ? Math.min(100, Math.round(((p.totalPagado || 0) / total) * 100)) : 0;
        return { pct, texto: `${pct}% pagado`, estilo: `width: ${Math.max(pct, 2)}%` };
    }
    get tituloPlan() {
        const s = this.seleccionada;
        return s ? `Cuotas de la póliza ${s.numero}` : 'Cuotas';
    }
    get subPlan() {
        const s = this.seleccionada;
        if (!s) return '';
        return [s.ramo, s.aseguradora, s.formaPago].filter(Boolean).join(' · ');
    }

    get recibos() {
        return this.cuotas.filter((c) => c.fechaPago && (c.pagado || 0) > 0).map((c) => ({
            ...c,
            titulo: `${c.etiqueta || 'Cuota'}${c.recibo ? ` · recibo ${c.recibo}` : ''}`,
            meta: `Pagado el ${c.pagoTexto}`
        }));
    }
    get hayRecibos() {
        return this.recibos.length > 0;
    }
    get urlMisPolizas() {
        return `${basePath || ''}/mis-polizas${this.polizaId ? `?poliza=${this.polizaId}&pestana=pagos` : ''}`;
    }

    // ---------- Formatos ----------

    claseEstado(estado, mora) {
        const e = String(estado || '').toLowerCase();
        if (e.includes('venc') || mora) return 'b-red';
        if (e.includes('pend')) return 'b-amber';
        if (e.includes('concil') || e.includes('pag')) return 'b-green';
        return 'b-gray';
    }

    fecha(valor) {
        if (!valor) return '—';
        const [a, m, d] = String(valor).substring(0, 10).split('-').map(Number);
        return new Intl.DateTimeFormat('es-MX', { day: '2-digit', month: 'short', year: 'numeric' }).format(new Date(a, m - 1, d));
    }

    moneda(n, codigo, decimales = 0) {
        const iso = codigoMoneda(codigo);
        const opciones = { minimumFractionDigits: decimales, maximumFractionDigits: decimales };
        if (iso === 'UDI') return `${Number(n || 0).toLocaleString('es-MX', opciones)} UDIS`;
        try {
            return new Intl.NumberFormat('es-MX', { style: 'currency', currency: iso, ...opciones }).format(n || 0);
        } catch (e) {
            return `$${Number(n || 0).toLocaleString('es-MX', opciones)}`;
        }
    }
}
