@IsTest
private class OrsRoutingProviderTest {
  private class OrsMock implements HttpCalloutMock {
    HttpRequest last;
    public HttpResponse respond(HttpRequest req) {
      last = req;
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      String path = req.getEndpoint();
      if (path.endsWith('/optimization')) {
        res.setBody(answer(req.getBody()));
      } else if (path.contains('/v2/matrix/')) {
        res.setBody(
          '{"durations":[[0,61.4],[59.6,0]],"distances":[[0,812.2],[790,0]]}'
        );
      } else {
        res.setBody(
          '{"routes":[{"geometry":"enc","summary":{"distance":1600,"duration":120},' +
          '"segments":[{"distance":800,"duration":60},{"distance":800,"duration":60}]}]}'
        );
      }
      return res;
    }
  }

  /** A VROOM-shaped answer: every job on the first vehicle, shipments unassigned. */
  private static String answer(String body) {
    Map<String, Object> p = (Map<String, Object>) JSON.deserializeUntyped(body);
    Map<String, Object> v = (Map<String, Object>) ((List<Object>) p.get(
      'vehicles'
    ))[0];
    Long t = Long.valueOf(
      String.valueOf(((List<Object>) v.get('time_window'))[0])
    );
    List<Object> steps = new List<Object>{
      new Map<String, Object>{
        'type' => 'start',
        'location' => v.get('start'),
        'arrival' => t,
        'duration' => 0,
        'distance' => 0
      }
    };
    Integer k = 1;
    for (Object o : (List<Object>) p.get('jobs')) {
      Map<String, Object> j = (Map<String, Object>) o;
      steps.add(
        new Map<String, Object>{
          'type' => 'job',
          'id' => j.get('id'),
          'location' => j.get('location'),
          'arrival' => t + 600 * k,
          'duration' => 300 * k,
          'distance' => 2000 * k,
          'service' => 300,
          'waiting_time' => 0,
          'load' => new List<Object>{ 0, 0, 0 }
        }
      );
      k++;
    }
    List<Object> breaks = (List<Object>) v.get('breaks');
    if (breaks != null) {
      steps.add(
        new Map<String, Object>{
          'type' => 'break',
          'id' => ((Map<String, Object>) breaks[0]).get('id'),
          'arrival' => t + 600 * k,
          'duration' => 300 * k,
          'distance' => 2000 * k,
          'service' => 1800
        }
      );
    }
    steps.add(
      new Map<String, Object>{
        'type' => 'end',
        'location' => v.get('start'),
        'arrival' => t + 600 * (k + 4),
        'duration' => 300 * (k + 1),
        'distance' => 2000 * (k + 1)
      }
    );
    List<Object> unassigned = new List<Object>();
    for (Object o : (List<Object>) p.get('shipments')) {
      Map<String, Object> s = (Map<String, Object>) o;
      unassigned.add(
        new Map<String, Object>{
          'id' => ((Map<String, Object>) s.get('pickup')).get('id'),
          'type' => 'pickup'
        }
      );
      unassigned.add(
        new Map<String, Object>{
          'id' => ((Map<String, Object>) s.get('delivery')).get('id'),
          'type' => 'delivery'
        }
      );
    }
    return JSON.serialize(
      new Map<String, Object>{
        'code' => 0,
        'routes' => new List<Object>{
          new Map<String, Object>{
            'vehicle' => v.get('id'),
            'steps' => steps,
            'distance' => 2000 * (k + 1),
            'geometry' => 'g'
          }
        },
        'unassigned' => unassigned,
        'summary' => new Map<String, Object>{
          'cost' => 1,
          'distance' => 2000 * (k + 1),
          'duration' => 300 * (k + 1)
        }
      }
    );
  }

  private static RoutingDtos.OptimizeRequest request(Integer jobs) {
    RoutingDtos.OptimizeRequest req = new RoutingDtos.OptimizeRequest();
    RoutingDtos.Vehicle v = new RoutingDtos.Vehicle();
    v.id = 'van-1';
    v.startLocation = Location.newInstance(31.2518, 34.7913);
    v.endLocation = v.startLocation;
    v.shiftStart = Datetime.newInstanceGmt(2026, 11, 4, 5, 0, 0);
    v.shiftEnd = v.shiftStart.addHours(10);
    v.capacity = new List<Integer>{ 800, 0, 0 };
    v.skills.add('Lift Gate');
    RoutingDtos.BreakSpec b = new RoutingDtos.BreakSpec();
    b.id = 'charge';
    b.serviceSeconds = 1800;
    b.windows.add(
      new RoutingDtos.TimeWindow(
        v.shiftStart.addHours(4),
        v.shiftStart.addHours(6)
      )
    );
    v.breaks.add(b);
    req.vehicles.add(v);
    for (Integer i = 0; i < jobs; i++) {
      RoutingDtos.Job j = new RoutingDtos.Job();
      j.id = 'visit-' + i;
      j.location = Location.newInstance(31.26 + i * 0.001, 34.8);
      j.windows.add(new RoutingDtos.TimeWindow(v.shiftStart, v.shiftEnd));
      j.skills.add('Lift Gate');
      req.jobs.add(j);
    }
    RoutingDtos.Shipment s = new RoutingDtos.Shipment();
    s.id = 'reloc';
    s.pickup = new RoutingDtos.ShipmentStep();
    s.pickup.id = 'p';
    s.pickup.location = Location.newInstance(31.27, 34.8);
    s.delivery = new RoutingDtos.ShipmentStep();
    s.delivery.id = 'd';
    s.delivery.location = Location.newInstance(31.28, 34.8);
    req.shipments.add(s);
    return req;
  }

