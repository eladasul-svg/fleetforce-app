@IsTest
private class DataHealthServiceTest {

    static final Datetime NOW_TS = Datetime.newInstanceGmt(2026, 10, 28, 9, 0, 0);

    static Fleet_Asset__c reload(Id assetId) {
        return [
            SELECT Data_Health_Score__c, Data_Health_Status__c, Freshness_Score__c, Completeness_Score__c, Consistency_Score__c,
                   Data_Health_Calculated__c, Open_Alert_Count__c, Resolved_Stream_Profile__c
            FROM Fleet_Asset__c WHERE Id = :assetId
        ];
    }

    static List<Asset_Alert__c> gaps(Id assetId) {
        return [SELECT Unique_Key__c, Severity__c, Status__c, Title__c, Resolved_On__c FROM Asset_Alert__c
                WHERE Fleet_Asset__c = :assetId AND Alert_Type__c = 'Data gap' ORDER BY Unique_Key__c];
    }

    @IsTest
    static void healthyVehicleScoresOneHundred() {
        DataHealthService.nowOverride = NOW_TS;
        Stream_Profile__c std = DataTrustTestData.standardProfile();
        Data_Source__c src = DataTrustTestData.source('Tele');
        Fleet_Asset__c a = DataTrustTestData.asset('2023 Ford Transit', 'Gasoline', 'Ford', 'Transit', 2023, 'PT');
        insert a;
        insert DataTrustTestData.healthyStreams(a.Id, src, NOW_TS);

        Map<Id, DataHealthService.Result> r = DataHealthService.evaluate(new Set<Id>{ a.Id });

        Fleet_Asset__c after = reload(a.Id);
        Assert.areEqual(100, r.get(a.Id).score);
        Assert.areEqual(100, after.Data_Health_Score__c.intValue());
        Assert.areEqual('Healthy', after.Data_Health_Status__c);
        Assert.areEqual(std.Id, after.Resolved_Stream_Profile__c);
        Assert.areEqual(NOW_TS, after.Data_Health_Calculated__c);
        Assert.areEqual(0, after.Open_Alert_Count__c.intValue());
        Assert.areEqual(0, gaps(a.Id).size());
        for (Data_Stream__c s : [SELECT Status__c FROM Data_Stream__c WHERE Fleet_Asset__c = :a.Id]) {
            Assert.areEqual('Healthy', s.Status__c);
        }
    }

    /** REF-2 from the seed README: F 81, C 75, K 90 = 80 Watch. */
    @IsTest
    static void watchVehicleMatchesHandCalculation() {
        DataHealthService.nowOverride = NOW_TS;
        DataTrustTestData.standardProfile();
        Data_Source__c src = DataTrustTestData.source('Tele');
        Fleet_Asset__c a = DataTrustTestData.asset('2024 Toyota Camry LE', 'Gasoline', 'Toyota', 'Camry', 2024, 'PT');
        insert a;
        insert new List<Data_Stream__c>{
            DataTrustTestData.stream(a.Id, src, 'Location', NOW_TS.addHours(-60), 2),
            DataTrustTestData.stream(a.Id, src, 'Odometer', NOW_TS.addHours(-60), 1),
            DataTrustTestData.stream(a.Id, src, 'Fuel or charge', NOW_TS.addHours(-12), 1),
            DataTrustTestData.stream(a.Id, src, 'Maintenance plan', NOW_TS.addHours(-72), 2)
        };

        DataHealthService.Result r = DataHealthService.evaluate(new Set<Id>{ a.Id }).get(a.Id);

        Assert.areEqual(81, r.freshness);
        Assert.areEqual(75, r.completeness);
        Assert.areEqual(90, r.consistency);
        Assert.areEqual(80, r.score);
        Assert.areEqual('Watch', r.status);
        List<Asset_Alert__c> g = gaps(a.Id);
        Assert.areEqual(1, g.size());
        Assert.areEqual('Medium', g[0].Severity__c);
        Assert.areEqual('Location data is stale', g[0].Title__c);
        Assert.areEqual('Stale', [SELECT Status__c FROM Data_Stream__c WHERE Fleet_Asset__c = :a.Id AND Data_Type__c = 'Location'].Status__c);
    }

