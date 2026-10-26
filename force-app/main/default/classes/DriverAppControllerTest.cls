@IsTest
private class DriverAppControllerTest {

    @TestSetup
    static void makeData() {
        Contact driver = new Contact(
            FirstName = 'Dana', LastName = 'Driver', Email = 'dana@example.com',
            fleetforce__Contact_Type__c = 'Driver', fleetforce__Driver_Status__c = 'Active',
            fleetforce__License_Expiry__c = Date.today().addDays(20),        // expiring soon -> notice
            fleetforce__Medical_Cert__c = Date.today().addDays(300),
            fleetforce__Safety_Score__c = 91
        );
        insert driver;
        Contact idle = new Contact(LastName = 'NoCar', fleetforce__Contact_Type__c = 'Driver', fleetforce__Driver_Status__c = 'Active');
        insert idle;

        fleetforce__Fleet_Asset__c car = new fleetforce__Fleet_Asset__c(
            Name = '2023 Chevrolet Malibu LT', fleetforce__License_Plate__c = 'DRV-001', fleetforce__Body_Type__c = 'Sedan',
            fleetforce__Fuel_Type__c = 'Gasoline', fleetforce__Status__c = 'Assigned', fleetforce__Is_Active__c = true,
            fleetforce__Driver__c = driver.Id, fleetforce__Odometer__c = 10000, fleetforce__Fuel_Energy_Level__c = 60,
            fleetforce__Last_Location__Latitude__s = 38.72, fleetforce__Last_Location__Longitude__s = -9.14
        );
        insert car;
        insert new fleetforce__Authorized_Driver__c(fleetforce__Driver__c = driver.Id, fleetforce__Fleet_Asset__c = car.Id,
            fleetforce__Is_Active__c = true, fleetforce__Type__c = 'Primary');
        insert new fleetforce__Asset_Document__c(fleetforce__Fleet_Asset__c = car.Id, fleetforce__Doc_Type__c = 'Registration',
            fleetforce__Valid_Until__c = Date.today().addDays(10), fleetforce__Status__c = 'Expiring Soon');
        insert new fleetforce__Citation__c(fleetforce__Fleet_Asset__c = car.Id, fleetforce__Driver__c = driver.Id,
            fleetforce__Ticket_Number__c = 'T-1', fleetforce__Violation_Type__c = 'Speeding', fleetforce__Status__c = 'New',
            fleetforce__Fine_Amount__c = 120, fleetforce__Citation_Date__c = Datetime.now().addDays(-2));
        insert new fleetforce__Telemetry_Violation__c(fleetforce__Fleet_Asset__c = car.Id, fleetforce__Driver__c = driver.Id,
            fleetforce__Type__c = 'Harsh Braking', fleetforce__Severity__c = 'Low', fleetforce__Timestamp__c = Datetime.now().addDays(-1));
        insert new fleetforce__Driver_Qualification__c(fleetforce__Driver__c = driver.Id, fleetforce__Type__c = 'Certification',
            fleetforce__Authority__c = 'DMV', fleetforce__Valid_Until__c = Date.today().addDays(200), fleetforce__Is_Mandatory__c = true);
        insert new fleetforce__Fuel_Card__c(fleetforce__Assigned_Driver__c = driver.Id, fleetforce__Provider__c = 'FleetCor',
            fleetforce__Full_Card_Number__c = '7001000012345678', fleetforce__Status__c = 'Active');
        insert new fleetforce__Reservation__c(fleetforce__Requestor_Contact__c = driver.Id, fleetforce__Assigned_Asset__c = car.Id,
            fleetforce__Start_Time__c = Datetime.now().addDays(1), fleetforce__End_Time__c = Datetime.now().addDays(2),
            fleetforce__Status__c = 'Approved');
        insert new fleetforce__Service_Ticket__c(fleetforce__Fleet_Asset__c = car.Id, fleetforce__Status__c = 'Draft',
            fleetforce__Priority__c = 'High', fleetforce__Summary__c = 'Brake noise', fleetforce__Date_Reported__c = Datetime.now());
    }

    private static Contact dana() {
        return [SELECT Id FROM Contact WHERE LastName = 'Driver' LIMIT 1];
    }

    private static fleetforce__Fleet_Asset__c car() {
        return [SELECT Id FROM fleetforce__Fleet_Asset__c LIMIT 1];
    }

    @IsTest
    static void driversWithAVehicleComeFirst() {
        List<DriverAppController.DriverOption> opts = DriverAppController.getDrivers();
        System.assertEquals(2, opts.size());
        System.assertEquals('Dana Driver', opts[0].name);
        System.assertEquals('2023 Chevrolet Malibu LT', opts[0].vehicle);
        System.assertEquals(null, opts[1].vehicle);
    }

