/**
 * @creation date: 12/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Censo de asegurados de una oportunidad COLECTIVA. Lee el archivo en el navegador
 *               (Excel .xlsx, CSV o PDF con IA), deja mapear las columnas, valida cada renglón
 *               (titulares, dependientes, fechas, duplicados) y lo guarda con CensoColectivoController
 *               en GroupCensus / GroupCensusMember / GroupClass. Muestra el resumen por categoría.
 */
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import {
    fold, tieneDatos, numero, fecha, fechaVisible, moneda, abrirTabla, detectarEncabezado,
    opcionesColumnas, opcionesEncabezado, bloquesPdf, inicioDatos
} from 'c/lectorArchivos';
import {
    CAMPOS_CENSO, mapeoCenso, normalizarCenso, payloadMiembro, conteoMovimientos, MOVIMIENTOS, movimientosPorRevisar, AVISO_SIN_CONTACTO,
    endosoDeTexto, clausulaDeTexto
} from 'c/clasificadorArchivos';
import movimientosSinContacto from '@salesforce/apex/CensoColectivoController.movimientosSinContacto';
import revisarCambios from '@salesforce/apex/CensoColectivoController.revisarCambios';
import aplicarBajas from '@salesforce/apex/CensoColectivoController.aplicarBajas';
import complementarCenso from '@salesforce/apex/CensoColectivoController.complementarCenso';
import getCenso from '@salesforce/apex/CensoColectivoController.getCenso';
import guardarCenso from '@salesforce/apex/CensoColectivoController.guardarCenso';
import eliminarCenso from '@salesforce/apex/CensoColectivoController.eliminarCenso';
import analizarCensoPdf from '@salesforce/apex/CensoColectivoController.analizarCensoPdf';
import { llamar } from 'c/portalContexto';

// Campos del censo: clave (la misma que devuelve la IA), etiqueta y encabezados con que suele venir.
// Se comparten con Crear Póliza (emisión de colectivos con varios archivos) en c/clasificadorArchivos.
const CAMPOS = CAMPOS_CENSO;

const POR_PAGINA = 50;
// Asegurados por llamada a Apex (el controlador acepta hasta 4,500).
const LOTE = 2000;
// Caracteres de texto por bloque que se manda a la IA (PDFs largos se parten).
const BLOQUE_PDF = 12000;

export default class CensoColectivo extends LightningElement {
    @api readOnly = false;
    // 'lector': solo lee y valida el archivo y lo entrega en el evento "leido" (no guarda ni muestra el censo).
    @api modo = '';

    @track censo = null;
    @track paso = 'resumen';
    @track mapeo = {};
    @track renglones = [];
    // Vista previa de los cambios del archivo (dato anterior y nuevo).
    @track cambiosRevision = [];
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
    verAsegurados = false;
    _opportunityId;
    _tabla = null;
    _cola = [];
    _totalArchivos = 0;
    _acumulado = [];
    _rangos = [];
    _archivoActual = '';

    @api
    get opportunityId() { return this._opportunityId; }
    set opportunityId(v) {
        const cambio = v !== this._opportunityId;
        this._opportunityId = v;
        if (cambio && v && !this.esLector) { this.cargarCenso(); }
    }

    // Vuelve a leer el censo guardado (por ejemplo, después de aplicar altas y bajas de la renovación).
    @api
    recargar() {
        return this.cargarCenso();
    }

    // En la póliza: el PDF de un endoso de la aseguradora que no trae asegurados (Vida o GMM: cláusula, beneficio
    // adicional, cambio de forma de administración...) no va a la IA; se entrega para registrarlo como endoso.
    @api leeEndosos = false;
    _endosos = [];

    get esLector() { return this.modo === 'lector'; }
    get mostrarCenso() { return !this.esLector; }
    get tituloCarga() { return this.esLector ? 'Cargar archivo de la aseguradora' : 'Cargar censo'; }

