/**
 * Writes the append-only Route_Event__c audit trail, and enforces "append-only" for everyone
 * (RouteEventTrigger): events are inserted, never updated or deleted, whatever the user's permissions.
 */
public with sharing class RouteEvents {
  public static final String APPEND_ONLY_MESSAGE = 'Route events are an append-only audit trail and cannot be changed or deleted.';

  public class Builder {
    public Route_Event__c record = new Route_Event__c();

    public Builder forPlan(Id planId) {
      record.Route_Plan__c = planId;
      return this;
    }
    public Builder forRoute(Id routeId) {
      record.Route__c = routeId;
      return this;
    }
    public Builder forWaypoint(Id waypointId) {
      record.Waypoint__c = waypointId;
      return this;
    }
    public Builder session(Id sessionId) {
      record.Assistant_Session__c = sessionId;
      return this;
    }
    public Builder payload(Object payload) {
      record.Payload__c = payload == null
        ? null
        : JSON.serialize(payload).abbreviate(131072);
      return this;
    }
  }

  public static Builder event(String type, String actorType) {
    Builder b = new Builder();
    b.record.Type__c = type;
    b.record.Actor_Type__c = actorType;
    b.record.Actor_User__c = UserInfo.getUserId();
    b.record.Occurred_At__c = System.now();
    return b;
  }

  public static Route_Event__c log(Builder b) {
    Database.insert(b.record, true, AccessLevel.USER_MODE);
    return b.record;
  }

  public static void log(List<Builder> builders) {
    List<Route_Event__c> rows = new List<Route_Event__c>();
    for (Builder b : builders) {
      rows.add(b.record);
    }
    Database.insert(rows, true, AccessLevel.USER_MODE);
  }

  /** Trigger entry: blocks every update and delete. */
  public static void enforceAppendOnly(List<Route_Event__c> rows) {
    for (Route_Event__c e : rows) {
      e.addError(APPEND_ONLY_MESSAGE);
    }
  }
}
