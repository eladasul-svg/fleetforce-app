@IsTest
private class FleetForceSetupTest {
  @TestSetup
  static void fleet() {
    DataTrustTestData.grantAccess();
    insert new List<Fleet_Asset__c>{
      DataTrustTestData.asset(
        '2022 Ford Transit-250 Cargo Van',
        'Gasoline',
        null,
        null,
        null,
        'PT'
      ),
      DataTrustTestData.asset(
        '2023 Ford Explorer XLT',
        'Gasoline',
        null,
        null,
        null,
        'PT'
      ),
      DataTrustTestData.asset(
        '2023 Toyota Camry LE',
        'Gasoline',
        null,
        null,
        null,
        'ES'
      )
    };
  }

  @IsTest
  static void seedResetAndSchedule() {
    System.runAs(DataTrustTestData.self()) {
      Map<String, Object> summary = (Map<String, Object>) JSON.deserializeUntyped(
        FleetForceSetup.seedDataTrustSample()
      );
      Assert.isTrue(summary.containsKey('referenceScores'));
      Assert.isTrue(
        [SELECT COUNT() FROM Data_Source__c WHERE Is_Sample__c = TRUE] > 0
      );

      FleetForceSetup.resetDataTrustSample();
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Data_Source__c WHERE Is_Sample__c = TRUE]
      );

      Test.startTest();
      Assert.isNotNull(FleetForceSetup.scheduleNightlyDataHealth());
      Test.stopTest();
    }
  }
}
