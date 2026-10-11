/**
 *   @name: PolicyController
 *   @version: 1.0
 *   @creation date: 08/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Apoya al LWC policyCreator: localiza la InsurancePolicy generada por
 *                 el flow del org al pasar la oportunidad a Póliza. La póliza se ubica
 *                 por la cotización origen (SourceQuoteId) y, como respaldo, por las
 *                 cotizaciones de la oportunidad.
 */
public with sharing class PolicyController {

	/**
	 * @creation date: 08/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve el Id de la InsurancePolicy asociada a la cotización o a la
	 *               oportunidad indicadas. Primero busca por SourceQuoteId = quoteId; si no
	 *               la encuentra, busca por las cotizaciones de la oportunidad.
	 * @param quoteId: Id de la cotización aceptada (origen de la póliza). Puede ser null.
	 * @param opportunityId: Id de la oportunidad. Puede ser null.
	 * @return Id de la InsurancePolicy encontrada, o null si no existe.
	 */
	@AuraEnabled(cacheable=false)
	public static Id getPolicyIdByQuote(Id quoteId, Id opportunityId) {
		try {
			// 1) Por la cotización origen (SourceQuoteId).
			if (quoteId != null) {
				List<InsurancePolicy> ps = [
					SELECT Id FROM InsurancePolicy
					WHERE SourceQuoteId = :quoteId
					ORDER BY CreatedDate DESC
					LIMIT 1
				];
				if (!ps.isEmpty()) { return ps[0].Id; }
			}
			// 2) Respaldo: por cualquier cotización de la oportunidad.
			if (opportunityId != null) {
				Set<Id> quoteIds = new Set<Id>();
				for (Quote q : [SELECT Id FROM Quote WHERE OpportunityId = :opportunityId]) {
					quoteIds.add(q.Id);
				}
				if (!quoteIds.isEmpty()) {
					List<InsurancePolicy> ps = [
						SELECT Id FROM InsurancePolicy
						WHERE SourceQuoteId IN :quoteIds
						ORDER BY CreatedDate DESC
						LIMIT 1
					];
					if (!ps.isEmpty()) { return ps[0].Id; }
				}
				// 3) Por la oportunidad origen (pólizas creadas desde Crear Póliza).
				for (InsurancePolicy p : [
					SELECT Id FROM InsurancePolicy WHERE SourceOpportunityId = :opportunityId
					ORDER BY CreatedDate DESC LIMIT 1
				]) { return p.Id; }
			}
			return null;
		} catch (Exception e) {
			throw new AuraHandledException('Error al localizar la póliza: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 02/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve los datos base para crear la póliza desde Crear Póliza (la póliza se crea al subir el
	 * PDF, ya con su número real). Toma de la oportunidad el asegurado y el propietario, y de la cotización
	 * aceptada la aseguradora, el producto, el ramo, la prima, la frecuencia y las fechas, con las mismas reglas
	 * que usaba el flujo Create_Insured_Policy. Los picklists solo se llenan con valores válidos.
	 * @param opportunityId: Id de la oportunidad (opcional; sin ella solo se devuelven el estatus y las fechas)
	 * @param quoteId: Id de la cotización aceptada (opcional; si no llega se toma la aceptada más reciente)
	 * @return Valores por API name de InsurancePolicy (fechas como AAAA-MM-DD)
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> datosBasePoliza(Id opportunityId, Id quoteId) {
		Date hoy = Date.today();
		Map<String, Object> base = new Map<String, Object>{
			'Status' => 'Inicial',
			'EffectiveDate' => String.valueOf(hoy),
			'ExpirationDate' => String.valueOf(hoy.addDays(365))
		};
		if (opportunityId == null) { return base; }
		Opportunity opp = [SELECT Id, AccountId, OwnerId FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
		base.put('SourceOpportunityId', opp.Id);
		base.put('NameInsuredId', opp.AccountId);
		base.put('OwnerId', opp.OwnerId);
		List<Quote> qs = quoteId != null
			? [SELECT Id, Aseguradora__c, Product__c, Ramos__c, Prima_Total__c, PrimaAnual__c, TotalPrice, Frecuencia_de_prima__c
			   FROM Quote WHERE Id = :quoteId AND OpportunityId = :opportunityId LIMIT 1]
			: [SELECT Id, Aseguradora__c, Product__c, Ramos__c, Prima_Total__c, PrimaAnual__c, TotalPrice, Frecuencia_de_prima__c
			   FROM Quote WHERE OpportunityId = :opportunityId AND Status = 'Accepted' ORDER BY CreatedDate DESC LIMIT 1];
		if (qs.isEmpty()) { return base; }
		Quote q = qs[0];
		base.put('SourceQuoteId', q.Id);
		base.put('Aseguradora__c', q.Aseguradora__c);
		base.put('ProductId', q.Product__c);
		putPicklist(base, 'PolicyType', InsurancePolicy.PolicyType.getDescribe(), q.Ramos__c);
		putPicklist(base, 'Ramo__c', InsurancePolicy.Ramo__c.getDescribe(), q.Ramos__c);
		Decimal prima = (q.Prima_Total__c != null && q.Prima_Total__c > 0) ? q.Prima_Total__c
			: ((q.PrimaAnual__c != null && q.PrimaAnual__c > 0) ? q.PrimaAnual__c : q.TotalPrice);
		base.put('PremiumAmount', prima);
		base.put('GrossWrittenPremium', prima);
		String frecuencia = String.isBlank(q.Frecuencia_de_prima__c) ? 'Anual' : q.Frecuencia_de_prima__c;
		putPicklist(base, 'PremiumFrequency', InsurancePolicy.PremiumFrequency.getDescribe(), frecuencia);
		Map<String, Integer> diasPago = new Map<String, Integer>{
			'Mensual' => 30, 'Bimestral' => 60, 'Trimestral' => 90, 'Semestral' => 180, 'Anual' => 365
		};
		Integer dias = diasPago.containsKey(q.Frecuencia_de_prima__c) ? diasPago.get(q.Frecuencia_de_prima__c) : 0;
		base.put('PaymentDueDate', String.valueOf(hoy.addDays(dias)));
		return base;
	}

	/**
	 * @creation date: 02/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Agrega al mapa el valor de un picklist solo si es un valor activo del campo (sin importar
	 * mayúsculas ni acentos), para no romper el guardado con un valor fuera del catálogo.
	 * @param base: Mapa de valores por API name
	 * @param campo: API name del campo
	 * @param f: Describe del campo picklist
	 * @param valor: Valor propuesto
	 * @return void
	 */
	private static void putPicklist(Map<String, Object> base, String campo, Schema.DescribeFieldResult f, String valor) {
		if (String.isBlank(valor)) { return; }
		String buscado = normKey(valor);
		for (Schema.PicklistEntry pe : f.getPicklistValues()) {
			if (pe.isActive() && normKey(pe.getValue()) == buscado) { base.put(campo, pe.getValue()); return; }
		}
	}

	// API Name del Prompt Template y de su variable de entrada (Prompt Builder).
	private static final String PROMPT_TEMPLATE_API_NAME = 'Analizador_Poliza_Auto';
	private static final String PROMPT_INPUT_PARAM = 'Input:TextoPoliza';

	/**
	 * @creation date: 10/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Envía a Einstein (Prompt Template) el texto extraído de un PDF de póliza
	 *               y devuelve el JSON con los datos de la póliza para llenar el formulario.
	 *               El texto se extrae en el navegador (pdf.js); aquí solo se llama al prompt.
	 * @param textoPoliza: texto plano de la póliza (extraído del PDF en el LWC).
	 * @return cadena JSON con los datos de la póliza (limpia de fences de código), o '' si falla.
	 */
	@AuraEnabled(cacheable=false)
	public static String analizarPoliza(String textoPoliza) {
		if (String.isBlank(textoPoliza)) {
			throw new AuraHandledException('No se recibió texto de la póliza para analizar.');
		}
		if (Test.isRunningTest()) { return '{}'; }
		try {
			String texto = textoPoliza.length() > 100000
				? textoPoliza.substring(0, 100000)
				: textoPoliza;

			ConnectApi.WrappedValue wrapped = new ConnectApi.WrappedValue();
			wrapped.value = texto;
			Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
			inputParams.put(PROMPT_INPUT_PARAM, wrapped);

			ConnectApi.EinsteinPromptTemplateGenerationsInput genInput = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
			genInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
			genInput.additionalConfig.applicationName = 'PromptBuilderPreview';
			genInput.isPreview = false;
			genInput.inputParams = inputParams;

			ConnectApi.EinsteinPromptTemplateGenerationsRepresentation gen =
				ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(PROMPT_TEMPLATE_API_NAME, genInput);

			if (gen != null && gen.generations != null && !gen.generations.isEmpty() && String.isNotBlank(gen.generations[0].text)) {
				return cleanJson(gen.generations[0].text);
			}
			throw new AuraHandledException('La IA no devolvió información de la póliza.');
		} catch (AuraHandledException ahe) {
			// Se re-lanza tal cual para conservar el mensaje real (si no, queda "Script-thrown exception").
			throw ahe;
		} catch (Exception e) {
			throw new AuraHandledException('Error al analizar la póliza: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 10/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Limpia la respuesta de la IA: quita los bloques de Markdown (```json) y recorta del primer "{"
	 * al último "}" para dejar solo el JSON.
	 * @param raw: Texto devuelto por el modelo
	 * @return JSON limpio listo para deserializar
	 */
	private static String cleanJson(String raw) {
		if (String.isBlank(raw)) { return '{}'; }
		String payload = raw.trim();
		if (payload.startsWith('```')) {
			payload = payload.replaceFirst('^```[a-zA-Z]*', '').trim();
			if (payload.endsWith('```')) {
				payload = payload.substring(0, payload.length() - 3).trim();
			}
		}
		Integer start = payload.indexOf('{');
		Integer last = payload.lastIndexOf('}');
		if (start < 0 || last < start) { return '{}'; }
		return payload.substring(start, last + 1);
	}

	/**
	 * @creation date: 27/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Al emitir la póliza crea el vínculo póliza–bien (InsurancePolicyAsset). Reúsa el Asset creado
	 * por la oportunidad si existe; si no, crea uno con los datos del vehículo o bien asegurado. Es idempotente.
	 * @param policyId: Id de la InsurancePolicy
	 * @return Id del InsurancePolicyAsset creado o existente; null si no hay bien que ligar
	 */
	@AuraEnabled
	public static Id crearVinculoBien(Id policyId) {
		if (policyId == null) {
			throw new AuraHandledException('No se recibió la póliza para vincular el bien.');
		}
		try {
			// 1) Datos de la póliza.
			InsurancePolicy pol = [
				SELECT Id, Name, NameInsuredId, SourceOpportunityId, SourceQuoteId,
					   Ramo__c, ProductId, PremiumAmount, EffectiveDate
				FROM InsurancePolicy
				WHERE Id = :policyId
				LIMIT 1
			];

			// 2) Si ya existe el vínculo, no duplicar (idempotente).
			List<InsurancePolicyAsset> existentes = [
				SELECT Id FROM InsurancePolicyAsset
				WHERE InsurancePolicyId = :policyId
				LIMIT 1
			];
			if (!existentes.isEmpty()) { return existentes[0].Id; }

			// 3) Cuenta del asegurado (por la oportunidad origen o por NameInsured).
			Id accountId = resolverCuentaDePoliza(pol);

			// 3.1) Bien del cliente (CustomerProperty) del asegurado, si existe.
			//      Es el objeto donde hoy se guarda el vehículo/bien.
			CustomerProperty bienCliente = null;
			if (accountId != null) {
				for (CustomerProperty cp : [
					SELECT Id, Name FROM CustomerProperty
					WHERE PrimaryOwnerId = :accountId
					ORDER BY LastModifiedDate DESC LIMIT 1
				]) { bienCliente = cp; }
			}
			Schema.DescribeFieldResult cpField = InsurancePolicyAsset.CustomerPropertyId.getDescribe();

			// 4) Bien a ligar. Si hay CustomerProperty y el campo lo acepta, se usa ese
			//    (no se crea Asset). Si no, se reúsa/crea un Asset como respaldo.
			// Para ramos que NO son de autos (GMM, Vida, Daños) no se liga un vehículo,
			// aunque la cuenta tenga uno de otra póliza. Si el ramo viene vacío, se permite.
			Boolean ramoNoAuto = String.isNotBlank(pol.Ramo__c) && !normKey(pol.Ramo__c).contains('auto');
			Boolean usarCustomerProperty = (!ramoNoAuto && bienCliente != null && campoAcepta(cpField, CustomerProperty.SObjectType));
			Id assetId = null;
			String assetName = null;
			if (!usarCustomerProperty) {
				if (pol.SourceOpportunityId != null) {
					for (Asset a : [
						SELECT Id, Name FROM Asset
						WHERE Oportunidad__c = :pol.SourceOpportunityId
						ORDER BY CreatedDate DESC LIMIT 1
					]) {
						assetId = a.Id;
						assetName = a.Name;
					}
				}
				if (assetId == null && campoAcepta(cpField, Asset.SObjectType)) {
					String nombreBien = String.isNotBlank(pol.Ramo__c)
						? ('Bien asegurado - ' + pol.Ramo__c)
						: 'Bien asegurado';
					Asset nuevo = new Asset(Name = nombreBien.left(255));
					if (accountId != null) { nuevo.AccountId = accountId; }
					if (pol.ProductId != null) { nuevo.Product2Id = pol.ProductId; }
					nuevo.put('Oportunidad__c', pol.SourceOpportunityId);
					insert nuevo;
					assetId = nuevo.Id;
					assetName = nuevo.Name;
				}
			}

			// 5) Crear el vínculo póliza-bien.
			String nombreVinculo = (bienCliente != null && String.isNotBlank(bienCliente.Name))
				? bienCliente.Name
				: (String.isNotBlank(assetName)
					? assetName
					: (String.isNotBlank(pol.Ramo__c) ? ('Bien asegurado - ' + pol.Ramo__c) : 'Bien asegurado'));
			InsurancePolicyAsset ipa = new InsurancePolicyAsset(
				InsurancePolicyId = policyId,
				AssetName = nombreVinculo.left(255),
				IsActive = true
			);
			// CustomerPropertyId puede apuntar a CustomerProperty o a Asset según el org.
			// Se prioriza el CustomerProperty del cliente (donde vive el vehículo/bien);
			// si el campo no lo acepta o no hay bien, se usa el Asset como respaldo.
			if (bienCliente != null && campoAcepta(cpField, CustomerProperty.SObjectType)) {
				ipa.CustomerPropertyId = bienCliente.Id;
			} else if (assetId != null && campoAcepta(cpField, Asset.SObjectType)) {
				ipa.CustomerPropertyId = assetId;
			}
			if (pol.ProductId != null) { ipa.ProductId = pol.ProductId; }
			if (pol.PremiumAmount != null) { ipa.StandardPremiumAmount = pol.PremiumAmount; }
			if (pol.EffectiveDate != null) { ipa.EffectiveFromDate = pol.EffectiveDate.date(); }
			insert ipa;
			return ipa.Id;
		} catch (AuraHandledException ahe) {
			throw ahe;
		} catch (DmlException e) {
			throw new AuraHandledException('No se pudo crear el vínculo póliza-bien: ' + detalleDml(e));
		} catch (Exception e) {
			throw new AuraHandledException('No se pudo crear el vínculo póliza-bien: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 17/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Indica si un campo de tipo lookup acepta registros del objeto indicado.
	 * @param f: Describe del campo a revisar
	 * @param objetivo: Objeto que se quiere asignar al lookup
	 * @return true si el lookup apunta a ese objeto
	 */
	private static Boolean campoAcepta(Schema.DescribeFieldResult f, Schema.SObjectType objetivo) {
		if (f == null || objetivo == null) { return false; }
		for (Schema.SObjectType t : f.getReferenceTo()) {
			if (t == objetivo) { return true; }
		}
		return false;
	}

	/**
	 * @creation date: 27/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Obtiene la cuenta del asegurado de la póliza: la de la oportunidad origen o, si NameInsured es
	 * una cuenta, esa misma.
	 * @param pol: Póliza con NameInsuredId y SourceOpportunityId consultados
	 * @return Id de la cuenta del asegurado; null si no se puede resolver
	 */
	private static Id resolverCuentaDePoliza(InsurancePolicy pol) {
		if (pol.SourceOpportunityId != null) {
			for (Opportunity o : [SELECT AccountId FROM Opportunity WHERE Id = :pol.SourceOpportunityId LIMIT 1]) {
				if (o.AccountId != null) { return o.AccountId; }
			}
		}
		if (pol.NameInsuredId != null && ((Id) pol.NameInsuredId).getSObjectType() == Account.SObjectType) {
			return (Id) pol.NameInsuredId;
		}
		return null;
	}

	/**
	 * @creation date: 06/08/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Guarda el PDF seleccionado como archivo de la póliza. Es idempotente: si ya existe un archivo
	 * con el mismo nombre ligado a la póliza, no lo duplica.
	 * @param base64: Contenido del PDF en Base64
	 * @param nombreArchivo: Nombre del archivo
	 * @param policyId: Id de la InsurancePolicy
	 * @return Id del ContentDocument ligado a la póliza
	 */
	@AuraEnabled
	public static Id guardarArchivoEnPoliza(String base64, String nombreArchivo, Id policyId) {
		if (String.isBlank(base64) || policyId == null) { return null; }
		try {
			String nombre = String.isBlank(nombreArchivo) ? 'Poliza.pdf' : nombreArchivo;
			// Evita duplicar: busca un archivo con el mismo nombre ya ligado a la póliza.
			Set<Id> docsLigados = new Set<Id>();
			for (ContentDocumentLink cdl : [
				SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :policyId
			]) {
				docsLigados.add(cdl.ContentDocumentId);
			}
			if (!docsLigados.isEmpty()) {
				for (ContentVersion cvExist : [
					SELECT ContentDocumentId FROM ContentVersion
					WHERE ContentDocumentId IN :docsLigados AND Title = :nombre LIMIT 1
				]) {
					return cvExist.ContentDocumentId;
				}
			}
			ContentVersion cv = new ContentVersion(
				Title = nombre,
				PathOnClient = nombre,
				VersionData = EncodingUtil.base64Decode(base64),
				Origin = 'H'
			);
			insert cv;
			ContentVersion stored = [
				SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1
			];
			insert new ContentDocumentLink(
				ContentDocumentId = stored.ContentDocumentId,
				LinkedEntityId = policyId,
				ShareType = 'V',
				Visibility = 'AllUsers'
			);
			return stored.ContentDocumentId;
		} catch (Exception e) {
			throw new AuraHandledException('No se pudo guardar el archivo en la póliza: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 17/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Orquestador: completa los registros hijos de la póliza (bien, participantes, coberturas,
	 * transacción inicial, fecha de renovación y producer) de forma idempotente. Cada paso se ejecuta por separado
	 * para que un error no detenga a los demás.
	 * @param policyId: Id de la InsurancePolicy
	 * @param opportunityId: Id de la oportunidad origen (si es null se toma de la póliza)
	 * @return Resumen con el resultado o el error de cada paso
	 */
	@AuraEnabled
	public static Map<String, Object> completarPoliza(Id policyId, Id opportunityId) {
		Map<String, Object> resumen = new Map<String, Object>();
		if (policyId == null) {
			throw new AuraHandledException('No se recibió la póliza para completar sus registros.');
		}
		// Resuelve la oportunidad origen si no llega por parámetro.
		Id oppId = opportunityId;
		if (oppId == null) {
			for (InsurancePolicy p : [SELECT SourceOpportunityId FROM InsurancePolicy WHERE Id = :policyId LIMIT 1]) {
				oppId = p.SourceOpportunityId;
			}
		}

		// 1) Bien asegurado.
		try {
			Id ipaId = crearVinculoBien(policyId);
			resumen.put('bien', ipaId != null ? 1 : 0);
		} catch (Exception e) { resumen.put('bienError', msgLimpio(e)); }

		// 2) Asegurados / participantes (colectiva por OCR + respaldo individual).
		try {
			resumen.put('asegurados', crearParticipantesPoliza(policyId, oppId));
		} catch (Exception e) { resumen.put('aseguradosError', msgLimpio(e)); }

		// 3) Coberturas desde el catálogo del producto.
		try {
			resumen.put('coberturas', crearCoberturasPoliza(policyId));
		} catch (Exception e) { resumen.put('coberturasError', msgLimpio(e)); }

		// 4) Transacción de prima inicial.
		try {
			Id txId = crearTransaccionInicial(policyId);
			resumen.put('transaccion', txId != null ? 1 : 0);
		} catch (Exception e) { resumen.put('transaccionError', msgLimpio(e)); }

		// 5) Fecha de renovación (para los avisos de renovación): se llena con el fin
		//    de vigencia si está vacía.
		try {
			resumen.put('renovacion', llenarFechaRenovacion(policyId) ? 1 : 0);
		} catch (Exception e) { resumen.put('renovacionError', msgLimpio(e)); }

		// 6) Producer (agente) de la oportunidad -> InsurancePolicy.ProducerId.
		try {
			resumen.put('producer', vincularProducer(policyId, oppId) ? 1 : 0);
		} catch (Exception e) { resumen.put('producerError', msgLimpio(e)); }

		return resumen;
	}

	/**
	 * @creation date: 18/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Liga el Producer de la oportunidad a la póliza (InsurancePolicy.ProducerId) si la póliza aún no
	 * tiene productor.
	 * @param policyId: Id de la InsurancePolicy
	 * @param opportunityId: Id de la oportunidad origen
	 * @return true si asignó el productor
	 */
	@AuraEnabled
	public static Boolean vincularProducer(Id policyId, Id opportunityId) {
		if (policyId == null || opportunityId == null) { return false; }
		Id prod = null;
		for (Opportunity o : [SELECT Producer__c FROM Opportunity WHERE Id = :opportunityId LIMIT 1]) {
			prod = (Id) o.get('Producer__c');
		}
		if (prod == null) { return false; }
		for (InsurancePolicy p : [SELECT Id, ProducerId FROM InsurancePolicy WHERE Id = :policyId LIMIT 1]) {
			if (p.ProducerId != null) { return false; }
		}
		update new InsurancePolicy(Id = policyId, ProducerId = prod);
		return true;
	}

	/**
	 * @creation date: 17/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Llena la fecha de renovación de la póliza (RenewalDate / PlannedRenewalDate) con el fin de
	 * vigencia si están vacías, para habilitar los avisos de renovación.
	 * @param policyId: Id de la InsurancePolicy
	 * @return true si se actualizó alguna fecha
	 */
	@AuraEnabled
	public static Boolean llenarFechaRenovacion(Id policyId) {
		if (policyId == null) { return false; }
		InsurancePolicy p = [
			SELECT Id, ExpirationDate, RenewalDate, PlannedRenewalDate
			FROM InsurancePolicy WHERE Id = :policyId LIMIT 1
		];
		Object exp = p.get('ExpirationDate');
		if (exp == null) { return false; }
		// ExpirationDate puede ser Date o Datetime según el org: se resuelven ambos tipos.
		Date d; Datetime dt;
		if (exp instanceof Datetime) { dt = (Datetime) exp; d = dt.date(); }
		else { d = (Date) exp; dt = Datetime.newInstance(d, Time.newInstance(12, 0, 0, 0)); }

		Boolean cambio = false;
		InsurancePolicy upd = new InsurancePolicy(Id = policyId);
		if (p.PlannedRenewalDate == null) { asignaFechaFlexible(upd, 'PlannedRenewalDate', d, dt); cambio = true; }
		if (p.RenewalDate == null)        { asignaFechaFlexible(upd, 'RenewalDate', d, dt); cambio = true; }
		if (cambio) { update upd; }
		return cambio;
	}

	/**
	 * @creation date: 17/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Crea los participantes de la póliza (InsurancePolicyParticipant): en colectivas copia los
	 * asegurados capturados como roles de contacto de la oportunidad; en individuales usa la persona de la cuenta
	 * asegurada.
	 * @param policyId: Id de la InsurancePolicy
	 * @param opportunityId: Id de la oportunidad origen
	 * @return Número de participantes creados
	 */
	@AuraEnabled
	public static Integer crearParticipantesPoliza(Id policyId, Id opportunityId) {
		if (policyId == null) {
			throw new AuraHandledException('No se recibió la póliza para crear sus participantes.');
		}
		InsurancePolicy pol = [
			SELECT Id, NameInsuredId, SourceOpportunityId
			FROM InsurancePolicy WHERE Id = :policyId LIMIT 1
		];
		Id oppId = opportunityId != null ? opportunityId : pol.SourceOpportunityId;

		Integer creados = 0;
		// 1) Colectiva: asegurados desde OCR (no rompe si falla o si no hay).
		if (oppId != null) {
			try { creados += AseguradosController.copiarAseguradosAPoliza(oppId, policyId); }
			catch (Exception ignore) {}
		}

		// 2) Si ya hay participantes en la póliza, no crear el respaldo.
		Integer total = [SELECT COUNT() FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :policyId];
		if (total > 0) { return creados; }

		// 3) Respaldo individual: participante desde el contacto de la oportunidad o el asegurado.
		Id contactId = null;
		String participante = null;
		if (oppId != null) {
			for (OpportunityContactRole ocr : [
				SELECT ContactId, Contact.Name FROM OpportunityContactRole
				WHERE OpportunityId = :oppId AND ContactId != null
				ORDER BY IsPrimary DESC, Contact.Name LIMIT 1
			]) { contactId = ocr.ContactId; participante = ocr.Contact != null ? ocr.Contact.Name : null; }
		}

		InsurancePolicyParticipant p = new InsurancePolicyParticipant();
		p.InsurancePolicyId = policyId;
		String rol = pickPicklist(InsurancePolicyParticipant.Role.getDescribe(),
			new List<String>{ 'Insured', 'Covered Party', 'Named Insured', 'Asegurado', 'Insured Party', 'Covered' });
		if (String.isNotBlank(rol)) { p.Role = rol; }
		try { p.EffectiveDate = Date.today(); } catch (Exception ignore) {}

		if (contactId != null) {
			p.PrimaryParticipantContactId = contactId;
		} else if (pol.NameInsuredId != null) {
			// NameInsured es Maestro-Detalle a Cuenta (o Contacto según el org).
			Id insuredId = pol.NameInsuredId;
			if (insuredId.getSObjectType() == Account.SObjectType) {
				p.PrimaryParticipantAccountId = insuredId;
				for (Account a : [SELECT Name FROM Account WHERE Id = :insuredId LIMIT 1]) { participante = a.Name; }
			} else if (insuredId.getSObjectType() == Contact.SObjectType) {
				p.PrimaryParticipantContactId = insuredId;
				for (Contact c : [SELECT Name FROM Contact WHERE Id = :insuredId LIMIT 1]) { participante = c.Name; }
			}
		}

		// Sin cuenta ni contacto que ligar, no hay participante que crear.
		if (p.PrimaryParticipantContactId == null && p.PrimaryParticipantAccountId == null) {
			return creados;
		}
		if (String.isNotBlank(participante)) { p.ParticipantName = participante.left(255); }
		// Completa Cuenta, Producto y detalle de prima desde la póliza.
		aplicarDatosParticipante(p, policyId, p.PrimaryParticipantAccountId);
		insert p;
		return creados + 1;
	}

	/**
	 * @creation date: 17/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Crea las coberturas de la póliza (InsurancePolicyCoverage) a partir de las coberturas del
	 * catálogo del producto. Es idempotente.
	 * @param policyId: Id de la InsurancePolicy
	 * @return Número de coberturas creadas
	 */
	@AuraEnabled
	public static Integer crearCoberturasPoliza(Id policyId) {
		if (policyId == null) {
			throw new AuraHandledException('No se recibió la póliza para crear sus coberturas.');
		}
		InsurancePolicy pol = [
			SELECT Id, ProductId, EffectiveDate
			FROM InsurancePolicy WHERE Id = :policyId LIMIT 1
		];
		if (pol.ProductId == null) {
			// Sin producto no se pueden derivar coberturas del catálogo.
			return 0;
		}

		// Coberturas ya presentes en la póliza (idempotencia por tipo y por nombre).
		Set<Id> yaPorTipo = new Set<Id>();
		Set<String> yaPorNombre = new Set<String>();
		for (InsurancePolicyCoverage c : [
			SELECT CoverageTypeId, CoverageName
			FROM InsurancePolicyCoverage WHERE InsurancePolicyId = :policyId
		]) {
			if (c.CoverageTypeId != null) { yaPorTipo.add(c.CoverageTypeId); }
			if (String.isNotBlank(c.CoverageName)) { yaPorNombre.add(c.CoverageName.toLowerCase()); }
		}

		// Bien asegurado de la póliza (para ligar la cobertura, si existe uno).
		Id assetId = null;
		for (InsurancePolicyAsset a : [
			SELECT Id FROM InsurancePolicyAsset
			WHERE InsurancePolicyId = :policyId ORDER BY CreatedDate ASC LIMIT 1
		]) { assetId = a.Id; }

		List<InsurancePolicyCoverage> nuevas = new List<InsurancePolicyCoverage>();
		// Catálogo de coberturas del producto: ProductCoverage (lo administra Productos y Coberturas).
		for (ProductCoverage pca : [
			SELECT CoverageTypeId, CoverageType.Name, CoverageType.CoverageCode,
				   CoverageType.LimitAmount, CoverageType.DeductibleAmount,
				   CoverageType.PremiumAmount, CoverageType.Description
			FROM ProductCoverage
			WHERE ProductId = :pol.ProductId AND CoverageTypeId != null
		]) {
			String nombre = pca.CoverageType != null ? pca.CoverageType.Name : null;
			if (String.isBlank(nombre)) { continue; }
			// Defensa: no traer placeholders "PENDIENTE" aunque quedara alguno en el catálogo.
			if (nombre.toUpperCase().startsWith('PENDIENTE')) { continue; }
			if (yaPorTipo.contains(pca.CoverageTypeId)) { continue; }
			if (yaPorNombre.contains(nombre.toLowerCase())) { continue; }

			InsurancePolicyCoverage c = new InsurancePolicyCoverage();
			c.InsurancePolicyId = policyId;
			c.CoverageTypeId = pca.CoverageTypeId;
			c.CoverageName = nombre.length() > 255 ? nombre.substring(0, 255) : nombre;
			if (pca.CoverageType != null) {
				if (String.isNotBlank(pca.CoverageType.CoverageCode)) { c.CoverageCode = pca.CoverageType.CoverageCode; }
				if (pca.CoverageType.LimitAmount != null)      { c.LimitAmount = pca.CoverageType.LimitAmount; }
				if (pca.CoverageType.DeductibleAmount != null) { c.DeductibleAmount = pca.CoverageType.DeductibleAmount; }
				if (pca.CoverageType.PremiumAmount != null)    { c.PremiumAmount = pca.CoverageType.PremiumAmount; }
				if (String.isNotBlank(pca.CoverageType.Description)) { c.Description = pca.CoverageType.Description; }
			}
			if (pol.ProductId != null) { c.ProductId = pol.ProductId; }
			if (assetId != null)       { c.InsurancePolicyAssetId = assetId; }
			if (pol.EffectiveDate != null) {
				// EffectiveDate de la cobertura puede ser Date o Datetime según el org.
				asignaFechaFlexible(c, 'EffectiveDate', pol.EffectiveDate.date(), pol.EffectiveDate);
			}
			// Evita duplicados dentro del mismo lote.
			yaPorTipo.add(pca.CoverageTypeId);
			yaPorNombre.add(nombre.toLowerCase());
			nuevas.add(c);
		}
		if (!nuevas.isEmpty()) { insert nuevas; }
		return nuevas.size();
	}

	/**
	 * @creation date: 17/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Crea la transacción de prima inicial (InsurancePolicyTransaction) de la póliza. Es idempotente:
	 * si ya tiene una transacción, devuelve la existente.
	 * @param policyId: Id de la InsurancePolicy
	 * @return Id de la transacción creada o existente
	 */
	@AuraEnabled
	public static Id crearTransaccionInicial(Id policyId) {
		if (policyId == null) {
			throw new AuraHandledException('No se recibió la póliza para crear la transacción.');
		}
		// Idempotente: si ya hay transacción, no crea otra.
		for (InsurancePolicyTransaction ex : [
			SELECT Id FROM InsurancePolicyTransaction
			WHERE InsurancePolicyId = :policyId ORDER BY CreatedDate ASC LIMIT 1
		]) { return ex.Id; }

		InsurancePolicy pol = [
			SELECT Id, Name, PremiumAmount, GrossWrittenPremium, TermPremiumAmount, EffectiveDate
			FROM InsurancePolicy WHERE Id = :policyId LIMIT 1
		];
		Decimal monto = pol.TermPremiumAmount != null ? pol.TermPremiumAmount
			: (pol.GrossWrittenPremium != null ? pol.GrossWrittenPremium : pol.PremiumAmount);

		InsurancePolicyTransaction t = new InsurancePolicyTransaction();
		t.InsurancePolicyId = policyId;
		if (monto != null) {
			// TransactionAmount es el importe base; TotalTransactionAmount lo calcula la plataforma.
			t.TransactionAmount = monto;
		}
		// Fecha en ambos tipos: el campo puede ser Date o Datetime según el org.
		Date fechaD = Date.today();
		Datetime fechaDT = Datetime.now();
		if (pol.EffectiveDate != null) { fechaDT = pol.EffectiveDate; fechaD = pol.EffectiveDate.date(); }
		asignaFechaFlexible(t, 'TransactionEffectiveDate', fechaD, fechaDT);
		asignaFechaFlexible(t, 'EffectiveFromDate', fechaD, fechaDT);

		// Picklists resueltos contra el catálogo real del org (evita valores inválidos).
		String tipo = pickPicklist(InsurancePolicyTransaction.Type.getDescribe(),
			new List<String>{ 'New Business', 'Issuance', 'Premium', 'New', 'Nueva', 'Emision', 'Emisión' });
		if (String.isNotBlank(tipo)) { t.Type = tipo; }
		String estatus = pickPicklist(InsurancePolicyTransaction.Status.getDescribe(),
			new List<String>{ 'Posted', 'Active', 'Completed', 'Approved', 'Draft', 'Pending' });
		if (String.isNotBlank(estatus)) { t.Status = estatus; }
		// Category y Name pueden ser autonumérico o restringidos: se asignan a prueba de fallos.
		try { t.put('Name', ('Prima inicial - ' + (pol.Name != null ? pol.Name : '')).left(80)); } catch (Exception ignore) {}

		insert t;
		return t.Id;
	}

	/**
	 * @creation date: 17/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Wrapper con los registros hijos de la póliza (coberturas, participantes, bienes y transacciones)
	 * para la vista de solo lectura del LWC policyCreator.
	 */
	public class RegistrosPoliza {
		@AuraEnabled public List<CoberturaRow> coberturas = new List<CoberturaRow>();
		@AuraEnabled public List<ParticipanteRow> participantes = new List<ParticipanteRow>();
		@AuraEnabled public List<BienRow> bienes = new List<BienRow>();
		@AuraEnabled public List<TransaccionRow> transacciones = new List<TransaccionRow>();
	}
	/**
	 * @creation date: 17/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Renglón de cobertura para la vista de la póliza: nombre, suma, deducible, prima y sus textos tal
	 * cual vienen en la póliza.
	 */
	public class CoberturaRow {
		@AuraEnabled public Id id;
		@AuraEnabled public String nombre;
		@AuraEnabled public Decimal suma;
		@AuraEnabled public Decimal deducible;
		@AuraEnabled public Decimal prima;
		// Texto tal cual aparece en la póliza (ej. "5 %", "AMPARADA", "50 UMAS").
		@AuraEnabled public String sumaTexto;
		@AuraEnabled public String deducibleTexto;
	}
	/**
	 * @creation date: 17/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Renglón de participante para la vista de la póliza: nombre, rol, parentesco y, en beneficiarios,
	 * porcentaje y tipo de beneficio.
	 */
	public class ParticipanteRow {
		@AuraEnabled public Id id;
		@AuraEnabled public String nombre;
		@AuraEnabled public String rol;
		@AuraEnabled public String relacion;
		// Beneficiarios: porcentaje asignado y tipo de beneficio (por muerte / supervivencia).
		@AuraEnabled public Decimal porcentaje;
		@AuraEnabled public String tipoBeneficio;
	}
	/**
	 * @creation date: 17/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Renglón de bien asegurado (InsurancePolicyAsset) para la vista de la póliza.
	 */
	public class BienRow {
		@AuraEnabled public Id id;
		@AuraEnabled public String nombre;
		@AuraEnabled public Boolean activo;
		@AuraEnabled public Decimal prima;
	}
	/**
	 * @creation date: 17/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Renglón de transacción de la póliza (InsurancePolicyTransaction) para la vista de la póliza.
	 */
	public class TransaccionRow {
		@AuraEnabled public Id id;
		@AuraEnabled public String nombre;
		@AuraEnabled public String tipo;
		@AuraEnabled public String estatus;
		@AuraEnabled public Decimal monto;
		@AuraEnabled public Datetime fecha;
	}

	/**
	 * @creation date: 17/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve los registros hijos de la póliza (coberturas, participantes, bien asegurado y
	 * transacciones) para mostrarlos en la vista de la póliza.
	 * @param policyId: Id de la InsurancePolicy
	 * @return Wrapper con las cuatro listas (vacías si no hay registros)
	 */
	@AuraEnabled(cacheable=false)
	public static RegistrosPoliza getRegistrosPoliza(Id policyId) {
		RegistrosPoliza out = new RegistrosPoliza();
		if (policyId == null) { return out; }
		try {
			for (InsurancePolicyCoverage c : [
				SELECT Id, CoverageName, LimitAmount, DeductibleAmount, PremiumAmount, Description
				FROM InsurancePolicyCoverage WHERE InsurancePolicyId = :policyId
				ORDER BY CoverageName
			]) {
				CoberturaRow r = new CoberturaRow();
				r.id = c.Id; r.nombre = c.CoverageName;
				r.suma = c.LimitAmount; r.deducible = c.DeductibleAmount; r.prima = c.PremiumAmount;
				r.sumaTexto = valorDeDescripcion(c.Description, 'Suma asegurada');
				r.deducibleTexto = valorDeDescripcion(c.Description, 'Deducible');
				out.coberturas.add(r);
			}
			for (InsurancePolicyParticipant p : [
				SELECT Id, ParticipantName, Role, RelationshipToInsured, BeneficiarySharePercentage, ParticipantCode
				FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :policyId
				ORDER BY ParticipantCode NULLS FIRST, ParticipantName
			]) {
				ParticipanteRow r = new ParticipanteRow();
				r.id = p.Id; r.nombre = p.ParticipantName;
				r.rol = p.Role; r.relacion = p.RelationshipToInsured;
				r.porcentaje = p.BeneficiarySharePercentage;
				r.tipoBeneficio = p.ParticipantCode == 'BEN-MUERTE' ? 'Por muerte'
					: (p.ParticipantCode == 'BEN-SUPERVIVENCIA' ? 'Por supervivencia' : null);
				out.participantes.add(r);
			}
			for (InsurancePolicyAsset a : [
				SELECT Id, AssetName, IsActive, StandardPremiumAmount
				FROM InsurancePolicyAsset WHERE InsurancePolicyId = :policyId
				ORDER BY AssetName
			]) {
				BienRow r = new BienRow();
				r.id = a.Id; r.nombre = a.AssetName;
				r.activo = a.IsActive; r.prima = a.StandardPremiumAmount;
				out.bienes.add(r);
			}
			for (InsurancePolicyTransaction t : [
				SELECT Id, Name, Type, Status, TransactionAmount, TransactionEffectiveDate
				FROM InsurancePolicyTransaction WHERE InsurancePolicyId = :policyId
				ORDER BY TransactionEffectiveDate DESC NULLS LAST
			]) {
				TransaccionRow r = new TransaccionRow();
				r.id = t.Id; r.nombre = t.Name; r.tipo = t.Type; r.estatus = t.Status;
				r.monto = t.TransactionAmount; r.fecha = t.TransactionEffectiveDate;
				out.transacciones.add(r);
			}
		} catch (Exception e) {
			// No romper la vista: si un objeto no está accesible, se devuelve lo que sí se pudo.
		}
		return out;
	}

	/**
	 * @creation date: 17/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Asigna una fecha al campo con el tipo correcto según el org (Date o Datetime).
	 * @param rec: Registro a modificar
	 * @param field: API name del campo
	 * @param d: Valor como fecha
	 * @param dt: Valor como fecha/hora
	 * @return void
	 */
	private static void asignaFechaFlexible(SObject rec, String field, Date d, Datetime dt) {
		try {
			Schema.SObjectField f = rec.getSObjectType().getDescribe().fields.getMap().get(field);
			if (f == null) { return; }
			if (f.getDescribe().getType() == Schema.DisplayType.DATETIME) {
				rec.put(field, dt);
			} else {
				rec.put(field, d);
			}
		} catch (Exception ignore) {}
	}

	/**
	 * @creation date: 17/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Devuelve el primer valor activo del picklist que coincida con alguno de los candidatos (sin
	 * importar mayúsculas).
	 * @param f: Describe del campo picklist
	 * @param candidatos: Valores aceptables en orden de preferencia
	 * @return Valor del picklist encontrado; null si ninguno existe
	 */
	private static String pickPicklist(Schema.DescribeFieldResult f, List<String> candidatos) {
		if (f == null) { return null; }
		Set<String> activos = new Set<String>();
		for (Schema.PicklistEntry pe : f.getPicklistValues()) {
			if (pe.isActive()) { activos.add(pe.getValue()); }
		}
		for (String cand : candidatos) {
			for (String a : activos) {
				if (a.equalsIgnoreCase(cand)) { return a; }
			}
		}
		return null;
	}

	/**
	 * @creation date: 17/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma un mensaje de error legible: el primer mensaje DML si la excepción es de DML, o el mensaje
	 * general.
	 * @param e: Excepción capturada
	 * @return Mensaje para mostrar al usuario
	 */
	private static String msgLimpio(Exception e) {
		if (e instanceof DmlException && ((DmlException) e).getNumDml() > 0) {
			return ((DmlException) e).getDmlMessage(0);
		}
		return e.getMessage();
	}

	/**
	 * @creation date: 18/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Guarda en la póliza los datos del PDF analizado: completa la cuenta, el vehículo, el bien, los
	 * participantes, los beneficiarios (y su grupo familiar), las coberturas con suma/deducible/prima, la
	 * transacción inicial, la fecha de renovación y el producer. Cada paso es independiente.
	 * @param policyId: Id de la InsurancePolicy
	 * @param opportunityId: Id de la oportunidad origen (opcional)
	 * @param datosJson: JSON con los datos extraídos del PDF por la IA
	 * @return Resumen con el resultado o el error de cada paso
	 */
	@AuraEnabled
	public static Map<String, Object> guardarDatosPolizaDesdePdf(Id policyId, Id opportunityId, String datosJson) {
		Map<String, Object> resumen = new Map<String, Object>();
		if (policyId == null) {
			throw new AuraHandledException('No se recibió la póliza para guardar sus datos.');
		}
		Map<String, Object> d = String.isBlank(datosJson)
			? new Map<String, Object>()
			: (Map<String, Object>) JSON.deserializeUntyped(datosJson);

		InsurancePolicy pol = [
			SELECT Id, NameInsuredId, SourceOpportunityId
			FROM InsurancePolicy WHERE Id = :policyId LIMIT 1
		];
		Id oppId = opportunityId != null ? opportunityId : pol.SourceOpportunityId;
		Id accountId = resolverCuentaDePoliza(pol);

		// 0) Completa los campos vacíos de la Cuenta (RFC, dirección, teléfono) con el PDF.
		try { completarCuentaDesdePdf(accountId, d); resumen.put('cuenta', 1); }
		catch (Exception e) { resumen.put('cuentaError', msgLimpio(e)); }

		// 1) Vehículo (CustomerProperty) con los datos reales del PDF.
		try { guardarVehiculoDesdePdf(accountId, d); resumen.put('vehiculo', 1); }
		catch (Exception e) { resumen.put('vehiculoError', msgLimpio(e)); }

		// 2) Bien de póliza (liga el CustomerProperty a la póliza).
		try { crearVinculoBien(policyId); resumen.put('bien', 1); }
		catch (Exception e) { resumen.put('bienError', msgLimpio(e)); }

		// 3) Participante = la PERSONA asegurada del PDF (ej. Rosa Margarita), como Contacto
		//    bajo la cuenta principal (ej. CASTEMON). Si el PDF no trae persona, se cae al
		//    participante de la cuenta.
		try {
			Integer n = crearParticipanteDesdePdf(policyId, accountId, d);
			// Solo si la póliza quedó SIN participantes se usa el respaldo (catálogo/OCR).
			// Si crearParticipanteDesdePdf no creó porque ya existía, NO se agrega otro.
			if (n == 0) {
				Integer yaHay = [SELECT COUNT() FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :policyId];
				if (yaHay == 0) { n = crearParticipantesPoliza(policyId, oppId); }
			}
			resumen.put('asegurados', n);
		} catch (Exception e) { resumen.put('aseguradosError', msgLimpio(e)); }

		// 3b) Beneficiarios (cualquier ramo que los traiga): designación de beneficiarios del PDF.
		try { resumen.put('beneficiarios', crearBeneficiariosDesdePdf(policyId, accountId, d)); }
		catch (Exception e) { resumen.put('beneficiariosError', msgLimpio(e)); }

		// 3c) Grupo familiar del titular: agrega a los beneficiarios como miembros y crea las
		//     relaciones de parentesco entre contactos (ambos sentidos).
		try { resumen.put('grupo', vincularBeneficiariosAGrupo(policyId)); }
		catch (Exception e) { resumen.put('grupoError', msgLimpio(e)); }

		// 4) Coberturas: primero desde el PDF (suma/deducible). Si el PDF no trae coberturas
		//    reales (p.ej. Vida, donde solo aparecen secciones como "TITULAR"), se usan las
		//    coberturas del CATÁLOGO del producto.
		try {
			Integer nc = crearCoberturasDesdePdf(policyId, d);
			if (nc == 0) { nc = crearCoberturasPoliza(policyId); }
			resumen.put('coberturas', nc);
		}
		catch (Exception e) { resumen.put('coberturasError', msgLimpio(e)); }

		// 5) Transacción de prima inicial.
		try { Id tx = crearTransaccionInicial(policyId); resumen.put('transaccion', tx != null ? 1 : 0); }
		catch (Exception e) { resumen.put('transaccionError', msgLimpio(e)); }

		// 6) Fecha de renovación (para avisos).
		try { resumen.put('renovacion', llenarFechaRenovacion(policyId) ? 1 : 0); }
		catch (Exception e) { resumen.put('renovacionError', msgLimpio(e)); }

		// 7) Producer (agente) -> InsurancePolicy.ProducerId.
		try { resumen.put('producer', vincularProducer(policyId, oppId) ? 1 : 0); }
		catch (Exception e) { resumen.put('producerError', msgLimpio(e)); }

		return resumen;
	}

	/**
	 * @creation date: 30/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Crea los beneficiarios de la póliza (cualquier ramo que los traiga) como participantes con rol
	 * Beneficiario, su porcentaje, su parentesco y el tipo de beneficio en ParticipantCode. "EL MISMO" se resuelve
	 * al titular y, si ya es participante, se le agrega el rol en el mismo registro. Es idempotente.
	 * @param policyId: Id de la InsurancePolicy
	 * @param accountId: Id de la cuenta del asegurado
	 * @param d: Datos del PDF con el arreglo "beneficiarios"
	 * @return Número de beneficiarios creados o actualizados
	 */
	@TestVisible
	private static Integer crearBeneficiariosDesdePdf(Id policyId, Id accountId, Map<String, Object> d) {
		Object bensO = d.get('beneficiarios');
		if (!(bensO instanceof List<Object>) || ((List<Object>) bensO).isEmpty()) { return 0; }
		InsurancePolicy pol = [
			SELECT Id, ProductId, NameInsuredId, SourceOpportunityId
			FROM InsurancePolicy WHERE Id = :policyId LIMIT 1
		];
		Id acc = accountId != null ? accountId : resolverCuentaDePoliza(pol);
		String titular = nombreTitular(d);
		String rolBen = pickPicklist(InsurancePolicyParticipant.Role.getDescribe(),
			new List<String>{ 'Beneficiary', 'Beneficiario', 'Primary Beneficiary', 'Beneficiario Principal' });
		Schema.DescribeFieldResult relDesc = InsurancePolicyParticipant.RelationshipToInsured.getDescribe();

		Set<String> ya = new Set<String>();
		// Participantes existentes por nombre (ej. el asegurado): si también es beneficiario se
		// actualiza ESE registro con ambos roles en lugar de crear otro.
		Map<String, InsurancePolicyParticipant> porNombre = new Map<String, InsurancePolicyParticipant>();
		for (InsurancePolicyParticipant p : [
			SELECT Id, ParticipantName, ParticipantCode, Role, RelationshipToInsured, BeneficiarySharePercentage
			FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :policyId
		]) {
			ya.add(llaveBeneficiario(p.ParticipantName, p.ParticipantCode));
			String kn = llaveBeneficiario(p.ParticipantName, null);
			if (!porNombre.containsKey(kn)) { porNombre.put(kn, p); }
		}

		List<InsurancePolicyParticipant> nuevos = new List<InsurancePolicyParticipant>();
		Map<Id, InsurancePolicyParticipant> actualizados = new Map<Id, InsurancePolicyParticipant>();
		for (Object o : (List<Object>) bensO) {
			if (!(o instanceof Map<String, Object>)) { continue; }
			Map<String, Object> b = (Map<String, Object>) o;
			String nombre = strOf(b.get('nombre'));
			String parentesco = strOf(b.get('parentesco'));
			// "EL MISMO" (en nombre o parentesco) = el titular de la póliza.
			if (esElMismo(nombre) || esElMismo(parentesco)) {
				if (String.isNotBlank(titular)) { nombre = titular; }
				parentesco = 'EL MISMO';
			}
			if (String.isBlank(nombre) || esElMismo(nombre)) { continue; }
			String codigo = codigoBeneficio(strOf(b.get('tipo')));
			String llave = llaveBeneficiario(nombre, codigo);
			if (ya.contains(llave)) { continue; }
			ya.add(llave);
			Decimal pct = parseMonto(strOf(b.get('porcentaje')));
			String rel = parentescoPicklist(relDesc, parentesco);

			// Ya es participante (ej. el asegurado) y aún no tiene un beneficio asignado:
			// se le agrega el rol Beneficiario (Role es selección múltiple) en el MISMO registro.
			InsurancePolicyParticipant ex = porNombre.get(llaveBeneficiario(nombre, null));
			if (ex != null && String.isBlank(ex.ParticipantCode)) {
				ex.Role = agregarRol(ex.Role, rolBen);
				ex.ParticipantCode = codigo;
				if (pct != null) { ex.BeneficiarySharePercentage = pct; }
				if (String.isNotBlank(rel) && String.isBlank(ex.RelationshipToInsured)) { ex.RelationshipToInsured = rel; }
				actualizados.put(ex.Id, ex);
				continue;
			}

			InsurancePolicyParticipant p = new InsurancePolicyParticipant();
			p.InsurancePolicyId = policyId;
			p.ParticipantName = nombre.normalizeSpace().left(255);
			p.ParticipantCode = codigo;
			if (String.isNotBlank(rolBen)) { p.Role = rolBen; }
			if (pct != null) { p.BeneficiarySharePercentage = pct; }
			if (String.isNotBlank(rel)) { p.RelationshipToInsured = rel; }
			if (acc != null) { p.PrimaryParticipantAccountId = acc; }
			if (pol.ProductId != null) { p.ProductId = pol.ProductId; }
			try { p.IsActiveParticipant = true; } catch (Exception ignore) {}
			try { p.EffectiveDate = Date.today(); } catch (Exception ignore) {}
			nuevos.add(p);
		}
		if (!nuevos.isEmpty()) { insert nuevos; }
		if (!actualizados.isEmpty()) { update actualizados.values(); }
		return nuevos.size() + actualizados.size();
	}

	/**
	 * @creation date: 30/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Agrega un rol a la selección múltiple Role sin repetirlo ("Asegurado" →
	 * "Asegurado;Beneficiario").
	 * @param actuales: Roles actuales separados por ";"
	 * @param rol: Rol a agregar
	 * @return Roles resultantes
	 */
	@TestVisible
	private static String agregarRol(String actuales, String rol) {
		if (String.isBlank(rol)) { return actuales; }
		List<String> roles = String.isBlank(actuales) ? new List<String>() : actuales.split(';');
		for (String r : roles) { if (r.trim().equalsIgnoreCase(rol)) { return actuales; } }
		roles.add(rol);
		return String.join(roles, ';');
	}

	/**
	 * @creation date: 30/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Obtiene el valor del picklist RelationshipToInsured para el parentesco impreso: primero el valor
	 * tal cual (sin mayúsculas ni acentos) y después sus sinónimos.
	 * @param f: Describe del campo RelationshipToInsured
	 * @param parentesco: Parentesco tal como viene en el PDF
	 * @return Valor del picklist; null si no hay equivalente
	 */
	@TestVisible
	private static String parentescoPicklist(Schema.DescribeFieldResult f, String parentesco) {
		if (f == null || String.isBlank(parentesco)) { return null; }
		Map<String, String> activos = new Map<String, String>();
		for (Schema.PicklistEntry pe : f.getPicklistValues()) {
			if (pe.isActive()) { activos.put(normKey(pe.getValue()).normalizeSpace(), pe.getValue()); }
		}
		for (String cand : candidatosParentesco(parentesco)) {
			String k = normKey(cand).normalizeSpace();
			if (activos.containsKey(k)) { return activos.get(k); }
		}
		return null;
	}

	/**
	 * @creation date: 30/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Obtiene el nombre del titular o asegurado principal del PDF (para resolver "EL MISMO").
	 * @param d: Datos del PDF
	 * @return Nombre del titular; null si no viene
	 */
	private static String nombreTitular(Map<String, Object> d) {
		List<String> candidatos = new List<String>{ strOf(d.get('titular')) };
		if (d.get('asegurado') instanceof Map<String, Object>) {
			candidatos.add(strOf(((Map<String, Object>) d.get('asegurado')).get('nombre')));
		}
		candidatos.add(strOf(d.get('aseguradoNombre')));
		if (d.get('contratante') instanceof Map<String, Object>) {
			candidatos.add(strOf(((Map<String, Object>) d.get('contratante')).get('nombre')));
		}
		for (String c : candidatos) { if (String.isNotBlank(c)) { return c; } }
		return null;
	}

	/**
	 * @creation date: 30/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Indica si el texto se refiere al propio titular ("EL MISMO", "TITULAR", "EL ASEGURADO"…).
	 * @param v: Texto del nombre o parentesco
	 * @return true si se refiere al titular
	 */
	@TestVisible
	private static Boolean esElMismo(String v) {
		if (String.isBlank(v)) { return false; }
		Set<String> mismo = new Set<String>{ 'el mismo', 'la misma', 'mismo', 'misma', 'titular', 'el titular', 'el asegurado', 'la asegurada' };
		return mismo.contains(normKey(v).normalizeSpace());
	}

	/**
	 * @creation date: 30/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Convierte el tipo de beneficio en código: BEN-MUERTE, BEN-SUPERVIVENCIA o BEN.
	 * @param tipo: Tipo de beneficio impreso
	 * @return Código del beneficio
	 */
	@TestVisible
	private static String codigoBeneficio(String tipo) {
		String t = normKey(tipo == null ? '' : tipo);
		if (t.contains('superviv')) { return 'BEN-SUPERVIVENCIA'; }
		if (t.contains('muerte') || t.contains('fallec') || t.contains('deceso')) { return 'BEN-MUERTE'; }
		return 'BEN';
	}

	/**
	 * @creation date: 30/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma la llave de un beneficiario (nombre normalizado + código de beneficio) para no duplicarlo.
	 * @param nombre: Nombre del beneficiario
	 * @param codigo: Código del beneficio (puede ser null)
	 * @return Llave de comparación
	 */
	private static String llaveBeneficiario(String nombre, String codigo) {
		return normKey(nombre == null ? '' : nombre).normalizeSpace() + '|' + (codigo == null ? '' : codigo);
	}

	/**
	 * @creation date: 30/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Lista los valores candidatos del picklist RelationshipToInsured para el parentesco impreso: el
	 * valor literal, sus sinónimos en español y equivalentes en inglés.
	 * @param parentesco: Parentesco tal como viene en el PDF
	 * @return Candidatos en orden de preferencia
	 */
	@TestVisible
	private static List<String> candidatosParentesco(String parentesco) {
		String p = normKey(parentesco == null ? '' : parentesco).normalizeSpace();
		// 1) El parentesco tal cual viene impreso (ej. HERMANO, TIA, SOBRINA, CUÑADO).
		List<String> c = new List<String>{ p };
		// 2) Sinónimos hacia los valores del picklist (en español y con género) y, como respaldo,
		//    los equivalentes en inglés de otras configuraciones.
		if (p.contains('mismo') || p.contains('titular')) { c.addAll(new List<String>{ 'El mismo', 'Self', 'Insured' }); }
		else if (p.contains('mama') || p == 'madre') { c.addAll(new List<String>{ 'Madre', 'Mother', 'Parent' }); }
		else if (p.contains('papa') || p == 'padre') { c.addAll(new List<String>{ 'Padre', 'Father', 'Parent' }); }
		else if (p.contains('esposo') || p.contains('marido') || p.contains('concubino')) { c.addAll(new List<String>{ 'Marido', 'Esposo', 'Husband', 'Spouse' }); }
		else if (p.contains('esposa') || p.contains('concubina')) { c.addAll(new List<String>{ 'Mujer', 'Esposa', 'Wife', 'Spouse' }); }
		else if (p.contains('conyug') || p.contains('pareja')) { c.addAll(new List<String>{ 'Cónyuge', 'Spouse', 'Partner' }); }
		else if (p.contains('hija')) { c.addAll(new List<String>{ 'Hija', 'Daughter', 'Child' }); }
		else if (p.contains('hijo')) { c.addAll(new List<String>{ 'Hijo', 'Son', 'Child' }); }
		else if (p.contains('hermana')) { c.addAll(new List<String>{ 'Hermana', 'Sister', 'Sibling' }); }
		else if (p.contains('hermano')) { c.addAll(new List<String>{ 'Hermano', 'Brother', 'Sibling' }); }
		else if (p.contains('abuela')) { c.addAll(new List<String>{ 'Abuela', 'Grandmother', 'Grandparent' }); }
		else if (p.contains('abuelo')) { c.addAll(new List<String>{ 'Abuelo', 'Grandfather', 'Grandparent' }); }
		else if (p.contains('nieta')) { c.addAll(new List<String>{ 'Nieta', 'Granddaughter', 'Grandchild' }); }
		else if (p.contains('nieto')) { c.addAll(new List<String>{ 'Nieto', 'Grandson', 'Grandchild' }); }
		c.addAll(new List<String>{ 'Otro', 'Other', 'Ninguno', 'None' });
		return c;
	}

	/**
	 * @creation date: 01/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Agrega a los beneficiarios de la póliza al grupo familiar del titular: crea o reutiliza el grupo
	 * (cuenta + PartyRelationshipGroup), crea los contactos de los beneficiarios, sus membresías con función y las
	 * relaciones de parentesco en ambos sentidos. Es idempotente.
	 * @param policyId: Id de la InsurancePolicy
	 * @return Número de beneficiarios vinculados al grupo
	 */
	@AuraEnabled
	public static Integer vincularBeneficiariosAGrupo(Id policyId) {
		if (policyId == null) { return 0; }
		InsurancePolicy pol = [
			SELECT Id, NameInsuredId, NameInsured.IsPersonAccount, NameInsured.PersonContactId
			FROM InsurancePolicy WHERE Id = :policyId LIMIT 1
		];
		List<InsurancePolicyParticipant> parts = [
			SELECT Id, ParticipantName, Role, RelationshipToInsured, ParticipantCode, PrimaryParticipantContactId
			FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :policyId
		];

		// Titular: el participante asegurado con contacto; si no, la persona de la cuenta asegurada.
		Id titularId = null;
		String titularNombre = null;
		for (InsurancePolicyParticipant p : parts) {
			if (p.PrimaryParticipantContactId != null && String.isNotBlank(p.Role) && p.Role.contains('Asegurado')) {
				titularId = p.PrimaryParticipantContactId; titularNombre = p.ParticipantName; break;
			}
		}
		if (titularId == null && pol.NameInsured != null && pol.NameInsured.IsPersonAccount) {
			titularId = pol.NameInsured.PersonContactId;
		}
		if (titularId == null) { return 0; }
		Contact titular = [SELECT Id, Name, Sexo__c FROM Contact WHERE Id = :titularId LIMIT 1];
		String claveTitular = normKey(titular.Name).normalizeSpace();
		String claveTitularPart = normKey(titularNombre == null ? '' : titularNombre).normalizeSpace();

		// Beneficiarios distintos del titular (un mismo nombre puede tener varios beneficios).
		Map<String, List<InsurancePolicyParticipant>> bens = new Map<String, List<InsurancePolicyParticipant>>();
		for (InsurancePolicyParticipant p : parts) {
			if (String.isBlank(p.ParticipantCode) || !p.ParticipantCode.startsWith('BEN')) { continue; }
			String k = normKey(p.ParticipantName == null ? '' : p.ParticipantName).normalizeSpace();
			if (String.isBlank(k) || k == claveTitular || k == claveTitularPart || p.PrimaryParticipantContactId == titularId) { continue; }
			if (!bens.containsKey(k)) { bens.put(k, new List<InsurancePolicyParticipant>()); }
			bens.get(k).add(p);
		}
		if (bens.isEmpty()) { return 0; }

		PartyRelationshipGroup grupo = grupoFamiliar(titular);

		// Miembros actuales del grupo (por contacto y por nombre).
		Map<Id, AccountContactRelation> acrPorContacto = new Map<Id, AccountContactRelation>();
		Map<String, Id> contactoPorNombre = new Map<String, Id>();
		for (AccountContactRelation a : [
			SELECT Id, ContactId, Contact.Name, Roles FROM AccountContactRelation WHERE AccountId = :grupo.AccountId
		]) {
			acrPorContacto.put(a.ContactId, a);
			contactoPorNombre.put(normKey(a.Contact.Name).normalizeSpace(), a.ContactId);
		}

		// El titular es miembro con función Titular.
		if (!acrPorContacto.containsKey(titular.Id)) {
			AccountContactRelation a = new AccountContactRelation(AccountId = grupo.AccountId, ContactId = titular.Id,
				Roles = 'Titular', IsActive = true);
			insert a;
			acrPorContacto.put(titular.Id, a);
		}

		// Contactos de los beneficiarios: el ya ligado al participante, uno del grupo con el mismo
		// nombre o uno nuevo bajo la cuenta del grupo.
		Map<String, Id> contactoDe = new Map<String, Id>();
		Map<String, Contact> nuevos = new Map<String, Contact>();
		for (String k : bens.keySet()) {
			Id cid = null;
			for (InsurancePolicyParticipant p : bens.get(k)) { if (p.PrimaryParticipantContactId != null) { cid = p.PrimaryParticipantContactId; } }
			if (cid == null) { cid = contactoPorNombre.get(k); }
			if (cid != null) { contactoDe.put(k, cid); continue; }
			Contact c = contactoDesdeNombre(bens.get(k)[0].ParticipantName, grupo.AccountId);
			String sexo = sexoDeRol(bens.get(k)[0].RelationshipToInsured);
			if (sexo != null) { c.Sexo__c = sexo; }
			nuevos.put(k, c);
		}
		if (!nuevos.isEmpty()) {
			insert nuevos.values();
			for (String k : nuevos.keySet()) { contactoDe.put(k, nuevos.get(k).Id); }
		}

		// Membresía con su función en el grupo (la relación directa se crea con el contacto).
		Map<Id, AccountContactRelation> acrs = new Map<Id, AccountContactRelation>();
		for (AccountContactRelation a : [
			SELECT Id, ContactId, Roles FROM AccountContactRelation
			WHERE AccountId = :grupo.AccountId AND ContactId IN :contactoDe.values()
		]) { acrs.put(a.ContactId, a); }
		List<AccountContactRelation> acrNuevas = new List<AccountContactRelation>();
		List<AccountContactRelation> acrCambios = new List<AccountContactRelation>();
		Boolean extendida = false;
		for (String k : contactoDe.keySet()) {
			String parentesco = bens.get(k)[0].RelationshipToInsured;
			String funcion = funcionEnGrupo(parentesco);
			if (funcion == 'Otro familiar') { extendida = true; }
			AccountContactRelation a = acrs.get(contactoDe.get(k));
			if (a == null) {
				acrNuevas.add(new AccountContactRelation(AccountId = grupo.AccountId, ContactId = contactoDe.get(k),
					Roles = funcion, IsActive = true));
			} else if (String.isBlank(a.Roles)) {
				a.Roles = funcion;
				acrCambios.add(a);
			}
		}
		if (!acrNuevas.isEmpty()) { insert acrNuevas; }
		if (!acrCambios.isEmpty()) { update acrCambios; }

		// Participantes de la póliza ligados a su contacto.
		List<InsurancePolicyParticipant> partCambios = new List<InsurancePolicyParticipant>();
		for (String k : contactoDe.keySet()) {
			for (InsurancePolicyParticipant p : bens.get(k)) {
				if (p.PrimaryParticipantContactId == null) {
					p.PrimaryParticipantContactId = contactoDe.get(k);
					partCambios.add(p);
				}
			}
		}
		if (!partCambios.isEmpty()) { update partCambios; }

		// Relaciones de parentesco titular ↔ beneficiario.
		crearParentescos(titular, contactoDe, bens);

		// Tamaño y subtipo del grupo.
		grupo.GroupSize = [SELECT COUNT() FROM AccountContactRelation WHERE AccountId = :grupo.AccountId AND IsActive = true];
		if (extendida && grupo.Subtype == 'Núcleo familiar') { grupo.Subtype = 'Familia extendida'; }
		update grupo;
		return contactoDe.size();
	}

	/**
	 * @creation date: 01/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Obtiene el grupo familiar del titular: el que ya tenga por su membresía o uno nuevo ("Familia
	 * <titular>") con su cuenta de negocio.
	 * @param titular: Contacto del titular
	 * @return Grupo familiar (PartyRelationshipGroup)
	 */
	private static PartyRelationshipGroup grupoFamiliar(Contact titular) {
		Set<Id> cuentas = new Set<Id>();
		for (AccountContactRelation a : [SELECT AccountId FROM AccountContactRelation WHERE ContactId = :titular.Id]) {
			cuentas.add(a.AccountId);
		}
		for (PartyRelationshipGroup g : [
			SELECT Id, AccountId, Subtype, GroupSize FROM PartyRelationshipGroup
			WHERE AccountId IN :cuentas AND Category = 'Familia' ORDER BY CreatedDate LIMIT 1
		]) { return g; }

		String nombre = ('Familia ' + titular.Name.normalizeSpace()).left(80);
		Account cuenta = new Account(Name = nombre);
		Schema.RecordTypeInfo rt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Business_Account');
		if (rt != null) { cuenta.RecordTypeId = rt.getRecordTypeId(); }
		insert cuenta;
		PartyRelationshipGroup g = new PartyRelationshipGroup(Name = nombre, AccountId = cuenta.Id,
			Type = 'Household', Category = 'Familia', Subtype = 'Núcleo familiar', Status = 'Active', StartDate = Date.today());
		insert g;
		return g;
	}

	/**
	 * @creation date: 01/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma un contacto nuevo con el nombre impreso: los dos últimos tokens son los apellidos.
	 * @param nombre: Nombre completo impreso
	 * @param accountId: Cuenta a la que pertenece el contacto
	 * @return Contacto sin insertar
	 */
	private static Contact contactoDesdeNombre(String nombre, Id accountId) {
		Contact c = new Contact(AccountId = accountId);
		List<String> t = nombre.normalizeSpace().split(' ');
		if (t.size() >= 3) {
			c.LastName = (t[t.size() - 2] + ' ' + t[t.size() - 1]).left(80);
			List<String> fn = new List<String>();
			for (Integer i = 0; i < t.size() - 2; i++) { fn.add(t[i]); }
			c.FirstName = String.join(fn, ' ').left(40);
		} else if (t.size() == 2) {
			c.FirstName = t[0].left(40); c.LastName = t[1].left(80);
		} else {
			c.LastName = nombre.normalizeSpace().left(80);
		}
		return c;
	}

	/**
	 * @creation date: 01/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Obtiene la función del miembro en el grupo según su parentesco con el titular (Cónyuge, Hijo(a),
	 * Padre / Madre u Otro familiar).
	 * @param parentesco: Parentesco con el titular
	 * @return Función para AccountContactRelation.Roles
	 */
	@TestVisible
	private static String funcionEnGrupo(String parentesco) {
		String p = normKey(parentesco == null ? '' : parentesco).normalizeSpace();
		if (p == 'marido' || p == 'mujer' || p.contains('conyug') || p.contains('espos')) { return 'Cónyuge'; }
		if (p == 'hijo' || p == 'hija') { return 'Hijo(a)'; }
		if (p == 'padre' || p == 'madre') { return 'Padre / Madre'; }
		return 'Otro familiar';
	}

	private static final Set<String> ROLES_FEMENINOS = new Set<String>{
		'hermana', 'hija', 'madre', 'mujer', 'abuela', 'nieta', 'tia', 'sobrina', 'suegra', 'nuera',
		'cunada', 'prima', 'esposa', 'media hermana', 'hermanastra', 'hijastra', 'madrastra', 'ex mujer'
	};

	/**
	 * @creation date: 01/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Obtiene el sexo que implica el parentesco impreso (Hermano → Masculino, Madre → Femenino).
	 * @param rol: Parentesco
	 * @return Femenino, Masculino o null
	 */
	@TestVisible
	private static String sexoDeRol(String rol) {
		if (String.isBlank(rol)) { return null; }
		String r = normKey(rol).normalizeSpace();
		if (r.contains('comun')) { return null; }
		return ROLES_FEMENINOS.contains(r) ? 'Femenino' : 'Masculino';
	}

	/**
	 * @creation date: 01/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Crea las relaciones de parentesco (ContactContactRelation) titular ↔ beneficiario en ambos
	 * sentidos con la definición recíproca correcta. Si ya existen y cambió la definición (p. ej. se capturó el sexo
	 * del titular), las corrige.
	 * @param titular: Contacto del titular (con Sexo__c)
	 * @param contactoDe: Contacto de cada beneficiario por su llave
	 * @param bens: Participantes beneficiarios por llave
	 * @return void
	 */
	private static void crearParentescos(Contact titular, Map<String, Id> contactoDe,
			Map<String, List<InsurancePolicyParticipant>> bens) {
		Map<String, List<PartyRoleRelation>> porRol = new Map<String, List<PartyRoleRelation>>();
		for (PartyRoleRelation r : [
			SELECT Id, RoleName, RelatedRoleName, RelatedInverseRecordId FROM PartyRoleRelation
			WHERE RelationshipObjectName = 'Contact_Contact_Relationship'
		]) {
			String k = normKey(r.RoleName).normalizeSpace();
			if (!porRol.containsKey(k)) { porRol.put(k, new List<PartyRoleRelation>()); }
			porRol.get(k).add(r);
		}
		Map<String, ContactContactRelation> existentes = new Map<String, ContactContactRelation>();
		for (ContactContactRelation c : [
			SELECT Id, ContactId, RelatedContactId, PartyRoleRelationId FROM ContactContactRelation
			WHERE ContactId = :titular.Id OR RelatedContactId = :titular.Id
		]) {
			existentes.put(c.ContactId + '|' + c.RelatedContactId, c);
		}

		List<ContactContactRelation> directas = new List<ContactContactRelation>();
		List<ContactContactRelation> inversas = new List<ContactContactRelation>();
		List<ContactContactRelation> corregidas = new List<ContactContactRelation>();
		for (String k : contactoDe.keySet()) {
			Id ben = contactoDe.get(k);
			PartyRoleRelation def = definicionParentesco(porRol, bens.get(k)[0].RelationshipToInsured, titular.Sexo__c);
			ContactContactRelation exDir = existentes.get(ben + '|' + titular.Id);
			ContactContactRelation exInv = existentes.get(titular.Id + '|' + ben);
			if (exDir != null || exInv != null) {
				// Ya existe: solo se corrige la definición si cambió (p.ej. se capturó el sexo del titular).
				if (def != null && exDir != null && exDir.PartyRoleRelationId != def.Id) {
					exDir.PartyRoleRelationId = def.Id;
					corregidas.add(exDir);
					if (exInv != null) {
						exInv.PartyRoleRelationId = def.RelatedInverseRecordId != null ? def.RelatedInverseRecordId : def.Id;
						corregidas.add(exInv);
					}
				}
				continue;
			}
			if (def == null) { continue; }
			// RoleName = función del contacto (beneficiario); RelatedRoleName = la del relacionado (titular).
			directas.add(new ContactContactRelation(ContactId = ben, RelatedContactId = titular.Id,
				PartyRoleRelationId = def.Id, IsActive = true, StartDate = Date.today()));
			inversas.add(new ContactContactRelation(ContactId = titular.Id, RelatedContactId = ben,
				PartyRoleRelationId = def.RelatedInverseRecordId != null ? def.RelatedInverseRecordId : def.Id,
				IsActive = true, StartDate = Date.today()));
		}
		if (!corregidas.isEmpty()) { update corregidas; }
		if (directas.isEmpty()) { return; }
		insert directas;
		insert inversas;
		for (Integer i = 0; i < directas.size(); i++) {
			directas[i].RelatedInverseRecordId = inversas[i].Id;
			inversas[i].RelatedInverseRecordId = directas[i].Id;
		}
		try {
			List<ContactContactRelation> todas = new List<ContactContactRelation>(directas);
			todas.addAll(inversas);
			update todas;
		} catch (Exception ignore) {}
	}

	/**
	 * @creation date: 01/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Elige la definición recíproca (PartyRoleRelation) para un parentesco: el rol del beneficiario es
	 * el parentesco y el del titular se elige por su sexo. Sin sexo usa la simétrica o la masculina.
	 * @param porRol: Definiciones agrupadas por rol normalizado
	 * @param parentesco: Parentesco del beneficiario
	 * @param sexoTitular: Sexo del titular
	 * @return Definición elegida; null si no existe
	 */
	@TestVisible
	private static PartyRoleRelation definicionParentesco(Map<String, List<PartyRoleRelation>> porRol,
			String parentesco, String sexoTitular) {
		if (String.isBlank(parentesco)) { return null; }
		List<PartyRoleRelation> opciones = porRol.get(normKey(parentesco).normalizeSpace());
		if (opciones == null || opciones.isEmpty()) { return null; }
		String sexo = normKey(sexoTitular == null ? '' : sexoTitular);
		PartyRoleRelation simetrica = null, masculina = null;
		for (PartyRoleRelation r : opciones) {
			Boolean fem = ROLES_FEMENINOS.contains(normKey(r.RelatedRoleName).normalizeSpace());
			if (sexo.startsWith('fem') && fem) { return r; }
			if (sexo.startsWith('masc') && !fem) { return r; }
			if (r.RelatedRoleName == r.RoleName && simetrica == null) { simetrica = r; }
			if (!fem && masculina == null) { masculina = r; }
		}
		if (simetrica != null) { return simetrica; }
		return masculina != null ? masculina : opciones[0];
	}

	/**
	 * @creation date: 18/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Crea el participante asegurado (persona) del PDF como contacto bajo la cuenta principal y como
	 * InsurancePolicyParticipant. No lo duplica si ya existe.
	 * @param policyId: Id de la InsurancePolicy
	 * @param accountId: Id de la cuenta principal
	 * @param d: Datos del PDF
	 * @return Número de participantes creados (0 o 1)
	 */
	private static Integer crearParticipanteDesdePdf(Id policyId, Id accountId, Map<String, Object> d) {
		if (accountId == null) { return 0; }
		Map<String, Object> per = (d.get('contratante') instanceof Map<String, Object>)
			? (Map<String, Object>) d.get('contratante') : null;
		Map<String, Object> aseg = (d.get('asegurado') instanceof Map<String, Object>)
			? (Map<String, Object>) d.get('asegurado') : null;
		String empresa = strOf(d.get('aseguradoNombre'));

		// GENÉRICO: la persona asegurada puede venir en distintos campos según la póliza.
		// Se toma el PRIMER candidato que sea una PERSONA real (distinta de la razón
		// social de la cuenta): conductor habitual → contratante → asegurado.
		// Si ninguno es persona (póliza a nombre de la propia cuenta), no se crea contacto
		// y se deja el participante de la cuenta.
		List<String> candidatos = new List<String>{
			strOf(d.get('conductorHabitual')),
			(per != null) ? strOf(per.get('nombre')) : null,
			(aseg != null) ? strOf(aseg.get('nombre')) : null
		};
		String nombre = null;
		for (String cand : candidatos) {
			if (String.isNotBlank(cand) && (String.isBlank(empresa) || !cand.equalsIgnoreCase(empresa))) {
				nombre = cand; break;
			}
		}
		if (String.isBlank(nombre)) { return 0; }

		// RFC/correo/teléfono: solo si pertenecen a ESTA persona (el contratante ES la persona).
		Boolean datosDeLaPersona = (per != null && nombre.equalsIgnoreCase(strOf(per.get('nombre'))));
		String rfc = datosDeLaPersona ? strOf(per.get('rfc')) : null;
		String email = datosDeLaPersona ? strOf(per.get('email')) : null;
		String tel = datosDeLaPersona ? strOf(per.get('telefono')) : null;

		// Busca el contacto bajo la cuenta comparando el nombre de forma TOLERANTE
		// (ignora acentos, mayúsculas y espacios). El Name compuesto del contacto casi
		// nunca coincide letra por letra con el texto del PDF; sin esto se creaba un
		// contacto nuevo (y un participante nuevo) en cada guardado.
		Id contactId = null;
		String claveBusca = normKey(nombre).replaceAll('\\s+', ' ');
		for (Contact c : [
			SELECT Id, Name FROM Contact WHERE AccountId = :accountId LIMIT 200
		]) {
			if (normKey(c.Name).replaceAll('\\s+', ' ') == claveBusca) { contactId = c.Id; break; }
		}
		if (contactId == null) {
			Contact c = new Contact(AccountId = accountId);
			List<String> t = nombre.trim().split('\\s+');
			if (t.size() >= 3) {
				c.LastName = (t[t.size() - 2] + ' ' + t[t.size() - 1]).left(80);
				List<String> fn = new List<String>();
				for (Integer i = 0; i < t.size() - 2; i++) { fn.add(t[i]); }
				c.FirstName = String.join(fn, ' ').left(40);
			} else if (t.size() == 2) {
				c.FirstName = t[0].left(40); c.LastName = t[1].left(80);
			} else {
				c.LastName = nombre.left(80);
			}
			// Correo y teléfono solo si tienen formato válido (evita reglas de validación).
			if (String.isNotBlank(email) && email.contains('@') && email.contains('.')) { c.Email = email; }
			if (String.isNotBlank(tel)) {
				String dig = tel.replaceAll('[^0-9]', '');
				if (dig.length() == 10 || (dig.length() == 12 && dig.startsWith('52'))) { c.Phone = tel; }
			}
			if (String.isNotBlank(rfc))   { try { c.put('RFC__c', rfc.toUpperCase()); } catch (Exception ignore) {} }
			insert c;
			contactId = c.Id;
		}

		// Evita duplicar el participante: por contacto o por el mismo nombre.
		if (polizaTieneParticipante(policyId, contactId, nombre)) { return 0; }

		InsurancePolicyParticipant part = new InsurancePolicyParticipant();
		part.InsurancePolicyId = policyId;
		part.PrimaryParticipantContactId = contactId;
		part.ParticipantName = nombre.left(255);
		String rol = pickPicklist(InsurancePolicyParticipant.Role.getDescribe(),
			new List<String>{ 'Insured', 'Covered Party', 'Named Insured', 'Asegurado', 'Insured Party', 'Covered' });
		if (String.isNotBlank(rol)) { part.Role = rol; }
		try { part.EffectiveDate = Date.today(); } catch (Exception ignore) {}
		// Completa Cuenta, Producto y detalle de prima desde la póliza.
		aplicarDatosParticipante(part, policyId, accountId);
		insert part;
		return 1;
	}

	/**
	 * @creation date: 29/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Indica si la póliza ya tiene un participante para ese contacto o con el mismo nombre (evita
	 * insertarlo dos veces).
	 * @param policyId: Id de la InsurancePolicy
	 * @param contactId: Id del contacto
	 * @param nombre: Nombre del participante
	 * @return true si ya existe
	 */
	private static Boolean polizaTieneParticipante(Id policyId, Id contactId, String nombre) {
		String nom = normKey(nombre == null ? '' : nombre).replaceAll('\\s+', ' ');
		for (InsurancePolicyParticipant p : [
			SELECT PrimaryParticipantContactId, ParticipantName
			FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :policyId
		]) {
			if (contactId != null && p.PrimaryParticipantContactId == contactId) { return true; }
			if (String.isNotBlank(nom)
				&& normKey(p.ParticipantName == null ? '' : p.ParticipantName).replaceAll('\\s+', ' ') == nom) {
				return true;
			}
		}
		return false;
	}

	/**
	 * @creation date: 24/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Completa en el participante los datos de la póliza: cuenta del asegurado, producto y detalle de
	 * prima. Cada campo se asigna con tolerancia por si el org lo tiene de solo lectura.
	 * @param part: Participante a completar
	 * @param policyId: Id de la InsurancePolicy
	 * @param accountId: Id de la cuenta del asegurado
	 * @return void
	 */
	private static void aplicarDatosParticipante(InsurancePolicyParticipant part, Id policyId, Id accountId) {
		InsurancePolicy pol = null;
		for (InsurancePolicy p : [
			SELECT ProductId, PremiumAmount, NameInsuredId, SourceOpportunityId
			FROM InsurancePolicy WHERE Id = :policyId LIMIT 1
		]) { pol = p; }
		if (pol == null) { return; }
		// Participante activo.
		try { part.IsActiveParticipant = true; } catch (Exception ignore) {}
		// Cuenta del asegurado: la recibida o, si no llega, la de la póliza.
		Id acc = accountId != null ? accountId : resolverCuentaDePoliza(pol);
		if (acc != null && part.PrimaryParticipantAccountId == null) {
			try { part.PrimaryParticipantAccountId = acc; } catch (Exception ignore) {}
		}
		// Producto de la póliza.
		if (pol.ProductId != null) { try { part.ProductId = pol.ProductId; } catch (Exception ignore) {} }
		// Detalle de prima: se copia la prima de la póliza (evita que quede en 0).
		if (pol.PremiumAmount != null) {
			for (String campo : new List<String>{
				'StandardPremiumAmount', 'TermPremiumAmount', 'TotalStandardAmount', 'TotalTermAmount'
			}) {
				try { part.put(campo, pol.PremiumAmount); } catch (Exception ignore) {}
			}
		}
	}

	/**
	 * @creation date: 20/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Completa los campos vacíos de la cuenta (RFC, dirección, teléfono) con los datos del PDF. No
	 * sobrescribe lo ya capturado.
	 * @param accountId: Id de la cuenta
	 * @param d: Datos del PDF
	 * @return void
	 */
	private static void completarCuentaDesdePdf(Id accountId, Map<String, Object> d) {
		if (accountId == null) { return; }
		Object cObj = d.get('contratante');
		if (!(cObj instanceof Map<String, Object>)) { return; }
		Map<String, Object> c = (Map<String, Object>) cObj;
		String rfc = strOf(c.get('rfc'));
		if (String.isBlank(rfc)) { rfc = strOf(d.get('rfc')); }
		String tel = strOf(c.get('telefono'));
		Map<String, Object> dir = (c.get('direccion') instanceof Map<String, Object>)
			? (Map<String, Object>) c.get('direccion') : new Map<String, Object>();
		String calle = strOf(dir.get('calle'));
		String colonia = strOf(dir.get('colonia'));
		String cp = strOf(dir.get('cp'));
		String municipio = strOf(dir.get('municipio'));
		String estado = strOf(dir.get('estado'));
		String calleFull = String.isNotBlank(colonia)
			? ((String.isNotBlank(calle) ? calle + ', ' : '') + colonia) : calle;

		Account acc = [
			SELECT Id, IsPersonAccount, Phone,
				   BillingStreet, BillingCity, BillingState, BillingPostalCode,
				   PersonMailingStreet, PersonMailingCity, PersonMailingState, PersonMailingPostalCode,
				   PersonEmail, RFC__pc
			FROM Account WHERE Id = :accountId LIMIT 1
		];
		Account upd = new Account(Id = accountId);
		Boolean cambio = false;

		// Teléfono: solo si está vacío y tiene formato válido.
		if (String.isBlank(acc.Phone) && String.isNotBlank(tel)) {
			String dig = tel.replaceAll('[^0-9]', '');
			if (dig.length() == 10 || (dig.length() == 12 && dig.startsWith('52'))) { upd.Phone = tel; cambio = true; }
		}

		if (acc.IsPersonAccount) {
			if (String.isBlank(acc.PersonMailingStreet) && String.isNotBlank(calleFull)) { upd.PersonMailingStreet = calleFull.left(255); cambio = true; }
			if (String.isBlank(acc.PersonMailingPostalCode) && String.isNotBlank(cp)) { upd.PersonMailingPostalCode = cp; cambio = true; }
			if (String.isBlank(acc.PersonMailingCity) && String.isNotBlank(municipio)) { upd.PersonMailingCity = municipio; cambio = true; }
			if (String.isBlank(acc.PersonMailingState) && String.isNotBlank(estado)) { upd.PersonMailingState = estado; cambio = true; }
			if (String.isNotBlank(rfc) && String.isBlank((String) acc.get('RFC__pc'))) {
				try { upd.put('RFC__pc', rfc.toUpperCase()); cambio = true; } catch (Exception ignore) {}
			}
		} else {
			if (String.isBlank(acc.BillingStreet) && String.isNotBlank(calleFull)) { upd.BillingStreet = calleFull.left(255); cambio = true; }
			if (String.isBlank(acc.BillingPostalCode) && String.isNotBlank(cp)) { upd.BillingPostalCode = cp; cambio = true; }
			if (String.isBlank(acc.BillingCity) && String.isNotBlank(municipio)) { upd.BillingCity = municipio; cambio = true; }
			if (String.isBlank(acc.BillingState) && String.isNotBlank(estado)) { upd.BillingState = estado; cambio = true; }
			if (String.isNotBlank(rfc) && Schema.SObjectType.Account.fields.getMap().containsKey('rfc__c')) {
				try {
					List<Account> cur = Database.query('SELECT RFC__c FROM Account WHERE Id = :accountId LIMIT 1');
					if (!cur.isEmpty() && String.isBlank((String) cur[0].get('RFC__c'))) { upd.put('RFC__c', rfc.toUpperCase()); cambio = true; }
				} catch (Exception ignore) {}
			}
		}

		if (cambio) { try { update upd; } catch (Exception ignore) {} }
	}

	/**
	 * @creation date: 18/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Crea o actualiza el CustomerProperty (vehículo) del asegurado con los datos del PDF.
	 * @param accountId: Id de la cuenta del asegurado
	 * @param d: Datos del PDF
	 * @return void
	 */
	private static void guardarVehiculoDesdePdf(Id accountId, Map<String, Object> d) {
		if (accountId == null) { return; }
		Object bienO = d.get('bienAsegurado');
		if (!(bienO instanceof Map<String, Object>)) { return; }
		Map<String, Object> bien = (Map<String, Object>) bienO;
		Map<String, String> a = new Map<String, String>();
		if (bien.get('atributos') instanceof List<Object>) {
			for (Object o : (List<Object>) bien.get('atributos')) {
				if (o instanceof Map<String, Object>) {
					Map<String, Object> mm = (Map<String, Object>) o;
					a.put(normKey(strOf(mm.get('campo'))), strOf(mm.get('valor')));
				}
			}
		}
		String vin = a.get('numero de serie');
		String marca = a.get('marca');
		// En México "Modelo" suele ser el AÑO. Si "modelo" es un año de 4 dígitos, va a
		// MakeYear; el nombre real del modelo (ej. X3) viene en "submarca".
		String modeloRaw = a.get('modelo');
		Boolean modeloEsAnio = String.isNotBlank(modeloRaw) && Pattern.matches('\\s*(19|20)\\d{2}\\s*', modeloRaw);
		String modelo = modeloEsAnio ? a.get('submarca') : modeloRaw;
		Decimal anioD = parseMonto(a.get('ano'));
		if (anioD == null && modeloEsAnio) { anioD = parseMonto(modeloRaw); }
		Integer anio = (anioD != null) ? anioD.intValue() : null;
		// Sin identificadores de vehículo no se crea CustomerProperty. Evita que ramos
		// sin auto (GMM, Vida, Daños) generen un vehículo vacío o incorrecto.
		if (String.isBlank(vin) && String.isBlank(marca) && String.isBlank(modelo) && anio == null) { return; }
		// Mismo auto = no duplicar: busca por VIN y, si no, por Marca+Modelo+Año
		// (el identificador puede diferir entre la cotización y la póliza).
		CustomerProperty cp = null;
		if (String.isNotBlank(vin)) {
			for (CustomerProperty c : [
				SELECT Id FROM CustomerProperty
				WHERE PrimaryOwnerId = :accountId AND Vin = :vin LIMIT 1
			]) { cp = c; }
		}
		if (cp == null && String.isNotBlank(marca) && String.isNotBlank(modelo) && anio != null) {
			for (CustomerProperty c : [
				SELECT Id FROM CustomerProperty
				WHERE PrimaryOwnerId = :accountId AND Make = :marca AND ModelName = :modelo AND MakeYear = :anio
				LIMIT 1
			]) { cp = c; }
		}
		if (cp == null) { cp = new CustomerProperty(PrimaryOwnerId = accountId); }
		if (String.isNotBlank(marca))                    { cp.Make = marca; }
		if (String.isNotBlank(modelo))                   { cp.ModelName = modelo; }
		if (String.isNotBlank(vin))                      { cp.Vin = vin; }
		if (String.isNotBlank(a.get('numero de motor'))) { cp.Motor__c = a.get('numero de motor'); }
		String descBien = strOf(bien.get('descripcion'));
		if (String.isNotBlank(descBien))                 { cp.Description = descBien.length() > 255 ? descBien.substring(0, 255) : descBien; }
		if (anio != null) { try { cp.put('MakeYear', anio); } catch (Exception ignore) {} }
		if (String.isNotBlank(a.get('uso')))             { try { cp.put('Uso__c', a.get('uso').left(40)); } catch (Exception ignore) {} }
		if (String.isNotBlank(a.get('tipo de unidad')))  { try { cp.put('TipoVehiculo__c', a.get('tipo de unidad').left(40)); } catch (Exception ignore) {} }
		upsert cp;
	}

	/**
	 * @creation date: 18/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Crea o actualiza las coberturas de la póliza desde el PDF con su suma asegurada, deducible,
	 * prima y la descripción en texto; quita las coberturas de catálogo que quedaron sin valores.
	 * @param policyId: Id de la InsurancePolicy
	 * @param d: Datos del PDF con el arreglo "coberturas"
	 * @return Número de coberturas creadas o actualizadas
	 */
	private static Integer crearCoberturasDesdePdf(Id policyId, Map<String, Object> d) {
		Object covsO = d.get('coberturas');
		if (!(covsO instanceof List<Object>)) { return 0; }
		Set<String> ya = new Set<String>();
		Map<String, InsurancePolicyCoverage> existentes = new Map<String, InsurancePolicyCoverage>();
		for (InsurancePolicyCoverage c : [
			SELECT Id, CoverageName, LimitAmount, DeductibleAmount, PremiumAmount, Description
			FROM InsurancePolicyCoverage WHERE InsurancePolicyId = :policyId
		]) {
			if (String.isNotBlank(c.CoverageName)) {
				ya.add(c.CoverageName.toLowerCase());
				existentes.put(c.CoverageName.toLowerCase(), c);
			}
		}
		Map<Id, InsurancePolicyCoverage> porActualizar = new Map<Id, InsurancePolicyCoverage>();

		InsurancePolicy pol = [SELECT Id, ProductId, EffectiveDate FROM InsurancePolicy WHERE Id = :policyId LIMIT 1];
		Id assetId = null;
		for (InsurancePolicyAsset x : [SELECT Id FROM InsurancePolicyAsset WHERE InsurancePolicyId = :policyId ORDER BY CreatedDate ASC LIMIT 1]) { assetId = x.Id; }

		List<InsurancePolicyCoverage> nuevas = new List<InsurancePolicyCoverage>();
		for (Object o : (List<Object>) covsO) {
			if (!(o instanceof Map<String, Object>)) { continue; }
			Map<String, Object> m = (Map<String, Object>) o;
			String nombre = strOf(m.get('nombre'));
			if (String.isBlank(nombre)) { continue; }
			// Descarta secciones/roles que no son coberturas (TITULAR, ASEGURADO, etc.).
			if (esRolNoCobertura(nombre)) { continue; }
			String sumaTxt = strOf(m.get('sumaAsegurada'));
			String ded = strOf(m.get('deducible'));
			Decimal suma = parseMonto(sumaTxt);
			Decimal dedMonto = esMontoSimple(ded) ? parseMonto(ded) : null;
			Decimal prima = parseMonto(strOf(m.get('prima')));
			String descCob = descripcionCobertura(suma == null ? sumaTxt : null, ded);

			InsurancePolicyCoverage ex = existentes.get(nombre.toLowerCase());
			if (ex != null) {
				Boolean cambio = false;
				if (ex.LimitAmount == null && suma != null)         { ex.LimitAmount = suma; cambio = true; }
				if (ex.DeductibleAmount == null && dedMonto != null) { ex.DeductibleAmount = dedMonto; cambio = true; }
				if (ex.PremiumAmount == null && prima != null)       { ex.PremiumAmount = prima; cambio = true; }
				if (String.isNotBlank(descCob) && ex.Description != descCob) { ex.Description = descCob; cambio = true; }
				if (cambio) { porActualizar.put(ex.Id, ex); }
				continue;
			}
			if (ya.contains(nombre.toLowerCase())) { continue; }
			InsurancePolicyCoverage c = new InsurancePolicyCoverage();
			c.InsurancePolicyId = policyId;
			c.CoverageName = nombre.length() > 255 ? nombre.substring(0, 255) : nombre;
			if (suma != null)     { c.LimitAmount = suma; }
			if (dedMonto != null) { c.DeductibleAmount = dedMonto; }
			if (prima != null)    { c.PremiumAmount = prima; }
			if (String.isNotBlank(descCob)) { c.Description = descCob; }
			if (pol.ProductId != null) { c.ProductId = pol.ProductId; }
			if (assetId != null)       { c.InsurancePolicyAssetId = assetId; }
			if (pol.EffectiveDate != null) { asignaFechaFlexible(c, 'EffectiveDate', pol.EffectiveDate.date(), pol.EffectiveDate); }
			ya.add(nombre.toLowerCase());
			nuevas.add(c);
		}
		if (!nuevas.isEmpty()) { insert nuevas; }
		if (!porActualizar.isEmpty()) { update porActualizar.values(); }
		return nuevas.size();
	}

	/**
	 * @creation date: 29/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma la descripción de la cobertura con los valores en texto tal cual la póliza ("Suma
	 * asegurada: AMPARADA | Deducible: 5 %").
	 * @param sumaTxt: Suma asegurada en texto
	 * @param dedTxt: Deducible en texto
	 * @return Descripción; null si no hay valores
	 */
	private static String descripcionCobertura(String sumaTxt, String dedTxt) {
		List<String> partes = new List<String>();
		if (String.isNotBlank(sumaTxt)) { partes.add('Suma asegurada: ' + sumaTxt); }
		if (String.isNotBlank(dedTxt))  { partes.add('Deducible: ' + dedTxt); }
		return partes.isEmpty() ? null : String.join(partes, ' | ').left(255);
	}

	/**
	 * @creation date: 29/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Lee un valor ("Deducible", "Suma asegurada") de la descripción de la cobertura.
	 * @param descripcion: Descripción de la cobertura
	 * @param etiqueta: Etiqueta a buscar
	 * @return Valor encontrado; null si no está
	 */
	@TestVisible
	private static String valorDeDescripcion(String descripcion, String etiqueta) {
		if (String.isBlank(descripcion)) { return null; }
		for (String parte : descripcion.split('\\|')) {
			String p = parte.trim();
			if (p.startsWithIgnoreCase(etiqueta + ':')) {
				String v = p.substring(etiqueta.length() + 1).trim();
				return String.isBlank(v) ? null : v;
			}
		}
		return null;
	}

	/**
	 * @creation date: 29/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Indica si el deducible es solo un monto (ej. "$5,000") y no trae porcentaje u otras unidades.
	 * @param v: Deducible en texto
	 * @return true si es un monto simple
	 */
	@TestVisible
	private static Boolean esMontoSimple(String v) {
		if (String.isBlank(v)) { return false; }
		String sinMonto = v.replaceAll('[0-9$.,\\s]', '').replaceAll('(?i)mxn|pesos|m\\.n\\.?', '');
		return String.isBlank(sinMonto) && parseMonto(v) != null;
	}

	/**
	 * @creation date: 24/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Indica si el texto es una sección o rol de la póliza ("TITULAR", "ASEGURADO"…) y no una
	 * cobertura real.
	 * @param nombre: Nombre de la supuesta cobertura
	 * @return true si no es una cobertura
	 */
	private static Boolean esRolNoCobertura(String nombre) {
		String k = normKey(nombre).replaceAll('\\s+', ' ');
		Set<String> roles = new Set<String>{
			'titular', 'contratante', 'asegurado', 'asegurada', 'asegurado titular',
			'beneficiario', 'beneficiarios', 'conductor', 'conductor habitual',
			'propietario', 'dependiente', 'dependientes', 'contratante/asegurado',
			'datos del asegurado', 'datos del contratante'
		};
		return roles.contains(k);
	}

	/**
	 * @creation date: 18/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Normaliza una llave de texto: minúsculas y sin acentos ("Número de Serie" → "numero de serie").
	 * @param s: Texto a normalizar
	 * @return Texto normalizado
	 */
	private static String normKey(String s) {
		if (s == null) { return ''; }
		String r = s.toLowerCase();
		r = r.replace('á', 'a').replace('é', 'e').replace('í', 'i').replace('ó', 'o').replace('ú', 'u').replace('ñ', 'n').replace('ü', 'u');
		return r.trim();
	}

	/**
	 * @creation date: 18/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Convierte un valor del JSON a texto sin espacios sobrantes.
	 * @param o: Valor a convertir
	 * @return Texto; null si el valor es null
	 */
	private static String strOf(Object o) { return o == null ? null : String.valueOf(o).trim(); }

	/**
	 * @creation date: 18/09/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Extrae el primer número de un texto ("$3,000,000", "150000 USD" → 150000).
	 * @param v: Texto con el monto
	 * @return Monto; null si no hay número
	 */
	private static Decimal parseMonto(String v) {
		if (String.isBlank(v)) { return null; }
		Matcher mt = Pattern.compile('[0-9][0-9,]*(\\.[0-9]+)?').matcher(v);
		if (mt.find()) {
			try { return Decimal.valueOf(mt.group().replace(',', '')); } catch (Exception e) {}
		}
		return null;
	}

	/**
	 * @creation date: 27/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Une todos los mensajes DML de la excepción en un solo texto.
	 * @param e: Excepción DML
	 * @return Mensajes separados por " | "
	 */
	private static String detalleDml(DmlException e) {
		List<String> partes = new List<String>();
		for (Integer i = 0; i < e.getNumDml(); i++) {
			String m = e.getDmlMessage(i);
			if (String.isNotBlank(m)) { partes.add(m); }
		}
		return partes.isEmpty() ? e.getMessage() : String.join(partes, ' | ');
	}
}