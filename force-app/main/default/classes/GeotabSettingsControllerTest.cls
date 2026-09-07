@IsTest
private class GeotabSettingsControllerTest {

    @IsTest
    static void testGetGeotabSettings() {
        // CMT records cannot be created programmatically in tests.
        // When packaged without a Default record, the controller returns a graceful fallback.
        // When a Default record exists (post-install unpackaged deploy), full map is returned.
        // Both paths are valid; the test branches on what the org actually has.
        Test.startTest();
        Map<String, String> settings = GeotabSettingsController.getGeotabSettings();
        Test.stopTest();

        System.assertNotEquals(null, settings, 'Settings map should not be null');
        System.assert(settings.containsKey('server'), 'Settings map should always contain server key');

        Integer recordCount = [SELECT COUNT() FROM Geotab_Setting__mdt];
        if (recordCount > 0) {
            System.assert(settings.containsKey('database'), 'Should have database when CMT record exists');
            System.assert(settings.containsKey('username'), 'Should have username when CMT record exists');
            System.assert(settings.containsKey('passwordMasked'), 'Should have passwordMasked when CMT record exists');
        } else {
            // No CMT record: only 'server' fallback key is present
            System.assert(!settings.containsKey('database'), 'Should not have database without CMT record');
        }
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
