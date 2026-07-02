/**
 *   @name: ContactService
 *   @version: 1.0
 *   @creation date: 02/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Servicio que crea u obtiene contactos a partir de registros Items_Cases__c y los relaciona con dichos items. Separa la creación de contactos (fase 1) de la actualización de los items (fase 2) y ofrece un método asíncrono que combina ambas fases.
 */
public with sharing class ContactService {

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Fase 1: crea u obtiene contactos para los items válidos (sin actualizar Items_Cases__c). Busca contactos existentes por nombre/apellidos, crea los faltantes y devuelve el mapeo item-contacto.
	 * @param items: Lista de registros Items_Cases__c a procesar.
	 * @return Mapa de Id de item a su Contact asignado.
	 */
	public static Map<Id, Contact> processContacts(List<Items_Cases__c> items) {
		Map<Id, Contact> result = new Map<Id, Contact>();
		if (items == null || items.isEmpty()) return result;

		// Filtrar items válidos
		List<Items_Cases__c> validItems = new List<Items_Cases__c>();
		for (Items_Cases__c i : items) {
			if (isValidItem(i)) {
				validItems.add(i);
			}
		}

		if (validItems.isEmpty()) return result;

		// Buscar contactos existentes
		Map<String, Contact> existingContactsMap = loadExistingContacts(validItems);

		// Preparar nuevos contactos
		List<Contact> contactsToCreate = new List<Contact>();
		Map<String, Id> keyToItemIdMap = new Map<String, Id>();

		for (Items_Cases__c i : validItems) {
			String contactKey = createKey(i);
			keyToItemIdMap.put(contactKey, i.Id);

			if (!existingContactsMap.containsKey(contactKey)) {
				Contact newContact = createContact(i);
				contactsToCreate.add(newContact);
				existingContactsMap.put(contactKey, newContact);
			}
		}

		// Insertar nuevos contactos
		if (!contactsToCreate.isEmpty()) {
			insert contactsToCreate;
		}

		// Crear mapa resultado
		for (Items_Cases__c i : validItems) {
			String contactKey = createKey(i);
			Contact assignedContact = existingContactsMap.get(contactKey);
			if (assignedContact != null) {
				result.put(i.Id, assignedContact);
			}
		}

		return result;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Fase 2: actualiza los registros Items_Cases__c con el contacto asignado en el campo Asegurado__c. Debe llamarse DESPUÉS del trigger, en un contexto diferente.
	 * @param itemContactMap: Mapa de Id de item a su Contact asignado.
	 * @return void
	 */
	public static void updateItemsWithContacts(Map<Id, Contact> itemContactMap) {
		if (itemContactMap == null || itemContactMap.isEmpty()) return;

		List<Items_Cases__c> itemsToUpdate = new List<Items_Cases__c>();

		for (Id itemId : itemContactMap.keySet()) {
			Contact c = itemContactMap.get(itemId);
			if (c != null && c.Id != null) {
				itemsToUpdate.add(new Items_Cases__c(
					Id = itemId,
					Asegurado__c = c.Id
				));
			}
		}

		if (!itemsToUpdate.isEmpty()) {
			update itemsToUpdate;
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Método asíncrono (@future) que consulta los items por Id, ejecuta la fase 1 (crear/obtener contactos) y la fase 2 (actualizar items). Pensado para invocarse fuera del contexto del trigger.
	 * @param itemIds: Conjunto de Ids de Items_Cases__c a procesar de forma asíncrona.
	 * @return void
	 */
	@future
	public static void createAndRelateContactsAsync(Set<Id> itemIds) {
		// Consultar los items
		List<Items_Cases__c> items = [
			SELECT Id, Nombre__c, Apellido_paterno__c,
			       Apellido_materno__c, Correo_electronico__c
			FROM Items_Cases__c
			WHERE Id IN :itemIds
		];

		// Procesar contactos
		Map<Id, Contact> itemContactMap = processContacts(items);

		// Actualizar items
		updateItemsWithContacts(itemContactMap);
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Carga los contactos ya existentes que coincidan por nombre y apellido paterno con los items dados, indexándolos por una clave normalizada.
	 * @param items: Lista de registros Items_Cases__c cuyos nombres/apellidos se usan para la búsqueda.
	 * @return Mapa de clave normalizada a Contact existente.
	 */
	private static Map<String, Contact> loadExistingContacts(List<Items_Cases__c> items) {
		Map<String, Contact> contactsMap = new Map<String, Contact>();

		Set<String> nombres = new Set<String>();
		Set<String> apellidos = new Set<String>();

		for (Items_Cases__c i : items) {
			nombres.add(i.Nombre__c);
			apellidos.add(i.Apellido_paterno__c);
		}

		List<Contact> existingContacts = [
			SELECT Id, FirstName, LastName, MiddleName, Email
			FROM Contact
			WHERE FirstName IN :nombres
			AND LastName IN :apellidos
		];

		for (Contact c : existingContacts) {
			String key = createKey(c.FirstName, c.LastName, c.MiddleName);
			contactsMap.put(key, c);
		}

		return contactsMap;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Determina si un item es válido para procesar, exigiendo que no sea nulo y que tenga nombre y apellido paterno.
	 * @param item: Registro Items_Cases__c a validar.
	 * @return True si el item es válido para procesar.
	 */
	private static Boolean isValidItem(Items_Cases__c item) {
		return item != null &&
		       String.isNotBlank(item.Nombre__c) &&
		       String.isNotBlank(item.Apellido_paterno__c);
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Genera la clave normalizada de un item a partir de su nombre y apellidos.
	 * @param item: Registro Items_Cases__c del que se genera la clave.
	 * @return Clave normalizada (nombre|apellidoPaterno|apellidoMaterno).
	 */
	private static String createKey(Items_Cases__c item) {
		return createKey(item.Nombre__c, item.Apellido_paterno__c, item.Apellido_materno__c);
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Genera una clave normalizada (minúsculas y sin espacios extremos) a partir de nombre y apellidos, para comparar contactos.
	 * @param firstName: Nombre de pila.
	 * @param lastName: Apellido paterno.
	 * @param secondLastName: Apellido materno.
	 * @return Clave normalizada en formato "nombre|apellidoPaterno|apellidoMaterno".
	 */
	private static String createKey(String firstName, String lastName, String secondLastName) {
		String fName = (firstName != null) ? firstName.trim().toLowerCase() : '';
		String lName = (lastName != null) ? lastName.trim().toLowerCase() : '';
		String sName = (secondLastName != null) ? secondLastName.trim().toLowerCase() : '';

		return fName + '|' + lName + '|' + sName;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Construye un nuevo registro Contact a partir de los datos de un item (nombre, apellidos y correo).
	 * @param item: Registro Items_Cases__c origen de los datos del contacto.
	 * @return Nuevo Contact sin insertar.
	 */
	private static Contact createContact(Items_Cases__c item) {
		return new Contact(
			FirstName = item.Nombre__c,
			LastName = item.Apellido_paterno__c,
			MiddleName = item.Apellido_materno__c,
			Email = item.Correo_electronico__c
		);
	}
}
