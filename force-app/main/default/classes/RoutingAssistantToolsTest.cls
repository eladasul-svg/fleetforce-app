@IsTest
private class RoutingAssistantToolsTest {
  @TestSetup
  static void makeData() {
    RoutingTestData.grantAccess();
    Id planId = RoutingTestData.scenario(4);
    System.runAs(RoutingTestData.self()) {
      RoutePlanService.PlanContext ctx = RoutePlanService.buildRequest(planId);
      RoutePlanService.applyResult(
        ctx,
        RoutingDtos.parseOptimize(RoutingTestData.answer(ctx.request.toJson()))
      );
    }
  }

  private static Route__c route() {
    return [
      SELECT Id, Name, Route_Plan__c, Driver__c, Revision__c
      FROM Route__c
      LIMIT 1
    ];
  }

  private static Assistant_Session__c session(Id recordId) {
    return new Assistant_Session__c(Record_Id__c = recordId);
  }

  private static List<Waypoint__c> stops(Id routeId) {
    return [
      SELECT
        Id,
        Sequence__c,
        Type__c,
        Status__c,
        Locked__c,
        (SELECT Id FROM Job_Visits__r)
      FROM Waypoint__c
      WHERE Route__c = :routeId
      ORDER BY Sequence__c
    ];
  }

  private static AssistantTools.ToolResult run(
    String tool,
    Map<String, Object> input,
    Id routeId
  ) {
    AssistantTools.ToolResult r;
    System.runAs(RoutingTestData.self()) {
      r = RoutingAssistantTools.execute(tool, input, session(routeId));
    }
    return r;
  }

  private static Map<String, Object> approve(Map<String, Object> proposal) {
    Map<String, Object> outcome;
    System.runAs(RoutingTestData.self()) {
      outcome = RoutingAssistantTools.executeProposal(
        (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(proposal)),
        null
      );
    }
    return outcome;
  }

  @IsTest
  static void toolsAreOfferedOnRouteChatsOnly() {
    Route__c r = route();
    System.assertEquals(8, RoutingAssistantTools.definitions().size());
    System.assert(RoutingAssistantTools.appliesTo(session(r.Id)));
    System.assert(!RoutingAssistantTools.appliesTo(session(r.Route_Plan__c)));
    System.assert(!RoutingAssistantTools.appliesTo(new Assistant_Session__c()));
    System.assert(
      !RoutingAssistantTools.appliesTo(
        new Assistant_Session__c(Record_Id__c = 'not-an-id')
      )
    );
    System.assert(
      RoutingAssistantTools.handles('reoptimize_remaining') &&
      !RoutingAssistantTools.handles('query_records')
    );
    System.assert(
      RoutingAssistantTools.contextPrompt()
        .contains('never invent a stop order')
    );
  }

  @IsTest
  static void getRouteListsRemainingStops() {
    Route__c r = route();
    AssistantTools.ToolResult res = run('get_route', null, r.Id);
    System.assert(!res.isError, res.content);
    Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(
      res.content
    );
    List<Object> remaining = (List<Object>) data.get('remainingStops');
    System.assertEquals(
      7,
      remaining.size(),
      '4 drops, pickup, drop and the end'
    );
    System.assertEquals('Dispatcher', data.get('you'));
    Map<String, Object> first = (Map<String, Object>) remaining[0];
    System.assertEquals(1, ((List<Object>) first.get('visits')).size());
  }

