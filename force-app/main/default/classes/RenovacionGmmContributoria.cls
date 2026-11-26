/**
 *   @name: RenovacionGmmContributoria
 *   @version: 1.0
 *   @creation date: 26/11/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Renovación de GMM colectivo contributorio. Desde «Enviar correo» de los movimientos de asegurados de la
 *                 póliza, al elegir la plantilla «Renovación GMM Contributoria», cada titular recibe un correo con su
 *                 categoría, su familia (parentesco, edad y prima de cada uno) y el total que paga, con los botones para
 *                 aceptar o rechazar la renovación. La prima de cada asegurado es la total (con su parte de derecho de
 *                 póliza e IVA): la prima neta es el total sin IVA menos el derecho de póliza por titular. La fecha límite
 *                 para confirmar y el derecho de póliza se capturan al enviar.
 */
public with sharing class RenovacionGmmContributoria {

	public static final String PLANTILLA = 'Renovacion_GMM_Contributoria';
	public static final String RESPUESTA = 'gmmfii@avanzaseguro.com';
	static final Decimal IVA = 0.16;
	static final List<String> IMAGENES = new List<String>{ 'HERO_FONDO', 'LOGO_AVANZA_BLANCO', 'DRA_SALUDANDO', 'ICONO_CREDENCIAL',
		'DRA_SENALANDO', 'ICONO_RELOJ', 'ICONO_CORAZON', 'ICONO_PORCENTAJE', 'ICONO_DOCUMENTO', 'DRA_PULGAR', 'ICONO_ESCUDO',
		'DRA_PORTAPAPELES' };
	static final List<String> FUENTES = new List<String>{ 'FUENTE_GILROY_MEDIUM', 'FUENTE_GILROY_EXTRABOLD', 'FUENTE_ANNIFONT' };

	/** Un titular con su familia (asegurados vigentes de la póliza). */
	public class Familia {
		public InsurancePolicyParticipant titular;
		public List<InsurancePolicyParticipant> miembros = new List<InsurancePolicyParticipant>();
		public String categoria;
		public String correo;
		public String nombrePila;
	}

	/** Datos del envío: los mismos para todas las familias. */
	public class Envio {
		public String empresa;
		public String aseguradora;
		public Date inicio;
		public Date fin;
		public Date fechaLimite;
		public Decimal derecho;
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Envía la renovación a los titulares elegidos (un dependiente elegido cuenta como su titular), desde
	 *               info@avanzaseguro.com, y marca como enviado al titular y a su familia.
	 * @param policyId: póliza (la de la nueva vigencia)
	 * @param participanteIds: asegurados elegidos (máximo 50)
	 * @param fechaLimite: «Confirma a más tardar» (AAAA-MM-DD)
	 * @param derecho: derecho de póliza por titular
	 * @param copias: correos que reciben copia de cada correo (separados por coma o punto y coma; opcional)
	 * @return {enviados, errores}
	 */
	@AuraEnabled
	public static Map<String, Object> enviar(Id policyId, List<Id> participanteIds, String fechaLimite, Decimal derecho, String copias) {
		if (participanteIds == null || participanteIds.isEmpty()) { throw CensoColectivoController.error('Selecciona al menos un asegurado.'); }
		if (participanteIds.size() > 50) { throw CensoColectivoController.error('Envía máximo 50 correos a la vez.'); }
		Envio e = envioDe(policyId);
		e.fechaLimite = fecha(fechaLimite);
		e.derecho = derecho == null ? 0 : derecho;
		if (e.fechaLimite == null) { throw CensoColectivoController.error('Captura la fecha límite para confirmar la renovación.'); }
		if (e.derecho < 0) { throw CensoColectivoController.error('El derecho de póliza no puede ser negativo.'); }
		List<String> cc = correos(copias);
		if (e.inicio == null || e.fin == null) { throw CensoColectivoController.error('La póliza no tiene su vigencia completa.'); }
		List<EmailTemplate> tpls = [SELECT Name, Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :PLANTILLA LIMIT 1];
		if (tpls.isEmpty()) { throw CensoColectivoController.error('No existe la plantilla «' + PLANTILLA + '».'); }

		Set<Id> elegidos = new Set<Id>(participanteIds);
		List<Familia> fams = new List<Familia>();
		for (Familia f : familias(policyId)) {
			Boolean va = elegidos.contains(f.titular.Id);
			for (InsurancePolicyParticipant m : f.miembros) { va = va || elegidos.contains(m.Id); }
			if (va) { fams.add(f); }
		}
		List<String> errores = new List<String>();
		Map<String, String> ligas = new Recursos().ligas();
		List<OrgWideEmailAddress> owe = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :AvisoRenovacionPoliza.CORREO_SERVICIO LIMIT 1];
		List<Messaging.SingleEmailMessage> mensajes = new List<Messaging.SingleEmailMessage>();
		List<Familia> destinos = new List<Familia>();
		for (Familia f : fams) {
			String falta = String.isBlank(f.correo) ? 'no tiene correo.' : faltaPrima(f);
			if (falta != null) { errores.add(f.titular.ParticipantName + ': ' + falta); continue; }
			Map<String, String> c = armar(f, e, tpls[0], ligas);
			Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
			m.setSubject(c.get('asunto'));
			m.setHtmlBody(c.get('html'));
			m.setToAddresses(new List<String>{ f.correo });
			if (!owe.isEmpty()) { m.setOrgWideEmailAddressId(owe[0].Id); }
			m.setReplyTo(RESPUESTA);
			if (!cc.isEmpty()) { m.setCcAddresses(cc); }
			m.setSaveAsActivity(false);
			mensajes.add(m);
			destinos.add(f);
		}
		Integer enviados = 0;
		if (!mensajes.isEmpty()) {
			List<Messaging.SendEmailResult> res;
			try {
				res = Messaging.sendEmail(mensajes, false);
			} catch (Exception ex) {
				throw CensoColectivoController.error('No se pudo enviar el correo: ' + ex.getMessage()
					+ ' Revisa en Configuración › Entregabilidad que el acceso esté en «Todo el email».');
			}
			List<InsurancePolicyParticipant> marcar = new List<InsurancePolicyParticipant>();
			for (Integer i = 0; i < res.size(); i++) {
				if (!res[i].isSuccess()) { errores.add(destinos[i].titular.ParticipantName + ': ' + res[i].getErrors()[0].getMessage()); continue; }
				enviados++;
				for (InsurancePolicyParticipant p : destinos[i].miembros) {
					marcar.add(new InsurancePolicyParticipant(Id = p.Id, Correo_Enviado__c = true, Fecha_Envio_Correo__c = Datetime.now(),
						Plantilla_Correo__c = tpls[0].Name.left(255)));
				}
			}
			update marcar;
		}
		return new Map<String, Object>{ 'enviados' => enviados, 'errores' => errores };
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Correo que recibiría un titular, sin enviarlo (para revisarlo).
	 * @param policyId: póliza
	 * @param titularId: titular
	 * @param fechaLimite: «Confirma a más tardar» (AAAA-MM-DD)
	 * @param derecho: derecho de póliza por titular
	 * @return asunto, html y correo; null si el titular no está en la póliza
	 */
	public static Map<String, String> vistaPrevia(Id policyId, Id titularId, String fechaLimite, Decimal derecho) {
		Envio e = envioDe(policyId);
		e.fechaLimite = fecha(fechaLimite);
		e.derecho = derecho == null ? 0 : derecho;
		EmailTemplate tpl = [SELECT Name, Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :PLANTILLA LIMIT 1];
		for (Familia f : familias(policyId)) {
			if (f.titular.Id != titularId) { continue; }
			Map<String, String> r = armar(f, e, tpl, new Recursos().ligas());
			r.put('correo', f.correo);
			return r;
		}
		return null;
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma el correo de una familia con la plantilla.
	 * @return asunto y html
	 */
	@TestVisible
	private static Map<String, String> armar(Familia f, Envio e, EmailTemplate tpl, Map<String, String> ligas) {
		Decimal total = 0;
		String filas = '';
		List<String> lista = new List<String>();
		String celda = 'padding:11px 12px;border-top:1px solid #6C6C6B;font-family:Gilroy, Arial, Helvetica, sans-serif;font-size:14px;color:#6C6C6B;';
		Map<String, String> etiquetas = new Map<String, String>();
		for (Schema.PicklistEntry pe : InsurancePolicyParticipant.RelationshipToInsured.getDescribe().getPicklistValues()) {
			etiquetas.put(pe.getValue(), pe.getLabel());
		}
		for (InsurancePolicyParticipant m : f.miembros) {
			String parentesco = m.Id == f.titular.Id ? 'Titular'
				: CensoColectivoController.parentescoPolizaVisible(m.RelationshipToInsured, etiquetas);
			if (String.isBlank(parentesco)) { parentesco = 'Dependiente'; }
			Integer edad = edadDe(m);
			Decimal prima = primaDe(m);
			total += prima;
			filas += '<tr><td style=\'' + celda + 'font-weight:800;\'>' + esc(nombreVisible(m.ParticipantName)) + '</td>'
				+ '<td style=\'' + celda + '\'>' + esc(parentesco) + '</td>'
				+ '<td style=\'' + celda + 'text-align:center;\'>' + (edad == null ? '' : String.valueOf(edad)) + '</td>'
				+ '<td style=\'' + celda + 'text-align:right;white-space:nowrap;\'>' + CorreoCotizacionAuto.moneda(prima) + '</td></tr>';
			lista.add('- ' + nombreVisible(m.ParticipantName) + ' (' + parentesco + (edad == null ? '' : ', ' + edad + ' años') + ')');
		}
		Decimal sinIva = (total / (1 + IVA)).setScale(2, System.RoundingMode.HALF_UP);
		Map<String, String> datos = new Map<String, String>{
			'NOMBRE' => f.nombrePila, 'NOMBRE_COMPLETO' => nombreVisible(f.titular.ParticipantName), 'CATEGORIA' => f.categoria,
			'EMPRESA' => e.empresa, 'ASEGURADORA' => e.aseguradora, 'INICIO' => fmt(e.inicio), 'FIN' => fmt(e.fin),
			'PERIODO' => e.inicio.year() + '-' + e.fin.year(), 'FECHA_LIMITE' => fmt(e.fechaLimite),
			'NUM_ASEGURADOS' => String.valueOf(f.miembros.size()), 'LISTA_ASEGURADOS' => String.join(lista, '\n'),
			'PRIMA_NETA' => CorreoCotizacionAuto.moneda(sinIva - e.derecho), 'DERECHO' => CorreoCotizacionAuto.moneda(e.derecho),
			'IVA' => CorreoCotizacionAuto.moneda(total - sinIva), 'TOTAL' => CorreoCotizacionAuto.moneda(total),
			'PRIMA_DIARIA' => CorreoCotizacionAuto.moneda(total / 365)
		};
		datos.putAll(ligas);
		return new Map<String, String>{
			'asunto' => CorreoCotizacionAuto.llenar(tpl.Subject, datos, new Map<String, String>())
				.replace('&amp;', '&').replace('&quot;', '"').replace('&lt;', '<').replace('&gt;', '>'),
			'html' => CorreoCotizacionAuto.llenar(tpl.HtmlValue, datos, new Map<String, String>{ 'FILAS' => filas, 'AVISO_PRUEBA' => '' })
		};
	}

	/**
	 * @creation date: 26/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Familias de la póliza: cada titular vigente con sus dependientes vigentes, su categoría y su correo (el de
	 *               su contacto o cuenta).
	 */
	@TestVisible
	private static List<Familia> familias(Id policyId) {
		List<Familia> r = new List<Familia>();
		Map<Id, Familia> porTitular = new Map<Id, Familia>();
		List<InsurancePolicyParticipant> dependientes = new List<InsurancePolicyParticipant>();
		for (InsurancePolicyParticipant p : [
			SELECT Id, ParticipantName, ParticipantCode, RelatedInsPolicyParticipantId, RelationshipToInsured, Categoria__c, FechaNacimiento__c,
				TermPremiumAmount, StandardPremiumAmount, PrimaryParticipantContactId, PrimaryParticipantAccountId,
				PrimaryParticipantContact.FirstName, PrimaryParticipantContact.Birthdate, IsActiveParticipant
			FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :policyId AND IsActiveParticipant = true
			ORDER BY CreatedDate ASC, Id ASC LIMIT 10000
		]) {
			if (p.RelatedInsPolicyParticipantId != null) { dependientes.add(p); continue; }
			Familia f = new Familia();
			f.titular = p;
			f.miembros.add(p);
			f.categoria = String.isNotBlank(p.Categoria__c) ? p.Categoria__c : '';
			f.nombrePila = primerNombre(p.ParticipantName);
			porTitular.put(p.Id, f);
			r.add(f);
		}
		for (InsurancePolicyParticipant d : dependientes) {
			if (porTitular.containsKey(d.RelatedInsPolicyParticipantId)) { porTitular.get(d.RelatedInsPolicyParticipantId).miembros.add(d); }
		}
		List<InsurancePolicyParticipant> titulares = new List<InsurancePolicyParticipant>();
		for (Familia f : r) { titulares.add(f.titular); }
		Map<Id, String> correos = ParticipantesPolizaController.correosDe(titulares);
		for (Familia f : r) { f.correo = correos.get(f.titular.Id); }
		return r;
	}

	// Motivo por el que no se puede enviar a la familia por su prima; null si todos tienen prima.
	private static String faltaPrima(Familia f) {
		List<String> sin = new List<String>();
		for (InsurancePolicyParticipant m : f.miembros) {
			if (primaDe(m) <= 0) { sin.add(nombreVisible(m.ParticipantName)); }
		}
		return sin.isEmpty() ? null : 'sin prima (' + String.join(sin, ', ') + ').';
	}

	private static Decimal primaDe(InsurancePolicyParticipant m) {
		if (m.TermPremiumAmount != null && m.TermPremiumAmount > 0) { return m.TermPremiumAmount; }
		return m.StandardPremiumAmount == null ? 0 : m.StandardPremiumAmount;
	}

	// Contratante, aseguradora y vigencia de la póliza.
	private static Envio envioDe(Id policyId) {
		List<InsurancePolicy> ps = [
			SELECT EffectiveDate, ExpirationDate, NameInsured.Name, Aseguradora__r.Name, Product.Aseguradora__r.Name
			FROM InsurancePolicy WHERE Id = :policyId LIMIT 1
		];
		if (ps.isEmpty()) { throw CensoColectivoController.error('No se encontró la póliza.'); }
		InsurancePolicy p = ps[0];
		Envio e = new Envio();
		e.empresa = p.NameInsured?.Name;
		e.aseguradora = p.Aseguradora__r?.Name != null ? p.Aseguradora__r.Name : p.Product?.Aseguradora__r?.Name;
		e.inicio = p.EffectiveDate?.date();
		e.fin = p.ExpirationDate?.date();
		return e;
	}

	@TestVisible
	private static Integer edadDe(InsurancePolicyParticipant m) {
		Date nac = m.FechaNacimiento__c != null ? m.FechaNacimiento__c
			: (m.PrimaryParticipantContactId != null ? m.PrimaryParticipantContact.Birthdate : null);
		if (nac == null) { return null; }
		Date hoy = Date.today();
		Integer e = hoy.year() - nac.year();
		if (hoy.month() < nac.month() || (hoy.month() == nac.month() && hoy.day() < nac.day())) { e--; }
		return e;
	}

	// Nombres de pila frecuentes, para saber en qué extremo del nombre completo está el nombre (el censo suele traer
	// «APELLIDOS NOMBRES») y saludar por el nombre.
	static final Set<String> NOMBRES = new Set<String>{
		'ABRAHAM', 'ADRIAN', 'ADRIANA', 'AGUSTIN', 'ALAN', 'ALBERTO', 'ALEJANDRA', 'ALEJANDRO', 'ALFONSO', 'ALFREDO', 'ALICIA', 'ALMA',
		'ANA', 'ANDREA', 'ANDRES', 'ANGEL', 'ANGELICA', 'ANTONIO', 'ARMANDO', 'ARTURO', 'BEATRIZ', 'BENJAMIN', 'BERENICE', 'BLANCA',
		'BRENDA', 'CARLOS', 'CARMEN', 'CAROLINA', 'CECILIA', 'CESAR', 'CLAUDIA', 'CONSUELO', 'CRISTINA', 'DANIEL', 'DANIELA', 'DAVID',
		'DIANA', 'DIEGO', 'DOLORES', 'EDUARDO', 'ELENA', 'ELIZABETH', 'EMILIO', 'EMMANUEL', 'ENRIQUE', 'ERIKA', 'ERNESTO', 'ESTEBAN',
		'ESTELA', 'EUGENIA', 'FABIOLA', 'FERNANDA', 'FERNANDO', 'FRANCISCO', 'GABRIEL', 'GABRIELA', 'GERARDO', 'GILBERTO', 'GLAFIRA', 'GLORIA',
		'GRACIELA', 'GUADALUPE', 'GUILLERMO', 'GUSTAVO', 'HECTOR', 'HUGO', 'IDALIA', 'IGNACIO', 'IRMA', 'ISABEL', 'ISRAEL', 'IVAN',
		'JAIME', 'JAVIER', 'JESUS', 'JORGE', 'JOSE', 'JOSEFINA', 'JUAN', 'JUANA', 'JULIA', 'JULIO', 'KARLA', 'KARINA',
		'LAURA', 'LETICIA', 'LILIANA', 'LORENA', 'LOURDES', 'LUCIA', 'LUIS', 'LUISA', 'LUZ', 'MANUEL', 'MARCELA', 'MARCO',
		'MARGARITA', 'MARIA', 'MARIANA', 'MARIO', 'MARISOL', 'MARTHA', 'MARTIN', 'MAURICIO', 'MICHELLE', 'MIGUEL', 'MONICA', 'NANCY',
		'NORMA', 'OCTAVIO', 'OLGA', 'OMAR', 'OSCAR', 'PABLO', 'PATRICIA', 'PAULA', 'PEDRO', 'RAFAEL', 'RAMON', 'RAUL',
		'REBECA', 'RICARDO', 'ROBERTO', 'RODOLFO', 'ROSA', 'ROSARIO', 'RUBEN', 'SALVADOR', 'SANDRA', 'SANTIAGO', 'SARA', 'SERGIO',
		'SILVIA', 'SOFIA', 'SONIA', 'SUSANA', 'TERESA', 'TOMAS', 'VALERIA', 'VERONICA', 'VICENTE', 'VICTOR', 'VIRGINIA', 'XOCHITL',
		'YOLANDA' };
	// Acentos de nombres y apellidos frecuentes (los censos vienen sin acentos).
	static final Map<String, String> ACENTOS = new Map<String, String>{
		'JOSE' => 'José', 'VICTOR' => 'Víctor', 'RAMON' => 'Ramón', 'JESUS' => 'Jesús', 'MARIA' => 'María', 'RAUL' => 'Raúl', 'HECTOR' => 'Héctor',
		'MARTIN' => 'Martín', 'ANGEL' => 'Ángel', 'ANGELICA' => 'Angélica', 'ANDRES' => 'Andrés', 'AGUSTIN' => 'Agustín', 'ADRIAN' => 'Adrián',
		'BENJAMIN' => 'Benjamín', 'CESAR' => 'César', 'IVAN' => 'Iván', 'LUCIA' => 'Lucía', 'MONICA' => 'Mónica', 'OSCAR' => 'Óscar',
		'RUBEN' => 'Rubén', 'SOFIA' => 'Sofía', 'TOMAS' => 'Tomás', 'VERONICA' => 'Verónica', 'XOCHITL' => 'Xóchitl', 'PEREZ' => 'Pérez',
		'LOPEZ' => 'López', 'GOMEZ' => 'Gómez', 'GONZALEZ' => 'González', 'HERNANDEZ' => 'Hernández', 'RAMIREZ' => 'Ramírez', 'RODRIGUEZ' => 'Rodríguez',
		'MARTINEZ' => 'Martínez', 'SANCHEZ' => 'Sánchez', 'GARCIA' => 'García', 'JIMENEZ' => 'Jiménez', 'GUTIERREZ' => 'Gutiérrez', 'FERNANDEZ' => 'Fernández',
		'DOMINGUEZ' => 'Domínguez', 'DIAZ' => 'Díaz', 'MARQUEZ' => 'Márquez', 'NUNEZ' => 'Núñez', 'ALVAREZ' => 'Álvarez', 'VAZQUEZ' => 'Vázquez',
		'JAUREGUI' => 'Jáuregui', 'LENERO' => 'Leñero', 'RIOS' => 'Ríos', 'MUNOZ' => 'Muñoz', 'PENA' => 'Peña', 'IBANEZ' => 'Ibáñez',
		'SUAREZ' => 'Suárez', 'CHAVEZ' => 'Chávez', 'VELAZQUEZ' => 'Velázquez', 'MENDEZ' => 'Méndez', 'JUAREZ' => 'Juárez', 'BENITEZ' => 'Benítez',
		'CARREON' => 'Carreón', 'LEON' => 'León', 'CORDOVA' => 'Córdova', 'VELEZ' => 'Vélez' };
	static final Set<String> PARTICULAS = new Set<String>{ 'DE', 'DEL', 'LA', 'LAS', 'LOS', 'Y' };

	// Nombre de pila para el saludo: los nombres al final («OCHOA ELIZONDO JOSE RAMON» -> «José Ramón») o al principio
	// («JUAN CARLOS MEDINA HERRERA» -> «Juan Carlos»); si no se reconoce, el nombre completo.
	@TestVisible
	private static String primerNombre(String completo) {
		List<String> t = CensoColectivoController.llave(completo).toUpperCase().split(' ');
		if (t.isEmpty() || String.isBlank(t[0])) { return ''; }
		Integer desde = t.size();
		for (Integer i = t.size() - 1; i > 0; i--) {
			if (NOMBRES.contains(t[i]) || (PARTICULAS.contains(t[i]) && desde < t.size() && i > 1 && NOMBRES.contains(t[i - 1]))) { desde = i; }
			else { break; }
		}
		if (desde < t.size() && !NOMBRES.contains(t[0])) {
			List<String> fin = new List<String>();
			for (Integer i = desde; i < t.size(); i++) { fin.add(t[i]); }
			return nombreVisible(String.join(fin, ' '));
		}
		List<String> ini = new List<String>();
		for (Integer i = 0; i < t.size() - 1; i++) {
			if (NOMBRES.contains(t[i]) || (PARTICULAS.contains(t[i]) && !ini.isEmpty() && NOMBRES.contains(t[i + 1]))) { ini.add(t[i]); }
			else { break; }
		}
		return nombreVisible(String.join(ini.isEmpty() ? t : ini, ' '));
	}

	// «VICTOR MANUEL DE ANDA REYNA» -> «Victor Manuel de Anda Reyna».
	@TestVisible
	private static String nombreVisible(String nombre) {
		if (String.isBlank(nombre)) { return ''; }
		Set<String> menores = new Set<String>{ 'de', 'del', 'la', 'las', 'los', 'y', 'e' };
		List<String> r = new List<String>();
		for (String p : nombre.normalizeSpace().split(' ')) {
			String b = p.toLowerCase();
			String llave = CensoColectivoController.llave(p).toUpperCase();
			r.add(!r.isEmpty() && menores.contains(b) ? b : (ACENTOS.containsKey(llave) && llave == p.toUpperCase() ? ACENTOS.get(llave) : b.capitalize()));
		}
		return String.join(r, ' ');
	}

	// Correos de copia validados: «a@b.com, c@d.com» -> lista (sin repetidos).
	@TestVisible
	private static List<String> correos(String texto) {
		List<String> r = new List<String>();
		if (String.isBlank(texto)) { return r; }
		for (String c : texto.split('[,;\\s]+')) {
			c = c.trim().toLowerCase();
			if (c == '' || r.contains(c)) { continue; }
			if (c.length() > 80 || !Pattern.matches('[^@\\s,;]+@[^@\\s,;]+\\.[^@\\s,;]+', c)) {
				throw CensoColectivoController.error('El correo de copia «' + c + '» no es válido.');
			}
			r.add(c);
		}
		if (r.size() > 5) { throw CensoColectivoController.error('Pon máximo 5 correos de copia.'); }
		return r;
	}

	// 01/12/2026 (no depende del idioma de quien envía).
	private static String fmt(Date d) {
		return d == null ? '' : String.valueOf(d.day()).leftPad(2, '0') + '/' + String.valueOf(d.month()).leftPad(2, '0') + '/' + d.year();
	}

	private static Date fecha(String s) {
		if (String.isBlank(s)) { return null; }
		try { return Date.valueOf(s.left(10)); } catch (Exception e) { return null; }
	}

	private static String esc(String s) {
		return s == null ? '' : s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;').replace('\'', '&#39;');
	}

	/** Ligas públicas de imágenes (documentos de Correos Avanza) y fuentes (recursos estáticos, por el sitio público). */
	private without sharing class Recursos {
		Map<String, String> ligas() {
			Map<String, String> r = new Map<String, String>();
			Map<String, String> porDoc = new Map<String, String>();
			for (String k : IMAGENES) { porDoc.put('Correo_GMM_' + titulo(k), k); r.put('IMG_' + k, ''); }
			for (Document d : [SELECT Id, DeveloperName FROM Document WHERE DeveloperName IN :porDoc.keySet() AND IsPublic = true]) {
				r.put('IMG_' + porDoc.get(d.DeveloperName), Url.getOrgDomainUrl().toExternalForm() + '/servlet/servlet.ImageServer?id='
					+ String.valueOf(d.Id).left(15) + '&oid=' + UserInfo.getOrganizationId().left(15));
			}
			String sitio;
			try { sitio = 'https://' + DomainCreator.getExperienceCloudSitesHostname(); } catch (Exception e) { sitio = null; }
			for (String k : FUENTES) { r.put(k, sitio == null ? '' : sitio + '/resource/Correo_' + titulo(k)); }
			return r;
		}
	}

	// HERO_FONDO -> Hero_Fondo
	private static String titulo(String k) {
		List<String> r = new List<String>();
		for (String p : k.split('_')) { r.add(p.toLowerCase().capitalize()); }
		return String.join(r, '_');
	}
}
