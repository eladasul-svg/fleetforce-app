trigger AssetAlertTrigger on Asset_Alert__c(
  before insert,
  before update,
  after insert,
  after update,
  after delete,
  after undelete
) {
  if (Trigger.isBefore) {
    DataTrustTriggerHandler.stampResolvedOn(Trigger.new, Trigger.oldMap);
  } else {
    DataTrustTriggerHandler.onAlerts(
      Trigger.isDelete ? null : Trigger.new,
      Trigger.isInsert || Trigger.isUndelete ? null : Trigger.oldMap
    );
  }
}