    @IsTest
    static void dashboardAssemblesEverythingForTheDriver() {
        DriverAppController.Dashboard d = DriverAppController.getDashboard(dana().Id);
        System.assertEquals('Dana', d.driver.firstName);
        System.assertEquals(20, d.driver.licenseDaysLeft);
        System.assertEquals('DRV-001', d.vehicle.plate);
        System.assertEquals('Primary', d.vehicle.authorizationType);
        System.assertEquals(30, d.vehicle.mpgCombined, 'Malibu has EPA figures');
        System.assertEquals(null, d.openTrip);
        System.assertEquals(1, d.reservations.size());
        System.assertEquals(1, d.tickets.size());
        System.assertEquals(1, d.documents.size());
        System.assertEquals(1, d.citations.size());
        System.assertEquals(1, d.violations.size());
        System.assertEquals(1, d.qualifications.size());
        System.assertEquals(1, d.authorized.size());
        System.assertEquals(true, d.authorized[0].isCurrent);
        System.assertEquals('5678', d.fuelCard.lastDigits);
        // license expiring, registration expiring, new citation, recent violation, upcoming booking
        Set<String> kinds = new Set<String>();
        for (DriverAppController.Notice n : d.notices) {
            kinds.add(n.kind);
        }
        System.assert(kinds.containsAll(new Set<String>{ 'license', 'document', 'citation', 'violation', 'reservation' }), String.valueOf(kinds));
        System.assertEquals('bad', d.notices[0].level, 'most urgent first');
    }

    @IsTest
    static void driverWithoutAVehicleStillLoads() {
        DriverAppController.Dashboard d = DriverAppController.getDashboard([SELECT Id FROM Contact WHERE LastName = 'NoCar'].Id);
        System.assertEquals(null, d.vehicle);
        System.assertEquals(0, d.tickets.size());
    }

    @IsTest
    static void tripLifecycleRecordsOdometerFuelAndDamage() {
        Id tripId = DriverAppController.startTrip(dana().Id, car().Id, 10050, 55, 'Scratch on the rear bumper', true);
        DriverAppController.Dashboard d = DriverAppController.getDashboard(dana().Id);
        System.assertNotEquals(null, d.openTrip, 'the trip is now open');
        System.assertEquals(10050, d.openTrip.odometerStart);
        System.assertEquals(2, [SELECT COUNT() FROM fleetforce__Service_Ticket__c WHERE fleetforce__Fleet_Asset__c = :car().Id],
            'new damage raises a ticket');

        DriverAppController.endTrip(tripId, 10120, 40, 'All fine', false);
        fleetforce__Allocation__c done = [SELECT fleetforce__Status__c, fleetforce__Distance_Driven__c, fleetforce__Has_New_Damage__c
                                          FROM fleetforce__Allocation__c WHERE Id = :tripId];
        System.assertEquals('Completed', done.fleetforce__Status__c);
        System.assertEquals(70, done.fleetforce__Distance_Driven__c);
        System.assertEquals(true, done.fleetforce__Has_New_Damage__c, 'damage found at the start stays on the trip');
        System.assertEquals(10120, [SELECT fleetforce__Odometer__c FROM fleetforce__Fleet_Asset__c WHERE Id = :car().Id].fleetforce__Odometer__c);
        System.assertEquals(null, DriverAppController.getDashboard(dana().Id).openTrip);
        System.assertEquals(1, DriverAppController.getDashboard(dana().Id).recentTrips.size());
    }

    @IsTest
    static void reportIssueCreatesATicketReportedByTheDriver() {
        Id ticketId = DriverAppController.reportIssue(dana().Id, car().Id, 'Corrective Repair', 'High', 'Warning light on the dashboard');
        fleetforce__Service_Ticket__c t = [SELECT fleetforce__Reported_By__c, fleetforce__Priority__c, fleetforce__Status__c
                                           FROM fleetforce__Service_Ticket__c WHERE Id = :ticketId];
        System.assertEquals(dana().Id, t.fleetforce__Reported_By__c);
        System.assertEquals('High', t.fleetforce__Priority__c);
        try {
            DriverAppController.reportIssue(dana().Id, car().Id, null, null, '');
            System.assert(false, 'an empty report is refused');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void fuelEntriesAreLoggedAgainstTheCard() {
        DriverAppController.logFuel(dana().Id, car().Id, 10, 'Gallons (US)', 42.5, 10200, true, 'Galp');
        fleetforce__Fuel_Log__c l = [SELECT fleetforce__Volume__c, fleetforce__Total_Cost__c, fleetforce__Fuel_Card__c, fleetforce__Unit_Cost__c
                                     FROM fleetforce__Fuel_Log__c];
        System.assertEquals(10, l.fleetforce__Volume__c);
        System.assertEquals(4.25, l.fleetforce__Unit_Cost__c);
        System.assertNotEquals(null, l.fleetforce__Fuel_Card__c);
        try {
            DriverAppController.logFuel(dana().Id, car().Id, 0, null, null, null, false, null);
            System.assert(false, 'zero volume is refused');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void photosAttachToTheRecord() {
        Id tripId = DriverAppController.startTrip(dana().Id, car().Id, 10050, 55, null, false);
        Id cv = DriverAppController.attachPhoto(tripId, 'bumper', EncodingUtil.base64Encode(Blob.valueOf('not really a jpeg')));
        System.assertNotEquals(null, cv);
        System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :tripId]);
    }
}
