/**
 * GeotabSyncScheduler
 * Schedulable wrapper for GeotabSyncBatch.
 *
 * To schedule from Anonymous Apex (runs every 15 min via 4 cron jobs):
 *   GeotabSyncScheduler.scheduleAll();
 *
 * To run once immediately:
 *   Database.executeBatch(new GeotabSyncBatch(), 50);
 */
global class GeotabSyncScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {
        Database.executeBatch(new GeotabSyncBatch(), 50);
    }

    /**
     * Convenience method: schedules 4 jobs to achieve ~15 min intervals.
     * Safe to call from Setup → Apex → Execute Anonymous.
     */
    public static void scheduleAll() {
        cancelExisting();
        System.schedule('Geotab Sync 00', '0 0 * * * ?',  new GeotabSyncScheduler());
        System.schedule('Geotab Sync 15', '0 15 * * * ?', new GeotabSyncScheduler());
        System.schedule('Geotab Sync 30', '0 30 * * * ?', new GeotabSyncScheduler());
        System.schedule('Geotab Sync 45', '0 45 * * * ?', new GeotabSyncScheduler());
    }

    /**
     * Cancels all existing Geotab Sync scheduled jobs.
     */
    public static void cancelExisting() {
        for (CronTrigger ct : [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Geotab Sync%'
        ]) {
            System.abortJob(ct.Id);
        }
    }
}
