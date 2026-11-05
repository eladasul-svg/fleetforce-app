/**
 * openrouteservice provider, for development and tests only: the free key caps optimization at
 * 50 jobs and 3 vehicles per request. ORS runs VROOM too, so the neutral request is translated to the
 * VROOM problem format here (the FleetForce service does the same translation in Python).
 *
 * Not supported here: locked stops (options.fixed), reasons for unassigned jobs, and the Min Distance and
 * Min Vehicles objectives (ORS takes no vehicle costs). Balanced uses the service's task cap.
 */
public with sharing class OrsRoutingProvider implements RoutingProvider {
  public static final String NAMED_CREDENTIAL = 'Openrouteservice';
  public static final Integer MAX_JOBS = 50;
  public static final Integer MAX_VEHICLES = 3;

  private static String endpoint(String path) {
    return 'callout:' +
      RoutingProviders.namedCredential(NAMED_CREDENTIAL) +
      path;
  }

  // ---------------------------------------------------------------------------------------------
  // optimize
  // ---------------------------------------------------------------------------------------------

  public RoutingDtos.OptimizeResult optimize(
    RoutingDtos.OptimizeRequest request
  ) {
    if (
      request.vehicles.size() > MAX_VEHICLES ||
      request.jobs.size() + 2 * request.shipments.size() > MAX_JOBS
    ) {
      throw new RoutingProviders.RoutingException(
        'openrouteservice handles at most ' +
          MAX_JOBS +
          ' stops and ' +
          MAX_VEHICLES +
          ' vehicles per request. Use the FleetForce Routing provider for this plan.'
      );
    }
    if (!request.fixed.isEmpty()) {
      throw new RoutingProviders.RoutingException(
        'Locked stops need the FleetForce Routing provider; openrouteservice cannot pin them.'
      );
    }
    Translation t = new Translation(request);
    String body = RoutingProviders.send(
      endpoint('/optimization'),
      JSON.serialize(t.problem),
      null
    );
    return t.parse(body);
  }

  @TestVisible
  private class Translation {
    Map<String, Object> problem = new Map<String, Object>();
    Map<Integer, String> taskIds = new Map<Integer, String>();
    Map<Integer, String> shipmentOf = new Map<Integer, String>();
    Map<Integer, String> breakIds = new Map<Integer, String>();
    Map<Integer, String> vehicleIds = new Map<Integer, String>();
    Map<String, Integer> skillIds = new Map<String, Integer>();
    Integer nextId = 1;

    Translation(RoutingDtos.OptimizeRequest req) {
      List<Object> vehicles = new List<Object>();
      for (RoutingDtos.Vehicle v : req.vehicles) {
        Integer vid = nextId++;
        vehicleIds.put(vid, v.id);
        Map<String, Object> m = new Map<String, Object>{
          'id' => vid,
          'profile' => 'driving-car',
          'start' => RoutingDtos.coord(v.startLocation),
          'time_window' => new List<Object>{
            unix(v.shiftStart),
            unix(v.shiftEnd)
          },
          'skills' => skills(v.skills)
        };
        if (v.endLocation != null) {
          m.put('end', RoutingDtos.coord(v.endLocation));
        }
        if (v.capacity != null) {
          m.put('capacity', v.capacity);
        }
        List<Object> breaks = new List<Object>();
        for (RoutingDtos.BreakSpec b : v.breaks) {
          Integer bid = nextId++;
          breakIds.put(bid, b.id);
          breaks.add(
            new Map<String, Object>{
              'id' => bid,
              'time_windows' => windows(b.windows),
              'service' => b.serviceSeconds
            }
          );
        }
        if (!breaks.isEmpty()) {
          m.put('breaks', breaks);
        }
        vehicles.add(m);
      }
      List<Object> jobs = new List<Object>();
      for (RoutingDtos.Job j : req.jobs) {
        Map<String, Object> m = task(
          j.id,
          j.location,
          j.serviceSeconds,
          j.windows
        );
        m.put('delivery', j.delivery);
        m.put('pickup', j.pickup);
        m.put('priority', j.priority);
        m.put('skills', skills(j.skills));
        jobs.add(m);
      }
      List<Object> shipments = new List<Object>();
      for (RoutingDtos.Shipment s : req.shipments) {
        Map<String, Object> p = task(
          s.pickup.id,
          s.pickup.location,
          s.pickup.serviceSeconds,
          s.pickup.windows
        );
        Map<String, Object> d = task(
          s.delivery.id,
          s.delivery.location,
          s.delivery.serviceSeconds,
          s.delivery.windows
        );
        shipmentOf.put((Integer) p.get('id'), s.id);
        shipmentOf.put((Integer) d.get('id'), s.id);
        shipments.add(
          new Map<String, Object>{
            'pickup' => p,
            'delivery' => d,
            'amount' => s.amount,
            'priority' => s.priority,
            'skills' => skills(s.skills)
          }
        );
      }
      // Balanced: the same cap per vehicle as the FleetForce service (both ends of a shipment count).
      if (req.objective == 'balanced' && !vehicles.isEmpty()) {
        Integer tasks = req.jobs.size() + 2 * req.shipments.size();
        Integer perVehicle =
          Math.ceil(tasks / (Decimal) vehicles.size()).intValue() + 1;
        for (Object o : vehicles) {
          ((Map<String, Object>) o).put('max_tasks', perVehicle);
        }
      }
      problem.put('vehicles', vehicles);
      problem.put('jobs', jobs);
      problem.put('shipments', shipments);
      problem.put('options', new Map<String, Object>{ 'g' => req.geometry });
    }

    private Map<String, Object> task(
      String id,
      Location l,
      Integer service,
      List<RoutingDtos.TimeWindow> ws
    ) {
      Integer tid = nextId++;
      taskIds.put(tid, id);
      Map<String, Object> m = new Map<String, Object>{
        'id' => tid,
        'location' => RoutingDtos.coord(l),
        'service' => service
      };
      if (!ws.isEmpty()) {
        m.put('time_windows', windows(ws));
      }
      return m;
    }

    private List<Object> skills(List<String> names) {
      List<Object> out = new List<Object>();
      for (String n : names) {
        if (!skillIds.containsKey(n)) {
          skillIds.put(n, skillIds.size() + 1);
        }
        out.add(skillIds.get(n));
      }
      return out;
    }

    private List<Object> windows(List<RoutingDtos.TimeWindow> ws) {
      List<Object> out = new List<Object>();
      for (RoutingDtos.TimeWindow w : ws) {
        out.add(new List<Object>{ unix(w.startTime), unix(w.endTime) });
      }
      return out;
    }

    RoutingDtos.OptimizeResult parse(String body) {
      Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(
        body
      );
      RoutingDtos.OptimizeResult r = new RoutingDtos.OptimizeResult();
      for (Object o : RoutingDtos.toList(m.get('routes'))) {
        Map<String, Object> rm = (Map<String, Object>) o;
        RoutingDtos.Route route = new RoutingDtos.Route();
        route.vehicleId = vehicleIds.get(RoutingDtos.toInt(rm.get('vehicle')));
        route.geometry = RoutingDtos.toStr(rm.get('geometry'));
        Integer prevDistance = 0;
        Integer prevDuration = 0;
        for (Object so : RoutingDtos.toList(rm.get('steps'))) {
          Map<String, Object> sm = (Map<String, Object>) so;
          RoutingDtos.Step s = new RoutingDtos.Step();
          s.stepType = RoutingDtos.toStr(sm.get('type'));
          Integer sid = RoutingDtos.toInt(sm.get('id'));
          s.id = s.stepType == 'break' ? breakIds.get(sid) : taskIds.get(sid);
          s.location = RoutingDtos.loc(sm.get('location'));
          s.arrival = fromUnix(RoutingDtos.toInt(sm.get('arrival')));
          s.waitingSeconds = RoutingDtos.toInt(sm.get('waiting_time'));
          s.serviceSeconds = RoutingDtos.toInt(sm.get('service'));
          s.departure = s.arrival.addSeconds(
            s.waitingSeconds + s.serviceSeconds
          );
          Integer distance = RoutingDtos.toInt(sm.get('distance'));
          Integer duration = RoutingDtos.toInt(sm.get('duration'));
          s.legDistanceM = distance - prevDistance;
          s.legDurationS = duration - prevDuration;
          prevDistance = distance;
          prevDuration = duration;
          for (Object l : RoutingDtos.toList(sm.get('load'))) {
            s.load.add(RoutingDtos.toInt(l));
          }
          route.steps.add(s);
        }
        if (!route.steps.isEmpty()) {
          route.startTime = route.steps[0].departure;
          route.endTime = route.steps[route.steps.size() - 1].arrival;
        }
        route.distanceM = RoutingDtos.toInt(rm.get('distance'));
        route.durationS = route.startTime == null
          ? 0
          : ((route.endTime.getTime() - route.startTime.getTime()) / 1000)
              .intValue();
        route.serviceS = RoutingDtos.toInt(rm.get('service'));
        route.waitingS = RoutingDtos.toInt(rm.get('waiting_time'));
        r.routes.add(route);
        r.summary.assigned += countTasks(route);
      }
      Set<String> seenShipments = new Set<String>();
      for (Object o : RoutingDtos.toList(m.get('unassigned'))) {
        Map<String, Object> um = (Map<String, Object>) o;
        Integer uid = RoutingDtos.toInt(um.get('id'));
        RoutingDtos.Unassigned u = new RoutingDtos.Unassigned();
        if (shipmentOf.containsKey(uid)) {
          if (!seenShipments.add(shipmentOf.get(uid))) {
            continue;
          }
          u.id = shipmentOf.get(uid);
          u.taskType = 'shipment';
        } else {
          u.id = taskIds.get(uid);
          u.taskType = 'job';
        }
        u.reason = 'no_room';
        u.detail = 'openrouteservice could not fit this stop (it does not report why).';
        r.unassigned.add(u);
      }
      Map<String, Object> sm = (Map<String, Object>) m.get('summary');
      r.summary.routes = r.routes.size();
      r.summary.unassigned = r.unassigned.size();
      r.summary.matrixSource = 'openrouteservice';
      if (sm != null) {
        r.summary.distanceM = RoutingDtos.toInt(sm.get('distance'));
        r.summary.durationS = RoutingDtos.toInt(sm.get('duration'));
        r.summary.serviceS = RoutingDtos.toInt(sm.get('service'));
        r.summary.waitingS = RoutingDtos.toInt(sm.get('waiting_time'));
        r.summary.cost = RoutingDtos.toInt(sm.get('cost'));
        r.rawSummary = JSON.serialize(sm);
      }
      return r;
    }
  }

  private static Integer countTasks(RoutingDtos.Route route) {
    Integer n = 0;
    for (RoutingDtos.Step s : route.steps) {
      if (s.isTask()) {
        n++;
      }
    }
    return n;
  }

  @TestVisible
  private static Long unix(Datetime t) {
    return t.getTime() / 1000;
  }

  private static Datetime fromUnix(Long seconds) {
    return Datetime.newInstance(seconds * 1000);
  }

  // ---------------------------------------------------------------------------------------------
  // matrix and route
  // ---------------------------------------------------------------------------------------------

  public RoutingDtos.MatrixResult matrix(List<Location> locations) {
    List<Object> coords = new List<Object>();
    for (Location l : locations) {
      coords.add(RoutingDtos.coord(l));
    }
    String body = RoutingProviders.send(
      endpoint('/v2/matrix/driving-car'),
      JSON.serialize(
        new Map<String, Object>{
          'locations' => coords,
          'metrics' => new List<String>{ 'duration', 'distance' }
        }
      ),
      null
    );
    Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(body);
    RoutingDtos.MatrixResult r = new RoutingDtos.MatrixResult();
    r.durations = intMatrix(m.get('durations'));
    r.distances = intMatrix(m.get('distances'));
    r.matrixSource = 'openrouteservice';
    return r;
  }

  public RoutingDtos.RouteResult route(
    List<RoutingDtos.RouteWaypoint> waypoints,
    Datetime departure
  ) {
    List<Object> coords = new List<Object>();
    for (RoutingDtos.RouteWaypoint w : waypoints) {
      coords.add(RoutingDtos.coord(w.location));
    }
    String body = RoutingProviders.send(
      endpoint('/v2/directions/driving-car'),
      JSON.serialize(new Map<String, Object>{ 'coordinates' => coords }),
      null
    );
    Map<String, Object> route = (Map<String, Object>) RoutingDtos.toList(
      ((Map<String, Object>) JSON.deserializeUntyped(body)).get('routes')
    )[0];
    RoutingDtos.RouteResult r = new RoutingDtos.RouteResult();
    List<Object> segments = RoutingDtos.toList(route.get('segments'));
    Datetime t = departure;
    for (Integer i = 0; i < segments.size(); i++) {
      Map<String, Object> seg = (Map<String, Object>) segments[i];
      RoutingDtos.Leg leg = new RoutingDtos.Leg();
      leg.fromId = waypoints[i].id;
      leg.toId = waypoints[i + 1].id;
      leg.distanceM = RoutingDtos.toInt(seg.get('distance'));
      leg.durationS = RoutingDtos.toInt(seg.get('duration'));
      if (t != null) {
        t = t.addSeconds(leg.durationS);
        leg.arrival = t;
      }
      r.legs.add(leg);
      r.distanceM += leg.distanceM;
      r.durationS += leg.durationS;
    }
    r.geometry = RoutingDtos.toStr(route.get('geometry'));
    r.matrixSource = 'openrouteservice';
    return r;
  }

  private static List<List<Integer>> intMatrix(Object o) {
    List<List<Integer>> out = new List<List<Integer>>();
    for (Object row : RoutingDtos.toList(o)) {
      List<Integer> r = new List<Integer>();
      for (Object v : RoutingDtos.toList(row)) {
        r.add(RoutingDtos.toInt(v));
      }
      out.add(r);
    }
    return out;
  }
}
