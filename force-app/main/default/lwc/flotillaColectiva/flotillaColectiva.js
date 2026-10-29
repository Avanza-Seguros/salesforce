/**
 * @creation date: 12/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Cotizaciones de FLOTILLA (Auto colectivo). El agente sube la cotización de cada aseguradora
 *               (Excel .xlsx/CSV con mapeo de columnas, o PDF leído con IA); se revisan los incisos y se guarda
 *               como Quote + Inciso_Flotilla__c (FlotillaController). Muestra el comparativo entre aseguradoras
 *               por tipo de vehículo y por vehículo (inciso).
 */
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import { NavigationMixin } from 'lightning/navigation';
import {
    fold, tieneDatos, numero, fecha, fechaVisible, moneda, abrirTabla, detectarEncabezado,
    mapeoAutomatico, opcionesColumnas, opcionesEncabezado, buscarVigencia, bloquesPdf, inicioDatos
} from 'c/lectorArchivos';
import getFlotilla from '@salesforce/apex/FlotillaController.getFlotilla';
import getCoberturasFlotilla from '@salesforce/apex/FlotillaController.getCoberturasFlotilla';
import getAseguradoras from '@salesforce/apex/FlotillaController.getAseguradoras';
import guardarCotizacionFlotilla from '@salesforce/apex/FlotillaController.guardarCotizacionFlotilla';
import eliminarCotizacionFlotilla from '@salesforce/apex/FlotillaController.eliminarCotizacionFlotilla';
import analizarFlotillaPdf from '@salesforce/apex/FlotillaController.analizarFlotillaPdf';
import generarComparativoPdf from '@salesforce/apex/FlotillaController.generarComparativoPdf';

// Campos del inciso (la clave es la misma que devuelve la IA) y encabezados con que suelen venir.
const CAMPOS = [
    { key: 'inciso', label: 'Inciso', alias: ['inciso', 'inc', 'no inciso', 'num inciso', 'no de inciso', 'numero de inciso', 'no', 'consecutivo'] },
    { key: 'serie', label: 'Serie (VIN)', alias: ['serie', 'series', 'no serie', 'no de serie', 'numero de serie', 'num serie', 'vin', 'niv'] },
    { key: 'claveVehicular', label: 'Clave vehicular', alias: ['clave', 'clave amis', 'amis', 'clave vehicular', 'clave vehiculo', 'cve amis', 'mtc'] },
    { key: 'marca', label: 'Marca', alias: ['marca'] },
    { key: 'descripcion', label: 'Descripción', excluir: ['equipo', 'adapt', 'cobertura'], alias: ['descripcion', 'descripcion ocupantes', 'descripcion del vehiculo', 'descripcion vehiculo', 'vehiculo', 'unidad', 'marca tipo', 'marca y tipo', 'marca submarca', 'submarca', 'version'] },
    { key: 'modelo', label: 'Modelo (año)', tipo: 'numero', alias: ['modelo', 'mod', 'ano', 'ano modelo', 'anio'] },
    { key: 'placas', label: 'Placas', alias: ['placas', 'placa', 'matricula'] },
    { key: 'uso', label: 'Uso', alias: ['uso', 'tipo de uso', 'uso del vehiculo', 'servicio'] },
    { key: 'tipoVehiculo', label: 'Tipo de vehículo', alias: ['tipo de vehiculo', 'tipo vehiculo', 'tipo de unidad', 'clase', 'categoria', 'tonelaje'] },
    { key: 'paquete', label: 'Paquete', alias: ['cobertura', 'paquete', 'paq', 'plan', 'tipo de cobertura', 'paquete de cobertura'] },
    { key: 'tipoValor', label: 'Tipo de valor', alias: ['tipo de valor', 'tipo valor', 'valor', 'suma aseg'] },
    { key: 'valor', label: 'Valor / suma asegurada', tipo: 'numero', alias: ['valor convenido', 'valor comercial', 'valor factura', 'suma asegurada', 'suma asegurada dm', 'suma aseg', 'valor vehiculo', 'sa dm', 'valor'] },
    { key: 'dedDM', label: 'Deducible DM', tipo: 'numero', alias: ['dm', 'deducible dm', 'deducibles dm', 'ded dm', 'deducible danos materiales', 'danos materiales ded', 'danos materiales'] },
    { key: 'dedRT', label: 'Deducible RT', tipo: 'numero', alias: ['rt', 'deducible rt', 'ded rt', 'deducible robo total', 'robo total ded', 'robo total'] },
    { key: 'rc', label: 'Responsabilidad civil', tipo: 'numero', alias: ['sumaaseg rc', 'suma asegurada rc', 'sa rc', 'responsabilidad civil por danos a terceros', 'responsabilidad civil', 'rc', 'rc bienes y personas'] },
    { key: 'gm', label: 'Gastos médicos', tipo: 'numero', alias: ['gm', 'gastos medicos', 'gastos medicos ocupantes', 'gmo', 'sa gm'] },
    { key: 'muerte', label: 'Muerte del conductor', tipo: 'numero', alias: ['muerte acc', 'muerte del conductor', 'muerte conductor', 'accidentes automovilisticos al conductor', 'muerte'] },
    { key: 'primaNeta', label: 'Prima neta del inciso', tipo: 'numero', alias: ['prima neta', 'neta', 'pn', 'pn c desc'] },
    { key: 'recargo', label: 'Recargo', tipo: 'numero', alias: ['rec', 'recargo', 'recargo por pago fraccionado', 'recargo fraccionado'] },
    { key: 'derechos', label: 'Derechos / gastos de expedición', tipo: 'numero', alias: ['der pol', 'derechos', 'derecho de poliza', 'derechos de poliza', 'gastos de expedicion', 'gastos expedicion'] },
    { key: 'iva', label: 'IVA', tipo: 'numero', alias: ['iva', 'i v a'] },
    { key: 'prima', label: 'Prima total del inciso', tipo: 'numero', alias: ['prima total', 'total', 'prima', 'prima anual', 'importe', 'importe total'] }
];

// Modelos de pick-up comunes (cuando la descripción no dice "pick up" ni el uso "carga").
const PICKUPS = ['hilux', 'tacoma', 'tundra', 'np300', 'frontier', 'ranger', 'f 150', 'f150', 'lobo', 'saveiro', 'amarok', 'l200',
    'ram 700', 'ram 1200', 'ram 1500', 'ram 2500', 'ram 4000', 'tornado', 's10', 'silverado', 'cheyenne', 'colorado', 'oroch', 'maverick',
    'raptor', 'navara', 'bt 50', 'great wall', 'jac t8', 'poer'];

// Palabras que no sirven para reconocer a la aseguradora en el texto del archivo.
const GENERICAS = new Set(['seguros', 'seguro', 'compania', 'mexico', 'grupo', 'life', 'general', 'generales', 'de', 'cv', 'sa', 'del']);
const POR_PAGINA = 50;
const BLOQUE_PDF = 12000;

