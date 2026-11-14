import { LightningElement, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getSupportedObjects from "@salesforce/apex/AutoNamingAdminController.getSupportedObjects";
import getObjectFields from "@salesforce/apex/AutoNamingAdminController.getObjectFields";
import previewPattern from "@salesforce/apex/AutoNamingAdminController.previewPattern";
import saveRule from "@salesforce/apex/AutoNamingAdminController.saveRule";
import runRecalculateBatch from "@salesforce/apex/AutoNamingAdminController.runRecalculateBatch";
import getBatchJobStatus from "@salesforce/apex/AutoNamingAdminController.getBatchJobStatus";

export default class FleetAutoNamingAdmin extends LightningElement {
  @track objects = [];
  @track selectedObject = "Fleet_Asset__c";
  @track availableFields = [];
  @track isLoading = true;
  @track isEditMode = false;
  @track isSaving = false;

  // Draft editing state
  @track draftPattern = "";
  @track draftIsActive = true;
  @track draftAllowOverride = false;
  @track livePreview = "";

  // Batch modal state
  @track isBatchModalOpen = false;
  @track isBatchRunning = false;
  @track batchJobId = null;
  @track batchStatus = "";
  batchPollInterval = null;
  previewDebounceTimeout = null;

  connectedCallback() {
    this.loadObjects();
  }

  disconnectedCallback() {
    if (this.batchPollInterval) {
      clearInterval(this.batchPollInterval);
    }
  }

  async loadObjects() {
    this.isLoading = true;
    try {
      const data = await getSupportedObjects();
      this.objects = data;
      if (this.objects.length > 0) {
        const found = this.objects.find(
          (o) => o.apiName === this.selectedObject
        );
        if (!found) {
          this.selectedObject = this.objects[0].apiName;
        }
        this.syncViewModeState();
      }
    } catch (error) {
      this.showToast(
        "Error",
        error?.body?.message || "Failed to load rules",
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  syncViewModeState() {
    const config = this.selectedObjectConfig;
    if (config) {
      this.draftPattern = config.currentPattern || "";
      this.draftIsActive = config.isActive;
      this.draftAllowOverride = config.allowManualOverride;
      this.triggerLivePreview(config.currentPattern);
    }
  }

  get isViewMode() {
    return !this.isEditMode;
  }

  get objectTabs() {
    return this.objects.map((obj) => ({
      ...obj,
      cssClass: `object-tab ${obj.apiName === this.selectedObject ? "active" : ""}`
    }));
  }

  get selectedObjectConfig() {
    return this.objects.find((o) => o.apiName === this.selectedObject);
  }

  get overrideBadgeText() {
    return this.selectedObjectConfig?.allowManualOverride
      ? "Manual Override Allowed"
      : "Enforced on All Records";
  }

  get patternForRecalculation() {
    return this.isEditMode
      ? this.draftPattern
      : this.selectedObjectConfig?.currentPattern || "";
  }

  get charCount() {
    return this.livePreview ? this.livePreview.length : 0;
  }

  get charCountClass() {
    const count = this.charCount;
    if (count > 80) return "char-counter danger";
    if (count > 65) return "char-counter warning";
    return "char-counter safe";
  }

  handleSelectObject(event) {
    const objName = event.currentTarget.dataset.object;
    if (objName && objName !== this.selectedObject) {
      this.selectedObject = objName;
      this.isEditMode = false;
      this.syncViewModeState();
    }
  }

  async handleEnterEditMode() {
    this.isEditMode = true;
    const config = this.selectedObjectConfig;
    if (config) {
      this.draftPattern = config.currentPattern || "";
      this.draftIsActive = config.isActive;
      this.draftAllowOverride = config.allowManualOverride;
    }
    await this.loadFields();
    this.triggerLivePreview(this.draftPattern);
  }

  handleCancelEdit() {
    this.isEditMode = false;
    this.syncViewModeState();
  }

  async loadFields() {
    try {
      const fields = await getObjectFields({
        objectApiName: this.selectedObject
      });
      this.availableFields = fields;
    } catch {
      this.availableFields = [];
    }
  }

  handlePatternInput(event) {
    this.draftPattern = event.target.value;
    this.triggerLivePreview(this.draftPattern);
  }

  handleInsertToken(event) {
    const token = event.currentTarget.dataset.token;
    if (!token) return;

    if (!this.draftPattern) {
      this.draftPattern = token;
    } else {
      this.draftPattern += ` ${token}`;
    }
    this.triggerLivePreview(this.draftPattern);
  }

  handleToggleActive(event) {
    this.draftIsActive = event.target.checked;
  }

  handleToggleOverride(event) {
    this.draftAllowOverride = event.target.checked;
  }

  handleRevertToDefault() {
    const defaults = {
      Fleet_Asset__c:
        "{Model_Year__c} {Make__c} {Model__c} · {License_Plate__c}",
      Citation__c: "{Ticket_Number__c} · {Violation_Type__c}",
      Reservation__c: "{Preferred_Body__c} ({Status__c})",
      Driver_Qualification__c: "{Type__c} ({Status__c})"
    };
    this.draftPattern = defaults[this.selectedObject] || "{Name}";
    this.triggerLivePreview(this.draftPattern);
    this.showToast("Reset", "Pattern reverted to default convention", "info");
  }

  triggerLivePreview(patternString) {
    if (this.previewDebounceTimeout) {
      clearTimeout(this.previewDebounceTimeout);
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.previewDebounceTimeout = setTimeout(async () => {
      try {
        const res = await previewPattern({
          objectApiName: this.selectedObject,
          pattern: patternString
        });
        this.livePreview = res || "(Empty Result)";
      } catch {
        this.livePreview = "(Preview unavailable)";
      }
    }, 150);
  }

  async handleSaveOnly() {
    this.isSaving = true;
    try {
      await saveRule({
        objectApiName: this.selectedObject,
        pattern: this.draftPattern,
        isActive: this.draftIsActive,
        allowManualOverride: this.draftAllowOverride,
        description: `Custom naming rule for ${this.selectedObject}`
      });

      // Update in-memory state
      const config = this.selectedObjectConfig;
      if (config) {
        config.currentPattern = this.draftPattern;
        config.isActive = this.draftIsActive;
        config.allowManualOverride = this.draftAllowOverride;
      }

      this.isEditMode = false;
      this.showToast(
        "Success",
        "Rule saved! Will apply to new and updated records.",
        "success"
      );
    } catch (error) {
      this.showToast(
        "Error Saving Rule",
        error?.body?.message || "Failed to save rule",
        "error"
      );
    } finally {
      this.isSaving = false;
    }
  }

  async handleSaveAndRecalculate() {
    this.isSaving = true;
    try {
      await saveRule({
        objectApiName: this.selectedObject,
        pattern: this.draftPattern,
        isActive: this.draftIsActive,
        allowManualOverride: this.draftAllowOverride,
        description: `Custom naming rule for ${this.selectedObject}`
      });

      const config = this.selectedObjectConfig;
      if (config) {
        config.currentPattern = this.draftPattern;
        config.isActive = this.draftIsActive;
        config.allowManualOverride = this.draftAllowOverride;
      }

      this.isSaving = false;
      this.isEditMode = false;
      this.showToast(
        "Rule Saved",
        "Formula saved. Starting recalculation across existing records...",
        "info"
      );

      // Open batch recalculation modal
      this.handleOpenBatchModal();
      this.handleStartBatch();
    } catch (error) {
      this.isSaving = false;
      this.showToast(
        "Error Saving Rule",
        error?.body?.message || "Failed to save rule",
        "error"
      );
    }
  }

  handleOpenBatchModal() {
    this.isBatchModalOpen = true;
    this.isBatchRunning = false;
  }

  handleCloseBatchModal() {
    if (this.isBatchRunning) return;
    this.isBatchModalOpen = false;
  }

  async handleStartBatch() {
    this.isBatchRunning = true;
    this.batchStatus = "Queued";

    try {
      const patternToUse = this.patternForRecalculation;
      const jobId = await runRecalculateBatch({
        objectApiName: this.selectedObject,
        pattern: patternToUse
      });
      this.batchJobId = jobId;
      this.pollBatchStatus();
    } catch (error) {
      this.isBatchRunning = false;
      this.showToast(
        "Error",
        error?.body?.message || "Failed to start batch recalculation",
        "error"
      );
    }
  }

  pollBatchStatus() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.batchPollInterval = setInterval(async () => {
      try {
        const statusDto = await getBatchJobStatus({ jobId: this.batchJobId });
        this.batchStatus = `${statusDto.status} (${statusDto.jobItemsProcessed} / ${statusDto.totalJobItems} batches)`;

        if (statusDto.isCompleted) {
          clearInterval(this.batchPollInterval);
          this.isBatchRunning = false;
          this.isBatchModalOpen = false;

          this.showToast(
            "Success",
            `Recalculation complete! All ${this.selectedObjectConfig?.label} records updated.`,
            "success"
          );
          this.loadObjects();
        }
      } catch {
        clearInterval(this.batchPollInterval);
        this.isBatchRunning = false;
        this.isBatchModalOpen = false;
      }
    }, 1500);
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
