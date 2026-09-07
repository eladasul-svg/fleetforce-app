@IsTest
private class FleetAssetMapControllerTest {

    @TestSetup
    static void makeData() {
        Account vendor = new Account(Name = 'Test Vendor');
        insert vendor;

        fleetforce__Fleet_Asset__c available = new fleetforce__Fleet_Asset__c(
            Name = 'TEST-AVAIL-001',
            fleetforce__Status__c = 'Available',
            fleetforce__Vendor__c = vendor.Id
        );
        insert available;

        fleetforce__Fleet_Asset__c inShopAsset = new fleetforce__Fleet_Asset__c(
            Name = 'TEST-SHOP-001',
            fleetforce__Status__c = 'Assigned',
            fleetforce__Vendor__c = vendor.Id
        );
        insert inShopAsset;

        fleetforce__Service_Ticket__c ticket = new fleetforce__Service_Ticket__c(
            fleetforce__Fleet_Asset__c = inShopAsset.Id,
            fleetforce__Status__c = 'In-Shop',
            fleetforce__Priority__c = 'High',
            fleetforce__Actual_Start__c = Date.today()
        );
        insert ticket;

        fleetforce__Fleet_Asset__c criticalAsset = new fleetforce__Fleet_Asset__c(
            Name = 'TEST-CRIT-001',
            fleetforce__Status__c = 'Assigned',
            fleetforce__Vendor__c = vendor.Id
        );
        insert criticalAsset;

        fleetforce__Telemetry_Violation__c violation = new fleetforce__Telemetry_Violation__c(
            fleetforce__Fleet_Asset__c = criticalAsset.Id,
            fleetforce__Severity__c = 'Critical',
            fleetforce__Timestamp__c = Datetime.now()
        );
        insert violation;
    }

    @IsTest
    static void testGetAssets_all() {
        Test.startTest();
        List<fleetforce__Fleet_Asset__c> result = FleetAssetMapController.getAssets('All');
        Test.stopTest();
        System.assertNotEquals(null, result);
        System.assert(result.size() >= 3, 'All filter should return all 3 test assets');
    }

    @IsTest
    static void testGetAssets_available() {
        Test.startTest();
        List<fleetforce__Fleet_Asset__c> result = FleetAssetMapController.getAssets('Available');
        Test.stopTest();
        System.assertEquals(1, result.size(), 'Available filter should return exactly 1 asset');
        System.assertEquals('Available', result[0].fleetforce__Status__c);
    }

    @IsTest
    static void testGetAssets_inShop() {
        Test.startTest();
        List<fleetforce__Fleet_Asset__c> result = FleetAssetMapController.getAssets('InShop');
        Test.stopTest();
        System.assertEquals(1, result.size(), 'InShop filter should return the 1 asset with an In-Shop ticket');
    }

    @IsTest
    static void testGetAssets_critical() {
        Test.startTest();
        List<fleetforce__Fleet_Asset__c> result = FleetAssetMapController.getAssets('Critical');
        Test.stopTest();
        System.assertEquals(1, result.size(), 'Critical filter should return the 1 asset with a Critical violation');
    }
}
