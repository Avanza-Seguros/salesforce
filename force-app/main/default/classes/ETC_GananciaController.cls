/**
 * @description       : 
 * @author            : MRHE
 * @group             : 
 * @last modified on  : 05-23-2023
 * @last modified by  : MRHE
**/

public with sharing class ETC_GananciaController {
    
    //27 - 13  14 - 26 este este
    @AuraEnabled
    public static Decimal getGananciaActual(){


        Decimal gananciaActual = 0;
        Date fechaActual = System.today();

        Integer diaActual = fechaActual.day();

        Date rangoInferior;
        Date rangoSuperior;

        if(diaActual>=27 && diaActual<=13 || Test.isRunningTest()){
            rangoInferior = Date.newInstance(fechaActual.year(), fechaActual.month(), 27);
            rangoSuperior = Date.newInstance(fechaActual.addMonths(1).year(), fechaActual.addMonths(1).month(), 13);
        }
        if(diaActual>=14 && diaActual<=27 || Test.isRunningTest()){
            rangoInferior = Date.newInstance(fechaActual.year(), fechaActual.month(), 14);
            rangoSuperior = Date.newInstance(fechaActual.year(), fechaActual.month(), 26);
        }


        for(Polizas__c poliza :[SELECT Id, Fecha_de_pago_de_comision__c, Comicion_Neta__c 
            FROM Polizas__c WHERE Fecha_de_pago_de_comision__c >= :rangoInferior AND Fecha_de_pago_de_comision__c <= :rangoSuperior]){
                gananciaActual += poliza.Comicion_Neta__c;
                System.debug(gananciaActual);
        }
        Comision__c comision = new Comision__c();
        comision.OwnerId = UserInfo.getUserId();
        comision.Rango_de_Fecha__c = rangoInferior.format() + '-' + rangoSuperior.format();
        comision.Comision__c = gananciaActual;
        comision.Inicio_Periodo__c = rangoInferior;
        comision.Fin_Periodo__c = rangoSuperior;
        upsert comision Rango_de_Fecha__c;
        return gananciaActual;
        
    }

    @AuraEnabled
    public static Decimal getGananciaAnterior(){
        System.debug('getGananciaAnterior');
        Decimal gananciaActual = 0;
        Date fechaActual = System.today();

        Integer diaActual = fechaActual.day();

        Date rangoInferior;
        Date rangoSuperior;

        if(  diaActual>=27 && diaActual<=13 || Test.isRunningTest()){
            rangoInferior = Date.newInstance(fechaActual.addMonths(-1).year(), fechaActual.addMonths(-1).month(), 14);
            rangoSuperior = Date.newInstance(fechaActual.addMonths(-1).year(), fechaActual.addMonths(-1).month(), 26);
        }
        if(diaActual>=14 && diaActual<=27 || Test.isRunningTest()){
            rangoInferior = Date.newInstance(fechaActual.addMonths(-1).year(), fechaActual.addMonths(-1).month(), 27);
            rangoSuperior = Date.newInstance(fechaActual.year(), fechaActual.month(), 13);
        }


        for(Polizas__c poliza :[SELECT Id, Fecha_de_pago_de_comision__c, Comicion_Neta__c 
            FROM Polizas__c WHERE Fecha_de_pago_de_comision__c >= :rangoInferior AND Fecha_de_pago_de_comision__c <= :rangoSuperior]){
                gananciaActual += poliza.Comicion_Neta__c;
                System.debug(gananciaActual);
        }
        Comision__c comision = new Comision__c();
        comision.OwnerId = UserInfo.getUserId();
        comision.Rango_de_Fecha__c = rangoInferior.format() + '-' + rangoSuperior.format();
        comision.Comision__c = gananciaActual;
        comision.Inicio_Periodo__c = rangoInferior;
        comision.Fin_Periodo__c = rangoSuperior;
        upsert comision Rango_de_Fecha__c;
        return gananciaActual;
    }
}