/**
 * @creation date: 16/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Datos del panel de Oportunidades (lwc oportunidadesPanel) para usuarios internos.
 *   Oportunidades: abiertas y las modificadas en los últimos 90 días, con su prima, ramo, tipo de contratación
 *   (Individual / Colectiva), tipo de venta, canal, fecha de cierre, propietario y número de cotizaciones.
 *   Gamificación con datos reales: una póliza "emitida" es una InsurancePolicy creada desde una oportunidad
 *   (SourceOpportunityId informado) que no está cancelada; el agente es el propietario de esa oportunidad.
 *   Con esas pólizas se calculan el ranking del mes, la meta del mes del usuario, su racha de días emitiendo
 *   y el logro "Rey de Autos" (más pólizas de autos en la semana).
 *   Respeta las reglas de compartición del usuario (with sharing).
 */
public with sharing class OportunidadesPanelController {

	/** Máximo de oportunidades que se envían al panel. */
	static final Integer LIMITE_OPORTUNIDADES = 500;
	/** Máximo de pólizas que se leen para la gamificación. */
	static final Integer LIMITE_POLIZAS = 5000;
	/** Días hacia atrás que se revisan para la racha. */
	static final Integer DIAS_RACHA = 60;
	/** Días hacia atrás para incluir oportunidades cerradas recientes. */
	static final Integer DIAS_RECIENTES = 90;
	/** Máximo de agentes en el ranking. */
	static final Integer LIMITE_RANKING = 10;
	static final String ESTADO_CANCELADO = 'Cancelado';

	public class Oportunidad {
		@AuraEnabled public Id id;
		@AuraEnabled public String nombre;
		@AuraEnabled public String cuenta;
		@AuraEnabled public String ramo;
		@AuraEnabled public String etapa;
		@AuraEnabled public Decimal prima;
		@AuraEnabled public String tipoContratacion;
		@AuraEnabled public String tipoVenta;
		@AuraEnabled public String canal;
		@AuraEnabled public Date fechaCierre;
		@AuraEnabled public Id propietarioId;
		@AuraEnabled public String propietario;
		@AuraEnabled public String agente;
		@AuraEnabled public Integer cotizaciones;
		@AuraEnabled public Datetime creada;
	}

	public class Agente {
		@AuraEnabled public Id usuarioId;
		@AuraEnabled public String nombre;
		@AuraEnabled public Integer polizasMes = 0;
		@AuraEnabled public Integer autosSemana = 0;
		@AuraEnabled public Boolean esUsuarioActual = false;
	}

	public class Panel {
		@AuraEnabled public Id usuarioId;
		@AuraEnabled public String nombreUsuario;
		@AuraEnabled public Date hoy;
		@AuraEnabled public List<Oportunidad> oportunidades = new List<Oportunidad>();
		@AuraEnabled public List<Agente> ranking = new List<Agente>();
		@AuraEnabled public Agente reyAutos;
		@AuraEnabled public Integer polizasMesUsuario = 0;
		@AuraEnabled public Integer polizasHoyUsuario = 0;
		@AuraEnabled public Integer rachaDias = 0;
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Arma todos los datos del panel: oportunidades, ranking del mes, meta, racha y Rey de Autos.
	 * @return Panel
	 */
	@AuraEnabled(cacheable=false)
	public static Panel obtenerPanel() {
		try {
			Panel p = new Panel();
			p.usuarioId = UserInfo.getUserId();
			p.nombreUsuario = String.isNotBlank(UserInfo.getFirstName()) ? UserInfo.getFirstName() : UserInfo.getName();
			p.hoy = Date.today();
			p.oportunidades = cargarOportunidades();
			calcularGamificacion(p);
			return p;
		} catch (Exception e) {
			throw new AuraHandledException('No se pudo cargar el panel de oportunidades: ' + e.getMessage());
		}
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Oportunidades abiertas y las modificadas en los últimos 90 días (por fecha de cierre),
	 *   con la prima (Prima_neta__c, si no Prima_Total__c, si no Amount; el cero cuenta como vacío) y el número de cotizaciones.
	 * @return Lista de oportunidades del panel
	 */
	static List<Oportunidad> cargarOportunidades() {
		Datetime desde = Datetime.now().addDays(-DIAS_RECIENTES);
		List<Opportunity> opps = [
			SELECT Id, Name, StageName, CloseDate, Amount, Prima_Total__c, Prima_neta__c, Type, Canal__c,
				Ramo__c, Tipo_Contratacion__c, OwnerId, Owner.Name, Producer__r.Name, Account.Name, CreatedDate
			FROM Opportunity
			WHERE IsClosed = false OR LastModifiedDate >= :desde
			ORDER BY CloseDate ASC NULLS LAST
			LIMIT :LIMITE_OPORTUNIDADES
		];
		Map<Id, Integer> cotizaciones = contarCotizaciones(opps);
		List<Oportunidad> res = new List<Oportunidad>();
		for (Opportunity o : opps) {
			Oportunidad r = new Oportunidad();
			r.id = o.Id;
			r.nombre = o.Name;
			r.cuenta = o.Account != null ? o.Account.Name : null;
			r.ramo = o.Ramo__c;
			r.etapa = o.StageName;
			r.prima = primaDe(o);
			r.tipoContratacion = String.isNotBlank(o.Tipo_Contratacion__c) ? o.Tipo_Contratacion__c : 'Individual';
			r.tipoVenta = o.Type;
			r.canal = o.Canal__c;
			r.fechaCierre = o.CloseDate;
			r.propietarioId = o.OwnerId;
			r.propietario = o.Owner != null ? o.Owner.Name : null;
			r.agente = o.Producer__r != null ? o.Producer__r.Name : null;
			r.cotizaciones = cotizaciones.containsKey(o.Id) ? cotizaciones.get(o.Id) : 0;
			r.creada = o.CreatedDate;
			res.add(r);
		}
		return res;
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Prima de la oportunidad: la prima neta; si viene vacía o en cero, la prima total; si no, Amount.
	 * @param o: Oportunidad
	 * @return Prima a mostrar (puede ser null)
	 */
	@TestVisible
	static Decimal primaDe(Opportunity o) {
		if (o.Prima_neta__c != null && o.Prima_neta__c != 0) {
			return o.Prima_neta__c;
		}
		if (o.Prima_Total__c != null && o.Prima_Total__c != 0) {
			return o.Prima_Total__c;
		}
		return o.Amount;
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cuenta las cotizaciones (Quote) de cada oportunidad.
	 * @param opps: Oportunidades del panel
	 * @return Mapa Id de oportunidad → número de cotizaciones
	 */
	static Map<Id, Integer> contarCotizaciones(List<Opportunity> opps) {
		Map<Id, Integer> res = new Map<Id, Integer>();
		if (opps.isEmpty()) {
			return res;
		}
		Set<Id> ids = new Map<Id, Opportunity>(opps).keySet();
		for (AggregateResult ar : [
			SELECT OpportunityId oppId, COUNT(Id) n
			FROM Quote
			WHERE OpportunityId IN :ids
			GROUP BY OpportunityId
		]) {
			res.put((Id) ar.get('oppId'), (Integer) ar.get('n'));
		}
		return res;
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Calcula ranking del mes, pólizas del mes y de hoy del usuario, racha y Rey de Autos a partir
	 *   de las pólizas emitidas desde oportunidades (no canceladas). La fecha de emisión es la de creación de la póliza.
	 * @param p: Panel a completar
	 * @return void
	 */
	static void calcularGamificacion(Panel p) {
		Date hoy = p.hoy;
		Date inicioMes = hoy.toStartOfMonth();
		Date inicioSemana = hoy.toStartOfWeek();
		Date inicioRacha = hoy.addDays(-DIAS_RACHA);
		Date desde = inicioMes;
		if (inicioSemana < desde) {
			desde = inicioSemana;
		}
		if (inicioRacha < desde) {
			desde = inicioRacha;
		}
		Datetime desdeDt = Datetime.newInstance(desde, Time.newInstance(0, 0, 0, 0));

		Map<Id, Agente> agentes = new Map<Id, Agente>();
		Set<Date> diasUsuario = new Set<Date>();
		for (InsurancePolicy pol : [
			SELECT Id, CreatedDate, Ramo__c, SourceOpportunity.OwnerId, SourceOpportunity.Owner.Name,
				SourceOpportunity.Ramo__c
			FROM InsurancePolicy
			WHERE SourceOpportunityId != null AND (Status = null OR Status != :ESTADO_CANCELADO)
				AND CreatedDate >= :desdeDt
			ORDER BY CreatedDate DESC
			LIMIT :LIMITE_POLIZAS
		]) {
			if (pol.SourceOpportunity == null || pol.SourceOpportunity.OwnerId == null) {
				continue;
			}
			Id ownerId = pol.SourceOpportunity.OwnerId;
			Date dia = pol.CreatedDate.date();
			if (ownerId == p.usuarioId) {
				diasUsuario.add(dia);
				if (dia == hoy) {
					p.polizasHoyUsuario++;
				}
			}
			Boolean enMes = dia >= inicioMes;
			Boolean enSemana = dia >= inicioSemana;
			if (!enMes && !enSemana) {
				continue;
			}
			Agente a = agentes.get(ownerId);
			if (a == null) {
				a = new Agente();
				a.usuarioId = ownerId;
				a.nombre = pol.SourceOpportunity.Owner != null ? pol.SourceOpportunity.Owner.Name : null;
				a.esUsuarioActual = ownerId == p.usuarioId;
				agentes.put(ownerId, a);
			}
			if (enMes) {
				a.polizasMes++;
			}
			String ramo = String.isNotBlank(pol.Ramo__c) ? pol.Ramo__c : pol.SourceOpportunity.Ramo__c;
			if (enSemana && esAutos(ramo)) {
				a.autosSemana++;
			}
		}

		if (agentes.containsKey(p.usuarioId)) {
			p.polizasMesUsuario = agentes.get(p.usuarioId).polizasMes;
		}
		p.rachaDias = calcularRacha(diasUsuario, hoy);
		p.ranking = ordenarRanking(agentes.values());
		for (Agente a : agentes.values()) {
			if (a.autosSemana > 0 && (p.reyAutos == null || a.autosSemana > p.reyAutos.autosSemana)) {
				p.reyAutos = a;
			}
		}
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Días consecutivos con al menos una póliza emitida. Cuenta desde hoy; si hoy todavía no hay
	 *   emisión, la racha sigue viva y se cuenta desde ayer.
	 * @param dias: Días en que el usuario emitió
	 * @param hoy: Fecha de hoy
	 * @return Número de días de la racha
	 */
	@TestVisible
	static Integer calcularRacha(Set<Date> dias, Date hoy) {
		Date d = dias.contains(hoy) ? hoy : hoy.addDays(-1);
		Integer racha = 0;
		while (dias.contains(d) && racha <= DIAS_RACHA) {
			racha++;
			d = d.addDays(-1);
		}
		return racha;
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Indica si el ramo es de autos (Automoviles, Autos, Automóvil...).
	 * @param ramo: Valor del ramo
	 * @return true si es autos
	 */
	@TestVisible
	static Boolean esAutos(String ramo) {
		return String.isNotBlank(ramo) && ramo.toLowerCase().startsWith('auto');
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Ordena los agentes con pólizas en el mes de mayor a menor (empate: por nombre) y deja los primeros 10.
	 * @param lista: Agentes con pólizas en el periodo
	 * @return Ranking del mes
	 */
	static List<Agente> ordenarRanking(List<Agente> lista) {
		List<Agente> pendientes = new List<Agente>();
		for (Agente a : lista) {
			if (a.polizasMes > 0) {
				pendientes.add(a);
			}
		}
		List<Agente> res = new List<Agente>();
		while (!pendientes.isEmpty() && res.size() < LIMITE_RANKING) {
			Integer mejor = 0;
			for (Integer i = 1; i < pendientes.size(); i++) {
				Agente a = pendientes[i];
				Agente b = pendientes[mejor];
				if (a.polizasMes > b.polizasMes
						|| (a.polizasMes == b.polizasMes && (a.nombre == null ? '' : a.nombre) < (b.nombre == null ? '' : b.nombre))) {
					mejor = i;
				}
			}
			res.add(pendientes.remove(mejor));
		}
		return res;
	}
}
