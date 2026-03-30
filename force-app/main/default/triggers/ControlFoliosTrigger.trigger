/**
 * Trigger ControlFoliosTrigger
 *
 * Este trigger se dispara después de actualizar o insertar registros en el objeto personalizado Control_de_Folios__c.
 * Su función es realizar acciones específicas basadas en ciertas condiciones cuando se actualizan registros.
 */
trigger ControlFoliosTrigger on Control_de_Folios__c (After Update, After Insert, Before Update) {

    // Obtiene el RecordTypeId para el tipo de registro 'Siniestros'
    Id devRecordTypeId = Schema.SObjectType.Control_de_Folios__c.getRecordTypeInfosByName().get('Siniestros').getRecordTypeId();

    // Verifica si la operación es una actualización y se ejecuta después de la actualización
    if (Trigger.isUpdate && Trigger.isAfter) {

        // Mapa de los registros antiguos
        Map<Id, Control_de_Folios__c> oldMap = Trigger.oldMap;

        // Itera a través de los nuevos registros
        for (Control_de_Folios__c obj : Trigger.new) {
            // Condiciones para enviar un correo
            if ((oldMap.get(obj.Id).Estatus__c != obj.Estatus__c || oldMap.get(obj.Id).Movimiento__c != obj.Movimiento__c) &&
                obj.Movimiento__c == 'Programación' && obj.Estatus__c == 'Aceptado' && String.isNotBlank(obj.Correo__c) &&
                obj.RecordTypeId == devRecordTypeId
            ) {
                // Llama al método SendEmail para enviar un correo con un adjunto
                SendEmailWithAttachment.sendEmail(obj);
            }
        }

        // Itera a través de los nuevos registros nuevamente
        for (Control_de_Folios__c obj : Trigger.new) {
            // Condiciones para enviar correos
            if ((oldMap.get(obj.Id).Estatus__c != obj.Estatus__c || oldMap.get(obj.Id).Movimiento__c != obj.Movimiento__c) &&
                obj.Movimiento__c == 'Reembolso' && obj.Estatus__c == 'Aceptado' && String.isNotBlank(obj.Correo__c) &&
                obj.RecordTypeId == devRecordTypeId
            ) {
                // Llama al método SendCorreos para enviar correos
                EnvioCorreo.SendCorreos(obj);
            }
        }

        // Itera a través de los nuevos registros nuevamente
        for (Control_de_Folios__c obj : Trigger.new) {
            // Condiciones para enviar cartas
            if ((oldMap.get(obj.Id).Estatus__c != obj.Estatus__c || oldMap.get(obj.Id).Movimiento__c != obj.Movimiento__c) &&
                obj.Movimiento__c == 'Ingreso Hospitalario' && obj.Estatus__c == 'Aceptado' && String.isNotBlank(obj.Correo__c) &&
                obj.RecordTypeId == devRecordTypeId
            ) {
                // Llama al método EnvioIngreso para enviar cartas
                EnvioCarta.EnvioIngreso(obj);
            }
        }
        
        String ids = '';
        Boolean downCont = false;
        Map<Id, Contact> mapContact = new Map<Id, Contact>();
        for(Control_de_Folios__c obj : Trigger.new){
            if(obj.Titular__c != null && obj.Enviar_Encuesta__c == true && obj.RecordTypeId == devRecordTypeId && oldMap.get(obj.Id).Enviar_Encuesta__c != obj.Enviar_Encuesta__c){
                ids = obj.Titular__c;
                mapContact.put(obj.Titular__c, new Contact(Id = obj.Titular__c, Conteo_de_Folios__c = 0));
                break;
            }else if(oldMap.get(obj.Id).Enviar_Encuesta__c != obj.Enviar_Encuesta__c && obj.Enviar_Encuesta__c == false){
                downCont = true;
            }
        }
        if(String.IsNotBlank(ids)){
            mapContact.get(ids).Conteo_de_Folios__c = (database.countQuery('SELECT count() FROM Control_de_Folios__c WHERE Titular__c =: ids AND RecordTypeId =: devRecordTypeId ')) +(downCont ? -1 : 1);
            Update mapContact.values();
        }
    }
    
    if(trigger.isInsert && trigger.isAfter){
        String ids = '';
        Map<Id, Contact> mapContact = new Map<Id, Contact>();
        for(Control_de_Folios__c obj : Trigger.new){
            if(obj.Titular__c != null && obj.Enviar_Encuesta__c == true && obj.RecordTypeId == devRecordTypeId){
                ids = obj.Titular__c;
                mapContact.put(obj.Titular__c, new Contact(Id = obj.Titular__c, Conteo_de_Folios__c = 0));
                break;
            }
        }
        if(String.IsNotBlank(ids)){
            mapContact.get(ids).Conteo_de_Folios__c = database.countQuery('SELECT count() FROM Control_de_Folios__c WHERE Titular__c =: ids AND RecordTypeId =: devRecordTypeId ');
            Update mapContact.values();
        }
    }
    
    if(trigger.isUpdate && trigger.isBefore){ system.debug('1');
        Map<Id, Control_de_Folios__c> oldMap = Trigger.oldMap;
        for(Control_de_Folios__c obj : Trigger.new){ system.debug('2');
            if(obj.Estatus__c != oldMap.get(obj.Id).Estatus__c && obj.RecordTypeId == devRecordTypeId){ system.debug('3');
                obj.Estatus_previo__c = oldMap.get(obj.Id).Estatus__c;
            }
        }
     }
  }