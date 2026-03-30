import { LightningElement, api, track, wire } from 'lwc';
import {NavigationMixin} from 'lightning/navigation';
import getSolicitudes from '@salesforce/apex/GladiadoresController.getSolicitudes';
import getAllGladiadores from '@salesforce/apex/GladiadoresController.getAllGladiadores';
import getAuthenticate from '@salesforce/apex/GladiadoresController.getAuthenticate';
import createSolicitudVacaciones from '@salesforce/apex/GladiadoresController.createSolicitudVacaciones';
import updateSolicitudVacaciones from '@salesforce/apex/GladiadoresController.updateSolicitudVacaciones';
import deleteSolicitudVacaciones from '@salesforce/apex/GladiadoresController.deleteSolicitudVacaciones';
import uploadFiles from '@salesforce/apex/GladiadoresController.UpdateFile';
import getDiasEspeciales from '@salesforce/apex/GladiadoresController.getDiasEspeciales'; 

import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

import TIPODEPERMISO_FIELD from '@salesforce/schema/Solicitudes_de_Vacaciones__c.TIpo_de_Permiso__c';
import DIASDESDE_FIELD from '@salesforce/schema/Solicitudes_de_Vacaciones__c.Dias_Desde__c';
import DIASHASTA_FIELD from '@salesforce/schema/Solicitudes_de_Vacaciones__c.Dias_Hasta__c';
import GLADIADOR_FIELD from '@salesforce/schema/Solicitudes_de_Vacaciones__c.Gladiador__c'; 
import MOTIVO_FIELD from '@salesforce/schema/Solicitudes_de_Vacaciones__c.Motivo_de_ausencia__c';
import MOTIVO_AUSENCIA_FIELD from '@salesforce/schema/Solicitudes_de_Vacaciones__c.Motivo_Ausencia__c';
import MOTIVO_INEXCUSABLE_FIELD from '@salesforce/schema/Solicitudes_de_Vacaciones__c.Motivo_Inexcusable__c';
import ESTABLECER_HORA_FIELD from '@salesforce/schema/Solicitudes_de_Vacaciones__c.Establecer_hora__c';

import REGRESO_HORA_FIELD from '@salesforce/schema/Solicitudes_de_Vacaciones__c.Hora_regreso_solicitada__c';
import SALIDA_HORA_FIELD from '@salesforce/schema/Solicitudes_de_Vacaciones__c.Hora_salida_solicitada__c'; 


export default class Gladiadores extends LightningElement {

    fields = [TIPODEPERMISO_FIELD, MOTIVO_AUSENCIA_FIELD, MOTIVO_INEXCUSABLE_FIELD, ESTABLECER_HORA_FIELD, SALIDA_HORA_FIELD, REGRESO_HORA_FIELD, MOTIVO_FIELD, DIASDESDE_FIELD, DIASHASTA_FIELD];

    @track options = [];

    @track recordGladiadorId;
    @track recordsSolicitudVacaciones = [];
    @track isAuthGladiador;
    @track isNewSolicitud;
    @track loadFile;

    @track AsuntoMedico;
    @track DeberesInexcusables;
    @track EnfermedadGrave;
    @track EnfermedadTrabajador;
    @track FallecimientoDirecto;
    @track HijosPrematuros;
    @track LactanciaMaterna;
    @track Nacimiento;
    @track PorMatrimonio;
    @track PorMudanza;

    @track disableMotivoTextArea = false;
    
    @api horizontalAlign = 'space';
    
    get disableMotivoTextAreaMethod(){
        return this.disableMotivoTextArea;
    }


get recordsTable(){
    let data = this.recordsSolicitudVacaciones;
    return data;
}

    @wire(getAllGladiadores)
    getAllGladiadores({data, error}){ 
        if(data){
            this.options = Object.keys(data).map(item=>(
                {
                label : data[item].Name, value : data[item].Id
                }
            ));
        }
    }

