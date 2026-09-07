@IsTest
private class GeotabSyncSchedulerTest {

    @IsTest
    static void testExecute_enqueuesBatch() {
        // Scheduler's execute() calls Database.executeBatch(new GeotabSyncBatch(), 50).
        // With no Telematics Equipment records in scope, the batch runs without callouts.
        Test.startTest();
        String jobId = System.schedule(
            'Test Geotab Execute',
            '0 0 * * * ?',
            new GeotabSyncScheduler()
        );
        Test.stopTest();

        List<AsyncApexJob> batchJobs = [
            SELECT Id, Status, JobType
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assert(!batchJobs.isEmpty(), 'execute() should have enqueued a BatchApex job');
    }

    @IsTest
    static void testScheduleAll_createsFourJobs() {
        Test.startTest();
        GeotabSyncScheduler.scheduleAll();
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Geotab Sync%'
        ];
        System.assertEquals(4, jobs.size(), 'scheduleAll should register exactly 4 scheduled jobs');
    }

    @IsTest
    static void testCancelExisting_removesAllJobs() {
        GeotabSyncScheduler.scheduleAll();

        Test.startTest();
        GeotabSyncScheduler.cancelExisting();
        Test.stopTest();

        List<CronTrigger> remaining = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Geotab Sync%'
        ];
        System.assertEquals(0, remaining.size(), 'cancelExisting should abort all Geotab Sync scheduled jobs');
    }
}
