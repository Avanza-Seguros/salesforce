/**
 * @creation date: 19/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Producto del catálogo (Product2) para una póliza leída de un PDF. Busca entre los productos activos
 * de la aseguradora el que es igual al plan/paquete de la carátula y, si ninguno es igual, el de mayor semejanza:
 * cuenta que la familia del producto corresponda al ramo, qué tanto se parece su nombre al plan (sin acentos,
 * mayúsculas ni palabras de relleno, y "Amplia" = "Amplio") y si su nombre aparece en el texto de la póliza. Con
 * aseguradora siempre devuelve uno de sus productos (sin ninguna pista, el más general del ramo); sin aseguradora
 * solo devuelve uno si el texto lo sugiere.
 */
public with sharing class ProductoPorSemejanza {

	// Palabras que no distinguen a un producto.
	private static final Set<String> RELLENO = new Set<String>{
		'de', 'del', 'la', 'las', 'el', 'los', 'y', 'e', 'o', 'u', 'a', 'al', 'para', 'en', 'con', 'por', 'sin',
		'the', 'of', 'and', 'seguro', 'seguros', 'plan', 'planes', 'paquete', 'poliza', 'producto', 'sa', 'cv',
		'mexico', 'version', 'english', 'espanol', 'cia', 'compania'
	};
	// Ramos parecidos entre sí (los productos de hogar están en varias familias).
	private static final Set<String> PATRIMONIALES = new Set<String>{ 'Danos', 'Empresarial', 'RC', 'Vision' };

	/**
	 * @creation date: 19/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Producto con mayor semejanza a lo leído del PDF.
	 * @param aseguradoraId: Aseguradora de la póliza (Aseguradora__c); null si no se reconoció
	 * @param ramo: Ramo de la póliza (Ramo__c o el texto del PDF)
	 * @param datos: JSON leído del PDF (plan, descripcion, bienAsegurado, tipoPoliza)
	 * @param texto: Texto de la carátula (opcional)
	 * @return Id del producto; null si no hay candidatos
	 */
	public static Id buscar(Id aseguradoraId, String ramo, Map<String, Object> datos, String texto) {
		Map<String, Object> d = datos == null ? new Map<String, Object>() : datos;
		String plan = str(d.get('plan'));
		Map<String, Object> bien = d.get('bienAsegurado') instanceof Map<String, Object>
			? (Map<String, Object>) d.get('bienAsegurado') : new Map<String, Object>();
		String otros = String.join(new List<String>{
			str(d.get('tipoPoliza')), str(d.get('descripcion')), str(bien.get('descripcion')),
			String.isBlank(texto) ? '' : texto.left(20000)
		}, ' ');
		List<Product2> candidatos = aseguradoraId != null
			? [SELECT Id, Name, Family, Aseguradora__r.Name FROM Product2
			   WHERE IsActive = true AND Aseguradora__c = :aseguradoraId ORDER BY Name LIMIT 2000]
			: [SELECT Id, Name, Family, Aseguradora__r.Name FROM Product2
			   WHERE IsActive = true AND Aseguradora__c != null ORDER BY Name LIMIT 2000];
		// Pólizas que ya tienen cada producto: desempatan a favor del más usado.
		Map<Id, Integer> usos = new Map<Id, Integer>();
		if (aseguradoraId != null && !candidatos.isEmpty()) {
			for (AggregateResult ar : [
				SELECT ProductId p, COUNT(Id) n FROM InsurancePolicy
				WHERE Aseguradora__c = :aseguradoraId AND ProductId IN :candidatos GROUP BY ProductId
			]) { usos.put((Id) ar.get('p'), (Integer) ar.get('n')); }
		}
		return mejor(candidatos, aseguradoraId != null, ramo, plan, otros, usos);
	}

	/**
	 * @creation date: 19/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Elige entre los candidatos el de mayor puntaje; empata a favor del que más pólizas tienen y,
	 * si no, del nombre más corto (el más general).
	 * @param candidatos: Productos activos
	 * @param conAseguradora: true si los candidatos son de la aseguradora de la póliza
	 * @param ramo: Ramo de la póliza
	 * @param plan: Plan/paquete leído del PDF
	 * @param otros: Demás texto de la póliza
	 * @param usos: Pólizas por producto (puede ser null)
	 * @return Id del producto elegido; null si no hay o (sin aseguradora) ninguno tiene relación con el texto
	 */
	@TestVisible
	private static Id mejor(List<Product2> candidatos, Boolean conAseguradora, String ramo, String plan, String otros,
		Map<Id, Integer> usos) {
		Map<Id, Integer> u = usos == null ? new Map<Id, Integer>() : usos;
		String ramoPoliza = ramoCanonico(ramo);
		List<String> tokensPlan = tokens(plan, null);
		String textoNorm = ' ' + normalizar(otros) + ' ';
		Product2 elegido = null;
		Decimal mejorPuntaje = null;
		for (Product2 p : candidatos) {
			Set<String> propias = new Set<String>(tokens(p.Aseguradora__r == null ? null : p.Aseguradora__r.Name, null));
			List<String> nombre = tokens(p.Name, propias);
			if (nombre.isEmpty()) { nombre = tokens(p.Name, null); }
			if (nombre.isEmpty()) { continue; }
			Decimal porTexto = puntajePlan(tokensPlan, nombre) + puntajeTexto(nombre, textoNorm);
			// Sin aseguradora el producto solo cuenta si el plan o el texto lo mencionan.
			if (!conAseguradora && porTexto < 20) { continue; }
			Decimal puntaje = porTexto + puntajeRamo(ramoPoliza, ramoCanonico(p.Family));
			Integer usoP = u.containsKey(p.Id) ? u.get(p.Id) : 0;
			Integer usoE = elegido == null || !u.containsKey(elegido.Id) ? 0 : u.get(elegido.Id);
			if (elegido == null || puntaje > mejorPuntaje
				|| (puntaje == mejorPuntaje && (usoP > usoE
					|| (usoP == usoE && p.Name.length() < elegido.Name.length())))) {
				elegido = p;
				mejorPuntaje = puntaje;
			}
		}
		return elegido == null ? null : elegido.Id;
	}

	// Plan igual al nombre: 100; si no, qué tanto se comparten las palabras (hasta 80) más 15 si el nombre completo
	// está en el plan.
	@TestVisible
	private static Decimal puntajePlan(List<String> plan, List<String> nombre) {
		if (plan.isEmpty() || nombre.isEmpty()) { return 0; }
		Integer delNombre = 0;
		for (String n : nombre) { if (estaEn(n, plan)) { delNombre++; } }
		Integer delPlan = 0;
		for (String t : plan) { if (estaEn(t, nombre)) { delPlan++; } }
		if (delNombre == nombre.size() && delPlan == plan.size()) { return 100; }
		Decimal r = 80.0 * (delNombre + delPlan) / (nombre.size() + plan.size());
		if (delNombre == nombre.size()) { r += 15; }
		return r;
	}

	// Nombre del producto en el texto de la póliza: 30 si aparece completo; si no, hasta 20 por sus palabras.
	@TestVisible
	private static Decimal puntajeTexto(List<String> nombre, String textoNorm) {
		if (String.isBlank(textoNorm)) { return 0; }
		if (textoNorm.contains(' ' + String.join(nombre, ' ') + ' ')) { return 30; }
		Integer encontradas = 0;
		for (String n : nombre) { if (textoNorm.contains(' ' + n + ' ')) { encontradas++; } }
		return 20.0 * encontradas / nombre.size();
	}

	// La familia del producto corresponde al ramo de la póliza: 40; ramo parecido (patrimoniales): 15.
	@TestVisible
	private static Decimal puntajeRamo(String ramoPoliza, String ramoProducto) {
		if (ramoPoliza == null || ramoProducto == null) { return 0; }
		if (ramoPoliza == ramoProducto) { return 40; }
		if (PATRIMONIALES.contains(ramoPoliza) && PATRIMONIALES.contains(ramoProducto)) { return 15; }
		return 0;
	}

	// Una palabra está en la lista si es igual, una empieza con la otra (auto/autos) o comparten las primeras 5
	// letras (amplia/amplio, limitada/limitado).
	private static Boolean estaEn(String palabra, List<String> lista) {
		for (String x : lista) {
			if (x == palabra) { return true; }
			if (x.length() >= 4 && palabra.length() >= 4 && (x.startsWith(palabra) || palabra.startsWith(x))) { return true; }
			if (x.length() >= 5 && palabra.length() >= 5 && x.left(5) == palabra.left(5)) { return true; }
		}
		return false;
	}

	/**
	 * @creation date: 19/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Ramo del catálogo para un ramo o una familia de producto escritos de cualquier forma.
	 * @param s: Ramo o familia ("Gastos Médicos Mayores", "Automoviles", "Hogar"...)
	 * @return Ramo (Automoviles, GMM, Vida, Danos, RC, Empresarial, Vision, Dental, Viajes, Mascotas, Fianzas)
	 */
	@TestVisible
	private static String ramoCanonico(String s) {
		if (String.isBlank(s)) { return null; }
		String r = ' ' + normalizar(s) + ' ';
		if (r.contains('auto') || r.contains('vehic') || r.contains('flotilla')) { return 'Automoviles'; }
		if (r.contains('gastos medicos') || r.contains(' gmm ') || r.contains('salud') || r.contains('accidentes personales')) { return 'GMM'; }
		if (r.contains('dental')) { return 'Dental'; }
		if (r.contains('vision')) { return 'Vision'; }
		if (r.contains('viaje')) { return 'Viajes'; }
		if (r.contains('mascota')) { return 'Mascotas'; }
		if (r.contains('fianza')) { return 'Fianzas'; }
		if (r.contains('vida') || r.contains('ahorro')) { return 'Vida'; }
		if (r.contains('empresarial')) { return 'Empresarial'; }
		if (r.contains('responsabilidad') || r.contains(' rc ')) { return 'RC'; }
		if (r.contains('dano') || r.contains('hogar') || r.contains('incendio') || r.contains('transporte')
			|| r.contains('embarcacion') || r.contains('casa')) { return 'Danos'; }
		return r.trim();
	}

	// Palabras de un texto sin acentos, símbolos ni relleno (ni las palabras propias de la aseguradora).
	@TestVisible
	private static List<String> tokens(String s, Set<String> excluir) {
		List<String> r = new List<String>();
		String n = normalizar(s);
		if (String.isBlank(n)) { return r; }
		for (String t : n.split(' ')) {
			if (t.length() < 2 || RELLENO.contains(t) || (excluir != null && excluir.contains(t))) { continue; }
			r.add(t);
		}
		return r;
	}

	// Minúsculas, sin acentos y solo letras y números separados por un espacio.
	@TestVisible
	private static String normalizar(String s) {
		if (String.isBlank(s)) { return ''; }
		String r = s.toLowerCase()
			.replaceAll('[áàäâ]', 'a').replaceAll('[éèëê]', 'e').replaceAll('[íìïî]', 'i')
			.replaceAll('[óòöô]', 'o').replaceAll('[úùüû]', 'u').replace('ñ', 'n');
		return r.replaceAll('[^a-z0-9]', ' ').normalizeSpace();
	}

	private static String str(Object o) { return o == null ? '' : String.valueOf(o).trim(); }
}
