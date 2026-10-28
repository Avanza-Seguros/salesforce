/**
 * @creation date: 14/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Cotizaciones colectivas por aseguradora. Ramos de PERSONAS (GMM, Vida Grupo, Accidentes Personales,
 *               Dental, Visión, Viajes): categorías con asegurados, plan, coberturas y tarifa por edad. Ramos de
 *               UBICACIONES (Daños, Empresarial): una fila por inmueble con dirección, valor asegurado, prima y coberturas.
 *               El agente sube la cotización de cada aseguradora (PDF, o Excel que se convierte a texto en el navegador);
 *               la IA la lee y se guarda sola (el agente solo revisa las que quedan incompletas) con ColectivoController (Quote + Categoria_Colectiva__c).
 *               Muestra el comparativo (con cuota al millar cuando hay suma asegurada) y genera el PDF.
 */
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import { NavigationMixin } from 'lightning/navigation';
import { fold, numero, fecha, fechaVisible, moneda, abrirTabla, paginasPdf, bloquesCompactos, tablaATexto, buscarVigencia } from 'c/lectorArchivos';
import getAseguradoras from '@salesforce/apex/FlotillaController.getAseguradoras';
import getCotizacionesColectivas from '@salesforce/apex/ColectivoController.getCotizacionesColectivas';
import guardarCotizacionColectiva from '@salesforce/apex/ColectivoController.guardarCotizacionColectiva';
import eliminarCotizacionColectiva from '@salesforce/apex/ColectivoController.eliminarCotizacionColectiva';
import analizarCotizacionColectiva from '@salesforce/apex/ColectivoController.analizarCotizacionColectiva';
import generarComparativoPdf from '@salesforce/apex/ColectivoController.generarComparativoPdf';

// Palabras que no sirven para reconocer a la aseguradora en el texto.
const GENERICAS = new Set(['seguros', 'seguro', 'compania', 'mexico', 'grupo', 'life', 'general', 'generales', 'de', 'cv', 'sa', 'del', 'corporativos']);
// Texto máximo que se manda a la IA en cada llamada. Un PDF más largo (pólizas o cotizaciones de cientos de páginas)
// se compacta y se lee por partes, hasta MAX_PARTES.
const MAX_TEXTO = 55000;
const MAX_PARTES = 8;
// Parámetros del plan que se comparan (clave en la categoría -> etiqueta).
const PLAN = [
    ['plan', 'Plan'], ['sumaAsegurada', 'Suma asegurada'], ['deducible', 'Deducible'], ['coaseguro', 'Coaseguro'],
    ['topeCoaseguro', 'Tope de coaseguro'], ['tabulador', 'Tabulador / círculo médico'], ['nivelHospitalario', 'Nivel hospitalario'],
    ['territorio', 'Territorio']
];
// Ramos en los que cada renglón de la cotización es una ubicación (inmueble) y no un grupo de personas.
const RAMOS_UBICACIONES = ['Danos', 'Empresarial'];
// Nombre del ramo para el título del comparativo.
const RAMOS_ETIQUETA = {
    GMM: 'Gastos Médicos Mayores', Vida: 'Vida Grupo', 'Accidentes Personales': 'Accidentes Personales', Dental: 'Dental',
    Vision: 'Visión', Viajes: 'Viajes', Danos: 'Daños', Empresarial: 'Paquete Empresarial'
};
// Palabras que identifican el ramo en el texto de la cotización (ya pasado por fold): gana el que más aparece.
const RAMOS_TEXTO = [
    ['GMM', /gastos medicos|\bgmm\b|\bgmg\b|hospitaliz|coaseguro|maternidad/g], ['Vida', /\bvida\b/g],
    ['Accidentes Personales', /accidentes personales/g], ['Dental', /\bdental\b/g], ['Vision', /\bvision\b|\blentes\b/g],
    ['Viajes', /\bviajes?\b|asistencia en viaje/g], ['Danos', /\bincendio\b|\bdanos\b|ubicacion|terremoto|\bedificio|contenidos/g],
    ['Empresarial', /paquete empresarial|\bempresarial\b|\bpyme\b/g]
];
// Valor de una cobertura (ya pasado por fold) que indica que no se incluye: "N/A", "No amparada", "Excluida", "-".
const NO_AMPARADA = /^(n a|na|no amparad[ao]s?|no aplica|excluid[ao]s?|no incluid[ao]s?|)$/;
// Coberturas que en GMM ya son campos fijos del plan.
const CAMPOS_GMM = /^(plan|suma asegurada|deducible|coaseguro|tope|tabulador|nivel hospitalario|hospitales|territorio|cobertura territori)/;

export default class ColectivoPersonas extends NavigationMixin(LightningElement) {
    @api readOnly = false;
    // Valor del picklist Ramo de la oportunidad (GMM, Vida, Accidentes Personales, Danos, ...). Al leer cotizaciones
    // desde "Crear desde PDFs" el ramo se detecta del texto del primer archivo.
    @api
    get ramo() { return this._ramo; }
    set ramo(v) { this._ramo = v; }
    // 'carga': subir y administrar cotizaciones; 'comparativo': solo el comparativo (en la sección Comparativa de
    // Cotizaciones de Crear Oportunidad); 'completo' (por omisión): ambos.
    @api modo = 'completo';

    @track cotizaciones = [];
    @track vista = null;
    aseguradoras = [];
    paso = 'resumen';
    cargando = false;
    progreso = '';
    errorMensaje = '';
    archivoNombre = '';
    _opportunityId;

    @api
    get opportunityId() { return this._opportunityId; }
    set opportunityId(v) {
        const cambio = v !== this._opportunityId;
        this._opportunityId = v;
        if (cambio && v) { this.cargar(); }
    }

    // Vuelve a leer las cotizaciones (Crear Oportunidad lo llama cuando la otra sección guarda o elimina una).
    @api
    refrescar() { return this.cargar(); }

    get verComparativo() { return this.modo !== 'carga'; }
    get verCarga() { return this.modo !== 'comparativo'; }
    get puedeCargar() { return this.puedeEditar && this.verCarga; }

    async connectedCallback() {
        try { this.aseguradoras = await getAseguradoras(); } catch (e) { this.aseguradoras = []; }
    }

    // ============================================================
    // Cotizaciones guardadas y comparativo
    // ============================================================
    async cargar() {
        if (!this._opportunityId) { return; }
        this.cargando = true;
        try {
            this.cotizaciones = (await getCotizacionesColectivas({ opportunityId: this._opportunityId })) || [];
            this.dispatchEvent(new CustomEvent('colectivoactualizado', { detail: { cotizaciones: this.cotizaciones.length } }));
        } catch (e) {
            this.toast('Cotización colectiva', this.mensaje(e), 'error');
        } finally {
            this.cargando = false;
        }
    }

    get sinOportunidad() { return !this._opportunityId; }
    get puedeEditar() { return !this.readOnly && !!this._opportunityId; }
    get enResumen() { return this.paso === 'resumen'; }
    get enVista() { return this.paso === 'vista'; }
    get hayCotizaciones() { return this.cotizaciones.length > 0; }
    get esUbicaciones() { return RAMOS_UBICACIONES.includes(this.ramo); }
    get esPersonas() { return !this.esUbicaciones; }
    // GMM (o sin ramo) usa los campos fijos del plan (deducible, coaseguro...); los demás ramos, la lista de coberturas.
    get esGmm() { return !this.ramo || this.ramo === 'GMM'; }
    get unidad() { return this.esUbicaciones ? 'ubicaciones' : 'asegurados'; }
    unidadDe(n) { return n === 1 ? (this.esUbicaciones ? 'ubicación' : 'asegurado') : this.unidad; }
    get etiquetaRenglon() { return this.esUbicaciones ? 'Ubicación' : 'Categoría'; }
    get tituloRenglones() { return this.esUbicaciones ? 'Ubicaciones' : 'Categorías'; }
    get textoCarga() {
        return this.esUbicaciones
            ? 'PDF o Excel (.xlsx, .xlsm, .xls, CSV). La IA lee las ubicaciones (dirección, valor asegurado y prima), las coberturas con sus deducibles y las formas de pago; la cotización se crea sola (si falta la aseguradora, la revisas). Puedes subir varias a la vez.'
            : 'PDF o Excel (.xlsx, .xlsm, .xls, CSV). La IA lee categorías, asegurados, suma asegurada, coberturas, primas, formas de pago y la tabla de edades; la cotización se crea sola (si falta la aseguradora, la revisas). Puedes subir varias a la vez.';
    }

