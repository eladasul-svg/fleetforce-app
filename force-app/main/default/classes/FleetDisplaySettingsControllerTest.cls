@IsTest
private class FleetDisplaySettingsControllerTest {

    @TestSetup
    static void grantAccess() {
        // FleetforceAdmin grants edit access to the setting (same pattern as AssistantToolsTest).
        Id userId = UserInfo.getUserId();
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'FleetforceAdmin' LIMIT 1];
        if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :userId AND PermissionSetId = :ps.Id] == 0) {
            System.runAs(new User(Id = userId)) {
                insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id);
            }
        }
    }

    @IsTest
    static void defaultsToSilhouetteWhenUnset() {
        System.assertEquals('silhouette', FleetDisplaySettingsController.getIconStyle());
    }

    @IsTest
    static void savedStyleIsReturned() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            System.assertEquals('classic', FleetDisplaySettingsController.saveIconStyle('Classic'));
            System.assertEquals('classic', FleetDisplaySettingsController.getIconStyle());
            FleetDisplaySettingsController.saveIconStyle('futuristic');
            System.assertEquals('futuristic', FleetDisplaySettingsController.getIconStyle());
        }
    }

    @IsTest
    static void unknownStyleIsRejected() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            try {
                FleetDisplaySettingsController.saveIconStyle('steampunk');
                System.assert(false, 'expected an exception');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
        System.assertEquals('silhouette', FleetDisplaySettingsController.getIconStyle());
    }
}
