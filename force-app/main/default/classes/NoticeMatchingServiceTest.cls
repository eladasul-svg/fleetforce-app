@IsTest
private class NoticeMatchingServiceTest {

    @TestSetup
    static void fleet() {
        insert new List<Fleet_Asset__c>{
            DataTrustTestData.asset('A 2022 F-150 PT', 'Gasoline', 'Ford', 'F-150', 2022, 'PT'),
            DataTrustTestData.asset('B 2023 F-150 ES', 'Gasoline', 'FORD', 'f-150', 2023, 'ES'),
            DataTrustTestData.asset('C 2025 F-150 PT', 'Gasoline', 'Ford', 'F-150', 2025, 'PT'),
            DataTrustTestData.asset('D 2023 Transit diesel GB', 'Diesel', 'Ford', 'Transit', 2023, 'GB'),
            DataTrustTestData.asset('E 2023 Sprinter diesel PT', 'Diesel', 'Mercedes-Benz', 'Sprinter', 2023, 'PT'),
            DataTrustTestData.asset('F no year', 'Gasoline', 'Ford', 'F-150', null, 'PT')
        };
        Fleet_Asset__c inactive = DataTrustTestData.asset('G inactive F-150', 'Gasoline', 'Ford', 'F-150', 2023, 'PT');
        inactive.Is_Active__c = false;
        insert inactive;
    }

    static Set<String> matchedNames(Id noticeId) {
        Set<String> names = new Set<String>();
        for (Asset_Alert__c a : [SELECT Fleet_Asset__r.Name FROM Asset_Alert__c WHERE External_Notice__c = :noticeId
                                 AND Status__c IN :AssetAlertService.OPEN_STATUSES]) {
            names.add(a.Fleet_Asset__r.Name.left(1));
        }
        return names;
    }

    static External_Notice__c insertQuietly(External_Notice__c n) {
        NoticeMatchingService.running = true;
        insert n;
        NoticeMatchingService.running = false;
        return n;
    }

    @IsTest
    static void recallMatchesMakeModelAndYearRangeAsPossibleMatches() {
        External_Notice__c n = insertQuietly(DataTrustTestData.notice('RCL-1', 'Recall', 'ford', 'F-150', 2022, 2023));

        Integer open = NoticeMatchingService.match(new Set<Id>{ n.Id });

        Assert.areEqual(2, open);
        Assert.areEqual(new Set<String>{ 'A', 'B' }, matchedNames(n.Id));
        Assert.areEqual(2, [SELECT Affected_Count__c FROM External_Notice__c WHERE Id = :n.Id].Affected_Count__c.intValue());
        Asset_Alert__c a = [SELECT Alert_Type__c, Title__c, Detail__c, Severity__c, Due_Date__c, Status__c, Unique_Key__c
                            FROM Asset_Alert__c WHERE External_Notice__c = :n.Id LIMIT 1];
        Assert.areEqual('Recall', a.Alert_Type__c);
        Assert.isTrue(a.Title__c.startsWith('Possible recall: '));
        Assert.isTrue(a.Detail__c.startsWith(NoticeMatchingService.POSSIBLE_MATCH));
        Assert.areEqual('High', a.Severity__c);
        Assert.areEqual(System.today().addDays(30), a.Due_Date__c);
        Assert.areEqual('New', a.Status__c);
        Assert.isTrue(a.Unique_Key__c.startsWith('NT:' + n.Id));
        Assert.areEqual(1, [SELECT Open_Alert_Count__c FROM Fleet_Asset__c WHERE Name LIKE 'A %'].Open_Alert_Count__c.intValue());
    }

    @IsTest
    static void regulationMatchesFuelTypeInsideTheJurisdiction() {
        External_Notice__c n = DataTrustTestData.notice('REG-1', 'Regulation', null, null, null, null);
        n.Fuel_Type__c = 'Diesel';
        n.Jurisdiction__c = 'PT; es,FR';
        insertQuietly(n);

        NoticeMatchingService.match(new Set<Id>{ n.Id });

        Assert.areEqual(new Set<String>{ 'E' }, matchedNames(n.Id), 'D is diesel but in GB');
        Asset_Alert__c a = [SELECT Alert_Type__c, Title__c FROM Asset_Alert__c WHERE External_Notice__c = :n.Id];
        Assert.areEqual('Regulation', a.Alert_Type__c);
        Assert.areEqual('REG-1 title', a.Title__c);
    }

    @IsTest
    static void unreviewedOrDraftNoticesNeverMatch() {
        External_Notice__c unreviewed = DataTrustTestData.notice('RCL-2', 'Recall', 'Ford', null, null, null);
        unreviewed.Reviewed__c = false;
        External_Notice__c draft = DataTrustTestData.notice('RCL-3', 'Service bulletin', 'Ford', null, null, null);
        draft.Status__c = 'Draft';
        NoticeMatchingService.running = true;
        insert new List<External_Notice__c>{ unreviewed, draft };
        NoticeMatchingService.running = false;

        Assert.areEqual(0, NoticeMatchingService.match(new Set<Id>{ unreviewed.Id, draft.Id }));
        Assert.areEqual(0, [SELECT COUNT() FROM Asset_Alert__c]);
        Assert.areEqual(0, [SELECT Affected_Count__c FROM External_Notice__c WHERE Id = :draft.Id].Affected_Count__c.intValue());
    }

