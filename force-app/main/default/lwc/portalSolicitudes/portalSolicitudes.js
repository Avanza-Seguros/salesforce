// portalSolicitudes/portalSolicitudes.js
// Pestaña Solicitudes del detalle de la póliza en el sitio: el contratante pide altas, bajas y cambios (se crea un
// caso «Solicitud de movimientos» y los movimientos se registran en la póliza con su folio) y ve el estado de las que
// ya envió. La solicitud se puede capturar uno por uno o subir un archivo (Excel o CSV) con todos los datos: el archivo
// se lee en el navegador, se reconocen sus columnas por el encabezado y cada renglón es un movimiento; el archivo
// también queda adjunto al caso.
import { LightningElement, api } from 'lwc';
import solicitudes from '@salesforce/apex/PortalPolizasPestanas.solicitudes';
import crearSolicitud from '@salesforce/apex/PortalPolizasPestanas.crearSolicitud';
import registrosPoliza from '@salesforce/apex/PortalPolizasPestanas.registrosPoliza';
import { abrirTabla, detectarEncabezado, inicioDatos, mapeoAutomatico, tieneDatos, letraColumna, fold, fecha as fechaIso, fechaVisible,
    descargarExcel, renglonesEncabezadoAbajo } from 'c/lectorArchivos';

// Igual que PortalPolizasPestanas.MAX_BYTES_SOLICITUD.
const MAX_BYTES = 4 * 1024 * 1024;
// Renglones del archivo que se mandan para el detalle del caso (el archivo completo va adjunto).
const MAX_FILAS = 2000;
const VISTA_FILAS = 8;

// Columnas que se reconocen en el archivo (por su encabezado), según lo que asegura la póliza. Con ellas los
// movimientos se registran en la póliza al enviar la solicitud. «fecha» es la columna con fecha (se pasa a AAAA-MM-DD).
const MOVIMIENTO = { key: 'movimiento', etiqueta: 'Movimiento', alias: ['movimiento', 'movimiento alta baja o cambio', 'tipo de movimiento',
    'tipo movimiento', 'alta baja o cambio', 'tipo de peticion', 'peticion'] };
const FECHA = { key: 'fecha', etiqueta: 'Fecha del movimiento', fecha: true, alias: ['fecha del movimiento', 'fecha de movimiento',
    'fecha movimiento', 'fecha de alta', 'fecha de baja', 'fecha de peticion', 'fecha'] };
const COMENTARIO = { key: 'comentario', etiqueta: 'Comentario', alias: ['comentario', 'comentarios', 'observaciones', 'motivo',
    'motivo de baja', 'nota', 'notas', 'descripcion del cambio'] };
// Número de póliza del renglón: puede ser otra póliza del mismo contratante (el movimiento se registra en esa).
const POLIZA = { key: 'poliza', etiqueta: 'Número de póliza', alias: ['numero de poliza', 'no de poliza', 'poliza', 'num poliza'] };
const COLUMNAS = {
    vehiculos: [MOVIMIENTO,
        { key: 'inciso', etiqueta: 'Inciso', alias: ['inciso', 'no inciso', 'numero de inciso', 'no de inciso'] },
        { key: 'serie', etiqueta: 'Serie', alias: ['serie', 'numero de serie', 'no de serie', 'no serie', 'niv', 'vin', 'series'] },
        { key: 'placas', etiqueta: 'Placas', alias: ['placas', 'placa', 'no de placas'] },
        { key: 'marca', etiqueta: 'Marca', alias: ['marca'] },
        { key: 'submarca', etiqueta: 'Submarca', alias: ['submarca', 'linea'] },
        { key: 'version', etiqueta: 'Versión', alias: ['version', 'tipo de vehiculo'] },
        { key: 'descripcion', etiqueta: 'Descripción', alias: ['descripcion', 'vehiculo', 'descripcion del vehiculo', 'unidad'] },
        { key: 'modelo', etiqueta: 'Modelo', alias: ['modelo', 'ano', 'anio', 'ano modelo', 'modelo ano'] },
        { key: 'uso', etiqueta: 'Uso', alias: ['uso', 'uso del vehiculo'] },
        FECHA, COMENTARIO, POLIZA],
    personas: [MOVIMIENTO,
        { key: 'certificado', etiqueta: 'Certificado', alias: ['certificado', 'no certificado', 'numero de certificado', 'no de certificado'] },
        { key: 'nombreCompleto', etiqueta: 'Nombre completo', alias: ['nombre completo', 'asegurado', 'nombre del asegurado'] },
        { key: 'nombre', etiqueta: 'Nombre(s)', alias: ['nombre', 'nombres', 'nombre s'], excluir: ['titular'] },
        { key: 'paterno', etiqueta: 'Apellido paterno', alias: ['apellido paterno', 'paterno', 'primer apellido'] },
        { key: 'materno', etiqueta: 'Apellido materno', alias: ['apellido materno', 'materno', 'segundo apellido'] },
        { key: 'nacimiento', etiqueta: 'Fecha de nacimiento', fecha: true, alias: ['fecha de nacimiento', 'nacimiento', 'fecha nacimiento', 'f nacimiento'] },
        { key: 'sexo', etiqueta: 'Sexo', alias: ['sexo', 'genero'] },
        { key: 'parentesco', etiqueta: 'Parentesco', alias: ['parentesco', 'relacion'] },
        { key: 'titular', etiqueta: 'Titular', alias: ['titular', 'titular si es dependiente', 'nombre del titular', 'certificado del titular'] },
        { key: 'correo', etiqueta: 'Correo', alias: ['correo', 'correo electronico', 'email', 'e mail', 'mail'] },
        { key: 'categoria', etiqueta: 'Categoría', alias: ['categoria', 'clase', 'categoria del asegurado'] },
        { key: 'fechaAntiguedad', etiqueta: 'Fecha de antigüedad', fecha: true, alias: ['fecha de antiguedad', 'antiguedad',
            'fecha antiguedad', 'reconocimiento de antiguedad'] },
        FECHA, COMENTARIO, POLIZA],
    ubicaciones: [MOVIMIENTO,
        { key: 'inciso', etiqueta: 'Inciso', alias: ['inciso', 'no inciso', 'numero de inciso'] },
        { key: 'ubicacion', etiqueta: 'Nombre de la ubicación', alias: ['nombre de la ubicacion', 'ubicacion', 'nombre', 'sucursal'] },
        { key: 'direccion', etiqueta: 'Dirección', alias: ['direccion', 'domicilio', 'calle y numero', 'calle', 'direccion completa'] },
        { key: 'colonia', etiqueta: 'Colonia', alias: ['colonia'] },
        { key: 'cp', etiqueta: 'Código postal', alias: ['codigo postal', 'cp', 'c p'] },
        { key: 'municipio', etiqueta: 'Municipio', alias: ['municipio', 'alcaldia', 'delegacion', 'ciudad'] },
        { key: 'estado', etiqueta: 'Estado', alias: ['estado', 'entidad', 'entidad federativa'] },
        { key: 'giro', etiqueta: 'Giro', alias: ['giro', 'actividad', 'giro o actividad'] },
        { key: 'suma', etiqueta: 'Suma asegurada', alias: ['suma asegurada', 'suma', 'valor'] },
        FECHA, COMENTARIO, POLIZA]
};
// Columnas que el archivo debe traer (al menos una de cada grupo), según el movimiento.
const REQUERIDAS = {
    vehiculos: { alta: [['serie'], ['descripcion', 'marca', 'version']], otro: [['serie', 'placas', 'inciso']] },
    personas: { alta: [['nombre', 'nombreCompleto']], otro: [['certificado', 'nombre', 'nombreCompleto']] },
    ubicaciones: { alta: [['direccion']], otro: [['inciso', 'ubicacion']] }
};

