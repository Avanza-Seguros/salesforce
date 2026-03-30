public with sharing class IntegrationConfigService {
    
    public static IntegrationConfig__mdt getConfig(String developerName) {
        IntegrationConfig__mdt cfg = [
            SELECT BaseUrl__c, BasePath__c, HttpMethod__c,
                   TimeoutMs__c, ContentType__c, AcceptHeader__c,
                   AuthHeaderName__c, AuthToken__c, Active__c
            FROM IntegrationConfig__mdt
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];

        if(cfg == null || !cfg.Active__c){
            throw new CalloutException('Integration config not active: ' + developerName);
        }

        return cfg;
    }
}