    // ============================================================
    // Censo guardado
    // ============================================================
    async cargarCenso() {
        if (!this._opportunityId) { return; }
        this.cargando = true;
        try {
            this.censo = await getCenso({ opportunityId: this._opportunityId });
            this.paginaCenso = 1;
            this.dispatchEvent(new CustomEvent('censoactualizado', { detail: { total: this.censo ? this.censo.total : 0 } }));
        } catch (e) {
            this.toast('Censo', this.mensaje(e), 'error');
        } finally {
            this.cargando = false;
        }
    }

    get tieneCenso() { return !!(this.censo && this.censo.censoId); }
    get enResumen() { return this.paso === 'resumen'; }
    get enMapeo() { return this.paso === 'mapeo'; }
    get enVista() { return this.paso === 'vista'; }
    get puedeEditar() { return !this.readOnly && (!!this._opportunityId || this.esLector); }
    get sinOportunidad() { return !this._opportunityId && !this.esLector; }

    get totalCategorias() { return this.censo && this.censo.categorias ? this.censo.categorias.length : 0; }
    get categoriasCenso() {
        return ((this.censo && this.censo.categorias) || []).map((c) => ({
            ...c,
            key: c.nombre,
            total: (c.titulares || 0) + (c.dependientes || 0),
            edadTxt: c.edadPromedio === null || c.edadPromedio === undefined ? '—' : c.edadPromedio + ' años',
            sueldoTxt: this.moneda(c.sueldoTotal),
            sumaTxt: this.moneda(c.sumaAseguradaTotal),
            primaTxt: this.moneda(c.primaTotal)
        }));
    }
    get verAseguradosLabel() { return this.verAsegurados ? 'Ocultar asegurados' : 'Ver asegurados'; }
    toggleAsegurados() { this.verAsegurados = !this.verAsegurados; }

    get miembrosCenso() {
        const lista = (this.censo && this.censo.miembros) || [];
        const ini = (this.paginaCenso - 1) * POR_PAGINA;
        return lista.slice(ini, ini + POR_PAGINA).map((m, i) => ({
            ...m,
            key: m.id || String(ini + i),
            num: ini + i + 1,
            esDependiente: !!m.titular,
            claseFila: m.titular ? 'fila-dependiente' : '',
            fechaTxt: this.fechaVisible(m.fechaNacimiento),
            edadTxt: m.edad === null || m.edad === undefined ? '' : m.edad,
            sueldoTxt: this.moneda(m.sueldoAnual),
            sumaTxt: this.moneda(m.sumaAsegurada),
            primaTxt: this.moneda(m.prima)
        }));
    }
    get paginasCenso() { return Math.max(1, Math.ceil(((this.censo && this.censo.miembros) || []).length / POR_PAGINA)); }
    get textoPaginaCenso() {
        const mostrados = ((this.censo && this.censo.miembros) || []).length;
        const extra = this.censo && this.censo.total > mostrados ? ` · se muestran los primeros ${mostrados} de ${this.censo.total}` : '';
        return `Página ${this.paginaCenso} de ${this.paginasCenso}${extra}`;
    }
    get sinAnteriorCenso() { return this.paginaCenso <= 1; }
    get sinSiguienteCenso() { return this.paginaCenso >= this.paginasCenso; }
    anteriorCenso() { if (this.paginaCenso > 1) { this.paginaCenso--; } }
    siguienteCenso() { if (this.paginaCenso < this.paginasCenso) { this.paginaCenso++; } }

    async handleEliminar() {
        const ok = await LightningConfirm.open({
            message: 'Se eliminará el censo con todos sus asegurados. Las categorías de la empresa se conservan. ¿Continuar?',
            variant: 'header', label: 'Eliminar censo', theme: 'warning'
        });
        if (!ok) { return; }
        this.cargando = true;
        try {
            await eliminarCenso({ opportunityId: this._opportunityId });
            this.toast('Censo', 'Censo eliminado.', 'success');
            await this.cargarCenso();
        } catch (e) {
            this.toast('Censo', this.mensaje(e), 'error');
        } finally {
            this.cargando = false;
        }
    }