// Plantilla genérica (un solo Excel para altas, bajas y cambios: la columna Tipo de movimiento dice cuál es cada
// renglón), según lo que asegura la póliza.
const PLANTILLA = {
    personas: ['Nombre(s)', 'Apellido paterno', 'Apellido materno', 'Fecha de nacimiento', 'Parentesco', 'Sexo (M/F)',
        'Tipo de movimiento', 'Fecha de petición', 'Número de póliza', 'Categoría', 'Certificado', 'Fecha de antigüedad',
        'Correo electrónico', 'Comentarios'],
    vehiculos: ['Tipo de movimiento', 'Fecha de petición', 'Número de póliza', 'Inciso', 'Modelo', 'Marca', 'Versión', 'Serie',
        'Placas', 'Uso', 'Comentarios'],
    ubicaciones: ['Tipo de movimiento', 'Fecha de petición', 'Número de póliza', 'Inciso', 'Nombre de la ubicación', 'Calle y número',
        'Colonia', 'Código postal', 'Municipio', 'Estado', 'Giro', 'Suma asegurada', 'Comentarios']
};
// Una alta puede ser de hasta 30 días atrás (igual que PortalPolizasPestanas.DIAS_RETROACTIVOS).
const DIAS_RETROACTIVOS = 30;
// Documentos de reconocimiento de antigüedad (RA), por su nombre (igual que PortalPolizasPestanas.ARCHIVO_RA).
const ARCHIVO_RA = /antig|carta|caratula|complemento/;
const SEGUIMIENTO = {
    Solicitado: 'estado estado_pendiente',
    'En proceso': 'estado estado_proceso',
    Concluido: 'estado estado_vigente',
    Rechazada: 'estado estado_rechazada'
};

// Datos que se piden en un alta, según lo que asegura la póliza.
const CAMPOS_ALTA = {
    personas: [
        { clave: 'nombre', etiqueta: 'Nombre(s)', requerido: true },
        { clave: 'paterno', etiqueta: 'Apellido paterno', requerido: true },
        { clave: 'materno', etiqueta: 'Apellido materno' },
        { clave: 'nacimiento', etiqueta: 'Fecha de nacimiento', tipo: 'date', requerido: true },
        { clave: 'sexo', etiqueta: 'Sexo', etiquetaCambio: 'Corrección de género', opciones: ['Mujer', 'Hombre'], requerido: true },
        // Un parentesco nuevo es un alta, no un cambio.
        { clave: 'parentesco', etiqueta: 'Parentesco', soloAlta: true, opciones: ['Titular', 'Cónyuge', 'Hijo(a)', 'Padre/Madre', 'Otro'], requerido: true },
        { clave: 'correo', etiqueta: 'Correo electrónico', tipo: 'email' }
    ],
    vehiculos: [
        { clave: 'descripcion', etiqueta: 'Vehículo (marca, submarca y versión)', requerido: true },
        { clave: 'modelo', etiqueta: 'Modelo (año)', requerido: true },
        { clave: 'serie', etiqueta: 'Número de serie', requerido: true },
        { clave: 'placas', etiqueta: 'Placas' },
        { clave: 'uso', etiqueta: 'Uso' }
    ],
    ubicaciones: [
        { clave: 'ubicacion', etiqueta: 'Nombre de la ubicación', requerido: true },
        { clave: 'direccion', etiqueta: 'Dirección completa', requerido: true },
        { clave: 'giro', etiqueta: 'Giro o actividad' },
        { clave: 'suma', etiqueta: 'Suma asegurada', tipo: 'number' }
    ]
};
const NOMBRES = { personas: ['asegurado', 'asegurados'], vehiculos: ['vehículo', 'vehículos'], ubicaciones: ['ubicación', 'ubicaciones'] };
const ESTADOS = {
    Recibida: 'estado estado_pendiente',
    'En proceso': 'estado estado_proceso',
    Cerrada: 'estado estado_vigente',
    Rechazada: 'estado estado_rechazada'
};

