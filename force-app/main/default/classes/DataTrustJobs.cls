/**
 * Background runners for the data trust layer.
 *   DataTrustJobs.Evaluate   queueable: re-evaluates data health for assets whose streams or data gap alerts changed
 *   DataTrustJobs.Match      queueable: re-matches notices that were activated, reviewed, edited or withdrawn
 *   DataTrustJobs (itself)   nightly schedulable + batch: data health for every active asset, then all notice matching
 *
 * Schedule the nightly run once per org from Anonymous Apex:  DataTrustJobs.scheduleNightly();
 */
public with sharing class DataTrustJobs implements Schedulable, Database.Batchable<SObject> {

    public static final String NIGHTLY_JOB_NAME = 'FleetForce data health nightly';

    public class Evaluate implements Queueable {
        private Set<Id> assetIds;
        public Evaluate(Set<Id> assetIds) {
            this.assetIds = assetIds;
        }
        public void execute(QueueableContext ctx) {
            DataHealthService.evaluate(assetIds);
        }
    }

    public class Match implements Queueable {
        private Set<Id> noticeIds;
        public Match(Set<Id> noticeIds) {
            this.noticeIds = noticeIds;
        }
        public void execute(QueueableContext ctx) {
            NoticeMatchingService.match(noticeIds);
        }
    }

    /** Runs now if we are already asynchronous or out of queueable slots, otherwise enqueues. */
    public static void evaluateSoon(Set<Id> assetIds) {
        assetIds = AssetAlertService.withoutNulls(assetIds);
        if (assetIds.isEmpty()) {
            return;
        }
        if (canEnqueue()) {
            System.enqueueJob(new Evaluate(assetIds));
        } else {
            DataHealthService.evaluate(assetIds);
        }
    }

    public static void matchSoon(Set<Id> noticeIds) {
        noticeIds = AssetAlertService.withoutNulls(noticeIds);
        if (noticeIds.isEmpty()) {
            return;
        }
        if (canEnqueue()) {
            System.enqueueJob(new Match(noticeIds));
        } else {
            NoticeMatchingService.match(noticeIds);
        }
    }

    private static Boolean canEnqueue() {
        return !System.isBatch() && !System.isFuture() && !System.isQueueable() &&
               Limits.getQueueableJobs() < Limits.getLimitQueueableJobs();
    }

    // ---------------------------------------------------------------- nightly

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new DataTrustJobs(), 200);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([SELECT Id FROM Fleet_Asset__c WHERE Is_Active__c = true]);
    }

    public void execute(Database.BatchableContext bc, List<Fleet_Asset__c> scope) {
        DataHealthService.evaluate(new Map<Id, Fleet_Asset__c>(scope).keySet());
    }

    public void finish(Database.BatchableContext bc) {
        NoticeMatchingService.matchAll();
    }

    /** Schedules the nightly run at 02:00 (org time), replacing any earlier schedule. */
    public static Id scheduleNightly() {
        for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :NIGHTLY_JOB_NAME]) {
            System.abortJob(ct.Id);
        }
        return System.schedule(NIGHTLY_JOB_NAME, '0 0 2 * * ?', new DataTrustJobs());
    }
}
