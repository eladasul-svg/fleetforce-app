@IsTest
private class RoutePlanControllerTest {
  @TestSetup
  static void makeData() {
    RoutingTestData.grantAccess();
    RoutingTestData.scenario(3);
  }

  @IsTest
  static void boardShowsRoutesStopsAndUnassignedJobs() {
    Id planId = [SELECT Id FROM Route_Plan__c LIMIT 1].Id;
    RoutePlanController.Board before;
    RoutePlanController.Board after;
    System.runAs(RoutingTestData.self()) {
      before = RoutePlanController.getBoard(planId);
      RoutePlanService.PlanContext ctx = RoutePlanService.buildRequest(planId);
      RoutePlanService.applyResult(
        ctx,
        RoutingDtos.parseOptimize(RoutingTestData.answer(ctx.request.toJson()))
      );
      after = RoutePlanController.getBoard(planId);
    }
    System.assertEquals('Draft', before.status);
    System.assert(before.canOptimize && !before.canPublish);
    System.assert(before.routes.isEmpty());
    System.assert(before.channel.endsWith('Route_Plan_Update__e'));

    System.assertEquals('Optimized', after.status);
    System.assert(after.canPublish);
    System.assertEquals(1, after.routes.size());
    RoutePlanController.RouteView r = after.routes[0];
    System.assertEquals('RT-VAN-1', r.vehicle);
    System.assertEquals(5, r.jobStops, '3 drops, pickup, drop');
    System.assertEquals('Start', r.stops[0].type);
    System.assertEquals(1, r.stops[1].jobs.size());
    System.assertEquals(
      2,
      after.unassigned.size(),
      'refrigerated and no-location jobs'
    );
  }

  @IsTest
  static void optimizeQueuesAndPublishChecksStatus() {
    Id planId = [SELECT Id FROM Route_Plan__c LIMIT 1].Id;
    Test.setMock(HttpCalloutMock.class, new RoutingTestData.EchoService());
    System.runAs(RoutingTestData.self()) {
      Test.startTest();
      System.assertNotEquals(null, RoutePlanController.optimize(planId));
      Test.stopTest();
      RoutePlanController.publish(planId);
      try {
        RoutePlanController.publish(planId);
        System.assert(false, 'expected an exception');
      } catch (AuraHandledException e) {
        System.assert(
          e.getMessage().contains('Only an Optimized plan'),
          e.getMessage()
        );
      }
      try {
        RoutePlanController.optimize(planId);
        System.assert(false, 'expected an exception');
      } catch (AuraHandledException e) {
        System.assert(
          e.getMessage().contains('cannot be re-optimized'),
          e.getMessage()
        );
      }
      try {
        RoutePlanController.getBoard(RoutingTestData.self().Id);
        System.assert(false, 'expected an exception');
      } catch (AuraHandledException e) {
        System.assertNotEquals(null, e.getMessage());
      }
    }
    System.assertEquals(
      'Published',
      [SELECT Status__c FROM Route_Plan__c WHERE Id = :planId].Status__c
    );
  }
}
