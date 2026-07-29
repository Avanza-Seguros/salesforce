/**
 *   @name: OpportunityController
 *   @version: 1.0
 *   @creation date: 02/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Controlador Aura/LWC para gestionar Oportunidades de seguros: listar, ver detalle con cotizaciones y coberturas, eliminar, buscar agentes, cuentas y vehiculos, extraer datos de polizas, guardar oportunidades y consultar productos.
 */
public with sharing class OpportunityController {

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve las 50 oportunidades mas recientes con sus campos principales para mostrarlas en el listado del LWC.
	 * @return Lista de Opportunity ordenada por fecha de creacion descendente
	 */
	@AuraEnabled(cacheable=false)
	public static List<Opportunity> getOpportunities() {
		try {
			return [
				SELECT
					Id,
					Name,
					StageName,
					CloseDate,
					Amount,
					Prima_Total__c,
					Prima_neta__c,
					Description,
					Type,
					LeadSource,
					Probability,
					AccountId,
					Ramo__c,
					Canal__c,
					Mercado__c,
					Account.Name,
					Owner.Name,
					CreatedDate
				FROM Opportunity
				ORDER BY CreatedDate DESC
				LIMIT 2000
			];
		} catch (Exception e) {
			throw new AuraHandledException('Error al cargar oportunidades: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Obtiene el detalle de una oportunidad junto con sus cotizaciones, sus lineas de producto y el conteo y nombres de coberturas por cotizacion.
	 * @param opportunityId: Id de la oportunidad a consultar
	 * @return OpportunityDetailWrapper con la oportunidad, cotizaciones y datos de coberturas
	 */
	@AuraEnabled(cacheable=false)
	public static OpportunityDetailWrapper getOpportunityDetails(String opportunityId) {
		try {
			OpportunityDetailWrapper wrapper = new OpportunityDetailWrapper();
			wrapper.opportunity = [
                SELECT Id, Name, StageName, Type, Canal__c, Mercado__c,
                    Ramo__c, CloseDate, Amount, Prima_Total__c, Prima_Neta__c,
                    AccountId, Account.Name, Description, Descripcion__c,
                    Agente_Relacionado__c, Agente_Relacionado__r.Name,
                    Contacto__c, Contacto__r.Name,
                    Automovil__c
                FROM Opportunity
                WHERE Id = :opportunityId
                LIMIT 1
            ];

            // El auto vive ligado a la Cuenta; la oportunidad guarda solo la
            // REFERENCIA (lookup Automovil__c). Recuperamos sus datos siguiendo esa
            // referencia para llenar el formulario al editar.
            if (wrapper.opportunity.Automovil__c != null) {
                List<Automovil__c> autos = [
                    SELECT Id, Name, Marca__c, Modelo__c, Serie__c, Placa__c, Motor__c, Descripcion_Completa__c
                    FROM Automovil__c
                    WHERE Id = :wrapper.opportunity.Automovil__c
                    LIMIT 1
                ];
                if (!autos.isEmpty()) { wrapper.automovil = autos[0]; }
            }

			// - QuoteLineItem    → línea con el PRODUCTO de la cotización
			// - Quote_Coverage__c → COBERTURAS reales (objeto custom)
			wrapper.quotes = [
				SELECT Id, IsDeleted, Name, Pricebook2Id, ContactId, Contact.Name, QuoteNumber,
					   IsSyncing, Tax, Status, ExpirationDate, Subtotal, TotalPrice, Email, AccountId,
					   Account.Name, Product__c, Product__r.Name, Is_Selected__c,
					   Prima_Total__c, PrimaAnual__c,
					   Aseguradora__c, Aseguradora__r.Name, Price_Book__c,
					   (SELECT Id, Product2Id, Product2.Name, Quantity, UnitPrice, TotalPrice
						FROM QuoteLineItems)
				FROM Quote
				WHERE OpportunityId = :opportunityId
				ORDER BY CreatedDate DESC
			];

			// Coberturas (Quote_Coverage__c) por cotización: traemos el
			// nombre y el orden. Con eso el LWC arma:
			//   • el conteo total para la tabla y el KPI
			//   • el comparativo imprimible (matriz cobertura × compañía)
			// Las coberturas de cada cotización se toman del PRODUCTO de la Quote,
			// a través de ProductCoverageAssignment__c (Coverage_Type__r.Name = nombre real).
			Set<Id> productIds = new Set<Id>();
			for (Quote q : wrapper.quotes) { if (q.Product__c != null) productIds.add(q.Product__c); }

			Map<Id, List<String>> coveragesByProduct = new Map<Id, List<String>>();
			if (!productIds.isEmpty()) {
				for (ProductCoverageAssignment__c pca : [
					SELECT Product__c, Coverage_Type__r.Name
					FROM ProductCoverageAssignment__c
					WHERE Product__c IN :productIds
					ORDER BY Coverage_Type__r.Name
				]) {
					if (pca.Coverage_Type__r == null || String.isBlank(pca.Coverage_Type__r.Name)) { continue; }
					if (!coveragesByProduct.containsKey(pca.Product__c)) {
						coveragesByProduct.put(pca.Product__c, new List<String>());
					}
					coveragesByProduct.get(pca.Product__c).add(pca.Coverage_Type__r.Name);
				}
			}

			Map<Id, Integer> coverageCounts = new Map<Id, Integer>();
			Map<Id, List<String>> coverageNamesByQuote = new Map<Id, List<String>>();
			for (Quote q : wrapper.quotes) {
				List<String> names = (q.Product__c != null && coveragesByProduct.containsKey(q.Product__c))
					? coveragesByProduct.get(q.Product__c)
					: new List<String>();
				coverageNamesByQuote.put(q.Id, names);
				coverageCounts.put(q.Id, names.size());
			}
			wrapper.coverageCounts = coverageCounts;
			wrapper.coverageNamesByQuote = coverageNamesByQuote;

			return wrapper;
		} catch (Exception e) {
			throw new AuraHandledException('Error al cargar detalles de la oportunidad: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Estructura de datos que agrupa la oportunidad, sus cotizaciones y la informacion de coberturas para exponerla al LWC.
	 */
	public class OpportunityDetailWrapper {
		@AuraEnabled public Opportunity opportunity;
		@AuraEnabled public List<Quote> quotes;
		@AuraEnabled public Map<Id, Integer> coverageCounts;
		@AuraEnabled public Map<Id, List<String>> coverageNamesByQuote;
		@AuraEnabled public Automovil__c automovil;   // vehículo ligado a la cuenta
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Elimina la oportunidad indicada.
	 * @param opportunityId: Id de la oportunidad a eliminar
	 * @return void
	 */
	@AuraEnabled(cacheable=false)
	public static void deleteOpportunity(String opportunityId) {
		try {
			Opportunity opp = [SELECT Id FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
			delete opp;
		} catch (Exception e) {
			throw new AuraHandledException('Error al eliminar oportunidad: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cambia el estatus de una cotizacion (Quote) a 'Aceptado'.
	 * @param quoteId: Id de la Quote a aceptar.
	 * @return void
	 */
	@AuraEnabled(cacheable=false)
	public static void aceptarCotizacion(String quoteId) {
		try {
			Quote q = [SELECT Id, Status FROM Quote WHERE Id = :quoteId LIMIT 1];
			q.Status = 'Accepted';
			update q;
		} catch (Exception e) {
			throw new AuraHandledException('Error al aceptar la cotizacion: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 08/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cambia la Etapa (StageName) de la oportunidad a 'Póliza'. Se usa
	 *               desde el botón "Póliza" que aparece cuando una cotización ya está aceptada.
	 * @param opportunityId: Id de la oportunidad a pasar a Póliza.
	 * @return void
	 */
	@AuraEnabled(cacheable=false)
	public static void cambiarEtapaAPoliza(String opportunityId) {
		try {
			Opportunity o = new Opportunity(Id = (Id) opportunityId, StageName = 'Póliza');
			update o;
		} catch (Exception e) {
			throw new AuraHandledException('Error al cambiar la etapa a Póliza: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Busca agentes/prospectores por nombre, email o nombre de contacto a partir de un termino de al menos 3 caracteres.
	 * @param searchTerm: Texto de busqueda (minimo 3 caracteres)
	 * @return Lista de Agente__c coincidentes (maximo 10)
	 */
	@AuraEnabled(cacheable=false)
	public static List<Agente__c> searchAgentsProspectors(String searchTerm) {
		try {
			if (String.isBlank(searchTerm) || searchTerm.length() < 3) {
				return new List<Agente__c>();
			}
			String searchQuery = '%' + searchTerm + '%';
			return [
				SELECT Id, Name, Email__c, Telefono__c, Contacto__r.Name, Horno_mes__c
				FROM Agente__c
				WHERE (Name LIKE :searchQuery
					   OR Email__c LIKE :searchQuery
					   OR Contacto__r.Name LIKE :searchQuery)
				ORDER BY Name
				LIMIT 10
			];
		} catch (Exception e) {
			throw new AuraHandledException('Error en búsqueda de agentes: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve los archivos (PDF u otros) vinculados a un registro mediante ContentDocumentLink.
	 * @param recordId: Id del registro cuyos archivos se quieren obtener
	 * @return Lista de PdfWrapper con id de documento, titulo e id de version
	 */
	@AuraEnabled(cacheable=false)
	public static List<PdfWrapper> getPdfFiles(Id recordId) {
		List<PdfWrapper> result = new List<PdfWrapper>();
		for (ContentDocumentLink cdl : [
			SELECT ContentDocument.Id,
				   ContentDocument.Title,
				   ContentDocument.LatestPublishedVersionId
			FROM ContentDocumentLink
			WHERE LinkedEntityId = :recordId
		]) {
			result.add(new PdfWrapper(
				cdl.ContentDocument.Id,
				cdl.ContentDocument.Title,
				cdl.ContentDocument.LatestPublishedVersionId
			));
		}
		return result;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Estructura que representa un archivo para exponer su id de documento, titulo e id de version al LWC.
	 */
	public class PdfWrapper {
		@AuraEnabled public Id documentId;
		@AuraEnabled public String title;
		@AuraEnabled public Id versionId;

		/**
		 * @creation date: 02/07/2026
		 * @author: Sergio Uribe Toledo - Volestra
		 * @description: Construye el wrapper de archivo con los datos del documento.
		 * @param docId: Id del ContentDocument
		 * @param t: Titulo del documento
		 * @param vId: Id de la ultima version publicada
		 */
		public PdfWrapper(Id docId, String t, Id vId) {
			documentId = docId;
			title = t;
			versionId = vId;
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Decodifica el contenido base64 de un archivo y devuelve datos de poliza simulados (placeholder para futura integracion con OCR).
	 * @param fileContent: Contenido del archivo en formato data URL base64
	 * @return Mapa con el resultado del proceso, confianza y campos extraidos
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> extractPolicyData(String fileContent) {
		Map<String, Object> result = new Map<String, Object>();
		try {
			Blob fileBlob = EncodingUtil.base64Decode(fileContent.split(',')[1]);
			// Integración futura con OCR (Google Vision, AWS Textract, etc.)
			result.put('success', true);
			result.put('confidence', 85);
			List<Map<String, Object>> extractedFields = new List<Map<String, Object>>();
			extractedFields.add(createField('NumeroPoliza__c', 'Número de Póliza', 'P-2024-0012345', 95));
			extractedFields.add(createField('Aseguradora__c', 'Compañía Aseguradora', 'Mapfre', 90));
			extractedFields.add(createField('Prima_Total__c', 'Prima Total', '1250.00', 80));
			result.put('extractedFields', extractedFields);
		} catch (Exception e) {
			result.put('success', false);
			result.put('error', e.getMessage());
		}
		return result;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Construye un mapa que representa un campo extraido con su nombre, etiqueta, valor y nivel de confianza.
	 * @param name: Nombre API del campo
	 * @param label: Etiqueta legible del campo
	 * @param value: Valor extraido
	 * @param confidence: Porcentaje de confianza de la extraccion
	 * @return Mapa con la informacion del campo
	 */
	private static Map<String, Object> createField(String name, String label, String value, Integer confidence) {
		Map<String, Object> field = new Map<String, Object>();
		field.put('name', name);
		field.put('label', label);
		field.put('value', value);
		field.put('confidence', confidence);
		return field;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Estructura que expone los datos de una cuenta (persona o empresa) para los resultados de busqueda en el LWC.
	 */
	public class AccountResult {
		@AuraEnabled public Id Id;
		@AuraEnabled public String Name;
		@AuraEnabled public Boolean IsPersonAccount;
		@AuraEnabled public String typeLabel;
		@AuraEnabled public String detailLine;
		@AuraEnabled public String clienteNombre;
		@AuraEnabled public String clienteRFC;
		@AuraEnabled public String clienteEmail;
		@AuraEnabled public String clienteTelefono;
		@AuraEnabled public String clienteCP;
		@AuraEnabled public String clienteDireccion;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Busca cuentas por nombre y devuelve sus datos de contacto adaptados segun sean cuenta persona o empresa.
	 * @param searchTerm: Texto de busqueda para el nombre de la cuenta
	 * @return Lista de AccountResult coincidentes (maximo 20)
	 */
	@AuraEnabled(cacheable=false)
	public static List<AccountResult> searchAccounts(String searchTerm) {
		String busqTerm = '%' + searchTerm + '%';
		List<AccountResult> out = new List<AccountResult>();
		for (Account a : [
			SELECT Id, Name, IsPersonAccount, Phone,
				   BillingStreet, BillingPostalCode,
				   PersonEmail, PersonMobilePhone,
				   PersonMailingStreet, PersonMailingPostalCode
			FROM Account
			WHERE Name LIKE :busqTerm
			ORDER BY Name LIMIT 20
		]) {
			AccountResult r = new AccountResult();
			r.Id = a.Id;  r.Name = a.Name;  r.IsPersonAccount = a.IsPersonAccount;
			r.typeLabel = a.IsPersonAccount ? 'Persona' : 'Empresa';
			r.clienteNombre = a.Name;
			if (a.IsPersonAccount) {
				r.clienteEmail = a.PersonEmail;
				r.clienteTelefono = a.PersonMobilePhone != null ? a.PersonMobilePhone : a.Phone;
				r.clienteCP = a.PersonMailingPostalCode;
				r.clienteDireccion = a.PersonMailingStreet;
			} else {
				r.clienteTelefono = a.Phone;
				r.clienteCP = a.BillingPostalCode;
				r.clienteDireccion = a.BillingStreet;
			}
			r.detailLine = r.typeLabel + (String.isNotBlank(r.clienteRFC) ? '  ·  RFC ' + r.clienteRFC : '');
			out.add(r);
		}
		return out;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Crea o actualiza una oportunidad a partir de un JSON del formulario; opcionalmente crea la cuenta (persona o empresa) y, si el ramo es Automoviles, resuelve o crea el vehiculo asociado.
	 * @param opportunityJson: Cadena JSON con los datos de la oportunidad, cuenta y vehiculo
	 * @param isNewAccount: Indica si debe crearse una cuenta nueva
	 * @return Id de la oportunidad creada o actualizada
	 */
	@AuraEnabled(cacheable=false)
	public static Id saveOpportunity(String opportunityJson, Boolean isNewAccount) {
		Map<String, Object> d =
			(Map<String, Object>) JSON.deserializeUntyped(opportunityJson);

		Id accountId = d.get('AccountId') != null
			? (Id) String.valueOf(d.get('AccountId'))
			: null;

		// ------------------------------------------------------------
		// 1) CUENTA NUEVA
		// ------------------------------------------------------------
		if (isNewAccount == true && accountId == null) {
			String tipoCliente = getStr(d, 'tipoCliente');
			Account acc = new Account();

			if (tipoCliente == 'Persona') {
				Id paRtId = getPersonAccountRecordTypeId();
				if (paRtId != null) {
					acc.RecordTypeId = paRtId;
				}
				acc.FirstName = getStr(d, 'clienteNombre');
				String paterno = getStr(d, 'clienteApellidoPaterno');
				String materno = getStr(d, 'clienteApellidoMaterno');
				if (String.isBlank(paterno) && String.isBlank(materno)) {
					String apellidos = getStr(d, 'clienteApellidos');
					if (String.isNotBlank(apellidos)) {
						List<String> partes = apellidos.trim().split('\\s+');
						paterno = partes.size() > 0 ? partes[0] : null;
						if (partes.size() > 1) {
							List<String> resto = new List<String>();
							for (Integer i = 1; i < partes.size(); i++) { resto.add(partes[i]); }
							materno = String.join(resto, ' ');
						}
					}
				}
				String last;
				if (String.isNotBlank(materno)) {
					try { acc.put('MiddleName', paterno); } catch (Exception ignore) {}
					last = materno;
				} else if (String.isNotBlank(paterno)) {
					last = paterno;
				} else {
					last = String.isNotBlank(acc.FirstName) ? acc.FirstName : getStr(d, 'AccountName');
					acc.FirstName = null;
				}
				acc.LastName = String.isNotBlank(last) ? last : getStr(d, 'AccountName');
				acc.PersonEmail             = getStr(d, 'clienteEmail');
				acc.Phone                   = getStr(d, 'clienteTelefono');
				acc.PersonMailingStreet     = getStr(d, 'clienteDireccion');
				acc.PersonMailingPostalCode = getStr(d, 'clienteCP');
			} else {
				acc.Name = getStr(d, 'AccountName');
				if (String.isBlank(acc.Name)) {
					acc.Name = getStr(d, 'clienteNombre');
				}
				acc.Phone             = getStr(d, 'clienteTelefono');
				acc.BillingStreet     = getStr(d, 'clienteDireccion');
				acc.BillingPostalCode = getStr(d, 'clienteCP');
			}

			// Evita duplicados: si ya existe una cuenta que coincide (por email de la
			// persona o por nombre exacto), se reutiliza en vez de crear otra.
			String nombreBuscar = (tipoCliente == 'Persona') ? nombrePersona(acc) : acc.Name;
			Id cuentaExistente = buscarCuentaExistente(d, tipoCliente, nombreBuscar);
			if (cuentaExistente != null) {
				accountId = cuentaExistente;
			} else {
				insert acc;
				accountId = acc.Id;
			}
		}

		// ------------------------------------------------------------
		// 2) OPORTUNIDAD (crear o actualizar)
		// ------------------------------------------------------------
		Opportunity opp = new Opportunity();
		if (d.get('Id') != null) {
			opp.Id = (Id) String.valueOf(d.get('Id'));
		}
		opp.Name        = getStr(d, 'Name');
		opp.AccountId   = accountId;
		// Defaults de negocio (por si llegaran vacíos desde el formulario)
		opp.Canal__c   = String.isNotBlank(getStr(d, 'Canal__c'))   ? getStr(d, 'Canal__c')   : 'Agente';
		opp.Mercado__c = String.isNotBlank(getStr(d, 'Mercado__c')) ? getStr(d, 'Mercado__c') : 'Corporativo';
		opp.Type = getStr(d, 'Type');   // ← tomar el Tipo del formulario (antes no se guardaba)
		if (String.isBlank(opp.StageName)) { opp.StageName = 'Gestion Comercial'; }
		if (String.isBlank(opp.Type))      { opp.Type = 'New_Business'; }

		// Agente (lookup a Agente_Relacionado__c)
		String agenteId = getStr(d, 'Agente_Relacionado__c');
		if (String.isNotBlank(agenteId)) {
			opp.Agente_Relacionado__c = (Id) agenteId;
		}
		opp.Ramo__c     = getStr(d, 'Ramo__c');
		opp.Description = getStr(d, 'Description');

		// Prima Total (campo custom) — sustituye al Amount estándar
		Object primaRaw = d.get('Prima_Total__c');
		if (primaRaw != null && String.isNotBlank(String.valueOf(primaRaw))) {
			try {
				opp.Prima_Total__c = Decimal.valueOf(String.valueOf(primaRaw));
			} catch (Exception ex) {
				// Si llega un valor no numérico, lo ignoramos en vez de tronar
			}
		}

		// Prima Neta (campo custom)
			Object primaNetaRaw = d.get('Prima_Neta__c');
			if (primaNetaRaw != null && String.isNotBlank(String.valueOf(primaNetaRaw))) {
				try {
					opp.Prima_Neta__c = Decimal.valueOf(String.valueOf(primaNetaRaw));
				} catch (Exception ex) {
					// valor no numérico: se ignora
				}
			}

			String closeDateStr = getStr(d, 'CloseDate');
		if (String.isNotBlank(closeDateStr)) {
			opp.CloseDate = Date.valueOf(closeDateStr);
		} else if (opp.Id == null) {
			opp.CloseDate = Date.today().addDays(30);
		}

		// Vehículo (ramo Automóviles): resolveVehiculo crea/liga el auto a la CUENTA
		// (Automovil__c.Cuenta__c). La oportunidad guarda SOLO la referencia (lookup)
		// al auto específico de este trato; los datos del auto no se duplican aquí.
		String ramoOpp = getStr(d, 'Ramo__c');
		if (ramoOpp != null && ramoOpp.toUpperCase().contains('AUTO')) {
			Id vehId = resolveVehiculo(d, accountId);
			if (vehId != null) {
				opp.Automovil__c = vehId;
			}
		}

		String mercadoSel = String.isNotBlank(getStr(d, 'Mercado__c')) ? getStr(d, 'Mercado__c') : opp.Mercado__c;
		if (mercadoSel == 'Individual' && accountId != null) {
			Id personContact = getPersonContactId(accountId);
			// Respaldo: si la cuenta no tiene contacto de persona (p. ej. no es
			// Cuenta Persona), creamos/ligamos uno con el nombre del cliente para
			// no dejar la oportunidad sin contacto.
			if (personContact == null) {
				personContact = crearContactoIndividual(d, accountId);
			}
			opp.Contacto__c = personContact;
		} else {
			String contactoId = getStr(d, 'Contacto__c');
			Boolean isNewContacto = d.get('isNewContacto') == true;
			if (String.isNotBlank(contactoId)) {
				opp.Contacto__c = (Id) contactoId;
			} else if (isNewContacto && accountId != null) {
				opp.Contacto__c = crearContacto(d, accountId);
			}
		}

		String compHtml = getStr(d, 'Descripcion__c');
		if (String.isNotBlank(compHtml)) {
			opp.Descripcion__c = compHtml;
		}

		// Detalle del ramo (todos los ramos): resumen en la descripcion de la oportunidad.
		Map<String, Object> detalleRamo = (d.get('detalleRamo') instanceof Map<String, Object>) ? (Map<String, Object>) d.get('detalleRamo') : null;
		String resumenRamo = buildRamoResumen(ramoOpp, detalleRamo);
		if (String.isNotBlank(resumenRamo)) {
			opp.Description = String.isBlank(opp.Description) ? resumenRamo : (opp.Description + '\n\n' + resumenRamo);
			if (opp.Description != null && opp.Description.length() > 32000) { opp.Description = opp.Description.left(32000); }
		}

		upsert opp;

		// Persistencia con objetos ESTANDAR de FSC (Autos usa Automovil__c, ya resuelto arriba).
		if (ramoOpp != null && !ramoOpp.toUpperCase().contains('AUTO')) {
			persistRamoStandardData(opp.Id, accountId, ramoOpp, detalleRamo);
		}

		return opp.Id;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Obtiene de forma segura el valor de una clave del mapa como String, devolviendo null si no existe.
	 * @param m: Mapa de datos deserializados
	 * @param key: Clave a leer
	 * @return Valor como String o null si la clave es nula
	 */
	private static String getStr(Map<String, Object> m, String key) {
		Object v = m.get(key);
		return v == null ? null : String.valueOf(v);
	}

	// Nombre completo de una Cuenta Persona a partir de sus componentes.
	private static String nombrePersona(Account acc) {
		List<String> partes = new List<String>();
		if (String.isNotBlank(acc.FirstName)) { partes.add(acc.FirstName); }
		String mid;
		try { mid = (String) acc.get('MiddleName'); } catch (Exception e) { mid = null; }
		if (String.isNotBlank(mid)) { partes.add(mid); }
		if (String.isNotBlank(acc.LastName)) { partes.add(acc.LastName); }
		return String.join(partes, ' ').trim();
	}

	// Busca una cuenta existente para evitar duplicados: primero por email (si es persona),
	// luego por nombre exacto (la comparación de texto en SOQL no distingue mayúsculas).
	private static Id buscarCuentaExistente(Map<String, Object> d, String tipoCliente, String nombreCuenta) {
		String email = getStr(d, 'clienteEmail');
		if (tipoCliente == 'Persona' && String.isNotBlank(email)) {
			for (Account a : [SELECT Id FROM Account WHERE PersonEmail = :email AND IsPersonAccount = true LIMIT 1]) {
				return a.Id;
			}
		}
		if (String.isBlank(nombreCuenta)) { return null; }
		for (Account a : [SELECT Id FROM Account WHERE Name = :nombreCuenta ORDER BY CreatedDate ASC LIMIT 1]) {
			return a.Id;
		}
		return null;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Resuelve el Id del Automovil__c a ligar: el seleccionado en el lookup, uno existente por Serie/VIN, o uno nuevo creado con los datos del formulario y ligado a la cuenta.
	 * @param d: Mapa de datos del formulario
	 * @param accountId: Id de la cuenta a la que se ligaria el vehiculo nuevo
	 * @return Id del Automovil__c resuelto o null si no aplica
	 */
	private static Id resolveVehiculo(Map<String, Object> d, Id accountId) {
		// 1) ¿Ya se seleccionó un vehículo en el lookup?
		String vehiculoId = getStr(d, 'Automovil__c');
		if (String.isNotBlank(vehiculoId)) {
			return (Id) vehiculoId;
		}
		// 2) Datos capturados/extraídos del auto.
		Object vObj = d.get('vehiculo');
		if (!(vObj instanceof Map<String, Object>)) {
			return null;
		}
		Map<String, Object> v = (Map<String, Object>) vObj;
		String serie = getStr(v, 'Serie__c');

		// 3) Buscar por Serie/VIN.
		if (String.isNotBlank(serie)) {
			List<Automovil__c> ex = [
				SELECT Id FROM Automovil__c WHERE Serie__c = :serie LIMIT 1
			];
			if (!ex.isEmpty()) {
				return ex[0].Id;
			}
		}

		// 4) Crear nuevo (si hay algún dato).
		// Serie__c es obligatoria en Vehiculo__c: sin serie no se puede crear.
		if (String.isBlank(serie)) {
			return null;
		}
		String marca = getStr(v, 'Marca__c');
		String modelo = getStr(v, 'Modelo__c');
		Automovil__c nv = new Automovil__c();
		nv.Marca__c = marca;
		nv.Modelo__c = modelo;
		nv.Serie__c = serie;
		nv.Placa__c = getStr(v, 'Placa__c');
		nv.Motor__c = getStr(v, 'Motor__c');
		nv.Descripcion_Completa__c = getStr(v, 'descripcion_completa__c');
		if (accountId != null) {
			nv.Cuenta__c = accountId;
		}
		// Año (solo si creaste el campo Anio__c en Automovil__c)
		setIfExistsVeh(nv, 'Anio__c', getStr(v, 'Anio__c'));
		// Name (si no es autonumérico, le ponemos algo legible)
		Schema.DescribeFieldResult nameDesc = Automovil__c.Name.getDescribe();
		if (!nameDesc.isAutoNumber()) {
			String nm = ((marca == null ? '' : marca) + ' ' +
						 (modelo == null ? '' : modelo) + ' ' +
						 (serie == null ? '' : serie)).trim();
			nv.Name = String.isBlank(nm) ? 'Vehículo' : nm.left(80);
		}
		insert nv;
		return nv.Id;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Asigna un valor a un campo del SObject solo si el campo existe, ignorando el error si no esta presente (p. ej. Anio__c).
	 * @param so: SObject al que se asignara el campo
	 * @param field: Nombre API del campo
	 * @param value: Valor a asignar
	 * @return void
	 */
	private static void setIfExistsVeh(SObject so, String field, Object value) {
		if (value == null || String.isBlank(String.valueOf(value))) { return; }
		try { so.put(field, value); } catch (Exception ignore) {}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve el Id del RecordType de tipo Persona activo para el objeto Account.
	 * @return Id del RecordType de cuenta persona o null si no existe
	 */
	private static Id getPersonAccountRecordTypeId() {
		for (RecordType rt : [
			SELECT Id FROM RecordType
			WHERE SObjectType = 'Account' AND IsPersonType = true AND IsActive = true
			LIMIT 1
		]) {
			return rt.Id;
		}
		return null;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Busca vehiculos por serie, placa, marca, modelo o nombre a partir de un termino de al menos 2 caracteres.
	 * @param searchTerm: Texto de busqueda (minimo 2 caracteres)
	 * @return Lista de Automovil__c coincidentes (maximo 10)
	 */
	@AuraEnabled(cacheable=false)
	public static List<Automovil__c> searchVehiculos(String searchTerm) {
		if (String.isBlank(searchTerm) || searchTerm.length() < 2) {
			return new List<Automovil__c>();
		}
		String filtro = '%' + searchTerm + '%';
		return [
			SELECT Id, Name, Marca__c, Modelo__c, Serie__c, Placa__c, Motor__c,
				   Descripcion_Completa__c, Cuenta__c, Cuenta__r.Name
			FROM Automovil__c
			WHERE Serie__c LIKE :filtro
			   OR Placa__c LIKE :filtro
			   OR Marca__c LIKE :filtro
			   OR Modelo__c LIKE :filtro
			   OR Name LIKE :filtro
			ORDER BY LastModifiedDate DESC
			LIMIT 10
		];
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve los productos activos de una familia (ramo) dada.
	 * @param ramo: Familia/ramo de producto a filtrar
	 * @return Lista de Product2 activos de la familia indicada
	 */
	@AuraEnabled(cacheable=true)
	public static List<Product2> getProducts(String ramo) {
		if (String.isBlank(ramo)) {
			return new List<Product2>();
		}
		return [
			SELECT Id, Name, ProductCode, Family
			FROM Product2
			WHERE IsActive = true
				AND Family = :ramo
			ORDER BY Name
		];
	}

	// Devuelve el Id del Contacto de una Cuenta Persona (PersonContactId).
	private static Id getPersonContactId(Id accountId) {
		try {
			Account a = [SELECT PersonContactId FROM Account WHERE Id = :accountId LIMIT 1];
			return a.PersonContactId;
		} catch (Exception e) {
			return null;
		}
	}

	// Crea un Contacto bajo la cuenta con el nombre escrito (o el del cliente).
	private static Id crearContacto(Map<String, Object> d, Id accountId) {
		String nombre = getStr(d, 'ContactoName');
		if (String.isBlank(nombre)) { nombre = getStr(d, 'clienteNombre'); }
		if (String.isBlank(nombre)) { return null; }
		List<String> partes = nombre.trim().split('\\s+');
		Contact c = new Contact();
		c.AccountId = accountId;
		c.Email = getStr(d, 'clienteEmail');
		c.Phone = getStr(d, 'clienteTelefono');
		if (partes.size() > 1) {
			c.LastName = partes[partes.size() - 1];
			String first = '';
			for (Integer i = 0; i < partes.size() - 1; i++) {
				first += (first == '' ? '' : ' ') + partes[i];
			}
			c.FirstName = first;
		} else {
			c.LastName = nombre.trim();
		}
		insert c;
		return c.Id;
	}

	// Crea (o reutiliza) un Contacto de persona bajo la cuenta usando el nombre y
	// apellidos del cliente. Respaldo para Individual cuando la cuenta no tiene
	// contacto de persona. Como solo se invoca si PersonContactId vino vacio, la
	// cuenta no es Cuenta Persona y por eso si se permite crear un Contacto normal.
	private static Id crearContactoIndividual(Map<String, Object> d, Id accountId) {
		if (accountId == null) { return null; }
		String nombre  = getStr(d, 'clienteNombre');
		String paterno = getStr(d, 'clienteApellidoPaterno');
		String materno = getStr(d, 'clienteApellidoMaterno');

		// Nombre completo para de-duplicar.
		List<String> ps = new List<String>();
		if (String.isNotBlank(nombre))  { ps.add(nombre.trim()); }
		if (String.isNotBlank(paterno)) { ps.add(paterno.trim()); }
		if (String.isNotBlank(materno)) { ps.add(materno.trim()); }
		String fullName = String.join(ps, ' ').trim();

		// Si ya existe un contacto con ese nombre bajo la cuenta, se reutiliza.
		if (String.isNotBlank(fullName)) {
			for (Contact ex : [SELECT Id FROM Contact WHERE AccountId = :accountId AND Name = :fullName LIMIT 1]) {
				return ex.Id;
			}
		}

		// LastName (Apellido) es obligatorio en Contact.
		String lastName = materno;
		if (String.isBlank(lastName)) { lastName = paterno; }
		if (String.isBlank(lastName)) { lastName = nombre; }
		if (String.isBlank(lastName)) {
			for (Account a : [SELECT Name FROM Account WHERE Id = :accountId LIMIT 1]) { lastName = a.Name; }
		}
		if (String.isBlank(lastName)) { return null; }

		Contact c = new Contact(AccountId = accountId);
		if (String.isNotBlank(nombre)) { c.FirstName = nombre; }
		// Si hay paterno y materno, el paterno va como segundo nombre (MiddleName)
		// y el materno como apellido, igual que en la Cuenta Persona.
		if (String.isNotBlank(paterno) && String.isNotBlank(materno)) {
			try { c.put('MiddleName', paterno); } catch (Exception ignore) {}
		}
		c.LastName = lastName;
		c.Email = getStr(d, 'clienteEmail');
		c.Phone = getStr(d, 'clienteTelefono');
		try {
			insert c;
			return c.Id;
		} catch (Exception e) {
			return null;
		}
	}

	// ============================================================
	// Persistencia por ramo con objetos ESTÁNDAR de FSC
	// ============================================================
	private static String buildRamoResumen(String ramo, Map<String, Object> det) {
		if (det == null || det.isEmpty()) { return null; }
		Map<String, String> etiquetas = new Map<String, String>{
			'estado' => 'Estado', 'tipoEstructura' => 'Tipo de estructura', 'numAsegurados' => 'No. de asegurados',
			'aseguradoPrincipal' => 'Asegurado principal', 'contratante' => 'Contratante', 'subramo' => 'Subramo',
			'destino' => 'Destino', 'numPasajeros' => 'No. de pasajeros',
			'giro' => 'Giro', 'actividad' => 'Actividad', 'ubicacion' => 'Ubicacion',
			'valorInmueble' => 'Valor del inmueble', 'valorContenidos' => 'Valor de contenidos',
			'tipoFianza' => 'Tipo de fianza', 'fiado' => 'Fiado', 'beneficiario' => 'Beneficiario', 'montoAfianzado' => 'Monto afianzado',
			'tipoRC' => 'Tipo de RC', 'profesion' => 'Profesion', 'plan' => 'Plan', 'red' => 'Red medica'
		};
		List<String> lineas = new List<String>();
		for (String k : det.keySet()) {
			Object v = det.get(k);
			if (v == null) { continue; }
			if (k == 'asegurados' && v instanceof List<Object>) {
				List<String> noms = new List<String>();
				for (Object ao : (List<Object>) v) {
					if (ao instanceof Map<String, Object>) {
						String nom = getStr((Map<String, Object>) ao, 'nombre');
						if (String.isNotBlank(nom)) { noms.add(nom); }
					}
				}
				if (!noms.isEmpty()) { lineas.add('\u2022 Asegurados: ' + String.join(noms, ', ')); }
				continue;
			}
			if (String.isBlank(String.valueOf(v))) { continue; }
			String etq = etiquetas.containsKey(k) ? etiquetas.get(k) : k;
			lineas.add('\u2022 ' + etq + ': ' + String.valueOf(v));
		}
		if (lineas.isEmpty()) { return null; }
		return 'Detalle del ramo' + (String.isBlank(ramo) ? '' : ' (' + ramo + ')') + ':\n' + String.join(lineas, '\n');
	}
	
	private static void persistRamoStandardData(Id opportunityId, Id accountId, String ramo, Map<String, Object> det) {
		if (det == null || det.isEmpty()) { return; }
		String r = ramo.toUpperCase();
		List<Asset> assets = new List<Asset>();
		if (accountId != null) {
			if (r.contains('EMPRESAR')) {
				String giro = getStr(det, 'giro');
				String ubic = getStr(det, 'ubicacion');
				String nombre = String.isNotBlank(giro) ? giro : 'Riesgo empresarial';
				if (String.isNotBlank(ubic)) { nombre += ' - ' + ubic; }
				Asset a = new Asset(Name = nombre.left(255), AccountId = accountId);
				Decimal valInm = toDecimalSafe(det.get('valorInmueble'));
				Decimal valCon = toDecimalSafe(det.get('valorContenidos'));
				if (valInm != null) { a.Price = valInm; }
				a.Description = ('Actividad: ' + getStr(det, 'actividad') + ' | Inmueble: ' + String.valueOf(valInm) + ' | Contenidos: ' + String.valueOf(valCon)).left(255);
				a.put('Oportunidad__c', opportunityId);
				assets.add(a);
			} else if (r.contains('DA\u00d1O') || r.contains('DANO') || r.contains('HOGAR')) {
				String sub = getStr(det, 'subramo');
				Asset ad = new Asset(Name = ('Bien asegurado - ' + (String.isBlank(sub) ? ramo : sub)).left(255), AccountId = accountId);
				ad.put('Oportunidad__c', opportunityId);
				assets.add(ad);
			}
		}
		if (!assets.isEmpty()) {
			try { insert assets; } catch (Exception e) { System.debug('RAMO::: Asset -> ' + e.getMessage()); }
		}
		List<OpportunityContactRole> roles = new List<OpportunityContactRole>();
		if (r.contains('VIDA')) {
			Id titular = crearContactoDeNombre(getStr(det, 'aseguradoPrincipal'), accountId);
			if (titular == null && accountId != null) { titular = getPersonContactId(accountId); }
			if (titular != null) {
				roles.add(new OpportunityContactRole(OpportunityId = opportunityId, ContactId = titular, IsPrimary = true, Role = pickRole(new List<String>{ 'Insured', 'Policy Holder', 'Business User', 'Other' })));
			}
			String contrat = getStr(det, 'contratante');
			if (String.isNotBlank(contrat)) {
				Id cId = crearContactoDeNombre(contrat, accountId);
				if (cId != null && cId != titular) {
					roles.add(new OpportunityContactRole(OpportunityId = opportunityId, ContactId = cId, Role = pickRole(new List<String>{ 'Contratante', 'Decision Maker', 'Economic Buyer', 'Other' })));
				}
			}
		}
		if (r.contains('GMM') || r.contains('GASTOS') || r.contains('DENTAL') || r.contains('VISION') || r.contains('VISI\u00d3N')) {
			String rolAseg = pickRole(new List<String>{ 'Insured', 'Policy Holder', 'Business User', 'Other' });
			Set<Id> yaLigados = new Set<Id>();
			Boolean primero = true;
			Object asegObj = det.get('asegurados');
			if (asegObj instanceof List<Object>) {
				for (Object ao : (List<Object>) asegObj) {
					if (!(ao instanceof Map<String, Object>)) { continue; }
					String nom = getStr((Map<String, Object>) ao, 'nombre');
					if (String.isBlank(nom)) { continue; }
					Id cId = crearContactoDeNombre(nom, accountId);
					if (cId == null && accountId != null) { cId = getPersonContactId(accountId); }
					if (cId != null && !yaLigados.contains(cId)) {
						roles.add(new OpportunityContactRole(OpportunityId = opportunityId, ContactId = cId, IsPrimary = primero, Role = rolAseg));
						yaLigados.add(cId); primero = false;
					}
				}
			}
			if (yaLigados.isEmpty()) {
				Id personContact = accountId != null ? getPersonContactId(accountId) : null;
				if (personContact != null) {
					roles.add(new OpportunityContactRole(OpportunityId = opportunityId, ContactId = personContact, IsPrimary = true, Role = rolAseg));
				}
			}
		}
		if (!roles.isEmpty()) {
			try { Database.insert(roles, false); } catch (Exception e) { System.debug('RAMO::: OCR -> ' + e.getMessage()); }
		}
	}
	
	private static Id crearContactoDeNombre(String nombreCompleto, Id accountId) {
		if (String.isBlank(nombreCompleto) || accountId == null) { return null; }
		String limpio = nombreCompleto.trim();
		List<Contact> existentes = [SELECT Id FROM Contact WHERE AccountId = :accountId AND Name = :limpio LIMIT 1];
		if (!existentes.isEmpty()) { return existentes[0].Id; }
		List<String> partes = limpio.split('\\s+');
		Contact c = new Contact(AccountId = accountId);
		if (partes.size() > 1) {
			c.LastName = partes[partes.size() - 1];
			List<String> first = new List<String>();
			for (Integer i = 0; i < partes.size() - 1; i++) { first.add(partes[i]); }
			c.FirstName = String.join(first, ' ');
		} else { c.LastName = limpio; }
		try { insert c; return c.Id; } catch (Exception e) { return null; }
	}
	
	private static Set<String> ocrRolesCache;
	private static String pickRole(List<String> preferidos) {
		if (ocrRolesCache == null) {
			ocrRolesCache = new Set<String>();
			for (Schema.PicklistEntry pe : OpportunityContactRole.Role.getDescribe().getPicklistValues()) {
				if (pe.isActive()) { ocrRolesCache.add(pe.getValue()); }
			}
		}
		for (String pref : preferidos) { if (ocrRolesCache.contains(pref)) { return pref; } }
		return null;
	}
	
	private static Decimal toDecimalSafe(Object o) {
		if (o == null) { return null; }
		try { return Decimal.valueOf(String.valueOf(o)); } catch (Exception e) { return null; }
	}
	
	// Buscador de contactos para el lookup del LWC (mismo patrón que searchAccounts).
	@AuraEnabled(cacheable=false)
	public static List<ContactResult> searchContacts(String searchTerm) {
		List<ContactResult> out = new List<ContactResult>();
		if (String.isBlank(searchTerm) || searchTerm.length() < 2) {
			return out;
		}
		String filtro = '%' + searchTerm + '%';
		for (Contact c : [
			SELECT Id, Name, Email, Phone, AccountId, Account.Name
			FROM Contact
			WHERE Name LIKE :filtro OR Email LIKE :filtro
			ORDER BY LastModifiedDate DESC
			LIMIT 10
		]) {
			ContactResult r = new ContactResult();
			r.Id = c.Id;
			r.Name = c.Name;
			r.Email = c.Email;
			r.Phone = c.Phone;
			r.AccountId = c.AccountId;
			out.add(r);
		}
		return out;
	}

	public class ContactResult {
		@AuraEnabled public Id Id;
		@AuraEnabled public String Name;
		@AuraEnabled public String Email;
		@AuraEnabled public String Phone;
		@AuraEnabled public Id AccountId;
	}
	/**
	 * @description: Devuelve los archivos (ContentDocument) ligados a una oportunidad,
	 *               con lo necesario para mostrarlos y abrirlos/descargarlos desde el LWC.
	 */
	@AuraEnabled(cacheable=false)
	public static List<ArchivoOpp> getArchivosDeOportunidad(Id opportunityId) {
		List<ArchivoOpp> out = new List<ArchivoOpp>();
		if (opportunityId == null) { return out; }
		try {
			Set<Id> docIds = new Set<Id>();
			for (ContentDocumentLink l : [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :opportunityId]) {
				docIds.add(l.ContentDocumentId);
			}
			if (docIds.isEmpty()) { return out; }
			for (ContentVersion v : [
				SELECT ContentDocumentId, Title, FileExtension, ContentSize, CreatedDate
				FROM ContentVersion
				WHERE ContentDocumentId IN :docIds AND IsLatest = true
				ORDER BY CreatedDate DESC
			]) {
				ArchivoOpp a = new ArchivoOpp();
				a.contentDocumentId = v.ContentDocumentId;
				a.title = v.Title;
				a.extension = v.FileExtension;
				a.size = (Integer) v.ContentSize;
				out.add(a);
			}
		} catch (Exception e) {
			throw new AuraHandledException('No se pudieron cargar los archivos: ' + e.getMessage());
		}
		return out;
	}

	public class ArchivoOpp {
		@AuraEnabled public Id contentDocumentId;
		@AuraEnabled public String title;
		@AuraEnabled public String extension;
		@AuraEnabled public Integer size;
	}
}