  @IsTest
  static void optimizeTranslatesToVroomAndBack() {
    OrsMock mock = new OrsMock();
    Test.setMock(HttpCalloutMock.class, mock);
    RoutingDtos.OptimizeResult r = new OrsRoutingProvider()
      .optimize(request(2));
    System.assert(
      mock.last.getEndpoint().endsWith('Openrouteservice/optimization'),
      mock.last.getEndpoint()
    );
    Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(
      mock.last.getBody()
    );
    Map<String, Object> v = (Map<String, Object>) ((List<Object>) sent.get(
      'vehicles'
    ))[0];
    System.assertEquals('driving-car', v.get('profile'));
    System.assertEquals(
      new List<Object>{ 1 },
      v.get('skills'),
      'skill names become integers'
    );
    System.assertEquals(
      String.valueOf(
        OrsRoutingProvider.unix(Datetime.newInstanceGmt(2026, 11, 4, 5, 0, 0))
      ),
      String.valueOf(((List<Object>) v.get('time_window'))[0])
    );

    RoutingDtos.Route route = r.routes[0];
    System.assertEquals('van-1', route.vehicleId);
    System.assertEquals('visit-0', route.steps[1].id);
    System.assertEquals(2000, route.steps[1].legDistanceM);
    System.assertEquals('charge', route.steps[3].id);
    System.assertEquals(2, r.summary.assigned);
    System.assertEquals(
      1,
      r.unassigned.size(),
      'both ends of a shipment are one unassigned entry'
    );
    System.assertEquals('reloc', r.unassigned[0].id);
    System.assertEquals('shipment', r.unassigned[0].taskType);
    System.assertEquals('openrouteservice', r.summary.matrixSource);
    System.assert(route.durationS > 0);
  }

  @IsTest
  static void balancedCapsTasksPerVehicle() {
    OrsMock mock = new OrsMock();
    Test.setMock(HttpCalloutMock.class, mock);
    new OrsRoutingProvider().optimize(request(2));
    Map<String, Object> v = sentVehicle(mock);
    System.assert(!v.containsKey('max_tasks'), 'no cap for Min Duration');

    RoutingDtos.OptimizeRequest req = request(2);
    req.objective = 'balanced';
    new OrsRoutingProvider().optimize(req);
    v = sentVehicle(mock);
    System.assertEquals(
      5,
      v.get('max_tasks'),
      'ceil(4 tasks / 1 vehicle) + 1, both ends of the shipment counted'
    );
  }

  private static Map<String, Object> sentVehicle(OrsMock mock) {
    Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(
      mock.last.getBody()
    );
    return (Map<String, Object>) ((List<Object>) sent.get('vehicles'))[0];
  }

  @IsTest
  static void refusesWhatTheFreeKeyCannotDo() {
    try {
      new OrsRoutingProvider().optimize(request(OrsRoutingProvider.MAX_JOBS));
      System.assert(false, 'expected an exception');
    } catch (RoutingProviders.RoutingException e) {
      System.assert(e.getMessage().contains('at most'), e.getMessage());
    }
    RoutingDtos.OptimizeRequest req = request(1);
    req.fixed.add(
      new RoutingDtos.FixedSteps('van-1', new List<String>{ 'visit-0' })
    );
    try {
      new OrsRoutingProvider().optimize(req);
      System.assert(false, 'expected an exception');
    } catch (RoutingProviders.RoutingException e) {
      System.assert(e.getMessage().contains('Locked stops'), e.getMessage());
    }
  }

  @IsTest
  static void matrixAndRoute() {
    Test.setMock(HttpCalloutMock.class, new OrsMock());
    RoutingDtos.MatrixResult m = new OrsRoutingProvider()
      .matrix(
        new List<Location>{
          Location.newInstance(31.25, 34.79),
          Location.newInstance(31.26, 34.8)
        }
      );
    System.assertEquals(61, m.durations[0][1]);
    System.assertEquals(812, m.distances[0][1]);
    RoutingDtos.RouteResult r = new OrsRoutingProvider()
      .route(
        new List<RoutingDtos.RouteWaypoint>{
          new RoutingDtos.RouteWaypoint(
            'a',
            Location.newInstance(31.25, 34.79)
          ),
          new RoutingDtos.RouteWaypoint('b', Location.newInstance(31.26, 34.8)),
          new RoutingDtos.RouteWaypoint('c', Location.newInstance(31.27, 34.8))
        },
        Datetime.newInstanceGmt(2026, 11, 4, 5, 0, 0)
      );
    System.assertEquals(2, r.legs.size());
    System.assertEquals(1600, r.distanceM);
    System.assertEquals(
      Datetime.newInstanceGmt(2026, 11, 4, 5, 2, 0),
      r.legs[1].arrival
    );
    System.assertEquals('enc', r.geometry);
  }
}
