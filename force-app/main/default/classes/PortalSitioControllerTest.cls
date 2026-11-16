/**
 * @creation date: 16/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Pruebas de PortalSitioController: encabezado, personas de la empresa y ejecutivo de cuenta.
 */
@isTest
private class PortalSitioControllerTest {

	/**
	 * @creation date: 16/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: El encabezado trae al usuario y el menú del sitio.
	 * @return void
	 */
	@isTest
	static void testEncabezado() {
		PortalSitioController.Enlace hijo = new PortalSitioController.Enlace();
		hijo.etiqueta = 'Peticiones';
		hijo.tipo = 'SalesforceObject';
		PortalSitioController.Enlace padre = new PortalSitioController.Enlace();
		padre.etiqueta = 'Movimientos';
		padre.tipo = 'MenuLabel';
		padre.hijos.add(hijo);
		PortalSitioController.menuPrueba = new List<PortalSitioController.Enlace>{ padre };

		Test.startTest();
		PortalSitioController.Encabezado e = PortalSitioController.encabezado();
		Test.stopTest();

		System.assertEquals(UserInfo.getUserId(), e.usuarioId, 'Usuario actual');
		System.assertEquals(true, e.interno, 'Usuario interno');
		System.assertEquals(1, e.menu.size(), 'Menú de prueba');
		System.assertEquals(1, e.menu[0].hijos.size(), 'Con su submenú');
		System.assertEquals('JP', PortalSitioController.iniciales('juan', 'pérez'), 'Iniciales');
		System.assertEquals('?', PortalSitioController.iniciales(null, ' '), 'Sin nombre');
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Conversión del menú: etiquetas con hijos, enlaces y elementos que no se muestran.
	 * @return void
	 */
	@isTest
	static void testEnlaceMenu() {
		ConnectApi.NavigationMenuItem interno = new ConnectApi.NavigationMenuItem();
		interno.label = 'Mis pólizas';
		interno.actionType = ConnectApi.NavigationMenuItemActionType.InternalLink;
		interno.actionValue = '/mis-polizas';
		interno.target = ConnectApi.NavigationMenuItemOpenTarget.NewWindow;
		ConnectApi.NavigationMenuItem accion = new ConnectApi.NavigationMenuItem();
		accion.label = 'Calendario';
		accion.actionType = ConnectApi.NavigationMenuItemActionType.Event;
		accion.actionValue = 'abrirCalendario';
		ConnectApi.NavigationMenuItem grupo = new ConnectApi.NavigationMenuItem();
		grupo.label = 'Movimientos';
				grupo.subMenu = new List<ConnectApi.NavigationMenuItem>{ interno, accion };
		ConnectApi.NavigationMenuItem vacio = new ConnectApi.NavigationMenuItem();
		vacio.label = 'Vacío';
		
		PortalSitioController.Enlace e = PortalSitioController.enlace(grupo);
		System.assertEquals(1, e.hijos.size(), 'Solo el enlace interno');
		System.assertEquals('/mis-polizas', e.hijos[0].valor, 'Ruta del enlace');
		System.assertEquals(true, e.hijos[0].nuevaVentana, 'Abre en otra ventana');
		System.assertEquals(null, PortalSitioController.enlace(accion), 'Las acciones no se muestran');
		System.assertEquals(null, PortalSitioController.enlace(vacio), 'Etiqueta sin hijos no se muestra');
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Contactos de la cuenta del usuario con sus productos activos; sin cuenta no hay contactos.
	 * @return void
	 */
	@isTest
	static void testContactos() {
		Account cuenta = new Account(Name = 'Empresa Contactos');
		insert cuenta;
		GroupCensus censo = new GroupCensus(Name = 'Censo prueba', AccountId = cuenta.Id, Status = 'Draft', Type = 'Quote');
		insert censo;
		GroupCensusMember titular = new GroupCensusMember(Name = 'ANA LOPEZ', FirstName = 'ANA', Lastname = 'LOPEZ',
			GroupCensusId = censo.Id, RelationshipToPrimaryMember = 'Self', Certificado__c = '0000000001',
			Birthdate = Date.today().addYears(-30), JoinDate = Date.newInstance(2020, 1, 1), Prima__c = 1000);
		insert titular;
		insert new GroupCensusMember(Name = 'LUIS LOPEZ', FirstName = 'LUIS', Lastname = 'LOPEZ', GroupCensusId = censo.Id,
			RelationshipToPrimaryMember = 'Secundario', PrimaryGroupCensusMemberId = titular.Id, Certificado__c = '0000000001', Edad__c = 4, Prima__c = 500);

		Test.startTest();
		PortalSitioController.Contactos vacio = PortalSitioController.contactos(null);
		PortalPolizasController.cuentaPrueba = cuenta.Id;
		PortalSitioController.Contactos c = PortalSitioController.contactos(null);
		Test.stopTest();

		System.assertEquals(0, vacio.personas.size(), 'Sin cuenta no hay personas');
		System.assertEquals('Empresa Contactos', c.cuenta, 'Nombre de la cuenta');
		System.assertEquals(2, c.personas.size(), 'Titular y dependiente');
		System.assertEquals('ANA LOPEZ', c.personas[0].nombre, 'El titular va primero');
		System.assertEquals('Titular', c.personas[0].parentesco, 'Parentesco del titular');
		System.assertEquals(30, c.personas[0].edad, 'Edad por fecha de nacimiento');
		System.assertEquals(false, c.personas[1].titular, 'Dependiente');
		System.assertEquals('ANA LOPEZ', c.personas[1].titularNombre, 'Titular del dependiente');
		System.assertEquals(4, c.personas[1].edad, 'Sin nacimiento usa la edad del censo');
		System.assertEquals(Date.newInstance(2020, 1, 1), c.personas[1].alta, 'El dependiente toma el alta del titular');
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Sin agente en las pólizas, el ejecutivo es el propietario de la cuenta.
	 * @return void
	 */
	@isTest
	static void testEjecutivo() {
		Account cuenta = new Account(Name = 'Empresa Ejecutivo');
		insert cuenta;

		Test.startTest();
		PortalSitioController.Ejecutivo sinCuenta = PortalSitioController.ejecutivo(null);
		PortalPolizasController.cuentaPrueba = cuenta.Id;
		PortalSitioController.Ejecutivo e = PortalSitioController.ejecutivo(null);
		Test.stopTest();

		System.assertEquals(null, sinCuenta, 'Sin cuenta no hay ejecutivo');
		System.assertNotEquals(null, e, 'El propietario de la cuenta');
		System.assertEquals(UserInfo.getName(), e.nombre, 'Nombre del ejecutivo');
	}
}
