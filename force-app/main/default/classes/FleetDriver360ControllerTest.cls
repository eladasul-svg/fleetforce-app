@isTest
private class FleetDriver360ControllerTest {
  @TestSetup
  static void setupTestData() {
    // 1. Create Branch
    fleetforce__Fleet_Branch__c branch = new fleetforce__Fleet_Branch__c(
      Name = 'Downtown Depot',
      fleetforce__Branch_ID__c = 'DWTN-01',
      fleetforce__Status__c = 'Active'
    );
    insert branch;

    // 2. Create Driver Contact
    Contact driver = new Contact(
      FirstName = 'Lucas',
      LastName = 'Vance',
      fleetforce__Contact_Type__c = 'Driver',
      fleetforce__Driver_Status__c = 'Active',
      fleetforce__Safety_Score__c = 88,
      fleetforce__License_Number__c = 'DL-889922',
      fleetforce__License_Class__c = 'Class A CDL',
      fleetforce__License_State__c = 'CA',
      fleetforce__License_Expiry__c = Date.today().addDays(45),
      fleetforce__Medical_Cert__c = Date.today().addDays(120),
      fleetforce__Driver_Branch__c = branch.Id,
      Email = 'lucas.vance@fleetforce.com',
      Phone = '555-019-2834',
      MobilePhone = '555-019-2835'
    );
    insert driver;

    // 3. Create Vehicle Asset
    fleetforce__Fleet_Asset__c asset = new fleetforce__Fleet_Asset__c(
      Name = 'VAN-104',
      fleetforce__Make__c = 'Ford',
      fleetforce__Model__c = 'Transit 350',
      fleetforce__Model_Year__c = '2024',
      fleetforce__License_Plate__c = '7XYZ999',
      fleetforce__VIN__c = '1FTNE3Y89RKA99999',
      fleetforce__Status__c = 'Available',
      fleetforce__Vehicle_Class__c = 'Compact',
      fleetforce__Key_Tag_ID__c = 'KEY-8841',
      fleetforce__Fuel_Energy_Level__c = 82,
      fleetforce__Fuel_Type__c = 'Gasoline',
      fleetforce__Odometer__c = 15400,
      fleetforce__Is_Active__c = true
    );
    insert asset;

    // 4. Create Authorized Driver
    fleetforce__Authorized_Driver__c ad = new fleetforce__Authorized_Driver__c(
      fleetforce__Driver__c = driver.Id,
      fleetforce__Fleet_Asset__c = asset.Id,
      fleetforce__Type__c = 'Primary',
      fleetforce__Has_Key__c = true,
      fleetforce__Is_Active__c = true,
      fleetforce__Start_Date__c = Date.today().addMonths(-2)
    );
    insert ad;

    // 5. Create Trips
    fleetforce__Trip__c tripBiz = new fleetforce__Trip__c(
      fleetforce__Driver__c = driver.Id,
      fleetforce__Fleet_Asset__c = asset.Id,
      fleetforce__Trip_Type__c = 'Business',
      fleetforce__Business_Purpose__c = 'Client Hardware Dropoff',
      fleetforce__Start_Time__c = Datetime.now().addDays(-2).addHours(-3),
      fleetforce__End_Time__c = Datetime.now().addDays(-2),
      fleetforce__Distance__c = 42.5,
      fleetforce__Distance_Unit__c = 'mi',
      fleetforce__Approval_Status__c = 'Approved'
    );
    fleetforce__Trip__c tripPriv = new fleetforce__Trip__c(
      fleetforce__Driver__c = driver.Id,
      fleetforce__Fleet_Asset__c = asset.Id,
      fleetforce__Trip_Type__c = 'Private',
      fleetforce__Start_Time__c = Datetime.now().addDays(-1).addHours(-1),
      fleetforce__End_Time__c = Datetime.now().addDays(-1),
      fleetforce__Distance__c = 12.0,
      fleetforce__Distance_Unit__c = 'mi',
      fleetforce__Approval_Status__c = 'Submitted'
    );
    insert new List<fleetforce__Trip__c>{ tripBiz, tripPriv };

    // 6. Create Telemetry Violations
    fleetforce__Telemetry_Violation__c tv1 = new fleetforce__Telemetry_Violation__c(
      fleetforce__Driver__c = driver.Id,
      fleetforce__Fleet_Asset__c = asset.Id,
      fleetforce__Type__c = 'Harsh Braking',
      fleetforce__Severity__c = 'High',
      fleetforce__Timestamp__c = Datetime.now().addDays(-3)
    );
    fleetforce__Telemetry_Violation__c tv2 = new fleetforce__Telemetry_Violation__c(
      fleetforce__Driver__c = driver.Id,
      fleetforce__Fleet_Asset__c = asset.Id,
      fleetforce__Type__c = 'Speeding',
      fleetforce__Severity__c = 'Medium',
      fleetforce__Timestamp__c = Datetime.now().addDays(-1)
    );
    insert new List<fleetforce__Telemetry_Violation__c>{ tv1, tv2 };

    // 7. Create Citation
    fleetforce__Citation__c cit = new fleetforce__Citation__c(
      fleetforce__Driver__c = driver.Id,
      fleetforce__Fleet_Asset__c = asset.Id,
      fleetforce__Citation_Date__c = Date.today().addDays(-10),
      fleetforce__Ticket_Number__c = 'CIT-9921',
      fleetforce__Violation_Type__c = 'Speeding',
      fleetforce__Fine_Amount__c = 150.00,
      fleetforce__Issuing_Authority__c = 'Highway Patrol',
      fleetforce__Status__c = 'New'
    );
    insert cit;
  }

