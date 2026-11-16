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
		insert new List<Contact>{
			new Contact(AccountId = cuenta.Id, LastName = 'Activo', FirstName = 'Ana', Title = 'Gerente', Email = 'ana@example.com',
				Activo__c = true, Activo_GMM__c = true, Activo_Vida__c = true),
			new Contact(AccountId = cuenta.Id, LastName = 'Baja', FirstName = 'Beto', Activo__c = false, Activo_Dentegra__c = true,
				Activo_Adicional__c = true)
		};

		Test.startTest();
		PortalSitioController.Contactos vacio = PortalSitioController.contactos(null);
		PortalPolizasController.cuentaPrueba = cuenta.Id;
		PortalSitioController.Contactos c = PortalSitioController.contactos(null);
		Test.stopTest();

		System.assertEquals(0, vacio.personas.size(), 'Sin cuenta no hay contactos');
		System.assertEquals('Empresa Contactos', c.cuenta, 'Nombre de la cuenta');
		System.assertEquals(2, c.personas.size(), 'Dos personas');
		System.assertEquals(true, c.personas[0].activo, 'Activos primero');
		System.assertEquals(new List<String>{ 'GMM', 'Vida' }, c.personas[0].productos, 'Productos del activo');
		System.assertEquals(new List<String>{ 'Dental', 'Adicional' }, c.personas[1].productos, 'Productos del inactivo');
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
