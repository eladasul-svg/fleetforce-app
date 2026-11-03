/**
 * Today's route for the driver app's Route tab.
 *
 * Like DriverAppController this runs without sharing and takes the driver as a parameter, because the
 * driver app is the demo build on a guest site with a driver picker and no login. It only reads. A real
 * deployment must resolve the driver from the logged-in user (open question in routing-module.md), and
 * only then can the assistant panel join this tab: the assistant needs a named user.
 */
public without sharing class DriverRouteController {
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
    public Datetime windowEnd;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String accessNotes;
    @AuraEnabled
    public Decimal latitude;
    @AuraEnabled
    public Decimal longitude;
    @AuraEnabled
    public Boolean done;
  }

  public class DriverRoute {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String vehicle;
    @AuraEnabled
    public Datetime plannedEnd;
    @AuraEnabled
    public Integer remaining = 0;
    @AuraEnabled
    public List<Stop> stops = new List<Stop>();
  }

  @AuraEnabled
  public static DriverRoute getTodayRoute(Id driverId) {
    if (driverId == null) {
      return null;
    }
    Date today = Date.today();
    List<Route__c> routes = [
      SELECT Id, Name, Status__c, Fleet_Asset__r.Name, Planned_End__c
      FROM Route__c
      WHERE
        Driver__c = :driverId
        AND Route_Plan__r.Plan_Date__c = :today
        AND Status__c IN ('Planned', 'Published', 'In Progress')
      ORDER BY Planned_Start__c
      LIMIT 1
    ];
    if (routes.isEmpty()) {
      return null;
    }
    Route__c r = routes[0];
    DriverRoute out = new DriverRoute();
    out.id = r.Id;
    out.name = r.Name;
    out.status = r.Status__c;
    out.vehicle = r.Fleet_Asset__r == null ? null : r.Fleet_Asset__r.Name;
    out.plannedEnd = r.Planned_End__c;

    Map<Id, List<Job_Visit__c>> visits = new Map<Id, List<Job_Visit__c>>();
    for (Job_Visit__c jv : [
      SELECT
        Waypoint__c,
        Role__c,
        Window_End__c,
        Access_Notes__c,
        Route_Job__r.Name,
        Route_Job__r.Type__c
      FROM Job_Visit__c
      WHERE Waypoint__r.Route__c = :r.Id
    ]) {
      if (!visits.containsKey(jv.Waypoint__c)) {
        visits.put(jv.Waypoint__c, new List<Job_Visit__c>());
      }
      visits.get(jv.Waypoint__c).add(jv);
    }
    for (Waypoint__c w : [
      SELECT
        Id,
        Sequence__c,
        Type__c,
        Status__c,
        ETA__c,
        Planned_Arrival__c,
        Location__Latitude__s,
        Location__Longitude__s
      FROM Waypoint__c
      WHERE Route__c = :r.Id AND Type__c != 'Start'
      ORDER BY Sequence__c
    ]) {
      Stop s = new Stop();
      s.id = w.Id;
      s.sequence = w.Sequence__c == null ? null : w.Sequence__c.intValue();
      s.type = w.Type__c;
      s.status = w.Status__c;
      s.eta = w.ETA__c != null ? w.ETA__c : w.Planned_Arrival__c;
      s.latitude = w.Location__Latitude__s;
      s.longitude = w.Location__Longitude__s;
      s.done = RouteReplanService.DONE_STATUSES.contains(w.Status__c);
      List<String> labels = new List<String>();
      List<String> notes = new List<String>();
      for (
        Job_Visit__c jv : visits.containsKey(w.Id)
          ? visits.get(w.Id)
          : new List<Job_Visit__c>()
      ) {
        labels.add(
          jv.Route_Job__r.Name + (jv.Role__c == 'Pickup' ? ' (pick up)' : '')
        );
        if (String.isNotBlank(jv.Access_Notes__c)) {
          notes.add(jv.Access_Notes__c);
        }
        if (
          jv.Window_End__c != null &&
          (s.windowEnd == null ||
          jv.Window_End__c < s.windowEnd)
        ) {
          s.windowEnd = jv.Window_End__c;
        }
      }
      s.label = labels.isEmpty()
        ? (w.Type__c == 'End' ? 'Back to depot' : w.Type__c)
        : String.join(labels, ', ');
      s.accessNotes = notes.isEmpty() ? null : String.join(notes, ' · ');
      if (!s.done && w.Type__c != 'End') {
        out.remaining++;
      }
      out.stops.add(s);
    }
    return out;
  }
}
