/**
 * @creation date: 12/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Utilidades compartidas para leer archivos en el navegador (sin librerías externas):
 *               Excel .xlsx (ZIP + XML con DecompressionStream), CSV, texto de PDF (pdf.js), detección
 *               del renglón de encabezados, mapeo automático de columnas y conversión de fechas/números.
 *               Lo usan censoColectivo (asegurados) y flotillaColectiva (incisos de Auto).
 */
import { loadScript } from 'lightning/platformResourceLoader';
import PDFJS from '@salesforce/resourceUrl/pdfjs';
import fontsResource from '@salesforce/resourceUrl/fuentes_pdf';

const MESES = { ene: 1, jan: 1, feb: 2, mar: 3, abr: 4, apr: 4, may: 5, jun: 6, jul: 7, ago: 8, aug: 8, sep: 9, set: 9, oct: 10, nov: 11, dic: 12, dec: 12 };

// ============================================================
// Texto, números y fechas
// ============================================================

// Texto en minúsculas, sin acentos ni signos (solo letras, números y espacios).
export function fold(v) {
    return (v === undefined || v === null ? '' : String(v)).toLowerCase().normalize('NFD')
        .replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, ' ').trim();
}

// Caracteres de Windows-1252 (0x80-0x9F) que no coinciden con su código Unicode.
const CP1252 = {
    '\u20AC': 0x80, '\u201A': 0x82, '\u0192': 0x83, '\u201E': 0x84, '\u2026': 0x85, '\u2020': 0x86, '\u2021': 0x87,
    '\u02C6': 0x88, '\u2030': 0x89, '\u0160': 0x8A, '\u2039': 0x8B, '\u0152': 0x8C, '\u017D': 0x8E, '\u2018': 0x91,
    '\u2019': 0x92, '\u201C': 0x93, '\u201D': 0x94, '\u2022': 0x95, '\u2013': 0x96, '\u2014': 0x97, '\u02DC': 0x98,
    '\u2122': 0x99, '\u0161': 0x9A, '\u203A': 0x9B, '\u0153': 0x9C, '\u017E': 0x9E, '\u0178': 0x9F
};

// Repara texto con acentos mal codificados (UTF-8 leído como Windows-1252/Latin-1), ej. "DAÃ‘OS" -> "DAÑOS".
// Si el texto no es un caso así (o no se puede convertir), se regresa sin cambios.
export function repararTexto(v) {
    if (typeof v !== 'string' || !/[\u00C3\u00C2]./.test(v)) { return v; }
    try {
        const bytes = Uint8Array.from(v, (ch) => {
            if (CP1252[ch] !== undefined) { return CP1252[ch]; }
            const c = ch.charCodeAt(0);
            if (c > 255) { throw new Error('no es Windows-1252'); }
            return c;
        });
        return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    } catch (e) {
        return v;
    }
}

export function tieneDatos(fila) {
    return (fila || []).some((c) => String(c ?? '').trim() !== '');
}

// Número desde texto ("$45,000.00", "5 %") o número; null si no es válido.
export function numero(v) {
    if (v === undefined || v === null || v === '') { return null; }
    if (typeof v === 'number') { return isNaN(v) ? null : v; }
    const s = String(v).replace(/[^0-9.,-]/g, '').replace(/,/g, '');
    if (!s || isNaN(Number(s))) { return null; }
    return Number(s);
}

