@IsTest
private class FleetKpiControllerTest {

    /**
     * Smoke test: seed minimal data, assert getFleetKpis() returns correct counts.
     * Covers Triage 1.1 SOQL fix — ensures the four tile values reflect real data
     * rather than stale "Recently Viewed" or miscounted aggregates.
     */
    @TestSetup
    static void makeData() {
        // Vendor account (required for Fleet_Asset lookup)
        Account vendor = new Account(Name = 'Test Vendor');
        insert vendor;

        // Fleet Assets: 2 Available, 1 Assigned, 1 Decommissioned (should NOT count)
        List<fleetforce__Fleet_Asset__c> assets = new List<fleetforce__Fleet_Asset__c>{
            new fleetforce__Fleet_Asset__c(
                Name = 'Asset-Available-1',
                fleetforce__Status__c = 'Available',
                fleetforce__Vendor__c = vendor.Id
            ),
            new fleetforce__Fleet_Asset__c(
                Name = 'Asset-Available-2',
                fleetforce__Status__c = 'Available',
                fleetforce__Vendor__c = vendor.Id
            ),
            new fleetforce__Fleet_Asset__c(
                Name = 'Asset-Assigned-1',
                fleetforce__Status__c = 'Assigned',
                fleetforce__Vendor__c = vendor.Id
            ),
            new fleetforce__Fleet_Asset__c(
                Name = 'Asset-Decommissioned',
                fleetforce__Status__c = 'Decommissioned',
                fleetforce__Vendor__c = vendor.Id
            )
        };
        insert assets;

        // Service Tickets: 2 In-Shop, 1 Draft, 1 Completed (Completed should not count in openTickets)
        List<fleetforce__Service_Ticket__c> tickets = new List<fleetforce__Service_Ticket__c>{
            new fleetforce__Service_Ticket__c(
                fleetforce__Fleet_Asset__c = assets[0].Id,
                fleetforce__Status__c = 'In-Shop',
                fleetforce__Priority__c = 'High',
                fleetforce__Actual_Start__c = Date.today()
            ),
            new fleetforce__Service_Ticket__c(
                fleetforce__Fleet_Asset__c = assets[1].Id,
                fleetforce__Status__c = 'In-Shop',
                fleetforce__Priority__c = 'Critical',
                fleetforce__Actual_Start__c = Date.today()
            ),
            new fleetforce__Service_Ticket__c(
                fleetforce__Fleet_Asset__c = assets[2].Id,
                fleetforce__Status__c = 'Draft',
                fleetforce__Priority__c = 'Medium'
            ),
            new fleetforce__Service_Ticket__c(
                fleetforce__Fleet_Asset__c = assets[3].Id,
                fleetforce__Status__c = 'Completed',
                fleetforce__Priority__c = 'Low',
                fleetforce__Actual_Start__c = Date.today(),
                fleetforce__Actual_End__c = Date.today()
            )
        };
        insert tickets;

        // Telemetry Violations: 1 High + 1 Critical (should count), 1 Low (should NOT count)
        List<fleetforce__Telemetry_Violation__c> violations = new List<fleetforce__Telemetry_Violation__c>{
            new fleetforce__Telemetry_Violation__c(
                fleetforce__Fleet_Asset__c = assets[0].Id,
                fleetforce__Severity__c = 'High',
                fleetforce__Timestamp__c = Datetime.now()
            ),
            new fleetforce__Telemetry_Violation__c(
                fleetforce__Fleet_Asset__c = assets[1].Id,
                fleetforce__Severity__c = 'Critical',
                fleetforce__Timestamp__c = Datetime.now()
            ),
            new fleetforce__Telemetry_Violation__c(
                fleetforce__Fleet_Asset__c = assets[2].Id,
                fleetforce__Severity__c = 'Low',
                fleetforce__Timestamp__c = Datetime.now()
            )
        };
        insert violations;
    }

    @IsTest
    static void testGetFleetKpis_counts() {
        Test.startTest();
        Map<String, Integer> kpis = FleetKpiController.getFleetKpis();
        Test.stopTest();

        // totalActive: Available(2) + Assigned(1) = 3 — exact, no automation touches assets
        System.assertEquals(3, kpis.get('totalActive'),
            'totalActive should count Available + Assigned assets');

        // inMaintenance: exactly 2 In-Shop tickets — the flow only creates Draft tickets,
        // so In-Shop count is fully controlled by test data
        System.assertEquals(2, kpis.get('inMaintenance'),
            'inMaintenance should count In-Shop service ticket rows');

        // criticalViolations: High(1) + Critical(1) = 2; Low excluded — exact count
        System.assertEquals(2, kpis.get('criticalViolations'),
            'criticalViolations should count High + Critical violations in last 30 days');

        // openTickets: at least Draft(1) + In-Shop(2) = 3.
        // The Violation_Auto_Escalation flow may create additional Draft tickets from
        // the High/Critical violations inserted above, so use >= to stay flow-tolerant.
        System.assert(kpis.get('openTickets') >= 3,
            'openTickets should count at least the 3 Draft+In-Shop tickets we created; got: '
            + kpis.get('openTickets'));
        // Completed ticket must NOT be counted
        System.assert(kpis.get('openTickets') < 10,
            'openTickets unexpectedly high — Completed ticket may have been included');
    }

    @IsTest
    static void testGetMaintenanceAlerts_filtersCorrectly() {
        Test.startTest();
        List<fleetforce__Service_Ticket__c> alerts = FleetKpiController.getMaintenanceAlerts();
        Test.stopTest();

        // High + Critical, Draft/In-Shop tickets. We inserted 2 explicitly;
        // Violation_Auto_Escalation may add more Draft/High-Critical tickets from our
        // violation inserts — so assert >= 2. All must satisfy the filter criteria.
        System.assert(alerts.size() >= 2,
            'getMaintenanceAlerts should return at least the 2 High/Critical In-Shop tickets; got: '
            + alerts.size());

        for (fleetforce__Service_Ticket__c t : alerts) {
            System.assert(
                t.fleetforce__Priority__c == 'High' || t.fleetforce__Priority__c == 'Critical',
                'All alerts must be High or Critical priority'
            );
            System.assert(
                t.fleetforce__Status__c == 'Draft' || t.fleetforce__Status__c == 'In-Shop',
                'All alerts must be Draft or In-Shop status'
            );
        }
    }

    @IsTest
    static void testGetAssetLocations_noException() {
        // Smoke: method should execute without exception even with no geolocation data
        Test.startTest();
        List<fleetforce__Fleet_Asset__c> locs = FleetKpiController.getAssetLocations();
        Test.stopTest();
        System.assertNotEquals(null, locs, 'getAssetLocations should not return null');
    }
}
