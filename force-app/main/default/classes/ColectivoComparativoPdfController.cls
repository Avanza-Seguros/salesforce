/**
 * @creation date: 14/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Controlador de la página ColectivoComparativoPdf (renderAs PDF). Arma el comparativo de cotizaciones
 *               colectivas a partir de los Quote y Categoria_Colectiva__c de la oportunidad: primas, plan y coberturas
 *               lado a lado, formas de pago, categorías (personas) o ubicaciones (Daños / Empresarial), coberturas
 *               adicionales, distribución por edad, cuota al millar y recomendación. Mismo estilo que los demás comparativos.
 */
public with sharing class ColectivoComparativoPdfController {

	public String htmlBody { get; private set; }

	private static final String TH = 'padding:4px 7px;border:1px solid #d9dee6;font-size:10.5px;text-align:left;background:#f4f6f9;';
	private static final String TH_MEJOR = 'padding:4px 7px;border:1px solid #d9dee6;font-size:10.5px;text-align:left;background:#fff3e0;';
	private static final String TD = 'padding:4px 7px;border:1px solid #eef1f5;font-size:10.5px;text-align:left;';
	private static final String TD_NUM = 'padding:4px 7px;border:1px solid #eef1f5;font-size:10.5px;text-align:right;';
	private static final String TD_NUM_MEJOR = 'padding:4px 7px;border:1px solid #eef1f5;font-size:10.5px;text-align:right;background:#e6f6e9;color:#194e31;font-weight:bold;';
	private static final String TD_AVISO = 'padding:4px 7px;border:1px solid #eef1f5;font-size:10.5px;text-align:right;background:#fff8ef;';
	private static final String ESTILO_PAGINA =
		'<style type="text/css">@page { size: letter landscape; margin: 12mm; } ' +
		'body { font-family: "Arial Unicode MS", Arial, sans-serif; font-size: 11px; color: #1c2433; } ' +
		'table { width: 100%; border-collapse: collapse; margin-bottom: 10px; } ' +
		'h2 { font-size: 18px; margin: 0 0 4px; } h3 { font-size: 13px; margin: 14px 0 6px; } ' +
		'tr { page-break-inside: avoid; }</style>';
	private static final Map<String, String> RAMOS = new Map<String, String>{
		'GMM' => 'Gastos Médicos Mayores', 'Vida' => 'Vida Grupo', 'Accidentes Personales' => 'Accidentes Personales',
		'Dental' => 'Dental', 'Vision' => 'Visión', 'Viajes' => 'Viajes', 'Danos' => 'Daños', 'Empresarial' => 'Paquete Empresarial'
	};
	// Parámetros del plan que se comparan lado a lado (clave de la categoría -> etiqueta).
	private static final List<List<String>> PLAN = new List<List<String>>{
		new List<String>{ 'plan', 'Plan' }, new List<String>{ 'sumaAsegurada', 'Suma asegurada' },
		new List<String>{ 'deducible', 'Deducible' }, new List<String>{ 'coaseguro', 'Coaseguro' },
		new List<String>{ 'topeCoaseguro', 'Tope de coaseguro' }, new List<String>{ 'tabulador', 'Tabulador / círculo médico' },
		new List<String>{ 'nivelHospitalario', 'Nivel hospitalario' }, new List<String>{ 'territorio', 'Territorio' }
	};

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Constructor: lee la oportunidad del parámetro oppId y arma el HTML del comparativo.
	 */
	public ColectivoComparativoPdfController() {
		String oppId = ApexPages.currentPage() == null ? null : ApexPages.currentPage().getParameters().get('oppId');
		htmlBody = String.isBlank(oppId) ? '' : construirHtml((Id) oppId);
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: HTML completo del comparativo colectivo de la oportunidad.
	 * @param opportunityId: oportunidad colectiva.
	 * @return documento HTML ('' si no hay cotizaciones colectivas).
	 */
	public static String construirHtml(Id opportunityId) {
		List<Opportunity> opps = [SELECT Id, Name, Account.Name, Ramo__c FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
		if (opps.isEmpty()) { return ''; }
		Opportunity opp = opps[0];
		List<Map<String, Object>> cot = ColectivoController.getCotizacionesColectivas(opportunityId);
		if (cot.isEmpty()) { return ''; }

		// Base de comparación: prima total si todas traen IVA (o ninguna); si alguna no lo trae, neta + derechos para todas.
		Integer conIva = 0;
		for (Map<String, Object> q : cot) { if (q.get('iva') != null) { conIva++; } }
		Boolean sinIva = conIva > 0 && conIva < cot.size();
		Boolean ubic = ColectivoController.esUbicaciones(opp.Ramo__c);
		String unidad = ubic ? 'ubicaciones' : 'asegurados';
		Map<Object, Decimal> base = new Map<Object, Decimal>();
		Map<Object, Decimal> asegurados = new Map<Object, Decimal>();
		Map<Object, Decimal> sumaTotal = new Map<Object, Decimal>();
		Boolean haySuma = false;
		for (Map<String, Object> q : cot) {
			Decimal b = sinIva ? dec(q.get('primaNeta')) + dec(q.get('derechos')) : dec(q.get('primaTotal'));
			if (b == 0) { b = dec(q.get('primaTotal')); }
			base.put(q.get('id'), b);
			Decimal a = 0;
			Decimal sa = 0;
			List<Object> cats = (List<Object>) q.get('categorias');
			for (Object o : cats) {
				a += dec(((Map<String, Object>) o).get('asegurados'));
				sa += dec(((Map<String, Object>) o).get('sumaAseguradaTotal'));
			}
			asegurados.put(q.get('id'), ubic ? cats.size() : a);
			sumaTotal.put(q.get('id'), sa);
			haySuma = haySuma || sa > 0;
		}
		cot = ordenar(cot, base);
		Integer n = cot.size();
		Decimal mejor = base.get(cot[0].get('id'));
		String ramo = RAMOS.containsKey(opp.Ramo__c) ? RAMOS.get(opp.Ramo__c) : (String.isBlank(opp.Ramo__c) ? 'Colectivo' : opp.Ramo__c);
		String ancho = n >= 4 ? '100%' : (220 + n * 190) + 'px';

		String h = '<html><head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>' + ESTILO_PAGINA
			+ '<style type="text/css">table.resumen { width: ' + ancho + '; table-layout: fixed; }</style></head><body>';
		Map<String, Object> primera = cot[0];
		String vigencia = primera.get('vigenciaDesde') != null
			? fechaTxt((Date) primera.get('vigenciaDesde')) + ' – ' + fechaTxt((Date) primera.get('vigenciaHasta')) : '';
		h += '<h2>Comparativo de Seguro Colectivo de ' + esc(ramo) + '</h2>';
		String cliente = opp.Account != null ? opp.Account.Name : null;
		h += '<p style="font-size:11px;color:#667;margin:0 0 4px;">'
			+ (String.isNotBlank(cliente) && cliente != opp.Name ? esc(cliente) + ' &middot; ' : '')
			+ esc(opp.Name) + (String.isNotBlank(vigencia) ? ' &middot; Vigencia ' + esc(vigencia) : '') + '</p>';
		h += '<p style="font-size:11px;color:#b85b00;margin:0 0 12px;">' + n + (n == 1 ? ' aseguradora cotizada' : ' aseguradoras comparadas')
			+ ' &middot; ' + maximo(asegurados.values()).intValue() + ' '
			+ (maximo(asegurados.values()) == 1 ? (ubic ? 'ubicaci&oacute;n' : 'asegurado') : unidad)
			+ (haySuma ? ' &middot; ' + (ubic ? 'valor asegurado ' : 'suma asegurada ') + moneda(maximo(sumaTotal.values())) : '')
			+ ' &middot; Cotizado por Avanza Seguro &middot; ' + fechaTxt(Date.today()) + '</p>';
		if (sinIva) {
			h += '<p style="font-size:10px;margin:0 0 8px;padding:6px 8px;background:#fff8ef;border:1px solid #f2d3a8;">'
				+ 'Algunas aseguradoras no incluyen IVA en su cotización: la comparación se hace sobre <b>prima neta + derechos (sin IVA)</b> para todas.</p>';
		}

		// ---------- Resumen ----------
		h += '<h3>Resumen por aseguradora</h3><table class="resumen">' + encabezado('Concepto', cot, base, mejor);
		String etiquetaBase = sinIva ? 'Prima neta + derechos (sin IVA)' : 'Prima total anual';
		h += '<tr><th style="' + TH + '">' + etiquetaBase + '</th>';
		for (Map<String, Object> q : cot) {
			Decimal b = base.get(q.get('id'));
			h += '<td style="' + (n > 1 && b == mejor ? TD_NUM_MEJOR : TD_NUM) + '">' + moneda(b) + '</td>';
		}
		h += '</tr><tr><th style="' + TH + '">Diferencia vs. la mejor</th>';
		for (Map<String, Object> q : cot) {
			Decimal dif = base.get(q.get('id')) - mejor;
			h += '<td style="' + TD_NUM + '">' + (dif == 0 ? '—' : '+' + moneda(dif) + ' (+' + porcentaje(mejor == 0 ? 0 : dif / mejor * 100) + ')') + '</td>';
		}
		h += '</tr>' + filaMonto('Prima neta', cot, 'primaNeta', null) + filaMonto('Derechos / gastos de expedición', cot, 'derechos', null)
			+ filaMonto('Recargo por pago fraccionado', cot, 'recargo', null) + filaMonto('IVA', cot, 'iva', 'No incluido')
			+ filaMonto('Prima total', cot, 'primaTotal', null);
		h += '<tr><th style="' + TH + '">' + unidad.capitalize() + '</th>';
		Decimal maxAseg = maximo(asegurados.values());
		for (Map<String, Object> q : cot) {
			Decimal a = asegurados.get(q.get('id'));
			h += '<td style="' + (a != maxAseg ? TD_AVISO : TD_NUM) + '">' + a.intValue() + '</td>';
		}
		h += '</tr><tr><th style="' + TH + '">Prima promedio por ' + (ubic ? 'ubicación' : 'asegurado') + '</th>';
		for (Map<String, Object> q : cot) {
			Decimal a = asegurados.get(q.get('id'));
			h += '<td style="' + TD_NUM + '">' + (a == 0 ? '—' : moneda(base.get(q.get('id')) / a)) + '</td>';
		}
		h += '</tr>';
		if (haySuma) {
			// Cuota al millar: prima neta por cada $1,000 de suma asegurada (compara precio aunque las sumas difieran).
			h += '<tr><th style="' + TH + '">' + (ubic ? 'Valor total asegurado' : 'Suma asegurada total') + '</th>';
			for (Map<String, Object> q : cot) {
				Decimal sa = sumaTotal.get(q.get('id'));
				h += '<td style="' + TD_NUM + '">' + (sa > 0 ? moneda(sa) : '—') + '</td>';
			}
			h += '</tr><tr><th style="' + TH + '">Cuota al millar (prima neta)</th>';
			for (Map<String, Object> q : cot) {
				Decimal cuota = cuotaAlMillar(q, sumaTotal.get(q.get('id')));
				h += '<td style="' + TD_NUM + '">' + (cuota == null ? '—' : String.valueOf(cuota.setScale(3, System.RoundingMode.HALF_UP)) + ' &permil;') + '</td>';
			}
			h += '</tr>';
		}
		h += '</table>';

		// ---------- Plan ----------
		h += '<h3>' + (ubic ? 'Coberturas cotizadas' : 'Plan cotizado') + '</h3><table class="resumen">' + encabezado('Concepto', cot, base, mejor);
		Set<String> distintos = new Set<String>();
		List<List<String>> filasPlan = ubic ? new List<List<String>>() : new List<List<String>>(PLAN);
		filasPlan.addAll(conceptos(cot));
		for (List<String> p : filasPlan) {
			List<String> valores = new List<String>();
			Boolean hay = false;
			for (Map<String, Object> q : cot) {
				String v = p[0].startsWith('#') ? valorParametro(q, p[0].substring(1)) : valorPlan(q, p[0]);
				valores.add(v);
				hay = hay || String.isNotBlank(v);
			}
			if (!hay) { continue; }
			Set<String> unicos = new Set<String>();
			for (String v : valores) { if (String.isNotBlank(v)) { unicos.add(v.toUpperCase().deleteWhitespace()); } }
			if (unicos.size() > 1 && p[0] != 'plan' && p[0] != 'tabulador') { distintos.add(p[1].toLowerCase()); }
			h += '<tr><th style="' + TH + '">' + esc(p[1]) + '</th>';
			for (String v : valores) { h += '<td style="' + TD_NUM + '">' + (String.isBlank(v) ? '—' : esc(v)) + '</td>'; }
			h += '</tr>';
		}
		h += '</table>';

		// ---------- Formas de pago ----------
		List<String> formas = new List<String>();
		for (Map<String, Object> q : cot) {
			for (Object o : (List<Object>) q.get('formasPago')) {
				String f = texto(((Map<String, Object>) o).get('forma'));
				if (String.isNotBlank(f) && !formas.contains(f.capitalize())) { formas.add(f.capitalize()); }
			}
		}
		if (!formas.isEmpty()) {
			h += '<h3>Formas de pago</h3><table class="resumen">' + encabezado('Forma de pago', cot, base, mejor);
			for (String f : formas) {
				h += '<tr><th style="' + TH + '">' + esc(f) + '</th>';
				for (Map<String, Object> q : cot) {
					Map<String, Object> fp = null;
					for (Object o : (List<Object>) q.get('formasPago')) {
						if (texto(((Map<String, Object>) o).get('forma')).equalsIgnoreCase(f)) { fp = (Map<String, Object>) o; }
					}
					String txt = '—';
					if (fp != null) {
						txt = fp.get('primaTotal') != null ? moneda(dec(fp.get('primaTotal'))) : '';
						List<String> det = new List<String>();
						if (fp.get('recargoPct') != null && dec(fp.get('recargoPct')) > 0) { det.add('recargo ' + porcentaje(dec(fp.get('recargoPct')))); }
						if (fp.get('numeroPagos') != null && dec(fp.get('numeroPagos')) > 1) {
							det.add(dec(fp.get('numeroPagos')).intValue() + ' pagos'
								+ (fp.get('primerPago') != null ? ', 1° ' + moneda(dec(fp.get('primerPago'))) : ''));
						}
						if (!det.isEmpty()) { txt += '<br/><span style="font-size:9px;color:#667;">' + esc(String.join(det, ' · ')) + '</span>'; }
						if (String.isBlank(txt)) { txt = '—'; }
					}
					h += '<td style="' + TD_NUM + '">' + txt + '</td>';
				}
				h += '</tr>';
			}
			h += '</table>';
		}

		// ---------- Categorías ----------
		h += '<h3>' + (ubic ? 'Ubicaciones' : 'Categorías y asegurados') + '</h3><table class="resumen">'
			+ encabezado('Aseguradora', cot, base, mejor).replace('Aseguradora', ubic ? 'Ubicación' : 'Categoría');
		List<String> nombres = new List<String>();
		for (Map<String, Object> q : cot) {
			for (Object o : (List<Object>) q.get('categorias')) {
				String c = texto(((Map<String, Object>) o).get('nombre'));
				if (!nombres.contains(c)) { nombres.add(c); }
			}
		}
		for (String c : nombres) {
			h += '<tr><th style="' + TH + '">' + esc(c) + '</th>';
			for (Map<String, Object> q : cot) {
				Map<String, Object> cat = null;
				for (Object o : (List<Object>) q.get('categorias')) { if (texto(((Map<String, Object>) o).get('nombre')) == c) { cat = (Map<String, Object>) o; } }
				if (cat == null) { h += '<td style="' + TD_NUM + '">—</td>'; continue; }
				String sub = ubic
					? esc(texto(cat.get('direccion'))) + (cat.get('sumaAseguradaTotal') != null ? (String.isBlank(texto(cat.get('direccion'))) ? '' : '<br/>')
						+ 'Valor asegurado ' + moneda(dec(cat.get('sumaAseguradaTotal'))) : '')
						+ (String.isNotBlank(texto(cat.get('plan'))) ? '<br/>Giro: ' + esc(texto(cat.get('plan'))) : '')
					: dec(cat.get('asegurados')).intValue() + ' asegurados'
						+ (cat.get('hombres') != null || cat.get('mujeres') != null ? ' (' + dec(cat.get('hombres')).intValue() + ' H / ' + dec(cat.get('mujeres')).intValue() + ' M)' : '')
						+ (cat.get('sumaAseguradaTotal') != null ? ' &middot; SA ' + moneda(dec(cat.get('sumaAseguradaTotal'))) : '');
				h += '<td style="' + TD_NUM + '">' + (cat.get('primaNeta') != null ? moneda(dec(cat.get('primaNeta'))) + ' neta<br/>' : '')
					+ '<span style="font-size:9px;color:#667;">' + sub + '</span></td>';
			}
			h += '</tr>';
		}
		h += '</table>';

		// ---------- Coberturas adicionales ----------
		Boolean hayCob = false;
		String filaCob = '<tr><th style="' + TH + '">Incluidas</th>';
		for (Map<String, Object> q : cot) {
			Set<String> cobs = new Set<String>();
			for (Object o : (List<Object>) q.get('categorias')) {
				for (Object c : (List<Object>) ((Map<String, Object>) o).get('coberturasAdicionales')) { if (String.isNotBlank(texto(c))) { cobs.add(texto(c)); } }
			}
			hayCob = hayCob || !cobs.isEmpty();
			List<String> lista = new List<String>();
			for (String c : cobs) { lista.add('&bull; ' + esc(c)); }
			filaCob += '<td style="' + TD + 'vertical-align:top;font-size:9.5px;">' + (lista.isEmpty() ? '—' : String.join(lista, '<br/>')) + '</td>';
		}
		if (hayCob) {
			h += '<h3>Coberturas adicionales</h3><table class="resumen">' + encabezado('Coberturas', cot, base, mejor) + filaCob + '</tr></table>';
		}

		// ---------- Distribución por edad ----------
		h += distribucionEdades(cot);

		// ---------- Recomendación ----------
		h += '<h3>Resumen y recomendación</h3>';
		h += '<p style="margin:0;padding:10px;background:#f4f6f9;border:1px solid #e6e9ef;font-size:11px;">'
			+ recomendacion(cot, base, asegurados, distintos, sinIva, unidad) + notaCuota(cot, asegurados, sumaTotal, unidad) + '</p>';
		h += '<p style="font-size:9.5px;color:#667;margin:10px 0 0;">Documento informativo elaborado con las cotizaciones de cada aseguradora. '
			+ (ubic ? 'Las primas pueden cambiar si los datos de las ubicaciones (construcción, giro, valores, protecciones) difieren de los cotizados; las '
				: 'Las primas pueden cambiar si la información de los asegurados (edad, sexo, parentesco) difiere de la cotizada; las ')
			+ 'condiciones finales se definen en la póliza y sus condiciones generales.</p>';
		h += '</body></html>';
		return h;
	}

	// ============================================================
	// Secciones
	// ============================================================

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Renglón de encabezado con una columna por aseguradora (la de mejor prima resaltada).
	 * @param primera: título de la primera columna.
	 * @param cot: cotizaciones en orden.
	 * @param base: prima de comparación por cotización.
	 * @param mejor: prima de comparación más baja.
	 * @return HTML del renglón.
	 */
	private static String encabezado(String primera, List<Map<String, Object>> cot, Map<Object, Decimal> base, Decimal mejor) {
		String h = '<tr><th style="' + TH + 'width:220px;">' + esc(primera) + '</th>';
		for (Map<String, Object> q : cot) {
			Boolean esMejor = cot.size() > 1 && base.get(q.get('id')) == mejor;
			h += '<th style="' + (esMejor ? TH_MEJOR : TH) + 'text-align:right;">' + esc((String) q.get('aseguradora'))
				+ (esMejor ? '<br/><span style="font-size:9px;color:#b85b00;">Mejor prima</span>' : '') + '</th>';
		}
		return h + '</tr>';
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Renglón de un monto de la cotización; se omite si ninguna lo trae.
	 * @param etiqueta: texto de la primera columna.
	 * @param cot: cotizaciones.
	 * @param campo: clave del monto.
	 * @param vacio: texto cuando una aseguradora no lo trae (null = "—").
	 * @return HTML del renglón o vacío.
	 */
	private static String filaMonto(String etiqueta, List<Map<String, Object>> cot, String campo, String vacio) {
		Boolean hay = false;
		String h = '<tr><th style="' + TH + '">' + esc(etiqueta) + '</th>';
		for (Map<String, Object> q : cot) {
			Object v = q.get(campo);
			hay = hay || v != null;
			h += '<td style="' + (v == null && vacio != null ? TD_AVISO : TD_NUM) + '">' + (v == null ? (vacio == null ? '—' : vacio) : moneda(dec(v))) + '</td>';
		}
		return hay ? h + '</tr>' : '';
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valor de un parámetro del plan en una cotización: único, o "Categoría: valor" por categoría si cambia.
	 * @param q: cotización.
	 * @param campo: clave del parámetro.
	 * @return texto del parámetro ('' si no viene).
	 */
	@TestVisible
	private static String valorPlan(Map<String, Object> q, String campo) {
		List<Object> cats = (List<Object>) q.get('categorias');
		Set<String> unicos = new Set<String>();
		List<String> porCategoria = new List<String>();
		for (Object o : cats) {
			Map<String, Object> c = (Map<String, Object>) o;
			String v = texto(c.get(campo));
			if (String.isBlank(v)) { continue; }
			unicos.add(v);
			porCategoria.add(texto(c.get('nombre')) + ': ' + v);
		}
		if (unicos.isEmpty()) { return ''; }
		return unicos.size() == 1 ? new List<String>(unicos)[0] : String.join(porCategoria, ' / ');
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Coberturas / condiciones de "parametros" de todas las cotizaciones, en el orden en que aparecen
	 *               (se agrupan por nombre sin acentos ni mayúsculas). La clave lleva "#" para distinguirlas de los campos fijos.
	 * @param cot: cotizaciones.
	 * @return lista de {"#llave", etiqueta}.
	 */
	private static List<List<String>> conceptos(List<Map<String, Object>> cot) {
		List<List<String>> res = new List<List<String>>();
		Set<String> vistos = new Set<String>();
		for (Map<String, Object> q : cot) {
			for (Object o : (List<Object>) q.get('categorias')) {
				List<Object> params = (List<Object>) ((Map<String, Object>) o).get('parametros');
				for (Object p : params == null ? new List<Object>() : params) {
					String concepto = texto(((Map<String, Object>) p).get('concepto'));
					String llave = llaveConcepto(concepto);
					if (String.isBlank(llave) || llave == 'cuotaalmillar' || vistos.contains(llave)) { continue; }
					vistos.add(llave);
					res.add(new List<String>{ '#' + llave, concepto });
				}
			}
		}
		return res;
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Llave de comparación de un concepto: minúsculas, sin acentos ni signos.
	 * @param concepto: nombre de la cobertura.
	 * @return llave.
	 */
	@TestVisible
	private static String llaveConcepto(String concepto) {
		if (String.isBlank(concepto)) { return ''; }
		String t = concepto.toLowerCase();
		Map<String, String> acentos = new Map<String, String>{ 'á' => 'a', 'é' => 'e', 'í' => 'i', 'ó' => 'o', 'ú' => 'u', 'ü' => 'u', 'ñ' => 'n' };
		for (String a : acentos.keySet()) { t = t.replace(a, acentos.get(a)); }
		return t.replaceAll('[^a-z0-9]', '');
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valor de una cobertura de "parametros" en una cotización: único, o "Categoría: valor" si cambia.
	 * @param q: cotización.
	 * @param llave: llave del concepto (llaveConcepto).
	 * @return texto ('' si la aseguradora no la incluye).
	 */
	@TestVisible
	private static String valorParametro(Map<String, Object> q, String llave) {
		Set<String> unicos = new Set<String>();
		List<String> porCategoria = new List<String>();
		for (Object o : (List<Object>) q.get('categorias')) {
			Map<String, Object> c = (Map<String, Object>) o;
			List<Object> params = (List<Object>) c.get('parametros');
			for (Object p : params == null ? new List<Object>() : params) {
				Map<String, Object> pm = (Map<String, Object>) p;
				if (llaveConcepto(texto(pm.get('concepto'))) != llave || String.isBlank(texto(pm.get('valor')))) { continue; }
				unicos.add(texto(pm.get('valor')));
				porCategoria.add(texto(c.get('nombre')) + ': ' + texto(pm.get('valor')));
			}
		}
		if (unicos.isEmpty()) { return ''; }
		// Un solo valor si aplica igual a todas las categorías; si solo algunas la tienen, se dice cuáles.
		Boolean todas = porCategoria.size() >= ((List<Object>) q.get('categorias')).size();
		return unicos.size() == 1 && todas ? new List<String>(unicos)[0] : String.join(porCategoria, ' / ');
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cuota al millar: prima neta (o la suma de las categorías) por cada $1,000 de suma asegurada.
	 * @param q: cotización.
	 * @param sumaAsegurada: suma asegurada total de la cotización.
	 * @return cuota o null si no hay suma asegurada o prima.
	 */
	@TestVisible
	private static Decimal cuotaAlMillar(Map<String, Object> q, Decimal sumaAsegurada) {
		if (sumaAsegurada == null || sumaAsegurada <= 0) { return null; }
		Decimal neta = dec(q.get('primaNeta'));
		if (neta == 0) {
			for (Object o : (List<Object>) q.get('categorias')) { neta += dec(((Map<String, Object>) o).get('primaNeta')); }
		}
		return neta == 0 ? null : neta / sumaAsegurada * 1000;
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cuando las aseguradoras no cotizaron lo mismo (distinto número de asegurados / ubicaciones o suma
	 *               asegurada distinta), la prima sola no basta: compara la cuota al millar (prima neta por cada $1,000
	 *               asegurados) y dice quién asegura más barato por peso.
	 * @param cot: cotizaciones en orden de prima.
	 * @param tamano: asegurados o ubicaciones por cotización.
	 * @param sumaTotal: suma asegurada total por cotización.
	 * @param unidad: "asegurados" o "ubicaciones".
	 * @return texto (vacío si no aplica).
	 */
	@TestVisible
	private static String notaCuota(List<Map<String, Object>> cot, Map<Object, Decimal> tamano, Map<Object, Decimal> sumaTotal, String unidad) {
		if (cot.size() < 2) { return ''; }
		Decimal minSa;
		Decimal maxSa = 0;
		Map<String, Object> mejor;
		Decimal mejorCuota;
		for (Map<String, Object> q : cot) {
			Decimal sa = sumaTotal.get(q.get('id'));
			Decimal cuota = cuotaAlMillar(q, sa);
			if (cuota == null) { return ''; }
			minSa = minSa == null || sa < minSa ? sa : minSa;
			maxSa = sa > maxSa ? sa : maxSa;
			if (mejorCuota == null || cuota < mejorCuota) { mejorCuota = cuota; mejor = q; }
		}
		Boolean mismoTamano = maximo(tamano.values()) == minimo(tamano.values());
		if (mismoTamano && (maxSa - minSa) <= maxSa * 0.01) { return ''; }
		String txt = ' <b>Ojo:</b> ' + (mismoTamano ? 'las sumas aseguradas no son iguales' : 'no todas cotizaron ' + (unidad == 'ubicaciones' ? 'las mismas ubicaciones' : 'los mismos asegurados'))
			+ ', así que compara también la cuota al millar (prima neta por cada $1,000 asegurados): ';
		if (mejor == cot[0]) {
			return txt + esc((String) mejor.get('aseguradora')) + ' también es la más barata por peso asegurado ('
				+ mejorCuota.setScale(3, System.RoundingMode.HALF_UP) + ' &permil;).';
		}
		return txt + '<b style="color:#b85b00;">' + esc((String) mejor.get('aseguradora')) + '</b> cobra menos por cada peso asegurado ('
			+ mejorCuota.setScale(3, System.RoundingMode.HALF_UP) + ' &permil; contra '
			+ cuotaAlMillar(cot[0], sumaTotal.get(cot[0].get('id'))).setScale(3, System.RoundingMode.HALF_UP) + ' &permil; de '
			+ esc((String) cot[0].get('aseguradora')) + ').';
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Tabla de asegurados y prima por rango de edad (suma de categorías), una columna por aseguradora.
	 * @param cot: cotizaciones.
	 * @return HTML de la sección o vacío si ninguna trae tarifa por edad.
	 */
	private static String distribucionEdades(List<Map<String, Object>> cot) {
		List<String> rangos = new List<String>();
		List<Map<String, List<Decimal>>> porQuote = new List<Map<String, List<Decimal>>>();
		for (Map<String, Object> q : cot) {
			Map<String, List<Decimal>> m = new Map<String, List<Decimal>>();
			for (Object o : (List<Object>) q.get('categorias')) {
				for (Object t : (List<Object>) ((Map<String, Object>) o).get('tarifaEdades')) {
					Map<String, Object> r = (Map<String, Object>) t;
					String rango = texto(r.get('rango'));
					if (String.isBlank(rango)) { continue; }
					if (!rangos.contains(rango)) { rangos.add(rango); }
					if (!m.containsKey(rango)) { m.put(rango, new List<Decimal>{ 0, 0, 0 }); }
					List<Decimal> acc = m.get(rango);
					acc[0] += dec(r.get('hombres'));
					acc[1] += dec(r.get('mujeres'));
					Decimal prima = r.get('primaTotal') != null ? dec(r.get('primaTotal'))
						: dec(r.get('hombres')) * dec(r.get('primaHombre')) + dec(r.get('mujeres')) * dec(r.get('primaMujer'));
					acc[2] += prima;
				}
			}
			porQuote.add(m);
		}
		if (rangos.isEmpty()) { return ''; }
		rangos = ordenarRangos(rangos);
		String h = '<h3>Distribución por edad</h3><table><tr><th style="' + TH + 'width:12%;">Edad</th>';
		for (Map<String, Object> q : cot) { h += '<th style="' + TH + 'text-align:right;">' + esc((String) q.get('aseguradora')) + '</th>'; }
		h += '</tr>';
		for (String rango : rangos) {
			h += '<tr><th style="' + TH + '">' + esc(rango) + '</th>';
			for (Map<String, List<Decimal>> m : porQuote) {
				List<Decimal> v = m.get(rango);
				h += '<td style="' + TD_NUM + '">' + (v == null ? '—' : v[0].intValue() + ' H / ' + v[1].intValue() + ' M'
					+ (v[2] > 0 ? ' &middot; ' + moneda(v[2]) : '')) + '</td>';
			}
			h += '</tr>';
		}
		return h + '</table>';
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Ordena los rangos de edad por su edad inicial (ej. "0-19", "15-19", "20-24"); los que no empiezan con número van al final.
	 * @param rangos: rangos en el orden en que aparecieron.
	 * @return rangos ordenados.
	 */
	@TestVisible
	private static List<String> ordenarRangos(List<String> rangos) {
		List<String> llaves = new List<String>();
		Map<String, String> porLlave = new Map<String, String>();
		Integer i = 0;
		for (String r : rangos) {
			String inicio = r.trim().replaceAll('^(\\d+).*$', '$1');
			Integer edad = inicio.isNumeric() ? Integer.valueOf(inicio) : 999;
			Integer fin = r.replaceAll('^\\D*\\d+\\D+(\\d+).*$', '$1').isNumeric() ? Integer.valueOf(r.replaceAll('^\\D*\\d+\\D+(\\d+).*$', '$1')) : edad;
			String llave = String.valueOf(1000 + edad) + String.valueOf(1000 + fin) + String.valueOf(1000 + i++);
			llaves.add(llave);
			porLlave.put(llave, r);
		}
		llaves.sort();
		List<String> ordenados = new List<String>();
		for (String k : llaves) { ordenados.add(porLlave.get(k)); }
		return ordenados;
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Texto de recomendación: mejor prima, ahorro contra la segunda, avisos de asegurados y plan distintos.
	 * @param cot: cotizaciones en orden.
	 * @param base: prima de comparación por cotización.
	 * @param asegurados: asegurados por cotización.
	 * @param distintos: parámetros del plan que no coinciden entre aseguradoras.
	 * @param sinIva: true si se comparó sin IVA.
	 * @param unidad: "asegurados" o "ubicaciones".
	 * @return HTML del texto.
	 */
	private static String recomendacion(List<Map<String, Object>> cot, Map<Object, Decimal> base, Map<Object, Decimal> asegurados,
			Set<String> distintos, Boolean sinIva, String unidad) {
		String mejor = esc((String) cot[0].get('aseguradora'));
		Decimal b0 = base.get(cot[0].get('id'));
		if (cot.size() == 1) {
			return 'Se cotizó con ' + mejor + ': ' + moneda(b0) + ' por ' + asegurados.get(cot[0].get('id')).intValue()
				+ ' ' + unidad + '. Agrega las cotizaciones de otras aseguradoras para compararlas.';
		}
		Decimal b1 = base.get(cot[1].get('id'));
		String txt = '<b style="color:#b85b00;">' + mejor + '</b> ofrece la menor prima' + (sinIva ? ' (neta + derechos, sin IVA)' : '')
			+ ': ' + moneda(b0) + ', ' + moneda(b1 - b0) + ' menos que ' + esc((String) cot[1].get('aseguradora'))
			+ ' (' + porcentaje(b0 == 0 ? 0 : (b1 - b0) / b0 * 100) + ').';
		Decimal max = maximo(asegurados.values());
		if (asegurados.get(cot[0].get('id')) != max) {
			txt += ' Ojo: ' + mejor + ' cotizó ' + asegurados.get(cot[0].get('id')).intValue() + ' de ' + max.intValue() + ' ' + unidad + '.';
		}
		if (!distintos.isEmpty()) {
			List<String> lista = new List<String>(distintos);
			String cuales = lista.size() > 4
				? String.join(new List<String>{ lista[0], lista[1], lista[2], lista[3] }, ', ') + ' y ' + (lista.size() - 4) + ' más'
				: String.join(lista, ', ');
			txt += ' Los planes no son idénticos (' + esc(cuales)
				+ '): revisa el plan y las coberturas antes de decidir solo por precio.';
		}
		return txt;
	}

	// ============================================================
	// Utilidades
	// ============================================================

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Ordena las cotizaciones de menor a mayor prima de comparación.
	 * @param cot: cotizaciones.
	 * @param base: prima de comparación por cotización.
	 * @return lista ordenada.
	 */
	private static List<Map<String, Object>> ordenar(List<Map<String, Object>> cot, Map<Object, Decimal> base) {
		List<Map<String, Object>> res = new List<Map<String, Object>>();
		List<Map<String, Object>> pendientes = new List<Map<String, Object>>(cot);
		while (!pendientes.isEmpty()) {
			Integer idx = 0;
			for (Integer i = 1; i < pendientes.size(); i++) {
				if (base.get(pendientes[i].get('id')) < base.get(pendientes[idx].get('id'))) { idx = i; }
			}
			res.add(pendientes.remove(idx));
		}
		return res;
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valor mínimo de una lista de montos.
	 * @param l: lista.
	 * @return mínimo (0 si está vacía).
	 */
	private static Decimal minimo(List<Decimal> l) {
		Decimal m;
		for (Decimal x : l) { if (x != null && (m == null || x < m)) { m = x; } }
		return m == null ? 0 : m;
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valor máximo de una lista de montos.
	 * @param l: lista.
	 * @return máximo (0 si está vacía).
	 */
	private static Decimal maximo(List<Decimal> l) {
		Decimal m = 0;
		for (Decimal x : l) { if (x != null && x > m) { m = x; } }
		return m;
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Convierte un valor a Decimal (0 si viene vacío o no es número).
	 * @param v: valor.
	 * @return Decimal.
	 */
	private static Decimal dec(Object v) {
		if (v == null) { return 0; }
		if (v instanceof Decimal) { return (Decimal) v; }
		try { return Decimal.valueOf(String.valueOf(v)); } catch (Exception e) { return 0; }
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Texto de un valor ('' si viene vacío).
	 * @param v: valor.
	 * @return texto.
	 */
	private static String texto(Object v) {
		return v == null ? '' : String.valueOf(v).trim();
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Monto con formato "$1,234,567" (sin decimales), independiente del idioma del usuario.
	 * @param d: monto.
	 * @return texto con formato de moneda.
	 */
	@TestVisible
	private static String moneda(Decimal d) {
		if (d == null) { return '—'; }
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
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Porcentaje con un decimal como máximo.
	 * @param d: valor.
	 * @return texto con %.
	 */
	@TestVisible
	private static String porcentaje(Decimal d) {
		if (d == null) { return '—'; }
		Decimal r = d.setScale(1, System.RoundingMode.HALF_UP);
		return (r == r.setScale(0) ? String.valueOf(r.setScale(0)) : String.valueOf(r)) + '%';
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Fecha en formato dd/mm/aaaa.
	 * @param d: fecha.
	 * @return texto de la fecha.
	 */
	private static String fechaTxt(Date d) {
		if (d == null) { return ''; }
		return String.valueOf(d.day()).leftPad(2, '0') + '/' + String.valueOf(d.month()).leftPad(2, '0') + '/' + d.year();
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Escapa el texto para HTML.
	 * @param s: texto.
	 * @return texto escapado.
	 */
	private static String esc(String s) {
		return s == null ? '' : s.escapeHtml4();
	}
}