    // Descarga una plantilla CSV con las columnas que se reconocen automáticamente.
    descargarPlantilla() {
        const filas = [
            'Certificado,Num. empleado,Nombre,Apellido paterno,Apellido materno,Fecha de nacimiento,Genero,Parentesco,Categoria,Fecha de movimiento,RFC,Correo,Telefono',
            '001,E-100,Juan,Perez,Lopez,14/03/1985,H,Titular,Directivos,01/01/2020,PELJ850314AB1,juan.perez@empresa.com,5512345678',
            '001,E-100,Maria,Sosa,Ruiz,02/07/1988,M,Conyuge,Directivos,01/01/2020,,,',
            '001,E-100,Sofia,Perez,Sosa,10/05/2015,M,Hijo,Directivos,01/01/2020,,,',
            '002,E-101,Pedro,Gomez,Diaz,22/11/1990,H,Titular,Empleados,15/06/2022,,,'
        ];
        const a = document.createElement('a');
        a.href = 'data:text/csv;charset=utf-8,' + encodeURIComponent('﻿' + filas.join('\r\n'));
        a.download = 'Plantilla_censo_colectivo.csv';
        a.click();
    }

    // ============================================================
    // Lectura del archivo
    // ============================================================
    // Zona de carga propia (la del componente estándar es muy pequeña): clic o arrastrar y soltar.
    arrastrando = false;
    get claseZona() { return 'censo-zona' + (this.arrastrando ? ' censo-zona-activa' : ''); }
    elegirArchivo() {
        const input = this.template.querySelector('input.censo-input');
        if (input) { input.click(); }
    }
    sobreZona(e) { e.preventDefault(); this.arrastrando = true; }
    fueraZona() { this.arrastrando = false; }
    soltarArchivo(e) {
        e.preventDefault();
        this.arrastrando = false;
        const files = Array.from((e.dataTransfer && e.dataTransfer.files) || []);
        if (files.length) { this.handleArchivo({ target: { files, value: null } }); }
    }

    // Uno o varios archivos: cada Excel pasa por el mapeo de columnas y cada PDF se lee solo; al final se revisan todos
    // juntos. Las filas se numeran seguidas entre archivos (las del segundo archivo continúan después del primero).
    async handleArchivo(event) {
        const files = Array.from((event.target && event.target.files) || []);
        event.target.value = null;
        if (!files.length) { return; }
        this._cola = files;
        this._totalArchivos = files.length;
        this._acumulado = [];
        this._rangos = [];
        this._endosos = [];
        this.errorMensaje = '';
        await this.siguienteArchivo();
    }
    async siguienteArchivo() {
        if (!this._cola.length) {
            if (this._acumulado.length) {
                this.archivoNombre = this._rangos.map((r) => r.nombre).join(', ');
                this.validar(this._acumulado);
            } else if (this._endosos.length) {
                // Solo endosos sin asegurados: se registran como endosos.
                const endosos = this._endosos;
                this.cancelar();
                this.dispatchEvent(new CustomEvent('endoso', { detail: { endosos } }));
            } else if (this.paso === 'mapeo') {
                this.cancelar();
            }
            return;
        }
        const file = this._cola.shift();
        const n = this._totalArchivos - this._cola.length;
        this._archivoActual = file.name;
        this.archivoNombre = this._totalArchivos > 1 ? `${file.name} (archivo ${n} de ${this._totalArchivos})` : file.name;
        const ext = file.name.toLowerCase().split('.').pop();
        this.cargando = true;
        this.progreso = 'Leyendo archivo…';
        let enMapeo = false;
        try {
            if (ext === 'pdf') {
                await this.procesarPdf(file);
            } else {
                this._tabla = await abrirTabla(file);
                this.hojas = this._tabla.hojas.map((h) => ({ label: h, value: h }));
                this.hojaActual = this._tabla.hojas.length ? this._tabla.hojas[0] : '';
                this.filasCrudas = await this._tabla.leerHoja(this.hojaActual);
                this.prepararMapeo();
                enMapeo = true;
            }
        } catch (e) {
            this.toast('Censo', this._totalArchivos > 1 ? `${file.name}: ${this.mensaje(e)}` : this.mensaje(e), 'error');
        } finally {
            this.cargando = false;
            this.progreso = '';
        }
        // Un Excel espera a que se confirme su mapeo (aplicarMapeo sigue con el siguiente archivo).
        if (!enMapeo) { await this.siguienteArchivo(); }
    }
    // Junta los renglones leídos de un archivo; las filas siguen la numeración del archivo anterior.
    agregarArchivo(datos) {
        const base = this._rangos.length ? this._rangos[this._rangos.length - 1].hasta : 0;
        let hasta = base;
        datos.forEach((d) => { d.fila = base + Number(d.fila || 0); hasta = Math.max(hasta, d.fila); });
        this._rangos.push({ nombre: this._archivoActual, desde: base + 1, hasta });
        this._acumulado.push(...datos);
    }
    // Archivo de donde viene una fila (solo cuando se cargó más de uno).
    archivoDe(fila) {
        if (this._rangos.length < 2) { return ''; }
        const r = this._rangos.find((x) => fila >= x.desde && fila <= x.hasta);
        return r ? r.nombre : '';
    }

