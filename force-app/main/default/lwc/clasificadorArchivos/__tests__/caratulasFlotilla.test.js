/**
 * Pólizas de flotilla con una carátula por inciso (Afirme, póliza 3201-033679-00): cada inciso ocupa varias
 * páginas con el mismo "Inciso: n" y al final vienen el recibo y el CFDI del inciso 1. Leídas por bloques con IA,
 * los incisos salían repetidos o con la serie del vecino / del recibo.
 */
import { vehiculosDeCaratulas, incisosDeCaratulas, unirIncisosIa } from 'c/clasificadorArchivos';

const ENCABEZADO = (n) => [
    `Número de Póliza: 3201-033679-00 Inciso: ${n}`,
    'CARÁTULA DE SEGURO DE',
    'Vigencia desde: las 12:00 h 16/12/2025',
    'AUTOMÓVILES RESIDENTES',
    'Hasta: las 12:00 h 16/12/2026',
    'Fecha de Emisión las 10:43 h 24/12/2025'
];
const ASEGURADO = [
    'DATOS DEL ASEGURADO',
    'Nombre: CASGUTSA',
    'CALLE ECA DO QUEIROS 5125 INT 1 JARDINES UNIVERSIDAD',
    'Domicilio: R.F.C.: CAS041109LG9',
    'ZAPOPAN JALISCO',
    'Contratante: CASGUTSA C.P.: 45110',
    'Conductor:'
];
const PIE = (neta, total) => [
    `Clave de Agente: 98424 Prima Neta: $${neta}`,
    'Nombre: AVANZA SEGUROS',
    'Financiamiento: $0.00',
    'SEGUROS Y DE FIANZAS, SA Gastos de Expedición: $550.00',
    'Forma de Pago: ANUAL I.V.A.: $1,080.54',
    `Moneda: NACIONAL Prima Total: $${total}`
];
const CARATULA_1 = [
    ...ENCABEZADO(1), ...ASEGURADO,
    'DATOS DEL VEHÍCULO',
    'Marca: CHEVROLET, Modelo: 2008 Tipo:',
    'SILVERADO 1500 CABINA REGULAR, V6, 4.3L, 200 CP, 2',
    'Version: Número de Serie: 3GCEC14X38M114075',
    'PUERTAS, STD, PAQ H',
    'Placas: SN Pasajeros: 2 Número de Motor: SN',
    'Uso: CAMIÓN USO NORMAL CARGA Clave: 300249 Tipo de Carga: NO PELIGROSA',
    'DAÑOS MATERIALES VALOR COMERCIAL 3 % $1520.41',
    'ROBO TOTAL VALOR COMERCIAL 5 % $1493.49',
    'RESPONSABILIDAD CIVIL $2,000,000.00 0 UMA $2094.38',
    ...PIE('6,203.35', '7,833.89')
].join('\n');
// Las otras páginas del inciso 1: mismo encabezado, sin datos del vehículo.
const LEGAL_1 = [...ENCABEZADO(1), 'SEGUROS AFIRME S.A. DE C.V., AFIRME GRUPO FINANCIERO (en lo sucesivo la "Institución")'].join('\n');
const OBSERVACIONES_1 = [...ENCABEZADO(1), 'OBSERVACIONES', 'TIPO DE CARGA DAÑOS OCASIONADOS POR LA CARGA: NO PELIGROSA'].join('\n');
// Inciso 77: el VIN viene partido en dos renglones ("LZWNNNGNXRC81530" + "5").
const CARATULA_77 = [
    ...ENCABEZADO(77), ...ASEGURADO,
    'DATOS DEL VEHÍCULO',
    'Marca: CHEVROLET, Modelo: 2024 Tipo:',
    'LZWNNNGNXRC81530',
    'Version: TORNADO VAN LS, L4, 1.5L, 103 CP, 5 PUERTAS, STD Número de Serie:',
    '5',
    'Placas: SN Pasajeros: 2 Número de Motor: SN',
    'Uso: CAMIÓN USO NORMAL CARGA Clave: 200048 Tipo de Carga: NO PELIGROSA',
    ...PIE('9,110.76', '11,206.48')
].join('\n');
// Recibo y CFDI del final: "Inciso: 1" otra vez, con folio y descripción del inciso.
const RECIBO = [
    'RECIBO DE PRIMAS',
    'Siniestro: 800 723 4763 Póliza Número: 001-3201033679-00 Inciso: 1',
    'Inciso: 1 Ramo: AF AUTOMOVILES FLOTILLA Linea: AF CAMIONES FLOTILLA'
].join('\n');
const CFDI = [
    'Afirme Grupo Financiero Serie Folio SAA-01978913',
    'No. endoso : Inciso : 1',
    'PRIMA NETA $ 6,203.35',
    'DESCRIPCION DEL INCISO:',
    'SILVERADO 1500 CABINA REGULAR, V6, 4.3L, 200 CP, 2PUERTAS, STD, PAQ H FIANZAS, SA DE CV'
].join('\n');
const POLIZA = [CARATULA_1, LEGAL_1, OBSERVACIONES_1, CARATULA_77, RECIBO, CFDI].join('\n');

