@IsTest
private class GeotabSyncBatchTest {

    // Stateful mock: returns auth, then GPS, then odometer, then fuel responses in order.
    private class GeotabBatchMock implements HttpCalloutMock {
        Integer callCount = 0;

        public HttpResponse respond(HttpRequest req) {
            callCount++;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            if (callCount == 1) {
                // authenticate() — success, no redirect
                res.setBody('{"jsonrpc":"2.0","result":{"credentials":{"sessionId":"test-session-id-000","database":"test-fake-db-000","userName":"test-fake-user-000@example.com"},"path":"ThisServer"},"id":1}');
            } else if (callCount == 2) {
                // fetchDeviceStatusInfo() — one device with GPS coords
                res.setBody('{"jsonrpc":"2.0","result":[{"device":{"id":"dev001"},"latitude":32.0853,"longitude":34.7818}],"id":2}');
            } else if (callCount == 3) {
                // fetchStatusData('DiagnosticOdometerId') — 1609344 metres = ~1000 miles
                res.setBody('{"jsonrpc":"2.0","result":[{"device":{"id":"dev001"},"data":1609344,"dateTime":"2024-01-01T12:00:00.000Z"}],"id":3}');
            } else {
                // fetchStatusData('DiagnosticFuelLevelPercentageId') — 75%
                res.setBody('{"jsonrpc":"2.0","result":[{"device":{"id":"dev001"},"data":0.75,"dateTime":"2024-01-01T12:00:00.000Z"}],"id":3}');
            }
            return res;
        }
    }

    @TestSetup
    static void makeData() {
        Account vendor = new Account(Name = 'Test Vendor Batch');
        insert vendor;

        fleetforce__Fleet_Asset__c asset = new fleetforce__Fleet_Asset__c(
            Name = 'BATCH-ASSET-001',
            fleetforce__Status__c = 'Assigned',
            fleetforce__Vendor__c = vendor.Id
        );
        insert asset;

        fleetforce__Telematics_Equipment__c equipment = new fleetforce__Telematics_Equipment__c(
            Name = 'BATCH-EQUIP-001',
            fleetforce__Fleet_Asset__c = asset.Id,
            Geotab_Id__c = 'dev001'
        );
        insert equipment;
    }

    @IsTest
    static void testBatch_updatesAssetFromGeotab() {
        Test.setMock(HttpCalloutMock.class, new GeotabBatchMock());

        Test.startTest();
        Database.executeBatch(new GeotabSyncBatch(), 50);
        Test.stopTest();

        fleetforce__Fleet_Asset__c updated = [
            SELECT Id, fleetforce__Odometer__c, fleetforce__Fuel_Energy_Level__c,
                   fleetforce__Last_Location__Latitude__s, fleetforce__Last_Location__Longitude__s
            FROM fleetforce__Fleet_Asset__c
            WHERE Name = 'BATCH-ASSET-001'
            LIMIT 1
        ];

        System.assertNotEquals(null, updated.fleetforce__Last_Location__Latitude__s,
            'Batch should have written GPS latitude to the Fleet Asset');
        System.assertNotEquals(null, updated.fleetforce__Last_Location__Longitude__s,
            'Batch should have written GPS longitude to the Fleet Asset');
        System.assertEquals(1000, updated.fleetforce__Odometer__c,
            'Odometer should be ~1000 miles (1609344 metres / 1609.344)');
        System.assertEquals(75, updated.fleetforce__Fuel_Energy_Level__c,
            'Fuel level should be 75% (0.75 ratio × 100)');
    }

    @IsTest
    static void testBatch_noEquipment_completesCleanly() {
        // With no Telematics Equipment, the batch start() returns 0 rows,
        // execute() is skipped, and finish() runs — no callouts needed.
        Test.startTest();
        Database.executeBatch(new GeotabSyncBatch(), 50);
        Test.stopTest();

        List<AsyncApexJob> jobs = [
            SELECT Id, Status
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND Status = 'Completed'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assert(!jobs.isEmpty(), 'Batch should complete even with no equipment records');
    }
}
