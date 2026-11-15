@IsTest
private class RoutePlanServiceTest {
  @TestSetup
  static void makeData() {
    RoutingTestData.grantAccess();
    RoutingTestData.scenario(4);
  }

  private static Id planId() {
    return [SELECT Id FROM Route_Plan__c LIMIT 1].Id;
  }

  // ---------------------------------------------------------------------------------------------
  // buildRequest
  // ---------------------------------------------------------------------------------------------

  @IsTest
  static void buildRequestPicksEligibleVehiclesAndPlannableJobs() {
    RoutePlanService.PlanContext ctx;
    System.runAs(RoutingTestData.self()) {
      ctx = RoutePlanService.buildRequest(planId());
    }
    Map<String, Fleet_Asset__c> vans = RoutingTestData.assetsByName();
    RoutingDtos.OptimizeRequest req = ctx.request;

    Set<String> vehicleIds = new Set<String>();
    for (RoutingDtos.Vehicle v : req.vehicles) {
      vehicleIds.add(v.id);
    }
    System.assertEquals(
      new Set<String>{ vans.get('RT-VAN-1').Id, vans.get('RT-VAN-2 EV').Id },
      vehicleIds,
      'the in-shop van and the van with an expired driver are left out'
    );
    System.assert(
      req.excludedVehicles.get(vans.get('RT-VAN-3 IN SHOP').Id)
        .contains('in-shop')
    );
    System.assert(
      req.excludedVehicles.get(vans.get('RT-VAN-4 EXPIRED').Id)
        .contains('licence expired')
    );

    System.assertEquals(5, req.jobs.size(), '4 drops and the refrigerated job');
    System.assertEquals(
      1,
      req.shipments.size(),
      'the relocation is a pickup -> drop shipment'
    );
    System.assertEquals(
      1,
      req.skippedJobs.size(),
      'the job whose visit has no location'
    );
    System.assertEquals('min_duration', req.objective);
  }

  @IsTest
  static void vehiclesGetShiftCapacitySkillsAndEvCharge() {
    RoutePlanService.PlanContext ctx;
    System.runAs(RoutingTestData.self()) {
      ctx = RoutePlanService.buildRequest(planId());
    }
    Map<String, Fleet_Asset__c> vans = RoutingTestData.assetsByName();
    RoutingDtos.Vehicle van1;
    RoutingDtos.Vehicle ev;
    for (RoutingDtos.Vehicle v : ctx.request.vehicles) {
      if (v.id == vans.get('RT-VAN-1').Id) {
        van1 = v;
      } else {
        ev = v;
      }
    }
    System.assertEquals(
      RoutingTestData.local(7, 0),
      van1.shiftStart,
      'default shift starts 07:00 depot time'
    );
    System.assertEquals(RoutingTestData.local(17, 0), van1.shiftEnd);
    System.assertEquals(
      new List<Integer>{ 800, 6000, 4 },
      van1.capacity,
      'm3 are scaled to litres'
    );
    System.assertEquals(new List<String>{ 'Lift Gate' }, van1.skills);
    System.assert(van1.breaks.isEmpty());
    System.assertEquals(
      RoutingTestData.DEPOT_LAT,
      Decimal.valueOf(van1.startLocation.getLatitude()).setScale(4)
    );

    System.assert(
      ev.skills.contains('Hazmat'),
      'valid driver qualifications are skills'
    );
    System.assertEquals(1, ev.breaks.size(), 'EVs get a charge stop');
    System.assertEquals('charge', ev.breaks[0].id);
    System.assertEquals(1800, ev.breaks[0].serviceSeconds);
    System.assertEquals(
      RoutingTestData.local(11, 30),
      ev.breaks[0].windows[0].startTime
    );
  }