    get hayVariasHojas() { return this.hojas.length > 1; }
    async handleHoja(event) {
        this.hojaActual = event.detail.value;
        this.cargando = true;
        try {
            this.filasCrudas = await this._tabla.leerHoja(this.hojaActual);
            this.prepararMapeo();
        } catch (e) {
            this.toast('Censo', this.mensaje(e), 'error');
        } finally {
            this.cargando = false;
        }
    }

    // Ubica el renglón de encabezados y propone el mapeo de columnas.
    // Los renglones vacíos se conservan para que el número de fila coincida con el del archivo.
    prepararMapeo() {
        const filas = this.filasCrudas;
        if (filas.filter((f) => this.tieneDatos(f)).length < 2) {
            throw new Error('El archivo no tiene renglones de asegurados.');
        }
        this.filaEncabezado = this.detectarEncabezado(filas);
        this.mapeo = this.mapeoAutomatico(filas, this.filaEncabezado);
        this.paso = 'mapeo';
    }

    tieneDatos(fila) {
        return tieneDatos(fila);
    }

    detectarEncabezado(filas) {
        return detectarEncabezado(filas, CAMPOS);
    }

    // Mapeo automático; "Nombre" sin columnas de apellidos es el nombre completo.
    mapeoAutomatico(filas, h) {
        return mapeoCenso(filas, h);
    }

    get opcionesColumnas() {
        return opcionesColumnas(this.filasCrudas, this.filaEncabezado);
    }
    get camposMapeo() {
        const ejemplo = this.filasCrudas.slice(this.inicioDatos).find((f) => this.tieneDatos(f)) || [];
        return CAMPOS.map((c) => {
            const col = this.mapeo[c.key];
            const v = col === undefined || col === '' ? '' : ejemplo[Number(col)];
            return {
                key: c.key,
                label: c.label,
                value: col === undefined ? '' : col,
                ejemplo: v === undefined || v === null || v === '' ? '' : 'Ej.: ' + this.textoCelda(v, c.tipo),
                clase: col === undefined || col === '' ? 'campo-mapeo' : 'campo-mapeo campo-mapeo_activo'
            };
        });
    }
    // Primer renglón de datos (después del encabezado y sus renglones de continuación).
    get inicioDatos() { return inicioDatos(this.filasCrudas, this.filaEncabezado); }
    get filasDatos() { return this.filasCrudas.slice(this.inicioDatos).filter((f) => this.tieneDatos(f)).length; }
    get textoEncabezado() { return `Encabezados en el renglón ${this.filaEncabezado + 1} · ${this.filasDatos} renglones de datos`; }
    get opcionesEncabezado() {
        return opcionesEncabezado(this.filasCrudas);
    }
    get filaEncabezadoValor() { return String(this.filaEncabezado); }
    handleEncabezado(event) {
        this.filaEncabezado = Number(event.detail.value);
        this.mapeo = this.mapeoAutomatico(this.filasCrudas, this.filaEncabezado);
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
        if (m.nombreCompleto === undefined && m.nombre === undefined && m.apellidoPaterno === undefined && m.apellidos === undefined) {
            this.toast('Censo', 'Indica al menos la columna del nombre del asegurado.', 'warning');
            return;
        }
        const ini = this.inicioDatos;
        const datos = this.filasCrudas.slice(ini)
            .map((f, i) => {
                const o = { fila: ini + i + 1 };
                Object.keys(m).forEach((k) => { o[k] = f[Number(m[k])]; });
                return o;
            })
            .filter((o, i) => this.tieneDatos(this.filasCrudas[ini + i]));
        this.agregarArchivo(datos);
        this.siguienteArchivo();
    }

