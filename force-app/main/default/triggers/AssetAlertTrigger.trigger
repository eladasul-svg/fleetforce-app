trigger AssetAlertTrigger on Asset_Alert__c (after insert, after update, after delete, after undelete) {
    DataTrustTriggerHandler.onAlerts(Trigger.isDelete ? null : Trigger.new, Trigger.isInsert || Trigger.isUndelete ? null : Trigger.oldMap);
}