// Fecha a "YYYY-MM-DD": número de serie de Excel, ISO, dd/mm/aaaa, dd-mm-aa o 15-ENE-1980.
export function fecha(v) {
    if (v === undefined || v === null || String(v).trim() === '') { return { iso: '' }; }
    const pad = (n) => String(n).padStart(2, '0');
    const armar = (a, m, d) => {
        if (a < 100) { a += (a > (new Date().getFullYear() % 100) + 10 ? 1900 : 2000); }
        const f = new Date(Date.UTC(a, m - 1, d));
        if (f.getUTCFullYear() !== a || f.getUTCMonth() !== m - 1 || f.getUTCDate() !== d || a < 1900 || a > 2100) { return null; }
        return `${a}-${pad(m)}-${pad(d)}`;
    };
    const s = String(v).trim();
    let iso = null;
    if (typeof v === 'number' || /^\d{4,5}(\.\d+)?$/.test(s)) {
        const n = Number(s);
        if (n > 0 && n < 80000) {
            const f = new Date(Date.UTC(1899, 11, 30) + Math.floor(n) * 86400000);
            iso = `${f.getUTCFullYear()}-${pad(f.getUTCMonth() + 1)}-${pad(f.getUTCDate())}`;
        }
    } else {
        let m = s.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})/);
        if (m) { iso = armar(+m[1], +m[2], +m[3]); }
        if (!iso && (m = s.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})$/))) {
            let d = +m[1];
            let mes = +m[2];
            if (mes > 12 && d <= 12) { [d, mes] = [mes, d]; }
            iso = armar(+m[3], mes, d);
        }
        if (!iso && (m = fold(s).match(/^(\d{1,2}) ?([a-z]{3})[a-z]* ?(\d{2,4})$/))) {
            if (MESES[m[2]]) { iso = armar(+m[3], MESES[m[2]], +m[1]); }
        }
    }
    return iso ? { iso } : { iso: '', invalida: true };
}

export function fechaVisible(iso) {
    if (!iso) { return ''; }
    const [a, m, d] = String(iso).substring(0, 10).split('-');
    return `${d}/${m}/${a}`;
}

export function moneda(n) {
    if (n === null || n === undefined || n === '' || Number(n) === 0) { return ''; }
    return new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN', maximumFractionDigits: 0 }).format(Number(n));
}

export function letraColumna(i) {
    let s = '';
    let n = i + 1;
    while (n > 0) { const r = (n - 1) % 26; s = String.fromCharCode(65 + r) + s; n = Math.floor((n - 1) / 26); }
    return s;
}

function indiceColumna(ref) {
    const letras = ref.replace(/[0-9]/g, '').toUpperCase();
    let n = 0;
    for (let i = 0; i < letras.length; i++) { n = n * 26 + (letras.charCodeAt(i) - 64); }
    return n - 1;
}

// ============================================================
// Tablas (Excel / CSV)
// ============================================================

/**
 * Abre un archivo de tabla. Devuelve { hojas: [nombres], leerHoja(nombre) -> filas[][] }.
 * Formatos binarios antiguos (.xls, .xlsb) no se pueden leer en el navegador: se pide guardarlos como .xlsx.
 */
export async function abrirTabla(file) {
    const ext = file.name.toLowerCase().split('.').pop();
    if (ext === 'xls' || ext === 'xlsb') {
        throw new Error(`El formato .${ext} de Excel no se puede leer aquí. Ábrelo en Excel y usa "Guardar como" → Libro de Excel (.xlsx) o CSV.`);
    }
    if (ext === 'xlsx' || ext === 'xlsm') {
        const x = await abrirXlsx(await file.arrayBuffer());
        return { hojas: x.hojas.map((h) => h.nombre), leerHoja: (nombre) => leerHojaXlsx(x, nombre) };
    }
    if (ext === 'csv' || ext === 'txt') {
        const filas = leerCsv(decodificar(await file.arrayBuffer())).map((f) => f.map(repararTexto));
        return { hojas: [], leerHoja: async () => filas };
    }
    throw new Error('Formato no soportado. Usa Excel (.xlsx), CSV o PDF.');
}

function decodificar(buffer) {
    const utf8 = new TextDecoder('utf-8').decode(buffer);
    return utf8.includes('�') ? new TextDecoder('windows-1252').decode(buffer) : utf8;
}

export function leerCsv(texto) {
    const t = texto.replace(/^﻿/, '');
    const primera = t.split(/\r?\n/)[0] || '';
    const sep = [',', ';', '\t', '|'].reduce((a, b) => (primera.split(b).length > primera.split(a).length ? b : a), ',');
    const filas = [];
    let fila = [];
    let celda = '';
    let comillas = false;
    for (let i = 0; i < t.length; i++) {
        const ch = t[i];
        if (comillas) {
            if (ch === '"' && t[i + 1] === '"') { celda += '"'; i++; }
            else if (ch === '"') { comillas = false; }
            else { celda += ch; }
        } else if (ch === '"') {
            comillas = true;
        } else if (ch === sep) {
            fila.push(celda); celda = '';
        } else if (ch === '\n' || ch === '\r') {
            if (ch === '\r' && t[i + 1] === '\n') { i++; }
            fila.push(celda); filas.push(fila); fila = []; celda = '';
        } else {
            celda += ch;
        }
    }
    if (celda !== '' || fila.length) { fila.push(celda); filas.push(fila); }
    return filas;
}