    cancelar() {
        this.errorMensaje = '';
        this.paso = 'resumen';
        this.renglones = [];
        this.filasCrudas = [];
        this._tabla = null;
        this._cola = [];
        this._acumulado = [];
        this._rangos = [];
        this._endosos = [];
    }
    volverAMapeo() {
        // Con un solo Excel se puede volver a su mapeo; con varios archivos se empieza de nuevo.
        if (this._totalArchivos === 1 && this.filasCrudas.length) {
            this._acumulado = [];
            this._rangos = [];
            this.paso = 'mapeo';
        } else {
            this.cancelar();
        }
    }

    // ============================================================
    // PDF (pdf.js + IA)
    // ============================================================
    async procesarPdf(file) {
        const bloques = await bloquesPdf(this, file, BLOQUE_PDF, (m) => { this.progreso = m; });
        if (!bloques.length) {
            throw new Error('No se pudo leer texto del PDF (¿está escaneado?). Pide el censo en Excel.');
        }
        if (this.esLector && this.leeEndosos) {
            const texto = bloques.join('\n');
            const clausula = clausulaDeTexto(texto);
            const endoso = clausula ? null : endosoDeTexto(texto, file.name);
            if (clausula || endoso) {
                this._endosos.push({ endoso, clausula, documento: file, archivo: file.name });
                return;
            }
        }
        const datos = [];
        for (let i = 0; i < bloques.length; i++) {
            this.progreso = `Analizando con IA: bloque ${i + 1} de ${bloques.length}…`;
            const json = await llamar('CensoColectivo.analizarCensoPdf', { textoCenso: bloques[i] }, analizarCensoPdf);
            let r = {};
            try { r = JSON.parse(json || '{}'); } catch (e) { r = {}; }
            (r.asegurados || []).forEach((a) => datos.push({ ...a, fila: datos.length + 1 }));
        }
        if (!datos.length) {
            throw new Error('La IA no encontró asegurados en el PDF.');
        }
        this.filasCrudas = [];
        this.agregarArchivo(datos);
    }

    // ============================================================
    // Normalización y validación
    // ============================================================
    validar(datos) {
        // Normaliza, liga dependientes con su titular y marca errores/avisos (lógica compartida con Crear Póliza).
        this.renglones = normalizarCenso(datos);
        this.filtro = 'todos';
        this.pagina = 1;
        // Un archivo de movimientos (altas, bajas, cambios) complementa el censo: no lo reemplaza.
        this.modoGuardar = this.hayMovimientos ? 'agregar' : 'reemplazar';
        this.paso = 'vista';
        this.cambiosRevision = [];
        this.revisarMovimientos();
        this.cargarCambios();
    }

    // Cambios del archivo: dato anterior y dato nuevo de cada persona. Si la persona no existe se agrega (internamente
    // es un alta) pero se muestra como cambio.
    async cargarCambios() {
        if (this.esLector || !this._opportunityId) { return; }
        const renglones = this.renglones;
        const cambios = renglones.filter((r) => !r.errores.length && r.movimiento === MOVIMIENTOS.CAMBIO)
            .map((r) => ({ ...payloadMiembro(r), fila: r.fila ?? r.idx + 1, titularIndex: r.esTitular ? null : 0 }));
        if (!cambios.length) { return; }
        let res;
        try {
            res = await revisarCambios({ opportunityId: this._opportunityId, personasJson: JSON.stringify(cambios) }) || [];
        } catch (e) {
            return; // Solo es una vista previa: si falla, la carga sigue.
        }
        if (renglones !== this.renglones) { return; }
        this.cambiosRevision = res.map((c) => ({
            ...c,
            key: 'cr' + c.fila,
            notaTxt: c.existe ? '' : 'No existía: se agrega',
            difs: (c.diferencias || []).map((d, i) => ({ key: `cr${c.fila}-${i}`, ...d })),
            sinDifs: !(c.diferencias || []).length
        }));
    }
    get hayCambiosRevision() { return this.cambiosRevision.length > 0; }

