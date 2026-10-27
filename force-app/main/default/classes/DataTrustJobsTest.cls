@IsTest
private class DataTrustJobsTest {

    @IsTest
    static void nightlyBatchScoresEveryActiveVehicleAndMatchesNotices() {
        DataTrustTestData.standardProfile();
        Data_Source__c src = DataTrustTestData.source('Tele');
        Fleet_Asset__c a = DataTrustTestData.asset('2023 Ford Transit', 'Diesel', 'Ford', 'Transit', 2023, 'PT');
        Fleet_Asset__c inactive = DataTrustTestData.asset('Old', 'Diesel', 'Ford', 'Transit', 2010, 'PT');
        inactive.Is_Active__c = false;
        insert new List<Fleet_Asset__c>{ a, inactive };
        DataHealthService.running = true;
        insert DataTrustTestData.healthyStreams(a.Id, src, System.now());
        DataHealthService.running = false;
        NoticeMatchingService.running = true;
        insert DataTrustTestData.notice('RCL-1', 'Recall', 'Ford', null, null, null);
        NoticeMatchingService.running = false;

        Id jobId = DataTrustJobs.scheduleNightly();
        DataTrustJobs.scheduleNightly(); // replaces, does not duplicate

        Test.startTest();
        new DataTrustJobs().execute((SchedulableContext) null);
        Test.stopTest();

        Assert.isNotNull(jobId);
        Assert.areEqual(1, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :DataTrustJobs.NIGHTLY_JOB_NAME]);
        Assert.areEqual(100, [SELECT Data_Health_Score__c FROM Fleet_Asset__c WHERE Id = :a.Id].Data_Health_Score__c.intValue());
        Assert.isNull([SELECT Data_Health_Score__c FROM Fleet_Asset__c WHERE Id = :inactive.Id].Data_Health_Score__c);
        Assert.areEqual(1, [SELECT COUNT() FROM Asset_Alert__c WHERE Alert_Type__c = 'Recall']);
    }

    @IsTest
    static void streamChangesReEvaluateTheVehicleInTheBackground() {
        DataTrustTestData.standardProfile();
        Data_Source__c src = DataTrustTestData.source('Tele');
        Fleet_Asset__c a = DataTrustTestData.asset('Van', 'Diesel', 'Ford', 'Transit', 2023, 'PT');
        insert a;

        Test.startTest();
        insert DataTrustTestData.healthyStreams(a.Id, src, System.now());
        Test.stopTest();
        Assert.areEqual(100, [SELECT Data_Health_Score__c FROM Fleet_Asset__c WHERE Id = :a.Id].Data_Health_Score__c.intValue());

        // a status-only change (what the service itself writes) does not re-trigger
        Data_Stream__c s = [SELECT Id FROM Data_Stream__c WHERE Data_Type__c = 'Location' AND Fleet_Asset__c = :a.Id];
        s.Status__c = 'Stale';
        update s;
        Assert.areEqual(0, Limits.getQueueableJobs());

        // the stream going quiet does
        s.Last_Update__c = System.now().addDays(-10);
        update s;
        Assert.areEqual(1, Limits.getQueueableJobs());
    }

    @IsTest
    static void queueablesRunTheServices() {
        DataTrustTestData.standardProfile();
        Fleet_Asset__c a = DataTrustTestData.asset('Van', 'Diesel', 'Ford', 'Transit', 2023, 'PT');
        insert a;
        NoticeMatchingService.running = true;
        External_Notice__c n = DataTrustTestData.notice('RCL-1', 'Recall', 'Ford', null, null, null);
        insert n;
        NoticeMatchingService.running = false;

        Test.startTest();
        System.enqueueJob(new DataTrustJobs.Evaluate(new Set<Id>{ a.Id }));
        System.enqueueJob(new DataTrustJobs.Match(new Set<Id>{ n.Id }));
        Test.stopTest();

        Assert.areEqual(0, [SELECT Data_Health_Score__c FROM Fleet_Asset__c WHERE Id = :a.Id].Data_Health_Score__c.intValue());
        Assert.areEqual(1, [SELECT Affected_Count__c FROM External_Notice__c WHERE Id = :n.Id].Affected_Count__c.intValue());
        DataTrustJobs.evaluateSoon(new Set<Id>());
        DataTrustJobs.matchSoon(null);
    }

    @IsTest
    static void deletingAnAlertRecountsTheVehicle() {
        Fleet_Asset__c a = DataTrustTestData.asset('Van', 'Diesel', 'Ford', 'Transit', 2023, 'PT');
        insert a;
        Asset_Alert__c al = new Asset_Alert__c(Fleet_Asset__c = a.Id, Alert_Type__c = 'Other', Severity__c = 'Low',
            Status__c = 'New', Unique_Key__c = 'OTHER:1', Title__c = 'Manual');
        insert al;
        Assert.areEqual(1, [SELECT Open_Alert_Count__c FROM Fleet_Asset__c WHERE Id = :a.Id].Open_Alert_Count__c.intValue());
        delete al;
        Assert.areEqual(0, [SELECT Open_Alert_Count__c FROM Fleet_Asset__c WHERE Id = :a.Id].Open_Alert_Count__c.intValue());
        undelete al;
        Assert.areEqual(1, [SELECT Open_Alert_Count__c FROM Fleet_Asset__c WHERE Id = :a.Id].Open_Alert_Count__c.intValue());
    }

    @IsTest
    static void alertQueryFiltersAndSorting() {
        Fleet_Asset__c a = DataTrustTestData.asset('Van', 'Diesel', 'Ford', 'Transit', 2023, 'PT');
        insert a;
        DataHealthService.running = true;
        insert new List<Asset_Alert__c>{
            new Asset_Alert__c(Fleet_Asset__c = a.Id, Alert_Type__c = 'Other', Severity__c = 'Low', Status__c = 'New', Unique_Key__c = 'K1', Due_Date__c = System.today()),
            new Asset_Alert__c(Fleet_Asset__c = a.Id, Alert_Type__c = 'Other', Severity__c = 'Critical', Status__c = 'New', Unique_Key__c = 'K2'),
            new Asset_Alert__c(Fleet_Asset__c = a.Id, Alert_Type__c = 'Other', Severity__c = 'Critical', Status__c = 'New', Unique_Key__c = 'K3', Due_Date__c = System.today()),
            new Asset_Alert__c(Fleet_Asset__c = a.Id, Alert_Type__c = 'Other', Severity__c = 'High', Status__c = 'Dismissed', Unique_Key__c = 'K4')
        };
        DataHealthService.running = false;

        AssetAlertService.AlertFilter f = new AssetAlertService.AlertFilter();
        Assert.areEqual(4, AssetAlertService.query(f).size());
        f.assetIds = new Set<Id>{ a.Id };
        f.openOnly = true;
        List<Asset_Alert__c> sorted = AssetAlertService.sortBySeverity(AssetAlertService.query(f));
        Assert.areEqual(new List<String>{ 'K3', 'K2', 'K1' },
            new List<String>{ sorted[0].Unique_Key__c, sorted[1].Unique_Key__c, sorted[2].Unique_Key__c });
        Assert.areEqual(4, AssetAlertService.rank(null));
        AssetAlertService.recountOpenAlerts(null);
    }
}
