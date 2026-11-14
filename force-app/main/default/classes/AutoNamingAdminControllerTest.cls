/**
 * @description Unit tests for AutoNamingAdminController.
 */
@IsTest
private class AutoNamingAdminControllerTest {
  @IsTest
  static void testGetSupportedObjectsAndFields() {
    Test.startTest();
    List<AutoNamingAdminController.ObjectConfigDTO> objects = AutoNamingAdminController.getSupportedObjects();
    Assert.isFalse(objects.isEmpty(), 'Expected supported objects list');

    List<AutoNamingAdminController.FieldDTO> fields = AutoNamingAdminController.getObjectFields(
      'Fleet_Asset__c'
    );
    Assert.isFalse(fields.isEmpty(), 'Expected field list for Fleet_Asset__c');
    Test.stopTest();
  }

  @IsTest
  static void testPreviewPatternWithSampleRecord() {
    Fleet_Asset__c asset = new Fleet_Asset__c(
      Make__c = 'Ford',
      Model__c = 'Transit',
      Model_Year__c = '2024',
      License_Plate__c = '48-912-34',
      Is_Active__c = true
    );
    insert asset;

    Test.startTest();
    String preview = AutoNamingAdminController.previewPattern(
      'Fleet_Asset__c',
      '{Model_Year__c} {Make__c} {Model__c}'
    );
    Test.stopTest();

    Assert.areEqual(
      '2024 Ford Transit',
      preview,
      'Expected preview to evaluate correctly'
    );
  }

  @IsTest
  static void testPreviewPatternWithMockFallback() {
    Test.startTest();
    String preview = AutoNamingAdminController.previewPattern(
      'Fleet_Asset__c',
      '{Make__c} {Model__c} ({Status__c})'
    );
    Test.stopTest();

    Assert.isTrue(
      String.isNotBlank(preview),
      'Expected mock preview to generate non-empty string'
    );
  }

  @IsTest
  static void testBatchExecutionAndStatus() {
    Fleet_Asset__c asset = new Fleet_Asset__c(
      Make__c = 'Ram',
      Model__c = 'ProMaster',
      Model_Year__c = '2023',
      License_Plate__c = '55-666-77',
      Is_Active__c = true
    );
    insert asset;

    Test.startTest();
    Id jobId = AutoNamingAdminController.runRecalculateBatch(
      'Fleet_Asset__c',
      '{Make__c} {Model__c}'
    );
    AutoNamingAdminController.BatchStatusDTO status = AutoNamingAdminController.getBatchJobStatus(
      jobId
    );
    Test.stopTest();

    Assert.isNotNull(jobId, 'Expected valid AsyncApexJob Id');
    Assert.isNotNull(status.status, 'Expected job status string');
  }

  @IsTest
  static void testSaveRule() {
    Test.startTest();
    AutoNamingAdminController.saveRule(
      'Fleet_Asset__c',
      '{Model_Year__c} {Make__c} {Model__c}',
      true,
      false,
      'Test rule'
    );
    Test.stopTest();
    // Succeeded without exception
    Assert.isTrue(true, 'Expected saveRule to execute cleanly');
  }
}
