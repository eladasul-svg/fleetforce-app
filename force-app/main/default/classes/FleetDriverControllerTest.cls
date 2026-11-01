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

  private static Id addFile(Id contactId, String title, String ext) {
    ContentVersion v = new ContentVersion(
      Title = title,
      PathOnClient = title + '.' + ext,
      VersionData = Blob.valueOf('not really an image'),
      FirstPublishLocationId = contactId
    );
    insert v;
    return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :v.Id]
    .ContentDocumentId;
  }

  @IsTest
  static void photoIsChosenFromTheDriversImageFiles() {
    Contact driver = [SELECT Id FROM Contact WHERE LastName = 'Patel' LIMIT 1];
    Id photo = addFile(driver.Id, 'Maya', 'jpg');
    addFile(driver.Id, 'Licence scan', 'pdf');

    List<FleetDriverController.DriverPhoto> photos;
    FleetDriverController.DriverCard d;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      photos = FleetDriverController.getDriverPhotos(driver.Id);
      FleetDriverController.setDriverPhoto(driver.Id, photo);
      d = FleetDriverController.getDriverCard(driver.Id);
    }
    System.assertEquals(1, photos.size(), 'only images are offered');
    System.assertEquals(photo, photos[0].documentId);
    System.assertEquals(photo, d.photoDocumentId);
    System.assert(
      d.photoUrl.startsWith('/sfc/servlet.shepherd/version/download/068'),
      d.photoUrl
    );
    System.assertEquals(true, d.canEditPhoto);

    System.runAs(new User(Id = UserInfo.getUserId())) {
      FleetDriverController.setDriverPhoto(driver.Id, null);
      d = FleetDriverController.getDriverCard(driver.Id);
    }
    System.assertEquals(null, d.photoUrl, 'removed: back to initials');
    System.assertEquals(
      1,
      [SELECT COUNT() FROM ContentDocument WHERE Id = :photo],
      'the file stays'
    );
  }

  @IsTest
  static void onlyTheDriversOwnImagesCanBeTheirPhoto() {
    Contact driver = [SELECT Id FROM Contact WHERE LastName = 'Patel' LIMIT 1];
    Contact other = new Contact(LastName = 'Other');
    insert other;
    Id otherPhoto = addFile(other.Id, 'Someone else', 'png');
    Id pdf = addFile(driver.Id, 'Licence scan', 'pdf');

    for (Id doc : new List<Id>{ otherPhoto, pdf }) {
      Boolean failed = false;
      System.runAs(new User(Id = UserInfo.getUserId())) {
        try {
          FleetDriverController.setDriverPhoto(driver.Id, doc);
        } catch (AuraHandledException e) {
          failed = true;
        }
      }
      System.assert(failed, 'rejected: ' + doc);
    }
    System.assertEquals(
      null,
      [
        SELECT fleetforce__Photo_Document_Id__c
        FROM Contact
        WHERE Id = :driver.Id
      ]
      .fleetforce__Photo_Document_Id__c
    );
  }
}
