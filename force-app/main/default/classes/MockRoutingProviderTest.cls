@IsTest
private class MockRoutingProviderTest {
  static final Datetime SHIFT = Datetime.newInstanceGmt(2026, 11, 4, 5, 0, 0);
  static final Location DEPOT = Location.newInstance(31.2518, 34.7913);

  private static RoutingDtos.Vehicle vehicle(String id, List<String> skills) {
    RoutingDtos.Vehicle v = new RoutingDtos.Vehicle();
    v.id = id;
    v.startLocation = DEPOT;
    v.endLocation = DEPOT;
    v.shiftStart = SHIFT;
    v.shiftEnd = SHIFT.addHours(10);
    v.capacity = new List<Integer>{ 100, 0, 0 };
    v.skills = skills;
    return v;
  }

  private static RoutingDtos.Job job(String id, Integer i, Integer kg) {
    RoutingDtos.Job j = new RoutingDtos.Job();
    j.id = id;
    j.location = Location.newInstance(31.255 + i * 0.002, 34.795);
    j.serviceSeconds = 300;
    j.delivery = new List<Integer>{ kg, 0, 0 };
    return j;
  }

  @IsTest
  static void plansGreedilyAndExplainsWhatDoesNotFit() {
    RoutingDtos.OptimizeRequest req = new RoutingDtos.OptimizeRequest();
    RoutingDtos.Vehicle v = vehicle('van', new List<String>{ 'Lift Gate' });
    RoutingDtos.BreakSpec b = new RoutingDtos.BreakSpec();
    b.id = 'charge';
    b.serviceSeconds = 1800;
    b.windows.add(new RoutingDtos.TimeWindow(SHIFT, SHIFT.addHours(3)));
    v.breaks.add(b);
    req.vehicles.add(v);
    req.jobs.add(job('a', 1, 30));
    req.jobs.add(job('b', 2, 30));
    RoutingDtos.Job windowed = job('w', 3, 10);
    windowed.windows.add(
      new RoutingDtos.TimeWindow(SHIFT.addHours(2), SHIFT.addHours(3))
    );
    req.jobs.add(windowed);
    RoutingDtos.Job cold = job('cold', 4, 10);
    cold.skills.add('Refrigerated');
    req.jobs.add(cold);
    req.jobs.add(job('heavy', 5, 500));
    RoutingDtos.Shipment s = new RoutingDtos.Shipment();
    s.id = 'reloc';
    s.pickup = new RoutingDtos.ShipmentStep();
    s.pickup.id = 'p';
    s.pickup.location = Location.newInstance(31.27, 34.8);
    s.delivery = new RoutingDtos.ShipmentStep();
    s.delivery.id = 'd';
    s.delivery.location = Location.newInstance(31.28, 34.8);
    s.amount = new List<Integer>{ 10, 0, 0 };
    req.shipments.add(s);
    req.fixed.add(new RoutingDtos.FixedSteps('van', new List<String>{ 'b' }));

    MockRoutingProvider mock = new MockRoutingProvider();
    RoutingDtos.OptimizeResult r = mock.optimize(req);
    System.assertEquals(1, mock.optimizeCalls);
    System.assertEquals(1, r.routes.size());
    List<String> order = new List<String>();
    Boolean sawBreak = false;
    for (RoutingDtos.Step st : r.routes[0].steps) {
      if (st.isTask()) {
        order.add(st.id);
      }
      if (st.stepType == 'break') {
        sawBreak = true;
      }
    }
    System.assertEquals('b', order[0], 'locked stop first');
    System.assert(r.routes[0].steps[1].locked);
    System.assert(order.indexOf('p') < order.indexOf('d'));
    System.assert(sawBreak);
    Map<String, String> reasons = new Map<String, String>();
    for (RoutingDtos.Unassigned u : r.unassigned) {
      reasons.put(u.id, u.reason);
    }
    System.assertEquals('skills', reasons.get('cold'));
    System.assertEquals('capacity', reasons.get('heavy'));
    System.assertEquals(
      5,
      r.summary.assigned,
      'a, b, w and both shipment ends'
    );
    System.assertEquals('mock', r.summary.matrixSource);
  }

  @IsTest
  static void cannedResponseAndHelpers() {
    MockRoutingProvider mock = new MockRoutingProvider();
    RoutingDtos.OptimizeRequest req = new RoutingDtos.OptimizeRequest();
    req.vehicles.add(vehicle('van', new List<String>()));
    req.jobs.add(job('a', 1, 1));
    mock.cannedOptimize = RoutingTestData.answer(req.toJson());
    System.assertEquals('a', mock.optimize(req).routes[0].steps[1].id);

    RoutingDtos.MatrixResult m = mock.matrix(
      new List<Location>{ DEPOT, Location.newInstance(31.26, 34.8) }
    );
    System.assertEquals(0, m.durations[0][0]);
    System.assert(m.distances[0][1] > 1000);
    RoutingDtos.RouteResult route = mock.route(
      new List<RoutingDtos.RouteWaypoint>{
        new RoutingDtos.RouteWaypoint('x', DEPOT),
        new RoutingDtos.RouteWaypoint('y', Location.newInstance(31.26, 34.8))
      },
      SHIFT
    );
    System.assertEquals(m.distances[0][1], route.distanceM);
    System.assert(route.legs[0].arrival > SHIFT);
    System.assertEquals(0, MockRoutingProvider.distanceM(null, DEPOT));
  }

  @IsTest
  static void lateLockedStopReportsLateness() {
    RoutingDtos.OptimizeRequest req = new RoutingDtos.OptimizeRequest();
    req.vehicles.add(vehicle('van', new List<String>()));
    RoutingDtos.Job missed = job('missed', 1, 1);
    missed.windows.add(
      new RoutingDtos.TimeWindow(SHIFT.addHours(-3), SHIFT.addHours(-2))
    );
    req.jobs.add(missed);
    req.fixed.add(
      new RoutingDtos.FixedSteps('van', new List<String>{ 'missed' })
    );
    RoutingDtos.OptimizeResult r = new MockRoutingProvider().optimize(req);
    System.assert(r.routes[0].steps[1].lateSeconds > 7000);
  }
}