let siguiente = 1;

export default class PortalSolicitudes extends LightningElement {
    _policyId;
    @api cuentaVistaPrevia;
    @api
    get policyId() { return this._policyId; }
    set policyId(v) {
        const cambio = v !== this._policyId;
        this._policyId = v;
        if (cambio && this.conectado) { this.cargar(); }
    }

    conectado = false;
    cargando = false;
    enviando = false;
    error;
    datos;
    formulario = false;
    movimientos = [];
    comentario = '';
    archivos = [];
    exito;
    abiertas = new Set();

    connectedCallback() {
        this.conectado = true;
        this.cargar();
    }

    async cargar() {
        if (!this._policyId) { return; }
        this.cargando = true;
        this.error = undefined;
        try {
            this.datos = await solicitudes({ policyId: this._policyId, cuentaVistaPrevia: this.cuentaVistaPrevia || null });
        } catch (e) {
            this.error = this.mensaje(e);
        } finally {
            this.cargando = false;
        }
    }

    // ===== Lista =====
    get tipo() { return (this.datos && this.datos.tipo) || 'personas'; }
    get nombreRegistro() { return NOMBRES[this.tipo][0]; }
    get puedeSolicitar() { return !!this.datos && this.datos.puedeSolicitar; }
    get avisoSinPermiso() {
        if (!this.datos || this.datos.puedeSolicitar) { return null; }
        if (!this.datos.esContratante) { return 'Las solicitudes de altas, bajas y cambios las envía el contratante de la póliza.'; }
        if (this.datos.esEmpresarial === false) {
            return 'Las solicitudes de altas, bajas y cambios son para pólizas empresariales (colectivas o flotillas). Para esta póliza, contacta a tu asesor.';
        }
        return null;
    }
    get haySolicitudes() { return !!this.datos && this.datos.solicitudes.length > 0; }
    get esPersonas() { return this.tipo === 'personas'; }
    get etiquetaClave() { return this.tipo === 'personas' ? 'Certificado' : 'Inciso'; }
    get lista() {
        if (!this.datos) { return []; }
        return this.datos.solicitudes.map((s) => {
            const abierta = this.abiertas.has(s.folio);
            const asunto = String(s.asunto || '').split(' · ');
            // Archivo con los datos (subir archivo): el que menciona el asunto.
            const enAsunto = /archivo (.+?)(?: \(\d+ rengl[oó]n(?:es)?\))?$/.exec(asunto.slice(2).join(' · ').replace(/ · con RA$/, ''));
            const conteo = [['altas', 'alta', 'altas'], ['bajas', 'baja', 'bajas'], ['cambios', 'cambio', 'cambios']]
                .filter(([k]) => s[k]).map(([k, uno, varios]) => `${s[k]} ${s[k] === 1 ? uno : varios}`);
            const movimientos = (s.movimientos || []).map((m, i) => ({
                ...m,
                key: s.folio + '-' + i,
                nacimientoTxt: fechaVisible(m.nacimiento),
                fechaTxt: fechaVisible(m.fecha),
                claseTipo: `estado estado_${String(m.tipo || '').toLowerCase()}`,
                claseSeguimiento: SEGUIMIENTO[m.seguimiento] || 'estado'
            }));
            return {
                ...s,
                resumen: asunto.length > 2 ? asunto.slice(2).join(' · ') : '',
                fechaTexto: this.fecha(s.fecha),
                claseEstado: ESTADOS[s.estado] || 'estado',
                abierta,
                textoVer: abierta ? 'Ocultar detalle' : 'Ver detalle',
                // Detalle de la solicitud: origen, caso, quién la envió, archivo, registros y lo que pidió.
                archivoTxt: enAsunto ? enAsunto[1] : ((s.archivos || []).join(', ') || '—'),
                registrosTxt: `${s.aplicados || 0}${conteo.length ? ' (' + conteo.join(', ') + ')' : ''}`,
                seguimientoTxt: s.seguimiento,
                claseSeguimiento: SEGUIMIENTO[s.seguimiento] || 'estado',
                cierreTxt: s.cierre ? this.fecha(s.cierre) : '',
                movimientos,
                hayMovimientos: movimientos.length > 0,
                detalle: String(s.descripcion || '').split('\n').filter((l) => /^\d+\./.test(l)),
                hayDetalle: String(s.descripcion || '').split('\n').some((l) => /^\d+\./.test(l)),
                avance: s.aplicados ? `${s.aplicados} ${s.aplicados === 1 ? 'movimiento aplicado' : 'movimientos aplicados'}${s.abiertos ? ` · ${s.abiertos} en trámite con la aseguradora` : ''}` : '',
                endososTexto: s.endosos && s.endosos.length ? `Endoso ${s.endosos.join(', ')}` : '',
                documentosTexto: s.documentos ? `${s.documentos} ${s.documentos === 1 ? 'archivo' : 'archivos'}` : ''
            };
        });
    }
    handleVer(e) {
        const f = e.currentTarget.dataset.folio;
        const a = new Set(this.abiertas);
        if (a.has(f)) { a.delete(f); } else { a.add(f); }
        this.abiertas = a;
    }

    // ===== Formulario =====
    handleNueva() {
        this.exito = undefined;
        this.error = undefined;
        this.movimientos = [this.nuevoMovimiento('alta')];
        this.comentario = '';
        this.archivos = [];
        this.modo = 'archivo';
        this.listado = null;
        this.formulario = true;
    }