// Lector mínimo de .xlsx: el archivo es un ZIP con XML. Se descomprime con DecompressionStream.
async function abrirXlsx(buffer) {
    const dv = new DataView(buffer);
    const u8 = new Uint8Array(buffer);
    let eocd = -1;
    for (let i = buffer.byteLength - 22; i >= Math.max(0, buffer.byteLength - 65557); i--) {
        if (dv.getUint32(i, true) === 0x06054b50) { eocd = i; break; }
    }
    if (eocd < 0) { throw new Error('El archivo no es un Excel válido (.xlsx).'); }
    const total = dv.getUint16(eocd + 10, true);
    let p = dv.getUint32(eocd + 16, true);
    const entradas = {};
    const dec = new TextDecoder('utf-8');
    for (let k = 0; k < total && dv.getUint32(p, true) === 0x02014b50; k++) {
        const nLen = dv.getUint16(p + 28, true);
        const nombre = dec.decode(u8.subarray(p + 46, p + 46 + nLen));
        entradas[nombre] = { metodo: dv.getUint16(p + 10, true), tam: dv.getUint32(p + 20, true), local: dv.getUint32(p + 42, true) };
        p += 46 + nLen + dv.getUint16(p + 30, true) + dv.getUint16(p + 32, true);
    }
    const leer = async (nombre) => {
        const e = entradas[nombre];
        if (!e) { return null; }
        const ini = e.local + 30 + dv.getUint16(e.local + 26, true) + dv.getUint16(e.local + 28, true);
        const datos = u8.subarray(ini, ini + e.tam);
        if (e.metodo === 0) { return dec.decode(datos); }
        if (typeof DecompressionStream === 'undefined') {
            throw new Error('Este navegador no puede leer .xlsx. Guarda el archivo como CSV e inténtalo de nuevo.');
        }
        const reader = new Blob([datos]).stream().pipeThrough(new DecompressionStream('deflate-raw')).getReader();
        const partes = [];
        let largo = 0;
        for (;;) {
            const { done, value } = await reader.read();
            if (done) { break; }
            partes.push(value);
            largo += value.length;
        }
        const out = new Uint8Array(largo);
        let o = 0;
        partes.forEach((x) => { out.set(x, o); o += x.length; });
        return dec.decode(out);
    };
    const xml = (s) => new DOMParser().parseFromString(s || '<x/>', 'application/xml');
    const tags = (nodo, n) => Array.from(nodo.getElementsByTagNameNS('*', n));

    const rels = {};
    tags(xml(await leer('xl/_rels/workbook.xml.rels')), 'Relationship').forEach((r) => {
        const t = r.getAttribute('Target') || '';
        rels[r.getAttribute('Id')] = t.startsWith('/') ? t.substring(1) : 'xl/' + t;
    });
    const hojas = tags(xml(await leer('xl/workbook.xml')), 'sheet').map((s) => ({
        nombre: s.getAttribute('name'),
        ruta: rels[s.getAttribute('r:id') || s.getAttributeNS('http://schemas.openxmlformats.org/officeDocument/2006/relationships', 'id')]
    })).filter((h) => h.ruta);
    if (!hojas.length && entradas['xl/worksheets/sheet1.xml']) { hojas.push({ nombre: 'Hoja 1', ruta: 'xl/worksheets/sheet1.xml' }); }
    if (!hojas.length) { throw new Error('El Excel no tiene hojas.'); }
    const compartidos = tags(xml(await leer('xl/sharedStrings.xml')), 'si')
        .map((si) => tags(si, 't').map((t) => t.textContent).join(''));
    return { hojas, leer, xml, tags, compartidos };
}

