/**
 *   @name: FleetIncisoService
 *   @version: 1.0
 *   @creation date: 08/11/2026
 *   @author: Javier Torres - Volestra
 *   @description: Reglas del inciso de una flotilla o del certificado de una colectiva, en un solo
 *                 sitio para el motor de cobranza y la pestaña Pagos.
 *                 - El número de inciso de un bien está en AssetCode; los bienes creados antes lo
 *                   llevan al principio del nombre («Inciso 3 - Av. Vallarta…»).
 *                 - El de una persona está en ParticipantCode.
 *                 - HDI numera sus certificados como «49-<póliza>-<inciso>»: el pago de un
 *                   certificado se busca en su póliza madre cuando no existe una póliza con ese
 *                   número exacto.
 *                 Los números se comparan sin ceros a la izquierda: «007» y «7» son el mismo inciso.
 */
public with sharing class FleetIncisoService {
	@TestVisible
	private static final String HDI_CARRIER_PATTERN = 'HDI%';
	private static final Pattern HDI_CERTIFICATE = Pattern.compile(
		'^(49-\\d+)-(\\d+)$'
	);
	private static final Pattern NAME_PREFIX = Pattern.compile(
		'^(?i)inciso\\s+(\\d+)\\b.*'
	);

	/**
	 * @creation date: 08/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Número de la póliza madre de un certificado de HDI («49-4785-42» → «49-4785»).
	 * @param policyNumber: Número tal como llega en el pago.
	 * @return Número de la póliza madre, o null si el número no tiene la forma de un certificado.
	 */
	public static String fleetNumberOf(String policyNumber) {
		Matcher m = certificateMatcher(policyNumber);
		return m == null ? null : m.group(1);
	}

	/**
	 * @creation date: 08/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Inciso de un certificado de HDI («49-4785-42» → «42»).
	 * @param policyNumber: Número tal como llega en el pago.
	 * @return Inciso normalizado, o null si el número no tiene la forma de un certificado.
	 */
	public static String certificateOf(String policyNumber) {
		Matcher m = certificateMatcher(policyNumber);
		return m == null ? null : normalize(m.group(2));
	}

	private static Matcher certificateMatcher(String policyNumber) {
		if (String.isBlank(policyNumber)) {
			return null;
		}
		Matcher m = HDI_CERTIFICATE.matcher(policyNumber.trim().toUpperCase());
		return m.matches() ? m : null;
	}

	/**
	 * @creation date: 08/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Pólizas madre de HDI de los certificados que no tienen póliza propia. Solo HDI:
	 *               en otras aseguradoras un número con guiones no es un certificado.
	 * @param unresolvedNumbers: Números de pago (en mayúsculas) sin póliza con ese número exacto.
	 * @return Por número de pago, las vigencias de su póliza madre.
	 */
	public static Map<String, List<InsurancePolicy>> fleetPoliciesFor(
		Set<String> unresolvedNumbers
	) {
		Map<String, List<InsurancePolicy>> result = new Map<String, List<InsurancePolicy>>();
		Map<String, Set<String>> paymentsByFleet = new Map<String, Set<String>>();
		for (String num : unresolvedNumbers) {
			String fleet = fleetNumberOf(num);
			if (fleet == null) {
				continue;
			}
			if (!paymentsByFleet.containsKey(fleet)) {
				paymentsByFleet.put(fleet, new Set<String>());
			}
			paymentsByFleet.get(fleet).add(num);
		}
		if (paymentsByFleet.isEmpty()) {
			return result;
		}
		for (InsurancePolicy policy : [
			SELECT Id, Name, PolicyName, Status, EffectiveDate, ExpirationDate
			FROM InsurancePolicy
			WHERE
				Name IN :paymentsByFleet.keySet()
				AND Aseguradora__r.Name LIKE :HDI_CARRIER_PATTERN
		]) {
			Set<String> payments = paymentsByFleet.get(policy.Name.toUpperCase());
			if (payments == null) {
				continue;
			}
			for (String num : payments) {
				if (!result.containsKey(num)) {
					result.put(num, new List<InsurancePolicy>());
				}
				result.get(num).add(policy);
			}
		}
		return result;
	}

	/**
	 * @creation date: 08/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Inciso de un recibo: el del bien o el de la persona a la que apunta. Requiere
	 *               policyAsset__r.AssetCode, policyAsset__r.AssetName y
	 *               policyParticipant__r.ParticipantCode en la consulta.
	 * @param installment: Cuota.
	 * @return Inciso normalizado, o null si el recibo no es de un inciso.
	 */
	public static String incisoOf(PaymentPlanInstallment__c installment) {
		if (installment.policyAsset__c != null) {
			return incisoOf(installment.policyAsset__r);
		}
		if (installment.policyParticipant__c != null) {
			return normalize(installment.policyParticipant__r?.ParticipantCode);
		}
		return null;
	}

	/**
	 * @creation date: 08/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Inciso de un bien: AssetCode y, si está vacío, el prefijo «Inciso N - » del nombre.
	 * @param asset: Bien de la póliza con AssetCode y AssetName.
	 * @return Inciso normalizado, o null.
	 */
	public static String incisoOf(InsurancePolicyAsset asset) {
		if (asset == null) {
			return null;
		}
		String code = normalize(asset.AssetCode);
		if (code != null || asset.AssetName == null) {
			return code;
		}
		Matcher m = NAME_PREFIX.matcher(asset.AssetName.trim());
		return m.matches() ? normalize(m.group(1)) : null;
	}

	/**
	 * @creation date: 08/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Quita espacios y ceros a la izquierda de un número de inciso o certificado.
	 * @param code: Número tal como está guardado.
	 * @return Número normalizado, o null si está vacío.
	 */
	public static String normalize(String code) {
		if (String.isBlank(code)) {
			return null;
		}
		String trimmed = code.trim();
		if (!trimmed.isNumeric()) {
			return trimmed.toUpperCase();
		}
		String withoutZeros = trimmed.replaceFirst('^0+', '');
		return withoutZeros == '' ? '0' : withoutZeros;
	}

	/**
	 * @creation date: 08/11/2026
	 * @author: Javier Torres - Volestra
	 * @description: Deja solo los recibos del inciso que paga el certificado. Si el pago no es de un
	 *               certificado, o la póliza no tiene recibos por inciso, no filtra nada: así una
	 *               póliza individual se concilia igual que siempre.
	 * @param policyNumber: Número de póliza del pago.
	 * @param installments: Cuotas que el pago puede tomar.
	 * @return Las cuotas de su inciso, o todas.
	 */
	public static List<PaymentPlanInstallment__c> onlyItsInciso(
		String policyNumber,
		List<PaymentPlanInstallment__c> installments
	) {
		String inciso = certificateOf(policyNumber);
		if (inciso == null || installments == null) {
			return installments;
		}
		Boolean byInciso = false;
		List<PaymentPlanInstallment__c> own = new List<PaymentPlanInstallment__c>();
		for (PaymentPlanInstallment__c inst : installments) {
			String code = incisoOf(inst);
			if (code == null) {
				continue;
			}
			byInciso = true;
			if (code == inciso) {
				own.add(inst);
			}
		}
		return byInciso ? own : installments;
	}
}
