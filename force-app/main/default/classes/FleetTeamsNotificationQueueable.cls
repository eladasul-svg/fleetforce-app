/**
 * @description Queueable job with callouts enabled to dispatch Teams Adaptive Cards asynchronously.
 */
public with sharing class FleetTeamsNotificationQueueable implements Queueable, Database.AllowsCallouts {
  private List<Fleet_Audit_Event__e> events;

  public FleetTeamsNotificationQueueable(List<Fleet_Audit_Event__e> events) {
    this.events = events != null ? events : new List<Fleet_Audit_Event__e>();
  }

  public void execute(QueueableContext context) {
    if (!this.events.isEmpty()) {
      FleetTeamsNotificationService.dispatchEvents(this.events);
    }
  }
}
