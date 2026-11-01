@IsTest
private class FleetDriverControllerTest {
  @TestSetup
  static void makeData() {
    fleetforce__Fleet_Branch__c branch = new fleetforce__Fleet_Branch__c(
      Name = 'London Hub'
    );
    insert branch;
    Contact driver = new Contact(
      FirstName = 'Maya',
      LastName = 'Patel',
      Title = 'Delivery Courier',
      MobilePhone = '+44 7700 900302',
      Email = 'maya.patel@example.com',
      fleetforce__Driver_Branch__c = branch.Id,
      fleetforce__Driver_Status__c = 'Active',
      fleetforce__License_Number__c = 'PATEL905153MA9',
      fleetforce__License_Expiry__c = Date.today().addYears(2),
      fleetforce__Safety_Score__c = 92
    );
    insert driver;
    insert new List<fleetforce__Driver_Qualification__c>{
      new fleetforce__Driver_Qualification__c(
        Name = 'Forklift',
        fleetforce__Driver__c = driver.Id,
        fleetforce__Status__c = 'Expired'
      ),
      new fleetforce__Driver_Qualification__c(
        Name = 'First aid',
        fleetforce__Driver__c = driver.Id,
        fleetforce__Status__c = 'Expiring Soon'
      ),
      new fleetforce__Driver_Qualification__c(
        Name = 'Hazmat',
        fleetforce__Driver__c = driver.Id,
        fleetforce__Status__c = 'Expiring Soon'
      ),
      new fleetforce__Driver_Qualification__c(
        Name = 'Defensive driving',
        fleetforce__Driver__c = driver.Id,
        fleetforce__Status__c = 'Valid'
      )
    };

    // FleetAdmin grants FLS on Contact's driver fields; USER_MODE queries need the call itself to run inside a
    // fresh System.runAs(self) block (same pattern as FleetVehicleControllerTest).
    Id userId = UserInfo.getUserId();
    PermissionSet ps = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'FleetAdmin'
      LIMIT 1
    ];
    if (
      [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE AssigneeId = :userId AND PermissionSetId = :ps.Id
      ] == 0
    ) {
      System.runAs(new User(Id = userId)) {
        insert new PermissionSetAssignment(
          AssigneeId = userId,
          PermissionSetId = ps.Id
        );
      }
    }
  }

  @IsTest
  static void cardHasDriverBranchLicenseAndWarnings() {
    Contact driver = [SELECT Id FROM Contact WHERE LastName = 'Patel' LIMIT 1];
    FleetDriverController.DriverCard d;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      d = FleetDriverController.getDriverCard(driver.Id);
    }
    System.assertEquals('Maya Patel', d.name);
    System.assertEquals('MP', d.initials);
    System.assertEquals('London Hub', d.branchName);
    System.assertEquals('+44 7700 900302', d.mobile);
    System.assertEquals('PATEL905153MA9', d.licenseNumber);
    System.assertEquals(92, d.safetyScore);
    System.assertEquals(null, d.photoUrl, 'no related user, so initials');
    System.assertEquals(1, d.qualificationsExpired);
    System.assertEquals(2, d.qualificationsExpiringSoon);
  }

  @IsTest
  static void noDriverGivesNoCard() {
    System.assertEquals(null, FleetDriverController.getDriverCard(null));
  }

  @IsTest
  static void defaultSilhouetteIsNotAPhoto() {
    System.assertEquals(
      null,
      FleetDriverController.photoUrl(
        'https://x.my.salesforce.com/profilephoto/005/M'
      )
    );
    System.assertEquals(
      'https://x.file.force.com/profilephoto/729xx/M',
      FleetDriverController.photoUrl(
        'https://x.file.force.com/profilephoto/729xx/M'
      )
    );
    System.assertEquals('J', FleetDriverController.initials('jo', null));
  }
}
