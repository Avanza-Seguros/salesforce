/**
 * @creation date: 30/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Censo de vehículos de una oportunidad COLECTIVA de Automóviles (flotilla). Lee el archivo en el
 *               navegador (Excel .xlsx, CSV o PDF con IA), deja mapear las columnas, valida cada vehículo (serie,
 *               duplicados, modelo) y lo guarda con CensoVehiculosController como Inciso_Flotilla__c de la oportunidad.
 *               Muestra el resumen por tipo de vehículo y la lista; al cargar la póliza los vehículos se ligan a ella.
 */
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import {
    fold, tieneDatos, numero, moneda, abrirTabla, detectarEncabezado,
    mapeoAutomatico, opcionesColumnas, opcionesEncabezado, bloquesPdf, inicioDatos
} from 'c/lectorArchivos';
import getCensoVehiculos from '@salesforce/apex/CensoVehiculosController.getCensoVehiculos';
import guardarCensoVehiculos from '@salesforce/apex/CensoVehiculosController.guardarCensoVehiculos';
import eliminarCensoVehiculos from '@salesforce/apex/CensoVehiculosController.eliminarCensoVehiculos';
import analizarFlotillaPdf from '@salesforce/apex/FlotillaController.analizarFlotillaPdf';

// Campos del vehículo (la clave es la misma que devuelve la IA) y encabezados con que suelen venir.
const CAMPOS = [
    { key: 'inciso', label: 'Inciso', alias: ['inciso', 'inc', 'no inciso', 'num inciso', 'no de inciso', 'numero de inciso', 'no', 'consecutivo'] },
    { key: 'serie', label: 'Serie (VIN)', alias: ['serie', 'series', 'no serie', 'no de serie', 'numero de serie', 'num serie', 'vin', 'niv'] },
    { key: 'claveVehicular', label: 'Clave vehicular', alias: ['clave', 'clave amis', 'amis', 'clave vehicular', 'clave vehiculo', 'cve amis', 'mtc'] },
    { key: 'marca', label: 'Marca', alias: ['marca'] },
    { key: 'descripcion', label: 'Descripción', excluir: ['equipo', 'adapt', 'cobertura'], alias: ['descripcion', 'descripcion del vehiculo', 'descripcion vehiculo', 'vehiculo', 'unidad', 'marca tipo', 'marca y tipo', 'marca submarca', 'submarca', 'version'] },
    { key: 'modelo', label: 'Modelo (año)', tipo: 'numero', alias: ['modelo', 'mod', 'ano', 'ano modelo', 'anio'] },
    { key: 'placas', label: 'Placas', alias: ['placas', 'placa', 'matricula'] },
    { key: 'uso', label: 'Uso', alias: ['uso', 'tipo de uso', 'uso del vehiculo', 'servicio'] },
    { key: 'tipoVehiculo', label: 'Tipo de vehículo', alias: ['tipo de vehiculo', 'tipo vehiculo', 'tipo de unidad', 'clase', 'categoria', 'tonelaje'] },
    { key: 'paquete', label: 'Paquete', alias: ['cobertura', 'paquete', 'paq', 'plan', 'tipo de cobertura', 'paquete de cobertura'] },
    { key: 'tipoValor', label: 'Tipo de valor', alias: ['tipo de valor', 'tipo valor'] },
    { key: 'valor', label: 'Valor / suma asegurada', tipo: 'numero', alias: ['valor convenido', 'valor comercial', 'valor factura', 'suma asegurada', 'suma aseg', 'valor vehiculo', 'valor'] },
    { key: 'prima', label: 'Prima', tipo: 'numero', alias: ['prima total', 'prima', 'prima anual', 'importe'] }
];

// Modelos de pick-up comunes (cuando la descripción no dice "pick up" ni el uso "carga").
const PICKUPS = ['hilux', 'tacoma', 'tundra', 'np300', 'frontier', 'ranger', 'f 150', 'f150', 'lobo', 'saveiro', 'amarok', 'l200',
    'ram 700', 'ram 1200', 'ram 1500', 'ram 2500', 'ram 4000', 'tornado', 's10', 'silverado', 'cheyenne', 'colorado', 'oroch', 'maverick',
    'raptor', 'navara', 'bt 50', 'great wall', 'jac t8', 'poer'];

const POR_PAGINA = 50;
// Vehículos por llamada a Apex (el controlador acepta hasta 3,000).
const LOTE = 1000;
const BLOQUE_PDF = 12000;

