public with sharing class IntegrationDataUtils {
    
    public static Date parseDateDDMMYYYY(String input){
        if(String.isBlank(input) || input == '00/00/0000') return null;
        List<String> parts = input.split('/');
        return Date.newInstance(
            Integer.valueOf(parts[2]),
            Integer.valueOf(parts[1]),
            Integer.valueOf(parts[0])
        );
    }

    public static Datetime toDateTime(Date d){
        return d == null ? null : Datetime.newInstance(d.year(), d.month(), d.day());
    }

    public static Decimal parseDecimal(String val){
        if(String.isBlank(val)) return null;
        return Decimal.valueOf(val);
    }

    public static String safeString(String val){
        return val == null ? '' : val.trim();
    }

    public static String removeLeadingZeros(String val){
        return String.isBlank(val) ? '' : val.replaceFirst('^0+', '');
    }
}