/**
 * @creation date: 16/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Datos generales del sitio Avanza Seguro: el menú y el usuario para el encabezado, las personas de la
 * empresa del cliente (página Mi empresa, desde el censo) y su ejecutivo de cuenta. Sin sharing porque el usuario del sitio no ve los
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
		@AuraEnabled public String parentesco;
		@AuraEnabled public Boolean titular = false;
		@AuraEnabled public String titularNombre;
		@AuraEnabled public String certificado;
		@AuraEnabled public Date nacimiento;
		@AuraEnabled public Integer edad;
		@AuraEnabled public String genero;
		@AuraEnabled public String grupo;
		@AuraEnabled public Date alta;
		@AuraEnabled public Decimal prima;
		@AuraEnabled public Decimal sumaAsegurada;
		@AuraEnabled public String correo;
		@AuraEnabled public String telefono;
		@AuraEnabled public String ramo;
	}

	public class Contactos {
		@AuraEnabled public String cuenta;
		@AuraEnabled public List<Persona> personas = new List<Persona>();
	}

	// Parentesco del censo (RelationshipToPrimaryMember) como se muestra en el sitio.
	static final Map<String, String> PARENTESCOS = new Map<String, String>{
		'Self' => 'Titular', 'Auto' => 'Titular', 'Principal' => 'Titular', 'Cónyuge' => 'Cónyuge',
		'Secundario' => 'Dependiente', 'Suegro' => 'Suegro(a)', 'Otros' => 'Otro'
	};

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
	 * @description: Personas de la empresa del usuario tomadas del censo (GroupCensusMember): titulares, cónyuges y
	 * dependientes vigentes (las bajas se borran del censo). Si la cuenta tiene varios censos, se usa el más reciente de
	 * cada ramo. Orden: ramo, certificado y el titular antes que sus dependientes.
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

			// El censo más reciente de cada ramo.
			Map<String, Id> censoPorRamo = new Map<String, Id>();
			Map<Id, String> ramoDelCenso = new Map<Id, String>();
			for (GroupCensus g : [
				SELECT Id, toLabel(Oportunidad__r.Ramo__c) FROM GroupCensus
				WHERE AccountId = :cuenta ORDER BY CreatedDate DESC LIMIT 50
			]) {
				String ramo = g.Oportunidad__r?.Ramo__c;
				String clave = ramo == null ? '' : ramo;
				if (censoPorRamo.containsKey(clave)) { continue; }
				censoPorRamo.put(clave, g.Id);
				ramoDelCenso.put(g.Id, ramo);
			}
			if (censoPorRamo.isEmpty()) { return c; }

			List<GroupCensusMember> miembros = [
				SELECT Id, Name, FirstName, Lastname, RelationshipToPrimaryMember, PrimaryGroupCensusMemberId,
					PrimaryGroupCensusMember.Name, Certificado__c, Birthdate, Edad__c, toLabel(Gender), GroupClass.Name,
					JoinDate, Prima__c, Suma_Asegurada__c, Email, PhoneNumber, GroupCensusId
				FROM GroupCensusMember
				WHERE GroupCensusId IN :censoPorRamo.values()
				ORDER BY Certificado__c ASC NULLS LAST, PrimaryGroupCensusMemberId ASC NULLS FIRST, Name ASC
				LIMIT 5000
			];
			// Fecha de alta de los dependientes: si no la traen, la de su titular.
			Map<Id, Date> altaTitular = new Map<Id, Date>();
			for (GroupCensusMember m : miembros) {
				if (m.PrimaryGroupCensusMemberId == null) { altaTitular.put(m.Id, m.JoinDate); }
			}
			for (GroupCensusMember m : miembros) {
				Persona p = new Persona();
				p.id = m.Id;
				p.nombre = String.isNotBlank(m.Name) ? m.Name : String.join(new List<String>{ m.FirstName, m.Lastname }, ' ').trim();
				p.titular = m.PrimaryGroupCensusMemberId == null;
				String rel = m.RelationshipToPrimaryMember;
				p.parentesco = PARENTESCOS.containsKey(rel) ? PARENTESCOS.get(rel) : (p.titular ? 'Titular' : (rel == null ? 'Dependiente' : rel));
				p.titularNombre = p.titular ? null : m.PrimaryGroupCensusMember?.Name;
				p.certificado = m.Certificado__c;
				p.nacimiento = m.Birthdate;
				p.edad = m.Birthdate != null ? edad(m.Birthdate) : (m.Edad__c == null ? null : m.Edad__c.intValue());
				p.genero = m.Gender;
				p.grupo = m.GroupClass?.Name;
				p.alta = m.JoinDate != null ? m.JoinDate : altaTitular.get(m.PrimaryGroupCensusMemberId);
				p.prima = m.Prima__c;
				p.sumaAsegurada = m.Suma_Asegurada__c;
				p.correo = m.Email;
				p.telefono = m.PhoneNumber;
				p.ramo = ramoDelCenso.get(m.GroupCensusId);
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
	 * @description: Edad cumplida a hoy.
	 * @param nacimiento: Fecha de nacimiento
	 * @return Años cumplidos
	 */
	@TestVisible
	static Integer edad(Date nacimiento) {
		Date hoy = Date.today();
		Integer anios = hoy.year() - nacimiento.year();
		if (hoy.month() < nacimiento.month() || (hoy.month() == nacimiento.month() && hoy.day() < nacimiento.day())) { anios--; }
		return anios;
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
