/**
 * @creation date: 10/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Detecta qué información trae cada archivo de una póliza colectiva y la convierte al formato que
 *               guarda Apex: carátula de la póliza (PDF), censo de asegurados (Excel/CSV o PDF), flotilla de
 *               vehículos (Excel/CSV) y ubicaciones de Daños (Excel/CSV). Lo usan Crear Póliza (emisión de
 *               colectivos con varios archivos), censoColectivo y flotillaColectiva (mismas columnas reconocidas).
 */
import { fold, numero, fecha, tieneDatos, detectarEncabezado, mapeoAutomatico, inicioDatos } from 'c/lectorArchivos';

// Tipos de archivo que se reconocen.
export const TIPOS = {
    POLIZA: 'poliza',
    CENSO: 'censo',
    VEHICULOS: 'vehiculos',
    UBICACIONES: 'ubicaciones',
    ADJUNTO: 'adjunto'
};

export const ETIQUETAS_TIPO = {
    poliza: 'Póliza (carátula)',
    censo: 'Censo de asegurados',
    vehiculos: 'Flotilla de vehículos',
    ubicaciones: 'Ubicaciones (Daños)',
    adjunto: 'Solo adjuntar'
};

// ============================================================
// Columnas reconocidas
// ============================================================

export const CAMPOS_CENSO = [
    { key: 'nombreCompleto', label: 'Nombre completo', alias: ['nombre completo', 'nombre del asegurado', 'nombre asegurado', 'asegurado', 'nombre y apellidos', 'nombre del empleado', 'empleado', 'nombre completo del asegurado'] },
    { key: 'nombre', label: 'Nombre(s)', alias: ['nombre', 'nombres', 'nombre s', 'primer nombre'] },
    { key: 'apellidoPaterno', label: 'Apellido paterno', alias: ['apellido paterno', 'paterno', 'ap paterno', 'primer apellido', 'a paterno', 'patern'] },
    { key: 'apellidoMaterno', label: 'Apellido materno', alias: ['apellido materno', 'materno', 'ap materno', 'segundo apellido', 'a materno', 'matern'] },
    { key: 'apellidos', label: 'Apellidos', alias: ['apellidos', 'apellido'] },
    { key: 'fechaNacimiento', label: 'Fecha de nacimiento', tipo: 'fecha', alias: ['fecha de nacimiento', 'fecha nacimiento', 'f nacimiento', 'nacimiento', 'fec nac', 'f nac', 'fecha nac', 'fnac', 'fnacim', 'fecnac'] },
    { key: 'edad', label: 'Edad', tipo: 'numero', alias: ['edad', 'edad actual', 'edad alcanzada'] },
    { key: 'sexo', label: 'Género', alias: ['sexo', 'genero', 'sex'] },
    { key: 'parentesco', label: 'Parentesco', alias: ['parentesco', 'tipo de asegurado', 'tipo asegurado', 'relacion', 'dependencia', 'tipo de dependiente'] },
    { key: 'categoria', label: 'Categoría', alias: ['categoria', 'grupo', 'clase', 'nivel', 'grupo asegurado', 'subgrupo', 'regla', 'catego'] },
    { key: 'sueldoMensual', label: 'Sueldo mensual', tipo: 'numero', alias: ['sueldo mensual', 'salario mensual', 'sueldo', 'salario', 'sueldo base'] },
    { key: 'sueldoAnual', label: 'Sueldo anual', tipo: 'numero', alias: ['sueldo anual', 'salario anual', 'ingreso anual'] },
    { key: 'sumaAsegurada', label: 'Suma asegurada', tipo: 'numero', alias: ['suma asegurada', 'sa', 's a', 'suma aseg', 'int sa'] },
    { key: 'prima', label: 'Prima', tipo: 'numero', alias: ['prima', 'prima neta', 'prima anual', 'prima total', 'costo', 'prima individual'] },
    { key: 'certificado', label: 'Certificado', alias: ['certificado', 'no certificado', 'num certificado', 'numero de certificado', 'cert', 'no de certificado', 'certif'] },
    // El alta del participante se toma de la fecha de movimiento (no de la fecha de alta, ingreso o antigüedad).
    { key: 'fechaAlta', label: 'Fecha de movimiento', tipo: 'fecha', excluir: ['tipo', 'clave', 'motivo'], alias: ['fecha de movimiento', 'fecha movimiento', 'fecha de mov', 'fecha mov', 'fec mov', 'f movimiento', 'f mov', 'fecmov', 'fmov', 'fecha mto', 'fecha de mto'] },
    { key: 'tipoMovimiento', label: 'Tipo de movimiento (alta/baja/cambio)', excluir: ['fecha', 'motivo'], alias: ['tipo de movimiento', 'tipo movimiento', 'tipo de mov', 'tipo mov', 'tipo de movto', 'tipo movto', 'movimiento', 'movto', 'mov', 'clave de movimiento', 'clave movimiento', 'cve mov', 'cve movimiento', 'tipo de operacion', 'operacion', 'a b c', 'abc'] },
    { key: 'numEmpleado', label: 'Núm. de empleado', alias: ['numero de empleado', 'no empleado', 'num empleado', 'no de empleado', 'nomina', 'no nomina', 'id empleado', 'clave empleado', 'clave'] },
    { key: 'rfc', label: 'RFC', alias: ['rfc'] },
    { key: 'email', label: 'Correo', alias: ['email', 'correo', 'correo electronico', 'e mail', 'mail'] },
    { key: 'telefono', label: 'Teléfono', alias: ['telefono', 'celular', 'tel', 'movil'] }
];