    // Si alguna aseguradora no incluye IVA, se compara prima neta + derechos para todas (como en el PDF).
    get compararSinIva() {
        const conIva = this.cotizaciones.filter((q) => q.iva !== null && q.iva !== undefined).length;
        return conIva > 0 && conIva < this.cotizaciones.length;
    }
    base(q) {
        const b = this.compararSinIva ? (Number(q.primaNeta) || 0) + (Number(q.derechos) || 0) : Number(q.primaTotal) || 0;
        return b || Number(q.primaTotal) || 0;
    }
    // Tamaño del grupo: asegurados (personas) o número de ubicaciones.
    asegurados(q) {
        if (this.esUbicaciones) { return (q.categorias || []).length; }
        return (q.categorias || []).reduce((s, c) => s + (Number(c.asegurados) || 0), 0);
    }
    sumaTotal(q) { return (q.categorias || []).reduce((s, c) => s + (Number(c.sumaAseguradaTotal) || 0), 0); }
    // Prima neta por cada $1,000 de suma asegurada: compara precio aunque las sumas aseguradas difieran.
    cuotaAlMillar(q) {
        const sa = this.sumaTotal(q);
        const neta = Number(q.primaNeta) || (q.categorias || []).reduce((s, c) => s + (Number(c.primaNeta) || 0), 0);
        return sa > 0 && neta > 0 ? (neta / sa) * 1000 : null;
    }
    get ordenadas() {
        return [...this.cotizaciones].sort((a, b) => this.base(a) - this.base(b));
    }
    get etiquetaBase() { return this.compararSinIva ? 'Prima neta + derechos (sin IVA)' : 'Prima total anual'; }

    // Si no cotizaron lo mismo (asegurados / ubicaciones o suma asegurada distintos), la que cobra menos por cada
    // $1,000 asegurados; null si todas cotizaron igual o a alguna le falta la suma asegurada.
    get mejorPorCuota() {
        const lista = this.ordenadas;
        if (lista.length < 2 || lista.some((q) => this.cuotaAlMillar(q) === null)) { return null; }
        const tamanos = new Set(lista.map((q) => this.asegurados(q)));
        const sumas = lista.map((q) => this.sumaTotal(q));
        if (tamanos.size === 1 && Math.max(...sumas) - Math.min(...sumas) <= Math.max(...sumas) * 0.01) { return null; }
        return lista.reduce((m, q) => (this.cuotaAlMillar(q) < this.cuotaAlMillar(m) ? q : m), lista[0]);
    }
    get notaCuota() {
        const m = this.mejorPorCuota;
        if (!m) { return ''; }
        const lista = this.ordenadas;
        const motivo = new Set(lista.map((q) => this.asegurados(q))).size > 1 ? `no todas cotizaron ${this.esUbicaciones ? 'las mismas ubicaciones' : 'los mismos asegurados'}` : 'las sumas aseguradas no son iguales';
        return m.id === lista[0].id
            ? `Ojo: ${motivo}. Por cada $1,000 asegurados, ${m.aseguradora} también es la más barata (${this.cuotaAlMillar(m).toFixed(3)} ‰).`
            : `Ojo: ${motivo}. Por cada $1,000 asegurados, ${m.aseguradora} cobra menos (${this.cuotaAlMillar(m).toFixed(3)} ‰ contra ${this.cuotaAlMillar(lista[0]).toFixed(3)} ‰ de ${lista[0].aseguradora}).`;
    }

    get tarjetas() {
        const lista = this.ordenadas;
        const mejor = lista.length ? this.base(lista[0]) : 0;
        const porCuota = this.mejorPorCuota;
        const maxAseg = Math.max(...lista.map((q) => this.asegurados(q)), 0);
        return lista.map((q, i) => {
            const a = this.asegurados(q);
            const b = this.base(q);
            const esMejor = lista.length > 1 && i === 0;
            return {
                id: q.id,
                aseguradora: q.aseguradora,
                numero: q.numero,
                baseTxt: moneda(b) || '$0',
                difTxt: !esMejor && lista.length > 1 && mejor ? `+${moneda(b - mejor)} (+${Math.round(((b - mejor) / mejor) * 1000) / 10}%)` : '',
                desgloseTxt: [q.primaNeta ? `Neta ${moneda(q.primaNeta)}` : '', q.derechos ? `Derechos ${moneda(q.derechos)}` : '',
                    q.iva ? `IVA ${moneda(q.iva)}` : 'Sin IVA', q.primaTotal ? `Total ${moneda(q.primaTotal)}` : ''].filter((x) => x).join(' · '),
                aseguradosTxt: `${a} ${this.unidadDe(a)} · ${a ? moneda(b / a) : '—'} por ${this.esUbicaciones ? 'ubicación' : 'asegurado'}`,
                aseguradosAviso: a < maxAseg ? `Cotizó ${a} de ${maxAseg} ${this.unidad}` : '',
                sumaTxt: this.sumaTotal(q) > 0
                    ? `${this.esUbicaciones ? 'Valor asegurado' : 'Suma asegurada'} ${moneda(this.sumaTotal(q))}`
                        + (this.cuotaAlMillar(q) !== null ? ` · cuota ${this.cuotaAlMillar(q).toFixed(3)} ‰` : '')
                    : '',
                vigenciaTxt: q.vigenciaDesde ? `${fechaVisible(q.vigenciaDesde)} – ${fechaVisible(q.vigenciaHasta)}` : '',
                mejor: esMejor,
                mejorCuota: !!porCuota && porCuota.id === q.id && !esMejor,
                clase: esMejor ? 'tarjeta tarjeta_mejor' : 'tarjeta',
                claseDoc: esMejor ? 'doc-card doc-card-win' : 'doc-card'
            };
        });
    }

    get columnas() { return this.ordenadas.map((q) => ({ id: q.id, aseguradora: q.aseguradora })); }

    // Coberturas de "parametros" de todas las cotizaciones (agrupadas por nombre sin acentos), en orden de aparición.
    get conceptos() {
        const vistos = new Map();
        this.ordenadas.forEach((q) => (q.categorias || []).forEach((c) => (c.parametros || []).forEach((pm) => {
            const llave = fold(pm.concepto || '').replace(/[^a-z0-9]/g, '');
            // La cuota al millar impresa no se repite: se calcula para todas en las tarjetas.
            if (llave && llave !== 'cuotaalmillar' && !vistos.has(llave)) { vistos.set(llave, this.txt(pm.concepto)); }
        })));
        return [...vistos.entries()].map(([llave, etiqueta]) => [`#${llave}`, etiqueta]);
    }

    // Plan lado a lado: un renglón por parámetro o cobertura; si cambia por categoría se muestra "Categoría: valor".
    get filasPlan() {
        const lista = this.ordenadas;
        // En ubicaciones el giro y el valor de cada inmueble ya están en la tabla de ubicaciones.
        return [...(this.esUbicaciones ? [] : PLAN), ...this.conceptos].map(([clave, etiqueta]) => {
            const valores = lista.map((q) => (clave.startsWith('#') ? this.valorParametro(q, clave.slice(1)) : this.valorPlan(q, clave)));
            const unicos = new Set(valores.filter((v) => v).map((v) => fold(v).replace(/\s/g, '')));
            return {
                key: clave,
                etiqueta,
                hay: valores.some((v) => v),
                distinto: unicos.size > 1 && clave !== 'plan' && clave !== 'tabulador',
                celdas: valores.map((v, i) => ({ key: lista[i].id, texto: v || '—', clase: 'num' + (unicos.size > 1 && clave !== 'plan' && clave !== 'tabulador' ? ' celda-aviso' : '') }))
            };
        }).filter((f) => f.hay);
    }
    get planDistinto() { return this.filasPlan.some((f) => f.distinto); }
    get tituloPlan() { return this.esUbicaciones ? 'Coberturas cotizadas' : 'Plan cotizado'; }
    valorParametro(q, llave) {
        const pares = [];
        (q.categorias || []).forEach((c) => (c.parametros || []).forEach((pm) => {
            if (fold(pm.concepto || '').replace(/[^a-z0-9]/g, '') === llave && this.txt(pm.valor)) { pares.push([c.nombre, this.txt(pm.valor)]); }
        }));
        const unicos = [...new Set(pares.map((x) => x[1]))];
        if (!unicos.length) { return ''; }
        // Un solo valor si aplica igual a todas las categorías; si solo algunas la tienen, se dice cuáles.
        const todas = pares.length >= (q.categorias || []).length;
        return unicos.length === 1 && todas ? unicos[0] : pares.map(([n, v]) => `${n}: ${v}`).join(' / ');
    }

