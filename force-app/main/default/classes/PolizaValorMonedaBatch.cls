public with sharing class PolizaValorMonedaBatch implements Database.Batchable<SObject>, Database.Stateful {

    private Boolean runHistorico;
    private Map<String, List<Exchange_Rate_History__c>> ratesByCurrency;

    public PolizaValorMonedaBatch(Boolean runHistorico){
        this.runHistorico = runHistorico;
    }

    public Database.QueryLocator start(Database.BatchableContext bc){

        ratesByCurrency = new Map<String, List<Exchange_Rate_History__c>>();

        Date todayDate = Date.today();

        List<Exchange_Rate_History__c> rates = [
            SELECT CurrencyType__c, RateValue__c, RateDate__c
            FROM Exchange_Rate_History__c
            WHERE CurrencyType__c IN ('UDI','USD')
            AND RateDate__c <= :todayDate
            ORDER BY CurrencyType__c, RateDate__c DESC
        ];

        for(Exchange_Rate_History__c r : rates){

            String monedaKey = normalizeCurrency(r.CurrencyType__c);

            if(!ratesByCurrency.containsKey(monedaKey)){
                ratesByCurrency.put(monedaKey, new List<Exchange_Rate_History__c>());
            }

            ratesByCurrency.get(monedaKey).add(r);
        }

        return Database.getQueryLocator(
            'SELECT Id, Moneda__c, Moneda_Hoy__c, ' +
            'Valor_Moneda_Emision__c, Fecha_de_Emision__c ' +
            'FROM Polizas__c ' +
            'WHERE Moneda__c != null'
        );
    }

    public void execute(Database.BatchableContext bc, List<Polizas__c> scope){

        List<Polizas__c> toUpdate = new List<Polizas__c>();
        Date todayDate = Date.today();

        for(Polizas__c p : scope){

            Boolean changed = false;

            String monedaNormalizada = normalizeCurrency(p.Moneda__c);
            if(monedaNormalizada == null){
                continue;
            }

            Decimal rateHoy = findRate(monedaNormalizada, todayDate);

            if(p.Moneda_Hoy__c != rateHoy){
                p.Moneda_Hoy__c = rateHoy;
                changed = true;
            }

            if(p.Fecha_de_Emision__c != null){

                Boolean debeCalcularEmision = false;

                if(runHistorico){
                    debeCalcularEmision = true;
                } else {
                    if(p.Valor_Moneda_Emision__c == null){
                        debeCalcularEmision = true;
                    }
                }

                if(debeCalcularEmision){

                    Decimal rateEmision = findRate(
                        monedaNormalizada,
                        p.Fecha_de_Emision__c
                    );

                    if(p.Valor_Moneda_Emision__c != rateEmision){
                        p.Valor_Moneda_Emision__c = rateEmision;
                        changed = true;
                    }
                }
            }

            if(changed){
                toUpdate.add(p);
            }
        }

        if(!toUpdate.isEmpty()){
            update toUpdate;
        }
    }


    private Decimal findRate(String moneda, Date targetDate){

        if(!ratesByCurrency.containsKey(moneda)){
            return null;
        }

        for(Exchange_Rate_History__c r : ratesByCurrency.get(moneda)){
            if(r.RateDate__c <= targetDate){
                return r.RateValue__c;
            }
        }

        return null;
    }


    private String normalizeCurrency(String moneda){

        if(moneda == null) return null;

        moneda = moneda.trim().toUpperCase();

        if(moneda == 'UDIS') return 'UDI';
        if(moneda == 'DLLS') return 'USD';

        return moneda;
    }

    public void finish(Database.BatchableContext bc){
        System.debug('Recalculo Polizas completado. Modo historico: ' + runHistorico);
    }
}