  @IsTest
  static void jobsCarryWindowsLoadsAndSkills() {
    RoutePlanService.PlanContext ctx;
    System.runAs(RoutingTestData.self()) {
      ctx = RoutePlanService.buildRequest(planId());
    }
    RoutingDtos.Job drop = ctx.request.jobs[0];
    System.assertEquals(360, drop.serviceSeconds);
    System.assertEquals(new List<Integer>{ 25, 200, 0 }, drop.delivery);
    System.assertEquals(new List<Integer>{ 0, 0, 0 }, drop.pickup);
    System.assertEquals(RoutingTestData.local(8, 0), drop.windows[0].startTime);
    System.assertEquals(
      RoutingTestData.local(16, 0),
      drop.windows[0].endTime,
      'hard windows are sent as is'
    );
    System.assertEquals(10, drop.priority);

    Boolean sawRefrigerated = false;
    for (RoutingDtos.Job j : ctx.request.jobs) {
      if (j.skills.contains('Refrigerated')) {
        sawRefrigerated = true;
      }
    }
    System.assert(sawRefrigerated);

    RoutingDtos.Shipment s = ctx.request.shipments[0];
    System.assertEquals(new List<Integer>{ 25, 200, 0 }, s.amount);
    System.assert(s.delivery.windows.isEmpty());

    Map<String, Object> wire = ctx.request.toMap();
    System.assertEquals(2, ((List<Object>) wire.get('vehicles')).size());
    String json = ctx.request.toJson();
    System.assert(
      json.contains('"shift_start"') && json.contains('"service_seconds"'),
      json.abbreviate(300)
    );
  }

  @IsTest
  static void softWindowsGetGraceAndOpenEndedWindowsAreFilled() {
    Datetime st = Datetime.newInstanceGmt(2026, 11, 4, 6, 0, 0);
    Datetime en = st.addHours(2);
    Datetime dayStart = Datetime.newInstanceGmt(2026, 11, 3, 22, 0, 0);
    List<RoutingDtos.TimeWindow> soft = RoutePlanService.windows(
      new Job_Visit__c(
        Window_Start__c = st,
        Window_End__c = en,
        Hard_Window__c = false
      ),
      dayStart
    );
    System.assertEquals(
      en.addMinutes(RoutePlanService.SOFT_WINDOW_GRACE_MINUTES),
      soft[0].endTime
    );
    List<RoutingDtos.TimeWindow> endOnly = RoutePlanService.windows(
      new Job_Visit__c(Window_End__c = en, Hard_Window__c = true),
      dayStart
    );
    System.assertEquals(dayStart, endOnly[0].startTime);
    List<RoutingDtos.TimeWindow> startOnly = RoutePlanService.windows(
      new Job_Visit__c(Window_Start__c = st, Hard_Window__c = true),
      dayStart
    );
    System.assertEquals(st.addHours(24), startOnly[0].endTime);
    System.assert(
      RoutePlanService.windows(new Job_Visit__c(), dayStart).isEmpty()
    );
  }

  @IsTest
  static void shiftComesFromTheSchedule() {
    Fleet_Asset__c van1 = RoutingTestData.assetsByName().get('RT-VAN-1');
    Fleet_Schedule__c schedule = new Fleet_Schedule__c(Name = 'Early shift');
    insert schedule;
    insert new Schedule_Window__c(
      Fleet_Schedule__c = schedule.Id,
      Day_OfWeek__c = RoutePlanService.weekday(RoutingTestData.planDate()),
      Start_Time__c = Time.newInstance(6, 0, 0, 0),
      End_Time__c = Time.newInstance(14, 0, 0, 0),
      Type__c = 'Available'
    );
    insert new Schedule_Assignment__c(
      Fleet_Schedule__c = schedule.Id,
      Fleet_Asset__c = van1.Id
    );

    RoutePlanService.PlanContext ctx;
    System.runAs(RoutingTestData.self()) {
      ctx = RoutePlanService.buildRequest(planId());
    }
    for (RoutingDtos.Vehicle v : ctx.request.vehicles) {
      if (v.id == van1.Id) {
        System.assertEquals(RoutingTestData.local(6, 0), v.shiftStart);
        System.assertEquals(RoutingTestData.local(14, 0), v.shiftEnd);
      }
    }
  }

