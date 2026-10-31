/**
 * @creation date: 30/10/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Censo de vehículos de una oportunidad COLECTIVA de Automóviles (flotilla). Cada vehículo es un
 *               Inciso_Flotilla__c de la oportunidad sin cotización (Cotizacion__c vacío). El archivo (Excel, CSV o PDF
 *               con IA) se lee en el LWC censoVehiculos. Al cargar la póliza (PolicyController) los incisos del censo
 *               con la misma serie se ligan a la póliza y a su vehículo del cliente en vez de duplicarse; los que ya
 *               están en una póliza no se modifican ni se borran desde el censo.
 */
public with sharing class CensoVehiculosController {

	@TestVisible private static final Integer MAX_VEHICULOS = 3000;
	// Vehículos que se regresan al LWC para la tabla (el resumen sí cuenta a todos).
	private static final Integer MAX_VEHICULOS_VISTA = 2000;
	private static final String SIN_TIPO = 'Sin tipo';

	/**
	 * @creation date: 30/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Censo de vehículos de la oportunidad: totales, resumen por tipo de vehículo y la lista.
	 * @param opportunityId: oportunidad colectiva de Auto
	 * @return {total, enPoliza, valorTotal, primaTotal, tipos[{tipo, vehiculos, valor, prima}], incisos[...]}
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> getCensoVehiculos(Id opportunityId) {
		Integer total = 0;
		Integer enPoliza = 0;
		Decimal valorTotal = 0;
		Decimal primaTotal = 0;
		Map<String, Map<String, Object>> tipos = new Map<String, Map<String, Object>>();
		List<Map<String, Object>> incisos = new List<Map<String, Object>>();
		for (Inciso_Flotilla__c i : [
			SELECT Id, Name, Numero_Inciso__c, Serie__c, Placas__c, Descripcion__c, Modelo__c, Tipo_Vehiculo__c, Uso__c,
				Paquete__c, Valor__c, Prima__c, Poliza__c, Poliza__r.Name, Vehiculo__c
			FROM Inciso_Flotilla__c
			WHERE Oportunidad__c = :opportunityId AND Cotizacion__c = null
			ORDER BY Numero_Inciso__c ASC NULLS LAST, Name ASC
			LIMIT :MAX_VEHICULOS
		]) {
			total++;
			if (i.Poliza__c != null) { enPoliza++; }
			valorTotal += nz(i.Valor__c);
			primaTotal += nz(i.Prima__c);
			String tipo = String.isBlank(i.Tipo_Vehiculo__c) ? SIN_TIPO : i.Tipo_Vehiculo__c;
			Map<String, Object> t = tipos.get(tipo);
			if (t == null) {
				t = new Map<String, Object>{ 'tipo' => tipo, 'vehiculos' => 0, 'valor' => 0, 'prima' => 0 };
				tipos.put(tipo, t);
			}
			t.put('vehiculos', (Integer) t.get('vehiculos') + 1);
			t.put('valor', (Decimal) t.get('valor') + nz(i.Valor__c));
			t.put('prima', (Decimal) t.get('prima') + nz(i.Prima__c));
			if (incisos.size() < MAX_VEHICULOS_VISTA) {
				incisos.add(new Map<String, Object>{
					'id' => i.Id, 'nombre' => i.Name, 'inciso' => i.Numero_Inciso__c, 'serie' => i.Serie__c,
					'placas' => i.Placas__c, 'descripcion' => i.Descripcion__c, 'modelo' => i.Modelo__c,
					'tipoVehiculo' => i.Tipo_Vehiculo__c, 'uso' => i.Uso__c, 'paquete' => i.Paquete__c,
					'valor' => i.Valor__c, 'prima' => i.Prima__c, 'polizaId' => i.Poliza__c,
					'poliza' => i.Poliza__r == null ? null : i.Poliza__r.Name, 'vehiculoId' => i.Vehiculo__c
				});
			}
		}
		return new Map<String, Object>{
			'total' => total, 'enPoliza' => enPoliza, 'valorTotal' => valorTotal, 'primaTotal' => primaTotal,
			'tipos' => tipos.values(), 'incisos' => incisos
		};
	}

	/**
	 * @creation date: 30/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Guarda el censo de vehículos. Al reemplazar se borran los vehículos del censo que aún no están
	 *               en una póliza. Un vehículo con la misma serie que otro del censo lo actualiza (si ya está en una
	 *               póliza se deja como está). Todo o nada.
	 * @param opportunityId: oportunidad colectiva de Auto
	 * @param incisosJson: lista de FlotillaController.IncisoEntrada ya normalizada en el navegador
	 * @param reemplazar: true para reemplazar el censo actual, false para agregar
	 * @return Número de vehículos del censo después de guardar
	 */
	@AuraEnabled(cacheable=false)
	public static Integer guardarCensoVehiculos(Id opportunityId, String incisosJson, Boolean reemplazar) {
		List<FlotillaController.IncisoEntrada> entrada;
		try {
			entrada = (List<FlotillaController.IncisoEntrada>) JSON.deserialize(
				String.isBlank(incisosJson) ? '[]' : incisosJson, List<FlotillaController.IncisoEntrada>.class);
		} catch (Exception e) {
			throw error('El censo no tiene un formato válido: ' + e.getMessage());
		}
		if (entrada.isEmpty()) { throw error('El censo no tiene vehículos.'); }
		if (entrada.size() > MAX_VEHICULOS) {
			throw error('El censo tiene ' + entrada.size() + ' vehículos; el máximo por carga es ' + MAX_VEHICULOS + '.');
		}
		if ([SELECT COUNT() FROM Opportunity WHERE Id = :opportunityId] == 0) { throw error('No se encontró la oportunidad.'); }

		Savepoint sp = Database.setSavepoint();
		try {
			if (reemplazar == true) {
				delete [
					SELECT Id FROM Inciso_Flotilla__c
					WHERE Oportunidad__c = :opportunityId AND Cotizacion__c = null AND Poliza__c = null
				];
			}
			Map<String, Inciso_Flotilla__c> porSerie = new Map<String, Inciso_Flotilla__c>();
			for (Inciso_Flotilla__c i : [
				SELECT Id, Serie__c, Poliza__c FROM Inciso_Flotilla__c
				WHERE Oportunidad__c = :opportunityId AND Cotizacion__c = null AND Serie__c != null
				ORDER BY CreatedDate ASC
			]) {
				String k = i.Serie__c.toUpperCase();
				if (!porSerie.containsKey(k)) { porSerie.put(k, i); }
			}
			Map<String, Inciso_Flotilla__c> guardar = new Map<String, Inciso_Flotilla__c>();
			List<Inciso_Flotilla__c> sinSerie = new List<Inciso_Flotilla__c>();
			for (FlotillaController.IncisoEntrada e : entrada) {
				String serie = String.isBlank(e.serie) ? null : e.serie.deleteWhitespace().toUpperCase();
				if (serie == null && String.isBlank(e.descripcion)) { continue; }
				Inciso_Flotilla__c ya = serie == null ? null : porSerie.get(serie);
				// Los vehículos que ya están en una póliza conservan los datos de la póliza.
				if (ya != null && ya.Poliza__c != null) { continue; }
				Inciso_Flotilla__c inc = ya != null ? new Inciso_Flotilla__c(Id = ya.Id)
					: new Inciso_Flotilla__c(Oportunidad__c = opportunityId);
				llenar(inc, e, serie);
				if (serie == null) { sinSerie.add(inc); } else { guardar.put(serie, inc); }
			}
			List<Inciso_Flotilla__c> todos = new List<Inciso_Flotilla__c>(guardar.values());
			todos.addAll(sinSerie);
			upsert todos;
		} catch (AuraHandledException ahe) {
			Database.rollback(sp);
			throw ahe;
		} catch (Exception e) {
			Database.rollback(sp);
			throw error('No se pudo guardar el censo de vehículos: ' + e.getMessage());
		}
		return [SELECT COUNT() FROM Inciso_Flotilla__c WHERE Oportunidad__c = :opportunityId AND Cotizacion__c = null];
	}

	/**
	 * @creation date: 30/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Elimina los vehículos del censo que no están en una póliza (los de la póliza se conservan).
	 * @param opportunityId: oportunidad colectiva de Auto
	 * @return Número de vehículos que quedan (los que están en una póliza)
	 */
	@AuraEnabled(cacheable=false)
	public static Integer eliminarCensoVehiculos(Id opportunityId) {
		try {
			delete [
				SELECT Id FROM Inciso_Flotilla__c
				WHERE Oportunidad__c = :opportunityId AND Cotizacion__c = null AND Poliza__c = null
			];
		} catch (Exception e) {
			throw error('No se pudo eliminar el censo de vehículos: ' + e.getMessage());
		}
		return [SELECT COUNT() FROM Inciso_Flotilla__c WHERE Oportunidad__c = :opportunityId AND Cotizacion__c = null];
	}

	/**
	 * @creation date: 30/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Pasa los datos del vehículo al inciso (respetando el largo de cada campo).
	 * @param inc: inciso nuevo o existente
	 * @param e: vehículo leído del archivo
	 * @param serie: serie normalizada (puede ser null)
	 * @return void
	 */
	private static void llenar(Inciso_Flotilla__c inc, FlotillaController.IncisoEntrada e, String serie) {
		inc.Numero_Inciso__c = e.inciso;
		inc.Serie__c = serie == null ? null : serie.left(30);
		inc.Clave_Vehicular__c = corto(e.claveVehicular, 30);
		inc.Descripcion__c = corto(e.descripcion, 255);
		inc.Modelo__c = e.modelo != null && e.modelo >= 1900 && e.modelo <= 2100 ? e.modelo : null;
		inc.Placas__c = corto(e.placas, 20);
		inc.Uso__c = corto(e.uso, 60);
		inc.Tipo_Vehiculo__c = corto(e.tipoVehiculo, 80);
		inc.Paquete__c = corto(e.paquete, 60);
		inc.Tipo_Valor__c = corto(e.tipoValor, 40);
		inc.Valor__c = e.valor;
		inc.Deducible_DM__c = porcentaje(e.dedDM);
		inc.Deducible_RT__c = porcentaje(e.dedRT);
		inc.Responsabilidad_Civil__c = e.rc;
		inc.Gastos_Medicos__c = e.gm;
		inc.Muerte_Conductor__c = e.muerte;
		inc.Prima_Neta__c = e.primaNeta;
		inc.Prima__c = e.prima;
	}

	/**
	 * @creation date: 30/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Texto sin espacios a los lados y cortado al largo del campo (vacío = null).
	 * @param v: texto
	 * @param largo: largo máximo
	 * @return texto o null
	 */
	private static String corto(String v, Integer largo) {
		return String.isBlank(v) ? null : v.trim().left(largo);
	}

	/**
	 * @creation date: 30/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Un deducible fuera de 0-100 no es un porcentaje (p. ej. un monto en pesos): no se guarda.
	 * @param v: deducible leído
	 * @return porcentaje o null
	 */
	private static Decimal porcentaje(Decimal v) {
		return v == null || v < 0 || v > 100 ? null : v;
	}

	/**
	 * @creation date: 30/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Cero si el valor es null.
	 * @param v: número
	 * @return número o 0
	 */
	private static Decimal nz(Decimal v) {
		return v == null ? 0 : v;
	}

	/**
	 * @creation date: 30/10/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Error con mensaje legible en el LWC.
	 * @param msg: mensaje
	 * @return AuraHandledException
	 */
	private static AuraHandledException error(String msg) {
		AuraHandledException e = new AuraHandledException(msg);
		e.setMessage(msg);
		return e;
	}
}
