/**
 * @description Listens to Fleet_Audit_Event__e platform events and enqueues asynchronous callout to Microsoft Teams.
 */
trigger FleetAuditEventTrigger on Fleet_Audit_Event__e(after insert) {
  if (!Trigger.new.isEmpty()) {
    System.enqueueJob(new FleetTeamsNotificationQueueable(Trigger.new));
  }
}