  @IsTest
  static void helpers() {
    System.assertEquals(
      'Sunday',
      RoutePlanService.weekday(Date.newInstance(2026, 11, 1))
    );
    System.assertEquals(
      'Wednesday',
      RoutePlanService.weekday(Date.newInstance(2026, 11, 4))
    );
    // Israel is UTC+2 in November.
    System.assertEquals(
      Datetime.newInstanceGmt(2026, 11, 4, 5, 0, 0),
      RoutePlanService.localToGmt(
        Date.newInstance(2026, 11, 4),
        Time.newInstance(7, 0, 0, 0),
        RoutingTestData.tz()
      )
    );
    System.assertEquals(
      'min_distance',
      RoutePlanService.objective('Min Distance')
    );
    System.assertEquals(
      'min_vehicles',
      RoutePlanService.objective('Min Vehicles')
    );
    System.assertEquals('balanced', RoutePlanService.objective('Balanced'));
    System.assertEquals('min_duration', RoutePlanService.objective(null));
    System.assertEquals(
      new List<String>{ 'A', 'B' },
      RoutePlanService.splitMulti('A; B;')
    );
    System.assertEquals(2, RoutePlanService.minutes(90));
    System.assertEquals(
      null,
      RoutePlanService.capacity(
        new Fleet_Asset__c(),
        RoutePlanService.capacityDimensions()
      ),
      'no recorded capacity means unlimited'
    );
  }

  @IsTest
  static void buildRequestNeedsDateDepotAndLocation() {
    Route_Plan__c plan = [
      SELECT Id, Depot_Branch__c
      FROM Route_Plan__c
      LIMIT 1
    ];
    update new Fleet_Branch__c(
      Id = plan.Depot_Branch__c,
      Location__Latitude__s = null,
      Location__Longitude__s = null
    );
    System.runAs(RoutingTestData.self()) {
      try {
        RoutePlanService.buildRequest(plan.Id);
        System.assert(false, 'expected an exception');
      } catch (RoutingProviders.RoutingException e) {
        System.assert(
          e.getMessage().contains('has no location'),
          e.getMessage()
        );
      }
      try {
        RoutePlanService.loadPlan(RoutingTestData.self().Id);
        System.assert(false, 'expected an exception');
      } catch (Exception e) {
        System.assert(e.getMessage().contains('not found'), e.getMessage());
      }
    }
  }

  // ---------------------------------------------------------------------------------------------
  // applyResult
  // ---------------------------------------------------------------------------------------------

