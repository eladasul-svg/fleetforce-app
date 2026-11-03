/**
 * Turns a Route_Plan__c into a solver request and a solver result back into records.
 *
 * Demand (Route_Job__c -> Job_Visit__c) is read, never reshaped: every task id in the request is a
 * Job_Visit__c Id (shipments use the Route_Job__c Id), so results map straight back to visits, and
 * visits point to the Waypoint__c that serves them. Every read and write runs in USER_MODE, so a
 * dispatcher plans only what they could see and change by hand. Callouts happen in the providers,
 * never here; callers make the callout between buildRequest() and applyResult().
 */
public with sharing class RoutePlanService {
  public static final Integer DEFAULT_SHIFT_START_HOUR = 7;
  public static final Integer DEFAULT_SHIFT_END_HOUR = 17;
  public static final Integer DEFAULT_SERVICE_MINUTES = 5;
  /** VROOM windows are hard, so a soft window is sent with this much slack after its end. */
  public static final Integer SOFT_WINDOW_GRACE_MINUTES = 30;
  public static final Integer CHARGE_MINUTES = 30;
  public static final Time CHARGE_WINDOW_START = Time.newInstance(11, 30, 0, 0);
  public static final Time CHARGE_WINDOW_END = Time.newInstance(13, 30, 0, 0);
  public static final String CHARGE_BREAK_ID = 'charge';
  public static final Integer UNLIMITED = 1000000000;

  public static final Set<String> PLANNABLE_JOB_STATUSES = new Set<String>{
    'Ready',
    'Planned'
  };
  public static final Set<String> USABLE_ASSET_STATUSES = new Set<String>{
    'Available',
    'Assigned'
  };
  public static final Set<String> RE_PLANNABLE_STATUSES = new Set<String>{
    'Draft',
    'Optimized',
    'Optimizing'
  };

  public class PlanContext {
    public Route_Plan__c plan;
    public TimeZone tz;
    public Location depot;
    public Map<Id, Fleet_Asset__c> assets = new Map<Id, Fleet_Asset__c>();
    public Map<Id, Route_Job__c> jobs = new Map<Id, Route_Job__c>();
    public Map<Id, Job_Visit__c> visits = new Map<Id, Job_Visit__c>();
    public Map<String, Id> jobOfVisit = new Map<String, Id>();
    public RoutingDtos.OptimizeRequest request = new RoutingDtos.OptimizeRequest();
  }

  // ---------------------------------------------------------------------------------------------
  // Entry points
  // ---------------------------------------------------------------------------------------------

  /** Marks the plan Optimizing and queues the callout. Returns the AsyncApexJob Id. */
  public static Id startOptimization(Id planId) {
    Route_Plan__c plan = loadPlan(planId);
    if (!RE_PLANNABLE_STATUSES.contains(plan.Status__c)) {
      throw new RoutingProviders.RoutingException(
        'A ' +
          plan.Status__c +
          ' plan cannot be re-optimized as a whole. Re-optimize individual routes instead.'
      );
    }
    plan.Status__c = 'Optimizing';
    plan.Error__c = null;
    Database.update(plan, true, AccessLevel.USER_MODE);
    return System.enqueueJob(new RoutePlanOptimizeJob(planId));
  }

  public static RoutingProvider provider(Route_Plan__c plan) {
    return RoutingProviders.forName(plan.Provider__c);
  }

  public static Route_Plan__c loadPlan(Id planId) {
    List<Route_Plan__c> rows = [
      SELECT
        Id,
        Name,
        Plan_Date__c,
        Status__c,
        Provider__c,
        Objective__c,
        Revision__c,
        Depot_Branch__c,
        Depot_Branch__r.Name,
        Depot_Branch__r.Location__Latitude__s,
        Depot_Branch__r.Location__Longitude__s,
        Depot_Branch__r.Time_Zone__c
      FROM Route_Plan__c
      WHERE Id = :planId
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw new RoutingProviders.RoutingException(
        'Route plan ' + planId + ' was not found or you cannot see it.'
      );
    }
    return rows[0];
  }

  // ---------------------------------------------------------------------------------------------
  // buildRequest
  // ---------------------------------------------------------------------------------------------

  public static PlanContext buildRequest(Id planId) {
    PlanContext ctx = new PlanContext();
    ctx.plan = loadPlan(planId);
    if (ctx.plan.Plan_Date__c == null || ctx.plan.Depot_Branch__c == null) {
      throw new RoutingProviders.RoutingException(
        'Set the plan date and depot branch before optimizing.'
      );
    }
    if (ctx.plan.Depot_Branch__r.Location__Latitude__s == null) {
      throw new RoutingProviders.RoutingException(
        'The depot branch ' +
          ctx.plan.Depot_Branch__r.Name +
          ' has no location.'
      );
    }
    ctx.depot = Location.newInstance(
      ctx.plan.Depot_Branch__r.Location__Latitude__s,
      ctx.plan.Depot_Branch__r.Location__Longitude__s
    );
    String tzId = String.isBlank(ctx.plan.Depot_Branch__r.Time_Zone__c)
      ? UserInfo.getTimeZone().getID()
      : ctx.plan.Depot_Branch__r.Time_Zone__c;
    ctx.tz = TimeZone.getTimeZone(tzId);
    ctx.request.objective = objective(ctx.plan.Objective__c);
    ctx.request.geometry = true;

    addVehicles(ctx);
    addJobs(ctx);
    return ctx;
  }

  public static String objective(String picklistValue) {
    switch on picklistValue {
      when 'Min Distance' {
        return 'min_distance';
      }
      when 'Min Vehicles' {
        return 'min_vehicles';
      }
      when 'Balanced' {
        return 'balanced';
      }
      when else {
        return 'min_duration';
      }
    }
  }

  // ---- vehicles -------------------------------------------------------------------------------

  private static void addVehicles(PlanContext ctx) {
    List<Capacity_Dimension__mdt> dims = capacityDimensions();
    Set<String> fields = new Set<String>{
      'Id',
      'Name',
      'License_Plate__c',
      'Fuel_Type__c',
      'Status__c',
      'Vehicle_Features__c',
      'Driver__c',
      'Driver__r.Name',
      'Driver__r.License_Expiry__c'
    };
    for (Capacity_Dimension__mdt d : dims) {
      if (d.Is_Active__c && String.isNotBlank(d.Asset_Field__c)) {
        fields.add(d.Asset_Field__c);
      }
    }
    Id branchId = ctx.plan.Depot_Branch__c;
    Set<String> statuses = USABLE_ASSET_STATUSES;
    List<Fleet_Asset__c> assets = Database.queryWithBinds(
      'SELECT ' +
        String.join(new List<String>(fields), ', ') +
        ' FROM Fleet_Asset__c WHERE Branch__c = :branchId AND Is_Active__c = true AND Status__c IN :statuses' +
        ' ORDER BY Name LIMIT 500',
      new Map<String, Object>{ 'branchId' => branchId, 'statuses' => statuses },
      AccessLevel.USER_MODE
    );

    Set<Id> assetIds = new Map<Id, Fleet_Asset__c>(assets).keySet();
    Set<Id> inShop = RoutingPolicy.assetsInShop(assetIds);
    Set<Id> driverIds = new Set<Id>();
    for (Fleet_Asset__c a : assets) {
      if (a.Driver__c != null) {
        driverIds.add(a.Driver__c);
      }
    }
    Map<Id, RoutingPolicy.DriverStatus> drivers = RoutingPolicy.driverStatus(
      driverIds,
      ctx.plan.Plan_Date__c
    );
    Map<Id, ShiftWindow> shifts = shifts(ctx, assetIds, driverIds);

    for (Fleet_Asset__c a : assets) {
      if (inShop.contains(a.Id)) {
        ctx.request.excludedVehicles.put(
          a.Id,
          a.Name + ': open in-shop service ticket'
        );
        continue;
      }
      RoutingPolicy.DriverStatus ds = a.Driver__c == null
        ? null
        : drivers.get(a.Driver__c);
      if (ds != null && !ds.eligible) {
        ctx.request.excludedVehicles.put(a.Id, a.Name + ': ' + ds.reason);
        continue;
      }
      ctx.assets.put(a.Id, a);

      RoutingDtos.Vehicle v = new RoutingDtos.Vehicle();
      v.id = a.Id;
      v.startLocation = ctx.depot;
      v.endLocation = ctx.depot;
      ShiftWindow shift = shifts.containsKey(a.Id)
        ? shifts.get(a.Id)
        : (a.Driver__c != null && shifts.containsKey(a.Driver__c)
            ? shifts.get(a.Driver__c)
            : null);
      v.shiftStart = shift != null
        ? shift.startTime
        : localToGmt(
            ctx.plan.Plan_Date__c,
            Time.newInstance(DEFAULT_SHIFT_START_HOUR, 0, 0, 0),
            ctx.tz
          );
      v.shiftEnd = shift != null
        ? shift.endTime
        : localToGmt(
            ctx.plan.Plan_Date__c,
            Time.newInstance(DEFAULT_SHIFT_END_HOUR, 0, 0, 0),
            ctx.tz
          );
      v.capacity = capacity(a, dims);
      v.skills = splitMulti(a.Vehicle_Features__c);
      if (ds != null) {
        v.skills.addAll(ds.skills);
      }
      if (a.Fuel_Type__c == 'Electric') {
        RoutingDtos.BreakSpec charge = new RoutingDtos.BreakSpec();
        charge.id = CHARGE_BREAK_ID;
        charge.description = 'Charge';
        charge.serviceSeconds = CHARGE_MINUTES * 60;
        charge.windows.add(
          new RoutingDtos.TimeWindow(
            localToGmt(ctx.plan.Plan_Date__c, CHARGE_WINDOW_START, ctx.tz),
            localToGmt(ctx.plan.Plan_Date__c, CHARGE_WINDOW_END, ctx.tz)
          )
        );
        v.breaks.add(charge);
      }
      ctx.request.vehicles.add(v);
    }
  }

  public static List<Capacity_Dimension__mdt> capacityDimensions() {
    List<Capacity_Dimension__mdt> dims = new List<Capacity_Dimension__mdt>();
    for (
      Capacity_Dimension__mdt d : Capacity_Dimension__mdt.getAll().values()
    ) {
      if (
        d.Slot__c != null &&
        d.Slot__c >= 1 &&
        d.Slot__c <= RoutingDtos.CAPACITY_DIMENSIONS
      ) {
        dims.add(d);
      }
    }
    return dims;
  }

  private static Capacity_Dimension__mdt dimFor(
    List<Capacity_Dimension__mdt> dims,
    Integer slot
  ) {
    for (Capacity_Dimension__mdt d : dims) {
      if (d.Slot__c == slot && d.Is_Active__c) {
        return d;
      }
    }
    return null;
  }

  /** Null (unlimited) when the asset has no capacity recorded in any active dimension. */
  @TestVisible
  private static List<Integer> capacity(
    Fleet_Asset__c a,
    List<Capacity_Dimension__mdt> dims
  ) {
    List<Integer> out = new List<Integer>();
    Boolean any = false;
    for (Integer slot = 1; slot <= RoutingDtos.CAPACITY_DIMENSIONS; slot++) {
      Capacity_Dimension__mdt d = dimFor(dims, slot);
      if (d == null) {
        out.add(0);
        continue;
      }
      Object raw = String.isBlank(d.Asset_Field__c)
        ? null
        : a.get(d.Asset_Field__c);
      if (raw == null) {
        out.add(UNLIMITED);
      } else {
        any = true;
        out.add(scaled((Decimal) raw, d));
      }
    }
    return any ? out : null;
  }

  private static Integer scaled(Decimal value, Capacity_Dimension__mdt d) {
    if (value == null) {
      return 0;
    }
    Decimal scale = d == null || d.Scale__c == null ? 1 : d.Scale__c;
    return (value.abs() * scale).round(System.RoundingMode.HALF_UP).intValue();
  }

  // ---- shifts ---------------------------------------------------------------------------------

  public class ShiftWindow {
    public Datetime startTime;
    public Datetime endTime;
  }

  /** Shift per asset or driver Id from Schedule_Assignment__c -> Schedule_Window__c for the plan's weekday. */
  private static Map<Id, ShiftWindow> shifts(
    PlanContext ctx,
    Set<Id> assetIds,
    Set<Id> driverIds
  ) {
    Map<Id, ShiftWindow> out = new Map<Id, ShiftWindow>();
    try {
      List<Schedule_Assignment__c> assignments = [
        SELECT Fleet_Asset__c, Driver__c, Fleet_Schedule__c
        FROM Schedule_Assignment__c
        WHERE Fleet_Asset__c IN :assetIds OR Driver__c IN :driverIds
        WITH USER_MODE
        LIMIT 1000
      ];
      Set<Id> scheduleIds = new Set<Id>();
      for (Schedule_Assignment__c sa : assignments) {
        scheduleIds.add(sa.Fleet_Schedule__c);
      }
      String weekday = weekday(ctx.plan.Plan_Date__c);
      Map<Id, ShiftWindow> bySchedule = new Map<Id, ShiftWindow>();
      for (Schedule_Window__c w : [
        SELECT Fleet_Schedule__c, Start_Time__c, End_Time__c
        FROM Schedule_Window__c
        WHERE
          Fleet_Schedule__c IN :scheduleIds
          AND Day_OfWeek__c = :weekday
          AND Type__c IN ('Available', 'Required')
        WITH USER_MODE
        LIMIT 2000
      ]) {
        if (w.Start_Time__c == null || w.End_Time__c == null) {
          continue;
        }
        ShiftWindow s = bySchedule.get(w.Fleet_Schedule__c);
        Datetime st = localToGmt(
          ctx.plan.Plan_Date__c,
          w.Start_Time__c,
          ctx.tz
        );
        Datetime en = localToGmt(ctx.plan.Plan_Date__c, w.End_Time__c, ctx.tz);
        if (en <= st) {
          en = en.addDays(1); // overnight window
        }
        if (s == null) {
          s = new ShiftWindow();
          s.startTime = st;
          s.endTime = en;
          bySchedule.put(w.Fleet_Schedule__c, s);
        } else {
          s.startTime = st < s.startTime ? st : s.startTime;
          s.endTime = en > s.endTime ? en : s.endTime;
        }
      }
      for (Schedule_Assignment__c sa : assignments) {
        ShiftWindow s = bySchedule.get(sa.Fleet_Schedule__c);
        if (s == null) {
          continue;
        }
        if (sa.Fleet_Asset__c != null && !out.containsKey(sa.Fleet_Asset__c)) {
          out.put(sa.Fleet_Asset__c, s);
        }
        if (sa.Driver__c != null && !out.containsKey(sa.Driver__c)) {
          out.put(sa.Driver__c, s);
        }
      }
    } catch (QueryException e) {
      // No access to schedules: every vehicle gets the default shift.
    }
    return out;
  }

  @TestVisible
  private static String weekday(Date d) {
    List<String> names = new List<String>{
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday'
    };
    Integer days = Date.newInstance(1900, 1, 7).daysBetween(d); // 1900-01-07 was a Sunday
    return names[Math.mod(Math.mod(days, 7) + 7, 7)];
  }

  /** The instant that local time t on day d is in time zone tz. */
  public static Datetime localToGmt(Date d, Time t, TimeZone tz) {
    Datetime asGmt = Datetime.newInstanceGmt(d, t);
    Integer offset = tz.getOffset(asGmt);
    offset = tz.getOffset(asGmt.addSeconds(-offset / 1000)); // settle DST edges
    return asGmt.addSeconds(-offset / 1000);
  }

  // ---- jobs -----------------------------------------------------------------------------------

  private static void addJobs(PlanContext ctx) {
    List<Capacity_Dimension__mdt> dims = capacityDimensions();
    Id branchId = ctx.plan.Depot_Branch__c;
    Date day = ctx.plan.Plan_Date__c;
    Set<String> statuses = PLANNABLE_JOB_STATUSES;
    List<Route_Job__c> jobs = [
      SELECT
        Id,
        Name,
        Type__c,
        Status__c,
        Priority__c,
        Required_Skills__c,
        (
          SELECT
            Id,
            Name,
            Role__c,
            Location__Latitude__s,
            Location__Longitude__s,
            Window_Start__c,
            Window_End__c,
            Hard_Window__c,
            Service_Minutes__c,
            Load_1__c,
            Load_2__c,
            Load_3__c,
            Address__c
          FROM Visits
          ORDER BY Name
        )
      FROM Route_Job__c
      WHERE
        Branch__c = :branchId
        AND Service_Date__c = :day
        AND Status__c IN :statuses
      WITH USER_MODE
      ORDER BY Priority__c DESC NULLS LAST, Name
      LIMIT 2000
    ];
    Datetime dayStart = localToGmt(day, Time.newInstance(0, 0, 0, 0), ctx.tz);
    for (Route_Job__c j : jobs) {
      ctx.jobs.put(j.Id, j);
      Job_Visit__c pickup;
      Job_Visit__c delivery;
      List<Job_Visit__c> others = new List<Job_Visit__c>();
      Boolean missingLocation = false;
      for (Job_Visit__c v : j.Visits) {
        ctx.visits.put(v.Id, v);
        ctx.jobOfVisit.put(v.Id, j.Id);
        if (
          v.Location__Latitude__s == null ||
          v.Location__Longitude__s == null
        ) {
          missingLocation = true;
        }
        if (v.Role__c == 'Pickup' && pickup == null) {
          pickup = v;
        } else if (v.Role__c == 'Delivery' && delivery == null) {
          delivery = v;
        } else {
          others.add(v);
        }
      }
      if (j.Visits.isEmpty()) {
        ctx.request.skippedJobs.put(j.Id, 'The job has no visits.');
        continue;
      }
      if (missingLocation) {
        ctx.request.skippedJobs.put(j.Id, 'A visit has no location.');
        continue;
      }
      List<String> skills = splitMulti(j.Required_Skills__c);
      Integer priority = j.Priority__c == null
        ? 0
        : Math.max(0, Math.min(100, j.Priority__c.intValue()));

      if (pickup != null && delivery != null && others.isEmpty()) {
        RoutingDtos.Shipment s = new RoutingDtos.Shipment();
        s.id = j.Id;
        s.pickup = shipmentStep(pickup, dayStart);
        s.delivery = shipmentStep(delivery, dayStart);
        s.amount = loads(pickup, dims);
        s.skills = skills;
        s.priority = priority;
        ctx.request.shipments.add(s);
      } else if (j.Visits.size() == 1) {
        Job_Visit__c v = j.Visits[0];
        RoutingDtos.Job job = new RoutingDtos.Job();
        job.id = v.Id;
        job.location = visitLocation(v);
        job.serviceSeconds = serviceSeconds(v);
        job.windows = windows(v, dayStart);
        if (v.Role__c == 'Pickup') {
          job.pickup = loads(v, dims);
        } else {
          job.delivery = loads(v, dims);
        }
        job.skills = skills;
        job.priority = priority;
        job.description = j.Name;
        ctx.request.jobs.add(job);
      } else {
        ctx.request.skippedJobs.put(
          j.Id,
          'Use one visit, or one Pickup and one Delivery visit.'
        );
      }
    }
  }

  private static RoutingDtos.ShipmentStep shipmentStep(
    Job_Visit__c v,
    Datetime dayStart
  ) {
    RoutingDtos.ShipmentStep s = new RoutingDtos.ShipmentStep();
    s.id = v.Id;
    s.location = visitLocation(v);
    s.serviceSeconds = serviceSeconds(v);
    s.windows = windows(v, dayStart);
    return s;
  }

  private static Location visitLocation(Job_Visit__c v) {
    return Location.newInstance(
      v.Location__Latitude__s,
      v.Location__Longitude__s
    );
  }

  private static Integer serviceSeconds(Job_Visit__c v) {
    Decimal minutes = v.Service_Minutes__c == null
      ? DEFAULT_SERVICE_MINUTES
      : v.Service_Minutes__c;
    return (minutes * 60).intValue();
  }

  @TestVisible
  private static List<RoutingDtos.TimeWindow> windows(
    Job_Visit__c v,
    Datetime dayStart
  ) {
    List<RoutingDtos.TimeWindow> out = new List<RoutingDtos.TimeWindow>();
    if (v.Window_Start__c == null && v.Window_End__c == null) {
      return out;
    }
    Datetime st = v.Window_Start__c != null ? v.Window_Start__c : dayStart;
    Datetime en = v.Window_End__c != null ? v.Window_End__c : st.addHours(24);
    if (v.Hard_Window__c != true && v.Window_End__c != null) {
      en = en.addMinutes(SOFT_WINDOW_GRACE_MINUTES);
    }
    out.add(new RoutingDtos.TimeWindow(st, en));
    return out;
  }

  private static List<Integer> loads(
    Job_Visit__c v,
    List<Capacity_Dimension__mdt> dims
  ) {
    List<Decimal> raw = new List<Decimal>{
      v.Load_1__c,
      v.Load_2__c,
      v.Load_3__c
    };
    List<Integer> out = new List<Integer>();
    for (Integer slot = 1; slot <= RoutingDtos.CAPACITY_DIMENSIONS; slot++) {
      Capacity_Dimension__mdt d = dimFor(dims, slot);
      out.add(d == null ? 0 : scaled(raw[slot - 1], d));
    }
    return out;
  }

  public static List<String> splitMulti(String value) {
    List<String> out = new List<String>();
    if (String.isBlank(value)) {
      return out;
    }
    for (String s : value.split(';')) {
      if (String.isNotBlank(s)) {
        out.add(s.trim());
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------------------------
  // applyResult
  // ---------------------------------------------------------------------------------------------

  /** Replaces the plan's routes with the solver's. DML only (USER_MODE); no callouts. */
  public static void applyResult(
    PlanContext ctx,
    RoutingDtos.OptimizeResult result
  ) {
    Route_Plan__c plan = ctx.plan;
    Integer revision =
      (plan.Revision__c == null ? 0 : plan.Revision__c.intValue()) + 1;

    List<Route__c> old = [
      SELECT Id
      FROM Route__c
      WHERE Route_Plan__c = :plan.Id
      WITH USER_MODE
      LIMIT 500
    ];
    if (!old.isEmpty()) {
      Database.delete(old, true, AccessLevel.USER_MODE);
    }

    Map<String, RoutingDtos.Vehicle> vehicles = new Map<String, RoutingDtos.Vehicle>();
    for (RoutingDtos.Vehicle v : ctx.request.vehicles) {
      vehicles.put(v.id, v);
    }

    List<Route__c> routes = new List<Route__c>();
    for (RoutingDtos.Route r : result.routes) {
      routes.add(
        newRoute(
          plan,
          ctx.assets.get(r.vehicleId),
          vehicles.get(r.vehicleId),
          r,
          revision
        )
      );
    }
    Database.insert(routes, true, AccessLevel.USER_MODE);

    WaypointBuild built = new WaypointBuild();
    for (Integer i = 0; i < routes.size(); i++) {
      buildWaypoints(
        routes[i],
        result.routes[i],
        plan.Depot_Branch__c,
        built,
        1
      );
    }
    Database.insert(built.waypoints, true, AccessLevel.USER_MODE);

    Map<Id, Route_Job__c> jobUpdates = new Map<Id, Route_Job__c>();
    List<Job_Visit__c> visitUpdates = new List<Job_Visit__c>();
    for (Integer i = 0; i < built.waypoints.size(); i++) {
      for (String visitId : built.visitsByIndex.get(i)) {
        Id jobId = ctx.jobOfVisit.get(visitId);
        if (jobId == null) {
          continue;
        }
        visitUpdates.add(
          new Job_Visit__c(
            Id = (Id) visitId,
            Waypoint__c = built.waypoints[i].Id,
            Status__c = 'Pending'
          )
        );
        jobUpdates.put(
          jobId,
          new Route_Job__c(
            Id = jobId,
            Status__c = 'Planned',
            Planned_Route__c = built.waypoints[i].Route__c,
            Unassigned_Reason__c = null
          )
        );
      }
    }
    for (RoutingDtos.Unassigned u : result.unassigned) {
      Id jobId = u.taskType == 'shipment'
        ? (Id) u.id
        : ctx.jobOfVisit.get(u.id);
      if (jobId == null) {
        continue;
      }
      jobUpdates.put(
        jobId,
        unplanned(jobId, u.reason + ': ' + (u.detail == null ? '' : u.detail))
      );
    }
    for (String jobId : ctx.request.skippedJobs.keySet()) {
      jobUpdates.put(
        (Id) jobId,
        unplanned((Id) jobId, 'skipped: ' + ctx.request.skippedJobs.get(jobId))
      );
    }
    jobUpdates.remove(null);
    if (!visitUpdates.isEmpty()) {
      Database.update(visitUpdates, true, AccessLevel.USER_MODE);
    }
    if (!jobUpdates.isEmpty()) {
      Database.update(jobUpdates.values(), true, AccessLevel.USER_MODE);
    }

    Integer unassignedCount =
      result.unassigned.size() + ctx.request.skippedJobs.size();
    Map<String, Object> summary = new Map<String, Object>{
      'revision' => revision,
      'routes' => result.routes.size(),
      'assigned' => result.summary.assigned,
      'unassigned' => unassignedCount,
      'matrixSource' => result.summary.matrixSource,
      'excludedVehicles' => ctx.request.excludedVehicles.values(),
      'skippedJobs' => ctx.request.skippedJobs.size(),
      'solver' => result.rawSummary == null
        ? null
        : JSON.deserializeUntyped(result.rawSummary)
    };
    plan.Status__c = 'Optimized';
    plan.Revision__c = revision;
    plan.Last_Optimized_At__c = System.now();
    plan.Unassigned_Count__c = unassignedCount;
    plan.Total_Distance_Km__c = (Decimal.valueOf(result.summary.distanceM) /
      1000)
      .setScale(2);
    plan.Total_Duration_Min__c = minutes(result.summary.durationS);
    plan.Solver_Summary__c = JSON.serialize(summary).abbreviate(131072);
    plan.Error__c = null;
    Database.update(
      new Route_Plan__c(
        Id = plan.Id,
        Status__c = plan.Status__c,
        Revision__c = plan.Revision__c,
        Last_Optimized_At__c = plan.Last_Optimized_At__c,
        Unassigned_Count__c = plan.Unassigned_Count__c,
        Total_Distance_Km__c = plan.Total_Distance_Km__c,
        Total_Duration_Min__c = plan.Total_Duration_Min__c,
        Solver_Summary__c = plan.Solver_Summary__c,
        Error__c = null
      ),
      true,
      AccessLevel.USER_MODE
    );
    RouteEvents.log(
      RouteEvents.event('Optimized', 'System').forPlan(plan.Id).payload(summary)
    );
  }

  private static Route_Job__c unplanned(Id jobId, String reason) {
    return new Route_Job__c(
      Id = jobId,
      Status__c = 'Ready',
      Planned_Route__c = null,
      Unassigned_Reason__c = reason.abbreviate(255)
    );
  }

  private static Route__c newRoute(
    Route_Plan__c plan,
    Fleet_Asset__c asset,
    RoutingDtos.Vehicle v,
    RoutingDtos.Route r,
    Integer revision
  ) {
    String driverName = asset == null ||
      asset.Driver__r == null
      ? null
      : asset.Driver__r.Name;
    String name =
      (asset == null ? r.vehicleId : asset.Name) +
      (driverName == null ? '' : ' · ' + driverName);
    Route__c route = new Route__c(
      Route_Plan__c = plan.Id,
      Name = name.abbreviate(80),
      Fleet_Asset__c = asset == null ? null : asset.Id,
      Driver__c = asset == null ? null : asset.Driver__c,
      Status__c = 'Planned',
      Shift_Start__c = v == null ? null : v.shiftStart,
      Shift_End__c = v == null ? null : v.shiftEnd,
      Planned_Start__c = r.startTime,
      Planned_End__c = r.endTime,
      Planned_Distance_Km__c = (Decimal.valueOf(r.distanceM) / 1000)
        .setScale(2),
      Planned_Duration_Min__c = minutes(r.durationS),
      Revision__c = revision,
      Geometry__c = r.geometry == null ? null : r.geometry.abbreviate(131072)
    );
    if (v != null && v.startLocation != null) {
      route.Start_Location__Latitude__s = v.startLocation.getLatitude();
      route.Start_Location__Longitude__s = v.startLocation.getLongitude();
    }
    if (v != null && v.endLocation != null) {
      route.End_Location__Latitude__s = v.endLocation.getLatitude();
      route.End_Location__Longitude__s = v.endLocation.getLongitude();
    }
    return route;
  }

  public class WaypointBuild {
    public List<Waypoint__c> waypoints = new List<Waypoint__c>();
    /** Visit Ids served by waypoints[i]. */
    public Map<Integer, List<String>> visitsByIndex = new Map<Integer, List<String>>();
  }

  /**
   * One Waypoint__c per stop. Consecutive task steps at the same place become one waypoint that
   * serves several visits (two drops at one address are one stop).
   */
  public static void buildWaypoints(
    Route__c route,
    RoutingDtos.Route r,
    Id depotBranchId,
    WaypointBuild built,
    Integer firstSequence
  ) {
    Integer seq = firstSequence;
    Waypoint__c previous;
    for (RoutingDtos.Step s : r.steps) {
      if (
        previous != null &&
        s.isTask() &&
        previous.Type__c == 'Job Stop' &&
        sameLocation(previous, s.location)
      ) {
        previous.Planned_Departure__c = s.departure;
        previous.Service_Minutes__c += minutes(s.serviceSeconds);
        previous.Wait_Minutes__c += minutes(s.waitingSeconds);
        previous.Locked__c = previous.Locked__c || s.locked;
        built.visitsByIndex.get(built.waypoints.size() - 1).add(s.id);
        continue;
      }
      Waypoint__c w = new Waypoint__c(
        Route__c = route.Id,
        Sequence__c = seq++,
        Type__c = waypointType(s),
        Planned_Arrival__c = s.arrival,
        Planned_Departure__c = s.departure,
        ETA__c = s.arrival,
        Status__c = 'Planned',
        Locked__c = s.locked,
        Service_Minutes__c = minutes(s.serviceSeconds),
        Wait_Minutes__c = minutes(s.waitingSeconds),
        Leg_Distance_Km__c = (Decimal.valueOf(s.legDistanceM) / 1000)
          .setScale(2),
        Leg_Duration_Min__c = minutes(s.legDurationS),
        Late_Minutes__c = s.lateSeconds > 0 ? minutes(s.lateSeconds) : null,
        Solver_Step_Id__c = s.id == null ? null : s.id.abbreviate(40),
        Branch__c = (s.stepType == 'start' ||
          s.stepType == 'end')
          ? depotBranchId
          : null
      );
      if (s.location != null) {
        w.Location__Latitude__s = s.location.getLatitude();
        w.Location__Longitude__s = s.location.getLongitude();
      }
      built.waypoints.add(w);
      built.visitsByIndex.put(
        built.waypoints.size() - 1,
        s.isTask() ? new List<String>{ s.id } : new List<String>()
      );
      previous = w;
    }
  }

  private static Boolean sameLocation(Waypoint__c w, Location l) {
    return l != null &&
      w.Location__Latitude__s != null &&
      Math.abs(w.Location__Latitude__s - l.getLatitude()) < 0.00001 &&
      Math.abs(w.Location__Longitude__s - l.getLongitude()) < 0.00001;
  }

  public static String waypointType(RoutingDtos.Step s) {
    switch on s.stepType {
      when 'start' {
        return 'Start';
      }
      when 'end' {
        return 'End';
      }
      when 'break' {
        return s.id != null && s.id.startsWith(CHARGE_BREAK_ID)
          ? 'Charge'
          : 'Break';
      }
      when else {
        return 'Job Stop';
      }
    }
  }

  public static Integer minutes(Integer seconds) {
    return seconds == null
      ? 0
      : (Decimal.valueOf(seconds) / 60)
          .round(System.RoundingMode.HALF_UP)
          .intValue();
  }

  // ---------------------------------------------------------------------------------------------
  // Failure and publish
  // ---------------------------------------------------------------------------------------------

  public static void recordFailure(Id planId, String message) {
    Database.update(
      new Route_Plan__c(
        Id = planId,
        Status__c = 'Draft',
        Error__c = message == null ? null : message.abbreviate(32768)
      ),
      true,
      AccessLevel.USER_MODE
    );
    RouteEvents.log(
      RouteEvents.event('Optimization Failed', 'System')
        .forPlan(planId)
        .payload(new Map<String, Object>{ 'error' => message })
    );
  }

  /**
   * Publishes an optimized plan: each route gets an Allocation__c so the motorpool sees the van as in
   * use, after the same overlap check the motorpool applies.
   */
  public static void publishPlan(Id planId) {
    Route_Plan__c plan = loadPlan(planId);
    if (plan.Status__c != 'Optimized') {
      throw new RoutingProviders.RoutingException(
        'Only an Optimized plan can be published.'
      );
    }
    List<Route__c> routes = [
      SELECT
        Id,
        Name,
        Fleet_Asset__c,
        Driver__c,
        Planned_Start__c,
        Planned_End__c,
        Allocation__c
      FROM Route__c
      WHERE Route_Plan__c = :planId
      WITH USER_MODE
      LIMIT 500
    ];
    List<String> conflicts = RoutingPolicy.allocationConflicts(routes);
    if (!conflicts.isEmpty()) {
      throw new RoutingProviders.RoutingException(
        'Cannot publish: ' + String.join(conflicts, '; ')
      );
    }
    List<Allocation__c> allocations = new List<Allocation__c>();
    List<Route__c> withAllocation = new List<Route__c>();
    for (Route__c r : routes) {
      if (r.Fleet_Asset__c == null || r.Allocation__c != null) {
        continue;
      }
      allocations.add(
        new Allocation__c(
          Name = ('Route ' + r.Name).abbreviate(80),
          Fleet_Asset__c = r.Fleet_Asset__c,
          Driver__c = r.Driver__c,
          Scheduled_Start__c = r.Planned_Start__c,
          Scheduled_End__c = r.Planned_End__c,
          Origin_Branch__c = plan.Depot_Branch__c,
          Return_Branch__c = plan.Depot_Branch__c,
          Status__c = 'Confirmed'
        )
      );
      withAllocation.add(r);
    }
    Database.insert(allocations, true, AccessLevel.USER_MODE);
    for (Integer i = 0; i < withAllocation.size(); i++) {
      withAllocation[i].Allocation__c = allocations[i].Id;
    }
    for (Route__c r : routes) {
      r.Status__c = 'Published';
    }
    Database.update(routes, true, AccessLevel.USER_MODE);
    Database.update(
      new Route_Plan__c(Id = planId, Status__c = 'Published'),
      true,
      AccessLevel.USER_MODE
    );
    RouteEvents.log(
      RouteEvents.event('Published', 'Dispatcher')
        .forPlan(planId)
        .payload(
          new Map<String, Object>{
            'routes' => routes.size(),
            'allocations' => allocations.size()
          }
        )
    );
  }
}
