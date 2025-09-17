/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 05-05-2023
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public with sharing class ETC_ModelBanxicoResponse {
    public class Series {
		public String idSerie;
		public String titulo;
		public List<Datos> datos;
	}

	public Bmx bmx;

	public class Datos {
		public String fecha;
		public String dato;
	}

	public class Bmx {
		public List<Series> series;
	}

	
	public static ETC_ModelBanxicoResponse parse(String json) {
		return (ETC_ModelBanxicoResponse) System.JSON.deserialize(json, ETC_ModelBanxicoResponse.class);
	}
}