    authenticate(){
        getAuthenticate({name: this.template.querySelector('lightning-combobox[data-id="comboUser"]').value, password: this.template.querySelector('lightning-input[data-id="passUser"]').value})
            .then((data) => {
                if(data){
                    getDiasEspeciales().then((result) => {
                        for(let i=0; i<result.length; i++){
                            console.log(result[i].Concepto__c);
                            this.calculateDiasEspeciales(result[i], data);
                        }
                    });

                    this.isAuthGladiador = data;
                    this.getTableValues();
                }else{
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Login',
                            message :'Password incorrecto',
                            variant: 'error',
                        }),
                    );
                }
            })
    }

    calculateDiasEspeciales(value, dataGladiador){
        if(value.Concepto__c == 'Deberes inexcusables'){
            this.DeberesInexcusables = 'Otorgados: '+ parseInt(value.Dias_disponibles__c)+'  Tomados: '+(parseInt(value.Dias_disponibles__c) - parseInt(dataGladiador.Dias_Inexcusable__c))+'  Restantes: '+parseInt(dataGladiador.Dias_Inexcusable__c);
        }
        if(value.Concepto__c == 'Enfermedad grave familiar directo'){
            this.EnfermedadGrave = 'Otorgados: '+ parseInt(value.Dias_disponibles__c)+'  Tomados: '+(parseInt(value.Dias_disponibles__c) - parseInt(dataGladiador.Dias_Familiar_Enfermedad__c))+'  Restantes: '+parseInt(dataGladiador.Dias_Familiar_Enfermedad__c);
        }
        if(value.Concepto__c == 'Enfermedad trabajador'){
            this.EnfermedadTrabajador = 'Otorgados: '+ parseInt(value.Dias_disponibles__c)+'  Tomados: '+(parseInt(value.Dias_disponibles__c) - parseInt(dataGladiador.Dias_Enfermedad__c))+'  Restantes: '+parseInt(dataGladiador.Dias_Enfermedad__c);
        }
        if(value.Concepto__c == 'Fallecimiento directo'){
            this.FallecimientoDirecto = 'Otorgados: '+ parseInt(value.Dias_disponibles__c)+'  Tomados: '+(parseInt(value.Dias_disponibles__c) - parseInt(dataGladiador.Dias_Fallecimiento__c))+'  Restantes: '+parseInt(dataGladiador.Dias_Fallecimiento__c);
        }
        if(value.Concepto__c == 'Hijos prematuros'){
            this.HijosPrematuros = 'Otorgados: '+ parseInt(value.Dias_disponibles__c)+'  Tomados: '+(parseInt(value.Dias_disponibles__c) - parseInt(dataGladiador.Dias_Hijo_Prematuro__c))+'  Restantes: '+parseInt(dataGladiador.Dias_Hijo_Prematuro__c);
        }
        if(value.Concepto__c == 'Lactancia materna'){
            this.LactanciaMaterna = 'Otorgados: '+ parseInt(value.Dias_disponibles__c)+'  Tomados: '+(parseInt(value.Dias_disponibles__c) - parseInt(dataGladiador.Dias_Lactancia__c))+'  Restantes: '+parseInt(dataGladiador.Dias_Lactancia__c);
        }
        if(value.Concepto__c == 'Nacimiento'){
            this.Nacimiento = 'Otorgados: '+ parseInt(value.Dias_disponibles__c)+'  Tomados: '+(parseInt(value.Dias_disponibles__c) - parseInt(dataGladiador.Dias_Nacimiento__c))+'  Restantes: '+parseInt(dataGladiador.Dias_Nacimiento__c);
        }
        if(value.Concepto__c == 'Por matrimonio'){
            this.PorMatrimonio = 'Otorgados: '+ parseInt(value.Dias_disponibles__c)+'  Tomados: '+(parseInt(value.Dias_disponibles__c) - parseInt(dataGladiador.Dias_Matrimonio__c))+'  Restantes: '+parseInt(dataGladiador.Dias_Matrimonio__c);
        }
        if(value.Concepto__c == 'Por mudanza'){
            this.PorMudanza = 'Otorgados: '+ parseInt(value.Dias_disponibles__c)+'  Tomados: '+(parseInt(value.Dias_disponibles__c) - parseInt(dataGladiador.Dias_Mudanza__c))+'  Restantes: '+parseInt(dataGladiador.Dias_Mudanza__c);
        }
    }

    getTableValues(){ 
        getSolicitudes({IdGladiador : this.isAuthGladiador.Id})
                        .then((dataTable) => {  
                            this.recordsSolicitudVacaciones = Object.keys(dataTable).map(item=>({
                                "Name": dataTable[item].Gladiador__r.Name, 
                                "DiasSolicitados": dataTable[item].Dias_que_se_Solicitan__c,
                                "FechaSolicitud": dataTable[item].Fecha_de_Solicitud__c,
                                "diasDesde": dataTable[item].Dias_Desde__c,
                                "diasHasta": dataTable[item].Dias_Hasta__c,
                                "etapa": dataTable[item].Etapa__c,
                                "tipoPermiso" : dataTable[item].TIpo_de_Permiso__c,
                                "Id": dataTable[item].Id,
                                "motivoDeAusencia": dataTable[item].Motivo_de_ausencia__c,

                                "isSolicitado": (dataTable[item].Etapa__c == 'Creado' ? true : false),
                                "canBeDeleted": (new Date(dataTable[item].Dias_Desde__c.replace( /(\d{4})-(\d{2})-(\d{2})/, "$2/$3/$1")) <= new Date() && dataTable[item].Etapa__c == 'Aceptado' ? false : true)
                            })); 
                        });
    }

    comboboxGladiador(event){
        this.recordGladiadorId = event.target.value;
    }isNewSolicitud

    newSolicitud(event){
        this.isNewSolicitud = true;
    }

    async handleSubmit(event) {
        event.preventDefault(); // stop the form from submitting
        const fields = event.detail.fields;
        if(fields.TIpo_de_Permiso__c == 'Permiso especial'){
            if(!fields.Motivo_de_ausencia__c){
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message :'Motivo de ausencia necesita tener una descripcion',
                        variant: 'error',
                    }),
                );
                return;
            }
            
        }

        if(fields.TIpo_de_Permiso__c != 'Permiso especial'){
            fields.Motivo_de_ausencia__c = fields.TIpo_de_Permiso__c;
        }

        var today = new Date();
        let recordIdValue;
        console.log(
            { fechaSolicitud : today.toISOString(), 
                idGladiadior : this.recordGladiadorId, 
                fechaDesde : fields.Dias_Desde__c, 
                fechaHasta : fields.Dias_Hasta__c, 
                tipoPermiso : fields.TIpo_de_Permiso__c, 
                motivoAusencia : fields.Motivo_Ausencia__c, 
                motivoAusenciaDescription : fields.Motivo_de_ausencia__c,
                Establecerhora : fields.Establecer_hora__c,
                HoraRegresoSolicitada : fields.Hora_regreso_solicitada__c,
                HoraSalidaSolicitada : fields.Hora_salida_solicitada__c,
                MotivoInexcusable : fields.Motivo_Inexcusable__c
            }
        );
        createSolicitudVacaciones({ fechaSolicitud : today.toISOString(), 
                                    idGladiadior : this.recordGladiadorId, 
                                    fechaDesde : fields.Dias_Desde__c, 
                                    fechaHasta : fields.Dias_Hasta__c, 
                                    tipoPermiso : fields.TIpo_de_Permiso__c, 
                                    motivoAusencia : fields.Motivo_Ausencia__c, 
                                    motivoAusenciaDescription : fields.Motivo_de_ausencia__c,
                                    Establecerhora : fields.Establecer_hora__c,
                                    HoraRegresoSolicitada : fields.Hora_regreso_solicitada__c,
                                    HoraSalidaSolicitada : fields.Hora_salida_solicitada__c,
                                    MotivoInexcusable : fields.Motivo_Inexcusable__c
                                })
        .then((dataTable) => { 
                recordIdValue = dataTable[0].Id; 
                this.recordsSolicitudVacaciones = Object.keys(dataTable).map(item=>({
                    "Name": dataTable[item].Gladiador__r.Name, 
                    "DiasSolicitados": dataTable[item].Dias_que_se_Solicitan__c,
                    "FechaSolicitud": dataTable[item].Fecha_de_Solicitud__c,
                    "diasDesde": dataTable[item].Dias_Desde__c,
                    "diasHasta": dataTable[item].Dias_Hasta__c,
                    "etapa": dataTable[item].Etapa__c,
                    "tipoPermiso" : dataTable[item].TIpo_de_Permiso__c,
                    "Id": dataTable[item].Id,

                    "isSolicitado": (dataTable[item].Etapa__c == 'Creado' ? true : false),
                    "canBeDeleted": (new Date(dataTable[item].Dias_Desde__c.replace( /(\d{4})-(\d{2})-(\d{2})/, "$2/$3/$1")) <= new Date() && dataTable[item].Etapa__c == 'Aceptado' ? false : true)
                }));
                this.isNewSolicitud = false; 

                if(this.loadFile){
                    for(var i=0; i <= this.loadFile.length; i++){ 
                        let tempVar = this.loadFile[i]?.documentId;
                        if(tempVar && recordIdValue){ 
                            uploadFiles({IdFile: tempVar, IdRecord: recordIdValue})
                            .then((data) => {
                                console.log('Success file');
                            }).catch((error) => { 
                            
                            });
                        }
                    }
                }

        }).catch((error) => { 
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message : error.body.message,
                    variant: 'error',
                }),
            );
        });    
    }

    async handleSolicitarVacaciones(event){
        updateSolicitudVacaciones({ idSolicitud : event.target.value, idGladiadior : this.recordGladiadorId })
        .then((dataTable) => { console.log('dataTable '+new Date(dataTable[0].Dias_Desde__c.replace( /(\d{4})-(\d{2})-(\d{2})/, "$2/$3/$1")));
                this.recordsSolicitudVacaciones = Object.keys(dataTable).map(item=>({
                    "Name": dataTable[item].Gladiador__r.Name, 
                    "DiasSolicitados": dataTable[item].Dias_que_se_Solicitan__c,
                    "FechaSolicitud": dataTable[item].Fecha_de_Solicitud__c,
                    "diasDesde": dataTable[item].Dias_Desde__c,
                    "diasHasta": dataTable[item].Dias_Hasta__c,
                    "etapa": dataTable[item].Etapa__c,
                    "tipoPermiso" : dataTable[item].TIpo_de_Permiso__c,
                    "Id": dataTable[item].Id,

                    "isSolicitado": (dataTable[item].Etapa__c == 'Creado' ? true : false),
                    "canBeDeleted": (new Date(dataTable[item].Dias_Desde__c.replace( /(\d{4})-(\d{2})-(\d{2})/, "$2/$3/$1")) <= new Date() && dataTable[item].Etapa__c == 'Aceptado' ? false : true)
                })); 
        }).catch((error) => {  console.log(error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message : error.body.message,
                    variant: 'error',
                }),
            );
        });
    }

    async deleteSolicitudVacaciones(event){
        let text = "Estas seguro de eliminar este registro ?";
        if (confirm(text) == true) {
            deleteSolicitudVacaciones({ idSolicitud : event.target.value, idGladiadior : this.recordGladiadorId })
            .then((dataTable) => { console.log('dataTable '+dataTable);
                    this.recordsSolicitudVacaciones = Object.keys(dataTable).map(item=>({
                        "Name": dataTable[item].Gladiador__r.Name, 
                        "DiasSolicitados": dataTable[item].Dias_que_se_Solicitan__c,
                        "FechaSolicitud": dataTable[item].Fecha_de_Solicitud__c,
                        "diasDesde": dataTable[item].Dias_Desde__c,
                        "diasHasta": dataTable[item].Dias_Hasta__c,
                        "etapa": dataTable[item].Etapa__c,
                        "tipoPermiso" : dataTable[item].TIpo_de_Permiso__c,
                        "Id": dataTable[item].Id,

                        "isSolicitado": (dataTable[item].Etapa__c == 'Creado' ? true : false),
                        "canBeDeleted": (new Date(dataTable[item].Dias_Desde__c.replace( /(\d{4})-(\d{2})-(\d{2})/, "$2/$3/$1")) <= new Date() && dataTable[item].Etapa__c == 'Aceptado' ? false : true)
                    })); 
            });
        }
    }

    cancelForm(){
        this.isNewSolicitud = false;
    }

    catchFile(event){ console.log('entro');
        //event.preventDefault();
        let uploadedFiles = event.detail.files;
        this.loadFile = uploadedFiles; console.log('Files yesssss');
    }

}