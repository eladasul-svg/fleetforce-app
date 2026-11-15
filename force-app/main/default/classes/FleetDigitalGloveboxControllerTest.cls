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

    // Insert Maintenance Plan with Line Items
    fleetforce__Maintenance_Plan__c plan = new fleetforce__Maintenance_Plan__c(
      Name = 'Truck 3-Year Commercial Program',
      fleetforce__Asset_Type__c = 'Truck',
      fleetforce__Frequency_Type__c = 'Mileage-Based',
      fleetforce__Interval_Value__c = 5000,
      fleetforce__Calendar_Interval_Months__c = 36,
      fleetforce__SOP_Checklist__c = 'Comprehensive PM schedule',
      fleetforce__Warning_Miles__c = 1000
    );
    insert plan;

    List<fleetforce__Maintenance_Plan_Line_Item__c> items = new List<fleetforce__Maintenance_Plan_Line_Item__c>{
      new fleetforce__Maintenance_Plan_Line_Item__c(
        Name = '5,000-Mile Oil Service',
        fleetforce__Maintenance_Plan__c = plan.Id,
        fleetforce__Sequence__c = 1,
        fleetforce__Milestone_Mileage__c = 5000,
        fleetforce__Milestone_Months__c = 6,
        fleetforce__Service_Category__c = 'Oil & Fluids',
        fleetforce__Components_Serviced__c = 'Engine Oil, Filter',
        fleetforce__Estimated_Cost__c = 110.00,
        fleetforce__Estimated_Hours__c = 1.0,
        fleetforce__SOP_Checklist__c = 'Drain and fill oil'
      ),
      new fleetforce__Maintenance_Plan_Line_Item__c(
        Name = '20,000-Mile Major Brake Service',
        fleetforce__Maintenance_Plan__c = plan.Id,
        fleetforce__Sequence__c = 2,
        fleetforce__Milestone_Mileage__c = 20000,
        fleetforce__Milestone_Months__c = 24,
        fleetforce__Service_Category__c = 'Tires & Brakes',
        fleetforce__Components_Serviced__c = 'Brake pads, rotors',
        fleetforce__Estimated_Cost__c = 350.00,
        fleetforce__Estimated_Hours__c = 2.5,
        fleetforce__SOP_Checklist__c = 'Replace front pads'
      )
    };
    insert items;

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
      fleetforce__Status__c = 'Available',
      fleetforce__Assigned_Maintenance_Plan__c = plan.Id
    );
    insert asset;

    // Direct Vehicle File
    ContentVersion cvDirect = new ContentVersion(
      Title = 'Vehicle_Title_Deed',
      PathOnClient = 'Vehicle_Title_Deed.pdf',
      VersionData = Blob.valueOf('Direct Vehicle Title'),
      IsMajorVersion = true
    );
    insert cvDirect;

    Id cvDirectDocId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :cvDirect.Id
    ]
    .ContentDocumentId;
    insert new ContentDocumentLink(
      LinkedEntityId = asset.Id,
      ContentDocumentId = cvDirectDocId,
      ShareType = 'V'
    );

    // Insert Citation with Attached File
    fleetforce__Citation__c cit = new fleetforce__Citation__c(
      fleetforce__Fleet_Asset__c = asset.Id,
      fleetforce__Ticket_Number__c = 'CIT-9901',
      fleetforce__Violation_Type__c = 'Speeding',
      fleetforce__Fine_Amount__c = 120.00,
      fleetforce__Status__c = 'New',
      fleetforce__Citation_Date__c = DateTime.now().addDays(-5)
    );
    insert cit;

    ContentVersion cvCit = new ContentVersion(
      Title = 'Speed_Camera_Photo',
      PathOnClient = 'Speed_Camera_Photo.jpg',
      VersionData = Blob.valueOf('Speed camera photo'),
      IsMajorVersion = true
    );
    insert cvCit;
    Id cvCitDocId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :cvCit.Id
    ]
    .ContentDocumentId;
    insert new ContentDocumentLink(
      LinkedEntityId = cit.Id,
      ContentDocumentId = cvCitDocId,
      ShareType = 'V'
    );

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

    // Attach ContentVersion to registration
    ContentVersion cvReg = new ContentVersion(
      Title = 'Registration_Certificate',
      PathOnClient = 'Registration_Certificate.pdf',
      VersionData = Blob.valueOf('Fake PDF Content'),
      IsMajorVersion = true
    );
    insert cvReg;

    Id regContentDocId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :cvReg.Id
    ]
    .ContentDocumentId;
    insert new ContentDocumentLink(
      LinkedEntityId = docs[0].Id,
      ContentDocumentId = regContentDocId,
      ShareType = 'V'
    );

    // Insert Service Ticket linked to plan line item
    fleetforce__Service_Ticket__c ticket = new fleetforce__Service_Ticket__c(
      fleetforce__Fleet_Asset__c = asset.Id,
      fleetforce__Category__c = 'Preventive Maintenance',
      fleetforce__Status__c = 'Draft',
      fleetforce__Summary__c = 'Scheduled 20,000-Mile Brake Service',
      fleetforce__Priority__c = 'Medium',
      fleetforce__Maintenance_Plan__c = plan.Id,
      fleetforce__Maintenance_Plan_Line_Item__c = items[1].Id,
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
    System.assertNotEquals(null, payload.modelResources);

    // Verify Compliance Documents
    System.assertEquals(
      3,
      payload.complianceDocuments.size(),
      'Should return 3 compliance docs'
    );

    // Verify Maintenance Info
    System.assertNotEquals(null, payload.maintenanceInfo);
    System.assert(
      payload.maintenanceInfo.hasActivePlan,
      'Should have active maintenance plan'
    );
    System.assertEquals(true, payload.maintenanceInfo.isOverridden);
    System.assertEquals(2, payload.maintenanceInfo.lineItems.size());
    System.assert(
      payload.maintenanceInfo.hasNextMilestone,
      'Should identify next milestone'
    );
    System.assertEquals(
      20000,
      payload.maintenanceInfo.nextMilestoneDueOdometer
    );
    System.assert(
      payload.maintenanceInfo.hasScheduledTicket,
      'Should identify scheduled ticket'
    );

    // Verify Vehicle Documents
    System.assertNotEquals(null, payload.directAssetDocuments);
    System.assertEquals(
      1,
      payload.directAssetDocuments.size(),
      'Should have 1 direct asset file'
    );
    System.assertNotEquals(null, payload.systemLinkedDocuments);
    System.assert(
      payload.systemLinkedDocuments.size() >= 1,
      'Should have system linked citation file'
    );
  }

  @IsTest
  static void testAssignMaintenancePlan() {
    fleetforce__Fleet_Asset__c asset = [
      SELECT Id, fleetforce__Assigned_Maintenance_Plan__c
      FROM fleetforce__Fleet_Asset__c
      LIMIT 1
    ];

    fleetforce__Maintenance_Plan__c newPlan = new fleetforce__Maintenance_Plan__c(
      Name = 'Severe Duty Winter Schedule',
      fleetforce__Asset_Type__c = 'Truck',
      fleetforce__Frequency_Type__c = 'Mileage-Based',
      fleetforce__Interval_Value__c = 3000
    );
    insert newPlan;

    Test.startTest();
    FleetDigitalGloveboxController.assignMaintenancePlan(asset.Id, newPlan.Id);
    Test.stopTest();

    fleetforce__Fleet_Asset__c updated = [
      SELECT Id, fleetforce__Assigned_Maintenance_Plan__c
      FROM fleetforce__Fleet_Asset__c
      WHERE Id = :asset.Id
    ];
    System.assertEquals(
      newPlan.Id,
      updated.fleetforce__Assigned_Maintenance_Plan__c
    );
  }

  @IsTest
  static void testAssignMaintenancePlanNullValidation() {
    try {
      FleetDigitalGloveboxController.assignMaintenancePlan(null, null);
      System.assert(false, 'Expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assert(true);
    }
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
