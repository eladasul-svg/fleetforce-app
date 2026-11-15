@IsTest
private class CmdtDeployServiceTest {
  @IsTest
  static void testUnsupportedTypeThrows() {
    Boolean threw = false;
    Test.startTest();
    try {
      CmdtDeployService.requestDeploy(
        'Account',
        'Test_Dev_Name',
        'Test Label',
        'req-1',
        new Map<String, Object>()
      );
    } catch (AuraHandledException ex) {
      threw = true;
    }
    Test.stopTest();
    System.assert(threw, 'Unsupported type should throw exception');
  }

  @IsTest
  static void testBlankDeveloperNameThrows() {
    Boolean threw = false;
    Test.startTest();
    try {
      CmdtDeployService.requestDeploy(
        'Country_Profile__mdt',
        '',
        'Test Label',
        'req-2',
        new Map<String, Object>()
      );
    } catch (AuraHandledException ex) {
      threw = true;
    }
    Test.stopTest();
    System.assert(threw, 'Blank developer name should throw exception');
  }

  @IsTest
  static void testBlankRequestKeyThrows() {
    Boolean threw = false;
    Test.startTest();
    try {
      CmdtDeployService.requestDeploy(
        'Country_Profile__mdt',
        'IT',
        'Italy',
        '',
        new Map<String, Object>()
      );
    } catch (AuraHandledException ex) {
      threw = true;
    }
    Test.stopTest();
    System.assert(threw, 'Blank request key should throw exception');
  }

  @IsTest
  static void testValidRequestEnqueuesDeployment() {
    Map<String, Object> values = new Map<String, Object>{
      'ISO_Code__c' => 'IT',
      'Country_Name__c' => 'Italy',
      'Distance_Unit__c' => 'km'
    };

    Test.startTest();
    String jobId = CmdtDeployService.requestDeploy(
      'Country_Profile__mdt',
      'IT',
      'Italy',
      'req-valid-123',
      values
    );
    Test.stopTest();

    System.assertEquals('TEST_DEPLOY_JOB_ID', jobId);
  }
}
