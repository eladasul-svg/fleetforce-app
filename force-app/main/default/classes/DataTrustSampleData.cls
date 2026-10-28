/**
 * Sample data for the data trust preview. Everything it creates is fictional and flagged Is_Sample__c = true, and
 * reset() deletes exactly those records. seed() starts with reset(), so running it twice gives the same result.
 * It extends the existing demo fleet (no new vehicles); all dates are offsets from the moment it runs.
 *
 *   Vendors    12 telematics vendor accounts with their public contact details (kept by reset: they are real data)
 *   Sources    Geotab, Samsara and Webfleet telematics (linked to those accounts), FMC maintenance file (sample),
 *              Fuel card feed (sample); vehicles are spread across the three telematics sources in name order
 *   Profiles   Standard (8 signals, default) and EV batch (14 signals, Fuel Type = Electric)
 *   Streams    most vehicles healthy; 8 with stale telematics (3 to 9 days, REF-3 included); 5 missing a required stream.
 *              Inactive vehicles (on order, retired) get healthy streams too, so every record page has data to show
 *   Data gaps  2 vehicles where the FMC file shows an active maintenance plan the fleet record does not have
 *   Notices    SAMPLE-RCL-001 / 002 (criteria picked from the fleet to match about 9 and 4 vehicles) and two
 *              regulations with future effective dates and three-country jurisdictions
 *   Reference  REF-1 / REF-2 / REF-3: three vehicles with hand-calculated scores (see docs/data-trust/seed-README.md)
 *
 * Run:  sf apex run --file scripts/apex/data_trust_seed.apex   /   scripts/apex/data_trust_reset.apex
 */