async function leerHojaXlsx(x, nombre) {
    const hoja = x.hojas.find((h) => h.nombre === nombre) || x.hojas[0];
    const doc = x.xml(await x.leer(hoja.ruta));
    const filas = [];
    x.tags(doc, 'row').forEach((row) => {
        const fila = [];
        let siguiente = 0;
        x.tags(row, 'c').forEach((c) => {
            const ref = c.getAttribute('r');
            const col = ref ? indiceColumna(ref) : siguiente;
            siguiente = col + 1;
            const tipo = c.getAttribute('t');
            const v = x.tags(c, 'v')[0];
            let valor = v ? v.textContent : '';
            if (tipo === 's') { valor = x.compartidos[Number(valor)] ?? ''; }
            else if (tipo === 'inlineStr') { valor = x.tags(c, 't').map((t) => t.textContent).join(''); }
            else if (tipo === 'b') { valor = valor === '1' ? 'VERDADERO' : 'FALSO'; }
            else if (tipo !== 'str' && tipo !== 'e' && valor !== '' && !isNaN(Number(valor))) { valor = Number(valor); }
            if (tipo === 'e') { valor = ''; }
            fila[col] = repararTexto(valor);
        });
        const r = Number(row.getAttribute('r'));
        filas[r ? r - 1 : filas.length] = Array.from(fila, (c) => (c === undefined ? '' : c));
    });
    return Array.from(filas, (f) => f || []);
}

// ============================================================
// Encabezados y mapeo de columnas
// ============================================================

// Etiquetas de una columna: el encabezado y el encabezado combinado con el renglón de arriba
// (muchas cotizaciones usan dos renglones, ej. "VALOR" / "CONVENIDO").
// El renglón de arriba solo cuenta si también parece encabezado (2+ celdas); un título no se combina.
// Las celdas numéricas (fechas, montos) de ese renglón no son parte del encabezado.
function filaArriba(filas, h) {
    const f = (h > 0 ? (filas[h - 1] || []) : []).map((c) => (numero(c) !== null && !/[a-z]/i.test(String(c)) ? '' : c));
    return f.filter((c) => String(c ?? '').trim() !== '').length >= 2 ? f : [];
}

// Renglones debajo del encabezado que lo continúan (ej. "PRIMA" / "NETA", "RESPONSABILIDAD" / "CIVIL" /
// "TERCEROS"): solo texto (sin números), con menos celdas que el encabezado y hasta 2 renglones.
export function renglonesEncabezadoAbajo(filas, h) {
    const llenas = (f) => (f || []).filter((c) => String(c ?? '').trim() !== '');
    const enc = llenas(filas[h]).length;
    let k = 0;
    for (let r = h + 1; r <= h + 2 && r < filas.length - 1; r++) {
        const celdas = llenas(filas[r]);
        const soloTexto = celdas.every((c) => numero(c) === null || /[a-z]{2,}/i.test(String(c)));
        if (!celdas.length || !soloTexto || celdas.length >= enc) { break; }
        k++;
    }
    return k;
}

// Índice del primer renglón de datos (después del encabezado y sus continuaciones).
export function inicioDatos(filas, h) {
    return h + 1 + renglonesEncabezadoAbajo(filas, h);
}

function filasAbajo(filas, h) {
    const k = renglonesEncabezadoAbajo(filas, h);
    return filas.slice(h + 1, h + 1 + k);
}

// true si la columna trae sobre todo números en los primeros renglones de datos.
function columnaNumerica(filas, h, col) {
    const valores = filas.slice(inicioDatos(filas, h), inicioDatos(filas, h) + 40).map((f) => (f || [])[col]).filter((v) => String(v ?? '').trim() !== '').slice(0, 8);
    if (!valores.length) { return true; }
    return valores.filter((v) => numero(v) !== null && !/[a-z]{3,}/i.test(String(v))).length >= valores.length / 2;
}

// Etiquetas de una columna: sola, con lo de abajo (continuación) y con el renglón de arriba.
function etiquetas(filas, h, col) {
    const solo = fold((filas[h] || [])[col]);
    const arriba = fold(filaArriba(filas, h)[col]);
    const abajo = filasAbajo(filas, h).map((f) => fold((f || [])[col])).filter((x) => x).join(' ');
    const conAbajo = [solo, abajo].filter((x) => x).join(' ');
    const combinada = [arriba, solo, abajo].filter((x) => x).join(' ');
    return { solo, conAbajo, combinada };
}

