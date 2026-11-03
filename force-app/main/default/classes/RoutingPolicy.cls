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
}