    // Bajas de personas que no existen (ni en el censo ni como contacto del cliente): se marca el renglón con un aviso
    // y se manda el mensaje; se puede guardar igual. Los cambios se revisan aparte (cargarCambios).
    async revisarMovimientos() {
        const revisar = movimientosPorRevisar(this.renglones).filter((p) => this.esLector || p.movimiento === MOVIMIENTOS.BAJA);
        if (!revisar.length || !this._opportunityId) { return; }
        const renglones = this.renglones;
        let faltan;
        try {
            faltan = new Set(await movimientosSinContacto({
                opportunityId: this._opportunityId, accountId: null, personasJson: JSON.stringify(revisar)
            }) || []);
        } catch (e) {
            return; // Solo es un aviso: si la revisión falla, la carga sigue.
        }
        // Se cargó otro archivo mientras se revisaba.
        if (renglones !== this.renglones || !faltan.size) { return; }
        const esMovimiento = (r) => !r.errores.length && (r.movimiento === MOVIMIENTOS.BAJA || r.movimiento === MOVIMIENTOS.CAMBIO);
        this.renglones = renglones.map((r) => (esMovimiento(r) && faltan.has(r.fila ?? r.idx + 1)
            ? { ...r, avisos: [...r.avisos, `${r.movimiento}: ${AVISO_SIN_CONTACTO}`] }
            : r));
        this.toast('Censo', `${faltan.size === 1 ? 'Un movimiento de baja o cambio corresponde a una persona que no está registrada'
            : `${faltan.size} movimientos de baja o cambio corresponden a personas que no están registradas`} en el censo ni como `
            + 'contacto del cliente; las bajas no serán procesadas. El resto de la información puede guardarse normalmente.', 'info');
    }

    fecha(v) {
        return fecha(v);
    }

    numero(v) {
        return numero(v);
    }

    // ============================================================
    // Vista previa
    // ============================================================
    get totalRenglones() { return this.renglones.length; }
    get conError() { return this.renglones.filter((r) => r.errores.length).length; }
    get conAviso() { return this.renglones.filter((r) => !r.errores.length && r.avisos.length).length; }
    // Las bajas (y los dependientes de un titular dado de baja) no se guardan como asegurados.
    get validos() { return this.renglones.filter((r) => !r.errores.length && !r.esBaja); }
    get movimientos() { return conteoMovimientos(this.renglones); }
    get hayMovimientos() { return this.movimientos.hay; }
    get totalValidos() { return this.validos.length; }
    get titularesValidos() { return this.validos.filter((r) => r.esTitular).length; }
    get dependientesValidos() { return this.totalValidos - this.titularesValidos; }
    get hayErrores() { return this.conError > 0; }
    // Bajas del archivo (sin errores) que se aplican al guardar.
    get bajas() { return this.esLector ? [] : movimientosPorRevisar(this.renglones).filter((p) => p.movimiento === MOVIMIENTOS.BAJA); }
    // Lector (Movimientos): se entregan también los renglones de baja para que se comparen contra los asegurados
    // existentes; los dependientes de un titular dado de baja no hacen falta (se dan de baja con él).
    get paraComparar() {
        return this.renglones.filter((r) => !r.errores.length && (!r.esBaja || r.movimiento === MOVIMIENTOS.BAJA));
    }
    get sinValidos() {
        if (this.esLector) { return !this.paraComparar.length || this.cargando; }
        return (this.totalValidos === 0 && !this.bajas.length) || this.cargando;
    }
    get mostrarModo() { return this.tieneCenso && !this.hayMovimientos; }
    get textoGuardar() {
        if (this.esLector) { return `Procesar registros (${this.paraComparar.length})`; }
        const partes = [];
        if (this.totalValidos) { partes.push(`Guardar ${this.totalValidos} asegurados`); }
        if (this.bajas.length) { partes.push(`${partes.length ? 'aplicar' : 'Aplicar'} ${this.bajas.length} baja(s)`); }
        return partes.join(' y ') || 'Guardar';
    }