export default class FlotillaColectiva extends NavigationMixin(LightningElement) {
    @api readOnly = false;
    // 'carga': subir y administrar cotizaciones; 'comparativo': solo el comparativo (en la sección Comparativa de
    // Cotizaciones de Crear Oportunidad); 'completo' (por omisión): ambos.
    @api modo = 'completo';

    @track cotizaciones = [];
    // Coberturas de las cotizaciones lado a lado (las que trae cada una; mismas reglas que el PDF).
    @track coberturas = [];
    @track mapeo = {};
    @track renglones = [];
    @track encabezado = this.encabezadoVacio();
    aseguradoras = [];
    paso = 'resumen';
    cargando = false;
    progreso = '';
    errorMensaje = '';
    archivoNombre = '';
    hojas = [];
    hojaActual = '';
    filasCrudas = [];
    filaEncabezado = 0;
    filtro = 'todos';
    pagina = 1;
    vistaComparativo = 'tipo';
    paginaComparativo = 1;
    _opportunityId;
    _tabla = null;
    _cola = [];

    @api
    get opportunityId() { return this._opportunityId; }
    set opportunityId(v) {
        const cambio = v !== this._opportunityId;
        this._opportunityId = v;
        if (cambio && v) { this.cargarFlotilla(); }
    }

    // Vuelve a leer las cotizaciones (Crear Oportunidad lo llama cuando la otra sección guarda o elimina una).
    @api
    refrescar() { return this.cargarFlotilla(); }

    get verComparativo() { return this.modo !== 'carga'; }
    get verCarga() { return this.modo !== 'comparativo'; }
    get puedeCargar() { return this.puedeEditar && this.verCarga; }

    async connectedCallback() {
        try {
            this.aseguradoras = await getAseguradoras();
        } catch (e) {
            this.aseguradoras = [];
        }
    }

    // ============================================================
    // Cotizaciones guardadas y comparativo
    // ============================================================
    async cargarFlotilla() {
        if (!this._opportunityId) { return; }
        this.cargando = true;
        try {
            this.cotizaciones = (await getFlotilla({ opportunityId: this._opportunityId })) || [];
            this.coberturas = this.verComparativo && this.cotizaciones.length
                ? (await getCoberturasFlotilla({ opportunityId: this._opportunityId })) || [] : [];
            this.paginaComparativo = 1;
            this.dispatchEvent(new CustomEvent('flotillaactualizada', { detail: { cotizaciones: this.cotizaciones.length } }));
        } catch (e) {
            this.toast('Flotilla', this.mensaje(e), 'error');
        } finally {
            this.cargando = false;
        }
    }

    get sinOportunidad() { return !this._opportunityId; }
    get puedeEditar() { return !this.readOnly && !!this._opportunityId; }
    get enResumen() { return this.paso === 'resumen'; }
    get enMapeo() { return this.paso === 'mapeo'; }
    get enVista() { return this.paso === 'vista'; }
    get hayCotizaciones() { return this.cotizaciones.length > 0; }

    // Tarjetas de cada aseguradora (la de menor prima se resalta).
    get tarjetas() {
        const minimo = Math.min(...this.cotizaciones.map((q) => Number(q.primaTotal) || Infinity));
        const maxUnidades = Math.max(...this.cotizaciones.map((q) => (q.incisos || []).length), 0);
        return this.cotizaciones.map((q) => {
            const incisos = q.incisos || [];
            // Si no cotizó todo el parque vehicular, su prima no es comparable 1 a 1 con las demás.
            const unidadesAviso = incisos.length < maxUnidades ? `Cotizó ${incisos.length} de ${maxUnidades} unidades` : '';
            const valor = incisos.reduce((s, i) => s + (Number(i.valor) || 0), 0);
            const mejor = this.cotizaciones.length > 1 && Number(q.primaTotal) === minimo;
            return {
                id: q.id,
                aseguradora: q.aseguradora,
                numero: q.numero,
                unidades: incisos.length,
                unidadesAviso,
                primaTxt: moneda(q.primaTotal) || '$0',
                desgloseTxt: [q.primaNeta ? `Neta ${moneda(q.primaNeta)}` : '', q.derechos ? `Derechos ${moneda(q.derechos)}` : '',
                    q.iva ? `IVA ${moneda(q.iva)}` : ''].filter((x) => x).join(' · '),
                valorTxt: moneda(valor),
                vigenciaTxt: q.vigenciaDesde ? `${fechaVisible(q.vigenciaDesde)} – ${fechaVisible(q.vigenciaHasta)}` : '',
                formaPago: q.formaPago,
                mejor,
                clase: mejor ? 'tarjeta tarjeta_mejor' : 'tarjeta',
                claseDoc: mejor ? 'doc-card doc-card-win' : 'doc-card'
            };
        });
    }