    // ===== Modo: subir archivo o capturar uno por uno =====
    modo = 'archivo';
    listado = null;
    leyendo = false;
    // El archivo puede traer cualquier combinación de altas, bajas y cambios (columna Tipo de movimiento), cada uno con
    // su fecha: el cliente ya no elige qué contiene ni la fecha en que aplica.
    tipoArchivo = 'varios';
    fechaArchivo = '';
    get enArchivo() { return this.modo === 'archivo'; }
    get claseModoArchivo() { return 'modo' + (this.enArchivo ? ' modo_activo' : ''); }
    get claseModoManual() { return 'modo' + (this.enArchivo ? '' : ' modo_activo'); }
    get pressedArchivo() { return String(this.enArchivo); }
    get pressedManual() { return String(!this.enArchivo); }
    handleModo(e) { this.modo = e.currentTarget.dataset.modo; this.error = undefined; }
    get nombrePlural() { return NOMBRES[this.tipo][1]; }
    get opcionesTipoArchivo() {
        return [
            { label: `Altas de ${this.nombrePlural}`, value: 'alta' },
            { label: `Bajas de ${this.nombrePlural}`, value: 'baja' },
            { label: 'Cambios de datos', value: 'cambio' },
            { label: 'Varios movimientos (el archivo indica cuál es cada uno)', value: 'varios' }
        ];
    }
    handleTipoArchivo(e) { this.tipoArchivo = e.detail.value; }
    handleFechaArchivo(e) { this.fechaArchivo = e.detail.value; }

    // Lee el Excel o CSV en el navegador: encuentra el renglón de títulos y toma los renglones con datos. Si no se puede
    // leer (PDF, imagen...), se manda igual como archivo de la solicitud.
    async handleListado(e) {
        const file = (e.target.files || [])[0];
        e.target.value = null;
        if (!file) { return; }
        this.error = undefined;
        if (file.size + this.archivos.reduce((t, a) => t + a.tamano, 0) > MAX_BYTES) {
            this.error = 'El archivo es muy pesado: entre todos los archivos el límite es 4 MB.';
            return;
        }
        this.leyendo = true;
        try {
            const base64 = await this.leerBase64(file);
            let encabezados = [];
            let filas = [];
            let aviso = '';
            let hoja = null;
            try {
                const tabla = await abrirTabla(file);
                let mejor = null;
                for (const hoja of (tabla.hojas.length ? tabla.hojas : [null])) {
                    const leidas = this.tablaDeHoja(await tabla.leerHoja(hoja));
                    if (!mejor || leidas.filas.length > mejor.filas.length) { mejor = leidas; }
                }
                encabezados = mejor.encabezados;
                filas = mejor.filas;
                hoja = mejor;
                if (!filas.length) { aviso = 'No encontramos renglones con datos en el archivo. Revisa que sea el correcto o descarga la plantilla.'; }
            } catch (err) {
                aviso = 'No pudimos leer el archivo. Usa un Excel (.xlsx) o CSV; puedes descargar la plantilla.';
            }
            this.listado = { nombre: file.name, tamano: file.size, base64, encabezados, filas, aviso, hoja };
        } catch (err) {
            this.error = 'No se pudo abrir el archivo. Intenta de nuevo.';
        } finally {
            this.leyendo = false;
        }
    }
    tablaDeHoja(crudas) {
        const filas = (crudas || []).map((f) => (f || []).map((c) => this.textoCelda(c)));
        if (!filas.some(tieneDatos)) { return { encabezados: [], filas: [], crudas: [], mapeo: {} }; }
        const campos = COLUMNAS[this.tipo];
        const h = detectarEncabezado(filas, campos);
        const inicio = inicioDatos(filas, h);
        // Encabezado en dos renglones (ej. «NOMBRE» sobre «NOMBRE(S) | APELLIDO PATERNO | APELLIDO MATERNO»): el título
        // de cada columna es el de abajo cuando lo hay (o los dos, si el de abajo continúa al de arriba).
        const abajo = filas.slice(h + 1, h + 1 + renglonesEncabezadoAbajo(filas, h));
        const tituloDe = (c) => {
            const arriba = String((filas[h] || [])[c] || '').trim();
            const bajo = abajo.map((f) => String((f || [])[c] || '').trim()).filter((x) => x).join(' ');
            if (!bajo) { return arriba; }
            if (!arriba || fold(bajo).includes(fold(arriba))) { return bajo; }
            return `${arriba} ${bajo}`;
        };
        // Renglones con datos y su número en el archivo (para los mensajes).
        const renglones = filas.map((f, i) => ({ f, n: i + 1 })).slice(inicio).filter((x) => tieneDatos(x.f));
        const mapeo = mapeoAutomatico(filas, h, campos);
        const datos = renglones.map((x) => x.f);
        const ancho = Math.max((filas[h] || []).length, ...datos.map((f) => f.length));
        // Solo las columnas que traen título o algún dato.
        // Sin título: el del dato que se reconoció en esa columna; si no, la letra de la columna.
        const reconocida = {};
        Object.keys(mapeo).forEach((k) => { reconocida[mapeo[k]] = campos.find((x) => x.key === k).etiqueta; });
        const columnas = [];
        for (let c = 0; c < ancho; c++) {
            const titulo = tituloDe(c);
            if (titulo || datos.some((f) => String(f[c] || '').trim())) {
                columnas.push({ c, titulo: titulo || reconocida[String(c)] || `Columna ${letraColumna(c)}` });
            }
        }
        // Las fechas de Excel llegan como número de serie: en columnas de fecha se muestran como dd/mm/aaaa.
        const esFecha = columnas.map((x) => /fecha|nacimiento|vigencia/.test(fold(x.titulo)));
        const valor = (v, i) => {
            const t = String(v ?? '').trim();
            if (!esFecha[i] || !/^\d{4,5}(\.\d+)?$/.test(t)) { return t; }
            const f = fechaIso(t);
            return f.iso ? fechaVisible(f.iso) : t;
        };
        return {
            encabezados: columnas.map((x) => x.titulo),
            filas: datos.map((f) => columnas.map((x, i) => valor(f[x.c], i))),
            crudas: renglones,
            mapeo
        };
    }

