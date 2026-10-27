trigger DataStreamTrigger on Data_Stream__c (after insert, after update, after delete, after undelete) {
    DataTrustTriggerHandler.onStreams(Trigger.isDelete ? null : Trigger.new, Trigger.isInsert || Trigger.isUndelete ? null : Trigger.oldMap);
}