    // ============================================================
    // Documento del comparativo (mismo estilo que "Comparativa de Cotizaciones" de Crear Oportunidad)
    // ============================================================
    unidadesDe(q) { return (q.incisos || []).length; }
    valorDe(q) { return (q.incisos || []).reduce((s, i) => s + (Number(i.valor) || 0), 0); }
    get maxUnidades() { return Math.max(...this.cotizaciones.map((q) => this.unidadesDe(q)), 0); }
    get mismasUnidades() { return new Set(this.cotizaciones.map((q) => this.unidadesDe(q))).size <= 1; }
    // La de menor prima total y la de menor prima por unidad (cuentan distinto si no cotizaron el mismo número de unidades).
    get mejorTotal() {
        const l = this.cotizaciones.filter((q) => Number(q.primaTotal) > 0);
        return l.length > 1 ? l.reduce((a, q) => (Number(q.primaTotal) < Number(a.primaTotal) ? q : a), l[0]) : null;
    }
    get mejorPorUnidad() {
        const l = this.cotizaciones.filter((q) => Number(q.primaTotal) > 0 && this.unidadesDe(q) > 0);
        return l.length > 1 ? l.reduce((a, q) => (q.primaTotal / this.unidadesDe(q) < a.primaTotal / this.unidadesDe(a) ? q : a), l[0]) : null;
    }
    get columnasTotal() { return this.cotizaciones.length + 1; }
    get docTitulo() { return 'Comparativo de Flotilla de Automóviles'; }
    get docSubtitulo() {
        const q = this.cotizaciones.find((x) => x.vigenciaDesde);
        return q ? `Vigencia ${fechaVisible(q.vigenciaDesde)} – ${fechaVisible(q.vigenciaHasta)}` : '';
    }
    get docTag() {
        const n = this.cotizaciones.length;
        return `${n} ${n === 1 ? 'aseguradora cotizada' : 'aseguradoras comparadas'} · ${this.maxUnidades} ${this.maxUnidades === 1 ? 'unidad' : 'unidades'} · Cotizado por Avanza Seguro`;
    }
    get kpis() {
        const l = this.cotizaciones.filter((q) => Number(q.primaTotal) > 0);
        if (!l.length) { return []; }
        const totales = l.map((q) => Number(q.primaTotal));
        const min = Math.min(...totales);
        const max = Math.max(...totales);
        const res = [
            { key: 'mejor', clase: 'kpi-card kpi-best-price', icono: 'utility:currency', etiqueta: 'Mejor precio', valor: moneda(min), detalle: l[totales.indexOf(min)].aseguradora },
            { key: 'alto', clase: 'kpi-card kpi-highest-price', icono: 'utility:up', etiqueta: 'Precio más alto', valor: moneda(max), detalle: l[totales.indexOf(max)].aseguradora },
            { key: 'prom', clase: 'kpi-card kpi-average', icono: 'utility:chart', etiqueta: 'Prima promedio',
                valor: moneda(totales.reduce((s, t) => s + t, 0) / totales.length), detalle: `${l.length} ${l.length === 1 ? 'cotización' : 'cotizaciones'}` },
            { key: 'ahorro', clase: 'kpi-card kpi-savings', icono: 'utility:success', etiqueta: 'Ahorro potencial', valor: moneda(max - min) || '$0',
                detalle: `${max ? Math.round(((max - min) / max) * 1000) / 10 : 0}% vs. más alto` }
        ];
        const pu = l.filter((q) => this.unidadesDe(q) > 0);
        if (pu.length) {
            const m = pu.reduce((a, q) => (q.primaTotal / this.unidadesDe(q) < a.primaTotal / this.unidadesDe(a) ? q : a), pu[0]);
            res.push({ key: 'unidad', clase: 'kpi-card kpi-coverage', icono: 'utility:travel_and_places', etiqueta: 'Menor prima por unidad',
                valor: moneda(m.primaTotal / this.unidadesDe(m)), detalle: m.aseguradora });
        }
        return res;
    }
    // Columnas: la recomendada en naranja (menor prima; si no cotizaron las mismas unidades, menor prima por unidad).
    get columnasDoc() {
        const recomendada = this.mismasUnidades ? this.mejorTotal : this.mejorPorUnidad;
        const total = this.mejorTotal;
        const unidad = this.mejorPorUnidad;
        return this.cotizaciones.map((q) => {
            const rec = !!recomendada && recomendada.id === q.id;
            const badges = [total && total.id === q.id ? 'Mejor prima' : '',
                !this.mismasUnidades && unidad && unidad.id === q.id ? 'Menor prima por unidad' : ''].filter((x) => x);
            return { id: q.id, aseguradora: q.aseguradora, badge: badges.join(' · '), hayBadge: badges.length > 0,
                headerClass: 'doc-th' + (rec ? ' doc-th-rec' : ''), bodyClass: 'doc-cell' + (rec ? ' doc-cell-hl' : '') };
        });
    }
    celdaDoc(columnas, i, texto, sub, extra) {
        const vacio = !texto || texto === '—';
        return { key: columnas[i].id, texto: vacio ? '—' : texto, sub: sub || '', haySub: !!sub,
            clase: columnas[i].bodyClass + (extra ? ' ' + extra : '') + (vacio ? ' doc-cell-no' : '') };
    }
    get precioDoc() {
        const cols = this.columnasDoc;
        const min = this.mejorTotal ? Number(this.mejorTotal.primaTotal) : 0;
        return this.cotizaciones.map((q, i) => {
            const t = Number(q.primaTotal) || 0;
            const dif = min && t > min ? `+${moneda(t - min)} (+${Math.round(((t - min) / min) * 1000) / 10}%) vs. la mejor` : '';
            return this.celdaDoc(cols, i, moneda(t), dif);
        });
    }
    get filasResumenDoc() {
        const cols = this.columnasDoc;
        const lista = this.cotizaciones;
        const max = this.maxUnidades;
        const filas = [];
        const agrega = (key, etiqueta, desc, celdas) => {
            if (celdas.some((c) => c.texto !== '—')) { filas.push({ key, etiqueta, desc, hayDesc: !!desc, celdas }); }
        };
        const monto = (k) => lista.map((q, i) => this.celdaDoc(cols, i, q[k] !== null && q[k] !== undefined ? moneda(q[k]) || '$0' : ''));
        agrega('neta', 'Prima neta', '', monto('primaNeta'));
        agrega('der', 'Derechos de póliza', '', monto('derechos'));
        agrega('rec', 'Recargo por pago fraccionado', '', monto('recargo'));
        agrega('iva', 'IVA', '', monto('iva'));
        agrega('uni', 'Unidades cotizadas', '', lista.map((q, i) => this.celdaDoc(cols, i, String(this.unidadesDe(q)),
            this.unidadesDe(q) < max ? `de ${max}` : '', this.unidadesDe(q) < max ? 'doc-cell-aviso' : '')));
        agrega('pu', 'Prima por unidad', 'Prima total entre unidades cotizadas', lista.map((q, i) => this.celdaDoc(cols, i,
            this.unidadesDe(q) ? moneda(Number(q.primaTotal) / this.unidadesDe(q)) : '')));
        agrega('valor', 'Valor asegurado de las unidades', '', lista.map((q, i) => this.celdaDoc(cols, i, this.valorDe(q) ? moneda(this.valorDe(q)) : '')));
        agrega('vig', 'Vigencia (inicio – fin)', '', lista.map((q, i) => this.celdaDoc(cols, i,
            q.vigenciaDesde ? `${fechaVisible(q.vigenciaDesde)} – ${fechaVisible(q.vigenciaHasta)}` : '')));
        agrega('fp', 'Forma de pago', '', lista.map((q, i) => this.celdaDoc(cols, i, q.formaPago)));
        agrega('num', 'Cotización', '', lista.map((q, i) => this.celdaDoc(cols, i, q.numero)));
        return filas;
    }
    get hayCoberturasDoc() { return this.coberturas.length > 0; }
    get coberturasDoc() {
        const cols = this.columnasDoc;
        return this.coberturas.map((f) => ({
            key: f.key,
            etiqueta: f.etiqueta,
            celdas: this.cotizaciones.map((q, i) => {
                const t = (f.valores || {})[q.id] || 'No incluida';
                return this.celdaDoc(cols, i, t === 'No incluida' ? '' : t, '', f.distinto && t !== 'No incluida' ? 'doc-cell-aviso' : '');
            }).map((c) => (c.texto === '—' ? { ...c, texto: 'No incluida' } : c))
        }));
    }