  @isTest
  static void testGetDriver360DataSuccess() {
    Contact driver = [SELECT Id FROM Contact WHERE LastName = 'Vance' LIMIT 1];

    Test.startTest();
    FleetDriver360Controller.Driver360Data data = FleetDriver360Controller.getDriver360Data(
      driver.Id
    );
    Test.stopTest();

    System.assertNotEquals(null, data, 'Driver 360 data should not be null');
    System.assertEquals('Lucas Vance', data.summary.name);
    System.assertEquals('Driver', data.summary.contactType);
    System.assertEquals(88, data.summary.safetyScore);
    System.assertEquals('Excellent', data.summary.safetyRating);
    System.assertEquals('Expiring Soon', data.summary.licenseExpiryStatus);
    System.assertEquals('Valid', data.summary.medicalExpiryStatus);
    System.assertEquals(2, data.summary.totalTrips);

    // Active Vehicle
    System.assertEquals(true, data.activeVehicle.hasVehicle);
    System.assertEquals('Ford', data.activeVehicle.make);
    System.assertEquals('Transit 350', data.activeVehicle.model);
    System.assertEquals('Primary', data.activeVehicle.authorizationLevel);
    System.assertEquals(true, data.activeVehicle.hasKey);

    // Mileage split
    System.assertNotEquals(null, data.mileageSplit);
    System.assertEquals(54.5, data.mileageSplit.totalMileage);
    System.assertEquals(42.5, data.mileageSplit.businessMileage);
    System.assertEquals(12.0, data.mileageSplit.privateMileage);
    System.assert(data.mileageSplit.businessPct > 0);

    // Telematics
    System.assertNotEquals(null, data.telematics);
    System.assertEquals(1, data.telematics.harshBrakingCount);
    System.assertEquals(1, data.telematics.speedingCount);
    System.assertEquals(2, data.telematics.totalViolations);
    System.assertEquals('Low Risk', data.telematics.riskLevel);

    // Citations
    System.assertEquals(1, data.citations.count);
    System.assertEquals(150.00, data.citations.totalFine);
  }

  @isTest
  static void testNullDriverReturnsNull() {
    Test.startTest();
    FleetDriver360Controller.Driver360Data data = FleetDriver360Controller.getDriver360Data(
      null
    );
    Test.stopTest();
    System.assertEquals(null, data);
  }

  @isTest
  static void testAvailableVehicles() {
    Test.startTest();
    List<FleetDriver360Controller.VehicleOption> listOptions = FleetDriver360Controller.getAvailableVehicles();
    Test.stopTest();
    System.assert(
      !listOptions.isEmpty(),
      'Available vehicles should not be empty'
    );
  }

  @isTest
  static void testToggleKeyAccess() {
    fleetforce__Authorized_Driver__c ad = [
      SELECT Id, fleetforce__Has_Key__c
      FROM fleetforce__Authorized_Driver__c
      LIMIT 1
    ];
    System.assertEquals(true, ad.fleetforce__Has_Key__c);

    Test.startTest();
    FleetDriver360Controller.toggleKeyAccess(ad.Id, false);
    Test.stopTest();

    fleetforce__Authorized_Driver__c updatedAd = [
      SELECT fleetforce__Has_Key__c
      FROM fleetforce__Authorized_Driver__c
      WHERE Id = :ad.Id
    ];
    System.assertEquals(false, updatedAd.fleetforce__Has_Key__c);
  }

  @isTest
  static void testAssignVehicle() {
    Contact driver = [SELECT Id FROM Contact WHERE LastName = 'Vance' LIMIT 1];
    fleetforce__Fleet_Asset__c newAsset = new fleetforce__Fleet_Asset__c(
      Name = 'SUV-205',
      fleetforce__Make__c = 'Chevrolet',
      fleetforce__Model__c = 'Tahoe',
      fleetforce__Is_Active__c = true
    );
    insert newAsset;

    Test.startTest();
    Id authId = FleetDriver360Controller.assignVehicle(
      driver.Id,
      newAsset.Id,
      'Secondary',
      true
    );
    Test.stopTest();

    System.assertNotEquals(null, authId);
    fleetforce__Authorized_Driver__c ad = [
      SELECT fleetforce__Type__c, fleetforce__Has_Key__c
      FROM fleetforce__Authorized_Driver__c
      WHERE Id = :authId
    ];
    System.assertEquals('Secondary', ad.fleetforce__Type__c);
    System.assertEquals(true, ad.fleetforce__Has_Key__c);
  }

  @isTest
  static void testQuickActions() {
    Contact driver = [SELECT Id FROM Contact WHERE LastName = 'Vance' LIMIT 1];
    fleetforce__Fleet_Asset__c asset = [
      SELECT Id
      FROM fleetforce__Fleet_Asset__c
      LIMIT 1
    ];

    Test.startTest();
    // 1. Quick Log Trip
    Id tripId = FleetDriver360Controller.quickLogTrip(
      driver.Id,
      asset.Id,
      'Business',
      'Branch audit run',
      Datetime.now().addHours(-2),
      Datetime.now(),
      18.5,
      'mi',
      15400,
      15418.5,
      'Depot A',
      'Branch B'
    );
    System.assertNotEquals(null, tripId);

    // 2. Quick Log Fuel
    Id fuelId = FleetDriver360Controller.quickLogFuel(
      driver.Id,
      asset.Id,
      Date.today(),
      14.2,
      52.50,
      15418.5,
      'Diesel'
    );
    System.assertNotEquals(null, fuelId);

    // 3. Quick Report Citation
    Id citId = FleetDriver360Controller.quickReportCitation(
      driver.Id,
      asset.Id,
      Date.today(),
      'TKT-10023',
      'Parking',
      75.00,
      'City Parking Auth'
    );
    System.assertNotEquals(null, citId);
    Test.stopTest();
  }
}
