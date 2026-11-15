/**
 * In-day changes to one Route__c: re-optimizing its remaining stops, moving a visit to another route,
 * and the before/after difference the dispatcher (or driver) approves.
 *
 * Re-optimizing is modelled as the design describes: the vehicle starts from where it is now, at now
 * plus any reported delay, with only the remaining visits; locked stops are sent as a fixed prefix.
 * Completed, arrived and skipped waypoints are history and never touched. Reads and writes run in
 * USER_MODE; building a request reads only, applying a result writes only, and the callout sits between.
 */
public with sharing class RouteReplanService {
  public static final Set<String> DONE_STATUSES = new Set<String>{
    'Completed',
    'Arrived',
    'Skipped',
    'Failed'
  };
  public static final Integer BREAK_WINDOW_MINUTES = 60;

  public class RouteContext {
    public Route__c route;
    public List<Waypoint__c> done = new List<Waypoint__c>();
    public List<Waypoint__c> remaining = new List<Waypoint__c>();
    public Map<Id, Job_Visit__c> visits = new Map<Id, Job_Visit__c>();
    public Integer delayMinutes = 0;
    public Datetime startTime;
    public Location startLocation;
    public RoutingDtos.OptimizeRequest request = new RoutingDtos.OptimizeRequest();
    /** Visit Ids in the order they are planned before the change. */
    public List<String> beforeOrder = new List<String>();
    public Map<String, Datetime> beforeEta = new Map<String, Datetime>();
  }

  // ---------------------------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------------------------

  public static Route__c loadRoute(Id routeId) {
    List<Route__c> rows = [
      SELECT
        Id,
        Name,
        Status__c,
        Revision__c,
        Route_Plan__c,
        Route_Plan__r.Name,
        Route_Plan__r.Plan_Date__c,
        Route_Plan__r.Provider__c,
        Route_Plan__r.Status__c,
        Route_Plan__r.Depot_Branch__c,
        Fleet_Asset__c,
        Fleet_Asset__r.Name,
        Fleet_Asset__r.Vehicle_Features__c,
        Fleet_Asset__r.Fuel_Type__c,
        Fleet_Asset__r.Payload_Kg__c,
        Fleet_Asset__r.Cargo_Volume_M3__c,
        Fleet_Asset__r.Pallet_Capacity__c,
        Fleet_Asset__r.Last_Location__Latitude__s,
        Fleet_Asset__r.Last_Location__Longitude__s,
        Driver__c,
        Driver__r.Name,
        Driver__r.Related_User__c,
        Start_Location__Latitude__s,
        Start_Location__Longitude__s,
        End_Location__Latitude__s,
        End_Location__Longitude__s,
        Shift_Start__c,
        Shift_End__c,
        Planned_Start__c,
        Planned_End__c,
        Planned_Distance_Km__c,
        Planned_Duration_Min__c
      FROM Route__c
      WHERE Id = :routeId
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw new RoutingProviders.RoutingException(
        'Route ' + routeId + ' was not found or you cannot see it.'
      );
    }
    return rows[0];
  }

  public static List<Waypoint__c> waypoints(Id routeId) {
    return [
      SELECT
        Id,
        Name,
        Sequence__c,
        Type__c,
        Status__c,
        Locked__c,
        Location__Latitude__s,
        Location__Longitude__s,
        Planned_Arrival__c,
        Planned_Departure__c,
        ETA__c,
        Actual_Arrival__c,
        Actual_Departure__c,
        Service_Minutes__c,
        Leg_Distance_Km__c,
        Reason__c,
        Solver_Step_Id__c
      FROM Waypoint__c
      WHERE Route__c = :routeId
      WITH USER_MODE
      ORDER BY Sequence__c
      LIMIT 1000
    ];
  }

  /** Visits planned on the route plus any extra visits (an incoming handoff). */
  public static Map<Id, Job_Visit__c> visits(
    Id routeId,
    Set<Id> extraVisitIds
  ) {
    Set<Id> extra = extraVisitIds == null ? new Set<Id>() : extraVisitIds;
    return new Map<Id, Job_Visit__c>(
      [
        SELECT
          Id,
          Name,
          Role__c,
          Status__c,
          Waypoint__c,
          Waypoint__r.Route__c,
          Location__Latitude__s,
          Location__Longitude__s,
          Window_Start__c,
          Window_End__c,
          Hard_Window__c,
          Service_Minutes__c,
          Load_1__c,
          Load_2__c,
          Load_3__c,
          Address__c,
          Access_Notes__c,
          Route_Job__c,
          Route_Job__r.Name,
          Route_Job__r.Priority__c,
          Route_Job__r.Required_Skills__c,
          Route_Job__r.Status__c
        FROM Job_Visit__c
        WHERE Waypoint__r.Route__c = :routeId OR Id IN :extra
        WITH USER_MODE
        LIMIT 2000
      ]
    );
  }

  /** Delay Reported minutes since the route was last re-optimized. */
  public static Integer pendingDelayMinutes(Id routeId) {
    Integer total = 0;
    for (Route_Event__c e : [
      SELECT Type__c, Payload__c
      FROM Route_Event__c
      WHERE Route__c = :routeId AND Type__c IN ('Delay Reported', 'Reoptimized')
      WITH USER_MODE
      ORDER BY Occurred_At__c DESC, Name DESC
      LIMIT 200
    ]) {
      if (e.Type__c == 'Reoptimized') {
        break;
      }
      total += delayOf(e.Payload__c);
    }
    return total;
  }

  public static Integer delayOf(String payload) {
    try {
      Object m = ((Map<String, Object>) JSON.deserializeUntyped(payload))
        .get('minutes');
      return m == null ? 0 : RoutingDtos.toInt(m);
    } catch (Exception e) {
      return 0;
    }
  }

  // ---------------------------------------------------------------------------------------------
  // Building the request
  // ---------------------------------------------------------------------------------------------

  /**
   * @param lockedWaypointIds extra waypoints to keep in their current order at the front
   * @param extraDelayMinutes delay not yet written as an event (reported in this same turn)
   * @param addVisitIds visits to add (handoff in); removeVisitIds visits to drop (handoff out)
   */
  public static RouteContext buildRequest(
    Id routeId,
    Set<Id> lockedWaypointIds,
    Integer extraDelayMinutes,
    Set<Id> addVisitIds,
    Set<Id> removeVisitIds
  ) {
    RouteContext ctx = new RouteContext();
    ctx.route = loadRoute(routeId);
    if (
      ctx.route.Status__c == 'Completed' ||
      ctx.route.Status__c == 'Cancelled'
    ) {
      throw new RoutingProviders.RoutingException(
        'A ' + ctx.route.Status__c + ' route cannot be re-planned.'
      );
    }
    Set<Id> locked = lockedWaypointIds == null
      ? new Set<Id>()
      : lockedWaypointIds;
    Set<Id> removed = removeVisitIds == null ? new Set<Id>() : removeVisitIds;
    for (Waypoint__c w : waypoints(routeId)) {
      // The start is history once the route exists: the van continues from where it is.
      if (DONE_STATUSES.contains(w.Status__c) || w.Type__c == 'Start') {
        ctx.done.add(w);
      } else {
        ctx.remaining.add(w);
      }
    }
    ctx.visits = visits(routeId, addVisitIds);
    ctx.delayMinutes =
      pendingDelayMinutes(routeId) +
      (extraDelayMinutes == null ? 0 : extraDelayMinutes);

    // Where and when the vehicle continues from.
    Datetime lastDeparture;
    Location lastPlace;
    for (Waypoint__c w : ctx.done) {
      Datetime dep = w.Actual_Departure__c != null
        ? w.Actual_Departure__c
        : w.Planned_Departure__c;
      if (dep != null && (lastDeparture == null || dep > lastDeparture)) {
        lastDeparture = dep;
      }
      if (w.Location__Latitude__s != null) {
        lastPlace = Location.newInstance(
          w.Location__Latitude__s,
          w.Location__Longitude__s
        );
      }
    }
    Datetime now = System.now();
    Datetime base = lastDeparture != null &&
      lastDeparture > now
      ? lastDeparture
      : now;
    if (ctx.route.Shift_Start__c != null && ctx.route.Shift_Start__c > base) {
      base = ctx.route.Shift_Start__c;
    }
    ctx.startTime = base.addMinutes(ctx.delayMinutes);
    if (
      ctx.route.Fleet_Asset__r != null &&
      ctx.route.Fleet_Asset__r.Last_Location__Latitude__s != null
    ) {
      ctx.startLocation = Location.newInstance(
        ctx.route.Fleet_Asset__r.Last_Location__Latitude__s,
        ctx.route.Fleet_Asset__r.Last_Location__Longitude__s
      );
    } else if (lastPlace != null) {
      ctx.startLocation = lastPlace;
    } else {
      ctx.startLocation = Location.newInstance(
        ctx.route.Start_Location__Latitude__s,
        ctx.route.Start_Location__Longitude__s
      );
    }

    RoutingDtos.Vehicle v = new RoutingDtos.Vehicle();
    v.id = ctx.route.Id;
    v.startLocation = ctx.startLocation;
    if (ctx.route.End_Location__Latitude__s != null) {
      v.endLocation = Location.newInstance(
        ctx.route.End_Location__Latitude__s,
        ctx.route.End_Location__Longitude__s
      );
    }
    v.shiftStart = ctx.startTime;
    v.shiftEnd = ctx.route.Shift_End__c != null &&
      ctx.route.Shift_End__c > ctx.startTime
      ? ctx.route.Shift_End__c
      : ctx.startTime.addHours(1);
    if (ctx.route.Fleet_Asset__r != null) {
      v.capacity = RoutePlanService.capacity(
        ctx.route.Fleet_Asset__r,
        RoutePlanService.capacityDimensions()
      );
      v.skills = RoutePlanService.splitMulti(
        ctx.route.Fleet_Asset__r.Vehicle_Features__c
      );
    }
    if (ctx.route.Driver__c != null) {
      Date day = ctx.route.Route_Plan__r.Plan_Date__c == null
        ? Date.today()
        : ctx.route.Route_Plan__r.Plan_Date__c;
      RoutingPolicy.DriverStatus ds = RoutingPolicy.driverStatus(
          new Set<Id>{ ctx.route.Driver__c },
          day
        )
        .get(ctx.route.Driver__c);
      if (ds != null) {
        v.skills.addAll(ds.skills);
      }
    }

    // Remaining breaks and charge stops travel with the route, inside an hour either side.
    List<String> fixedIds = new List<String>();
    for (Waypoint__c w : ctx.remaining) {
      if (
        (w.Type__c == 'Break' || w.Type__c == 'Charge') &&
        w.Planned_Arrival__c != null
      ) {
        RoutingDtos.BreakSpec b = new RoutingDtos.BreakSpec();
        b.id =
          (w.Type__c == 'Charge' ? RoutePlanService.CHARGE_BREAK_ID : 'break') +
          '-' +
          w.Id;
        b.description = w.Type__c;
        b.serviceSeconds =
          (w.Service_Minutes__c == null ? 0 : w.Service_Minutes__c.intValue()) *
          60;
        Datetime windowFrom = w.Planned_Arrival__c.addMinutes(
          -BREAK_WINDOW_MINUTES
        );
        b.windows.add(
          new RoutingDtos.TimeWindow(
            windowFrom < ctx.startTime ? ctx.startTime : windowFrom,
            w.Planned_Arrival__c.addMinutes(
              BREAK_WINDOW_MINUTES + ctx.delayMinutes
            )
          )
        );
        if (b.windows[0].endTime > b.windows[0].startTime) {
          v.breaks.add(b);
        }
      }
    }
    ctx.request.vehicles.add(v);

    // Visits: remaining job stops in their current order, then any added visits.
    Map<Id, List<Job_Visit__c>> visitsByWaypoint = new Map<Id, List<Job_Visit__c>>();
    List<Job_Visit__c> added = new List<Job_Visit__c>();
    for (Job_Visit__c jv : ctx.visits.values()) {
      if (
        removed.contains(jv.Id) ||
        jv.Status__c == 'Done' ||
        jv.Status__c == 'Failed'
      ) {
        continue;
      }
      if (jv.Waypoint__c != null && jv.Waypoint__r.Route__c == routeId) {
        if (!visitsByWaypoint.containsKey(jv.Waypoint__c)) {
          visitsByWaypoint.put(jv.Waypoint__c, new List<Job_Visit__c>());
        }
        visitsByWaypoint.get(jv.Waypoint__c).add(jv);
      } else {
        added.add(jv);
      }
    }
    List<Job_Visit__c> ordered = new List<Job_Visit__c>();
    for (Waypoint__c w : ctx.remaining) {
      if (!visitsByWaypoint.containsKey(w.Id)) {
        continue;
      }
      for (Job_Visit__c jv : visitsByWaypoint.get(w.Id)) {
        ordered.add(jv);
        ctx.beforeOrder.add(jv.Id);
        ctx.beforeEta.put(
          jv.Id,
          w.ETA__c != null ? w.ETA__c : w.Planned_Arrival__c
        );
        if (w.Locked__c || locked.contains(w.Id)) {
          fixedIds.add(jv.Id);
        }
      }
    }
    ordered.addAll(added);
    addTasks(ctx, ordered);
    if (!fixedIds.isEmpty()) {
      ctx.request.fixed.add(new RoutingDtos.FixedSteps(ctx.route.Id, fixedIds));
    }
    return ctx;
  }

  private static void addTasks(RouteContext ctx, List<Job_Visit__c> ordered) {
    List<Capacity_Dimension__mdt> dims = RoutePlanService.capacityDimensions();
    Map<Id, Job_Visit__c> pickupByJob = new Map<Id, Job_Visit__c>();
    Map<Id, Job_Visit__c> deliveryByJob = new Map<Id, Job_Visit__c>();
    for (Job_Visit__c jv : ordered) {
      if (jv.Role__c == 'Pickup') {
        pickupByJob.put(jv.Route_Job__c, jv);
      } else if (jv.Role__c == 'Delivery') {
        deliveryByJob.put(jv.Route_Job__c, jv);
      }
    }
    Datetime dayStart = ctx.startTime.addHours(-24);
    Set<Id> shipped = new Set<Id>();
    for (Job_Visit__c jv : ordered) {
      if (jv.Location__Latitude__s == null) {
        ctx.request.skippedJobs.put(
          jv.Route_Job__c,
          'A visit has no location.'
        );
        continue;
      }
      List<String> skills = RoutePlanService.splitMulti(
        jv.Route_Job__r.Required_Skills__c
      );
      Integer priority = jv.Route_Job__r.Priority__c == null
        ? 0
        : jv.Route_Job__r.Priority__c.intValue();
      Job_Visit__c p = pickupByJob.get(jv.Route_Job__c);
      Job_Visit__c d = deliveryByJob.get(jv.Route_Job__c);
      if (p != null && d != null) {
        if (shipped.add(jv.Route_Job__c)) {
          RoutingDtos.Shipment s = new RoutingDtos.Shipment();
          s.id = jv.Route_Job__c;
          s.pickup = RoutePlanService.shipmentStep(p, dayStart);
          s.delivery = RoutePlanService.shipmentStep(d, dayStart);
          s.amount = RoutePlanService.loads(p, dims);
          s.skills = skills;
          s.priority = priority;
          ctx.request.shipments.add(s);
        }
        continue;
      }
      RoutingDtos.Job job = new RoutingDtos.Job();
      job.id = jv.Id;
      job.location = Location.newInstance(
        jv.Location__Latitude__s,
        jv.Location__Longitude__s
      );
      job.serviceSeconds = RoutePlanService.serviceSeconds(jv);
      job.windows = RoutePlanService.windows(jv, dayStart);
      if (jv.Role__c == 'Pickup') {
        job.pickup = RoutePlanService.loads(jv, dims);
      } else {
        // A delivery whose pickup is already done is on board: a plain delivery.
        job.delivery = RoutePlanService.loads(jv, dims);
      }
      job.skills = skills;
      job.priority = priority;
      job.description = jv.Route_Job__r.Name;
      ctx.request.jobs.add(job);
    }
  }

  // ---------------------------------------------------------------------------------------------
  // The difference
  // ---------------------------------------------------------------------------------------------

  /** Before/after for the approval card and the Route_Event__c payload. */
  public static Map<String, Object> diff(
    RouteContext ctx,
    RoutingDtos.OptimizeResult result
  ) {
    RoutingDtos.Route r = result.routeFor(ctx.route.Id);
    List<String> after = new List<String>();
    List<Object> etaChanges = new List<Object>();
    List<String> late = new List<String>();
    List<String> lateHard = new List<String>();
    if (r != null) {
      for (RoutingDtos.Step s : r.steps) {
        if (!s.isTask()) {
          continue;
        }
        after.add(s.id);
        Job_Visit__c jv = ctx.visits.get((Id) s.id);
        Datetime before = ctx.beforeEta.get(s.id);
        Integer delta = before == null ||
          s.arrival == null
          ? null
          : ((s.arrival.getTime() - before.getTime()) / 60000).intValue();
        etaChanges.add(
          new Map<String, Object>{
            'visitId' => s.id,
            'name' => jv == null ? s.id : label(jv),
            'eta' => RoutingDtos.iso(s.arrival),
            'deltaMinutes' => delta,
            'locked' => s.locked
          }
        );
        Datetime serviceStart = s.arrival == null
          ? null
          : s.arrival.addSeconds(s.waitingSeconds);
        Boolean isLate =
          s.lateSeconds > 0 ||
          (jv != null &&
          jv.Window_End__c != null &&
          serviceStart > jv.Window_End__c);
        if (isLate) {
          late.add(jv == null ? s.id : label(jv));
          if (jv != null && jv.Hard_Window__c == true) {
            lateHard.add(label(jv));
          }
        }
      }
    }
    List<Object> unassigned = new List<Object>();
    for (RoutingDtos.Unassigned u : result.unassigned) {
      Job_Visit__c jv = u.taskType == 'shipment'
        ? null
        : ctx.visits.get((Id) u.id);
      unassigned.add(
        new Map<String, Object>{
          'id' => u.id,
          'name' => jv == null ? u.id : label(jv),
          'reason' => u.reason,
          'detail' => u.detail
        }
      );
    }
    Integer moved = 0;
    List<String> beforeComparable = new List<String>();
    for (String id : ctx.beforeOrder) {
      if (after.contains(id)) {
        beforeComparable.add(id);
      }
    }
    for (Integer i = 0; i < beforeComparable.size() && i < after.size(); i++) {
      if (beforeComparable[i] != after[i]) {
        moved++;
      }
    }
    return new Map<String, Object>{
      'routeId' => ctx.route.Id,
      'delayMinutes' => ctx.delayMinutes,
      'start' => RoutingDtos.iso(ctx.startTime),
      'before' => names(ctx, ctx.beforeOrder),
      'after' => names(ctx, after),
      'movedStops' => moved,
      'etaChanges' => etaChanges,
      'late' => late,
      'lateHardWindows' => lateHard,
      'unassigned' => unassigned,
      'plannedEnd' => r == null ? null : RoutingDtos.iso(r.endTime),
      'distanceKm' => r == null
        ? 0
        : (Decimal.valueOf(r.distanceM) / 1000).setScale(1)
    };
  }

  private static List<String> names(RouteContext ctx, List<String> visitIds) {
    List<String> out = new List<String>();
    for (String id : visitIds) {
      Job_Visit__c jv = ctx.visits.get((Id) id);
      out.add(jv == null ? id : label(jv));
    }
    return out;
  }

  public static String label(Job_Visit__c jv) {
    String job = jv.Route_Job__r == null ? null : jv.Route_Job__r.Name;
    return (job == null
        ? jv.Name
        : job + (jv.Role__c == 'Pickup' ? ' pickup' : '')) +
      (String.isBlank(jv.Address__c)
        ? ''
        : ' (' + jv.Address__c.abbreviate(40) + ')');
  }

  // ---------------------------------------------------------------------------------------------
  // Applying
  // ---------------------------------------------------------------------------------------------

  /** Replaces the route's remaining waypoints with the solver's. DML only. */
  public static void apply(
    RouteContext ctx,
    RoutingDtos.OptimizeResult result,
    Id sessionId,
    String actorType
  ) {
    Route__c route = ctx.route;
    Integer revision =
      (route.Revision__c == null ? 0 : route.Revision__c.intValue()) + 1;
    if (!ctx.remaining.isEmpty()) {
      Database.delete(ctx.remaining, true, AccessLevel.USER_MODE);
    }
    Integer nextSeq = 1;
    for (Waypoint__c w : ctx.done) {
      if (w.Sequence__c != null && w.Sequence__c.intValue() >= nextSeq) {
        nextSeq = w.Sequence__c.intValue() + 1;
      }
    }
    // The start step is where the van is now, not a stop.
    RoutingDtos.Route solved = result.routeFor(route.Id);
    RoutingDtos.Route r = new RoutingDtos.Route();
    if (solved != null) {
      for (RoutingDtos.Step s : solved.steps) {
        if (s.stepType != 'start') {
          r.steps.add(s);
        }
      }
    }
    RoutePlanService.WaypointBuild built = new RoutePlanService.WaypointBuild();
    RoutePlanService.buildWaypoints(
      route,
      r,
      route.Route_Plan__r.Depot_Branch__c,
      built,
      nextSeq
    );
    Database.insert(built.waypoints, true, AccessLevel.USER_MODE);

    List<Job_Visit__c> visitUpdates = new List<Job_Visit__c>();
    Map<Id, Route_Job__c> jobUpdates = new Map<Id, Route_Job__c>();
    for (Integer i = 0; i < built.waypoints.size(); i++) {
      for (String visitId : built.visitsByIndex.get(i)) {
        Job_Visit__c jv = ctx.visits.get((Id) visitId);
        visitUpdates.add(
          new Job_Visit__c(
            Id = (Id) visitId,
            Waypoint__c = built.waypoints[i].Id
          )
        );
        if (jv != null) {
          jobUpdates.put(
            jv.Route_Job__c,
            new Route_Job__c(
              Id = jv.Route_Job__c,
              Planned_Route__c = route.Id,
              Unassigned_Reason__c = null
            )
          );
        }
      }
    }
    for (RoutingDtos.Unassigned u : result.unassigned) {
      Id jobId = u.taskType == 'shipment'
        ? (Id) u.id
        : (ctx.visits.containsKey((Id) u.id)
            ? ctx.visits.get((Id) u.id).Route_Job__c
            : null);
      if (jobId != null) {
        jobUpdates.put(
          jobId,
          new Route_Job__c(
            Id = jobId,
            Status__c = 'Ready',
            Planned_Route__c = null,
            Unassigned_Reason__c = (u.reason +
              ': ' +
              (u.detail == null ? '' : u.detail))
              .abbreviate(255)
          )
        );
      }
    }
    if (!visitUpdates.isEmpty()) {
      Database.update(visitUpdates, true, AccessLevel.USER_MODE);
    }
    if (!jobUpdates.isEmpty()) {
      Database.update(jobUpdates.values(), true, AccessLevel.USER_MODE);
    }

    Decimal doneKm = 0;
    for (Waypoint__c w : ctx.done) {
      doneKm += w.Leg_Distance_Km__c == null ? 0 : w.Leg_Distance_Km__c;
    }
    Route__c upd = new Route__c(Id = route.Id, Revision__c = revision);
    if (solved != null) {
      upd.Planned_End__c = solved.endTime;
      upd.Planned_Distance_Km__c = (doneKm +
        Decimal.valueOf(solved.distanceM) / 1000)
        .setScale(2);
      upd.Geometry__c = solved.geometry == null
        ? null
        : solved.geometry.abbreviate(131072);
    }
    Database.update(upd, true, AccessLevel.USER_MODE);
    route.Revision__c = revision;
  }
}
