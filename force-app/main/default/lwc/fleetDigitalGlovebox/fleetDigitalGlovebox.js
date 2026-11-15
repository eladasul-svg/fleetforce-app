import { LightningElement, api, wire, track } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";
import getGloveboxData from "@salesforce/apex/FleetDigitalGloveboxController.getGloveboxData";
import createAssetDocument from "@salesforce/apex/FleetDigitalGloveboxController.createAssetDocument";
import assignMaintenancePlan from "@salesforce/apex/FleetDigitalGloveboxController.assignMaintenancePlan";

const DEFAULT_DOC = {
  docType: "Registration",
  docNumber: "",
  validFrom: null,
  validUntil: null,
  docLink: ""
};

export default class FleetDigitalGlovebox extends NavigationMixin(
  LightningElement
) {
  @api recordId;

  @track payload;
  @track loading = true;
  @track error;

  @track showAddModal = false;
  @track savingDoc = false;
  @track newDoc = { ...DEFAULT_DOC };

  @track showChangePlanModal = false;
  @track selectedPlanId;
  @track savingPlan = false;

  wiredGloveboxResult;

  @wire(getGloveboxData, { assetId: "$recordId" })
  wiredGlovebox(result) {
    this.wiredGloveboxResult = result;
    const { data, error } = result;
    if (data) {
      this.payload = data;
      this.error = undefined;
      this.loading = false;
    } else if (error) {
      this.error = error.body
        ? error.body.message
        : error.message || "Error loading glovebox data";
      this.payload = undefined;
      this.loading = false;
    }
  }

  get complianceDocumentsCount() {
    return this.payload?.complianceDocuments?.length || 0;
  }

  get systemLinkedCount() {
    return this.payload?.systemLinkedDocuments?.length || 0;
  }

  get directAssetCount() {
    return this.payload?.directAssetDocuments?.length || 0;
  }

  get hasComplianceDocuments() {
    return (
      this.payload &&
      Array.isArray(this.payload.complianceDocuments) &&
      this.payload.complianceDocuments.length > 0
    );
  }

  get hasSystemLinkedDocuments() {
    return (
      this.payload &&
      Array.isArray(this.payload.systemLinkedDocuments) &&
      this.payload.systemLinkedDocuments.length > 0
    );
  }

  get hasDirectAssetDocuments() {
    return (
      this.payload &&
      Array.isArray(this.payload.directAssetDocuments) &&
      this.payload.directAssetDocuments.length > 0
    );
  }

  get hasLineItems() {
    return (
      this.payload &&
      this.payload.maintenanceInfo &&
      Array.isArray(this.payload.maintenanceInfo.lineItems) &&
      this.payload.maintenanceInfo.lineItems.length > 0
    );
  }

  get hasRecentTickets() {
    return (
      this.payload &&
      this.payload.maintenanceInfo &&
      Array.isArray(this.payload.maintenanceInfo.recentTickets) &&
      this.payload.maintenanceInfo.recentTickets.length > 0
    );
  }

  get planOptions() {
    if (!this.payload?.maintenanceInfo?.availablePlans) {
      return [];
    }
    return this.payload.maintenanceInfo.availablePlans.map((p) => ({
      label: p.label,
      value: p.value
    }));
  }

  get docTypeOptions() {
    return [
      { label: "Registration", value: "Registration" },
      { label: "Insurance Card", value: "Insurance Card" },
      { label: "DOT Inspection Report", value: "DOT Inspection Report" },
      { label: "Emissions Certificate", value: "Emissions Certificate" },
      { label: "Permit", value: "Permit" },
      { label: "Lease Agreement", value: "Lease Agreement" },
      { label: "Warranty Document", value: "Warranty Document" }
    ];
  }

  handleViewAssetDocument(event) {
    const docId = event.currentTarget.dataset.id;
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: docId,
        actionName: "view"
      }
    });
  }

  handleViewRecord(event) {
    const recId = event.currentTarget.dataset.id;
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: recId,
        actionName: "view"
      }
    });
  }

  handleViewActivePlanRecord() {
    const planId = this.payload?.maintenanceInfo?.activePlan?.id;
    if (!planId) return;
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: planId,
        actionName: "view"
      }
    });
  }

  handleOpenChangePlanModal() {
    this.selectedPlanId = this.payload?.maintenanceInfo?.activePlan?.id;
    this.showChangePlanModal = true;
  }

  handleCloseChangePlanModal() {
    this.showChangePlanModal = false;
  }

  handlePlanSelect(event) {
    this.selectedPlanId = event.detail.value;
  }

  async handleSavePlanAssignment() {
    if (!this.selectedPlanId) {
      return;
    }
    this.savingPlan = true;
    try {
      await assignMaintenancePlan({
        assetId: this.recordId,
        planId: this.selectedPlanId
      });

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Success",
          message: "Vehicle maintenance program updated.",
          variant: "success"
        })
      );
      this.handleCloseChangePlanModal();
      await refreshApex(this.wiredGloveboxResult);
    } catch (err) {
      const msg = err.body
        ? err.body.message
        : err.message || "Error updating program";
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Error Updating Program",
          message: msg,
          variant: "error"
        })
      );
    } finally {
      this.savingPlan = false;
    }
  }

  async handleUploadFinished() {
    this.dispatchEvent(
      new ShowToastEvent({
        title: "File Uploaded",
        message: "Document successfully attached to vehicle.",
        variant: "success"
      })
    );
    await refreshApex(this.wiredGloveboxResult);
  }

  handleOpenAddModal() {
    this.newDoc = { ...DEFAULT_DOC };
    this.showAddModal = true;
  }

  handleCloseAddModal() {
    this.showAddModal = false;
    this.newDoc = { ...DEFAULT_DOC };
  }

  handleFormChange(event) {
    const field = event.target.name;
    const value = event.target.value;
    this.newDoc = {
      ...this.newDoc,
      [field]: value
    };
  }

  async handleSaveNewDoc() {
    if (!this.newDoc.docType) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Validation Error",
          message: "Please select a document type.",
          variant: "error"
        })
      );
      return;
    }

    this.savingDoc = true;
    try {
      await createAssetDocument({
        assetId: this.recordId,
        docType: this.newDoc.docType,
        docNumber: this.newDoc.docNumber,
        validFrom: this.newDoc.validFrom || null,
        validUntil: this.newDoc.validUntil || null,
        docLink: this.newDoc.docLink || null
      });

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Success",
          message: `${this.newDoc.docType} uploaded to glovebox.`,
          variant: "success"
        })
      );

      this.handleCloseAddModal();
      await refreshApex(this.wiredGloveboxResult);
    } catch (err) {
      const msg = err.body
        ? err.body.message
        : err.message || "Error saving document";
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Failed to Save Document",
          message: msg,
          variant: "error"
        })
      );
    } finally {
      this.savingDoc = false;
    }
  }
}
