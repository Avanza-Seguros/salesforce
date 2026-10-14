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
    mapeoAutomatico, opcionesColumnas, opcionesEncabezado, bloquesPdf, inicioDatos
} from 'c/lectorArchivos';
import getCenso from '@salesforce/apex/CensoColectivoController.getCenso';
import guardarCenso from '@salesforce/apex/CensoColectivoController.guardarCenso';
import eliminarCenso from '@salesforce/apex/CensoColectivoController.eliminarCenso';
import analizarCensoPdf from '@salesforce/apex/CensoColectivoController.analizarCensoPdf';

// Campos del censo: clave (la misma que devuelve la IA), etiqueta y encabezados con que suele venir.
const CAMPOS = [
    { key: 'nombreCompleto', label: 'Nombre completo', alias: ['nombre completo', 'nombre del asegurado', 'nombre asegurado', 'asegurado', 'nombre y apellidos', 'nombre del empleado', 'empleado', 'nombre completo del asegurado'] },
    { key: 'nombre', label: 'Nombre(s)', alias: ['nombre', 'nombres', 'nombre s', 'primer nombre'] },
    { key: 'apellidoPaterno', label: 'Apellido paterno', alias: ['apellido paterno', 'paterno', 'ap paterno', 'primer apellido', 'a paterno'] },
    { key: 'apellidoMaterno', label: 'Apellido materno', alias: ['apellido materno', 'materno', 'ap materno', 'segundo apellido', 'a materno'] },
    { key: 'apellidos', label: 'Apellidos', alias: ['apellidos', 'apellido'] },
    { key: 'fechaNacimiento', label: 'Fecha de nacimiento', tipo: 'fecha', alias: ['fecha de nacimiento', 'fecha nacimiento', 'f nacimiento', 'nacimiento', 'fec nac', 'f nac', 'fecha nac', 'fnac'] },
    { key: 'edad', label: 'Edad', tipo: 'numero', alias: ['edad', 'edad actual', 'edad alcanzada'] },
    { key: 'sexo', label: 'Sexo', alias: ['sexo', 'genero', 'sex'] },
    { key: 'parentesco', label: 'Parentesco', alias: ['parentesco', 'tipo de asegurado', 'tipo asegurado', 'relacion', 'dependencia', 'tipo de dependiente'] },
    { key: 'categoria', label: 'Categoría', alias: ['categoria', 'grupo', 'clase', 'nivel', 'grupo asegurado', 'subgrupo', 'regla'] },
    { key: 'sueldoMensual', label: 'Sueldo mensual', tipo: 'numero', alias: ['sueldo mensual', 'salario mensual', 'sueldo', 'salario', 'sueldo base'] },
    { key: 'sueldoAnual', label: 'Sueldo anual', tipo: 'numero', alias: ['sueldo anual', 'salario anual', 'ingreso anual'] },
    { key: 'sumaAsegurada', label: 'Suma asegurada', tipo: 'numero', alias: ['suma asegurada', 'sa', 's a', 'suma aseg'] },
    { key: 'certificado', label: 'Certificado', alias: ['certificado', 'no certificado', 'num certificado', 'numero de certificado', 'cert', 'no de certificado'] },
    { key: 'fechaAlta', label: 'Fecha de alta', tipo: 'fecha', alias: ['fecha de alta', 'fecha alta', 'alta', 'fecha de ingreso', 'fecha ingreso', 'antiguedad', 'fecha de antiguedad'] },
    { key: 'numEmpleado', label: 'Núm. de empleado', alias: ['numero de empleado', 'no empleado', 'num empleado', 'no de empleado', 'nomina', 'no nomina', 'id empleado', 'clave empleado', 'clave'] },
    { key: 'rfc', label: 'RFC', alias: ['rfc'] },
    { key: 'email', label: 'Correo', alias: ['email', 'correo', 'correo electronico', 'e mail', 'mail'] },
    { key: 'telefono', label: 'Teléfono', alias: ['telefono', 'celular', 'tel', 'movil'] }
];

// Parentescos que se reconocen (texto normalizado -> valor que se muestra y se guarda).
const PARENTESCOS = [
    { valor: 'Titular', claves: ['titular', 'empleado', 'asegurado titular', 'principal', 'trabajador', 't', 'e', 'tit', 'asegurado', 'socio', 'self', 'miembro', 'colaborador'] },
    { valor: 'Cónyuge', claves: ['conyuge', 'esposo', 'esposa', 'c', 'concubino', 'concubina', 'pareja', 'spouse', 'esp'] },
    { valor: 'Hijo(a)', claves: ['hijo', 'hija', 'hijo a', 'hijos', 'h', 'child', 'dependiente hijo'] },
    { valor: 'Padre/Madre', claves: ['padre', 'madre', 'papa', 'mama', 'parent'] },
    { valor: 'Suegro(a)', claves: ['suegro', 'suegra'] }
];

