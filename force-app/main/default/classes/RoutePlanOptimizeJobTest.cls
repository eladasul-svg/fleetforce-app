@IsTest
private class RoutePlanOptimizeJobTest {
  @TestSetup
  static void makeData() {
    RoutingTestData.grantAccess();
    RoutingTestData.scenario(3);
  }

  private static Id planId() {
    return [SELECT Id FROM Route_Plan__c LIMIT 1].Id;
  }

  @IsTest
  static void queueableOptimizesAndPublishesAnUpdate() {
    Id pid = planId();
    RoutingTestData.EchoService service = new RoutingTestData.EchoService();
    Test.setMock(HttpCalloutMock.class, service);
    System.runAs(RoutingTestData.self()) {
      Test.startTest();
      System.enqueueJob(new RoutePlanOptimizeJob(pid));
      Test.stopTest();
    }
    Route_Plan__c plan = [
      SELECT Status__c, Revision__c, Error__c
      FROM Route_Plan__c
      WHERE Id = :pid
    ];
    System.assertEquals('Optimized', plan.Status__c, plan.Error__c);
    System.assertEquals(1, plan.Revision__c);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Route__c WHERE Route_Plan__c = :pid]
    );
    System.assert(service.lastBody.contains('"vehicles"'));
  }

  @IsTest
  static void serviceErrorsLeaveTheErrorOnThePlan() {
    Id pid = planId();
    RoutingTestData.EchoService service = new RoutingTestData.EchoService();
    service.statusCode = 500;
    service.errorBody = 'Internal error';
    Test.setMock(HttpCalloutMock.class, service);
    RoutingDtos.OptimizeResult result;
    System.runAs(RoutingTestData.self()) {
      Test.startTest();
      result = RoutePlanOptimizeJob.run(pid);
      Test.stopTest();
    }
    System.assertEquals(null, result);
    Route_Plan__c plan = [
      SELECT Status__c, Error__c
      FROM Route_Plan__c
      WHERE Id = :pid
    ];
    System.assertEquals('Draft', plan.Status__c);
    System.assert(
      plan.Error__c.contains('temporarily unavailable'),
      plan.Error__c
    );
    System.assertEquals(0, [SELECT COUNT() FROM Route__c]);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Route_Event__c WHERE Type__c = 'Optimization Failed']
    );
  }

  @IsTest
  static void noEligibleVehicleIsAnError() {
    Id pid = planId();
    List<Fleet_Asset__c> vans = [
      SELECT Id
      FROM Fleet_Asset__c
      WHERE Name IN ('RT-VAN-1', 'RT-VAN-2 EV')
    ];
    for (Fleet_Asset__c a : vans) {
      a.Is_Active__c = false;
    }
    update vans;
    System.runAs(RoutingTestData.self()) {
      RoutePlanOptimizeJob.run(pid);
    }
    Route_Plan__c plan = [
      SELECT Status__c, Error__c
      FROM Route_Plan__c
      WHERE Id = :pid
    ];
    System.assertEquals('Draft', plan.Status__c);
    System.assert(
      plan.Error__c.contains('No vehicle at the depot can be routed'),
      plan.Error__c
    );
    System.assert(plan.Error__c.contains('in-shop'), plan.Error__c);
  }

  @IsTest
  static void planWithoutJobsOptimizesToNothingWithoutACallout() {
    Id pid = planId();
    delete [SELECT Id FROM Route_Job__c];
    MockRoutingProvider mock = new MockRoutingProvider();
    RoutingProviders.useForTest(mock);
    System.runAs(RoutingTestData.self()) {
      RoutePlanOptimizeJob.run(pid);
    }
    System.assertEquals(0, mock.optimizeCalls);
    System.assertEquals(
      'Optimized',
      [SELECT Status__c FROM Route_Plan__c WHERE Id = :pid].Status__c
    );
  }

  @IsTest
  static void mockProviderPlansTheWholeScenario() {
    Id pid = planId();
    RoutingProviders.useForTest(new MockRoutingProvider());
    System.runAs(RoutingTestData.self()) {
      RoutePlanOptimizeJob.run(pid);
    }
    Route_Plan__c plan = [
      SELECT Status__c, Error__c, Unassigned_Count__c
      FROM Route_Plan__c
      WHERE Id = :pid
    ];
    System.assertEquals('Optimized', plan.Status__c, plan.Error__c);
    System.assertEquals(
      2,
      plan.Unassigned_Count__c,
      'refrigerated and no-location'
    );
    System.assert(
      [SELECT COUNT() FROM Route__c WHERE Route_Plan__c = :pid] >= 1
    );
  }
}