export const CAMPOS_FLOTILLA = [
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

export const CAMPOS_UBICACIONES = [
    { key: 'inciso', label: 'Inciso / ubicación', alias: ['inciso', 'inc', 'no inciso', 'ubicacion no', 'no ubicacion', 'num ubicacion', 'numero de ubicacion', 'consecutivo', 'no'] },
    { key: 'direccion', label: 'Domicilio completo', alias: ['direccion', 'domicilio', 'domicilio del riesgo', 'ubicacion del riesgo', 'direccion completa', 'domicilio completo', 'ubicacion'] },
    { key: 'calle', label: 'Calle y número', alias: ['calle', 'calle y numero', 'calle y no', 'calle numero'] },
    { key: 'numExterior', label: 'Núm. exterior', alias: ['numero exterior', 'no exterior', 'num ext', 'no ext', 'exterior'] },
    { key: 'numInterior', label: 'Núm. interior', alias: ['numero interior', 'no interior', 'num int', 'no int', 'interior'] },
    { key: 'colonia', label: 'Colonia', alias: ['colonia', 'col', 'fraccionamiento'] },
    { key: 'cp', label: 'Código postal', alias: ['cp', 'c p', 'codigo postal', 'cod postal', 'c postal'] },
    { key: 'municipio', label: 'Municipio / alcaldía', alias: ['municipio', 'alcaldia', 'delegacion', 'municipio alcaldia', 'ciudad', 'poblacion', 'localidad'] },
    { key: 'estado', label: 'Estado', alias: ['estado', 'entidad', 'entidad federativa'] },
    { key: 'giro', label: 'Giro', alias: ['giro', 'actividad', 'giro del negocio', 'giro comercial', 'ocupacion'] },
    { key: 'techos', label: 'Techos', alias: ['techos', 'techo', 'tipo de techo'] },
    { key: 'muros', label: 'Muros', alias: ['muros', 'muro', 'tipo de muro'] },
    { key: 'pisosAltos', label: 'Pisos', tipo: 'numero', alias: ['pisos', 'pisos altos', 'niveles', 'numero de pisos', 'no de pisos'] },
    { key: 'sotanos', label: 'Sótanos', tipo: 'numero', alias: ['sotanos', 'sotano'] },
    { key: 'sumaAsegurada', label: 'Suma asegurada', tipo: 'numero', alias: ['suma asegurada', 'sa', 'suma aseg', 'valor', 'valor del inmueble', 'suma asegurada total', 'edificio'] },
    { key: 'primaNeta', label: 'Prima neta', tipo: 'numero', alias: ['prima neta', 'neta', 'pn'] },
    { key: 'primaTotal', label: 'Prima total', tipo: 'numero', alias: ['prima total', 'total', 'prima', 'importe', 'importe total'] }
];

// Columnas que distinguen cada tipo de tabla (las genéricas como "prima" o "inciso" no cuentan).
const DISTINTIVAS = {
    censo: ['nombreCompleto', 'nombre', 'apellidoPaterno', 'apellidoMaterno', 'apellidos', 'fechaNacimiento', 'edad', 'sexo', 'parentesco', 'sueldoMensual', 'sueldoAnual', 'certificado', 'numEmpleado', 'rfc'],
    vehiculos: ['serie', 'claveVehicular', 'marca', 'descripcion', 'modelo', 'placas', 'uso', 'tipoVehiculo', 'dedDM', 'dedRT', 'rc', 'gm', 'muerte'],
    ubicaciones: ['direccion', 'calle', 'numExterior', 'colonia', 'cp', 'municipio', 'estado', 'giro', 'techos', 'muros', 'pisosAltos', 'sotanos']
};

const CAMPOS_POR_TIPO = { censo: CAMPOS_CENSO, vehiculos: CAMPOS_FLOTILLA, ubicaciones: CAMPOS_UBICACIONES };

// Mapeo de columnas del censo; "Nombre" sin columnas de apellidos es el nombre completo.
export function mapeoCenso(filas, h) {
    const mapeo = mapeoAutomatico(filas, h, CAMPOS_CENSO);
    if (mapeo.nombre !== undefined && mapeo.nombreCompleto === undefined
        && mapeo.apellidoPaterno === undefined && mapeo.apellidos === undefined) {
        mapeo.nombreCompleto = mapeo.nombre;
        delete mapeo.nombre;
    }
    return mapeo;
}

function mapeoDe(tipo, filas, h) {
    return tipo === TIPOS.CENSO ? mapeoCenso(filas, h) : mapeoAutomatico(filas, h, CAMPOS_POR_TIPO[tipo]);
}

// ¿El mapeo trae lo mínimo para usar la tabla como ese tipo?
function tieneMinimo(tipo, m) {
    const hay = (k) => m[k] !== undefined;
    if (tipo === TIPOS.CENSO) {
        return (hay('nombreCompleto') || hay('nombre') || hay('apellidoPaterno') || hay('apellidos'))
            && ['fechaNacimiento', 'edad', 'parentesco', 'sexo', 'certificado', 'numEmpleado', 'apellidoPaterno'].some(hay);
    }
    if (tipo === TIPOS.VEHICULOS) {
        return hay('serie') || hay('placas') || (hay('marca') && (hay('modelo') || hay('descripcion')));
    }
    return hay('direccion') || hay('cp') || (hay('calle') && (hay('colonia') || hay('municipio')));
}

/**
 * Lee una hoja como el tipo indicado (cuando el usuario corrige el tipo detectado): { encabezado, mapeo, valido }.
 */
export function mapeoComo(tipo, filas) {
    if (!CAMPOS_POR_TIPO[tipo] || (filas || []).filter((f) => tieneDatos(f)).length < 2) {
        return { encabezado: 0, mapeo: {}, valido: false };
    }
    const encabezado = detectarEncabezado(filas, CAMPOS_POR_TIPO[tipo]);
    const mapeo = mapeoDe(tipo, filas, encabezado);
    return { encabezado, mapeo, valido: tieneMinimo(tipo, mapeo) };
}

/**
 * Detecta si una hoja es censo de asegurados, flotilla de vehículos o ubicaciones. Devuelve
 * { tipo, encabezado, mapeo, puntos } con el tipo de mejor puntaje, o tipo "adjunto" si no se reconoce.
 * El nombre del archivo/hoja desempata (ej. "Censo GMM.xlsx", hoja "Vehículos").
 */
export function detectarTipoTabla(filas, nombre) {
    const pista = pistaPorNombre(nombre);
    let mejor = { tipo: TIPOS.ADJUNTO, encabezado: 0, mapeo: {}, puntos: 0 };
    if ((filas || []).filter((f) => tieneDatos(f)).length < 2) { return mejor; }
    [TIPOS.CENSO, TIPOS.VEHICULOS, TIPOS.UBICACIONES].forEach((tipo) => {
        const h = detectarEncabezado(filas, CAMPOS_POR_TIPO[tipo]);
        const mapeo = mapeoDe(tipo, filas, h);
        if (!tieneMinimo(tipo, mapeo)) { return; }
        let puntos = DISTINTIVAS[tipo].filter((k) => mapeo[k] !== undefined).length;
        if (pista === tipo) { puntos += 2; }
        if (puntos > mejor.puntos) { mejor = { tipo, encabezado: h, mapeo, puntos }; }
    });
    return mejor.puntos >= 2 ? mejor : { tipo: TIPOS.ADJUNTO, encabezado: 0, mapeo: {}, puntos: 0 };
}

// Pista del tipo por el nombre del archivo o de la hoja.
export function pistaPorNombre(nombre) {
    const n = fold(nombre);
    if (/\b(censo|asegurados?|relacion de asegurados|listado|plantilla|empleados|colaboradores|nomina)\b/.test(n)) { return TIPOS.CENSO; }
    if (/\b(flotilla|vehiculos?|unidades|autos|parque vehicular|incisos)\b/.test(n)) { return TIPOS.VEHICULOS; }
    if (/\b(ubicaciones?|inmuebles|locales|sucursales|domicilios)\b/.test(n)) { return TIPOS.UBICACIONES; }
    if (/\b(poliza|caratula|especificacion|endoso)\b/.test(n)) { return TIPOS.POLIZA; }
    return null;
}

const PARENTESCO_LINEA = /\b(titular|conyuge|esposa|esposo|hija|hijo|concubin[oa])\b/;
const FECHA_LINEA = /\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b|\b\d{1,2}[/-][a-z]{3}[/-]\d{2,4}\b/i;
const PALABRAS_POLIZA = ['vigencia', 'prima neta', 'prima total', 'contratante', 'forma de pago', 'derecho de poliza',
    'gastos de expedicion', 'coberturas', 'suma asegurada', 'numero de poliza', 'poliza no', 'caratula'];

/**
 * Detecta si un PDF es la carátula/póliza o un censo (listado de asegurados). Devuelve "poliza", "censo" o
 * "adjunto" (sin texto, ej. escaneado). El nombre del archivo desempata.
 */
export function detectarTipoPdf(nombre, texto) {
    const t = String(texto || '');
    if (t.replace(/\s/g, '').length < 40) { return TIPOS.ADJUNTO; }
    const pista = pistaPorNombre(nombre);
    // Renglones de personas: parentesco y una fecha en el mismo renglón (la fecha se busca en el texto original,
    // fold() quita las diagonales).
    const personas = t.split('\n').filter((l) => FECHA_LINEA.test(l) && PARENTESCO_LINEA.test(fold(l))).length;
    const encabezadoCenso = /\b(parentesco|certificado|fecha de nacimiento|f nac|fec nac)\b/.test(fold(t.substring(0, 20000)));
    const inicio = fold(t.substring(0, 15000));
    const poliza = PALABRAS_POLIZA.filter((p) => inicio.includes(p)).length;
    if (pista === TIPOS.CENSO && (personas >= 3 || encabezadoCenso)) { return TIPOS.CENSO; }
    if (pista === TIPOS.POLIZA) { return TIPOS.POLIZA; }
    if (encabezadoCenso && personas >= 10 && personas > poliza * 3) { return TIPOS.CENSO; }
    return TIPOS.POLIZA;
}

// ============================================================
// Conversión de filas
// ============================================================

// Renglones de datos de la tabla como objetos { fila, campo: valor } según el mapeo.
export function filasComoObjetos(filas, h, mapeo) {
    const ini = inicioDatos(filas, h);
    return filas.slice(ini)
        .map((f, i) => {
            const o = { fila: ini + i + 1 };
            Object.keys(mapeo).forEach((k) => { o[k] = (f || [])[Number(mapeo[k])]; });
            return o;
        })
        .filter((o, i) => tieneDatos(filas[ini + i]));
}

const txt = (v) => (v === undefined || v === null ? '' : String(v).replace(/\s+/g, ' ').trim());
const sinDecimalCero = (v) => txt(v).replace(/\.0+$/, '');

// Renglones de totales/subtotales al final de muchos archivos.
const esTotal = (v) => /^(sub)?total(es)?\b/.test(fold(v));

/**
 * Vehículos de una tabla de flotilla, con las llaves que usa PolicyController.guardarVehiculosDesdePdf.
 */
export function vehiculosDesdeTabla(filas, h, mapeo) {
    return filasComoObjetos(filas, h, mapeo)
        .filter((o) => !esTotal(o.inciso) && !esTotal(o.marca) && !esTotal(o.descripcion))
        .map((o) => {
            const v = {
                inciso: sinDecimalCero(o.inciso),
                serie: txt(o.serie).toUpperCase(),
                clave: sinDecimalCero(o.claveVehicular),
                marca: txt(o.marca),
                anio: sinDecimalCero(o.modelo),
                descripcion: txt(o.descripcion),
                placas: txt(o.placas).toUpperCase(),
                uso: txt(o.uso),
                tipoVehiculo: txt(o.tipoVehiculo),
                tipoValor: txt(o.tipoValor),
                sumaAsegurada: numero(o.valor),
                deducibleDM: txt(o.dedDM),
                deducibleRT: txt(o.dedRT),
                responsabilidadCivil: numero(o.rc),
                gastosMedicos: numero(o.gm),
                muerteConductor: numero(o.muerte),
                paquete: txt(o.paquete),
                primaNeta: numero(o.primaNeta),
                gastosExpedicion: numero(o.derechos),
                iva: numero(o.iva),
                primaTotal: numero(o.prima)
            };
            Object.keys(v).forEach((k) => { if (v[k] === '' || v[k] === null) { delete v[k]; } });
            return v;
        })
        .filter((v) => v.serie || v.inciso || v.placas);
}

/**
 * Ubicaciones de una tabla de Daños, con las llaves que usa PolicyController.guardarUbicacionesDesdePdf.
 * El domicilio se arma como "CALLE NÚM, COLONIA, C.P. 00000, MUNICIPIO, ESTADO" (formato que Apex desglosa).
 */
export function ubicacionesDesdeTabla(filas, h, mapeo) {
    return filasComoObjetos(filas, h, mapeo)
        .filter((o) => !esTotal(o.inciso) && !esTotal(o.direccion) && !esTotal(o.calle))
        .map((o) => {
            let direccion = txt(o.direccion);
            if (!direccion) {
                const calle = [txt(o.calle), sinDecimalCero(o.numExterior), o.numInterior ? 'Int. ' + sinDecimalCero(o.numInterior) : '']
                    .filter((x) => x).join(' ');
                const cp = sinDecimalCero(o.cp);
                direccion = [calle, txt(o.colonia), cp ? 'C.P. ' + cp.padStart(5, '0') : '', txt(o.municipio), txt(o.estado)]
                    .filter((x) => x).join(', ');
            }
            const u = {
                inciso: sinDecimalCero(o.inciso),
                direccion,
                giro: txt(o.giro),
                techos: txt(o.techos),
                muros: txt(o.muros),
                pisosAltos: sinDecimalCero(o.pisosAltos),
                sotanos: sinDecimalCero(o.sotanos),
                sumaAsegurada: numero(o.sumaAsegurada),
                primaNeta: numero(o.primaNeta),
                primaTotal: numero(o.primaTotal)
            };
            Object.keys(u).forEach((k) => { if (u[k] === '' || u[k] === null) { delete u[k]; } });
            return u;
        })
        .filter((u) => u.direccion);
}

// ============================================================
// Censo: normalización y validación
// ============================================================

// Parentescos que se reconocen (texto normalizado -> valor que se muestra y se guarda).
const PARENTESCOS = [
    { valor: 'Titular', claves: ['titular', 'empleado', 'asegurado titular', 'principal', 'trabajador', 't', 'e', 'tit', 'asegurado', 'socio', 'self', 'miembro', 'colaborador'] },
    { valor: 'Cónyuge', claves: ['conyuge', 'esposo', 'esposa', 'c', 'concubino', 'concubina', 'pareja', 'spouse', 'esp'] },
    { valor: 'Hijo(a)', claves: ['hijo', 'hija', 'hijo a', 'hijos', 'h', 'child', 'dependiente hijo'] },
    { valor: 'Padre/Madre', claves: ['padre', 'madre', 'papa', 'mama', 'parent'] },
    { valor: 'Suegro(a)', claves: ['suegro', 'suegra'] }
];

// Parentesco en código de aseguradora ("01" titular, "02" cónyuge, "03" en adelante hijos).
function parentescoPorCodigo(p) {
    if (!/^\d{1,2}$/.test(p)) { return null; }
    const n = Number(p);
    const valor = n <= 1 ? 'Titular' : (n === 2 ? 'Cónyuge' : 'Hijo(a)');
    return PARENTESCOS.find((x) => x.valor === valor);
}

// Sexo en código 1/2: cada aseguradora lo usa distinto, así que se deduce de los nombres del archivo
// (los que terminan en "a" suelen ser mujeres y en "o" hombres). Regresa { '1': ..., '2': ... } o null.
function sexoPorCodigo(datos) {
    const votos = { 1: 0, 2: 0 };
    let codigos = 0;
    datos.forEach((d) => {
        const s = fold(d.sexo);
        if (s !== '1' && s !== '2') { return; }
        codigos++;
        const nombre = fold(d.nombre || d.nombreCompleto).split(' ')[0] || '';
        if (/a$/.test(nombre)) { votos[s]++; } else if (/o$/.test(nombre)) { votos[s]--; }
    });
    if (!codigos || votos[1] === votos[2]) { return null; }
    return votos[1] > votos[2] ? { 1: 'Mujer', 2: 'Hombre' } : { 1: 'Hombre', 2: 'Mujer' };
}

// Tipo de movimiento del renglón (texto normalizado -> Alta, Baja o Cambio).
export const MOVIMIENTOS = { ALTA: 'Alta', BAJA: 'Baja', CAMBIO: 'Cambio' };
const CLAVES_MOVIMIENTO = [
    { valor: MOVIMIENTOS.ALTA, claves: ['a', 'al', 'alta', 'altas', 'ingreso', 'inclusion', 'nuevo', 'nueva', 'nuevo ingreso', 'add', 'i'] },
    { valor: MOVIMIENTOS.BAJA, claves: ['b', 'ba', 'baja', 'bajas', 'cancelacion', 'cancelado', 'exclusion', 'egreso', 'retiro', 'del'] },
    { valor: MOVIMIENTOS.CAMBIO, claves: ['c', 'ca', 'cambio', 'cambios', 'modificacion', 'mod', 'm', 'actualizacion', 'endoso', 'correccion', 'upd'] }
];
function movimientoDe(v) {
    const p = fold(v);
    if (!p) { return ''; }
    const m = CLAVES_MOVIMIENTO.find((x) => x.claves.includes(p) || x.claves.some((k) => k.length > 3 && p.startsWith(k)));
    return m ? m.valor : null;
}

/** Cuántos renglones son alta, baja y cambio: { altas, bajas, cambios, hay }. */
export function conteoMovimientos(renglones) {
    const c = { altas: 0, bajas: 0, cambios: 0 };
    renglones.forEach((r) => {
        if (r.movimiento === MOVIMIENTOS.ALTA) { c.altas++; }
        else if (r.movimiento === MOVIMIENTOS.BAJA) { c.bajas++; }
        else if (r.movimiento === MOVIMIENTOS.CAMBIO) { c.cambios++; }
    });
    c.hay = c.altas + c.bajas + c.cambios > 0;
    return c;
}

export function edadDe(iso) {
    const [a, m, d] = iso.split('-').map(Number);
    const hoy = new Date();
    let e = hoy.getFullYear() - a;
    if (hoy.getMonth() + 1 < m || (hoy.getMonth() + 1 === m && hoy.getDate() < d)) { e--; }
    return e;
}

function normalizarRenglon(d, usaMF, sexo12) {
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

    const fn = fecha(d.fechaNacimiento);
    if (fn.invalida) { r.avisos.push(`Fecha de nacimiento no válida (${txt(d.fechaNacimiento)})`); }
    r.fechaNacimiento = fn.iso;
    const fa = fecha(d.fechaAlta);
    if (fa.invalida) { r.avisos.push(`Fecha de movimiento no válida (${txt(d.fechaAlta)})`); }
    r.fechaAlta = fa.iso;
    let edad = numero(d.edad);
    if (r.fechaNacimiento) { edad = edadDe(r.fechaNacimiento); }
    r.edad = edad === null ? null : Math.floor(edad);
    if (r.edad === null) { r.avisos.push('Sin fecha de nacimiento ni edad'); }
    else if (r.edad < 0 || r.edad > 99) { r.avisos.push(`Edad fuera de rango (${r.edad})`); }

    const s = fold(d.sexo);
    if (['h', 'hombre', 'masculino', 'masc', 'male', 'varon'].includes(s) || (s === 'm' && usaMF)) { r.sexo = 'Hombre'; }
    else if (['mujer', 'f', 'femenino', 'fem', 'female'].includes(s) || (s === 'm' && !usaMF)) { r.sexo = 'Mujer'; }
    else if (sexo12 && sexo12[s]) { r.sexo = sexo12[s]; }
    else { r.sexo = ''; }

    r.parentescoOriginal = txt(d.parentesco);
    const p = fold(d.parentesco);
    const encontrado = parentescoPorCodigo(p)
        || PARENTESCOS.find((x) => x.claves.includes(p) || x.claves.some((k) => k.length > 3 && p.startsWith(k)));
    r.parentesco = !p ? 'Titular' : (encontrado ? encontrado.valor : 'Otro');
    if (p && !encontrado) { r.avisos.push(`Parentesco "${r.parentescoOriginal}" se guardará como Otro`); }
    r.esTitular = r.parentesco === 'Titular';

    r.categoria = txt(d.categoria);
    const mensual = numero(d.sueldoMensual);
    const anual = numero(d.sueldoAnual);
    r.sueldoAnual = anual !== null ? anual : (mensual !== null ? Math.round(mensual * 12 * 100) / 100 : null);
    r.sumaAsegurada = numero(d.sumaAsegurada);
    r.prima = numero(d.prima);
    r.certificado = sinDecimalCero(d.certificado);
    r.numEmpleado = sinDecimalCero(d.numEmpleado);
    r.rfc = txt(d.rfc).toUpperCase();
    r.email = txt(d.email);
    r.telefono = sinDecimalCero(d.telefono);

    r.movimientoOriginal = txt(d.tipoMovimiento);
    const mov = movimientoDe(d.tipoMovimiento);
    r.movimiento = mov || '';
    if (mov === null) { r.avisos.push(`Tipo de movimiento "${r.movimientoOriginal}" no reconocido`); }
    return r;
}

/**
 * Normaliza y valida los renglones del censo (de Excel, CSV o de la IA): nombre, fechas, edad, sexo,
 * parentesco y sueldo; liga cada dependiente con su titular (mismo certificado o núm. de empleado; si no, el
 * titular anterior) y marca errores y avisos. Devuelve los renglones con idx, esTitular, titularIndex, errores y avisos.
 */
export function normalizarCenso(datos) {
    // "M" es Mujer salvo que el archivo use M/F (Masculino/Femenino).
    const usaMF = datos.some((d) => ['f', 'femenino', 'fem'].includes(fold(d.sexo)));
    const sexo12 = sexoPorCodigo(datos);
    const renglones = datos
        .map((d) => normalizarRenglon(d, usaMF, sexo12))
        .filter((r) => r.nombreCompleto || r.parentescoOriginal || r.fechaNacimiento)
        .filter((r) => !esTotal(r.nombreCompleto));

    const porLlave = {};
    const vistos = {};
    let ultimoTitular = null;
    renglones.forEach((r, i) => {
        r.idx = i;
        if (r.esTitular) {
            ultimoTitular = i;
            [r.certificado, r.numEmpleado].forEach((k) => { if (k) { porLlave[fold(k)] = i; } });
        } else {
            let t;
            [r.certificado, r.numEmpleado].forEach((k) => {
                if (t === undefined && k) {
                    const base = fold(String(k).split(/[-/]/)[0]);
                    t = porLlave[fold(k)] ?? porLlave[base];
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
        const llave = fold(r.nombreCompleto) + '|' + (r.fechaNacimiento || r.edad || '');
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
    // Las bajas no se agregan como asegurados; los dependientes de un titular dado de baja tampoco.
    renglones.forEach((r) => {
        if (r.errores.length) { return; }
        if (r.movimiento === MOVIMIENTOS.BAJA) {
            r.esBaja = true;
        } else if (!r.esTitular && r.titularIndex != null && renglones[r.titularIndex].movimiento === MOVIMIENTOS.BAJA) {
            r.esBaja = true;
            r.avisos.push(`Su titular (fila ${renglones[r.titularIndex].fila}) es baja: se da de baja con él`);
        }
    });
    return renglones;
}

// Renglón validado en el formato de CensoColectivoController.MiembroEntrada (sin titularIndex).
export function payloadMiembro(r) {
    return {
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
        prima: r.prima,
        certificado: r.certificado,
        fechaAlta: r.fechaAlta || null,
        movimiento: r.movimiento || null,
        numEmpleado: r.numEmpleado,
        rfc: r.rfc,
        email: r.email,
        telefono: r.telefono
    };
}

/**
 * Asegurados válidos del censo listos para Apex: titularIndex es la posición del titular en la misma lista.
 * Devuelve { miembros, conError }.
 */
export function miembrosValidos(renglones) {
    const validos = renglones.filter((r) => !r.errores.length && !r.esBaja);
    const posicion = new Map(validos.map((r, j) => [r.idx, j]));
    return {
        miembros: validos.map((r) => ({ ...payloadMiembro(r), titularIndex: r.esTitular ? null : (posicion.get(r.titularIndex) ?? null) })),
        conError: renglones.filter((r) => r.errores.length).length,
        movimientos: conteoMovimientos(renglones),
        revisar: movimientosPorRevisar(renglones)
    };
}

/**
 * Renglones de baja o cambio (sin errores) que deben corresponder a alguien que ya existe, en el formato de
 * CensoColectivoController.PersonaMovimiento.
 */
export function movimientosPorRevisar(renglones) {
    return renglones
        .filter((r) => !r.errores.length && (r.movimiento === MOVIMIENTOS.BAJA || r.movimiento === MOVIMIENTOS.CAMBIO))
        .map((r) => ({
            fila: r.fila ?? r.idx + 1,
            nombreCompleto: r.nombreCompleto,
            certificado: r.certificado || null,
            rfc: r.rfc || null,
            movimiento: r.movimiento,
            fechaMovimiento: r.fechaAlta || null
        }));
}

// Aviso que se muestra en el renglón de baja o cambio que no corresponde a ningún contacto existente.
export const AVISO_SIN_CONTACTO = 'no existe el contacto';

/**
 * Parte los asegurados en lotes de hasta "tamano" sin separar a un titular de sus dependientes. En cada lote
 * titularIndex se recalcula a la posición dentro del lote.
 */
export function lotesCenso(miembros, tamano) {
    const grupos = [];
    const porTitular = new Map();
    miembros.forEach((m, i) => {
        if (m.titularIndex === null || m.titularIndex === undefined) {
            const g = [i];
            grupos.push(g);
            porTitular.set(i, g);
            return;
        }
        const g = porTitular.get(m.titularIndex);
        if (g) { g.push(i); }
    });
    const lotes = [];
    let lote = [];
    grupos.forEach((g) => {
        if (lote.length && lote.length + g.length > tamano) { lotes.push(lote); lote = []; }
        lote.push(...g);
    });
    if (lote.length) { lotes.push(lote); }
    return lotes.map((idxs) => {
        const pos = new Map(idxs.map((x, j) => [x, j]));
        return idxs.map((x) => {
            const m = miembros[x];
            return { ...m, titularIndex: m.titularIndex === null || m.titularIndex === undefined ? null : pos.get(m.titularIndex) };
        });
    });
}

/**
 * Une listas de vehículos sin repetir: misma serie (o, sin serie, mismo inciso). Lo que ya venía (ej. del PDF)
 * se completa con lo nuevo (ej. del Excel) sin sobrescribir.
 */
export function unirVehiculos(base, nuevos) {
    return unirPorLlave(base, nuevos, (v) => (v.serie ? 'serie ' + fold(v.serie) : (v.inciso ? 'inciso ' + fold(v.inciso) : (v.placas ? 'placas ' + fold(v.placas) : null))));
}

/** Une listas de ubicaciones sin repetir (mismo domicilio). */
export function unirUbicaciones(base, nuevas) {
    return unirPorLlave(base, nuevas, (u) => (u.direccion ? fold(u.direccion) : null));
}

function unirPorLlave(base, nuevos, llave) {
    const out = (base || []).map((x) => ({ ...x }));
    const porLlave = new Map();
    out.forEach((x) => { const k = llave(x); if (k) { porLlave.set(k, x); } });
    (nuevos || []).forEach((x) => {
        const k = llave(x);
        const ya = k ? porLlave.get(k) : null;
        if (ya) {
            Object.keys(x).forEach((c) => { if (ya[c] === undefined || ya[c] === null || ya[c] === '') { ya[c] = x[c]; } });
            return;
        }
        const copia = { ...x };
        out.push(copia);
        if (k) { porLlave.set(k, copia); }
    });
    return out;
}

// ============================================================
// Pólizas con una carátula por inciso (ej. Afirme flotilla)
// ============================================================

/**
 * Vehículos de una póliza de flotilla / colectiva de autos con una carátula por inciso (ej. Afirme), leídos del
 * texto completo sin IA: inciso, asegurado (nombre, RFC, domicilio, C.P., contratante, conductor), vehículo
 * (marca, año, descripción, serie, placas, pasajeros, motor, uso, clave), coberturas principales y primas del
 * inciso. Cada inciso ocupa varias páginas (carátula, texto legal, observaciones, UNE) y al final vienen el recibo
 * y el CFDI del inciso 1: solo la página con "DATOS DEL VEHÍCULO" es un vehículo, así que cada inciso sale una vez.
 * Con menos de dos vehículos, [] (póliza individual).
 */
export function vehiculosDeCaratulas(texto) {
        const t = String(texto || '');
        const inicio = /DATOS DEL ASEGURADO/gi;
        const cortes = [];
        let m;
        while ((m = inicio.exec(t)) !== null) { cortes.push(m.index); }
        const limpio = (v) => (v == null ? '' : String(v).replace(/\s+/g, ' ').trim());
        const uno = (re, txt) => { const r = re.exec(txt); return r ? limpio(r[1]) : ''; };
        const monto = (re, txt) => { const v = uno(re, txt); return v ? v.replace(/[$,\s]/g, '') : ''; };
        const vehiculos = [];
        const vistos = new Set();
        cortes.forEach((desde, i) => {
            const hasta = i + 1 < cortes.length ? cortes[i + 1] : t.length;
            let bloque = t.substring(desde, hasta);
            if (!/DATOS DEL VEH[IÍ]CULO/i.test(bloque) || !/N[uú]mero de Serie/i.test(bloque)) { return; }
            const total = /Prima Total\s*:\s*\$?\s*[\d,]+(?:\.\d+)?/i.exec(bloque);
            if (total) { bloque = bloque.substring(0, total.index + total[0].length); }
            // Número de inciso: el del encabezado de la carátula (antes del bloque).
            const incisos = t.substring(Math.max(0, desde - 800), desde).match(/Inciso\s*:\s*(\d+)/gi);
            const inciso = incisos ? incisos[incisos.length - 1].replace(/\D/g, '') : '';

            const asegurado = bloque.split(/DATOS DEL VEH[IÍ]CULO/i)[0];
            const vehiculo = bloque.substring(asegurado.length);
            // Domicilio: renglones entre "Nombre:" y "Contratante:" sin las etiquetas ni el RFC.
            const domM = /Nombre\s*:[^\n]*\n([\s\S]*?)\n\s*Contratante\s*:/i.exec(asegurado);
            const domicilio = domM
                ? domM[1].split('\n')
                    .map((r) => limpio(r.replace(/Domicilio\s*:/i, '').replace(/R\.?\s*F\.?\s*C\.?\s*:\s*\S*/i, '')))
                    .filter((r) => r)
                : [];
            // Descripción: del "Tipo:" a "Placas:" sin "Version:" ni el número de serie.
            const descM = /Tipo\s*:([\s\S]*?)\n\s*Placas\s*:/i.exec(vehiculo);
            const renglones = descM
                ? descM[1].replace(/Versi[oó]n\s*:/gi, ' ').replace(/N[uú]mero de Serie\s*:[ \t]*[A-Z0-9-]*/i, ' ')
                    .split('\n').map(limpio).filter((r) => r)
                : [];
            let serie = uno(/N[uú]mero de Serie\s*:[ \t]*([A-Z0-9-]{5,})/i, vehiculo);
            if (!serie) {
                // Serie partida en dos renglones por el PDF ("LZWNNNGNXRC81530" + "5"): se une hasta 17 caracteres.
                const base = renglones.find((r) => /^[A-Z0-9]{8,17}$/.test(r) && /\d/.test(r) && /[A-Z]/.test(r));
                if (base) {
                    const resto = renglones.find((r) => r !== base && /^[A-Z0-9]{1,9}$/.test(r) && (base + r).length === 17);
                    serie = base + (resto || '');
                    renglones.splice(renglones.indexOf(base), 1);
                    if (resto) { renglones.splice(renglones.indexOf(resto), 1); }
                }
            }
            const llave = serie || `inciso ${inciso}`;
            if (vistos.has(llave)) { return; }
            vistos.add(llave);
            const uso = uno(/Uso\s*:\s*(.*?)\s+Clave\s*:/i, vehiculo);
            const conductor = uno(/Conductor\s*:[ \t]*([^\n]*)/i, asegurado);
            const dm = /DA[NÑ]OS MATERIALES\s+(VALOR [A-ZÁÉÍÓÚ]+)\s+([\d.]+)\s*%/i.exec(vehiculo);
            const rt = /ROBO TOTAL\s+(VALOR [A-ZÁÉÍÓÚ]+)\s+([\d.]+)\s*%/i.exec(vehiculo);
            vehiculos.push({
                inciso,
                asegurado: uno(/Nombre\s*:\s*([^\n]+)/i, asegurado),
                rfc: uno(/R\.?\s*F\.?\s*C\.?\s*:\s*([A-ZÑ&]{3,4}\d{6}[A-Z0-9]{3})/i, asegurado),
                domicilio: domicilio.join(', '),
                calle: domicilio[0] || '',
                ciudadEstado: domicilio.slice(1).join(' '),
                cp: uno(/C\.\s*P\.\s*:?\s*(\d{5})/i, asegurado),
                contratante: uno(/Contratante\s*:\s*(.*?)(?:\s+C\.\s*P\.|\n|$)/i, asegurado),
                conductor: /[A-Za-zÁÉÍÓÚÑ]/.test(conductor) ? conductor : '',
                marca: uno(/Marca\s*:\s*([^,\n]+?)\s*,?\s*Modelo\s*:/i, vehiculo),
                anio: uno(/Modelo\s*:\s*((?:19|20)\d{2})/i, vehiculo),
                descripcion: limpio(renglones.join(' ')),
                serie,
                placas: uno(/Placas\s*:\s*(\S+)/i, vehiculo),
                pasajeros: uno(/Pasajeros\s*:\s*(\d+)/i, vehiculo),
                motor: uno(/N[uú]mero de Motor\s*:\s*(\S+)/i, vehiculo),
                uso,
                tipoVehiculo: limpio(uso.split(/\s+USO\s+/i)[0]),
                clave: uno(/Clave\s*:\s*([A-Z0-9-]+)/i, vehiculo),
                tipoCarga: uno(/Tipo de Carga\s*:[ \t]*([^\n]*)/i, vehiculo),
                tipoValor: dm ? limpio(dm[1]) : (rt ? limpio(rt[1]) : ''),
                deducibleDM: dm ? dm[2] : '',
                deducibleRT: rt ? rt[2] : '',
                responsabilidadCivil: monto(/^RESPONSABILIDAD CIVIL\s+\$\s*([\d,]+(?:\.\d+)?)/im, vehiculo),
                gastosMedicos: monto(/GASTOS M[EÉ]DICOS[^\n$]*\$\s*([\d,]+(?:\.\d+)?)/i, vehiculo),
                muerteConductor: monto(/AL CONDUCTOR\s+\$\s*([\d,]+(?:\.\d+)?)/i, vehiculo),
                primaNeta: monto(/Prima Neta\s*:\s*\$?\s*([\d,]+(?:\.\d+)?)/i, vehiculo),
                gastosExpedicion: monto(/Gastos de Expedici[oó]n\s*:\s*\$?\s*([\d,]+(?:\.\d+)?)/i, vehiculo),
                iva: monto(/I\.?\s*V\.?\s*A\.?\s*:\s*\$?\s*([\d,]+(?:\.\d+)?)/i, vehiculo),
                primaTotal: monto(/Prima Total\s*:\s*\$?\s*([\d,]+(?:\.\d+)?)/i, vehiculo)
            });
        });
        return vehiculos.length > 1 ? vehiculos : [];
}

/**
 * Incisos de una póliza con una carátula por inciso en el formato del censo / cotización de flotilla
 * (mismas llaves que regresa la IA en Extractor_Flotilla_Auto). [] si el PDF no tiene ese formato.
 */
export function incisosDeCaratulas(texto) {
    return vehiculosDeCaratulas(texto).map((v) => ({
        inciso: v.inciso,
        serie: v.serie,
        claveVehicular: v.clave,
        marca: v.marca,
        descripcion: v.descripcion,
        modelo: v.anio,
        placas: /^S\/?N$/i.test(v.placas || '') ? '' : v.placas,
        uso: v.uso,
        tipoVehiculo: v.tipoVehiculo,
        tipoValor: v.tipoValor,
        dedDM: v.deducibleDM,
        dedRT: v.deducibleRT,
        rc: v.responsabilidadCivil,
        gm: v.gastosMedicos,
        muerte: v.muerteConductor,
        primaNeta: v.primaNeta,
        derechos: v.gastosExpedicion,
        iva: v.iva,
        prima: v.primaTotal
    }));
}

// Un VIN: 17 caracteres sin I, O ni Q.
const VIN = /^[A-HJ-NPR-Z0-9]{17}$/;

/**
 * Une los incisos que regresa la IA bloque por bloque. Un PDF largo se manda en bloques de páginas y un inciso
 * puede quedar partido entre dos bloques (la carátula en uno y sus demás páginas, con el mismo "Inciso: n", en el
 * siguiente), o repetirse en el recibo / CFDI del final con el folio como "serie". Se juntan:
 *  - los de la misma serie;
 *  - los del mismo número de inciso (y mismo paquete) cuando a uno le falta la serie o solo uno trae un VIN
 *    válido (la otra "serie" es un folio o el VIN mal leído).
 * Lo que ya venía se completa con lo nuevo sin sobrescribirlo, salvo la serie cuando la nueva sí es un VIN.
 * Dos incisos con el mismo número y VIN distintos se dejan (los marca la validación).
 */
export function unirIncisosIa(incisos) {
    const vacio = (v) => v === undefined || v === null || v === '';
    const serieDe = (x) => String(x.serie ?? '').replace(/\s/g, '').toUpperCase();
    const numeroDe = (x) => { const n = numero(x.inciso); return n === null ? '' : String(Math.round(n)); };
    const mismoPaquete = (a, b) => !a.paquete || !b.paquete || fold(a.paquete) === fold(b.paquete);
    const out = [];
    const porSerie = new Map();
    const porNumero = new Map();
    (incisos || []).forEach((x) => {
        if (!x) { return; }
        const s = serieDe(x);
        const n = numeroDe(x);
        let ya = s ? porSerie.get(s) : null;
        if (!ya && n && porNumero.has(n)) {
            const mismo = porNumero.get(n);
            const sm = serieDe(mismo);
            if (mismoPaquete(x, mismo) && (!s || !sm || VIN.test(s) !== VIN.test(sm))) { ya = mismo; }
        }
        if (ya) {
            if (VIN.test(s) && !VIN.test(serieDe(ya))) { ya.serie = x.serie; }
            Object.keys(x).forEach((c) => { if (vacio(ya[c]) && !vacio(x[c])) { ya[c] = x[c]; } });
            if (serieDe(ya)) { porSerie.set(serieDe(ya), ya); }
            return;
        }
        const copia = { ...x };
        out.push(copia);
        if (s) { porSerie.set(s, copia); }
        if (n && !porNumero.has(n)) { porNumero.set(n, copia); }
    });
    return out;
}
