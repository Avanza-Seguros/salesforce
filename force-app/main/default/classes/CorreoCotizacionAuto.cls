/**
 *   @name: CorreoCotizacionAuto
 *   @version: 1.0
 *   @creation date: 24/11/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Correo de cotización de Auto (guía «Cotización Auto» aprobada el 21/11/2026): llena la plantilla
 *                 Cotizacion_Auto_Comparativo (dos o más cotizaciones) o Cotizacion_Auto_Una_Opcion (una sola) con los
 *                 datos de la oportunidad. El mismo correo va al cliente y al agente. Los marcadores {{...}} que están
 *                 dentro de una liga (mailto: o wa.me) se codifican para URL; los demás, para HTML. Después de enviarlo
 *                 deja al agente una tarea de seguimiento a 3 días hábiles.
 */
public with sharing class CorreoCotizacionAuto {

	public static final String RESPUESTA = 'cotizaciones@avanzaseguro.com';
	private static final String PLANTILLA_VARIAS = 'Cotizacion_Auto_Comparativo';
	private static final String PLANTILLA_UNA = 'Cotizacion_Auto_Una_Opcion';
	private static final String WHATSAPP_AVANZA = '523335754472';
	private static final String TELEFONO_AVANZA = '33 3575 4472';
	private static final String ASUNTO_TAREA = 'Dar seguimiento a la cotización de Auto enviada';
	private static final String FUENTE = 'font-family:Arial, Helvetica, sans-serif;';
	private static final Set<String> IMAGENES = new Set<String>{ 'Correo_Logo_Avanza', 'Correo_Icono_Correo', 'Correo_Icono_WhatsApp' };

	/**
	 * @creation date: 24/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma el correo de una oportunidad de Auto individual.
	 * @param registroId: Oportunidad
	 * @return Asunto y cuerpo; null si no es una oportunidad de Auto, es empresarial (flotilla), no tiene cotizaciones con
	 *         prima o no existe la plantilla (entonces se usa el correo de los demás ramos)
	 */
	public static CorreoOportunidadIA.Correo armar(Id registroId) {
		if (registroId == null || registroId.getSObjectType() != Opportunity.SObjectType) { return null; }
		Opportunity o = [
			SELECT Name, Ramo__c, Tipo_Contratacion__c, Description, Descripcion_del_vehiculo__c, Producer__c, Account.Name,
				Account.IsPersonAccount, Account.FirstName, Contacto__r.Name, Contacto__r.FirstName, Owner.Name, Owner.Email, OwnerId
			FROM Opportunity WHERE Id = :registroId LIMIT 1
		];
		if (o.Ramo__c == null || !o.Ramo__c.toLowerCase().contains('auto') || o.Tipo_Contratacion__c == 'Colectiva') { return null; }
		List<Map<String, Object>> opciones = opcionesDe(registroId);
		if (opciones.isEmpty()) { return null; }
		List<EmailTemplate> tpls = [
			SELECT Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :(opciones.size() > 1 ? PLANTILLA_VARIAS : PLANTILLA_UNA) LIMIT 1
		];
		if (tpls.isEmpty() || String.isBlank(tpls[0].HtmlValue)) { return null; }

		Agente a = agenteDe(o);
		Map<String, String> imagenes = new Imagenes().ligas();
		String vehiculo = vehiculoDe(o);
		Map<String, Object> principal = opciones[0];
		Map<String, String> datos = new Map<String, String>{
			'NOMBRE' => nombreCliente(o),
			'VEHICULO' => vehiculo == null ? 'auto' : vehiculo,
			'AGENTE' => a.nombre,
			'CORREO_AGENTE' => a.correo == null ? '' : a.correo,
			'TELEFONO_AGENTE' => a.telefono,
			'WHATSAPP_AGENTE' => a.whatsapp,
			'ASEGURADORA' => (String) principal.get('aseguradora'),
			'PLAN' => (String) principal.get('plan'),
			'PRIMA' => (String) principal.get('prima') + ' MXN',
			'PRIMA_DIARIA' => (String) principal.get('primaDiaria'),
			'SUMA' => principal.get('suma') == null ? 'Ver PDF adjunto' : (String) principal.get('suma') + ' MXN',
			'FORMA_PAGO' => principal.get('formaPago') == null ? 'Ver PDF adjunto' : (String) principal.get('formaPago'),
			'MOTIVO' => (String) principal.get('motivo')
		};
		// Bloques que ya van en HTML.
		Map<String, String> bloques = new Map<String, String>{
			'ENCABEZADO' => logoEncabezado(a.logo, imagenes),
			'LOGO_AVANZA' => logoAvanza(imagenes, 40, 18),
			'LOGO_ASEGURADORA' => logoAseguradora(principal, 44, 8)
		};
		String html = tpls[0].HtmlValue;
		String asunto = tpls[0].Subject;
		if (vehiculo == null) {
			html = html.replace('seguro para el {{VEHICULO}}', 'seguro de {{VEHICULO}}')
				.replace('seguro%20para%20el%20{{VEHICULO}}', 'seguro%20de%20{{VEHICULO}}');
			asunto = asunto.replace('seguro para el {{VEHICULO}}', 'seguro de {{VEHICULO}}');
		}
		if (String.isBlank(a.correo)) { html = html.replace('cc={{CORREO_AGENTE}}&amp;', '').replace('cc={{CORREO_AGENTE}}&', ''); }
		if (String.isBlank(a.correo)) { html = html.replace(' ({{CORREO_AGENTE}})', ''); }
		if (!algunPlanAmplio(opciones)) { html = sinBloque(html, 'PLAN_AMPLIO'); }

		CorreoOportunidadIA.Correo c = new CorreoOportunidadIA.Correo();
		c.asunto = asunto;
		for (String k : datos.keySet()) { c.asunto = c.asunto.replace('{{' + k + '}}', datos.get(k) == null ? '' : datos.get(k)); }
		c.asunto = c.asunto.left(200);
		String filas = '';
		if (opciones.size() > 1) {
			for (Map<String, Object> op : opciones) { filas += fila(op, a, datos, c.asunto, imagenes); }
		}
		bloques.put('FILAS', filas);
		html = llenar(html, datos, bloques);
		c.cuerpo = html;
		c.html = html;
		return c;
	}

	// Cotizaciones con prima: la recomendada primero y las demás de menor a mayor prima.
	private static List<Map<String, Object>> opcionesDe(Id oportunidadId) {
		List<Map<String, Object>> lista = new List<Map<String, Object>>();
		for (Quote q : [
			SELECT Name, Plan__c, Aseguradora__r.Name, Aseguradora__r.Logo_URL__c, PrimaAnual__c, Prima_Total__c, SumaAsegurada__c, DeducibleDanos_Pct__c,
				toLabel(Frecuencia_de_prima__c)
			FROM Quote WHERE OpportunityId = :oportunidadId AND (PrimaAnual__c > 0 OR Prima_Total__c > 0) ORDER BY PrimaAnual__c ASC LIMIT 20
		]) {
			String plan = planDe(q);
			// Las capturadas a mano pueden traer solo la prima total.
			Decimal anual = q.PrimaAnual__c != null && q.PrimaAnual__c > 0 ? q.PrimaAnual__c : q.Prima_Total__c;
			Integer lugar = 0;
			while (lugar < lista.size() && (Decimal) lista[lugar].get('primaAnual') <= anual) { lugar++; }
			Map<String, Object> op = new Map<String, Object>{
				'aseguradora' => String.isNotBlank(q.Aseguradora__r?.Name) ? q.Aseguradora__r.Name : q.Name.substringBefore(' - '),
				'plan' => plan,
				'logo' => q.Aseguradora__r?.Logo_URL__c,
				'primaAnual' => anual,
				'sumaAsegurada' => q.SumaAsegurada__c,
				'prima' => moneda(anual),
				'primaDiaria' => moneda(anual / 365),
				'suma' => q.SumaAsegurada__c == null || q.SumaAsegurada__c <= 0 ? null : moneda(q.SumaAsegurada__c),
				'formaPago' => q.Frecuencia_de_prima__c,
				'deducible' => q.DeducibleDanos_Pct__c
			};
			if (lugar == lista.size()) { lista.add(op); } else { lista.add(lugar, op); }
		}
		// La misma recomendación que en los demás correos de cotización.
		CorreoOportunidadIA.marcarRecomendada(lista);
		List<Map<String, Object>> orden = new List<Map<String, Object>>();
		for (Map<String, Object> op : lista) {
			if (op.get('recomendada') == true) {
				op.put('motivo', motivo(op));
				orden.add(op);
			}
		}
		for (Map<String, Object> op : lista) { if (op.get('recomendada') != true) { orden.add(op); } }
		return orden;
	}

	// «Es la opción con la prima más baja y mantiene cobertura amplia con deducible de daños del 5%.»
	private static String motivo(Map<String, Object> op) {
		String m = ((String) op.get('motivoRecomendacion')).removeEnd('.');
		Decimal ded = (Decimal) op.get('deducible');
		String deducible = ded == null || ded <= 0 ? '' : ' con deducible de daños del ' + ded.stripTrailingZeros().toPlainString() + '%';
		if (esAmplio((String) op.get('plan'))) { return m + ' y mantiene cobertura amplia' + deducible + '.'; }
		return m + (deducible == '' ? '' : ',' + deducible) + '.';
	}

	private static Boolean esAmplio(String plan) {
		return plan != null && plan.toLowerCase().contains('ampli');
	}

	// El recuadro «Qué te cubre un plan amplio» sobra cuando todas las opciones son limitadas, básicas o de RC.
	private static Boolean algunPlanAmplio(List<Map<String, Object>> opciones) {
		for (Map<String, Object> op : opciones) {
			if (!Pattern.compile('(?i)limitad|b[aá]sic|\\brc\\b|responsabilidad').matcher((String) op.get('plan')).find()) { return true; }
		}
		return false;
	}

	// Plan de la cotización; si viene todo en mayúsculas, como oración («AMPLIA» -> «Amplia», «HDI EN MI AUTO» -> «HDI en mi auto»).
	@TestVisible
	private static String planDe(Quote q) {
		String plan = String.isNotBlank(q.Plan__c) ? q.Plan__c.trim() : (q.Name.contains(' - ') ? q.Name.substringAfter(' - ').trim() : 'Plan cotizado');
		if (!plan.equals(plan.toUpperCase())) { return plan; }
		Set<String> siglas = new Set<String>{ 'HDI', 'GNP', 'AXA', 'RC', 'VIP', 'GMX', 'BX' };
		List<String> palabras = new List<String>();
		for (String p : plan.split('\\s+')) { palabras.add(siglas.contains(p) ? p : p.toLowerCase()); }
		String r = String.join(palabras, ' ');
		return r.left(1).toUpperCase() + r.substring(1);
	}

	/** Datos del agente que muestra el correo. */
	private class Agente {
		String nombre;
		String correo;
		String telefono;
		String whatsapp;
		String logo;
	}

	// El agente es el Producer de la oportunidad; si no tiene, el propietario. El celular sale de su contacto, de su usuario, de
	// su cuenta o del catálogo de agentes; sin celular se usa el de Avanza.
	private static Agente agenteDe(Opportunity o) {
		Agente a = new Agente();
		List<String> celulares = new List<String>();
		if (o.Producer__c != null) {
			for (Producer p : [
				SELECT Name, Logo_URL__c, Contact.MobilePhone, Contact.Phone, InternalUser.MobilePhone, InternalUser.Phone, Account.Phone
				FROM Producer WHERE Id = :o.Producer__c LIMIT 1
			]) {
				a.nombre = p.Name;
				a.logo = p.Logo_URL__c;
				celulares.addAll(new List<String>{ p.Contact?.MobilePhone, p.InternalUser?.MobilePhone, p.Contact?.Phone, p.InternalUser?.Phone, p.Account?.Phone });
			}
			a.correo = OpportunityController.getProducerEmail(o.Producer__c);
			if (a.nombre != null) {
				for (Agente__c g : [SELECT Telefono__c FROM Agente__c WHERE Name = :a.nombre AND Telefono__c != null LIMIT 1]) { celulares.add(g.Telefono__c); }
			}
		}
		if (a.nombre == null) {
			a.nombre = o.Owner.Name;
			a.correo = o.Owner.Email;
			for (User u : [SELECT MobilePhone, Phone FROM User WHERE Id = :o.OwnerId LIMIT 1]) { celulares.addAll(new List<String>{ u.MobilePhone, u.Phone }); }
		}
		a.whatsapp = WHATSAPP_AVANZA;
		a.telefono = TELEFONO_AVANZA;
		for (String c : celulares) {
			String w = whatsapp(c);
			if (w == null) { continue; }
			a.whatsapp = w;
			String diez = w.right(10);
			a.telefono = diez.left(2) + ' ' + diez.substring(2, 6) + ' ' + diez.substring(6);
			break;
		}
		return a;
	}

	// Solo dígitos con lada 52 («+52 1 33 1234-5678» -> 523312345678); null si no es un teléfono de 10 dígitos.
	@TestVisible
	private static String whatsapp(String telefono) {
		String d = telefono == null ? '' : telefono.replaceAll('[^0-9]', '');
		if (d.length() == 10) { return '52' + d; }
		if (d.length() == 12 && d.startsWith('52')) { return d; }
		return d.length() == 13 && d.startsWith('521') ? '52' + d.right(10) : null;
	}

	// Nombre de pila del cliente; el de una empresa sin contacto es su razón social.
	@TestVisible
	private static String nombreCliente(Opportunity o) {
		String cuenta = o.Account == null || o.Account.Name == null ? o.Name : o.Account.Name;
		if (o.Contacto__r != null) {
			String n = String.isNotBlank(o.Contacto__r.FirstName) ? o.Contacto__r.FirstName : o.Contacto__r.Name;
			return primera(n);
		}
		if (o.Account?.IsPersonAccount == true) { return primera(String.isNotBlank(o.Account.FirstName) ? o.Account.FirstName : cuenta); }
		return cuenta.startsWithIgnoreCase('Familia ') ? primera(cuenta.substring(8)) : cuenta;
	}

	private static String primera(String nombre) {
		String p = nombre.trim().split('\\s+')[0].toLowerCase();
		return p.left(1).toUpperCase() + p.substring(1);
	}

	/**
	 * @creation date: 24/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Vehículo cotizado en pocas palabras («Suzuki Swift GLX 2023»): marca, modelo y año del detalle del ramo que
	 *               guarda Crear Oportunidad en la descripción.
	 * @param o: Oportunidad con Description y Descripcion_del_vehiculo__c
	 * @return Vehículo; null si la oportunidad no lo trae
	 */
	@TestVisible
	private static String vehiculoDe(Opportunity o) {
		String texto = o.Description == null ? '' : o.Description;
		Integer ini = texto.lastIndexOf('Detalle del ramo');
		Map<String, String> d = new Map<String, String>();
		if (ini >= 0) {
			for (String linea : texto.substring(ini).split('\n')) {
				Matcher m = Pattern.compile('^\\W*([A-Za-z_]+__c)\\s*:\\s*(.+)$').matcher(linea.trim());
				if (m.matches()) { d.put(m.group(1).toLowerCase(), m.group(2).trim()); }
			}
		}
		String marca = d.get('marca__c');
		String anio = d.get('anio__c') != null ? d.get('anio__c') : d.get('modelo__c');
		String descripcion = d.get('descripcion_completa__c') != null ? d.get('descripcion_completa__c') : o.Descripcion_del_vehiculo__c;
		List<String> partes = new List<String>();
		Set<String> vistas = new Set<String>();
		if (String.isNotBlank(marca)) {
			partes.add(titulo(marca));
			for (String w : marca.toLowerCase().split('\\s+')) { vistas.add(w); }
		}
		Integer modelo = 0;
		for (String w : descripcion == null ? new List<String>() : descripcion.split('\\s+')) {
			String limpia = w.removeEnd(',').removeEnd('.');
			if (limpia == '') { continue; }
			Boolean esMarca = marca != null && marca.toLowerCase().split('\\s+').contains(limpia.toLowerCase());
			if (esMarca && modelo == 0) { continue; }
			// El modelo termina donde se repite, en los datos técnicos (puertas, motor) o a las tres palabras.
			if (!vistas.add(limpia.toLowerCase()) || modelo == 3 || Pattern.matches('[0-9].*[A-Za-z.].*|[0-9]{1,2}|[A-Za-z][0-9]', limpia)
				|| new Set<String>{ 'puertas', 'aut', 'auto', 'std', 'tm', 'ta', 'valor', 'uso', 'transmisión', 'sedan', 'suv' }.contains(limpia.toLowerCase())) { break; }
			partes.add(titulo(limpia));
			modelo++;
			if (w.endsWith(',')) { break; }
		}
		if (partes.isEmpty()) { return null; }
		if (anio != null && Pattern.matches('(19|20)[0-9]{2}', anio) && !partes.contains(anio)) { partes.add(anio); }
		return String.join(partes, ' ');
	}

	// «SWIFT» -> «Swift»; las siglas y claves (GLX, EX30, X3) se quedan igual.
	private static String titulo(String s) {
		List<String> r = new List<String>();
		for (String w : s.split('\\s+')) {
			r.add(w.length() <= 3 || Pattern.matches('.*[0-9].*', w) || !w.equals(w.toUpperCase()) ? w : w.left(1) + w.substring(1).toLowerCase());
		}
		return String.join(r, ' ');
	}

	// Renglón de una aseguradora en el comparativo.
	private static String fila(Map<String, Object> op, Agente a, Map<String, String> datos, String asunto, Map<String, String> imagenes) {
		Boolean rec = op.get('recomendada') == true;
		String aseg = (String) op.get('aseguradora');
		String plan = (String) op.get('plan');
		String prima = (String) op.get('prima');
		String td = 'padding:10px 6px;border-bottom:1px solid #DDE3EA;vertical-align:middle;';
		String eleccion = 'Elijo la opción de ' + aseg + ' (' + plan + ') con prima anual de ' + prima;
		String correo = ligaCorreo(asunto, a, eleccion + ' y quiero contratar mi seguro.', datos.get('NOMBRE'));
		String wa = 'https://wa.me/' + a.whatsapp + '?text=' + url('Hola, ' + a.nombre + '. Soy ' + datos.get('NOMBRE') + '. ' + eleccion
			+ ' para mi ' + datos.get('VEHICULO') + ' y quiero contratar mi seguro. En seguida te envío mis documentos por aquí.');
		return '<tr style="' + (rec ? 'background:#EAFAF1;' : '') + '"><td style="' + td + '"><table cellpadding="0" cellspacing="0" role="presentation"><tr>'
			+ '<td valign="middle" style="padding-right:8px;">' + logoAseguradora(op, 36, 6) + '</td><td valign="middle"><strong>' + esc(aseg) + '</strong>'
			+ '<br><span style="font-size:12px;color:#5B6775;">' + esc(plan) + '</span>'
			+ (op.get('suma') == null ? '' : '<br><span style="font-size:11px;color:#5B6775;">Suma asegurada: ' + (String) op.get('suma') + '</span>')
			+ (rec ? '<br><span style="display:inline-block;background:#1E8E5A;color:#fff;font-size:11px;font-weight:bold;padding:2px 8px;border-radius:10px;margin-top:4px;">Recomendada</span>' : '')
			+ '</td></tr></table></td><td style="' + td + 'text-align:right;white-space:nowrap;">' + (rec ? '<strong>' + prima + '</strong>' : prima)
			+ '<br><span style="font-size:11px;color:#5B6775;white-space:normal;">equivale a<br>' + (String) op.get('primaDiaria') + ' al día</span></td>'
			+ '<td style="' + td + '"><div style="text-align:center;line-height:34px;"><span style="' + FUENTE
			+ 'font-size:16px;font-weight:bold;color:#0B3B60;vertical-align:middle;padding-right:4px;">Elegir</span> '
			+ icono(correo, imagenes.get('Correo_Icono_Correo'), 'Correo') + ' ' + icono(wa, imagenes.get('Correo_Icono_WhatsApp'), 'WhatsApp') + '</div></td></tr>';
	}

	private static String icono(String liga, String imagen, String texto) {
		return '<a href="' + esc(liga) + '" title="Elegir por ' + (texto == 'Correo' ? 'correo' : texto) + '" style="text-decoration:none;'
			+ (imagen == null ? FUENTE + 'font-size:12px;color:#0B3B60;' : '') + '">'
			+ (imagen == null ? texto : '<img src="' + esc(imagen) + '" width="30" height="30" alt="' + texto
				+ '" style="display:inline-block;border:0;vertical-align:middle;">') + '</a>';
	}

	private static String ligaCorreo(String asunto, Agente a, String primeraLinea, String cliente) {
		return 'mailto:' + RESPUESTA + '?' + (String.isBlank(a.correo) ? '' : 'cc=' + a.correo + '&') + 'subject=' + url('RE: ' + asunto) + '&body='
			+ url('Hola, equipo Avanza Seguro y ' + a.nombre + ':\n\n' + primeraLinea + '\n\nLes adjunto mis documentos para la emisión:\n'
				+ '- Identificación oficial vigente (INE o pasaporte, por ambos lados)\n- Comprobante de domicilio no mayor a 3 meses\n'
				+ '- CURP (solo si tu identificación no la incluye)\n- Factura del vehículo o tarjeta de circulación vigente\n'
				+ '- Constancia de Situación Fiscal\n- Auto a nombre de empresa: acta constitutiva, poder e identificación del representante '
				+ 'legal, Constancia de Situación Fiscal y comprobante de domicilio de la empresa\n- Auto financiado: la financiera es ________\n\n'
				+ '(Borra lo que no aplique y adjunta tus archivos antes de enviar)\n\nQuedo atento a mi póliza.\n\nGracias,\n' + cliente);
	}

	// Logo del encabezado: el del agente o, si no tiene, el de Avanza.
	private static String logoEncabezado(String logoAgente, Map<String, String> imagenes) {
		if (String.isBlank(logoAgente)) { return logoAvanza(imagenes, 44, 19); }
		return '<img src="' + esc(logoAgente) + '" alt="Logo" height="44" style="display:block;height:44px;width:auto;max-width:240px;border:0;">';
	}

	private static String logoAvanza(Map<String, String> imagenes, Integer alto, Integer letra) {
		String img = imagenes.get('Correo_Logo_Avanza');
		return '<table cellpadding="0" cellspacing="0" role="presentation"><tr>'
			+ (img == null ? '' : '<td valign="middle" style="padding-right:8px;"><img src="' + esc(img) + '" alt="Avanza Seguro" height="' + alto
				+ '" style="display:block;height:' + alto + 'px;width:auto;border:0;"></td>')
			+ '<td valign="middle" style="' + FUENTE + 'font-size:' + letra + 'px;line-height:1.15;letter-spacing:1px;color:#4A88BF;">'
			+ '<strong style="color:#0B3B60;">AVANZA</strong> SEGURO</td></tr></table>';
	}

	// Logo de la aseguradora (Aseguradora__c.Logo_URL__c); sin logo registrado, un recuadro con sus siglas para que nunca salga
	// una imagen rota.
	private static String logoAseguradora(Map<String, Object> op, Integer lado, Integer radio) {
		String nombre = (String) op.get('aseguradora');
		if (String.isNotBlank((String) op.get('logo'))) {
			return '<img src="' + esc(((String) op.get('logo'))) + '" width="' + lado + '" height="' + lado + '" alt="' + esc(nombre)
				+ '" style="display:block;border:0;border-radius:' + radio + 'px;">';
		}
		return '<table cellpadding="0" cellspacing="0" role="presentation"><tr><td align="center" valign="middle" width="' + lado + '" height="' + lado
			+ '" style="width:' + lado + 'px;height:' + lado + 'px;background:#0B3B60;border-radius:' + radio + 'px;' + FUENTE
			+ 'font-size:' + (siglas(nombre).length() > 2 ? 11 : 12) + 'px;font-weight:bold;color:#FFFFFF;">' + esc(siglas(nombre)) + '</td></tr></table>';
	}

	// «HDI Seguros» -> HDI; «Chubb México» -> CH.
	@TestVisible
	private static String siglas(String nombre) {
		String p = nombre.trim().split('\\s+')[0];
		return p.length() <= 4 && p.equals(p.toUpperCase()) ? p : p.left(2).toUpperCase();
	}

	// Cambia los marcadores: dentro de una liga mailto: o wa.me van codificados para URL; fuera, para HTML.
	@TestVisible
	private static String llenar(String html, Map<String, String> datos, Map<String, String> bloques) {
		String r = '';
		Integer pos = 0;
		Matcher m = Pattern.compile('href=["\'](?:mailto:|https://wa\\.me/)[^"\']*["\']').matcher(html);
		while (m.find()) {
			r += reemplazar(html.substring(pos, m.start()), datos, false) + reemplazar(m.group(), datos, true);
			pos = m.end();
		}
		r += reemplazar(html.substring(pos), datos, false);
		for (String k : bloques.keySet()) { r = r.replace('{{' + k + '}}', bloques.get(k)); }
		return r;
	}

	private static String reemplazar(String texto, Map<String, String> datos, Boolean enLiga) {
		for (String k : datos.keySet()) {
			String v = datos.get(k) == null ? '' : datos.get(k);
			// El correo del agente va en copia (cc): la arroba no se codifica.
			texto = texto.replace('{{' + k + '}}', !enLiga ? esc(v) : (k == 'CORREO_AGENTE' ? v : url(v)));
		}
		return texto;
	}

	private static String sinBloque(String html, String nombre) {
		Integer ini = html.indexOf('<!--' + nombre + '-->');
		String cierre = '<!--/' + nombre + '-->';
		Integer fin = html.indexOf(cierre);
		return ini < 0 || fin < ini ? html : html.left(ini) + html.substring(fin + cierre.length());
	}

	private static String esc(String s) {
		return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;');
	}

	private static String url(String s) {
		return EncodingUtil.urlEncode(s, 'UTF-8').replace('+', '%20');
	}

	// 14069.33 -> $14,069.33 (no depende del idioma de quien envía).
	@TestVisible
	private static String moneda(Decimal v) {
		List<String> p = v.setScale(2, System.RoundingMode.HALF_UP).toPlainString().split('\\.');
		return '$' + p[0].reverse().replaceAll('([0-9]{3})(?=[0-9])', '$1,').reverse() + '.' + p[1];
	}

	/**
	 * @creation date: 24/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Tarea de seguimiento al agente a 3 días hábiles de enviar la cotización. Queda a su usuario o, si no tiene,
	 *               al propietario de la oportunidad. No se repite si ya hay una abierta.
	 * @param oportunidadId: Oportunidad
	 * @return void
	 */
	public static void seguimiento(Id oportunidadId) {
		if (![SELECT Id FROM Task WHERE WhatId = :oportunidadId AND Subject = :ASUNTO_TAREA AND IsClosed = false LIMIT 1].isEmpty()) { return; }
		Opportunity o = [SELECT OwnerId, Producer__r.InternalUserId, Producer__r.InternalUser.IsActive FROM Opportunity WHERE Id = :oportunidadId LIMIT 1];
		Boolean conUsuario = o.Producer__r?.InternalUserId != null && o.Producer__r.InternalUser.IsActive == true;
		Task t = new Task(WhatId = oportunidadId, Subject = ASUNTO_TAREA, ActivityDate = diasHabiles(Date.today(), 3), Priority = 'Normal',
			OwnerId = conUsuario ? o.Producer__r.InternalUserId : o.OwnerId);
		Database.insert(t, false);
	}

	@TestVisible
	private static Date diasHabiles(Date desde, Integer dias) {
		Date d = desde;
		// El 1 de enero de 1900 fue lunes: 0-4 son de lunes a viernes.
		while (dias > 0) {
			d = d.addDays(1);
			if (Math.mod(Date.newInstance(1900, 1, 1).daysBetween(d), 7) < 5) { dias--; }
		}
		return d;
	}

	/** Ligas públicas de las imágenes del correo (documentos de la carpeta Correos Avanza); quien envía puede no ver la carpeta. */
	private without sharing class Imagenes {
		Map<String, String> ligas() {
			Map<String, String> r = new Map<String, String>();
			for (Document d : [SELECT Id, DeveloperName FROM Document WHERE DeveloperName IN :IMAGENES AND IsPublic = true]) {
				r.put(d.DeveloperName, Url.getOrgDomainUrl().toExternalForm() + '/servlet/servlet.ImageServer?id=' + String.valueOf(d.Id).left(15)
					+ '&oid=' + UserInfo.getOrganizationId().left(15));
			}
			return r;
		}
	}
}
