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
    { key: 'categoria', label: 'Categoría', alias: ['categoria', 'categorias', 'grupo', 'clase', 'nivel', 'grupo asegurado', 'subgrupo', 'regla', 'catego'] },
    { key: 'sueldoMensual', label: 'Sueldo mensual', tipo: 'numero', alias: ['sueldo mensual', 'salario mensual', 'sueldo', 'salario', 'sueldo base'] },
    { key: 'sueldoAnual', label: 'Sueldo anual', tipo: 'numero', alias: ['sueldo anual', 'salario anual', 'ingreso anual'] },
    { key: 'sumaAsegurada', label: 'Suma asegurada', tipo: 'numero', alias: ['suma asegurada', 'sa', 's a', 'suma aseg', 'int sa'] },
    { key: 'prima', label: 'Prima', tipo: 'numero', alias: ['prima', 'prima neta', 'prima anual', 'prima total', 'costo', 'prima individual'] },
    { key: 'certificado', label: 'Certificado', alias: ['certificado', 'no certificado', 'num certificado', 'numero de certificado', 'cert', 'no de certificado', 'certif'] },
    // El alta del participante se toma de la fecha de movimiento (no de la fecha de alta, ingreso o antigüedad).
    { key: 'fechaAlta', label: 'Fecha de movimiento', tipo: 'fecha', excluir: ['tipo', 'clave', 'motivo'], alias: ['fecha de movimiento', 'fecha movimiento', 'fecha de mov', 'fecha mov', 'fec mov', 'f movimiento', 'f mov', 'fecmov', 'fmov', 'fecha mto', 'fecha de mto'] },
    { key: 'tipoMovimiento', label: 'Tipo de movimiento (alta/baja/cambio)', excluir: ['fecha', 'motivo'], alias: ['tipo de movimiento', 'tipo movimiento', 'tipo de mov', 'tipo mov', 'tipo de movto', 'tipo movto', 'movimiento', 'movto', 'mov', 'clave de movimiento', 'clave movimiento', 'cve mov', 'cve movimiento', 'tipo de operacion', 'operacion', 'a b c', 'abc', 'tipo'] },
    // Soporte de recibo de la aseguradora (GMM, p. ej. el ajuste "AJF"): cada renglón trae el número de movimiento o
    // endoso en que entró y lo que cobra o devuelve; de ahí salen los endosos con su prima.
    { key: 'numeroEndoso', label: 'Número de endoso (No. Mvto.)', excluir: ['tipo', 'fecha', 'motivo'], alias: ['no mvto', 'no movto', 'num mvto', 'no de mvto', 'numero de mvto', 'no movimiento', 'no de movimiento', 'numero de movimiento', 'num movimiento', 'no endoso', 'no de endoso', 'numero de endoso', 'num endoso', 'endoso'] },
    { key: 'recargo', label: 'Recargo', tipo: 'numero', alias: ['recargo', 'recargos', 'recargo fraccionado', 'recargo por pago fraccionado'] },
    { key: 'derechos', label: 'Derechos / gastos de expedición', tipo: 'numero', alias: ['gastos de expedicion', 'gastos expedicion', 'gastos de exp', 'gastos exp', 'derechos', 'derecho de poliza', 'derechos de poliza'] },
    { key: 'iva', label: 'IVA', tipo: 'numero', alias: ['iva', 'i v a', 'impuesto'] },
    { key: 'primaMovimiento', label: 'Prima del movimiento (complemento)', tipo: 'numero', excluir: ['solo'], alias: ['complemento', 'prima del movimiento', 'importe del movimiento', 'prima del endoso', 'prima endoso', 'importe endoso'] },
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

