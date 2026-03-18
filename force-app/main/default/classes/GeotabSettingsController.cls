public with sharing class GeotabSettingsController implements Metadata.DeployCallback {
    
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getGeotabSettings() {
        Map<String, String> settings = new Map<String, String>();
        try {
            // We expect only one record, e.g., 'Default'
            Geotab_Setting__mdt setting = [SELECT Database__c, Server__c, Username__c, Password__c 
                                          FROM Geotab_Setting__mdt LIMIT 1];
            settings.put('database', setting.Database__c);
            settings.put('server', setting.Server__c);
            settings.put('username', setting.Username__c);
            // Don't send password back to the UI in plain text for security, or send a mask
            settings.put('passwordMasked', String.isNotBlank(setting.Password__c) ? '********' : '');
            settings.put('hasPassword', String.isNotBlank(setting.Password__c) ? 'true' : 'false');
        } catch(Exception e) {
            // No settings exist yet
            settings.put('server', 'my.geotab.com');
        }
        return settings;
    }

    @AuraEnabled
    public static String saveGeotabSettings(String database, String server, String username, String password) {
        try {
            Metadata.CustomMetadata customMetadata = new Metadata.CustomMetadata();
            customMetadata.fullName = 'Geotab_Setting__mdt.Default';
            customMetadata.label = 'Default';

            Metadata.CustomMetadataValue dbField = new Metadata.CustomMetadataValue();
            dbField.field = 'Database__c';
            dbField.value = database;
            customMetadata.values.add(dbField);

            Metadata.CustomMetadataValue serverField = new Metadata.CustomMetadataValue();
            serverField.field = 'Server__c';
            serverField.value = server;
            customMetadata.values.add(serverField);

            Metadata.CustomMetadataValue userField = new Metadata.CustomMetadataValue();
            userField.field = 'Username__c';
            userField.value = username;
            customMetadata.values.add(userField);

            if(String.isNotBlank(password) && password != '********') {
                Metadata.CustomMetadataValue passField = new Metadata.CustomMetadataValue();
                passField.field = 'Password__c';
                passField.value = password;
                customMetadata.values.add(passField);
            }

            Metadata.DeployContainer mdContainer = new Metadata.DeployContainer();
            mdContainer.addMetadata(customMetadata);

            GeotabSettingsController callback = new GeotabSettingsController();
            Id jobId = Metadata.Operations.enqueueDeployment(mdContainer, callback);
            return jobId;
        } catch(Exception e) {
            throw new AuraHandledException('Error saving mapping: ' + e.getMessage());
        }
    }

    public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
        if (result.status == Metadata.DeployStatus.Succeeded) {
            System.debug('Geotab Settings Deployment Succeeded!');
        } else {
            System.debug('Geotab Settings Deployment Failed: ' + result.errorMessage);
        }
    }
}
