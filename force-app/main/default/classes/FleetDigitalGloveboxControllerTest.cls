@IsTest
private class FleetDigitalGloveboxControllerTest {
  @TestSetup
  static void setupTestData() {
    fleetforce__Fleet_Branch__c branch = new fleetforce__Fleet_Branch__c(
      Name = 'Atlanta Metro Hub',
      fleetforce__Country__c = 'US',
      fleetforce__Time_Zone__c = 'America/New_York'
    );
    insert branch;

    fleetforce__Fleet_Asset__c asset = new fleetforce__Fleet_Asset__c(
      Name = '2025 Ford F-150 · NH73CXK',
      fleetforce__VIN__c = '1FTFW1ED8NFC12345',
      fleetforce__Make__c = 'Ford',
      fleetforce__Model__c = 'F-150',
      fleetforce__Model_Year__c = '2025',
      fleetforce__Body_Type__c = 'Truck',
      fleetforce__Fuel_Type__c = 'Gasoline',
      fleetforce__Odometer__c = 15200,
      fleetforce__Branch__c = branch.Id,
      fleetforce__Status__c = 'Available'
    );
    insert asset;

    // Insert Asset Documents
    Date today = Date.today();
    List<fleetforce__Asset_Document__c> docs = new List<fleetforce__Asset_Document__c>{
      new fleetforce__Asset_Document__c(
        fleetforce__Fleet_Asset__c = asset.Id,
        fleetforce__Doc_Type__c = 'Registration',
        fleetforce__Doc_Number__c = 'REG-GA-2025-01',
        fleetforce__Valid_From__c = today.addMonths(-6),
        fleetforce__Valid_Until__c = today.addMonths(6),
        fleetforce__Doc_Link__c = 'https://example.com/reg.pdf',
        fleetforce__Is_Required__c = true
      ),
      new fleetforce__Asset_Document__c(
        fleetforce__Fleet_Asset__c = asset.Id,
        fleetforce__Doc_Type__c = 'Insurance Card',
        fleetforce__Doc_Number__c = 'INS-POLICY-999',
        fleetforce__Valid_From__c = today.addMonths(-11),
        fleetforce__Valid_Until__c = today.addDays(15),
        fleetforce__Doc_Link__c = 'https://example.com/ins.pdf',
        fleetforce__Is_Required__c = true
      ),
      new fleetforce__Asset_Document__c(
        fleetforce__Fleet_Asset__c = asset.Id,
        fleetforce__Doc_Type__c = 'Inspection Report',
        fleetforce__Doc_Number__c = 'DOT-INSP-2024',
        fleetforce__Valid_From__c = today.addMonths(-13),
        fleetforce__Valid_Until__c = today.addDays(-5),
        fleetforce__Doc_Link__c = null,
        fleetforce__Is_Required__c = false
      )
    };
    insert docs;

    // Attach ContentVersion to the first document
    ContentVersion cv = new ContentVersion(
      Title = 'Registration_Certificate',
      PathOnClient = 'Registration_Certificate.pdf',
      VersionData = Blob.valueOf('Fake PDF Content'),
      IsMajorVersion = true
    );
    insert cv;

    Id contentDocId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :cv.Id
    ]
    .ContentDocumentId;
    ContentDocumentLink cdl = new ContentDocumentLink(
      LinkedEntityId = docs[0].Id,
      ContentDocumentId = contentDocId,
      ShareType = 'V'
    );
    insert cdl;

    // Insert Maintenance Plan
    fleetforce__Maintenance_Plan__c plan = new fleetforce__Maintenance_Plan__c(
      Name = 'PM-002: 10,000-Mile Commercial Tire Rotation',
      fleetforce__Asset_Type__c = 'Truck',
      fleetforce__Frequency_Type__c = 'Mileage-Based',
      fleetforce__Interval_Value__c = 10000,
      fleetforce__Calendar_Interval_Months__c = 6,
      fleetforce__SOP_Checklist__c = '1. Inspect tread depth\n2. Rotate diagonally\n3. Torq lug nuts to 150 lb-ft',
      fleetforce__Warning_Miles__c = 1000
    );
    insert plan;