    // Detalle por tipo de vehículo o por vehículo con el estilo del documento (la mejor de cada renglón en verde).
    get comparativoTiposDoc() {
        const cols = this.columnasDoc;
        return this.comparativoTipos.map((f) => ({ ...f, esTotal: f.clase === 'fila-total',
            celdas: f.celdas.map((c, i) => this.celdaDoc(cols, i, c.texto, c.sub, c.clase.includes('celda-mejor') ? 'doc-cell-verde' : '')) }));
    }
    get filasVehiculosDoc() {
        const cols = this.columnasDoc;
        return this.filasVehiculos.map((v) => ({ ...v,
            celdas: v.celdas.map((c, i) => this.celdaDoc(cols, i, c.texto, '', c.clase.includes('celda-mejor') ? 'doc-cell-verde' : '')) }));
    }
    get recomendacion() {
        const l = this.cotizaciones;
        if (!l.length) { return ''; }
        if (l.length === 1) {
            return `Se cotizó con ${l[0].aseguradora}: ${moneda(l[0].primaTotal)} por ${this.unidadesDe(l[0])} unidades. Agrega las cotizaciones de otras aseguradoras para compararlas.`;
        }
        const orden = [...l].sort((a, b) => Number(a.primaTotal) - Number(b.primaTotal));
        const [a, b] = orden;
        const partes = [`${a.aseguradora} ofrece la menor prima total: ${moneda(a.primaTotal)}, ${moneda(b.primaTotal - a.primaTotal)} menos que ${b.aseguradora}`
            + ` (${a.primaTotal ? Math.round(((b.primaTotal - a.primaTotal) / a.primaTotal) * 1000) / 10 : 0}%).`];
        if (!this.mismasUnidades) {
            const faltan = l.filter((q) => this.unidadesDe(q) < this.maxUnidades).map((q) => `${q.aseguradora} cotizó ${this.unidadesDe(q)} de ${this.maxUnidades}`);
            partes.push(`Ojo: no todas cotizaron las mismas unidades (${faltan.join('; ')}), así que la comparación justa es la prima por unidad`
                + (this.mejorPorUnidad ? `: ${this.mejorPorUnidad.aseguradora} es la más barata por unidad (${moneda(this.mejorPorUnidad.primaTotal / this.unidadesDe(this.mejorPorUnidad))}).` : '.'));
        }
        partes.push('Revisa en el detalle por tipo de vehículo o por vehículo las coberturas, deducibles y la prima de cada unidad antes de decidir.');
        return partes.join(' ');
    }

    get columnasComparativo() {
        return this.cotizaciones.map((q) => ({ id: q.id, aseguradora: q.aseguradora }));
    }

    // Comparativo por tipo de vehículo: unidades y prima de cada aseguradora.
    get comparativoTipos() {
        const tipos = [];
        this.cotizaciones.forEach((q) => (q.incisos || []).forEach((i) => {
            const t = i.tipoVehiculo || 'Sin tipo';
            if (!tipos.includes(t)) { tipos.push(t); }
        }));
        const filas = tipos.map((t) => this.filaComparativo(t, (i) => (i.tipoVehiculo || 'Sin tipo') === t, false));
        if (tipos.length) { filas.push(this.filaComparativo('Total', () => true, true)); }
        return filas;
    }

    filaComparativo(nombre, filtro, esTotal) {
        const celdas = this.cotizaciones.map((q) => {
            const inc = (q.incisos || []).filter(filtro);
            return { id: q.id, unidades: inc.length, prima: inc.reduce((s, i) => s + this.primaComparable(i), 0) };
        });
        const conPrima = celdas.filter((c) => c.unidades && c.prima > 0);
        // Con distinto número de unidades entre aseguradoras, se compara la prima por unidad.
        const porUnidad = new Set(conPrima.map((c) => c.unidades)).size > 1;
        const valor = (c) => (porUnidad ? c.prima / c.unidades : c.prima);
        const minimo = conPrima.length > 1 ? Math.min(...conPrima.map(valor)) : null;
        return {
            key: nombre,
            nombre,
            clase: esTotal ? 'fila-total' : '',
            celdas: celdas.map((c) => ({
                key: c.id,
                texto: c.unidades ? moneda(c.prima) || '$0' : '—',
                sub: c.unidades
                    ? `${c.unidades} ${c.unidades === 1 ? 'unidad' : 'unidades'}${porUnidad ? ` · ${moneda(c.prima / c.unidades)} c/u` : ''}`
                    : '',
                clase: 'num' + (minimo !== null && c.unidades && c.prima > 0 && valor(c) === minimo ? ' celda-mejor' : '')
            }))
        };
    }

    // Comparativo por vehículo: misma serie (o descripción + modelo) en cada aseguradora.
    get vehiculosComparativo() {
        const mapa = new Map();
        this.cotizaciones.forEach((q, qi) => (q.incisos || []).forEach((i, n) => {
            // Sin serie no se puede saber si es el mismo vehículo en otra aseguradora: va en su propio renglón.
            const k = i.serie ? 'S' + i.serie : `N${qi}|${n}`;
            if (!mapa.has(k)) {
                mapa.set(k, { key: k, descripcion: i.descripcion, serie: i.serie, modelo: i.modelo, tipo: i.tipoVehiculo, primas: [] });
            }
            mapa.get(k).primas[qi] = this.primaComparable(i) || null;
        }));
        return [...mapa.values()];
    }
    get filasVehiculos() {
        const ini = (this.paginaComparativo - 1) * POR_PAGINA;
        return this.vehiculosComparativo.slice(ini, ini + POR_PAGINA).map((v, n) => {
            const validas = this.cotizaciones.map((q, qi) => v.primas[qi]).filter((p) => p);
            const minimo = validas.length > 1 ? Math.min(...validas) : null;
            return {
                ...v,
                num: ini + n + 1,
                celdas: this.cotizaciones.map((q, qi) => ({
                    key: q.id,
                    texto: v.primas[qi] ? moneda(v.primas[qi]) : '—',
                    clase: 'num' + (minimo !== null && v.primas[qi] === minimo ? ' celda-mejor' : '')
                }))
            };
        });
    }
    // Prima del inciso comparable entre aseguradoras (calculada en el servidor con derechos e IVA proporcionales).
    primaComparable(i) {
        const v = i.primaComparable !== undefined && i.primaComparable !== null ? i.primaComparable : (i.prima !== null ? i.prima : i.primaNeta);
        return Number(v) || 0;
    }
    get paginasComparativo() { return Math.max(1, Math.ceil(this.vehiculosComparativo.length / POR_PAGINA)); }
    get textoPaginaComparativo() { return `Página ${this.paginaComparativo} de ${this.paginasComparativo} · ${this.vehiculosComparativo.length} vehículos`; }
    get sinAnteriorComparativo() { return this.paginaComparativo <= 1; }
    get sinSiguienteComparativo() { return this.paginaComparativo >= this.paginasComparativo; }
    anteriorComparativo() { if (this.paginaComparativo > 1) { this.paginaComparativo--; } }
    siguienteComparativo() { if (this.paginaComparativo < this.paginasComparativo) { this.paginaComparativo++; } }

