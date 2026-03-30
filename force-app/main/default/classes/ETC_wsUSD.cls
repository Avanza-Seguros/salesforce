/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 05-17-2023
 * @last modified by  : MRHE
**/
public with sharing class ETC_wsUSD extends ETC_Callout{
    public static final String ENDPOINTNAME = 'wsUSD';

    public ETC_wsUSD (){
        this.claseApex = ETC_wsUSD.class.getName();
    }

    private Decimal calloutgetUSD(){
        System.debug('<--calloutgetUSD');
        Callout callout = createCallout(ENDPOINTNAME);
        Datetime fechaInicio =ETC_Callout.getDateTime(Date.newInstance(System.today().addMonths(-1).year(), System.today().addMonths(-1).month(), 1));
        Datetime fechaFin = System.now();
        callout.request.setEndpoint(callout.request.getEndpoint() + '/'+fechaInicio.format('YYYY-MM-dd')+'/'+fechaFin.format('YYYY-MM-dd'));
        HttpResponse response = sendCallout(callout);

        System.debug(response.getStatusCode());
        System.debug(response.getBody());

        Decimal tipoCambio = null;
        if(response.getStatusCode() == 200 || Test.isRunningTest()) {
            ETC_ModelBanxicoResponse bodyResponse = ETC_ModelBanxicoResponse.parse(Test.isRunningTest()? this.mdt.Response__c :response.getBody());
            Date fecha = null;
            
            for (ETC_ModelBanxicoResponse.Datos dato : bodyResponse.bmx.series[0]?.datos) {
                Date fechaActual = ETC_Callout.getDateString(dato.fecha);
                if(fecha ==  null){
                    fecha = fechaActual;
                    tipoCambio = Decimal.valueOf(dato.dato);
                }else{
                    if(fecha < fechaActual) {
                        fecha = fechaActual;
                        tipoCambio = Decimal.valueOf(dato.dato);
                    }
                }
            }
        }
        System.debug('calloutgetUSD-->');
        return tipoCambio;
    }


    public static Decimal getUSD(){
        ETC_wsUSD ws = new ETC_wsUSD();
        return ws.calloutgetUSD();
    }
}