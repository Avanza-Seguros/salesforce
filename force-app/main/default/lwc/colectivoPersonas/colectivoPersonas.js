/**
 * @creation date: 14/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Cotizaciones colectivas por aseguradora. Ramos de PERSONAS (GMM, Vida Grupo, Accidentes Personales,
 *               Dental, Visión, Viajes): categorías con asegurados, plan, coberturas y tarifa por edad. Ramos de
 *               UBICACIONES (Daños, Empresarial): una fila por inmueble con dirección, valor asegurado, prima y coberturas.
 *               El agente sube la cotización de cada aseguradora (PDF, o Excel que se convierte a texto en el navegador);
 *               la IA la lee, el agente revisa/corrige y se guarda con ColectivoController (Quote + Categoria_Colectiva__c).
 *               Muestra el comparativo (con cuota al millar cuando hay suma asegurada) y genera el PDF.
 */
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import { NavigationMixin } from 'lightning/navigation';
import { fold, numero, fecha, fechaVisible, moneda, abrirTabla, bloquesPdf, tablaATexto, buscarVigencia } from 'c/lectorArchivos';
import getAseguradoras from '@salesforce/apex/FlotillaController.getAseguradoras';
import getCotizacionesColectivas from '@salesforce/apex/ColectivoController.getCotizacionesColectivas';
import guardarCotizacionColectiva from '@salesforce/apex/ColectivoController.guardarCotizacionColectiva';
import eliminarCotizacionColectiva from '@salesforce/apex/ColectivoController.eliminarCotizacionColectiva';
import analizarCotizacionColectiva from '@salesforce/apex/ColectivoController.analizarCotizacionColectiva';
import generarComparativoPdf from '@salesforce/apex/ColectivoController.generarComparativoPdf';

// Palabras que no sirven para reconocer a la aseguradora en el texto.
const GENERICAS = new Set(['seguros', 'seguro', 'compania', 'mexico', 'grupo', 'life', 'general', 'generales', 'de', 'cv', 'sa', 'del', 'corporativos']);
// Texto máximo que se manda a la IA (una sola llamada: la cotización se lee completa).
const MAX_TEXTO = 55000;
// Parámetros del plan que se comparan (clave en la categoría -> etiqueta).
const PLAN = [
    ['plan', 'Plan'], ['sumaAsegurada', 'Suma asegurada'], ['deducible', 'Deducible'], ['coaseguro', 'Coaseguro'],
    ['topeCoaseguro', 'Tope de coaseguro'], ['tabulador', 'Tabulador / círculo médico'], ['nivelHospitalario', 'Nivel hospitalario'],
    ['territorio', 'Territorio']
];
// Ramos en los que cada renglón de la cotización es una ubicación (inmueble) y no un grupo de personas.
const RAMOS_UBICACIONES = ['Danos', 'Empresarial'];
// Valor de una cobertura (ya pasado por fold) que indica que no se incluye: "N/A", "No amparada", "Excluida", "-".
const NO_AMPARADA = /^(n a|na|no amparad[ao]s?|no aplica|excluid[ao]s?|no incluid[ao]s?|)$/;
// Coberturas que en GMM ya son campos fijos del plan.
const CAMPOS_GMM = /^(plan|suma asegurada|deducible|coaseguro|tope|tabulador|nivel hospitalario|hospitales|territorio|cobertura territori)/;

