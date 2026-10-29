/**
 * @creation date: 12/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Cotizaciones de FLOTILLA (Auto colectivo). Cada cotización de aseguradora (Excel o PDF, leída
 *               en el LWC flotillaColectiva) se guarda como un Quote de la oportunidad con un Inciso_Flotilla__c
 *               por vehículo (prima, valor, deducibles, RC...). Cada vehículo con serie se liga a un
 *               CustomerProperty de la empresa (el mismo objeto que usa Auto individual), sin duplicar por VIN.
 */
public with sharing class FlotillaController {

	// Prompt Template (Prompt Builder) que lee cotizaciones de flotilla en PDF y su variable de entrada.
	private static final String PROMPT_TEMPLATE_API_NAME = 'Extractor_Flotilla_Auto';
	private static final String PROMPT_INPUT_PARAM = 'Input:TextoCotizacion';
	@TestVisible private static final Integer MAX_INCISOS = 3000;

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Inciso que envía el LWC (ya normalizado en el navegador).
	 */
	public class IncisoEntrada {
		public Integer inciso;
		public String serie;
		public String claveVehicular;
		public String descripcion;
		public Integer modelo;
		public String placas;
		public String uso;
		public String tipoVehiculo;
		public String paquete;
		public String tipoValor;
		public Decimal valor;
		public Decimal dedDM;
		public Decimal dedRT;
		public Decimal rc;
		public Decimal gm;
		public Decimal muerte;
		public Decimal prima;
		public Decimal primaNeta;
		public Integer fila;
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Datos de la cotización de la aseguradora (encabezado + incisos).
	 */
	public class CotizacionEntrada {
		public Id aseguradoraId;
		public String vigenciaDesde;
		public String vigenciaHasta;
		public String formaPago;
		public String archivo;
		public Decimal primaNeta;
		public Decimal derechos;
		public Decimal recargo;
		public Decimal iva;
		public Decimal primaTotal;
		public List<IncisoEntrada> incisos;
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Aseguradoras disponibles para elegir a quién pertenece la cotización.
	 * @return lista de {id, nombre} ordenada por nombre.
	 */
	@AuraEnabled(cacheable=true)
	public static List<Map<String, Object>> getAseguradoras() {
		List<Map<String, Object>> res = new List<Map<String, Object>>();
		for (Aseguradora__c a : [SELECT Id, Name FROM Aseguradora__c ORDER BY Name LIMIT 500]) {
			res.add(new Map<String, Object>{ 'id' => a.Id, 'nombre' => a.Name });
		}
		return res;
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cotizaciones de flotilla de la oportunidad con sus incisos, para el resumen y el comparativo.
	 * @param opportunityId: oportunidad colectiva de Auto.
	 * @return lista de cotizaciones {id, nombre, numero, aseguradora, primaTotal, vigencia..., incisos[]}.
	 */
	@AuraEnabled(cacheable=false)
	public static List<Map<String, Object>> getFlotilla(Id opportunityId) {
		Map<Id, Map<String, Object>> porQuote = new Map<Id, Map<String, Object>>();
		for (Inciso_Flotilla__c i : [
			SELECT Id, Cotizacion__c, Cotizacion__r.Name, Cotizacion__r.QuoteNumber, Cotizacion__r.Prima_Total__c,
				Cotizacion__r.Aseguradora__r.Name, Cotizacion__r.Vigencia_Inicio__c, Cotizacion__r.ExpirationDate,
				Cotizacion__r.Forma_de_pago__c, Cotizacion__r.CreatedDate, Cotizacion__r.Prima_Neta__c,
				Cotizacion__r.Derechos_Poliza__c, Cotizacion__r.Recargo_Fraccionado__c, Cotizacion__r.IVA__c,
				Numero_Inciso__c, Serie__c, Clave_Vehicular__c, Descripcion__c, Modelo__c, Placas__c, Uso__c,
				Tipo_Vehiculo__c, Paquete__c, Tipo_Valor__c, Valor__c, Deducible_DM__c, Deducible_RT__c,
				Responsabilidad_Civil__c, Gastos_Medicos__c, Muerte_Conductor__c, Prima__c, Prima_Neta__c
			FROM Inciso_Flotilla__c
			WHERE Oportunidad__c = :opportunityId AND Cotizacion__c != null
			ORDER BY Cotizacion__r.CreatedDate ASC, Numero_Inciso__c ASC NULLS LAST, Name ASC
			LIMIT 10000
		]) {
			Map<String, Object> q = porQuote.get(i.Cotizacion__c);
			if (q == null) {
				q = new Map<String, Object>{
					'id' => i.Cotizacion__c,
					'nombre' => i.Cotizacion__r.Name,
					'numero' => i.Cotizacion__r.QuoteNumber,
					'aseguradora' => i.Cotizacion__r.Aseguradora__r != null ? i.Cotizacion__r.Aseguradora__r.Name : i.Cotizacion__r.Name,
					'primaTotal' => i.Cotizacion__r.Prima_Total__c,
					'vigenciaDesde' => i.Cotizacion__r.Vigencia_Inicio__c,
					'vigenciaHasta' => i.Cotizacion__r.ExpirationDate,
					'formaPago' => i.Cotizacion__r.Forma_de_pago__c,
					'primaNeta' => i.Cotizacion__r.Prima_Neta__c,
					'derechos' => i.Cotizacion__r.Derechos_Poliza__c,
					'recargo' => i.Cotizacion__r.Recargo_Fraccionado__c,
					'iva' => i.Cotizacion__r.IVA__c,
					'incisos' => new List<Object>()
				};
				porQuote.put(i.Cotizacion__c, q);
			}
			((List<Object>) q.get('incisos')).add(new Map<String, Object>{
				'id' => i.Id, 'inciso' => i.Numero_Inciso__c, 'serie' => i.Serie__c, 'claveVehicular' => i.Clave_Vehicular__c,
				'descripcion' => i.Descripcion__c, 'modelo' => i.Modelo__c, 'placas' => i.Placas__c, 'uso' => i.Uso__c,
				'tipoVehiculo' => i.Tipo_Vehiculo__c, 'paquete' => i.Paquete__c, 'tipoValor' => i.Tipo_Valor__c,
				'valor' => i.Valor__c, 'dedDM' => i.Deducible_DM__c, 'dedRT' => i.Deducible_RT__c,
				'rc' => i.Responsabilidad_Civil__c, 'gm' => i.Gastos_Medicos__c, 'muerte' => i.Muerte_Conductor__c,
				'prima' => i.Prima__c, 'primaNeta' => i.Prima_Neta__c
			});
		}
		// Producto y coberturas de cada cotización (Quote_Coverage__c) para comparar las coberturas reales.
		if (!porQuote.isEmpty()) {
			for (Quote qt : [SELECT Id, Product__r.Name FROM Quote WHERE Id IN :porQuote.keySet()]) {
				porQuote.get(qt.Id).put('producto', qt.Product__r != null ? qt.Product__r.Name : null);
				porQuote.get(qt.Id).put('coberturas', new List<Object>());
			}
			for (Quote_Coverage__c c : [
				SELECT Quote__c, Name, Coverage_Name__c, Sum_Insured__c, Deductible__c, Limit__c, Coinsurance__c
				FROM Quote_Coverage__c
				WHERE Quote__c IN :porQuote.keySet()
				ORDER BY Quote__c, Order__c ASC NULLS LAST, Name ASC
				LIMIT 5000
			]) {
				((List<Object>) porQuote.get(c.Quote__c).get('coberturas')).add(new Map<String, Object>{
					'nombre' => String.isNotBlank(c.Coverage_Name__c) ? c.Coverage_Name__c : c.Name,
					'suma' => c.Sum_Insured__c, 'deducible' => c.Deductible__c, 'limite' => c.Limit__c, 'coaseguro' => c.Coinsurance__c
				});
			}
		}
		for (Map<String, Object> q : porQuote.values()) { asignarPrimaComparable(q); }
		return porQuote.values();
	}

	/**
	 * @creation date: 15/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Coberturas de las cotizaciones de flotilla de la oportunidad, lado a lado (para el comparativo en
	 *               pantalla; el PDF y "Análisis IA" usan la misma lógica).
	 * @param opportunityId: oportunidad colectiva de Auto.
	 * @return renglones {key, etiqueta, valores: {quoteId: texto}, distinto}.
	 */
	@AuraEnabled(cacheable=false)
	public static List<Map<String, Object>> getCoberturasFlotilla(Id opportunityId) {
		return coberturasComparadas(getFlotilla(opportunityId));
	}

	/**
	 * @creation date: 15/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma las coberturas lado a lado con lo que trae cada cotización, sin renglones fijos:
	 *               1) paquete y tipo de valor si los incisos los traen; 2) las coberturas de cada cotización
	 *               (Quote_Coverage__c), agrupando nombres equivalentes entre aseguradoras y omitiendo la que solo
	 *               repite el nombre del producto; el valor es la suma / límite / deducible de la cobertura o, si no lo
	 *               trae, el dato de los incisos (deducible de daños materiales y robo, RC, gastos médicos, muerte del
	 *               conductor); si no hay valor, "Amparada"; si la aseguradora no la tiene, "No incluida";
	 *               3) datos de los incisos que no tienen cobertura registrada. Primero las que tienen todas.
	 * @param cot: cotizaciones de getFlotilla.
	 * @return renglones {key, etiqueta, valores: {quoteId: texto}, distinto}.
	 */
	public static List<Map<String, Object>> coberturasComparadas(List<Map<String, Object>> cot) {
		List<String> llaves = new List<String>();
		Map<String, String> etiquetas = new Map<String, String>();
		Map<String, Map<String, String>> valores = new Map<String, Map<String, String>>();
		// 1) Paquete y tipo de valor (texto de los incisos).
		for (String campo : new List<String>{ 'paquete', 'tipoValor' }) {
			Map<String, String> v = new Map<String, String>();
			for (Map<String, Object> q : cot) {
				String t = textosInciso(q, campo);
				if (String.isNotBlank(t)) { v.put(String.valueOf(q.get('id')), t); }
			}
			if (!v.isEmpty()) {
				llaves.add('#' + campo);
				etiquetas.put('#' + campo, campo == 'paquete' ? 'Paquete' : 'Tipo de valor');
				valores.put('#' + campo, v);
			}
		}
		// 2) Coberturas de cada cotización.
		for (Map<String, Object> q : cot) {
			String qid = String.valueOf(q.get('id'));
			String producto = normalizarCobertura((String) q.get('producto'));
			List<Object> cobs = (List<Object>) q.get('coberturas');
			for (Object o : cobs == null ? new List<Object>() : cobs) {
				Map<String, Object> c = (Map<String, Object>) o;
				String nombre = String.valueOf(c.get('nombre') == null ? '' : c.get('nombre')).replace('*', ' ').normalizeSpace();
				String k = normalizarCobertura(nombre);
				// Sin nombre, o es el mismo producto / paquete (ej. "Auto Amplio MAPFRE" en "Seguro de Auto Amplio MAPFRE").
				if (String.isBlank(k) || (String.isNotBlank(producto) && producto.contains(k))) { continue; }
				if (!valores.containsKey(k)) {
					llaves.add(k);
					etiquetas.put(k, nombre);
					valores.put(k, new Map<String, String>());
				}
				String v = valorCobertura(c);
				if (String.isBlank(v)) { v = valorInciso(q, conceptoInciso(k)); }
				valores.get(k).put(qid, String.isBlank(v) ? 'Amparada' : v);
			}
		}
		// 3) Datos de los incisos que ninguna cobertura registrada recoge.
		for (String concepto : ETIQUETAS_INCISO.keySet()) {
			String k;
			for (String l : llaves) { if (conceptoInciso(l) == concepto) { k = l; break; } }
			for (Map<String, Object> q : cot) {
				String v = valorInciso(q, concepto);
				if (String.isBlank(v)) { continue; }
				if (k == null) {
					k = '#' + concepto;
					llaves.add(k);
					etiquetas.put(k, ETIQUETAS_INCISO.get(concepto));
					valores.put(k, new Map<String, String>());
				}
				String qid = String.valueOf(q.get('id'));
				if (!valores.get(k).containsKey(qid)) { valores.get(k).put(qid, v); }
			}
		}
		// Renglones: paquete / tipo de valor, luego las coberturas que tienen todas y al final las parciales.
		List<Map<String, Object>> completas = new List<Map<String, Object>>();
		List<Map<String, Object>> parciales = new List<Map<String, Object>>();
		for (String k : llaves) {
			Map<String, String> v = valores.get(k);
			Map<String, String> celdas = new Map<String, String>();
			Set<String> distintos = new Set<String>();
			for (Map<String, Object> q : cot) {
				String qid = String.valueOf(q.get('id'));
				String t = v.containsKey(qid) ? v.get(qid) : 'No incluida';
				celdas.put(qid, t);
				distintos.add(t.toUpperCase().deleteWhitespace().replace('.', ''));
			}
			Map<String, Object> r = new Map<String, Object>{
				'key' => k, 'etiqueta' => etiquetas.get(k), 'valores' => celdas, 'distinto' => cot.size() > 1 && distintos.size() > 1
			};
			if (k.startsWith('#paquete') || k.startsWith('#tipoValor') || v.size() == cot.size()) { completas.add(r); } else { parciales.add(r); }
		}
		completas.addAll(parciales);
		return completas;
	}

	// Datos de los incisos que equivalen a una cobertura (campo del inciso -> nombre si ninguna cobertura lo recoge).
	private static final Map<String, String> ETIQUETAS_INCISO = new Map<String, String>{
		'dedDM' => 'Daños materiales', 'dedRT' => 'Robo total', 'rc' => 'Responsabilidad civil',
		'gm' => 'Gastos médicos ocupantes', 'muerte' => 'Muerte del conductor'
	};
	// Palabras que no ayudan a reconocer la misma cobertura entre aseguradoras.
	private static final Set<String> PALABRAS_VACIAS = new Set<String>{
		'a', 'al', 'de', 'del', 'en', 'por', 'la', 'el', 'los', 'las', 'y', 'para', 'con', 'cds'
	};

	/**
	 * @creation date: 15/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Nombre de cobertura normalizado (minúsculas, sin acentos, signos ni palabras vacías) para reconocer
	 *               la misma cobertura con nombres distintos (ej. "Gastos Médicos a Ocupantes" = "Gastos Médicos Ocupantes").
	 * @param nombre: nombre de la cobertura o del producto.
	 * @return llave normalizada ('' si viene vacío).
	 */
	@TestVisible
	private static String normalizarCobertura(String nombre) {
		if (String.isBlank(nombre)) { return ''; }
		String t = nombre.toLowerCase();
		Map<String, String> acentos = new Map<String, String>{ 'á' => 'a', 'é' => 'e', 'í' => 'i', 'ó' => 'o', 'ú' => 'u', 'ü' => 'u', 'ñ' => 'n' };
		for (String a : acentos.keySet()) { t = t.replace(a, acentos.get(a)); }
		List<String> palabras = new List<String>();
		for (String p : t.replaceAll('[^a-z0-9]+', ' ').trim().split(' ')) {
			if (String.isNotBlank(p) && !PALABRAS_VACIAS.contains(p)) { palabras.add(p); }
		}
		return String.join(palabras, ' ');
	}

	/**
	 * @creation date: 15/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Dato del inciso que corresponde a la cobertura (por su nombre normalizado).
	 * @param k: nombre normalizado de la cobertura.
	 * @return campo del inciso (dedDM, dedRT, rc, gm, muerte) o null.
	 */
	@TestVisible
	private static String conceptoInciso(String k) {
		if (String.isBlank(k)) { return null; }
		String t = k.removeStart('#');
		if (ETIQUETAS_INCISO.containsKey(t)) { return t; }
		if (t.contains('danos materiales')) { return 'dedDM'; }
		if (t.contains('robo total')) { return 'dedRT'; }
		if (t.contains('gastos medicos')) { return 'gm'; }
		if (t.contains('conductor') || t.contains('muerte')) { return 'muerte'; }
		if (t.startsWith('responsabilidad civil') && (t.contains('terceros') || t == 'responsabilidad civil')) { return 'rc'; }
		return null;
	}

	/**
	 * @creation date: 15/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Suma asegurada, límite, deducible y coaseguro de la cobertura de la cotización.
	 * @param c: cobertura {suma, limite, deducible, coaseguro}.
	 * @return texto ('' si no trae ninguno).
	 */
	private static String valorCobertura(Map<String, Object> c) {
		List<String> partes = new List<String>();
		if (c.get('suma') != null && (Decimal) c.get('suma') > 0) { partes.add(montoTxt((Decimal) c.get('suma'))); }
		if (c.get('limite') != null && (Decimal) c.get('limite') > 0) { partes.add('Límite ' + montoTxt((Decimal) c.get('limite'))); }
		if (c.get('deducible') != null && (Decimal) c.get('deducible') > 0) { partes.add('Ded. ' + pctTxt((Decimal) c.get('deducible'))); }
		if (c.get('coaseguro') != null && (Decimal) c.get('coaseguro') > 0) { partes.add('Coas. ' + pctTxt((Decimal) c.get('coaseguro'))); }
		return String.join(partes, ' · ');
	}

	/**
	 * @creation date: 15/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Dato de los incisos para una cobertura: deducible (porcentaje) o suma asegurada; si cambia según la
	 *               unidad se da el rango.
	 * @param q: cotización con incisos.
	 * @param campo: dedDM, dedRT, rc, gm o muerte (null = sin dato).
	 * @return texto ('' si ningún inciso lo trae).
	 */
	private static String valorInciso(Map<String, Object> q, String campo) {
		if (campo == null) { return ''; }
		Boolean esPct = campo == 'dedDM' || campo == 'dedRT';
		Decimal min;
		Decimal max;
		for (Object o : (List<Object>) q.get('incisos')) {
			Object v = ((Map<String, Object>) o).get(campo);
			if (v == null) { continue; }
			Decimal d = v instanceof Decimal ? (Decimal) v : null;
			if (d == null || d == 0) { continue; }
			min = min == null || d < min ? d : min;
			max = max == null || d > max ? d : max;
		}
		if (min == null) { return ''; }
		String a = esPct ? pctTxt(min) : montoTxt(min);
		String b = esPct ? pctTxt(max) : montoTxt(max);
		return (esPct ? 'Ded. ' : '') + (min == max ? a : a + ' – ' + b);
	}

	/**
	 * @creation date: 15/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Textos distintos de un campo de los incisos (paquete, tipo de valor), en mayúsculas.
	 * @param q: cotización con incisos.
	 * @param campo: campo del inciso.
	 * @return textos unidos con " / " ('' si ninguno).
	 */
	private static String textosInciso(Map<String, Object> q, String campo) {
		Set<String> textos = new Set<String>();
		for (Object o : (List<Object>) q.get('incisos')) {
			Object v = ((Map<String, Object>) o).get(campo);
			if (v != null && String.isNotBlank(String.valueOf(v))) { textos.add(String.valueOf(v).trim().toUpperCase()); }
		}
		return String.join(new List<String>(textos), ' / ');
	}

	/**
	 * @creation date: 15/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Monto "$1,234,567" sin decimales.
	 * @param d: monto.
	 * @return texto.
	 */
	private static String montoTxt(Decimal d) {
		Long n = d.setScale(0, System.RoundingMode.HALF_UP).longValue();
		String s = String.valueOf(Math.abs(n));
		String out = '';
		while (s.length() > 3) {
			out = ',' + s.right(3) + out;
			s = s.left(s.length() - 3);
		}
		return (n < 0 ? '-$' : '$') + s + out;
	}

	/**
	 * @creation date: 15/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Porcentaje con hasta dos decimales ("5%", "2.5%").
	 * @param d: porcentaje.
	 * @return texto.
	 */
	private static String pctTxt(Decimal d) {
		Decimal r = d.setScale(2, System.RoundingMode.HALF_UP).stripTrailingZeros();
		return r.toPlainString() + '%';
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Prima comparable de cada inciso: su prima total, o la neta cuando la aseguradora solo da la
	 *               total de la póliza; en ese caso se reparte la diferencia (derechos, recargo e IVA) en proporción a
	 *               la prima de cada inciso, para que la suma coincida con la prima total y se compare igual entre
	 *               aseguradoras. Marca 'prorrateo' = true en la cotización cuando se repartió.
	 * @param q: cotización con sus incisos (de getFlotilla).
	 */
	@TestVisible
	private static void asignarPrimaComparable(Map<String, Object> q) {
		List<Object> incisos = (List<Object>) q.get('incisos');
		Boolean todosConTotal = true;
		for (Object o : incisos) { if (((Map<String, Object>) o).get('prima') == null) { todosConTotal = false; } }
		Decimal suma = 0;
		for (Object o : incisos) { suma += base((Map<String, Object>) o, todosConTotal); }
		Decimal total = (Decimal) q.get('primaTotal');
		Decimal factor = (total != null && total > 0 && suma > 0) ? total / suma : 1;
		for (Object o : incisos) {
			Map<String, Object> i = (Map<String, Object>) o;
			i.put('primaComparable', (base(i, todosConTotal) * factor).setScale(2, System.RoundingMode.HALF_UP));
		}
		q.put('prorrateo', Math.abs(factor - 1) > 0.005);
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Prima base del inciso para el reparto: la total si todos los incisos la traen; si no, la neta.
	 * @param i: inciso.
	 * @param usarTotal: true si todos los incisos de la cotización traen prima total.
	 * @return prima base (0 si no hay).
	 */
	private static Decimal base(Map<String, Object> i, Boolean usarTotal) {
		Decimal v = (Decimal) (usarTotal ? i.get('prima') : (i.get('primaNeta') != null ? i.get('primaNeta') : i.get('prima')));
		return v == null ? 0 : v;
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Guarda la cotización de flotilla de una aseguradora: crea el Quote (prima total = suma de
	 *               incisos), los vehículos (CustomerProperty de la empresa, reutilizando por VIN) y un
	 *               Inciso_Flotilla__c por vehículo. Todo o nada.
	 * @param opportunityId: oportunidad colectiva de Auto (debe tener cliente/empresa).
	 * @param datosJson: JSON de CotizacionEntrada.
	 * @return Id del Quote creado.
	 */
	@AuraEnabled(cacheable=false)
	public static Id guardarCotizacionFlotilla(Id opportunityId, String datosJson) {
		CotizacionEntrada datos;
		try {
			datos = (CotizacionEntrada) JSON.deserialize(String.isBlank(datosJson) ? '{}' : datosJson, CotizacionEntrada.class);
		} catch (Exception e) {
			throw error('La cotización no tiene un formato válido: ' + e.getMessage());
		}
		if (datos.aseguradoraId == null) { throw error('Selecciona la aseguradora de la cotización.'); }
		if (datos.incisos == null || datos.incisos.isEmpty()) { throw error('La cotización no tiene incisos para guardar.'); }
		if (datos.incisos.size() > MAX_INCISOS) {
			throw error('La cotización tiene ' + datos.incisos.size() + ' incisos; el máximo por carga es ' + MAX_INCISOS + '.');
		}
		List<Opportunity> opps = [SELECT Id, Name, AccountId, Pricebook2Id, Ramo__c, Prima_neta__c FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
		if (opps.isEmpty()) { throw error('No se encontró la oportunidad.'); }
		Opportunity opp = opps[0];
		if (opp.AccountId == null) {
			throw error('La oportunidad no tiene cliente. En una flotilla el cliente es la empresa contratante: asígnalo y guarda la oportunidad.');
		}
		List<Aseguradora__c> asegs = [SELECT Id, Name FROM Aseguradora__c WHERE Id = :datos.aseguradoraId LIMIT 1];
		if (asegs.isEmpty()) { throw error('No se encontró la aseguradora seleccionada.'); }

		Savepoint sp = Database.setSavepoint();
		try {
			// Prima total: la del archivo; si no viene, la suma de los incisos (si todos traen total) o neta + derechos + recargo + IVA.
			Decimal sumaTotal = 0;
			Decimal sumaNeta = 0;
			Boolean todosConTotal = true;
			for (IncisoEntrada i : datos.incisos) {
				if (i.prima != null) { sumaTotal += i.prima; } else { todosConTotal = false; }
				if (i.primaNeta != null) { sumaNeta += i.primaNeta; }
			}
			Decimal neta = datos.primaNeta != null ? datos.primaNeta : (sumaNeta > 0 ? sumaNeta : null);
			Decimal total = datos.primaTotal;
			if (total == null && todosConTotal) { total = sumaTotal; }
			if (total == null && neta != null) {
				total = neta + nz(datos.derechos) + nz(datos.recargo) + nz(datos.iva);
			}
			if (total == null) { total = sumaTotal; }

			Quote q = new Quote(OpportunityId = opp.Id, Status = 'In Review');
			q.Name = ('Flotilla - ' + asegs[0].Name + ' (' + datos.incisos.size() + ' unidades)').left(255);
			q.Pricebook2Id = opp.Pricebook2Id != null ? opp.Pricebook2Id : pricebookEstandar();
			q.put('Aseguradora__c', asegs[0].Id);
			Id producto = productoAuto(asegs[0].Id, opp.Ramo__c);
			if (producto != null) { q.put('Product__c', producto); }
			if (String.isNotBlank(opp.Ramo__c)) { q.put('Ramos__c', opp.Ramo__c); }
			q.put('RatingDate', Date.today());
			Date desde = fecha(datos.vigenciaDesde);
			Date hasta = fecha(datos.vigenciaHasta);
			if (desde != null) { q.put('Vigencia_Inicio__c', desde); }
			q.ExpirationDate = hasta != null ? hasta : (desde != null ? desde : Date.today()).addYears(1);
			if (String.isNotBlank(datos.formaPago)) { q.put('Forma_de_pago__c', datos.formaPago.left(40)); }
			// Frecuencia de prima es obligatoria en el Quote: sin forma de pago se toma Anual.
			q.put('Frecuencia_de_prima__c', valorPicklist(Quote.Frecuencia_de_prima__c, frecuencia(datos.formaPago), 'Anual'));
			q.put('PrimaAnual__c', total);
			q.put('Prima_Total__c', total);
			if (neta != null) { q.put('Prima_Neta__c', neta); }
			if (datos.derechos != null) { q.put('Derechos_Poliza__c', datos.derechos); }
			if (datos.recargo != null) { q.put('Recargo_Fraccionado__c', datos.recargo); }
			if (datos.iva != null) { q.put('IVA__c', datos.iva); }
			if (String.isNotBlank(datos.archivo)) { q.Description = ('Cotización de flotilla cargada de: ' + datos.archivo).left(32000); }
			insert q;
			// La flotilla creada desde los archivos se guarda sin prima: toma la de la primera cotización.
			if (neta != null && (opp.Prima_neta__c == null || opp.Prima_neta__c <= 0)) {
				update new Opportunity(Id = opp.Id, Prima_neta__c = neta);
			}

			Map<String, Id> vehiculos = vehiculosDe(opp.AccountId, datos.incisos);
			List<Inciso_Flotilla__c> incisos = new List<Inciso_Flotilla__c>();
			List<Integer> filas = new List<Integer>();
			for (IncisoEntrada e : datos.incisos) {
				if (String.isBlank(e.serie) && String.isBlank(e.descripcion)) {
					throw error('Fila ' + e.fila + ': el inciso no tiene serie ni descripción.');
				}
				Inciso_Flotilla__c i = new Inciso_Flotilla__c(Cotizacion__c = q.Id, Oportunidad__c = opp.Id);
				i.Vehiculo__c = String.isBlank(e.serie) ? null : vehiculos.get(vin(e.serie));
				i.Numero_Inciso__c = e.inciso;
				setTexto(i, 'Serie__c', e.serie == null ? null : vin(e.serie));
				setTexto(i, 'Clave_Vehicular__c', e.claveVehicular);
				setTexto(i, 'Descripcion__c', e.descripcion);
				if (e.modelo != null && e.modelo > 1900 && e.modelo < 2100) { i.Modelo__c = e.modelo; }
				setTexto(i, 'Placas__c', e.placas == null ? null : e.placas.deleteWhitespace().toUpperCase());
				setTexto(i, 'Uso__c', e.uso);
				setTexto(i, 'Tipo_Vehiculo__c', e.tipoVehiculo);
				setTexto(i, 'Paquete__c', e.paquete);
				setTexto(i, 'Tipo_Valor__c', e.tipoValor);
				i.Valor__c = e.valor;
				i.Deducible_DM__c = porcentaje(e.dedDM);
				i.Deducible_RT__c = porcentaje(e.dedRT);
				i.Responsabilidad_Civil__c = e.rc;
				i.Gastos_Medicos__c = e.gm;
				i.Muerte_Conductor__c = e.muerte;
				i.Prima__c = e.prima;
				i.Prima_Neta__c = e.primaNeta;
				incisos.add(i);
				filas.add(e.fila);
			}
			try {
				insert incisos;
			} catch (DmlException de) {
				Integer idx = de.getDmlIndex(0);
				throw error((idx != null && idx < filas.size() ? 'Fila ' + filas[idx] + ': ' : '') + de.getDmlMessage(0));
			}
			// El mismo comparativo del PDF queda en la oportunidad para "Análisis IA".
			ColectivoController.guardarComparativoEnOportunidad(opportunityId, FlotillaComparativoPdfController.construirHtml(opportunityId));
			return q.Id;
		} catch (AuraHandledException ahe) {
			Database.rollback(sp);
			throw ahe;
		} catch (Exception e) {
			Database.rollback(sp);
			throw error('No se pudo guardar la cotización de flotilla: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Elimina una cotización de flotilla con sus incisos. Los vehículos (CustomerProperty) se
	 *               conservan porque son de la empresa.
	 * @param quoteId: Quote a eliminar.
	 */
	@AuraEnabled(cacheable=false)
	public static void eliminarCotizacionFlotilla(Id quoteId) {
		if (quoteId == null) { return; }
		Id oppId;
		for (Quote q : [SELECT OpportunityId FROM Quote WHERE Id = :quoteId LIMIT 1]) { oppId = q.OpportunityId; }
		Savepoint sp = Database.setSavepoint();
		try {
			delete [SELECT Id FROM Inciso_Flotilla__c WHERE Cotizacion__c = :quoteId];
			delete [SELECT Id FROM Quote WHERE Id = :quoteId];
			if (oppId != null) {
				ColectivoController.guardarComparativoEnOportunidad(oppId, FlotillaComparativoPdfController.construirHtml(oppId));
			}
		} catch (Exception e) {
			Database.rollback(sp);
			throw error('No se pudo eliminar la cotización: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Envía a Einstein (Prompt Template Extractor_Flotilla_Auto) el texto de un bloque de páginas
	 *               de una cotización de flotilla en PDF. El LWC parte los PDFs largos y llama una vez por bloque.
	 * @param textoCotizacion: texto del bloque (extraído con pdf.js en el navegador).
	 * @return JSON {aseguradora, vigenciaDesde, vigenciaHasta, formaPago, incisos:[...]}.
	 */
	@AuraEnabled(cacheable=false)
	public static String analizarFlotillaPdf(String textoCotizacion) {
		if (String.isBlank(textoCotizacion)) { throw error('No se recibió texto de la cotización para analizar.'); }
		if (Test.isRunningTest()) { return '{"incisos":[]}'; }
		try {
			ConnectApi.WrappedValue wrapped = new ConnectApi.WrappedValue();
			wrapped.value = textoCotizacion.length() > 60000 ? textoCotizacion.substring(0, 60000) : textoCotizacion;
			ConnectApi.EinsteinPromptTemplateGenerationsInput genInput = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
			genInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
			genInput.additionalConfig.applicationName = 'PromptBuilderPreview';
			genInput.isPreview = false;
			genInput.inputParams = new Map<String, ConnectApi.WrappedValue>{ PROMPT_INPUT_PARAM => wrapped };
			ConnectApi.EinsteinPromptTemplateGenerationsRepresentation gen =
				ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(PROMPT_TEMPLATE_API_NAME, genInput);
			if (gen != null && gen.generations != null && !gen.generations.isEmpty() && String.isNotBlank(gen.generations[0].text)) {
				return limpiarJson(gen.generations[0].text);
			}
			throw error('La IA no devolvió incisos de este bloque de la cotización.');
		} catch (AuraHandledException ahe) {
			throw ahe;
		} catch (Exception e) {
			throw error('Error al analizar la cotización: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 13/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Genera el PDF del comparativo de flotilla (página FlotillaComparativoPdf) y lo guarda como
	 *               archivo de la oportunidad y de cada cotización de flotilla. Si ya existe el comparativo, se
	 *               agrega como nueva versión del mismo archivo (no se acumulan archivos repetidos).
	 * @param opportunityId: oportunidad colectiva de Auto con cotizaciones de flotilla.
	 * @return Id del ContentDocument del comparativo.
	 */
	@AuraEnabled(cacheable=false)
	public static Id generarComparativoPdf(Id opportunityId) {
		List<Opportunity> opps = [SELECT Id, Name FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
		if (opps.isEmpty()) { throw error('No se encontró la oportunidad.'); }
		Set<Id> quoteIds = new Set<Id>();
		for (Inciso_Flotilla__c i : [SELECT Cotizacion__c FROM Inciso_Flotilla__c WHERE Oportunidad__c = :opportunityId AND Cotizacion__c != null LIMIT 10000]) {
			quoteIds.add(i.Cotizacion__c);
		}
		if (quoteIds.isEmpty()) { throw error('Agrega al menos una cotización de flotilla para generar el comparativo.'); }
		try {
			Blob pdf;
			if (Test.isRunningTest()) {
				pdf = Blob.valueOf(FlotillaComparativoPdfController.construirHtml(opportunityId));
			} else {
				PageReference pr = Page.FlotillaComparativoPdf;
				pr.getParameters().put('oppId', opportunityId);
				pdf = pr.getContentAsPDF();
			}
			String titulo = ('Comparativo flotilla - ' + opps[0].Name).left(240);
			Id docId;
			for (ContentDocumentLink l : [
				SELECT ContentDocumentId FROM ContentDocumentLink
				WHERE LinkedEntityId = :opportunityId AND ContentDocument.Title = :titulo LIMIT 1
			]) { docId = l.ContentDocumentId; }

			ContentVersion cv = new ContentVersion(Title = titulo, PathOnClient = titulo + '.pdf', VersionData = pdf, Origin = 'H');
			if (docId != null) { cv.ContentDocumentId = docId; }
			insert cv;
			if (docId == null) {
				docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
			}
			// Liga el archivo a la oportunidad y a cada cotización que aún no lo tenga.
			Set<Id> ligados = new Set<Id>();
			for (ContentDocumentLink l : [SELECT LinkedEntityId FROM ContentDocumentLink WHERE ContentDocumentId = :docId]) {
				ligados.add(l.LinkedEntityId);
			}
			List<ContentDocumentLink> links = new List<ContentDocumentLink>();
			Set<Id> destinos = new Set<Id>(quoteIds);
			destinos.add(opportunityId);
			for (Id destino : destinos) {
				if (!ligados.contains(destino)) {
					links.add(new ContentDocumentLink(ContentDocumentId = docId, LinkedEntityId = destino, ShareType = 'V', Visibility = 'AllUsers'));
				}
			}
			if (!links.isEmpty()) { insert links; }
			ColectivoController.guardarComparativoEnOportunidad(opportunityId, FlotillaComparativoPdfController.construirHtml(opportunityId));
			return docId;
		} catch (Exception e) {
			throw error('No se pudo generar el PDF del comparativo: ' + e.getMessage());
		}
	}

	// ============================================================
	// Helpers
	// ============================================================

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Vehículos (CustomerProperty) de la empresa para los incisos con serie: reutiliza los que ya
	 *               existen con el mismo VIN y crea los que faltan.
	 * @param accountId: empresa dueña de la flotilla.
	 * @param incisos: incisos de la cotización.
	 * @return mapa VIN normalizado -> Id de CustomerProperty.
	 */
	private static Map<String, Id> vehiculosDe(Id accountId, List<IncisoEntrada> incisos) {
		Map<String, IncisoEntrada> porVin = new Map<String, IncisoEntrada>();
		for (IncisoEntrada e : incisos) {
			if (String.isNotBlank(e.serie) && !porVin.containsKey(vin(e.serie))) { porVin.put(vin(e.serie), e); }
		}
		Map<String, Id> res = new Map<String, Id>();
		if (porVin.isEmpty()) { return res; }
		for (CustomerProperty c : [SELECT Id, Vin FROM CustomerProperty WHERE PrimaryOwnerId = :accountId AND Vin IN :porVin.keySet()]) {
			res.put(vin(c.Vin), c.Id);
		}
		List<CustomerProperty> nuevos = new List<CustomerProperty>();
		for (String v : porVin.keySet()) {
			if (res.containsKey(v)) { continue; }
			IncisoEntrada e = porVin.get(v);
			CustomerProperty c = new CustomerProperty(PrimaryOwnerId = accountId, Vin = v);
			setTexto(c, 'Description', e.descripcion);
			setTexto(c, 'Make', marcaDe(e.descripcion));
			setTexto(c, 'RegistrationNumber', e.placas == null ? null : e.placas.deleteWhitespace().toUpperCase());
			setTexto(c, 'Uso__c', e.uso);
			setTexto(c, 'TipoVehiculo__c', e.tipoVehiculo);
			if (e.modelo != null && e.modelo > 1900 && e.modelo < 2100) { c.MakeYear = e.modelo; }
			nuevos.add(c);
		}
		if (!nuevos.isEmpty()) {
			insert nuevos;
			for (CustomerProperty c : nuevos) { res.put(c.Vin, c.Id); }
		}
		return res;
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Marca del vehículo a partir de la descripción de la aseguradora. Quita prefijos de
	 *               abreviatura que usan las tarifas (ej. "TY TOYOTA HILUX", "CS NISSAN NP300").
	 * @param descripcion: descripción del vehículo.
	 * @return marca o null.
	 */
	@TestVisible
	private static String marcaDe(String descripcion) {
		if (String.isBlank(descripcion)) { return null; }
		List<String> partes = descripcion.normalizeSpace().split(' ');
		Integer i = 0;
		while (i < partes.size() - 1 && partes[i].length() <= 2) { i++; }
		return partes[i].left(40);
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Producto de Auto de la aseguradora (Family = ramo de la oportunidad o que contenga "Auto").
	 * @param aseguradoraId: aseguradora.
	 * @param ramo: ramo de la oportunidad.
	 * @return Id de Product2 o null.
	 */
	private static Id productoAuto(Id aseguradoraId, String ramo) {
		String patron = '%Auto%';
		for (Product2 p : [
			SELECT Id, Family FROM Product2
			WHERE IsActive = true AND Aseguradora__c = :aseguradoraId AND (Family = :ramo OR Family LIKE :patron)
			ORDER BY Name LIMIT 20
		]) {
			if (p.Family == ramo) { return p.Id; }
		}
		for (Product2 p : [
			SELECT Id FROM Product2
			WHERE IsActive = true AND Aseguradora__c = :aseguradoraId AND Family LIKE :patron
			ORDER BY Name LIMIT 1
		]) { return p.Id; }
		return null;
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Lista de precios estándar (requerida por Quote).
	 * @return Id del Pricebook2 estándar.
	 */
	private static Id pricebookEstandar() {
		if (Test.isRunningTest()) { return Test.getStandardPricebookId(); }
		List<Pricebook2> l = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
		return l.isEmpty() ? null : l[0].Id;
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Frecuencia de prima del Quote a partir de la forma de pago.
	 * @param formaPago: texto (Contado, Semestral, Mensual...).
	 * @return valor del picklist Frecuencia_de_prima__c.
	 */
	@TestVisible
	private static String frecuencia(String formaPago) {
		String v = formaPago == null ? '' : formaPago.toLowerCase();
		// Contado = un solo pago anual (el picklist del Quote no tiene "Contado").
		if (v.contains('contado') || v.contains('unic') || v.contains('una sola')) { return 'Anual'; }
		if (v.contains('mensual')) { return 'Mensual'; }
		if (v.contains('trimestr')) { return 'Trimestral'; }
		if (v.contains('semestr')) { return 'Semestral'; }
		return 'Anual';
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve el valor si existe (activo) en el picklist; si no, el valor de respaldo.
	 * @param campo: campo picklist.
	 * @param valor: valor deseado.
	 * @param respaldo: valor a usar si el deseado no existe.
	 * @return valor válido del picklist.
	 */
	@TestVisible
	private static String valorPicklist(Schema.SObjectField campo, String valor, String respaldo) {
		for (Schema.PicklistEntry pe : campo.getDescribe().getPicklistValues()) {
			if (pe.isActive() && pe.getValue() == valor) { return valor; }
		}
		return respaldo;
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cero cuando el monto viene vacío.
	 * @param v: monto.
	 * @return el monto o 0.
	 */
	private static Decimal nz(Decimal v) {
		return v == null ? 0 : v;
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Deducible como porcentaje (0.05 -> 5).
	 * @param v: valor recibido.
	 * @return porcentaje o null.
	 */
	@TestVisible
	private static Decimal porcentaje(Decimal v) {
		if (v == null) { return null; }
		return (v > 0 && v <= 1) ? v * 100 : v;
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: VIN normalizado (sin espacios, en mayúsculas).
	 * @param s: serie.
	 * @return serie normalizada.
	 */
	private static String vin(String s) {
		return s == null ? null : s.deleteWhitespace().toUpperCase().left(30);
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Convierte "YYYY-MM-DD" a Date; null si viene vacío o no es válida.
	 * @param s: fecha ISO.
	 * @return Date o null.
	 */
	@TestVisible
	private static Date fecha(String s) {
		if (String.isBlank(s)) { return null; }
		try { return Date.valueOf(s.trim().left(10)); } catch (Exception e) { return null; }
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Asigna un texto recortado a la longitud del campo.
	 * @param so: registro.
	 * @param campo: API name del campo de texto.
	 * @param valor: texto (vacío = no se asigna).
	 */
	private static void setTexto(SObject so, String campo, String valor) {
		if (String.isBlank(valor)) { return; }
		Integer largo = so.getSObjectType().getDescribe().fields.getMap().get(campo).getDescribe().getLength();
		String v = valor.normalizeSpace();
		so.put(campo, largo > 0 && v.length() > largo ? v.left(largo) : v);
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Limpia la respuesta de la IA: recorta del primer "{" al último "}".
	 * @param raw: texto devuelto por el modelo.
	 * @return JSON limpio.
	 */
	@TestVisible
	private static String limpiarJson(String raw) {
		if (String.isBlank(raw)) { return '{"incisos":[]}'; }
		Integer ini = raw.indexOf('{');
		Integer fin = raw.lastIndexOf('}');
		return (ini >= 0 && fin > ini) ? raw.substring(ini, fin + 1) : '{"incisos":[]}';
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: AuraHandledException con el mensaje visible en el LWC.
	 * @param msg: mensaje para el usuario.
	 * @return excepción lista para lanzar.
	 */
	private static AuraHandledException error(String msg) {
		AuraHandledException e = new AuraHandledException(msg);
		e.setMessage(msg);
		return e;
	}
}