    /** REF-3 from the seed README: F 25, C 75, K 25 = 45 At risk; rerun never duplicates. */
    @IsTest
    static void atRiskVehicleMatchesHandCalculationAndRerunsCleanly() {
        DataHealthService.nowOverride = NOW_TS;
        DataTrustTestData.standardProfile();
        Data_Source__c src = DataTrustTestData.source('Tele');
        Fleet_Asset__c a = DataTrustTestData.asset('2023 Ford F-150 Lariat', 'Gasoline', 'Ford', 'F-150', 2023, 'PT');
        insert a;
        insert new List<Data_Stream__c>{
            DataTrustTestData.stream(a.Id, src, 'Location', NOW_TS.addHours(-216), 2),
            DataTrustTestData.stream(a.Id, src, 'Odometer', NOW_TS.addHours(-216), 1),
            DataTrustTestData.stream(a.Id, src, 'Diagnostics', NOW_TS.addHours(-216), 1),
            DataTrustTestData.stream(a.Id, src, 'Fuel or charge', NOW_TS.addHours(-12), 2)
        };

        DataHealthService.Result r = DataHealthService.evaluate(new Set<Id>{ a.Id }).get(a.Id);
        Assert.areEqual(25, r.freshness);
        Assert.areEqual(75, r.completeness);
        Assert.areEqual(25, r.consistency);
        Assert.areEqual(45, r.score);
        Assert.areEqual('At risk', r.status);
        Assert.areEqual(3, gaps(a.Id).size(), 'location, odometer and maintenance plan');

        r = DataHealthService.evaluate(new Set<Id>{ a.Id }).get(a.Id);
        Assert.areEqual(45, r.score);
        Assert.areEqual(3, gaps(a.Id).size(), 'a rerun must not duplicate alerts');
        Assert.areEqual(3, reload(a.Id).Open_Alert_Count__c.intValue());
    }

    @IsTest
    static void fixedStreamAutoResolvesItsAlertAndReopensIfItBreaksAgain() {
        DataHealthService.nowOverride = NOW_TS;
        DataTrustTestData.standardProfile();
        Data_Source__c src = DataTrustTestData.source('Tele');
        Fleet_Asset__c a = DataTrustTestData.asset('Van', 'Gasoline', 'Ford', 'Transit', 2022, 'PT');
        insert a;
        List<Data_Stream__c> streams = DataTrustTestData.healthyStreams(a.Id, src, NOW_TS);
        streams.remove(4); // no maintenance plan
        insert streams;

        DataHealthService.evaluate(new Set<Id>{ a.Id });
        Asset_Alert__c missing = gaps(a.Id)[0];
        Assert.areEqual('High', missing.Severity__c);
        Assert.areEqual('New', missing.Status__c);
        Assert.areEqual(75, reload(a.Id).Consistency_Score__c.intValue());

        Data_Stream__c maint = DataTrustTestData.stream(a.Id, src, 'Maintenance plan', NOW_TS.addHours(-5), 2);
        DataHealthService.running = true; // keep the trigger's queueable out of this test
        insert maint;
        DataHealthService.running = false;
        DataHealthService.evaluate(new Set<Id>{ a.Id });
        missing = gaps(a.Id)[0];
        Assert.areEqual('Resolved', missing.Status__c);
        Assert.isNotNull(missing.Resolved_On__c);
        Assert.areEqual(100, reload(a.Id).Data_Health_Score__c.intValue());

        DataHealthService.running = true;
        delete maint;
        DataHealthService.running = false;
        DataHealthService.evaluate(new Set<Id>{ a.Id });
        Assert.areEqual('New', gaps(a.Id)[0].Status__c, 'a system-resolved alert reopens');
        Assert.areEqual(1, gaps(a.Id).size());
    }

    @IsTest
    static void dismissedAlertStaysDismissedAndStopsCounting() {
        DataHealthService.nowOverride = NOW_TS;
        DataTrustTestData.standardProfile();
        Data_Source__c src = DataTrustTestData.source('Tele');
        Fleet_Asset__c a = DataTrustTestData.asset('Van', 'Gasoline', 'Ford', 'Transit', 2022, 'PT');
        insert a;
        List<Data_Stream__c> streams = DataTrustTestData.healthyStreams(a.Id, src, NOW_TS);
        streams.remove(4);
        insert streams;
        DataHealthService.evaluate(new Set<Id>{ a.Id });

        Asset_Alert__c g = gaps(a.Id)[0];
        g.Status__c = 'Dismissed';
        update g; // the alert trigger re-scores the vehicle
        Assert.areEqual(100, reload(a.Id).Consistency_Score__c.intValue());
        DataHealthService.evaluate(new Set<Id>{ a.Id });
        Assert.areEqual('Dismissed', gaps(a.Id)[0].Status__c);
        Assert.areEqual(0, reload(a.Id).Open_Alert_Count__c.intValue());
    }

