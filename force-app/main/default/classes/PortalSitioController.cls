/**
 * @creation date: 16/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Datos generales del sitio Avanza Seguro: el menú y el usuario para el encabezado, las personas de la
 * empresa del cliente (página Contactos) y su ejecutivo de cuenta. Sin sharing porque el usuario del sitio no ve los
 * registros de su empresa; todo se limita a la cuenta del usuario (o a la de la vista previa del administrador).
 */
public without sharing class PortalSitioController {
	@TestVisible static final String MENU = 'Default Navigation';
	@TestVisible static List<Enlace> menuPrueba;

	public class Enlace {
		@AuraEnabled public String etiqueta;
		@AuraEnabled public String tipo;
		@AuraEnabled public String valor;
		@AuraEnabled public Boolean nuevaVentana = false;
		@AuraEnabled public List<Enlace> hijos = new List<Enlace>();
	}

	public class Encabezado {
		@AuraEnabled public String nombre;
		@AuraEnabled public String iniciales;
		@AuraEnabled public String cuenta;
		@AuraEnabled public String foto;
		@AuraEnabled public Id usuarioId;
		@AuraEnabled public Boolean interno = false;
		@AuraEnabled public List<Enlace> menu = new List<Enlace>();
	}

	public class Persona {
		@AuraEnabled public Id id;
		@AuraEnabled public String nombre;
		@AuraEnabled public String puesto;
		@AuraEnabled public String area;
		@AuraEnabled public String correo;
		@AuraEnabled public String telefono;
		@AuraEnabled public String celular;
		@AuraEnabled public Date nacimiento;
		@AuraEnabled public Date ingreso;
		@AuraEnabled public Boolean activo = false;
		@AuraEnabled public Boolean cumpleHoy = false;
		@AuraEnabled public String certificado;
		@AuraEnabled public String parentesco;
		@AuraEnabled public List<String> productos = new List<String>();
	}

	public class Contactos {
		@AuraEnabled public String cuenta;
		@AuraEnabled public List<Persona> personas = new List<Persona>();
	}

	public class Ejecutivo {
		@AuraEnabled public String nombre;
		@AuraEnabled public String puesto;
		@AuraEnabled public String correo;
		@AuraEnabled public String telefono;
		@AuraEnabled public String foto;
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Usuario y menú del encabezado. El menú es el «Default Navigation» publicado del sitio, con sus
	 * submenús; los elementos que no son enlaces (acciones globales, eventos) se omiten.
	 * @return Encabezado
	 */
	@AuraEnabled(cacheable=true)
	public static Encabezado encabezado() {
		try {
			Encabezado e = new Encabezado();
			User u = [
				SELECT Id, FirstName, LastName, Name, SmallPhotoUrl, UserType, Contact.Account.Name, CompanyName
				FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1
			];
			e.usuarioId = u.Id;
			e.nombre = u.Name;
			e.iniciales = iniciales(u.FirstName, u.LastName);
			e.cuenta = u.Contact?.Account?.Name != null ? u.Contact.Account.Name : u.CompanyName;
			e.foto = u.SmallPhotoUrl != null && !u.SmallPhotoUrl.contains('/profilephoto/005/') ? u.SmallPhotoUrl : null;
			e.interno = u.UserType == 'Standard';
			e.menu = menu();
			return e;
		} catch (Exception ex) {
			throw PortalPolizasController.errorSitio(ex);
		}
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Menú publicado del sitio actual (Connect API). Fuera de un sitio (o en pruebas) no hay menú.
	 * @return Elementos del menú de primer nivel con sus hijos
	 */
	static List<Enlace> menu() {
		if (Test.isRunningTest()) { return menuPrueba == null ? new List<Enlace>() : menuPrueba; }
		List<Enlace> salida = new List<Enlace>();
		Id red = Network.getNetworkId();
		if (red == null) { return salida; }
		List<NavigationLinkSet> menus = [
			SELECT Id FROM NavigationLinkSet WHERE NetworkId = :red AND MasterLabel = :MENU
			ORDER BY CreatedDate LIMIT 1
		];
		if (menus.isEmpty()) { return salida; }
		ConnectApi.NavigationMenuItemCollection elementos = ConnectApi.NavigationMenu.getCommunityNavigationMenu(
			red, menus[0].Id, null, ConnectApi.PublishStatus.Live, false, false,
			new List<ConnectApi.NavigationMenuItemType>()
		);
		for (ConnectApi.NavigationMenuItem i : elementos.menuItems) {
			Enlace en = enlace(i);
			if (en != null) { salida.add(en); }
		}
		return salida;
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Convierte un elemento del menú publicado: enlaces internos y externos con su ruta, y agrupaciones
	 * (sin ruta) con sus hijos. Eventos y ventanas modales no se muestran.
	 * @param i: Elemento del menú
	 * @return Enlace o null si no se puede mostrar
	 */
	@TestVisible
	static Enlace enlace(ConnectApi.NavigationMenuItem i) {
		Enlace e = new Enlace();
		e.etiqueta = i.label;
		e.tipo = i.actionType == null ? null : String.valueOf(i.actionType);
		e.valor = i.actionValue;
		e.nuevaVentana = i.target == ConnectApi.NavigationMenuItemOpenTarget.NewWindow;
		if (i.subMenu != null) {
			for (ConnectApi.NavigationMenuItem h : i.subMenu) {
				Enlace eh = enlace(h);
				if (eh != null) { e.hijos.add(eh); }
			}
		}
		if (String.isBlank(e.valor)) { return e.hijos.isEmpty() ? null : e; }
		return e.tipo == 'InternalLink' || e.tipo == 'ExternalLink' ? e : null;
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Personas (contactos) de la empresa del usuario, activas primero y por nombre, con los productos
	 * en los que están activas (GMM, Vida, Dental, Adicional).
	 * @param cuentaVistaPrevia: Cuenta a simular (solo vista previa de administrador); null para el usuario real
	 * @return Contactos
	 */
	@AuraEnabled(cacheable=true)
	public static Contactos contactos(Id cuentaVistaPrevia) {
		try {
			Contactos c = new Contactos();
			Id cuenta = PortalPolizasController.identidad(cuentaVistaPrevia)[0];
			if (cuenta == null) { return c; }
			c.cuenta = [SELECT Name FROM Account WHERE Id = :cuenta LIMIT 1].Name;
			for (Contact x : [
				SELECT Id, Name, Title, Department, Email, Phone, MobilePhone, Birthdate, Fecha_de_ingreso_a_la_empresa__c,
					Activo__c, Activo_GMM__c, Activo_Vida__c, Activo_Dentegra__c, Activo_Adicional__c, Cumplea_os_Hoy__c,
					Certificado_GMM__c, toLabel(Parentesco_GMM__c)
				FROM Contact
				WHERE AccountId = :cuenta
				ORDER BY Activo__c DESC, Name ASC
				LIMIT 3000
			]) {
				Persona p = new Persona();
				p.id = x.Id;
				p.nombre = x.Name;
				p.puesto = x.Title;
				p.area = x.Department;
				p.correo = x.Email;
				p.telefono = x.Phone;
				p.celular = x.MobilePhone;
				p.nacimiento = x.Birthdate;
				p.ingreso = x.Fecha_de_ingreso_a_la_empresa__c;
				p.activo = x.Activo__c == true;
				p.cumpleHoy = x.Cumplea_os_Hoy__c == true;
				p.certificado = x.Certificado_GMM__c;
				p.parentesco = x.Parentesco_GMM__c;
				if (x.Activo_GMM__c == true) { p.productos.add('GMM'); }
				if (x.Activo_Vida__c == true) { p.productos.add('Vida'); }
				if (x.Activo_Dentegra__c == true) { p.productos.add('Dental'); }
				if (x.Activo_Adicional__c == true) { p.productos.add('Adicional'); }
				c.personas.add(p);
			}
			return c;
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			throw PortalPolizasController.errorSitio(e);
		}
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Ejecutivo de la cuenta del cliente: el agente (Producer con usuario interno) de su póliza vigente
	 * más reciente; si no hay, el propietario de la cuenta.
	 * @param cuentaVistaPrevia: Cuenta a simular (solo vista previa de administrador); null para el usuario real
	 * @return Ejecutivo o null si la cuenta no tiene
	 */
	@AuraEnabled(cacheable=true)
	public static Ejecutivo ejecutivo(Id cuentaVistaPrevia) {
		try {
			Id cuenta = PortalPolizasController.identidad(cuentaVistaPrevia)[0];
			if (cuenta == null) { return null; }
			Id usuario;
			for (InsurancePolicy p : [
				SELECT Producer.InternalUserId FROM InsurancePolicy
				WHERE NameInsuredId = :cuenta AND Producer.InternalUserId != null
				ORDER BY IsActive DESC, ExpirationDate DESC NULLS LAST LIMIT 1
			]) {
				usuario = p.Producer.InternalUserId;
			}
			if (usuario == null) {
				usuario = [SELECT OwnerId FROM Account WHERE Id = :cuenta LIMIT 1].OwnerId;
			}
			List<User> us = [
				SELECT Name, Title, Email, Phone, MobilePhone, SmallPhotoUrl, IsActive FROM User
				WHERE Id = :usuario AND IsActive = true AND UserType = 'Standard' LIMIT 1
			];
			if (us.isEmpty()) { return null; }
			Ejecutivo e = new Ejecutivo();
			e.nombre = us[0].Name;
			e.puesto = us[0].Title;
			e.correo = us[0].Email;
			e.telefono = String.isNotBlank(us[0].Phone) ? us[0].Phone : us[0].MobilePhone;
			e.foto = us[0].SmallPhotoUrl != null && !us[0].SmallPhotoUrl.contains('/profilephoto/005/') ? us[0].SmallPhotoUrl : null;
			return e;
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			throw PortalPolizasController.errorSitio(e);
		}
	}

	/**
	 * @creation date: 16/11/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Iniciales para el avatar.
	 * @param nombre: Nombre
	 * @param apellido: Apellido
	 * @return Hasta dos letras en mayúsculas
	 */
	@TestVisible
	static String iniciales(String nombre, String apellido) {
		String a = String.isBlank(nombre) ? '' : nombre.trim().left(1);
		String b = String.isBlank(apellido) ? '' : apellido.trim().left(1);
		String r = (a + b).toUpperCase();
		return String.isBlank(r) ? '?' : r;
	}
}
