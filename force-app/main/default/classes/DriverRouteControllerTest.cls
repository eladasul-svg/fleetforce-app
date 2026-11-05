@IsTest
private class DriverRouteControllerTest {
  @TestSetup
  static void makeData() {
    RoutingTestData.grantAccess();
    Id planId = RoutingTestData.scenario(2);
    update new Route_Plan__c(Id = planId, Plan_Date__c = Date.today());
    List<Route_Job__c> jobs = [
      SELECT Id
      FROM Route_Job__c
      WHERE Service_Date__c = :RoutingTestData.planDate()
    ];
    for (Route_Job__c j : jobs) {
      j.Service_Date__c = Date.today();
    }
    update jobs;
    System.runAs(RoutingTestData.self()) {
      RoutePlanService.PlanContext ctx = RoutePlanService.buildRequest(planId);
      RoutePlanService.applyResult(
        ctx,
        RoutingDtos.parseOptimize(RoutingTestData.answer(ctx.request.toJson()))
      );
    }
  }

  @IsTest
  static void returnsTodaysStopsForTheDriver() {
    Fleet_Asset__c van1 = RoutingTestData.assetsByName().get('RT-VAN-1');
    Job_Visit__c first = [
      SELECT Id
      FROM Job_Visit__c
      WHERE Waypoint__c != NULL
      ORDER BY Waypoint__r.Sequence__c
      LIMIT 1
    ];
    update new Job_Visit__c(Id = first.Id, Access_Notes__c = 'Back gate');
    DriverRouteController.DriverRoute r = DriverRouteController.getTodayRoute(
      van1.Driver__c
    );
    System.assertNotEquals(null, r);
    System.assertEquals('RT-VAN-1', r.vehicle);
    System.assertEquals(4, r.remaining, '2 drops, pickup, drop');
    System.assertEquals('Back to depot', r.stops[r.stops.size() - 1].label);
    System.assertEquals('Back gate', r.stops[0].accessNotes);
    System.assert(r.stops[2].label.contains('pick up'));
    System.assertEquals(null, DriverRouteController.getTodayRoute(null));
    Fleet_Asset__c ev = RoutingTestData.assetsByName().get('RT-VAN-2 EV');
    System.assertEquals(
      null,
      DriverRouteController.getTodayRoute(ev.Driver__c),
      'no route today'
    );
  }
}