    // Ubicaciones lado a lado (Daños / Empresarial): prima y valor asegurado de cada inmueble por aseguradora.
    get filasUbicaciones() {
        if (!this.esUbicaciones) { return []; }
        const lista = this.ordenadas;
        const llave = (c) => fold(c.direccion || c.nombre || '').replace(/[^a-z0-9]/g, '').slice(0, 40);
        const filas = [];
        lista.forEach((q) => (q.categorias || []).forEach((c) => {
            if (!filas.some((f) => f.llave === llave(c))) { filas.push({ llave: llave(c), nombre: c.nombre, direccion: c.direccion || '' }); }
        }));
        return filas.map((f) => ({
            key: f.llave || f.nombre,
            nombre: f.nombre,
            direccion: f.direccion,
            celdas: lista.map((q) => {
                const c = (q.categorias || []).find((x) => llave(x) === f.llave);
                return {
                    key: q.id,
                    texto: c ? moneda(c.primaNeta) || '—' : 'No cotizada',
                    sub: c && c.sumaAseguradaTotal ? `Valor ${moneda(c.sumaAseguradaTotal)}` : ''
                };
            })
        }));
    }
    get hayUbicaciones() { return this.filasUbicaciones.length > 0; }
    valorPlan(q, clave) {
        const cats = (q.categorias || []).filter((c) => c[clave]);
        const unicos = [...new Set(cats.map((c) => c[clave]))];
        if (!unicos.length) { return ''; }
        return unicos.length === 1 ? unicos[0] : cats.map((c) => `${c.nombre}: ${c[clave]}`).join(' / ');
    }

    // Formas de pago: total anual en cada forma por aseguradora.
    get filasFormasPago() {
        const lista = this.ordenadas;
        const formas = [];
        lista.forEach((q) => (q.formasPago || []).forEach((f) => {
            const nombre = this.capitalizar(f.forma);
            if (nombre && !formas.includes(nombre)) { formas.push(nombre); }
        }));
        return formas.map((forma) => ({
            key: forma,
            forma,
            celdas: lista.map((q) => {
                const f = (q.formasPago || []).find((x) => this.capitalizar(x.forma) === forma);
                if (!f) { return { key: q.id, texto: '—', sub: '' }; }
                const sub = [Number(f.recargoPct) ? `recargo ${f.recargoPct}%` : '', Number(f.numeroPagos) > 1 ? `${f.numeroPagos} pagos` : ''].filter((x) => x).join(' · ');
                return { key: q.id, texto: moneda(f.primaTotal) || '—', sub };
            })
        }));
    }
    get hayFormasPago() { return this.filasFormasPago.length > 0; }

    // ============================================================
    // Documento del comparativo (mismo estilo que "Comparativa de Cotizaciones" de Crear Oportunidad)
    // ============================================================
    // Columnas de la tabla (concepto + una por aseguradora), para los renglones de sección.
    get columnasTotal() { return this.cotizaciones.length + 1; }
    get ramoEtiqueta() { return RAMOS_ETIQUETA[this.ramo] || this.ramo || 'Gastos Médicos Mayores'; }
    get docTitulo() { return `Comparativo de Seguro Colectivo de ${this.ramoEtiqueta}`; }
    get docSubtitulo() {
        const q = this.ordenadas.find((x) => x.vigenciaDesde);
        return q ? `Vigencia ${fechaVisible(q.vigenciaDesde)} – ${fechaVisible(q.vigenciaHasta)}` : '';
    }
    get docTag() {
        const n = this.cotizaciones.length;
        const max = Math.max(...this.cotizaciones.map((q) => this.asegurados(q)), 0);
        return `${n} ${n === 1 ? 'aseguradora cotizada' : 'aseguradoras comparadas'} · ${max} ${this.unidadDe(max)} · Cotizado por Avanza Seguro`;
    }

    // Indicadores: mejor y peor prima, promedio, ahorro y la mejor cuota al millar (o prima por asegurado / ubicación).
    get kpis() {
        const lista = this.ordenadas;
        if (!lista.length) { return []; }
        const bases = lista.map((q) => this.base(q));
        const min = bases[0];
        const max = Math.max(...bases);
        const peor = lista[bases.indexOf(max)];
        const prom = bases.reduce((s, b) => s + b, 0) / bases.length;
        const res = [
            { key: 'mejor', clase: 'kpi-card kpi-best-price', icono: 'utility:currency', etiqueta: 'Mejor precio', valor: moneda(min), detalle: lista[0].aseguradora },
            { key: 'alto', clase: 'kpi-card kpi-highest-price', icono: 'utility:up', etiqueta: 'Precio más alto', valor: moneda(max), detalle: peor.aseguradora },
            { key: 'prom', clase: 'kpi-card kpi-average', icono: 'utility:chart', etiqueta: 'Prima promedio', valor: moneda(prom),
                detalle: `${lista.length} ${lista.length === 1 ? 'cotización' : 'cotizaciones'}` },
            { key: 'ahorro', clase: 'kpi-card kpi-savings', icono: 'utility:success', etiqueta: 'Ahorro potencial', valor: moneda(max - min) || '$0',
                detalle: `${max ? Math.round(((max - min) / max) * 1000) / 10 : 0}% vs. más alto` }
        ];
        const conCuota = lista.filter((q) => this.cuotaAlMillar(q) !== null);
        if (conCuota.length) {
            const m = conCuota.reduce((a, q) => (this.cuotaAlMillar(q) < this.cuotaAlMillar(a) ? q : a), conCuota[0]);
            res.push({ key: 'cuota', clase: 'kpi-card kpi-coverage', icono: 'utility:percent', etiqueta: 'Mejor cuota al millar',
                valor: `${this.cuotaAlMillar(m).toFixed(3)} ‰`, detalle: m.aseguradora });
        } else {
            const porUnidad = lista.filter((q) => this.asegurados(q) > 0);
            if (porUnidad.length) {
                const m = porUnidad.reduce((a, q) => (this.base(q) / this.asegurados(q) < this.base(a) / this.asegurados(a) ? q : a), porUnidad[0]);
                res.push({ key: 'unidad', clase: 'kpi-card kpi-coverage', icono: this.esUbicaciones ? 'utility:location' : 'utility:groups',
                    etiqueta: `Menor prima por ${this.esUbicaciones ? 'ubicación' : 'asegurado'}`, valor: moneda(this.base(m) / this.asegurados(m)),
                    detalle: m.aseguradora });
            }
        }
        return res;
    }