    // ===== Lo que se registra del archivo =====
    // Columnas reconocidas, para que el cliente vea cómo se leyó su archivo.
    get columnasReconocidas() {
        const h = this.listado && this.listado.hoja;
        if (!h || !h.filas.length) { return ''; }
        const nombres = COLUMNAS[this.tipo].filter((c) => h.mapeo[c.key] !== undefined).map((c) => c.etiqueta);
        return nombres.length ? `Columnas reconocidas: ${nombres.join(', ')}.` : '';
    }
    // Movimiento de un renglón: el elegido para todo el archivo o, en «varios», el de la columna Movimiento.
    tipoDeRenglon(valor) {
        if (this.tipoArchivo !== 'varios') { return this.tipoArchivo; }
        const v = fold(valor);
        if (/^(alta|a$|nuevo|inclusion|agregar)/.test(v)) { return 'alta'; }
        if (/^(baja|b$|cancelacion|exclusion|eliminar)/.test(v)) { return 'baja'; }
        if (/^(cambio|c$|modificacion|correccion|actualizacion)/.test(v)) { return 'cambio'; }
        return null;
    }
    // Arma los movimientos del archivo con las columnas reconocidas. Regresa { registros } o { error } (lo que falta).
    registrosArchivo() {
        const h = this.listado && this.listado.hoja;
        if (!h || !h.filas.length) { return { error: this.listado && this.listado.aviso ? this.listado.aviso : 'El archivo no tiene renglones con datos.' }; }
        const campos = COLUMNAS[this.tipo];
        const col = (k) => (h.mapeo[k] === undefined ? null : Number(h.mapeo[k]));
        const etiqueta = (k) => campos.find((c) => c.key === k).etiqueta;
        if (this.tipoArchivo === 'varios' && col('movimiento') === null) {
            return { error: 'El archivo debe traer la columna «Tipo de movimiento» (Alta, Baja o Cambio) en cada renglón. Descarga la plantilla genérica.' };
        }
        // Número de póliza del renglón: la de esta solicitud u otra vigente del mismo contratante.
        const polizas = new Map(((this.datos && this.datos.polizas) || []).map((p) => [this.codigo(p.nombre), p]));
        const limite = this.fechaLimiteAlta;
        const registros = [];
        for (const x of h.crudas) {
            const valor = (k) => {
                const c = col(k);
                const v = c === null ? '' : String(x.f[c] ?? '').trim();
                if (!v || !campos.find((y) => y.key === k).fecha) { return v; }
                return fechaIso(v).iso || '';
            };
            const tipo = this.tipoDeRenglon(valor('movimiento'));
            if (!tipo) { return { error: `Renglón ${x.n}: indica en la columna Movimiento si es Alta, Baja o Cambio.` }; }
            const datos = {};
            campos.forEach((c) => {
                if (['movimiento', 'fecha', 'comentario', 'titular', 'poliza'].includes(c.key)) { return; }
                const v = valor(c.key);
                if (v) { datos[c.key] = v; }
            });
            // Sexo M/F (masculino / femenino) como en la captura uno por uno.
            if (datos.sexo) {
                const sx = fold(datos.sexo);
                if (/^(m|masc|masculino|h|hombre)$/.test(sx)) { datos.sexo = 'Hombre'; } else if (/^(f|fem|femenino|mujer)$/.test(sx)) { datos.sexo = 'Mujer'; }
            }
            const fecha = valor('fecha') || null;
            if (tipo === 'alta' && fecha && fecha < limite) {
                return { error: `Renglón ${x.n}: la fecha de alta puede ser de máximo ${DIAS_RETROACTIVOS} días retroactivos.` };
            }
            let polizaId = null;
            const numPoliza = valor('poliza');
            if (numPoliza) {
                const p = polizas.get(this.codigo(numPoliza));
                if (!p) { return { error: `Renglón ${x.n}: la póliza ${numPoliza} no es una de tus pólizas vigentes de este tipo.` }; }
                polizaId = p.actual ? null : p.id;
            }
            registros.push({ tipo, fila: x.n, fecha, comentario: valor('comentario') || null,
                titular: valor('titular') || null, campos: datos, polizaId });
        }
        // Columnas obligatorias según los movimientos que trae.
        const grupos = REQUERIDAS[this.tipo];
        const faltan = [];
        const revisar = (lista) => lista.forEach((g) => {
            if (!g.some((k) => col(k) !== null)) { faltan.push(g.map(etiqueta).join(' o ')); }
        });
        if (registros.some((r) => r.tipo === 'alta')) { revisar(grupos.alta); }
        if (registros.some((r) => r.tipo !== 'alta')) { revisar(grupos.otro); }
        if (faltan.length) {
            return { error: `No encontramos en el archivo ${faltan.length === 1 ? 'la columna' : 'las columnas'} ${[...new Set(faltan)].join('; ')}. `
                + 'Revisa los encabezados o usa la plantilla.' };
        }
        // Cada renglón con lo mínimo para registrarlo.
        for (const r of registros) {
            const lista = r.tipo === 'alta' ? grupos.alta : grupos.otro;
            const falta = lista.find((g) => !g.some((k) => r.campos[k]));
            if (falta) { return { error: `Renglón ${r.fila}: falta ${falta.map(etiqueta).join(' o ').toLowerCase()}.` }; }
            if (r.tipo === 'cambio' && Object.keys(r.campos).length < 2) {
                return { error: `Renglón ${r.fila}: en un cambio indica cómo identificar el registro y los datos nuevos.` };
            }
        }
        return { registros };
    }
    textoCelda(v) {
        if (v === null || v === undefined) { return ''; }
        return String(v).trim();
    }
    leerBase64(file) {
        return new Promise((ok, mal) => {
            const r = new FileReader();
            r.onload = () => ok(String(r.result).split(',')[1]);
            r.onerror = () => mal(r.error);
            r.readAsDataURL(file);
        });
    }
    handleQuitarListado() { this.listado = null; }
    handleSobreZona(e) { e.preventDefault(); }
    handleSoltar(e) {
        e.preventDefault();
        const files = (e.dataTransfer && e.dataTransfer.files) || [];
        if (files.length) { this.handleListado({ target: { files, value: null } }); }
    }
    get textoZona() { return this.leyendo ? 'Leyendo el archivo…' : 'Elige o arrastra aquí el archivo con los datos'; }
    get textoAdjuntar() { return this.enArchivo ? 'Adjuntar documentos' : 'Adjuntar archivos'; }
    get notaAdjuntar() {
        return this.enArchivo ? 'Opcional: identificaciones, actas, facturas o lo que pida la aseguradora (hasta 4 MB en total).'
            : 'Excel con el listado, identificaciones, actas o lo que pida la aseguradora (hasta 4 MB en total).';
    }
    get hayListado() { return !!this.listado; }
    get listadoConDatos() { return !!this.listado && this.listado.filas.length > 0; }
    get textoListado() {
        if (!this.listado) { return ''; }
        const n = this.listado.filas.length;
        const peso = this.tamano(this.listado.tamano);
        return n ? `${n} ${n === 1 ? 'renglón' : 'renglones'} con datos · ${peso}` : peso;
    }
    get vistaEncabezados() { return this.listado ? this.listado.encabezados.map((t, i) => ({ key: 'h' + i, t })) : []; }
    get vistaFilas() {
        if (!this.listado) { return []; }
        return this.listado.filas.slice(0, VISTA_FILAS).map((f, i) => ({ key: 'f' + i, celdas: f.map((t, j) => ({ key: j, t })) }));
    }
    get textoMasFilas() {
        const n = this.listado ? this.listado.filas.length - VISTA_FILAS : 0;
        return n > 0 ? `y ${n} ${n === 1 ? 'renglón' : 'renglones'} más` : '';
    }
    handlePlantilla() {
        descargarExcel('PLANTILLA DE MOVIMIENTOS.xlsx', 'Movimientos', PLANTILLA[this.tipo], []);
    }
    // Número de póliza, certificado o inciso para comparar: mayúsculas, sin espacios ni guiones.
    codigo(v) { return String(v || '').toUpperCase().replace(/[^A-Z0-9]/g, ''); }
    // Fecha más antigua permitida para un alta (AAAA-MM-DD).
    get fechaLimiteAlta() {
        const d = new Date();
        d.setDate(d.getDate() - DIAS_RETROACTIVOS);
        return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    }
    get textoRetroactivo() { return `Máximo ${DIAS_RETROACTIVOS} días retroactivos`; }
    handleCancelar() { this.formulario = false; }
    nuevoMovimiento(tipo) {
        return { key: 'm' + siguiente++, tipo, polizaId: this._policyId, registroId: '', fecha: '', detalle: '', datos: {}, titularId: '',
            filtro: 'todos' };
    }
    handleAgregar() { this.movimientos = [...this.movimientos, this.nuevoMovimiento(this.movimientos.length ? this.movimientos[this.movimientos.length - 1].tipo : 'alta')]; }
    handleQuitar(e) {
        const k = e.currentTarget.dataset.key;
        this.movimientos = this.movimientos.filter((m) => m.key !== k);
    }
    cambiar(key, cambios) { this.movimientos = this.movimientos.map((m) => (m.key === key ? { ...m, ...cambios } : m)); }
    handleTipo(e) {
        this.cambiar(e.target.dataset.key, { tipo: e.detail.value, registroId: '', detalle: '', datos: {}, polizaId: this._policyId, filtro: 'todos' });
    }
    handleCampo(e) { this.cambiar(e.target.dataset.key, { [e.target.dataset.campo]: e.detail.value }); }

