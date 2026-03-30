@isTest
public with sharing class IntegrationHttpClientTest {
    @IsTest
    static void testSend() {

        Test.setMock(HttpCalloutMock.class, new BanxicoHttpMock());

        Test.startTest();
        HttpResponse res = IntegrationHttpClient.send(
            'Banxico_API',
            '/series/SF63528/datos/oportuno',
            null
        );
        Test.stopTest();

        Assert.areEqual(200, res.getStatusCode());
        Assert.isTrue(res.getBody().contains('series'));
    }
}