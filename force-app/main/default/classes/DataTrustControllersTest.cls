@IsTest
private class DataTrustControllersTest {
  @TestSetup
  static void data() {
    insert new List<Fleet_Asset__c>{
      DataTrustTestData.asset(
        '2023 Ford Transit A',
        'Diesel',
        'Ford',
        'Transit',
        2023,
        'PT'
      ),
      DataTrustTestData.asset(
        '2023 Ford Transit B',
        'Diesel',
        'Ford',
        'Transit',
        2023,
        'ES'
      ),
      DataTrustTestData.asset(
        '2024 Toyota Camry',
        'Gasoline',
        'Toyota',
        'Camry',
        2024,
        'PT'
      )
    };
    DataTrustTestData.standardProfile();
  }

  static Fleet_Asset__c asset(String name) {
    return [SELECT Id FROM Fleet_Asset__c WHERE Name = :name];
  }

  @IsTest
  static void recordPageShowsScoreStreamsAndAlertsAndCanAcknowledge() {
    Fleet_Asset__c a = asset('2023 Ford Transit A');
    Data_Source__c src = DataTrustTestData.source('Tele');
    List<Data_Stream__c> streams = DataTrustTestData.healthyStreams(
      a.Id,
      src,
      System.now()
    );
    streams.remove(4); // missing maintenance plan
    streams[0].Is_Sample__c = true;
    streams[1].Reference_URL__c = 'https://example.com/vehicle/1';
    DataHealthService.running = true;
    insert streams;
    DataHealthService.running = false;
    External_Notice__c n = DataTrustTestData.notice(
      'RCL-1',
      'Recall',
      'Ford',
      'Transit',
      null,
      null
    );
    n.Severity__c = 'Critical';
    NoticeMatchingService.running = true;
    insert n;
    NoticeMatchingService.running = false;
    NoticeMatchingService.match(new Set<Id>{ n.Id });

    AssetDataHealthController.Health h = AssetDataHealthController.getHealth(
      a.Id
    );
    Assert.isNull(h.score, 'not calculated yet');
    Assert.areEqual(4, h.streams.size());
    Assert.isTrue(h.isSample);

    h = AssetDataHealthController.refreshHealth(a.Id);
    Assert.areEqual(75, h.freshness);
    Assert.areEqual('Standard', h.profileName);
    Assert.isNotNull(h.calculatedOn);
    Assert.areEqual(2, h.alerts.size());
    Assert.areEqual('Critical', h.alerts[0].severity, 'sorted by severity');
    Assert.areEqual('Recall', h.alerts[0].alertType);
    Assert.areEqual('High', h.alerts[1].severity);
    for (AssetDataHealthController.StreamRow r : h.streams) {
      Assert.isNotNull(r.referenceUrl, 'falls back to the source URL');
      Assert.areEqual('Tele', r.sourceName);
    }

    h = AssetDataHealthController.setAlertStatus(
      h.alerts[0].id,
      'Acknowledged'
    );
    Assert.areEqual('Acknowledged', h.alerts[0].status);
    Assert.areEqual(2, h.alerts.size(), 'acknowledged alerts stay open');

    h = AssetDataHealthController.setAlertStatus(h.alerts[0].id, 'Resolved');
    Assert.areEqual(1, h.alerts.size());
    Assert.isNotNull(
      [
        SELECT Resolved_On__c
        FROM Asset_Alert__c
        WHERE External_Notice__c = :n.Id AND Fleet_Asset__c = :a.Id
      ]
      .Resolved_On__c
    );

    try {
      AssetDataHealthController.setAlertStatus(h.alerts[0].id, 'Bogus');
      Assert.fail('expected an error');
    } catch (AuraHandledException e) {
      Assert.isNotNull(e.getMessage());
    }
  }

  @IsTest
  static void recordPageEmptyAndMissingAsset() {
    Fleet_Asset__c a = asset('2024 Toyota Camry');
    AssetDataHealthController.Health h = AssetDataHealthController.getHealth(
      a.Id
    );
    Assert.areEqual(0, h.streams.size());
    Assert.areEqual(0, h.alerts.size());
    Assert.isFalse(h.isSample);

    delete a;
    h = AssetDataHealthController.getHealth(a.Id);
    Assert.isNull(h.score);
    try {
      AssetDataHealthController.getHealth('bogus');
      Assert.fail('expected an error');
    } catch (Exception e) {
      Assert.isNotNull(e);
    }
  }

