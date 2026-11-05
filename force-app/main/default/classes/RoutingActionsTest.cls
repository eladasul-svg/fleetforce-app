@IsTest
private class RoutingActionsTest {
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

  private static RoutingActions.Request req(String tool, String inputJson) {
    RoutingActions.Request r = new RoutingActions.Request();
    r.toolName = tool;
    r.routeId = [SELECT Id FROM Route__c LIMIT 1].Id;
    r.inputJson = inputJson;
    return r;
  }

  @IsTest
  static void toolsRunAndProposalsApplyOnASecondCall() {
    RoutingProviders.useForTest(new MockRoutingProvider());
    List<RoutingActions.Result> results;
    System.runAs(RoutingTestData.self()) {
      results = RoutingActions.run(
        new List<RoutingActions.Request>{
          req('get_route', null),
          req('report_delay', '{"minutes": 40, "reason": "loading"}'),
          req('reoptimize_remaining', '{}'),
          req('teleport', null),
          req('get_route', '[1,2]')
        }
      );
    }
    System.assert(
      results[0].success && results[0].resultJson.contains('remainingStops')
    );
    System.assert(results[1].success);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Route_Event__c WHERE Type__c = 'Delay Reported']
    );
    System.assertNotEquals(null, results[2].proposalJson);
    System.assertEquals('Driver', results[2].approver);
    System.assert(
      !results[3].success && results[3].message.contains('Unknown')
    );
    System.assert(!results[4].success);

    RoutingActions.Request approve = req(null, null);
    approve.approveProposalJson = results[2].proposalJson;
    RoutingActions.Request notRouting = req(null, null);
    notRouting.approveProposalJson = '{"action":"update"}';
    System.runAs(RoutingTestData.self()) {
      results = RoutingActions.run(
        new List<RoutingActions.Request>{ approve, notRouting }
      );
    }
    System.assert(results[0].success, results[0].message);
    System.assert(!results[1].success);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Route_Event__c WHERE Type__c = 'Reoptimized']
    );
  }
}
