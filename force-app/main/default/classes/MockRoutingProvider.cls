/**
 * Offline provider for tests and demos without the routing service. It is a greedy nearest-neighbour
 * planner on straight-line distance (1.3 detour factor, 40 km/h) that honours skills, capacity, time
 * windows, breaks and locked prefixes well enough to exercise every code path. It is not an optimizer:
 * plans come from the FleetForce Routing Service.
 *
 * Tests can also hand it a canned response body, which it returns parsed (cannedOptimize).
 */
public with sharing class MockRoutingProvider implements RoutingProvider {
  public static final Decimal SPEED_MS = 40 / 3.6;
  public static final Decimal DETOUR = 1.3;

  public String cannedOptimize;
  public Integer optimizeCalls = 0;
  public RoutingDtos.OptimizeRequest lastRequest;

  // ---------------------------------------------------------------------------------------------
  // optimize
  // ---------------------------------------------------------------------------------------------

  public RoutingDtos.OptimizeResult optimize(
    RoutingDtos.OptimizeRequest request
  ) {
    optimizeCalls++;
    lastRequest = request;
    if (cannedOptimize != null) {
      return RoutingDtos.parseOptimize(cannedOptimize);
    }

    // Tasks the planner places, as visit-sized units: jobs, and shipments as pickup+delivery pairs.
    List<Unit> openUnits = new List<Unit>();
    Map<String, Unit> byTaskId = new Map<String, Unit>();
    for (RoutingDtos.Job j : request.jobs) {
      Unit u = new Unit(j.id, 'job', j.skills, j.delivery);
      u.steps.add(
        new PlannedStop('job', j.id, j.location, j.serviceSeconds, j.windows)
      );
      openUnits.add(u);
      byTaskId.put(j.id, u);
    }
    for (RoutingDtos.Shipment s : request.shipments) {
      Unit u = new Unit(s.id, 'shipment', s.skills, RoutingDtos.zeros());
      u.peak = s.amount;
      u.steps.add(
        new PlannedStop(
          'pickup',
          s.pickup.id,
          s.pickup.location,
          s.pickup.serviceSeconds,
          s.pickup.windows
        )
      );
      u.steps.add(
        new PlannedStop(
          'delivery',
          s.delivery.id,
          s.delivery.location,
          s.delivery.serviceSeconds,
          s.delivery.windows
        )
      );
      openUnits.add(u);
      byTaskId.put(s.pickup.id, u);
      byTaskId.put(s.delivery.id, u);
    }

    Map<String, List<String>> lockedByVehicle = new Map<String, List<String>>();
    for (RoutingDtos.FixedSteps f : request.fixed) {
      lockedByVehicle.put(f.vehicleId, f.taskIds);
    }

    RoutingDtos.OptimizeResult result = new RoutingDtos.OptimizeResult();
    Set<String> placed = new Set<String>();
    for (RoutingDtos.Vehicle v : request.vehicles) {
      Builder b = new Builder(v);
      if (lockedByVehicle.containsKey(v.id)) {
        for (String tid : lockedByVehicle.get(v.id)) {
          Unit u = byTaskId.get(tid);
          for (PlannedStop ps : u.steps) {
            if (ps.id == tid) {
              b.add(ps, true);
            }
          }
          placed.add(u.id);
        }
      }
      while (true) {
        Unit best;
        Decimal bestDistance;
        for (Unit u : openUnits) {
          if (placed.contains(u.id) || !b.fits(u)) {
            continue;
          }
          Decimal d = distanceM(b.at, u.steps[0].location);
          if (best == null || d < bestDistance) {
            best = u;
            bestDistance = d;
          }
        }
        if (best == null) {
          break;
        }
        b.place(best);
        placed.add(best.id);
      }
      if (b.steps.size() > 1) {
        result.routes.add(b.finish());
      }
    }

    for (Unit u : openUnits) {
      if (placed.contains(u.id)) {
        continue;
      }
      RoutingDtos.Unassigned un = new RoutingDtos.Unassigned();
      un.id = u.id;
      un.taskType = u.kind;
      un.reason = reasonFor(u, request.vehicles);
      un.detail = 'Mock planner: ' + un.reason.replace('_', ' ') + '.';
      result.unassigned.add(un);
    }

    for (RoutingDtos.Route r : result.routes) {
      result.summary.distanceM += r.distanceM;
      result.summary.durationS += r.durationS;
      result.summary.serviceS += r.serviceS;
      result.summary.waitingS += r.waitingS;
      for (RoutingDtos.Step s : r.steps) {
        if (s.isTask()) {
          result.summary.assigned++;
        }
      }
    }
    result.summary.routes = result.routes.size();
    result.summary.unassigned = result.unassigned.size();
    result.summary.matrixSource = 'mock';
    result.rawSummary = JSON.serialize(
      new Map<String, Object>{ 'provider' => 'mock' }
    );
    return result;
  }

  private static String reasonFor(Unit u, List<RoutingDtos.Vehicle> vehicles) {
    Boolean skillsOk = false;
    Boolean capacityOk = false;
    for (RoutingDtos.Vehicle v : vehicles) {
      if (new Set<String>(v.skills).containsAll(u.skills)) {
        skillsOk = true;
        if (v.capacity == null || fitsCapacity(u.peakLoad(), v.capacity)) {
          capacityOk = true;
        }
      }
    }
    return !skillsOk ? 'skills' : (!capacityOk ? 'capacity' : 'no_room');
  }

  private static Boolean fitsCapacity(
    List<Integer> load,
    List<Integer> capacity
  ) {
    for (Integer i = 0; i < load.size(); i++) {
      Integer cap = i < capacity.size() ? capacity[i] : 0;
      if (load[i] > cap) {
        return false;
      }
    }
    return true;
  }

  private class Unit {
    String id;
    String kind;
    List<String> skills;
    List<Integer> delivery;
    List<Integer> peak;
    List<PlannedStop> steps = new List<PlannedStop>();
    Unit(String id, String kind, List<String> skills, List<Integer> delivery) {
      this.id = id;
      this.kind = kind;
      this.skills = skills;
      this.delivery = delivery;
    }
    List<Integer> peakLoad() {
      return peak != null ? peak : delivery;
    }
  }

  private class PlannedStop {
    String kind;
    String id;
    Location location;
    Integer service;
    List<RoutingDtos.TimeWindow> windows;
    PlannedStop(
      String kind,
      String id,
      Location location,
      Integer service,
      List<RoutingDtos.TimeWindow> windows
    ) {
      this.kind = kind;
      this.id = id;
      this.location = location;
      this.service = service;
      this.windows = windows;
    }
  }

  private class Builder {
    RoutingDtos.Vehicle v;
    List<RoutingDtos.Step> steps = new List<RoutingDtos.Step>();
    Location at;
    Datetime clock;
    List<Integer> carried = RoutingDtos.zeros();
    List<RoutingDtos.BreakSpec> pendingBreaks;

    Builder(RoutingDtos.Vehicle v) {
      this.v = v;
      this.at = v.startLocation;
      this.clock = v.shiftStart;
      this.pendingBreaks = new List<RoutingDtos.BreakSpec>(v.breaks);
      RoutingDtos.Step s = new RoutingDtos.Step();
      s.stepType = 'start';
      s.location = at;
      s.arrival = clock;
      s.departure = clock;
      steps.add(s);
    }

    Boolean fits(Unit u) {
      if (!new Set<String>(v.skills).containsAll(u.skills)) {
        return false;
      }
      List<Integer> after = new List<Integer>();
      for (Integer i = 0; i < 3; i++) {
        after.add(carried[i] + u.peakLoad()[i]);
      }
      if (v.capacity != null && !fitsCapacity(after, v.capacity)) {
        return false;
      }
      Datetime t = clock;
      Location here = at;
      for (PlannedStop ps : u.steps) {
        Datetime arrival = t.addSeconds(travelS(here, ps.location));
        Datetime serviceAt = serviceStart(arrival, ps.windows);
        if (serviceAt == null) {
          return false;
        }
        t = serviceAt.addSeconds(ps.service);
        here = ps.location;
      }
      Location home = v.endLocation == null ? here : v.endLocation;
      return t.addSeconds(travelS(here, home)) <= v.shiftEnd;
    }

    void place(Unit u) {
      for (Integer i = 0; i < 3; i++) {
        carried[i] += u.peakLoad()[i];
      }
      for (PlannedStop ps : u.steps) {
        add(ps, false);
      }
      if (u.kind == 'shipment') {
        for (Integer i = 0; i < 3; i++) {
          carried[i] -= u.peakLoad()[i];
        }
      }
    }

    void add(PlannedStop ps, Boolean locked) {
      RoutingDtos.Step s = new RoutingDtos.Step();
      s.stepType = ps.kind;
      s.id = ps.id;
      s.location = ps.location;
      s.legDistanceM = RoutingDtos.toInt(distanceM(at, ps.location));
      s.legDurationS = travelS(at, ps.location);
      s.arrival = clock.addSeconds(s.legDurationS);
      Datetime serviceAt = serviceStart(s.arrival, ps.windows);
      if (serviceAt == null) {
        serviceAt = s.arrival;
        s.lateSeconds = ((s.arrival.getTime() -
          ps.windows[ps.windows.size() - 1].endTime.getTime()) / 1000)
          .intValue();
      }
      s.waitingSeconds = ((serviceAt.getTime() - s.arrival.getTime()) / 1000)
        .intValue();
      s.serviceSeconds = ps.service;
      s.departure = serviceAt.addSeconds(ps.service);
      s.locked = locked;
      s.load = new List<Integer>(carried);
      steps.add(s);
      at = ps.location;
      clock = s.departure;
      takeBreakIfDue();
    }

    void takeBreakIfDue() {
      for (Integer i = 0; i < pendingBreaks.size(); i++) {
        RoutingDtos.BreakSpec b = pendingBreaks[i];
        if (b.windows.isEmpty() || clock < b.windows[0].startTime) {
          continue;
        }
        RoutingDtos.Step s = new RoutingDtos.Step();
        s.stepType = 'break';
        s.id = b.id;
        s.location = at;
        s.arrival = clock;
        s.serviceSeconds = b.serviceSeconds;
        s.departure = clock.addSeconds(b.serviceSeconds);
        s.load = new List<Integer>(carried);
        steps.add(s);
        clock = s.departure;
        pendingBreaks.remove(i);
        return;
      }
    }

    RoutingDtos.Route finish() {
      Location home = v.endLocation == null ? at : v.endLocation;
      RoutingDtos.Step e = new RoutingDtos.Step();
      e.stepType = 'end';
      e.location = home;
      e.legDistanceM = RoutingDtos.toInt(distanceM(at, home));
      e.legDurationS = travelS(at, home);
      e.arrival = clock.addSeconds(e.legDurationS);
      e.departure = e.arrival;
      e.load = RoutingDtos.zeros();
      steps.add(e);

      // Loads: start full with the deliveries, then follow each stop.
      RoutingDtos.Route r = new RoutingDtos.Route();
      r.vehicleId = v.id;
      r.steps = steps;
      r.startTime = steps[0].departure;
      r.endTime = e.arrival;
      r.durationS = ((r.endTime.getTime() - r.startTime.getTime()) / 1000)
        .intValue();
      for (RoutingDtos.Step s : steps) {
        r.distanceM += s.legDistanceM;
        r.serviceS += s.serviceSeconds;
        r.waitingS += s.waitingSeconds;
      }
      return r;
    }
  }

  private static Datetime serviceStart(
    Datetime arrival,
    List<RoutingDtos.TimeWindow> windows
  ) {
    if (windows == null || windows.isEmpty()) {
      return arrival;
    }
    for (RoutingDtos.TimeWindow w : windows) {
      if (arrival <= w.endTime) {
        return arrival < w.startTime ? w.startTime : arrival;
      }
    }
    return null;
  }

  public static Decimal distanceM(Location a, Location b) {
    if (a == null || b == null) {
      return 0;
    }
    return Decimal.valueOf(Location.getDistance(a, b, 'km')) * 1000 * DETOUR;
  }

  public static Integer travelS(Location a, Location b) {
    return RoutingDtos.toInt(distanceM(a, b) / SPEED_MS);
  }

  // ---------------------------------------------------------------------------------------------
  // matrix and route
  // ---------------------------------------------------------------------------------------------

  public RoutingDtos.MatrixResult matrix(List<Location> locations) {
    RoutingDtos.MatrixResult r = new RoutingDtos.MatrixResult();
    for (Location a : locations) {
      List<Integer> durations = new List<Integer>();
      List<Integer> distances = new List<Integer>();
      for (Location b : locations) {
        durations.add(travelS(a, b));
        distances.add(RoutingDtos.toInt(distanceM(a, b)));
      }
      r.durations.add(durations);
      r.distances.add(distances);
    }
    r.matrixSource = 'mock';
    return r;
  }

  public RoutingDtos.RouteResult route(
    List<RoutingDtos.RouteWaypoint> waypoints,
    Datetime departure
  ) {
    RoutingDtos.RouteResult r = new RoutingDtos.RouteResult();
    Datetime t = departure;
    for (Integer i = 1; i < waypoints.size(); i++) {
      RoutingDtos.Leg leg = new RoutingDtos.Leg();
      leg.fromId = waypoints[i - 1].id;
      leg.toId = waypoints[i].id;
      leg.distanceM = RoutingDtos.toInt(
        distanceM(waypoints[i - 1].location, waypoints[i].location)
      );
      leg.durationS = travelS(waypoints[i - 1].location, waypoints[i].location);
      if (t != null) {
        t = t.addSeconds(leg.durationS);
        leg.arrival = t;
      }
      r.legs.add(leg);
      r.distanceM += leg.distanceM;
      r.durationS += leg.durationS;
    }
    r.matrixSource = 'mock';
    return r;
  }
}