    get opcionesVistaComparativo() {
        return [
            { label: 'Por tipo de vehículo', value: 'tipo' },
            { label: 'Por vehículo', value: 'vehiculo' }
        ];
    }
    get comparativoPorTipo() { return this.vistaComparativo === 'tipo'; }
    handleVistaComparativo(event) { this.vistaComparativo = event.detail.value; }

    // Genera el PDF del comparativo (se guarda en la oportunidad y en cada cotización) y lo abre.
    async handleComparativoPdf() {
        this.cargando = true;
        this.progreso = 'Generando comparativo PDF…';
        try {
            const docId = await generarComparativoPdf({ opportunityId: this._opportunityId });
            this.toast('Flotilla', 'Comparativo PDF generado y guardado en la oportunidad y en las cotizaciones.', 'success');
            this[NavigationMixin.Navigate]({
                type: 'standard__namedPage',
                attributes: { pageName: 'filePreview' },
                state: { selectedRecordId: docId }
            });
        } catch (e) {
            this.toast('Flotilla', this.mensaje(e), 'error');
        } finally {
            this.cargando = false;
            this.progreso = '';
        }
    }

    async handleEliminar(event) {
        const id = event.currentTarget.dataset.id;
        const q = this.cotizaciones.find((x) => x.id === id);
        const ok = await LightningConfirm.open({
            message: `Se eliminará la cotización de ${q ? q.aseguradora : 'la aseguradora'} con todos sus incisos. Los vehículos del cliente se conservan. ¿Continuar?`,
            variant: 'header', label: 'Eliminar cotización', theme: 'warning'
        });
        if (!ok) { return; }
        this.cargando = true;
        try {
            await eliminarCotizacionFlotilla({ quoteId: id });
            this.toast('Flotilla', 'Cotización eliminada.', 'success');
            await this.cargarFlotilla();
        } catch (e) {
            this.toast('Flotilla', this.mensaje(e), 'error');
        } finally {
            this.cargando = false;
        }
    }

    // ============================================================
    // Lectura del archivo de la aseguradora
    // ============================================================
    async handleArchivo(event) {
        const file = event.target.files && event.target.files[0];
        event.target.value = null;
        if (!file) { return; }
        this._cola = [];
        await this.leerArchivo(file);
    }

    // Archivos subidos en "Crear desde PDFs": se leen uno por uno; al guardar o cancelar uno sigue el siguiente.
    @api
    async cargarArchivos(files) {
        this._cola = [...(files || [])];
        await this.siguienteArchivo();
    }

    async siguienteArchivo() {
        const file = (this._cola || []).shift();
        if (file) { await this.leerArchivo(file); }
    }

    async leerArchivo(file) {
        let fallo = false;
        this.archivoNombre = file.name;
        this.errorMensaje = '';
        this.encabezado = this.encabezadoVacio();
        this._filasOtrasHojas = [];
        this.cargando = true;
        this.progreso = 'Leyendo archivo…';
        try {
            if (file.name.toLowerCase().endsWith('.pdf')) {
                await this.procesarPdf(file);
                return;
            }
            this._tabla = await abrirTabla(file);
            this.hojas = this._tabla.hojas.map((h) => ({ label: h, value: h }));
            this.hojaActual = this.hojaConIncisos(this._tabla.hojas);
            this.filasCrudas = await this._tabla.leerHoja(this.hojaActual);
            // Aseguradora y vigencia pueden venir en otra hoja (ej. "Resumen"): se revisan las primeras filas de todas.
            for (const h of this._tabla.hojas) {
                if (h !== this.hojaActual) { this._filasOtrasHojas.push(...(await this._tabla.leerHoja(h)).slice(0, 40)); }
            }
            this.prepararMapeo();
        } catch (e) {
            this.toast('Flotilla', `${file.name}: ${this.mensaje(e)}`, 'error');
            this.paso = 'resumen';
            fallo = true;
        } finally {
            this.cargando = false;
            this.progreso = '';
        }
        if (fallo) { await this.siguienteArchivo(); }
    }

    // Las cotizaciones suelen traer una hoja de presentación y otra con el detalle ("Cotiza", "Detalle", "Incisos").
    hojaConIncisos(hojas) {
        const preferida = hojas.find((h) => /cotiza|detalle|inciso|unidades|vehicul|flotilla/.test(fold(h)));
        return preferida || hojas[0] || '';
    }

    get hayVariasHojas() { return this.hojas.length > 1; }
    async handleHoja(event) {
        this.hojaActual = event.detail.value;
        this.cargando = true;
        try {
            this.filasCrudas = await this._tabla.leerHoja(this.hojaActual);
            this.prepararMapeo();
        } catch (e) {
            this.toast('Flotilla', this.mensaje(e), 'error');
        } finally {
            this.cargando = false;
        }
    }

    prepararMapeo() {
        const filas = this.filasCrudas;
        if (filas.filter((f) => tieneDatos(f)).length < 2) {
            throw new Error('La hoja no tiene renglones de vehículos. Elige otra hoja.');
        }
        this.filaEncabezado = detectarEncabezado(filas, CAMPOS);
        this.mapeo = mapeoAutomatico(filas, this.filaEncabezado, CAMPOS);
        this.detectarEncabezadoCotizacion(filas);
        this.paso = 'mapeo';
    }

    // Encabezado vacío de la cotización: aseguradora, vigencia, forma de pago y montos de la póliza.
    encabezadoVacio() {
        return { aseguradoraId: '', vigenciaDesde: '', vigenciaHasta: '', formaPago: '', primaNeta: null, derechos: null, recargo: null, iva: null, primaTotal: null };
    }

    // Aseguradora, vigencia y forma de pago a partir del texto del archivo (todas sus hojas y el nombre del archivo).
    detectarEncabezadoCotizacion(filas) {
        const todas = [...(this._filasOtrasHojas || []), ...filas];
        const texto = [this.archivoNombre, ...todas.slice(0, 200).map((f) => (f || []).join(' '))].join(' ');
        const enc = { ...this.encabezado };
        enc.aseguradoraId = enc.aseguradoraId || this.aseguradoraPorTexto(texto);
        const vig = buscarVigencia(todas);
        enc.vigenciaDesde = enc.vigenciaDesde || vig.desde;
        enc.vigenciaHasta = enc.vigenciaHasta || vig.hasta;
        if (!enc.formaPago) {
            const todo = fold(todas.map((f) => (f || []).join(' ')).join(' '));
            const formas = ['contado', 'semestral', 'trimestral', 'mensual', 'anual'];
            const f = formas.find((x) => todo.includes(x));
            enc.formaPago = f ? f.charAt(0).toUpperCase() + f.slice(1) : '';
        }
        this.encabezado = enc;
    }

