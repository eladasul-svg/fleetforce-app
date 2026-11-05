@IsTest
private class RouteReplanServiceTest {
  @TestSetup
  static void makeData() {
    RoutingTestData.grantAccess();
    Id planId = RoutingTestData.scenario(3);
    System.runAs(RoutingTestData.self()) {
      RoutePlanService.PlanContext ctx = RoutePlanService.buildRequest(planId);
      RoutePlanService.applyResult(
        ctx,
        RoutingDtos.parseOptimize(RoutingTestData.answer(ctx.request.toJson()))
      );
    }
  }

  @IsTest
  static void continuesFromTheLastCompletedStopWithTheDelay() {
    Route__c r = [SELECT Id FROM Route__c LIMIT 1];
    List<Waypoint__c> ws = [
      SELECT Id, Location__Latitude__s
      FROM Waypoint__c
      WHERE Route__c = :r.Id
      ORDER BY Sequence__c
    ];
    Datetime departed = RoutingTestData.local(11, 0);
    update new Waypoint__c(
      Id = ws[1].Id,
      Status__c = 'Completed',
      Actual_Departure__c = departed
    );
    insert new Route_Event__c(
      Route__c = r.Id,
      Type__c = 'Delay Reported',
      Actor_Type__c = 'Driver',
      Payload__c = '{"minutes":40}',
      Occurred_At__c = System.now()
    );
    RouteReplanService.RouteContext ctx;
    System.runAs(RoutingTestData.self()) {
      ctx = RouteReplanService.buildRequest(r.Id, null, 5, null, null);
    }
    System.assertEquals(45, ctx.delayMinutes);
    System.assertEquals(departed.addMinutes(45), ctx.startTime);
    System.assertEquals(
      ws[1].Location__Latitude__s.setScale(5),
      Decimal.valueOf(ctx.startLocation.getLatitude()).setScale(5)
    );
    System.assertEquals(
      3,
      ctx.request.taskCount(),
      '2 drops left and the relocation shipment'
    );
  }

  @IsTest
  static void helpers() {
    System.assertEquals(0, RouteReplanService.delayOf('not json'));
    System.assertEquals(0, RouteReplanService.delayOf('{"other":1}'));
    Route__c r = [SELECT Id FROM Route__c LIMIT 1];
    update new Route__c(Id = r.Id, Status__c = 'Completed');
    System.runAs(RoutingTestData.self()) {
      try {
        RouteReplanService.buildRequest(r.Id, null, 0, null, null);
        System.assert(false, 'expected an exception');
      } catch (RoutingProviders.RoutingException e) {
        System.assert(e.getMessage().contains('cannot be re-planned'));
      }
    }
  }
}
