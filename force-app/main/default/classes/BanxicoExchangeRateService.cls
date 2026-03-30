public with sharing class BanxicoExchangeRateService {
    
    private static final String CONFIG_NAME = 'Banxico_API';

    public static void fetchLatestRates() {
        fetchRates(null, null, true);
    }

    public static void fetchHistoricalRates(Date startDate, Date endDate) {
        fetchRates(startDate, endDate, false);
    }

    private static void fetchRates(Date startDate, Date endDate, Boolean oportunoOnly) {

        List<ExchangeRateSeries__mdt> seriesList = [
            SELECT SeriesCode__c, CurrencyType__c
            FROM ExchangeRateSeries__mdt
            WHERE Active__c = TRUE
        ];

        List<Exchange_Rate_History__c> allRecords = new List<Exchange_Rate_History__c>();

        for(ExchangeRateSeries__mdt series : seriesList){
            Boolean isUDI = series.CurrencyType__c == 'UDI';
            String endpoint;

            if(oportunoOnly && !isUDI){
                endpoint = '/' + series.SeriesCode__c + '/datos/oportuno';

            } else {
                Date effectiveStart = (startDate != null) ? startDate : Date.today();
                Date effectiveEnd   = (endDate   != null) ? endDate   : Date.today().addDays(60);

                String start = DateTime.newInstance(effectiveStart, Time.newInstance(0,0,0,0)).format('yyyy-MM-dd');
                String endDay = DateTime.newInstance(effectiveEnd, Time.newInstance(0,0,0,0)).format('yyyy-MM-dd');

                endpoint = '/' + series.SeriesCode__c + '/datos/' + start + '/' + endDay;
            }

            HttpResponse res = IntegrationHttpClient.send(CONFIG_NAME, endpoint, null);

            if(res.getStatusCode() != 200){
                continue;
            }

            Map<String,Object> json = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> seriesData = (List<Object>) ((Map<String,Object>)json.get('bmx')).get('series');
            Map<String,Object> firstSeries = (Map<String,Object>) seriesData[0];
            List<Object> datos = (List<Object>) firstSeries.get('datos');

            for(Object o : datos){
                Map<String,Object> rate = (Map<String,Object>) o;

                Date rateDate = IntegrationDataUtils.parseDateDDMMYYYY((String)rate.get('fecha'));
                Decimal value = IntegrationDataUtils.parseDecimal((String)rate.get('dato'));

                Exchange_Rate_History__c record = new Exchange_Rate_History__c();
                record.RateDate__c     = rateDate;
                record.RateValue__c    = value;
                record.CurrencyType__c = series.CurrencyType__c;
                record.SeriesCode__c   = series.SeriesCode__c;
                record.Source__c       = 'BANXICO';
                record.UniqueKey__c    = series.CurrencyType__c + '_' + String.valueOf(rateDate);

                allRecords.add(record);
            }
        }

        if(!allRecords.isEmpty()){
            upsert allRecords UniqueKey__c;
        }
    }
}