    aseguradoraPorTexto(texto) {
        const t = ` ${fold(texto)} `;
        let mejor = '';
        let puntos = 0;
        (this.aseguradoras || []).forEach((a) => {
            const palabras = fold(a.nombre).split(' ').filter((p) => p.length >= 3 && !GENERICAS.has(p));
            const p = palabras.filter((w) => t.includes(` ${w} `)).length;
            if (p > puntos) { puntos = p; mejor = a.id; }
        });
        return mejor;
    }

    get opcionesColumnas() { return opcionesColumnas(this.filasCrudas, this.filaEncabezado); }
    get opcionesEncabezado() { return opcionesEncabezado(this.filasCrudas); }
    get filaEncabezadoValor() { return String(this.filaEncabezado); }
    // Primer renglón de datos (después del encabezado y sus renglones de continuación).
    get inicioDatos() { return inicioDatos(this.filasCrudas, this.filaEncabezado); }
    get filasDatos() { return this.filasCrudas.slice(this.inicioDatos).filter((f) => tieneDatos(f)).length; }
    get textoEncabezado() {
        const hoja = this.hojaActual ? ` de la hoja "${this.hojaActual}"` : '';
        return `Encabezados en el renglón ${this.filaEncabezado + 1}${hoja}`;
    }
    get camposMapeo() {
        const ejemplo = this.filasCrudas.slice(this.inicioDatos).find((f) => tieneDatos(f)) || [];
        return CAMPOS.map((c) => {
            const col = this.mapeo[c.key];
            const v = col === undefined || col === '' ? '' : ejemplo[Number(col)];
            return {
                key: c.key,
                label: c.label,
                value: col === undefined ? '' : col,
                ejemplo: v === undefined || v === null || v === '' ? '' : 'Ej.: ' + String(v).substring(0, 40),
                clase: col === undefined || col === '' ? 'campo-mapeo' : 'campo-mapeo campo-mapeo_activo'
            };
        });
    }
    handleEncabezado(event) {
        this.filaEncabezado = Number(event.detail.value);
        this.mapeo = mapeoAutomatico(this.filasCrudas, this.filaEncabezado, CAMPOS);
    }
    handleMapeo(event) {
        const campo = event.target.dataset.campo;
        const valor = event.detail.value;
        const nuevo = { ...this.mapeo };
        if (valor !== '') {
            Object.keys(nuevo).forEach((k) => { if (nuevo[k] === valor) { delete nuevo[k]; } });
        }
        if (valor === '') { delete nuevo[campo]; } else { nuevo[campo] = valor; }
        this.mapeo = nuevo;
    }

    aplicarMapeo() {
        const m = this.mapeo;
        if (m.serie === undefined && m.descripcion === undefined) {
            this.toast('Flotilla', 'Indica al menos la columna de la serie o de la descripción del vehículo.', 'warning');
            return;
        }
        if (m.prima === undefined) {
            this.toast('Flotilla', 'Indica la columna de la prima de cada inciso para poder comparar.', 'warning');
            return;
        }
        const datos = [];
        const ini = this.inicioDatos;
        this.filasCrudas.slice(ini).forEach((f, i) => {
            if (!tieneDatos(f)) { return; }
            const o = { fila: ini + i + 1 };
            Object.keys(m).forEach((k) => { o[k] = f[Number(m[k])]; });
            datos.push(o);
        });
        this.validar(datos);
    }

    cancelar() {
        this.limpiar();
        this.siguienteArchivo();
    }
    limpiar() {
        this.errorMensaje = '';
        this.paso = 'resumen';
        this.renglones = [];
        this.filasCrudas = [];
        this._tabla = null;
    }
    volverAMapeo() {
        if (this.filasCrudas.length) { this.paso = 'mapeo'; } else { this.cancelar(); }
    }

    // PDF: texto con pdf.js y lectura de incisos con IA, por bloques de páginas.
    async procesarPdf(file) {
        const bloques = await bloquesPdf(this, file, BLOQUE_PDF, (m) => { this.progreso = m; });
        if (!bloques.length) {
            throw new Error('No se pudo leer texto del PDF (¿está escaneado?). Pide la cotización en Excel.');
        }
        const datos = [];
        const enc = { ...this.encabezado };
        for (let i = 0; i < bloques.length; i++) {
            this.progreso = `Analizando con IA: bloque ${i + 1} de ${bloques.length}…`;
            const json = await analizarFlotillaPdf({ textoCotizacion: bloques[i] });
            let r = {};
            try { r = JSON.parse(json || '{}'); } catch (e) { r = {}; }
            if (!enc.aseguradoraId && r.aseguradora) { enc.aseguradoraId = this.aseguradoraPorTexto(r.aseguradora); }
            enc.vigenciaDesde = enc.vigenciaDesde || fecha(r.vigenciaDesde).iso;
            enc.vigenciaHasta = enc.vigenciaHasta || fecha(r.vigenciaHasta).iso;
            enc.formaPago = enc.formaPago || this.formaPagoNormalizada(r.formaPago);
            ['primaNeta', 'derechos', 'recargo', 'iva', 'primaTotal'].forEach((k) => {
                if (numero(r[k]) !== null) { enc[k] = numero(r[k]); }
            });
            (r.incisos || []).forEach((x) => datos.push({ ...x, fila: datos.length + 1 }));
        }
        if (!enc.aseguradoraId) { enc.aseguradoraId = this.aseguradoraPorTexto(this.archivoNombre + ' ' + bloques[0].substring(0, 3000)); }
        this.encabezado = enc;
        if (!datos.length) {
            throw new Error('La IA no encontró incisos en el PDF.');
        }
        this.filasCrudas = [];
        this.validar(datos);
    }

    // ============================================================
    // Normalización y validación
    // ============================================================
    validar(datos) {
        const renglones = datos
            .map((d) => this.normalizar(d))
            // Un inciso tiene serie, o descripción con prima/valor (descarta pies de página y notas).
            .filter((r) => r.serie || (/[a-z]/i.test(r.descripcion) && (r.prima !== null || r.primaNeta !== null || r.valor !== null)))
            .filter((r) => !/^(sub)?total(es)?\b/.test(fold(r.descripcion)));
        const series = {};
        renglones.forEach((r, i) => {
            r.idx = i;
            if (r.serie) {
                if (series[r.serie] !== undefined) {
                    r.avisos.push(`Serie repetida (fila ${renglones[series[r.serie]].fila})`);
                } else {
                    series[r.serie] = i;
                }
                if (r.serie.length !== 17) { r.avisos.push(`La serie tiene ${r.serie.length} caracteres (un VIN tiene 17)`); }
            } else {
                r.avisos.push('Sin serie: no se ligará a un vehículo del cliente');
            }
            if (r.prima === null && r.primaNeta === null) { r.avisos.push('Sin prima'); }
            if (r.prima !== null && r.prima < 0) { r.errores.push('Prima negativa'); }
        });
        this.renglones = renglones;
        this.sumarMontosIncisos();
        this.filtro = 'todos';
        this.pagina = 1;
        this.paso = 'vista';
    }