    @IsTest
    static void otherDataGapsLowerConsistencyButAreNotAutoResolved() {
        DataHealthService.nowOverride = NOW_TS;
        DataTrustTestData.standardProfile();
        Data_Source__c src = DataTrustTestData.source('Tele');
        Fleet_Asset__c a = DataTrustTestData.asset('Van', 'Gasoline', 'Ford', 'Transit', 2022, 'PT');
        insert a;
        insert DataTrustTestData.healthyStreams(a.Id, src, NOW_TS);
        DataHealthService.running = true;
        insert new Asset_Alert__c(Fleet_Asset__c = a.Id, Alert_Type__c = 'Data gap', Severity__c = 'Critical', Status__c = 'New',
            Unique_Key__c = 'DGC:' + a.Id + ':Maintenance plan', Title__c = 'Mismatch');
        DataHealthService.running = false;

        DataHealthService.Result r = DataHealthService.evaluate(new Set<Id>{ a.Id }).get(a.Id);
        Assert.areEqual(60, r.consistency);
        Assert.areEqual(92, r.score);
        Assert.areEqual('New', [SELECT Status__c FROM Asset_Alert__c WHERE Unique_Key__c LIKE 'DGC:%'].Status__c);
    }

    @IsTest
    static void tooFewSignalsRaisesALowAlert() {
        DataHealthService.nowOverride = NOW_TS;
        DataTrustTestData.standardProfile();
        Data_Source__c src = DataTrustTestData.source('Tele');
        Fleet_Asset__c a = DataTrustTestData.asset('Van', 'Gasoline', 'Ford', 'Transit', 2022, 'PT');
        insert a;
        List<Data_Stream__c> streams = DataTrustTestData.healthyStreams(a.Id, src, NOW_TS);
        streams[0].Signals_Present__c = 1; // location needs 2
        insert streams;

        DataHealthService.Result r = DataHealthService.evaluate(new Set<Id>{ a.Id }).get(a.Id);
        List<Asset_Alert__c> g = gaps(a.Id);
        Assert.areEqual(1, g.size());
        Assert.isTrue(g[0].Unique_Key__c.startsWith('DGS:'));
        Assert.areEqual('Low', g[0].Severity__c);
        Assert.areEqual(95, r.consistency);
        Assert.areEqual(88, r.completeness);
    }

    @IsTest
    static void profileResolutionUsesOverrideThenMatchThenDefault() {
        Stream_Profile__c std = DataTrustTestData.standardProfile();
        Stream_Profile__c ev = DataTrustTestData.evProfile();
        Stream_Profile__c fordVans = new Stream_Profile__c(Name = 'Ford vans', Expected_Signal_Count__c = 5, Make__c = 'ford',
            Model__c = 'Transit', Priority__c = 5, Active__c = true);
        Stream_Profile__c inactive = new Stream_Profile__c(Name = 'Inactive', Expected_Signal_Count__c = 5, Make__c = 'Ford',
            Priority__c = 1, Active__c = false);
        insert new List<Stream_Profile__c>{ fordVans, inactive };

        Fleet_Asset__c gas = DataTrustTestData.asset('Car', 'Gasoline', 'Toyota', 'Camry', 2024, 'PT');
        Fleet_Asset__c electric = DataTrustTestData.asset('EV', 'Electric', 'Ford', 'E-Transit', 2023, 'PT');
        Fleet_Asset__c van = DataTrustTestData.asset('Van', 'Gasoline', 'Ford', 'Transit', 2022, 'PT');
        Fleet_Asset__c overridden = DataTrustTestData.asset('Override', 'Electric', 'Ford', 'Transit', 2022, 'PT');
        insert new List<Fleet_Asset__c>{ gas, electric, van, overridden };
        overridden.Stream_Profile_Override__c = std.Id;
        update overridden;

        Map<Id, DataHealthService.Result> r = DataHealthService.evaluate(new Set<Id>{ gas.Id, electric.Id, van.Id, overridden.Id });
        Assert.areEqual(std.Id, r.get(gas.Id).profileId, 'default');
        Assert.areEqual(ev.Id, r.get(electric.Id).profileId, 'fuel type');
        Assert.areEqual(fordVans.Id, r.get(van.Id).profileId, 'make and model, priority 5 beats 10, inactive ignored');
        Assert.areEqual(std.Id, r.get(overridden.Id).profileId, 'override wins');
        Assert.areEqual(0, r.get(gas.Id).score, 'no streams at all');
    }

    @IsTest
    static void noProfileAtAllStillScores() {
        DataHealthService.nowOverride = NOW_TS;
        Data_Source__c src = DataTrustTestData.source('Tele');
        Fleet_Asset__c a = DataTrustTestData.asset('Van', 'Gasoline', 'Ford', 'Transit', 2022, 'PT');
        insert a;
        insert DataTrustTestData.stream(a.Id, src, 'Location', NOW_TS.addHours(-1), 2);
        DataHealthService.Result r = DataHealthService.evaluate(new Set<Id>{ a.Id }).get(a.Id);
        Assert.isNull(r.profileId);
        Assert.areEqual(100, r.freshness);
        Assert.areEqual(0, r.completeness);
        Assert.areEqual(100, r.consistency);
        Assert.areEqual(60, r.score);
    }

