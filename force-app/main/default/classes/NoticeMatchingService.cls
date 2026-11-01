/**
 * Matches External_Notice__c records (recalls, regulations, service bulletins) to fleet assets and keeps one
 * Asset_Alert__c per vehicle per notice, keyed NT:<noticeId>:<assetId> so reruns never duplicate.
 *
 * Only notices that are Active AND Reviewed are matched. A notice that is withdrawn, back in draft or not reviewed
 * resolves its open alerts. A vehicle matches when every criterion that is filled in matches: make, model
 * (case-insensitive), model year range, fuel type, category, and a registration country inside the jurisdiction
 * (semicolon- or comma-separated ISO codes; blank = every country). Only active vehicles are matched.
 *
 * Category: a notice's Regulatory Category is matched against the vehicle's Regulatory Category. A vehicle with no
 * Regulatory Category falls back to the notice's Vehicle Category against its Vehicle Class (and does not match when
 * the notice has no Vehicle Category). A notice with no Regulatory Category matches on Vehicle Category only.
 * The country is the vehicle's effective registration country (its own, else its branch country).
 *
 * Recall matches are possible matches: public recall data is by make, model and year, not VIN, so the alert says so.
 * A user's Acknowledged / In progress / Dismissed status is kept on rerun; only system-resolved alerts are reopened.
 */