// Parentesco abreviado con la primera palabra: "CONY." (cónyuge), "TIT. SIERRA CABALLERO" (titular), "HIJ", "ESPOSA DE...".
// La palabra completa o su inicio (3 letras o más) debe coincidir con una clave.
function parentescoAbreviado(p) {
    const w = (p || '').split(' ')[0];
    if (!w) { return null; }
    return PARENTESCOS.find((x) => x.claves.includes(w))
        || (w.length >= 3 && !/^\d+$/.test(w) ? PARENTESCOS.find((x) => x.claves.some((k) => k.length > w.length && k.startsWith(w))) : null)
        || null;
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
        || PARENTESCOS.find((x) => x.claves.includes(p) || x.claves.some((k) => k.length > 3 && p.startsWith(k)))
        || parentescoAbreviado(p);
    r.parentesco = !p ? 'Titular' : (encontrado ? encontrado.valor : 'Otro');
    // "TIT. SIERRA CABALLERO": lo que sigue al parentesco son los apellidos cuando el nombre viene sin ellos
    // (p. ej. solo "GEORGINA"). No aplica a "ESPOSA DE JUAN PÉREZ" (eso es a quién pertenece, no sus apellidos).
    if (encontrado && !parentescoPorCodigo(p)) {
        const resto = txt(d.parentesco).replace(/^\S+\s*/, '').replace(/[^\p{L}\s'-]/gu, ' ').replace(/\s+/g, ' ').trim();
        const sinApellidos = !r.apellidos && r.nombreCompleto && !/\s/.test(r.nombreCompleto.trim());
        // Solo palabras de 3 letras o más ("HIJO A" no trae apellidos).
        const palabras = resto.split(' ').filter((x) => x);
        if (palabras.length && palabras.every((x) => x.length >= 3) && sinApellidos && !/^(de|del|la|los|las)\b/i.test(resto)) {
            r.nombre = r.nombre || r.nombreCompleto.trim();
            r.apellidos = resto;
            r.nombreCompleto = `${r.nombre} ${resto}`;
        }
    }
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
    r.numeroEndoso = sinDecimalCero(d.numeroEndoso);
    r.recargo = numero(d.recargo);
    r.derechos = numero(d.derechos);
    r.iva = numero(d.iva);
    r.primaMovimiento = numero(d.primaMovimiento);

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
        numeroEndoso: r.numeroEndoso || null,
        recargo: r.recargo ?? null,
        derechos: r.derechos ?? null,
        iva: r.iva ?? null,
        primaMovimiento: r.primaMovimiento ?? null,
        numEmpleado: r.numEmpleado,
        rfc: r.rfc,
        email: r.email,
        telefono: r.telefono
    };
}

/**
 * Prima de cada endoso del archivo (soporte de recibo de la aseguradora): { 'número': { primaNeta, derechos, iva,
 * total } }. El total es la suma de lo que cobra o devuelve cada movimiento (complemento, ya con IVA). Los derechos
 * (gastos de expedición) se cobran completos; el IVA sale de la tasa de cada renglón (IVA entre prima de tarifa,
 * recargo y gastos; 16% si no se puede calcular) y la prima neta es lo que queda. Solo los endosos con complemento.
 * @param miembros: renglones con numeroEndoso, prima, recargo, derechos, iva y primaMovimiento.
 */
export function primasPorEndoso(miembros) {
    const res = {};
    const r2 = (n) => Math.round(n * 100) / 100;
    (miembros || []).forEach((m) => {
        const num = m && m.numeroEndoso ? String(m.numeroEndoso).trim() : '';
        const comp = m ? m.primaMovimiento : null;
        if (!num || comp === null || comp === undefined || Number.isNaN(Number(comp))) { return; }
        const total = Number(comp);
        const der = Number(m.derechos || 0);
        const gravable = Number(m.prima || 0) + Number(m.recargo || 0) + der;
        const iva = Number(m.iva || 0);
        const tasa = gravable && iva ? Math.abs(iva / gravable) : 0.16;
        const base = total / (1 + tasa);
        const p = res[num] || (res[num] = { primaNeta: 0, derechos: 0, iva: 0, total: 0 });
        p.primaNeta += base - der;
        p.derechos += der;
        p.iva += total - base;
        p.total += total;
    });
    Object.keys(res).forEach((k) => {
        const p = res[k];
        res[k] = { primaNeta: r2(p.primaNeta), derechos: r2(p.derechos), iva: r2(p.iva), total: r2(p.total) };
    });
    return res;
}

// Letra dañada: algunos PDF traen un renglón con la letra sin tabla de equivalencias y cada carácter llega recorrido
// («(5,&.)» es «ERICK»). Se reconoce porque no hay palabras y sí signos, y se regresa a su letra.
const ACENTOS_DANADOS = { 'È': 'Á', e: 'É', 'Ë': 'Í', 'Ï': 'Ó', 'Ò': 'Ú', f: 'Ñ', h: 'Ü' };
export function textoReparado(texto) {
    const t = String(texto || '');
    if (/[A-Za-zÁÉÍÓÚÑáéíóúñ]{3,}/.test(t) || !/[\x03$%&()*+,/0-9<=>]/.test(t)) { return t; }
    return [...t].map((c) => {
        if (ACENTOS_DANADOS[c]) { return ACENTOS_DANADOS[c]; }
        const n = c.charCodeAt(0);
        return n >= 3 && n <= 0x5d ? String.fromCharCode(n + 29) : c;
    }).join('').replace(/\s+/g, ' ').trim();
}

const importe = (t) => {
    const x = String(t).replace(/[,$]/g, '');
    const n = Number(x.endsWith('-') ? '-' + x.slice(0, -1) : x);
    return Number.isNaN(n) ? null : n;
};
const isoDe = (t) => t.split('/').reverse().join('-');
const FECHA_MX = '(\\d{2}\\/\\d{2}\\/\\d{4})';
const INICIO_LISTADO = '^([ABCM])?\\s*(\\d{5,12})\\s+(\\d{2})\\s+(.+?)\\s+([MF])\\s+(\\d{1,3})\\s+' + FECHA_MX + '\\s+' + FECHA_MX + '\\s+' + FECHA_MX + '\\s+';
// «PRIMA FRAC | DIAS | COMPLEM.» o «DÍAS | PRIMA ANUAL | IMPORTE»: lo que se cobra o devuelve es la última columna.
const RENGLON_LISTADO = new RegExp(INICIO_LISTADO + '(?:(-?[\\d,]+\\.\\d{2}-?)\\s+-?\\d+|-?\\d+\\s+(-?[\\d,]+\\.\\d{2}-?))\\s+(-?[\\d,]+\\.\\d{2}-?)$');

/**
 * Listado de movimientos de GMM que manda la aseguradora (PDF «Relación de asegurados por movimiento»): cada asegurado
 * con su complemento (o importe), que es lo que cobra o devuelve por el movimiento. El total del movimiento es la suma
 * de los complementos.
 * @param texto: texto del PDF, un renglón por línea.
 * @return { poliza, movimiento, filas: [{ tipo, certificado, parentesco, nombre, sexo, fechaNacimiento, fecha, prima,
 *          complemento }], total }, o null si el PDF no es un listado.
 */
export function listadoMovimiento(texto) {
    const t = String(texto || '');
    if (!/COMPLEM|\bIMPORTE\b/i.test(t)) { return null; }
    const filas = [];
    t.split('\n').forEach((linea) => {
        // Los renglones con la letra dañada traen un carácter de control en lugar de los espacios del nombre.
        const m = RENGLON_LISTADO.exec(linea.replace(/[ \t]+/g, ' ').trim());
        if (!m) { return; }
        filas.push({
            tipo: { B: 'Baja', C: 'Cambio', M: 'Cambio' }[m[1]] || 'Alta',
            certificado: m[2], parentesco: { '01': 'Titular', '02': 'Cónyuge', '03': 'Hijo(a)' }[m[3]] || 'Otro',
            nombre: textoReparado(m[4]), sexo: m[5] === 'M' ? 'Hombre' : 'Mujer', fechaNacimiento: isoDe(m[7]), fecha: isoDe(m[9]),
            prima: importe(m[10] || m[11]), complemento: importe(m[12])
        });
    });
    if (!filas.length) { return null; }
    const poliza = /\b[A-Z]{2,4}-\d{3,}\b/.exec(t);
    const mov = /MOVIMIENTO\s*:\s*(\d+)/i.exec(t);
    return {
        poliza: poliza ? poliza[0] : '', movimiento: mov ? mov[1] : '', filas,
        total: Math.round(filas.reduce((n, f) => n + (f.complemento || 0), 0) * 100) / 100
    };
}

/**
 * Número de certificado y de póliza que dice un documento de un asegurado (certificado, credencial…), por su etiqueta.
 * @return { certificado, poliza, movimiento } (movimiento: Alta, Baja o Cambio; vacíos si no vienen o si el documento trae varios certificados distintos).
 */
export function datosDocumento(texto) {
    const t = String(texto || '');
    const certs = new Set([...t.matchAll(/certificado\s*(?:individual)?\s*(?:n[uú]m(?:ero)?|no)?\.?\s*[:#]?\s*(\d{4,12})\b/gi)].map((m) => m[1]).filter((c) => !/^0+$/.test(c)));
    const pol = [...t.matchAll(/p[oó]liza\s*(?:n[uú]m(?:ero)?|no)?\.?\s*[:#]\s*([A-Z0-9][A-Z0-9/-]{3,})/gi)].map((m) => m[1])
        .find((x) => /\d{3,}/.test(x) && !/^\d{1,2}\/\d{1,2}\//.test(x));
    const mov = /tipo de movimiento\s*:\s*([^\n]*)/i.exec(t);
    const movimiento = !mov ? '' : (/cambio|modificaci/i.test(mov[1]) ? 'Cambio' : (/baja/i.test(mov[1]) ? 'Baja' : (/alta/i.test(mov[1]) ? 'Alta' : '')));
    return { certificado: certs.size === 1 ? [...certs][0] : '', poliza: pol || '', movimiento };
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
 * También lee los endosos de alta (la carátula de uno o dos incisos nuevos, ej. "Inciso: 101"): la descripción sin la
 * clave al inicio ("701788 - ITALIKA FT150"), placas y motor solo si traen dígitos ("NA", ".", "HECHO EN WULING" no
 * son) y el valor convenido de las OBSERVACIONES del inciso.
 * Con menos de "minimo" vehículos (2 por omisión: un solo vehículo es una póliza individual), [].
 */
export function vehiculosDeCaratulas(texto, minimo = 2) {
        const t = String(texto || '');
        const inicio = /DATOS DEL ASEGURADO/gi;
        const cortes = [];
        let m;
        while ((m = inicio.exec(t)) !== null) { cortes.push(m.index); }
        const limpio = (v) => (v == null ? '' : String(v).replace(/\s+/g, ' ').trim());
        const uno = (re, txt) => { const r = re.exec(txt); return r ? limpio(r[1]) : ''; };
        const monto = (re, txt) => { const v = uno(re, txt); return v ? v.replace(/[$,\s]/g, '') : ''; };
        // Placas / número de motor: "SN", "NA", "." o "HECHO" (de "HECHO EN WULING") no son un dato.
        const conDigito = (v) => (/\d/.test(v) ? v : '');
        const vehiculos = [];
        const vistos = new Set();
        cortes.forEach((desde, i) => {
            const hasta = i + 1 < cortes.length ? cortes[i + 1] : t.length;
            let bloque = t.substring(desde, hasta);
            if (!/DATOS DEL VEH[IÍ]CULO/i.test(bloque) || !/N[uú]mero de Serie/i.test(bloque)) { return; }
            // Valor convenido de las OBSERVACIONES (otra página del mismo inciso, antes de la siguiente carátula).
            const valorConvenido = monto(/VALOR\s+CON?VENIDO\s*:?\s*\$?\s*([\d,]+(?:\.\d+)?)/i, bloque);
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
                descripcion: limpio(renglones.join(' ')).replace(/^\d+\s*-\s*/, ''),
                serie,
                placas: conDigito(uno(/Placas\s*:\s*(\S+)/i, vehiculo)),
                pasajeros: uno(/Pasajeros\s*:\s*(\d+)/i, vehiculo),
                motor: conDigito(uno(/N[uú]mero de Motor\s*:\s*(\S+)/i, vehiculo)),
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
                primaTotal: monto(/Prima Total\s*:\s*\$?\s*([\d,]+(?:\.\d+)?)/i, vehiculo),
                valorConvenido
            });
        });
        return vehiculos.length >= minimo ? vehiculos : [];
}

/**
 * Incisos de una póliza con una carátula por inciso en el formato del censo / cotización de flotilla
 * (mismas llaves que regresa la IA en Extractor_Flotilla_Auto). Aquí basta un inciso (ej. el endoso de alta de un
 * vehículo). [] si el PDF no tiene ese formato.
 */
export function incisosDeCaratulas(texto) {
    // Endoso de Quálitas: sus carátulas de inciso ya vienen en este formato.
    const qualitas = endosoQualitas(texto);
    if (qualitas && qualitas.vehiculos.length) { return qualitas.vehiculos; }
    return vehiculosDeCaratulas(texto, 1).map((v) => ({
        inciso: v.inciso,
        serie: v.serie,
        claveVehicular: v.clave,
        marca: v.marca,
        descripcion: v.descripcion,
        modelo: v.anio,
        placas: v.placas,
        uso: v.uso,
        tipoVehiculo: v.tipoVehiculo,
        tipoValor: v.valorConvenido ? 'VALOR CONVENIDO' : v.tipoValor,
        valor: v.valorConvenido,
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

/**
 * Endoso de la aseguradora, leído del texto sin IA. Formatos de Afirme:
 *  - Autos ("ENDOSO-B"): "INFORMACIÓN GENERAL DEL ENDOSO", "Endoso No.", "Tipo de Endoso: CAMBIO DE DATOS",
 *    "Vigencia del Endoso", "Inciso No. 102 - 200048 - CHEVROLET ..." y las primas junto a su etiqueta.
 *  - Daños ("elabora endoso a la póliza"): "Endoso No. 16", "Endoso de Tipo: Modificación de Póliza",
 *    "MOVIMIENTOS DE APLICACIÓN GENERAL" (toca toda la póliza, no una ubicación) y las primas en una tabla
 *    ("Concepto Prima Neta Recargo Derecho IVA (16%) Total" / "Prima $694.86 $0.00 $350.00 $167.18 $1,212.04").
 * Regresa número de endoso, tipo y movimiento que implica (alta, baja o cambio), si es de aplicación general (sin
 * incisos), fecha en que surte efecto, incisos que toca (número, clave y descripción), detalle de la modificación y
 * desglose de primas. null si el texto no es un endoso.
 * @param texto: texto del PDF.
 * @param nombreArchivo: nombre del archivo (de ahí sale el número de endoso si el texto no lo trae, ej. "_000038").
 */
export function endosoDeTexto(texto, nombreArchivo) {
    const t = String(texto || '');
    const qualitas = endosoQualitas(t);
    if (qualitas) { return qualitas; }
    const hdi = endosoHdi(t);
    if (hdi) { return hdi; }
    if (!/Endoso\s+No\.?\s*:?/i.test(t) || !/(Tipo\s+de\s+Endoso|Endoso\s+de\s+Tipo)/i.test(t)
        || !/(INFORMACI[OÓ]N GENERAL DEL ENDOSO|\bENDOSO-[A-Z]\b|PRESENTE CONTRATO SUFRE|elabora endoso)/i.test(t)) {
        return null;
    }
    const limpio = (v) => (v == null ? '' : String(v).replace(/\s+/g, ' ').trim());
    const montoNum = (v) => (v == null || v === '' ? null : Number(String(v).replace(/[$,\s]/g, '')));
    // Monto junto a su etiqueta, antes ("$0.00 Prima Neta") o después ("Gastos Expedición $0.00").
    const monto = (etiqueta) => {
        const despues = new RegExp(etiqueta + '\\s*:?\\s*\\$\\s*([\\d,]+(?:\\.\\d+)?)', 'i').exec(t);
        if (despues) { return montoNum(despues[1]); }
        const antes = new RegExp('\\$\\s*([\\d,]+(?:\\.\\d+)?)\\s*' + etiqueta, 'i').exec(t);
        return antes ? montoNum(antes[1]) : null;
    };
    const lineas = t.split('\n');

    // Número: junto a la etiqueta ("Endoso No. 16"), junto al número de póliza ("3201-033679-00   38"; en Vida
    // "005-0000364872-00 0000321804 - B", con la letra del endoso) o del archivo.
    let numero = '';
    const enLinea = /Endoso\s+No\.?\s*:?[ \t]*(\d+)/i.exec(t);
    const conPoliza = /\b\d{3,5}-\d{5,10}-\d{2}\s+(\d{1,10})(?:\s*-\s*([A-Z])\b)?/.exec(t);
    if (enLinea) { numero = enLinea[1]; } else if (conPoliza) { numero = conPoliza[1].replace(/^0+(?=\d)/, '') + (conPoliza[2] ? '-' + conPoliza[2] : ''); }
    if (!numero) {
        const delArchivo = /endoso[^0-9]*(?:\d[\d-]*[_\s-]+)?0*(\d+)\.[a-z]+$/i.exec(String(nombreArchivo || ''));
        if (delArchivo) { numero = delArchivo[1]; }
    }
    numero = numero.replace(/^0+(?=\d)/, '');

    // Tipo: "Endoso de Tipo: ...", junto a "Tipo de Endoso:" o un renglón que es solo el tipo ("CAMBIO DE DATOS").
    const TIPO = '(?:ALTA|BAJA|CAMBIO|MODIFICACI[OÓ]N|CANCELACI[OÓ]N|INCLUSI[OÓ]N|EXCLUSI[OÓ]N|AUMENTO|DISMINUCI[OÓ]N|CORRECCI[OÓ]N)';
    let tipo = '';
    const tipoDe = /Endoso\s+de\s+Tipo\s*:[ \t]*([^\n]+)/i.exec(t);
    const tipoLinea = new RegExp('Tipo\\s+de\\s+Endoso\\s*:[ \\t]*(' + TIPO + '[A-ZÁÉÍÓÚÑ ]*)', 'i').exec(t);
    const tipoSolo = new RegExp('^\\s*(' + TIPO + '(?: [A-ZÁÉÍÓÚÑ]+){0,4})\\s*$', 'm').exec(t);
    // Cualquier otro tipo en mayúsculas junto a la etiqueta ("Tipo de Endoso: DE MOVIMIENTOS SIN COBRO DE PRIMAS").
    const tipoOtro = /Tipo\s+de\s+Endoso\s*:[ \t]*([A-ZÁÉÍÓÚÑ][A-ZÁÉÍÓÚÑ ]{2,80})/.exec(t);
    if (tipoDe) { tipo = limpio(tipoDe[1]); } else if (tipoLinea) { tipo = limpio(tipoLinea[1]); } else if (tipoSolo) { tipo = limpio(tipoSolo[1]); }
    else if (tipoOtro) { tipo = limpio(tipoOtro[1]); }
    const f = tipo.toUpperCase();
    let movimiento = /BAJA|CANCELACI|EXCLUSI/.test(f) ? 'baja' : (/ALTA|INCLUSI/.test(f) ? 'alta' : 'cambio');

    // Fecha en que surte efecto: la primera fecha después de "Vigencia del Endoso" o, si no, de "Desde".
    let fecha = null;
    const vig = /Vigencia\s+del\s+Endoso/i.exec(t) || /\bDesde\b/i.exec(t);
    const fm = /(\d{2})\/(\d{2})\/(\d{4})/.exec(vig ? t.substring(vig.index) : '');
    if (fm) { fecha = `${fm[3]}-${fm[2]}-${fm[1]}`; }

    // Incisos: "Inciso No. 102 - 200048 - CHEVROLET TORNADO VAN ... (CAMIONES FLOTILLA) :".
    const incisos = [];
    const vistos = new Set();
    const reInciso = /Inciso\s+No\.?\s*:?\s*(\d+)\s*-\s*([A-Z0-9]+)\s*-\s*([^\n]*?)\s*(?:\(([^)\n]*)\))?\s*:?[ \t]*$/gim;
    let m;
    while ((m = reInciso.exec(t)) !== null) {
        if (vistos.has(m[1])) { continue; }
        vistos.add(m[1]);
        incisos.push({ inciso: m[1], clave: m[2], descripcion: limpio(m[3]), paquete: limpio(m[4]) });
    }
    // Movimientos al inciso (Daños): tabla "Inciso/ Sección Movimiento Realizado" con renglones como
    // "30 Datos de Riesgo Alta de Inciso". Cada inciso trae su movimiento y, si es alta, su especificación.
    const movimientoDe = (txt) => (/BAJA|CANCELACI|EXCLUSI/i.test(txt) ? 'baja' : (/ALTA|INCLUSI/i.test(txt) ? 'alta' : 'cambio'));
    const iMov = lineas.findIndex((l) => /MOVIMIENTOS AL INCISO/i.test(l));
    if (iMov >= 0) {
        for (let i = iMov + 1; i < lineas.length; i++) {
            const l = limpio(lineas[i]);
            if (/^Concepto\b|^\$|Prima Neta/i.test(l)) { break; }
            const mi = /^(\d+)\s+(.*?)\s*\b((?:Alta|Baja|Cancelaci[oó]n|Modificaci[oó]n|Cambio|Inclusi[oó]n|Exclusi[oó]n)\b.*)$/i.exec(l);
            if (!mi || vistos.has(mi[1])) { continue; }
            vistos.add(mi[1]);
            incisos.push({ inciso: mi[1], seccion: limpio(mi[2]), descripcion: limpio(mi[3]), movimiento: movimientoDe(mi[3]),
                ...especificacionUbicacion(t, mi[1]) });
        }
        // Tabla partida en renglones (el número del inciso queda solo, a media descripción): el inciso es el número
        // suelto que tiene su "ESPECIFICACIÓN UBICACIÓN n" y el movimiento es todo el texto de la tabla.
        if (!incisos.some((x) => x.seccion !== undefined)) {
            const bloque = [];
            const sueltos = [];
            for (let i = iMov + 1; i < lineas.length; i++) {
                const l = limpio(lineas[i]);
                if (/^Concepto\b|^\$|Prima Neta/i.test(l)) { break; }
                if (/^\d{1,4}$/.test(l)) { sueltos.push(l); continue; }
                if (!l || /^(Inciso\/?|Secci[oó]n Movimiento Realizado|Ubicaci[oó]n|Sección)$/i.test(l)
                    || /^[A-ZÁÉÍÓÚÑ ]+$/.test(l) && !/[a-z]/.test(l) && l.split(' ').length <= 3) { continue; }
                bloque.push(l);
            }
            const desc = limpio(bloque.join(' '));
            sueltos.filter((n) => new RegExp(`ESPECIFICACI[OÓ]N\\s+UBICACI[OÓ]N\\s+${n}\\b`, 'i').test(t)).forEach((n) => {
                if (vistos.has(n) || !desc) { return; }
                vistos.add(n);
                incisos.push({ inciso: n, seccion: '', descripcion: desc.substring(0, 600), movimiento: movimientoDe(desc),
                    ...especificacionUbicacion(t, n) });
            });
        }
    }
    const general = !incisos.length;

    // Detalle: lo que sigue al último renglón de inciso (o al tipo del endoso) hasta las primas o el texto fijo.
    let inicio = -1;
    lineas.forEach((l, i) => { if (/Inciso\s+No\.?/i.test(l)) { inicio = i; } });
    if (inicio < 0) { inicio = lineas.findIndex((l) => /Endoso\s+de\s+Tipo\s*:/i.test(l)); }
    // Vida: el detalle va en el "Texto Aclaratorio".
    if (inicio < 0) { inicio = lineas.findIndex((l) => /Texto\s+Aclaratorio\s*:?\s*$/i.test(l)); }
    let detalle = '';
    if (inicio >= 0) {
        const partes = [];
        for (let i = inicio + 1; i < lineas.length; i++) {
            const l = limpio(lineas[i]);
            if (/^\$|^Concepto\b|^MOVIMIENTOS AL INCISO|Prima Neta|Descuento|Financiamiento|Gastos Expedici|I\.V\.A|Los dem[aá]s t|REG\. C\.N\.S|Art[ií]culo \d|En testimonio|Funcionario|Moneda|Forma de pago/i.test(l)) { break; }
            // "2 Se agrega Texto:": sin el número de movimiento.
            if (l) { partes.push(l.replace(/^\d+\s+(?=[A-ZÁÉÍÓÚÑ])/i, '')); }
        }
        detalle = limpio(partes.join(' ')).replace(/\.{2,}/g, '.').substring(0, 1000);
    }
    // Movimientos al inciso: van en el detalle ("Inciso 30 (Datos de Riesgo): Alta de Inciso").
    const porInciso = incisos.filter((i) => i.seccion !== undefined)
        .map((i) => `Inciso ${i.inciso}${i.seccion ? ` (${i.seccion})` : ''}: ${i.descripcion}`);
    if (porInciso.length) { detalle = limpio([detalle, porInciso.join('; ')].filter((x) => x).join(' · ')).substring(0, 1000); }

    // Primas: en tabla ("Concepto Prima Neta Recargo Derecho IVA Total" y abajo los montos) o junto a su etiqueta.
    let primaNeta = null;
    let derechos = null;
    let iva = null;
    let total = null;
    const iTabla = lineas.findIndex((l) => /^\s*Concepto\s+Prima\s+Neta\b/i.test(l));
    const fila = iTabla >= 0 ? lineas.slice(iTabla + 1, iTabla + 4).find((l) => /\$\s*[\d,]+\.\d+/.test(l)) : null;
    if (fila) {
        const encabezado = lineas[iTabla];
        const columnas = [['neta', /Prima\s+Neta/i], ['recargo', /Recargo/i], ['derecho', /Derecho/i], ['iva', /IVA|I\.V\.A/i], ['total', /Total/i]]
            .map(([k, re]) => ({ k, pos: encabezado.search(re) }))
            .filter((c) => c.pos >= 0)
            .sort((a, b) => a.pos - b.pos);
        const montos = (fila.match(/\$\s*[\d,]+(?:\.\d+)?/g) || []).map(montoNum);
        const de = (k) => { const i = columnas.findIndex((c) => c.k === k); return i >= 0 && i < montos.length ? montos[i] : null; };
        primaNeta = de('neta');
        derechos = de('derecho');
        iva = de('iva');
        total = de('total');
    } else {
        primaNeta = monto('Prima\\s+Neta');
        derechos = monto('Gastos\\s+(?:de\\s+)?Expedici[oó]n');
        iva = monto('I\\.?\\s*V\\.?\\s*A\\.?');
        const financiamiento = monto('Financiamiento');
        total = monto('Prima\\s+Total');
        if (total === null && [primaNeta, derechos, iva].some((v) => v !== null)) {
            total = [primaNeta, derechos, iva, financiamiento].reduce((s, v) => s + (v || 0), 0);
        }
    }
    // Con movimientos al inciso, el del endoso es el de sus incisos (si todos son alta, es alta; si todos baja, baja).
    const movs = incisos.filter((i) => i.movimiento).map((i) => i.movimiento);
    if (movs.length && movs.every((x) => x === movs[0])) { movimiento = movs[0]; }
    // Un solo inciso dado de alta: su prima es la prima neta del endoso.
    const altas = incisos.filter((i) => i.movimiento === 'alta');
    if (altas.length === 1 && incisos.length === 1 && primaNeta !== null) { altas[0].prima = primaNeta; }
    return { numero, tipo, movimiento, general, fecha, incisos, detalle, primaNeta, derechos, iva, total };
}

const MESES_CORTOS = { ENE: '01', FEB: '02', MAR: '03', ABR: '04', MAY: '05', JUN: '06', JUL: '07', AGO: '08', SEP: '09', SEPT: '09', OCT: '10', NOV: '11', DIC: '12' };

/**
 * Endoso de Daños de HDI ("ENDOSO EMPRESA"): "No. de Póliza: 49 - 5277 Inciso: 6 Endoso: D0087", el tipo en el renglón
 * siguiente ("CANCELACIÓN DE CIS"), "Vigencia: Desde las 12 Hrs. del 14/OCT/2026", el "Detalle del Endoso" y las primas
 * del formato de pago ("Prima Neta -2,726.08", "Derecho de Póliza 0.00", "I.V.A. 16.00% -436.17", "Total a pagar ...").
 * Cada inciso de HDI es una ubicación. null si no es un endoso de HDI.
 */
function endosoHdi(t) {
    const cab = /No\.\s*de\s+P[oó]liza\s*:\s*([\d -]+?)\s+Inciso\s*:\s*(\d+)\s+Endoso\s*:\s*([A-Z0-9-]+)/i.exec(t);
    if (!cab || !/ENDOSO\s+EMPRESA|Detalle\s+del\s+Endoso/i.test(t)) { return null; }
    const limpio = (v) => (v == null ? '' : String(v).replace(/\s+/g, ' ').trim());
    const num = (v) => (v == null ? null : Number(String(v).replace(/[$,\s]/g, '')));
    const lineas = t.split('\n').map(limpio);
    const iEnc = lineas.findIndex((l) => /^ENDOSO\s+(MAESTRO\s+)?EMPRESA$/i.test(l));
    const tipo = iEnc >= 0 && lineas[iEnc + 1] && !/^Operaci[oó]n/i.test(lineas[iEnc + 1]) ? lineas[iEnc + 1] : 'Endoso';
    // Detalle: lo que sigue a "Detalle del Endoso:" hasta la tabla de primas.
    const partes = [];
    const iDet = lineas.findIndex((l) => /^Detalle\s+del\s+Endoso\s*:?$/i.test(l));
    for (let i = iDet + 1; iDet >= 0 && i < lineas.length; i++) {
        const l = lineas[i];
        if (/^(Reducci[oó]n|Prima\s+Neta|-?\$|Art[ií]culo\s+\d)/i.test(l)) { break; }
        if (l && !/^SE HACE CONSTAR POR MEDIO DEL PRESENTE ENDOSO QUE:?$/i.test(l)) { partes.push(l); }
    }
    const detalle = limpio(partes.join(' ')).substring(0, 1000);
    const que = `${tipo} ${detalle}`.toUpperCase();
    const movimiento = /CANCELA|BAJA|EXCLU/.test(que) ? 'baja' : (/\bALTA\b|INCLU|SE AGREGA/.test(que) ? 'alta' : 'cambio');
    const fm = /Vigencia\s*:\s*Desde[^\n]*?(\d{1,2})\/([A-Z]{3,4})\/(\d{4})/i.exec(t);
    const fecha = fm && MESES_CORTOS[fm[2].toUpperCase()] ? `${fm[3]}-${MESES_CORTOS[fm[2].toUpperCase()]}-${fm[1].padStart(2, '0')}` : null;
    const monto = (re) => { const x = re.exec(t); return x ? num(x[1]) : null; };
    let primaNeta = monto(/^\s*Prima\s+Neta\s+(-?[\d,]+\.\d+)\s*$/im);
    let derechos = monto(/^\s*Derecho\s+de\s+P[oó]liza\s+(-?[\d,]+\.\d+)/im);
    let iva = monto(/^\s*I\.V\.A\.[^\n]*?(-?[\d,]+\.\d+)\s*$/im);
    let total = monto(/^\s*Total\s+a\s+pagar\s+(-?[\d,]+\.\d+)/im);
    if (primaNeta === null) {
        // Endoso maestro: los importes van en un solo renglón con "Tasa: … Importe: …"; la prima neta queda al
        // principio o al final del renglón, el total es el mayor y el I.V.A. va justo antes del total.
        const r = lineas.find((l) => /Tasa\s*:.*Importe\s*:/i.test(l) && /\$/.test(l));
        const ms = r ? (r.match(/-?\$\s*-?[\d,]+\.\d+/g) || []).map(num) : [];
        if (ms.length >= 3) {
            const alInicio = /^-?\$/.test(r);
            primaNeta = alInicio ? ms[0] : ms[ms.length - 1];
            const resto = alInicio ? ms.slice(1) : ms.slice(0, -1);
            const iTot = resto.reduce((k, v, j) => (Math.abs(v) > Math.abs(resto[k]) ? j : k), 0);
            total = resto[iTot];
            iva = iTot > 0 ? resto[iTot - 1] : null;
            derechos = Math.round((total - primaNeta - (iva || 0)) * 100) / 100;
        }
    }
    const inciso = String(Number(cab[2]));
    const inc = { inciso, seccion: '', descripcion: tipo, movimiento };
    if (movimiento === 'alta') {
        // Alta de ubicación: domicilio de la empresa, giro y suma asegurada (Todo Riesgo Incendio edificio + contenidos).
        const dom = /Domicilio\s+de\s+la\s+Empresa\s*:\s*([\s\S]*?)\n\s*Informaci[oó]n\s+de\s+la\s+Empresa/i.exec(t);
        const giro = /^\s*Giro\s*:\s*([^\n]+)/im.exec(t);
        const b = t.substring(dom ? dom.index : 0);
        const ed = /Todo\s+Riesgo\s+Incendio\s+Edificio\s+\$\s*([\d,]+\.\d+)/i.exec(b);
        const co = /Todo\s+Riesgo\s+Incendio\s+Contenidos\s+\$\s*([\d,]+\.\d+)/i.exec(b);
        const suma = (ed ? num(ed[1]) : 0) + (co ? num(co[1]) : 0);
        if (dom) { inc.direccion = limpio(dom[1]).replace(/\s+,/g, ','); }
        if (giro) { inc.giro = limpio(giro[1]); }
        if (suma) { inc.sumaAsegurada = suma; }
        if (primaNeta !== null) { inc.prima = primaNeta; }
    }
    return {
        numero: cab[3].toUpperCase(),
        tipo: tipo.charAt(0) + tipo.slice(1).toLowerCase(),
        movimiento,
        general: false,
        fecha,
        incisos: [inc],
        detalle: limpio(`Inciso ${inciso}: ${detalle || inc.direccion || tipo}`).substring(0, 1000),
        primaNeta, derechos, iva, total,
        aseguradora: 'HDI'
    };
}

/**
 * Especificación de una ubicación en un endoso / póliza de Daños de Afirme ("ESPECIFICACIÓN UBICACIÓN 30"): domicilio,
 * giro y suma asegurada (la de Incendio de sus secciones: edificio y contenidos). Vacío si no viene.
 */
export function especificacionUbicacion(texto, inciso) {
    const t = String(texto || '');
    const re = /ESPECIFICACI[OÓ]N\s+UBICACI[OÓ]N\s+(\d+)/gi;
    let desde = -1;
    let hasta = t.length;
    let m;
    while ((m = re.exec(t)) !== null) {
        if (m[1] === String(inciso)) {
            if (desde < 0) { desde = m.index; }
        } else if (desde >= 0) {
            hasta = m.index;
            break;
        }
    }
    if (desde < 0) { return {}; }
    const b = t.substring(desde, hasta);
    const limpio = (v) => (v == null ? '' : String(v).replace(/\s+/g, ' ').trim());
    const dir = /Ubicaci[oó]n\s*:\s*([\s\S]*?)\n\s*Tipo\s+Constructivo/i.exec(b);
    const giro = /Giro\s+o\s+Actividad\s*:\s*([^\n]+)/i.exec(b);
    let suma = 0;
    const reInc = /Incendio\s+y\/o\s+Rayo\s+\$\s*([\d,]+(?:\.\d+)?)/gi;
    let x;
    while ((x = reInc.exec(b)) !== null) { suma += Number(x[1].replace(/,/g, '')); }
    return {
        direccion: dir ? limpio(dir[1]).replace(/\s+,/g, ',') : '',
        giro: giro ? limpio(giro[1]) : '',
        sumaAsegurada: suma || null
    };
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
 * Lo que ya venía se completa con lo nuevo sin sobrescribirlo, salvo la serie cuando la nueva sí es un VIN y los datos
 * de un renglón sin número de inciso (ej. un anexo con el mismo vehículo), que ceden ante los del renglón con inciso.
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
            if (vacio(ya.inciso) && n) {
                Object.keys(x).forEach((c) => { if (c !== 'serie' && !vacio(x[c])) { ya[c] = x[c]; } });
                if (!porNumero.has(n)) { porNumero.set(n, ya); }
            }
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

// ============================================================
// Bloques para la IA que no parten un inciso
// ============================================================

// Número de inciso del encabezado de una página ("Inciso: 15" en sus primeros renglones); null si no tiene.
function incisoDePagina(pagina) {
    const m = /Inciso\s*:\s*(\d+)/i.exec(String(pagina || '').substring(0, 600));
    return m ? String(Number(m[1])) : null;
}

// Números de serie con forma de VIN (17 caracteres con letras y dígitos, sin I, O ni Q) de un texto.
const VIN_EN_TEXTO = /(?:^|[^A-Za-z0-9])((?=[A-HJ-NPR-Z0-9]*[A-HJ-NPR-Z])(?=[A-HJ-NPR-Z0-9]*\d)[A-HJ-NPR-Z0-9]{17})(?![A-Za-z0-9])/g;
function vinsDe(texto) {
    return [...String(texto || '').matchAll(VIN_EN_TEXTO)].map((m) => m[1]);
}

/**
 * Agrupa las páginas por inciso: cada grupo empieza en la página con un "Inciso: n" nuevo y sigue con las páginas
 * del mismo inciso y las que no traen encabezado (ej. el anexo de RC en E.U.A. y Canadá de Chubb que viene tras
 * cada automóvil de Afirme). Las páginas de un inciso que ya pasó y sin ningún VIN (recibo de primas y CFDI del
 * final) se descartan. Devuelve [{ inciso, paginas }]; las páginas antes del primer inciso van con inciso null.
 */
export function gruposPorInciso(paginas) {
    const grupos = [];
    const vistos = new Set();
    let actual = null;
    (paginas || []).forEach((p) => {
        const n = incisoDePagina(p);
        if (n && (!actual || actual.inciso !== n)) {
            if (vistos.has(n) && !vinsDe(p).length) { actual = { inciso: n, descartado: true, paginas: [] }; return; }
            vistos.add(n);
            actual = { inciso: n, paginas: [] };
            grupos.push(actual);
        } else if (!actual) {
            actual = { inciso: null, paginas: [] };
            grupos.push(actual);
        }
        if (!actual.descartado) { actual.paginas.push(p); }
    });
    return grupos;
}

/**
 * Bloques de hasta "maxCaracteres" para mandar a la IA, armados con incisos completos: un inciso nunca queda partido
 * entre dos bloques (si un solo inciso no cabe, se parte por páginas). En un PDF sin "Inciso: n" equivale a partir
 * por páginas completas, como bloquesPdf.
 */
export function bloquesPorInciso(paginas, maxCaracteres) {
    const bloques = [];
    let actual = '';
    const agregar = (texto) => {
        if (actual && actual.length + texto.length > maxCaracteres) { bloques.push(actual); actual = ''; }
        actual += texto;
    };
    gruposPorInciso(paginas).forEach((g) => {
        const texto = g.paginas.map((p) => p + '\n').join('');
        if (g.inciso !== null && texto.length <= maxCaracteres) { agregar(texto); return; }
        g.paginas.forEach((p) => agregar(p + '\n'));
    });
    if (actual.trim()) { bloques.push(actual); }
    return bloques;
}

/**
 * Corrige el número de inciso que dio la IA con el del PDF: si la serie del vehículo aparece en las páginas de un
 * solo inciso, ese es su número (la IA tomaba el "Inciso: n" del encabezado de otra página del bloque).
 */
export function corregirIncisos(incisos, paginas) {
    const porVin = new Map();
    gruposPorInciso(paginas).forEach((g) => {
        if (g.inciso === null) { return; }
        new Set(vinsDe(g.paginas.join('\n'))).forEach((v) => {
            porVin.set(v, porVin.has(v) && porVin.get(v) !== g.inciso ? null : g.inciso);
        });
    });
    return (incisos || []).map((x) => {
        if (!x) { return x; }
        const n = porVin.get(String(x.serie ?? '').replace(/\s/g, '').toUpperCase());
        return n && String(numero(x.inciso)) !== n ? { ...x, inciso: Number(n) } : x;
    });
}

/**
 * Endoso de GMM sin movimientos de asegurados (cláusula o beneficio adicional que se adhiere a la póliza, o la lista
 * "ENDOSOS QUE INTEGRAN LA POLIZA"), leído del texto del PDF. Da lo necesario para registrarlo como endoso:
 * descripción (nombre del endoso y categorías a las que aplica) y fecha (inicio de vigencia o fecha del documento).
 * null si el texto no es de ese tipo.
 * @param texto: texto del PDF.
 */
export function clausulaDeTexto(texto) {
    const t = String(texto || '').replace(/\r/g, '');
    const plano = t.replace(/\s+/g, ' ');
    const iso = (m) => (m ? `${m[3]}-${m[2]}-${m[1]}` : null);
    const categorias = (lista) => [...new Set(lista)].sort();
    // Lista de endosos de la póliza: "1 - Clave endoso 2019024 Nombre endoso: Complicaciones Vacuna COVID19. Aplica
    // para las categorías: 01."
    if (/ENDOSOS\s+QUE\s+INTEGRAN\s+LA\s+P[OÓ]LIZA/i.test(plano)) {
        const nombres = new Map();
        const cats = [];
        const re = /Clave\s+endoso\s+(\w+)\s+Nombre\s+endoso:\s*(.+?)\.\s*Apl\s*i\s*c\s*a\s+para\s+las\s+categor[ií]as:\s*([\d,\s]+)/gi;
        let m;
        while ((m = re.exec(plano)) !== null) {
            nombres.set(m[1], m[2].replace(/\s+/g, ' ').trim());
            m[3].split(/[,\s]+/).filter((x) => x).forEach((x) => cats.push(x));
        }
        if (!nombres.size) { return null; }
        const c = categorias(cats);
        return {
            descripcion: [...nombres.entries()].map(([k, v]) => `${v} (clave ${k})`).join('; ')
                + (c.length ? ` · categorías ${c.join(', ')}` : ''),
            fecha: iso(plano.match(/Fecha:\s*(\d{2})\/(\d{2})\/(\d{4})/i)),
            categorias: c
        };
    }
    // Cláusula: "BENEFICIO ADICIONAL PARA ... COLECTIVO / Beneficio que se adhiere y forma parte integrante de la Póliza
    // ... aplicable a la categoría 00, cuya vigencia es del 01/12/2023 al 01/12/2024".
    if (!/se\s+adhiere\s+y\s+forma\s+parte\s+integrante/i.test(plano)) { return null; }
    const lineas = t.split('\n').map((l) => l.trim()).filter((l) => l && !/^=== PAGINA/.test(l));
    const i = lineas.findIndex((l) => /se\s+adhiere\s+y\s+forma\s+parte/i.test(l));
    // Título: los renglones en mayúsculas antes de "Beneficio que se adhiere".
    const titulo = [];
    for (let j = i - 1; j >= 0 && titulo.length < 4; j--) {
        if (lineas[j] !== lineas[j].toUpperCase() || !/[A-ZÁÉÍÓÚÑ]{3}/.test(lineas[j])) { break; }
        titulo.unshift(lineas[j]);
    }
    const cats = [];
    const re = /aplicable\s+a\s+la\s+categor[ií]a\s+(\d+)/gi;
    let m;
    while ((m = re.exec(plano)) !== null) { cats.push(m[1]); }
    const c = categorias(cats);
    const nombre = titulo.join(' ').replace(/\s+-\s+/g, '-').replace(/\s+/g, ' ').trim() || 'Beneficio adicional';
    return {
        descripcion: nombre + (c.length ? ` · ${c.length > 1 ? 'categorías' : 'categoría'} ${c.join(', ')}` : ''),
        fecha: iso(plano.match(/vigencia\s+es\s+del\s+(\d{2})\/(\d{2})\/(\d{4})/i)),
        categorias: c
    };
}

// ============================================================
// Endosos de Quálitas
// ============================================================

// Encabezado de cada página de Quálitas: PÓLIZA (10 dígitos), ENDOSO (6) e INCISO (4). Según el lector de PDF los
// valores salen bajo sus etiquetas ("PÓLIZA ENDOSO INCISO" / "0971582235 151760 0006"), cada uno junto a la suya
// ("PÓLIZA 0971582235 ENDOSO 151760 INCISO 0006") o en otro orden ("INCISO 0000 ENDOSO 151760 PÓLIZA 0971582235").
function encabezadosQualitas(t) {
    const plano = t.replace(/\s+/g, ' ');
    const res = [];
    const agregar = (index, poliza, endoso, inciso) => res.push({ index, poliza, endoso, inciso });
    const patrones = [
        [/P[OÓ]LIZA ?(\d{10}) ?ENDOSO ?(\d{6}) ?INCISO ?(\d{4})\b/gi, (m) => [m[1], m[2], m[3]]],
        [/INCISO ?(\d{4}) ?ENDOSO ?(\d{6}) ?P[OÓ]LIZA ?(\d{10})\b/gi, (m) => [m[3], m[2], m[1]]],
        [/\b(\d{10}) (\d{6}) (\d{4})\b/g, (m) => [m[1], m[2], m[3]]]
    ];
    patrones.forEach(([re, valores]) => {
        let m;
        while ((m = re.exec(plano)) !== null) {
            if (!res.some((r) => Math.abs(r.index - m.index) < 40)) { agregar(m.index, ...valores(m)); }
        }
    });
    return res.sort((a, b) => a.index - b.index);
}

/**
 * Endoso de Quálitas: se imprime igual que la póliza ("PÓLIZA DE SEGURO DE AUTOMÓVILES") pero su ENDOSO no es 000000
 * y trae "Movimiento: A-ADICIONAL" (alta), de baja o de cambio. La primera página es el endoso (inciso 0000) y cada
 * página siguiente es la carátula de un inciso que toca (en un alta, el vehículo nuevo). null si no es un endoso de
 * Quálitas (la póliza misma trae ENDOSO 000000).
 * @param texto: texto del PDF.
 * @return mismo formato que endosoDeTexto, más el número de póliza (poliza) y los vehículos (formato de
 *         incisosDeCaratulas) de las carátulas de inciso.
 */
export function endosoQualitas(texto) {
    const t = String(texto || '');
    if (!/Qu[aá]litas/i.test(t)) { return null; }
    const mov = /Movimiento\s*:[ \t]*([A-Z])\s*-\s*([A-ZÁÉÍÓÚÑ][A-ZÁÉÍÓÚÑ ]*)/.exec(t);
    const cabeceras = encabezadosQualitas(t).filter((c) => !/^0+$/.test(c.endoso));
    if (!mov || !cabeceras.length) { return null; }
    const limpio = (v) => (v == null ? '' : String(v).replace(/\s+/g, ' ').trim());
    const dinero = (v) => (v == null || v === '' ? null : Number(String(v).replace(/[$,\s]/g, '')));
    const palabra = limpio(mov[2]).toUpperCase();
    const movimiento = /BAJA|CANCELA|DISMINU|EXCLU/.test(palabra) ? 'baja'
        : (/ADICIONAL|ALTA|INCLU/.test(palabra) ? 'alta' : ({ A: 'alta', B: 'baja', D: 'baja' }[mov[1]] || 'cambio'));
    const { poliza, endoso } = cabeceras[0];

    // Surte efecto en la fecha "Desde las 12:00 P.M. del 09/OCT/2026".
    let fecha = null;
    const desde = /\bDesde\b/i.exec(t);
    const fm = new RegExp('(\\d{2})\\/(' + Object.keys(MESES_CORTOS).join('|') + ')\\/(\\d{4})', 'i').exec(desde ? t.substring(desde.index) : t);
    if (fm) { fecha = `${fm[3]}-${MESES_CORTOS[fm[2].toUpperCase()]}-${fm[1]}`; }

    // Primas (las del endoso; cada inciso las repite): los montos desde "Prima Neta" en su orden, sin los de "$" (pagos
    // de la forma de pago). Según el lector salen junto a su etiqueta o todos después, así que se reconocen por la suma:
    // prima neta + (financiamiento) + gastos = subtotal y subtotal + IVA = importe total.
    const iNeta = t.search(/Prima\s+Neta/i);
    const montos = [];
    if (iNeta >= 0) {
        const re = /(\$\s*)?\b(\d{1,3}(?:,\d{3})*\.\d{2})\b/g;
        re.lastIndex = iNeta;
        let m;
        while (montos.length < 8 && (m = re.exec(t)) !== null) { if (!m[1]) { montos.push(dinero(m[2])); } }
    }
    const igual = (a, b) => Math.abs(a - b) < 0.05;
    let primaNeta = null;
    let derechos = null;
    let iva = null;
    let total = null;
    for (let k = 2; k + 2 < montos.length && k <= 4; k++) {
        const intermedios = montos.slice(1, k);
        if (igual(montos[0] + intermedios.reduce((a, b) => a + b, 0), montos[k]) && igual(montos[k] + montos[k + 1], montos[k + 2])) {
            [primaNeta, , iva, total] = [montos[0], montos[k], montos[k + 1], montos[k + 2]];
            // Con Tasa Financiamiento, el último intermedio son los gastos por expedición.
            derechos = intermedios[intermedios.length - 1];
            break;
        }
    }

    // Carátula de cada inciso: el vehículo junto a su "Serie:" (descripción, tipo, modelo, placas, uso, plan y suma).
    const incisosPag = cabeceras.filter((c) => !/^0+$/.test(c.inciso))
        .filter((c, i, l) => i === 0 || l[i - 1].inciso !== c.inciso).map((c) => String(Number(c.inciso)));
    const series = [];
    const reSerie = /Serie\s*:[ \t]*([A-HJ-NPR-Z0-9]{8,17})\b/g;
    let ms;
    while ((ms = reSerie.exec(t)) !== null) { if (!series.some((s) => s.serie === ms[1])) { series.push({ serie: ms[1], index: ms.index }); } }
    const vehiculos = series.map((s, k) => {
        const ini = k ? series[k - 1].index + 20 : 0;
        const fin = k + 1 < series.length ? series[k + 1].index : t.length;
        const v = t.substring(ini, fin);
        const uno = (re) => { const m = re.exec(v); return m ? limpio(m[1]) : ''; };
        // Descripción: "12701 MITSUBISHI L200 ..." (clave de 4 a 6 dígitos y el vehículo; sin etiquetas ni comas).
        const cerca = v.split('\n').map(limpio).filter((l) => /^\d{4,6} [A-Z][A-Z0-9 .\/-]{4,}$/.test(l) && !/[:,]/.test(l));
        const desc = cerca.length ? cerca[0] : '';
        // Suma de Daños Materiales; si no está junto a su etiqueta, la primera suma después de la serie.
        const dm = /Da[ñn]os\s+Materiales\s*\$\s*([\d,]{5,})/i.exec(v) || /\$\s*(\d{1,3}(?:,\d{3})+)(?!\.\d)/.exec(t.substring(s.index, fin));
        const modelo = uno(/Modelo\s*:\s*((?:19|20)\d{2})\b/i);
        return {
            inciso: incisosPag[k] || '',
            serie: s.serie,
            claveVehicular: desc ? desc.split(' ')[0] : '',
            descripcion: desc ? desc.substring(desc.indexOf(' ') + 1) : '',
            modelo,
            placas: uno(/Placas\s*:[ \t]*([A-Z0-9-]{4,10})\b/i),
            uso: uno(/Uso\s*:[ \t]*([A-ZÁÉÍÓÚÑ][A-ZÁÉÍÓÚÑ ]*?)(?=[ \t]+Servicio\s*:|[ \t\r]*(?:\n|$))/),
            tipoVehiculo: uno(/\bTipo\s*:[ \t]*([A-Za-zÁÉÍÓÚÑáéíóúñ-]+(?: [A-Za-zÁÉÍÓÚÑáéíóúñ-]+)?)\s+(?:Modelo|Serie)\b/i),
            paquete: uno(/PLAN\s*:[ \t]*([A-ZÁÉÍÓÚÑ]+)/),
            tipoValor: '',
            valor: dm ? dinero(dm[1]) : null
        };
    });
    // Un solo vehículo: la prima del endoso es la suya.
    if (vehiculos.length === 1) {
        vehiculos[0].primaNeta = primaNeta;
        vehiculos[0].prima = total;
    }
    const incisos = (vehiculos.length ? vehiculos.map((v) => v.inciso) : incisosPag).filter((i) => i)
        .map((i) => {
            const v = vehiculos.find((x) => x.inciso === i);
            return { inciso: i, descripcion: v ? limpio(`${v.descripcion} ${v.serie}`) : '', movimiento,
                prima: vehiculos.length === 1 ? primaNeta : null };
        });
    const tipo = limpio(`${mov[1]}-${palabra}`);
    const detalle = incisos.length
        ? `${tipo}: ${incisos.map((i) => `inciso ${i.inciso}${i.descripcion ? ' ' + i.descripcion : ''}`).join('; ')}`
        : tipo;
    return { numero: endoso.replace(/^0+(?=\d)/, ''), tipo, movimiento, general: !incisos.length, fecha, incisos,
        detalle: detalle.substring(0, 1000), primaNeta, derechos, iva, total, poliza, vehiculos };
}
