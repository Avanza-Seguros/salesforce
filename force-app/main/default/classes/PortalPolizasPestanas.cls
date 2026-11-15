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
			salida.tipo = tipoRamo(p.Ramo__c);
			if (salida.tipo != 'personas') { return salida; }

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
				f.desde = pp.EffectiveFromDate;
				f.hasta = pp.EffectiveToDate;
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
				TermPremiumAmount, EffectiveFromDate, EffectiveToDate, IsActiveParticipant, Motivo_Baja__c,
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
			f.desde = pp.EffectiveFromDate;
			f.hasta = pp.EffectiveToDate;
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
}