describe('vehiculosDeCaratulas', () => {
    it('lee un vehículo por carátula, una sola vez, aunque el inciso se repita en otras páginas', () => {
        const v = vehiculosDeCaratulas(POLIZA);
        expect(v.map((x) => x.inciso)).toEqual(['1', '77']);
        expect(v.map((x) => x.serie)).toEqual(['3GCEC14X38M114075', 'LZWNNNGNXRC815305']);
        expect(v[0].marca).toBe('CHEVROLET');
        expect(v[0].anio).toBe('2008');
        expect(v[0].primaTotal).toBe('7833.89');
        expect(v[1].descripcion).toBe('TORNADO VAN LS, L4, 1.5L, 103 CP, 5 PUERTAS, STD');
    });

    it('con un solo vehículo es una póliza individual', () => {
        expect(vehiculosDeCaratulas(CARATULA_1)).toEqual([]);
        expect(vehiculosDeCaratulas('Inciso Serie Descripción\n1 3GCEC14X38M114075 SILVERADO')).toEqual([]);
    });
});

describe('incisosDeCaratulas', () => {
    it('entrega los incisos con las llaves del censo / cotización de flotilla', () => {
        const [i1, i77] = incisosDeCaratulas(POLIZA);
        expect(i1).toEqual(expect.objectContaining({
            inciso: '1', serie: '3GCEC14X38M114075', marca: 'CHEVROLET', modelo: '2008', placas: '',
            claveVehicular: '300249', uso: 'CAMIÓN USO NORMAL CARGA', tipoVehiculo: 'CAMIÓN', tipoValor: 'VALOR COMERCIAL',
            dedDM: '3', dedRT: '5', rc: '2000000.00', primaNeta: '6203.35', derechos: '550.00', prima: '7833.89'
        }));
        expect(i77.serie).toBe('LZWNNNGNXRC815305');
        expect(i77.prima).toBe('11206.48');
    });
});

describe('unirIncisosIa', () => {
    it('une el inciso partido entre dos bloques (sin serie en el segundo)', () => {
        const r = unirIncisosIa([
            { inciso: 2, serie: '3TMJU4GN4AM093766', modelo: 2010, prima: null },
            { inciso: 2, serie: null, modelo: null, prima: 9017.5 }
        ]);
        expect(r).toEqual([{ inciso: 2, serie: '3TMJU4GN4AM093766', modelo: 2010, prima: 9017.5 }]);
    });

    it('descarta el inciso repetido con el folio del recibo como serie', () => {
        const r = unirIncisosIa([
            { inciso: 1, serie: '3GCEC14X38M114075', descripcion: 'SILVERADO 1500' },
            { inciso: '1', serie: 'SAA-01978913', descripcion: 'SILVERADO 1500 CABINA REGULAR', prima: 7833.89 }
        ]);
        expect(r).toHaveLength(1);
        expect(r[0]).toEqual({ inciso: 1, serie: '3GCEC14X38M114075', descripcion: 'SILVERADO 1500', prima: 7833.89 });
    });

    it('cambia el VIN mal leído por el VIN completo del mismo inciso', () => {
        const r = unirIncisosIa([
            { inciso: 77, serie: 'LZWNNNGNXRC81530', modelo: 2024 },
            { inciso: 77, serie: 'LZWNNNGNXRC815305', descripcion: 'TORNADO VAN' }
        ]);
        expect(r).toEqual([{ inciso: 77, serie: 'LZWNNNGNXRC815305', modelo: 2024, descripcion: 'TORNADO VAN' }]);
    });

    it('une la misma serie aunque cambie el número de inciso o los espacios', () => {
        const r = unirIncisosIa([
            { inciso: 5, serie: 'MR0EX32G1D0004689' },
            { inciso: null, serie: 'mr0ex32g1d0004689 ', placas: 'JAL123' }
        ]);
        expect(r).toEqual([{ inciso: 5, serie: 'MR0EX32G1D0004689', placas: 'JAL123' }]);
    });

    it('no junta vehículos distintos: dos VIN válidos con el mismo número o paquetes distintos del inciso', () => {
        expect(unirIncisosIa([
            { inciso: 3, serie: '3GCNC9CX8DG244071' },
            { inciso: 3, serie: 'MR0EX8CB7G1393949' }
        ])).toHaveLength(2);
        expect(unirIncisosIa([
            { inciso: 4, serie: null, paquete: 'Amplia', prima: 10000 },
            { inciso: 4, serie: null, paquete: 'Limitada', prima: 7000 }
        ])).toHaveLength(2);
    });

    it('tolera listas vacías y renglones nulos', () => {
        expect(unirIncisosIa(null)).toEqual([]);
        expect(unirIncisosIa([null, { descripcion: 'NISSAN NP300' }])).toEqual([{ descripcion: 'NISSAN NP300' }]);
    });
});