export default class CensoVehiculos extends LightningElement {
    @api readOnly = false;

    @track censo = null;
    @track mapeo = {};
    @track renglones = [];
    paso = 'resumen';
    cargando = false;
    progreso = '';
    errorMensaje = '';
    archivoNombre = '';
    hojas = [];
    hojaActual = '';
    filasCrudas = [];
    filaEncabezado = 0;
    modoGuardar = 'reemplazar';
    filtro = 'todos';
    pagina = 1;
    paginaCenso = 1;
    verVehiculos = false;
    _opportunityId;
    _tabla = null;

    @api
    get opportunityId() { return this._opportunityId; }
    set opportunityId(v) {
        const cambio = v !== this._opportunityId;
        this._opportunityId = v;
        if (cambio && v) { this.cargarCenso(); }
    }

    // ============================================================
    // Censo guardado
    // ============================================================
    async cargarCenso() {
        if (!this._opportunityId) { return; }
        this.cargando = true;
        try {
            this.censo = await getCensoVehiculos({ opportunityId: this._opportunityId });
            this.paginaCenso = 1;
            this.dispatchEvent(new CustomEvent('censoactualizado', { detail: { total: this.censo ? this.censo.total : 0 } }));
        } catch (e) {
            this.toast('Censo de vehículos', this.mensaje(e), 'error');
        } finally {
            this.cargando = false;
        }
    }

    get tieneCenso() { return !!(this.censo && this.censo.total); }
    get enResumen() { return this.paso === 'resumen'; }
    get enMapeo() { return this.paso === 'mapeo'; }
    get enVista() { return this.paso === 'vista'; }
    get puedeEditar() { return !this.readOnly && !!this._opportunityId; }
    get sinOportunidad() { return !this._opportunityId; }
    get totalTipos() { return this.censo && this.censo.tipos ? this.censo.tipos.length : 0; }
    get valorCenso() { return moneda(this.censo && this.censo.valorTotal) || '—'; }

    get tiposCenso() {
        return ((this.censo && this.censo.tipos) || []).map((t) => ({
            ...t,
            key: t.tipo,
            valorTxt: moneda(t.valor),
            primaTxt: moneda(t.prima)
        }));
    }
    get verVehiculosLabel() { return this.verVehiculos ? 'Ocultar vehículos' : 'Ver vehículos'; }
    toggleVehiculos() { this.verVehiculos = !this.verVehiculos; }

    get vehiculosCenso() {
        const lista = (this.censo && this.censo.incisos) || [];
        const ini = (this.paginaCenso - 1) * POR_PAGINA;
        return lista.slice(ini, ini + POR_PAGINA).map((v, i) => ({
            ...v,
            key: v.id || String(ini + i),
            num: ini + i + 1,
            polizaUrl: v.polizaId ? '/' + v.polizaId : null,
            valorTxt: moneda(v.valor),
            primaTxt: moneda(v.prima)
        }));
    }
    get paginasCenso() { return Math.max(1, Math.ceil(((this.censo && this.censo.incisos) || []).length / POR_PAGINA)); }
    get textoPaginaCenso() {
        const mostrados = ((this.censo && this.censo.incisos) || []).length;
        const extra = this.censo && this.censo.total > mostrados ? ` · se muestran los primeros ${mostrados} de ${this.censo.total}` : '';
        return `Página ${this.paginaCenso} de ${this.paginasCenso}${extra}`;
    }
    get sinAnteriorCenso() { return this.paginaCenso <= 1; }
    get sinSiguienteCenso() { return this.paginaCenso >= this.paginasCenso; }
    anteriorCenso() { if (this.paginaCenso > 1) { this.paginaCenso--; } }
    siguienteCenso() { if (this.paginaCenso < this.paginasCenso) { this.paginaCenso++; } }

    async handleEliminar() {
        const ok = await LightningConfirm.open({
            message: 'Se eliminarán los vehículos del censo. Los que ya están en una póliza se conservan. ¿Continuar?',
            variant: 'header', label: 'Eliminar censo de vehículos', theme: 'warning'
        });
        if (!ok) { return; }
        this.cargando = true;
        try {
            const quedan = await eliminarCensoVehiculos({ opportunityId: this._opportunityId });
            this.toast('Censo de vehículos', quedan ? `Censo eliminado. Se conservan ${quedan} vehículos que están en una póliza.` : 'Censo eliminado.', 'success');
            await this.cargarCenso();
        } catch (e) {
            this.toast('Censo de vehículos', this.mensaje(e), 'error');
        } finally {
            this.cargando = false;
        }
    }

