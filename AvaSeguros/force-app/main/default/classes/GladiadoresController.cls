public with sharing class GladiadoresController {
    @AuraEnabled(cacheable=true)
    public static List<Solicitudes_de_Vacaciones__c> getSolicitudes(String IdGladiador){
        return [SELECT Id, Gladiador__r.Name, Dias_que_se_Solicitan__c, Fecha_de_Solicitud__c, Dias_Desde__c, Dias_Hasta__c, Etapa__c, TIpo_de_Permiso__c, Motivo_Ausencia__c, Motivo_de_ausencia__c FROM Solicitudes_de_Vacaciones__c WHERE Gladiador__c =: IdGladiador  AND Etapa__c <> 'Archivado' order by CreatedDate desc];
    }

    @AuraEnabled(cacheable=true)
    public static List<Gladiadores__c> getAllGladiadores(){
        return [SELECT Id, Contrase_a__c, Nombre_Completo__c, Name FROM Gladiadores__c WHERE Desactivado__c = false];
    }

    @AuraEnabled(cacheable=true)
    public static List<Vacaciones_especiales__mdt> getDiasEspeciales(){
        return [select Concepto__c, Dias_disponibles__c from Vacaciones_especiales__mdt];
    }

    @AuraEnabled(cacheable=true)
    public static Gladiadores__c getAuthenticate(String name, String password){
        List<Gladiadores__c> lstGladiadores = new List<Gladiadores__c>();
        lstGladiadores = [SELECT Id, Contrase_a__c, 
                                A_os_Laborados__c, 
                                Dias_Restantes__c, 
                                Dias_Tomados__c, 
                                Fecha_de_Alta__c, 
                                Permisos_sin_Goce__c, 
                                Puesto__c, 
                                Total_dias_especiales__c, 
                                Tipo_de_Contrato__c, 
                                Fecha_de_Nacimiento__c,
                                Mes_de_Nacimiento__c,
                                Salario_Diario__c,
                                Salario_Diario_Integrado__c,
                                Cita_medica__c,
                                NSS__c,
                                Curp__c,
                                Dias_tomados_especiales__c,
                                Vacaciones_Otorgadas_2__c,
                                Numero_Gladiador__c,

                                Dias_Inexcusable__c,
                                Dias_Familiar_Enfermedad__c,
                                Dias_Enfermedad__c,
                                Dias_Fallecimiento__c,
                                Dias_Hijo_Prematuro__c,
                                Dias_Lactancia__c,
                                Dias_Nacimiento__c,
                                Dias_Matrimonio__c,
                                Dias_Mudanza__c,
                                Name FROM Gladiadores__c WHERE Id =: name AND Contrase_a__c =: password];
        if(lstGladiadores.size() > 0){
            return lstGladiadores[0];
        }else{
            return null;
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<Solicitudes_de_Vacaciones__c> createSolicitudVacaciones(
                                                                               String fechaSolicitud, 
                                                                               String idGladiadior, 
                                                                               String fechaDesde, 
                                                                               String fechaHasta, 
                                                                               String tipoPermiso, 
                                                                               String motivoAusencia, 
                                                                               String motivoAusenciaDescription,
                                                                               String Establecerhora,
                                                                               String HoraRegresoSolicitada,
                                                                               String HoraSalidaSolicitada,
                                                                               String MotivoInexcusable
                                                                               ){

        DateTime dTdesde = date.valueOf(fechaDesde);
        DateTime dThasta = date.valueOf(fechaHasta); //formatGMT('EEE, dd MMM yyyy HH:mm:ss') + ' GMT' Datetime.valueOfGmt()

        dTdesde = Datetime.valueOfGmt(''+dTdesde);
        dThasta = Datetime.valueOfGmt(''+dThasta);

        if( (dTdesde <= System.today()) || (dThasta <= dTdesde) && (tipoPermiso != 'Ausentismo por salud' || motivoAusencia != 'Fallecimiento' || motivoAusencia != 'Familiar enfermo' || motivoAusencia != 'Enfermedad')){
            if(!(dThasta == dTdesde)){
                CalloutException e = new CalloutException();
                e.setMessage('Las fechas seleccionadas no son correctas, verifica que no esten en el pasado o en el dia en curso');
                throw e;
            }
        }
        try{
            Insert new Solicitudes_de_Vacaciones__c(
                Gladiador__c = idGladiadior,
                Fecha_de_Solicitud__c = System.today(),
                Dias_Desde__c = date.valueOf(fechaDesde),
                Dias_Hasta__c = date.valueOf(fechaHasta),
                TIpo_de_Permiso__c = tipoPermiso,
                Motivo_Ausencia__c = motivoAusencia,
                Motivo_de_ausencia__c = motivoAusenciaDescription,
                Dias_que_se_Solicitan__c = calculateDiasSolicitan(dTdesde, dThasta),
                Etapa__c = 'Creado',
                Establecer_hora__c = Establecerhora,
                Hora_regreso_solicitada__c = HoraRegresoSolicitada,
                Hora_salida_solicitada__c = HoraSalidaSolicitada,
                Motivo_Inexcusable__c = MotivoInexcusable
            );
        }catch(DMLException ex){
            CalloutException e = new CalloutException();
            e.setMessage(ex.getDmlMessage(0));
            throw e;
        }
        

        return getSolicitudes(idGladiadior);
    }

    @AuraEnabled(cacheable=false)
    public static List<Solicitudes_de_Vacaciones__c> updateSolicitudVacaciones(String idSolicitud, String idGladiadior){

        Gladiadores__c GladiadorObj = [SELECT Id, Contrase_a__c, Nombre_Completo__c, Name, 
                                        Dias_Restantes__c,
                                        Dias_Enfermedad__c, 
                                        Dias_Fallecimiento__c, 
                                        Dias_Familiar_Enfermedad__c, 
                                        Dias_Hijo_Prematuro__c, 
                                        Dias_Inexcusable__c, 
                                        Dias_Lactancia__c, 
                                        Dias_Matrimonio__c, 
                                        Dias_Mudanza__c, 
                                        Dias_Nacimiento__c,
                                        Cita_medica__c,
                                        Vacaciones_Otorgadas_2__c,
                                        Dias_Tomados__c FROM Gladiadores__c WHERE Id =: idGladiadior];

        Solicitudes_de_Vacaciones__c SVobj = [SELECT Id, Gladiador__r.Name, Dias_que_se_Solicitan__c, Dias_Solicitados__c, Fecha_de_Solicitud__c, Dias_Desde__c, Dias_Hasta__c, Etapa__c, TIpo_de_Permiso__c, Motivo_Ausencia__c FROM Solicitudes_de_Vacaciones__c WHERE Id =: idSolicitud];

        //Availables days validation
        if(SVobj.Dias_Desde__c.addDays(-3) <= date.Today() && (SVobj.TIpo_de_Permiso__c != 'Permiso especial' && SVobj.TIpo_de_Permiso__c != 'Salida Temprano' && SVobj.TIpo_de_Permiso__c != 'Entrada Tarde' && SVobj.TIpo_de_Permiso__c != 'Ausentarse por Horas' && SVobj.TIpo_de_Permiso__c != 'Ausentismo por salud') && SVobj.Motivo_Ausencia__c != 'Cita Medica' ){
            CalloutException e = new CalloutException();
            e.setMessage('La fecha de inicio solicitada debe ser mayor a 3 dias de la fecha en curso');
            throw e;
        }
        
        //Availables days validation
        if(SVobj.Dias_Solicitados__c > GladiadorObj.Dias_Restantes__c){
            CalloutException e = new CalloutException();
            e.setMessage('Ya no tienes dias disponibles para el año en curso');
            throw e;
        }
        //Overlap day validation
        if([SELECT Id FROM Solicitudes_de_Vacaciones__c WHERE Gladiador__c =: idGladiadior AND Etapa__c = 'Solicitado' AND ((Dias_Desde__c >=: SVobj.Dias_Desde__c AND Dias_Hasta__c <=: SVobj.Dias_Hasta__c) OR (Dias_Hasta__c >=: SVobj.Dias_Desde__c))].size() > 0){
            CalloutException e = new CalloutException();
            e.setMessage('El Periodo solicitado interfiere con otro anteriormente solicitado, modifica el actual o elimina el solicitado');
            throw e;
        }

        if(validateDiasEspeciales(GladiadorObj, SVobj)){
            CalloutException e = new CalloutException();
            e.setMessage('Ya no hay dias disponibles para ese tipo de permiso especial');
            throw e;
        }

        Update new Solicitudes_de_Vacaciones__c(
            Id = idSolicitud,
            Etapa__c = 'Solicitado'
        );

        return getSolicitudes(idGladiadior);
    }

    @AuraEnabled(cacheable=false)
    public static List<Solicitudes_de_Vacaciones__c> deleteSolicitudVacaciones(String idSolicitud, String idGladiadior){
        Delete new Solicitudes_de_Vacaciones__c(
            Id = idSolicitud
        );

        return getSolicitudes(idGladiadior);
    }

    @TestVisible
    private static Integer calculateDiasSolicitan(Datetime desde, Datetime hasta){
        BusinessHours bh = [SELECT Id FROM BusinessHours WHERE Name = 'Avanza'];
        //datetime referenceTime = desde;
        datetime referenceTime = BusinessHours.nextStartDate(bh.Id, desde);
        Integer daysTaked = 0;
        system.debug('desde '+desde);
        system.debug('hasta '+hasta);
        hasta = hasta.addHours(15);
        for(Integer x = 1; referenceTime <= hasta; x++){  system.debug('avr  '+BusinessHours.isWithin(bh.id, referenceTime) + ' reference '+referenceTime);
            if(BusinessHours.isWithin(bh.id, referenceTime)){ 
                daysTaked++; 
            }
            system.debug('daysTaked '+daysTaked);
            //referenceTime = desde.addDays(x); system.debug('nextStartDate '+desde.addDays(x)+' '+x);
            system.debug('?? '+referenceTime.addDays(1));
            system.debug('nextStartDate '+BusinessHours.nextStartDate(bh.Id, referenceTime.addDays(1))+' '+x+ ' mm '+referenceTime);
            referenceTime = BusinessHours.nextStartDate(bh.Id, referenceTime.addDays(1)); 
        }
        return daysTaked;
    }

    @TestVisible
    private static boolean validateDiasEspeciales(Gladiadores__c gladiador, Solicitudes_de_Vacaciones__c solicitudVacaciones){
        Boolean returnFlag = false;
        if(solicitudVacaciones.TIpo_de_Permiso__c == 'Permiso especial'){
            switch on solicitudVacaciones.Motivo_Ausencia__c {
                when  'Matrimonio' {
                    returnFlag = ((gladiador.Dias_Matrimonio__c - solicitudVacaciones.Dias_que_se_Solicitan__c) < 0 ? true : false);
                }
                when 'Mudanza' {
                    returnFlag = ((gladiador.Dias_Mudanza__c - solicitudVacaciones.Dias_que_se_Solicitan__c) < 0 ? true : false);
                }
                when 'Nacimiento' {
                    returnFlag = ((gladiador.Dias_Nacimiento__c - solicitudVacaciones.Dias_que_se_Solicitan__c) < 0 ? true : false);
                }
                when 'Fallecimiento' {
                    returnFlag = ((gladiador.Dias_Fallecimiento__c - solicitudVacaciones.Dias_que_se_Solicitan__c) < 0 ? true : false);
                }
                when 'Familiar enfermo' {
                    returnFlag = ((gladiador.Dias_Familiar_Enfermedad__c - solicitudVacaciones.Dias_que_se_Solicitan__c) < 0 ? true : false);
                }
                when 'Enfermedad' {
                    returnFlag = ((gladiador.Dias_Enfermedad__c - solicitudVacaciones.Dias_que_se_Solicitan__c) < 0 ? true : false);
                }
                when 'Inexcusable' {
                    returnFlag = ((gladiador.Dias_Inexcusable__c - solicitudVacaciones.Dias_que_se_Solicitan__c) < 0 ? true : false);
                }
                /*
                when 'Cita Medica' {
                    returnFlag = ((gladiador.Cita_medica__c - solicitudVacaciones.Dias_que_se_Solicitan__c) < 0 ? true : false);
                }
                */
                when 'Lactancia' {
                    returnFlag = ((gladiador.Dias_Lactancia__c - solicitudVacaciones.Dias_que_se_Solicitan__c) < 0 ? true : false);
                }
                when 'Hijo prematuro' {
                    returnFlag = ((gladiador.Dias_Hijo_Prematuro__c - solicitudVacaciones.Dias_que_se_Solicitan__c) < 0 ? true : false);
                }
            }
        }
        return returnFlag;
    }

    public static void sendEmail(Solicitudes_de_Vacaciones__c SV, String nameTemplate, String emailGladiador) {
        List<String> emailLst =  new List<String>();
        if(emailGladiador != null){
            emailLst.add(emailGladiador);
        }

        for(Admins_Vacaciones__mdt AVmdt : [SELECT Id, email_admin__c FROM Admins_Vacaciones__mdt]){
            emailLst.add(AVmdt.email_admin__c);
        }

        if(emailLst.size() == 0){
            return;
        }

        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        Id senderEmailId = [SELECT Id FROM OrgWideEmailAddress WHERE Address = 'info@avanzaseguro.com' LIMIT 1].Id;
            EmailTemplate et = [SELECT Id, Subject, Body FROM EmailTemplate WHERE DeveloperName = : nameTemplate LIMIT 1];

            if (et != null) {
                Messaging.SingleEmailMessage email = Messaging.renderStoredEmailTemplate(et.Id, UserInfo.getUserId(), SV.Id);

                String emailSubject = email.getSubject();
                String emailTextBody = email.getPlainTextBody();

                //email.toAddresses = new String[] { 'crystian.r1010@gmail.com' };
                email.toAddresses = emailLst;
                email.setOrgWideEmailAddressId(senderEmailId);
                email.setTargetObjectId(UserInfo.getUserId());
                email.setSubject(emailSubject);
                email.setPlainTextBody(emailTextBody);
                email.saveAsActivity = false;

                //if(!Test.isRunningTest()) {
                Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] {email});
                //}

                if (results[0].success) {
                    System.debug('The email was sent successfully.');
                } else {
                    System.debug('The email failed to send: ' + results[0].errors[0].message);
                }
            } else {
                System.debug('No Bajas EmailTemplate Id found.');
            }
    }

    @AuraEnabled
    public static void UpdateFile(String IdFile, String IdRecord){
            if(IdFile != null && IdRecord != null){
                ContentDocumentLink cdl = new ContentDocumentLink();
                cdl.LinkedEntityId = IdRecord;
                cdl.ContentDocumentId = IdFile;
                Insert cdl;
            } 
    }
}