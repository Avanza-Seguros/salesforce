/**
 *   @name: CorreoOportunidadIA
 *   @version: 1.0
 *   @creation date: 18/11/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Redacta con Prompt Builder el correo de la oportunidad que manda las cotizaciones (al cliente o al
 *                 agente) y el de la póliza que manda su documentación. Arma los datos del registro (oportunidad y sus
 *                 cotizaciones, o póliza con su cobranza, coberturas, bienes y asegurados) y los PDFs adjuntos, llama
 *                 al prompt (Correo_Cotizacion_Cliente / _Agente o Correo_Poliza_Cliente / _Agente) y devuelve el
 *                 asunto y el cuerpo HTML con el formato de Avanza.
 */
public with sharing class CorreoOportunidadIA {

	/** Respuesta simulada de la IA en las pruebas (ConnectApi no corre en pruebas). */
	@TestVisible
	private static String respuestaPrueba;

	/** Asunto y cuerpo HTML del correo (cuerpo: solo lo que redactó la IA; html: ya en un marco sencillo de Avanza). */
	public class Correo {
		public String asunto;
		public String cuerpo;
		public String html;
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Redacta el correo con el prompt indicado.
	 * @param prompt: Nombre API del prompt (Correo_Cotizacion_* para una oportunidad, Correo_Poliza_* para una póliza)
	 * @param registroId: Oportunidad de las cotizaciones o póliza (InsurancePolicy)
	 * @param destinatarioId: Contacto o usuario que recibe el correo (para el saludo)
	 * @param adjuntos: Nombres de los PDFs que van adjuntos
	 * @return Asunto y cuerpo HTML
	 */
	public static Correo generar(String prompt, Id registroId, Id destinatarioId, List<String> adjuntos) {
		ConnectApi.WrappedValue datos = new ConnectApi.WrappedValue();
		// En el correo del agente, si su contacto o usuario no se conoce, se saluda con el nombre del agente (Producer).
		Boolean paraAgente = prompt != null && prompt.endsWithIgnoreCase('_Agente');
		datos.value = registroId != null && registroId.getSObjectType() == InsurancePolicy.SObjectType
			? datosPoliza(registroId, destinatarioId, adjuntos, paraAgente)
			: datos(registroId, destinatarioId, adjuntos, paraAgente);
		String texto;
		if (Test.isRunningTest()) {
			texto = respuestaPrueba;
		} else {
			ConnectApi.EinsteinPromptTemplateGenerationsInput entrada = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
			entrada.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
			entrada.additionalConfig.applicationName = 'PromptBuilderPreview';
			entrada.isPreview = false;
			entrada.inputParams = new Map<String, ConnectApi.WrappedValue>{ 'Input:Datos' => datos };
			ConnectApi.EinsteinPromptTemplateGenerationsRepresentation gen =
				ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(prompt, entrada);
			if (gen != null && gen.generations != null && !gen.generations.isEmpty()) {
				texto = gen.generations[0].text;
			}
		}
		return interpretar(texto);
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Datos que recibe el prompt (JSON): oportunidad, cliente, agente, destinatario, cotizaciones y PDFs.
	 * @param oportunidadId: Oportunidad
	 * @param destinatarioId: Contacto o usuario que recibe el correo
	 * @param adjuntos: Nombres de los PDFs adjuntos
	 * @return JSON con los datos
	 */
	@TestVisible
	private static String datos(Id oportunidadId, Id destinatarioId, List<String> adjuntos, Boolean paraAgente) {
		Opportunity o = [
			SELECT Name, toLabel(StageName), toLabel(Ramo__c), Tipo_Contratacion__c, CloseDate, Prima_Total__c, Prima_Neta__c,
				Account.Name, Producer__r.Name, Contacto__r.Name, Owner.Name
			FROM Opportunity WHERE Id = :oportunidadId LIMIT 1
		];
		List<Map<String, Object>> cotizaciones = new List<Map<String, Object>>();
		for (Quote q : [
			SELECT Name, Aseguradora__r.Name, PrimaAnual__c, SumaAsegurada__c, Notas_IA__c, ExpirationDate
			FROM Quote WHERE OpportunityId = :oportunidadId ORDER BY PrimaAnual__c ASC NULLS LAST LIMIT 20
		]) {
			cotizaciones.add(new Map<String, Object>{
				'aseguradora' => q.Aseguradora__r?.Name,
				'plan' => q.Name,
				'primaAnual' => q.PrimaAnual__c,
				'sumaAsegurada' => q.SumaAsegurada__c,
				'notas' => q.Notas_IA__c,
				'vigenteHasta' => q.ExpirationDate
			});
		}
		marcarRecomendada(cotizaciones);
		String[] nombres = nombre(destinatarioId);
		if (paraAgente == true && String.isBlank(nombres[0])) { nombres = nombreDeTexto(o.Producer__r?.Name); }
		return JSON.serialize(new Map<String, Object>{
			'oportunidad' => o.Name,
			'etapa' => o.StageName,
			'ramo' => o.Ramo__c,
			'tipoContratacion' => o.Tipo_Contratacion__c == 'Colectiva' ? 'Empresarial' : o.Tipo_Contratacion__c,
			'primaTotal' => o.Prima_Total__c,
			'primaNeta' => o.Prima_Neta__c,
			'cliente' => o.Account?.Name,
			'contactoCliente' => o.Contacto__r?.Name,
			'agente' => o.Producer__r?.Name,
			'ejecutivo' => o.Owner?.Name,
			'destinatario' => nombres[0],
			'nombreDestinatario' => nombres[1],
			'cotizaciones' => cotizaciones,
			'pdfsAdjuntos' => adjuntos == null ? new List<String>() : adjuntos
		});
	}

	/**
	 * @creation date: 19/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Datos que recibe el prompt del correo de la póliza (JSON): número, situación (nueva, renovacion o
	 *               cancelada), cliente, agente, aseguradora, producto, ramo, vigencia, prima y cobranza (con los días
	 *               que faltan para la fecha límite de pago), coberturas principales, lo que ampara (vehículos o
	 *               ubicaciones; en GMM y Vida las personas por rol), los siguientes pasos del agente (con los datos
	 *               que le faltan a la póliza) y PDFs adjuntos. Lo que depende de reglas se decide aquí para que la IA
	 *               solo lo redacte. Las fechas van ya escritas en español.
	 * @param polizaId: Póliza (InsurancePolicy)
	 * @param destinatarioId: Contacto o usuario que recibe el correo
	 * @param adjuntos: Nombres de los PDFs adjuntos
	 * @return JSON con los datos
	 */
	@TestVisible
	private static String datosPoliza(Id polizaId, Id destinatarioId, List<String> adjuntos, Boolean paraAgente) {
		InsurancePolicy p = [
			SELECT Name, toLabel(Status), toLabel(Ramo__c), toLabel(PremiumFrequency), ProductId, Product.Name,
				Aseguradora__r.Name, NameInsured.Name, Producer.Name, Owner.Name, EffectiveDate, ExpirationDate,
				PremiumAmount, Moneda__c, Numero_Pagos__c, Primer_Pago__c, Pago_Subsecuente__c, Pagos_Subsecuentes__c,
				PaymentDueDate, PolicyDescription, IsRenewedPolicy, SourceOpportunity.Tipo_Contratacion__c,
				SourceOpportunity.Contacto__r.Name
			FROM InsurancePolicy WHERE Id = :polizaId LIMIT 1
		];
		// Coberturas: las de mayor suma asegurada primero (máximo 8 en el correo) y el total.
		List<Map<String, Object>> coberturas = new List<Map<String, Object>>();
		Integer totalCoberturas = 0;
		for (InsurancePolicyCoverage c : [
			SELECT CoverageName, LimitAmount, DeductibleAmount FROM InsurancePolicyCoverage
			WHERE InsurancePolicyId = :polizaId ORDER BY LimitAmount DESC NULLS LAST LIMIT 500
		]) {
			totalCoberturas++;
			if (coberturas.size() < 8) {
				coberturas.add(new Map<String, Object>{
					'nombre' => c.CoverageName, 'sumaAsegurada' => c.LimitAmount, 'deducible' => c.DeductibleAmount
				});
			}
		}
		// Bienes asegurados (vehículos, ubicaciones, bien individual): total y los primeros nombres.
		List<String> bienes = new List<String>();
		Integer totalBienes = 0;
		for (InsurancePolicyAsset a : [
			SELECT AssetName FROM InsurancePolicyAsset WHERE InsurancePolicyId = :polizaId ORDER BY CreatedDate LIMIT 2000
		]) {
			totalBienes++;
			if (bienes.size() < 3 && String.isNotBlank(a.AssetName)) { bienes.add(a.AssetName); }
		}
		// Participantes activos por rol (Asegurado, Beneficiario, Titular...).
		Map<String, Integer> porRol = new Map<String, Integer>();
		for (InsurancePolicyParticipant x : [
			SELECT toLabel(Role) FROM InsurancePolicyParticipant
			WHERE InsurancePolicyId = :polizaId AND IsActiveParticipant = true LIMIT 5000
		]) {
			String rol = String.isBlank(x.Role) ? 'Asegurado' : x.Role;
			porRol.put(rol, (porRol.containsKey(rol) ? porRol.get(rol) : 0) + 1);
		}
		Date fechaPago = soloFecha(p.get('PaymentDueDate'));
		Integer diasPago = fechaPago == null ? null : Date.today().daysBetween(fechaPago);
		List<String> faltantes = new List<String>();
		if (p.ProductId == null) { faltantes.add('producto'); }
		if (p.PremiumAmount == null) { faltantes.add('prima'); }
		if (fechaPago == null) { faltantes.add('fecha límite de pago'); }
		if (totalCoberturas == 0) { faltantes.add('coberturas'); }
		String[] nombres = nombre(destinatarioId);
		if (paraAgente == true && String.isBlank(nombres[0])) { nombres = nombreDeTexto(p.Producer?.Name); }
		String tipo = p.SourceOpportunity?.Tipo_Contratacion__c;
		// Solo una fecha de pago que no ha pasado (si ya pasó, puede estar pagada) y dentro de la vigencia.
		Date finVigencia = soloFecha(p.ExpirationDate);
		Boolean pagoPendiente = diasPago != null && diasPago >= 0 && (finVigencia == null || fechaPago <= finVigencia);
		String situacion = p.Status != null && p.Status.toLowerCase().contains('cancel') ? 'cancelada'
			: (p.IsRenewedPolicy == true ? 'renovacion' : 'nueva');
		// Lo que ampara según el ramo: vehículos (Autos), ubicaciones o bienes (Daños), personas (GMM, Vida).
		String ramo = p.Ramo__c == null ? '' : p.Ramo__c.toLowerCase();
		Boolean deBienes = ramo.contains('auto') || ramo.contains('dañ') || ramo.contains('dan') || ramo.contains('empresarial')
			|| ramo.contains('responsabilidad') || ramo == 'rc';
		String amparo = null;
		if (deBienes && totalBienes > 0) {
			Boolean autos = ramo.contains('auto');
			// Frase completa ("ampara ..."): el prompt la usa tal cual (si solo venía "el vehículo X", la IA lo repetía).
			amparo = 'ampara ' + (totalBienes == 1 && !bienes.isEmpty()
				? (autos ? 'el vehículo ' : 'el bien ') + bienes[0]
				: totalBienes + (autos ? ' vehículos' : ' ubicaciones o bienes'));
		} else if (!deBienes && !porRol.isEmpty()) {
			amparo = 'ampara a ' + personasPorRol(porRol);
		}
		String ejecutivo = String.isNotBlank(p.Owner?.Name) ? p.Owner.Name : 'Avanza Seguro';
		List<String> pasos = new List<String>();
		if (situacion != 'cancelada') {
			pasos.add('Confirmar con el cliente que recibió y revisó su póliza.');
			if (pagoPendiente) {
				pasos.add('Dar seguimiento al primer pago antes del ' + fechaTexto(fechaPago)
					+ (diasPago <= 7 ? ' (faltan ' + diasPago + ' días).' : '.'));
			}
			if (situacion == 'renovacion') { pasos.add('Comentar con el cliente los cambios de la nueva vigencia.'); }
		}
		if (!faltantes.isEmpty()) {
			pasos.add('En Salesforce a la póliza le falta: ' + String.join(faltantes, ', ')
				+ '. Si tienes esa información, compártela con ' + ejecutivo + '.');
		}
		pasos.add('Si detectas alguna inconsistencia en la documentación, repórtala a ' + ejecutivo + '.');
		return JSON.serialize(new Map<String, Object>{
			'numeroPoliza' => p.Name,
			'situacion' => situacion,
			'ramo' => p.Ramo__c,
			'tipoContratacion' => tipo == 'Colectiva' ? 'Empresarial' : tipo,
			'aseguradora' => p.Aseguradora__r?.Name,
			'producto' => p.Product?.Name,
			'descripcion' => p.PolicyDescription,
			'cliente' => p.NameInsured?.Name,
			// El contacto solo si es otra persona (si su nombre trae el del cliente, el correo lo repetiría).
			'contactoCliente' => String.isBlank(p.SourceOpportunity?.Contacto__r?.Name)
				|| (String.isNotBlank(p.NameInsured?.Name)
					&& p.SourceOpportunity.Contacto__r.Name.containsIgnoreCase(p.NameInsured.Name))
				? null : p.SourceOpportunity.Contacto__r.Name,
			'agente' => p.Producer?.Name,
			'ejecutivo' => p.Owner?.Name,
			'destinatario' => nombres[0],
			'nombreDestinatario' => nombres[1],
			'vigenciaDesde' => fechaTexto(soloFecha(p.EffectiveDate)),
			'vigenciaHasta' => fechaTexto(soloFecha(p.ExpirationDate)),
			'primaTotal' => p.PremiumAmount,
			'moneda' => moneda(p.Moneda__c),
			'formaPago' => p.PremiumFrequency,
			'numeroPagos' => p.Numero_Pagos__c,
			'primerPago' => p.Primer_Pago__c,
			'pagoSubsecuente' => p.Pago_Subsecuente__c,
			'pagosSubsecuentes' => p.Pagos_Subsecuentes__c,
			'fechaLimitePago' => pagoPendiente ? fechaTexto(fechaPago) : null,
			'diasParaFechaLimitePago' => pagoPendiente ? diasPago : null,
			'coberturasPrincipales' => coberturas,
			'totalCoberturas' => totalCoberturas,
			'amparo' => amparo,
			'pasosAgente' => pasos,
			'pdfsAdjuntos' => adjuntos == null ? new List<String>() : adjuntos
		});
	}

	// "15 asegurados y 9 miembros familiares": personas por rol, de la mayor cantidad a la menor.
	@TestVisible
	private static String personasPorRol(Map<String, Integer> porRol) {
		List<String> roles = new List<String>(porRol.keySet());
		for (Integer i = 0; i < roles.size(); i++) {
			for (Integer j = i + 1; j < roles.size(); j++) {
				if (porRol.get(roles[j]) > porRol.get(roles[i])) { String t = roles[i]; roles[i] = roles[j]; roles[j] = t; }
			}
		}
		List<String> partes = new List<String>();
		for (String r : roles) {
			Integer n = porRol.get(r);
			partes.add(n + ' ' + (n == 1 ? r.toLowerCase() : plural(r.toLowerCase())));
		}
		if (partes.size() == 1) { return partes[0]; }
		String ultima = partes.remove(partes.size() - 1);
		return String.join(partes, ', ') + ' y ' + ultima;
	}

	// Plural en español palabra por palabra ("miembro familiar" -> "miembros familiares").
	private static String plural(String texto) {
		List<String> r = new List<String>();
		for (String w : texto.split(' ')) {
			if (String.isBlank(w) || w.length() < 3) { r.add(w); continue; }
			String u = w.right(1);
			if ('aeiouáéó'.contains(u)) { r.add(w + 's'); }
			else if (u == 's') { r.add(w); }
			else if (u == 'z') { r.add(w.left(w.length() - 1) + 'ces'); }
			else { r.add(w + 'es'); }
		}
		return String.join(r, ' ');
	}

	// Fecha de un campo Date o Fecha/Hora (las fechas de la póliza se guardan a mediodía GMT).
	private static Date soloFecha(Object v) {
		if (v instanceof Datetime) { return ((Datetime) v).date(); }
		return v instanceof Date ? (Date) v : null;
	}

	private static final List<String> MESES = new List<String>{ 'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
		'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre' };

	// "15 de enero de 2027".
	@TestVisible
	private static String fechaTexto(Date d) {
		return d == null ? null : d.day() + ' de ' + MESES[d.month() - 1] + ' de ' + d.year();
	}

	// Moneda de la póliza como MXN, USD o UDI (la carátula la trae como "PESOS", "DÓLARES"...).
	@TestVisible
	private static String moneda(String m) {
		String s = m == null ? '' : m.toUpperCase();
		if (s.contains('USD') || s.contains('DOLAR') || s.contains('DÓLAR')) { return 'USD'; }
		if (s.contains('UDI')) { return 'UDI'; }
		return 'MXN';
	}

	// Nombre completo y nombre de pila del contacto o usuario que recibe el correo.
	private static String[] nombre(Id destinatarioId) {
		String[] r = new String[]{ null, null };
		if (destinatarioId == null) { return r; }
		String tipo = destinatarioId.getSObjectType().getDescribe().getName();
		if (tipo == 'Contact') {
			for (Contact c : [SELECT Name, FirstName FROM Contact WHERE Id = :destinatarioId LIMIT 1]) {
				r = new String[]{ c.Name, c.FirstName };
			}
		} else if (tipo == 'User') {
			for (User u : [SELECT Name, FirstName FROM User WHERE Id = :destinatarioId LIMIT 1]) {
				r = new String[]{ u.Name, u.FirstName };
			}
		}
		// Saludo con la primera palabra del nombre (hay contactos con el nombre completo en FirstName), con mayúscula inicial.
		r[1] = primeraPalabra(String.isNotBlank(r[1]) ? r[1] : r[0]);
		return r;
	}

	// Nombre completo y nombre de pila a partir de un nombre en texto (el del agente, Producer, si no hay contacto ni usuario).
	@TestVisible
	private static String[] nombreDeTexto(String completo) {
		return new String[]{ String.isBlank(completo) ? null : completo.trim(), primeraPalabra(completo) };
	}

	// Primera palabra del nombre con mayúscula inicial ("ABRAHAM GONZALEZ" -> "Abraham").
	private static String primeraPalabra(String nombre) {
		if (String.isBlank(nombre)) { return null; }
		String primera = nombre.trim().split('\\s+')[0].toLowerCase();
		return primera.left(1).toUpperCase() + primera.substring(1);
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Marca la cotización recomendada (la misma en el correo del cliente y en el del agente): la de menor
	 *               prima, salvo que otra dé más suma asegurada con una prima a lo más 10% mayor (entonces la de mayor
	 *               suma asegurada de esas). Pone "recomendada" y "motivoRecomendacion".
	 * @param cotizaciones: Cotizaciones ordenadas de menor a mayor prima
	 * @return void
	 */
	public static void marcarRecomendada(List<Map<String, Object>> cotizaciones) {
		Map<String, Object> menor = null;
		for (Map<String, Object> c : cotizaciones) {
			if (c.get('primaAnual') != null) { menor = c; break; }
		}
		if (menor == null) { return; }
		Decimal prima = (Decimal) menor.get('primaAnual');
		Decimal suma = menor.get('sumaAsegurada') == null ? 0 : (Decimal) menor.get('sumaAsegurada');
		Map<String, Object> elegida = menor;
		for (Map<String, Object> c : cotizaciones) {
			Decimal p = (Decimal) c.get('primaAnual');
			Decimal sa = (Decimal) c.get('sumaAsegurada');
			if (p != null && sa != null && sa > suma && p <= prima * 1.10) {
				elegida = c;
				suma = sa;
			}
		}
		elegida.put('recomendada', true);
		elegida.put('motivoRecomendacion', elegida == menor ? 'Es la opción con la prima más baja.'
			: 'Da mayor suma asegurada por una prima muy similar a la más baja.');
	}

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Lee la respuesta de la IA ({"asunto": "...", "cuerpo_html": "..."}) y pone el cuerpo en el formato
	 *               de correo de Avanza.
	 * @param texto: Respuesta de la IA
	 * @return Asunto y cuerpo HTML
	 */
	@TestVisible
	private static Correo interpretar(String texto) {
		if (String.isBlank(texto)) { throw new CorreoIAException('La IA no devolvió el correo.'); }
		String limpio = texto.trim();
		Integer ini = limpio.indexOf('{');
		Integer fin = limpio.lastIndexOf('}');
		if (ini < 0 || fin <= ini) { throw new CorreoIAException('La IA no devolvió el correo en el formato esperado.'); }
		Map<String, Object> r = (Map<String, Object>) JSON.deserializeUntyped(limpio.substring(ini, fin + 1));
		String asunto = r.get('asunto') == null ? null : String.valueOf(r.get('asunto')).trim();
		String cuerpo = r.get('cuerpo_html') == null ? null : String.valueOf(r.get('cuerpo_html'));
		if (String.isBlank(asunto) || String.isBlank(cuerpo)) {
			throw new CorreoIAException('La IA no devolvió el asunto o el cuerpo del correo.');
		}
		Correo c = new Correo();
		c.asunto = asunto.left(200);
		c.cuerpo = cuerpo;
		c.html = '<html><body style="margin:0;padding:0;background:#f4f6f9;">'
			+ '<table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f6f9;"><tr><td align="center" style="padding:24px 12px;">'
			+ '<table width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#ffffff;border-radius:6px;">'
			+ '<tr><td style="background:#2980b9;color:#ffffff;padding:18px 28px;font-family:Arial,Helvetica,sans-serif;'
			+ 'font-size:20px;font-weight:bold;border-radius:6px 6px 0 0;">Avanza Seguro</td></tr>'
			+ '<tr><td style="padding:24px 28px;font-family:Arial,Helvetica,sans-serif;font-size:15px;line-height:1.5;color:#333333;">'
			+ cuerpo
			+ '</td></tr></table></td></tr></table></body></html>';
		return c;
	}

	public class CorreoIAException extends Exception {}
}