    // ===== Póliza y registro de bajas y cambios =====
    // Registros vigentes de otras pólizas del contratante (se cargan al elegirlas): póliza → { registros, mensaje }.
    registrosOtras = {};
    get opcionesPoliza() {
        return ((this.datos && this.datos.polizas) || []).map((p) => ({
            label: `${p.nombre}${p.ramo ? ' · ' + p.ramo : ''}${p.actual ? ' (esta póliza)' : ''}`, value: p.id
        }));
    }
    async handlePoliza(e) {
        const key = e.target.dataset.key;
        const polizaId = e.detail.value;
        this.cambiar(key, { polizaId, registroId: '' });
        if (polizaId === this._policyId || this.registrosOtras[polizaId]) { return; }
        this.registrosOtras = { ...this.registrosOtras, [polizaId]: { cargando: true, registros: [] } };
        try {
            const r = await registrosPoliza({ policyId: polizaId, cuentaVistaPrevia: this.cuentaVistaPrevia || null });
            this.registrosOtras = { ...this.registrosOtras, [polizaId]: { registros: r.registros || [], mensaje: r.mensaje } };
        } catch (err) {
            this.registrosOtras = { ...this.registrosOtras, [polizaId]: { registros: [], mensaje: this.mensaje(err) } };
        }
    }
    handleFiltro(e) {
        this.cambiar(e.currentTarget.dataset.key, { filtro: e.currentTarget.dataset.filtro, registroId: '' });
    }
    registrosDe(polizaId) {
        if (!polizaId || polizaId === this._policyId) { return (this.datos && this.datos.registros) || []; }
        return (this.registrosOtras[polizaId] || {}).registros || [];
    }
    // Ordenados por certificado o inciso (ya vienen así); en personas indica Titular o Dependiente y se filtra.
    opcionesRegistroDe(m) {
        const personas = this.tipo === 'personas';
        return this.registrosDe(m.polizaId)
            .filter((r) => !personas || m.filtro === 'todos' || (m.filtro === 'titulares' ? !r.dependiente : r.dependiente))
            .map((r) => ({
                label: [r.clave, r.nombre, personas ? (r.dependiente ? `Dependiente${r.parentesco && r.parentesco !== 'Dependiente' ? ' (' + r.parentesco + ')' : ''}` : 'Titular') : r.detalle]
                    .filter((x) => x).join(' · '),
                value: r.id
            }));
    }
    filtrosDe(m) {
        return [['todos', 'Todos'], ['titulares', 'Titulares'], ['dependientes', 'Dependientes']].map(([v, t]) => ({
            key: m.key + v, valor: v, texto: t, clase: 'filtro' + (m.filtro === v ? ' filtro_activo' : ''), pressed: String(m.filtro === v)
        }));
    }
    get etiquetaRegistro() {
        const n = this.nombreRegistro;
        return n.charAt(0).toUpperCase() + n.slice(1);
    }

