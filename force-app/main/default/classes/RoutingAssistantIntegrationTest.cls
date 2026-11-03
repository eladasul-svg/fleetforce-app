/** The routing tools inside a real AssistantService turn, with Claude mocked over HTTP. */
@IsTest
private class RoutingAssistantIntegrationTest {
  private class ClaudeMock implements HttpCalloutMock {
    List<String> bodies;
    Integer calls = 0;
    String lastBody;
    ClaudeMock(List<String> bodies) {
      this.bodies = bodies;
    }
    public HttpResponse respond(HttpRequest req) {
      lastBody = req.getBody();
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setBody(bodies[Math.min(calls++, bodies.size() - 1)]);
      return res;
    }
  }

  private static String toolUse(String name, Map<String, Object> input) {
    return JSON.serialize(
      new Map<String, Object>{
        'content' => new List<Object>{
          new Map<String, Object>{
            'type' => 'text',
            'text' => 'Checking the route.'
          },
          new Map<String, Object>{
            'type' => 'tool_use',
            'id' => 'toolu_1',
            'name' => name,
            'input' => input
          }
        },
        'stop_reason' => 'tool_use',
        'usage' => new Map<String, Object>{
          'input_tokens' => 10,
          'output_tokens' => 5
        }
      }
    );
  }

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

  private static Assistant_Session__c routeSession() {
    Route__c r = [SELECT Id FROM Route__c LIMIT 1];
    Assistant_Session__c s = new Assistant_Session__c(
      Record_Id__c = r.Id,
      Record_Object__c = 'Route__c',
      Last_Activity__c = System.now()
    );
    insert s;
    return s;
  }

  @IsTest
  static void routeChatsGetRoutingToolsAndGuidance() {
    Assistant_Session__c s = routeSession();
    ClaudeMock mock = new ClaudeMock(
      new List<String>{ toolUse('get_route', new Map<String, Object>()) }
    );
    Test.setMock(HttpCalloutMock.class, mock);
    AssistantService.TurnResult r;
    System.runAs(RoutingTestData.self()) {
      Test.startTest();
      r = AssistantService.sendMessage(s.Id, 'Where am I?');
      Test.stopTest();
    }
    System.assertEquals('tool_step', r.kind);
    Map<String, Object> req = (Map<String, Object>) JSON.deserializeUntyped(
      mock.lastBody
    );
    System.assertEquals(6 + 8, ((List<Object>) req.get('tools')).size());
    String context = (String) ((Map<String, Object>) ((List<Object>) req.get(
        'system'
      ))[1])
      .get('text');
    System.assert(context.contains('never invent a stop order'), context);
    Assistant_Message__c toolResults = [
      SELECT Content__c
      FROM Assistant_Message__c
      WHERE Session__c = :s.Id AND Role__c = 'user'
      ORDER BY Sequence__c DESC
      LIMIT 1
    ];
    System.assert(
      toolResults.Content__c.contains('remainingStops'),
      toolResults.Content__c.abbreviate(300)
    );
  }

  @IsTest
  static void delayThenReplanIsAProposalLinkedToTheSession() {
    Assistant_Session__c s = routeSession();
    RoutingProviders.useForTest(new MockRoutingProvider());
    Test.setMock(
      HttpCalloutMock.class,
      new ClaudeMock(
        new List<String>{
          toolUse('reoptimize_remaining', new Map<String, Object>())
        }
      )
    );
    AssistantService.TurnResult r;
    System.runAs(RoutingTestData.self()) {
      Test.startTest();
      r = AssistantService.sendMessage(s.Id, 'Re-plan my stops please');
      Test.stopTest();
      System.assertEquals('proposal', r.kind);
      System.assertEquals('routing.reoptimize', r.proposal.get('action'));
      AssistantService.TurnResult resolved = AssistantService.resolveProposal(
        s.Id,
        true,
        null
      );
      System.assertEquals(
        true,
        resolved.outcome.get('success'),
        resolved.outcome.get('error')
      );
    }
    Route_Event__c e = [
      SELECT Assistant_Session__c, Actor_Type__c
      FROM Route_Event__c
      WHERE Type__c = 'Reoptimized'
    ];
    System.assertEquals(s.Id, e.Assistant_Session__c);
    System.assertEquals('Dispatcher', e.Actor_Type__c);
  }

  @IsTest
  static void declinedRoutingProposalsAreLogged() {
    Assistant_Session__c s = routeSession();
    Test.setMock(
      HttpCalloutMock.class,
      new ClaudeMock(
        new List<String>{
          toolUse(
            'add_waypoint',
            new Map<String, Object>{ 'type' => 'Break', 'minutes' => 15 }
          )
        }
      )
    );
    System.runAs(RoutingTestData.self()) {
      Test.startTest();
      AssistantService.sendMessage(s.Id, 'I need a break');
      Test.stopTest();
      AssistantService.resolveProposal(s.Id, false, 'Later');
    }
    Route_Event__c e = [
      SELECT Assistant_Session__c, Payload__c
      FROM Route_Event__c
      WHERE Type__c = 'Proposal Rejected'
    ];
    System.assertEquals(s.Id, e.Assistant_Session__c);
    System.assert(e.Payload__c.contains('Later'));
  }
}
