@isTest
private class FleetBranchControllerTest {
  @isTest
  static void testGetBranchHighlightsComplete() {
    // Create Manager Contact
    Contact mgr = new Contact(
      FirstName = 'Elena',
      LastName = 'Reyes',
      Title = 'Branch Operations Manager',
      Email = 'elena.reyes@example.com',
      Phone = '+1-555-0100',
      MobilePhone = '+1-555-0101'
    );
    insert mgr;

    // Create a photo ContentVersion
    ContentVersion cv = new ContentVersion(
      Title = 'Manager Photo',
      PathOnClient = 'elena.png',
      VersionData = Blob.valueOf('test-photo-data')
    );
    insert cv;

    ContentVersion queriedCv = [
      SELECT Id, ContentDocumentId
      FROM ContentVersion
      WHERE Id = :cv.Id
      LIMIT 1
    ];
    mgr.fleetforce__Photo_Document_Id__c = queriedCv.ContentDocumentId;
    update mgr;

    // Create Fleet Branch
    fleetforce__Fleet_Branch__c branch = new fleetforce__Fleet_Branch__c(
      Name = 'Downtown Fleet Hub',
      fleetforce__Branch_ID__c = 'BR-DT-01',
      fleetforce__Status__c = 'Active',
      fleetforce__Type__c = 'Hub',
      fleetforce__Capacity__c = 20,
      fleetforce__Street__c = '100 Main St',
      fleetforce__City__c = 'Atlanta',
      fleetforce__US_State__c = 'GA',
      fleetforce__Zip_Code__c = '30301',
      fleetforce__Country__c = 'US',
      fleetforce__Phone__c = '+1-404-555-0199',
      fleetforce__Email__c = 'atlanta.hub@fleetforce.com',
      fleetforce__Location__Latitude__s = 33.7490,
      fleetforce__Location__Longitude__s = -84.3880,
      fleetforce__Approving_Manager__c = mgr.Id
    );
    insert branch;

    // Create Assigned Driver Contact
    Contact driver = new Contact(
      FirstName = 'Carlos',
      LastName = 'Gomez',
      Email = 'carlos.gomez@example.com',
      fleetforce__Driver_Branch__c = branch.Id,
      fleetforce__Driver_Status__c = 'Active'
    );
    insert driver;

    // Create Fleet Assets
    fleetforce__Fleet_Asset__c asset1 = new fleetforce__Fleet_Asset__c(
      Name = 'Asset 001',
      fleetforce__Branch__c = branch.Id,
      fleetforce__Status__c = 'Available',
      fleetforce__Is_Active__c = true
    );
    fleetforce__Fleet_Asset__c asset2 = new fleetforce__Fleet_Asset__c(
      Name = 'Asset 002',
      fleetforce__Branch__c = branch.Id,
      fleetforce__Status__c = 'Assigned',
      fleetforce__Is_Active__c = true
    );
    insert new List<fleetforce__Fleet_Asset__c>{ asset1, asset2 };

    // Create Service Ticket on Asset 1 (In Shop)
    fleetforce__Service_Ticket__c ticket = new fleetforce__Service_Ticket__c(
      fleetforce__Fleet_Asset__c = asset1.Id,
      fleetforce__Actual_Start__c = Date.today().addDays(-1),
      fleetforce__Status__c = 'In-Shop'
    );
    insert ticket;

    // Create Route Plan
    fleetforce__Route_Plan__c plan = new fleetforce__Route_Plan__c(
      Name = 'Morning Atlanta Dispatch',
      fleetforce__Depot_Branch__c = branch.Id,
      fleetforce__Status__c = 'Optimized'
    );
    insert plan;

    Test.startTest();
    FleetBranchController.BranchHighlightsDTO dto = FleetBranchController.getBranchHighlights(
      branch.Id
    );
    Test.stopTest();

    System.assertNotEquals(null, dto, 'DTO should not be null');
    System.assertEquals(branch.Id, dto.branchId);
    System.assertEquals('Downtown Fleet Hub', dto.name);
    System.assertEquals('BR-DT-01', dto.branchCode);
    System.assertEquals('Active', dto.status);
    System.assertEquals('Hub', dto.locationType);
    System.assertEquals(20, dto.capacity);
    System.assertEquals(33.7490, dto.latitude);
    System.assertEquals(-84.3880, dto.longitude);
    System.assert(
      dto.fullAddress.contains('100 Main St'),
      'Address should include street'
    );
    System.assert(
      dto.googleMapsUrl.contains('33.749'),
      'Maps URL should contain coordinates'
    );

    // Manager asserts
    System.assertNotEquals(
      null,
      dto.manager,
      'Manager info should be populated'
    );
    System.assertEquals('Elena Reyes', dto.manager.name);
    System.assertEquals('ER', dto.manager.initials);
    System.assertEquals('Branch Operations Manager', dto.manager.title);
    System.assert(
      dto.manager.photoUrl != null &&
      dto.manager.photoUrl.contains(queriedCv.Id),
      'Photo URL should point to version'
    );

    // Metrics asserts
    System.assertEquals(2, dto.totalVehicles);
    System.assertEquals(2, dto.activeVehicles);
    System.assertEquals(1, dto.inShopVehicles);
    System.assertEquals(1, dto.assignedDrivers);
    System.assertEquals(1, dto.activeRoutePlans);
    System.assertEquals(1, dto.openServiceTickets);
    System.assertEquals(10.0, dto.capacityUtilizationPct);
    System.assertEquals('optimal', dto.capacityStatus);
  }

