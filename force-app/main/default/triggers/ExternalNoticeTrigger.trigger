trigger ExternalNoticeTrigger on External_Notice__c (after insert, after update) {
    DataTrustTriggerHandler.onNotices(Trigger.new, Trigger.isInsert ? null : Trigger.oldMap);
}