    // Insert Service Ticket
    fleetforce__Service_Ticket__c ticket = new fleetforce__Service_Ticket__c(
      fleetforce__Fleet_Asset__c = asset.Id,
      fleetforce__Category__c = 'Preventive Maintenance',
      fleetforce__Status__c = 'Draft',
      fleetforce__Summary__c = 'Scheduled 15,000-Mile Tire Rotation',
      fleetforce__Priority__c = 'Medium',
      fleetforce__Maintenance_Plan__c = plan.Id,
      fleetforce__Due_Date__c = today.addDays(7),
      fleetforce__Fixed_Cost__c = 120.00
    );
    insert ticket;
  }

  @IsTest
  static void testGetGloveboxData() {
    fleetforce__Fleet_Asset__c asset = [
      SELECT Id
      FROM fleetforce__Fleet_Asset__c
      LIMIT 1
    ];

    Test.startTest();
    FleetDigitalGloveboxController.GloveboxPayload payload = FleetDigitalGloveboxController.getGloveboxData(
      asset.Id
    );
    Test.stopTest();

    System.assertNotEquals(null, payload, 'Payload should not be null');
    System.assertEquals(
      '1FTFW1ED8NFC12345',
      payload.assetInfo.vin,
      'VIN should match'
    );
    System.assertEquals(
      'NH73CXK',
      payload.assetInfo.licensePlate,
      'License plate should be parsed from name'
    );

    // Verify Model Resources
    System.assertNotEquals(
      null,
      payload.modelResources,
      'Model resources should be populated'
    );

    // Verify Compliance Documents
    System.assertEquals(
      3,
      payload.complianceDocuments.size(),
      'Should return 3 compliance docs'
    );
    Boolean foundWithFile = false;
    Boolean foundExpiring = false;
    Boolean foundExpired = false;

    for (
      FleetDigitalGloveboxController.ComplianceDoc doc : payload.complianceDocuments
    ) {
      if (doc.hasFiles) {
        foundWithFile = true;
        System.assertNotEquals(null, doc.fileDownloadUrl);
      }
      if (doc.expiryStatus == 'warning') {
        foundExpiring = true;
      }
      if (doc.expiryStatus == 'expired') {
        foundExpired = true;
      }
    }
    System.assert(foundWithFile, 'Should have attached file on registration');
    System.assert(
      foundExpiring,
      'Should detect document expiring within 30 days'
    );
    System.assert(foundExpired, 'Should detect expired document');

    // Verify Maintenance
    System.assertNotEquals(null, payload.maintenanceInfo);
    System.assertEquals(1, payload.maintenanceInfo.recentTickets.size());
    System.assert(payload.maintenanceInfo.applicablePlans.size() >= 1);
  }

  @IsTest
  static void testGetGloveboxDataNullAsset() {
    try {
      FleetDigitalGloveboxController.getGloveboxData(null);
      System.assert(false, 'Expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assert(true);
    }
  }

  @IsTest
  static void testCreateAssetDocument() {
    fleetforce__Fleet_Asset__c asset = [
      SELECT Id
      FROM fleetforce__Fleet_Asset__c
      LIMIT 1
    ];

    Test.startTest();
    Id newDocId = FleetDigitalGloveboxController.createAssetDocument(
      asset.Id,
      'Permit (Commercial)',
      'PERMIT-7890',
      Date.today(),
      Date.today().addYears(1),
      'https://example.com/permit.pdf'
    );
    Test.stopTest();

    System.assertNotEquals(null, newDocId);
    fleetforce__Asset_Document__c created = [
      SELECT Id, fleetforce__Doc_Type__c, fleetforce__Status__c
      FROM fleetforce__Asset_Document__c
      WHERE Id = :newDocId
    ];
    System.assertEquals('Permit (Commercial)', created.fleetforce__Doc_Type__c);
    System.assertEquals('Current', created.fleetforce__Status__c);
  }

  @IsTest
  static void testCreateAssetDocumentValidation() {
    try {
      FleetDigitalGloveboxController.createAssetDocument(
        null,
        'Registration',
        '123',
        null,
        null,
        null
      );
      System.assert(false, 'Expected AuraHandledException for null asset');
    } catch (AuraHandledException e) {
      System.assert(true);
    }

    try {
      fleetforce__Fleet_Asset__c asset = [
        SELECT Id
        FROM fleetforce__Fleet_Asset__c
        LIMIT 1
      ];
      FleetDigitalGloveboxController.createAssetDocument(
        asset.Id,
        '',
        '123',
        null,
        null,
        null
      );
      System.assert(false, 'Expected AuraHandledException for empty docType');
    } catch (AuraHandledException e) {
      System.assert(true);
    }
  }

  @IsTest
  static void testToEmbedUrl() {
    System.assertEquals(null, FleetDigitalGloveboxController.toEmbedUrl(null));
    System.assertEquals(
      'https://www.youtube-nocookie.com/embed/f2dI3L41qB0',
      FleetDigitalGloveboxController.toEmbedUrl(
        'https://www.youtube.com/watch?v=f2dI3L41qB0&t=10s'
      )
    );
    System.assertEquals(
      'https://www.youtube-nocookie.com/embed/f2dI3L41qB0',
      FleetDigitalGloveboxController.toEmbedUrl(
        'https://youtu.be/f2dI3L41qB0?si=abc'
      )
    );
    System.assertEquals(
      'https://www.youtube.com/embed/f2dI3L41qB0',
      FleetDigitalGloveboxController.toEmbedUrl(
        'https://www.youtube.com/embed/f2dI3L41qB0'
      )
    );
  }
}
