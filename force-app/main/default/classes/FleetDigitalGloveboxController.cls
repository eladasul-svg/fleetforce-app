public with sharing class FleetDigitalGloveboxController {
  public class GloveboxPayload {
    @AuraEnabled
    public AssetSummary assetInfo;
    @AuraEnabled
    public ModelResources modelResources;
    @AuraEnabled
    public List<ComplianceDoc> complianceDocuments = new List<ComplianceDoc>();
    @AuraEnabled
    public MaintenanceSummary maintenanceInfo;
  }

  public class AssetSummary {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String vin;
    @AuraEnabled
    public String licensePlate;
    @AuraEnabled
    public String make;
    @AuraEnabled
    public String model;
    @AuraEnabled
    public String modelYear;
    @AuraEnabled
    public String bodyType;
    @AuraEnabled
    public String fuelType;
    @AuraEnabled
    public Decimal odometer;
    @AuraEnabled
    public String distanceUnit;
    @AuraEnabled
    public String branchName;
    @AuraEnabled
    public String country;
  }

  public class ModelResources {
    @AuraEnabled
    public String modelLabel;
    @AuraEnabled
    public String manufacturerHandbookUrl;
    @AuraEnabled
    public String infotainmentVideoUrl;
    @AuraEnabled
    public String infotainmentVideoEmbedUrl;
    @AuraEnabled
    public String emergencyGuideUrl;
    @AuraEnabled
    public Decimal epaMpgCombined;
    @AuraEnabled
    public Decimal evRangeMiles;
    @AuraEnabled
    public Boolean hasHandbook;
    @AuraEnabled
    public Boolean hasVideo;
    @AuraEnabled
    public Boolean hasEmergencyGuide;
  }

  public class ComplianceDoc {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String docType;
    @AuraEnabled
    public String docNumber;
    @AuraEnabled
    public Date validFrom;
    @AuraEnabled
    public Date validUntil;
    @AuraEnabled
    public Integer daysUntilExpiry;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String complianceState;
    @AuraEnabled
    public String expiryStatus; // 'good', 'warning', 'expired', 'none'
    @AuraEnabled
    public String expiryBadgeClass;
    @AuraEnabled
    public String expiryLabel;
    @AuraEnabled
    public String docLink;
    @AuraEnabled
    public Boolean isRequired;
    @AuraEnabled
    public String issuingAuthority;
    @AuraEnabled
    public Boolean hasFiles;
    @AuraEnabled
    public Id fileId;
    @AuraEnabled
    public String fileName;
    @AuraEnabled
    public String fileDownloadUrl;
  }

  public class MaintenanceSummary {
    @AuraEnabled
    public List<TicketSummary> recentTickets = new List<TicketSummary>();
    @AuraEnabled
    public List<PlanSummary> applicablePlans = new List<PlanSummary>();
  }

  public class TicketSummary {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String summary;
    @AuraEnabled
    public String category;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String priority;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Date actualEnd;
    @AuraEnabled
    public Decimal totalCost;
    @AuraEnabled
    public String maintenancePlanName;
  }

  public class PlanSummary {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String assetType;
    @AuraEnabled
    public String frequencyType;
    @AuraEnabled
    public Decimal intervalValue;
    @AuraEnabled
    public Decimal intervalMonths;
    @AuraEnabled
    public String sopChecklist;
  }

  @AuraEnabled(cacheable=true)
  public static GloveboxPayload getGloveboxData(Id assetId) {
    if (assetId == null) {
      throw new AuraHandledException('Asset ID is required.');
    }

    fleetforce__Fleet_Asset__c asset = [
      SELECT
        Id,
        Name,
        fleetforce__VIN__c,
        fleetforce__Make__c,
        fleetforce__Model__c,
        fleetforce__Model_Year__c,
        fleetforce__Body_Type__c,
        fleetforce__Fuel_Type__c,
        fleetforce__Odometer__c,
        fleetforce__Effective_Distance_Unit__c,
        fleetforce__Operating_Country__c,
        fleetforce__Branch__r.Name
      FROM fleetforce__Fleet_Asset__c
      WHERE Id = :assetId
      LIMIT 1
    ];

    GloveboxPayload payload = new GloveboxPayload();

    // 1. Asset Summary
    AssetSummary asst = new AssetSummary();
    asst.id = asset.Id;
    asst.name = asset.Name;
    asst.vin = asset.fleetforce__VIN__c;
    asst.make = asset.fleetforce__Make__c;
    asst.model = asset.fleetforce__Model__c;
    asst.modelYear = asset.fleetforce__Model_Year__c;
    asst.bodyType = asset.fleetforce__Body_Type__c;
    asst.fuelType = asset.fleetforce__Fuel_Type__c;
    asst.odometer = asset.fleetforce__Odometer__c;
    asst.distanceUnit = asset.fleetforce__Effective_Distance_Unit__c;
    asst.country = asset.fleetforce__Operating_Country__c;
    asst.branchName = asset.fleetforce__Branch__r != null
      ? asset.fleetforce__Branch__r.Name
      : null;

    // Extract license plate from Name (e.g. '2025 Ford F-150 · NH73CXK')
    if (String.isNotBlank(asset.Name) && asset.Name.contains('·')) {
      asst.licensePlate = asset.Name.substringAfter('·').trim();
    }
    payload.assetInfo = asst;

    // 2. Model Resources (from Vehicle_Model__mdt)
    fleetforce__Vehicle_Model__mdt model = matchVehicleModel(
      asset.Name,
      asset.fleetforce__Make__c,
      asset.fleetforce__Model__c
    );
    ModelResources mr = new ModelResources();
    if (model != null) {
      mr.modelLabel = model.MasterLabel;
      mr.manufacturerHandbookUrl = model.fleetforce__Manufacturer_Handbook_URL__c;
      mr.infotainmentVideoUrl = model.fleetforce__Infotainment_Video_URL__c;
      mr.infotainmentVideoEmbedUrl = toEmbedUrl(
        model.fleetforce__Infotainment_Video_URL__c
      );
      mr.emergencyGuideUrl = model.fleetforce__Emergency_Guide_URL__c;
      mr.epaMpgCombined = model.fleetforce__MPG_Combined__c;
      mr.evRangeMiles = model.fleetforce__EV_Range_Miles__c;
      mr.hasHandbook = String.isNotBlank(
        model.fleetforce__Manufacturer_Handbook_URL__c
      );
      mr.hasVideo = String.isNotBlank(
        model.fleetforce__Infotainment_Video_URL__c
      );
      mr.hasEmergencyGuide = String.isNotBlank(
        model.fleetforce__Emergency_Guide_URL__c
      );
    } else {
      mr.modelLabel =
        (asst.make != null ? asst.make : '') +
        ' ' +
        (asst.model != null ? asst.model : '');
      mr.hasHandbook = false;
      mr.hasVideo = false;
      mr.hasEmergencyGuide = false;
    }
    payload.modelResources = mr;

    // 3. Compliance Documents (Asset_Document__c)
    List<fleetforce__Asset_Document__c> docs = [
      SELECT
        Id,
        Name,
        fleetforce__Doc_Type__c,
        fleetforce__Doc_Number__c,
        fleetforce__Doc_Link__c,
        fleetforce__Valid_From__c,
        fleetforce__Valid_Until__c,
        fleetforce__Status__c,
        fleetforce__Compliance_State__c,
        fleetforce__Is_Required__c,
        fleetforce__Issuing_Authority__c
      FROM fleetforce__Asset_Document__c
      WHERE fleetforce__Fleet_Asset__c = :asset.Id
      ORDER BY fleetforce__Valid_Until__c ASC NULLS LAST
    ];

    Date today = Date.today();
    Map<Id, ContentVersion> docFiles = queryAttachedFiles(docs);

    for (fleetforce__Asset_Document__c doc : docs) {
      ComplianceDoc cd = new ComplianceDoc();
      cd.id = doc.Id;
      cd.name = doc.Name;
      cd.docType = doc.fleetforce__Doc_Type__c;
      cd.docNumber = doc.fleetforce__Doc_Number__c;
      cd.validFrom = doc.fleetforce__Valid_From__c;
      cd.validUntil = doc.fleetforce__Valid_Until__c;
      cd.status = doc.fleetforce__Status__c;
      cd.complianceState = doc.fleetforce__Compliance_State__c;
      cd.docLink = doc.fleetforce__Doc_Link__c;
      cd.isRequired = doc.fleetforce__Is_Required__c;
      cd.issuingAuthority = doc.fleetforce__Issuing_Authority__c;

      if (doc.fleetforce__Valid_Until__c != null) {
        Integer days = today.daysBetween(doc.fleetforce__Valid_Until__c);
        cd.daysUntilExpiry = days;
        if (days < 0) {
          cd.expiryStatus = 'expired';
          cd.expiryBadgeClass = 'slds-badge slds-theme_error';
          cd.expiryLabel = 'Expired ' + Math.abs(days) + 'd ago';
        } else if (days <= 30) {
          cd.expiryStatus = 'warning';
          cd.expiryBadgeClass = 'slds-badge slds-theme_warning';
          cd.expiryLabel = 'Expires in ' + days + 'd';
        } else {
          cd.expiryStatus = 'good';
          cd.expiryBadgeClass = 'slds-badge slds-theme_success';
          cd.expiryLabel = 'Valid (' + days + 'd)';
        }
      } else {
        cd.expiryStatus = 'none';
        cd.expiryBadgeClass = 'slds-badge slds-badge_lightest';
        cd.expiryLabel = 'No Expiration';
      }

      if (docFiles.containsKey(doc.Id)) {
        ContentVersion cv = docFiles.get(doc.Id);
        cd.hasFiles = true;
        cd.fileId = cv.Id;
        cd.fileName = cv.Title + '.' + cv.FileExtension;
        cd.fileDownloadUrl = '/sfc/servlet.shepherd/version/download/' + cv.Id;
      } else {
        cd.hasFiles = false;
      }
      payload.complianceDocuments.add(cd);
    }

    // 4. Maintenance & Plans
    MaintenanceSummary ms = new MaintenanceSummary();

    // Recent Service Tickets
    for (fleetforce__Service_Ticket__c t : [
      SELECT
        Id,
        Name,
        fleetforce__Summary__c,
        fleetforce__Category__c,
        fleetforce__Status__c,
        fleetforce__Priority__c,
        fleetforce__Due_Date__c,
        fleetforce__Actual_End__c,
        fleetforce__Fixed_Cost__c,
        fleetforce__Total_Parts_Cost__c,
        fleetforce__Total_Labor_Cost__c,
        fleetforce__Maintenance_Plan__r.Name
      FROM fleetforce__Service_Ticket__c
      WHERE fleetforce__Fleet_Asset__c = :asset.Id
      ORDER BY fleetforce__Date_Reported__c DESC NULLS LAST
      LIMIT 5
    ]) {
      TicketSummary ts = new TicketSummary();
      ts.id = t.Id;
      ts.name = t.Name;
      ts.summary = t.fleetforce__Summary__c;
      ts.category = t.fleetforce__Category__c;
      ts.status = t.fleetforce__Status__c;
      ts.priority = t.fleetforce__Priority__c;
      ts.dueDate = t.fleetforce__Due_Date__c;
      ts.actualEnd = t.fleetforce__Actual_End__c;
      ts.maintenancePlanName = t.fleetforce__Maintenance_Plan__r != null
        ? t.fleetforce__Maintenance_Plan__r.Name
        : null;

      Decimal cost = 0;
      if (t.fleetforce__Fixed_Cost__c != null)
        cost += t.fleetforce__Fixed_Cost__c;
      if (t.fleetforce__Total_Parts_Cost__c != null)
        cost += t.fleetforce__Total_Parts_Cost__c;
      if (t.fleetforce__Total_Labor_Cost__c != null)
        cost += t.fleetforce__Total_Labor_Cost__c;
      ts.totalCost = cost;
      ms.recentTickets.add(ts);
    }

    // Applicable Maintenance Plans by Body/Asset Type
    String assetType = asset.fleetforce__Body_Type__c;
    for (fleetforce__Maintenance_Plan__c plan : [
      SELECT
        Id,
        Name,
        fleetforce__Asset_Type__c,
        fleetforce__Frequency_Type__c,
        fleetforce__Interval_Value__c,
        fleetforce__Calendar_Interval_Months__c,
        fleetforce__SOP_Checklist__c
      FROM fleetforce__Maintenance_Plan__c
      WHERE
        fleetforce__Asset_Type__c = 'All'
        OR fleetforce__Asset_Type__c = :assetType
      ORDER BY fleetforce__Interval_Value__c ASC NULLS LAST
      LIMIT 5
    ]) {
      PlanSummary ps = new PlanSummary();
      ps.id = plan.Id;
      ps.name = plan.Name;
      ps.assetType = plan.fleetforce__Asset_Type__c;
      ps.frequencyType = plan.fleetforce__Frequency_Type__c;
      ps.intervalValue = plan.fleetforce__Interval_Value__c;
      ps.intervalMonths = plan.fleetforce__Calendar_Interval_Months__c;
      ps.sopChecklist = plan.fleetforce__SOP_Checklist__c;
      ms.applicablePlans.add(ps);
    }
    payload.maintenanceInfo = ms;

    return payload;
  }

  @AuraEnabled
  public static Id createAssetDocument(
    Id assetId,
    String docType,
    String docNumber,
    Date validFrom,
    Date validUntil,
    String docLink
  ) {
    if (assetId == null) {
      throw new AuraHandledException('Asset ID is required.');
    }
    if (String.isBlank(docType)) {
      throw new AuraHandledException('Document Type is required.');
    }

    fleetforce__Asset_Document__c doc = new fleetforce__Asset_Document__c();
    doc.fleetforce__Fleet_Asset__c = assetId;
    doc.fleetforce__Doc_Type__c = docType;
    doc.fleetforce__Doc_Number__c = docNumber;
    doc.fleetforce__Valid_From__c = validFrom;
    doc.fleetforce__Valid_Until__c = validUntil;
    doc.fleetforce__Doc_Link__c = docLink;
    doc.fleetforce__Status__c = (validUntil != null &&
      validUntil < Date.today())
      ? 'Expired'
      : (validUntil != null &&
          validUntil <= Date.today().addDays(30))
          ? 'Expiring Soon'
          : 'Current';

    insert doc;
    return doc.Id;
  }

  @TestVisible
  private static fleetforce__Vehicle_Model__mdt matchVehicleModel(
    String assetName,
    String make,
    String model
  ) {
    if (String.isBlank(assetName)) {
      return null;
    }
    // Clean asset name: '2025 Ford F-150 · NH73CXK' -> 'ford f-150'
    String clean = assetName.replaceAll('·.*$', '')
      .replaceAll('\\(.*\\)$', '')
      .replaceAll('^\\d{4}\\s+', '')
      .trim()
      .toLowerCase();

    String makeModel = '';
    if (String.isNotBlank(make) && String.isNotBlank(model)) {
      makeModel = (make + ' ' + model).trim().toLowerCase();
    }

    fleetforce__Vehicle_Model__mdt fallback = null;
    for (
      fleetforce__Vehicle_Model__mdt m : fleetforce__Vehicle_Model__mdt.getAll()
        .values()
    ) {
      if (m.fleetforce__Model_Key__c == null) {
        continue;
      }
      String key = m.fleetforce__Model_Key__c.trim().toLowerCase();
      if (key == clean) {
        return m; // Exact match
      }
      if (
        clean.length() > 3 && (key.startsWith(clean) || clean.startsWith(key))
      ) {
        return m; // Prefix match
      }
      if (
        String.isNotBlank(makeModel) &&
        (key == makeModel || key.startsWith(makeModel))
      ) {
        fallback = m; // Make + Model match
      }
    }
    return fallback;
  }

  @TestVisible
  private static String toEmbedUrl(String rawUrl) {
    if (String.isBlank(rawUrl)) {
      return null;
    }
    String u = rawUrl.trim();
    if (u.contains('youtube.com/embed/')) {
      return u;
    }
    if (u.contains('youtube.com/watch?v=')) {
      String videoId = u.substringAfter('watch?v=');
      if (videoId.contains('&')) {
        videoId = videoId.substringBefore('&');
      }
      return 'https://www.youtube-nocookie.com/embed/' + videoId;
    }
    if (u.contains('youtu.be/')) {
      String videoId = u.substringAfter('youtu.be/');
      if (videoId.contains('?')) {
        videoId = videoId.substringBefore('?');
      }
      return 'https://www.youtube-nocookie.com/embed/' + videoId;
    }
    return u;
  }

  private static Map<Id, ContentVersion> queryAttachedFiles(
    List<fleetforce__Asset_Document__c> docs
  ) {
    Map<Id, ContentVersion> docFiles = new Map<Id, ContentVersion>();
    Set<Id> docIds = (new Map<Id, fleetforce__Asset_Document__c>(docs))
      .keySet();
    if (docIds.isEmpty()) {
      return docFiles;
    }

    Map<Id, Id> docToContentDocId = new Map<Id, Id>();
    for (ContentDocumentLink cdl : [
      SELECT LinkedEntityId, ContentDocumentId
      FROM ContentDocumentLink
      WHERE LinkedEntityId IN :docIds
    ]) {
      docToContentDocId.put(cdl.LinkedEntityId, cdl.ContentDocumentId);
    }

    if (!docToContentDocId.isEmpty()) {
      Map<Id, ContentVersion> cdToCv = new Map<Id, ContentVersion>();
      for (ContentVersion cv : [
        SELECT Id, Title, FileExtension, ContentDocumentId
        FROM ContentVersion
        WHERE
          ContentDocumentId IN :docToContentDocId.values()
          AND IsLatest = TRUE
      ]) {
        cdToCv.put(cv.ContentDocumentId, cv);
      }
      for (Id dId : docToContentDocId.keySet()) {
        Id cdId = docToContentDocId.get(dId);
        if (cdToCv.containsKey(cdId)) {
          docFiles.put(dId, cdToCv.get(cdId));
        }
      }
    }
    return docFiles;
  }
}
