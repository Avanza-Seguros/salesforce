public with sharing class PagoPolizaValorMonedaBatch implements Database.Batchable<SObject>, Database.Stateful {

    private Boolean runHistorico;

    private Map<String, List<Exchange_Rate_History__c>> ratesByCurrency;

    public PagoPolizaValorMonedaBatch(Boolean runHistorico){
        this.runHistorico = runHistorico;
    }

    public Database.QueryLocator start(Database.BatchableContext bc){

        ratesByCurrency = new Map<String, List<Exchange_Rate_History__c>>();

        Date todayDate = Date.today();

        List<Exchange_Rate_History__c> rates = [
            SELECT CurrencyType__c, RateValue__c, RateDate__c
            FROM Exchange_Rate_History__c
            WHERE CurrencyType__c IN ('UDI','UDIS','USD')
            AND RateDate__c <= :todayDate
            ORDER BY CurrencyType__c, RateDate__c DESC
        ];

        for(Exchange_Rate_History__c r : rates){

            if(!ratesByCurrency.containsKey(r.CurrencyType__c)){
                ratesByCurrency.put(r.CurrencyType__c, new List<Exchange_Rate_History__c>());
            }

            ratesByCurrency.get(r.CurrencyType__c).add(r);
        }

        return Database.getQueryLocator(
            'SELECT Id, Tipo_de_Moneda__c, Valor_Moneda__c, Fecha_de_de_Vencimiento__c,' +
            'Estatus_pago__c, Fecha_de_Aplicaci_n_del_pago__c ' +
            'FROM Pago_Poliza__c ' +
            'WHERE Tipo_de_Moneda__c IN (\'UDI\', \'UDIS\', \'USD\')'
        );
    }

    public void execute(Database.BatchableContext bc, List<Pago_Poliza__c> scope){

        List<Pago_Poliza__c> toUpdate = new List<Pago_Poliza__c>();
        Date todayDate = Date.today();

        for(Pago_Poliza__c p : scope){

            Decimal newRate;
            String monedaNormalizada = normalizeCurrency(p.Tipo_de_Moneda__c);

            if(runHistorico){

                if(p.Estatus_pago__c == 'Pagado'){

                    if(p.Fecha_de_Aplicaci_n_del_pago__c != null){

                        newRate = findRate(monedaNormalizada, p.Fecha_de_Aplicaci_n_del_pago__c);
                    }

                } else if(p.Estatus_pago__c == 'Pendiente'){
                    
                    newRate = findRate(monedaNormalizada, todayDate);

                } else if(p.Estatus_pago__c == 'Cancelado' || p.Estatus_pago__c == 'Vencida'){
                    
                    if(p.Fecha_de_de_Vencimiento__c != null){

                        newRate = findRate(monedaNormalizada, p.Fecha_de_de_Vencimiento__c);

                    } else {

                        newRate = findRate(monedaNormalizada, todayDate);

                    }
                }

            } else {

                if(p.Estatus_pago__c == 'Pendiente'){
                    newRate = findRate(monedaNormalizada, todayDate);
                }
            }

            if(newRate != null && p.Valor_Moneda__c != newRate){
                p.Valor_Moneda__c = newRate;
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

    public void finish(Database.BatchableContext bc){
        System.debug('Recalculo completado. Modo historico: ' + runHistorico);
    }

    private String normalizeCurrency(String moneda){
        if(moneda == null) return null;

        moneda = moneda.trim().toUpperCase();

        if(moneda == 'UDIS'){
            return 'UDI';
        }
        return moneda;
    }
}