public with sharing class DataTrustSampleData {
  /** The telematics vendors whose accounts feed the sample streams, in the order vehicles are assigned to them. */
  public static final List<String> TELEMATICS_SOURCES = new List<String>{
    'Geotab',
    'Samsara',
    'Webfleet'
  };

  /**
   * Telematics vendors as accounts: name, website, login URL, phone, city, state, country, description.
   * Public contact details as published by each vendor (or a business directory where the vendor publishes none);
   * blank where no reliable value was found.
   */
  public static final List<List<String>> TELEMATICS_VENDORS = new List<List<String>>{
    new List<String>{
      'Samsara',
      'https://www.samsara.com',
      'https://cloud.samsara.com/signin',
      '+1 415 985 2400',
      'San Francisco',
      'CA',
      'United States',
      'Connected operations platform: vehicle telematics, video safety and equipment monitoring.'
    },
    new List<String>{
      'Geotab',
      'https://www.geotab.com',
      'https://my.geotab.com',
      '+1 877 436 8221',
      'Oakville',
      'ON',
      'Canada',
      'Telematics devices and the MyGeotab fleet platform, sold through authorised resellers.'
    },
    new List<String>{
      'Webfleet',
      'https://www.webfleet.com',
      'https://live.webfleet.com',
      '+1 866 224 9451',
      'Amsterdam',
      null,
      'Netherlands',
      'Fleet management platform from Bridgestone Mobility Solutions.'
    },
    new List<String>{
      'Verizon Connect',
      'https://www.verizonconnect.com',
      'https://login.us.vzconnect.com',
      '+1 844 617 1100',
      'Atlanta',
      'GA',
      'United States',
      'Fleet tracking and the Reveal fleet management platform.'
    },
    new List<String>{
      'Motive',
      'https://gomotive.com',
      'https://app.gomotive.com',
      '+1 855 434 3564',
      'San Francisco',
      'CA',
      'United States',
      'ELDs, AI dashcams and fleet management (formerly KeepTruckin).'
    },
    new List<String>{
      'Lytx',
      'https://www.lytx.com',
      'https://login.lytx.com',
      '+1 866 910 0403',
      'San Diego',
      'CA',
      'United States',
      'Video telematics and DriveCam driver safety programmes.'
    },
    new List<String>{
      'Ituran',
      'https://www.ituran.com',
      null,
      '+972 3 557 1314',
      'Azor',
      null,
      'Israel',
      'Vehicle tracking, stolen vehicle recovery and fleet telematics.'
    },
    new List<String>{
      'Teletrac Navman',
      'https://www.teletracnavman.com',
      null,
      '+1 800 894 1881',
      null,
      null,
      'United States',
      'TN360 fleet management platform for mixed fleets and heavy equipment.'
    },
    new List<String>{
      'Azuga',
      'https://www.azuga.com',
      null,
      '+1 888 790 0715',
      'Fremont',
      'CA',
      'United States',
      'Fleet tracking and driver safety, part of Bridgestone.'
    },
    new List<String>{
      'GPS Insight',
      'https://www.gpsinsight.com',
      null,
      '+1 866 477 4321',
      'Scottsdale',
      'AZ',
      'United States',
      'GPS fleet tracking, ELD compliance and field service telematics.'
    },
    new List<String>{
      'Powerfleet',
      'https://www.powerfleet.com',
      'http://unityaiot.com',
      null,
      'Woodcliff Lake',
      'NJ',
      'United States',
      'AIoT fleet and asset platform (Unity), including the former MiX Telematics.'
    },
    new List<String>{
      'Cartrack',
      'https://www.cartrack.pt',
      null,
      null,
      null,
      null,
      'Portugal',
      'Vehicle tracking and fleet management; operates locally as Cartrack Portugal, S.A.'
    }
  };
  public static final String FMC = 'FMC maintenance file (sample)';
  public static final String FUEL_CARD = 'Fuel card feed (sample)';

  /** What the seed did, for the script output and the tests. */
  public class Summary {
    public Integer vehicles = 0;
    public Integer inactiveVehicles = 0;
    public Integer electric = 0;
    public Integer streams = 0;
    public Integer staleTelematics = 0;
    public Integer missingStream = 0;
    public Integer consistencyGaps = 0;
    public Map<String, Integer> noticeMatches = new Map<String, Integer>();
    public Map<String, Id> referenceVehicles = new Map<String, Id>();
    public Map<String, Integer> referenceScores = new Map<String, Integer>();

    public override String toString() {
      return JSON.serializePretty(this);
    }
  }

  // --------------------------------------------------------------------------------------------------- reset

  public static void reset() {
    Boolean dh = DataHealthService.running;
    Boolean nm = NoticeMatchingService.running;
    DataHealthService.running = true;
    NoticeMatchingService.running = true;
    try {
      Set<Id> assetIds = new Set<Id>();
      for (Data_Stream__c s : [
        SELECT Fleet_Asset__c
        FROM Data_Stream__c
        WHERE Is_Sample__c = TRUE
      ]) {
        assetIds.add(s.Fleet_Asset__c);
      }
      for (Asset_Alert__c a : [
        SELECT Fleet_Asset__c
        FROM Asset_Alert__c
        WHERE Is_Sample__c = TRUE
      ]) {
        assetIds.add(a.Fleet_Asset__c);
      }
      delete [
        SELECT Id
        FROM Asset_Alert__c
        WHERE Is_Sample__c = TRUE OR External_Notice__r.Is_Sample__c = TRUE
      ];
      delete [SELECT Id FROM Data_Stream__c WHERE Is_Sample__c = TRUE];
      delete [SELECT Id FROM External_Notice__c WHERE Is_Sample__c = TRUE];
      delete [SELECT Id FROM Stream_Profile__c WHERE Is_Sample__c = TRUE];
      delete [SELECT Id FROM Data_Source__c WHERE Is_Sample__c = TRUE];

      List<Fleet_Asset__c> cleared = new List<Fleet_Asset__c>();
      for (Id assetId : assetIds) {
        cleared.add(
          new Fleet_Asset__c(
            Id = assetId,
            Data_Health_Score__c = null,
            Data_Health_Status__c = null,
            Freshness_Score__c = null,
            Completeness_Score__c = null,
            Consistency_Score__c = null,
            Data_Health_Calculated__c = null,
            Resolved_Stream_Profile__c = null,
            Stream_Profile_Override__c = null
          )
        );
      }
      update cleared;
      AssetAlertService.recountOpenAlerts(assetIds);
    } finally {
      DataHealthService.running = dh;
      NoticeMatchingService.running = nm;
    }
  }

  // --------------------------------------------------------------------------------------------------- seed

  public static Summary seed() {
    reset();
    Summary sum = new Summary();
    Datetime nowTs = System.now();
    Date today = nowTs.date();

    Boolean dh = DataHealthService.running;
    Boolean nm = NoticeMatchingService.running;
    DataHealthService.running = true;
    NoticeMatchingService.running = true;
    List<Fleet_Asset__c> allAssets;
    List<Fleet_Asset__c> fleet = new List<Fleet_Asset__c>();
    List<Fleet_Asset__c> inactive = new List<Fleet_Asset__c>();
    Map<String, External_Notice__c> notices;
    try {
      allAssets = prepareFleet();
      for (Fleet_Asset__c a : allAssets) {
        if (a.Is_Active__c) {
          fleet.add(a);
        } else {
          inactive.add(a);
        }
      }
      sum.vehicles = fleet.size();
      sum.inactiveVehicles = inactive.size();

      // sources
      // telematics: one source per vendor account, linked so the record page can open the vendor
      Map<String, Account> vendors = ensureVendorAccounts();
      List<Data_Source__c> teles = new List<Data_Source__c>();
      for (String v : TELEMATICS_SOURCES) {
        Account acct = vendors.get(v);
        Data_Source__c tsrc = source(
          v + ' telematics',
          acct.Name,
          'Telematics',
          String.isNotBlank(acct.Login_URL__c)
            ? acct.Login_URL__c
            : acct.Website,
          1,
          nowTs.addMinutes(-20)
        );
        tsrc.Vendor_Account__c = acct.Id;
        teles.add(tsrc);
      }
      Integer t = 0; // next telematics source, round robin in the order vehicles are seeded
      Data_Source__c fmc = source(
        FMC,
        'Sample Fleet Management Co.',
        'FMC feed',
        'https://fmc.example.com/portal',
        168,
        nowTs.addDays(-2)
      );
      Data_Source__c fuel = source(
        FUEL_CARD,
        'Sample Fuel Card Ltd.',
        'Other',
        'https://fuelcard.example.com',
        24,
        nowTs.addHours(-10)
      );
      insert new List<Data_Source__c>{ fmc, fuel };
      insert teles;

      // profiles
      Stream_Profile__c standard = new Stream_Profile__c(
        Name = 'Standard',
        Expected_Signal_Count__c = 8,
        Is_Default__c = true,
        Priority__c = 100,
        Active__c = true,
        Is_Sample__c = true
      );
      Stream_Profile__c ev = new Stream_Profile__c(
        Name = 'EV batch',
        Expected_Signal_Count__c = 14,
        Fuel_Type__c = 'Electric',
        Priority__c = 10,
        Active__c = true,
        Is_Sample__c = true
      );
      insert new List<Stream_Profile__c>{ standard, ev };
      insert new List<Stream_Profile_Line__c>{
        line(standard, 'Location', true, 24, 2),
        line(standard, 'Odometer', true, 72, 1),
        line(standard, 'Fuel or charge', true, 72, 1),
        line(standard, 'Maintenance plan', true, 720, 1),
        line(standard, 'Diagnostics', false, 168, null),
        line(ev, 'Location', true, 24, 3),
        line(ev, 'Odometer', true, 72, 1),
        line(ev, 'Fuel or charge', true, 24, 4),
        line(ev, 'Diagnostics', true, 72, 3),
        line(ev, 'Maintenance plan', true, 720, 1)
      };

      // notices: recall criteria are chosen from the fleet so the matches land near 9 and 4 vehicles
      notices = buildNotices(fleet, today);
      insert notices.values();

      // pick the reference vehicles: REF-3 (at risk) is a non-electric vehicle the first recall matches
      List<Fleet_Asset__c> nonEv = new List<Fleet_Asset__c>();
      List<Fleet_Asset__c> evs = new List<Fleet_Asset__c>();
      for (Fleet_Asset__c a : fleet) {
        if (a.Fuel_Type__c == 'Electric') {
          evs.add(a);
        } else {
          nonEv.add(a);
        }
      }
      sum.electric = evs.size();
      Fleet_Asset__c ref3 = null;
      for (Fleet_Asset__c a : nonEv) {
        if (NoticeMatchingService.matches(notices.get('SAMPLE-RCL-001'), a)) {
          ref3 = a;
          break;
        }
      }
      List<Fleet_Asset__c> rest = new List<Fleet_Asset__c>();
      for (Fleet_Asset__c a : nonEv) {
        if (ref3 == null || a.Id != ref3.Id) {
          rest.add(a);
        }
      }
      if (ref3 == null && !rest.isEmpty()) {
        ref3 = rest.remove(rest.size() - 1);
      }
      Fleet_Asset__c ref1 = rest.isEmpty() ? null : rest.remove(0);
      Fleet_Asset__c ref2 = rest.isEmpty() ? null : rest.remove(0);

      List<Data_Stream__c> streams = new List<Data_Stream__c>();
      List<Asset_Alert__c> gaps = new List<Asset_Alert__c>();
      Map<Id, Data_Stream__c> maintStreamByAsset = new Map<Id, Data_Stream__c>();

      // REF-1: everything fresh, all 8 signals                    -> F 100, C 100, K 100 = 100 Healthy
      if (ref1 != null) {
        streams.addAll(
          standardStreams(
            ref1,
            teles[Math.mod(t++, teles.size())],
            fmc,
            fuel,
            nowTs,
            2,
            12,
            72,
            true,
            2,
            true
          )
        );
        sum.referenceVehicles.put('REF-1', ref1.Id);
      }
      // REF-2: telematics 60 h old, no diagnostics, fuel card 1 signal -> F 81, C 75, K 90 = 80 Watch
      if (ref2 != null) {
        streams.addAll(
          standardStreams(
            ref2,
            teles[Math.mod(t++, teles.size())],
            fmc,
            fuel,
            nowTs,
            60,
            12,
            72,
            false,
            1,
            true
          )
        );
        sum.referenceVehicles.put('REF-2', ref2.Id);
      }
      // REF-3: telematics 9 days old, no maintenance plan stream     -> F 25, C 75, K 25 = 45 At risk
      // (it is one of the 8 stale-telematics vehicles and one of the 5 missing a stream)
      if (ref3 != null) {
        streams.addAll(
          standardStreams(
            ref3,
            teles[Math.mod(t++, teles.size())],
            fmc,
            fuel,
            nowTs,
            216,
            12,
            null,
            true,
            2,
            true
          )
        );
        sum.referenceVehicles.put('REF-3', ref3.Id);
        sum.staleTelematics++;
        sum.missingStream++;
      }

      // the rest of the fleet, in name order: 8 stale telematics, 5 missing a stream, 2 consistency gaps, rest healthy
      List<Integer> staleDays = new List<Integer>{ 3, 4, 5, 6, 7, 8, 9 };
      Integer staleTarget = sum.staleTelematics + staleDays.size();
      Integer staleIdx = 0;
      Integer i = 0;
      for (Fleet_Asset__c a : rest) {
        Integer teleAge = 1 + Math.mod(i, 5);
        Integer fuelAge = 6 + Math.mod(i, 12);
        Integer maintAge = 24 * (1 + Math.mod(i, 20));
        Boolean hasFuel = true;
        Boolean hasMaint = true;
        if (sum.staleTelematics < staleTarget) {
          teleAge = 24 * staleDays[staleIdx++] + Math.mod(i, 7);
          sum.staleTelematics++;
        } else if (sum.missingStream < 5) {
          if (sum.missingStream < 3) {
            // 2 more without a maintenance plan (REF-3 is the first), then 2 without a fuel feed
            hasMaint = false;
          } else {
            hasFuel = false;
          }
          sum.missingStream++;
        } else if (sum.consistencyGaps < 2) {
          sum.consistencyGaps++;
          gaps.add(
            new Asset_Alert__c(
              Fleet_Asset__c = a.Id,
              Unique_Key__c = 'DGC:' + a.Id + ':Maintenance plan',
              Alert_Type__c = 'Data gap',
              Severity__c = 'High',
              Status__c = 'New',
              Is_Sample__c = true,
              Title__c = 'Maintenance plan active in FMC file, missing on fleet record',
              Detail__c = 'The ' +
                FMC +
                ' lists an active maintenance plan for this vehicle, but the fleet record has none. ' +
                'Check which system is right and update the other.'
            )
          );
        }
        List<Data_Stream__c> mine = standardStreams(
          a,
          teles[Math.mod(t++, teles.size())],
          fmc,
          fuel,
          nowTs,
          teleAge,
          hasFuel ? fuelAge : null,
          hasMaint ? maintAge : null,
          true,
          2,
          hasFuel
        );
        streams.addAll(mine);
        i++;
      }
      for (Fleet_Asset__c a : evs) {
        streams.addAll(
          evStreams(
            a,
            teles[Math.mod(t++, teles.size())],
            fmc,
            nowTs,
            1 + Math.mod(i, 4)
          )
        );
        i++;
      }
      // inactive vehicles sit outside the scenario above: all healthy, so the counts and references stay put
      for (Fleet_Asset__c a : inactive) {
        if (a.Fuel_Type__c == 'Electric') {
          streams.addAll(
            evStreams(
              a,
              teles[Math.mod(t++, teles.size())],
              fmc,
              nowTs,
              1 + Math.mod(i, 4)
            )
          );
        } else {
          streams.addAll(
            standardStreams(
              a,
              teles[Math.mod(t++, teles.size())],
              fmc,
              fuel,
              nowTs,
              1 + Math.mod(i, 5),
              6 + Math.mod(i, 12),
              24 * (1 + Math.mod(i, 20)),
              true,
              2,
              true
            )
          );
        }
        i++;
      }
      insert streams;
      sum.streams = streams.size();
      for (Data_Stream__c s : streams) {
        if (s.Data_Type__c == 'Maintenance plan') {
          maintStreamByAsset.put(s.Fleet_Asset__c, s);
        }
      }
      for (Asset_Alert__c g : gaps) {
        g.Data_Stream__c = maintStreamByAsset.get(g.Fleet_Asset__c)?.Id;
      }
      insert gaps;
    } finally {
      DataHealthService.running = dh;
      NoticeMatchingService.running = nm;
    }

    // score every vehicle and match the notices, the same way the nightly job does
    Map<Id, DataHealthService.Result> results = DataHealthService.evaluate(
      new Map<Id, Fleet_Asset__c>(allAssets).keySet()
    );
    NoticeMatchingService.match(
      new Map<Id, External_Notice__c>(notices.values()).keySet()
    );
    for (External_Notice__c n : [
      SELECT External_Id__c, Affected_Count__c
      FROM External_Notice__c
      WHERE Is_Sample__c = TRUE
    ]) {
      sum.noticeMatches.put(
        n.External_Id__c,
        n.Affected_Count__c == null ? 0 : n.Affected_Count__c.intValue()
      );
    }
    for (String ref : sum.referenceVehicles.keySet()) {
      sum.referenceScores.put(
        ref,
        results.get(sum.referenceVehicles.get(ref)).score
      );
    }
    return sum;
  }

  // --------------------------------------------------------------------------------------------------- vendors

  /**
   * Creates or refreshes the telematics vendor accounts, matched by name. They are real data, not sample: reset()
   * leaves them in place, and fields the seed does not set (owner, notes, contacts) are kept.
   */
  public static Map<String, Account> ensureVendorAccounts() {
    Set<String> names = new Set<String>();
    for (List<String> v : TELEMATICS_VENDORS) {
      names.add(v[0]);
    }
    Map<String, Id> existing = new Map<String, Id>();
    for (Account a : [
      SELECT Id, Name
      FROM Account
      WHERE Name IN :names
      ORDER BY CreatedDate
    ]) {
      if (!existing.containsKey(a.Name)) {
        existing.put(a.Name, a.Id);
      }
    }
    Map<String, Account> byName = new Map<String, Account>();
    for (List<String> v : TELEMATICS_VENDORS) {
      byName.put(
        v[0],
        new Account(
          Id = existing.get(v[0]),
          Name = v[0],
          Website = v[1],
          Login_URL__c = v[2],
          Phone = v[3],
          BillingCity = v[4],
          BillingState = v[5],
          BillingCountry = v[6],
          Description = v[7],
          Type = 'Technology Partner',
          Industry = 'Transportation'
        )
      );
    }
    upsert byName.values();
    return byName;
  }

  // --------------------------------------------------------------------------------------------------- fleet

  /** Every vehicle in name order, with make, model, year and country filled in from the name where blank. */
  @TestVisible
  private static List<Fleet_Asset__c> prepareFleet() {
    List<Fleet_Asset__c> fleet = [
      SELECT
        Id,
        Name,
        Is_Active__c,
        Make__c,
        Model__c,
        Model_Year__c,
        Country__c,
        Fuel_Type__c,
        Vehicle_Class__c
      FROM Fleet_Asset__c
      ORDER BY Name, Id
      LIMIT 500
    ];
    List<Fleet_Asset__c> changed = new List<Fleet_Asset__c>();
    Integer i = 0;
    for (Fleet_Asset__c a : fleet) {
      NameParts p = parseName(a.Name);
      Boolean dirty = false;
      if (a.Model_Year__c == null && p.year != null) {
        a.Model_Year__c = p.year;
        dirty = true;
      }
      if (String.isBlank(a.Make__c) && p.make != null) {
        a.Make__c = p.make;
        dirty = true;
      }
      if (String.isBlank(a.Model__c) && p.model != null) {
        a.Model__c = p.model;
        dirty = true;
      }
      if (String.isBlank(a.Country__c)) {
        // the demo fleet runs from Lisbon; a few vehicles are cross-border so the regulations differ
        a.Country__c = Math.mod(i, 5) == 3
          ? 'ES'
          : (Math.mod(i, 7) == 6 ? 'GB' : 'PT');
        dirty = true;
      }
      if (dirty) {
        changed.add(
          new Fleet_Asset__c(
            Id = a.Id,
            Make__c = a.Make__c,
            Model__c = a.Model__c,
            Model_Year__c = a.Model_Year__c,
            Country__c = a.Country__c
          )
        );
      }
      if (a.Is_Active__c) {
        // the country rotation counts active vehicles only, as before inactive ones were seeded
        i++;
      }
    }
    update changed;
    return fleet;
  }

  public class NameParts {
    public Integer year;
    public String make;
    public String model;
  }

  /** "2023 Ford F-150 Lariat 4WD (On Order)" -> 2023 / Ford / F-150. */
  public static NameParts parseName(String name) {
    NameParts p = new NameParts();
    if (String.isBlank(name)) {
      return p;
    }
    List<String> words = name.replaceFirst('\\s*\\([^)]*\\)\\s*$', '')
      .trim()
      .split('\\s+');
    Integer at = 0;
    if (!words.isEmpty() && words[0].isNumeric() && words[0].length() == 4) {
      p.year = Integer.valueOf(words[0]);
      at = 1;
    }
    if (words.size() > at) {
      p.make = words[at];
    }
    if (words.size() > at + 1) {
      p.model = words[at + 1];
    }
    return p;
  }

  // --------------------------------------------------------------------------------------------------- notices

  @TestVisible
  private static Map<String, External_Notice__c> buildNotices(
    List<Fleet_Asset__c> fleet,
    Date today
  ) {
    Criteria c1 = pickCriteria(fleet, 9, null);
    Criteria c2 = pickCriteria(fleet, 4, c1);
    Map<String, External_Notice__c> out = new Map<String, External_Notice__c>();
    out.put(
      'SAMPLE-RCL-001',
      new External_Notice__c(
        Name = 'SAMPLE-RCL-001',
        External_Id__c = 'SAMPLE-RCL-001',
        Notice_Type__c = 'Recall',
        Is_Sample__c = true,
        Source__c = 'Manufacturer recall (sample)',
        Severity__c = 'High',
        Status__c = 'Active',
        Reviewed__c = true,
        Title__c = c1.label() + ': rear axle bolt may loosen (sample)',
        Summary__c = 'Fictional recall for the preview. A rear axle bolt may not have been torqued to specification. ' +
          'Dealers will inspect and re-torque the bolt free of charge.',
        Source_URL__c = 'https://recalls.example.com/SAMPLE-RCL-001',
        Published_On__c = today.addDays(-2),
        Effective_On__c = today.addDays(30),
        Make__c = c1.make,
        Model__c = c1.model,
        Year_From__c = c1.yearFrom,
        Year_To__c = c1.yearTo
      )
    );
    out.put(
      'SAMPLE-RCL-002',
      new External_Notice__c(
        Name = 'SAMPLE-RCL-002',
        External_Id__c = 'SAMPLE-RCL-002',
        Notice_Type__c = 'Recall',
        Is_Sample__c = true,
        Source__c = 'Manufacturer recall (sample)',
        Severity__c = 'Critical',
        Status__c = 'Active',
        Reviewed__c = true,
        Title__c = c2.label() + ': airbag inflator inspection (sample)',
        Summary__c = 'Fictional recall for the preview. The passenger airbag inflator may need replacement. ' +
          'Do not seat passengers in the front until inspected.',
        Source_URL__c = 'https://recalls.example.com/SAMPLE-RCL-002',
        Published_On__c = today.addDays(-20),
        Effective_On__c = today.addDays(14),
        Make__c = c2.make,
        Model__c = c2.model,
        Year_From__c = c2.yearFrom,
        Year_To__c = c2.yearTo
      )
    );
    out.put(
      'SAMPLE-REG-LEZ',
      new External_Notice__c(
        Name = 'SAMPLE-REG-LEZ',
        External_Id__c = 'SAMPLE-REG-LEZ',
        Notice_Type__c = 'Regulation',
        Is_Sample__c = true,
        Source__c = 'Regulation digest (sample)',
        Severity__c = 'Medium',
        Status__c = 'Active',
        Reviewed__c = true,
        Title__c = 'Low-emission zone: older diesel vans restricted (sample)',
        Summary__c = 'Fictional rule change for the preview. City low-emission zones extend to diesel vehicles; ' +
          'affected vehicles need an exemption or a route change before the effective date.',
        Source_URL__c = 'https://regulations.example.com/SAMPLE-REG-LEZ',
        Published_On__c = today.addDays(-3),
        Effective_On__c = today.addDays(45),
        Jurisdiction__c = 'PT;ES;FR',
        Fuel_Type__c = 'Diesel'
      )
    );
    out.put(
      'SAMPLE-REG-DOC',
      new External_Notice__c(
        Name = 'SAMPLE-REG-DOC',
        External_Id__c = 'SAMPLE-REG-DOC',
        Notice_Type__c = 'Regulation',
        Is_Sample__c = true,
        Source__c = 'Regulation digest (sample)',
        Severity__c = 'Low',
        Status__c = 'Active',
        Reviewed__c = true,
        Title__c = 'Commercial vehicles must carry digital driver documents (sample)',
        Summary__c = 'Fictional rule change for the preview. Drivers of commercial vehicles must carry digital copies ' +
          'of licence and vehicle documents.',
        Source_URL__c = 'https://regulations.example.com/SAMPLE-REG-DOC',
        Published_On__c = today.addDays(-10),
        Effective_On__c = today.addDays(90),
        Jurisdiction__c = 'PT;ES;IT',
        Vehicle_Category__c = 'Commercial'
      )
    );
    return out;
  }

  @TestVisible
  private class Criteria {
    public String make;
    public String model;
    public Integer yearFrom;
    public Integer yearTo;
    public Integer count = 0;
    public Set<Id> ids = new Set<Id>();

    public String label() {
      String yrs = yearFrom == null
        ? ''
        : (yearFrom == yearTo ? yearFrom + ' ' : yearFrom + '-' + yearTo + ' ');
      return (yrs +
        (make ?? 'Multiple makes') +
        (model == null ? '' : ' ' + model))
        .trim();
    }
  }

  /**
   * Picks a make / model / year-range combination from the fleet whose match count is closest to the target,
   * preferring one that does not overlap `avoid`. Deterministic for a given fleet.
   */
  @TestVisible
  private static Criteria pickCriteria(
    List<Fleet_Asset__c> fleet,
    Integer target,
    Criteria avoid
  ) {
    Map<String, Criteria> candidates = new Map<String, Criteria>();
    for (Fleet_Asset__c a : fleet) {
      if (a.Make__c == null) {
        continue;
      }
      Integer y = a.Model_Year__c == null ? null : a.Model_Year__c.intValue();
      addCandidate(candidates, a, a.Make__c, null, null, null);
      if (a.Model__c != null) {
        addCandidate(candidates, a, a.Make__c, a.Model__c, null, null);
      }
      if (y != null) {
        addCandidate(candidates, a, a.Make__c, null, y, y);
        addCandidate(candidates, a, a.Make__c, null, y - 1, y);
        addCandidate(candidates, a, a.Make__c, null, y, y + 1);
      }
    }
    // a year range candidate must count every vehicle of that make in the range, not just the one that created it
    for (Criteria c : candidates.values()) {
      c.ids.clear();
      for (Fleet_Asset__c a : fleet) {
        if (
          DataHealthService.same(c.make, a.Make__c) &&
          DataHealthService.same(c.model, a.Model__c) &&
          (c.yearFrom == null ||
          (a.Model_Year__c != null &&
          a.Model_Year__c >= c.yearFrom &&
          a.Model_Year__c <= c.yearTo))
        ) {
          c.ids.add(a.Id);
        }
      }
      c.count = c.ids.size();
    }
    List<String> keys = new List<String>(candidates.keySet());
    keys.sort();
    Criteria best;
    Integer bestCost;
    for (String k : keys) {
      Criteria c = candidates.get(k);
      Integer overlap = 0;
      if (avoid != null) {
        for (Id i : c.ids) {
          if (avoid.ids.contains(i)) {
            overlap++;
          }
        }
      }
      Integer cost =
        Math.abs(c.count - target) * 10 +
        overlap * 3 +
        (c.model == null ? 1 : 0);
      if (best == null || cost < bestCost) {
        best = c;
        bestCost = cost;
      }
    }
    return best ?? new Criteria();
  }

  private static void addCandidate(
    Map<String, Criteria> m,
    Fleet_Asset__c a,
    String make,
    String model,
    Integer yFrom,
    Integer yTo
  ) {
    String k = (make +
      '|' +
      (model ?? '') +
      '|' +
      (yFrom ?? 0) +
      '|' +
      (yTo ?? 0))
      .toLowerCase();
    if (!m.containsKey(k)) {
      Criteria c = new Criteria();
      c.make = make;
      c.model = model;
      c.yearFrom = yFrom;
      c.yearTo = yTo;
      m.put(k, c);
    }
  }

  // --------------------------------------------------------------------------------------------------- builders

  private static Data_Source__c source(
    String name,
    String vendor,
    String type,
    String url,
    Integer freqHours,
    Datetime lastReceived
  ) {
    return new Data_Source__c(
      Name = name,
      Vendor__c = vendor,
      Source_Type__c = type,
      Reference_URL__c = url,
      Status__c = 'Active',
      Expected_Frequency_Hours__c = freqHours,
      Last_Received__c = lastReceived,
      Is_Sample__c = true
    );
  }

  private static Stream_Profile_Line__c line(
    Stream_Profile__c p,
    String type,
    Boolean required,
    Integer maxAge,
    Integer minSignals
  ) {
    return new Stream_Profile_Line__c(
      Stream_Profile__c = p.Id,
      Data_Type__c = type,
      Required__c = required,
      Max_Age_Hours__c = maxAge,
      Min_Signals__c = minSignals
    );
  }

  /**
   * Streams for a vehicle on the Standard profile. Ages are in hours; a null age means that stream is absent.
   * Signals: location 2, odometer 1, diagnostics 1, fuel card `fuelSignals`, maintenance plan 2.
   */
  private static List<Data_Stream__c> standardStreams(
    Fleet_Asset__c a,
    Data_Source__c tele,
    Data_Source__c fmc,
    Data_Source__c fuel,
    Datetime nowTs,
    Integer teleAge,
    Integer fuelAge,
    Integer maintAge,
    Boolean withDiagnostics,
    Integer fuelSignals,
    Boolean withFuel
  ) {
    List<Data_Stream__c> out = new List<Data_Stream__c>();
    out.add(stream(a, tele, 'Location', nowTs.addHours(-teleAge), 2, 'TEL'));
    out.add(stream(a, tele, 'Odometer', nowTs.addHours(-teleAge), 1, 'TEL'));
    if (withDiagnostics) {
      out.add(
        stream(a, tele, 'Diagnostics', nowTs.addHours(-teleAge), 1, 'TEL')
      );
    }
    if (withFuel && fuelAge != null) {
      out.add(
        stream(
          a,
          fuel,
          'Fuel or charge',
          nowTs.addHours(-fuelAge),
          fuelSignals,
          'FC'
        )
      );
    }
    if (maintAge != null) {
      out.add(
        stream(a, fmc, 'Maintenance plan', nowTs.addHours(-maintAge), 2, 'FMC')
      );
    }
    return out;
  }

  /** Streams for an electric vehicle: 3 + 1 + 4 + 4 + 2 = 14 signals, all fresh. */
  private static List<Data_Stream__c> evStreams(
    Fleet_Asset__c a,
    Data_Source__c tele,
    Data_Source__c fmc,
    Datetime nowTs,
    Integer teleAge
  ) {
    return new List<Data_Stream__c>{
      stream(a, tele, 'Location', nowTs.addHours(-teleAge), 3, 'TEL'),
      stream(a, tele, 'Odometer', nowTs.addHours(-teleAge), 1, 'TEL'),
      stream(a, tele, 'Fuel or charge', nowTs.addHours(-teleAge), 4, 'TEL'),
      stream(a, tele, 'Diagnostics', nowTs.addHours(-teleAge), 4, 'TEL'),
      stream(a, fmc, 'Maintenance plan', nowTs.addDays(-5), 2, 'FMC')
    };
  }

  private static Data_Stream__c stream(
    Fleet_Asset__c a,
    Data_Source__c src,
    String type,
    Datetime lastUpdate,
    Integer signals,
    String prefix
  ) {
    String extId = prefix + '-' + String.valueOf(a.Id).right(8);
    return new Data_Stream__c(
      Name = (src.Name.removeEnd(' (sample)') + ' - ' + type).left(80),
      Fleet_Asset__c = a.Id,
      Data_Source__c = src.Id,
      Data_Type__c = type,
      External_Id__c = extId,
      Last_Update__c = lastUpdate,
      Signals_Present__c = signals,
      Record_Count_30d__c = lastUpdate > nowMinusDays(30) ? 30 * 24 : 0,
      Reference_URL__c = src.Vendor_Account__c != null
        ? null
        : src.Reference_URL__c + '/vehicles/' + extId,
      Is_Sample__c = true
    );
  }

  private static Datetime nowMinusDays(Integer d) {
    return System.now().addDays(-d);
  }
}