    normalizar(d) {
        const txt = (v) => (v === undefined || v === null ? '' : String(v).replace(/\s+/g, ' ').trim());
        const entero = (v) => { const n = numero(v); return n === null ? null : Math.round(n); };
        const pct = (v) => {
            const n = numero(v);
            if (n === null) { return null; }
            return n > 0 && n <= 1 ? Math.round(n * 10000) / 100 : n;
        };
        const r = { fila: d.fila, errores: [], avisos: [] };
        r.inciso = entero(d.inciso);
        r.serie = txt(d.serie).replace(/\s/g, '').toUpperCase();
        r.claveVehicular = txt(d.claveVehicular).replace(/\.0+$/, '');
        r.descripcion = txt(d.descripcion);
        // Si la marca viene en otra columna y la descripción no la trae, se antepone ("RAM 700" -> "CHRYSLER RAM 700").
        const marca = txt(d.marca);
        if (marca && !fold(r.descripcion).includes(fold(marca))) { r.descripcion = `${marca} ${r.descripcion}`.trim(); }
        r.modelo = entero(d.modelo);
        if (r.modelo !== null && (r.modelo < 1900 || r.modelo > 2100)) { r.modelo = null; }
        r.placas = txt(d.placas).replace(/\s/g, '').toUpperCase();
        r.uso = txt(d.uso);
        r.paquete = txt(d.paquete);
        r.tipoValor = txt(d.tipoValor);
        r.valor = numero(d.valor);
        r.dedDM = pct(d.dedDM);
        r.dedRT = pct(d.dedRT);
        r.rc = numero(d.rc);
        r.gm = numero(d.gm);
        r.muerte = numero(d.muerte);
        const dinero = (v) => { const n = numero(v); return n === null ? null : Math.round(n * 100) / 100; };
        r.prima = dinero(d.prima);
        r.primaNeta = dinero(d.primaNeta);
        r.derechos = dinero(d.derechos);
        r.recargo = dinero(d.recargo);
        r.iva = dinero(d.iva);
        r.tipoVehiculo = this.tipoNormalizado(txt(d.tipoVehiculo)) || this.tipoVehiculo(r.descripcion, r.uso);
        return r;
    }

    // Lleva el tipo que trae el archivo (o la IA) a la lista fija, para no partir el resumen
    // en variantes ("Pick up", "PICK-UP CARGA", "Pick-up de cargo"...). Si no se reconoce, se conserva.
    tipoNormalizado(tipo) {
        const t = ` ${fold(tipo)} `;
        if (!t.trim()) { return ''; }
        const tipos = [
            [/ moto/, 'Motocicletas'], [/ tracto/, 'Tractocamiones'], [/remolque| caja/, 'Remolques'],
            [/ (auto|micro|midi|mini)bus/, 'Autobuses'], [/ camion/, 'Camiones'], [/ pick ?up| pickup| carga /, 'Pick-up de carga'],
            [/ autos? | automovil(es)? | sedan| particular/, 'Automóviles']
        ];
        const encontrado = tipos.find(([re]) => re.test(t));
        return encontrado ? encontrado[1] : tipo;
    }

    // Forma de pago con el mismo texto que las opciones del combo ("CONTADO" -> "Contado").
    formaPagoNormalizada(v) {
        const f = fold(v);
        const op = ['Contado', 'Anual', 'Semestral', 'Trimestral', 'Mensual'].find((o) => f.includes(fold(o)));
        return op || '';
    }

    // Tipo de vehículo a partir de la descripción y el uso (como lo agrupan las aseguradoras).
    tipoVehiculo(descripcion, uso) {
        const d = ` ${fold(descripcion)} `;
        const u = fold(uso);
        if (/ moto/.test(d)) { return 'Motocicletas'; }
        if (/ tracto/.test(d)) { return 'Tractocamiones'; }
        if (/ (remolque|semirremolque|caja seca|plataforma|dolly) /.test(d)) { return 'Remolques'; }
        if (/ (autobus|microbus|midibus|minibus) /.test(d)) { return 'Autobuses'; }
        if (/ (camion|rabon|torton|thorton) /.test(d)) { return 'Camiones'; }
        if (u.includes('carga') || / (pick up|pickup|chasis|doble cabina|cabina sencilla|estacas) /.test(d) || / cs /.test(d)
            || PICKUPS.some((m) => d.includes(` ${m} `))) {
            return 'Pick-up de carga';
        }
        return 'Automóviles';
    }

    // ============================================================
    // Vista previa
    // ============================================================
    get validos() { return this.renglones.filter((r) => !r.errores.length); }
    get totalValidos() { return this.validos.length; }
    get conError() { return this.renglones.filter((r) => r.errores.length).length; }
    get conAviso() { return this.renglones.filter((r) => !r.errores.length && r.avisos.length).length; }
    get hayErrores() { return this.conError > 0; }
    // Montos de la póliza propuestos con la suma de los incisos (si el archivo los desglosa por inciso).
    sumarMontosIncisos() {
        const enc = { ...this.encabezado };
        const suma = (k) => {
            const con = this.validos.filter((r) => r[k] !== null && r[k] !== undefined);
            return con.length ? Math.round(con.reduce((s, r) => s + r[k], 0) * 100) / 100 : null;
        };
        if (enc.primaNeta === null) { enc.primaNeta = suma('primaNeta'); }
        if (enc.derechos === null) { enc.derechos = suma('derechos'); }
        if (enc.recargo === null) { enc.recargo = suma('recargo'); }
        if (enc.iva === null) { enc.iva = suma('iva'); }
        // La prima total solo se toma de los incisos si TODOS la traen.
        if (enc.primaTotal === null && this.validos.length && this.validos.every((r) => r.prima !== null)) { enc.primaTotal = suma('prima'); }
        this.encabezado = enc;
    }

    // Prima total de la cotización: la capturada o, si no hay, neta + derechos + recargo + IVA.
    get primaTotalCalculada() {
        const e = this.encabezado;
        if (numero(e.primaTotal) !== null) { return numero(e.primaTotal); }
        if (numero(e.primaNeta) === null) { return null; }
        return Math.round(['primaNeta', 'derechos', 'recargo', 'iva'].reduce((s, k) => s + (numero(e[k]) || 0), 0) * 100) / 100;
    }
    get primaVista() { return moneda(this.primaTotalCalculada) || '$0'; }
    get netaVista() { return moneda(this.encabezado.primaNeta) || '—'; }
    // Aviso cuando la prima total sale solo de la neta (sin IVA ni derechos): compararía contra totales de otras aseguradoras.
    get avisoTotalSinIva() {
        const e = this.encabezado;
        return numero(e.primaTotal) === null && numero(e.primaNeta) !== null && numero(e.iva) === null;
    }
    get valorVista() { return moneda(this.validos.reduce((s, r) => s + (r.valor || 0), 0)) || '—'; }
    get sinGuardar() { return this.totalValidos === 0 || this.cargando || !this.encabezado.aseguradoraId; }
    get textoGuardar() { return `Guardar cotización (${this.totalValidos} incisos)`; }
    get faltaAseguradora() { return !this.encabezado.aseguradoraId; }