export default class ColectivoPersonas extends NavigationMixin(LightningElement) {
    @api readOnly = false;
    // Valor del picklist Ramo de la oportunidad (GMM, Vida, Accidentes Personales, Danos, ...).
    @api ramo;

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
            ? 'PDF o Excel (.xlsx, .xlsm, CSV). La IA lee las ubicaciones (dirección, valor asegurado y prima), las coberturas con sus deducibles y las formas de pago; revisas antes de guardar.'
            : 'PDF o Excel (.xlsx, .xlsm, CSV). La IA lee categorías, asegurados, suma asegurada, coberturas, primas, formas de pago y la tabla de edades; revisas antes de guardar.';
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
                clase: esMejor ? 'tarjeta tarjeta_mejor' : 'tarjeta'
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
    async handleArchivo(event) {
        const file = event.target.files && event.target.files[0];
        event.target.value = null;
        if (!file) { return; }
        this.archivoNombre = file.name;
        this.errorMensaje = '';
        this.cargando = true;
        this.progreso = 'Leyendo archivo…';
        try {
            let texto;
            let vigencia = { desde: '', hasta: '' };
            if (file.name.toLowerCase().endsWith('.pdf')) {
                const bloques = await bloquesPdf(this, file, MAX_TEXTO, (m) => { this.progreso = m; });
                texto = bloques.join('\n');
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
            this.progreso = 'Analizando la cotización con IA…';
            const json = await analizarCotizacionColectiva({ textoCotizacion: texto.substring(0, 60000), ramo: this.ramo || null });
            const datos = this.parsearJsonIA(json);
            this.vista = this.normalizar(datos, vigencia, texto);
            this.paso = 'vista';
        } catch (e) {
            this.toast('Cotización colectiva', this.mensaje(e), 'error');
        } finally {
            this.cargando = false;
            this.progreso = '';
        }
    }

    // JSON de la IA; si trae operaciones en lugar de números ("962+300.1"), se calculan antes de leerlo.
    parsearJsonIA(texto) {
        try {
            return JSON.parse(texto || '{}');
        } catch (e) {
            // Valor de propiedad o elemento de lista: se repite hasta que no quede ninguna operación.
            const patron = /([:[,]\s*)(-?\d+(?:\.\d+)?(?:\s*[-+*/]\s*\d+(?:\.\d+)?)+)(\s*[,}\]])/g;
            let limpio = String(texto);
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

    // Revisa y completa lo que devolvió la IA (asegurados contra la tabla de edades, formas de pago, coaseguro).
    normalizar(d, vigencia, texto) {
        const avisos = [];
        const categorias = (d.categorias || []).map((c, i) => {
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
                    primaTotal: total === null ? null : Math.round(total * 100) / 100 };
            }).filter((t) => t.hombres || t.mujeres);
            let hombres = numero(c.hombres);
            let mujeres = numero(c.mujeres);
            let asegurados = numero(c.asegurados);
            const sumH = tarifa.reduce((s, t) => s + t.hombres, 0);
            const sumM = tarifa.reduce((s, t) => s + t.mujeres, 0);
            if (tarifa.length && (sumH !== hombres || sumM !== mujeres || sumH + sumM !== asegurados)) {
                avisos.push(`${c.nombre || 'Categoría'}: asegurados ajustados con la tabla de edades (${sumH} H / ${sumM} M).`);
                hombres = sumH;
                mujeres = sumM;
                asegurados = sumH + sumM;
            }
            if (asegurados === null && hombres !== null && mujeres !== null) { asegurados = hombres + mujeres; }
            // Sin coberturas no amparadas ni, en GMM, las que repiten un campo fijo del plan (deducible, coaseguro...).
            const parametros = (c.parametros || []).map((pm, j) => ({ key: `p${i}-${j}`, concepto: this.txt(pm && pm.concepto), valor: this.txt(pm && pm.valor) }))
                .filter((pm) => pm.concepto && pm.valor && !NO_AMPARADA.test(fold(pm.valor))
                    && !(this.esGmm && CAMPOS_GMM.test(fold(pm.concepto))));
            return {
                key: `c${i}`, nombre: c.nombre || (this.esUbicaciones ? `Ubicación ${i + 1}` : 'General'), asegurados, hombres, mujeres,
                titulares: numero(c.titulares), dependientes: numero(c.dependientes), primaNeta: numero(c.primaNeta),
                sumaAseguradaTotal: numero(c.sumaAseguradaTotal), direccion: this.txt(c.direccion), parametros,
                plan: this.txt(c.plan), sumaAsegurada: this.txt(c.sumaAsegurada), deducible: this.txt(c.deducible),
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
        const primaNeta = numero(d.primaNeta) !== null ? numero(d.primaNeta) : (sumaNeta || null);
        if (numero(d.primaNeta) !== null && sumaNeta && Math.abs(sumaNeta - primaNeta) / primaNeta > 0.01) {
            avisos.push(`La suma de la prima neta de las categorías (${moneda(sumaNeta)}) no coincide con la prima neta total (${moneda(primaNeta)}).`);
        }
        const formasPago = this.normalizarFormasPago(d.formasPago || [], numero(d.primaTotal));
        const anual = formasPago.find((f) => /anual|contado/i.test(f.forma));
        const encabezado = {
            aseguradoraId: this.aseguradoraPorTexto(`${d.aseguradora || ''} ${this.archivoNombre} ${texto.substring(0, 2000)}`),
            numeroCotizacion: this.txt(d.numeroCotizacion),
            vigenciaDesde: fecha(d.vigenciaDesde).iso || vigencia.desde || '',
            vigenciaHasta: fecha(d.vigenciaHasta).iso || vigencia.hasta || '',
            formaPago: this.capitalizar(d.formaPago) || 'Anual',
            primaNeta,
            derechos: numero(d.derechos),
            recargo: numero(d.recargo),
            iva: numero(d.iva),
            primaTotal: numero(d.primaTotal) !== null ? numero(d.primaTotal) : (anual && anual.primaTotal ? anual.primaTotal : null)
        };
        if (encabezado.iva === null && this.ramo !== 'Vida') { avisos.push('La cotización no incluye IVA: el comparativo se hará sobre prima neta + derechos.'); }
        return { encabezado, categorias, formasPago, avisos, aseguradoraTexto: this.txt(d.aseguradora), contratante: this.txt(d.contratante) };
    }

    // Total anual de cada forma de pago: primer pago + subsecuentes; si la aseguradora solo da el importe de cada pago, ese × número de pagos.
    normalizarFormasPago(lista, totalAnual) {
        const anualFp = lista.find((f) => /anual|contado/i.test(f.forma || ''));
        const anual = totalAnual || (anualFp ? numero(anualFp.primaTotal) : null);
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
            return { key: `f${i}`, forma: this.capitalizar(f.forma), recargoPct: numero(f.recargoPct), numeroPagos: n,
                primaTotal: total === null ? null : Math.round(total * 100) / 100, primerPago: primer, pagoSubsecuente: sub };
        }).filter((f) => f.forma);
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
    get aseguradosVista() {
        const cats = this.vista ? this.vista.categorias : [];
        return this.esUbicaciones ? cats.length : cats.reduce((s, c) => s + (Number(c.asegurados) || 0), 0);
    }
    get etiquetaTamanoVista() { return this.esUbicaciones ? 'Ubicaciones' : 'Asegurados'; }
    get totalCalculado() {
        const e = this.enc;
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

    cancelar() {
        this.errorMensaje = '';
        this.vista = null;
        this.paso = 'resumen';
    }

    async guardar() {
        const e = this.enc;
        this.cargando = true;
        this.progreso = 'Guardando cotización…';
        try {
            const datos = {
                aseguradoraId: e.aseguradoraId, numeroCotizacion: e.numeroCotizacion || null,
                vigenciaDesde: e.vigenciaDesde || null, vigenciaHasta: e.vigenciaHasta || null, formaPago: e.formaPago || null,
                primaNeta: numero(e.primaNeta), derechos: numero(e.derechos), recargo: numero(e.recargo), iva: numero(e.iva),
                primaTotal: this.totalCalculado, archivo: this.archivoNombre,
                formasPago: this.vista.formasPago.map(({ key, ...f }) => f),
                categorias: this.vista.categorias.map(({ key, tarifaEdades, parametros, ...c }) => ({
                    ...c, tarifaEdades: tarifaEdades.map(({ key: k, ...t }) => t), parametros: parametros.map(({ key: k, ...pm }) => pm)
                }))
            };
            await guardarCotizacionColectiva({ opportunityId: this._opportunityId, datosJson: JSON.stringify(datos) });
            this.toast('Cotización colectiva', `Cotización guardada: ${this.aseguradosVista} ${this.unidad}.`, 'success');
            this.cancelar();
            await this.cargar();
            this.dispatchEvent(new CustomEvent('cotizacioncreada'));
        } catch (err) {
            this.toast('Cotización colectiva', this.mensaje(err), 'error');
        } finally {
            this.cargando = false;
            this.progreso = '';
        }
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
    toast(title, message, variant) {
        this.errorMensaje = variant === 'error' ? message : '';
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
