/**
 * Data behind the assetDataHealth LWC on the fleet asset record page: the score with its three parts, the
 * vehicle's streams, and its open alerts (read through AssetAlertService.query, the same query as the
 * fleet exposure view).
 */
public with sharing class AssetDataHealthController {
  public class Health {
    @AuraEnabled
    public Id assetId;
    @AuraEnabled
    public Integer score;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Integer freshness;
    @AuraEnabled
    public Integer completeness;
    @AuraEnabled
    public Integer consistency;
    @AuraEnabled
    public Datetime calculatedOn;
    @AuraEnabled
    public String profileName;
    @AuraEnabled
    public Boolean isSample = false;
    @AuraEnabled
    public List<StreamRow> streams = new List<StreamRow>();
    @AuraEnabled
    public List<AlertRow> alerts = new List<AlertRow>();
  }

  public class StreamRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String sourceName;
    @AuraEnabled
    public String sourceType;
    @AuraEnabled
    public String dataType;
    @AuraEnabled
    public Datetime lastUpdate;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Decimal signals;
    @AuraEnabled
    public String referenceUrl;
    @AuraEnabled
    public Id vendorAccountId;
    @AuraEnabled
    public String vendorName;
  }

  public class AlertRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String alertType;
    @AuraEnabled
    public String severity;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String detail;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Datetime resolvedOn;
    @AuraEnabled
    public Boolean isOpen;
  }

  @AuraEnabled
  public static Health getHealth(Id assetId) {
    try {
      return load(assetId);
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /** Re-runs the evaluation for this vehicle now, then returns the fresh result. */
  @AuraEnabled
  public static Health refreshHealth(Id assetId) {
    try {
      DataHealthService.evaluate(new Set<Id>{ assetId });
      return load(assetId);
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled
  public static Health setAlertStatus(Id alertId, String status) {
    try {
      AssetAlertService.setStatus(alertId, status);
      Asset_Alert__c a = [
        SELECT Fleet_Asset__c
        FROM Asset_Alert__c
        WHERE Id = :alertId
        WITH USER_MODE
      ];
      return load(a.Fleet_Asset__c);
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  private static Health load(Id assetId) {
    Health h = new Health();
    h.assetId = assetId;
    List<Fleet_Asset__c> rows = [
      SELECT
        Id,
        Data_Health_Score__c,
        Data_Health_Status__c,
        Freshness_Score__c,
        Completeness_Score__c,
        Consistency_Score__c,
        Data_Health_Calculated__c,
        Resolved_Stream_Profile__r.Name
      FROM Fleet_Asset__c
      WHERE Id = :assetId
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      return h;
    }
    Fleet_Asset__c a = rows[0];
    h.score = toInt(a.Data_Health_Score__c);
    h.status = a.Data_Health_Status__c;
    h.freshness = toInt(a.Freshness_Score__c);
    h.completeness = toInt(a.Completeness_Score__c);
    h.consistency = toInt(a.Consistency_Score__c);
    h.calculatedOn = a.Data_Health_Calculated__c;
    h.profileName = a.Resolved_Stream_Profile__r?.Name;

    for (Data_Stream__c s : [
      SELECT
        Id,
        Data_Type__c,
        Last_Update__c,
        Status__c,
        Signals_Present__c,
        Reference_URL__c,
        Is_Sample__c,
        Data_Source__r.Name,
        Data_Source__r.Source_Type__c,
        Data_Source__r.Reference_URL__c,
        Data_Source__r.Vendor_Account__c,
        Data_Source__r.Vendor_Account__r.Name
      FROM Data_Stream__c
      WHERE Fleet_Asset__c = :assetId
      WITH USER_MODE
      ORDER BY Data_Type__c, Data_Source__r.Name
    ]) {
      StreamRow r = new StreamRow();
      r.id = s.Id;
      r.sourceName = s.Data_Source__r?.Name;
      r.sourceType = s.Data_Source__r?.Source_Type__c;
      r.dataType = s.Data_Type__c;
      r.lastUpdate = s.Last_Update__c;
      r.status = s.Status__c ?? (s.Last_Update__c == null ? 'Missing' : null);
      r.signals = s.Signals_Present__c;
      r.referenceUrl = String.isNotBlank(s.Reference_URL__c)
        ? s.Reference_URL__c
        : s.Data_Source__r?.Reference_URL__c;
      r.vendorAccountId = s.Data_Source__r?.Vendor_Account__c;
      r.vendorName = s.Data_Source__r?.Vendor_Account__r?.Name;
      h.streams.add(r);
      h.isSample = h.isSample || s.Is_Sample__c;
    }

    AssetAlertService.AlertFilter f = new AssetAlertService.AlertFilter();
    f.assetIds = new Set<Id>{ assetId };
    // every status, so the card shows what was acknowledged, resolved or dismissed: open alerts first, then closed
    List<Asset_Alert__c> open = new List<Asset_Alert__c>();
    List<Asset_Alert__c> closed = new List<Asset_Alert__c>();
    for (
      Asset_Alert__c al : AssetAlertService.sortBySeverity(
        AssetAlertService.query(f)
      )
    ) {
      (AssetAlertService.OPEN_STATUSES.contains(al.Status__c) ? open : closed)
        .add(al);
    }
    open.addAll(closed);
    for (Asset_Alert__c al : open) {
      AlertRow r = new AlertRow();
      r.id = al.Id;
      r.alertType = al.Alert_Type__c;
      r.severity = al.Severity__c;
      r.status = al.Status__c;
      r.title = al.Title__c;
      r.detail = al.Detail__c;
      r.dueDate = al.Due_Date__c;
      r.resolvedOn = al.Resolved_On__c;
      r.isOpen = AssetAlertService.OPEN_STATUSES.contains(al.Status__c);
      h.alerts.add(r);
      h.isSample = h.isSample || al.Is_Sample__c;
    }
    return h;
  }

  private static Integer toInt(Decimal d) {
    return d == null ? null : d.intValue();
  }
}