    // Documentos adjuntos que son de reconocimiento de antigüedad (RA), por su nombre.
    get documentosRA() { return this.archivos.filter((a) => ARCHIVO_RA.test(fold(a.nombre))).map((a) => a.nombre); }
    get avisoRA() {
        const d = this.documentosRA;
        if (!d.length || this.enArchivo || !this.movimientos.some((m) => m.tipo !== 'baja')) { return ''; }
        return `Identificamos documentos de reconocimiento de antigüedad (RA): ${d.join(', ')}. Las altas y cambios de esta solicitud se envían con RA.`;
    }
    handleDato(e) {
        const m = this.movimientos.find((x) => x.key === e.target.dataset.key);
        this.cambiar(m.key, { datos: { ...m.datos, [e.target.dataset.campo]: e.detail.value } });
    }
    handleComentario(e) { this.comentario = e.detail.value; }

    get opcionesTipo() {
        return [
            { label: `Alta de ${this.nombreRegistro}`, value: 'alta' },
            { label: `Baja de ${this.nombreRegistro}`, value: 'baja' },
            { label: 'Cambio de datos', value: 'cambio' }
        ];
    }
    get opcionesRegistro() {
        return ((this.datos && this.datos.registros) || []).map((r) => ({
            label: `${r.clave ? r.clave + ' · ' : ''}${r.nombre}${r.dependiente ? ' (dependiente)' : ''}`, value: r.id
        }));
    }
    get opcionesTitular() {
        return ((this.datos && this.datos.registros) || []).filter((r) => !r.dependiente)
            .map((r) => ({ label: `${r.clave ? r.clave + ' · ' : ''}${r.nombre}`, value: r.id }));
    }
    get sinRegistros() { return !this.opcionesRegistro.length; }
    get filasMovimiento() {
        return this.movimientos.map((m, i) => {
            const esAlta = m.tipo === 'alta';
            // Alta: los datos del registro nuevo. Cambio: los mismos campos, solo se llenan los que cambian.
            const campos = m.tipo !== 'baja' ? CAMPOS_ALTA[this.tipo].filter((c) => esAlta || !c.soloAlta).map((c) => ({
                ...c,
                key: m.key + c.clave,
                etiqueta: esAlta ? c.etiqueta : (c.etiquetaCambio || `${c.etiqueta} nuevo`.replace('(s) nuevo', '(s) nuevo(s)')),
                requerido: esAlta && c.requerido,
                valor: m.datos[c.clave] || '',
                tipoInput: c.tipo || 'text',
                esLista: !!c.opciones,
                opciones: (c.opciones || []).map((o) => ({ label: o, value: o }))
            })) : [];
            const parentesco = m.datos.parentesco;
            const otra = m.polizaId && m.polizaId !== this._policyId ? this.registrosOtras[m.polizaId] : null;
            return {
                ...m,
                numero: i + 1,
                esAlta,
                conRegistro: !esAlta,
                opcionesRegistro: esAlta ? [] : this.opcionesRegistroDe(m),
                filtros: !esAlta && this.tipo === 'personas' ? this.filtrosDe(m) : null,
                avisoPoliza: otra ? (otra.cargando ? 'Cargando los registros de la póliza…' : (otra.mensaje || '')) : '',
                placeholderRegistro: `Elige ${this.tipo === 'personas' ? 'al asegurado' : 'el ' + this.nombreRegistro} (por número de ${this.tipo === 'personas' ? 'certificado' : 'inciso'})`,
                // Reconocimiento de antigüedad: recordatorio de documentos en altas y cambios de personas.
                conRecordatorioRA: this.tipo === 'personas' && m.tipo !== 'baja',
                textoRA: esAlta ? 'Si el alta es con reconocimiento de antigüedad (RA), adjunta en «Adjuntar archivos»:'
                    : 'Si el cambio es un reconocimiento de antigüedad (RA), adjunta en «Adjuntar archivos»:',
                minFecha: esAlta ? this.fechaLimiteAlta : null,
                notaFecha: esAlta ? this.textoRetroactivo : '',
                campos,
                conTitular: esAlta && this.tipo === 'personas' && !!parentesco && parentesco !== 'Titular',
                esCambio: m.tipo === 'cambio',
                etiquetaDetalle: m.tipo === 'baja' ? 'Motivo de la baja' : (m.tipo === 'cambio' ? 'Comentario del cambio (opcional)' : 'Nota (opcional)'),
                detalleRequerido: false,
                etiquetaFecha: m.tipo === 'baja' ? 'Fecha de baja' : (m.tipo === 'alta' ? 'Fecha de alta' : 'Fecha en que aplica'),
                puedeQuitar: this.movimientos.length > 1
            };
        });
    }

