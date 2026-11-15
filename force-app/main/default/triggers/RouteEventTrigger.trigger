trigger RouteEventTrigger on Route_Event__c(before update, before delete) {
  RouteEvents.enforceAppendOnly(Trigger.isDelete ? Trigger.old : Trigger.new);
}
