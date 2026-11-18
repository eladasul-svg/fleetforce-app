import { LightningElement, api, wire, track } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";
import getPlanOverview from "@salesforce/apex/MaintenancePlanOverviewController.getPlanOverview";
import createMilestone from "@salesforce/apex/MaintenancePlanOverviewController.createMilestone";
import createChildProcedure from "@salesforce/apex/MaintenancePlanOverviewController.createChildProcedure";
import assignAssets from "@salesforce/apex/MaintenancePlanOverviewController.assignAssets";
import unassignAsset from "@salesforce/apex/MaintenancePlanOverviewController.unassignAsset";
import deleteLineItem from "@salesforce/apex/MaintenancePlanOverviewController.deleteLineItem";

export default class MaintenancePlanOverview extends NavigationMixin(
  LightningElement
) {
  @api recordId;

  @track payload = null;
  @track isLoading = true;

  // Modal states
  @track showAddMilestoneModal = false;
  @track showAddProcedureModal = false;
  @track showAssignVehiclesModal = false;

  // Milestone Form fields
  @track milestoneForm = {
    name: "",
    sequence: 1,
    milestoneMileage: null,
    milestoneMonths: null,
    serviceCategory: "Comprehensive Service",
    estimatedCost: 0,
    estimatedHours: 0,
    componentsServiced: "",
    sopChecklist: ""
  };

  // Procedure Form fields
  @track procedureForm = {
    parentLineItemId: "",
    name: "",
    itemType: "Component / Part Replacement",
    sequence: 1,
    serviceCategory: "Oil & Fluids",
    estimatedCost: 0,
    estimatedHours: 0,
    componentsServiced: "",
    sopChecklist: ""
  };

  // Vehicle selection state
  @track selectedAssetIds = new Set();
  @track isSelectAll = false;

  wiredOverviewResult;

  @wire(getPlanOverview, { planId: "$recordId" })
  wiredOverview(result) {
    this.wiredOverviewResult = result;
    const { data, error } = result;
    this.isLoading = false;
    if (data) {
      this.payload = JSON.parse(JSON.stringify(data));
      // Tag milestones with badge CSS classes for UI
      if (this.payload.milestones) {
        this.payload.milestones.forEach((m) => {
          if (m.childItems) {
            m.childItems.forEach((c) => {
              c.typeBadgeClass = this.getTypeBadgeClass(c.itemType);
            });
          }
        });
      }
    } else if (error) {
      this.showToast(
        "Error loading plan overview",
        error?.body?.message || "Unknown error",
        "error"
      );
    }
  }

  getTypeBadgeClass(type) {
    if (!type) return "slds-badge slds-badge_lightest";
    if (type.includes("Fluid")) return "type-badge-fluid";
    if (type.includes("Part")) return "type-badge-part";
    if (type.includes("Inspection")) return "type-badge-inspection";
    if (type.includes("Tire") || type.includes("Brake"))
      return "type-badge-tire";
    return "slds-badge slds-badge_lightest";
  }

  // Getters
  get hasPayload() {
    return this.payload != null && this.payload.plan != null;
  }

  get plan() {
    return this.payload?.plan || {};
  }

  get kpis() {
    return this.payload?.kpis || {};
  }

  get milestones() {
    return this.payload?.milestones || [];
  }

  get hasMilestones() {
    return this.milestones.length > 0;
  }

  get milestonesTabLabel() {
    return `Milestones & Tasks (${this.milestones.length})`;
  }

  get vehiclesTabLabel() {
    return `Connected Fleet (${this.assignedAssets.length})`;
  }

  get assignedAssets() {
    return this.payload?.assignedAssets || [];
  }

  get hasAssignedAssets() {
    return this.assignedAssets.length > 0;
  }

  get eligibleAssets() {
    const list = this.payload?.eligibleAssets || [];
    return list.map((a) => ({
      ...a,
      isChecked: this.selectedAssetIds.has(a.id)
    }));
  }

  get hasEligibleAssets() {
    return (this.payload?.eligibleAssets || []).length > 0;
  }

  get eligibleAssetsCount() {
    return this.payload?.eligibleAssets?.length || 0;
  }

  get selectedAssetsCount() {
    return this.selectedAssetIds.size;
  }

  get isAssignDisabled() {
    return this.selectedAssetIds.size === 0;
  }

  get milestoneOptions() {
    return this.milestones.map((m) => ({
      label: m.name + (m.milestoneMileage ? ` (${m.milestoneMileage} mi)` : ""),
      value: m.id
    }));
  }

  get typeOptions() {
    return [
      {
        label: "Component / Part Replacement",
        value: "Component / Part Replacement"
      },
      { label: "Fluid & Filter Service", value: "Fluid & Filter Service" },
      { label: "Tire & Brake Service", value: "Tire & Brake Service" },
      { label: "Inspection / Diagnostic", value: "Inspection / Diagnostic" }
    ];
  }

  get categoryOptions() {
    return [
      { label: "Oil & Fluids", value: "Oil & Fluids" },
      { label: "Tires & Brakes", value: "Tires & Brakes" },
      { label: "Powertrain", value: "Powertrain" },
      { label: "Electrical & Battery", value: "Electrical & Battery" },
      { label: "Annual Inspection", value: "Annual Inspection" },
      { label: "Comprehensive Service", value: "Comprehensive Service" }
    ];
  }

  // Navigation
  handleNavigateToAsset(event) {
    const assetId = event.currentTarget.dataset.id;
    if (!assetId) return;
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: assetId,
        objectApiName: "fleetforce__Fleet_Asset__c",
        actionName: "view"
      }
    });
  }

  handleNavigateToLineItem(event) {
    const itemId = event.currentTarget.dataset.id;
    if (!itemId) return;
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: itemId,
        objectApiName: "fleetforce__Maintenance_Plan_Line_Item__c",
        actionName: "view"
      }
    });
  }

  // Refresh
  async handleRefresh() {
    this.isLoading = true;
    try {
      await refreshApex(this.wiredOverviewResult);
    } finally {
      this.isLoading = false;
    }
  }

  // Modal Handlers: Add Milestone
  handleOpenAddMilestone() {
    const nextSeq = this.milestones.length + 1;
    this.milestoneForm = {
      name: "",
      sequence: nextSeq,
      milestoneMileage: null,
      milestoneMonths: null,
      serviceCategory: "Comprehensive Service",
      estimatedCost: 0,
      estimatedHours: 0,
      componentsServiced: "",
      sopChecklist: ""
    };
    this.showAddMilestoneModal = true;
  }

  handleCloseAddMilestone() {
    this.showAddMilestoneModal = false;
  }

  handleMilestoneInputChange(event) {
    const field = event.target.dataset.field;
    this.milestoneForm[field] = event.target.value;
  }

  async handleSaveMilestone() {
    if (!this.milestoneForm.name) {
      this.showToast("Validation Error", "Milestone Name is required", "error");
      return;
    }
    this.isLoading = true;
    try {
      await createMilestone({
        planId: this.recordId,
        name: this.milestoneForm.name,
        sequence: this.milestoneForm.sequence,
        milestoneMileage: this.milestoneForm.milestoneMileage,
        milestoneMonths: this.milestoneForm.milestoneMonths,
        serviceCategory: this.milestoneForm.serviceCategory,
        estimatedCost: this.milestoneForm.estimatedCost,
        estimatedHours: this.milestoneForm.estimatedHours,
        componentsServiced: this.milestoneForm.componentsServiced,
        sopChecklist: this.milestoneForm.sopChecklist
      });
      this.showToast("Success", "Milestone created successfully", "success");
      this.showAddMilestoneModal = false;
      await refreshApex(this.wiredOverviewResult);
    } catch (err) {
      this.showToast(
        "Error creating milestone",
        err?.body?.message || "Operation failed",
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  // Modal Handlers: Add Procedure
  handleOpenAddProcedure(event) {
    const parentId = event?.currentTarget?.dataset?.parentid;
    this.procedureForm = {
      parentLineItemId: parentId || (this.milestones[0]?.id ?? ""),
      name: "",
      itemType: "Component / Part Replacement",
      sequence: 1,
      serviceCategory: "Oil & Fluids",
      estimatedCost: 0,
      estimatedHours: 0,
      componentsServiced: "",
      sopChecklist: ""
    };
    this.showAddProcedureModal = true;
  }

  handleCloseAddProcedure() {
    this.showAddProcedureModal = false;
  }

  handleProcedureInputChange(event) {
    const field = event.target.dataset.field;
    this.procedureForm[field] = event.target.value;
  }

  async handleSaveProcedure() {
    if (!this.procedureForm.name || !this.procedureForm.parentLineItemId) {
      this.showToast(
        "Validation Error",
        "Target Milestone and Procedure Name are required",
        "error"
      );
      return;
    }
    this.isLoading = true;
    try {
      await createChildProcedure({
        planId: this.recordId,
        parentLineItemId: this.procedureForm.parentLineItemId,
        name: this.procedureForm.name,
        itemType: this.procedureForm.itemType,
        sequence: this.procedureForm.sequence,
        serviceCategory: this.procedureForm.serviceCategory,
        estimatedCost: this.procedureForm.estimatedCost,
        estimatedHours: this.procedureForm.estimatedHours,
        componentsServiced: this.procedureForm.componentsServiced,
        sopChecklist: this.procedureForm.sopChecklist
      });
      this.showToast("Success", "Procedure created successfully", "success");
      this.showAddProcedureModal = false;
      await refreshApex(this.wiredOverviewResult);
    } catch (err) {
      this.showToast(
        "Error creating procedure",
        err?.body?.message || "Operation failed",
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  // Delete Line Item
  async handleDeleteItem(event) {
    const itemId = event.currentTarget.dataset.id;
    if (!itemId) return;
    this.isLoading = true;
    try {
      await deleteLineItem({ lineItemId: itemId });
      this.showToast("Success", "Line item deleted", "success");
      await refreshApex(this.wiredOverviewResult);
    } catch (err) {
      this.showToast(
        "Error deleting item",
        err?.body?.message || "Operation failed",
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  // Assign Vehicles Modal
  handleOpenAssignVehicles() {
    this.selectedAssetIds = new Set();
    this.isSelectAll = false;
    this.showAssignVehiclesModal = true;
  }

  handleCloseAssignVehicles() {
    this.showAssignVehiclesModal = false;
  }

  handleToggleAssetSelect(event) {
    const assetId = event.target.dataset.id;
    if (event.target.checked) {
      this.selectedAssetIds.add(assetId);
    } else {
      this.selectedAssetIds.delete(assetId);
    }
    this.selectedAssetIds = new Set(this.selectedAssetIds);
  }

  handleToggleSelectAll(event) {
    const isChecked = event.target.checked;
    this.isSelectAll = isChecked;
    if (isChecked) {
      const allIds = (this.payload?.eligibleAssets || []).map((a) => a.id);
      this.selectedAssetIds = new Set(allIds);
    } else {
      this.selectedAssetIds = new Set();
    }
  }

  async handleSaveVehicleAssignments() {
    if (this.selectedAssetIds.size === 0) return;
    this.isLoading = true;
    try {
      await assignAssets({
        planId: this.recordId,
        assetIds: Array.from(this.selectedAssetIds)
      });
      this.showToast(
        "Success",
        `${this.selectedAssetIds.size} vehicle(s) assigned to this plan`,
        "success"
      );
      this.showAssignVehiclesModal = false;
      await refreshApex(this.wiredOverviewResult);
    } catch (err) {
      this.showToast(
        "Error assigning vehicles",
        err?.body?.message || "Operation failed",
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  // Unassign Vehicle
  async handleUnassignAsset(event) {
    const assetId = event.currentTarget.dataset.id;
    if (!assetId) return;
    this.isLoading = true;
    try {
      await unassignAsset({ assetId });
      this.showToast("Success", "Vehicle unassigned from this plan", "success");
      await refreshApex(this.wiredOverviewResult);
    } catch (err) {
      this.showToast(
        "Error unassigning vehicle",
        err?.body?.message || "Operation failed",
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(
      new ShowToastEvent({
        title,
        message,
        variant
      })
    );
  }
}