    // Descarga una plantilla CSV con las columnas que se reconocen automáticamente.
    descargarPlantilla() {
        const filas = [
            'Inciso,Serie,Marca,Descripcion,Modelo,Placas,Uso,Tipo de vehiculo,Paquete,Tipo de valor,Valor',
            '1,3GCEC14X38M114075,CHEVROLET,SILVERADO 1500 CABINA REGULAR,2008,JAL1234,Carga,Pick-up de carga,Amplia,Comercial,180000',
            '2,3N1CN7AD5KL800001,NISSAN,VERSA SENSE,2019,JAL5678,Particular,Automóviles,Amplia,Comercial,190000'
        ];
        const a = document.createElement('a');
        a.href = 'data:text/csv;charset=utf-8,' + encodeURIComponent('﻿' + filas.join('\r\n'));
        a.download = 'Plantilla_censo_vehiculos.csv';
        a.click();
    }

    // ============================================================
    // Lectura del archivo
    // ============================================================
    async handleArchivo(event) {
        const file = event.target.files && event.target.files[0];
        event.target.value = null;
        if (!file) { return; }
        const ext = file.name.toLowerCase().split('.').pop();
        this.archivoNombre = file.name;
        this.errorMensaje = '';
        this.cargando = true;
        this.progreso = 'Leyendo archivo…';
        try {
            if (ext === 'pdf') {
                await this.procesarPdf(file);
                return;
            }
            this._tabla = await abrirTabla(file);
            this.hojas = this._tabla.hojas.map((h) => ({ label: h, value: h }));
            this.hojaActual = this._tabla.hojas.length ? this._tabla.hojas[0] : '';
            this.filasCrudas = await this._tabla.leerHoja(this.hojaActual);
            this.prepararMapeo();
        } catch (e) {
            this.toast('Censo de vehículos', this.mensaje(e), 'error');
        } finally {
            this.cargando = false;
            this.progreso = '';
        }
    }

    get hayVariasHojas() { return this.hojas.length > 1; }
    async handleHoja(event) {
        this.hojaActual = event.detail.value;
        this.cargando = true;
        try {
            this.filasCrudas = await this._tabla.leerHoja(this.hojaActual);
            this.prepararMapeo();
        } catch (e) {
            this.toast('Censo de vehículos', this.mensaje(e), 'error');
        } finally {
            this.cargando = false;
        }
    }

    // Ubica el renglón de encabezados y propone el mapeo de columnas.
    prepararMapeo() {
        const filas = this.filasCrudas;
        if (filas.filter((f) => tieneDatos(f)).length < 2) {
            throw new Error('El archivo no tiene renglones de vehículos.');
        }
        this.filaEncabezado = detectarEncabezado(filas, CAMPOS);
        this.mapeo = mapeoAutomatico(filas, this.filaEncabezado, CAMPOS);
        this.paso = 'mapeo';
    }