public with sharing class NoticeMatchingService {
  public static final String POSSIBLE_MATCH = 'Possible match, confirm by VIN with the manufacturer.';

  /** True while the service writes, so the notice trigger does not re-enqueue it. */
  public static Boolean running = false;

  /** Matches every notice that is Active and Reviewed, and clears the rest. Used by the nightly job. */
  public static Integer matchAll() {
    return match(
      new Map<Id, External_Notice__c>(
          [SELECT Id FROM External_Notice__c LIMIT 2000]
        )
        .keySet()
    );
  }

  /** Returns the number of open alerts the notices now carry. */
  public static Integer match(Set<Id> noticeIds) {
    noticeIds = AssetAlertService.withoutNulls(noticeIds);
    if (noticeIds.isEmpty()) {
      return 0;
    }
    Boolean wasRunning = running;
    running = true;
    try {
      return doMatch(noticeIds);
    } finally {
      running = wasRunning;
    }
  }

  private static Integer doMatch(Set<Id> noticeIds) {
    Datetime nowTs = System.now();
    List<External_Notice__c> notices = [
      SELECT
        Id,
        Name,
        Notice_Type__c,
        Title__c,
        Summary__c,
        Severity__c,
        Effective_On__c,
        Status__c,
        Reviewed__c,
        Jurisdiction__c,
        Make__c,
        Model__c,
        Year_From__c,
        Year_To__c,
        Fuel_Type__c,
        Vehicle_Category__c,
        Regulatory_Category__c,
        Affected_Count__c,
        Is_Sample__c
      FROM External_Notice__c
      WHERE Id IN :noticeIds
    ];

    List<External_Notice__c> eligible = new List<External_Notice__c>();
    Set<String> makes = new Set<String>();
    Boolean anyMake = false;
    for (External_Notice__c n : notices) {
      if (isEligible(n)) {
        eligible.add(n);
        if (String.isBlank(n.Make__c)) {
          anyMake = true;
        } else {
          makes.add(n.Make__c.trim());
        }
      }
    }

    List<Fleet_Asset__c> assets = new List<Fleet_Asset__c>();
    if (!eligible.isEmpty()) {
      // narrow the scan by make when every notice names one (SOQL = on text is case-insensitive)
      String soql =
        'SELECT Id, Name, Make__c, Model__c, Model_Year__c, Fuel_Type__c, Vehicle_Class__c, ' +
        'Regulatory_Category__c, Effective_Registration_Country__c ' +
        'FROM Fleet_Asset__c WHERE Is_Active__c = true' +
        (anyMake ? '' : ' AND Make__c IN :makes') +
        ' ORDER BY Name LIMIT 50000';
      assets = Database.queryWithBinds(
        soql,
        new Map<String, Object>{ 'makes' => makes },
        AccessLevel.SYSTEM_MODE
      );
    }

    Map<String, Asset_Alert__c> existingByKey = new Map<String, Asset_Alert__c>();
    Set<Id> touchedAssets = new Set<Id>();
    for (Asset_Alert__c a : [
      SELECT
        Id,
        Fleet_Asset__c,
        External_Notice__c,
        Unique_Key__c,
        Status__c,
        Severity__c,
        Title__c,
        Detail__c,
        Due_Date__c
      FROM Asset_Alert__c
      WHERE External_Notice__c IN :noticeIds
    ]) {
      existingByKey.put(a.Unique_Key__c, a);
    }

    Map<String, Asset_Alert__c> upserts = new Map<String, Asset_Alert__c>();
    Map<Id, Integer> affected = new Map<Id, Integer>();
    Set<String> wantedKeys = new Set<String>();
    Integer openCount = 0;
    for (External_Notice__c n : eligible) {
      Integer count = 0;
      for (Fleet_Asset__c a : assets) {
        if (!matches(n, a)) {
          continue;
        }
        count++;
        String key = key(n.Id, a.Id);
        wantedKeys.add(key);
        Asset_Alert__c w = alertFor(n, a, key);
        Asset_Alert__c existing = existingByKey.get(key);
        if (existing == null || existing.Status__c == 'Resolved') {
          w.Status__c = 'New';
          w.Resolved_On__c = null;
          upserts.put(key, w);
          touchedAssets.add(a.Id);
          openCount++;
        } else {
          if (
            existing.Severity__c != w.Severity__c ||
            existing.Title__c != w.Title__c ||
            existing.Detail__c != w.Detail__c ||
            existing.Due_Date__c != w.Due_Date__c
          ) {
            upserts.put(key, w);
          }
          if (AssetAlertService.OPEN_STATUSES.contains(existing.Status__c)) {
            openCount++;
          }
        }
      }
      affected.put(n.Id, count);
    }

    // anything no longer matching (or on a notice that is not active and reviewed) is resolved
    for (Asset_Alert__c a : existingByKey.values()) {
      if (
        !wantedKeys.contains(a.Unique_Key__c) &&
        AssetAlertService.OPEN_STATUSES.contains(a.Status__c)
      ) {
        upserts.put(
          a.Unique_Key__c,
          new Asset_Alert__c(
            Unique_Key__c = a.Unique_Key__c,
            Status__c = 'Resolved',
            Resolved_On__c = nowTs
          )
        );
        touchedAssets.add(a.Fleet_Asset__c);
      }
    }

    List<External_Notice__c> noticeUpdates = new List<External_Notice__c>();
    for (External_Notice__c n : notices) {
      Integer count = affected.containsKey(n.Id) ? affected.get(n.Id) : 0;
      if (n.Affected_Count__c != count) {
        noticeUpdates.add(
          new External_Notice__c(Id = n.Id, Affected_Count__c = count)
        );
      }
    }

    if (!upserts.isEmpty()) {
      upsert upserts.values() Asset_Alert__c.Fields.Unique_Key__c;
    }
    update noticeUpdates;
    AssetAlertService.recountOpenAlerts(touchedAssets);
    return openCount;
  }

  public static Boolean isEligible(External_Notice__c n) {
    return n.Status__c == 'Active' && n.Reviewed__c == true;
  }

  public static Boolean matches(External_Notice__c n, Fleet_Asset__c a) {
    if (
      !DataHealthService.same(n.Make__c, a.Make__c) ||
      !DataHealthService.same(n.Model__c, a.Model__c) ||
      !DataHealthService.same(n.Fuel_Type__c, a.Fuel_Type__c) ||
      !categoryMatches(n, a)
    ) {
      return false;
    }
    if (
      n.Year_From__c != null &&
      (DataHealthService.modelYear(a) == null ||
      DataHealthService.modelYear(a) < n.Year_From__c)
    ) {
      return false;
    }
    if (
      n.Year_To__c != null &&
      (DataHealthService.modelYear(a) == null ||
      DataHealthService.modelYear(a) > n.Year_To__c)
    ) {
      return false;
    }
    Set<String> countries = jurisdictionCodes(n.Jurisdiction__c);
    String country = registrationCountry(a);
    return countries.isEmpty() ||
      (country != null && countries.contains(country.trim().toUpperCase()));
  }

  public static Boolean categoryMatches(
    External_Notice__c n,
    Fleet_Asset__c a
  ) {
    if (String.isBlank(n.Regulatory_Category__c)) {
      return DataHealthService.same(n.Vehicle_Category__c, a.Vehicle_Class__c);
    }
    String category = populated(a, 'Regulatory_Category__c');
    if (String.isNotBlank(category)) {
      return n.Regulatory_Category__c == category;
    }
    return String.isNotBlank(n.Vehicle_Category__c) &&
      DataHealthService.same(n.Vehicle_Category__c, a.Vehicle_Class__c);
  }

  /**
   * The vehicle's own Registration Country when it is on the record (callers such as the sample seed set it in memory),
   * else the effective one from the formula (its branch country). Reads only fields that were queried or set.
   */
  private static String registrationCountry(Fleet_Asset__c a) {
    String own = populated(a, 'Country__c');
    return String.isNotBlank(own)
      ? own
      : populated(a, 'Effective_Registration_Country__c');
  }

  /** A text field if it was queried or set, with or without the namespace prefix; else null. */
  private static String populated(SObject record, String field) {
    Map<String, Object> f = record.getPopulatedFieldsAsMap();
    Object v = f.containsKey(field)
      ? f.get(field)
      : f.get('fleetforce__' + field);
    return (String) v;
  }

  public static Set<String> jurisdictionCodes(String jurisdiction) {
    Set<String> codes = new Set<String>();
    if (String.isBlank(jurisdiction)) {
      return codes;
    }
    for (String part : jurisdiction.split('[;,\\s]+')) {
      if (String.isNotBlank(part)) {
        codes.add(part.trim().toUpperCase());
      }
    }
    return codes;
  }

  public static String key(Id noticeId, Id assetId) {
    return 'NT:' + noticeId + ':' + assetId;
  }

  private static Asset_Alert__c alertFor(
    External_Notice__c n,
    Fleet_Asset__c a,
    String key
  ) {
    String type = n.Notice_Type__c == 'Recall'
      ? 'Recall'
      : (n.Notice_Type__c == 'Regulation' ? 'Regulation' : 'Other');
    String title = n.Notice_Type__c == 'Recall'
      ? 'Possible recall: ' + (n.Title__c ?? n.Name)
      : (n.Title__c ?? n.Name);
    String detail = n.Notice_Type__c == 'Recall' ? POSSIBLE_MATCH : '';
    if (String.isNotBlank(n.Summary__c)) {
      detail = (detail + ' ' + n.Summary__c).trim();
    }
    return new Asset_Alert__c(
      Fleet_Asset__c = a.Id,
      External_Notice__c = n.Id,
      Unique_Key__c = key,
      Alert_Type__c = type,
      Severity__c = n.Severity__c ?? 'Medium',
      Title__c = title.left(255),
      Detail__c = detail.left(4000),
      Due_Date__c = n.Effective_On__c,
      Is_Sample__c = n.Is_Sample__c
    );
  }
}
