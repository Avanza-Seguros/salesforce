/**
 * @creation date: 14/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Cotizaciones colectivas por aseguradora. Ramos de PERSONAS (GMM, Vida Grupo, Accidentes Personales,
 *               Dental, Visión, Viajes): un Categoria_Colectiva__c por categoría (asegurados, prima, plan, coberturas y
 *               tarifa por edad). Ramos de UBICACIONES (Daños, Empresarial): un Categoria_Colectiva__c por ubicación
 *               (dirección, valor asegurado, prima y coberturas). Cada cotización (PDF o Excel, leída con IA en el LWC
 *               colectivoPersonas) es un Quote de la oportunidad. Alimenta el comparativo en pantalla y en PDF.
 */
public with sharing class ColectivoController {

	// Prompt Template (Prompt Builder) que lee cotizaciones colectivas de personas y su variable de entrada.
	private static final String PROMPT_TEMPLATE_API_NAME = 'Extractor_Colectivo_Personas';
	// Prompt Template para cotizaciones de Daños / Empresarial con varias ubicaciones.
	private static final String PROMPT_UBICACIONES_API_NAME = 'Extractor_Colectivo_Ubicaciones';
	private static final String PROMPT_INPUT_PARAM = 'Input:TextoCotizacion';
	// Marca del comparativo colectivo / de flotilla guardado en Opportunity.Descripcion__c (lo muestra "Análisis IA").
	public static final String MARCA_COMPARATIVO = '<!--comparativo-colectivo-->';
	// Secciones de detalle que se omiten (en este orden) si el comparativo no cabe en Descripcion__c.
	private static final List<String> SECCIONES_DETALLE = new List<String>{
		'Prima por vehículo', 'Distribución por edad', 'Coberturas adicionales', 'Coberturas y deducibles'
	};
	// Ramos en los que cada renglón de la cotización es una ubicación (inmueble) y no un grupo de personas.
	private static final Set<String> RAMOS_UBICACIONES = new Set<String>{ 'Danos', 'Empresarial' };

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Asegurados y prima de un rango de edad.
	 */
	public class TarifaEdad {
		public String rango;
		public Decimal hombres;
		public Decimal mujeres;
		public Decimal primaHombre;
		public Decimal primaMujer;
		public Decimal primaTotal;
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Forma de pago cotizada (anual, semestral, trimestral, mensual).
	 */
	public class FormaPago {
		public String forma;
		public Decimal recargoPct;
		public Decimal numeroPagos;
		public Decimal primaTotal;
		public Decimal primerPago;
		public Decimal pagoSubsecuente;
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cobertura o condición del plan (concepto y valor tal cual vienen en la cotización).
	 */
	public class Parametro {
		public String concepto;
		public String valor;
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Categoría (subgrupo de personas) o ubicación de la cotización.
	 */
	public class CategoriaEntrada {
		public String nombre;
		public Decimal asegurados;
		public Decimal hombres;
		public Decimal mujeres;
		public Decimal titulares;
		public Decimal dependientes;
		public Decimal primaNeta;
		public Decimal sumaAseguradaTotal;
		public String direccion;
		public String plan;
		public String sumaAsegurada;
		public String deducible;
		public String coaseguro;
		public String topeCoaseguro;
		public String tabulador;
		public String nivelHospitalario;
		public String territorio;
		public List<String> coberturasAdicionales;
		public List<TarifaEdad> tarifaEdades;
		public List<Parametro> parametros;
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cotización de la aseguradora que envía el LWC.
	 */
	public class CotizacionEntrada {
		public Id aseguradoraId;
		public String numeroCotizacion;
		public String vigenciaDesde;
		public String vigenciaHasta;
		public String formaPago;
		public Decimal primaNeta;
		public Decimal derechos;
		public Decimal recargo;
		public Decimal iva;
		public Decimal primaTotal;
		public String archivo;
		public List<FormaPago> formasPago;
		public List<CategoriaEntrada> categorias;
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cotizaciones colectivas de la oportunidad con sus categorías, para el comparativo.
	 * @param opportunityId: oportunidad colectiva.
	 * @return lista de cotizaciones {id, aseguradora, montos, formasPago, categorias[]}.
	 */
	@AuraEnabled(cacheable=false)
	public static List<Map<String, Object>> getCotizacionesColectivas(Id opportunityId) {
		Map<Id, Map<String, Object>> porQuote = new Map<Id, Map<String, Object>>();
		// Cotizaciones solo con aseguradora y primas (sin categorías ni ubicaciones).
		for (Quote qt : [
			SELECT Id, Name, QuoteNumber, Aseguradora__r.Name, Prima_Total__c, Prima_Neta__c, Derechos_Poliza__c,
				Recargo_Fraccionado__c, IVA__c, Forma_de_pago__c, Vigencia_Inicio__c, ExpirationDate, Opciones_Pago__c,
				Ramos__c, NumeroCotizacion__c
			FROM Quote
			WHERE OpportunityId = :opportunityId AND Name LIKE 'Colectivo %'
			ORDER BY CreatedDate ASC
			LIMIT 200
		]) {
			porQuote.put(qt.Id, new Map<String, Object>{
				'id' => qt.Id, 'nombre' => qt.Name, 'numero' => qt.QuoteNumber,
				'aseguradora' => qt.Aseguradora__r != null ? qt.Aseguradora__r.Name : qt.Name,
				'ramo' => qt.Ramos__c, 'numeroCotizacion' => qt.NumeroCotizacion__c,
				'primaTotal' => qt.Prima_Total__c, 'primaNeta' => qt.Prima_Neta__c, 'derechos' => qt.Derechos_Poliza__c,
				'recargo' => qt.Recargo_Fraccionado__c, 'iva' => qt.IVA__c, 'formaPago' => qt.Forma_de_pago__c,
				'vigenciaDesde' => qt.Vigencia_Inicio__c, 'vigenciaHasta' => qt.ExpirationDate,
				'formasPago' => jsonLista(qt.Opciones_Pago__c), 'categorias' => new List<Object>()
			});
		}
		for (Categoria_Colectiva__c c : [
			SELECT Id, Name, Cotizacion__c, Cotizacion__r.Name, Cotizacion__r.QuoteNumber, Cotizacion__r.Aseguradora__r.Name,
				Cotizacion__r.Prima_Total__c, Cotizacion__r.Prima_Neta__c, Cotizacion__r.Derechos_Poliza__c,
				Cotizacion__r.Recargo_Fraccionado__c, Cotizacion__r.IVA__c, Cotizacion__r.Forma_de_pago__c,
				Cotizacion__r.Vigencia_Inicio__c, Cotizacion__r.ExpirationDate, Cotizacion__r.Opciones_Pago__c,
				Cotizacion__r.Ramos__c, Cotizacion__r.NumeroCotizacion__c, Cotizacion__r.CreatedDate,
				Asegurados__c, Hombres__c, Mujeres__c, Titulares__c, Dependientes__c, Prima_Neta__c, Plan__c,
				Suma_Asegurada__c, Deducible__c, Coaseguro__c, Tope_Coaseguro__c, Tabulador__c, Nivel_Hospitalario__c,
				Territorio__c, Coberturas_Adicionales__c, Tarifa_Edades__c, Parametros__c, Suma_Asegurada_Total__c, Direccion__c
			FROM Categoria_Colectiva__c
			WHERE Oportunidad__c = :opportunityId AND Cotizacion__c != null
			ORDER BY Cotizacion__r.CreatedDate ASC, CreatedDate ASC, Name ASC
			LIMIT 2000
		]) {
			Map<String, Object> q = porQuote.get(c.Cotizacion__c);
			if (q == null) {
				Quote qt = c.Cotizacion__r;
				q = new Map<String, Object>{
					'id' => c.Cotizacion__c, 'nombre' => qt.Name, 'numero' => qt.QuoteNumber,
					'aseguradora' => qt.Aseguradora__r != null ? qt.Aseguradora__r.Name : qt.Name,
					'ramo' => qt.Ramos__c, 'numeroCotizacion' => qt.NumeroCotizacion__c,
					'primaTotal' => qt.Prima_Total__c, 'primaNeta' => qt.Prima_Neta__c, 'derechos' => qt.Derechos_Poliza__c,
					'recargo' => qt.Recargo_Fraccionado__c, 'iva' => qt.IVA__c, 'formaPago' => qt.Forma_de_pago__c,
					'vigenciaDesde' => qt.Vigencia_Inicio__c, 'vigenciaHasta' => qt.ExpirationDate,
					'formasPago' => jsonLista(qt.Opciones_Pago__c), 'categorias' => new List<Object>()
				};
				porQuote.put(c.Cotizacion__c, q);
			}
			((List<Object>) q.get('categorias')).add(new Map<String, Object>{
				'id' => c.Id, 'nombre' => c.Name, 'asegurados' => c.Asegurados__c, 'hombres' => c.Hombres__c,
				'mujeres' => c.Mujeres__c, 'titulares' => c.Titulares__c, 'dependientes' => c.Dependientes__c,
				'primaNeta' => c.Prima_Neta__c, 'sumaAseguradaTotal' => c.Suma_Asegurada_Total__c, 'direccion' => c.Direccion__c,
				'plan' => c.Plan__c, 'sumaAsegurada' => c.Suma_Asegurada__c,
				'deducible' => c.Deducible__c, 'coaseguro' => c.Coaseguro__c, 'topeCoaseguro' => c.Tope_Coaseguro__c,
				'tabulador' => c.Tabulador__c, 'nivelHospitalario' => c.Nivel_Hospitalario__c, 'territorio' => c.Territorio__c,
				'coberturasAdicionales' => String.isBlank(c.Coberturas_Adicionales__c) ? new List<String>() : c.Coberturas_Adicionales__c.split('\n'),
				'tarifaEdades' => jsonLista(c.Tarifa_Edades__c), 'parametros' => jsonLista(c.Parametros__c)
			});
		}
		return porQuote.values();
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Guarda la cotización colectiva de una aseguradora: Quote (primas, formas de pago) y una
	 *               Categoria_Colectiva__c por categoría. Sin categorías se guarda solo la cotización con sus primas
	 *               y no se genera comparativo. La prima total es la del archivo o, si no viene,
	 *               prima neta + derechos + recargo + IVA. Todo o nada.
	 * @param opportunityId: oportunidad colectiva.
	 * @param datosJson: JSON de CotizacionEntrada.
	 * @return Id del Quote creado.
	 */
	@AuraEnabled(cacheable=false)
	public static Id guardarCotizacionColectiva(Id opportunityId, String datosJson) {
		CotizacionEntrada datos;
		try {
			datos = (CotizacionEntrada) JSON.deserialize(String.isBlank(datosJson) ? '{}' : datosJson, CotizacionEntrada.class);
		} catch (Exception e) {
			throw error('La cotización no tiene un formato válido: ' + e.getMessage());
		}
		if (datos.aseguradoraId == null) { throw error('Selecciona la aseguradora de la cotización.'); }
		if (datos.categorias == null) { datos.categorias = new List<CategoriaEntrada>(); }
		if (datos.categorias.isEmpty() && datos.primaNeta == null && datos.primaTotal == null) {
			throw error('La cotización no tiene prima neta ni prima total.');
		}
		List<Opportunity> opps = [SELECT Id, Name, Pricebook2Id, Ramo__c FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
		if (opps.isEmpty()) { throw error('No se encontró la oportunidad.'); }
		Opportunity opp = opps[0];
		List<Aseguradora__c> asegs = [SELECT Id, Name FROM Aseguradora__c WHERE Id = :datos.aseguradoraId LIMIT 1];
		if (asegs.isEmpty()) { throw error('No se encontró la aseguradora seleccionada.'); }

		Savepoint sp = Database.setSavepoint();
		try {
			Decimal sumaNeta = 0;
			Decimal asegurados = 0;
			for (CategoriaEntrada c : datos.categorias) {
				if (String.isBlank(c.nombre)) { c.nombre = 'General'; }
				sumaNeta += nz(c.primaNeta);
				asegurados += nz(c.asegurados);
			}
			Decimal neta = datos.primaNeta != null ? datos.primaNeta : (sumaNeta > 0 ? sumaNeta : null);
			Decimal total = datos.primaTotal != null ? datos.primaTotal
				: (neta == null ? null : neta + nz(datos.derechos) + nz(datos.recargo) + nz(datos.iva));

			String ramo = String.isNotBlank(opp.Ramo__c) ? opp.Ramo__c : 'GMM';
			Quote q = new Quote(OpportunityId = opp.Id, Status = 'In Review');
			String tamano = datos.categorias.isEmpty() ? ''
				: esUbicaciones(ramo) ? datos.categorias.size() + (datos.categorias.size() == 1 ? ' ubicación' : ' ubicaciones')
				: asegurados.intValue() + ' asegurados';
			q.Name = ('Colectivo ' + etiquetaRamo(ramo) + ' - ' + asegs[0].Name + (String.isBlank(tamano) ? '' : ' (' + tamano + ')')).left(255);
			q.Pricebook2Id = opp.Pricebook2Id != null ? opp.Pricebook2Id : pricebookEstandar();
			q.put('Aseguradora__c', asegs[0].Id);
			Id producto = productoRamo(asegs[0].Id, ramo);
			if (producto != null) { q.put('Product__c', producto); }
			q.put('Ramos__c', valorPicklist(Quote.Ramos__c, ramo, null));
			q.put('RatingDate', Date.today());
			Date desde = fecha(datos.vigenciaDesde);
			Date hasta = fecha(datos.vigenciaHasta);
			if (desde != null) { q.put('Vigencia_Inicio__c', desde); }
			q.ExpirationDate = hasta != null ? hasta : (desde != null ? desde : Date.today()).addYears(1);
			if (String.isNotBlank(datos.formaPago)) { q.put('Forma_de_pago__c', datos.formaPago.left(40)); }
			q.put('Frecuencia_de_prima__c', valorPicklist(Quote.Frecuencia_de_prima__c, frecuencia(datos.formaPago), 'Anual'));
			if (String.isNotBlank(datos.numeroCotizacion)) { q.put('NumeroCotizacion__c', datos.numeroCotizacion.left(60)); }
			if (total != null) { q.put('Prima_Total__c', total); q.put('PrimaAnual__c', total); }
			if (neta != null) { q.put('Prima_Neta__c', neta); }
			if (datos.derechos != null) { q.put('Derechos_Poliza__c', datos.derechos); }
			if (datos.recargo != null) { q.put('Recargo_Fraccionado__c', datos.recargo); }
			if (datos.iva != null) { q.put('IVA__c', datos.iva); }
			if (datos.formasPago != null && !datos.formasPago.isEmpty()) { q.put('Opciones_Pago__c', JSON.serialize(datos.formasPago, true)); }
			if (String.isNotBlank(datos.archivo)) { q.Description = ('Cotización colectiva cargada de: ' + datos.archivo).left(32000); }
			insert q;

			List<Categoria_Colectiva__c> categorias = new List<Categoria_Colectiva__c>();
			for (CategoriaEntrada e : datos.categorias) {
				Categoria_Colectiva__c c = new Categoria_Colectiva__c(Cotizacion__c = q.Id, Oportunidad__c = opp.Id);
				setTexto(c, 'Name', e.nombre);
				c.Asegurados__c = e.asegurados;
				c.Hombres__c = e.hombres;
				c.Mujeres__c = e.mujeres;
				c.Titulares__c = e.titulares;
				c.Dependientes__c = e.dependientes;
				c.Prima_Neta__c = e.primaNeta;
				c.Suma_Asegurada_Total__c = e.sumaAseguradaTotal;
				setTexto(c, 'Direccion__c', e.direccion);
				setTexto(c, 'Plan__c', e.plan);
				setTexto(c, 'Suma_Asegurada__c', e.sumaAsegurada);
				setTexto(c, 'Deducible__c', e.deducible);
				setTexto(c, 'Coaseguro__c', e.coaseguro);
				setTexto(c, 'Tope_Coaseguro__c', e.topeCoaseguro);
				setTexto(c, 'Tabulador__c', e.tabulador);
				setTexto(c, 'Nivel_Hospitalario__c', e.nivelHospitalario);
				setTexto(c, 'Territorio__c', e.territorio);
				if (e.coberturasAdicionales != null && !e.coberturasAdicionales.isEmpty()) {
					c.Coberturas_Adicionales__c = String.join(e.coberturasAdicionales, '\n').left(32768);
				}
				if (e.tarifaEdades != null && !e.tarifaEdades.isEmpty()) { c.Tarifa_Edades__c = JSON.serialize(e.tarifaEdades, true); }
				List<Parametro> params = new List<Parametro>();
				for (Parametro pm : e.parametros == null ? new List<Parametro>() : e.parametros) {
					if (pm != null && String.isNotBlank(pm.concepto) && String.isNotBlank(pm.valor)) { params.add(pm); }
				}
				if (!params.isEmpty()) { c.Parametros__c = JSON.serialize(params, true).left(32768); }
				categorias.add(c);
			}
			if (!categorias.isEmpty()) {
				insert categorias;
				actualizarComparativo(opp.Id);
			}
			return q.Id;
		} catch (AuraHandledException ahe) {
			Database.rollback(sp);
			throw ahe;
		} catch (Exception e) {
			Database.rollback(sp);
			throw error('No se pudo guardar la cotización colectiva: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Elimina una cotización colectiva con sus categorías.
	 * @param quoteId: Quote a eliminar.
	 */
	@AuraEnabled(cacheable=false)
	public static void eliminarCotizacionColectiva(Id quoteId) {
		if (quoteId == null) { return; }
		Id oppId;
		for (Quote q : [SELECT OpportunityId FROM Quote WHERE Id = :quoteId LIMIT 1]) { oppId = q.OpportunityId; }
		Savepoint sp = Database.setSavepoint();
		try {
			delete [SELECT Id FROM Categoria_Colectiva__c WHERE Cotizacion__c = :quoteId];
			delete [SELECT Id FROM Quote WHERE Id = :quoteId];
			if (oppId != null) { actualizarComparativo(oppId); }
		} catch (Exception e) {
			Database.rollback(sp);
			throw error('No se pudo eliminar la cotización: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Envía a Einstein el texto de la cotización (PDF, o Excel convertido a texto en el navegador) y
	 *               devuelve el JSON con categorías o ubicaciones, plan y primas. Usa Extractor_Colectivo_Ubicaciones
	 *               en Daños / Empresarial y Extractor_Colectivo_Personas en los demás ramos.
	 * @param textoCotizacion: texto de la cotización.
	 * @param ramo: ramo de la oportunidad (guía para la IA; vacío = personas).
	 * @return JSON de la cotización.
	 */
	@AuraEnabled(cacheable=false)
	public static String analizarCotizacionColectiva(String textoCotizacion, String ramo) {
		if (String.isBlank(textoCotizacion)) { throw error('No se recibió texto de la cotización para analizar.'); }
		if (Test.isRunningTest()) { return '{"categorias":[]}'; }
		try {
			String prompt = esUbicaciones(ramo) ? PROMPT_UBICACIONES_API_NAME : PROMPT_TEMPLATE_API_NAME;
			String texto = (String.isNotBlank(ramo) ? 'RAMO DE LA OPORTUNIDAD: ' + etiquetaRamo(ramo) + '\n' : '') + textoCotizacion;
			ConnectApi.WrappedValue wrapped = new ConnectApi.WrappedValue();
			wrapped.value = texto.length() > 60000 ? texto.substring(0, 60000) : texto;
			ConnectApi.EinsteinPromptTemplateGenerationsInput genInput = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
			genInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
			genInput.additionalConfig.applicationName = 'PromptBuilderPreview';
			genInput.isPreview = false;
			genInput.inputParams = new Map<String, ConnectApi.WrappedValue>{ PROMPT_INPUT_PARAM => wrapped };
			ConnectApi.EinsteinPromptTemplateGenerationsRepresentation gen =
				ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(prompt, genInput);
			if (gen != null && gen.generations != null && !gen.generations.isEmpty() && String.isNotBlank(gen.generations[0].text)) {
				return limpiarJson(gen.generations[0].text);
			}
			throw error('La IA no devolvió datos de la cotización.');
		} catch (AuraHandledException ahe) {
			throw ahe;
		} catch (Exception e) {
			throw error('Error al analizar la cotización: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Genera el PDF del comparativo colectivo (página ColectivoComparativoPdf) y lo guarda en la
	 *               oportunidad y en cada cotización; si ya existe, agrega una versión al mismo archivo.
	 * @param opportunityId: oportunidad colectiva con cotizaciones.
	 * @return Id del ContentDocument del comparativo.
	 */
	@AuraEnabled(cacheable=false)
	public static Id generarComparativoPdf(Id opportunityId) {
		List<Opportunity> opps = [SELECT Id, Name FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
		if (opps.isEmpty()) { throw error('No se encontró la oportunidad.'); }
		Set<Id> quoteIds = new Set<Id>();
		for (Categoria_Colectiva__c c : [SELECT Cotizacion__c FROM Categoria_Colectiva__c WHERE Oportunidad__c = :opportunityId AND Cotizacion__c != null LIMIT 2000]) {
			quoteIds.add(c.Cotizacion__c);
		}
		if (quoteIds.isEmpty()) { throw error('Agrega al menos una cotización colectiva para generar el comparativo.'); }
		try {
			Blob pdf;
			if (Test.isRunningTest()) {
				pdf = Blob.valueOf(ColectivoComparativoPdfController.construirHtml(opportunityId));
			} else {
				PageReference pr = Page.ColectivoComparativoPdf;
				pr.getParameters().put('oppId', opportunityId);
				pdf = pr.getContentAsPDF();
			}
			String titulo = ('Comparativo colectivo - ' + opps[0].Name).left(240);
			Id docId;
			for (ContentDocumentLink l : [
				SELECT ContentDocumentId FROM ContentDocumentLink
				WHERE LinkedEntityId = :opportunityId AND ContentDocument.Title = :titulo LIMIT 1
			]) { docId = l.ContentDocumentId; }
			ContentVersion cv = new ContentVersion(Title = titulo, PathOnClient = titulo + '.pdf', VersionData = pdf, Origin = 'H');
			if (docId != null) { cv.ContentDocumentId = docId; }
			insert cv;
			if (docId == null) { docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId; }
			Set<Id> ligados = new Set<Id>();
			for (ContentDocumentLink l : [SELECT LinkedEntityId FROM ContentDocumentLink WHERE ContentDocumentId = :docId]) { ligados.add(l.LinkedEntityId); }
			List<ContentDocumentLink> links = new List<ContentDocumentLink>();
			Set<Id> destinos = new Set<Id>(quoteIds);
			destinos.add(opportunityId);
			for (Id d : destinos) {
				if (!ligados.contains(d)) { links.add(new ContentDocumentLink(ContentDocumentId = docId, LinkedEntityId = d, ShareType = 'V', Visibility = 'AllUsers')); }
			}
			if (!links.isEmpty()) { insert links; }
			actualizarComparativo(opportunityId);
			return docId;
		} catch (Exception e) {
			throw error('No se pudo generar el PDF del comparativo: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Resumen de las oportunidades para la lista de Crear Oportunidad: tamaño del grupo (asegurados del
	 *               censo o de las cotizaciones, unidades de la flotilla o ubicaciones) y cotizaciones cargadas.
	 * @param opportunityIds: oportunidades visibles en la lista.
	 * @return mapa Id de oportunidad -> {asegurados, unidades, ubicaciones, cotizaciones}.
	 */
	@AuraEnabled(cacheable=false)
	public static Map<Id, Map<String, Object>> getResumenOportunidades(List<Id> opportunityIds) {
		Map<Id, Map<String, Object>> res = new Map<Id, Map<String, Object>>();
		if (opportunityIds == null || opportunityIds.isEmpty()) { return res; }
		Set<Id> ids = new Set<Id>(opportunityIds);
		Map<Id, Integer> censo = new Map<Id, Integer>();
		Map<Id, Integer> asegCotizacion = new Map<Id, Integer>();
		for (Id i : ids) { res.put(i, new Map<String, Object>{ 'asegurados' => 0, 'unidades' => 0, 'ubicaciones' => 0, 'cotizaciones' => 0 }); }
		for (AggregateResult ar : [SELECT OpportunityId o, COUNT(Id) n FROM Quote WHERE OpportunityId IN :ids GROUP BY OpportunityId]) {
			res.get((Id) ar.get('o')).put('cotizaciones', (Integer) ar.get('n'));
		}
		// Censo (FSC): puede no estar disponible para el usuario; en ese caso se usa lo de las cotizaciones.
		try {
			for (AggregateResult ar : [
				SELECT GroupCensus.Oportunidad__c o, COUNT(Id) n FROM GroupCensusMember
				WHERE GroupCensus.Oportunidad__c IN :ids GROUP BY GroupCensus.Oportunidad__c
			]) { censo.put((Id) ar.get('o'), (Integer) ar.get('n')); }
		} catch (Exception e) {
			System.debug(LoggingLevel.WARN, 'Censo no disponible para el resumen: ' + e.getMessage());
		}
		for (AggregateResult ar : [
			SELECT Oportunidad__c o, Cotizacion__c q, COUNT(Id) n FROM Inciso_Flotilla__c
			WHERE Oportunidad__c IN :ids AND Cotizacion__c != null GROUP BY Oportunidad__c, Cotizacion__c
		]) {
			Map<String, Object> m = res.get((Id) ar.get('o'));
			m.put('unidades', Math.max((Integer) m.get('unidades'), (Integer) ar.get('n')));
		}
		for (AggregateResult ar : [
			SELECT Oportunidad__c o, Cotizacion__c q, COUNT(Id) n, SUM(Asegurados__c) a FROM Categoria_Colectiva__c
			WHERE Oportunidad__c IN :ids AND Cotizacion__c != null GROUP BY Oportunidad__c, Cotizacion__c
		]) {
			Id o = (Id) ar.get('o');
			Decimal a = (Decimal) ar.get('a');
			if (a != null && a > 0) {
				asegCotizacion.put(o, Math.max(asegCotizacion.containsKey(o) ? asegCotizacion.get(o) : 0, a.intValue()));
			} else {
				Map<String, Object> m = res.get(o);
				m.put('ubicaciones', Math.max((Integer) m.get('ubicaciones'), (Integer) ar.get('n')));
			}
		}
		for (Id o : ids) {
			Integer a = censo.containsKey(o) ? censo.get(o) : asegCotizacion.get(o);
			if (a != null) { res.get(o).put('asegurados', a); }
		}
		return res;
	}

	// ============================================================
	// Comparativo en la oportunidad (para el componente "Análisis IA")
	// ============================================================

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Guarda en la oportunidad el comparativo colectivo vigente (el mismo del PDF) para que "Análisis IA"
	 *               muestre exactamente lo mismo que Crear Oportunidad. Si ya no hay cotizaciones lo quita.
	 * @param opportunityId: oportunidad colectiva.
	 * @return void
	 */
	private static void actualizarComparativo(Id opportunityId) {
		guardarComparativoEnOportunidad(opportunityId, ColectivoComparativoPdfController.construirHtml(opportunityId));
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Escribe el comparativo (HTML del PDF adaptado a la página) en Opportunity.Descripcion__c. Sin
	 *               comparativo, borra solo uno colectivo / de flotilla anterior (no toca el de la IA de una individual).
	 *               Si no cabe en el campo se conserva el anterior. Nunca interrumpe el guardado de la cotización.
	 * @param opportunityId: oportunidad.
	 * @param html: HTML completo del comparativo ('' si no hay cotizaciones).
	 * @return void
	 */
	public static void guardarComparativoEnOportunidad(Id opportunityId, String html) {
		if (opportunityId == null) { return; }
		try {
			List<Opportunity> opps = [SELECT Id, Descripcion__c FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
			if (opps.isEmpty()) { return; }
			String fragmento = String.isBlank(html) ? null : aFragmento(html);
			// Si no cabe (ej. flotillas grandes), se quitan los detalles más pesados; el detalle completo queda en el PDF.
			Integer maximo = Opportunity.Descripcion__c.getDescribe().getLength();
			String recortado = html;
			for (String seccion : SECCIONES_DETALLE) {
				if (fragmento == null || fragmento.length() <= maximo) { break; }
				recortado = quitarSeccion(recortado, seccion);
				fragmento = aFragmento(recortado.replace('<h3>Resumen y recomendaci',
					'<p style="font-size:10px;color:#667;margin:8px 0;">El detalle completo (' + seccion.toLowerCase()
					+ ' y demás) está en el comparativo en PDF.</p><h3>Resumen y recomendaci'));
			}
			if (fragmento == null) {
				if (opps[0].Descripcion__c != null && opps[0].Descripcion__c.contains(MARCA_COMPARATIVO)) {
					update new Opportunity(Id = opportunityId, Descripcion__c = null);
				}
				return;
			}
			if (fragmento.length() > maximo) { return; }
			update new Opportunity(Id = opportunityId, Descripcion__c = fragmento);
		} catch (Exception e) {
			System.debug(LoggingLevel.WARN, 'No se pudo guardar el comparativo en la oportunidad: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Quita del HTML la sección con ese título (desde su <h3> hasta el siguiente <h3>).
	 * @param html: HTML del comparativo.
	 * @param titulo: título de la sección.
	 * @return HTML sin la sección (igual si no la tiene).
	 */
	@TestVisible
	private static String quitarSeccion(String html, String titulo) {
		Integer ini = html.indexOf('<h3>' + titulo + '</h3>');
		if (ini < 0) { return html; }
		Integer fin = html.indexOf('<h3>', ini + 4);
		return fin < 0 ? html.left(ini) : html.left(ini) + html.substring(fin);
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Convierte el HTML del PDF (documento con estilos por clase) en un fragmento con estilos en línea
	 *               que se puede mostrar dentro de una página de Lightning.
	 * @param html: documento HTML del comparativo.
	 * @return fragmento con la marca MARCA_COMPARATIVO.
	 */
	@TestVisible
	private static String aFragmento(String html) {
		String cuerpo = html;
		Integer ini = cuerpo.indexOf('<body>');
		Integer fin = cuerpo.lastIndexOf('</body>');
		if (ini >= 0 && fin > ini) { cuerpo = cuerpo.substring(ini + 6, fin); }
		String tabla = '<table style="width:100%;border-collapse:collapse;margin-bottom:10px;">';
		cuerpo = cuerpo.replace('<table class="resumen">', tabla).replace('<table>', tabla)
			.replace('<h2>', '<h2 style="font-size:18px;margin:0 0 4px;color:#1c2433;">')
			.replace('<h3>', '<h3 style="font-size:13px;margin:14px 0 6px;color:#1c2433;">');
		return MARCA_COMPARATIVO + '<div style="font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#1c2433;overflow-x:auto;">'
			+ cuerpo + '</div>';
	}

	/**
	 * @creation date: 28/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: true si la cuenta ya tiene una póliza del ramo: la oportunidad colectiva es una renovación aunque
	 *               las cotizaciones de las otras aseguradoras digan "Nueva".
	 * @param accountId: cuenta del cliente.
	 * @param ramo: valor del picklist Ramo (vacío = cualquier ramo).
	 * @return true si hay al menos una póliza.
	 */
	@AuraEnabled
	public static Boolean tienePolizaDelRamo(Id accountId, String ramo) {
		if (accountId == null) { return false; }
		if (String.isBlank(ramo)) {
			return [SELECT COUNT() FROM InsurancePolicy WHERE NameInsuredId = :accountId] > 0;
		}
		return [SELECT COUNT() FROM InsurancePolicy WHERE NameInsuredId = :accountId AND Ramo__c = :ramo] > 0;
	}

	// ============================================================
	// Helpers
	// ============================================================

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: true si en el ramo cada renglón de la cotización es una ubicación (Daños, Empresarial).
	 * @param ramo: valor del picklist Ramo.
	 * @return true para ramos de ubicaciones.
	 */
	public static Boolean esUbicaciones(String ramo) {
		return String.isNotBlank(ramo) && RAMOS_UBICACIONES.contains(ramo);
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Etiqueta legible del ramo (Danos -> Daños, Vision -> Visión).
	 * @param ramo: valor del picklist Ramo.
	 * @return etiqueta.
	 */
	public static String etiquetaRamo(String ramo) {
		if (ramo == 'Danos') { return 'Daños'; }
		if (ramo == 'Vision') { return 'Visión'; }
		if (ramo == 'Automoviles') { return 'Automóviles'; }
		return ramo;
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Producto de la aseguradora para el ramo (Family igual al ramo o equivalente, ej. GMM / Gastos Médicos Mayores).
	 * @param aseguradoraId: aseguradora.
	 * @param ramo: ramo de la oportunidad.
	 * @return Id de Product2 o null.
	 */
	private static Id productoRamo(Id aseguradoraId, String ramo) {
		Set<String> familias = new Set<String>{ ramo, etiquetaRamo(ramo) };
		if (ramo == 'GMM') { familias.add('Gastos Médicos Mayores'); }
		if (ramo == 'Accidentes Personales' || ramo == 'Vida') { familias.add('Personas'); }
		for (Product2 p : [
			SELECT Id FROM Product2 WHERE IsActive = true AND Aseguradora__c = :aseguradoraId AND Family IN :familias ORDER BY Name LIMIT 1
		]) { return p.Id; }
		return null;
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Lista desde un JSON guardado (formas de pago, tarifa por edad); vacía si no hay o no es válido.
	 * @param json: texto JSON.
	 * @return lista deserializada.
	 */
	private static List<Object> jsonLista(String json) {
		if (String.isBlank(json)) { return new List<Object>(); }
		try { return (List<Object>) System.JSON.deserializeUntyped(json); } catch (Exception e) { return new List<Object>(); }
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Lista de precios estándar (requerida por Quote).
	 * @return Id del Pricebook2 estándar.
	 */
	private static Id pricebookEstandar() {
		if (Test.isRunningTest()) { return Test.getStandardPricebookId(); }
		List<Pricebook2> l = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
		return l.isEmpty() ? null : l[0].Id;
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Frecuencia de prima del Quote a partir de la forma de pago (contado = anual).
	 * @param formaPago: texto.
	 * @return frecuencia.
	 */
	@TestVisible
	private static String frecuencia(String formaPago) {
		String v = formaPago == null ? '' : formaPago.toLowerCase();
		if (v.contains('mensual')) { return 'Mensual'; }
		if (v.contains('trimestr')) { return 'Trimestral'; }
		if (v.contains('semestr')) { return 'Semestral'; }
		return 'Anual';
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Valor del picklist si existe (activo); si no, el valor de respaldo.
	 * @param campo: campo picklist.
	 * @param valor: valor deseado.
	 * @param respaldo: valor si el deseado no existe.
	 * @return valor válido o respaldo.
	 */
	private static String valorPicklist(Schema.SObjectField campo, String valor, String respaldo) {
		for (Schema.PicklistEntry pe : campo.getDescribe().getPicklistValues()) {
			if (pe.isActive() && pe.getValue() == valor) { return valor; }
		}
		return respaldo;
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cero cuando el monto viene vacío.
	 * @param v: monto.
	 * @return el monto o 0.
	 */
	private static Decimal nz(Decimal v) {
		return v == null ? 0 : v;
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Convierte "YYYY-MM-DD" a Date; null si viene vacío o no es válida.
	 * @param s: fecha ISO.
	 * @return Date o null.
	 */
	@TestVisible
	private static Date fecha(String s) {
		if (String.isBlank(s)) { return null; }
		try { return Date.valueOf(s.trim().left(10)); } catch (Exception e) { return null; }
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Asigna un texto recortado a la longitud del campo.
	 * @param so: registro.
	 * @param campo: API name del campo de texto.
	 * @param valor: texto (vacío = no se asigna).
	 * @return void.
	 */
	private static void setTexto(SObject so, String campo, String valor) {
		if (String.isBlank(valor)) { return; }
		Integer largo = so.getSObjectType().getDescribe().fields.getMap().get(campo).getDescribe().getLength();
		String v = valor.normalizeSpace();
		so.put(campo, largo > 0 && v.length() > largo ? v.left(largo) : v);
	}

	/**
	 * @creation date: 14/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Limpia la respuesta de la IA: recorta del primer "{" al último "}".
	 * @param raw: texto devuelto por el modelo.
	 * @return JSON limpio.
	 */
	@TestVisible
	private static String limpiarJson(String raw) {
		if (String.isBlank(raw)) { return '{"categorias":[]}'; }
		Integer ini = raw.indexOf('{');
		Integer fin = raw.lastIndexOf('}');
		return (ini >= 0 && fin > ini) ? raw.substring(ini, fin + 1) : '{"categorias":[]}';
	}

	/**
	 * @creation date: 14/10/2026
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
}