    // Columnas del documento: la de mejor prima resaltada en naranja; la de mejor cuota al millar lleva su etiqueta.
    get columnasDoc() {
        const lista = this.ordenadas;
        const porCuota = this.mejorPorCuota;
        return lista.map((q, i) => {
            const mejor = lista.length > 1 && i === 0;
            const badges = [mejor ? 'Mejor prima' : '', porCuota && porCuota.id === q.id && !mejor ? 'Mejor cuota al millar' : ''].filter((x) => x);
            return { id: q.id, aseguradora: q.aseguradora, badge: badges.join(' · '), hayBadge: badges.length > 0,
                headerClass: 'doc-th' + (mejor ? ' doc-th-rec' : ''), bodyClass: 'doc-cell' + (mejor ? ' doc-cell-hl' : '') };
        });
    }
    celdaDoc(columnas, i, texto, sub, aviso) {
        const vacio = !texto || texto === '—';
        return { key: columnas[i].id, texto: vacio ? '—' : texto, sub: sub || '', haySub: !!sub,
            clase: columnas[i].bodyClass + (aviso ? ' doc-cell-aviso' : '') + (vacio ? ' doc-cell-no' : '') };
    }
    get precioDoc() {
        const lista = this.ordenadas;
        const cols = this.columnasDoc;
        const mejor = lista.length ? this.base(lista[0]) : 0;
        return lista.map((q, i) => {
            const b = this.base(q);
            const dif = i > 0 && mejor ? `+${moneda(b - mejor)} (+${Math.round(((b - mejor) / mejor) * 1000) / 10}%) vs. la mejor` : '';
            return this.celdaDoc(cols, i, moneda(b), dif);
        });
    }
    // Renglones de montos, tamaño del grupo, suma asegurada y datos de la cotización (se omiten los que ninguna trae).
    get filasResumenDoc() {
        const lista = this.ordenadas;
        const cols = this.columnasDoc;
        const maxAseg = Math.max(...lista.map((q) => this.asegurados(q)), 0);
        const monto = (k, vacio) => lista.map((q, i) => {
            const v = q[k];
            const hay = v !== null && v !== undefined && v !== '';
            return this.celdaDoc(cols, i, hay ? moneda(v) || '$0' : vacio || '', '', !hay && !!vacio);
        });
        const filas = [];
        const agrega = (key, etiqueta, desc, celdas) => {
            if (celdas.some((c) => c.texto !== '—' && c.texto !== 'No incluido')) { filas.push({ key, etiqueta, desc, hayDesc: !!desc, celdas }); }
        };
        agrega('neta', 'Prima neta', '', monto('primaNeta'));
        agrega('der', 'Derechos / gastos de expedición', '', monto('derechos'));
        agrega('rec', 'Recargo por pago fraccionado', '', monto('recargo'));
        agrega('iva', 'IVA', '', monto('iva', this.compararSinIva ? 'No incluido' : ''));
        agrega('total', 'Prima total', '', monto('primaTotal'));
        agrega('tam', this.esUbicaciones ? 'Ubicaciones cotizadas' : 'Asegurados cotizados', '',
            lista.map((q, i) => this.celdaDoc(cols, i, String(this.asegurados(q)), this.asegurados(q) < maxAseg ? `de ${maxAseg}` : '', this.asegurados(q) < maxAseg)));
        agrega('prom', `Prima por ${this.esUbicaciones ? 'ubicación' : 'asegurado'}`, '',
            lista.map((q, i) => this.celdaDoc(cols, i, this.asegurados(q) ? moneda(this.base(q) / this.asegurados(q)) : '')));
        agrega('sa', this.esUbicaciones ? 'Valor total asegurado' : 'Suma asegurada total', '',
            lista.map((q, i) => this.celdaDoc(cols, i, this.sumaTotal(q) > 0 ? moneda(this.sumaTotal(q)) : '')));
        agrega('cuota', 'Cuota al millar', 'Prima neta por cada $1,000 asegurados',
            lista.map((q, i) => this.celdaDoc(cols, i, this.cuotaAlMillar(q) !== null ? `${this.cuotaAlMillar(q).toFixed(3)} ‰` : '')));
        agrega('vig', 'Vigencia (inicio – fin)', '',
            lista.map((q, i) => this.celdaDoc(cols, i, q.vigenciaDesde ? `${fechaVisible(q.vigenciaDesde)} – ${fechaVisible(q.vigenciaHasta)}` : '')));
        agrega('num', 'Número de cotización', '', lista.map((q, i) => this.celdaDoc(cols, i, q.numeroCotizacion || q.numero)));
        return filas;
    }
    get filasPlanDoc() {
        const cols = this.columnasDoc;
        return this.filasPlan.map((f) => ({ ...f, celdas: f.celdas.map((c, i) => this.celdaDoc(cols, i, c.texto, '', f.distinto)) }));
    }
    get filasFormasPagoDoc() {
        const cols = this.columnasDoc;
        return this.filasFormasPago.map((f) => ({ ...f, celdas: f.celdas.map((c, i) => this.celdaDoc(cols, i, c.texto, c.sub)) }));
    }
    get filasUbicacionesDoc() {
        const cols = this.columnasDoc;
        return this.filasUbicaciones.map((f) => ({ ...f, hayDireccion: !!f.direccion,
            celdas: f.celdas.map((c, i) => this.celdaDoc(cols, i, c.texto === 'No cotizada' ? 'No cotizada' : c.texto, c.sub, c.texto === 'No cotizada')) }));
    }
    // Recomendación en palabras: la de menor prima, cuánto ahorra, y los "ojo" (tamaño, plan distinto, cuota al millar).
    get recomendacion() {
        const lista = this.ordenadas;
        if (!lista.length) { return ''; }
        const b0 = this.base(lista[0]);
        if (lista.length === 1) {
            return `Se cotizó con ${lista[0].aseguradora}: ${moneda(b0)} por ${this.asegurados(lista[0])} ${this.unidadDe(this.asegurados(lista[0]))}. `
                + 'Agrega las cotizaciones de otras aseguradoras para compararlas.';
        }
        const b1 = this.base(lista[1]);
        const partes = [`${lista[0].aseguradora} ofrece la menor prima${this.compararSinIva ? ' (neta + derechos, sin IVA)' : ''}: ${moneda(b0)}, `
            + `${moneda(b1 - b0)} menos que ${lista[1].aseguradora} (${b0 ? Math.round(((b1 - b0) / b0) * 1000) / 10 : 0}%).`];
        const maxAseg = Math.max(...lista.map((q) => this.asegurados(q)));
        if (this.asegurados(lista[0]) < maxAseg) {
            partes.push(`Ojo: ${lista[0].aseguradora} cotizó ${this.asegurados(lista[0])} de ${maxAseg} ${this.unidad}.`);
        }
        const distintas = this.filasPlan.filter((f) => f.distinto).map((f) => f.etiqueta.toLowerCase());
        if (distintas.length) {
            const cuales = distintas.length > 4 ? `${distintas.slice(0, 4).join(', ')} y ${distintas.length - 4} más` : distintas.join(', ');
            partes.push(`Los planes no son idénticos (${cuales}): revisa el plan y las coberturas antes de decidir solo por precio.`);
        }
        if (this.notaCuota) { partes.push(this.notaCuota.replace(/^Ojo: /, 'Además, ')); }
        return partes.join(' ');
    }

    async handleEliminar(event) {
        const id = event.currentTarget.dataset.id;
        const q = this.cotizaciones.find((x) => x.id === id);
        const ok = await LightningConfirm.open({
            message: `Se eliminará la cotización de ${q ? q.aseguradora : 'la aseguradora'} con sus categorías. ¿Continuar?`,
            variant: 'header', label: 'Eliminar cotización', theme: 'warning'
        });
        if (!ok) { return; }
        this.cargando = true;
        try {
            await eliminarCotizacionColectiva({ quoteId: id });
            this.toast('Cotización colectiva', 'Cotización eliminada.', 'success');
            await this.cargar();
            this.dispatchEvent(new CustomEvent('cotizacioncreada'));
        } catch (e) {
            this.toast('Cotización colectiva', this.mensaje(e), 'error');
        } finally {
            this.cargando = false;
        }
    }

    async handleComparativoPdf() {
        this.cargando = true;
        this.progreso = 'Generando comparativo PDF…';
        try {
            const docId = await generarComparativoPdf({ opportunityId: this._opportunityId });
            this.toast('Cotización colectiva', 'Comparativo PDF generado y guardado en la oportunidad y en las cotizaciones.', 'success');
            this[NavigationMixin.Navigate]({ type: 'standard__namedPage', attributes: { pageName: 'filePreview' }, state: { selectedRecordId: docId } });
        } catch (e) {
            this.toast('Cotización colectiva', this.mensaje(e), 'error');
        } finally {
            this.cargando = false;
            this.progreso = '';
        }
    }