    @IsTest
    static void bulkTwoHundredVehicles() {
        DataHealthService.nowOverride = NOW_TS;
        DataTrustTestData.standardProfile();
        DataTrustTestData.evProfile();
        Data_Source__c src = DataTrustTestData.source('Tele');
        List<Fleet_Asset__c> fleet = new List<Fleet_Asset__c>();
        for (Integer i = 0; i < 200; i++) {
            fleet.add(DataTrustTestData.asset('Vehicle ' + i, Math.mod(i, 10) == 0 ? 'Electric' : 'Diesel', 'Make' + Math.mod(i, 3),
                'Model', 2020 + Math.mod(i, 5), 'PT'));
        }
        insert fleet;
        List<Data_Stream__c> streams = new List<Data_Stream__c>();
        for (Integer i = 0; i < 200; i++) {
            Id assetId = fleet[i].Id;
            streams.add(DataTrustTestData.stream(assetId, src, 'Location', NOW_TS.addHours(-(Math.mod(i, 4) == 0 ? 100 : 1)), 2));
            streams.add(DataTrustTestData.stream(assetId, src, 'Odometer', NOW_TS.addHours(-1), 1));
            streams.add(DataTrustTestData.stream(assetId, src, 'Fuel or charge', NOW_TS.addHours(-1), 4));
        }
        DataHealthService.running = true;
        insert streams;
        DataHealthService.running = false;
        Set<Id> ids = new Map<Id, Fleet_Asset__c>(fleet).keySet();

        Test.startTest();
        Map<Id, DataHealthService.Result> r = DataHealthService.evaluate(ids);
        Integer queries = Limits.getQueries();
        DataHealthService.evaluate(ids);
        Test.stopTest();

        Assert.areEqual(200, r.size());
        Assert.isTrue(queries <= 10, 'query count must not grow with the fleet: ' + queries);
        Assert.areEqual(200, [SELECT COUNT() FROM Fleet_Asset__c WHERE Data_Health_Score__c != null]);
        Assert.areEqual(0, [SELECT COUNT() FROM Fleet_Asset__c WHERE Data_Health_Status__c = null]);
        // every vehicle is missing its maintenance plan (Standard) or nothing (EV batch only needs location and charge)
        Assert.areEqual(180, [SELECT COUNT() FROM Asset_Alert__c WHERE Unique_Key__c LIKE 'DG:%:Maintenance plan']);
        Assert.areEqual(50, [SELECT COUNT() FROM Asset_Alert__c WHERE Unique_Key__c LIKE 'DG:%:Location']);
    }

    @IsTest
    static void scoringHelpers() {
        Assert.areEqual(100, DataHealthService.lineFreshness(10, 24).intValue());
        Assert.areEqual(50, DataHealthService.lineFreshness(48, 24).intValue());
        Assert.areEqual(0, DataHealthService.lineFreshness(72, 24).intValue());
        Assert.areEqual(0, DataHealthService.lineFreshness(null, 24).intValue());
        Assert.areEqual(100, DataHealthService.lineFreshness(500, null).intValue());
        Assert.areEqual('Healthy', DataHealthService.band(85));
        Assert.areEqual('Watch', DataHealthService.band(84));
        Assert.areEqual('Watch', DataHealthService.band(60));
        Assert.areEqual('At risk', DataHealthService.band(59));
        Assert.isNull(DataHealthService.band(null));
        Datetime t = Datetime.newInstanceGmt(2026, 1, 1, 0, 0, 0);
        Assert.areEqual('Missing', DataHealthService.streamStatus(null, 24, t));
        Assert.areEqual('Stale', DataHealthService.streamStatus(t.addHours(-25), 24, t));
        Assert.areEqual('Healthy', DataHealthService.streamStatus(t.addHours(-25), null, t));
        Assert.areEqual('5 hours', DataHealthService.describeAge(5));
        Assert.areEqual('1 hour', DataHealthService.describeAge(1));
        Assert.areEqual('9 days', DataHealthService.describeAge(216));
        Assert.isTrue(DataHealthService.same(null, 'x'));
        Assert.isTrue(DataHealthService.same('FORD ', 'ford'));
        Assert.isFalse(DataHealthService.same('Ford', null));
        Assert.isTrue(DataHealthService.isOwnedKey('DGS:x'));
        Assert.isFalse(DataHealthService.isOwnedKey('DGC:x'));
        Assert.areEqual(0, DataHealthService.evaluate(new Set<Id>()).size());
    }
}
