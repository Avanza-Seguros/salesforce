public with sharing class IntegrationHttpClient {
    public static HttpResponse send(String configName, String relativePath, String body) {

        IntegrationConfig__mdt cfg = IntegrationConfigService.getConfig(configName);

        String finalEndpoint = cfg.BaseUrl__c + cfg.BasePath__c + relativePath;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(finalEndpoint);
        req.setMethod(cfg.HttpMethod__c);
        req.setTimeout(Integer.valueOf(cfg.TimeoutMs__c));

        if(String.isNotBlank(cfg.ContentType__c)) {
            req.setHeader('Content-Type', cfg.ContentType__c);
        }

        if(String.isNotBlank(cfg.AcceptHeader__c)) {
            req.setHeader('Accept', cfg.AcceptHeader__c);
        }

        if(String.isNotBlank(cfg.AuthHeaderName__c) && String.isNotBlank(cfg.AuthToken__c)) {
            req.setHeader(cfg.AuthHeaderName__c, cfg.AuthToken__c);
        }

        if(body != null) {
            req.setBody(body);
        }

        Http http = new Http();
        HttpResponse res = http.send(req);

        return res;
    }
}