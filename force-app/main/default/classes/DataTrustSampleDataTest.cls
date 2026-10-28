@IsTest
private class DataTrustSampleDataTest {
  /** A small copy of the demo fleet: 34 combustion / hybrid vehicles and 6 electric ones, names only. */
  @TestSetup
  static void fleet() {
    List<Fleet_Asset__c> fleet = new List<Fleet_Asset__c>();
    Map<String, Integer> combustion = new Map<String, Integer>{
      '2022 Ford Transit-250 Cargo Van' => 6,
      '2023 Ford F-150 XLT' => 3,
      '2024 Ford F-150 STX 4WD' => 2,
      '2023 Chevrolet Silverado 1500 LT' => 4,
      '2024 Toyota Camry Hybrid LE' => 4,
      '2022 Ram ProMaster 1500' => 4,
      '2023 Mercedes-Benz Sprinter 2500' => 3,
      '2022 Isuzu NPR-HD Diesel Truck' => 2,
      '2024 Honda Accord EX' => 2,
      '2023 Subaru Outback Premium' => 2,
      '2023 GMC Savana 2500 Cargo' => 2
    };
    for (String name : combustion.keySet()) {
      for (Integer i = 0; i < combustion.get(name); i++) {
        String fuel = name.contains('Hybrid')
          ? 'Hybrid'
          : (name.contains('Sprinter') || name.contains('Diesel')
              ? 'Diesel'
              : 'Gasoline');
        fleet.add(
          new Fleet_Asset__c(
            Name = name + ' #' + i,
            Is_Active__c = true,
            Fuel_Type__c = fuel,
            Vehicle_Class__c = 'Commercial'
          )
        );
      }
    }
    for (
      String name : new List<String>{
        '2023 Ford E-Transit Cargo Van EV',
        '2024 Ford F-150 Lightning Pro EV',
        '2025 Chevrolet Silverado EV'
      }
    ) {
      for (Integer i = 0; i < 2; i++) {
        fleet.add(
          new Fleet_Asset__c(
            Name = name + ' #' + i,
            Is_Active__c = true,
            Fuel_Type__c = 'Electric',
            Vehicle_Class__c = 'Standard'
          )
        );
      }
    }
    fleet.add(
      new Fleet_Asset__c(
        Name = '2018 Chevrolet Express (Decommissioned)',
        Is_Active__c = false,
        Fuel_Type__c = 'Gasoline'
      )
    );
    insert fleet;
  }

  static Map<String, Integer> counts() {
    return new Map<String, Integer>{
      'sources' => [
        SELECT COUNT()
        FROM Data_Source__c
        WHERE Is_Sample__c = TRUE
      ],
      'profiles' => [
        SELECT COUNT()
        FROM Stream_Profile__c
        WHERE Is_Sample__c = TRUE
      ],
      'lines' => [
        SELECT COUNT()
        FROM Stream_Profile_Line__c
        WHERE Stream_Profile__r.Is_Sample__c = TRUE
      ],
      'streams' => [
        SELECT COUNT()
        FROM Data_Stream__c
        WHERE Is_Sample__c = TRUE
      ],
      'notices' => [
        SELECT COUNT()
        FROM External_Notice__c
        WHERE Is_Sample__c = TRUE
      ],
      'alerts' => [SELECT COUNT() FROM Asset_Alert__c],
      'openAlerts' => [
        SELECT COUNT()
        FROM Asset_Alert__c
        WHERE Status__c IN :AssetAlertService.OPEN_STATUSES
      ],
      'stale' => [SELECT COUNT() FROM Data_Stream__c WHERE Status__c = 'Stale'],
      'atRisk' => [
        SELECT COUNT()
        FROM Fleet_Asset__c
        WHERE Data_Health_Status__c = 'At risk'
      ]
    };
  }