    async handleArchivos(e) {
        const nuevos = [...(e.target.files || [])];
        e.target.value = null;
        const leidos = await Promise.all(nuevos.map((f) => new Promise((ok, mal) => {
            const r = new FileReader();
            r.onload = () => ok({ nombre: f.name, tamano: f.size, base64: String(r.result).split(',')[1] });
            r.onerror = () => mal(r.error);
            r.readAsDataURL(f);
        })));
        const todos = [...this.archivos, ...leidos];
        if (todos.reduce((t, a) => t + a.tamano, 0) + (this.enArchivo && this.listado ? this.listado.tamano : 0) > MAX_BYTES) {
            this.error = 'Los archivos suman más de 4 MB. Adjunta archivos más ligeros.';
            return;
        }
        this.error = undefined;
        this.archivos = todos;
    }
    get listaArchivos() { return this.archivos.map((a, i) => ({ key: i + a.nombre, i, nombre: a.nombre, tamano: this.tamano(a.tamano) })); }
    get hayArchivos() { return this.archivos.length > 0; }
    handleQuitarArchivo(e) {
        const i = Number(e.currentTarget.dataset.i);
        this.archivos = this.archivos.filter((a, j) => j !== i);
    }

    async handleEnviar() {
        const validos = [...this.template.querySelectorAll('lightning-input, lightning-combobox, lightning-textarea')]
            .reduce((ok, c) => (c.reportValidity ? c.reportValidity() : true) && ok, true);
        if (!validos) { return; }
        if (this.enArchivo && !this.listado) {
            this.error = 'Elige el archivo con los datos o cambia a «Capturar uno por uno».';
            return;
        }
        let leidos = null;
        if (this.enArchivo) {
            leidos = this.registrosArchivo();
            if (leidos.error) { this.error = leidos.error; return; }
            if (leidos.registros.length > MAX_FILAS) {
                this.error = `El archivo trae ${leidos.registros.length} renglones; envía hasta ${MAX_FILAS} por solicitud.`;
                return;
            }
        } else {
            const sinDatos = this.movimientos.findIndex((m) => m.tipo === 'cambio' && !Object.values(m.datos).some((v) => v));
            if (sinDatos >= 0) {
                this.error = `Movimiento ${sinDatos + 1}: captura los datos que cambian.`;
                return;
            }
        }
        const registros = new Map(((this.datos && this.datos.registros) || []).map((r) => [r.id, r]));
        const archivos = this.archivos.map((a) => ({ nombre: a.nombre, base64: a.base64 }));
        let listado = null;
        if (this.enArchivo) {
            const l = this.listado;
            archivos.unshift({ nombre: l.nombre, base64: l.base64 });
            listado = { tipo: this.tipoArchivo, nombre: l.nombre, fecha: null, encabezados: l.encabezados,
                filas: l.filas.slice(0, MAX_FILAS), total: l.filas.length, registros: leidos.registros };
        }
        const movimientos = this.enArchivo ? [] : this.movimientos.map((m, i) => {
            const conDatos = m.tipo !== 'baja';
            const datos = conDatos ? CAMPOS_ALTA[this.tipo].filter((c) => m.tipo === 'alta' || m.datos[c.clave])
                .map((c) => ({ etiqueta: c.etiqueta, valor: m.datos[c.clave] || '' })) : [];
            if (m.titularId && registros.has(m.titularId)) {
                const t = registros.get(m.titularId);
                datos.push({ etiqueta: 'Titular', valor: `${t.clave ? t.clave + ' · ' : ''}${t.nombre}` });
            }
            const campos = {};
            if (conDatos) { Object.keys(m.datos).filter((k) => m.datos[k]).forEach((k) => { campos[k] = m.datos[k]; }); }
            // Bajas y cambios de otra póliza del contratante: se registran en esa póliza (su propia solicitud).
            const polizaId = m.tipo !== 'alta' && m.polizaId && m.polizaId !== this._policyId ? m.polizaId : null;
            return { tipo: m.tipo, registroId: m.registroId || null, fecha: m.fecha || null, detalle: m.detalle || null, datos, campos,
                titularId: m.titularId || null, polizaId, numero: i + 1 };
        });
        this.enviando = true;
        this.error = undefined;
        try {
            const r = await crearSolicitud({
                policyId: this._policyId,
                solicitudJson: JSON.stringify({
                    movimientos,
                    listado,
                    comentario: this.comentario,
                    archivos
                }),
                cuentaVistaPrevia: this.cuentaVistaPrevia || null
            });
            this.formulario = false;
            const varias = r.solicitudes > 1;
            this.exito = r.registrados
                ? `Registramos tu${varias ? 's solicitudes' : ' solicitud'} ${r.folio}: ${r.registrados} ${r.registrados === 1 ? 'movimiento quedó' : 'movimientos quedaron'} en trámite con la aseguradora. Verás aquí su avance.`
                : `Recibimos tu${varias ? 's solicitudes' : ' solicitud'} ${r.folio}. Tu asesor la revisará y verás aquí su avance.`;
            await this.cargar();
        } catch (e) {
            this.error = this.mensaje(e);
        } finally {
            this.enviando = false;
        }
    }

    // ===== Utilidades =====
    fecha(v) {
        if (!v) { return ''; }
        return new Intl.DateTimeFormat('es-MX', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }).format(new Date(v));
    }
    tamano(b) { return b >= 1024 * 1024 ? `${(b / 1024 / 1024).toFixed(1)} MB` : `${Math.max(1, Math.round(b / 1024))} KB`; }
    mensaje(e) {
        return (e && e.body && (e.body.message || (e.body.pageErrors && e.body.pageErrors[0] && e.body.pageErrors[0].message)))
            || (e && e.message) || 'Ocurrió un error. Intenta de nuevo.';
    }
}
