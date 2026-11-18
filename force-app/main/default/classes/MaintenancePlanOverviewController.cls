/**
 * Controller for the maintenancePlanOverview LWC.
 * Supplies hierarchical milestone and task structure, plan-level rollups,
 * connected fleet vehicles, and actions to create items or assign assets.
 */
public with sharing class MaintenancePlanOverviewController {
  public class PlanKPIs {
    @AuraEnabled
    public Integer milestonesCount;
    @AuraEnabled
    public Integer proceduresCount;
    @AuraEnabled
    public Decimal totalEstimatedCost;
    @AuraEnabled
    public Decimal totalEstimatedHours;
    @AuraEnabled
    public Integer assignedAssetsCount;
    @AuraEnabled
    public Integer eligibleAssetsCount;
  }

  public class LineItemDTO {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String itemType;
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
    public Id parentLineItemId;
    @AuraEnabled
    public String parentLineItemName;
    @AuraEnabled
    public List<LineItemDTO> childItems;
    @AuraEnabled
    public Decimal subtotalCost;
    @AuraEnabled
    public Decimal subtotalHours;
    @AuraEnabled
    public Integer childCount;

    public LineItemDTO() {
      this.childItems = new List<LineItemDTO>();
      this.subtotalCost = 0;
      this.subtotalHours = 0;
      this.childCount = 0;
    }
  }

  public class AssignedAssetDTO {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String licensePlate;
    @AuraEnabled
    public String vin;
    @AuraEnabled
    public String bodyType;
    @AuraEnabled
    public String makeModel;
    @AuraEnabled
    public Decimal odometer;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String branchName;
    @AuraEnabled
    public String nextMilestoneName;
    @AuraEnabled
    public Decimal milesRemaining;
    @AuraEnabled
    public String milestoneBadgeClass;
    @AuraEnabled
    public String milestoneStatusLabel;
  }

  public class EligibleAssetDTO {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String licensePlate;
    @AuraEnabled
    public String vin;
    @AuraEnabled
    public String bodyType;
    @AuraEnabled
    public String makeModel;
    @AuraEnabled
    public Decimal odometer;
    @AuraEnabled
    public String branchName;
  }

  public class PlanOverviewPayload {
    @AuraEnabled
    public fleetforce__Maintenance_Plan__c plan;
    @AuraEnabled
    public PlanKPIs kpis;
    @AuraEnabled
    public List<LineItemDTO> milestones;
    @AuraEnabled
    public List<AssignedAssetDTO> assignedAssets;
    @AuraEnabled
    public List<EligibleAssetDTO> eligibleAssets;
  }

  @AuraEnabled(cacheable=true)
  public static PlanOverviewPayload getPlanOverview(Id planId) {
    if (planId == null) {
      throw new AuraHandledException('Maintenance Plan ID is required.');
    }

    PlanOverviewPayload payload = new PlanOverviewPayload();

    fleetforce__Maintenance_Plan__c plan = [
      SELECT
        Id,
        Name,
        fleetforce__Asset_Type__c,
        fleetforce__Frequency_Type__c,
        fleetforce__Interval_Value__c,
        fleetforce__Calendar_Interval_Months__c,
        fleetforce__Is_Recurring__c,
        fleetforce__Warning_Miles__c,
        fleetforce__SOP_Checklist__c,
        fleetforce__Type__c
      FROM fleetforce__Maintenance_Plan__c
      WHERE Id = :planId
      LIMIT 1
    ];
    payload.plan = plan;

    // 1. Fetch Line Items
    List<fleetforce__Maintenance_Plan_Line_Item__c> items = [
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
      WHERE fleetforce__Maintenance_Plan__c = :planId
      ORDER BY
        fleetforce__Sequence__c ASC NULLS LAST,
        fleetforce__Milestone_Mileage__c ASC NULLS LAST,
        CreatedDate ASC
    ];

    Map<Id, LineItemDTO> milestoneMap = new Map<Id, LineItemDTO>();
    List<LineItemDTO> topLevelMilestones = new List<LineItemDTO>();
    List<LineItemDTO> childList = new List<LineItemDTO>();

    Decimal totalPlanCost = 0;
    Decimal totalPlanHours = 0;
    Integer totalProcedures = 0;

    for (fleetforce__Maintenance_Plan_Line_Item__c item : items) {
      LineItemDTO dto = new LineItemDTO();
      dto.id = item.Id;
      dto.name = item.Name;
      dto.itemType = item.fleetforce__Type__c;
      dto.sequence = item.fleetforce__Sequence__c;
      dto.milestoneMileage = item.fleetforce__Milestone_Mileage__c;
      dto.milestoneMonths = item.fleetforce__Milestone_Months__c;
      dto.serviceCategory = item.fleetforce__Service_Category__c;
      dto.componentsServiced = item.fleetforce__Components_Serviced__c;
      dto.estimatedCost = item.fleetforce__Estimated_Cost__c != null
        ? item.fleetforce__Estimated_Cost__c
        : 0;
      dto.estimatedHours = item.fleetforce__Estimated_Hours__c != null
        ? item.fleetforce__Estimated_Hours__c
        : 0;
      dto.sopChecklist = item.fleetforce__SOP_Checklist__c;
      dto.parentLineItemId = item.fleetforce__Parent_Line_Item__c;
      dto.parentLineItemName = item.fleetforce__Parent_Line_Item__r != null
        ? item.fleetforce__Parent_Line_Item__r.Name
        : null;

      if (dto.parentLineItemId == null) {
        dto.subtotalCost = 0;
        dto.subtotalHours = 0;
        milestoneMap.put(dto.id, dto);
        topLevelMilestones.add(dto);
      } else {
        childList.add(dto);
        totalProcedures++;
      }
    }

    // Attach children and rollup costs/hours to parents
    for (LineItemDTO child : childList) {
      if (milestoneMap.containsKey(child.parentLineItemId)) {
        LineItemDTO parent = milestoneMap.get(child.parentLineItemId);
        parent.childItems.add(child);
        parent.childCount++;
        parent.subtotalCost += child.estimatedCost;
        parent.subtotalHours += child.estimatedHours;
      } else {
        topLevelMilestones.add(child);
      }
    }

    for (LineItemDTO m : topLevelMilestones) {
      if (m.childCount == 0) {
        m.subtotalCost = m.estimatedCost;
        m.subtotalHours = m.estimatedHours;
      }
      totalPlanCost += m.subtotalCost;
      totalPlanHours += m.subtotalHours;
    }

    payload.milestones = topLevelMilestones;

    // 2. Fetch Assigned Assets
    List<fleetforce__Fleet_Asset__c> assignedList = [
      SELECT
        Id,
        Name,
        fleetforce__License_Plate__c,
        fleetforce__VIN__c,
        fleetforce__Body_Type__c,
        fleetforce__Make__c,
        fleetforce__Model__c,
        fleetforce__Odometer__c,
        fleetforce__Status__c,
        fleetforce__Branch__r.Name
      FROM fleetforce__Fleet_Asset__c
      WHERE fleetforce__Assigned_Maintenance_Plan__c = :planId
      ORDER BY Name ASC
    ];

    List<AssignedAssetDTO> assignedDTOs = new List<AssignedAssetDTO>();
    for (fleetforce__Fleet_Asset__c a : assignedList) {
      AssignedAssetDTO ad = new AssignedAssetDTO();
      ad.id = a.Id;
      ad.name = a.Name;
      ad.licensePlate = a.fleetforce__License_Plate__c;
      ad.vin = a.fleetforce__VIN__c;
      ad.bodyType = a.fleetforce__Body_Type__c;
      ad.makeModel =
        (a.fleetforce__Make__c != null ? a.fleetforce__Make__c : '') +
        (a.fleetforce__Model__c != null ? ' ' + a.fleetforce__Model__c : '');
      ad.odometer = a.fleetforce__Odometer__c != null
        ? a.fleetforce__Odometer__c
        : 0;
      ad.status = a.fleetforce__Status__c;
      ad.branchName = a.fleetforce__Branch__r != null
        ? a.fleetforce__Branch__r.Name
        : 'Unassigned Branch';

      // Calculate next milestone
      computeAssetNextMilestone(ad, topLevelMilestones);
      assignedDTOs.add(ad);
    }
    payload.assignedAssets = assignedDTOs;

    // 3. Fetch Eligible Unassigned Assets
    String targetType = plan.fleetforce__Asset_Type__c;
    List<fleetforce__Fleet_Asset__c> eligibleList;
    if (String.isNotBlank(targetType) && targetType != 'All') {
      eligibleList = [
        SELECT
          Id,
          Name,
          fleetforce__License_Plate__c,
          fleetforce__VIN__c,
          fleetforce__Body_Type__c,
          fleetforce__Make__c,
          fleetforce__Model__c,
          fleetforce__Odometer__c,
          fleetforce__Branch__r.Name
        FROM fleetforce__Fleet_Asset__c
        WHERE
          fleetforce__Body_Type__c = :targetType
          AND (fleetforce__Assigned_Maintenance_Plan__c = NULL
          OR fleetforce__Assigned_Maintenance_Plan__c != :planId)
        ORDER BY Name ASC
        LIMIT 50
      ];
    } else {
      eligibleList = [
        SELECT
          Id,
          Name,
          fleetforce__License_Plate__c,
          fleetforce__VIN__c,
          fleetforce__Body_Type__c,
          fleetforce__Make__c,
          fleetforce__Model__c,
          fleetforce__Odometer__c,
          fleetforce__Branch__r.Name
        FROM fleetforce__Fleet_Asset__c
        WHERE
          fleetforce__Assigned_Maintenance_Plan__c = NULL
          OR fleetforce__Assigned_Maintenance_Plan__c != :planId
        ORDER BY Name ASC
        LIMIT 50
      ];
    }

    List<EligibleAssetDTO> eligibleDTOs = new List<EligibleAssetDTO>();
    for (fleetforce__Fleet_Asset__c ea : eligibleList) {
      EligibleAssetDTO ed = new EligibleAssetDTO();
      ed.id = ea.Id;
      ed.name = ea.Name;
      ed.licensePlate = ea.fleetforce__License_Plate__c;
      ed.vin = ea.fleetforce__VIN__c;
      ed.bodyType = ea.fleetforce__Body_Type__c;
      ed.makeModel =
        (ea.fleetforce__Make__c != null ? ea.fleetforce__Make__c : '') +
        (ea.fleetforce__Model__c != null ? ' ' + ea.fleetforce__Model__c : '');
      ed.odometer = ea.fleetforce__Odometer__c != null
        ? ea.fleetforce__Odometer__c
        : 0;
      ed.branchName = ea.fleetforce__Branch__r != null
        ? ea.fleetforce__Branch__r.Name
        : 'Unassigned Branch';
      eligibleDTOs.add(ed);
    }
    payload.eligibleAssets = eligibleDTOs;

    // 4. Compute KPIs
    PlanKPIs kpis = new PlanKPIs();
    kpis.milestonesCount = topLevelMilestones.size();
    kpis.proceduresCount = totalProcedures;
    kpis.totalEstimatedCost = totalPlanCost;
    kpis.totalEstimatedHours = totalPlanHours;
    kpis.assignedAssetsCount = assignedDTOs.size();
    kpis.eligibleAssetsCount = eligibleDTOs.size();
    payload.kpis = kpis;

    return payload;
  }

  private static void computeAssetNextMilestone(
    AssignedAssetDTO ad,
    List<LineItemDTO> milestones
  ) {
    if (milestones == null || milestones.isEmpty()) {
      ad.nextMilestoneName = 'No Milestones Defined';
      ad.milestoneStatusLabel = 'N/A';
      ad.milestoneBadgeClass = 'slds-badge slds-badge_lightest';
      return;
    }

    LineItemDTO nextM = null;
    Decimal lowestOdoDiff = null;

    for (LineItemDTO m : milestones) {
      if (m.milestoneMileage != null) {
        if (m.milestoneMileage >= (ad.odometer - 1500)) {
          nextM = m;
          break;
        }
      }
    }

    if (nextM != null) {
      ad.nextMilestoneName = nextM.name;
      Decimal diff = nextM.milestoneMileage - ad.odometer;
      ad.milesRemaining = diff;

      if (diff < 0) {
        ad.milestoneStatusLabel =
          'OVERDUE by ' +
          Math.abs(diff.intValue()) +
          ' mi';
        ad.milestoneBadgeClass = 'slds-badge slds-theme_error';
      } else if (diff <= 1500) {
        ad.milestoneStatusLabel = 'Due in ' + diff.intValue() + ' mi';
        ad.milestoneBadgeClass = 'slds-badge slds-theme_warning';
      } else {
        ad.milestoneStatusLabel = 'Due in ' + diff.intValue() + ' mi';
        ad.milestoneBadgeClass = 'slds-badge slds-theme_info';
      }
    } else {
      ad.nextMilestoneName = 'All Milestones Completed';
      ad.milestoneStatusLabel = 'Up to date';
      ad.milestoneBadgeClass = 'slds-badge slds-theme_success';
    }
  }

  @AuraEnabled
  public static Id createMilestone(
    Id planId,
    String name,
    Decimal sequence,
    Decimal milestoneMileage,
    Decimal milestoneMonths,
    String serviceCategory,
    Decimal estimatedCost,
    Decimal estimatedHours,
    String componentsServiced,
    String sopChecklist
  ) {
    if (planId == null || String.isBlank(name)) {
      throw new AuraHandledException(
        'Plan ID and Milestone Name are required.'
      );
    }

    fleetforce__Maintenance_Plan_Line_Item__c m = new fleetforce__Maintenance_Plan_Line_Item__c(
      Name = name,
      fleetforce__Maintenance_Plan__c = planId,
      fleetforce__Type__c = 'Milestone / Service Package',
      fleetforce__Sequence__c = sequence,
      fleetforce__Milestone_Mileage__c = milestoneMileage,
      fleetforce__Milestone_Months__c = milestoneMonths,
      fleetforce__Service_Category__c = serviceCategory,
      fleetforce__Estimated_Cost__c = estimatedCost,
      fleetforce__Estimated_Hours__c = estimatedHours,
      fleetforce__Components_Serviced__c = componentsServiced,
      fleetforce__SOP_Checklist__c = sopChecklist
    );
    insert m;
    return m.Id;
  }

  @AuraEnabled
  public static Id createChildProcedure(
    Id planId,
    Id parentLineItemId,
    String name,
    String itemType,
    Decimal sequence,
    String serviceCategory,
    Decimal estimatedCost,
    Decimal estimatedHours,
    String componentsServiced,
    String sopChecklist
  ) {
    if (planId == null || parentLineItemId == null || String.isBlank(name)) {
      throw new AuraHandledException(
        'Plan ID, Parent Milestone, and Procedure Name are required.'
      );
    }

    fleetforce__Maintenance_Plan_Line_Item__c p = new fleetforce__Maintenance_Plan_Line_Item__c(
      Name = name,
      fleetforce__Maintenance_Plan__c = planId,
      fleetforce__Parent_Line_Item__c = parentLineItemId,
      fleetforce__Type__c = String.isNotBlank(itemType)
        ? itemType
        : 'Component / Part Replacement',
      fleetforce__Sequence__c = sequence,
      fleetforce__Service_Category__c = serviceCategory,
      fleetforce__Estimated_Cost__c = estimatedCost,
      fleetforce__Estimated_Hours__c = estimatedHours,
      fleetforce__Components_Serviced__c = componentsServiced,
      fleetforce__SOP_Checklist__c = sopChecklist
    );
    insert p;
    return p.Id;
  }

  @AuraEnabled
  public static void assignAssets(Id planId, List<Id> assetIds) {
    if (planId == null || assetIds == null || assetIds.isEmpty()) {
      throw new AuraHandledException('Plan ID and Asset IDs are required.');
    }

    List<fleetforce__Fleet_Asset__c> toUpdate = new List<fleetforce__Fleet_Asset__c>();
    for (Id aId : assetIds) {
      toUpdate.add(
        new fleetforce__Fleet_Asset__c(
          Id = aId,
          fleetforce__Assigned_Maintenance_Plan__c = planId
        )
      );
    }
    update toUpdate;
  }

  @AuraEnabled
  public static void unassignAsset(Id assetId) {
    if (assetId == null) {
      throw new AuraHandledException('Asset ID is required.');
    }
    fleetforce__Fleet_Asset__c a = new fleetforce__Fleet_Asset__c(
      Id = assetId,
      fleetforce__Assigned_Maintenance_Plan__c = null
    );
    update a;
  }

  @AuraEnabled
  public static void deleteLineItem(Id lineItemId) {
    if (lineItemId == null) {
      throw new AuraHandledException('Line Item ID is required.');
    }
    delete [
      SELECT Id
      FROM fleetforce__Maintenance_Plan_Line_Item__c
      WHERE Id = :lineItemId
    ];
  }
}
