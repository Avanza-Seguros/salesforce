/**
 *   @name: AvisoSolicitudSitio
 *   @version: 1.0
 *   @creation date: 19/11/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Aviso a Avanza de una solicitud de movimientos enviada desde el sitio de empresas (lo llama el Flow
 *                 «Solicitud Movimientos Aviso»). El correo trae un resumen breve (folio, cliente, póliza, cuántas altas,
 *                 bajas y cambios, comentario) y adjunto el «Excel para la aseguradora» de la solicitud, el mismo que se
 *                 descarga en Salesforce en Asegurados, Vehículos o Ubicaciones. El Excel también queda en el caso.
 *                 Sin sharing: el Flow corre como el sistema y el Excel lee todos los registros de la póliza.
 */
public without sharing class AvisoSolicitudSitio {

	public class Solicitud {
		@InvocableVariable(label='Caso de la solicitud' required=true)
		public Id casoId;
		@InvocableVariable(label='Destinatarios (separados por coma)' required=true)
		public String destinatarios;
		@InvocableVariable(label='Remitente (dirección de toda la organización)')
		public String remitente;
	}

	public class Resultado {
		@InvocableVariable(label='Enviado')
		public Boolean enviado = false;
		@InvocableVariable(label='Mensaje')
		public String mensaje;
	}

	// Excel de la solicitud (ver excel).
	public class Archivo {
		public String nombre;
		public Blob contenido;
		public Integer renglones = 0;
		public String bienes;
		public Map<String, Integer> porTipo = new Map<String, Integer>();
		public Date desde;
		public Date hasta;
	}

	/**
	 * @creation date: 19/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Envía el aviso de cada solicitud con su Excel adjunto.
	 * @param solicitudes: caso, destinatarios y remitente
	 * @return Un resultado por solicitud
	 */
	@InvocableMethod(label='Aviso de solicitud del sitio (con Excel para la aseguradora)' category='Correo')
	public static List<Resultado> enviar(List<Solicitud> solicitudes) {
		List<Resultado> out = new List<Resultado>();
		for (Solicitud s : solicitudes) {
			Resultado r = new Resultado();
			try {
				r.mensaje = enviarUno(s);
				r.enviado = true;
			} catch (Exception e) {
				r.mensaje = 'No se pudo enviar el aviso: ' + e.getMessage();
				System.debug(LoggingLevel.ERROR, 'AvisoSolicitudSitio: ' + e.getMessage() + ' | ' + e.getStackTraceString());
			}
			out.add(r);
		}
		return out;
	}

	private static String enviarUno(Solicitud s) {
		Case c = [
			SELECT Id, CaseNumber, Solicitud__c, Subject, Comentarios__c, InsurancePolicy__c, InsurancePolicy__r.Name,
				InsurancePolicy__r.Ramo__c, Account.Name, CreatedBy.Name
			FROM Case WHERE Id = :s.casoId LIMIT 1
		];
		Archivo x = null;
		String avisoExcel = '';
		try {
			x = excel(c.InsurancePolicy__c, c.Solicitud__c);
		} catch (Exception e) {
			avisoExcel = 'No se pudo generar el Excel: ' + e.getMessage();
		}
		Messaging.EmailFileAttachment adjunto = null;
		if (x != null && x.renglones > 0) {
			// El Excel queda también en el caso.
			insert new ContentVersion(Title = x.nombre.removeEnd('.xlsx'), PathOnClient = x.nombre, VersionData = x.contenido,
				FirstPublishLocationId = c.Id);
			adjunto = new Messaging.EmailFileAttachment();
			adjunto.setFileName(x.nombre);
			adjunto.setContentType('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
			adjunto.setBody(x.contenido);
		} else if (String.isBlank(avisoExcel)) {
			avisoExcel = 'La solicitud no registró movimientos en la póliza; revisa el caso y sus archivos.';
		}

		Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
		List<String> para = new List<String>();
		for (String d : s.destinatarios.split('[,;]')) { if (String.isNotBlank(d)) { para.add(d.trim()); } }
		m.setToAddresses(para);
		m.setSubject('Nueva solicitud de movimientos ' + c.Solicitud__c + ' · ' + c.Account.Name + ' · Póliza ' + c.InsurancePolicy__r.Name);
		m.setHtmlBody(cuerpo(c, x, avisoExcel));
		m.setSaveAsActivity(false);
		if (String.isNotBlank(s.remitente)) {
			for (OrgWideEmailAddress o : [SELECT Id FROM OrgWideEmailAddress WHERE Address = :s.remitente LIMIT 1]) {
				m.setOrgWideEmailAddressId(o.Id);
			}
		}
		if (adjunto != null) { m.setFileAttachments(new List<Messaging.EmailFileAttachment>{ adjunto }); }
		Messaging.SendEmailResult res = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ m }, false)[0];
		if (!res.isSuccess()) { throw new AvisoException(res.getErrors()[0].getMessage()); }
		return 'Aviso enviado a ' + String.join(para, ', ') + (adjunto == null ? ' sin Excel' : ' con ' + x.nombre) + '.';
	}

	// Resumen breve: lo importante de la solicitud, sin listar cada registro (van en el Excel).
	@TestVisible
	private static String cuerpo(Case c, Archivo x, String avisoExcel) {
		String liga = Url.getOrgDomainUrl().toExternalForm() + '/' + c.Id;
		List<String> movs = new List<String>();
		if (x != null) {
			for (String t : x.porTipo.keySet()) {
				Integer n = x.porTipo.get(t);
				movs.add(n + ' ' + (n == 1 ? t.toLowerCase() : plural(t)));
			}
		}
		String h = '<p>El cliente envió una solicitud de movimientos desde el sitio de empresas.</p><table cellpadding="4" style="border-collapse:collapse;font-family:Arial,sans-serif;font-size:14px">'
			+ fila('Folio', c.Solicitud__c) + fila('Cliente', c.Account.Name) + fila('Póliza', c.InsurancePolicy__r.Name)
			+ fila('Ramo', c.InsurancePolicy__r.Ramo__c) + fila('Enviada por', c.CreatedBy.Name)
			+ fila('Movimientos', movs.isEmpty() ? null : String.join(movs, ', ') + (x.bienes == null ? '' : ' de ' + x.bienes))
			+ fila('Fecha de los movimientos', x == null || x.desde == null ? null
				: (x.desde == x.hasta ? fecha(x.desde) : fecha(x.desde) + ' a ' + fecha(x.hasta)))
			+ fila('Comentario del cliente', String.isBlank(c.Comentarios__c) ? null : c.Comentarios__c.abbreviate(500))
			+ fila('Caso', c.CaseNumber) + '</table>';
		if (x != null && x.renglones > 0) {
			h += '<p>Adjunto va el Excel para la aseguradora (<b>' + x.nombre.escapeHtml4() + '</b>) con el detalle de los movimientos; también quedó en el caso.</p>';
		}
		if (String.isNotBlank(avisoExcel)) { h += '<p><b>Nota:</b> ' + avisoExcel.escapeHtml4() + '</p>'; }
		h += '<p><a href="' + liga + '">Ver el caso en Salesforce</a></p>'
			+ '<p>Cuando llegue el endoso de la aseguradora, cierra los movimientos con su número.</p>';
		return h;
	}

	private static String fila(String etiqueta, String valor) {
		if (String.isBlank(valor)) { return ''; }
		return '<tr><td style="color:#555"><b>' + etiqueta + '</b></td><td>' + valor.escapeHtml4() + '</td></tr>';
	}

	private static String plural(String t) {
		String l = t.toLowerCase();
		return l.endsWith('a') || l.endsWith('o') || l.endsWith('e') ? l + 's' : l + 'es';
	}

	// ============================================================
	// Excel para la aseguradora (mismo formato que el botón de Salesforce en movimientosColectivo,
	// movimientosFlotilla y movimientosUbicaciones).
	// ============================================================

	/**
	 * @creation date: 19/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma el Excel de los registros de la póliza con el folio de la solicitud.
	 * @param policyId: póliza
	 * @param folio: folio de la solicitud (SOL-0001...)
	 * @return Excel; renglones = 0 si la solicitud no tiene registros
	 */
	public static Archivo excel(Id policyId, String folio) {
		Map<String, Object> base = MovimientosColectivoController.getDatos(policyId);
		String poliza = (String) base.get('nombre');
		Archivo a = new Archivo();
		List<String> columnas;
		List<List<Object>> filas = new List<List<Object>>();
		String hoja;
		String prefijo;
		List<Map<String, Object>> registros = new List<Map<String, Object>>();
		if (base.get('flotilla') == true) {
			Map<String, Object> d = MovimientosFlotillaController.getDatos(policyId);
			for (Object o : lista(d.get('vehiculos'))) { if (deFolio(o, folio)) { registros.add((Map<String, Object>) o); } }
			hoja = 'Vehículos'; prefijo = 'Vehiculos'; a.bienes = 'vehículos';
			columnas = new List<String>{ 'Vehículo', 'Serie', 'Modelo', 'Placas', 'Uso',
				'Tipo de petición', 'Fecha de petición', 'Poliza', 'Paquete', 'Inciso', 'Vigencia desde', 'Vigencia hasta', 'Valor', 'Prima',
				'Descripción' };
			for (Map<String, Object> r : registros) {
				Object desde = r.get('fechaAlta') != null ? r.get('fechaAlta') : d.get('inicio');
				Object hasta = r.get('fechaBaja') != null ? r.get('fechaBaja') : d.get('fin');
				filas.add(new List<Object>{ r.get('descripcion'), r.get('serie'), num(r.get('modelo')),
					r.get('placas'), r.get('uso'), tipo(r), fecha(r.get('fechaMovimiento')), poliza, r.get('paquete'),
					num(r.get('inciso')), fecha(desde), fecha(hasta), num(r.get('valor')), num(r.get('prima')), txt(r.get('motivoBaja')) });
			}
		} else if (base.get('ubicaciones') == true) {
			Map<String, Object> d = MovimientosUbicacionesController.getDatos(policyId);
			for (Object o : lista(d.get('ubicaciones'))) { if (deFolio(o, folio)) { registros.add((Map<String, Object>) o); } }
			hoja = 'Ubicaciones'; prefijo = 'Ubicaciones'; a.bienes = 'ubicaciones';
			columnas = new List<String>{ 'Nombre', 'Dirección', 'Giro', 'Tipo de petición',
				'Fecha de petición', 'Poliza', 'Inciso', 'Fecha de alta', 'Suma asegurada', 'Prima', 'Descripción' };
			for (Map<String, Object> r : registros) {
				Object inciso = num(r.get('inciso'));
				filas.add(new List<Object>{ r.get('nombre'), r.get('direccion'), r.get('giro'),
					tipo(r), fecha(r.get('fechaMovimiento')), poliza, inciso == null ? r.get('inciso') : inciso,
					fecha(r.get('fechaAlta')), num(r.get('sumaAsegurada')), num(r.get('prima')), txt(r.get('motivoBaja')) });
			}
		} else {
			List<Map<String, Object>> miembros = new List<Map<String, Object>>();
			for (Object o : lista(base.get('miembros'))) { miembros.add((Map<String, Object>) o); }
			for (Map<String, Object> r : miembros) { if (deFolio(r, folio)) { registros.add(r); } }
			hoja = 'Asegurados'; prefijo = 'Asegurados'; a.bienes = 'asegurados';
			columnas = asegurados(registros, poliza, (String) base.get('ramo'), filas);
		}
		a.renglones = filas.size();
		for (Map<String, Object> r : registros) {
			String t = tipo(r);
			a.porTipo.put(t, (a.porTipo.containsKey(t) ? a.porTipo.get(t) : 0) + 1);
			Date f = r.get('fechaMovimiento') instanceof Date ? (Date) r.get('fechaMovimiento') : null;
			if (f != null) {
				if (a.desde == null || f < a.desde) { a.desde = f; }
				if (a.hasta == null || f > a.hasta) { a.hasta = f; }
			}
		}
		a.nombre = prefijo + '_' + String.valueOf(poliza == null ? '' : poliza).replaceAll('[^A-Za-z0-9-]+', '_') + '_' + folio + '.xlsx';
		if (a.renglones > 0) { a.contenido = xlsx(hoja, columnas, filas); }
		return a;
	}

	// Solo los registros solicitados, los dependientes en las columnas de su titular (igual que movimientosColectivo.excelDe).
	private static List<String> asegurados(List<Map<String, Object>> registros, String poliza, String ramo,
			List<List<Object>> filas) {
		// El porcentaje no aplica en GMM.
		Boolean conPorcentaje = ramo == null || !ramo.toUpperCase().startsWith('GMM');
		// Solo los registros que se solicitan: el dependiente va en las columnas de su titular si el titular se pide con el mismo
		// tipo de movimiento; si no, en su propio renglón.
		Set<String> titularesPedidos = new Set<String>();
		for (Map<String, Object> r : registros) { if (r.get('esTitular') == true) { titularesPedidos.add(r.get('id') + '|' + tipo(r)); } }
		Map<String, Map<String, Object>> titulares = new Map<String, Map<String, Object>>();
		Map<String, List<Map<String, Object>>> enMovimiento = new Map<String, List<Map<String, Object>>>();
		Map<String, List<Map<String, Object>>> dependientes = new Map<String, List<Map<String, Object>>>();
		List<Map<String, Object>> conTitular = new List<Map<String, Object>>();
		for (Map<String, Object> r : registros) {
			if (r.get('esTitular') != true && titularesPedidos.contains(r.get('titularId') + '|' + tipo(r))) { conTitular.add(r); continue; }
			String clave = r.get('id') + '|' + tipo(r);
			titulares.put(clave, r);
			enMovimiento.put(clave, new List<Map<String, Object>>{ r });
			dependientes.put(clave, new List<Map<String, Object>>());
		}
		for (Map<String, Object> r : conTitular) {
			String clave = r.get('titularId') + '|' + tipo(r);
			enMovimiento.get(clave).add(r);
			dependientes.get(clave).add(r);
		}
		// Solo las columnas de los dependientes que hay (ninguna si no hay).
		Integer numDep = 0;
		for (String k : dependientes.keySet()) { numDep = Math.max(numDep, dependientes.get(k).size()); }
		List<String> columnas = new List<String>{ 'Nombre', 'Apellido Paterno del Asegurado',
			'Apellido Materno del Asegurado', 'Fecha de nacimiento', 'Sexo', 'Tipo de petición', 'Fecha de petición',
			'Poliza', 'Categorias', 'Certificado', 'Parentesco' };
		for (Integer i = 1; i <= numDep; i++) {
			columnas.addAll(new List<String>{ 'Nombre(s)', 'Apellido paterno', 'Apellido materno', 'Fecha de Nacimiento', 'Parentesco',
				'Sexo Dependiente ' + i });
			if (conPorcentaje) { columnas.add('Porcentaje'); }
		}
		columnas.addAll(new List<String>{ 'Descripción', 'Correo electrónico' });
		for (String clave : titulares.keySet()) {
			Map<String, Object> t = titulares.get(clave);
			String[] n = partesNombre(t);
			List<Object> f = new List<Object>{ n[0], n[1], n[2], fecha(t.get('fechaNacimiento')), sexo(t),
				tipo(t), fecha(t.get('fechaMovimiento')), poliza, txt(t.get('categoria')),
				t.get('certificado') == null ? 'POR ASIGNAR' : txt(t.get('certificado')),
				t.get('esTitular') == true ? '01 Titular' : (t.get('parentesco') == null ? 'Dependiente' : txt(t.get('parentesco'))) };
			List<Map<String, Object>> deps = dependientes.get(clave);
			for (Integer i = 0; i < numDep; i++) {
				if (i < deps.size()) {
					Map<String, Object> d = deps[i];
					String[] nd = partesNombre(d);
					f.addAll(new List<Object>{ nd[0], nd[1], nd[2], fecha(d.get('fechaNacimiento')), txt(d.get('parentesco')), sexo(d) });
				} else {
					f.addAll(new List<Object>{ '', '', '', '', '', '' });
				}
				if (conPorcentaje) { f.add(0); }
			}
			List<String> motivos = new List<String>();
			for (Map<String, Object> r : enMovimiento.get(clave)) {
				if (r.get('motivoBaja') == null || String.isBlank(String.valueOf(r.get('motivoBaja')))) { continue; }
				motivos.add(String.valueOf(r.get('id')) == String.valueOf(t.get('id')) ? String.valueOf(r.get('motivoBaja'))
					: r.get('nombre') + ': ' + r.get('motivoBaja'));
			}
			Object correo = t.get('activo') == false && t.get('correoPersonal') != null ? t.get('correoPersonal') : t.get('correo');
			f.addAll(new List<Object>{ String.join(motivos, ' | '), txt(correo) });
			filas.add(f);
		}
		return columnas;
	}

	private static String[] partesNombre(Map<String, Object> r) {
		if (r.get('nombres') != null || r.get('apellidoPaterno') != null) {
			return new String[]{ txt(r.get('nombres')), txt(r.get('apellidoPaterno')), txt(r.get('apellidoMaterno')) };
		}
		List<String> p = new List<String>();
		for (String x : txt(r.get('nombre')).trim().split('\\s+')) { if (String.isNotBlank(x)) { p.add(x); } }
		if (p.size() >= 3) {
			List<String> nom = new List<String>();
			for (Integer i = 0; i < p.size() - 2; i++) { nom.add(p[i]); }
			return new String[]{ String.join(nom, ' '), p[p.size() - 2], p[p.size() - 1] };
		}
		if (p.size() == 2) { return new String[]{ p[0], p[1], '' }; }
		return new String[]{ String.join(p, ' '), '', '' };
	}

	private static String sexo(Map<String, Object> r) {
		Object v = r.get('sexo') != null ? r.get('sexo') : r.get('sexoContacto');
		String s = txt(v).toLowerCase().trim();
		if (String.isBlank(s)) { return ''; }
		if (s.startsWith('f') || s.startsWith('mujer')) { return 'Femenino'; }
		if (s.startsWith('mas') || s.startsWith('h') || s == 'm') { return 'Masculino'; }
		return txt(v);
	}

	private static String tipo(Map<String, Object> r) {
		if (r.get('tipoMovimiento') != null && String.isNotBlank(String.valueOf(r.get('tipoMovimiento')))) {
			return String.valueOf(r.get('tipoMovimiento'));
		}
		return r.get('activo') == false ? 'Baja' : 'Alta';
	}

	private static Boolean deFolio(Object o, String folio) {
		return o instanceof Map<String, Object> && ((Map<String, Object>) o).get('solicitud') == folio;
	}

	private static List<Object> lista(Object o) { return o instanceof List<Object> ? (List<Object>) o : new List<Object>(); }

	private static String txt(Object v) { return v == null ? '' : String.valueOf(v); }

	private static Object num(Object v) {
		if (v == null || String.isBlank(String.valueOf(v))) { return null; }
		try { return Decimal.valueOf(String.valueOf(v).trim()); } catch (Exception e) { return null; }
	}

	// DD/MM/AAAA (fechaVisible del sitio).
	private static String fecha(Object v) {
		if (v == null) { return ''; }
		String s = v instanceof Date ? String.valueOf((Date) v) : (v instanceof Datetime ? ((Datetime) v).formatGmt('yyyy-MM-dd') : String.valueOf(v));
		if (s.length() < 10) { return s; }
		return s.substring(8, 10) + '/' + s.substring(5, 7) + '/' + s.substring(0, 4);
	}

	// ============================================================
	// .xlsx de una hoja (mismo contenido que generarXlsx de lectorArchivos).
	// ============================================================
	private static final String XML = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
	private static final String NS_MAIN = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
	private static final String NS_REL = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

	@TestVisible
	private static Blob xlsx(String hoja, List<String> columnas, List<List<Object>> filas) {
		List<Object> encabezado = new List<Object>();
		for (String c : columnas) { encabezado.add(c); }
		List<List<Object>> todas = new List<List<Object>>{ encabezado };
		todas.addAll(filas);
		List<String> renglones = new List<String>();
		for (Integer i = 0; i < todas.size(); i++) {
			List<String> celdas = new List<String>();
			for (Integer c = 0; c < todas[i].size(); c++) { celdas.add(celda(todas[i][c], i + 1, c)); }
			renglones.add('<row r="' + (i + 1) + '">' + String.join(celdas, '') + '</row>');
		}
		List<String> anchos = new List<String>();
		for (Integer c = 0; c < columnas.size(); c++) {
			Integer largo = columnas[c].length();
			for (List<Object> f : filas) { if (c < f.size() && f[c] != null) { largo = Math.max(largo, String.valueOf(f[c]).length()); } }
			anchos.add('<col min="' + (c + 1) + '" max="' + (c + 1) + '" width="' + Math.min(60, Math.max(10, largo + 2)) + '" customWidth="1"/>');
		}
		String nombreHoja = esc(String.valueOf(hoja == null ? 'Hoja1' : hoja).replaceAll('[\\\\/?*\\[\\]:]', ' ').left(31));
		Compression.ZipWriter z = new Compression.ZipWriter();
		z.addEntry('[Content_Types].xml', Blob.valueOf(XML
			+ '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
			+ '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
			+ '<Default Extension="xml" ContentType="application/xml"/>'
			+ '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
			+ '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
			+ '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
			+ '</Types>'));
		z.addEntry('_rels/.rels', Blob.valueOf(XML
			+ '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
			+ '<Relationship Id="rId1" Type="' + NS_REL + '/officeDocument" Target="xl/workbook.xml"/></Relationships>'));
		z.addEntry('xl/workbook.xml', Blob.valueOf(XML
			+ '<workbook xmlns="' + NS_MAIN + '" xmlns:r="' + NS_REL + '"><sheets><sheet name="' + nombreHoja
			+ '" sheetId="1" r:id="rId1"/></sheets></workbook>'));
		z.addEntry('xl/_rels/workbook.xml.rels', Blob.valueOf(XML
			+ '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
			+ '<Relationship Id="rId1" Type="' + NS_REL + '/worksheet" Target="worksheets/sheet1.xml"/>'
			+ '<Relationship Id="rId2" Type="' + NS_REL + '/styles" Target="styles.xml"/></Relationships>'));
		z.addEntry('xl/styles.xml', Blob.valueOf(XML
			+ '<styleSheet xmlns="' + NS_MAIN + '">'
			+ '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
			+ '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
			+ '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
			+ '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
			+ '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
			+ '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs></styleSheet>'));
		z.addEntry('xl/worksheets/sheet1.xml', Blob.valueOf(XML
			+ '<worksheet xmlns="' + NS_MAIN + '">'
			+ '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
			+ '<cols>' + String.join(anchos, '') + '</cols><sheetData>' + String.join(renglones, '') + '</sheetData></worksheet>'));
		return z.getArchive();
	}

	private static String celda(Object v, Integer r, Integer c) {
		if (v == null || (v instanceof String && String.isBlank((String) v))) { return ''; }
		String ref = columna(c) + r;
		if (v instanceof Decimal || v instanceof Integer || v instanceof Double || v instanceof Long) {
			return '<c r="' + ref + '"><v>' + String.valueOf(v) + '</v></c>';
		}
		return '<c r="' + ref + '" t="inlineStr"' + (r == 1 ? ' s="1"' : '') + '><is><t xml:space="preserve">' + esc(String.valueOf(v))
			+ '</t></is></c>';
	}

	private static String columna(Integer i) {
		String s = '';
		Integer n = i + 1;
		while (n > 0) {
			Integer m = Math.mod(n - 1, 26);
			s = String.fromCharArray(new List<Integer>{ 65 + m }) + s;
			n = (n - 1 - m) / 26;
		}
		return s;
	}

	private static String esc(String s) {
		return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;')
			.replaceAll('[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F]', '');
	}

	public class AvisoException extends Exception {}
}