    get opcionesColumnas() { return opcionesColumnas(this.filasCrudas, this.filaEncabezado); }
    get opcionesEncabezado() { return opcionesEncabezado(this.filasCrudas); }
    get filaEncabezadoValor() { return String(this.filaEncabezado); }
    // Primer renglón de datos (después del encabezado y sus renglones de continuación).
    get inicioDatos() { return inicioDatos(this.filasCrudas, this.filaEncabezado); }
    get filasDatos() { return this.filasCrudas.slice(this.inicioDatos).filter((f) => tieneDatos(f)).length; }
    get textoEncabezado() { return `Encabezados en el renglón ${this.filaEncabezado + 1} · ${this.filasDatos} renglones de datos`; }
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
        // Una columna solo puede ir a un campo.
        if (valor !== '') {
            Object.keys(nuevo).forEach((k) => { if (nuevo[k] === valor) { delete nuevo[k]; } });
        }
        if (valor === '') { delete nuevo[campo]; } else { nuevo[campo] = valor; }
        this.mapeo = nuevo;
    }

    aplicarMapeo() {
        const m = this.mapeo;
        if (m.serie === undefined && m.descripcion === undefined) {
            this.toast('Censo de vehículos', 'Indica al menos la columna de la serie o de la descripción del vehículo.', 'warning');
            return;
        }
        const ini = this.inicioDatos;
        const datos = [];
        this.filasCrudas.slice(ini).forEach((f, i) => {
            if (!tieneDatos(f)) { return; }
            const o = { fila: ini + i + 1 };
            Object.keys(m).forEach((k) => { o[k] = f[Number(m[k])]; });
            datos.push(o);
        });
        this.validar(datos);
    }

    cancelar() {
        this.errorMensaje = '';
        this.paso = 'resumen';
        this.renglones = [];
        this.filasCrudas = [];
        this._tabla = null;
    }
    volverAMapeo() {
        if (this.filasCrudas.length) { this.paso = 'mapeo'; } else { this.cancelar(); }
    }

    // ============================================================
    // PDF (pdf.js + IA)
    // ============================================================
    async procesarPdf(file) {
        const bloques = await bloquesPdf(this, file, BLOQUE_PDF, (m) => { this.progreso = m; });
        if (!bloques.length) {
            throw new Error('No se pudo leer texto del PDF (¿está escaneado?). Pide el listado en Excel.');
        }
        const datos = [];
        for (let i = 0; i < bloques.length; i++) {
            this.progreso = `Analizando con IA: bloque ${i + 1} de ${bloques.length}…`;
            const json = await analizarFlotillaPdf({ textoCotizacion: bloques[i] });
            let r = {};
            try { r = JSON.parse(json || '{}'); } catch (e) { r = {}; }
            (r.incisos || []).forEach((x) => datos.push({ ...x, fila: datos.length + 1 }));
        }
        if (!datos.length) {
            throw new Error('La IA no encontró vehículos en el PDF.');
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
            // Un vehículo tiene serie o descripción (descarta pies de página y notas).
            .filter((r) => r.serie || /[a-z]/i.test(r.descripcion))
            .filter((r) => !/^(sub)?total(es)?\b/.test(fold(r.descripcion)));
        const series = {};
        renglones.forEach((r, i) => {
            r.idx = i;
            if (r.serie) {
                if (series[r.serie] !== undefined) {
                    r.errores.push(`Serie repetida (fila ${renglones[series[r.serie]].fila})`);
                } else {
                    series[r.serie] = i;
                }
                if (r.serie.length !== 17) { r.avisos.push(`La serie tiene ${r.serie.length} caracteres (un VIN tiene 17)`); }
            } else {
                r.avisos.push('Sin serie: no se podrá ligar con la póliza');
            }
            if (!r.descripcion) { r.avisos.push('Sin descripción'); }
        });
        this.renglones = renglones;
        this.filtro = 'todos';
        this.pagina = 1;
        this.modoGuardar = 'reemplazar';
        this.paso = 'vista';
    }

    normalizar(d) {
        const txt = (v) => (v === undefined || v === null ? '' : String(v).replace(/\s+/g, ' ').trim());
        const entero = (v) => { const n = numero(v); return n === null ? null : Math.round(n); };
        const r = { fila: d.fila, errores: [], avisos: [] };
        r.inciso = entero(d.inciso);
        r.serie = txt(d.serie).replace(/\s/g, '').toUpperCase();
        r.claveVehicular = txt(d.claveVehicular).replace(/\.0+$/, '');
        r.descripcion = txt(d.descripcion);
        // Si la marca viene en otra columna y la descripción no la trae, se antepone.
        const marca = txt(d.marca);
        if (marca && !fold(r.descripcion).includes(fold(marca))) { r.descripcion = `${marca} ${r.descripcion}`.trim(); }
        r.modelo = entero(d.modelo);
        if (r.modelo !== null && (r.modelo < 1900 || r.modelo > 2100)) {
            r.avisos.push(`Modelo no válido (${txt(d.modelo)})`);
            r.modelo = null;
        }
        r.placas = txt(d.placas).replace(/\s/g, '').toUpperCase();
        if (['SN', 'S/N', 'SINPLACAS'].includes(r.placas)) { r.placas = ''; }
        r.uso = txt(d.uso);
        r.paquete = txt(d.paquete);
        r.tipoValor = txt(d.tipoValor);
        r.valor = numero(d.valor);
        const prima = numero(d.prima);
        r.prima = prima === null ? null : Math.round(prima * 100) / 100;
        r.tipoVehiculo = this.tipoNormalizado(txt(d.tipoVehiculo)) || this.tipoVehiculo(r.descripcion, r.uso);
        return r;
    }

    // Lleva el tipo que trae el archivo (o la IA) a la lista fija que usa la flotilla. Si no se reconoce, se conserva.
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
    get totalRenglones() { return this.renglones.length; }
    get validos() { return this.renglones.filter((r) => !r.errores.length); }
    get totalValidos() { return this.validos.length; }
    get conSerieValidos() { return this.validos.filter((r) => r.serie).length; }
    get conError() { return this.renglones.filter((r) => r.errores.length).length; }
    get conAviso() { return this.renglones.filter((r) => !r.errores.length && r.avisos.length).length; }
    get hayErrores() { return this.conError > 0; }
    get sinValidos() { return this.totalValidos === 0 || this.cargando; }
    get textoGuardar() { return `Guardar ${this.totalValidos} vehículos`; }

    get resumenVista() {
        const mapa = {};
        this.validos.forEach((r) => {
            const k = r.tipoVehiculo || 'Sin tipo';
            const t = mapa[k] || (mapa[k] = { key: k, tipo: k, vehiculos: 0, valor: 0, prima: 0 });
            t.vehiculos++;
            t.valor += r.valor || 0;
            t.prima += r.prima || 0;
        });
        return Object.values(mapa).map((t) => ({ ...t, valorTxt: moneda(t.valor), primaTxt: moneda(t.prima) }));
    }

    get opcionesFiltro() {
        return [
            { label: `Todos (${this.totalRenglones})`, value: 'todos' },
            { label: `Con error (${this.conError})`, value: 'errores' },
            { label: `Con aviso (${this.conAviso})`, value: 'avisos' }
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
            inciso: r.inciso === null ? '' : r.inciso,
            serie: r.serie,
            descripcion: r.descripcion || '(sin descripción)',
            modelo: r.modelo === null ? '' : r.modelo,
            placas: r.placas,
            uso: r.uso,
            tipoVehiculo: r.tipoVehiculo,
            valorTxt: moneda(r.valor),
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

    get opcionesModo() {
        return [
            { label: 'Reemplazar el censo actual', value: 'reemplazar' },
            { label: 'Agregar al censo actual', value: 'agregar' }
        ];
    }
    handleModo(event) { this.modoGuardar = event.detail.value; }

    // ============================================================
    // Guardado
    // ============================================================
    async guardar() {
        const validos = this.validos;
        if (!validos.length) { return; }
        const lotes = [];
        for (let i = 0; i < validos.length; i += LOTE) { lotes.push(validos.slice(i, i + LOTE)); }
        this.cargando = true;
        let total = 0;
        try {
            for (let i = 0; i < lotes.length; i++) {
                this.progreso = lotes.length > 1 ? `Guardando lote ${i + 1} de ${lotes.length}…` : 'Guardando censo…';
                const payload = lotes[i].map((r) => ({
                    fila: r.fila,
                    inciso: r.inciso,
                    serie: r.serie || null,
                    claveVehicular: r.claveVehicular || null,
                    descripcion: r.descripcion || null,
                    modelo: r.modelo,
                    placas: r.placas || null,
                    uso: r.uso || null,
                    tipoVehiculo: r.tipoVehiculo || null,
                    paquete: r.paquete || null,
                    tipoValor: r.tipoValor || null,
                    valor: r.valor,
                    prima: r.prima
                }));
                total = await guardarCensoVehiculos({
                    opportunityId: this._opportunityId,
                    incisosJson: JSON.stringify(payload),
                    reemplazar: i === 0 && this.modoGuardar === 'reemplazar'
                });
            }
            this.toast('Censo de vehículos', `Censo guardado: ${total} vehículos.`, 'success');
            this.cancelar();
            await this.cargarCenso();
        } catch (e) {
            this.toast('Censo de vehículos', this.mensaje(e), 'error');
        } finally {
            this.cargando = false;
            this.progreso = '';
        }
    }

    // ============================================================
    // Utilidades
    // ============================================================
    mensaje(e) {
        return (e && e.body && e.body.message) || (e && e.message) || 'Ocurrió un error inesperado.';
    }
    toast(title, message, variant) {
        // Los errores también se muestran dentro del componente (el toast desaparece solo).
        this.errorMensaje = variant === 'error' ? message : '';
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
