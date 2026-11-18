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
    @AuraEnabled
    public List<VehicleDocItem> systemLinkedDocuments = new List<VehicleDocItem>();
    @AuraEnabled
    public List<VehicleDocItem> directAssetDocuments = new List<VehicleDocItem>();
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
    @AuraEnabled
    public Id assignedPlanId;
    @AuraEnabled
    public String assignedPlanName;
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
    public Boolean hasHandbook = false;
    @AuraEnabled
    public Boolean hasVideo = false;
    @AuraEnabled
    public Boolean hasEmergencyGuide = false;
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
    public PlanDetail activePlan;
    @AuraEnabled
    public Boolean hasActivePlan = false;
    @AuraEnabled
    public Boolean isOverridden = false;
    @AuraEnabled
    public List<PlanLineItemSummary> lineItems = new List<PlanLineItemSummary>();
    @AuraEnabled
    public PlanLineItemSummary nextMilestone;
    @AuraEnabled
    public Boolean hasNextMilestone = false;
    @AuraEnabled
    public Decimal nextMilestoneDueOdometer;
    @AuraEnabled
    public Decimal nextMilestoneMilesRemaining;
    @AuraEnabled
    public String nextMilestoneStatusBadgeClass;
    @AuraEnabled
    public String nextMilestoneStatusLabel;
    @AuraEnabled
    public TicketSummary scheduledTicket;
    @AuraEnabled
    public Boolean hasScheduledTicket = false;
    @AuraEnabled
    public List<TicketSummary> recentTickets = new List<TicketSummary>();
    @AuraEnabled
    public List<PlanOption> availablePlans = new List<PlanOption>();
  }

  public class PlanDetail {
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

  public class PlanLineItemSummary {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Decimal sequence;
    @AuraEnabled
    public Decimal milestoneMileage;
    @AuraEnabled
    public Decimal milestoneMonths;
    @AuraEnabled
    public String serviceCategory;
    @AuraEnabled
    public String componentsServiced;
    @AuraEnabled
    public Decimal estimatedCost;
    @AuraEnabled
    public Decimal estimatedHours;
    @AuraEnabled
    public String sopChecklist;
    @AuraEnabled
    public String itemType;
    @AuraEnabled
    public Id parentLineItemId;
    @AuraEnabled
    public String parentLineItemName;
    @AuraEnabled
    public List<PlanLineItemSummary> childItems = new List<PlanLineItemSummary>();
    @AuraEnabled
    public Boolean hasChildItems = false;
    @AuraEnabled
    public String milestoneBadgeClass;
    @AuraEnabled
    public String milestoneStatus; // 'Completed', 'Next Due', 'Upcoming'
    @AuraEnabled
    public Boolean isNextDue = false;
    @AuraEnabled
    public Boolean isCompleted = false;
  }

  public class PlanOption {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
    @AuraEnabled
    public String assetType;
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
    @AuraEnabled
    public String lineItemName;
  }

  public class VehicleDocItem {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public Id documentId;
    @AuraEnabled
    public Id fileId;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String fileExtension;
    @AuraEnabled
    public String fileSize;
    @AuraEnabled
    public DateTime createdDate;
    @AuraEnabled
    public String sourceEntityType;
    @AuraEnabled
    public Id sourceRecordId;
    @AuraEnabled
    public String sourceRecordName;
    @AuraEnabled
    public String sourceBadgeClass;
    @AuraEnabled
    public String downloadUrl;
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
        fleetforce__Branch__r.Name,
        fleetforce__Assigned_Maintenance_Plan__c,
        fleetforce__Assigned_Maintenance_Plan__r.Name,
        fleetforce__Assigned_Maintenance_Plan__r.fleetforce__Asset_Type__c,
        fleetforce__Assigned_Maintenance_Plan__r.fleetforce__Frequency_Type__c,
        fleetforce__Assigned_Maintenance_Plan__r.fleetforce__Interval_Value__c,
        fleetforce__Assigned_Maintenance_Plan__r.fleetforce__Calendar_Interval_Months__c,
        fleetforce__Assigned_Maintenance_Plan__r.fleetforce__SOP_Checklist__c
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
    asst.odometer = asset.fleetforce__Odometer__c != null
      ? asset.fleetforce__Odometer__c
      : 0;
    asst.distanceUnit = asset.fleetforce__Effective_Distance_Unit__c;
    asst.country = asset.fleetforce__Operating_Country__c;
    asst.branchName = asset.fleetforce__Branch__r != null
      ? asset.fleetforce__Branch__r.Name
      : null;
    asst.assignedPlanId = asset.fleetforce__Assigned_Maintenance_Plan__c;
    asst.assignedPlanName = asset.fleetforce__Assigned_Maintenance_Plan__r !=
      null
      ? asset.fleetforce__Assigned_Maintenance_Plan__r.Name
      : null;

    if (String.isNotBlank(asset.Name) && asset.Name.contains('·')) {
      asst.licensePlate = asset.Name.substringAfter('·').trim();
    }
    payload.assetInfo = asst;

    // 2. Model Resources Inheritance
    payload.modelResources = resolveModelResources(
      asset.Name,
      asset.fleetforce__Make__c,
      asset.fleetforce__Model__c
    );

    // 3. Compliance Documents
    payload.complianceDocuments = queryComplianceDocuments(asset.Id);

    // 4. Maintenance Summary with Line Items & Milestone Resolution
    payload.maintenanceInfo = resolveMaintenanceSummary(asset);

    // 5. Vehicle Documents (System-Linked & Direct Asset Files)
    resolveVehicleDocuments(asset.Id, payload);

    return payload;
  }

  @AuraEnabled
  public static void assignMaintenancePlan(Id assetId, Id planId) {
    if (assetId == null) {
      throw new AuraHandledException('Asset ID is required.');
    }
    fleetforce__Fleet_Asset__c asset = new fleetforce__Fleet_Asset__c(
      Id = assetId,
      fleetforce__Assigned_Maintenance_Plan__c = planId
    );
    update asset;
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

  private static ModelResources resolveModelResources(
    String assetName,
    String make,
    String model
  ) {
    ModelResources mr = new ModelResources();
    fleetforce__Vehicle_Model__mdt matchedModel = matchVehicleModel(
      assetName,
      make,
      model
    );

    if (matchedModel != null) {
      mr.modelLabel = matchedModel.MasterLabel;
      mr.manufacturerHandbookUrl = matchedModel.fleetforce__Manufacturer_Handbook_URL__c;
      mr.infotainmentVideoUrl = matchedModel.fleetforce__Infotainment_Video_URL__c;
      mr.infotainmentVideoEmbedUrl = toEmbedUrl(
        matchedModel.fleetforce__Infotainment_Video_URL__c
      );
      mr.emergencyGuideUrl = matchedModel.fleetforce__Emergency_Guide_URL__c;
      mr.epaMpgCombined = matchedModel.fleetforce__MPG_Combined__c;
      mr.evRangeMiles = matchedModel.fleetforce__EV_Range_Miles__c;
    } else {
      mr.modelLabel = String.isNotBlank(model)
        ? (make + ' ' + model)
        : 'Standard Fleet Asset';
    }

    mr.hasHandbook = String.isNotBlank(mr.manufacturerHandbookUrl);
    mr.hasVideo = String.isNotBlank(mr.infotainmentVideoEmbedUrl);
    mr.hasEmergencyGuide = String.isNotBlank(mr.emergencyGuideUrl);
    return mr;
  }

  private static List<ComplianceDoc> queryComplianceDocuments(Id assetId) {
    List<ComplianceDoc> docList = new List<ComplianceDoc>();
    List<fleetforce__Asset_Document__c> rawDocs = [
      SELECT
        Id,
        Name,
        fleetforce__Doc_Type__c,
        fleetforce__Doc_Number__c,
        fleetforce__Valid_From__c,
        fleetforce__Valid_Until__c,
        fleetforce__Days_Until_Expiry__c,
        fleetforce__Status__c,
        fleetforce__Compliance_State__c,
        fleetforce__Doc_Link__c,
        fleetforce__Is_Required__c,
        fleetforce__Issuing_Authority__c
      FROM fleetforce__Asset_Document__c
      WHERE fleetforce__Fleet_Asset__c = :assetId
      ORDER BY fleetforce__Valid_Until__c ASC NULLS LAST
    ];

    if (rawDocs.isEmpty()) {
      return docList;
    }

    Set<Id> docIds = new Set<Id>();
    for (fleetforce__Asset_Document__c d : rawDocs) {
      docIds.add(d.Id);
    }

    Map<Id, ContentDocumentLink> cdlMap = new Map<Id, ContentDocumentLink>();
    for (ContentDocumentLink cdl : [
      SELECT
        LinkedEntityId,
        ContentDocumentId,
        ContentDocument.Title,
        ContentDocument.LatestPublishedVersionId
      FROM ContentDocumentLink
      WHERE LinkedEntityId IN :docIds
    ]) {
      cdlMap.put(cdl.LinkedEntityId, cdl);
    }

    for (fleetforce__Asset_Document__c d : rawDocs) {
      ComplianceDoc cd = new ComplianceDoc();
      cd.id = d.Id;
      cd.name = d.Name;
      cd.docType = d.fleetforce__Doc_Type__c;
      cd.docNumber = d.fleetforce__Doc_Number__c;
      cd.validFrom = d.fleetforce__Valid_From__c;
      cd.validUntil = d.fleetforce__Valid_Until__c;
      cd.status = d.fleetforce__Status__c;
      cd.complianceState = d.fleetforce__Compliance_State__c;
      cd.docLink = d.fleetforce__Doc_Link__c;
      cd.isRequired = d.fleetforce__Is_Required__c;
      cd.issuingAuthority = d.fleetforce__Issuing_Authority__c;

      Integer daysRemaining = null;
      if (d.fleetforce__Valid_Until__c != null) {
        daysRemaining = Date.today().daysBetween(d.fleetforce__Valid_Until__c);
      } else if (d.fleetforce__Days_Until_Expiry__c != null) {
        daysRemaining = d.fleetforce__Days_Until_Expiry__c.intValue();
      }
      cd.daysUntilExpiry = daysRemaining;

      if (daysRemaining != null) {
        if (daysRemaining < 0) {
          cd.expiryStatus = 'expired';
          cd.expiryBadgeClass = 'slds-badge slds-theme_error';
          cd.expiryLabel = 'Expired (' + Math.abs(daysRemaining) + 'd ago)';
        } else if (daysRemaining <= 30) {
          cd.expiryStatus = 'warning';
          cd.expiryBadgeClass = 'slds-badge slds-theme_warning';
          cd.expiryLabel = 'Expiring in ' + daysRemaining + 'd';
        } else {
          cd.expiryStatus = 'good';
          cd.expiryBadgeClass = 'slds-badge slds-theme_success';
          cd.expiryLabel = 'Valid (' + daysRemaining + 'd)';
        }
      } else {
        cd.expiryStatus = 'none';
        cd.expiryBadgeClass = 'slds-badge slds-badge_lightest';
        cd.expiryLabel = 'No Expiration Date';
      }

      if (cdlMap.containsKey(d.Id)) {
        ContentDocumentLink matchLink = cdlMap.get(d.Id);
        cd.hasFiles = true;
        cd.fileId = matchLink.ContentDocument.LatestPublishedVersionId;
        cd.fileName = matchLink.ContentDocument.Title;
        cd.fileDownloadUrl =
          '/sfc/servlet.shepherd/version/download/' + cd.fileId;
      } else {
        cd.hasFiles = false;
      }

      docList.add(cd);
    }
    return docList;
  }

  private static MaintenanceSummary resolveMaintenanceSummary(
    fleetforce__Fleet_Asset__c asset
  ) {
    MaintenanceSummary ms = new MaintenanceSummary();

    // 1. Determine Active Plan
    fleetforce__Maintenance_Plan__c activePlanRecord = null;
    Boolean isOverride = false;

    if (asset.fleetforce__Assigned_Maintenance_Plan__c != null) {
      activePlanRecord = [
        SELECT
          Id,
          Name,
          fleetforce__Asset_Type__c,
          fleetforce__Frequency_Type__c,
          fleetforce__Interval_Value__c,
          fleetforce__Calendar_Interval_Months__c,
          fleetforce__SOP_Checklist__c
        FROM fleetforce__Maintenance_Plan__c
        WHERE Id = :asset.fleetforce__Assigned_Maintenance_Plan__c
        LIMIT 1
      ];
      isOverride = true;
    } else {
      String assetType = asset.fleetforce__Body_Type__c;
      List<fleetforce__Maintenance_Plan__c> defaults = [
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
          fleetforce__Asset_Type__c = :assetType
          OR fleetforce__Asset_Type__c = 'All'
        ORDER BY CreatedDate DESC
        LIMIT 1
      ];
      if (!defaults.isEmpty()) {
        activePlanRecord = defaults[0];
      }
    }

    ms.isOverridden = isOverride;

    if (activePlanRecord != null) {
      ms.hasActivePlan = true;
      PlanDetail pd = new PlanDetail();
      pd.id = activePlanRecord.Id;
      pd.name = activePlanRecord.Name;
      pd.assetType = activePlanRecord.fleetforce__Asset_Type__c;
      pd.frequencyType = activePlanRecord.fleetforce__Frequency_Type__c;
      pd.intervalValue = activePlanRecord.fleetforce__Interval_Value__c;
      pd.intervalMonths = activePlanRecord.fleetforce__Calendar_Interval_Months__c;
      pd.sopChecklist = activePlanRecord.fleetforce__SOP_Checklist__c;
      ms.activePlan = pd;

      // Query Line Items for Active Plan
      Decimal currentOdo = asset.fleetforce__Odometer__c != null
        ? asset.fleetforce__Odometer__c
        : 0;
      Boolean foundNext = false;

      List<fleetforce__Maintenance_Plan_Line_Item__c> allItems = [
        SELECT
          Id,
          Name,
          fleetforce__Sequence__c,
          fleetforce__Milestone_Mileage__c,
          fleetforce__Milestone_Months__c,
          fleetforce__Service_Category__c,
          fleetforce__Components_Serviced__c,
          fleetforce__Estimated_Cost__c,
          fleetforce__Estimated_Hours__c,
          fleetforce__SOP_Checklist__c,
          fleetforce__Type__c,
          fleetforce__Parent_Line_Item__c,
          fleetforce__Parent_Line_Item__r.Name
        FROM fleetforce__Maintenance_Plan_Line_Item__c
        WHERE fleetforce__Maintenance_Plan__c = :activePlanRecord.Id
        ORDER BY
          fleetforce__Sequence__c ASC NULLS LAST,
          fleetforce__Milestone_Mileage__c ASC NULLS LAST,
          CreatedDate ASC
      ];

      Map<Id, PlanLineItemSummary> itemSummaryMap = new Map<Id, PlanLineItemSummary>();
      List<PlanLineItemSummary> topLevelItems = new List<PlanLineItemSummary>();
      List<PlanLineItemSummary> childItemsList = new List<PlanLineItemSummary>();

      for (fleetforce__Maintenance_Plan_Line_Item__c item : allItems) {
        PlanLineItemSummary lis = new PlanLineItemSummary();
        lis.id = item.Id;
        lis.name = item.Name;
        lis.sequence = item.fleetforce__Sequence__c;
        lis.milestoneMileage = item.fleetforce__Milestone_Mileage__c;
        lis.milestoneMonths = item.fleetforce__Milestone_Months__c;
        lis.serviceCategory = item.fleetforce__Service_Category__c;
        lis.componentsServiced = item.fleetforce__Components_Serviced__c;
        lis.estimatedCost = item.fleetforce__Estimated_Cost__c;
        lis.estimatedHours = item.fleetforce__Estimated_Hours__c;
        lis.sopChecklist = item.fleetforce__SOP_Checklist__c;
        lis.itemType = item.fleetforce__Type__c;
        lis.parentLineItemId = item.fleetforce__Parent_Line_Item__c;
        lis.parentLineItemName = item.fleetforce__Parent_Line_Item__r != null
          ? item.fleetforce__Parent_Line_Item__r.Name
          : null;

        itemSummaryMap.put(item.Id, lis);

        if (item.fleetforce__Parent_Line_Item__c == null) {
          topLevelItems.add(lis);

          if (
            item.fleetforce__Milestone_Mileage__c != null &&
            currentOdo >= item.fleetforce__Milestone_Mileage__c + 1500
          ) {
            lis.milestoneStatus = 'Completed';
            lis.isCompleted = true;
            lis.milestoneBadgeClass = 'slds-badge slds-theme_success';
          } else if (
            !foundNext &&
            item.fleetforce__Milestone_Mileage__c != null &&
            item.fleetforce__Milestone_Mileage__c >= (currentOdo - 1500)
          ) {
            lis.milestoneStatus = 'Next Due';
            lis.isNextDue = true;
            lis.milestoneBadgeClass = 'slds-badge slds-theme_warning';
            foundNext = true;
            ms.nextMilestone = lis;
            ms.hasNextMilestone = true;
            ms.nextMilestoneDueOdometer = item.fleetforce__Milestone_Mileage__c;
            Decimal diff = item.fleetforce__Milestone_Mileage__c - currentOdo;
            ms.nextMilestoneMilesRemaining = diff;

            if (diff < 0) {
              ms.nextMilestoneStatusBadgeClass = 'slds-badge slds-theme_error';
              ms.nextMilestoneStatusLabel =
                'OVERDUE by ' +
                Math.abs(diff.intValue()) +
                ' mi';
            } else if (diff <= 1500) {
              ms.nextMilestoneStatusBadgeClass = 'slds-badge slds-theme_warning';
              ms.nextMilestoneStatusLabel = 'Due in ' + diff.intValue() + ' mi';
            } else {
              ms.nextMilestoneStatusBadgeClass = 'slds-badge slds-theme_info';
              ms.nextMilestoneStatusLabel = 'Due in ' + diff.intValue() + ' mi';
            }
          } else {
            lis.milestoneStatus = 'Upcoming';
            lis.milestoneBadgeClass = 'slds-badge slds-badge_lightest';
          }
        } else {
          childItemsList.add(lis);
        }
      }

      // Attach child items to their parent milestone
      for (PlanLineItemSummary child : childItemsList) {
        if (itemSummaryMap.containsKey(child.parentLineItemId)) {
          PlanLineItemSummary parent = itemSummaryMap.get(
            child.parentLineItemId
          );
          parent.childItems.add(child);
          parent.hasChildItems = true;
        } else {
          topLevelItems.add(child);
        }
      }

      ms.lineItems = topLevelItems;
    } else {
      ms.hasActivePlan = false;
    }

    // 2. Query Recent and Scheduled Service Tickets
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
        fleetforce__Maintenance_Plan__r.Name,
        fleetforce__Maintenance_Plan_Line_Item__r.Name
      FROM fleetforce__Service_Ticket__c
      WHERE fleetforce__Fleet_Asset__c = :asset.Id
      ORDER BY CreatedDate DESC
      LIMIT 10
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
      ts.lineItemName = t.fleetforce__Maintenance_Plan_Line_Item__r != null
        ? t.fleetforce__Maintenance_Plan_Line_Item__r.Name
        : null;

      Decimal cost = 0;
      if (t.fleetforce__Fixed_Cost__c != null)
        cost += t.fleetforce__Fixed_Cost__c;
      if (t.fleetforce__Total_Parts_Cost__c != null)
        cost += t.fleetforce__Total_Parts_Cost__c;
      if (t.fleetforce__Total_Labor_Cost__c != null)
        cost += t.fleetforce__Total_Labor_Cost__c;
      ts.totalCost = cost;

      if (
        !ms.hasScheduledTicket &&
        (t.fleetforce__Status__c == 'Draft' ||
        t.fleetforce__Status__c == 'In-Shop')
      ) {
        ms.scheduledTicket = ts;
        ms.hasScheduledTicket = true;
      }

      ms.recentTickets.add(ts);
    }

    // 3. Query All Available Master Plans for Dropdown
    for (fleetforce__Maintenance_Plan__c p : [
      SELECT Id, Name, fleetforce__Asset_Type__c
      FROM fleetforce__Maintenance_Plan__c
      ORDER BY Name ASC
    ]) {
      PlanOption opt = new PlanOption();
      opt.label =
        p.Name +
        (String.isNotBlank(p.fleetforce__Asset_Type__c)
          ? ' (' + p.fleetforce__Asset_Type__c + ')'
          : '');
      opt.value = p.Id;
      opt.assetType = p.fleetforce__Asset_Type__c;
      ms.availablePlans.add(opt);
    }

    return ms;
  }

  private static void resolveVehicleDocuments(
    Id assetId,
    GloveboxPayload payload
  ) {
    Map<Id, String> entityTypeMap = new Map<Id, String>();
    Map<Id, String> entityNameMap = new Map<Id, String>();
    Map<Id, String> entityBadgeMap = new Map<Id, String>();

    for (fleetforce__Citation__c c : [
      SELECT Id, Name, fleetforce__Ticket_Number__c
      FROM fleetforce__Citation__c
      WHERE fleetforce__Fleet_Asset__c = :assetId
      LIMIT 25
    ]) {
      entityTypeMap.put(c.Id, 'Traffic Citation');
      entityNameMap.put(
        c.Id,
        String.isNotBlank(c.fleetforce__Ticket_Number__c)
          ? c.fleetforce__Ticket_Number__c
          : c.Name
      );
      entityBadgeMap.put(c.Id, 'slds-badge slds-theme_error');
    }

    for (fleetforce__Asset_Insurance_Link__c i : [
      SELECT
        Id,
        Name,
        fleetforce__Cert_Number__c,
        fleetforce__Insurance_Policy__r.Name
      FROM fleetforce__Asset_Insurance_Link__c
      WHERE fleetforce__Fleet_Asset__c = :assetId
      LIMIT 25
    ]) {
      entityTypeMap.put(i.Id, 'Insurance Policy');
      String label = i.fleetforce__Insurance_Policy__r != null
        ? i.fleetforce__Insurance_Policy__r.Name
        : (String.isNotBlank(i.fleetforce__Cert_Number__c)
            ? i.fleetforce__Cert_Number__c
            : i.Name);
      entityNameMap.put(i.Id, label);
      entityBadgeMap.put(i.Id, 'slds-badge slds-theme_success');
    }

    for (fleetforce__Service_Ticket__c t : [
      SELECT Id, Name, fleetforce__Summary__c
      FROM fleetforce__Service_Ticket__c
      WHERE fleetforce__Fleet_Asset__c = :assetId
      LIMIT 25
    ]) {
      entityTypeMap.put(t.Id, 'Service Invoice');
      entityNameMap.put(
        t.Id,
        t.Name +
        (String.isNotBlank(t.fleetforce__Summary__c)
          ? ' · ' + t.fleetforce__Summary__c
          : '')
      );
      entityBadgeMap.put(t.Id, 'slds-badge slds-theme_info');
    }

    Set<Id> allLinkedIds = new Set<Id>(entityTypeMap.keySet());
    allLinkedIds.add(assetId);

    for (ContentDocumentLink cdl : [
      SELECT
        Id,
        LinkedEntityId,
        ContentDocumentId,
        ContentDocument.Title,
        ContentDocument.FileExtension,
        ContentDocument.ContentSize,
        ContentDocument.CreatedDate,
        ContentDocument.LatestPublishedVersionId
      FROM ContentDocumentLink
      WHERE LinkedEntityId IN :allLinkedIds
      ORDER BY ContentDocument.CreatedDate DESC
      LIMIT 50
    ]) {
      VehicleDocItem vdoc = new VehicleDocItem();
      vdoc.id = cdl.Id;
      vdoc.documentId = cdl.ContentDocumentId;
      vdoc.fileId = cdl.ContentDocument.LatestPublishedVersionId;
      vdoc.title = cdl.ContentDocument.Title;
      vdoc.fileExtension = String.isNotBlank(cdl.ContentDocument.FileExtension)
        ? cdl.ContentDocument.FileExtension.toUpperCase()
        : 'FILE';
      vdoc.fileSize = formatFileSize(cdl.ContentDocument.ContentSize);
      vdoc.createdDate = cdl.ContentDocument.CreatedDate;
      vdoc.downloadUrl =
        '/sfc/servlet.shepherd/version/download/' + vdoc.fileId;

      if (cdl.LinkedEntityId == assetId) {
        vdoc.sourceEntityType = 'Vehicle Asset Direct';
        vdoc.sourceRecordId = assetId;
        vdoc.sourceRecordName = 'Primary Asset Record';
        vdoc.sourceBadgeClass = 'slds-badge slds-badge_lightest';
        payload.directAssetDocuments.add(vdoc);
      } else {
        vdoc.sourceEntityType = entityTypeMap.get(cdl.LinkedEntityId);
        vdoc.sourceRecordId = cdl.LinkedEntityId;
        vdoc.sourceRecordName = entityNameMap.get(cdl.LinkedEntityId);
        vdoc.sourceBadgeClass = entityBadgeMap.get(cdl.LinkedEntityId);
        payload.systemLinkedDocuments.add(vdoc);
      }
    }
  }

  private static String formatFileSize(Integer bytes) {
    if (bytes == null || bytes <= 0)
      return '0 KB';
    if (bytes < 1024)
      return bytes + ' B';
    if (bytes < 1048576)
      return (bytes / 1024) + ' KB';
    Decimal mb = Decimal.valueOf(bytes) / 1048576;
    return mb.setScale(1) + ' MB';
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

    String searchName = assetName.toLowerCase();
    List<fleetforce__Vehicle_Model__mdt> allModels = [
      SELECT
        Id,
        DeveloperName,
        MasterLabel,
        fleetforce__Model_Key__c,
        fleetforce__MPG_Combined__c,
        fleetforce__EV_Range_Miles__c,
        fleetforce__Manufacturer_Handbook_URL__c,
        fleetforce__Infotainment_Video_URL__c,
        fleetforce__Emergency_Guide_URL__c
      FROM fleetforce__Vehicle_Model__mdt
      LIMIT 100
    ];

    if (String.isNotBlank(make) && String.isNotBlank(model)) {
      String fullModel = (make + ' ' + model).toLowerCase();
      for (fleetforce__Vehicle_Model__mdt vm : allModels) {
        if (
          vm.MasterLabel != null &&
          vm.MasterLabel.toLowerCase().contains(fullModel)
        ) {
          return vm;
        }
      }
    }

    for (fleetforce__Vehicle_Model__mdt vm : allModels) {
      if (
        vm.MasterLabel != null &&
        searchName.contains(vm.MasterLabel.toLowerCase())
      ) {
        return vm;
      }
      if (
        vm.fleetforce__Model_Key__c != null &&
        searchName.contains(vm.fleetforce__Model_Key__c.toLowerCase())
      ) {
        return vm;
      }
    }

    return null;
  }

  @TestVisible
  private static String toEmbedUrl(String rawUrl) {
    if (String.isBlank(rawUrl)) {
      return null;
    }
    if (rawUrl.contains('youtube.com/embed/')) {
      return rawUrl;
    }
    if (rawUrl.contains('watch?v=')) {
      String videoId = rawUrl.substringAfter('watch?v=');
      if (videoId.contains('&')) {
        videoId = videoId.substringBefore('&');
      }
      return 'https://www.youtube-nocookie.com/embed/' + videoId;
    }
    if (rawUrl.contains('youtu.be/')) {
      String videoId = rawUrl.substringAfter('youtu.be/');
      if (videoId.contains('?')) {
        videoId = videoId.substringBefore('?');
      }
      return 'https://www.youtube-nocookie.com/embed/' + videoId;
    }
    return rawUrl;
  }
}