function puntaje(etiqueta, alias) {
    if (!etiqueta) { return 0; }
    if (etiqueta === alias) { return 100 + alias.length; }
    if (alias.length >= 4 && (` ${etiqueta} `).includes(` ${alias} `)) { return 50 + alias.length; }
    return 0;
}

// Renglón (de los primeros 30) con más encabezados reconocidos; el primero con datos si no hay.
export function detectarEncabezado(filas, campos) {
    const primero = Math.max(0, filas.findIndex((f) => tieneDatos(f)));
    let mejor = primero;
    let puntos = 0;
    const todos = new Set(campos.flatMap((c) => c.alias));
    for (let i = 0; i < Math.min(filas.length, 30); i++) {
        const p = (filas[i] || []).filter((c) => todos.has(fold(c))).length;
        if (p > puntos) { puntos = p; mejor = i; }
    }
    return puntos >= 2 ? mejor : primero;
}

/**
 * Propone a qué columna va cada campo: { campo: 'índice de columna' }.
 * Cada campo tiene alias (encabezados conocidos) y opcionalmente "excluir" (palabras que descartan la columna).
 */
export function mapeoAutomatico(filas, h, campos) {
    const ancho = Math.max(...filas.slice(Math.max(0, h - 1), inicioDatos(filas, h)).map((f) => (f || []).length), 0);
    const candidatos = [];
    for (let col = 0; col < ancho; col++) {
        const { solo, conAbajo, combinada } = etiquetas(filas, h, col);
        if (!solo && !conAbajo) { continue; }
        campos.forEach((c) => {
            if ((c.excluir || []).some((x) => combinada.includes(x))) { return; }
            let mejor = 0;
            c.alias.forEach((a) => { mejor = Math.max(mejor, puntaje(solo, a), puntaje(conAbajo, a), puntaje(combinada, a)); });
            // Un campo numérico (montos, deducibles) no debe tomar una columna de texto ("Amparado").
            if (mejor && c.tipo === 'numero' && !columnaNumerica(filas, h, col)) { mejor -= 80; }
            if (mejor > 0) { candidatos.push({ campo: c.key, col, puntos: mejor }); }
        });
    }
    candidatos.sort((a, b) => b.puntos - a.puntos || a.col - b.col);
    const mapeo = {};
    const usadas = new Set();
    candidatos.forEach((c) => {
        if (mapeo[c.campo] !== undefined || usadas.has(c.col)) { return; }
        mapeo[c.campo] = String(c.col);
        usadas.add(c.col);
    });
    return mapeo;
}

// Opciones del combo de columnas: "F: SERIES".
export function opcionesColumnas(filas, h) {
    const enc = filas[h] || [];
    const arriba = filaArriba(filas, h);
    const abajo = filasAbajo(filas, h);
    const ancho = Math.max(...filas.slice(0, 60).map((f) => (f || []).length), 0);
    const ops = [{ label: '— No usar —', value: '' }];
    for (let i = 0; i < ancho; i++) {
        const t = [arriba[i], enc[i], ...abajo.map((f) => (f || [])[i])]
            .map((x) => String(x ?? '').trim()).filter((x) => x).join(' ');
        ops.push({ label: `${letraColumna(i)}: ${t || '(sin título)'}`, value: String(i) });
    }
    return ops;
}

// Opciones del combo "Renglón de encabezados" (solo renglones con datos).
export function opcionesEncabezado(filas) {
    return filas.slice(0, 30)
        .map((f, i) => ({ f, i }))
        .filter(({ f }) => tieneDatos(f))
        .map(({ f, i }) => ({
            label: `Renglón ${i + 1}: ${(f || []).filter((c) => String(c ?? '').trim()).slice(0, 4).join(' | ').substring(0, 70)}`,
            value: String(i)
        }));
}

// Busca en las primeras filas una etiqueta (ej. "desde") y devuelve el primer valor de la derecha que sea fecha.
export function buscarFechaEtiquetada(filas, etiquetasBuscadas) {
    for (const f of filas) {
        for (let c = 0; c < (f || []).length; c++) {
            const t = fold(f[c]);
            if (!t || !etiquetasBuscadas.some((e) => t === e || t.startsWith(e + ' ') || t.endsWith(' ' + e))) { continue; }
            for (let d = c + 1; d < f.length; d++) {
                if (String(f[d] ?? '').trim() === '') { continue; }
                const r = fecha(f[d]);
                if (r.iso) { return r.iso; }
                break;
            }
        }
    }
    return '';
}

