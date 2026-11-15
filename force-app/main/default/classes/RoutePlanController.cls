/**
 * Backs the routePlanBoard LWC on a Route_Plan__c record page. getBoard only reads (it is cacheable, so
 * it must never make a callout: the fleetListMap lesson); optimize queues the callout in a Queueable.
 */
public with sharing class RoutePlanController {
  public class Stop {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public Integer sequence;
    @AuraEnabled
    public String type;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Datetime eta;
    @AuraEnabled
    public Boolean locked;
    @AuraEnabled
    public Decimal latitude;
    @AuraEnabled
    public Decimal longitude;
    @AuraEnabled
    public Decimal lateMinutes;
    @AuraEnabled
    public List<String> jobs = new List<String>();
  }

  public class RouteView {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String vehicle;
    @AuraEnabled
    public String driver;
    @AuraEnabled
    public Datetime plannedStart;
    @AuraEnabled
    public Datetime plannedEnd;
    @AuraEnabled
    public Decimal distanceKm;
    @AuraEnabled
    public Integer jobStops = 0;
    /** Encoded polyline (precision 5) of the road path, for the map. */
    @AuraEnabled
    public String geometry;
    @AuraEnabled
    public List<Stop> stops = new List<Stop>();
  }

  public class JobView {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String type;
    @AuraEnabled
    public String reason;
  }

  public class Board {
    @AuraEnabled
    public Id planId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Date planDate;
    @AuraEnabled
    public String depot;
    @AuraEnabled
    public Decimal revision;
    @AuraEnabled
    public Datetime lastOptimizedAt;
    @AuraEnabled
    public Decimal totalDistanceKm;
    @AuraEnabled
    public Decimal totalDurationMin;
    @AuraEnabled
    public Decimal unassignedCount;
    @AuraEnabled
    public String error;
    @AuraEnabled
    public Boolean canOptimize;
    @AuraEnabled
    public Boolean canPublish;
    /** empApi channel for Route_Plan_Update__e, namespace-qualified. */
    @AuraEnabled
    public String channel;
    @AuraEnabled
    public List<RouteView> routes = new List<RouteView>();
    @AuraEnabled
    public List<JobView> unassigned = new List<JobView>();
  }

  @AuraEnabled(cacheable=true)
  public static Board getBoard(Id planId) {
    try {
      return buildBoard(planId);
    } catch (Exception e) {
      throw auraError(e);
    }
  }

  @AuraEnabled
  public static Id optimize(Id planId) {
    try {
      return RoutePlanService.startOptimization(planId);
    } catch (Exception e) {
      throw auraError(e);
    }
  }

  @AuraEnabled
  public static void publish(Id planId) {
    try {
      RoutePlanService.publishPlan(planId);
    } catch (Exception e) {
      throw auraError(e);
    }
  }

  private static Board buildBoard(Id planId) {
    Route_Plan__c plan = [
      SELECT
        Id,
        Name,
        Status__c,
        Plan_Date__c,
        Depot_Branch__c,
        Depot_Branch__r.Name,
        Revision__c,
        Last_Optimized_At__c,
        Total_Distance_Km__c,
        Total_Duration_Min__c,
        Unassigned_Count__c,
        Error__c
      FROM Route_Plan__c
      WHERE Id = :planId
      WITH USER_MODE
    ];
    Board b = new Board();
    b.planId = plan.Id;
    b.name = plan.Name;
    b.status = plan.Status__c;
    b.planDate = plan.Plan_Date__c;
    b.depot = plan.Depot_Branch__r == null ? null : plan.Depot_Branch__r.Name;
    b.revision = plan.Revision__c;
    b.lastOptimizedAt = plan.Last_Optimized_At__c;
    b.totalDistanceKm = plan.Total_Distance_Km__c;
    b.totalDurationMin = plan.Total_Duration_Min__c;
    b.unassignedCount = plan.Unassigned_Count__c;
    b.error = plan.Error__c;
    b.canOptimize =
      RoutePlanService.RE_PLANNABLE_STATUSES.contains(plan.Status__c) &&
      plan.Status__c != 'Optimizing';
    b.canPublish = plan.Status__c == 'Optimized';
    b.channel =
      '/event/' +
      AssistantClaudeClient.namespacePrefix() +
      'Route_Plan_Update__e';

    Map<Id, RouteView> views = new Map<Id, RouteView>();
    for (Route__c r : [
      SELECT
        Id,
        Name,
        Status__c,
        Fleet_Asset__r.Name,
        Driver__r.Name,
        Planned_Start__c,
        Planned_End__c,
        Planned_Distance_Km__c,
        Geometry__c
      FROM Route__c
      WHERE Route_Plan__c = :planId
      WITH USER_MODE
      ORDER BY Name
      LIMIT 200
    ]) {
      RouteView v = new RouteView();
      v.id = r.Id;
      v.name = r.Name;
      v.status = r.Status__c;
      v.vehicle = r.Fleet_Asset__r == null ? null : r.Fleet_Asset__r.Name;
      v.driver = r.Driver__r == null ? null : r.Driver__r.Name;
      v.plannedStart = r.Planned_Start__c;
      v.plannedEnd = r.Planned_End__c;
      v.distanceKm = r.Planned_Distance_Km__c;
      v.geometry = r.Geometry__c;
      views.put(r.Id, v);
      b.routes.add(v);
    }
    Map<Id, Stop> stops = new Map<Id, Stop>();
    for (Waypoint__c w : [
      SELECT
        Id,
        Route__c,
        Sequence__c,
        Type__c,
        Status__c,
        ETA__c,
        Planned_Arrival__c,
        Locked__c,
        Location__Latitude__s,
        Location__Longitude__s,
        Late_Minutes__c
      FROM Waypoint__c
      WHERE Route__r.Route_Plan__c = :planId
      WITH USER_MODE
      ORDER BY Route__c, Sequence__c
      LIMIT 5000
    ]) {
      Stop s = new Stop();
      s.id = w.Id;
      s.sequence = w.Sequence__c == null ? null : w.Sequence__c.intValue();
      s.type = w.Type__c;
      s.status = w.Status__c;
      s.eta = w.ETA__c != null ? w.ETA__c : w.Planned_Arrival__c;
      s.locked = w.Locked__c;
      s.latitude = w.Location__Latitude__s;
      s.longitude = w.Location__Longitude__s;
      s.lateMinutes = w.Late_Minutes__c;
      stops.put(w.Id, s);
      RouteView v = views.get(w.Route__c);
      if (v != null) {
        v.stops.add(s);
        if (w.Type__c == 'Job Stop') {
          v.jobStops++;
        }
      }
    }
    for (Job_Visit__c jv : [
      SELECT Waypoint__c, Route_Job__r.Name
      FROM Job_Visit__c
      WHERE Waypoint__c IN :stops.keySet()
      WITH USER_MODE
      LIMIT 5000
    ]) {
      stops.get(jv.Waypoint__c).jobs.add(jv.Route_Job__r.Name);
    }
    for (Route_Job__c j : [
      SELECT Id, Name, Type__c, Unassigned_Reason__c
      FROM Route_Job__c
      WHERE
        Unassigned_Reason__c != NULL
        AND Planned_Route__c = NULL
        AND Status__c = 'Ready'
        AND Branch__c = :plan.Depot_Branch__c
        AND Service_Date__c = :plan.Plan_Date__c
      WITH USER_MODE
      ORDER BY Name
      LIMIT 500
    ]) {
      JobView jv = new JobView();
      jv.id = j.Id;
      jv.name = j.Name;
      jv.type = j.Type__c;
      jv.reason = j.Unassigned_Reason__c;
      b.unassigned.add(jv);
    }
    return b;
  }

  private static AuraHandledException auraError(Exception e) {
    AuraHandledException ae = new AuraHandledException(e.getMessage());
    ae.setMessage(e.getMessage());
    return ae;
  }
}
