/**
 *   @name: CorreosOportunidadTest
 *   @version: 1.0
 *   @creation date: 19/11/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Pruebas de CorreosOportunidad.
 */
@isTest
private class CorreosOportunidadTest {

	@isTest
	static void devuelveCorreosDeClienteYAgente() {
		Account acc = new Account(Name = 'Cliente Prueba Correo', Correo_electronico__c = 'cliente@prueba.com');
		insert acc;
		Producer p = new Producer(Name = 'Agente Prueba Correo', InternalUserId = UserInfo.getUserId());
		insert p;
		Opportunity o = new Opportunity(Name = 'Opp correo', AccountId = acc.Id, StageName = 'Gestion Comercial',
			CloseDate = Date.today().addDays(10), Producer__c = p.Id);
		insert o;

		Test.startTest();
		List<CorreosOportunidad.Resultado> r = CorreosOportunidad.obtener(new List<Id>{ o.Id });
		Test.stopTest();

		Assert.areEqual('cliente@prueba.com', r[0].cliente, 'Correo del cliente');
		Assert.areEqual([SELECT Email FROM User WHERE Id = :UserInfo.getUserId()].Email, r[0].agente, 'Correo del agente');
		Assert.areEqual(UserInfo.getUserId(), r[0].agenteUsuarioId, 'Usuario del agente');
	}

	@isTest
	static void sinOportunidadDevuelveVacio() {
		Account acc = new Account(Name = 'Cuenta borrada');
		insert acc;
		Opportunity o = new Opportunity(Name = 'Opp borrada', AccountId = acc.Id, StageName = 'Gestion Comercial',
			CloseDate = Date.today().addDays(10));
		insert o;
		Id oppId = o.Id;
		delete o;
		List<CorreosOportunidad.Resultado> r = CorreosOportunidad.obtener(new List<Id>{ oppId });
		Assert.isNull(r[0].cliente, 'Sin oportunidad no hay correo');
	}
}
