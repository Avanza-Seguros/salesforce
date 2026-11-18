/**
 * @creation date: 14/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pestañas del detalle de póliza en el sitio Avanza Seguro (componente portalPolizas), las mismas
 *   que la página de la póliza en Salesforce: Información, Pagos, Vigencias, Asegurados / Vehículos / Ubicaciones
 *   y Participantes. Son de solo lectura y muestran solo lo que le sirve al cliente (sin datos internos de
 *   sincronización con la aseguradora ni de cobranza interna).
 *   Cada método valida primero, con PortalPolizasController.validarAcceso, que la póliza sea del usuario del
 *   sitio (o de la cuenta elegida en vista previa); por eso la clase no depende de la compartición del sitio.
 */
public without sharing class PortalPolizasPestanas {

	/** Cuotas que ya no se deben: no suman en los totales. */
	static final Set<String> ESTADOS_CERRADOS = new Set<String>{ 'Cancelado', 'Condonado' };
	/** La emisión original llega como endoso vacío o en ceros ("0", "000000"). */
	static final Pattern ENDOSO_EMISION = Pattern.compile('^0+$');
	/** Tope de vigencias encadenadas (evita un bucle si un enlace quedara circular). */
	static final Integer MAX_NIVELES = 30;

	// ---------------------------------------------------------------- Información

	public class Campo {
		@AuraEnabled public String etiqueta;
		/** texto | moneda | fecha | numero */
		@AuraEnabled public String tipo;
		@AuraEnabled public String texto;
		@AuraEnabled public Decimal numero;
		@AuraEnabled public Date fecha;
		@AuraEnabled public Boolean ancho = false;
	}

	public class Seccion {
		@AuraEnabled public String titulo;
		@AuraEnabled public List<Campo> campos = new List<Campo>();
	}

	public class Informacion {
		@AuraEnabled public String moneda;
		@AuraEnabled public List<Seccion> secciones = new List<Seccion>();
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Pestaña Información Póliza: datos de la póliza, prima, vigencia y renovación y estado de pago.
	 * @param policyId: Id de la póliza
	 * @param cuentaVistaPrevia: Cuenta a simular (solo vista previa de administrador); null para el usuario real
	 * @return Secciones con sus campos (solo los que tienen valor)
	 */
	@AuraEnabled(cacheable=true)
	public static Informacion informacion(Id policyId, Id cuentaVistaPrevia) {
		try {
			Map<Id, String> roles = PortalPolizasController.validarAcceso(policyId, cuentaVistaPrevia);
			InsurancePolicy p = [
				SELECT Name, Aseguradora__r.Name, toLabel(Ramo__c), Product.Name, NameInsured.Name, toLabel(Status),
					EffectiveDate, ExpirationDate, CancellationDate, CancellationReason, insuredAssetDescription__c,
					PremiumAmount, toLabel(PremiumFrequency), Numero_Pagos__c, Primer_Pago__c, Pago_Subsecuente__c,
					Pagos_Subsecuentes__c, Subtotal__c, Derecho_Poliza__c, Financiamiento__c, IVA__c, Descuento__c,
					Moneda__c, SaleDate, PriorPolicy.Name, RenewedFromPolicy.Name, ReferencePolicyNumber, termPeriod__c,
					toLabel(collectionPaymentStatus__c), collectionNextDueDate__c, PaidToDate, totalRefundedAmount__c
				FROM InsurancePolicy WHERE Id = :policyId LIMIT 1
			];
			Informacion info = new Informacion();
			info.moneda = String.isBlank(p.Moneda__c) ? 'MXN' : p.Moneda__c;

			Seccion datos = seccion(info, 'Detalles de la póliza');
			texto(datos, 'Número de póliza', p.Name);
			texto(datos, 'Aseguradora', p.Aseguradora__r?.Name);
			texto(datos, 'Ramo', p.Ramo__c);
			texto(datos, 'Producto', p.Product?.Name);
			texto(datos, 'Titular', p.NameInsured?.Name);
			texto(datos, 'Tu participación', roles.get(policyId));
			texto(datos, 'Estado', p.Status);
			fecha(datos, 'Inicio de vigencia', p.EffectiveDate);
			fecha(datos, 'Fin de vigencia', p.ExpirationDate);
			fecha(datos, 'Fecha de cancelación', p.CancellationDate);
			Campo motivo = texto(datos, 'Motivo de cancelación', p.CancellationReason);
			if (motivo != null) { motivo.ancho = true; }
			Campo bien = texto(datos, 'Bien asegurado', p.insuredAssetDescription__c);
			if (bien != null) { bien.ancho = true; }

			Seccion prima = seccion(info, 'Información de prima');
			moneda(prima, 'Prima total', p.PremiumAmount);
			texto(prima, 'Forma de pago', p.PremiumFrequency);
			numero(prima, 'Número de pagos', p.Numero_Pagos__c);
			moneda(prima, 'Primer pago', p.Primer_Pago__c);
			moneda(prima, 'Pago subsecuente', p.Pago_Subsecuente__c);
			numero(prima, 'Pagos subsecuentes', p.Pagos_Subsecuentes__c);
			moneda(prima, 'Prima neta', p.Subtotal__c);
			moneda(prima, 'Derecho de póliza', p.Derecho_Poliza__c);
			moneda(prima, 'Financiamiento', p.Financiamiento__c);
			moneda(prima, 'Descuento', p.Descuento__c);
			moneda(prima, 'IVA', p.IVA__c);
			texto(prima, 'Moneda', info.moneda);

			Seccion renov = seccion(info, 'Vigencia y renovación');
			texto(renov, 'Vigencia', p.termPeriod__c);
			fecha(renov, 'Fecha de venta', p.SaleDate);
			texto(renov, 'Póliza anterior', p.PriorPolicy?.Name);
			texto(renov, 'Renovación de', p.RenewedFromPolicy?.Name);
			texto(renov, 'Número de referencia', p.ReferencePolicyNumber);

			Seccion cobranza = seccion(info, 'Estado de pago');
			texto(cobranza, 'Estado de pago', p.collectionPaymentStatus__c);
			fecha(cobranza, 'Próximo pago', p.collectionNextDueDate__c);
			fecha(cobranza, 'Pagado hasta', p.PaidToDate);
			moneda(cobranza, 'Total devuelto', p.totalRefundedAmount__c);

			// No se muestran secciones vacías.
			List<Seccion> conDatos = new List<Seccion>();
			for (Seccion s : info.secciones) {
				if (!s.campos.isEmpty()) { conDatos.add(s); }
			}
			info.secciones = conDatos;
			return info;
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			throw PortalPolizasController.errorSitio(e);
		}
	}

	// ---------------------------------------------------------------- Pagos

	public class Cuota {
		@AuraEnabled public Id id;
		@AuraEnabled public String etiqueta;
		@AuraEnabled public String recibo;
		@AuraEnabled public Date vence;
		@AuraEnabled public Date fechaPago;
		@AuraEnabled public Decimal importe;
		@AuraEnabled public Decimal pagado;
		@AuraEnabled public Decimal pendiente;
		@AuraEnabled public String estado;
		@AuraEnabled public Integer diasMora;
		@AuraEnabled public Boolean estimada = false;
		@AuraEnabled public Integer recibosReemplazados = 0;
	}

	public class Pagos {
		@AuraEnabled public String moneda;
		@AuraEnabled public List<Cuota> cuotas = new List<Cuota>();
		@AuraEnabled public Decimal totalImporte = 0;
		@AuraEnabled public Decimal totalPagado = 0;
		@AuraEnabled public Decimal totalPendiente = 0;
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Pestaña Pagos: una fila por cuota vigente (las que reemplazó un recibo nuevo de la aseguradora
	 * se cuentan pero no se listan), con los totales de lo que se debe. Misma regla que policyInstallments.
	 * @param policyId: Id de la póliza
	 * @param cuentaVistaPrevia: Cuenta a simular (solo vista previa de administrador); null para el usuario real
	 * @return Cuotas y totales
	 */
	@AuraEnabled(cacheable=true)
	public static Pagos pagos(Id policyId, Id cuentaVistaPrevia) {
		try {
			PortalPolizasController.validarAcceso(policyId, cuentaVistaPrevia);
			Pagos salida = new Pagos();
			String moneda = [SELECT Moneda__c FROM InsurancePolicy WHERE Id = :policyId LIMIT 1].Moneda__c;
			salida.moneda = String.isBlank(moneda) ? 'MXN' : moneda;

			List<PaymentPlanInstallment__c> todas = [
				SELECT Id, Name, sequenceNumber__c, dueDate__c, expectedAmount__c, matchedAmount__c, outstandingAmount__c,
					toLabel(installmentStatus__c) estadoEtiqueta, installmentStatus__c, daysOverdue__c,
					carrierReceiptNumber__c, carrierEndorsementNumber__c, carrierInstallmentNumber__c, isEstimated__c,
					replacesInstallment__c, matchedReceipt__r.receiptDate__c
				FROM PaymentPlanInstallment__c
				WHERE paymentPlan__r.insurancePolicy__c = :policyId
				ORDER BY dueDate__c ASC NULLS LAST, sequenceNumber__c ASC
				LIMIT 2000
			];
			Map<Id, PaymentPlanInstallment__c> porId = new Map<Id, PaymentPlanInstallment__c>(todas);
			Set<Id> reemplazadas = new Set<Id>();
			for (PaymentPlanInstallment__c c : todas) {
				if (c.replacesInstallment__c != null) { reemplazadas.add(c.replacesInstallment__c); }
			}
			for (PaymentPlanInstallment__c viva : todas) {
				if (reemplazadas.contains(viva.Id)) { continue; }
				// El número de cuota de la aseguradora es el de la emisión original de la cadena.
				PaymentPlanInstallment__c origen = viva;
				Integer reemplazos = 0;
				Set<Id> vistos = new Set<Id>{ viva.Id };
				while (origen.replacesInstallment__c != null && porId.containsKey(origen.replacesInstallment__c)
						&& !vistos.contains(origen.replacesInstallment__c)) {
					origen = porId.get(origen.replacesInstallment__c);
					vistos.add(origen.Id);
					reemplazos++;
				}
				Cuota q = new Cuota();
				q.id = viva.Id;
				q.etiqueta = etiquetaCuota(origen, viva);
				q.estimada = viva.isEstimated__c == true;
				q.recibo = String.isNotBlank(viva.carrierReceiptNumber__c) ? viva.carrierReceiptNumber__c
					: (q.estimada ? 'Sin recibo aún' : null);
				q.vence = viva.dueDate__c;
				q.fechaPago = viva.matchedReceipt__r?.receiptDate__c;
				q.importe = viva.expectedAmount__c;
				q.pagado = viva.matchedAmount__c;
				q.pendiente = viva.outstandingAmount__c;
				q.estado = (String) viva.get('estadoEtiqueta');
				q.diasMora = viva.daysOverdue__c != null && viva.daysOverdue__c > 0 ? viva.daysOverdue__c.intValue() : null;
				q.recibosReemplazados = reemplazos;
				salida.cuotas.add(q);
				if (!ESTADOS_CERRADOS.contains(viva.installmentStatus__c)) {
					salida.totalImporte += viva.expectedAmount__c == null ? 0 : viva.expectedAmount__c;
					salida.totalPagado += viva.matchedAmount__c == null ? 0 : viva.matchedAmount__c;
					salida.totalPendiente += viva.outstandingAmount__c == null ? 0 : viva.outstandingAmount__c;
				}
			}
			return salida;
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			throw PortalPolizasController.errorSitio(e);
		}
	}

	// ---------------------------------------------------------------- Vigencias

	public class Vigencia {
		@AuraEnabled public Id id;
		@AuraEnabled public String numero;
		@AuraEnabled public String periodo;
		@AuraEnabled public Datetime inicio;
		@AuraEnabled public String estado;
		@AuraEnabled public Decimal prima;
		@AuraEnabled public Decimal pagado = 0;
		@AuraEnabled public Decimal pendiente = 0;
		@AuraEnabled public Boolean actual = false;
		@AuraEnabled public String renovacion;
	}

	public class Vigencias {
		@AuraEnabled public String moneda;
		@AuraEnabled public List<Vigencia> vigencias = new List<Vigencia>();
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Pestaña Vigencias: la cadena de renovaciones de la póliza (póliza anterior y las que la
	 * renuevan), de la más reciente a la más antigua. Solo se listan las vigencias que también son del usuario.
	 * @param policyId: Id de la póliza
	 * @param cuentaVistaPrevia: Cuenta a simular (solo vista previa de administrador); null para el usuario real
	 * @return Vigencias con prima, pagado y pendiente
	 */
	@AuraEnabled(cacheable=true)
	public static Vigencias vigencias(Id policyId, Id cuentaVistaPrevia) {
		try {
			Map<Id, String> roles = PortalPolizasController.validarAcceso(policyId, cuentaVistaPrevia);
			Map<Id, InsurancePolicy> cadena = new Map<Id, InsurancePolicy>();
			// Hacia atrás: póliza anterior de cada vigencia.
			Id anterior = policyId;
			for (Integer i = 0; anterior != null && !cadena.containsKey(anterior) && i < MAX_NIVELES; i++) {
				List<InsurancePolicy> l = [
					SELECT Id, Name, termPeriod__c, EffectiveDate, toLabel(Status), PremiumAmount, Moneda__c,
						PriorPolicyId, PriorPolicy.Name
					FROM InsurancePolicy WHERE Id = :anterior
				];
				if (l.isEmpty()) { break; }
				cadena.put(l[0].Id, l[0]);
				anterior = l[0].PriorPolicyId;
			}
			// Hacia adelante: las pólizas que renuevan a alguna de la cadena.
			Set<Id> frontera = new Set<Id>{ policyId };
			for (Integer i = 0; !frontera.isEmpty() && i < MAX_NIVELES; i++) {
				Set<Id> siguiente = new Set<Id>();
				for (InsurancePolicy p : [
					SELECT Id, Name, termPeriod__c, EffectiveDate, toLabel(Status), PremiumAmount, Moneda__c,
						PriorPolicyId, PriorPolicy.Name
					FROM InsurancePolicy WHERE PriorPolicyId IN :frontera
				]) {
					if (!cadena.containsKey(p.Id)) {
						cadena.put(p.Id, p);
						siguiente.add(p.Id);
					}
				}
				frontera = siguiente;
			}

			Vigencias salida = new Vigencias();
			String moneda = cadena.get(policyId).Moneda__c;
			salida.moneda = String.isBlank(moneda) ? 'MXN' : moneda;
			Map<Id, Vigencia> porId = new Map<Id, Vigencia>();
			for (InsurancePolicy p : cadena.values()) {
				if (!roles.containsKey(p.Id)) { continue; }
				Vigencia v = new Vigencia();
				v.id = p.Id;
				v.numero = p.Name;
				v.periodo = String.isBlank(p.termPeriod__c) ? 'Sin fechas' : p.termPeriod__c;
				v.inicio = p.EffectiveDate;
				v.estado = p.Status;
				v.prima = p.PremiumAmount;
				v.actual = p.Id == policyId;
				v.renovacion = p.PriorPolicyId == null ? 'Primera registrada'
					: (p.PriorPolicy != null && p.PriorPolicy.Name != p.Name
						? 'Renumerada · antes ' + p.PriorPolicy.Name : 'Mismo número');
				porId.put(p.Id, v);
			}

			// Pagado y pendiente de cada vigencia, con la misma regla que la pestaña Pagos.
			List<PaymentPlanInstallment__c> cuotas = [
				SELECT Id, installmentStatus__c, matchedAmount__c, outstandingAmount__c, replacesInstallment__c,
					paymentPlan__r.insurancePolicy__c
				FROM PaymentPlanInstallment__c
				WHERE paymentPlan__r.insurancePolicy__c IN :porId.keySet()
				LIMIT 10000
			];
			Set<Id> reemplazadas = new Set<Id>();
			for (PaymentPlanInstallment__c c : cuotas) {
				if (c.replacesInstallment__c != null) { reemplazadas.add(c.replacesInstallment__c); }
			}
			for (PaymentPlanInstallment__c c : cuotas) {
				if (reemplazadas.contains(c.Id) || ESTADOS_CERRADOS.contains(c.installmentStatus__c)) { continue; }
				Vigencia v = porId.get(c.paymentPlan__r.insurancePolicy__c);
				v.pagado += c.matchedAmount__c == null ? 0 : c.matchedAmount__c;
				v.pendiente += c.outstandingAmount__c == null ? 0 : c.outstandingAmount__c;
			}

			List<Vigencia> ordenadas = porId.values();
			// De la más reciente a la más antigua por inicio de vigencia (sin fecha al final).
			for (Integer i = 1; i < ordenadas.size(); i++) {
				Vigencia x = ordenadas[i];
				Integer j = i - 1;
				while (j >= 0 && masAntigua(ordenadas[j], x)) {
					ordenadas[j + 1] = ordenadas[j];
					j--;
				}
				ordenadas[j + 1] = x;
			}
			salida.vigencias = ordenadas;
			return salida;
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			throw PortalPolizasController.errorSitio(e);
		}
	}

	// ---------------------------------------------------------------- Asegurados / Vehículos / Ubicaciones

	/** Roles que no son asegurados (van en Participantes). Misma regla que movimientosColectivo. */
	static final List<String> ROLES_NO_ASEGURADO = new List<String>{ 'contrat', 'benefic', 'pagador', 'owner', 'policyholder' };
	static final Integer MAX_FILAS = 5000;

	public class Fila {
		@AuraEnabled public Id id;
		/** Certificado (personas) o inciso (vehículos / ubicaciones). */
		@AuraEnabled public String clave;
		@AuraEnabled public String nombre;
		@AuraEnabled public String detalle;
		@AuraEnabled public Boolean dependiente = false;
		@AuraEnabled public Date desde;
		@AuraEnabled public Date hasta;
		@AuraEnabled public Decimal prima;
		@AuraEnabled public Decimal suma;
		@AuraEnabled public Boolean activo = true;
		@AuraEnabled public String motivoBaja;
		// Solo participantes
		@AuraEnabled public String roles;
		@AuraEnabled public String parentesco;
		@AuraEnabled public String titular;
		@AuraEnabled public Decimal porcentaje;
		@AuraEnabled public String grupo;
	}

	public class Bienes {
		/** personas | vehiculos | ubicaciones */
		@AuraEnabled public String tipo;
		@AuraEnabled public String moneda;
		/** true si el usuario solo ve a su grupo familiar (no es el contratante). */
		@AuraEnabled public Boolean soloMiGrupo = false;
		@AuraEnabled public List<Fila> filas = new List<Fila>();
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Pestaña Asegurados / Vehículos / Ubicaciones, según el ramo (igual que movimientosColectivo):
	 * automóviles → incisos de la flotilla; daños y empresarial → ubicaciones; los demás → personas aseguradas,
	 * cada titular seguido de sus dependientes. Incluye las bajas. Quien no es el contratante solo ve a su grupo.
	 * @param policyId: Id de la póliza
	 * @param cuentaVistaPrevia: Cuenta a simular (solo vista previa de administrador); null para el usuario real
	 * @return Tipo de lista y filas
	 */
	@AuraEnabled(cacheable=true)
	public static Bienes asegurados(Id policyId, Id cuentaVistaPrevia) {
		try {
			Map<Id, String> roles = PortalPolizasController.validarAcceso(policyId, cuentaVistaPrevia);
			InsurancePolicy p = [SELECT Ramo__c, Moneda__c FROM InsurancePolicy WHERE Id = :policyId LIMIT 1];
			Bienes salida = new Bienes();
			salida.moneda = String.isBlank(p.Moneda__c) ? 'MXN' : p.Moneda__c;
			salida.tipo = tipoRamo(p.Ramo__c);
			if (salida.tipo == 'vehiculos') {
				salida.filas = vehiculos(policyId);
			} else if (salida.tipo == 'ubicaciones') {
				salida.filas = ubicaciones(policyId);
			} else {
				List<InsurancePolicyParticipant> lista = participantesVisibles(policyId, roles.get(policyId) != 'Titular',
					cuentaVistaPrevia, salida);
				salida.filas = personas(lista);
			}
			return salida;
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			throw PortalPolizasController.errorSitio(e);
		}
	}

	/**
	 * @creation date: 14/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Pestaña Participantes: todas las personas y empresas de la póliza con sus roles (asegurados,
	 * dependientes, beneficiarios, contratante…). En automóviles, daños y empresarial no aplica (igual que en SF).
	 * Quien no es el contratante solo ve a su grupo familiar y sus beneficiarios.
	 * @param policyId: Id de la póliza
	 * @param cuentaVistaPrevia: Cuenta a simular (solo vista previa de administrador); null para el usuario real
	 * @return Filas con roles, parentesco, titular y porcentaje
	 */
	@AuraEnabled(cacheable=true)
	public static Bienes participantes(Id policyId, Id cuentaVistaPrevia) {
		try {
			Map<Id, String> roles = PortalPolizasController.validarAcceso(policyId, cuentaVistaPrevia);
			InsurancePolicy p = [SELECT Ramo__c, Moneda__c FROM InsurancePolicy WHERE Id = :policyId LIMIT 1];
			Bienes salida = new Bienes();
			salida.moneda = String.isBlank(p.Moneda__c) ? 'MXN' : p.Moneda__c;
			// En autos, daños y empresarial también hay participantes (contratante, asegurado, beneficiario preferente).
			salida.tipo = tipoRamo(p.Ramo__c);

			Map<String, String> rolEtiquetas = MovimientosColectivoController.etiquetas(InsurancePolicyParticipant.Role.getDescribe());
			Map<String, String> relaciones = MovimientosColectivoController.etiquetas(
				InsurancePolicyParticipant.RelationshipToInsured.getDescribe());
			Map<String, String> motivos = MovimientosColectivoController.etiquetas(
				InsurancePolicyParticipant.Motivo_Baja__c.getDescribe());
			for (InsurancePolicyParticipant pp : participantesVisibles(policyId, roles.get(policyId) != 'Titular',
					cuentaVistaPrevia, salida)) {
				Fila f = new Fila();
				f.id = pp.Id;
				f.clave = pp.ParticipantCode;
				f.nombre = pp.ParticipantName;
				List<String> etiquetasRol = new List<String>();
				for (String r : String.isBlank(pp.Role) ? new List<String>() : pp.Role.split(';')) {
					etiquetasRol.add(rolEtiquetas.containsKey(r) ? rolEtiquetas.get(r) : r);
				}
				f.roles = String.join(etiquetasRol, ', ');
				f.parentesco = pp.RelationshipToInsured == null ? null
					: CensoColectivoController.parentescoPolizaVisible(pp.RelationshipToInsured, relaciones);
				f.titular = pp.RelatedInsPolicyParticipant?.ParticipantName;
				f.porcentaje = pp.BeneficiarySharePercentage;
				f.desde = desde(pp);
				f.hasta = hasta(pp);
				f.prima = pp.TermPremiumAmount;
				f.activo = esActivo(pp);
				f.motivoBaja = pp.Motivo_Baja__c == null ? null : motivos.get(pp.Motivo_Baja__c);
				f.grupo = grupo(pp);
				f.dependiente = f.grupo == 'dependiente';
				salida.filas.add(f);
			}
			return salida;
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			throw PortalPolizasController.errorSitio(e);
		}
	}

	// Vigencia del participante como la muestra Salesforce: la del participante o, si no la tiene, la de su registro.
	@TestVisible
	static Date desde(InsurancePolicyParticipant pp) {
		return pp.EffectiveFromDate != null ? pp.EffectiveFromDate : (pp.EffectiveDate == null ? null : pp.EffectiveDate.date());
	}

	@TestVisible
	static Date hasta(InsurancePolicyParticipant pp) {
		return pp.EffectiveToDate != null ? pp.EffectiveToDate : (pp.ExpirationDate == null ? null : pp.ExpirationDate.date());
	}

	/** personas | vehiculos | ubicaciones, con la misma regla que movimientosColectivo. */
	@TestVisible
	static String tipoRamo(String ramo) {
		if (String.isBlank(ramo)) { return 'personas'; }
		String r = CensoColectivoController.llave(ramo);
		if (r == null) { return 'personas'; }
		if (r.startsWith('auto')) { return 'vehiculos'; }
		if (r.startsWith('dano') || r.startsWith('empresarial')) { return 'ubicaciones'; }
		return 'personas';
	}

	/**
	 * Participantes de la póliza que el usuario puede ver. El contratante ve a todos; un asegurado solo a sí mismo,
	 * a quienes dependen de él (dependientes y beneficiarios) y, si es dependiente, a su titular.
	 */
	static List<InsurancePolicyParticipant> participantesVisibles(Id policyId, Boolean soloMiGrupo, Id cuentaVistaPrevia,
			Bienes salida) {
		List<InsurancePolicyParticipant> todos = [
			SELECT Id, ParticipantName, ParticipantCode, RelatedInsPolicyParticipantId,
				RelatedInsPolicyParticipant.ParticipantName, RelationshipToInsured, Role, Categoria__c,
				TermPremiumAmount, EffectiveFromDate, EffectiveToDate, EffectiveDate, ExpirationDate, IsActiveParticipant, Motivo_Baja__c,
				BeneficiarySharePercentage, PrimaryParticipantAccountId, PrimaryParticipantContactId
			FROM InsurancePolicyParticipant
			WHERE InsurancePolicyId = :policyId
			ORDER BY ParticipantCode NULLS LAST, ParticipantName
			LIMIT :MAX_FILAS
		];
		if (!soloMiGrupo) { return todos; }
		salida.soloMiGrupo = true;
		List<Id> yo = PortalPolizasController.identidad(cuentaVistaPrevia);
		Set<Id> propios = new Set<Id>();
		Set<Id> titulares = new Set<Id>();
		for (InsurancePolicyParticipant pp : todos) {
			if ((yo[0] != null && pp.PrimaryParticipantAccountId == yo[0])
					|| (yo[1] != null && pp.PrimaryParticipantContactId == yo[1])) {
				propios.add(pp.Id);
				if (pp.RelatedInsPolicyParticipantId != null) { titulares.add(pp.RelatedInsPolicyParticipantId); }
			}
		}
		List<InsurancePolicyParticipant> visibles = new List<InsurancePolicyParticipant>();
		for (InsurancePolicyParticipant pp : todos) {
			if (propios.contains(pp.Id) || titulares.contains(pp.Id) || propios.contains(pp.RelatedInsPolicyParticipantId)) {
				visibles.add(pp);
			}
		}
		return visibles;
	}

	/**
	 * @creation date: 15/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Bienes asegurados vigentes de varias pólizas para el Dashboard, con las mismas reglas que la
	 * pestaña Asegurados / Vehículos / Ubicaciones: personas aseguradas activas (quien no es el contratante solo
	 * cuenta a su grupo), vehículos de la flotilla sin baja (o el bien de la póliza de un solo auto) y ubicaciones
	 * sin baja.
	 * @param ramos: Póliza → ramo (etiqueta)
	 * @param roles: Póliza → rol del usuario
	 * @param cuentaVistaPrevia: Cuenta a simular (solo vista previa de administrador); null para el usuario real
	 * @return { personas, vehiculos, ubicaciones }
	 */
	public static Map<String, Integer> contarBienes(Map<Id, String> ramos, Map<Id, String> roles, Id cuentaVistaPrevia) {
		Map<String, Integer> r = new Map<String, Integer>{ 'personas' => 0, 'vehiculos' => 0, 'ubicaciones' => 0 };
		Set<Id> autos = new Set<Id>();
		Set<Id> danos = new Set<Id>();
		Set<Id> titular = new Set<Id>();
		List<Id> grupo = new List<Id>();
		for (Id pid : ramos.keySet()) {
			String t = tipoRamo(ramos.get(pid));
			if (t == 'vehiculos') { autos.add(pid); }
			else if (t == 'ubicaciones') { danos.add(pid); }
			else if (roles.get(pid) == 'Titular') { titular.add(pid); }
			else { grupo.add(pid); }
		}
		if (!autos.isEmpty()) {
			Set<Id> conFlotilla = new Set<Id>();
			for (AggregateResult ar : [
				SELECT Poliza__c pol, COUNT(Id) n FROM Inciso_Flotilla__c
				WHERE Poliza__c IN :autos AND Fecha_Baja__c = null GROUP BY Poliza__c
			]) {
				conFlotilla.add((Id) ar.get('pol'));
				r.put('vehiculos', r.get('vehiculos') + (Integer) ar.get('n'));
			}
			for (Id pid : conFlotilla) { autos.remove(pid); }
			// Pólizas de un solo auto o sin flotilla: el bien de la póliza.
			if (!autos.isEmpty()) {
				r.put('vehiculos', r.get('vehiculos') + [
					SELECT COUNT() FROM InsurancePolicyAsset
					WHERE InsurancePolicyId IN :autos AND Fecha_Baja__c = null AND IsActive != false
				]);
			}
		}
		if (!danos.isEmpty()) {
			r.put('ubicaciones', [
				SELECT COUNT() FROM InsurancePolicyAsset
				WHERE InsurancePolicyId IN :danos AND Fecha_Baja__c = null AND IsActive != false
			]);
		}
		Integer personas = 0;
		if (!titular.isEmpty()) {
			for (InsurancePolicyParticipant pp : [
				SELECT Role, IsActiveParticipant, EffectiveToDate, Motivo_Baja__c FROM InsurancePolicyParticipant
				WHERE InsurancePolicyId IN :titular LIMIT 20000
			]) {
				if (esAsegurado(pp) && esActivo(pp)) { personas++; }
			}
		}
		// Pólizas donde el usuario es asegurado (no contratante): solo su grupo. Pocas por usuario.
		for (Integer i = 0; i < grupo.size() && i < 20; i++) {
			for (InsurancePolicyParticipant pp : participantesVisibles(grupo[i], true, cuentaVistaPrevia, new Bienes())) {
				if (esAsegurado(pp) && esActivo(pp)) { personas++; }
			}
		}
		r.put('personas', personas);
		return r;
	}

	static List<Fila> personas(List<InsurancePolicyParticipant> lista) {
		Map<String, String> relaciones = MovimientosColectivoController.etiquetas(
			InsurancePolicyParticipant.RelationshipToInsured.getDescribe());
		Map<String, String> motivos = MovimientosColectivoController.etiquetas(
			InsurancePolicyParticipant.Motivo_Baja__c.getDescribe());
		List<Fila> titulares = new List<Fila>();
		Map<Id, List<Fila>> dependientes = new Map<Id, List<Fila>>();
		Set<Id> ids = new Set<Id>();
		for (InsurancePolicyParticipant pp : lista) {
			if (!esAsegurado(pp)) { continue; }
			ids.add(pp.Id);
		}
		for (InsurancePolicyParticipant pp : lista) {
			if (!ids.contains(pp.Id)) { continue; }
			Fila f = new Fila();
			f.id = pp.Id;
			f.clave = pp.ParticipantCode;
			f.nombre = pp.ParticipantName;
			f.dependiente = pp.RelatedInsPolicyParticipantId != null;
			f.parentesco = !f.dependiente ? 'Titular'
				: (pp.RelationshipToInsured == null ? 'Dependiente'
					: CensoColectivoController.parentescoPolizaVisible(pp.RelationshipToInsured, relaciones));
			f.titular = pp.RelatedInsPolicyParticipant?.ParticipantName;
			f.detalle = pp.Categoria__c;
			f.desde = desde(pp);
			f.hasta = hasta(pp);
			f.prima = pp.TermPremiumAmount;
			f.activo = pp.IsActiveParticipant != false;
			f.motivoBaja = pp.Motivo_Baja__c == null ? null : motivos.get(pp.Motivo_Baja__c);
			if (f.dependiente && ids.contains(pp.RelatedInsPolicyParticipantId)) {
				if (!dependientes.containsKey(pp.RelatedInsPolicyParticipantId)) {
					dependientes.put(pp.RelatedInsPolicyParticipantId, new List<Fila>());
				}
				dependientes.get(pp.RelatedInsPolicyParticipantId).add(f);
			} else {
				titulares.add(f);
			}
		}
		// Cada titular seguido de sus dependientes.
		List<Fila> salida = new List<Fila>();
		for (Fila t : titulares) {
			salida.add(t);
			if (dependientes.containsKey(t.id)) { salida.addAll(dependientes.get(t.id)); }
		}
		return salida;
	}

	static List<Fila> vehiculos(Id policyId) {
		Map<String, String> motivos = MovimientosColectivoController.etiquetas(Inciso_Flotilla__c.Motivo_Baja__c.getDescribe());
		List<Fila> salida = new List<Fila>();
		for (Inciso_Flotilla__c i : [
			SELECT Id, Name, Numero_Inciso__c, Serie__c, Placas__c, Descripcion__c, Modelo__c, Uso__c, Valor__c, Prima__c,
				Fecha_Alta__c, Fecha_Baja__c, Motivo_Baja__c
			FROM Inciso_Flotilla__c WHERE Poliza__c = :policyId
			ORDER BY Numero_Inciso__c ASC NULLS LAST, Name ASC LIMIT :MAX_FILAS
		]) {
			Fila f = new Fila();
			f.id = i.Id;
			f.clave = i.Numero_Inciso__c == null ? null : String.valueOf(i.Numero_Inciso__c.intValue());
			f.nombre = String.isBlank(i.Descripcion__c) ? i.Name : i.Descripcion__c;
			List<String> partes = new List<String>();
			if (i.Modelo__c != null) { partes.add('Modelo ' + i.Modelo__c.intValue()); }
			if (String.isNotBlank(i.Placas__c)) { partes.add('Placas ' + i.Placas__c); }
			if (String.isNotBlank(i.Serie__c)) { partes.add('Serie ' + i.Serie__c); }
			if (String.isNotBlank(i.Uso__c)) { partes.add(i.Uso__c); }
			f.detalle = String.join(partes, ' · ');
			f.desde = i.Fecha_Alta__c;
			f.hasta = i.Fecha_Baja__c;
			f.suma = i.Valor__c;
			f.prima = i.Prima__c;
			f.activo = i.Fecha_Baja__c == null;
			f.motivoBaja = i.Motivo_Baja__c == null ? null : motivos.get(i.Motivo_Baja__c);
			salida.add(f);
		}
		// Pólizas de un solo auto o sin flotilla: los bienes de la póliza.
		return salida.isEmpty() ? bienesPoliza(policyId) : salida;
	}

	static List<Fila> ubicaciones(Id policyId) {
		return bienesPoliza(policyId);
	}

	static List<Fila> bienesPoliza(Id policyId) {
		Map<String, String> motivos = MovimientosColectivoController.etiquetas(InsurancePolicyAsset.Motivo_Baja__c.getDescribe());
		List<Fila> salida = new List<Fila>();
		for (InsurancePolicyAsset a : [
			SELECT Id, AssetName, IsActive, EffectiveFromDate, EffectiveToDate, StandardPremiumAmount, Suma_Asegurada__c,
				Fecha_Baja__c, Motivo_Baja__c, CustomerProperty.Street, CustomerProperty.City, CustomerProperty.PostalCode,
				CustomerProperty.Uso__c, CustomerProperty.FairMarketValue
			FROM InsurancePolicyAsset WHERE InsurancePolicyId = :policyId
			ORDER BY CreatedDate ASC, Id ASC LIMIT :MAX_FILAS
		]) {
			Fila f = new Fila();
			f.id = a.Id;
			Matcher m = Pattern.compile('(?i)^\\s*inciso\\s*(\\d+)').matcher(a.AssetName == null ? '' : a.AssetName);
			f.clave = m.find() ? m.group(1) : null;
			f.nombre = a.AssetName;
			List<String> partes = new List<String>();
			if (a.CustomerProperty != null) {
				for (String s : new List<String>{ a.CustomerProperty.Street, a.CustomerProperty.City,
						a.CustomerProperty.PostalCode == null ? null : 'CP ' + a.CustomerProperty.PostalCode,
						a.CustomerProperty.Uso__c }) {
					if (String.isNotBlank(s)) { partes.add(s); }
				}
			}
			f.detalle = String.join(partes, ' · ');
			f.desde = a.EffectiveFromDate;
			f.hasta = a.Fecha_Baja__c != null ? a.Fecha_Baja__c : a.EffectiveToDate;
			f.suma = a.Suma_Asegurada__c != null ? a.Suma_Asegurada__c
				: (a.CustomerProperty == null ? null : a.CustomerProperty.FairMarketValue);
			f.prima = a.StandardPremiumAmount;
			f.activo = a.Fecha_Baja__c == null && a.IsActive != false;
			f.motivoBaja = a.Motivo_Baja__c == null ? null : motivos.get(a.Motivo_Baja__c);
			salida.add(f);
		}
		// Por número de inciso; los que no tienen número, al final en su orden.
		List<Fila> conInciso = new List<Fila>();
		List<Fila> sinInciso = new List<Fila>();
		for (Fila f : salida) {
			if (f.clave == null) { sinInciso.add(f); } else { conInciso.add(f); }
		}
		for (Integer i = 1; i < conInciso.size(); i++) {
			Fila x = conInciso[i];
			Integer j = i - 1;
			while (j >= 0 && Integer.valueOf(conInciso[j].clave) > Integer.valueOf(x.clave)) {
				conInciso[j + 1] = conInciso[j];
				j--;
			}
			conInciso[j + 1] = x;
		}
		conInciso.addAll(sinInciso);
		return conInciso;
	}

	static Boolean esAsegurado(InsurancePolicyParticipant pp) {
		String rol = pp.Role == null ? '' : pp.Role.toLowerCase();
		for (String r : ROLES_NO_ASEGURADO) {
			if (rol.contains(r)) { return false; }
		}
		return true;
	}

	/** Misma regla de baja que participantesPoliza. */
	static Boolean esActivo(InsurancePolicyParticipant pp) {
		return !(pp.Motivo_Baja__c != null || (pp.IsActiveParticipant == false && pp.EffectiveToDate != null));
	}

	/** asegurado | dependiente | beneficiario | otro, como participantesPoliza. */
	static String grupo(InsurancePolicyParticipant pp) {
		String rol = pp.Role == null ? '' : pp.Role.toLowerCase();
		Boolean beneficiario = rol.contains('benefic');
		if (rol.contains('miembro familiar') || rol.contains('familymember')
				|| (pp.RelatedInsPolicyParticipantId != null && !beneficiario)) {
			return 'dependiente';
		}
		if (rol.contains('asegurado') || rol.contains('insured') || rol.contains('miembro') || rol.contains('suscriptor')) {
			return 'asegurado';
		}
		return beneficiario ? 'beneficiario' : 'otro';
	}

	// ---------------------------------------------------------------- Utilidades

	static Boolean masAntigua(Vigencia a, Vigencia b) {
		if (a.inicio == null) { return b.inicio != null; }
		if (b.inicio == null) { return false; }
		return a.inicio < b.inicio;
	}

	static String etiquetaCuota(PaymentPlanInstallment__c origen, PaymentPlanInstallment__c viva) {
		String base;
		if (origen.carrierInstallmentNumber__c == null) {
			base = viva.sequenceNumber__c != null ? 'Cuota ' + viva.sequenceNumber__c.intValue() : viva.Name;
		} else {
			String endoso = origen.carrierEndorsementNumber__c;
			base = 'Cuota ' + origen.carrierInstallmentNumber__c.intValue()
				+ (String.isNotBlank(endoso) && !ENDOSO_EMISION.matcher(endoso.trim()).matches() ? ' · Endoso ' + endoso : '');
		}
		return base + (viva.isEstimated__c == true ? ' · Estimada' : '');
	}

	static Seccion seccion(Informacion info, String titulo) {
		Seccion s = new Seccion();
		s.titulo = titulo;
		info.secciones.add(s);
		return s;
	}

	static Campo texto(Seccion s, String etiqueta, String valor) {
		if (String.isBlank(valor)) { return null; }
		Campo c = campo(s, etiqueta, 'texto');
		c.texto = valor;
		return c;
	}

	static void moneda(Seccion s, String etiqueta, Decimal valor) {
		if (valor == null) { return; }
		campo(s, etiqueta, 'moneda').numero = valor;
	}

	static void numero(Seccion s, String etiqueta, Decimal valor) {
		if (valor == null) { return; }
		campo(s, etiqueta, 'numero').numero = valor;
	}

	static void fecha(Seccion s, String etiqueta, Date valor) {
		if (valor == null) { return; }
		campo(s, etiqueta, 'fecha').fecha = valor;
	}

	static void fecha(Seccion s, String etiqueta, Datetime valor) {
		if (valor == null) { return; }
		fecha(s, etiqueta, valor.date());
	}

	static Campo campo(Seccion s, String etiqueta, String tipo) {
		Campo c = new Campo();
		c.etiqueta = etiqueta;
		c.tipo = tipo;
		s.campos.add(c);
		return c;
	}

	// ============================================================
	// Solicitudes de movimientos (altas, bajas y cambios) desde el sitio
	// ============================================================

	// Tamaño máximo de los archivos de una solicitud (en total).
	@TestVisible static final Integer MAX_BYTES_SOLICITUD = 4 * 1024 * 1024;

	/**
	 * @creation date: 17/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Pestaña Solicitudes: las solicitudes de movimientos que el cliente envió desde el sitio (casos de
	 * tipo «Solicitud de movimientos») con su folio, estado (Recibida, En proceso, Cerrada o Rechazada) y lo que pidió.
	 * Al contratante también le da los registros vigentes de la póliza (asegurados, vehículos o ubicaciones) para
	 * pedir bajas y cambios.
	 * @param policyId: Id de la póliza
	 * @param cuentaVistaPrevia: Cuenta a simular (solo vista previa de administrador); null para el usuario real
	 * @return tipo, puedeSolicitar, registros y solicitudes
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> solicitudes(Id policyId, Id cuentaVistaPrevia) {
		try {
			Map<Id, String> roles = PortalPolizasController.validarAcceso(policyId, cuentaVistaPrevia);
			Boolean contratante = roles.get(policyId) == 'Titular';
			Bienes bienes = asegurados(policyId, cuentaVistaPrevia);
			List<Map<String, Object>> registros = new List<Map<String, Object>>();
			if (contratante) {
				for (Fila f : bienes.filas) {
					if (f.activo == false) { continue; }
					registros.add(new Map<String, Object>{ 'id' => f.id, 'clave' => f.clave, 'nombre' => f.nombre,
						'detalle' => f.detalle, 'dependiente' => f.dependiente });
				}
			}
			List<Map<String, Object>> lista = new List<Map<String, Object>>();
			for (Map<String, Object> s : EndosoPoliza.solicitudes(policyId, null)) {
				if (s.get('portal') != true) { continue; }
				lista.add(new Map<String, Object>{
					'folio' => s.get('folio'), 'caso' => s.get('caso'), 'fecha' => s.get('fecha'), 'estado' => s.get('estadoPortal'),
					'asunto' => s.get('asunto'), 'descripcion' => s.get('descripcion'), 'respuesta' => s.get('respuesta'),
					'enviadaPor' => s.get('enviadaPor'), 'aplicados' => s.get('total'), 'abiertos' => s.get('abiertos'),
					'endosos' => s.get('endosos'), 'documentos' => ((List<Object>) s.get('documentos')).size()
				});
			}
			return new Map<String, Object>{
				'tipo' => bienes.tipo, 'esContratante' => contratante, 'vistaPrevia' => cuentaVistaPrevia != null,
				'esEmpresarial' => esEmpresarial(policyId, bienes),
				'puedeSolicitar' => contratante && EndosoPoliza.tipoCaso() != null && esEmpresarial(policyId, bienes),
				'registros' => registros, 'solicitudes' => lista
			};
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			throw PortalPolizasController.errorSitio(e);
		}
	}

	/**
	 * @creation date: 17/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: El contratante envía una solicitud de movimientos: se crea un caso «Solicitud de movimientos» ligado
	 * a la póliza, con el folio de solicitud de la póliza (SOL-0001...), lo que pidió y sus archivos, y los movimientos se
	 * registran en la póliza con ese folio (abiertos hasta el endoso de la aseguradora; ver registrar). Al crearse se
	 * avisa por correo a Avanza (flujo del caso) y el ejecutivo descarga el Excel de la solicitud para la aseguradora.
	 * @param policyId: Id de la póliza
	 * @param solicitudJson: { movimientos: [{ tipo: alta|baja|cambio, registroId, fecha, detalle, titularId,
	 *                          datos: [{ etiqueta, valor }], campos: { clave: valor } }],
	 *                        listado: { tipo, nombre, fecha, encabezados, filas, total,
	 *                          registros: [{ tipo, fila, fecha, comentario, titular, campos: { clave: valor } }] },
	 *                        comentario, archivos: [{ nombre, base64 }] }
	 * @param cuentaVistaPrevia: Cuenta a simular (vista previa de administrador, para pruebas); null para el usuario real
	 * @return folio y número de caso
	 */
	@AuraEnabled(cacheable=false)
	public static Map<String, Object> crearSolicitud(Id policyId, String solicitudJson, Id cuentaVistaPrevia) {
		try {
			Map<Id, String> roles = PortalPolizasController.validarAcceso(policyId, cuentaVistaPrevia);
			if (roles.get(policyId) != 'Titular') {
				throw new AuraHandledException('Solo el contratante de la póliza puede enviar solicitudes de movimientos.');
			}
			Id tipoCaso = EndosoPoliza.tipoCaso();
			if (tipoCaso == null) { throw new AuraHandledException('Las solicitudes no están disponibles por ahora. Contacta a tu asesor.'); }
			Map<String, Object> d = String.isBlank(solicitudJson) ? new Map<String, Object>()
				: (Map<String, Object>) JSON.deserializeUntyped(solicitudJson);
			List<Object> movs = d.get('movimientos') instanceof List<Object> ? (List<Object>) d.get('movimientos') : new List<Object>();
			// Solicitud por archivo: el cliente sube un Excel/CSV con todos los datos (va adjunto al caso).
			Map<String, Object> listado = d.get('listado') instanceof Map<String, Object> ? (Map<String, Object>) d.get('listado') : null;
			if (movs.isEmpty() && listado == null) { throw new AuraHandledException('Agrega al menos un movimiento a la solicitud.'); }
			if (movs.size() > 500) { throw new AuraHandledException('Una solicitud admite hasta 500 movimientos; para más, adjunta el archivo.'); }

			Bienes bienes = asegurados(policyId, cuentaVistaPrevia);
			if (!esEmpresarial(policyId, bienes)) {
				throw new AuraHandledException('Las solicitudes de movimientos son para pólizas empresariales (colectivas o flotillas). Para esta póliza, contacta a tu asesor.');
			}
			Map<Id, Fila> vigentes = new Map<Id, Fila>();
			for (Fila f : bienes.filas) { if (f.activo != false) { vigentes.put(f.id, f); } }
			Map<String, String> nombres = new Map<String, String>{ 'alta' => 'Alta', 'baja' => 'Baja', 'cambio' => 'Cambio' };
			Map<String, Integer> cuenta = new Map<String, Integer>{ 'alta' => 0, 'baja' => 0, 'cambio' => 0 };
			// Movimientos que se registran en la póliza al enviar la solicitud (como si los capturara el ejecutivo).
			List<Map<String, Object>> aRegistrar = new List<Map<String, Object>>();
			Integer i = 0;
			for (Object o : movs) {
				i++;
				Map<String, Object> m = (Map<String, Object>) o;
				String tipo = String.valueOf(m.get('tipo')).toLowerCase();
				if (!nombres.containsKey(tipo)) { throw new AuraHandledException('Movimiento ' + i + ': tipo no válido.'); }
				cuenta.put(tipo, cuenta.get(tipo) + 1);
				// Datos capturados del movimiento (para validar que el alta los traiga).
				List<String> partes = new List<String>{ nombres.get(tipo) };
				if (tipo != 'alta') {
					Fila f = m.get('registroId') == null ? null : vigentes.get((Id) String.valueOf(m.get('registroId')));
					if (f == null) { throw new AuraHandledException('Movimiento ' + i + ': elige un registro vigente de la póliza.'); }
					partes.add((String.isBlank(f.clave) ? '' : f.clave + ' · ') + f.nombre);
				}
				if (m.get('datos') instanceof List<Object>) {
					for (Object x : (List<Object>) m.get('datos')) {
						Map<String, Object> dx = (Map<String, Object>) x;
						if (dx.get('valor') != null && String.isNotBlank(String.valueOf(dx.get('valor')))) {
							partes.add(dx.get('etiqueta') + ': ' + dx.get('valor'));
						}
					}
				}
				if (tipo == 'alta' && partes.size() == 1) { throw new AuraHandledException('Movimiento ' + i + ': captura los datos del alta.'); }
				if (m.get('fecha') != null && String.isNotBlank(String.valueOf(m.get('fecha')))) { partes.add('Fecha solicitada: ' + m.get('fecha')); }
				if (m.get('detalle') != null && String.isNotBlank(String.valueOf(m.get('detalle')))) {
					partes.add((tipo == 'baja' ? 'Motivo: ' : (tipo == 'cambio' ? 'Cambio: ' : 'Nota: ')) + m.get('detalle'));
				}
				Map<String, Object> campos = m.get('campos') instanceof Map<String, Object> ? (Map<String, Object>) m.get('campos') : null;
				if (tipo == 'cambio' && (campos == null || campos.isEmpty())
						&& (m.get('detalle') == null || String.isBlank(String.valueOf(m.get('detalle'))))) {
					throw new AuraHandledException('Movimiento ' + i + ': describe qué se cambia.');
				}
				aRegistrar.add(new Map<String, Object>{ 'tipo' => tipo, 'registroId' => m.get('registroId'), 'fecha' => m.get('fecha'),
					'comentario' => m.get('detalle'), 'campos' => campos, 'titularId' => m.get('titularId'), 'etiqueta' => 'Movimiento ' + i });
			}
			String tipoArchivo = null;
			String resumenArchivo = null;
			if (listado != null) {
				String tipo = String.valueOf(listado.get('tipo')).toLowerCase();
				Map<String, String> plurales = new Map<String, String>{ 'alta' => 'Altas', 'baja' => 'Bajas', 'cambio' => 'Cambios', 'varios' => 'Varios movimientos' };
				if (!plurales.containsKey(tipo)) { throw new AuraHandledException('Indica qué contiene el archivo.'); }
				String nombreArchivo = String.valueOf(listado.get('nombre'));
				if (String.isBlank(nombreArchivo)) { throw new AuraHandledException('Elige el archivo con los datos.'); }
				List<Object> filas = listado.get('filas') instanceof List<Object> ? (List<Object>) listado.get('filas') : new List<Object>();
				Integer total = listado.get('total') == null ? filas.size() : Integer.valueOf(listado.get('total'));
				if (tipo != 'varios') { cuenta.put(tipo, cuenta.get(tipo) + Math.max(total, 1)); }
				resumenArchivo = 'archivo ' + nombreArchivo + (total > 0 ? ' (' + total + (total == 1 ? ' renglón)' : ' renglones)') : '');
				tipoArchivo = tipo;
				// Renglones del archivo ya interpretados en el sitio (columnas reconocidas): se registran en la póliza.
				if (listado.get('registros') instanceof List<Object>) {
					for (Object o : (List<Object>) listado.get('registros')) {
						Map<String, Object> r = (Map<String, Object>) o;
						String t = r.get('tipo') == null ? tipo : String.valueOf(r.get('tipo')).toLowerCase();
						String donde = r.get('fila') == null ? 'Un renglón del archivo' : 'Renglón ' + r.get('fila') + ' del archivo';
						if (!nombres.containsKey(t)) { throw new AuraHandledException(donde + ': indica si es alta, baja o cambio.'); }
						Object f = r.get('fecha') != null && String.isNotBlank(String.valueOf(r.get('fecha'))) ? r.get('fecha') : listado.get('fecha');
						aRegistrar.add(new Map<String, Object>{ 'tipo' => t, 'fecha' => f, 'comentario' => r.get('comentario'),
							'campos' => r.get('campos'), 'titular' => r.get('titular'), 'etiqueta' => donde });
					}
				}
			}

			// Archivos (opcionales): Excel o PDF con el detalle, identificaciones, actas...
			List<ContentVersion> archivos = new List<ContentVersion>();
			Integer bytes = 0;
			if (d.get('archivos') instanceof List<Object>) {
				for (Object o : (List<Object>) d.get('archivos')) {
					Map<String, Object> a = (Map<String, Object>) o;
					Blob b = EncodingUtil.base64Decode(String.valueOf(a.get('base64')));
					bytes += b.size();
					String nombre = String.valueOf(a.get('nombre'));
					archivos.add(new ContentVersion(Title = nombre.substringBeforeLast('.').left(255), PathOnClient = nombre, VersionData = b));
				}
			}
			if (bytes > MAX_BYTES_SOLICITUD) { throw new AuraHandledException('Los archivos suman más de 4 MB. Envía archivos más ligeros.'); }

			List<String> resumen = new List<String>();
			if (resumenArchivo != null) { resumen.add(resumenArchivo); }
			for (String t : new List<String>{ 'alta', 'baja', 'cambio' }) {
				Integer n = cuenta.get(t);
				if (n > 0 && resumenArchivo == null) { resumen.add(n + ' ' + nombres.get(t).toLowerCase() + (n == 1 ? '' : 's')); }
			}
			String tipoUnico = tipoArchivo == 'varios' ? 'varios' : null;
			for (String t : cuenta.keySet()) {
				if (cuenta.get(t) > 0) { tipoUnico = tipoUnico == null ? nombres.get(t) : 'varios'; }
			}
			InsurancePolicy p = [SELECT Name, OwnerId FROM InsurancePolicy WHERE Id = :policyId LIMIT 1];
			List<Id> yo = PortalPolizasController.identidad(cuentaVistaPrevia);
			String comentario = d.get('comentario') == null ? '' : String.valueOf(d.get('comentario')).trim();
			String folio = EndosoPoliza.siguienteFolio(policyId);
			Case c = new Case(RecordTypeId = tipoCaso, InsurancePolicy__c = policyId, AccountId = yo[0], Origin = 'Sitio Web',
				Solicitud__c = folio, Subject = (folio + ' · Póliza ' + p.Name + ' · ' + String.join(resumen, ', ')).left(255),
				Poliza_Number__c = p.Name,
				Description = 'Solicitud ' + folio + ' enviada desde el sitio por ' + UserInfo.getName()
					+ (cuentaVistaPrevia == null ? '' : ' (vista previa de administrador)') + ' para la póliza ' + p.Name + '.',
				Comentarios__c = String.isBlank(comentario) ? null : comentario.left(131072));
			if (tipoUnico != null && tipoUnico != 'varios') { c.Reason = tipoUnico; }
			// El caso lo atiende el ejecutivo dueño de la póliza.
			if (p.OwnerId != null && p.OwnerId.getSobjectType() == User.SObjectType
					&& [SELECT COUNT() FROM User WHERE Id = :p.OwnerId AND IsActive = true AND ContactId = null] > 0) {
				c.OwnerId = p.OwnerId;
			}
			// Todo o nada: si los movimientos no se pueden registrar, no queda la solicitud y el cliente ve por qué.
			Savepoint sp = Database.setSavepoint();
			insert c;
			for (ContentVersion v : archivos) { v.FirstPublishLocationId = c.Id; }
			if (!archivos.isEmpty()) { insert archivos; }
			Integer registrados;
			try {
				registrados = registrar(policyId, bienes, aRegistrar, folio);
			} catch (Exception e) {
				Database.rollback(sp);
				String msg = e instanceof AuraHandledException ? e.getMessage() : MovimientosColectivoController.mensaje(e);
				System.debug(LoggingLevel.ERROR, 'crearSolicitud (registro): ' + msg + ' | ' + e.getStackTraceString());
				AuraHandledException a = new AuraHandledException('No se pudo registrar la solicitud: ' + msg);
				a.setMessage('No se pudo registrar la solicitud: ' + msg);
				throw a;
			}
			return new Map<String, Object>{ 'folio' => folio, 'caso' => [SELECT CaseNumber FROM Case WHERE Id = :c.Id].CaseNumber,
				'registrados' => registrados };
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			System.debug(LoggingLevel.ERROR, 'crearSolicitud: ' + e.getMessage() + ' | ' + e.getStackTraceString());
			String msg = 'No se pudo enviar la solicitud. Intenta de nuevo o contacta a tu asesor.';
			AuraHandledException a = new AuraHandledException(msg);
			a.setMessage(msg);
			throw a;
		}
	}

	/**
	 * @creation date: 17/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Registra en la póliza los movimientos de la solicitud del sitio, igual que si los capturara el ejecutivo
	 * (Asegurados, Vehículos o Ubicaciones): quedan con el folio de la solicitud y abiertos hasta que se cierren con el
	 * endoso de la aseguradora. Las bajas y cambios que vienen del archivo se reconocen por serie, placas o inciso
	 * (vehículos), certificado o nombre (asegurados) e inciso o nombre (ubicaciones). Los controladores son de
	 * «inherited sharing»: desde aquí corren sin compartir, porque el usuario del sitio no ve los registros de la póliza.
	 * Pólizas de un solo vehículo (sin incisos de flotilla): no se registra nada y el ejecutivo atiende el caso.
	 * @param policyId: Id de la póliza
	 * @param bienes: registros de la póliza como los ve el contratante
	 * @param regs: { tipo, registroId, fecha, comentario, campos, titularId, titular, etiqueta }
	 * @param folio: folio de la solicitud
	 * @return número de movimientos registrados
	 */
	@TestVisible
	static Integer registrar(Id policyId, Bienes bienes, List<Map<String, Object>> regs, String folio) {
		if (regs.isEmpty()) { return 0; }
		String tipo = bienes.tipo;
		if (tipo == 'vehiculos' && [SELECT COUNT() FROM Inciso_Flotilla__c WHERE Poliza__c = :policyId] == 0) { return 0; }
		Map<String, Id> claves = clavesVigentes(policyId, bienes);
		String hoy = String.valueOf(Date.today());
		List<Map<String, Object>> movs = new List<Map<String, Object>>();
		// Altas de titulares en la misma solicitud (para ligar a sus dependientes): nombre -> posición.
		Map<String, Integer> altasTitular = new Map<String, Integer>();
		for (Map<String, Object> r : regs) {
			String t = String.valueOf(r.get('tipo'));
			String donde = String.valueOf(r.get('etiqueta'));
			Map<String, Object> c = r.get('campos') instanceof Map<String, Object> ? (Map<String, Object>) r.get('campos') : new Map<String, Object>();
			Map<String, Object> datos = tipo == 'vehiculos' ? datosVehiculo(c) : (tipo == 'ubicaciones' ? datosUbicacion(c) : datosPersona(c));
			String fecha = r.get('fecha') == null || CensoColectivoController.fecha(String.valueOf(r.get('fecha'))) == null
				? hoy : String.valueOf(r.get('fecha')).left(10);
			String comentario = r.get('comentario') == null ? null : ('Del cliente: ' + String.valueOf(r.get('comentario')).normalizeSpace()).left(255);
			Map<String, Object> m = new Map<String, Object>{ 'tipo' => t, 'fecha' => fecha, 'comentario' => comentario };
			if (t != 'alta') {
				Id id = r.get('registroId') == null || String.isBlank(String.valueOf(r.get('registroId'))) ? buscar(tipo, c, claves)
					: (Id) String.valueOf(r.get('registroId'));
				if (id == null) {
					throw falla(donde + ': no encontramos ' + (tipo == 'vehiculos' ? 'el vehículo (por serie, placas o inciso)'
						: (tipo == 'ubicaciones' ? 'la ubicación (por inciso o nombre)' : 'al asegurado (por certificado o nombre)'))
						+ ' entre los vigentes de la póliza.');
				}
				m.put('id', id);
			}
			if (t == 'cambio' && datos.isEmpty()) {
				throw falla(donde + ': indica los datos nuevos (solo los que cambian).');
			}
			if (t != 'baja') { m.put('datos', datos); }
			if (tipo == 'personas' && t == 'alta') {
				String parentesco = String.valueOf(datos.get('parentesco'));
				if (String.isBlank(parentesco) || CensoColectivoController.llave(parentesco) == 'titular') {
					altasTitular.put(llaveNombre(texto(datos.get('nombre')) + ' ' + texto(datos.get('apellidos'))), movs.size());
				} else if (r.get('titularId') != null && String.isNotBlank(String.valueOf(r.get('titularId')))) {
					m.put('titularId', String.valueOf(r.get('titularId')));
				} else {
					String titular = r.get('titular') == null ? '' : String.valueOf(r.get('titular'));
					Id tid = String.isBlank(titular) ? null : buscar('personas', new Map<String, Object>{ 'certificado' => titular, 'nombreCompleto' => titular }, claves);
					Integer ref = altasTitular.get(llaveNombre(titular));
					if (tid != null) { m.put('titularId', tid); } else if (ref != null) { m.put('titularRef', ref); } else {
						throw falla(donde + ': indica el titular del dependiente (su certificado o nombre).');
					}
				}
			}
			movs.add(m);
		}
		String json = System.JSON.serialize(new Map<String, Object>{ 'movimientos' => movs, 'solicitud' => folio });
		Map<String, Object> res;
		try {
			res = tipo == 'vehiculos' ? MovimientosFlotillaController.aplicar(policyId, json)
				: (tipo == 'ubicaciones' ? MovimientosUbicacionesController.aplicar(policyId, json) : MovimientosColectivoController.aplicar(policyId, json));
		} catch (AuraHandledException e) {
			// «Movimiento N» del controlador es la posición en esta lista: se cambia por lo que ve el cliente.
			String msg = e.getMessage();
			Matcher mt = Pattern.compile('^Movimiento (\\d+)').matcher(msg == null ? '' : msg);
			if (mt.find()) {
				Integer n = Integer.valueOf(mt.group(1));
				if (n >= 1 && n <= regs.size()) { msg = regs[n - 1].get('etiqueta') + msg.substring(mt.end()); }
			}
			throw falla(msg);
		}
		Integer total = 0;
		for (String k : new List<String>{ 'altas', 'bajas', 'cambios' }) {
			if (res.get(k) instanceof Integer) { total += (Integer) res.get(k); }
		}
		return total;
	}

	/**
	 * @creation date: 17/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: El sitio es de empresas: las solicitudes de movimientos solo aplican a pólizas empresariales. Lo es
	 * si la oportunidad de origen tiene Tipo de contratación «Empresarial» (valor Colectiva) o, si no, cuando es una
	 * flotilla (autos con incisos) o tiene más de un asegurado o ubicación. «Individual» no descarta la póliza porque es el
	 * valor por defecto del campo. Las pólizas que no vienen de una oportunidad (cargadas directo) son empresariales si el
	 * contratante es una cuenta de empresa (no persona física), aunque todavía no tengan registros.
	 * @param policyId: Id de la póliza
	 * @param bienes: registros de la póliza como los ve el contratante
	 * @return true si es colectiva o flotilla
	 */
	@TestVisible
	static Boolean esEmpresarial(Id policyId, Bienes bienes) {
		List<InsurancePolicy> pol = [
			SELECT SourceOpportunityId, SourceOpportunity.Tipo_Contratacion__c, NameInsuredId, NameInsured.IsPersonAccount
			FROM InsurancePolicy WHERE Id = :policyId LIMIT 1
		];
		if (pol.isEmpty()) { return false; }
		if (pol[0].SourceOpportunityId != null && pol[0].SourceOpportunity.Tipo_Contratacion__c == 'Colectiva') { return true; }
		if (pol[0].SourceOpportunityId == null && pol[0].NameInsuredId != null && pol[0].NameInsured.IsPersonAccount != true) { return true; }
		if (bienes.tipo == 'vehiculos') { return [SELECT COUNT() FROM Inciso_Flotilla__c WHERE Poliza__c = :policyId] > 0; }
		return bienes.filas.size() > 1;
	}

	static AuraHandledException falla(String msg) {
		AuraHandledException e = new AuraHandledException(msg);
		e.setMessage(msg);
		return e;
	}

	/** Vigentes de la póliza por llave: S:serie, P:placas, I:inciso (vehículos y ubicaciones), C:certificado y N:nombre. */
	static Map<String, Id> clavesVigentes(Id policyId, Bienes bienes) {
		Map<String, Id> res = new Map<String, Id>();
		if (bienes.tipo == 'vehiculos') {
			for (Inciso_Flotilla__c i : [
				SELECT Id, Serie__c, Placas__c, Numero_Inciso__c FROM Inciso_Flotilla__c
				WHERE Poliza__c = :policyId AND Fecha_Baja__c = null LIMIT :MAX_FILAS
			]) {
				if (String.isNotBlank(i.Serie__c)) { res.put('S:' + codigo(i.Serie__c), i.Id); }
				if (String.isNotBlank(i.Placas__c)) { res.put('P:' + codigo(i.Placas__c), i.Id); }
				if (i.Numero_Inciso__c != null) { res.put('I:' + i.Numero_Inciso__c.intValue(), i.Id); }
			}
			return res;
		}
		for (Fila f : bienes.filas) {
			if (f.activo == false) { continue; }
			if (String.isNotBlank(f.clave)) { res.put((bienes.tipo == 'ubicaciones' ? 'I:' : 'C:') + codigo(f.clave), f.id); }
			if (String.isNotBlank(f.nombre)) { res.put('N:' + llaveNombre(f.nombre), f.id); }
		}
		return res;
	}

	static Id buscar(String tipo, Map<String, Object> c, Map<String, Id> claves) {
		List<String> llaves = new List<String>();
		if (tipo == 'vehiculos') {
			llaves.add('S:' + codigo(texto(c.get('serie'))));
			llaves.add('P:' + codigo(texto(c.get('placas'))));
			llaves.add('I:' + codigo(texto(c.get('inciso'))).replaceFirst('^0+', ''));
		} else if (tipo == 'ubicaciones') {
			llaves.add('I:' + codigo(texto(c.get('inciso'))));
			llaves.add('N:' + llaveNombre(texto(c.get('ubicacion'))));
		} else {
			llaves.add('C:' + codigo(texto(c.get('certificado'))));
			String completo = c.get('nombreCompleto') != null ? texto(c.get('nombreCompleto'))
				: texto(c.get('nombre')) + ' ' + texto(c.get('paterno')) + ' ' + texto(c.get('materno'));
			llaves.add('N:' + llaveNombre(completo));
		}
		for (String k : llaves) {
			if (k.length() > 2 && claves.containsKey(k)) { return claves.get(k); }
		}
		return null;
	}

	static Map<String, Object> datosVehiculo(Map<String, Object> c) {
		Map<String, Object> d = new Map<String, Object>();
		String descripcion = texto(c.get('descripcion'));
		if (String.isBlank(descripcion)) {
			descripcion = (texto(c.get('marca')) + ' ' + texto(c.get('submarca')) + ' ' + texto(c.get('version'))).normalizeSpace();
		}
		poner(d, 'descripcion', descripcion.toUpperCase());
		poner(d, 'serie', codigo(texto(c.get('serie'))));
		poner(d, 'placas', codigo(texto(c.get('placas'))));
		poner(d, 'uso', texto(c.get('uso')));
		String modelo = texto(c.get('modelo')).replaceAll('[^0-9]', '');
		if (modelo.length() == 4) { d.put('modelo', Integer.valueOf(modelo)); }
		return d;
	}

	static Map<String, Object> datosUbicacion(Map<String, Object> c) {
		Map<String, Object> d = new Map<String, Object>();
		poner(d, 'nombre', texto(c.get('ubicacion')));
		String direccion = texto(c.get('direccion'));
		List<String> partes = new List<String>();
		if (String.isNotBlank(direccion)) { partes.add(direccion); }
		if (String.isNotBlank(texto(c.get('colonia')))) { partes.add('Col. ' + texto(c.get('colonia'))); }
		if (String.isNotBlank(texto(c.get('cp')))) { partes.add('CP ' + texto(c.get('cp'))); }
		for (String k : new List<String>{ 'municipio', 'estado' }) {
			if (String.isNotBlank(texto(c.get(k)))) { partes.add(texto(c.get(k))); }
		}
		poner(d, 'direccion', String.join(partes, ', '));
		poner(d, 'giro', texto(c.get('giro')));
		Decimal suma = numero(c.get('suma'));
		if (suma != null) { d.put('sumaAsegurada', suma); }
		return d;
	}

	static Map<String, Object> datosPersona(Map<String, Object> c) {
		Map<String, Object> d = new Map<String, Object>();
		poner(d, 'nombre', texto(c.get('nombre')));
		poner(d, 'apellidos', (texto(c.get('paterno')) + ' ' + texto(c.get('materno'))).normalizeSpace());
		if (!d.containsKey('nombre')) { poner(d, 'nombreCompleto', texto(c.get('nombreCompleto'))); }
		String nacimiento = texto(c.get('nacimiento'));
		if (CensoColectivoController.fecha(nacimiento) != null) { d.put('fechaNacimiento', nacimiento.left(10)); }
		poner(d, 'sexo', texto(c.get('sexo')));
		poner(d, 'parentesco', texto(c.get('parentesco')));
		poner(d, 'email', texto(c.get('correo')));
		poner(d, 'certificado', texto(c.get('certificado')));
		return d;
	}

	static void poner(Map<String, Object> d, String k, String v) {
		if (String.isNotBlank(v)) { d.put(k, v.trim()); }
	}

	static String texto(Object v) {
		return v == null ? '' : String.valueOf(v).normalizeSpace();
	}

	static Decimal numero(Object v) {
		String s = texto(v).replaceAll('[^0-9.\\-]', '');
		if (String.isBlank(s)) { return null; }
		try { return Decimal.valueOf(s); } catch (Exception e) { return null; }
	}

	/** Serie, placas, inciso o certificado para comparar: mayúsculas, sin espacios ni guiones. */
	static String codigo(String s) {
		return s == null ? '' : s.toUpperCase().replaceAll('[^A-Z0-9]', '');
	}

	/** Nombre para comparar sin importar el orden de nombres y apellidos, acentos ni mayúsculas. */
	static String llaveNombre(String s) {
		List<String> palabras = CensoColectivoController.llave(s == null ? '' : s).split(' ');
		palabras.sort();
		return String.join(palabras, ' ').trim();
	}

	// ---------------------------------------------------------------- Pestañas con los componentes de Salesforce

	/**
	 * @creation date: 18/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Datos de las pestañas Asegurados / Vehículos / Ubicaciones y Participantes tal cual las muestra
	 * Salesforce: el sitio usa los mismos componentes (movimientosColectivo, movimientosFlotilla,
	 * movimientosUbicaciones y participantesPoliza) en solo lectura. Valida que la póliza sea del usuario y llama a
	 * los mismos controladores de Salesforce (inherited sharing, así que aquí corren sin compartir). Quien no es el
	 * contratante solo ve a su grupo familiar (y sus beneficiarios). No se entregan las solicitudes pendientes (el
	 * sitio tiene su pestaña Solicitudes) ni los archivos de cada persona.
	 * @param policyId: Id de la póliza
	 * @param cuentaVistaPrevia: Cuenta a simular (solo vista previa de administrador); null para el usuario real
	 * @param tipo: asegurados | vehiculos | ubicaciones | participantes
	 * @return Mismo mapa que el getDatos del controlador de Salesforce
	 */
	@AuraEnabled
	public static Map<String, Object> datosComponente(Id policyId, Id cuentaVistaPrevia, String tipo) {
		try {
			Map<Id, String> roles = PortalPolizasController.validarAcceso(policyId, cuentaVistaPrevia);
			Boolean soloMiGrupo = roles.get(policyId) != 'Titular';
			Map<String, Object> res;
			if (tipo == 'vehiculos') {
				res = MovimientosFlotillaController.getDatos(policyId);
			} else if (tipo == 'ubicaciones') {
				res = MovimientosUbicacionesController.getDatos(policyId);
			} else if (tipo == 'participantes') {
				res = ParticipantesPolizaController.getDatos(policyId);
				filtrarParticipantes(res, soloMiGrupo ? idsVisibles(policyId, cuentaVistaPrevia) : null);
			} else if (tipo == 'asegurados') {
				res = MovimientosColectivoController.getDatos(policyId);
				if (soloMiGrupo) { filtrarAsegurados(res, idsVisibles(policyId, cuentaVistaPrevia)); }
			} else {
				throw new AuraHandledException('Pestaña no válida.');
			}
			res.put('solicitudes', new List<Object>());
			res.put('portal', true);
			res.put('soloMiGrupo', soloMiGrupo && (tipo == 'asegurados' || tipo == 'participantes'));
			return res;
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			throw PortalPolizasController.errorSitio(e);
		}
	}

	/** Participantes de la póliza que ve un usuario que no es el contratante (su grupo familiar). */
	static Set<String> idsVisibles(Id policyId, Id cuentaVistaPrevia) {
		Set<String> ids = new Set<String>();
		for (InsurancePolicyParticipant pp : participantesVisibles(policyId, true, cuentaVistaPrevia, new Bienes())) {
			ids.add((String) pp.Id);
		}
		return ids;
	}

	/** Asegurados: deja solo los del grupo y los movimientos de esas personas. */
	static void filtrarAsegurados(Map<String, Object> res, Set<String> visibles) {
		List<Object> miembros = new List<Object>();
		Set<String> nombres = new Set<String>();
		for (Object o : (List<Object>) res.get('miembros')) {
			Map<String, Object> m = (Map<String, Object>) o;
			if (visibles.contains(String.valueOf(m.get('id')))) {
				miembros.add(m);
				if (m.get('nombre') != null) { nombres.add(String.valueOf(m.get('nombre')).toUpperCase()); }
			}
		}
		res.put('miembros', miembros);
		List<Object> movimientos = new List<Object>();
		for (Object o : res.get('movimientos') == null ? new List<Object>() : (List<Object>) res.get('movimientos')) {
			Object asegurado = ((Map<String, Object>) o).get('asegurado');
			if (asegurado != null && nombres.contains(String.valueOf(asegurado).toUpperCase())) { movimientos.add(o); }
		}
		res.put('movimientos', movimientos);
	}

	/** Participantes: quita los archivos de cada persona y, si aplica, deja solo los del grupo (recalcula el resumen). */
	static void filtrarParticipantes(Map<String, Object> res, Set<String> visibles) {
		List<Object> lista = new List<Object>();
		Map<String, Integer> resumen = (Map<String, Integer>) res.get('resumen');
		if (visibles != null) {
			for (String k : resumen.keySet()) { resumen.put(k, 0); }
		}
		for (Object o : (List<Object>) res.get('participantes')) {
			Map<String, Object> m = (Map<String, Object>) o;
			m.put('archivos', new List<Object>());
			if (visibles != null) {
				if (!visibles.contains(String.valueOf(m.get('id')))) { continue; }
				String grupo = (String) m.get('grupo');
				String estado = m.get('activo') == true ? 'vigentes' : 'bajas';
				if (grupo != null) { resumen.put(grupo, (resumen.containsKey(grupo) ? resumen.get(grupo) : 0) + 1); }
				resumen.put(estado, (resumen.containsKey(estado) ? resumen.get(estado) : 0) + 1);
			}
			lista.add(m);
		}
		res.put('participantes', lista);
	}
}
