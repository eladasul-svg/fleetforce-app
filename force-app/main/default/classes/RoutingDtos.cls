/**
 * Apex side of the FleetForce routing contract (services/routing/app/schemas.py, v1).
 *
 * The contract uses snake_case keys and words Apex reserves (type, end), so requests are built as
 * maps (toMap) and responses are parsed from untyped JSON (fromMap) instead of JSON.serialize on
 * these classes. Units are the contract's: [lon, lat], metres, seconds, ISO 8601 datetimes.
 */
public with sharing class RoutingDtos {
  public static final Integer CAPACITY_DIMENSIONS = 3;

  // ---------------------------------------------------------------------------------------------
  // Request
  // ---------------------------------------------------------------------------------------------

  public class TimeWindow {
    public Datetime startTime;
    public Datetime endTime;
    public TimeWindow(Datetime startTime, Datetime endTime) {
      this.startTime = startTime;
      this.endTime = endTime;
    }
    public Map<String, Object> toMap() {
      return new Map<String, Object>{
        'start' => iso(startTime),
        'end' => iso(endTime)
      };
    }
  }

  public class BreakSpec {
    public String id;
    public String description;
    public Integer serviceSeconds = 0;
    public List<TimeWindow> windows = new List<TimeWindow>();
    public Map<String, Object> toMap() {
      return new Map<String, Object>{
        'id' => id,
        'description' => description,
        'service_seconds' => serviceSeconds,
        'time_windows' => windowMaps(windows)
      };
    }
  }

  public class Vehicle {
    public String id;
    public Location startLocation;
    /** Null for an open trip. */
    public Location endLocation;
    public Datetime shiftStart;
    public Datetime shiftEnd;
    /** Null for unlimited capacity. */
    public List<Integer> capacity;
    public List<String> skills = new List<String>();
    public List<BreakSpec> breaks = new List<BreakSpec>();
    public Map<String, Object> toMap() {
      Map<String, Object> m = new Map<String, Object>{
        'id' => id,
        'start' => coord(startLocation),
        'shift_start' => iso(shiftStart),
        'shift_end' => iso(shiftEnd),
        'skills' => skills
      };
      if (endLocation != null) {
        m.put('end', coord(endLocation));
      }
      if (capacity != null) {
        m.put('capacity', capacity);
      }
      if (!breaks.isEmpty()) {
        List<Object> bs = new List<Object>();
        for (BreakSpec b : breaks) {
          bs.add(b.toMap());
        }
        m.put('breaks', bs);
      }
      return m;
    }
  }

  public class Job {
    public String id;
    public Location location;
    public Integer serviceSeconds = 0;
    public List<TimeWindow> windows = new List<TimeWindow>();
    public List<Integer> delivery = zeros();
    public List<Integer> pickup = zeros();
    public List<String> skills = new List<String>();
    public Integer priority = 0;
    public String description;
    public Map<String, Object> toMap() {
      return new Map<String, Object>{
        'id' => id,
        'location' => coord(location),
        'service_seconds' => serviceSeconds,
        'time_windows' => windowMaps(windows),
        'delivery' => delivery,
        'pickup' => pickup,
        'skills' => skills,
        'priority' => priority,
        'description' => description
      };
    }
  }

  public class ShipmentStep {
    public String id;
    public Location location;
    public Integer serviceSeconds = 0;
    public List<TimeWindow> windows = new List<TimeWindow>();
    public String description;
    public Map<String, Object> toMap() {
      return new Map<String, Object>{
        'id' => id,
        'location' => coord(location),
        'service_seconds' => serviceSeconds,
        'time_windows' => windowMaps(windows),
        'description' => description
      };
    }
  }

  public class Shipment {
    public String id;
    public ShipmentStep pickup;
    public ShipmentStep delivery;
    public List<Integer> amount = zeros();
    public List<String> skills = new List<String>();
    public Integer priority = 0;
    public Map<String, Object> toMap() {
      return new Map<String, Object>{
        'id' => id,
        'pickup' => pickup.toMap(),
        'delivery' => delivery.toMap(),
        'amount' => amount,
        'skills' => skills,
        'priority' => priority
      };
    }
  }

  public class FixedSteps {
    public String vehicleId;
    public List<String> taskIds = new List<String>();
    public FixedSteps(String vehicleId, List<String> taskIds) {
      this.vehicleId = vehicleId;
      this.taskIds = taskIds;
    }
  }

  public class OptimizeRequest {
    public List<Vehicle> vehicles = new List<Vehicle>();
    public List<Job> jobs = new List<Job>();
    public List<Shipment> shipments = new List<Shipment>();
    /** min_duration | min_distance | min_vehicles | balanced */
    public String objective = 'min_duration';
    public Boolean geometry = true;
    public List<FixedSteps> fixed = new List<FixedSteps>();

    // Not sent to the solver: what the request builder left out, and why.
    public Map<String, String> excludedVehicles = new Map<String, String>();
    public Map<String, String> skippedJobs = new Map<String, String>();

    public Integer taskCount() {
      return jobs.size() + shipments.size();
    }

    public Map<String, Object> toMap() {
      List<Object> vs = new List<Object>();
      for (Vehicle v : vehicles) {
        vs.add(v.toMap());
      }
      List<Object> js = new List<Object>();
      for (Job j : jobs) {
        js.add(j.toMap());
      }
      List<Object> ss = new List<Object>();
      for (Shipment s : shipments) {
        ss.add(s.toMap());
      }
      List<Object> fx = new List<Object>();
      for (FixedSteps f : fixed) {
        fx.add(
          new Map<String, Object>{
            'vehicle_id' => f.vehicleId,
            'task_ids' => f.taskIds
          }
        );
      }
      return new Map<String, Object>{
        'vehicles' => vs,
        'jobs' => js,
        'shipments' => ss,
        'options' => new Map<String, Object>{
          'objective' => objective,
          'geometry' => geometry,
          'fixed' => fx
        }
      };
    }

    public String toJson() {
      return JSON.serialize(toMap(), true);
    }
  }

  // ---------------------------------------------------------------------------------------------
  // Response
  // ---------------------------------------------------------------------------------------------

  public class Step {
    /** start | job | pickup | delivery | break | end */
    public String stepType;
    public String id;
    public Location location;
    public Datetime arrival;
    public Datetime departure;
    public Integer serviceSeconds = 0;
    public Integer waitingSeconds = 0;
    public Integer legDistanceM = 0;
    public Integer legDurationS = 0;
    public List<Integer> load = new List<Integer>();
    public Boolean locked = false;
    public Integer lateSeconds = 0;

    public Boolean isTask() {
      return stepType == 'job' ||
        stepType == 'pickup' ||
        stepType == 'delivery';
    }
  }

  public class Route {
    public String vehicleId;
    public List<Step> steps = new List<Step>();
    public Integer distanceM = 0;
    public Integer durationS = 0;
    public Integer serviceS = 0;
    public Integer waitingS = 0;
    public Datetime startTime;
    public Datetime endTime;
    public String geometry;
  }

  public class Unassigned {
    public String id;
    /** job | pickup | delivery | shipment */
    public String taskType;
    /** skills | capacity | time_window | no_room | locked_conflict */
    public String reason;
    public String detail;
  }

  public class Summary {
    public Integer routes = 0;
    public Integer assigned = 0;
    public Integer unassigned = 0;
    public Integer distanceM = 0;
    public Integer durationS = 0;
    public Integer serviceS = 0;
    public Integer waitingS = 0;
    public Integer cost = 0;
    public String matrixSource;
    public Integer solveMs = 0;
  }

  public class OptimizeResult {
    public List<Route> routes = new List<Route>();
    public List<Unassigned> unassigned = new List<Unassigned>();
    public Summary summary = new Summary();
    /** The raw response, kept for Route_Plan__c.Solver_Summary__c. */
    public String rawSummary;

    public Route routeFor(String vehicleId) {
      for (Route r : routes) {
        if (r.vehicleId == vehicleId) {
          return r;
        }
      }
      return null;
    }
  }

  public class MatrixResult {
    public List<List<Integer>> durations = new List<List<Integer>>();
    public List<List<Integer>> distances = new List<List<Integer>>();
    public String matrixSource;
  }

  public class RouteWaypoint {
    public String id;
    public Location location;
    public RouteWaypoint(String id, Location location) {
      this.id = id;
      this.location = location;
    }
  }

  public class Leg {
    public String fromId;
    public String toId;
    public Integer distanceM = 0;
    public Integer durationS = 0;
    public Datetime arrival;
  }

  public class RouteResult {
    public List<Leg> legs = new List<Leg>();
    public Integer distanceM = 0;
    public Integer durationS = 0;
    public String geometry;
    public String matrixSource;
  }

  // ---------------------------------------------------------------------------------------------
  // Parsing
  // ---------------------------------------------------------------------------------------------

  public static OptimizeResult parseOptimize(String body) {
    Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(body);
    OptimizeResult r = new OptimizeResult();
    for (Object o : toList(m.get('routes'))) {
      Map<String, Object> rm = (Map<String, Object>) o;
      Route route = new Route();
      route.vehicleId = toStr(rm.get('vehicle_id'));
      route.distanceM = toInt(rm.get('distance_m'));
      route.durationS = toInt(rm.get('duration_s'));
      route.serviceS = toInt(rm.get('service_s'));
      route.waitingS = toInt(rm.get('waiting_s'));
      route.startTime = dt(rm.get('start_time'));
      route.endTime = dt(rm.get('end_time'));
      route.geometry = toStr(rm.get('geometry'));
      for (Object so : toList(rm.get('steps'))) {
        route.steps.add(parseStep((Map<String, Object>) so));
      }
      r.routes.add(route);
    }
    for (Object o : toList(m.get('unassigned'))) {
      Map<String, Object> um = (Map<String, Object>) o;
      Unassigned u = new Unassigned();
      u.id = toStr(um.get('id'));
      u.taskType = toStr(um.get('type'));
      u.reason = toStr(um.get('reason'));
      u.detail = toStr(um.get('detail'));
      r.unassigned.add(u);
    }
    Map<String, Object> sm = (Map<String, Object>) m.get('summary');
    if (sm != null) {
      r.summary.routes = toInt(sm.get('routes'));
      r.summary.assigned = toInt(sm.get('assigned'));
      r.summary.unassigned = toInt(sm.get('unassigned'));
      r.summary.distanceM = toInt(sm.get('distance_m'));
      r.summary.durationS = toInt(sm.get('duration_s'));
      r.summary.serviceS = toInt(sm.get('service_s'));
      r.summary.waitingS = toInt(sm.get('waiting_s'));
      r.summary.cost = toInt(sm.get('cost'));
      r.summary.matrixSource = toStr(sm.get('matrix_source'));
      r.summary.solveMs = toInt(sm.get('solve_ms'));
      r.rawSummary = JSON.serialize(sm);
    }
    return r;
  }

  private static Step parseStep(Map<String, Object> sm) {
    Step s = new Step();
    s.stepType = toStr(sm.get('type'));
    s.id = toStr(sm.get('id'));
    s.location = loc(sm.get('location'));
    s.arrival = dt(sm.get('arrival'));
    s.departure = dt(sm.get('departure'));
    s.serviceSeconds = toInt(sm.get('service_seconds'));
    s.waitingSeconds = toInt(sm.get('waiting_seconds'));
    s.legDistanceM = toInt(sm.get('leg_distance_m'));
    s.legDurationS = toInt(sm.get('leg_duration_s'));
    s.locked = sm.get('locked') == true;
    s.lateSeconds = toInt(sm.get('late_seconds'));
    for (Object l : toList(sm.get('load'))) {
      s.load.add(toInt(l));
    }
    return s;
  }

  public static MatrixResult parseMatrix(String body) {
    Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(body);
    MatrixResult r = new MatrixResult();
    r.durations = intMatrix(m.get('durations'));
    r.distances = intMatrix(m.get('distances'));
    r.matrixSource = toStr(m.get('matrix_source'));
    return r;
  }

  public static RouteResult parseRoute(String body) {
    Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(body);
    RouteResult r = new RouteResult();
    for (Object o : toList(m.get('legs'))) {
      Map<String, Object> lm = (Map<String, Object>) o;
      Leg l = new Leg();
      l.fromId = toStr(lm.get('from_id'));
      l.toId = toStr(lm.get('to_id'));
      l.distanceM = toInt(lm.get('distance_m'));
      l.durationS = toInt(lm.get('duration_s'));
      l.arrival = dt(lm.get('arrival'));
      r.legs.add(l);
    }
    r.distanceM = toInt(m.get('distance_m'));
    r.durationS = toInt(m.get('duration_s'));
    r.geometry = toStr(m.get('geometry'));
    r.matrixSource = toStr(m.get('matrix_source'));
    return r;
  }

  // ---------------------------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------------------------

  public static List<Integer> zeros() {
    return new List<Integer>{ 0, 0, 0 };
  }

  public static List<Object> coord(Location l) {
    return l == null
      ? null
      : new List<Object>{ l.getLongitude(), l.getLatitude() };
  }

  public static Location loc(Object o) {
    List<Object> pair = toList(o);
    if (pair.size() != 2) {
      return null;
    }
    return Location.newInstance(toDec(pair[1]), toDec(pair[0]));
  }

  /** ISO 8601 in UTC, the format the service and JSON.serialize both use. */
  public static String iso(Datetime t) {
    return t == null ? null : t.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
  }

  public static Datetime dt(Object o) {
    if (o == null) {
      return null;
    }
    String s = String.valueOf(o).trim();
    if (s.endsWith('+00:00')) {
      s = s.removeEnd('+00:00') + 'Z';
    }
    return (Datetime) JSON.deserialize('"' + s + '"', Datetime.class);
  }

  private static List<Object> windowMaps(List<TimeWindow> windows) {
    List<Object> out = new List<Object>();
    for (TimeWindow w : windows) {
      out.add(w.toMap());
    }
    return out;
  }

  private static List<List<Integer>> intMatrix(Object o) {
    List<List<Integer>> out = new List<List<Integer>>();
    for (Object row : toList(o)) {
      List<Integer> r = new List<Integer>();
      for (Object v : toList(row)) {
        r.add(toInt(v));
      }
      out.add(r);
    }
    return out;
  }

  public static List<Object> toList(Object o) {
    return o instanceof List<Object> ? (List<Object>) o : new List<Object>();
  }

  public static String toStr(Object o) {
    return o == null ? null : String.valueOf(o);
  }

  public static Integer toInt(Object o) {
    return o == null
      ? 0
      : toDec(o).round(System.RoundingMode.HALF_UP).intValue();
  }

  public static Decimal toDec(Object o) {
    return o == null ? null : Decimal.valueOf(String.valueOf(o));
  }
}