    @IsTest
    static void rerunKeepsUserStatusAndWithdrawalResolvesEverything() {
        External_Notice__c n = insertQuietly(DataTrustTestData.notice('RCL-4', 'Recall', 'Ford', 'F-150', null, null));
        NoticeMatchingService.match(new Set<Id>{ n.Id });
        Assert.areEqual(new Set<String>{ 'A', 'B', 'C', 'F' }, matchedNames(n.Id));

        Asset_Alert__c ack = [SELECT Id FROM Asset_Alert__c WHERE External_Notice__c = :n.Id AND Fleet_Asset__r.Name LIKE 'A %'];
        ack.Status__c = 'Acknowledged';
        update ack;

        // rerun: no duplicates, acknowledgement kept; tighten the year range: C and F drop out and are resolved
        n.Year_From__c = 2022;
        n.Year_To__c = 2023;
        NoticeMatchingService.running = true;
        update n;
        NoticeMatchingService.running = false;
        NoticeMatchingService.match(new Set<Id>{ n.Id });
        Assert.areEqual(4, [SELECT COUNT() FROM Asset_Alert__c WHERE External_Notice__c = :n.Id]);
        Assert.areEqual('Acknowledged', [SELECT Status__c FROM Asset_Alert__c WHERE Id = :ack.Id].Status__c);
        Assert.areEqual(new Set<String>{ 'A', 'B' }, matchedNames(n.Id));
        Assert.areEqual(2, [SELECT COUNT() FROM Asset_Alert__c WHERE External_Notice__c = :n.Id AND Status__c = 'Resolved' AND Resolved_On__c != null]);

        // widen again: system-resolved alerts reopen
        n.Year_From__c = null;
        n.Year_To__c = null;
        NoticeMatchingService.running = true;
        update n;
        NoticeMatchingService.running = false;
        NoticeMatchingService.match(new Set<Id>{ n.Id });
        Assert.areEqual(new Set<String>{ 'A', 'B', 'C', 'F' }, matchedNames(n.Id));

        // withdraw
        n.Status__c = 'Withdrawn';
        NoticeMatchingService.running = true;
        update n;
        NoticeMatchingService.running = false;
        NoticeMatchingService.match(new Set<Id>{ n.Id });
        Assert.areEqual(0, matchedNames(n.Id).size());
        Assert.areEqual(0, [SELECT Affected_Count__c FROM External_Notice__c WHERE Id = :n.Id].Affected_Count__c.intValue());
        Assert.areEqual(0, [SELECT COUNT() FROM Fleet_Asset__c WHERE Open_Alert_Count__c > 0]);
    }

    @IsTest
    static void triggerMatchesAnEligibleNoticeAsynchronously() {
        Test.startTest();
        insert DataTrustTestData.notice('RCL-5', 'Recall', 'Mercedes-Benz', null, null, null);
        Test.stopTest();
        External_Notice__c n = [SELECT Id, Affected_Count__c FROM External_Notice__c WHERE External_Id__c = 'RCL-5'];
        Assert.areEqual(1, n.Affected_Count__c.intValue());
        Assert.areEqual(new Set<String>{ 'E' }, matchedNames(n.Id));
    }

    @IsTest
    static void triggerRematchesWhenANoticeIsReviewed() {
        External_Notice__c n = DataTrustTestData.notice('RCL-6', 'Recall', 'Ford', 'Transit', null, null);
        n.Reviewed__c = false;
        insert n; // not eligible: nothing enqueued
        Assert.areEqual(0, [SELECT COUNT() FROM Asset_Alert__c]);

        Test.startTest();
        n.Reviewed__c = true;
        update n;
        Test.stopTest();
        Assert.areEqual(new Set<String>{ 'D' }, matchedNames(n.Id));
    }

    @IsTest
    static void matchAllCoversEveryNotice() {
        insertQuietly(DataTrustTestData.notice('RCL-7', 'Recall', 'Ford', 'Transit', null, null));
        insertQuietly(DataTrustTestData.notice('RCL-8', 'Recall', null, 'Sprinter', null, null));
        Assert.areEqual(2, NoticeMatchingService.matchAll());
        Assert.areEqual(0, NoticeMatchingService.match(new Set<Id>()));
    }

    @IsTest
    static void jurisdictionParsing() {
        Assert.areEqual(new Set<String>{ 'PT', 'ES', 'FR' }, NoticeMatchingService.jurisdictionCodes(' pt;ES , fr '));
        Assert.isTrue(NoticeMatchingService.jurisdictionCodes(null).isEmpty());
        Fleet_Asset__c noCountry = DataTrustTestData.asset('x', 'Diesel', 'Ford', 'Transit', 2023, null);
        External_Notice__c n = DataTrustTestData.notice('X', 'Regulation', null, null, null, null);
        n.Jurisdiction__c = 'PT';
        Assert.isFalse(NoticeMatchingService.matches(n, noCountry));
        n.Jurisdiction__c = null;
        Assert.isTrue(NoticeMatchingService.matches(n, noCountry));
    }
}
