import { LightningElement, api, wire, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";
import getGloveboxData from "@salesforce/apex/FleetDigitalGloveboxController.getGloveboxData";
import createAssetDocument from "@salesforce/apex/FleetDigitalGloveboxController.createAssetDocument";

const DEFAULT_DOC = {
  docType: "Registration",
  docNumber: "",
  validFrom: null,
  validUntil: null,
  docLink: ""
};

export default class FleetDigitalGlovebox extends LightningElement {
  @api recordId;

  @track payload;
  @track loading = true;
  @track error;
  @track showAddModal = false;
  @track savingDoc = false;
  @track newDoc = { ...DEFAULT_DOC };

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

  get hasComplianceDocuments() {
    return (
      this.payload &&
      Array.isArray(this.payload.complianceDocuments) &&
      this.payload.complianceDocuments.length > 0
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