const POR_PAGINA = 50;
// Asegurados por llamada a Apex (el controlador acepta hasta 4,500).
const LOTE = 2000;
// Caracteres de texto por bloque que se manda a la IA (PDFs largos se parten).
const BLOQUE_PDF = 12000;

export default class CensoColectivo extends LightningElement {
    @api readOnly = false;

    @track censo = null;
    @track paso = 'resumen';
    @track mapeo = {};
    @track renglones = [];
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
    get puedeEditar() { return !this.readOnly && !!this._opportunityId; }
    get sinOportunidad() { return !this._opportunityId; }

    get totalCategorias() { return this.censo && this.censo.categorias ? this.censo.categorias.length : 0; }
    get categoriasCenso() {
        return ((this.censo && this.censo.categorias) || []).map((c) => ({
            ...c,
            key: c.nombre,
            total: (c.titulares || 0) + (c.dependientes || 0),
            edadTxt: c.edadPromedio === null || c.edadPromedio === undefined ? '—' : c.edadPromedio + ' años',
            sueldoTxt: this.moneda(c.sueldoTotal),
            sumaTxt: this.moneda(c.sumaAseguradaTotal)
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
            sumaTxt: this.moneda(m.sumaAsegurada)
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
            'Certificado,Num. empleado,Nombre,Apellido paterno,Apellido materno,Fecha de nacimiento,Sexo,Parentesco,Categoria,Sueldo mensual,Suma asegurada,Fecha de alta,RFC,Correo,Telefono',
            '001,E-100,Juan,Perez,Lopez,14/03/1985,H,Titular,Directivos,45000,1000000,01/01/2020,PELJ850314AB1,juan.perez@empresa.com,5512345678',
            '001,E-100,Maria,Sosa,Ruiz,02/07/1988,M,Conyuge,Directivos,,,01/01/2020,,,',
            '001,E-100,Sofia,Perez,Sosa,10/05/2015,M,Hijo,Directivos,,,01/01/2020,,,',
            '002,E-101,Pedro,Gomez,Diaz,22/11/1990,H,Titular,Empleados,18000,500000,15/06/2022,,,'
        ];
        const a = document.createElement('a');
        a.href = 'data:text/csv;charset=utf-8,' + encodeURIComponent('﻿' + filas.join('\r\n'));
        a.download = 'Plantilla_censo_colectivo.csv';
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
            this.toast('Censo', this.mensaje(e), 'error');
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
        const mapeo = mapeoAutomatico(filas, h, CAMPOS);
        if (mapeo.nombre !== undefined && mapeo.nombreCompleto === undefined
            && mapeo.apellidoPaterno === undefined && mapeo.apellidos === undefined) {
            mapeo.nombreCompleto = mapeo.nombre;
            delete mapeo.nombre;
        }
        return mapeo;
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
            throw new Error('No se pudo leer texto del PDF (¿está escaneado?). Pide el censo en Excel.');
        }
        const datos = [];
        for (let i = 0; i < bloques.length; i++) {
            this.progreso = `Analizando con IA: bloque ${i + 1} de ${bloques.length}…`;
            const json = await analizarCensoPdf({ textoCenso: bloques[i] });
            let r = {};
            try { r = JSON.parse(json || '{}'); } catch (e) { r = {}; }
            (r.asegurados || []).forEach((a) => datos.push({ ...a, fila: datos.length + 1 }));
        }
        if (!datos.length) {
            throw new Error('La IA no encontró asegurados en el PDF.');
        }
        this.filasCrudas = [];
        this.validar(datos);
    }

    // ============================================================
    // Normalización y validación
    // ============================================================
    validar(datos) {
        // "M" es Mujer salvo que el archivo use M/F (Masculino/Femenino).
        const usaMF = datos.some((d) => ['f', 'femenino', 'fem'].includes(this.fold(d.sexo)));
        const renglones = datos
            .map((d) => this.normalizar(d, usaMF))
            .filter((r) => r.nombreCompleto || r.parentescoOriginal || r.fechaNacimiento)
            // Renglones de totales/subtotales al final de muchos censos.
            .filter((r) => !/^(sub)?total(es)?\b/.test(this.fold(r.nombreCompleto)));

        // Liga dependientes con su titular: mismo certificado o núm. de empleado; si no, el titular anterior.
        const porLlave = {};
        const vistos = {};
        let ultimoTitular = null;
        renglones.forEach((r, i) => {
            r.idx = i;
            if (r.esTitular) {
                ultimoTitular = i;
                [r.certificado, r.numEmpleado].forEach((k) => { if (k) { porLlave[this.fold(k)] = i; } });
            } else {
                let t;
                [r.certificado, r.numEmpleado].forEach((k) => {
                    if (t === undefined && k) {
                        const base = this.fold(String(k).split(/[-/]/)[0]);
                        t = porLlave[this.fold(k)] ?? porLlave[base];
                    }
                });
                r.titularIndex = t ?? ultimoTitular;
                if (r.titularIndex === null || r.titularIndex === undefined) {
                    r.errores.push('Dependiente sin titular antes de él');
                } else {
                    const tit = renglones[r.titularIndex];
                    r.titularNombre = tit.nombreCompleto;
                    if (!r.categoria) { r.categoria = tit.categoria; }
                }
            }
            if (!r.nombreCompleto) { r.errores.push('Sin nombre'); }
            const llave = this.fold(r.nombreCompleto) + '|' + (r.fechaNacimiento || r.edad || '');
            if (r.nombreCompleto && vistos[llave] !== undefined) {
                r.avisos.push(`Posible duplicado de la fila ${renglones[vistos[llave]].fila}`);
            } else if (r.nombreCompleto) {
                vistos[llave] = i;
            }
        });
        // Un dependiente cuyo titular tiene errores tampoco se puede guardar.
        renglones.forEach((r) => {
            if (!r.esTitular && r.titularIndex != null && renglones[r.titularIndex].errores.length) {
                r.errores.push(`Su titular (fila ${renglones[r.titularIndex].fila}) tiene errores`);
            }
        });
        this.renglones = renglones;
        this.filtro = 'todos';
        this.pagina = 1;
        this.modoGuardar = 'reemplazar';
        this.paso = 'vista';
    }

    normalizar(d, usaMF) {
        const txt = (v) => (v === undefined || v === null ? '' : String(v).replace(/\s+/g, ' ').trim());
        const r = { fila: d.fila, errores: [], avisos: [] };
        const apellidos = txt(d.apellidos) || [txt(d.apellidoPaterno), txt(d.apellidoMaterno)].filter((x) => x).join(' ');
        r.nombre = txt(d.nombre);
        r.apellidos = apellidos;
        r.nombreCompleto = txt(d.nombreCompleto) || [r.nombre, apellidos].filter((x) => x).join(' ');
        // Formato "APELLIDOS, NOMBRES".
        if (!r.nombre && !apellidos && r.nombreCompleto.includes(',')) {
            const [ap, nom] = r.nombreCompleto.split(',');
            r.apellidos = txt(ap);
            r.nombre = txt(nom);
            r.nombreCompleto = [r.nombre, r.apellidos].filter((x) => x).join(' ');
        }

        const fn = this.fecha(d.fechaNacimiento);
        if (fn.invalida) { r.avisos.push(`Fecha de nacimiento no válida (${txt(d.fechaNacimiento)})`); }
        r.fechaNacimiento = fn.iso;
        const fa = this.fecha(d.fechaAlta);
        if (fa.invalida) { r.avisos.push(`Fecha de alta no válida (${txt(d.fechaAlta)})`); }
        r.fechaAlta = fa.iso;
        let edad = this.numero(d.edad);
        if (r.fechaNacimiento) { edad = this.edadDe(r.fechaNacimiento); }
        r.edad = edad === null ? null : Math.floor(edad);
        if (r.edad === null) { r.avisos.push('Sin fecha de nacimiento ni edad'); }
        else if (r.edad < 0 || r.edad > 99) { r.avisos.push(`Edad fuera de rango (${r.edad})`); }

        const s = this.fold(d.sexo);
        if (['h', 'hombre', 'masculino', 'masc', 'male', 'varon'].includes(s) || (s === 'm' && usaMF)) { r.sexo = 'Hombre'; }
        else if (['mujer', 'f', 'femenino', 'fem', 'female'].includes(s) || (s === 'm' && !usaMF)) { r.sexo = 'Mujer'; }
        else { r.sexo = ''; }

        r.parentescoOriginal = txt(d.parentesco);
        const p = this.fold(d.parentesco);
        const encontrado = PARENTESCOS.find((x) => x.claves.includes(p) || x.claves.some((k) => k.length > 3 && p.startsWith(k)));
        r.parentesco = !p ? 'Titular' : (encontrado ? encontrado.valor : 'Otro');
        if (p && !encontrado) { r.avisos.push(`Parentesco "${r.parentescoOriginal}" se guardará como Otro`); }
        r.esTitular = r.parentesco === 'Titular';

        r.categoria = txt(d.categoria);
        const mensual = this.numero(d.sueldoMensual);
        const anual = this.numero(d.sueldoAnual);
        r.sueldoAnual = anual !== null ? anual : (mensual !== null ? Math.round(mensual * 12 * 100) / 100 : null);
        r.sumaAsegurada = this.numero(d.sumaAsegurada);
        r.certificado = txt(d.certificado).replace(/\.0+$/, '');
        r.numEmpleado = txt(d.numEmpleado).replace(/\.0+$/, '');
        r.rfc = txt(d.rfc).toUpperCase();
        r.email = txt(d.email);
        r.telefono = txt(d.telefono).replace(/\.0+$/, '');
        return r;
    }

    fecha(v) {
        return fecha(v);
    }

    numero(v) {
        return numero(v);
    }

    edadDe(iso) {
        const [a, m, d] = iso.split('-').map(Number);
        const hoy = new Date();
        let e = hoy.getFullYear() - a;
        if (hoy.getMonth() + 1 < m || (hoy.getMonth() + 1 === m && hoy.getDate() < d)) { e--; }
        return e;
    }

    // ============================================================
    // Vista previa
    // ============================================================
    get totalRenglones() { return this.renglones.length; }
    get conError() { return this.renglones.filter((r) => r.errores.length).length; }
    get conAviso() { return this.renglones.filter((r) => !r.errores.length && r.avisos.length).length; }
    get validos() { return this.renglones.filter((r) => !r.errores.length); }
    get totalValidos() { return this.validos.length; }
    get titularesValidos() { return this.validos.filter((r) => r.esTitular).length; }
    get dependientesValidos() { return this.totalValidos - this.titularesValidos; }
    get hayErrores() { return this.conError > 0; }
    get sinValidos() { return this.totalValidos === 0 || this.cargando; }
    get textoGuardar() { return `Guardar ${this.totalValidos} asegurados`; }

    get resumenVista() {
        const mapa = {};
        this.validos.forEach((r) => {
            const k = r.categoria || 'Sin categoría';
            const c = mapa[k] || (mapa[k] = { key: k, nombre: k, titulares: 0, dependientes: 0, edades: 0, n: 0, sueldo: 0, suma: 0 });
            if (r.esTitular) { c.titulares++; } else { c.dependientes++; }
            if (r.edad !== null) { c.edades += r.edad; c.n++; }
            c.sueldo += r.sueldoAnual || 0;
            c.suma += r.sumaAsegurada || 0;
        });
        return Object.values(mapa).map((c) => ({
            ...c,
            total: c.titulares + c.dependientes,
            edadTxt: c.n ? (Math.round((c.edades / c.n) * 10) / 10) + ' años' : '—',
            sueldoTxt: this.moneda(c.sueldo),
            sumaTxt: this.moneda(c.suma)
        }));
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
        if (!validos.length) { return; }
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
        try {
            for (let i = 0; i < lotes.length; i++) {
                this.progreso = lotes.length > 1 ? `Guardando lote ${i + 1} de ${lotes.length}…` : 'Guardando censo…';
                const posicion = new Map(lotes[i].map((r, j) => [r.idx, j]));
                const payload = lotes[i].map((r) => ({
                    fila: r.fila,
                    nombreCompleto: r.nombreCompleto,
                    nombre: r.nombre,
                    apellidos: r.apellidos,
                    fechaNacimiento: r.fechaNacimiento || null,
                    edad: r.edad,
                    sexo: r.sexo,
                    parentesco: r.parentesco,
                    categoria: r.categoria,
                    sueldoAnual: r.sueldoAnual,
                    sumaAsegurada: r.sumaAsegurada,
                    certificado: r.certificado,
                    fechaAlta: r.fechaAlta || null,
                    numEmpleado: r.numEmpleado,
                    rfc: r.rfc,
                    email: r.email,
                    telefono: r.telefono,
                    titularIndex: r.esTitular ? null : posicion.get(r.titularIndex)
                }));
                total = await guardarCenso({
                    opportunityId: this._opportunityId,
                    miembrosJson: JSON.stringify(payload),
                    reemplazar: i === 0 && (this.modoGuardar === 'reemplazar' || !this.tieneCenso)
                });
            }
            this.toast('Censo', `Censo guardado: ${total} asegurados.`, 'success');
            this.cancelar();
            await this.cargarCenso();
        } catch (e) {
            this.toast('Censo', this.mensaje(e), 'error');
        } finally {
            this.cargando = false;
            this.progreso = '';
        }
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
