/**
 *   @name: CorreosOportunidad
 *   @version: 1.0
 *   @creation date: 19/11/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Acción para Flows que devuelve los correos de una oportunidad tal como se muestran en el formulario:
 *                 "Email cliente" (correo de la cuenta) y "Email Agente" (correo del Producer). La usa el Flow
 *                 "Enviar Correo Oportunidad" para mandar el correo a esas direcciones.
 */
public with sharing class CorreosOportunidad {

	public class Resultado {
		@InvocableVariable(label='Correo del cliente')
		public String cliente;
		@InvocableVariable(label='Correo del agente')
		public String agente;
		@InvocableVariable(label='Usuario interno del agente (para el saludo si no tiene contacto)')
		public Id agenteUsuarioId;
	}

	/**
	 * @creation date: 19/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Correos del cliente y del agente de cada oportunidad.
	 * @param oportunidadIds: Ids de las oportunidades
	 * @return Un resultado por oportunidad, en el mismo orden
	 */
	@InvocableMethod(label='Correos de la oportunidad (cliente y agente)' category='Correo')
	public static List<Resultado> obtener(List<Id> oportunidadIds) {
		Map<Id, Opportunity> opps = new Map<Id, Opportunity>([
			SELECT Id, Producer__c, Producer__r.InternalUserId, Account.PersonEmail, Account.Correo_electronico__c
			FROM Opportunity WHERE Id IN :oportunidadIds
		]);
		List<Resultado> out = new List<Resultado>();
		for (Id oppId : oportunidadIds) {
			Resultado r = new Resultado();
			Opportunity o = opps.get(oppId);
			if (o != null) {
				if (o.Account != null) {
					r.cliente = String.isNotBlank(o.Account.PersonEmail) ? o.Account.PersonEmail : o.Account.Correo_electronico__c;
				}
				if (o.Producer__c != null) {
					r.agente = OpportunityController.getProducerEmail(o.Producer__c);
					r.agenteUsuarioId = o.Producer__r.InternalUserId;
				}
			}
			out.add(r);
		}
		return out;
	}
}