    get resumenVista() {
        const mapa = {};
        this.validos.forEach((r) => {
            const k = r.categoria || 'Sin categoría';
            const c = mapa[k] || (mapa[k] = { key: k, nombre: k, titulares: 0, dependientes: 0, edades: 0, n: 0, sueldo: 0, suma: 0, prima: 0 });
            if (r.esTitular) { c.titulares++; } else { c.dependientes++; }
            if (r.edad !== null) { c.edades += r.edad; c.n++; }
            c.sueldo += r.sueldoAnual || 0;
            c.suma += r.sumaAsegurada || 0;
            c.prima += r.prima || 0;
        });
        return Object.values(mapa).map((c) => ({
            ...c,
            total: c.titulares + c.dependientes,
            edadTxt: c.n ? (Math.round((c.edades / c.n) * 10) / 10) + ' años' : '—',
            sueldoTxt: this.moneda(c.sueldo),
            sumaTxt: this.moneda(c.suma),
            primaTxt: this.moneda(c.prima)
        }));
    }

    get opcionesFiltro() {
        const ops = [
            { label: `Todos (${this.totalRenglones})`, value: 'todos' },
            { label: `Con error (${this.conError})`, value: 'errores' },
            { label: `Con aviso (${this.conAviso})`, value: 'avisos' }
        ];
        if (this.hayMovimientos) {
            const m = this.movimientos;
            ops.push(
                { label: `Altas (${m.altas})`, value: MOVIMIENTOS.ALTA },
                { label: `Bajas (${m.bajas})`, value: MOVIMIENTOS.BAJA },
                { label: `Cambios (${m.cambios})`, value: MOVIMIENTOS.CAMBIO }
            );
        }
        return ops;
    }
    handleFiltro(event) { this.filtro = event.detail.value; this.pagina = 1; }
    get filtrados() {
        if (this.filtro === 'errores') { return this.renglones.filter((r) => r.errores.length); }
        if (this.filtro === 'avisos') { return this.renglones.filter((r) => !r.errores.length && r.avisos.length); }
        if (Object.values(MOVIMIENTOS).includes(this.filtro)) { return this.renglones.filter((r) => r.movimiento === this.filtro); }
        return this.renglones;
    }
    get renglonesVista() {
        const ini = (this.pagina - 1) * POR_PAGINA;
        return this.filtrados.slice(ini, ini + POR_PAGINA).map((r) => ({
            key: 'r' + r.idx,
            fila: r.fila,
            archivo: this.archivoDe(r.fila),
            nombre: r.nombreCompleto || '(sin nombre)',
            parentesco: r.parentesco,
            titular: r.esTitular ? '' : (r.titularNombre || ''),
            categoria: r.categoria,
            fechaTxt: this.fechaVisible(r.fechaNacimiento),
            edad: r.edad === null ? '' : r.edad,
            sexo: r.sexo,
            certificado: r.certificado,
            sueldoTxt: this.moneda(r.sueldoAnual),
            sumaTxt: this.moneda(r.sumaAsegurada),
            primaTxt: this.moneda(r.prima),
            movimiento: (r.movimiento || r.movimientoOriginal || '') + (r.numeroEndoso ? ` · End. ${r.numeroEndoso}` : ''),
            claseMovimiento: 'chip-movimiento' + (r.movimiento ? ' mov-' + r.movimiento.toLowerCase() : ''),
            mensajes: [...r.errores, ...r.avisos].join(' · '),
            claseFila: (r.errores.length ? 'fila-error' : (r.avisos.length ? 'fila-aviso' : '')) + (r.esTitular ? '' : ' fila-dependiente'),
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
        const bajas = this.bajas;
        if (this.esLector) {
            // Se entrega la lista leída (con las bajas); titularIndex es la posición del titular en la misma lista.
            const lista = this.paraComparar;
            if (!lista.length) { return; }
            const posicion = new Map(lista.map((r, j) => [r.idx, j]));
            const miembros = lista.map((r) => ({ ...this.payload(r), titularIndex: r.esTitular ? null : (posicion.get(r.titularIndex) ?? null) }));
            this.dispatchEvent(new CustomEvent('leido', { detail: { miembros, archivo: this.archivoNombre, endosos: this._endosos } }));
            this.cancelar();
            return;
        }
        if (!validos.length && !bajas.length) { return; }
        // Grupos titular + dependientes, para no separarlos entre lotes.
        const nuevoIdx = new Map();
        validos.forEach((r, i) => nuevoIdx.set(r.idx, i));
        const grupos = [];
        validos.forEach((r) => {
            if (r.esTitular) { grupos.push([r]); return; }
            const g = grupos.find((x) => x[0].idx === r.titularIndex);
            if (g) { g.push(r); }
        });
        const lotes = [];
        let lote = [];
        grupos.forEach((g) => {
            if (lote.length && lote.length + g.length > LOTE) { lotes.push(lote); lote = []; }
            lote.push(...g);
        });
        if (lote.length) { lotes.push(lote); }

        this.cargando = true;
        let total = 0;
        const movimientos = this.hayMovimientos;
        try {
            for (let i = 0; i < lotes.length; i++) {
                this.progreso = lotes.length > 1 ? `Guardando lote ${i + 1} de ${lotes.length}…` : 'Guardando censo…';
                const posicion = new Map(lotes[i].map((r, j) => [r.idx, j]));
                const payload = lotes[i].map((r) => ({
                    ...this.payload(r),
                    titularIndex: r.esTitular ? null : posicion.get(r.titularIndex)
                }));
                if (movimientos) {
                    // Altas y cambios: se agregan los que falten y se completan los que ya están (sin duplicar).
                    const r = await complementarCenso({ opportunityId: this._opportunityId, miembrosJson: JSON.stringify(payload) });
                    total = (r && r.total) || total;
                } else {
                    total = await guardarCenso({
                        opportunityId: this._opportunityId,
                        miembrosJson: JSON.stringify(payload),
                        reemplazar: i === 0 && (this.modoGuardar === 'reemplazar' || !this.tieneCenso)
                    });
                }
            }
            const partes = [];
            if (lotes.length) { partes.push(`Censo guardado: ${total} asegurados.`); }
            if (bajas.length) {
                this.progreso = 'Aplicando bajas…';
                const r = await aplicarBajas({ opportunityId: this._opportunityId, policyId: null, personasJson: JSON.stringify(bajas) }) || {};
                partes.push(`${r.censo || 0} asegurado(s) dados de baja del censo.`);
                const faltan = (r.noEncontrados || []).length;
                if (faltan) {
                    this.toast('Censo', `${faltan === 1 ? 'Una baja no fue procesada porque la persona no está registrada'
                        : `${faltan} bajas no fueron procesadas porque las personas no están registradas`} en el censo. Se recomienda validar la información con la aseguradora.`, 'info');
                }
            }
            this.toast('Censo', partes.join(' '), 'success');
            this.cancelar();
            await this.cargarCenso();
        } catch (e) {
            this.toast('Censo', this.mensaje(e), 'error');
        } finally {
            this.cargando = false;
            this.progreso = '';
        }
    }

    // Renglón validado en el formato de CensoColectivoController.MiembroEntrada (sin titularIndex).
    payload(r) {
        return payloadMiembro(r);
    }

    // ============================================================
    // Utilidades
    // ============================================================
    fold(v) {
        return fold(v);
    }
    textoCelda(v, tipo) {
        if (tipo === 'fecha') { const f = this.fecha(v); return f.iso ? this.fechaVisible(f.iso) : String(v); }
        return String(v).substring(0, 40);
    }
    fechaVisible(iso) {
        return fechaVisible(iso);
    }
    moneda(n) {
        return moneda(n);
    }
    mensaje(e) {
        return (e && e.body && e.body.message) || (e && e.message) || 'Ocurrió un error inesperado.';
    }
    toast(title, message, variant) {
        // Los errores también se muestran dentro del componente (el toast desaparece solo).
        this.errorMensaje = variant === 'error' ? message : '';
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
