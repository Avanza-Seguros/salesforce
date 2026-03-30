@isTest
public with sharing class IntegrationDataUtilsTest {
    @IsTest
    static void testParsingHelpers() {
        Date d = IntegrationDataUtils.parseDateDDMMYYYY('05/02/2026');
        Assert.areEqual(Date.newInstance(2026,2,5), d);

        Decimal val = IntegrationDataUtils.parseDecimal('17.3456');
        Assert.areEqual(17.3456, val);

        Assert.areEqual('', IntegrationDataUtils.safeString(null));
        Assert.areEqual('ABC', IntegrationDataUtils.safeString('ABC'));
    }
}