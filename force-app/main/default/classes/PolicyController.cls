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
			}
			return null;
		} catch (Exception e) {
			throw new AuraHandledException('Error al localizar la póliza: ' + e.getMessage());
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

	// Quita fences de Markdown (```json ... ```) y recorta al primer '{' y último '}'.
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
	 * @description: Al emitir la póliza, crea el vínculo póliza–bien (InsurancePolicyAsset).
	 *               Reúsa el Asset creado por la oportunidad si existe; si no, crea uno con
	 *               los datos de la póliza. Es idempotente: si el vínculo ya existe, no duplica.
	 * @param policyId: Id de la InsurancePolicy recién emitida.
	 * @return Id del InsurancePolicyAsset creado o existente.
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
			Boolean usarCustomerProperty = (bienCliente != null && campoAcepta(cpField, CustomerProperty.SObjectType));
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

	// Indica si un campo de tipo lookup acepta registros del objeto indicado.
	private static Boolean campoAcepta(Schema.DescribeFieldResult f, Schema.SObjectType objetivo) {
		if (f == null || objetivo == null) { return false; }
		for (Schema.SObjectType t : f.getReferenceTo()) {
			if (t == objetivo) { return true; }
		}
		return false;
	}

	// Cuenta del asegurado: por la oportunidad origen o, si NameInsured es una cuenta, esa.
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
	 * @description Guarda (adjunta) el PDF seleccionado como archivo de la Póliza.
	 *              Es idempotente: si ya existe un archivo con el mismo nombre ligado
	 *              a la póliza, no lo vuelve a subir.
	 * @param base64 Contenido del PDF en base64 (sin el prefijo data:).
	 * @param nombreArchivo Nombre del archivo (con extensión).
	 * @param policyId Id de la InsurancePolicy a la que se adjunta.
	 * @return Id del ContentDocument adjuntado o existente, o null.
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

	// ============================================================
	// ORQUESTADOR: completa los registros hijos de la póliza (FSC).
	//   Al emitir la póliza crea, de forma idempotente e independiente,
	//   los registros que faltan del modelo de Financial Services:
	//     1) Bien asegurado        (InsurancePolicyAsset)
	//     2) Asegurados/participantes (InsurancePolicyParticipant)
	//     3) Coberturas            (InsurancePolicyCoverage) desde el catálogo del producto
	//     4) Transacción de prima  (InsurancePolicyTransaction)
	//   Cada paso va en su propio try: si uno falla, los demás continúan.
	// @param policyId Id de la InsurancePolicy recién emitida.
	// @param opportunityId Oportunidad origen (para los asegurados). Puede ser null;
	//        en ese caso se toma de InsurancePolicy.SourceOpportunityId.
	// @return Mapa con el resumen de lo creado y, si aplica, los errores por paso.
	// ============================================================
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

		return resumen;
	}

	/**
	 * @description Crea los Participantes de la póliza (InsurancePolicyParticipant).
	 *              1) Colectiva: copia los asegurados capturados como Rol de Contacto de
	 *                 Oportunidad (reúsa AseguradosController.copiarAseguradosAPoliza).
	 *              2) Individual: si la póliza queda sin participantes, crea uno con el
	 *                 asegurado de la póliza (cuenta en NameInsured) o el contacto de la
	 *                 oportunidad. Es idempotente: no crea si ya hay participantes.
	 * @param policyId Id de la InsurancePolicy.
	 * @param opportunityId Oportunidad origen. Puede ser null (se toma de la póliza).
	 * @return número de participantes creados.
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
		insert p;
		return creados + 1;
	}

	/**
	 * @description Crea las Coberturas de la póliza (InsurancePolicyCoverage) a partir
	 *              de las coberturas del producto (ProductCoverageAssignment__c → CoverageType).
	 *              Es idempotente: no duplica coberturas ya existentes en la póliza y omite
	 *              cualquier cobertura marcada como "PENDIENTE" (placeholder del catálogo).
	 * @param policyId Id de la InsurancePolicy.
	 * @return número de coberturas creadas.
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
		for (ProductCoverageAssignment__c pca : [
			SELECT Coverage_Type__c, Coverage_Type__r.Name, Coverage_Type__r.CoverageCode,
				   Coverage_Type__r.LimitAmount, Coverage_Type__r.DeductibleAmount,
				   Coverage_Type__r.PremiumAmount, Coverage_Type__r.Description
			FROM ProductCoverageAssignment__c
			WHERE Product__c = :pol.ProductId AND Coverage_Type__c != null
		]) {
			String nombre = pca.Coverage_Type__r != null ? pca.Coverage_Type__r.Name : null;
			if (String.isBlank(nombre)) { continue; }
			// Defensa: no traer placeholders "PENDIENTE" aunque quedara alguno en el catálogo.
			if (nombre.toUpperCase().startsWith('PENDIENTE')) { continue; }
			if (yaPorTipo.contains(pca.Coverage_Type__c)) { continue; }
			if (yaPorNombre.contains(nombre.toLowerCase())) { continue; }

			InsurancePolicyCoverage c = new InsurancePolicyCoverage();
			c.InsurancePolicyId = policyId;
			c.CoverageTypeId = pca.Coverage_Type__c;
			c.CoverageName = nombre.length() > 255 ? nombre.substring(0, 255) : nombre;
			if (pca.Coverage_Type__r != null) {
				if (String.isNotBlank(pca.Coverage_Type__r.CoverageCode)) { c.CoverageCode = pca.Coverage_Type__r.CoverageCode; }
				if (pca.Coverage_Type__r.LimitAmount != null)      { c.LimitAmount = pca.Coverage_Type__r.LimitAmount; }
				if (pca.Coverage_Type__r.DeductibleAmount != null) { c.DeductibleAmount = pca.Coverage_Type__r.DeductibleAmount; }
				if (pca.Coverage_Type__r.PremiumAmount != null)    { c.PremiumAmount = pca.Coverage_Type__r.PremiumAmount; }
				if (String.isNotBlank(pca.Coverage_Type__r.Description)) { c.Description = pca.Coverage_Type__r.Description; }
			}
			if (pol.ProductId != null) { c.ProductId = pol.ProductId; }
			if (assetId != null)       { c.InsurancePolicyAssetId = assetId; }
			if (pol.EffectiveDate != null) {
				// EffectiveDate de la cobertura puede ser Date o Datetime según el org.
				asignaFechaFlexible(c, 'EffectiveDate', pol.EffectiveDate.date(), pol.EffectiveDate);
			}
			// Evita duplicados dentro del mismo lote.
			yaPorTipo.add(pca.Coverage_Type__c);
			yaPorNombre.add(nombre.toLowerCase());
			nuevas.add(c);
		}
		if (!nuevas.isEmpty()) { insert nuevas; }
		return nuevas.size();
	}

	/**
	 * @description Crea la Transacción de prima inicial (InsurancePolicyTransaction) de la póliza.
	 *              Es idempotente: si la póliza ya tiene una transacción, devuelve la existente.
	 *              El importe usa la prima del periodo (TermPremiumAmount); si no, la prima total
	 *              o la neta como respaldo. Los picklists se resuelven contra el catálogo del org.
	 * @param policyId Id de la InsurancePolicy.
	 * @return Id de la transacción creada o existente.
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

	// ============================================================
	// Wrappers para la vista de solo lectura (registros hijos de la póliza).
	// ============================================================
	public class RegistrosPoliza {
		@AuraEnabled public List<CoberturaRow> coberturas = new List<CoberturaRow>();
		@AuraEnabled public List<ParticipanteRow> participantes = new List<ParticipanteRow>();
		@AuraEnabled public List<BienRow> bienes = new List<BienRow>();
		@AuraEnabled public List<TransaccionRow> transacciones = new List<TransaccionRow>();
	}
	public class CoberturaRow {
		@AuraEnabled public Id id;
		@AuraEnabled public String nombre;
		@AuraEnabled public Decimal suma;
		@AuraEnabled public Decimal deducible;
		@AuraEnabled public Decimal prima;
	}
	public class ParticipanteRow {
		@AuraEnabled public Id id;
		@AuraEnabled public String nombre;
		@AuraEnabled public String rol;
		@AuraEnabled public String relacion;
	}
	public class BienRow {
		@AuraEnabled public Id id;
		@AuraEnabled public String nombre;
		@AuraEnabled public Boolean activo;
		@AuraEnabled public Decimal prima;
	}
	public class TransaccionRow {
		@AuraEnabled public Id id;
		@AuraEnabled public String nombre;
		@AuraEnabled public String tipo;
		@AuraEnabled public String estatus;
		@AuraEnabled public Decimal monto;
		@AuraEnabled public Datetime fecha;
	}

	/**
	 * @description Devuelve los registros hijos de la póliza (coberturas, participantes,
	 *              bien asegurado y transacciones) para mostrarlos en la vista de la póliza.
	 * @param policyId Id de la InsurancePolicy.
	 * @return wrapper con las cuatro listas (vacías si no hay).
	 */
	@AuraEnabled(cacheable=false)
	public static RegistrosPoliza getRegistrosPoliza(Id policyId) {
		RegistrosPoliza out = new RegistrosPoliza();
		if (policyId == null) { return out; }
		try {
			for (InsurancePolicyCoverage c : [
				SELECT Id, CoverageName, LimitAmount, DeductibleAmount, PremiumAmount
				FROM InsurancePolicyCoverage WHERE InsurancePolicyId = :policyId
				ORDER BY CoverageName
			]) {
				CoberturaRow r = new CoberturaRow();
				r.id = c.Id; r.nombre = c.CoverageName;
				r.suma = c.LimitAmount; r.deducible = c.DeductibleAmount; r.prima = c.PremiumAmount;
				out.coberturas.add(r);
			}
			for (InsurancePolicyParticipant p : [
				SELECT Id, ParticipantName, Role, RelationshipToInsured
				FROM InsurancePolicyParticipant WHERE InsurancePolicyId = :policyId
				ORDER BY ParticipantName
			]) {
				ParticipanteRow r = new ParticipanteRow();
				r.id = p.Id; r.nombre = p.ParticipantName;
				r.rol = p.Role; r.relacion = p.RelationshipToInsured;
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

	// Asigna una fecha al campo con el tipo correcto (Date o Datetime según el org).
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

	// Devuelve el primer valor de picklist activo que coincida (ignora mayúsculas).
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

	// Mensaje de error legible (primer mensaje DML si aplica).
	private static String msgLimpio(Exception e) {
		if (e instanceof DmlException && ((DmlException) e).getNumDml() > 0) {
			return ((DmlException) e).getDmlMessage(0);
		}
		return e.getMessage();
	}

	private static String detalleDml(DmlException e) {
		List<String> partes = new List<String>();
		for (Integer i = 0; i < e.getNumDml(); i++) {
			String m = e.getDmlMessage(i);
			if (String.isNotBlank(m)) { partes.add(m); }
		}
		return partes.isEmpty() ? e.getMessage() : String.join(partes, ' | ');
	}
}