  @IsTest
  static void seedBuildsTheDemoAndReferenceScoresMatchTheReadme() {
    Test.startTest();
    DataTrustSampleData.Summary s = DataTrustSampleData.seed();
    Test.stopTest();

    Assert.areEqual(40, s.vehicles);
    Assert.areEqual(1, s.inactiveVehicles);
    Assert.areEqual(6, s.electric);
    Assert.areEqual(8, s.staleTelematics);
    Assert.areEqual(5, s.missingStream);
    Assert.areEqual(2, s.consistencyGaps);
    Assert.areEqual(100, s.referenceScores.get('REF-1'));
    Assert.areEqual(80, s.referenceScores.get('REF-2'));
    Assert.areEqual(45, s.referenceScores.get('REF-3'));
    Assert.areEqual(4, s.noticeMatches.size());
    Assert.isTrue(s.toString().contains('REF-3'));

    Map<String, Integer> c = counts();
    Assert.areEqual(5, c.get('sources'));
    // the telematics sources belong to real vendor accounts, which reset keeps
    Assert.areEqual(
      DataTrustSampleData.TELEMATICS_VENDORS.size(),
      [
        SELECT COUNT()
        FROM Account
        WHERE Type = 'Technology Partner' AND Industry = 'Transportation'
      ]
    );
    Assert.areEqual(
      3,
      [SELECT COUNT() FROM Data_Source__c WHERE Vendor_Account__c != NULL]
    );
    Account samsara = [
      SELECT Website, Login_URL__c, Phone
      FROM Account
      WHERE Name = 'Samsara'
    ];
    Assert.areEqual('https://cloud.samsara.com/signin', samsara.Login_URL__c);
    Assert.isNotNull(samsara.Phone);
    Assert.areEqual(2, c.get('profiles'));
    Assert.areEqual(10, c.get('lines'));
    Assert.areEqual(4, c.get('notices'));

    Fleet_Asset__c ref1 = [
      SELECT Data_Health_Status__c, Resolved_Stream_Profile__r.Name
      FROM Fleet_Asset__c
      WHERE Id = :s.referenceVehicles.get('REF-1')
    ];
    Assert.areEqual('Healthy', ref1.Data_Health_Status__c);
    Assert.areEqual('Standard', ref1.Resolved_Stream_Profile__r.Name);
    Fleet_Asset__c ref2 = [
      SELECT Data_Health_Status__c
      FROM Fleet_Asset__c
      WHERE Id = :s.referenceVehicles.get('REF-2')
    ];
    Assert.areEqual('Watch', ref2.Data_Health_Status__c);

    // REF-3 is the "open an At risk vehicle" step: stale telematics, a data gap and a recall alert
    Id ref3 = s.referenceVehicles.get('REF-3');
    Assert.areEqual(
      'At risk',
      [SELECT Data_Health_Status__c FROM Fleet_Asset__c WHERE Id = :ref3]
      .Data_Health_Status__c
    );
    Assert.isTrue(
      [
        SELECT COUNT()
        FROM Data_Stream__c
        WHERE Fleet_Asset__c = :ref3 AND Status__c = 'Stale'
      ] > 0
    );
    Assert.isTrue(
      [
        SELECT COUNT()
        FROM Asset_Alert__c
        WHERE Fleet_Asset__c = :ref3 AND Alert_Type__c = 'Data gap'
      ] > 0
    );
    Asset_Alert__c recall = [
      SELECT Detail__c, Is_Sample__c
      FROM Asset_Alert__c
      WHERE Fleet_Asset__c = :ref3 AND Alert_Type__c = 'Recall'
      LIMIT 1
    ];
    Assert.isTrue(
      recall.Detail__c.startsWith(NoticeMatchingService.POSSIBLE_MATCH)
    );
    Assert.isTrue(recall.Is_Sample__c);

    // electric vehicles use the EV batch profile and are fully healthy
    for (Fleet_Asset__c ev : [
      SELECT Data_Health_Score__c, Resolved_Stream_Profile__r.Name
      FROM Fleet_Asset__c
      WHERE Fuel_Type__c = 'Electric'
    ]) {
      Assert.areEqual('EV batch', ev.Resolved_Stream_Profile__r.Name);
      Assert.areEqual(100, ev.Data_Health_Score__c.intValue());
    }
    // make, model, year and country were filled in from the names, inactive vehicles included
    Fleet_Asset__c parsed = [
      SELECT Make__c, Model__c, Model_Year__c, Country__c
      FROM Fleet_Asset__c
      WHERE Name = '2023 Mercedes-Benz Sprinter 2500 #0'
    ];
    Assert.areEqual('Mercedes-Benz', parsed.Make__c);
    Assert.areEqual('Sprinter', parsed.Model__c);
    Assert.areEqual(2023, parsed.Model_Year__c.intValue());
    Assert.isNotNull(parsed.Country__c);
    // the inactive vehicle is seeded and scored too, so its record page has data, but recalls skip it
    Fleet_Asset__c parked = [
      SELECT Id, Make__c, Data_Health_Score__c
      FROM Fleet_Asset__c
      WHERE Is_Active__c = FALSE
    ];
    Assert.areEqual('Chevrolet', parked.Make__c);
    Assert.areEqual(100, parked.Data_Health_Score__c.intValue());
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM Asset_Alert__c
        WHERE Fleet_Asset__c = :parked.Id AND Alert_Type__c != 'Data gap'
      ]
    );
    // the two regulations have future effective dates and three-country jurisdictions
    for (External_Notice__c n : [
      SELECT Effective_On__c, Jurisdiction__c
      FROM External_Notice__c
      WHERE Notice_Type__c = 'Regulation'
    ]) {
      Assert.isTrue(n.Effective_On__c > System.today());
      Assert.areEqual(
        3,
        NoticeMatchingService.jurisdictionCodes(n.Jurisdiction__c).size()
      );
    }
  }

  @IsTest
  static void seedTwiceGivesTheSameResultAndResetRemovesEverything() {
    Test.startTest();
    DataTrustSampleData.Summary first = DataTrustSampleData.seed();
    Map<String, Integer> afterFirst = counts();
    DataTrustSampleData.Summary second = DataTrustSampleData.seed();
    Map<String, Integer> afterSecond = counts();
    Test.stopTest();

    Assert.areEqual(afterFirst, afterSecond);
    Assert.areEqual(first.referenceScores, second.referenceScores);
    Assert.areEqual(first.noticeMatches, second.noticeMatches);

    DataTrustSampleData.reset();
    DataTrustSampleData.reset();
    Map<String, Integer> afterReset = counts();
    for (String k : afterReset.keySet()) {
      Assert.areEqual(0, afterReset.get(k), k);
    }
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM Fleet_Asset__c
        WHERE Data_Health_Score__c != NULL OR Open_Alert_Count__c > 0
      ]
    );
    Assert.areEqual(
      DataTrustSampleData.TELEMATICS_VENDORS.size(),
      [
        SELECT COUNT()
        FROM Account
        WHERE Name = 'Geotab' OR Type = 'Technology Partner'
      ],
      'vendor accounts are real data: seeding twice does not duplicate them and reset keeps them'
    );
  }

  @IsTest
  static void nameParsing() {
    DataTrustSampleData.NameParts p = DataTrustSampleData.parseName(
      '2023 Ford F-150 Lariat 4WD (On Order)'
    );
    Assert.areEqual(2023, p.year);
    Assert.areEqual('Ford', p.make);
    Assert.areEqual('F-150', p.model);
    p = DataTrustSampleData.parseName('Tesla');
    Assert.isNull(p.year);
    Assert.areEqual('Tesla', p.make);
    Assert.isNull(p.model);
    Assert.isNull(DataTrustSampleData.parseName(null).make);
  }
}
