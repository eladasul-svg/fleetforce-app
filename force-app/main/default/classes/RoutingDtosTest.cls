@IsTest
private class RoutingDtosTest {
  @IsTest
  static void requestUsesTheWireNames() {
    RoutingDtos.OptimizeRequest req = new RoutingDtos.OptimizeRequest();
    RoutingDtos.Vehicle v = new RoutingDtos.Vehicle();
    v.id = 'van';
    v.startLocation = Location.newInstance(31.25, 34.79);
    v.shiftStart = Datetime.newInstanceGmt(2026, 11, 4, 5, 0, 0);
    v.shiftEnd = v.shiftStart.addHours(8);
    v.capacity = new List<Integer>{ 800, 0, 0 };
    RoutingDtos.BreakSpec b = new RoutingDtos.BreakSpec();
    b.id = 'charge';
    b.windows.add(new RoutingDtos.TimeWindow(v.shiftStart, v.shiftEnd));
    v.breaks.add(b);
    req.vehicles.add(v);
    RoutingDtos.Shipment s = new RoutingDtos.Shipment();
    s.id = 'reloc';
    s.pickup = new RoutingDtos.ShipmentStep();
    s.pickup.id = 'p';
    s.pickup.location = Location.newInstance(31.26, 34.8);
    s.delivery = new RoutingDtos.ShipmentStep();
    s.delivery.id = 'd';
    s.delivery.location = Location.newInstance(31.27, 34.81);
    req.shipments.add(s);
    req.fixed.add(new RoutingDtos.FixedSteps('van', new List<String>{ 'p' }));

    Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(
      req.toJson()
    );
    Map<String, Object> vm = (Map<String, Object>) ((List<Object>) m.get(
      'vehicles'
    ))[0];
    System.assert(!vm.containsKey('end'), 'open trip: no end');
    System.assertEquals(new List<Object>{ 800, 0, 0 }, vm.get('capacity'));
    Map<String, Object> bm = (Map<String, Object>) ((List<Object>) vm.get(
      'breaks'
    ))[0];
    System.assertEquals(
      '2026-11-04T05:00:00Z',
      ((Map<String, Object>) ((List<Object>) bm.get('time_windows'))[0])
        .get('start')
    );
    Map<String, Object> options = (Map<String, Object>) m.get('options');
    Map<String, Object> fx = (Map<String, Object>) ((List<Object>) options.get(
      'fixed'
    ))[0];
    System.assertEquals('van', fx.get('vehicle_id'));
    Map<String, Object> sm = (Map<String, Object>) ((List<Object>) m.get(
      'shipments'
    ))[0];
    System.assertEquals(
      'p',
      ((Map<String, Object>) sm.get('pickup')).get('id')
    );
    System.assertEquals(1, req.taskCount());
  }

  @IsTest
  static void parsesAnOptimizeResponse() {
    String body =
      '{"routes":[{"vehicle_id":"van","distance_m":2000,"duration_s":900,"service_s":300,"waiting_s":60,' +
      '"start_time":"2026-11-04T05:00:00Z","end_time":"2026-11-04T05:15:00Z","geometry":null,"steps":[' +
      '{"type":"start","id":null,"location":[34.79,31.25],"arrival":"2026-11-04T05:00:00Z","departure":"2026-11-04T05:00:00Z","load":[25,0,0]},' +
      '{"type":"job","id":"v1","location":[34.8,31.26],"arrival":"2026-11-04T05:05:00Z","departure":"2026-11-04T05:11:00Z",' +
      '"service_seconds":300,"waiting_seconds":60,"leg_distance_m":1000,"leg_duration_s":300,"load":[0,0,0],"locked":true,"late_seconds":120},' +
      '{"type":"end","location":[34.79,31.25],"arrival":"2026-11-04T05:15:00+00:00","departure":"2026-11-04T05:15:00Z"}]}],' +
      '"unassigned":[{"id":"v2","type":"job","reason":"skills","detail":"No vehicle has Refrigerated."}],' +
      '"summary":{"routes":1,"assigned":1,"unassigned":1,"distance_m":2000,"duration_s":900,"service_s":300,' +
      '"waiting_s":60,"cost":900,"matrix_source":"haversine","solve_ms":4}}';
    RoutingDtos.OptimizeResult r = RoutingDtos.parseOptimize(body);
    System.assertEquals(1, r.routes.size());
    RoutingDtos.Step job = r.routes[0].steps[1];
    System.assertEquals('job', job.stepType);
    System.assert(job.isTask() && job.locked);
    System.assertEquals(120, job.lateSeconds);
    System.assertEquals(
      31.26,
      Decimal.valueOf(job.location.getLatitude()).setScale(2)
    );
    System.assertEquals(
      Datetime.newInstanceGmt(2026, 11, 4, 5, 15, 0),
      r.routes[0].steps[2].arrival
    );
    System.assertEquals('skills', r.unassigned[0].reason);
    System.assertEquals(4, r.summary.solveMs);
    System.assert(r.rawSummary.contains('haversine'));
    System.assert(r.routeFor('van') != null && r.routeFor('nope') == null);
  }

  @IsTest
  static void helpers() {
    System.assertEquals(null, RoutingDtos.iso(null));
    System.assertEquals(null, RoutingDtos.dt(null));
    System.assertEquals(null, RoutingDtos.loc(new List<Object>{ 1 }));
    System.assertEquals(null, RoutingDtos.coord(null));
    System.assertEquals(0, RoutingDtos.toInt(null));
    System.assertEquals(3, RoutingDtos.toInt(2.6));
    System.assert(RoutingDtos.toList('x').isEmpty());
    System.assertEquals(null, RoutingDtos.toStr(null));
  }
}
