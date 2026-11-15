/**
 * The rules every route change passes before anything is written.
 *
 * Eligibility ("never allowed"): a vehicle with an open in-shop service ticket, or a driver whose
 * licence or a mandatory qualification has expired, is never routed. Approval rules (who may approve
 * a proposed change) are in decide().
 */
public with sharing class RoutingPolicy {
  public static final Set<String> BLOCKING_QUALIFICATION_STATUSES = new Set<String>{
    'Expired',
    'Revoked'
  };
  public static final Set<String> ACTIVE_ALLOCATION_STATUSES = new Set<String>{
    'Pending',
    'Confirmed',
    'Active'
  };

  // ---------------------------------------------------------------------------------------------
  // Eligibility
  // ---------------------------------------------------------------------------------------------

  /** Assets with a service ticket that has started and not ended (Service_Ticket__c.In_Shop__c). */
  public static Set<Id> assetsInShop(Set<Id> assetIds) {
    Set<Id> out = new Set<Id>();
    if (assetIds == null || assetIds.isEmpty()) {
      return out;
    }
    // In_Shop__c is a formula on TODAY(), so it is read rather than filtered on.
    for (Service_Ticket__c t : [
      SELECT Fleet_Asset__c, In_Shop__c, Status__c
      FROM Service_Ticket__c
      WHERE Fleet_Asset__c IN :assetIds AND Status__c != 'Completed'
      WITH USER_MODE
      LIMIT 5000
    ]) {
      if (t.In_Shop__c || t.Status__c == 'In-Shop') {
        out.add(t.Fleet_Asset__c);
      }
    }
    return out;
  }

  public class DriverStatus {
    public Id driverId;
    public Boolean eligible = true;
    public String reason;
    /** Valid qualification names, matched against Route_Job__c.Required_Skills__c. */
    public List<String> skills = new List<String>();
  }

  public static Map<Id, DriverStatus> driverStatus(
    Set<Id> driverIds,
    Date onDate
  ) {
    Map<Id, DriverStatus> out = new Map<Id, DriverStatus>();
    if (driverIds == null || driverIds.isEmpty()) {
      return out;
    }
    for (Contact c : [
      SELECT Id, Name, License_Expiry__c
      FROM Contact
      WHERE Id IN :driverIds
      WITH USER_MODE
    ]) {
      DriverStatus s = new DriverStatus();
      s.driverId = c.Id;
      if (c.License_Expiry__c != null && c.License_Expiry__c < onDate) {
        s.eligible = false;
        s.reason =
          'driver ' +
          c.Name +
          '\'s licence expired on ' +
          String.valueOf(c.License_Expiry__c);
      }
      out.put(c.Id, s);
    }
    for (Driver_Qualification__c q : [
      SELECT
        Driver__c,
        Name,
        Status__c,
        Valid_Until__c,
        Is_Mandatory__c,
        Does_Expire__c
      FROM Driver_Qualification__c
      WHERE Driver__c IN :driverIds
      WITH USER_MODE
      LIMIT 5000
    ]) {
      DriverStatus s = out.get(q.Driver__c);
      if (s == null) {
        continue;
      }
      Boolean expired =
        BLOCKING_QUALIFICATION_STATUSES.contains(q.Status__c) ||
        (q.Valid_Until__c != null &&
        q.Valid_Until__c < onDate);
      if (expired && q.Is_Mandatory__c == true && s.eligible) {
        s.eligible = false;
        s.reason = 'mandatory qualification ' + q.Name + ' is not valid';
      } else if (!expired && String.isNotBlank(q.Name)) {
        s.skills.add(q.Name.trim());
      }
    }
    return out;
  }

  /** Overlaps with other live allocations of the same vehicles (the motorpool's conflict rule). */
  public static List<String> allocationConflicts(List<Route__c> routes) {
    List<String> out = new List<String>();
    Set<Id> assetIds = new Set<Id>();
    Set<Id> own = new Set<Id>();
    for (Route__c r : routes) {
      if (r.Fleet_Asset__c != null) {
        assetIds.add(r.Fleet_Asset__c);
      }
      if (r.Allocation__c != null) {
        own.add(r.Allocation__c);
      }
    }
    if (assetIds.isEmpty()) {
      return out;
    }
    Set<String> statuses = ACTIVE_ALLOCATION_STATUSES;
    List<Allocation__c> live = [
      SELECT Id, Name, Fleet_Asset__c, Scheduled_Start__c, Scheduled_End__c
      FROM Allocation__c
      WHERE
        Fleet_Asset__c IN :assetIds
        AND Status__c IN :statuses
        AND Id NOT IN :own
      WITH USER_MODE
      LIMIT 5000
    ];
    for (Route__c r : routes) {
      if (r.Planned_Start__c == null || r.Planned_End__c == null) {
        continue;
      }
      for (Allocation__c a : live) {
        if (
          a.Fleet_Asset__c == r.Fleet_Asset__c &&
          a.Scheduled_Start__c != null &&
          a.Scheduled_End__c != null &&
          a.Scheduled_Start__c < r.Planned_End__c &&
          a.Scheduled_End__c > r.Planned_Start__c
        ) {
          out.add(r.Name + ' overlaps allocation ' + a.Name);
        }
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------------------------
  // Approval rules
  // ---------------------------------------------------------------------------------------------

  public static final String DRIVER = 'Driver';
  public static final String DISPATCHER = 'Dispatcher';

  public class Decision {
    public Boolean allowed = true;
    /** 'Driver' when the route's driver may approve alone, else 'Dispatcher'. */
    public String approver = DRIVER;
    public List<String> reasons = new List<String>();

    public Decision needsDispatcher(String reason) {
      approver = DISPATCHER;
      reasons.add(reason);
      return this;
    }
    public Decision refuse(String reason) {
      allowed = false;
      approver = DISPATCHER;
      reasons.add(reason);
      return this;
    }
    public Map<String, Object> toMap() {
      return new Map<String, Object>{
        'allowed' => allowed,
        'approver' => approver,
        'reasons' => reasons
      };
    }
  }

  @TestVisible
  private static Routing_Policy_Setting__mdt settingsOverride;

  public static Routing_Policy_Setting__mdt settings() {
    if (settingsOverride != null) {
      return settingsOverride;
    }
    Routing_Policy_Setting__mdt s = Routing_Policy_Setting__mdt.getInstance(
      'Default'
    );
    return s != null
      ? s
      : new Routing_Policy_Setting__mdt(
          Driver_Approves_Reorder__c = true,
          Driver_Approves_Breaks__c = true,
          Late_Tolerance_Minutes__c = 0
        );
  }

  /** Driver when the running user is the route's driver (Contact.Related_User__c), else Dispatcher. */
  public static String actorRole(Route__c route) {
    return route != null &&
      route.Driver__r != null &&
      route.Driver__r.Related_User__c == UserInfo.getUserId()
      ? DRIVER
      : DISPATCHER;
  }

  /** Re-ordering the remaining stops of one route (reoptimize_remaining). */
  public static Decision forReoptimize(Map<String, Object> diff) {
    Decision d = new Decision();
    if (settings().Driver_Approves_Reorder__c != true) {
      d.needsDispatcher('Re-ordering a route needs a dispatcher in this org.');
    }
    List<Object> hard = (List<Object>) diff.get('lateHardWindows');
    if (hard != null && !hard.isEmpty()) {
      d.needsDispatcher('It breaks a hard time window: ' + joinAll(hard) + '.');
    }
    List<Object> unassigned = (List<Object>) diff.get('unassigned');
    if (unassigned != null && !unassigned.isEmpty()) {
      d.needsDispatcher(
        'It leaves ' + unassigned.size() + ' job(s) unassigned.'
      );
    }
    return d;
  }

  public static Decision forWindowChange(Job_Visit__c visit) {
    Decision d = new Decision();
    if (visit.Hard_Window__c == true) {
      d.needsDispatcher('The visit has a hard time window.');
    }
    return d;
  }

  public static Decision forSkip() {
    return new Decision()
      .needsDispatcher('Skipping a stop leaves its job unassigned.');
  }

  public static Decision forAddWaypoint(String waypointType) {
    Decision d = new Decision();
    Boolean breakLike = waypointType == 'Break' || waypointType == 'Charge';
    if (!breakLike) {
      d.needsDispatcher(
        'Only breaks and charge stops can be added by the driver alone.'
      );
    } else if (settings().Driver_Approves_Breaks__c != true) {
      d.needsDispatcher('Adding a stop needs a dispatcher in this org.');
    }
    return d;
  }

  /** Moving a visit to another route: always a dispatcher, never to a van that may not drive. */
  public static Decision forHandoff(Route__c target, Date onDate) {
    Decision d = new Decision()
      .needsDispatcher('It changes another driver\'s route.');
    if (
      target.Fleet_Asset__c != null &&
      !assetsInShop(new Set<Id>{ target.Fleet_Asset__c }).isEmpty()
    ) {
      return d.refuse(target.Name + ' has an open in-shop service ticket.');
    }
    if (target.Driver__c != null) {
      DriverStatus s = driverStatus(new Set<Id>{ target.Driver__c }, onDate)
        .get(target.Driver__c);
      if (s != null && !s.eligible) {
        return d.refuse(
          'The driver on ' + target.Name + ' may not drive: ' + s.reason + '.'
        );
      }
    }
    return d;
  }

  /** At approval time: a change that needs a dispatcher cannot be approved by the driver. */
  public static String approvalError(String approver, Route__c route) {
    if (approver == DISPATCHER && actorRole(route) == DRIVER) {
      return 'This change needs a dispatcher\'s approval; ask dispatch to approve it.';
    }
    return null;
  }

  private static String joinAll(List<Object> items) {
    List<String> out = new List<String>();
    for (Object o : items) {
      out.add(String.valueOf(o));
    }
    return String.join(out, ', ');
  }
}