  @IsTest
  static void exposureViewSummaryNoticesDrillDownAndSources() {
    Data_Source__c src = DataTrustTestData.source('Tele');
    src.Is_Sample__c = true;
    update src;
    Data_Source__c empty = DataTrustTestData.source('Empty');
    Fleet_Asset__c a = asset('2023 Ford Transit A');
    Fleet_Asset__c b = asset('2023 Ford Transit B');
    List<Data_Stream__c> streams = DataTrustTestData.healthyStreams(
      a.Id,
      src,
      System.now()
    );
    streams.add(
      DataTrustTestData.stream(
        b.Id,
        src,
        'Location',
        System.now().addDays(-9),
        2
      )
    );
    DataHealthService.running = true;
    insert streams;
    DataHealthService.running = false;
    DataHealthService.evaluate(new Set<Id>{ a.Id, b.Id });

    External_Notice__c recall = DataTrustTestData.notice(
      'RCL-1',
      'Recall',
      'Ford',
      'Transit',
      2023,
      2023
    );
    External_Notice__c reg = DataTrustTestData.notice(
      'REG-1',
      'Regulation',
      null,
      null,
      null,
      null
    );
    reg.Jurisdiction__c = 'ES';
    reg.Published_On__c = System.today().addDays(-30);
    NoticeMatchingService.running = true;
    insert new List<External_Notice__c>{ recall, reg };
    NoticeMatchingService.running = false;
    NoticeMatchingService.match(new Set<Id>{ recall.Id, reg.Id });

    FleetExposureController.Summary s = FleetExposureController.getSummary();
    Map<String, Integer> byType = new Map<String, Integer>();
    for (FleetExposureController.TypeCount t : s.openByType) {
      byType.put(t.alertType, t.count);
    }
    Assert.areEqual(2, byType.get('Recall'));
    Assert.areEqual(1, byType.get('Regulation'));
    Assert.isTrue(byType.get('Data gap') > 0);
    Assert.areEqual(1, s.vehiclesAtRisk);
    Assert.areEqual(1, s.newNotices7d);
    Assert.areEqual(2, s.scoredVehicles);
    Assert.isNotNull(s.averageHealth);
    Assert.isTrue(s.isSample);
    // each tile carries the list view of the records it counts (list views deploy with the package, so they exist here)
    Assert.areEqual(6, s.lists.size());
    Assert.areEqual(
      Asset_Alert__c.SObjectType.getDescribe().getName(),
      s.lists.get('reg').objectApiName
    );
    Assert.areEqual(
      Fleet_Asset__c.SObjectType.getDescribe().getName(),
      s.lists.get('risk').objectApiName
    );
    Assert.isNotNull(s.lists.get('new').listViewId);

    List<FleetExposureController.NoticeRow> notices = FleetExposureController.getNotices();
    Assert.areEqual(2, notices.size());
    Assert.areEqual('RCL-1', notices[0].externalId, 'newest first');
    Assert.areEqual(2, notices[0].affectedCount);

    List<FleetExposureController.VehicleRow> vehicles = FleetExposureController.getAffectedVehicles(
      recall.Id
    );
    Assert.areEqual(2, vehicles.size());
    for (FleetExposureController.VehicleRow v : vehicles) {
      Assert.areEqual('New', v.alertStatus);
      Assert.isNotNull(v.healthScore);
      Assert.isTrue(v.assetName.startsWith('2023 Ford Transit'));
    }

    Map<String, FleetExposureController.SourceRow> sources = new Map<String, FleetExposureController.SourceRow>();
    for (
      FleetExposureController.SourceRow r : FleetExposureController.getSourceHealth()
    ) {
      sources.put(r.name, r);
    }
    Assert.areEqual(6, sources.get('Tele').streams);
    Assert.areEqual(1, sources.get('Tele').stale);
    Assert.areEqual(17, sources.get('Tele').staleShare);
    Assert.areEqual(0, sources.get('Empty').streams);
    Assert.areEqual(0, sources.get('Empty').staleShare);
  }

  @IsTest
  static void exposureViewWithNothingYet() {
    FleetExposureController.Summary s = FleetExposureController.getSummary();
    Assert.areEqual(0, s.openAlerts);
    Assert.isNull(s.averageHealth);
    Assert.isFalse(s.isSample);
    Assert.areEqual(0, FleetExposureController.getNotices().size());
    Assert.areEqual(0, FleetExposureController.getSourceHealth().size());
    Assert.areEqual(
      0,
      FleetExposureController.getAffectedVehicles(null).size()
    );
  }
}