    // ============================================================
    // Lectura del archivo (siempre con IA)
    // ============================================================
    // Se pueden subir varias cotizaciones a la vez: cada una se lee con la IA y se guarda sola, como las cotizaciones
    // de PDF individuales. Solo quedan para revisión las que no se pudieron completar (sin aseguradora o sin
    // asegurados/ubicaciones).
    async handleArchivo(event) {
        const archivos = Array.from(event.target.files || []);
        event.target.value = null;
        if (!archivos.length) { return; }
        const { vistas, fallas } = await this.leerArchivos(archivos);
        if (fallas.length) { this.toast('Cotización colectiva', fallas.join(' | '), 'error', 'sticky'); }
        await this.crearVistas(vistas);
    }

    // "Crear desde PDFs" de Crear Oportunidad: lee las cotizaciones antes de que exista la oportunidad (detecta el
    // ramo) y regresa lo leído; al guardar la oportunidad, Crear Oportunidad llama a crearCotizaciones.
    @api
    async analizarArchivos(archivos) {
        if (!this.aseguradoras.length) {
            try { this.aseguradoras = await getAseguradoras(); } catch (e) { this.aseguradoras = []; }
        }
        this._detectarRamo = true;
        const { vistas, fallas } = await this.leerArchivos(archivos);
        this._detectarRamo = false;
        this._porCrear = vistas.length;
        const nombre = (id) => ((this.aseguradoras || []).find((a) => a.id === id) || {}).nombre || '';
        return JSON.parse(JSON.stringify({
            ramo: this._ramo,
            fallas,
            vistas,
            resumen: vistas.map((v) => ({
                archivo: v.archivo, contratante: v.contratante, aseguradora: nombre(v.encabezado.aseguradoraId) || v.aseguradoraTexto,
                primaNeta: numero(v.encabezado.primaNeta), primaTotal: this.totalDe(v.encabezado), tamano: this.tamanoDe(v),
                vigenciaDesde: v.encabezado.vigenciaDesde, vigenciaHasta: v.encabezado.vigenciaHasta
            }))
        }));
    }

    // Crea las cotizaciones leídas con analizarArchivos en la oportunidad ya guardada.
    @api
    async crearCotizaciones(vistas, opportunityId) {
        if (opportunityId) { this._opportunityId = opportunityId; }
        this._porCrear = 0;
        await this.crearVistas(JSON.parse(JSON.stringify(vistas || [])));
    }

    get porCrearTxt() {
        return this._porCrear
            ? `Se leyeron ${this._porCrear} ${this._porCrear === 1 ? 'cotización' : 'cotizaciones'}: se crearán al guardar la oportunidad.`
            : '';
    }

    async leerArchivos(archivos) {
        this.errorMensaje = '';
        this.cargando = true;
        const vistas = [];
        const fallas = [];
        try {
            for (let i = 0; i < archivos.length; i++) {
                const file = archivos[i];
                this.archivoNombre = file.name;
                this._prefijo = archivos.length > 1 ? `(${i + 1} de ${archivos.length}) ${file.name}: ` : '';
                try {
                    // eslint-disable-next-line no-await-in-loop
                    vistas.push(await this.leerCotizacion(file));
                } catch (e) {
                    fallas.push(`${file.name}: ${this.mensaje(e)}`);
                }
            }
        } finally {
            this._prefijo = '';
            this.cargando = false;
            this.progreso = '';
        }
        return { vistas, fallas };
    }

    // Guarda las cotizaciones completas; las que no traen aseguradora o asegurados quedan para revisión.
    async crearVistas(vistas) {
        const creadas = [];
        const conAvisos = [];
        const pendientes = [];
        const fallas = [];
        this.cargando = true;
        try {
            for (let i = 0; i < vistas.length; i++) {
                const vista = vistas[i];
                if (!this.completa(vista)) { pendientes.push(vista); continue; }
                this._prefijo = vistas.length > 1 ? `(${i + 1} de ${vistas.length}) ` : '';
                this.avance('Guardando cotización…');
                try {
                    // eslint-disable-next-line no-await-in-loop
                    await this.guardarVista(vista);
                    creadas.push(`${vista.archivo} (${this.tamanoDe(vista)} ${this.unidad})`);
                    if (vista.avisos.length) { conAvisos.push(`${vista.archivo}: ${vista.avisos.join(' ')}`); }
                } catch (e) {
                    fallas.push(`${vista.archivo}: ${this.mensaje(e)}`);
                }
            }
        } finally {
            this._prefijo = '';
            this.cargando = false;
            this.progreso = '';
        }
        if (creadas.length) {
            this.toast('Cotización colectiva', `Cotización creada: ${creadas.join(', ')}.`, 'success');
            await this.cargar();
            this.dispatchEvent(new CustomEvent('cotizacioncreada'));
        }
        if (conAvisos.length) { this.toast('Revisa la cotización creada', conAvisos.join(' | '), 'warning', 'sticky'); }
        if (fallas.length) { this.toast('Cotización colectiva', fallas.join(' | '), 'error', 'sticky'); }
        this._pendientes = pendientes;
        this.siguientePendiente();
    }

    avance(m) { this.progreso = (this._prefijo || '') + m; }

    // Lee el archivo (PDF por partes si es muy largo, o Excel) y lo pasa por la IA; regresa la vista de la cotización.
    async leerCotizacion(file) {
        this.avance('Leyendo archivo…');
        let texto;
        let partes = null;
        let vigencia = { desde: '', hasta: '' };
        if (file.name.toLowerCase().endsWith('.pdf')) {
            const paginas = await paginasPdf(this, file, (m) => this.avance(m));
            texto = paginas.join('\n');
            if (texto.length > MAX_TEXTO) {
                partes = bloquesCompactos(paginas, MAX_TEXTO);
                texto = partes.join('\n');
            }
        } else {
            const tabla = await abrirTabla(file);
            const hojas = tabla.hojas.length ? tabla.hojas : [''];
            const leidas = [];
            for (const h of hojas) { leidas.push({ h, filas: await tabla.leerHoja(h) }); }
            // La hoja con más números (la de primas) va primero; las demás se agregan si caben.
            const numeros = (filas) => filas.reduce((s, f) => s + (f || []).filter((c) => typeof c === 'number').length, 0);
            leidas.sort((a, b) => numeros(b.filas) - numeros(a.filas));
            const partes = [];
            let largo = 0;
            leidas.forEach(({ h, filas }) => {
                const t = tablaATexto(filas, MAX_TEXTO - largo);
                if (t && largo + t.length < MAX_TEXTO) { partes.push((h ? `=== HOJA ${h} ===\n` : '') + t); largo += t.length; }
            });
            texto = partes.join('\n');
            vigencia = buscarVigencia(leidas.flatMap((x) => x.filas.slice(0, 60)));
        }
        if (!texto || texto.trim().length < 50) {
            throw new Error('No se pudo leer texto del archivo (¿PDF escaneado?). Pide la cotización en Excel o en PDF con texto.');
        }
        if (this._detectarRamo) {
            this._ramo = this.ramoPorTexto(texto) || this._ramo;
            this._detectarRamo = false;
        }
        let datos;
        const avisosLectura = [];
        if (partes && partes.length > 1) {
            if (partes.length > MAX_PARTES) {
                avisosLectura.push(`El documento es muy largo: se leyeron sus primeras ${MAX_PARTES} de ${partes.length} partes. `
                    + `Revisa que estén todas las ${this.esUbicaciones ? 'ubicaciones' : 'categorías'}.`);
                partes = partes.slice(0, MAX_PARTES);
            }
            const resultados = [];
            for (let i = 0; i < partes.length; i++) {
                this.avance(`Analizando la cotización con IA (parte ${i + 1} de ${partes.length})…`);
                // eslint-disable-next-line no-await-in-loop
                const json = await analizarCotizacionColectiva({
                    textoCotizacion: `PARTE ${i + 1} DE ${partes.length}\n${partes[i]}`.substring(0, 60000), ramo: this.ramo || null
                });
                resultados.push(this.parsearJsonIA(json));
            }
            datos = this.unirPartes(resultados);
        } else {
            this.avance('Analizando la cotización con IA…');
            const json = await analizarCotizacionColectiva({ textoCotizacion: (partes ? partes[0] : texto).substring(0, 60000), ramo: this.ramo || null });
            datos = this.parsearJsonIA(json);
        }
        const vista = this.normalizar(datos, vigencia, texto);
        vista.avisos.unshift(...avisosLectura);
        vista.archivo = file.name;
        return vista;
    }