  @IsTest
  static void reportDelayIsBufferedThenWritten() {
    Route__c r = route();
    AssistantTools.ToolResult res = run(
      'report_delay',
      new Map<String, Object>{ 'minutes' => 40, 'reason' => 'loading' },
      r.Id
    );
    System.assert(!res.isError, res.content);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Route_Event__c WHERE Type__c = 'Delay Reported'],
      'nothing written before the turn ends'
    );
    Assistant_Session__c s = new Assistant_Session__c(
      Record_Id__c = r.Id,
      Last_Activity__c = System.now()
    );
    insert s;
    System.runAs(RoutingTestData.self()) {
      RoutingAssistantTools.commitPending(s.Id);
      System.assertEquals(40, RouteReplanService.pendingDelayMinutes(r.Id));
    }
    Route_Event__c e = [
      SELECT Assistant_Session__c, Payload__c, Route__c
      FROM Route_Event__c
      WHERE Type__c = 'Delay Reported'
    ];
    System.assertEquals(s.Id, e.Assistant_Session__c);
    System.assertEquals(r.Id, e.Route__c);
    System.assert(
      run('report_delay', new Map<String, Object>{ 'minutes' => 0 }, r.Id)
        .isError
    );
  }

  @IsTest
  static void reoptimizeProposesThenAppliesTheSolverResult() {
    Route__c r = route();
    RoutingProviders.useForTest(new MockRoutingProvider());
    List<Waypoint__c> before = stops(r.Id);
    Id lockedId = before[2].Id;
    AssistantTools.ToolResult res = run(
      'reoptimize_remaining',
      new Map<String, Object>{
        'locked_waypoint_ids' => new List<Object>{ lockedId }
      },
      r.Id
    );
    System.assert(!res.isError, res.content);
    System.assertEquals('routing.reoptimize', res.proposal.get('action'));
    System.assertEquals(
      'Driver',
      res.proposal.get('approver'),
      'nothing late or unassigned'
    );
    Map<String, Object> diff = (Map<String, Object>) res.proposal.get('diff');
    System.assertEquals(6, ((List<String>) diff.get('after')).size());

    Map<String, Object> outcome = approve(res.proposal);
    System.assertEquals(true, outcome.get('success'), outcome.get('error'));
    List<Waypoint__c> after = stops(r.Id);
    System.assertEquals(
      'Start',
      after[0].Type__c,
      'the start is history and stays'
    );
    System.assertEquals(
      before[2].Job_Visits__r[0].Id,
      after[1].Job_Visits__r[0].Id,
      'the locked stop comes first'
    );
    System.assert(after[1].Locked__c);
    System.assertEquals('End', after[after.size() - 1].Type__c);
    System.assertEquals(
      2,
      [SELECT Revision__c FROM Route__c WHERE Id = :r.Id].Revision__c
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Route_Event__c
        WHERE Type__c = 'Reoptimized' AND Route__c = :r.Id
      ]
    );
  }

  @IsTest
  static void staleProposalsAreRefused() {
    Route__c r = route();
    RoutingProviders.useForTest(new MockRoutingProvider());
    AssistantTools.ToolResult res = run('reoptimize_remaining', null, r.Id);
    Waypoint__c next = stops(r.Id)[1];
    update new Waypoint__c(Id = next.Id, Status__c = 'Completed');
    Map<String, Object> outcome = approve(res.proposal);
    System.assertEquals(false, outcome.get('success'));
    System.assert(
      String.valueOf(outcome.get('error')).contains('changed since'),
      outcome.get('error')
    );
  }

  @IsTest
  static void updateWindowNeedsADispatcherForHardWindows() {
    Route__c r = route();
    Job_Visit__c v = [
      SELECT Id, Hard_Window__c
      FROM Job_Visit__c
      WHERE Waypoint__r.Route__c = :r.Id
      LIMIT 1
    ];
    Map<String, Object> input = new Map<String, Object>{
      'visit_id' => v.Id,
      'start' => RoutingDtos.iso(RoutingTestData.local(15, 0)),
      'end' => RoutingDtos.iso(RoutingTestData.local(17, 0)),
      'reason' => 'Customer asked for after 3'
    };
    AssistantTools.ToolResult res = run('update_window', input, r.Id);
    System.assertEquals('Dispatcher', res.proposal.get('approver'));
    System.assert(
      String.valueOf(res.proposal.get('reason')).contains('hard time window')
    );

    // The driver may not approve it.
    update new Contact(
      Id = r.Driver__c,
      Related_User__c = UserInfo.getUserId()
    );
    Map<String, Object> outcome = approve(res.proposal);
    System.assertEquals(false, outcome.get('success'));
    System.assert(String.valueOf(outcome.get('error')).contains('dispatcher'));

    // A dispatcher may.
    update new Contact(Id = r.Driver__c, Related_User__c = null);
    outcome = approve(res.proposal);
    System.assertEquals(true, outcome.get('success'), outcome.get('error'));
    System.assertEquals(
      RoutingTestData.local(15, 0),
      [SELECT Window_Start__c FROM Job_Visit__c WHERE Id = :v.Id]
      .Window_Start__c
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Route_Event__c WHERE Type__c = 'Window Changed']
    );
    input.put('end', input.get('start'));
    System.assert(run('update_window', input, r.Id).isError);
  }

  @IsTest
  static void skipStopPutsTheJobBackToReady() {
    Route__c r = route();
    Waypoint__c stop = stops(r.Id)[1];
    AssistantTools.ToolResult res = run(
      'skip_stop',
      new Map<String, Object>{
        'waypoint_id' => stop.Id,
        'reason' => 'Gate locked'
      },
      r.Id
    );
    System.assertEquals('Dispatcher', res.proposal.get('approver'));
    Map<String, Object> outcome = approve(res.proposal);
    System.assertEquals(true, outcome.get('success'), outcome.get('error'));
    System.assertEquals(
      'Skipped',
      [SELECT Status__c FROM Waypoint__c WHERE Id = :stop.Id].Status__c
    );
    Job_Visit__c v = [
      SELECT Waypoint__c, Route_Job__r.Status__c, Route_Job__r.Planned_Route__c
      FROM Job_Visit__c
      WHERE Id = :stop.Job_Visits__r[0].Id
    ];
    System.assertEquals(null, v.Waypoint__c);
    System.assertEquals('Ready', v.Route_Job__r.Status__c);
    System.assertEquals(null, v.Route_Job__r.Planned_Route__c);
    System.assert(
      run(
          'skip_stop',
          new Map<String, Object>{ 'waypoint_id' => stop.Id, 'reason' => 'x' },
          r.Id
        )
        .isError,
      'already skipped'
    );
  }

  @IsTest
  static void addWaypointInsertsABreakAndShiftsLaterStops() {
    Route__c r = route();
    List<Waypoint__c> before = stops(r.Id);
    AssistantTools.ToolResult res = run(
      'add_waypoint',
      new Map<String, Object>{
        'type' => 'Break',
        'minutes' => 20,
        'reason' => 'Lunch'
      },
      r.Id
    );
    System.assertEquals('Driver', res.proposal.get('approver'));
    Map<String, Object> outcome = approve(res.proposal);
    System.assertEquals(true, outcome.get('success'), outcome.get('error'));
    List<Waypoint__c> after = stops(r.Id);
    System.assertEquals(before.size() + 1, after.size());
    System.assertEquals('Break', after[2].Type__c, 'right after the next stop');
    System.assertEquals(before[2].Id, after[3].Id);

    System.assertEquals(
      'Dispatcher',
      run(
          'add_waypoint',
          new Map<String, Object>{ 'type' => 'Refuel', 'minutes' => 10 },
          r.Id
        )
        .proposal.get('approver')
    );
    System.assert(
      run(
          'add_waypoint',
          new Map<String, Object>{ 'type' => 'Picnic', 'minutes' => 10 },
          r.Id
        )
        .isError
    );
    System.assert(
      run(
          'add_waypoint',
          new Map<String, Object>{ 'type' => 'Break', 'minutes' => 0 },
          r.Id
        )
        .isError
    );
  }

  @IsTest
  static void whatIfComparesWithoutSaving() {
    Route__c r = route();
    RoutingProviders.useForTest(new MockRoutingProvider());
    Integer routesBefore = [SELECT COUNT() FROM Route__c];
    AssistantTools.ToolResult res = run(
      'what_if',
      new Map<String, Object>{
        'exclude_route_ids' => new List<Object>{ r.Id },
        'extra_delay_minutes' => 30
      },
      r.Id
    );
    System.assert(!res.isError, res.content);
    Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(
      res.content
    );
    System.assertEquals(false, data.get('saved'));
    System.assertEquals(
      1,
      ((Map<String, Object>) data.get('before')).get('routes')
    );
    System.assertEquals(routesBefore, [SELECT COUNT() FROM Route__c]);

    update new Contact(
      Id = r.Driver__c,
      Related_User__c = UserInfo.getUserId()
    );
    System.assert(
      run('what_if', null, r.Id).isError,
      'drivers cannot run what-ifs'
    );
  }

  @IsTest
  static void handoffMovesAVisitToAnotherRoute() {
    Route__c source = route();
    Fleet_Asset__c ev = RoutingTestData.assetsByName().get('RT-VAN-2 EV');
    Route__c target = new Route__c(
      Route_Plan__c = source.Route_Plan__c,
      Name = 'EV · Yossi',
      Fleet_Asset__c = ev.Id,
      Driver__c = ev.Driver__c,
      Status__c = 'Planned',
      Start_Location__Latitude__s = RoutingTestData.DEPOT_LAT,
      Start_Location__Longitude__s = RoutingTestData.DEPOT_LON,
      End_Location__Latitude__s = RoutingTestData.DEPOT_LAT,
      End_Location__Longitude__s = RoutingTestData.DEPOT_LON,
      Shift_Start__c = RoutingTestData.local(7, 0),
      Shift_End__c = RoutingTestData.local(17, 0),
      Revision__c = 1
    );
    insert target;
    insert new List<Waypoint__c>{
      new Waypoint__c(
        Route__c = target.Id,
        Sequence__c = 1,
        Type__c = 'Start',
        Status__c = 'Planned',
        Location__Latitude__s = RoutingTestData.DEPOT_LAT,
        Location__Longitude__s = RoutingTestData.DEPOT_LON
      ),
      new Waypoint__c(
        Route__c = target.Id,
        Sequence__c = 2,
        Type__c = 'End',
        Status__c = 'Planned',
        Location__Latitude__s = RoutingTestData.DEPOT_LAT,
        Location__Longitude__s = RoutingTestData.DEPOT_LON
      )
    };
    RoutingProviders.useForTest(new MockRoutingProvider());
    Waypoint__c moving = stops(source.Id)[1];
    Id visitId = moving.Job_Visits__r[0].Id;

    AssistantTools.ToolResult res = run(
      'propose_handoff',
      new Map<String, Object>{
        'visit_id' => visitId,
        'to_route_id' => target.Id
      },
      source.Id
    );
    System.assert(!res.isError, res.content);
    System.assertEquals('Dispatcher', res.proposal.get('approver'));
    Map<String, Object> outcome = approve(res.proposal);
    System.assertEquals(true, outcome.get('success'), outcome.get('error'));
    Job_Visit__c v = [
      SELECT Waypoint__r.Route__c, Route_Job__r.Planned_Route__c
      FROM Job_Visit__c
      WHERE Id = :visitId
    ];
    System.assertEquals(target.Id, v.Waypoint__r.Route__c);
    System.assertEquals(target.Id, v.Route_Job__r.Planned_Route__c);
    System.assertEquals(
      2,
      [SELECT COUNT() FROM Route_Event__c WHERE Type__c = 'Handoff Approved']
    );

    System.assert(
      run(
          'propose_handoff',
          new Map<String, Object>{
            'visit_id' => visitId,
            'to_route_id' => source.Id
          },
          source.Id
        )
        .isError,
      'the visit is no longer on the source route'
    );
  }

  @IsTest
  static void handoffToAVanInTheShopIsRefused() {
    Route__c source = route();
    Fleet_Asset__c shop = RoutingTestData.assetsByName()
      .get('RT-VAN-3 IN SHOP');
    Route__c target = new Route__c(
      Route_Plan__c = source.Route_Plan__c,
      Name = 'Shop van',
      Fleet_Asset__c = shop.Id,
      Status__c = 'Planned'
    );
    insert target;
    Id visitId = stops(source.Id)[1].Job_Visits__r[0].Id;
    AssistantTools.ToolResult res = run(
      'propose_handoff',
      new Map<String, Object>{
        'visit_id' => visitId,
        'to_route_id' => target.Id
      },
      source.Id
    );
    System.assert(res.isError);
    System.assert(res.content.contains('in-shop'), res.content);
  }

  @IsTest
  static void rejectionsAndErrors() {
    Route__c r = route();
    AssistantTools.ToolResult res = run(
      'add_waypoint',
      new Map<String, Object>{ 'type' => 'Break', 'minutes' => 15 },
      r.Id
    );
    System.runAs(RoutingTestData.self()) {
      RoutingAssistantTools.logRejected(res.proposal, null, 'Not now');
      RoutingAssistantTools.logRejected(
        new Map<String, Object>{ 'recordId' => 'bad' },
        null,
        null
      );
    }
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Route_Event__c WHERE Type__c = 'Proposal Rejected']
    );
    System.assert(RoutingAssistantTools.isRoutingProposal(res.proposal));
    System.assert(
      !RoutingAssistantTools.isRoutingProposal(
        new Map<String, Object>{ 'action' => 'update' }
      )
    );

    System.assert(run('nope', null, r.Id).isError);
    System.assert(
      run(
          'get_route',
          new Map<String, Object>{ 'route_id' => r.Route_Plan__c },
          r.Id
        )
        .isError
    );
    System.assert(
      run('get_route', new Map<String, Object>{ 'route_id' => 'xyz' }, r.Id)
        .isError
    );
    System.assert(run('get_route', null, null).isError, 'no route in context');
    System.assert(
      run(
          'update_window',
          new Map<String, Object>{
            'visit_id' => r.Id,
            'start' => 'x',
            'end' => 'y'
          },
          r.Id
        )
        .isError
    );
    Map<String, Object> bad = approve(
      new Map<String, Object>{
        'action' => 'routing.unknown',
        'recordId' => r.Id,
        'routing' => new Map<String, Object>()
      }
    );
    System.assertEquals(false, bad.get('success'));
  }
}
