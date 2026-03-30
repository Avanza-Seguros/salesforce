/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 05-05-2023
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public with sharing class ETC_wsUDI extends ETC_Callout{
    public static final String ENDPOINTNAME = 'wsUDIS';

    public ETC_wsUDI (){
        this.claseApex = ETC_wsUDI.class.getName();
    }

    private Decimal calloutgetUDI(){
        System.debug('<--calloutgetUDI');
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
        System.debug('calloutgetUDI-->');
        return tipoCambio;
    }


    public static Decimal getUDI(){
        ETC_wsUDI ws = new ETC_wsUDI();
        return ws.calloutgetUDI();
    }
}