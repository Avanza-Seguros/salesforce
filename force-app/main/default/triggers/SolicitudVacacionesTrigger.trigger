trigger SolicitudVacacionesTrigger on Solicitudes_de_Vacaciones__c (before insert, after update) {
   
    if(trigger.isUpdate && trigger.isAfter){
        Map<Id, Gladiadores__c> mapGladiador = new Map<Id, Gladiadores__c>([Select Id, 
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
                                          Dias_Tomados__c, 
                                          email__c
                                        FROM Gladiadores__c]);
        for(Solicitudes_de_Vacaciones__c obj : Trigger.new){ 
            Gladiadores__c objGladiador = mapGladiador.get(obj.Gladiador__c);

            if(obj.Etapa__c == 'Solicitado'){
                if(obj.TIpo_de_Permiso__c == 'Permiso especial'){
                    GladiadoresController.sendEmail(obj, 'Plantilla_de_solicitud_de_permiso_especial', null);
                }else{
                    GladiadoresController.sendEmail(obj, 'Plantilla_de_solicitud_de_vacaciones', null);
                }
                return;
            }

            if(obj.Etapa__c == 'Rechazado'){
                GladiadoresController.sendEmail(obj, 'Rechazo_de_Solicitud_de_vacasiones', null);
                return;
            }

            if(obj.Etapa__c == 'Aceptado'){
                if(obj.TIpo_de_Permiso__c == 'Permiso especial'){
                    switch on obj.Motivo_Ausencia__c {
                        when  'Matrimonio' {
                            objGladiador.Dias_Matrimonio__c = 0;
                        }
                        when 'Mudanza' {
                            objGladiador.Dias_Mudanza__c = 0;
                        }
                        when 'Nacimiento' {
                            objGladiador.Dias_Nacimiento__c = 0;
                        }
                        when 'Fallecimiento' {
                            objGladiador.Dias_Fallecimiento__c = objGladiador.Dias_Fallecimiento__c - obj.Dias_que_se_Solicitan__c;
                        }
                        when 'Familiar enfermo' {
                            objGladiador.Dias_Familiar_Enfermedad__c = objGladiador.Dias_Familiar_Enfermedad__c - obj.Dias_que_se_Solicitan__c;
                        }
                        when 'Enfermedad' {
                            objGladiador.Dias_Enfermedad__c = objGladiador.Dias_Enfermedad__c - obj.Dias_que_se_Solicitan__c;
                        }
                        when 'Inexcusable' {
                            objGladiador.Dias_Inexcusable__c = objGladiador.Dias_Inexcusable__c - obj.Dias_que_se_Solicitan__c;
                        }
                        when 'Cita Medica' {
                            objGladiador.Cita_medica__c = objGladiador.Cita_medica__c + 1;
                        }
                        when 'Lactancia' {
                            objGladiador.Dias_Lactancia__c = 0;
                        }
                        when 'Hijo prematuro' {
                            objGladiador.Dias_Hijo_Prematuro__c = 0;
                        }
                    }
                    GladiadoresController.sendEmail(obj, 'Aprovacion_de_Solicitud_de_vacasiones', objGladiador.email__c);
                }else{
                    //restar dias normales
                    objGladiador.Dias_Tomados__c = objGladiador.Dias_Tomados__c + obj.Dias_que_se_Solicitan__c;
                }
                // enviar email 
                Update objGladiador;
                GladiadoresController.sendEmail(obj, 'Aprovacion_de_Solicitud_de_vacasiones', objGladiador.email__c);
                return;
            }
        }
    }
}