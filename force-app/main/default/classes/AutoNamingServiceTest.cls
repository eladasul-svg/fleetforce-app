/**
 * @description Comprehensive unit tests for AutoNamingService and AutoNamingBatch.
 */
@IsTest
private class AutoNamingServiceTest {
  @IsTest
  static void testFleetAssetAutoNaming() {
    Fleet_Asset__c asset = new Fleet_Asset__c(
      Make__c = 'Ford',
      Model__c = 'Ranger XLT',
      Model_Year__c = '2024',
      License_Plate__c = '48-912-34',
      Is_Active__c = true
    );

    Test.startTest();
    insert asset;
    Test.stopTest();

    Fleet_Asset__c reloaded = [
      SELECT Id, Name
      FROM Fleet_Asset__c
      WHERE Id = :asset.Id
    ];
    Assert.isTrue(
      reloaded.Name.contains('2024'),
      'Expected model year in name'
    );
    Assert.isTrue(
      reloaded.Name.contains('Ford Ranger XLT'),
      'Expected make and model in name'
    );
    Assert.isTrue(
      reloaded.Name.contains('48-912-34'),
      'Expected license plate in name'
    );
  }

  @IsTest
  static void testCitationAutoNaming() {
    Fleet_Asset__c asset = new Fleet_Asset__c(
      Make__c = 'Chevrolet',
      Model__c = 'Express',
      Model_Year__c = '2023',
      Is_Active__c = true
    );
    insert asset;

    Citation__c citation = new Citation__c(
      Fleet_Asset__c = asset.Id,
      Ticket_Number__c = 'CIT-12345',
      Violation_Type__c = 'Speeding'
    );

    Test.startTest();
    insert citation;
    Test.stopTest();

    Citation__c reloaded = [
      SELECT Id, Name
      FROM Citation__c
      WHERE Id = :citation.Id
    ];
    Assert.areEqual(
      'CIT-12345 · Speeding',
      reloaded.Name,
      'Expected formatted citation name'
    );
  }

  @IsTest
  static void testFallbackWhenPatternFieldsNull() {
    Fleet_Asset__c asset = new Fleet_Asset__c(
      Asset_ID__c = 'FA-9999',
      Is_Active__c = true
    );

    Test.startTest();
    insert asset;
    Test.stopTest();

    Fleet_Asset__c reloaded = [
      SELECT Id, Name
      FROM Fleet_Asset__c
      WHERE Id = :asset.Id
    ];
    Assert.areEqual(
      'FA-9999',
      reloaded.Name,
      'Expected fallback to Asset ID when make/model are blank'
    );
  }

  @IsTest
  static void testSanitizationAndBoundaryTruncation() {
    String raw = '  ( ) [ ] · - 2024 Ford Transit - ·  ';
    String cleaned = AutoNamingService.sanitizeFormattedString(raw);
    Assert.areEqual(
      '2024 Ford Transit',
      cleaned,
      'Expected stripped dangling separators'
    );

    String veryLong = 'A'.repeat(120);
    String truncated = AutoNamingService.enforceLength(veryLong);
    Assert.areEqual(
      80,
      truncated.length(),
      'Expected 80 characters truncation'
    );
  }

  @IsTest
  static void testAutoNamingBatchRecalculation() {
    List<Fleet_Asset__c> assets = new List<Fleet_Asset__c>();
    for (Integer i = 1; i <= 5; i++) {
      assets.add(
        new Fleet_Asset__c(
          Name = 'Raw Asset ' + i,
          Make__c = 'Toyota',
          Model__c = 'Hilux',
          Model_Year__c = '2022',
          License_Plate__c = '100-0' + i,
          Is_Active__c = true
        )
      );
    }
    insert assets;

    Test.startTest();
    AutoNamingBatch batchJob = new AutoNamingBatch('Fleet_Asset__c');
    Database.executeBatch(batchJob, 5);
    Test.stopTest();

    List<Fleet_Asset__c> reloaded = [
      SELECT Id, Name
      FROM Fleet_Asset__c
      WHERE Id IN :assets
    ];
    for (Fleet_Asset__c a : reloaded) {
      Assert.isTrue(
        a.Name.contains('Toyota Hilux'),
        'Expected batch to recalculate asset names'
      );
    }
  }

  @IsTest
  static void testAutoNamingBatchWithCustomPattern() {
    Fleet_Asset__c asset = new Fleet_Asset__c(
      Make__c = 'Mercedes',
      Model__c = 'Sprinter',
      Model_Year__c = '2024',
      License_Plate__c = '99-888-77',
      Is_Active__c = true
    );
    insert asset;

    Test.startTest();
    AutoNamingBatch batchJob = new AutoNamingBatch(
      'Fleet_Asset__c',
      '[{Model_Year__c}] {Make__c} {Model__c}'
    );
    Database.executeBatch(batchJob, 1);
    Test.stopTest();

    Fleet_Asset__c reloaded = [
      SELECT Id, Name
      FROM Fleet_Asset__c
      WHERE Id = :asset.Id
    ];
    Assert.areEqual(
      '[2024] Mercedes Sprinter',
      reloaded.Name,
      'Expected custom pattern evaluation'
    );
  }
}
