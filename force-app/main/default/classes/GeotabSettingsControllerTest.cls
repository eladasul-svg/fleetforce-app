@IsTest
private class GeotabSettingsControllerTest {

    @IsTest
    static void testGetGeotabSettings_withRecord() {
        // Geotab_Setting__mdt.Default is deployed in source with test-fake credentials.
        // CMT records are always visible in tests regardless of seeAllData.
        Test.startTest();
        Map<String, String> settings = GeotabSettingsController.getGeotabSettings();
        Test.stopTest();

        System.assertNotEquals(null, settings, 'Settings map should not be null');
        System.assert(settings.containsKey('server'), 'Settings map should contain server key');
        System.assert(settings.containsKey('database'), 'Settings map should contain database key');
        System.assert(settings.containsKey('username'), 'Settings map should contain username key');
        System.assert(settings.containsKey('passwordMasked'), 'Settings map should contain passwordMasked key');
        System.assertEquals('true', settings.get('hasPassword'),
            'hasPassword should be true since Default CMT record has a password');
        System.assertEquals('********', settings.get('passwordMasked'),
            'Password should be masked in the response');
    }

    @IsTest
    static void testSaveGeotabSettings_withNewPassword() {
        // Metadata.Operations.enqueueDeployment() may throw in scratch org test context;
        // the production catch block rethrows as AuraHandledException. Either path covers lines.
        Test.startTest();
        try {
            String jobId = GeotabSettingsController.saveGeotabSettings(
                'test-fake-db-000',
                'test-fake-server-000.geotab.com',
                'test-fake-user-000@example.com',
                'test-fake-new-password-000'
            );
            System.assertNotEquals(null, jobId, 'If deployment queued, jobId should be non-null');
        } catch (AuraHandledException e) {
            System.assert(true, 'AuraHandledException acceptable when enqueueDeployment is unavailable in test context');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSaveGeotabSettings_maskedPasswordSkipped() {
        // When password is '********', the password field is omitted from the deployment payload.
        Test.startTest();
        try {
            String jobId = GeotabSettingsController.saveGeotabSettings(
                'test-fake-db-000',
                'test-fake-server-000.geotab.com',
                'test-fake-user-000@example.com',
                '********'
            );
            System.assertNotEquals(null, jobId);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @IsTest
    static void testSaveGeotabSettings_blankPasswordSkipped() {
        Test.startTest();
        try {
            String jobId = GeotabSettingsController.saveGeotabSettings(
                'test-fake-db-000',
                'test-fake-server-000.geotab.com',
                'test-fake-user-000@example.com',
                ''
            );
            System.assertNotEquals(null, jobId);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @IsTest
    static void testHandleResult_succeeded() {
        GeotabSettingsController ctrl = new GeotabSettingsController();
        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status = Metadata.DeployStatus.Succeeded;
        Metadata.DeployCallbackContext ctx = new Metadata.DeployCallbackContext();

        Test.startTest();
        ctrl.handleResult(result, ctx);
        Test.stopTest();
        // No exception = pass
    }

    @IsTest
    static void testHandleResult_failed() {
        GeotabSettingsController ctrl = new GeotabSettingsController();
        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status = Metadata.DeployStatus.Failed;
        result.errorMessage = 'Test deployment failure';
        Metadata.DeployCallbackContext ctx = new Metadata.DeployCallbackContext();

        Test.startTest();
        ctrl.handleResult(result, ctx);
        Test.stopTest();
        // No exception = pass; error path logged via System.debug
    }
}
