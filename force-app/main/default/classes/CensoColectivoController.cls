/**
 * @creation date: 12/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Censo de asegurados de una oportunidad COLECTIVA (cualquier ramo). Usa los objetos
 *               estándar de FSC: GroupCensus (censo, ligado a la oportunidad por Oportunidad__c),
 *               GroupClass (categoría, de la empresa contratante) y GroupCensusMember (asegurado
 *               titular o dependiente). El archivo (Excel, CSV o PDF) se lee en el LWC censoColectivo;
 *               aquí se guarda, se consulta el resumen y se pide a la IA la lectura de censos en PDF.
 */
public with sharing class CensoColectivoController {

	// Prompt Template (Prompt Builder) que lee censos en PDF y su variable de entrada.
	private static final String PROMPT_TEMPLATE_API_NAME = 'Extractor_Censo_Colectivo';
	private static final String PROMPT_INPUT_PARAM = 'Input:TextoCenso';
	// Límite de asegurados por carga (dos inserts + borrado deben caber en 10,000 filas DML).
	@TestVisible private static final Integer MAX_MIEMBROS = 4500;
	// Asegurados que se regresan al LWC para la tabla (el resumen sí cuenta a todos).
	private static final Integer MAX_MIEMBROS_VISTA = 500;
	private static final String SIN_CATEGORIA = 'Sin categoría';
	// Valores de RelationshipToPrimaryMember para cada AssociationWithPrimaryMbr. En dev el picklist quedó
	// con valores API traducidos (Child = "Secundario", Parent = "Principal"); se prueban ambos en orden.
	private static final Map<String, List<String>> RELACION_POR_ASOCIACION = new Map<String, List<String>>{
		'Spouse' => new List<String>{ 'Spouse', 'Cónyuge' },
		'Child' => new List<String>{ 'Child', 'Secundario' },
		'Parent' => new List<String>{ 'Parent', 'Principal' },
		'Parent-in-law' => new List<String>{ 'Parent-in-law', 'ParentInLaw', 'Suegro' },
		'Other' => new List<String>{ 'Other', 'Otros' }
	};

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Renglón del censo que envía el LWC (ya validado y normalizado en el navegador).
	 */
	public class MiembroEntrada {
		public String nombreCompleto;
		public String nombre;
		public String apellidos;
		public String fechaNacimiento;
		public Decimal edad;
		public String sexo;
		public String parentesco;
		public String categoria;
		public Decimal sueldoAnual;
		public Decimal sumaAsegurada;
		public Decimal prima;
		public String certificado;
		public String fechaAlta;
		public String numEmpleado;
		public String rfc;
		public String email;
		public String telefono;
		// Índice (en la misma lista) del titular de un dependiente; null en titulares.
		public Integer titularIndex;
		// Número de fila del archivo, solo para mensajes de error.
		public Integer fila;
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve el censo de la oportunidad: totales, resumen por categoría y los primeros
	 *               asegurados para mostrarlos en la tabla.
	 * @param opportunityId: Id de la oportunidad colectiva.
	 * @return mapa con censoId, total, titulares, dependientes, categorias y miembros; censoId null si no hay censo.
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> getCenso(Id opportunityId) {
		Map<String, Object> res = new Map<String, Object>{
			'censoId' => null, 'total' => 0, 'titulares' => 0, 'dependientes' => 0,
			'categorias' => new List<Object>(), 'miembros' => new List<Object>()
		};
		GroupCensus censo = censoDe(opportunityId);
		if (censo == null) { return res; }
		res.put('censoId', censo.Id);
		res.put('nombre', censo.Name);

		List<GroupCensusMember> miembros = [
			SELECT Id, Name, Birthdate, Gender, GroupClass.Name, AssociationWithPrimaryMbr,
				PrimaryGroupCensusMember.Name, AnnualEligibleSalary, SourceSystemIdentifier,
				Certificado__c, RFC__c, Edad__c, Suma_Asegurada__c, Prima__c, JoinDate
			FROM GroupCensusMember
			WHERE GroupCensusId = :censo.Id
			ORDER BY CreatedDate ASC, Id ASC
			LIMIT 10000
		];
		miembros = porFamilia(miembros);

		Map<String, Map<String, Object>> porCategoria = new Map<String, Map<String, Object>>();
		Map<String, Integer> edadesContadas = new Map<String, Integer>();
		Integer titulares = 0;
		List<Object> vista = new List<Object>();
		for (GroupCensusMember m : miembros) {
			String cat = m.GroupClass != null && String.isNotBlank(m.GroupClass.Name) ? m.GroupClass.Name : SIN_CATEGORIA;
			Boolean esTitular = m.PrimaryGroupCensusMemberId == null;
			if (esTitular) { titulares++; }
			Integer edad = edadDe(m);

			Map<String, Object> c = porCategoria.get(cat);
			if (c == null) {
				c = new Map<String, Object>{ 'nombre' => cat, 'titulares' => 0, 'dependientes' => 0,
					'sumaEdades' => 0, 'sueldoTotal' => 0.0, 'sumaAseguradaTotal' => 0.0, 'primaTotal' => 0.0 };
				porCategoria.put(cat, c);
				edadesContadas.put(cat, 0);
			}
			c.put(esTitular ? 'titulares' : 'dependientes', (Integer) c.get(esTitular ? 'titulares' : 'dependientes') + 1);
			if (edad != null) {
				c.put('sumaEdades', (Integer) c.get('sumaEdades') + edad);
				edadesContadas.put(cat, edadesContadas.get(cat) + 1);
			}
			if (m.AnnualEligibleSalary != null) { c.put('sueldoTotal', (Decimal) c.get('sueldoTotal') + m.AnnualEligibleSalary); }
			if (m.Suma_Asegurada__c != null) { c.put('sumaAseguradaTotal', (Decimal) c.get('sumaAseguradaTotal') + m.Suma_Asegurada__c); }
			if (m.Prima__c != null) { c.put('primaTotal', (Decimal) c.get('primaTotal') + m.Prima__c); }

			if (vista.size() < MAX_MIEMBROS_VISTA) {
				vista.add(new Map<String, Object>{
					'id' => m.Id, 'nombre' => m.Name, 'parentesco' => parentescoVisible(m.AssociationWithPrimaryMbr, esTitular),
					'titular' => esTitular ? null : (m.PrimaryGroupCensusMember != null ? m.PrimaryGroupCensusMember.Name : null),
					'categoria' => cat, 'fechaNacimiento' => m.Birthdate, 'edad' => edad, 'sexo' => m.Gender,
					'certificado' => m.Certificado__c, 'numEmpleado' => m.SourceSystemIdentifier,
					'sueldoAnual' => m.AnnualEligibleSalary, 'sumaAsegurada' => m.Suma_Asegurada__c, 'prima' => m.Prima__c,
					'fechaAlta' => m.JoinDate, 'rfc' => m.RFC__c
				});
			}
		}
		List<Object> categorias = new List<Object>();
		for (String cat : porCategoria.keySet()) {
			Map<String, Object> c = porCategoria.get(cat);
			Integer n = edadesContadas.get(cat);
			c.put('edadPromedio', n > 0 ? Decimal.valueOf((Integer) c.get('sumaEdades')).divide(n, 1) : null);
			c.remove('sumaEdades');
			categorias.add(c);
		}
		res.put('total', miembros.size());
		res.put('titulares', titulares);
		res.put('dependientes', miembros.size() - titulares);
		res.put('categorias', categorias);
		res.put('miembros', vista);
		return res;
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Guarda el censo de la oportunidad. Crea el GroupCensus si no existe, las categorías
	 *               (GroupClass de la empresa) que falten y los asegurados: primero titulares y después
	 *               dependientes ligados a su titular. Todo o nada: si un renglón falla, no se guarda nada.
	 * @param opportunityId: Id de la oportunidad colectiva (debe tener cliente/empresa).
	 * @param miembrosJson: JSON con la lista de MiembroEntrada.
	 * @param reemplazar: true borra los asegurados actuales del censo antes de cargar; false los agrega.
	 * @return número total de asegurados del censo después de guardar.
	 */
	@AuraEnabled(cacheable=false)
	public static Integer guardarCenso(Id opportunityId, String miembrosJson, Boolean reemplazar) {
		List<MiembroEntrada> entrada;
		try {
			entrada = (List<MiembroEntrada>) JSON.deserialize(String.isBlank(miembrosJson) ? '[]' : miembrosJson, List<MiembroEntrada>.class);
		} catch (Exception e) {
			throw error('El censo no tiene un formato válido: ' + e.getMessage());
		}
		if (entrada.isEmpty()) { throw error('El censo no tiene asegurados para guardar.'); }
		if (entrada.size() > MAX_MIEMBROS) {
			throw error('El censo tiene ' + entrada.size() + ' asegurados; el máximo por carga es ' + MAX_MIEMBROS
				+ '. Divide el archivo y usa la opción "Agregar al censo".');
		}

		List<Opportunity> opps = [SELECT Id, Name, AccountId FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
		if (opps.isEmpty()) { throw error('No se encontró la oportunidad.'); }
		Opportunity opp = opps[0];
		if (opp.AccountId == null) {
			throw error('La oportunidad no tiene cliente. En una póliza colectiva el cliente es la empresa contratante: asígnalo y guarda la oportunidad antes de cargar el censo.');
		}

		Savepoint sp = Database.setSavepoint();
		try {
			GroupCensus censo = censoDe(opportunityId);
			if (censo == null) {
				censo = new GroupCensus(AccountId = opp.AccountId, Oportunidad__c = opp.Id);
				setTexto(censo, 'Name', 'Censo - ' + opp.Name);
				setPicklist(censo, 'Status', 'Draft');
				setPicklist(censo, 'Type', 'Quote');
				insert censo;
			} else if (reemplazar == true) {
				// Primero dependientes y luego titulares (los dependientes apuntan a su titular).
				delete [SELECT Id FROM GroupCensusMember WHERE GroupCensusId = :censo.Id AND PrimaryGroupCensusMemberId != null];
				delete [SELECT Id FROM GroupCensusMember WHERE GroupCensusId = :censo.Id];
			}

			Map<String, Id> categorias = categoriasDe(opp.AccountId, entrada);

			// Titulares primero para tener su Id al ligar a los dependientes.
			Map<Integer, GroupCensusMember> titulares = new Map<Integer, GroupCensusMember>();
			List<GroupCensusMember> listaTitulares = new List<GroupCensusMember>();
			List<Integer> filasTitulares = new List<Integer>();
			for (Integer i = 0; i < entrada.size(); i++) {
				MiembroEntrada e = entrada[i];
				if (e.titularIndex != null) { continue; }
				GroupCensusMember m = miembro(e, censo.Id, categorias);
				titulares.put(i, m);
				listaTitulares.add(m);
				filasTitulares.add(e.fila);
			}
			insertarConFila(listaTitulares, filasTitulares);

			List<GroupCensusMember> dependientes = new List<GroupCensusMember>();
			List<Integer> filasDependientes = new List<Integer>();
			for (Integer i = 0; i < entrada.size(); i++) {
				MiembroEntrada e = entrada[i];
				if (e.titularIndex == null) { continue; }
				GroupCensusMember titular = titulares.get(e.titularIndex);
				if (titular == null) {
					throw error('Fila ' + e.fila + ': el dependiente no tiene un titular válido en el censo.');
				}
				GroupCensusMember m = miembro(e, censo.Id, categorias);
				m.PrimaryGroupCensusMemberId = titular.Id;
				if (m.GroupClassId == null) { m.GroupClassId = titular.GroupClassId; }
				dependientes.add(m);
				filasDependientes.add(e.fila);
			}
			insertarConFila(dependientes, filasDependientes);

			return [SELECT COUNT() FROM GroupCensusMember WHERE GroupCensusId = :censo.Id];
		} catch (AuraHandledException ahe) {
			Database.rollback(sp);
			throw ahe;
		} catch (Exception e) {
			Database.rollback(sp);
			throw error('No se pudo guardar el censo: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Elimina el censo de la oportunidad con todos sus asegurados. Las categorías
	 *               (GroupClass) se conservan porque son de la empresa y se reutilizan.
	 * @param opportunityId: Id de la oportunidad colectiva.
	 */
	@AuraEnabled(cacheable=false)
	public static void eliminarCenso(Id opportunityId) {
		GroupCensus censo = censoDe(opportunityId);
		if (censo == null) { return; }
		try {
			delete [SELECT Id FROM GroupCensusMember WHERE GroupCensusId = :censo.Id AND PrimaryGroupCensusMemberId != null];
			delete [SELECT Id FROM GroupCensusMember WHERE GroupCensusId = :censo.Id];
			delete censo;
		} catch (Exception e) {
			throw error('No se pudo eliminar el censo: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Envía a Einstein (Prompt Template Extractor_Censo_Colectivo) el texto de un bloque
	 *               de páginas de un censo en PDF y devuelve el JSON con los asegurados. El LWC parte
	 *               los PDFs largos en bloques y llama a este método una vez por bloque.
	 * @param textoCenso: texto del bloque (extraído con pdf.js en el navegador).
	 * @return JSON {"asegurados":[...]} limpio de fences de código.
	 */
	@AuraEnabled(cacheable=false)
	public static String analizarCensoPdf(String textoCenso) {
		if (String.isBlank(textoCenso)) { throw error('No se recibió texto del censo para analizar.'); }
		if (Test.isRunningTest()) { return '{"asegurados":[]}'; }
		try {
			// Los nombres que en el PDF ocupan dos renglones se unen antes de la IA (si no, los toma como otros asegurados).
			String texto = unirNombresPartidos(textoCenso);
			ConnectApi.WrappedValue wrapped = new ConnectApi.WrappedValue();
			wrapped.value = texto.length() > 60000 ? texto.substring(0, 60000) : texto;
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
			throw error('La IA no devolvió asegurados de este bloque del censo.');
		} catch (AuraHandledException ahe) {
			throw ahe;
		} catch (Exception e) {
			throw error('Error al analizar el censo: ' + e.getMessage());
		}
	}

	// ============================================================
	// Helpers
	// ============================================================

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Censo (GroupCensus) ligado a la oportunidad, el más reciente si hubiera varios.
	 * @param opportunityId: Id de la oportunidad.
	 * @return GroupCensus o null si la oportunidad aún no tiene censo.
	 */
	private static GroupCensus censoDe(Id opportunityId) {
		if (opportunityId == null) { return null; }
		List<GroupCensus> l = [SELECT Id, Name FROM GroupCensus WHERE Oportunidad__c = :opportunityId ORDER BY CreatedDate DESC LIMIT 1];
		return l.isEmpty() ? null : l[0];
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Ordena los asegurados por familia: cada titular seguido de sus dependientes.
	 * @param miembros: asegurados en orden de alta.
	 * @return asegurados ordenados (los dependientes sin titular en la lista van al final).
	 */
	private static List<GroupCensusMember> porFamilia(List<GroupCensusMember> miembros) {
		Map<Id, List<GroupCensusMember>> dependientes = new Map<Id, List<GroupCensusMember>>();
		for (GroupCensusMember m : miembros) {
			if (m.PrimaryGroupCensusMemberId == null) { continue; }
			if (!dependientes.containsKey(m.PrimaryGroupCensusMemberId)) {
				dependientes.put(m.PrimaryGroupCensusMemberId, new List<GroupCensusMember>());
			}
			dependientes.get(m.PrimaryGroupCensusMemberId).add(m);
		}
		List<GroupCensusMember> res = new List<GroupCensusMember>();
		for (GroupCensusMember m : miembros) {
			if (m.PrimaryGroupCensusMemberId != null) { continue; }
			res.add(m);
			if (dependientes.containsKey(m.Id)) { res.addAll(dependientes.remove(m.Id)); }
		}
		for (List<GroupCensusMember> huerfanos : dependientes.values()) { res.addAll(huerfanos); }
		return res;
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Busca las categorías del censo entre las GroupClass de la empresa (sin importar
	 *               mayúsculas ni acentos) y crea las que no existan.
	 * @param accountId: empresa contratante.
	 * @param entrada: renglones del censo.
	 * @return mapa llave normalizada de la categoría -> Id de GroupClass.
	 */
	private static Map<String, Id> categoriasDe(Id accountId, List<MiembroEntrada> entrada) {
		Map<String, String> nuevas = new Map<String, String>();
		for (MiembroEntrada e : entrada) {
			if (String.isNotBlank(e.categoria)) { nuevas.put(llave(e.categoria), e.categoria.normalizeSpace()); }
		}
		Map<String, Id> res = new Map<String, Id>();
		if (nuevas.isEmpty()) { return res; }
		for (GroupClass gc : [SELECT Id, Name FROM GroupClass WHERE AccountId = :accountId LIMIT 2000]) {
			String k = llave(gc.Name);
			if (!res.containsKey(k)) { res.put(k, gc.Id); }
		}
		List<GroupClass> crear = new List<GroupClass>();
		for (String k : nuevas.keySet()) {
			if (res.containsKey(k)) { continue; }
			GroupClass gc = new GroupClass(AccountId = accountId);
			setTexto(gc, 'Name', nuevas.get(k));
			// FSC no permite dos GroupClass de la misma cuenta con el mismo Code (vacío cuenta como igual).
			setTexto(gc, 'Code', k.toUpperCase());
			crear.add(gc);
		}
		if (!crear.isEmpty()) {
			insert crear;
			for (GroupClass gc : crear) { res.put(llave(gc.Name), gc.Id); }
		}
		return res;
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma el GroupCensusMember a partir de un renglón del censo.
	 * @param e: renglón del censo.
	 * @param censoId: GroupCensus al que pertenece.
	 * @param categorias: llave de categoría -> Id de GroupClass.
	 * @return GroupCensusMember sin insertar.
	 */
	private static GroupCensusMember miembro(MiembroEntrada e, Id censoId, Map<String, Id> categorias) {
		GroupCensusMember m = new GroupCensusMember(GroupCensusId = censoId);
		String nombre = e.nombre == null ? null : e.nombre.normalizeSpace();
		String apellidos = e.apellidos == null ? null : e.apellidos.normalizeSpace();
		nombre = sinPalabraRepetida(nombre, apellidos);
		// Con nombre y apellidos separados, el nombre completo se arma en orden natural (el de la IA puede venir revuelto
		// cuando el nombre se partió en dos renglones del PDF); si no, se usa el nombre completo tal cual.
		String completo = String.isNotBlank(nombre) && String.isNotBlank(apellidos)
			? nombre + ' ' + apellidos
			: (String.isNotBlank(e.nombreCompleto)
				? e.nombreCompleto.normalizeSpace()
				: ((nombre == null ? '' : nombre) + ' ' + (apellidos == null ? '' : apellidos)).normalizeSpace());
		if (String.isBlank(completo)) { throw error('Fila ' + e.fila + ': el asegurado no tiene nombre.'); }
		if (String.isBlank(nombre) && String.isBlank(apellidos)) {
			List<String> partes = completo.split(' ');
			if (partes.size() == 1) {
				apellidos = partes[0];
			} else if (partes.size() == 2) {
				nombre = partes[0];
				apellidos = partes[1];
			} else {
				nombre = String.join(sublista(partes, 0, partes.size() - 2), ' ');
				apellidos = String.join(sublista(partes, partes.size() - 2, partes.size()), ' ');
			}
		}
		setTexto(m, 'Name', completo);
		setTexto(m, 'FirstName', String.isBlank(nombre) ? '-' : nombre.normalizeSpace());
		setTexto(m, 'Lastname', String.isBlank(apellidos) ? completo : apellidos.normalizeSpace());
		m.Birthdate = fecha(e.fechaNacimiento);
		// FSC solo acepta la fecha de alta en el titular; el dependiente toma la de su titular.
		if (e.titularIndex == null) { m.JoinDate = fecha(e.fechaAlta); }
		if (e.edad != null && e.edad >= 0 && e.edad < 130) { m.Edad__c = e.edad.round(System.RoundingMode.DOWN); }
		if (e.sueldoAnual != null) { m.AnnualEligibleSalary = e.sueldoAnual; }
		if (e.sumaAsegurada != null) { m.Suma_Asegurada__c = e.sumaAsegurada; }
		if (e.prima != null) { m.Prima__c = e.prima; }
		setPicklist(m, 'Gender', e.sexo);
		// FSC: el titular va SIN parentesco (si lo trae, exige un titular); el dependiente lleva ambos campos.
		if (e.titularIndex != null) {
			String asoc = asociacion(e.parentesco, false);
			setPicklist(m, 'AssociationWithPrimaryMbr', asoc);
			for (String v : RELACION_POR_ASOCIACION.get(asoc)) {
				setPicklist(m, 'RelationshipToPrimaryMember', v);
				if (m.get('RelationshipToPrimaryMember') != null) { break; }
			}
		}
		setTexto(m, 'Certificado__c', e.certificado);
		setTexto(m, 'SourceSystemIdentifier', e.numEmpleado);
		setTexto(m, 'RFC__c', e.rfc == null ? null : e.rfc.deleteWhitespace().toUpperCase());
		setTexto(m, 'PhoneNumber', e.telefono);
		if (String.isNotBlank(e.email) && Pattern.matches('[^@\\s]+@[^@\\s]+\\.[^@\\s]+', e.email.trim())) {
			m.Email = e.email.trim();
		}
		if (String.isNotBlank(e.categoria)) { m.GroupClassId = categorias.get(llave(e.categoria)); }
		return m;
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Inserta los asegurados y, si alguno falla, reporta la fila del archivo con el error.
	 * @param registros: asegurados a insertar.
	 * @param filas: número de fila del archivo de cada asegurado (mismo orden).
	 */
	private static void insertarConFila(List<GroupCensusMember> registros, List<Integer> filas) {
		if (registros.isEmpty()) { return; }
		try {
			insert registros;
		} catch (DmlException de) {
			Integer idx = de.getDmlIndex(0);
			Integer fila = (idx != null && idx < filas.size()) ? filas[idx] : null;
			throw error((fila != null ? 'Fila ' + fila + ': ' : '') + de.getDmlMessage(0));
		}
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Traduce el parentesco del censo al valor de AssociationWithPrimaryMbr
	 *               (Self, Spouse, Child, Parent, Parent-in-law, Other).
	 * @param parentesco: parentesco normalizado por el LWC (Titular, Cónyuge, Hijo(a), ...).
	 * @param esTitular: true si el renglón es titular.
	 * @return valor del picklist en inglés.
	 */
	@TestVisible
	private static String asociacion(String parentesco, Boolean esTitular) {
		if (esTitular) { return 'Self'; }
		String p = llave(parentesco);
		if (p.startsWith('conyuge') || p.startsWith('espos') || p.startsWith('concubin') || p == 'pareja') { return 'Spouse'; }
		if (p.startsWith('hij')) { return 'Child'; }
		if (p.startsWith('suegr')) { return 'Parent-in-law'; }
		if (p.startsWith('padre') || p.startsWith('madre')) { return 'Parent'; }
		return 'Other';
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Texto en español del parentesco guardado, para mostrarlo en la tabla.
	 * @param valor: valor de AssociationWithPrimaryMbr.
	 * @param esTitular: true si el asegurado no tiene titular.
	 * @return parentesco en español.
	 */
	@TestVisible
	private static String parentescoVisible(String valor, Boolean esTitular) {
		if (esTitular || valor == 'Self') { return 'Titular'; }
		Map<String, String> m = new Map<String, String>{
			'Spouse' => 'Cónyuge', 'Child' => 'Hijo(a)', 'Parent' => 'Padre/Madre', 'Parent-in-law' => 'Suegro(a)'
		};
		return m.containsKey(valor) ? m.get(valor) : 'Otro';
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Edad del asegurado: calculada con la fecha de nacimiento o la del censo (Edad__c).
	 * @param m: asegurado.
	 * @return edad en años o null.
	 */
	private static Integer edadDe(GroupCensusMember m) {
		if (m.Birthdate != null) {
			Date hoy = Date.today();
			Integer e = hoy.year() - m.Birthdate.year();
			if (hoy.month() < m.Birthdate.month() || (hoy.month() == m.Birthdate.month() && hoy.day() < m.Birthdate.day())) { e--; }
			return e;
		}
		return m.Edad__c == null ? null : m.Edad__c.intValue();
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Convierte "YYYY-MM-DD" a Date; null si viene vacío o no es válida.
	 * @param s: fecha en formato ISO.
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
	 * @description: Llave para comparar textos: minúsculas, sin acentos y sin espacios repetidos.
	 * @param s: texto.
	 * @return texto normalizado ('' si viene vacío).
	 */
	@TestVisible
	private static String llave(String s) {
		if (String.isBlank(s)) { return ''; }
		return s.toLowerCase().replace('á', 'a').replace('é', 'e').replace('í', 'i').replace('ó', 'o')
			.replace('ú', 'u').replace('ü', 'u').replace('ñ', 'n').normalizeSpace();
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Asigna un texto recortado a la longitud del campo (evita errores de "data value too large").
	 * @param so: registro.
	 * @param campo: API name del campo de texto.
	 * @param valor: texto a asignar (vacío = no se asigna).
	 */
	private static void setTexto(SObject so, String campo, String valor) {
		if (String.isBlank(valor)) { return; }
		Schema.DescribeFieldResult f = campoDe(so, campo);
		Integer largo = f.getLength();
		String v = valor.trim();
		so.put(campo, largo > 0 && v.length() > largo ? v.left(largo) : v);
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Asigna un valor de picklist solo si existe en el campo (comparando valor y etiqueta,
	 *               sin acentos). Acepta "Hombre"/"Mujer" aunque el valor API esté en inglés.
	 * @param so: registro.
	 * @param campo: API name del picklist.
	 * @param valor: valor deseado.
	 */
	private static void setPicklist(SObject so, String campo, String valor) {
		if (String.isBlank(valor)) { return; }
		Set<String> buscados = new Set<String>{ llave(valor) };
		if (llave(valor) == 'hombre') { buscados.add('male'); buscados.add('masculino'); }
		if (llave(valor) == 'mujer') { buscados.add('female'); buscados.add('femenino'); }
		Schema.DescribeFieldResult f = campoDe(so, campo);
		for (Schema.PicklistEntry pe : f.getPicklistValues()) {
			if (pe.isActive() && (buscados.contains(llave(pe.getValue())) || buscados.contains(llave(pe.getLabel())))) {
				so.put(campo, pe.getValue());
				return;
			}
		}
	}

	// Describe de campos ya consultados (se usa por cada asegurado; evita repetir el describe).
	private static Map<String, Schema.DescribeFieldResult> describes = new Map<String, Schema.DescribeFieldResult>();

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Describe de un campo, guardado en memoria durante la transacción.
	 * @param so: registro.
	 * @param campo: API name del campo.
	 * @return DescribeFieldResult del campo.
	 */
	private static Schema.DescribeFieldResult campoDe(SObject so, String campo) {
		String k = String.valueOf(so.getSObjectType()) + '.' + campo;
		if (!describes.containsKey(k)) {
			describes.put(k, so.getSObjectType().getDescribe().fields.getMap().get(campo).getDescribe());
		}
		return describes.get(k);
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Copia de una parte de la lista [desde, hasta).
	 * @param l: lista original.
	 * @param desde: índice inicial (incluido).
	 * @param hasta: índice final (excluido).
	 * @return sublista.
	 */
	private static List<String> sublista(List<String> l, Integer desde, Integer hasta) {
		List<String> r = new List<String>();
		for (Integer i = desde; i < hasta; i++) { r.add(l[i]); }
		return r;
	}

	/**
	 * @creation date: 12/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Limpia la respuesta de la IA: quita fences de Markdown y recorta del primer "{" al último "}".
	 * @param raw: texto devuelto por el modelo.
	 * @return JSON limpio.
	 */
	@TestVisible
	private static String limpiarJson(String raw) {
		if (String.isBlank(raw)) { return '{"asegurados":[]}'; }
		String p = raw.trim();
		Integer ini = p.indexOf('{');
		Integer fin = p.lastIndexOf('}');
		return (ini >= 0 && fin > ini) ? p.substring(ini, fin + 1) : '{"asegurados":[]}';
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

	/**
	 * @creation date: 15/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Copia el censo de la oportunidad colectiva a la póliza: un participante (InsurancePolicyParticipant)
	 *               por asegurado. Titulares con rol "Asegurado"; dependientes con rol "Miembro familiar", ligados a su
	 *               titular y con el parentesco según el censo y el sexo (Cónyuge -> Mujer/Marido, hijo -> Hijo/Hija).
	 *               Lleva certificado, categoría (subgrupo), fecha de alta y el contacto si el asegurado lo tiene.
	 *               Cada titular queda ligado a un Contacto de la cuenta de la póliza (a quien se le envía su
	 *               certificado): se reutiliza el que ya exista o se crea con los datos del censo.
	 *               No duplica: omite asegurados que ya están en la póliza (mismo certificado y nombre).
	 * @param opportunityId: oportunidad colectiva con censo.
	 * @param policyId: póliza emitida.
	 * @return número de participantes creados.
	 */
	public static Integer copiarCensoAPoliza(Id opportunityId, Id policyId) {
		if (opportunityId == null || policyId == null) { return 0; }
		List<GroupCensusMember> miembros = [
			SELECT Id, FirstName, LastName, Name, Gender, RelationshipToPrimaryMember, PrimaryGroupCensusMemberId,
				PrimaryGroupCensusMember.JoinDate, GroupClassId, JoinDate, Birthdate, Certificado__c, RFC__c, ContactId, Prima__c,
				Email, PhoneNumber
			FROM GroupCensusMember
			WHERE GroupCensus.Oportunidad__c = :opportunityId
			ORDER BY PrimaryGroupCensusMemberId NULLS FIRST, Certificado__c, Name
			LIMIT 10000
		];
		if (miembros.isEmpty()) { return 0; }
		InsurancePolicy pol = [SELECT EffectiveDate, ExpirationDate, NameInsuredId FROM InsurancePolicy WHERE Id = :policyId LIMIT 1];
		ligarContactosTitulares(miembros, pol.NameInsuredId);

		// Participantes que ya están en la póliza (mismo certificado y nombre): no se duplican, solo se completan.
		Map<String, InsurancePolicyParticipant> yaEstan = new Map<String, InsurancePolicyParticipant>();
		for (InsurancePolicyParticipant p : [
			SELECT Id, ParticipantName, ParticipantCode, RelationshipToInsured, RelatedInsPolicyParticipantId,
				EffectiveFromDate, EffectiveToDate, EffectiveDate, ExpirationDate, FechaNacimiento__c, Identificacion__c,
				PrimaryParticipantContactId
			FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :policyId
		]) { yaEstan.put(llaveParticipante(p.ParticipantCode, p.ParticipantName), p); }

		String rolTitular = valorPicklist(InsurancePolicyParticipant.Role.getDescribe(), new List<String>{ 'Asegurado', 'Insured' });
		String rolDependiente = valorPicklist(InsurancePolicyParticipant.Role.getDescribe(),
			new List<String>{ 'Miembro familiar', 'Asegurado', 'Insured' });
		Map<Id, InsurancePolicyParticipant> completar = new Map<Id, InsurancePolicyParticipant>();

		// 1) Titulares (los dependientes se ligan a ellos).
		Map<Id, InsurancePolicyParticipant> porTitular = new Map<Id, InsurancePolicyParticipant>();
		List<InsurancePolicyParticipant> titulares = new List<InsurancePolicyParticipant>();
		for (GroupCensusMember m : miembros) {
			if (m.PrimaryGroupCensusMemberId != null) { continue; }
			InsurancePolicyParticipant p = participante(m, policyId, rolTitular, pol);
			InsurancePolicyParticipant existe = yaEstan.get(llaveParticipante(p.ParticipantCode, p.ParticipantName));
			if (existe != null) {
				porTitular.put(m.Id, existe);
				if (completarDatos(existe, p)) { completar.put(existe.Id, existe); }
				continue;
			}
			porTitular.put(m.Id, p);
			titulares.add(p);
		}
		if (!titulares.isEmpty()) { insert titulares; }

		// 2) Dependientes con su parentesco y ligados al participante de su titular.
		Schema.DescribeFieldResult relacion = InsurancePolicyParticipant.RelationshipToInsured.getDescribe();
		List<InsurancePolicyParticipant> dependientes = new List<InsurancePolicyParticipant>();
		for (GroupCensusMember m : miembros) {
			if (m.PrimaryGroupCensusMemberId == null) { continue; }
			InsurancePolicyParticipant p = participante(m, policyId, rolDependiente, pol);
			if (porTitular.containsKey(m.PrimaryGroupCensusMemberId)) {
				p.RelatedInsPolicyParticipantId = porTitular.get(m.PrimaryGroupCensusMemberId).Id;
			}
			String rel = valorPicklist(relacion, parentescoPoliza(m.RelationshipToPrimaryMember, m.Gender));
			if (String.isNotBlank(rel)) { p.RelationshipToInsured = rel; }
			InsurancePolicyParticipant existe = yaEstan.get(llaveParticipante(p.ParticipantCode, p.ParticipantName));
			if (existe != null) {
				if (completarDatos(existe, p)) { completar.put(existe.Id, existe); }
				continue;
			}
			dependientes.add(p);
		}
		if (!dependientes.isEmpty()) { insert dependientes; }
		if (!completar.isEmpty()) { update completar.values(); }
		return titulares.size() + dependientes.size();
	}

	/**
	 * @creation date: 28/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Liga cada titular del censo a un Contacto de la cuenta (a quien se le envía su certificado). Reutiliza
	 *               el contacto que ya exista en la cuenta con el mismo RFC o con el mismo nombre y fecha de nacimiento;
	 *               si no hay, lo crea con nombre, apellidos, fecha de nacimiento, RFC, correo y teléfono del censo. Guarda
	 *               el contacto en el asegurado del censo para que la renovación use el mismo.
	 * @param miembros: asegurados del censo (se les llena ContactId).
	 * @param accountId: cuenta de la póliza (la empresa).
	 */
	private static void ligarContactosTitulares(List<GroupCensusMember> miembros, Id accountId) {
		if (accountId == null) { return; }
		List<GroupCensusMember> sinContacto = new List<GroupCensusMember>();
		for (GroupCensusMember m : miembros) {
			if (m.PrimaryGroupCensusMemberId == null && m.ContactId == null && String.isNotBlank(m.LastName)) { sinContacto.add(m); }
		}
		if (sinContacto.isEmpty()) { return; }

		Map<String, Id> existentes = new Map<String, Id>();
		for (Contact c : [SELECT Id, Name, FirstName, LastName, Birthdate, RFC__c FROM Contact WHERE AccountId = :accountId LIMIT 10000]) {
			if (String.isNotBlank(c.RFC__c)) { existentes.put('rfc:' + c.RFC__c.deleteWhitespace().toUpperCase(), c.Id); }
			existentes.put(llaveContacto((c.FirstName == null ? '' : c.FirstName + ' ') + c.LastName, c.Birthdate), c.Id);
		}

		List<GroupCensusMember> porCrear = new List<GroupCensusMember>();
		List<Contact> nuevos = new List<Contact>();
		for (GroupCensusMember m : sinContacto) {
			String rfc = String.isBlank(m.RFC__c) ? null : 'rfc:' + m.RFC__c.deleteWhitespace().toUpperCase();
			String llave = llaveContacto((m.FirstName == null || m.FirstName == '-' ? '' : m.FirstName + ' ') + m.LastName, m.Birthdate);
			Id existe = rfc != null && existentes.containsKey(rfc) ? existentes.get(rfc) : existentes.get(llave);
			if (existe != null) {
				m.ContactId = existe;
				continue;
			}
			Contact c = new Contact(AccountId = accountId, LastName = m.LastName.left(80), Birthdate = m.Birthdate);
			if (String.isNotBlank(m.FirstName) && m.FirstName != '-') { c.FirstName = m.FirstName.left(40); }
			if (String.isNotBlank(m.RFC__c)) { c.RFC__c = m.RFC__c.deleteWhitespace().toUpperCase().left(13); }
			if (String.isNotBlank(m.Email)) { c.Email = m.Email; }
			// Celular: el campo Teléfono tiene una regla de formato que rechazaría el contacto completo.
			if (String.isNotBlank(m.PhoneNumber)) { c.MobilePhone = m.PhoneNumber.left(40); }
			porCrear.add(m);
			nuevos.add(c);
		}
		if (!nuevos.isEmpty()) {
			// Las reglas de duplicados no deben frenar el alta masiva; un contacto que no se pueda crear queda sin ligar.
			Database.DMLOptions opciones = new Database.DMLOptions();
			opciones.DuplicateRuleHeader.allowSave = true;
			opciones.OptAllOrNone = false;
			List<Database.SaveResult> res = Database.insert(nuevos, opciones);
			for (Integer i = 0; i < res.size(); i++) {
				if (res[i].isSuccess()) { porCrear[i].ContactId = res[i].getId(); }
				else { System.debug(LoggingLevel.WARN, 'Contacto no creado: ' + res[i].getErrors()); }
			}
		}
		List<GroupCensusMember> actualizar = new List<GroupCensusMember>();
		for (GroupCensusMember m : sinContacto) {
			if (m.ContactId != null) { actualizar.add(new GroupCensusMember(Id = m.Id, ContactId = m.ContactId)); }
		}
		if (!actualizar.isEmpty()) { Database.update(actualizar, false); }
	}

	/**
	 * @creation date: 28/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Llave para encontrar un contacto: nombre sin acentos ni signos más la fecha de nacimiento.
	 * @param nombre: nombre completo.
	 * @param nacimiento: fecha de nacimiento (puede ser null).
	 * @return llave.
	 */
	private static String llaveContacto(String nombre, Date nacimiento) {
		return 'nom:' + llave(nombre) + '|' + (nacimiento == null ? '' : String.valueOf(nacimiento));
	}

	/**
	 * @creation date: 28/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Llena en un participante que ya estaba en la póliza los datos que le falten (fechas, fecha de
	 *               nacimiento, identificación, parentesco y titular); no cambia lo que ya tiene.
	 * @param existe: participante guardado.
	 * @param nuevo: participante armado desde el censo.
	 * @return true si se llenó algún dato.
	 */
	private static Boolean completarDatos(InsurancePolicyParticipant existe, InsurancePolicyParticipant nuevo) {
		Boolean cambio = false;
		for (String campo : new List<String>{ 'EffectiveFromDate', 'EffectiveToDate', 'EffectiveDate', 'ExpirationDate',
				'FechaNacimiento__c', 'Identificacion__c', 'RelationshipToInsured', 'RelatedInsPolicyParticipantId',
				'PrimaryParticipantContactId' }) {
			if (existe.get(campo) == null && nuevo.get(campo) != null) {
				existe.put(campo, nuevo.get(campo));
				cambio = true;
			}
		}
		return cambio;
	}

	/**
	 * @creation date: 15/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Une los nombres que en el texto del PDF quedaron partidos en varios renglones. Cuando el nombre no
	 *               cabe en su celda, el renglón de datos (certificado, parentesco, edad...) queda sin nombre o con el
	 *               nombre incompleto, y el resto queda en renglones que solo tienen palabras de nombre:
	 *               - renglón de datos que empieza con un número (sin nombre): toma el renglón de nombre de arriba y el
	 *                 de abajo ("REYES SAUCEDO ROMAN" / "00000002 TITULAR ..." / "ALEJANDRO");
	 *               - renglón de nombre suelto debajo de un renglón de datos que sí trae nombre: se agrega al final de
	 *                 ese nombre, antes de los datos.
	 * @param texto: texto del censo, un renglón por línea.
	 * @return texto con un renglón por asegurado.
	 */
	@TestVisible
	private static String unirNombresPartidos(String texto) {
		if (String.isBlank(texto)) { return texto; }
		List<String> r = texto.replace('\r', '').split('\n');
		Integer n = r.size();
		List<String> nuevo = new List<String>(r);
		Set<Integer> quitados = new Set<Integer>();
		// 1) Renglones de datos sin nombre: nombre = renglón de arriba + renglón de abajo.
		for (Integer i = 0; i < n; i++) {
			if (!esDatosSinNombre(r[i])) { continue; }
			String antes = (i > 0 && !quitados.contains(i - 1) && esSoloNombre(r[i - 1])) ? r[i - 1].trim() : null;
			String despues = (i + 1 < n && esSoloNombre(r[i + 1]) && !esDatosSinNombre(i + 2 < n ? r[i + 2] : '')) ? r[i + 1].trim() : null;
			if (antes == null && despues == null) { continue; }
			nuevo[i] = ((antes == null ? '' : antes) + ' ' + (despues == null ? '' : despues) + ' ' + r[i].trim()).normalizeSpace();
			if (antes != null) { quitados.add(i - 1); }
			if (despues != null) { quitados.add(i + 1); }
		}
		// 2) Pedazo de nombre debajo de un renglón de datos que sí trae nombre: va al final del nombre.
		for (Integer i = 1; i < n; i++) {
			if (quitados.contains(i) || !esSoloNombre(r[i]) || quitados.contains(i - 1)) { continue; }
			String previo = nuevo[i - 1].trim();
			if (!Pattern.matches('^[A-ZÁÉÍÓÚÑÜ .\'-]+\\s\\d{3,}.*', previo) || esDatosSinNombre(r[i - 1])) { continue; }
			Matcher m = Pattern.compile('\\s(?=\\S*\\d)').matcher(previo);
			if (!m.find()) { continue; }
			nuevo[i - 1] = previo.substring(0, m.start()) + ' ' + r[i].trim() + previo.substring(m.start());
			quitados.add(i);
		}
		List<String> salida = new List<String>();
		for (Integer i = 0; i < n; i++) { if (!quitados.contains(i)) { salida.add(nuevo[i]); } }
		return String.join(salida, '\n');
	}

	/**
	 * @creation date: 15/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Renglón que solo tiene palabras (sin números ni signos de datos): posible pedazo de un nombre.
	 * @param renglon: texto.
	 * @return true si parece pedazo de nombre.
	 */
	private static Boolean esSoloNombre(String renglon) {
		if (String.isBlank(renglon)) { return false; }
		String t = renglon.trim();
		return t.length() <= 60 && Pattern.matches('^[A-ZÁÉÍÓÚÑÜ][A-ZÁÉÍÓÚÑÜ .\'-]*$', t);
	}

	/**
	 * @creation date: 15/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Renglón de datos de un asegurado que empieza con un número (certificado, consecutivo): no trae nombre.
	 * @param renglon: texto.
	 * @return true si es un renglón de datos sin nombre.
	 */
	private static Boolean esDatosSinNombre(String renglon) {
		return String.isNotBlank(renglon) && Pattern.matches('^\\d{3,}\\s+\\S+.*', renglon.trim());
	}

	/**
	 * @creation date: 15/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Quita del nombre la última palabra cuando es la misma con la que empiezan los apellidos (la IA a
	 *               veces la repite al separar "ORLANDO RANGEL IVAN" en nombre "IVAN ORLANDO" y apellidos "ORLANDO RANGEL").
	 * @param nombre: nombre(s) de pila.
	 * @param apellidos: apellidos.
	 * @return nombre sin la palabra repetida.
	 */
	@TestVisible
	private static String sinPalabraRepetida(String nombre, String apellidos) {
		if (String.isBlank(nombre) || String.isBlank(apellidos)) { return nombre; }
		List<String> n = nombre.split(' ');
		List<String> a = apellidos.split(' ');
		if (n.size() > 1 && n[n.size() - 1].equalsIgnoreCase(a[0])) {
			n.remove(n.size() - 1);
			return String.join(n, ' ');
		}
		return nombre;
	}

	/**
	 * @creation date: 15/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Participante de la póliza con los datos del asegurado del censo.
	 * @param m: asegurado del censo.
	 * @param policyId: póliza.
	 * @param rol: rol del participante.
	 * @return participante sin insertar.
	 */
	private static InsurancePolicyParticipant participante(GroupCensusMember m, Id policyId, String rol, InsurancePolicy pol) {
		InsurancePolicyParticipant p = new InsurancePolicyParticipant(InsurancePolicyId = policyId);
		String nombre = String.isNotBlank(m.Name) ? m.Name : ((m.FirstName == null ? '' : m.FirstName + ' ') + m.LastName);
		p.ParticipantName = nombre.normalizeSpace().left(255);
		if (String.isNotBlank(rol)) { p.Role = rol; }
		if (String.isNotBlank(m.Certificado__c)) { p.ParticipantCode = m.Certificado__c.left(255); }
		// Categoría (subgrupo): el campo existe en versiones recientes de la API; si no está disponible se omite.
		if (m.GroupClassId != null) { try { p.put('GroupClassId', m.GroupClassId); } catch (Exception e) { System.debug(LoggingLevel.FINE, e.getMessage()); } }
		if (m.ContactId != null) { p.PrimaryParticipantContactId = m.ContactId; }
		// Vigencia del asegurado: desde su fecha de alta (el dependiente toma la de su titular; sin alta, el inicio de
		// la póliza) hasta el fin de vigencia de la póliza.
		Date alta = m.JoinDate != null ? m.JoinDate
			: (m.PrimaryGroupCensusMember != null && m.PrimaryGroupCensusMember.JoinDate != null ? m.PrimaryGroupCensusMember.JoinDate
				: (pol != null && pol.EffectiveDate != null ? pol.EffectiveDate.date() : null));
		if (alta != null) {
			p.EffectiveFromDate = alta;
			p.EffectiveDate = Datetime.newInstance(alta, Time.newInstance(12, 0, 0, 0));
		}
		if (pol != null && pol.ExpirationDate != null) {
			p.EffectiveToDate = pol.ExpirationDate.date();
			p.ExpirationDate = pol.ExpirationDate;
		}
		if (m.Birthdate != null) { p.FechaNacimiento__c = m.Birthdate; }
		if (String.isNotBlank(m.RFC__c)) { p.Identificacion__c = m.RFC__c.left(50); }
		// Prima individual del asegurado (del listado de la aseguradora) como prima del periodo del participante.
		if (m.Prima__c != null) { p.TermPremiumAmount = m.Prima__c; }
		p.IsActiveParticipant = true;
		return p;
	}

	/**
	 * @creation date: 15/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Parentesco con el titular para la póliza a partir del parentesco del censo y el sexo.
	 * @param censo: valor de RelationshipToPrimaryMember (Cónyuge, Secundario/hijo, Suegro...).
	 * @param sexo: Hombre / Mujer.
	 * @return valores candidatos del picklist RelationshipToInsured, en orden de preferencia.
	 */
	@TestVisible
	private static List<String> parentescoPoliza(String censo, String sexo) {
		String r = censo == null ? '' : censo.toLowerCase();
		Boolean mujer = sexo != null && (sexo.toLowerCase().startsWith('m') && !sexo.toLowerCase().startsWith('mas') || sexo.toLowerCase().startsWith('f'));
		if (r.contains('nyuge') || r.contains('spouse') || r.contains('esposa') || r.contains('esposo')) {
			return mujer ? new List<String>{ 'Mujer', 'Esposa' } : new List<String>{ 'Marido', 'Esposo' };
		}
		if (r.contains('secundario') || r.contains('child') || r.contains('hij')) {
			return mujer ? new List<String>{ 'Hija' } : new List<String>{ 'Hijo' };
		}
		if (r.contains('suegr')) { return mujer ? new List<String>{ 'Suegra' } : new List<String>{ 'Suegro' }; }
		if (r.contains('padre') || r.contains('madre') || r.contains('parent')) { return mujer ? new List<String>{ 'Madre' } : new List<String>{ 'Padre' }; }
		return new List<String>();
	}

	/**
	 * @creation date: 15/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Primer valor activo del picklist que coincida (sin importar mayúsculas) con los candidatos.
	 * @param campo: describe del picklist.
	 * @param candidatos: valores en orden de preferencia.
	 * @return valor del picklist o null.
	 */
	private static String valorPicklist(Schema.DescribeFieldResult campo, List<String> candidatos) {
		for (String c : candidatos) {
			for (Schema.PicklistEntry pe : campo.getPicklistValues()) {
				if (pe.isActive() && (pe.getValue().equalsIgnoreCase(c) || pe.getLabel().equalsIgnoreCase(c))) { return pe.getValue(); }
			}
		}
		return null;
	}

	/**
	 * @creation date: 15/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Llave para no duplicar participantes: certificado + nombre en mayúsculas.
	 * @param certificado: certificado.
	 * @param nombre: nombre del asegurado.
	 * @return llave.
	 */
	private static String llaveParticipante(String certificado, String nombre) {
		return (certificado == null ? '' : certificado.trim()) + '|' + (nombre == null ? '' : nombre.normalizeSpace().toUpperCase());
	}
}