  @isTest
  static void testGetBranchHighlightsFallbacksAndCapacityAlert() {
    // Create Branch without manager and high utilization
    fleetforce__Fleet_Branch__c branch = new fleetforce__Fleet_Branch__c(
      Name = 'Overflow Yard',
      fleetforce__Branch_ID__c = 'BR-OF-99',
      fleetforce__Status__c = 'Active',
      fleetforce__Capacity__c = 1,
      fleetforce__Street__c = '99 Depot Rd',
      fleetforce__City__c = 'Chicago',
      fleetforce__US_State__c = 'IL'
    );
    insert branch;

    fleetforce__Fleet_Asset__c asset = new fleetforce__Fleet_Asset__c(
      Name = 'Asset 999',
      fleetforce__Branch__c = branch.Id,
      fleetforce__Status__c = 'Available',
      fleetforce__Is_Active__c = true
    );
    insert asset;

    Test.startTest();
    FleetBranchController.BranchHighlightsDTO dto = FleetBranchController.getBranchHighlights(
      branch.Id
    );
    Test.stopTest();

    System.assertNotEquals(null, dto);
    System.assertEquals(null, dto.manager, 'Manager should be null');
    System.assertEquals(100.0, dto.capacityUtilizationPct);
    System.assertEquals(
      'critical',
      dto.capacityStatus,
      'Capacity should be critical at 100%'
    );
    System.assert(
      dto.googleMapsUrl.contains('Chicago'),
      'Fallback map URL should use address query'
    );
  }

  @isTest
  static void testNullAndMissingBranch() {
    Test.startTest();
    FleetBranchController.BranchHighlightsDTO dtoNull = FleetBranchController.getBranchHighlights(
      null
    );
    FleetBranchController.BranchHighlightsDTO dtoFake = FleetBranchController.getBranchHighlights(
      'a0KWm0000000000MAA'
    );
    Test.stopTest();

    System.assertEquals(null, dtoNull);
    System.assertEquals(null, dtoFake);
  }

  @isTest
  static void testWarningCapacityAndManagerFallbacks() {
    // Manager with only Name or Primary Contact fallback
    Contact primary = new Contact(
      LastName = 'SingleName',
      Email = 'single@example.com'
    );
    insert primary;

    fleetforce__Fleet_Branch__c branch = new fleetforce__Fleet_Branch__c(
      Name = 'Warning Depot',
      fleetforce__Capacity__c = 10,
      fleetforce__Primary_Contact__c = primary.Id
    );
    insert branch;

    List<fleetforce__Fleet_Asset__c> assets = new List<fleetforce__Fleet_Asset__c>();
    for (Integer i = 0; i < 8; i++) {
      assets.add(
        new fleetforce__Fleet_Asset__c(
          Name = 'Asset ' + i,
          fleetforce__Branch__c = branch.Id,
          fleetforce__Status__c = 'Available'
        )
      );
    }
    insert assets;

    Test.startTest();
    FleetBranchController.BranchHighlightsDTO dto = FleetBranchController.getBranchHighlights(
      branch.Id
    );
    Test.stopTest();

    System.assertNotEquals(null, dto);
    System.assertEquals('warning', dto.capacityStatus);
    System.assertEquals(80.0, dto.capacityUtilizationPct);
    System.assertNotEquals(null, dto.manager);
  }
}