// ============================================================
// PDF (pdf.js)
// ============================================================

let pdfListo = false;

async function cargarPdfJs(componente) {
    if (pdfListo && window.pdfjsLib) { return; }
    try {
        await loadScript(componente, PDFJS + '/pdf.js');
    } catch (e) {
        await loadScript(componente, PDFJS + '/pdf.min.js');
    }
    if (typeof window.pdfjsLib === 'undefined') { throw new Error('No se pudo cargar el lector de PDF.'); }
    try { window.pdfjsLib.GlobalWorkerOptions.workerSrc = PDFJS + '/pdf.worker.js'; } catch (e) { /* sin worker */ }
    pdfListo = true;
}

// Une los fragmentos de texto por renglón (misma lógica que Crear Póliza).
function textoPorRenglones(items) {
    const filas = [];
    (items || []).forEach((it) => {
        if (!it || typeof it.str !== 'string' || !it.str.trim() || !it.transform) { return; }
        const x = it.transform[4];
        const y = it.transform[5];
        let fila = filas.find((f) => Math.abs(f.y - y) <= 3);
        if (!fila) { fila = { y, partes: [] }; filas.push(fila); }
        fila.partes.push({ x, s: it.str.trim() });
    });
    filas.sort((a, b) => b.y - a.y);
    return filas.map((f) => f.partes.sort((a, b) => a.x - b.x).map((p) => p.s).join(' ').replace(/\s+/g, ' ').trim()).join('\n');
}

/**
 * Texto del PDF partido en bloques de hasta "maxCaracteres" (por páginas completas) para mandarlos a la IA.
 * alProgresar(mensaje) informa el avance.
 */
export async function bloquesPdf(componente, file, maxCaracteres, alProgresar) {
    await cargarPdfJs(componente);
    const pdf = await window.pdfjsLib.getDocument({
        data: new Uint8Array(await file.arrayBuffer()),
        isEvalSupported: false, useWorkerFetch: false,
        standardFontDataUrl: fontsResource + '/', disableFontFace: true
    }).promise;
    const bloques = [];
    let actual = '';
    for (let p = 1; p <= pdf.numPages; p++) {
        if (alProgresar) { alProgresar(`Leyendo página ${p} de ${pdf.numPages}…`); }
        const page = await pdf.getPage(p);
        const content = await page.getTextContent();
        const texto = textoPorRenglones(content.items);
        if (actual && (actual.length + texto.length) > maxCaracteres) { bloques.push(actual); actual = ''; }
        actual += texto + '\n';
    }
    if (actual.trim()) { bloques.push(actual); }
    return bloques;
}

// Vigencia de la póliza: etiquetas "Desde/Hasta" (o "Del/Al"), o una celda "Vigencia" con un rango de un año
// ("15/09/26 - 15/09/27"). Un rango corto (ej. 30 días de validez de la cotización) no se toma como vigencia.
export function buscarVigencia(filas) {
    let desde = buscarFechaEtiquetada(filas, ['desde', 'vigencia desde', 'inicio de vigencia', 'inicio vigencia', 'del']);
    let hasta = buscarFechaEtiquetada(filas, ['hasta', 'vigencia hasta', 'fin de vigencia', 'fin vigencia', 'al']);
    if (desde && hasta) { return { desde, hasta }; }
    const patron = /(\d{4}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4})/g;
    for (const f of filas) {
        for (let c = 0; c < (f || []).length; c++) {
            const t = String(f[c] ?? '');
            if (!fold(t).includes('vigencia')) { continue; }
            const texto = [t, ...(f.slice(c + 1, c + 6))].map((x) => String(x ?? '')).join(' ');
            const fechas = (texto.match(patron) || []).map((x) => fecha(x).iso).filter((x) => x);
            if (fechas.length >= 2) {
                const dias = (new Date(fechas[1]) - new Date(fechas[0])) / 86400000;
                if (dias >= 300 && dias <= 400) { return { desde: fechas[0], hasta: fechas[1] }; }
            }
        }
    }
    return { desde: desde || '', hasta: hasta || '' };
}
