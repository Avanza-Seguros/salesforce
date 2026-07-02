/**
 *   @name: ContactQueueable
 *   @version: 1.0
 *   @creation date: 02/07/2026
 *   @author: Sergio Uribe Toledo - Volestra
 *   @description: Job asincrono (Queueable) que, para un conjunto de Items_Cases__c sin Asegurado asignado, busca contactos existentes por Nombre completo, Email y Cuenta, crea los contactos faltantes evitando duplicados dentro de la misma ejecucion, y actualiza los items con el contacto correspondiente. Gestiona el flag TriggerControl.skipEmailTrigger durante la actualizacion.
 */
public class ContactQueueable implements Queueable {

	private Set<Id> itemIds;

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Constructor. Recibe y almacena el conjunto de Ids de Items_Cases__c a procesar en el job.
	 * @param itemIds: Conjunto de Ids de Items_Cases__c a procesar
	 * @return void
	 */
	public ContactQueueable(Set<Id> itemIds) {
		this.itemIds = itemIds;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Punto de entrada del Queueable. Recupera los items sin Asegurado, busca contactos existentes, crea los nuevos que falten, los inserta y actualiza los items con su contacto asignado. Ante error restablece TriggerControl.skipEmailTrigger y relanza la excepcion.
	 * @param context: Contexto del Queueable proporcionado por la plataforma
	 * @return void
	 */
	public void execute(QueueableContext context) {
		try {
			System.debug('🔄 Procesando ' + itemIds.size() + ' items');

			// 1. Obtener items
			List<Items_Cases__c> items = [
				SELECT Id, Nombre__c, Apellido_paterno__c, Apellido_materno__c,
					   Correo_electronico__c, Asegurado__c, Nombre_cuenta__c,
					   Nombre_completo__c, Fecha_de_nacimiento__c
				FROM Items_Cases__c
				WHERE Id IN :itemIds
				AND Asegurado__c = null
			];

			if (items.isEmpty()) return;

			// 2. Buscar contactos existentes usando Nombre_Completo__c, Cuenta y Email
			Map<Id, Id> itemToContactMap = buscarContactosExistentes(items);

			// 3. Crear contactos nuevos para items sin asignación
			Map<Id, Contact> contactosNuevos = crearContactosNuevos(items, itemToContactMap);

			// 4. Insertar contactos nuevos y actualizar mapeo
			if (!contactosNuevos.isEmpty()) {
				insertarContactosNuevos(contactosNuevos, itemToContactMap);
			}

			// 5. Actualizar items con contactos asignados
			if (!itemToContactMap.isEmpty()) {
				actualizarItemsConContactos(itemToContactMap);
			}

			System.debug('✅ Completado: ' + itemToContactMap.size() + ' de ' + items.size() + ' items asignados');

		} catch(Exception e) {
			System.debug('❌ Error: ' + e.getMessage());
			TriggerControl.skipEmailTrigger = false;
			throw e;
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Busca contactos existentes para los items dados consultando por AccountId y coincidencia de Nombre_completo__c o Email, y asigna a cada item el contacto que mejor coincida segun un orden de prioridad (clave completa, luego nombre+cuenta, luego email+cuenta).
	 * @param items: Lista de Items_Cases__c para los que se buscan contactos existentes
	 * @return Mapa de Id de item a Id de contacto existente asignado
	 */
	private Map<Id, Id> buscarContactosExistentes(List<Items_Cases__c> items) {
		Map<Id, Id> itemToContactMap = new Map<Id, Id>();

		if (items.isEmpty()) return itemToContactMap;

		// Preparar criterios de búsqueda
		Set<String> nombresCompletos = new Set<String>();
		Set<String> emails = new Set<String>();
		Set<Id> accountIds = new Set<Id>();

		// Mapa para búsqueda rápida de items por criterio
		Map<String, List<Items_Cases__c>> itemsPorCriterioCompleto = new Map<String, List<Items_Cases__c>>();

		for (Items_Cases__c item : items) {
			if (item.Nombre_cuenta__c == null) continue;

			String nombreCompleto = item.Nombre_completo__c != null ?
				item.Nombre_completo__c.trim().toLowerCase() : null;
			String email = item.Correo_electronico__c != null ?
				item.Correo_electronico__c.trim().toLowerCase() : null;

			if (nombreCompleto != null) {
				nombresCompletos.add(nombreCompleto);
				accountIds.add(item.Nombre_cuenta__c);
			}
			if (email != null) {
				emails.add(email);
				accountIds.add(item.Nombre_cuenta__c);
			}

			// Crear clave compuesta para búsqueda exacta
			if (nombreCompleto != null && email != null && item.Nombre_cuenta__c != null) {
				String claveCompleta = nombreCompleto + '|' + email + '|' + item.Nombre_cuenta__c;
				if (!itemsPorCriterioCompleto.containsKey(claveCompleta)) {
					itemsPorCriterioCompleto.put(claveCompleta, new List<Items_Cases__c>());
				}
				itemsPorCriterioCompleto.get(claveCompleta).add(item);
			}
		}

		if (accountIds.isEmpty()) return itemToContactMap;

		// Buscar contactos existentes por los tres criterios
		List<Contact> contactosExistentes = [
			SELECT Id, Nombre_completo__c, Email, AccountId
			FROM Contact
			WHERE AccountId IN :accountIds
			AND (
				(Nombre_completo__c != NULL AND Nombre_completo__c IN :nombresCompletos)
				OR
				(Email != NULL AND Email IN :emails)
			)
		];

		// Crear mapas de contactos por criterios para búsqueda rápida
		Map<String, List<Contact>> contactosPorNombreCuenta = new Map<String, List<Contact>>();
		Map<String, List<Contact>> contactosPorEmailCuenta = new Map<String, List<Contact>>();
		Map<String, Contact> contactosPorClaveCompleta = new Map<String, Contact>();

		for (Contact contacto : contactosExistentes) {
			String nombreCompletoContacto = contacto.Nombre_completo__c != null ?
				contacto.Nombre_completo__c.trim().toLowerCase() : null;
			String emailContacto = contacto.Email != null ?
				contacto.Email.trim().toLowerCase() : null;

			// Mapa por Nombre_Completo__c + AccountId
			if (nombreCompletoContacto != null && contacto.AccountId != null) {
				String claveNombre = nombreCompletoContacto + '|' + contacto.AccountId;
				if (!contactosPorNombreCuenta.containsKey(claveNombre)) {
					contactosPorNombreCuenta.put(claveNombre, new List<Contact>());
				}
				contactosPorNombreCuenta.get(claveNombre).add(contacto);
			}

			// Mapa por Email + AccountId
			if (emailContacto != null && contacto.AccountId != null) {
				String claveEmail = emailContacto + '|' + contacto.AccountId;
				if (!contactosPorEmailCuenta.containsKey(claveEmail)) {
					contactosPorEmailCuenta.put(claveEmail, new List<Contact>());
				}
				contactosPorEmailCuenta.get(claveEmail).add(contacto);
			}

			// Mapa por combinación completa
			if (nombreCompletoContacto != null && emailContacto != null && contacto.AccountId != null) {
				String claveCompleta = nombreCompletoContacto + '|' + emailContacto + '|' + contacto.AccountId;
				contactosPorClaveCompleta.put(claveCompleta, contacto);
			}
		}

		// Asignar contactos existentes a los items
		for (Items_Cases__c item : items) {
			// Si el item ya tiene contacto asignado, saltar
			if (itemToContactMap.containsKey(item.Id)) continue;

			if (item.Nombre_cuenta__c == null) continue;

			String nombreCompletoItem = item.Nombre_completo__c != null ?
				item.Nombre_completo__c.trim().toLowerCase() : null;
			String emailItem = item.Correo_electronico__c != null ?
				item.Correo_electronico__c.trim().toLowerCase() : null;

			Contact contactoAsignado = null;

			// PRIORIDAD 1: Buscar por coincidencia exacta (los tres criterios)
			if (nombreCompletoItem != null && emailItem != null) {
				String claveCompleta = nombreCompletoItem + '|' + emailItem + '|' + item.Nombre_cuenta__c;
				if (contactosPorClaveCompleta.containsKey(claveCompleta)) {
					contactoAsignado = contactosPorClaveCompleta.get(claveCompleta);
				}
			}

			// PRIORIDAD 2: Buscar por Nombre_Completo__c + AccountId
			else if (contactoAsignado == null && nombreCompletoItem != null) {
				String claveNombre = nombreCompletoItem + '|' + item.Nombre_cuenta__c;
				if (contactosPorNombreCuenta.containsKey(claveNombre)) {
					// Si hay múltiples contactos con mismo nombre+cuenta, tomar el primero
					contactoAsignado = contactosPorNombreCuenta.get(claveNombre)[0];
				}
			}

			// PRIORIDAD 3: Buscar por Email + AccountId
			else if (contactoAsignado == null && emailItem != null) {
				String claveEmail = emailItem + '|' + item.Nombre_cuenta__c;
				if (contactosPorEmailCuenta.containsKey(claveEmail)) {
					// Si hay múltiples contactos con mismo email+cuenta, tomar el primero
					contactoAsignado = contactosPorEmailCuenta.get(claveEmail)[0];
				}
			}

			if (contactoAsignado != null) {
				itemToContactMap.put(item.Id, contactoAsignado.Id);
				System.debug('✅ Contacto encontrado para item ' + item.Id + ': ' + contactoAsignado.Id +
						   ' (Criterio: Nombre=' + nombreCompletoItem + ', Email=' + emailItem + ', Cuenta=' + item.Nombre_cuenta__c + ')');
			}
		}

		return itemToContactMap;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Construye los contactos nuevos (aun no insertados) para los items que no tienen contacto asignado y que cumplen los datos minimos (Nombre, Apellido paterno y Cuenta), evitando duplicados dentro de la misma ejecucion mediante un criterio unico.
	 * @param items: Lista de Items_Cases__c a evaluar
	 * @param itemToContactMap: Mapa de items ya asignados a contactos existentes, usado para saltar los ya resueltos
	 * @return Mapa de Id de item al Contact nuevo (sin insertar) que le corresponde
	 */
	private Map<Id, Contact> crearContactosNuevos(List<Items_Cases__c> items, Map<Id, Id> itemToContactMap) {
		Map<Id, Contact> contactosNuevos = new Map<Id, Contact>();

		// Mapa para evitar crear contactos duplicados en la misma ejecución
		Map<String, Id> criterioToItemId = new Map<String, Id>();

		for (Items_Cases__c item : items) {
			// Saltar items que ya tienen contacto asignado
			if (itemToContactMap.containsKey(item.Id)) continue;

			// Verificar datos mínimos para crear contacto
			if (String.isNotBlank(item.Nombre__c) &&
				String.isNotBlank(item.Apellido_paterno__c) &&
				item.Nombre_cuenta__c != null) {

				// Crear criterio único para evitar duplicados
				String criterioUnico = null;
				String nombreCompletoItem = item.Nombre_completo__c != null ?
					item.Nombre_completo__c.trim().toLowerCase() : null;
				String emailItem = item.Correo_electronico__c != null ?
					item.Correo_electronico__c.trim().toLowerCase() : null;

				if (nombreCompletoItem != null && emailItem != null) {
					criterioUnico = nombreCompletoItem + '|' + emailItem + '|' + item.Nombre_cuenta__c;
				} else if (emailItem != null) {
					criterioUnico = emailItem + '|' + item.Nombre_cuenta__c;
				} else if (nombreCompletoItem != null) {
					criterioUnico = nombreCompletoItem + '|' + item.Nombre_cuenta__c;
				}

				// Verificar si ya vamos a crear un contacto con este criterio
				if (criterioUnico != null && criterioToItemId.containsKey(criterioUnico)) {
					// Este item compartirá contacto con otro item que ya está creando uno
					Id itemIdExistente = criterioToItemId.get(criterioUnico);
					if (contactosNuevos.containsKey(itemIdExistente)) {
						// El contacto ya se está creando para otro item
						System.debug('♻️  Item ' + item.Id + ' compartirá contacto con item ' + itemIdExistente);
					}
				} else {
					// Crear nuevo contacto
					Contact nuevoContacto = new Contact(
						FirstName = item.Nombre__c,
						LastName = item.Apellido_paterno__c +
								  (item.Apellido_materno__c != null ? ' ' + item.Apellido_materno__c : ''),
						Apellido_paterno__c = item.Apellido_paterno__c,
						Apellido_materno__c = item.Apellido_materno__c,
						Birthdate = item.Fecha_de_nacimiento__c,
						AccountId = item.Nombre_cuenta__c,
						Email = item.Correo_electronico__c  // Copiar el campo Nombre_completo__c
					);

					contactosNuevos.put(item.Id, nuevoContacto);

					if (criterioUnico != null) {
						criterioToItemId.put(criterioUnico, item.Id);
					}

					System.debug('➕ Creando nuevo contacto para item ' + item.Id +
							   ' (Nombre: ' + item.Nombre_completo__c +
							   ', Email: ' + item.Correo_electronico__c +
							   ', Cuenta: ' + item.Nombre_cuenta__c + ')');
				}
			}
		}

		return contactosNuevos;
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Inserta los contactos nuevos con DMLOptions (permitiendo duplicados y sin all-or-none), asigna a cada item su contacto insertado y propaga la asignacion a otros items que compartan el mismo criterio.
	 * @param contactosNuevos: Mapa de Id de item a Contact nuevo a insertar
	 * @param itemToContactMap: Mapa de items a contactos que se actualiza con los contactos insertados
	 * @return void
	 */
	private void insertarContactosNuevos(Map<Id, Contact> contactosNuevos, Map<Id, Id> itemToContactMap) {
		if (contactosNuevos.isEmpty()) return;

		// Crear lista de contactos y mantener relación con sus items
		List<Contact> contactosParaInsertar = new List<Contact>();
		List<Id> itemIdsCorrespondientes = new List<Id>();

		for (Id itemId : contactosNuevos.keySet()) {
			Contact contacto = contactosNuevos.get(itemId);
			contactosParaInsertar.add(contacto);
			itemIdsCorrespondientes.add(itemId);
		}

		Database.DMLOptions dmlOpts = new Database.DMLOptions();
		dmlOpts.DuplicateRuleHeader.AllowSave = true;
		dmlOpts.DuplicateRuleHeader.RunAsCurrentUser = true;
		dmlOpts.OptAllOrNone = false;

		Database.SaveResult[] results = Database.insert(contactosParaInsertar, dmlOpts);

		// Procesar resultados
		for (Integer i = 0; i < results.size(); i++) {
			Database.SaveResult sr = results[i];
			Id itemId = itemIdsCorrespondientes[i];
			Contact contactoInsertado = contactosParaInsertar[i];

			if (sr.isSuccess()) {
				// Asignar el contacto insertado al item que lo creó
				itemToContactMap.put(itemId, sr.getId());
				System.debug('🔗 Asignado: Item ' + itemId + ' → Contacto ' + sr.getId());

				// Buscar otros items que deban compartir este contacto
				buscarItemsParaMismoContacto(itemId, contactoInsertado, contactosNuevos, itemToContactMap, sr.getId());
			} else {
				System.debug('❌ Error insertando contacto para item ' + itemId + ': ' + sr.getErrors());
			}
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: A partir de un contacto recien insertado, busca otros items en el mapa de contactos nuevos que compartan el mismo criterio (nombre completo, email y cuenta) y les asigna el mismo Id de contacto para evitar duplicados.
	 * @param itemIdOrigen: Id del item que origino el contacto insertado
	 * @param contactoInsertado: Contact que fue insertado y cuyo criterio se compara
	 * @param contactosNuevos: Mapa de Id de item a Contact nuevo, entre los que se buscan coincidencias
	 * @param itemToContactMap: Mapa de items a contactos que se actualiza con las coincidencias encontradas
	 * @param contactoId: Id del contacto insertado a asignar a los items coincidentes
	 * @return void
	 */
	private void buscarItemsParaMismoContacto(Id itemIdOrigen, Contact contactoInsertado,
											 Map<Id, Contact> contactosNuevos,
											 Map<Id, Id> itemToContactMap, Id contactoId) {
		// Construir criterio del contacto insertado
		String nombreCompletoContacto = contactoInsertado.Nombre_completo__c != null ?
			contactoInsertado.Nombre_completo__c.trim().toLowerCase() : null;
		String emailContacto = contactoInsertado.Email != null ?
			contactoInsertado.Email.trim().toLowerCase() : null;
		Id accountIdContacto = contactoInsertado.AccountId;

		if (accountIdContacto == null) return;

		// Buscar otros items en contactosNuevos que tengan el mismo criterio
		for (Id otroItemId : contactosNuevos.keySet()) {
			// Saltar el item origen
			if (otroItemId == itemIdOrigen) continue;

			// Si ya tiene contacto asignado, saltar
			if (itemToContactMap.containsKey(otroItemId)) continue;

			Contact otroContacto = contactosNuevos.get(otroItemId);

			// Comparar criterios
			String otroNombreCompleto = otroContacto.Nombre_completo__c != null ?
				otroContacto.Nombre_completo__c.trim().toLowerCase() : null;
			String otroEmail = otroContacto.Email != null ?
				otroContacto.Email.trim().toLowerCase() : null;

			// Verificar si es el mismo contacto (mismo criterio)
			boolean mismoContacto = false;

			if (nombreCompletoContacto != null && otroNombreCompleto != null &&
				emailContacto != null && otroEmail != null) {
				// Coincidencia exacta con ambos campos
				mismoContacto = nombreCompletoContacto.equals(otroNombreCompleto) &&
							  emailContacto.equals(otroEmail) &&
							  accountIdContacto == otroContacto.AccountId;
			} else if (emailContacto != null && otroEmail != null) {
				// Coincidencia solo por email
				mismoContacto = emailContacto.equals(otroEmail) &&
							  accountIdContacto == otroContacto.AccountId;
			} else if (nombreCompletoContacto != null && otroNombreCompleto != null) {
				// Coincidencia solo por nombre completo
				mismoContacto = nombreCompletoContacto.equals(otroNombreCompleto) &&
							  accountIdContacto == otroContacto.AccountId;
			}

			if (mismoContacto) {
				// Asignar el mismo contacto a este item también
				itemToContactMap.put(otroItemId, contactoId);
				System.debug('🔗 Compartido: Item ' + otroItemId + ' también usa Contacto ' + contactoId);
			}
		}
	}

	/**
	 * @creation date: 02/07/2026
	 * @author: Sergio Uribe Toledo - Volestra
	 * @description: Actualiza los Items_Cases__c asignandoles el contacto (Asegurado__c) correspondiente. Desactiva temporalmente el trigger de emails mediante TriggerControl.skipEmailTrigger durante el DML y lo restablece en el bloque finally.
	 * @param itemToContactMap: Mapa de Id de item a Id de contacto asignado
	 * @return void
	 */
	private void actualizarItemsConContactos(Map<Id, Id> itemToContactMap) {
		List<Items_Cases__c> itemsToUpdate = new List<Items_Cases__c>();

		for (Id itemId : itemToContactMap.keySet()) {
			itemsToUpdate.add(new Items_Cases__c(
				Id = itemId,
				Asegurado__c = itemToContactMap.get(itemId)
			));
		}

		TriggerControl.skipEmailTrigger = true;
		try {
			update itemsToUpdate;
			System.debug('✅ ' + itemsToUpdate.size() + ' items actualizados');
		} finally {
			TriggerControl.skipEmailTrigger = false;
		}
	}
}