  @IsTest
  static void applyResultWritesRoutesWaypointsAndLinksVisits() {
    Id pid = planId();
    System.runAs(RoutingTestData.self()) {
      RoutePlanService.PlanContext ctx = RoutePlanService.buildRequest(pid);
      RoutingDtos.OptimizeResult result = RoutingDtos.parseOptimize(
        RoutingTestData.answer(ctx.request.toJson())
      );
      Test.startTest();
      RoutePlanService.applyResult(ctx, result);
      Test.stopTest();
    }

    Route_Plan__c plan = [
      SELECT
        Status__c,
        Revision__c,
        Unassigned_Count__c,
        Total_Distance_Km__c,
        Solver_Summary__c,
        Last_Optimized_At__c
      FROM Route_Plan__c
      WHERE Id = :pid
    ];
    System.assertEquals('Optimized', plan.Status__c);
    System.assertEquals(1, plan.Revision__c);
    System.assertEquals(
      2,
      plan.Unassigned_Count__c,
      'refrigerated (skills) + no location (skipped)'
    );
    System.assert(plan.Total_Distance_Km__c > 0);
    System.assert(
      plan.Solver_Summary__c.contains('in-shop'),
      'excluded vehicles are recorded'
    );

    List<Route__c> routes = [
      SELECT
        Id,
        Name,
        Fleet_Asset__r.Name,
        Driver__c,
        Status__c,
        Revision__c,
        Planned_Start__c,
        Geometry__c,
        (
          SELECT Sequence__c, Type__c, Solver_Step_Id__c
          FROM Waypoints__r
          ORDER BY Sequence__c
        )
      FROM Route__c
      WHERE Route_Plan__c = :pid
    ];
    System.assertEquals(1, routes.size());
    Route__c r = routes[0];
    System.assertEquals('RT-VAN-1', r.Fleet_Asset__r.Name);
    System.assert(r.Name.contains('Dana'), r.Name);
    System.assertEquals('Planned', r.Status__c);
    System.assertNotEquals(null, r.Geometry__c);
    System.assertEquals('Start', r.Waypoints__r[0].Type__c);
    System.assertEquals(
      'End',
      r.Waypoints__r[r.Waypoints__r.size() - 1].Type__c
    );
    System.assertEquals(
      8,
      r.Waypoints__r.size(),
      'start, 4 drops, pickup, drop, end'
    );

    Integer linked = [
      SELECT COUNT()
      FROM Job_Visit__c
      WHERE Waypoint__c != NULL
    ];
    System.assertEquals(6, linked, '4 drops plus both ends of the relocation');
    for (Route_Job__c j : [
      SELECT
        Status__c,
        Planned_Route__c,
        Unassigned_Reason__c,
        Required_Skills__c
      FROM Route_Job__c
    ]) {
      if (j.Required_Skills__c == 'Refrigerated') {
        System.assertEquals('Ready', j.Status__c);
        System.assert(
          j.Unassigned_Reason__c.startsWith('skills:'),
          j.Unassigned_Reason__c
        );
      }
    }
    System.assertEquals(
      4 + 1,
      [
        SELECT COUNT()
        FROM Route_Job__c
        WHERE Status__c = 'Planned' AND Planned_Route__c = :r.Id
      ]
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Route_Job__c
        WHERE Unassigned_Reason__c LIKE 'skipped:%'
      ]
    );
    Route_Event__c ev = [
      SELECT Type__c, Actor_Type__c, Payload__c
      FROM Route_Event__c
      WHERE Route_Plan__c = :pid
    ];
    System.assertEquals('Optimized', ev.Type__c);
    System.assert(ev.Payload__c.contains('"revision":1'), ev.Payload__c);
  }

  @IsTest
  static void reoptimizingReplacesRoutesAndBumpsRevision() {
    Id pid = planId();
    System.runAs(RoutingTestData.self()) {
      for (Integer i = 0; i < 2; i++) {
        RoutePlanService.PlanContext ctx = RoutePlanService.buildRequest(pid);
        RoutePlanService.applyResult(
          ctx,
          RoutingDtos.parseOptimize(
            RoutingTestData.answer(ctx.request.toJson())
          )
        );
      }
    }
    System.assertEquals(
      2,
      [SELECT Revision__c FROM Route_Plan__c WHERE Id = :pid].Revision__c
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Route__c WHERE Route_Plan__c = :pid]
    );
    System.assertEquals(
      2,
      [SELECT COUNT() FROM Route_Event__c WHERE Type__c = 'Optimized']
    );
  }

  @IsTest
  static void stopsAtTheSamePlaceShareOneWaypoint() {
    RoutingDtos.Route r = new RoutingDtos.Route();
    Location here = Location.newInstance(31.25, 34.79);
    r.steps.add(step('start', null, here));
    r.steps.add(step('job', 'a', Location.newInstance(31.26, 34.8)));
    r.steps.add(step('job', 'b', Location.newInstance(31.26, 34.8)));
    r.steps.add(step('break', 'charge', null));
    r.steps.add(step('break', 'lunch', null));
    r.steps.add(step('end', null, here));
    RoutePlanService.WaypointBuild built = new RoutePlanService.WaypointBuild();
    RoutePlanService.buildWaypoints(new Route__c(), r, null, built, 1);
    System.assertEquals(5, built.waypoints.size());
    System.assertEquals(
      new List<String>{ 'a', 'b' },
      built.visitsByIndex.get(1)
    );
    System.assertEquals(12, built.waypoints[1].Service_Minutes__c);
    System.assertEquals('Charge', built.waypoints[2].Type__c);
    System.assertEquals('Break', built.waypoints[3].Type__c);
    System.assertEquals(5, built.waypoints[4].Sequence__c);
  }

  private static RoutingDtos.Step step(String type, String id, Location l) {
    RoutingDtos.Step s = new RoutingDtos.Step();
    s.stepType = type;
    s.id = id;
    s.location = l;
    s.arrival = Datetime.now();
    s.departure = Datetime.now();
    s.serviceSeconds = type == 'job' ? 360 : 0;
    return s;
  }

  // ---------------------------------------------------------------------------------------------
  // startOptimization, failure and publish
  // ---------------------------------------------------------------------------------------------

  @IsTest
  static void startOptimizationQueuesTheJob() {
    Id pid = planId();
    RoutingTestData.EchoService service = new RoutingTestData.EchoService();
    Test.setMock(HttpCalloutMock.class, service);
    System.runAs(RoutingTestData.self()) {
      Test.startTest();
      Id jobId = RoutePlanService.startOptimization(pid);
      System.assertNotEquals(null, jobId);
      System.assertEquals(
        'Optimizing',
        [SELECT Status__c FROM Route_Plan__c WHERE Id = :pid].Status__c
      );
      Test.stopTest();
    }
    System.assertEquals(1, service.calls);
    System.assert(
      service.lastEndpoint.startsWith('callout:'),
      service.lastEndpoint
    );
    System.assert(
      service.lastEndpoint.endsWith('FleetForce_Routing/v1/optimize'),
      service.lastEndpoint
    );
    System.assertEquals(
      'Optimized',
      [SELECT Status__c FROM Route_Plan__c WHERE Id = :pid].Status__c
    );
  }

  @IsTest
  static void publishedPlansCannotBeReoptimizedWhole() {
    Id pid = planId();
    update new Route_Plan__c(Id = pid, Status__c = 'Published');
    System.runAs(RoutingTestData.self()) {
      try {
        RoutePlanService.startOptimization(pid);
        System.assert(false, 'expected an exception');
      } catch (RoutingProviders.RoutingException e) {
        System.assert(
          e.getMessage().contains('Re-optimize individual routes'),
          e.getMessage()
        );
      }
    }
  }

  @IsTest
  static void recordFailureKeepsTheErrorAndLogsIt() {
    Id pid = planId();
    System.runAs(RoutingTestData.self()) {
      RoutePlanService.recordFailure(pid, 'boom');
    }
    Route_Plan__c plan = [
      SELECT Status__c, Error__c
      FROM Route_Plan__c
      WHERE Id = :pid
    ];
    System.assertEquals('Draft', plan.Status__c);
    System.assertEquals('boom', plan.Error__c);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Route_Event__c WHERE Type__c = 'Optimization Failed']
    );
  }

  @IsTest
  static void publishCreatesAllocationsAndChecksConflicts() {
    Id pid = planId();
    System.runAs(RoutingTestData.self()) {
      RoutePlanService.PlanContext ctx = RoutePlanService.buildRequest(pid);
      RoutePlanService.applyResult(
        ctx,
        RoutingDtos.parseOptimize(RoutingTestData.answer(ctx.request.toJson()))
      );
      try {
        RoutePlanService.publishPlan(pid);
      } catch (Exception e) {
        System.assert(false, 'publish failed: ' + e.getMessage());
      }
    }
    Route__c r = [
      SELECT
        Status__c,
        Allocation__c,
        Allocation__r.Status__c,
        Allocation__r.Scheduled_Start__c,
        Planned_Start__c
      FROM Route__c
    ];
    System.assertEquals('Published', r.Status__c);
    System.assertEquals('Confirmed', r.Allocation__r.Status__c);
    System.assertEquals(r.Planned_Start__c, r.Allocation__r.Scheduled_Start__c);
    System.assertEquals(
      'Published',
      [SELECT Status__c FROM Route_Plan__c WHERE Id = :pid].Status__c
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Route_Event__c WHERE Type__c = 'Published']
    );

    System.runAs(RoutingTestData.self()) {
      try {
        RoutePlanService.publishPlan(pid);
        System.assert(false, 'expected an exception');
      } catch (RoutingProviders.RoutingException e) {
        System.assert(
          e.getMessage().contains('Only an Optimized plan'),
          e.getMessage()
        );
      }
    }
  }

  @IsTest
  static void publishRefusesOverlappingAllocations() {
    Id pid = planId();
    Fleet_Asset__c van1 = RoutingTestData.assetsByName().get('RT-VAN-1');
    insert new Allocation__c(
      Name = 'Motorpool booking',
      Fleet_Asset__c = van1.Id,
      Status__c = 'Confirmed',
      Scheduled_Start__c = RoutingTestData.local(0, 0),
      Scheduled_End__c = RoutingTestData.local(23, 0)
    );
    System.runAs(RoutingTestData.self()) {
      RoutePlanService.PlanContext ctx = RoutePlanService.buildRequest(pid);
      RoutePlanService.applyResult(
        ctx,
        RoutingDtos.parseOptimize(RoutingTestData.answer(ctx.request.toJson()))
      );
      try {
        RoutePlanService.publishPlan(pid);
        System.assert(false, 'expected an exception');
      } catch (RoutingProviders.RoutingException e) {
        System.assert(
          e.getMessage().contains('overlaps allocation'),
          e.getMessage()
        );
      }
    }
  }
}
