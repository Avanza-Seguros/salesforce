/**
 * @creation date: 13/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Controlador de la página FlotillaComparativoPdf (renderAs PDF). Arma el comparativo de
 *               FLOTILLA para el cliente a partir de las cotizaciones guardadas (Quote + Inciso_Flotilla__c) de
 *               la oportunidad: resumen por aseguradora, prima por tipo de vehículo, coberturas y deducibles,
 *               detalle de prima por vehículo y recomendación. Mismo estilo que el comparativo individual.
 */
public with sharing class FlotillaComparativoPdfController {

	public String htmlBody { get; private set; }

	// Estilos (mismos colores y tipografía que el comparativo de cotizaciones individuales).
	private static final String TH = 'padding:4px 7px;border:1px solid #d9dee6;font-size:10.5px;text-align:left;background:#f4f6f9;';
	private static final String TH_MEJOR = 'padding:4px 7px;border:1px solid #d9dee6;font-size:10.5px;text-align:left;background:#fff3e0;';
	private static final String TD = 'padding:4px 7px;border:1px solid #eef1f5;font-size:10.5px;text-align:left;';
	private static final String TD_NUM = 'padding:4px 7px;border:1px solid #eef1f5;font-size:10.5px;text-align:right;';
	private static final String TD_NUM_MEJOR = 'padding:4px 7px;border:1px solid #eef1f5;font-size:10.5px;text-align:right;background:#e6f6e9;color:#194e31;font-weight:bold;';
	private static final String TD_TOTAL = 'padding:4px 7px;border:1px solid #d9dee6;border-top:2px solid #9aa5b5;font-size:10.5px;text-align:right;font-weight:bold;';
	private static final String TD_TOTAL_MEJOR = 'padding:4px 7px;border:1px solid #d9dee6;border-top:2px solid #9aa5b5;font-size:10.5px;text-align:right;font-weight:bold;background:#e6f6e9;color:#194e31;';
	private static final String ESTILO_PAGINA =
		'<style type="text/css">@page { size: letter landscape; margin: 12mm; } ' +
		'body { font-family: "Arial Unicode MS", Arial, sans-serif; font-size: 11px; color: #1c2433; } ' +
		'table { width: 100%; border-collapse: collapse; margin-bottom: 10px; } ' +
		'h2 { font-size: 18px; margin: 0 0 4px; } h3 { font-size: 13px; margin: 14px 0 6px; } ' +
		'.salto { page-break-before: always; } tr { page-break-inside: avoid; }</style>';

	/**
	 * @creation date: 13/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Constructor: lee la oportunidad del parámetro oppId y arma el HTML del comparativo.
	 */
	public FlotillaComparativoPdfController() {
		String oppId = ApexPages.currentPage() == null ? null : ApexPages.currentPage().getParameters().get('oppId');
		htmlBody = String.isBlank(oppId) ? '' : construirHtml((Id) oppId);
	}

	/**
	 * @creation date: 13/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: HTML completo del comparativo de flotilla de la oportunidad.
	 * @param opportunityId: oportunidad colectiva de Auto.
	 * @return documento HTML listo para renderizar como PDF ('' si no hay cotizaciones de flotilla).
	 */
	public static String construirHtml(Id opportunityId) {
		List<Opportunity> opps = [SELECT Id, Name, Account.Name FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
		if (opps.isEmpty()) { return ''; }
		Opportunity opp = opps[0];

		// Cotizaciones (columnas) en orden de prima total, la más baja primero.
		List<Map<String, Object>> cot = new List<Map<String, Object>>();
		for (Map<String, Object> q : FlotillaController.getFlotilla(opportunityId)) { cot.add(q); }
		if (cot.isEmpty()) { return ''; }
		cot = ordenarPorPrima(cot);
		Integer n = cot.size();

		// Totales por aseguradora y por tipo de vehículo; prima por vehículo.
		List<Decimal> totales = new List<Decimal>();
		List<Decimal> valores = new List<Decimal>();
		List<Integer> unidades = new List<Integer>();
		List<String> tipos = new List<String>();
		Map<String, List<Decimal>> primaTipo = new Map<String, List<Decimal>>();
		Map<String, List<Integer>> unidadesTipo = new Map<String, List<Integer>>();
		List<String> vehiculos = new List<String>();
		Map<String, Map<String, Object>> datosVehiculo = new Map<String, Map<String, Object>>();
		Map<String, List<Decimal>> primaVehiculo = new Map<String, List<Decimal>>();
		for (Integer c = 0; c < n; c++) {
			Decimal total = 0;
			Decimal valor = 0;
			List<Object> incisos = (List<Object>) cot[c].get('incisos');
			for (Object o : incisos) {
				Map<String, Object> i = (Map<String, Object>) o;
				Decimal prima = dec(i.get('prima'));
				total += prima;
				valor += dec(i.get('valor'));
				String tipo = String.isBlank((String) i.get('tipoVehiculo')) ? 'Sin tipo' : (String) i.get('tipoVehiculo');
				if (!primaTipo.containsKey(tipo)) {
					tipos.add(tipo);
					primaTipo.put(tipo, ceros(n));
					unidadesTipo.put(tipo, cerosInt(n));
				}
				primaTipo.get(tipo)[c] += prima;
				unidadesTipo.get(tipo)[c] += 1;
				String k = llaveVehiculo(i);
				if (!primaVehiculo.containsKey(k)) {
					vehiculos.add(k);
					datosVehiculo.put(k, i);
					primaVehiculo.put(k, nulos(n));
				}
				primaVehiculo.get(k)[c] = prima;
			}
			totales.add(total);
			valores.add(valor);
			unidades.add(incisos.size());
		}
		Decimal mejor = totales[0];

		// Columna de conceptos de 200px y 170px por aseguradora; con 4 o más se usa todo el ancho de la hoja.
		String ancho = n >= 4 ? '100%' : (200 + n * 170) + 'px';
		String h = '<html><head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>' + ESTILO_PAGINA
			+ '<style type="text/css">table.resumen { width: ' + ancho + '; table-layout: fixed; }</style></head><body>';

		// ---------- Encabezado ----------
		Map<String, Object> primera = cot[0];
		String vigencia = primera.get('vigenciaDesde') != null
			? fechaTxt((Date) primera.get('vigenciaDesde')) + ' – ' + fechaTxt((Date) primera.get('vigenciaHasta')) : '';
		h += '<h2>Comparativo de Seguro de Flotilla</h2>';
		h += '<p style="font-size:11px;color:#667;margin:0 0 4px;">' + esc(opp.Account != null ? opp.Account.Name : opp.Name)
			+ ' &middot; ' + esc(opp.Name) + (String.isNotBlank(vigencia) ? ' &middot; Vigencia ' + esc(vigencia) : '') + '</p>';
		h += '<p style="font-size:11px;color:#b85b00;margin:0 0 12px;">' + n + (n == 1 ? ' aseguradora cotizada' : ' aseguradoras comparadas')
			+ ' &middot; ' + maximo(unidades) + ' unidades &middot; Cotizado por Avanza Seguro &middot; ' + fechaTxt(Date.today()) + '</p>';

		// ---------- Resumen por aseguradora ----------
		h += '<h3>Resumen por aseguradora</h3><table class="resumen">';
		h += encabezadoAseguradoras('Concepto', cot, totales, mejor);
		h += '<tr><th style="' + TH + '">Prima total</th>';
		for (Integer c = 0; c < n; c++) { h += '<td style="' + (totales[c] == mejor && n > 1 ? TD_NUM_MEJOR : TD_NUM) + '">' + moneda(totales[c]) + '</td>'; }
		h += '</tr><tr><th style="' + TH + '">Diferencia vs. la mejor</th>';
		for (Integer c = 0; c < n; c++) {
			Decimal dif = totales[c] - mejor;
			String txt = dif == 0 ? '—' : '+' + moneda(dif) + ' (+' + porcentaje(mejor == 0 ? 0 : dif / mejor * 100) + ')';
			h += '<td style="' + TD_NUM + '">' + txt + '</td>';
		}
		h += '</tr>' + filaTexto('Unidades cotizadas', cot, unidades, null);
		h += '<tr><th style="' + TH + '">Valor asegurado total</th>';
		for (Integer c = 0; c < n; c++) { h += '<td style="' + TD_NUM + '">' + moneda(valores[c]) + '</td>'; }
		h += '</tr><tr><th style="' + TH + '">Prima promedio por unidad</th>';
		for (Integer c = 0; c < n; c++) { h += '<td style="' + TD_NUM + '">' + (unidades[c] == 0 ? '—' : moneda(totales[c] / unidades[c])) + '</td>'; }
		h += '</tr><tr><th style="' + TH + '">Forma de pago</th>';
		for (Integer c = 0; c < n; c++) { h += '<td style="' + TD_NUM + '">' + esc(texto(cot[c].get('formaPago'), '—')) + '</td>'; }
		h += '</tr><tr><th style="' + TH + '">Vigencia</th>';
		for (Integer c = 0; c < n; c++) {
			Object d = cot[c].get('vigenciaDesde');
			h += '<td style="' + TD_NUM + '">' + (d == null ? '—' : fechaTxt((Date) d) + ' – ' + fechaTxt((Date) cot[c].get('vigenciaHasta'))) + '</td>';
		}
		h += '</tr></table>';

		// ---------- Prima por tipo de vehículo ----------
		h += '<h3>Prima por tipo de vehículo</h3><table class="resumen">';
		h += encabezadoAseguradoras('Tipo de vehículo', cot, totales, mejor);
		for (String t : tipos) {
			List<Decimal> p = primaTipo.get(t);
			Decimal min = minimoValido(p, unidadesTipo.get(t));
			h += '<tr><th style="' + TH + '">' + esc(t) + '</th>';
			for (Integer c = 0; c < n; c++) {
				Integer u = unidadesTipo.get(t)[c];
				Boolean esMejor = n > 1 && u > 0 && p[c] == min;
				h += '<td style="' + (esMejor ? TD_NUM_MEJOR : TD_NUM) + '">' + (u == 0 ? '—' : moneda(p[c])
					+ '<br/><span style="font-size:9px;color:#667;font-weight:normal;">' + u + (u == 1 ? ' unidad' : ' unidades') + '</span>') + '</td>';
			}
			h += '</tr>';
		}
		h += '<tr><th style="' + TH + '">Total</th>';
		for (Integer c = 0; c < n; c++) { h += '<td style="' + (totales[c] == mejor && n > 1 ? TD_TOTAL_MEJOR : TD_TOTAL) + '">' + moneda(totales[c]) + '</td>'; }
		h += '</tr></table>';

		// ---------- Coberturas y deducibles ----------
		h += '<h3>Coberturas y deducibles</h3><table class="resumen">';
		h += encabezadoAseguradoras('Cobertura', cot, totales, mejor);
		h += filaCobertura('Paquete', cot, 'paquete', false, false);
		h += filaCobertura('Tipo de valor', cot, 'tipoValor', false, false);
		h += filaCobertura('Deducible daños materiales', cot, 'dedDM', false, true);
		h += filaCobertura('Deducible robo total', cot, 'dedRT', false, true);
		h += filaCobertura('Responsabilidad civil', cot, 'rc', true, false);
		h += filaCobertura('Gastos médicos ocupantes', cot, 'gm', true, false);
		h += filaCobertura('Muerte del conductor', cot, 'muerte', true, false);
		h += '</table>';
		h += '<p style="font-size:9.5px;color:#667;margin:0;">Cuando una cobertura cambia según la unidad (por ejemplo, RC de pick-ups de carga vs. automóviles) se muestra el rango.</p>';

		// ---------- Detalle por vehículo ----------
		h += '<h3>Prima por vehículo</h3><table>';
		h += '<tr><th style="' + TH + 'width:3%;">#</th><th style="' + TH + '">Vehículo</th><th style="' + TH + 'width:11%;">Tipo</th>'
			+ '<th style="' + TH + 'width:9%;text-align:right;">Valor</th>';
		for (Integer c = 0; c < n; c++) { h += '<th style="' + TH + 'text-align:right;">' + esc((String) cot[c].get('aseguradora')) + '</th>'; }
		h += '</tr>';
		Integer num = 0;
		for (String k : vehiculos) {
			num++;
			Map<String, Object> v = datosVehiculo.get(k);
			List<Decimal> p = primaVehiculo.get(k);
			Decimal min = null;
			Integer validos = 0;
			for (Decimal x : p) { if (x != null && x > 0) { validos++; min = (min == null || x < min) ? x : min; } }
			String detalle = (v.get('modelo') != null ? String.valueOf(((Decimal) v.get('modelo')).intValue()) : '')
				+ (String.isNotBlank((String) v.get('serie')) ? ' &middot; ' + esc((String) v.get('serie')) : '');
			h += '<tr><td style="' + TD + '">' + num + '</td><td style="' + TD + '">' + esc(texto(v.get('descripcion'), ''))
				+ '<br/><span style="font-size:9px;color:#667;">' + detalle + '</span></td>'
				+ '<td style="' + TD + '">' + esc(texto(v.get('tipoVehiculo'), '')) + '</td>'
				+ '<td style="' + TD_NUM + '">' + moneda(dec(v.get('valor'))) + '</td>';
			for (Integer c = 0; c < n; c++) {
				Boolean esMejor = validos > 1 && p[c] != null && p[c] == min;
				h += '<td style="' + (esMejor ? TD_NUM_MEJOR : TD_NUM) + '">' + (p[c] == null ? 'No cotizado' : moneda(p[c])) + '</td>';
			}
			h += '</tr>';
		}
		h += '</table>';

		// ---------- Recomendación ----------
		h += '<h3>Resumen y recomendación</h3>';
		h += '<p style="margin:0;padding:10px;background:#f4f6f9;border:1px solid #e6e9ef;font-size:11px;">' + recomendacion(cot, totales, tipos, primaTipo, unidadesTipo, unidades) + '</p>';
		h += '<p style="font-size:9.5px;color:#667;margin:10px 0 0;">Documento informativo elaborado con las cotizaciones de cada aseguradora. '
			+ 'Las primas pueden variar por inexactitud en las características de las unidades; las condiciones finales (sumas aseguradas, '
			+ 'deducibles y coberturas) se definen en la póliza. Varias aseguradoras condicionan la propuesta a asegurar el total del parque vehicular.</p>';
		h += '</body></html>';
		return h;
	}

	// ============================================================
	// Secciones
	// ============================================================

	/**
	 * @creation date: 13/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Renglón de encabezado con una columna por aseguradora (la de mejor prima resaltada).
	 * @param primera: título de la primera columna.
	 * @param cot: cotizaciones en orden de prima.
	 * @param totales: prima total por cotización.
	 * @param mejor: prima total más baja.
	 * @return HTML del renglón.
	 */
	private static String encabezadoAseguradoras(String primera, List<Map<String, Object>> cot, List<Decimal> totales, Decimal mejor) {
		String h = '<tr><th style="' + TH + 'width:200px;">' + esc(primera) + '</th>';
		for (Integer c = 0; c < cot.size(); c++) {
			Boolean esMejor = cot.size() > 1 && totales[c] == mejor;
			h += '<th style="' + (esMejor ? TH_MEJOR : TH) + 'text-align:right;">' + esc((String) cot[c].get('aseguradora'))
				+ (esMejor ? '<br/><span style="font-size:9px;color:#b85b00;">Mejor prima</span>' : '') + '</th>';
		}
		return h + '</tr>';
	}

	/**
	 * @creation date: 13/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Renglón con un número entero por aseguradora.
	 * @param etiqueta: texto de la primera columna.
	 * @param cot: cotizaciones.
	 * @param valores: valor por cotización.
	 * @param sufijo: texto opcional después del número.
	 * @return HTML del renglón.
	 */
	private static String filaTexto(String etiqueta, List<Map<String, Object>> cot, List<Integer> valores, String sufijo) {
		String h = '<tr><th style="' + TH + '">' + esc(etiqueta) + '</th>';
		for (Integer c = 0; c < cot.size(); c++) { h += '<td style="' + TD_NUM + '">' + valores[c] + (sufijo == null ? '' : sufijo) + '</td>'; }
		return h + '</tr>';
	}

	/**
	 * @creation date: 13/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Renglón de una cobertura: valor único, rango (montos/porcentajes) o lista de textos por aseguradora. Se omite si ninguna lo trae.
	 * @param etiqueta: nombre de la cobertura.
	 * @param cot: cotizaciones.
	 * @param campo: clave del inciso (paquete, dedDM, rc...).
	 * @param esMonto: true si es monto en pesos.
	 * @param esPct: true si es porcentaje.
	 * @return HTML del renglón o vacío.
	 */
	private static String filaCobertura(String etiqueta, List<Map<String, Object>> cot, String campo, Boolean esMonto, Boolean esPct) {
		String h = '<tr><th style="' + TH + '">' + esc(etiqueta) + '</th>';
		Boolean hayDato = false;
		String celdas = '';
		for (Map<String, Object> q : cot) {
			Decimal min = null;
			Decimal max = null;
			Set<String> textos = new Set<String>();
			for (Object o : (List<Object>) q.get('incisos')) {
				Object v = ((Map<String, Object>) o).get(campo);
				if (v == null || String.valueOf(v).trim() == '') { continue; }
				if (esMonto || esPct) {
					Decimal d = dec(v);
					if (d == 0) { continue; }
					min = min == null || d < min ? d : min;
					max = max == null || d > max ? d : max;
				} else {
					textos.add(String.valueOf(v).trim().toUpperCase());
				}
			}
			String txt;
			if (esMonto || esPct) {
				if (min == null) { txt = '—'; }
				else {
					String a = esPct ? porcentaje(min) : moneda(min);
					String b = esPct ? porcentaje(max) : moneda(max);
					txt = min == max ? a : a + ' – ' + b;
					hayDato = true;
				}
			} else {
				txt = textos.isEmpty() ? '—' : String.join(new List<String>(textos), ' / ');
				hayDato = hayDato || !textos.isEmpty();
			}
			celdas += '<td style="' + TD_NUM + '">' + esc(txt) + '</td>';
		}
		return hayDato ? h + celdas + '</tr>' : '';
	}

	/**
	 * @creation date: 13/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Texto de recomendación: aseguradora con menor prima total, ahorro contra la segunda y tipos de vehículo donde otra es más económica.
	 * @param cot: cotizaciones en orden de prima.
	 * @param totales: prima total por cotización.
	 * @param tipos: tipos de vehículo.
	 * @param primaTipo: prima por tipo y cotización.
	 * @param unidadesTipo: unidades por tipo y cotización.
	 * @param unidades: unidades por cotización.
	 * @return HTML del texto.
	 */
	private static String recomendacion(List<Map<String, Object>> cot, List<Decimal> totales, List<String> tipos,
			Map<String, List<Decimal>> primaTipo, Map<String, List<Integer>> unidadesTipo, List<Integer> unidades) {
		String mejor = (String) cot[0].get('aseguradora');
		if (cot.size() == 1) {
			return 'Se cotizó la flotilla con ' + esc(mejor) + ': prima total de ' + moneda(totales[0]) + ' por ' + unidades[0]
				+ ' unidades. Agrega las cotizaciones de otras aseguradoras para compararlas.';
		}
		String txt = '<b style="color:#b85b00;">' + esc(mejor) + '</b> ofrece la menor prima total de la flotilla: ' + moneda(totales[0])
			+ ', ' + moneda(totales[1] - totales[0]) + ' menos que ' + esc((String) cot[1].get('aseguradora'))
			+ ' (' + porcentaje(totales[0] == 0 ? 0 : (totales[1] - totales[0]) / totales[0] * 100) + ').';
		if (unidades[0] != maximo(unidades)) {
			txt += ' Ojo: ' + esc(mejor) + ' cotizó ' + unidades[0] + ' de ' + maximo(unidades) + ' unidades; compara contra el mismo parque vehicular.';
		}
		List<String> notas = new List<String>();
		for (String t : tipos) {
			List<Decimal> p = primaTipo.get(t);
			Decimal min = minimoValido(p, unidadesTipo.get(t));
			for (Integer c = 1; c < cot.size(); c++) {
				if (unidadesTipo.get(t)[c] > 0 && p[c] == min && unidadesTipo.get(t)[0] > 0 && p[0] > min) {
					notas.add(esc((String) cot[c].get('aseguradora')) + ' es más económica en ' + esc(t.toLowerCase())
						+ ' (' + moneda(p[c]) + ' vs. ' + moneda(p[0]) + ')');
				}
			}
		}
		if (!notas.isEmpty()) {
			txt += ' Por tipo de vehículo: ' + String.join(notas, '; ') + '. Antes de dividir la flotilla entre aseguradoras, '
				+ 'confirma que lo permitan (normalmente la propuesta se condiciona a asegurar todas las unidades).';
		}
		return txt;
	}

	// ============================================================
	// Utilidades
	// ============================================================

	/**
	 * @creation date: 13/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Ordena las cotizaciones de menor a mayor prima total.
	 * @param cot: cotizaciones.
	 * @return lista ordenada.
	 */
	private static List<Map<String, Object>> ordenarPorPrima(List<Map<String, Object>> cot) {
		List<Map<String, Object>> res = new List<Map<String, Object>>();
		List<Map<String, Object>> pendientes = new List<Map<String, Object>>(cot);
		while (!pendientes.isEmpty()) {
			Integer idx = 0;
			for (Integer i = 1; i < pendientes.size(); i++) {
				if (totalDe(pendientes[i]) < totalDe(pendientes[idx])) { idx = i; }
			}
			res.add(pendientes.remove(idx));
		}
		return res;
	}

	/**
	 * @creation date: 13/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Prima total de una cotización (suma de incisos).
	 * @param q: cotización.
	 * @return prima total.
	 */
	private static Decimal totalDe(Map<String, Object> q) {
		Decimal t = 0;
		for (Object o : (List<Object>) q.get('incisos')) { t += dec(((Map<String, Object>) o).get('prima')); }
		return t;
	}

	/**
	 * @creation date: 13/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Llave para comparar el mismo vehículo entre aseguradoras: serie o descripción + modelo.
	 * @param i: inciso.
	 * @return llave del vehículo.
	 */
	private static String llaveVehiculo(Map<String, Object> i) {
		String serie = (String) i.get('serie');
		if (String.isNotBlank(serie)) { return 'S' + serie.toUpperCase(); }
		return 'D' + texto(i.get('descripcion'), '').toLowerCase().normalizeSpace() + '|' + texto(i.get('modelo'), '');
	}

	/**
	 * @creation date: 13/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Prima mínima entre las aseguradoras que sí cotizaron ese tipo de vehículo.
	 * @param p: prima por cotización.
	 * @param u: unidades por cotización.
	 * @return prima mínima o null.
	 */
	private static Decimal minimoValido(List<Decimal> p, List<Integer> u) {
		Decimal min = null;
		for (Integer c = 0; c < p.size(); c++) {
			if (u[c] > 0 && (min == null || p[c] < min)) { min = p[c]; }
		}
		return min;
	}

	/**
	 * @creation date: 13/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valor máximo de una lista de enteros.
	 * @param l: lista.
	 * @return máximo (0 si está vacía).
	 */
	private static Integer maximo(List<Integer> l) {
		Integer m = 0;
		for (Integer x : l) { m = Math.max(m, x); }
		return m;
	}

	/**
	 * @creation date: 13/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Lista de n ceros (Decimal).
	 * @param n: tamaño.
	 * @return lista.
	 */
	private static List<Decimal> ceros(Integer n) {
		List<Decimal> l = new List<Decimal>();
		for (Integer i = 0; i < n; i++) { l.add(0); }
		return l;
	}

	/**
	 * @creation date: 13/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Lista de n ceros (Integer).
	 * @param n: tamaño.
	 * @return lista.
	 */
	private static List<Integer> cerosInt(Integer n) {
		List<Integer> l = new List<Integer>();
		for (Integer i = 0; i < n; i++) { l.add(0); }
		return l;
	}

	/**
	 * @creation date: 13/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Lista de n valores nulos.
	 * @param n: tamaño.
	 * @return lista.
	 */
	private static List<Decimal> nulos(Integer n) {
		List<Decimal> l = new List<Decimal>();
		for (Integer i = 0; i < n; i++) { l.add(null); }
		return l;
	}

	/**
	 * @creation date: 13/10/2026
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
	 * @creation date: 13/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Texto de un valor o el texto de respaldo si viene vacío.
	 * @param v: valor.
	 * @param vacio: texto de respaldo.
	 * @return texto.
	 */
	private static String texto(Object v, String vacio) {
		return v == null || String.isBlank(String.valueOf(v)) ? vacio : String.valueOf(v);
	}

	/**
	 * @creation date: 13/10/2026
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
	 * @creation date: 13/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Porcentaje con un decimal como máximo ("5%", "4.4%").
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
	 * @creation date: 13/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Fecha en formato dd/mm/aaaa.
	 * @param d: fecha.
	 * @return texto de la fecha.
	 */
	@TestVisible
	private static String fechaTxt(Date d) {
		if (d == null) { return ''; }
		return String.valueOf(d.day()).leftPad(2, '0') + '/' + String.valueOf(d.month()).leftPad(2, '0') + '/' + d.year();
	}

	/**
	 * @creation date: 13/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Escapa el texto para HTML.
	 * @param s: texto.
	 * @return texto escapado.
	 */
	private static String esc(String s) {
		return s == null ? '' : s.escapeHtml4();
	}
}
