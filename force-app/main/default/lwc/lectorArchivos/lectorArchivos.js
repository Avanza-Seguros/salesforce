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
 * Excel .xlsx/.xlsm y .xls (Excel 97-2003). Las hojas ocultas (cálculos, catálogos) no se listan, salvo que
 * todas lo estén. El formato .xlsb no se puede leer en el navegador: se pide guardarlo como .xlsx.
 */
export async function abrirTabla(file) {
    const ext = file.name.toLowerCase().split('.').pop();
    if (ext === 'xlsb') {
        throw new Error('El formato .xlsb de Excel no se puede leer aquí. Ábrelo en Excel y usa "Guardar como" → Libro de Excel (.xlsx) o CSV.');
    }
    const visibles = (hojas) => (hojas.some((h) => !h.oculta) ? hojas.filter((h) => !h.oculta) : hojas);
    if (ext === 'xls') {
        const hojas = visibles(leerXls(await file.arrayBuffer()));
        return { hojas: hojas.map((h) => h.nombre), leerHoja: async (nombre) => (hojas.find((h) => h.nombre === nombre) || hojas[0]).filas };
    }
    if (ext === 'xlsx' || ext === 'xlsm') {
        const x = await abrirXlsx(await file.arrayBuffer());
        x.hojas = visibles(x.hojas);
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
        oculta: /hidden/i.test(s.getAttribute('state') || ''),
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

// ---------- Excel 97-2003 (.xls) ----------
// INICIO-XLS (bloque que también se prueba fuera de Salesforce)

// Contenido de un flujo del contenedor OLE (Compound File) por nombre ("Workbook" o "Book"), o null.
function flujoOle(u8, nombres) {
    const dv = new DataView(u8.buffer, u8.byteOffset, u8.byteLength);
    if (u8.length < 512 || dv.getUint32(0, true) !== 0xe011cfd0 || dv.getUint32(4, true) !== 0xe11ab1a1) { return null; }
    const tamSector = 1 << dv.getUint16(30, true);
    const tamMini = 1 << dv.getUint16(32, true);
    const corteMini = dv.getUint32(56, true);
    const sector = (s) => 512 + s * tamSector;
    // Sectores de la FAT: 109 en el encabezado y el resto en la cadena DIFAT.
    const sectoresFat = [];
    for (let i = 0; i < 109; i++) { const s = dv.getUint32(76 + i * 4, true); if (s < 0xfffffffa) { sectoresFat.push(s); } }
    let difat = dv.getUint32(68, true);
    for (let n = dv.getUint32(72, true); n > 0 && difat < 0xfffffffa; n--) {
        for (let i = 0; i < tamSector / 4 - 1; i++) { const s = dv.getUint32(sector(difat) + i * 4, true); if (s < 0xfffffffa) { sectoresFat.push(s); } }
        difat = dv.getUint32(sector(difat) + tamSector - 4, true);
    }
    const fat = [];
    sectoresFat.forEach((s) => { for (let i = 0; i < tamSector / 4; i++) { fat.push(dv.getUint32(sector(s) + i * 4, true)); } });
    const cadena = (inicio, tabla) => {
        const lista = [];
        for (let s = inicio; s < 0xfffffffa && lista.length <= tabla.length; s = tabla[s]) { lista.push(s); }
        return lista;
    };
    const leerCadena = (inicio, tam) => {
        const out = new Uint8Array(cadena(inicio, fat).length * tamSector);
        cadena(inicio, fat).forEach((s, i) => out.set(u8.subarray(sector(s), sector(s) + tamSector), i * tamSector));
        return out.subarray(0, tam);
    };
    const dir = leerCadena(dv.getUint32(48, true), Infinity);
    const entradas = [];
    for (let p = 0; p + 128 <= dir.length; p += 128) {
        const d = new DataView(dir.buffer, dir.byteOffset + p, 128);
        const largo = d.getUint16(64, true);
        let nombre = '';
        for (let i = 0; i < largo / 2 - 1; i++) { nombre += String.fromCharCode(d.getUint16(i * 2, true)); }
        entradas.push({ nombre, tipo: d.getUint8(66), inicio: d.getUint32(116, true), tam: d.getUint32(120, true) });
    }
    const e = entradas.find((x) => x.tipo === 2 && nombres.includes(x.nombre));
    if (!e) { return null; }
    if (e.tam >= corteMini) { return leerCadena(e.inicio, e.tam); }
    // Flujo chico: vive en el mini flujo de la entrada raíz y se encadena con la mini FAT.
    const raiz = entradas.find((x) => x.tipo === 5);
    const mini = leerCadena(raiz.inicio, raiz.tam);
    const miniFat = [];
    const bytesMiniFat = leerCadena(dv.getUint32(60, true), dv.getUint32(64, true) * tamSector);
    for (let i = 0; i + 4 <= bytesMiniFat.length; i += 4) { miniFat.push(new DataView(bytesMiniFat.buffer, bytesMiniFat.byteOffset + i, 4).getUint32(0, true)); }
    const out = new Uint8Array(cadena(e.inicio, miniFat).length * tamMini);
    cadena(e.inicio, miniFat).forEach((s, i) => out.set(mini.subarray(s * tamMini, (s + 1) * tamMini), i * tamMini));
    return out.subarray(0, e.tam);
}

// Número RK de Excel (entero o flotante comprimido, opcionalmente /100).
function numeroRk(rk) {
    let v;
    if (rk & 2) {
        v = rk >> 2;
    } else {
        const b = new DataView(new ArrayBuffer(8));
        b.setUint32(4, rk & 0xfffffffc, true);
        v = b.getFloat64(0, true);
    }
    return rk & 1 ? v / 100 : v;
}

/**
 * Lee un libro .xls (BIFF8). Devuelve [{ nombre, oculta, filas[][] }] con texto y números (fórmulas con su
 * último valor calculado). Los libros protegidos con contraseña no se pueden leer.
 */
export function leerXls(buffer) {
    const u8 = new Uint8Array(buffer);
    const wb = flujoOle(u8, ['Workbook', 'Book']);
    if (!wb) { throw new Error('El archivo no es un Excel .xls válido. Ábrelo en Excel y guárdalo como .xlsx.'); }
    const dv = new DataView(wb.buffer, wb.byteOffset, wb.byteLength);
    // Registros: [tipo, inicio de datos, largo].
    const registros = [];
    for (let p = 0; p + 4 <= wb.length;) {
        const tipo = dv.getUint16(p, true);
        const largo = dv.getUint16(p + 2, true);
        registros.push([tipo, p + 4, largo]);
        p += 4 + largo;
    }
    const latin = new TextDecoder('windows-1252');
    const texto16 = new TextDecoder('utf-16le');
    // Cadena Unicode que puede continuar en registros CONTINUE: cada continuación dentro de los caracteres
    // empieza con un byte de opciones que dice si siguen en 1 o 2 bytes.
    const lector = (partes) => {
        let i = 0;
        let p = partes.length ? partes[0][0] : 0;
        const fin = () => partes[i][0] + partes[i][1];
        const avanzarSiAcabo = () => { while (i < partes.length - 1 && p >= fin()) { i++; p = partes[i][0]; } };
        const u8b = () => { avanzarSiAcabo(); return wb[p++]; };
        const u16 = () => { avanzarSiAcabo(); const v = dv.getUint16(p, true); p += 2; return v; };
        const u32 = () => { avanzarSiAcabo(); const v = dv.getUint32(p, true); p += 4; return v; };
        const saltar = (n) => { while (n > 0) { avanzarSiAcabo(); const k = Math.min(n, fin() - p); p += k; n -= k; if (k <= 0) { break; } } };
        const cadena = (cch, opciones) => {
            let doble = opciones & 1;
            const ricos = opciones & 8 ? u16() : 0;
            const ext = opciones & 4 ? u32() : 0;
            let s = '';
            while (cch > 0) {
                if (p >= fin() && i < partes.length - 1) { i++; p = partes[i][0]; doble = wb[p++] & 1; }
                const disponibles = Math.floor((fin() - p) / (doble ? 2 : 1));
                const k = Math.min(cch, Math.max(disponibles, 0));
                if (k <= 0) { break; }
                s += (doble ? texto16 : latin).decode(wb.subarray(p, p + k * (doble ? 2 : 1)));
                p += k * (doble ? 2 : 1);
                cch -= k;
            }
            saltar(ricos * 4 + ext);
            return s;
        };
        return { u8: u8b, u16, u32, cadena, fin: () => i >= partes.length - 1 && p >= fin() };
    };
    const larga = (partes) => { const l = lector(partes); const cch = l.u16(); return l.cadena(cch, l.u8()); };

    const hojas = [];
    const sst = [];
    for (let k = 0; k < registros.length; k++) {
        const [tipo, ini, largo] = registros[k];
        if (tipo === 0x002f) { throw new Error('El Excel está protegido con contraseña. Quítale la protección o guárdalo como .xlsx.'); }
        if (tipo === 0x0085) {
            const l = lector([[ini + 6, largo - 6]]);
            hojas.push({ pos: dv.getUint32(ini, true), oculta: wb[ini + 4] !== 0, esHoja: wb[ini + 5] === 0, nombre: l.cadena(l.u8(), l.u8()), filas: [] });
        } else if (tipo === 0x00fc) {
            const partes = [[ini + 8, largo - 8]];
            while (k + 1 < registros.length && registros[k + 1][0] === 0x003c) { k++; partes.push([registros[k][1], registros[k][2]]); }
            const l = lector(partes);
            const total = dv.getUint32(ini + 4, true);
            for (let n = 0; n < total && !l.fin(); n++) { const cch = l.u16(); sst.push(l.cadena(cch, l.u8())); }
        }
    }
    hojas.forEach((h) => {
        const k0 = registros.findIndex((r) => r[1] - 4 === h.pos);
        if (k0 < 0 || !h.esHoja) { return; }
        const poner = (fila, col, valor) => {
            const f = h.filas[fila] || (h.filas[fila] = []);
            f[col] = typeof valor === 'string' ? repararTexto(valor) : valor;
        };
        let formulaPendiente = null;
        for (let k = k0 + 1; k < registros.length; k++) {
            const [tipo, ini, largo] = registros[k];
            if (tipo === 0x000a) { break; }
            const fila = dv.getUint16(ini, true);
            const col = dv.getUint16(ini + 2, true);
            if (tipo === 0x00fd) { poner(fila, col, sst[dv.getUint32(ini + 6, true)] ?? ''); }
            else if (tipo === 0x0203) { poner(fila, col, dv.getFloat64(ini + 6, true)); }
            else if (tipo === 0x027e) { poner(fila, col, numeroRk(dv.getUint32(ini + 6, true))); }
            else if (tipo === 0x00bd) {
                const ultima = dv.getUint16(ini + largo - 2, true);
                for (let c = col; c <= ultima; c++) { poner(fila, c, numeroRk(dv.getUint32(ini + 4 + (c - col) * 6 + 2, true))); }
            } else if (tipo === 0x0204 || tipo === 0x00d6) {
                poner(fila, col, larga([[ini + 6, largo - 6]]));
            } else if (tipo === 0x0205) {
                if (wb[ini + 7] === 0) { poner(fila, col, wb[ini + 6] ? 'VERDADERO' : 'FALSO'); }
            } else if (tipo === 0x0006) {
                // Resultado guardado de la fórmula: número, o texto en el registro STRING que sigue.
                if (dv.getUint16(ini + 12, true) !== 0xffff) { poner(fila, col, dv.getFloat64(ini + 6, true)); }
                else if (wb[ini + 6] === 0) { formulaPendiente = [fila, col]; }
                else if (wb[ini + 6] === 1) { poner(fila, col, wb[ini + 8] ? 'VERDADERO' : 'FALSO'); }
            } else if (tipo === 0x0207 && formulaPendiente) {
                const partes = [[ini, largo]];
                while (k + 1 < registros.length && registros[k + 1][0] === 0x003c) { k++; partes.push([registros[k][1], registros[k][2]]); }
                poner(formulaPendiente[0], formulaPendiente[1], larga(partes));
                formulaPendiente = null;
            }
        }
        h.filas = Array.from(h.filas, (f) => Array.from(f || [], (c) => (c === undefined ? '' : c)));
    });
    if (!hojas.length) { throw new Error('El Excel no tiene hojas.'); }
    return hojas.filter((h) => h.esHoja).map(({ nombre, oculta, filas }) => ({ nombre, oculta, filas }));
}
// FIN-XLS

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
    const bloques = [];
    let actual = '';
    (await paginasPdf(componente, file, alProgresar)).forEach((texto) => {
        if (actual && (actual.length + texto.length) > maxCaracteres) { bloques.push(actual); actual = ''; }
        actual += texto + '\n';
    });
    if (actual.trim()) { bloques.push(actual); }
    return bloques;
}

/**
 * Texto de cada página del PDF (un renglón por línea). alProgresar(mensaje) informa el avance.
 */
export async function paginasPdf(componente, file, alProgresar) {
    await cargarPdfJs(componente);
    const pdf = await window.pdfjsLib.getDocument({
        data: new Uint8Array(await file.arrayBuffer()),
        isEvalSupported: false, useWorkerFetch: false,
        standardFontDataUrl: fontsResource + '/', disableFontFace: true
    }).promise;
    const paginas = [];
    for (let p = 1; p <= pdf.numPages; p++) {
        if (alProgresar) { alProgresar(`Leyendo página ${p} de ${pdf.numPages}…`); }
        const page = await pdf.getPage(p);
        const content = await page.getTextContent();
        paginas.push(textoPorRenglones(content.items));
        page.cleanup();
    }
    pdf.destroy();
    return paginas;
}

// Página con algún monto ("$1,500.00", "1,234.56").
const MONTO = /\$\s?\d|\d,\d{3}(\.\d{2})?\b|\d\.\d{2}\b/;

/**
 * Bloques de un PDF largo (pólizas o cotizaciones de cientos de páginas) para mandarlos a la IA por partes.
 * Se quitan las páginas sin montos (condiciones generales), los párrafos largos sin cifras, el folio
 * "Página n de m" y los renglones de encabezado que se repiten en muchas páginas o en la página anterior;
 * al empezar cada bloque se conservan, para que cada parte traiga su propio encabezado (póliza, inciso,
 * domicilio). Los títulos de columnas que van justo arriba de un renglón con montos (ej. "Prima Neta ... Prima
 * Total") se conservan siempre. Cada página va marcada con "[Página n]". Devuelve hasta "maxBloques" bloques
 * de "maxCaracteres".
 */
export function bloquesCompactos(paginas, maxCaracteres, maxBloques) {
    // Sin el folio de página y con los montos pegados separados ("$4,242.21$3,157.08" -> "$4,242.21 $3,157.08").
    const limpia = (l) => l.replace(/\s*P[aá]gina \d+ de \d+\s*$/i, '').replace(/(\d)\$/g, '$1 $').replace(/\s+/g, ' ').trim();
    const renglones = paginas.map((p) => String(p || '').split('\n').map(limpia).filter((l) => l));
    const veces = new Map();
    renglones.forEach((ls) => new Set(ls).forEach((l) => veces.set(l, (veces.get(l) || 0) + 1)));
    const repetido = Math.max(3, paginas.length * 0.2);
    const bloques = [];
    let actual = '';
    let vistos = new Set();
    let anterior = new Set();
    renglones.forEach((ls, i) => {
        const deAntes = anterior;
        anterior = new Set(ls);
        if (!ls.some((l) => MONTO.test(l))) { return; }
        const armar = () => ls.filter((l, j) => {
            const titulosDeMontos = !/\d/.test(l) && MONTO.test(ls[j + 1] || '');
            if (l.length > 60 && !/\d/.test(l) && !titulosDeMontos) { return false; }
            if (vistos.has(l) && !titulosDeMontos && (deAntes.has(l) || veces.get(l) >= repetido)) { return false; }
            vistos.add(l);
            return true;
        }).join('\n');
        let texto = armar();
        if (actual && actual.length + texto.length > maxCaracteres) {
            bloques.push(actual);
            actual = '';
            vistos = new Set();
            texto = armar();
        }
        if (texto) { actual += `[Página ${i + 1}]\n${texto}\n`; }
    });
    if (actual.trim()) { bloques.push(actual); }
    return bloques.slice(0, maxBloques || bloques.length);
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

// Texto de una hoja para la IA: un renglón por fila con datos ("R12: celda | celda"), números con 2 decimales como
// máximo y sin celdas vacías. Se corta en "maxCaracteres" (la IA recibe un bloque limitado).
export function tablaATexto(filas, maxCaracteres) {
    const lineas = [];
    let largo = 0;
    for (let i = 0; i < filas.length; i++) {
        // Un número junto a una etiqueta de fecha ("Del: 46235") es una fecha de Excel: se escribe como dd/mm/aaaa.
        let anterior = '';
        const celdas = [];
        (filas[i] || []).forEach((c) => {
            let t;
            if (typeof c === 'number') {
                const f = /(^| )(del|al|desde|hasta|vigencia|fecha|inicio|fin|emision)( |$)/.test(fold(anterior)) ? fecha(c).iso : '';
                t = f ? fechaVisible(f) : String(Math.round(c * 100) / 100);
            } else {
                t = String(c ?? '').replace(/\s+/g, ' ').trim();
            }
            if (t !== '') { celdas.push(t); anterior = t; }
        });
        if (!celdas.length) { continue; }
        const linea = `R${i + 1}: ${celdas.join(' | ')}`;
        if (maxCaracteres && largo + linea.length > maxCaracteres) { break; }
        lineas.push(linea);
        largo += linea.length + 1;
    }
    return lineas.join('\n');
}