    get resumenVista() {
        const mapa = {};
        this.validos.forEach((r) => {
            const c = mapa[r.tipoVehiculo] || (mapa[r.tipoVehiculo] = { key: r.tipoVehiculo, tipo: r.tipoVehiculo, unidades: 0, prima: 0, valor: 0 });
            c.unidades++;
            c.prima += (r.prima !== null ? r.prima : r.primaNeta) || 0;
            c.valor += r.valor || 0;
        });
        return Object.values(mapa).map((c) => ({ ...c, primaTxt: moneda(c.prima) || '$0', valorTxt: moneda(c.valor) }));
    }

    get opcionesAseguradora() { return (this.aseguradoras || []).map((a) => ({ label: a.nombre, value: a.id })); }
    get opcionesFormaPago() {
        return ['Contado', 'Anual', 'Semestral', 'Trimestral', 'Mensual'].map((v) => ({ label: v, value: v }));
    }
    handleEncabezadoCotizacion(event) {
        const campo = event.target.dataset.campo;
        const montos = ['primaNeta', 'derechos', 'recargo', 'iva', 'primaTotal'];
        const valor = montos.includes(campo) ? numero(event.detail.value) : event.detail.value;
        this.encabezado = { ...this.encabezado, [campo]: valor };
    }

    get opcionesFiltro() {
        return [
            { label: `Todos (${this.renglones.length})`, value: 'todos' },
            { label: `Con aviso (${this.conAviso})`, value: 'avisos' },
            { label: `Con error (${this.conError})`, value: 'errores' }
        ];
    }
    handleFiltro(event) { this.filtro = event.detail.value; this.pagina = 1; }
    get filtrados() {
        if (this.filtro === 'errores') { return this.renglones.filter((r) => r.errores.length); }
        if (this.filtro === 'avisos') { return this.renglones.filter((r) => !r.errores.length && r.avisos.length); }
        return this.renglones;
    }
    get renglonesVista() {
        const ini = (this.pagina - 1) * POR_PAGINA;
        return this.filtrados.slice(ini, ini + POR_PAGINA).map((r) => ({
            key: 'r' + r.idx,
            fila: r.fila,
            inciso: r.inciso,
            serie: r.serie,
            descripcion: r.descripcion,
            modelo: r.modelo,
            uso: r.uso,
            tipo: r.tipoVehiculo,
            paquete: r.paquete,
            valorTxt: moneda(r.valor),
            dedTxt: [r.dedDM !== null ? `DM ${r.dedDM}%` : '', r.dedRT !== null ? `RT ${r.dedRT}%` : ''].filter((x) => x).join(' · '),
            rcTxt: moneda(r.rc),
            primaTxt: r.prima !== null ? moneda(r.prima) : moneda(r.primaNeta),
            primaSub: r.prima === null && r.primaNeta !== null ? 'neta' : '',
            mensajes: [...r.errores, ...r.avisos].join(' · '),
            claseFila: r.errores.length ? 'fila-error' : (r.avisos.length ? 'fila-aviso' : ''),
            icono: r.errores.length ? 'utility:error' : (r.avisos.length ? 'utility:warning' : 'utility:success'),
            variante: r.errores.length ? 'error' : (r.avisos.length ? 'warning' : 'success')
        }));
    }
    get paginas() { return Math.max(1, Math.ceil(this.filtrados.length / POR_PAGINA)); }
    get textoPagina() { return `Página ${this.pagina} de ${this.paginas}`; }
    get sinAnterior() { return this.pagina <= 1; }
    get sinSiguiente() { return this.pagina >= this.paginas; }
    anterior() { if (this.pagina > 1) { this.pagina--; } }
    siguiente() { if (this.pagina < this.paginas) { this.pagina++; } }

    // ============================================================
    // Guardado
    // ============================================================
    async guardar() {
        if (!this.encabezado.aseguradoraId) {
            this.toast('Flotilla', 'Selecciona la aseguradora de la cotización.', 'warning');
            return;
        }
        this.cargando = true;
        this.progreso = 'Guardando cotización…';
        let guardada = false;
        try {
            const datos = {
                aseguradoraId: this.encabezado.aseguradoraId,
                vigenciaDesde: this.encabezado.vigenciaDesde || null,
                vigenciaHasta: this.encabezado.vigenciaHasta || null,
                formaPago: this.encabezado.formaPago || null,
                primaNeta: numero(this.encabezado.primaNeta),
                derechos: numero(this.encabezado.derechos),
                recargo: numero(this.encabezado.recargo),
                iva: numero(this.encabezado.iva),
                primaTotal: this.primaTotalCalculada,
                archivo: this.archivoNombre,
                incisos: this.validos.map((r) => ({
                    fila: r.fila, inciso: r.inciso, serie: r.serie || null, claveVehicular: r.claveVehicular,
                    descripcion: r.descripcion, modelo: r.modelo, placas: r.placas || null, uso: r.uso,
                    tipoVehiculo: r.tipoVehiculo, paquete: r.paquete, tipoValor: r.tipoValor, valor: r.valor,
                    dedDM: r.dedDM, dedRT: r.dedRT, rc: r.rc, gm: r.gm, muerte: r.muerte, prima: r.prima, primaNeta: r.primaNeta
                }))
            };
            await guardarCotizacionFlotilla({ opportunityId: this._opportunityId, datosJson: JSON.stringify(datos) });
            this.toast('Flotilla', `Cotización guardada: ${datos.incisos.length} incisos.`, 'success');
            this.limpiar();
            guardada = true;
            await this.cargarFlotilla();
            // La cotización también es un Quote de la oportunidad: el padre refresca su lista.
            this.dispatchEvent(new CustomEvent('cotizacioncreada'));
        } catch (e) {
            this.toast('Flotilla', this.mensaje(e), 'error');
        } finally {
            this.cargando = false;
            this.progreso = '';
        }
        if (guardada) { await this.siguienteArchivo(); }
    }

    // ============================================================
    // Utilidades
    // ============================================================
    mensaje(e) {
        return (e && e.body && e.body.message) || (e && e.message) || 'Ocurrió un error inesperado.';
    }
    toast(title, message, variant) {
        this.errorMensaje = variant === 'error' ? message : '';
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