    ramoPorTexto(texto) {
        const t = fold(texto.substring(0, 30000));
        let mejor = '';
        let veces = 0;
        RAMOS_TEXTO.forEach(([ramo, re]) => {
            const n = (t.match(re) || []).length;
            if (n > veces) { veces = n; mejor = ramo; }
        });
        return mejor;
    }

    // Lista para crearse sin revisión: trae aseguradora y asegurados (o ubicaciones).
    completa(vista) { return !!vista.encabezado.aseguradoraId && this.tamanoDe(vista) > 0; }

    // Muestra para revisión la siguiente cotización que no se pudo crear sola.
    siguientePendiente() {
        const vista = (this._pendientes || []).shift();
        this.vista = vista || null;
        this.paso = vista ? 'vista' : 'resumen';
        if (vista) {
            this.archivoNombre = vista.archivo;
            this.toast('Cotización colectiva', `Falta la aseguradora o los ${this.unidad} de ${vista.archivo}: revísala y guárdala.`, 'warning');
        }
    }

    // JSON de la IA; si trae operaciones en lugar de números ("962+300.1"), se calculan antes de leerlo.
    parsearJsonIA(texto) {
        try {
            return JSON.parse(texto || '{}');
        } catch (e) {
            // Valor de propiedad o elemento de lista: se repite hasta que no quede ninguna operación.
            const patron = /([:[,]\s*)(-?\d+(?:\.\d+)?(?:\s*[-+*/]\s*\d+(?:\.\d+)?)+)(\s*[,}\]])/g;
            // Un monto con signo de interrogación ("192665?") es un dato dudoso: queda en null.
            let limpio = String(texto).replace(/-?\d+(?:\.\d+)?\?(?=\s*[,}\]])/g, 'null');
            let antes;
            do {
                antes = limpio;
                limpio = limpio.replace(patron, (m, ini, expr, fin) => `${ini}${this.calcular(expr)}${fin}`);
            } while (limpio !== antes);
            try { return JSON.parse(limpio); } catch (e2) {
                throw new Error('La IA respondió en un formato no válido. Intenta de nuevo.');
            }
        }
    }
    // Suma/resta de productos simples, sin eval ("962+300.1", "3*1200-5").
    calcular(expr) {
        const terminos = expr.replace(/\s/g, '').match(/[-+]?[^-+]+/g) || [];
        const total = terminos.reduce((s, t) => {
            const signo = t.startsWith('-') ? -1 : 1;
            const factores = t.replace(/^[-+]/, '').split(/([*/])/);
            let v = Number(factores[0]);
            for (let i = 1; i < factores.length; i += 2) { v = factores[i] === '*' ? v * Number(factores[i + 1]) : v / Number(factores[i + 1]); }
            return s + signo * v;
        }, 0);
        return Math.round(total * 100) / 100;
    }

    // Une lo que devolvió la IA para cada parte de un documento largo: los datos generales se toman de la primera
    // parte que los trae (los montos de la póliza, todos de la misma parte: la del resumen) y las categorías o
    // ubicaciones repetidas en el corte entre partes (mismo nombre) se juntan.
    unirPartes(resultados) {
        const d = { formasPago: [], categorias: [] };
        const vacio = (v) => v === undefined || v === null || v === '';
        const escalares = ['aseguradora', 'ramo', 'contratante', 'numeroCotizacion', 'vigenciaDesde', 'vigenciaHasta', 'formaPago', 'asegurados'];
        const montos = ['primaNeta', 'derechos', 'recargo', 'iva', 'primaTotal'];
        const llave = (c) => fold(c.nombre).replace(/[^a-z0-9]/g, '');
        resultados.forEach((r) => {
            escalares.forEach((k) => { if (vacio(d[k]) && !vacio(r[k])) { d[k] = r[k]; } });
            if (montos.every((k) => vacio(d[k])) && (numero(r.primaNeta) || numero(r.primaTotal))) { montos.forEach((k) => { d[k] = r[k]; }); }
            if (!d.formasPago.length && (r.formasPago || []).some((f) => numero(f.primaTotal) !== null)) { d.formasPago = r.formasPago; }
            (r.categorias || []).forEach((c) => {
                const igual = llave(c) && d.categorias.find((o) => llave(o) === llave(c)
                    && (!o.direccion || !c.direccion || fold(o.direccion).substring(0, 15) === fold(c.direccion).substring(0, 15)));
                if (!igual) { d.categorias.push({ ...c }); return; }
                Object.keys(c).forEach((k) => { if (vacio(igual[k]) && !vacio(c[k]) && !Array.isArray(c[k])) { igual[k] = c[k]; } });
                const conceptos = new Set((igual.parametros || []).map((pm) => fold(pm && pm.concepto)));
                igual.parametros = [...(igual.parametros || []), ...(c.parametros || []).filter((pm) => pm && !conceptos.has(fold(pm.concepto)))];
                igual.coberturasAdicionales = [...new Set([...(igual.coberturasAdicionales || []), ...(c.coberturasAdicionales || [])])];
                if (!(igual.tarifaEdades || []).length) { igual.tarifaEdades = c.tarifaEdades || []; }
                if (!(igual.formasPago || []).length) { igual.formasPago = c.formasPago || []; }
            });
        });
        return d;
    }

    // Revisa y completa lo que devolvió la IA (asegurados contra la tabla de edades, totales por categoría, formas de pago, coaseguro).
    normalizar(d, vigencia, texto) {
        const avisos = [];
        const cats = d.categorias || [];
        const redondear = (n) => Math.round(n * 100) / 100;
        // Prima neta o asegurados de TODA la póliza que la IA puso en una categoría (ej. "PRIMA NETA TOTAL" en la hoja del
        // primer subgrupo): a esa categoría le corresponde el total menos lo de las demás.
        const corregidos = {};
        if (cats.length > 1) {
            ['primaNeta', 'asegurados'].forEach((k) => {
                const total = numero(d[k]);
                if (!total) { return; }
                cats.forEach((c, i) => {
                    const otras = cats.reduce((s, o, j) => s + (j === i ? 0 : numero(o[k]) || 0), 0);
                    if (numero(c[k]) !== null && Math.abs(numero(c[k]) - total) <= total * 0.001 && otras > 0 && otras < total) {
                        corregidos[`${i}.${k}`] = redondear(total - otras);
                    }
                });
            });
        }
        let giro = '';
        const categorias = cats.map((c, i) => {
            const nombre = this.txt(c.nombre).replace(/^inciso\s*:?\s*/i, 'Inciso ') || (this.esUbicaciones ? `Ubicación ${i + 1}` : 'General');
            const tarifa = (c.tarifaEdades || []).map((t, j) => {
                const h = numero(t.hombres) || 0;
                const m = numero(t.mujeres) || 0;
                let total = numero(t.primaTotal);
                if (total === null && (numero(t.primaHombres) !== null || numero(t.primaMujeres) !== null)) {
                    total = (numero(t.primaHombres) || 0) + (numero(t.primaMujeres) || 0);
                }
                if (total === null && numero(t.primaHombre) !== null && numero(t.primaMujer) !== null) {
                    total = h * numero(t.primaHombre) + m * numero(t.primaMujer);
                }
                return { key: `t${i}-${j}`, rango: String(t.rango || ''), hombres: h, mujeres: m,
                    primaHombre: numero(t.primaHombre), primaMujer: numero(t.primaMujer),
                    primaTotal: total === null ? null : redondear(total) };
            }).filter((t) => t.hombres || t.mujeres);
            let hombres = numero(c.hombres);
            let mujeres = numero(c.mujeres);
            let asegurados = corregidos[`${i}.asegurados`] ?? numero(c.asegurados);
            const sumH = tarifa.reduce((s, t) => s + t.hombres, 0);
            const sumM = tarifa.reduce((s, t) => s + t.mujeres, 0);
            // La tabla de edades manda si cuadra con los asegurados impresos de la categoría (o si no vienen); si no
            // cuadra, se conservan los impresos y se avisa para revisar.
            if (tarifa.length && (asegurados === null || sumH + sumM === asegurados)) {
                if (sumH !== hombres || sumM !== mujeres) {
                    avisos.push(`${nombre}: hombres y mujeres tomados de la tabla de edades (${sumH} H / ${sumM} M).`);
                }
                hombres = sumH;
                mujeres = sumM;
                asegurados = sumH + sumM;
            } else if (tarifa.length) {
                avisos.push(`${nombre}: la tabla de edades suma ${sumH + sumM} asegurados (${sumH} H / ${sumM} M) y la cotización indica ${asegurados}. Revisa la categoría.`);
                if (hombres === null || mujeres === null || hombres + mujeres !== asegurados) { hombres = null; mujeres = null; }
            }
            if (asegurados === null && hombres !== null && mujeres !== null) { asegurados = hombres + mujeres; }
            // Sin coberturas no amparadas ni, en GMM, las que repiten un campo fijo del plan (deducible, coaseguro...).
            const parametros = (c.parametros || []).map((pm, j) => ({ key: `p${i}-${j}`, concepto: this.txt(pm && pm.concepto), valor: this.txt(pm && pm.valor) }))
                .filter((pm) => pm.concepto && pm.valor && !NO_AMPARADA.test(fold(pm.valor))
                    && !(this.esGmm && CAMPOS_GMM.test(fold(pm.concepto))));
            // En ubicaciones el giro suele venir solo en la primera de varias seguidas: las siguientes lo heredan.
            let plan = this.txt(c.plan);
            if (this.esUbicaciones) {
                plan = plan.replace(/^giro\s*:?\s*/i, '').replace(/\.$/, '') || giro;
                giro = plan;
            }
            return {
                key: `c${i}`, nombre, asegurados, hombres, mujeres,
                titulares: numero(c.titulares), dependientes: numero(c.dependientes), primaNeta: corregidos[`${i}.primaNeta`] ?? numero(c.primaNeta),
                sumaAseguradaTotal: numero(c.sumaAseguradaTotal), direccion: this.txt(c.direccion), parametros,
                plan, sumaAsegurada: this.txt(c.sumaAsegurada), deducible: this.txt(c.deducible),
                coaseguro: this.porcentajeTxt(c.coaseguro), topeCoaseguro: this.montoTxt(c.topeCoaseguro), tabulador: this.txt(c.tabulador),
                nivelHospitalario: this.txt(c.nivelHospitalario), territorio: this.txt(c.territorio),
                coberturasAdicionales: (c.coberturasAdicionales || []).map((x) => this.txt(x)).filter((x) => x),
                tarifaEdades: tarifa
            };
        });
        if (!categorias.length) {
            throw new Error(this.esUbicaciones ? 'La IA no encontró ubicaciones en la cotización.' : 'La IA no encontró categorías ni asegurados en la cotización.');
        }

        const sumaNeta = categorias.reduce((s, c) => s + (c.primaNeta || 0), 0);
        const primaNeta = numero(d.primaNeta) !== null ? numero(d.primaNeta) : (sumaNeta ? redondear(sumaNeta) : null);
        if (numero(d.primaNeta) !== null && sumaNeta && Math.abs(sumaNeta - primaNeta) / primaNeta > 0.01) {
            avisos.push(`La suma de la prima neta de las ${this.esUbicaciones ? 'ubicaciones' : 'categorías'} (${moneda(sumaNeta)}) no coincide con la prima neta total (${moneda(primaNeta)}).`);
        }
        // Cuando cada categoría trae sus propios gastos, IVA, prima total y formas de pago (una página por categoría),
        // los de la póliza son la suma de las categorías.
        const sumaCategorias = (k) => {
            const v = cats.map((c) => numero(c[k])).filter((x) => x !== null);
            return v.length ? redondear(v.reduce((s, x) => s + x, 0)) : null;
        };
        const deCategoria = cats.filter((c) => (c.formasPago || []).length);
        const formasPago = deCategoria.length > 1 || (!(d.formasPago || []).length && deCategoria.length)
            ? this.sumarFormasPago(deCategoria.map((c) => this.normalizarFormasPago(c.formasPago, numero(c.primaTotal))))
            : this.normalizarFormasPago(d.formasPago || [], numero(d.primaTotal));
        const anual = formasPago.find((f) => /anual|contado/i.test(f.forma));
        const totalPoliza = numero(d.primaTotal) ?? sumaCategorias('primaTotal');
        const encabezado = {
            aseguradoraId: this.aseguradoraPorTexto(`${d.aseguradora || ''} ${this.archivoNombre} ${texto.substring(0, 2000)}`),
            numeroCotizacion: this.txt(d.numeroCotizacion),
            vigenciaDesde: fecha(d.vigenciaDesde).iso || vigencia.desde || '',
            vigenciaHasta: fecha(d.vigenciaHasta).iso || vigencia.hasta || '',
            formaPago: this.capitalizar(d.formaPago) || 'Anual',
            primaNeta,
            derechos: numero(d.derechos) ?? sumaCategorias('derechos'),
            recargo: numero(d.recargo) ?? sumaCategorias('recargo'),
            iva: numero(d.iva) ?? sumaCategorias('iva'),
            primaTotal: totalPoliza !== null ? totalPoliza : (anual && anual.primaTotal ? anual.primaTotal : null)
        };
        // IVA que no se pudo asociar a su columna: la diferencia entre la prima total y la suma de los demás montos,
        // solo si equivale al 16% de esa suma.
        if (encabezado.iva === null && encabezado.primaTotal && encabezado.primaNeta) {
            const base = encabezado.primaNeta + (encabezado.derechos || 0) + (encabezado.recargo || 0);
            const dif = redondear(encabezado.primaTotal - base);
            if (dif > 0 && Math.abs(dif - base * 0.16) <= Math.max(1, base * 0.0005)) { encabezado.iva = dif; }
        }
        if (encabezado.iva === null && this.ramo !== 'Vida') { avisos.push('La cotización no incluye IVA: el comparativo se hará sobre prima neta + derechos.'); }
        return { encabezado, categorias, formasPago, avisos, aseguradoraTexto: this.txt(d.aseguradora), contratante: this.txt(d.contratante) };
    }

    // Total anual de cada forma de pago: primer pago + subsecuentes; si la aseguradora solo da el importe de cada pago, ese × número de pagos.
    // "Pago único" y "Contado" son la forma Anual; un recargo escrito como fracción (0.04) es 4%.
    normalizarFormasPago(lista, totalAnual) {
        const anualFp = lista.find((f) => /anual|contado|unico/i.test(fold(f.forma)));
        const anual = totalAnual || (anualFp ? numero(anualFp.primaTotal) : null);
        const vistas = new Set();
        return lista.map((f, i) => {
            const n = numero(f.numeroPagos) || 1;
            let total = numero(f.primaTotal);
            let primer = numero(f.primerPago);
            const sub = numero(f.pagoSubsecuente);
            if (n > 1 && primer !== null && sub !== null) {
                total = primer + sub * (n - 1);
            } else if (n > 1 && total !== null && anual && total < anual * 0.75) {
                primer = primer !== null ? primer : total;
                total = total * n;
            }
            let pct = numero(f.recargoPct);
            if (pct !== null && pct > 0 && pct < 1) { pct = Math.round(pct * 10000) / 100; }
            const forma = /^(pago unico|contado|de contado|anual.*)$/.test(fold(f.forma)) ? 'Anual' : this.capitalizar(f.forma);
            return { key: `f${i}`, forma, recargoPct: pct, numeroPagos: n,
                primaTotal: total === null ? null : Math.round(total * 100) / 100, primerPago: primer, pagoSubsecuente: sub };
        }).filter((f) => {
            if (!f.forma || vistas.has(f.forma)) { return false; }
            vistas.add(f.forma);
            return true;
        });
    }

    // Formas de pago de la póliza a partir de las de cada categoría: se suman los importes de la misma forma.
    sumarFormasPago(listas) {
        const porForma = new Map();
        const suma = (a, b) => (a === null && b === null ? null : Math.round(((a || 0) + (b || 0)) * 100) / 100);
        listas.flat().forEach((f) => {
            const o = porForma.get(f.forma);
            if (!o) { porForma.set(f.forma, { ...f }); return; }
            o.primaTotal = suma(o.primaTotal, f.primaTotal);
            o.primerPago = suma(o.primerPago, f.primerPago);
            o.pagoSubsecuente = suma(o.pagoSubsecuente, f.pagoSubsecuente);
        });
        return [...porForma.values()].map((f, i) => ({ ...f, key: `f${i}` }));
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

    // ============================================================
    // Vista previa (editable)
    // ============================================================
    get opcionesAseguradora() { return (this.aseguradoras || []).map((a) => ({ label: a.nombre, value: a.id })); }
    get opcionesFormaPago() { return ['Anual', 'Contado', 'Semestral', 'Trimestral', 'Mensual'].map((v) => ({ label: v, value: v })); }
    get enc() { return this.vista ? this.vista.encabezado : {}; }
    get avisos() { return this.vista ? this.vista.avisos.map((a, i) => ({ key: `a${i}`, texto: a })) : []; }
    get hayAvisos() { return this.avisos.length > 0; }
    get categoriasVista() {
        return (this.vista ? this.vista.categorias : []).map((c) => ({
            ...c,
            tarifaTxt: c.tarifaEdades.length ? `${c.tarifaEdades.length} rangos de edad` : 'Sin tabla de edades',
            coberturasTxt: c.coberturasAdicionales.join(' · '),
            parametrosTxt: c.parametros.map((pm) => `${pm.concepto}: ${pm.valor}`).join(' · '),
            hayParametros: c.parametros.length > 0,
            keyOtras: `o${c.key}`
        }));
    }
    get sumaVista() {
        const t = (this.vista ? this.vista.categorias : []).reduce((s, c) => s + (Number(c.sumaAseguradaTotal) || 0), 0);
        return t ? moneda(t) : '';
    }
    get formasPagoVista() {
        return (this.vista ? this.vista.formasPago : []).map((f) => ({
            ...f, totalTxt: moneda(f.primaTotal) || '—', recargoTxt: f.recargoPct ? `${f.recargoPct}%` : '—',
            primerTxt: moneda(f.primerPago) || '—'
        }));
    }
    get hayFormasPagoVista() { return this.formasPagoVista.length > 0; }
    get aseguradosVista() { return this.vista ? this.tamanoDe(this.vista) : 0; }
    tamanoDe(vista) {
        const cats = vista.categorias;
        return this.esUbicaciones ? cats.length : cats.reduce((s, c) => s + (Number(c.asegurados) || 0), 0);
    }
    get etiquetaTamanoVista() { return this.esUbicaciones ? 'Ubicaciones' : 'Asegurados'; }
    get totalCalculado() { return this.totalDe(this.enc); }
    totalDe(e) {
        if (numero(e.primaTotal) !== null) { return numero(e.primaTotal); }
        if (numero(e.primaNeta) === null) { return null; }
        return ['primaNeta', 'derechos', 'recargo', 'iva'].reduce((s, k) => s + (numero(e[k]) || 0), 0);
    }
    get totalVista() { return moneda(this.totalCalculado) || '—'; }
    get faltaAseguradora() { return !this.enc.aseguradoraId; }
    get sinGuardar() { return this.cargando || !this.enc.aseguradoraId || !this.aseguradosVista; }

    handleEncabezado(event) {
        const campo = event.target.dataset.campo;
        const montos = ['primaNeta', 'derechos', 'recargo', 'iva', 'primaTotal'];
        const valor = montos.includes(campo) ? numero(event.detail.value) : event.detail.value;
        this.vista = { ...this.vista, encabezado: { ...this.vista.encabezado, [campo]: valor } };
    }
    handleCategoria(event) {
        const idx = Number(event.target.dataset.index);
        const campo = event.target.dataset.campo;
        const numericos = ['asegurados', 'hombres', 'mujeres', 'primaNeta', 'sumaAseguradaTotal'];
        const valor = numericos.includes(campo) ? numero(event.detail.value) : event.detail.value;
        const categorias = this.vista.categorias.map((c, i) => {
            if (i !== idx) { return c; }
            const nueva = { ...c, [campo]: valor };
            if (campo === 'hombres' || campo === 'mujeres') { nueva.asegurados = (Number(nueva.hombres) || 0) + (Number(nueva.mujeres) || 0); }
            return nueva;
        });
        this.vista = { ...this.vista, categorias };
    }

    // Descarta la cotización en revisión y pasa a la siguiente pendiente, si hay.
    cancelar() {
        this.errorMensaje = '';
        this.siguientePendiente();
    }

    async guardar() {
        this.cargando = true;
        this.progreso = 'Guardando cotización…';
        try {
            await this.guardarVista(this.vista);
            this.toast('Cotización colectiva', `Cotización guardada: ${this.aseguradosVista} ${this.unidad}.`, 'success');
            await this.cargar();
            this.dispatchEvent(new CustomEvent('cotizacioncreada'));
            this.siguientePendiente();
        } catch (err) {
            this.toast('Cotización colectiva', this.mensaje(err), 'error');
        } finally {
            this.cargando = false;
            this.progreso = '';
        }
    }

    guardarVista(vista) {
        const e = vista.encabezado;
        const datos = {
            aseguradoraId: e.aseguradoraId, numeroCotizacion: e.numeroCotizacion || null,
            vigenciaDesde: e.vigenciaDesde || null, vigenciaHasta: e.vigenciaHasta || null, formaPago: e.formaPago || null,
            primaNeta: numero(e.primaNeta), derechos: numero(e.derechos), recargo: numero(e.recargo), iva: numero(e.iva),
            primaTotal: this.totalDe(e), archivo: vista.archivo,
            formasPago: vista.formasPago.map(({ key, ...f }) => f),
            categorias: vista.categorias.map(({ key, tarifaEdades, parametros, ...c }) => ({
                ...c, tarifaEdades: tarifaEdades.map(({ key: k, ...t }) => t), parametros: parametros.map(({ key: k, ...pm }) => pm)
            }))
        };
        return guardarCotizacionColectiva({ opportunityId: this._opportunityId, datosJson: JSON.stringify(datos) });
    }

    // ============================================================
    // Utilidades
    // ============================================================
    txt(v) { return v === undefined || v === null ? '' : String(v).replace(/\s+/g, ' ').trim(); }
    capitalizar(v) {
        const t = this.txt(v).toLowerCase();
        return t ? t.charAt(0).toUpperCase() + t.slice(1) : '';
    }
    // "0.1" -> "10%", "10" -> "10%", "10.00%" -> "10%".
    porcentajeTxt(v) {
        const t = this.txt(v);
        if (!t) { return ''; }
        const n = numero(t);
        if (n === null || /[a-z]/i.test(t)) { return t; }
        const pct = n > 0 && n <= 1 && !t.includes('%') ? n * 100 : n;
        return `${Math.round(pct * 100) / 100}%`;
    }
    // "60000 MXP" -> "$60,000"; textos (UMAM, SMGM) se conservan.
    montoTxt(v) {
        const t = this.txt(v);
        if (!t) { return ''; }
        if (/uma|smg|salario|mes/i.test(t)) { return t; }
        const n = numero(t);
        return n === null ? t : moneda(n);
    }
    mensaje(e) {
        return (e && e.body && e.body.message) || (e && e.message) || 'Ocurrió un error inesperado.';
    }
    toast(title, message, variant, mode) {
        this.errorMensaje = variant === 'error' ? message : '';
        this.dispatchEvent(new ShowToastEvent({ title, message, variant, mode: mode || 'dismissible' }));
    }
}
