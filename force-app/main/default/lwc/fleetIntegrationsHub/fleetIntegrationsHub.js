import { LightningElement, wire, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";

import getConnectors from "@salesforce/apex/FleetIntegrationsController.getConnectors";
import getConnectorDetails from "@salesforce/apex/FleetIntegrationsController.getConnectorDetails";
import saveConnector from "@salesforce/apex/FleetIntegrationsController.saveConnector";
import testConnection from "@salesforce/apex/FleetIntegrationsController.testConnection";
import triggerSync from "@salesforce/apex/FleetIntegrationsController.triggerSync";

const FREQUENCY_OPTIONS = [
  { label: "Every 15 Minutes (High Priority)", value: 0 },
  { label: "Hourly (Standard Default)", value: 1 },
  { label: "Every 6 Hours", value: 6 },
  { label: "Daily (Batch Mode)", value: 24 }
];

export default class FleetIntegrationsHub extends LightningElement {
  @track connectors = [];
  isLoading = true;
  isActionInProgress = false;
  wiredConnectorsResult;

  // Modal state
  showModal = false;
  activeConnectorKey = "";
  isSavingConfig = false;
  @track modalForm = {};
  pingResult = null;

  frequencyOptions = FREQUENCY_OPTIONS;

  @wire(getConnectors)
  wiredConnectors(result) {
    this.wiredConnectorsResult = result;
    this.isLoading = false;
    if (result.data) {
      this.connectors = result.data.map((c) => ({
        ...c,
        badgeClass: `slds-badge slds-theme_${c.statusVariant || "inverse"}`,
        formattedLastSync: c.lastReceived
          ? new Date(c.lastReceived).toLocaleString()
          : "Never"
      }));
    } else if (result.error) {
      this.showToast(
        "Error Loading Connectors",
        this.extractErrorMessage(result.error),
        "error"
      );
    }
  }

  get hasConnectors() {
    return !this.isLoading && this.connectors && this.connectors.length > 0;
  }

  get totalConnectorsCount() {
    return this.connectors.length;
  }

  get totalStreamsCount() {
    return this.connectors.reduce((acc, c) => acc + (c.totalStreams || 0), 0);
  }

  get healthyStreamsCount() {
    return this.connectors.reduce((acc, c) => acc + (c.healthyStreams || 0), 0);
  }

  get monitoredAssetsCount() {
    return this.connectors.reduce(
      (acc, c) => acc + (c.monitoredAssets || 0),
      0
    );
  }

  get activeModalTitle() {
    const match = this.connectors.find(
      (c) => c.key === this.activeConnectorKey
    );
    return match ? match.name : "Connector";
  }

  get isGeotabModal() {
    return this.activeConnectorKey === "geotab";
  }

  get isSamsaraModal() {
    return this.activeConnectorKey === "samsara";
  }

  get isWebfleetModal() {
    return this.activeConnectorKey === "webfleet";
  }

  get isCustomWebhookModal() {
    return this.activeConnectorKey === "custom";
  }

  get hasPollingFrequency() {
    return this.activeConnectorKey !== "custom";
  }

  get passwordPlaceholder() {
    return this.modalForm && this.modalForm.hasPassword
      ? "•••••••••••• (Leave blank to keep)"
      : "Enter API Password";
  }

  async handleOpenConfig(event) {
    const key = event.target.dataset.key;
    this.activeConnectorKey = key;
    this.pingResult = null;
    this.modalForm = {
      server: "",
      database: "",
      username: "",
      password: "",
      apiKey: "",
      frequencyHours: 1
    };

    try {
      const details = await getConnectorDetails({ connectorKey: key });
      if (details) {
        this.modalForm = {
          server: details.server || "",
          database: details.database || "",
          username: details.username || "",
          password: "",
          apiKey: details.apiKeyMasked || "",
          hasPassword: details.hasPassword,
          webhookUrl: details.webhookUrl || "",
          webhookSecret: details.webhookSecret || "",
          frequencyHours:
            details.frequencyHours != null ? details.frequencyHours : 1
        };
      }
      this.showModal = true;
    } catch (error) {
      this.showToast(
        "Failed to Load Config",
        this.extractErrorMessage(error),
        "error"
      );
    }
  }

  closeModal() {
    if (this.isSavingConfig) return;
    this.showModal = false;
    this.pingResult = null;
  }

  handleFormChange(event) {
    const fieldName = event.target.name;
    const val = event.detail.value;
    this.modalForm = { ...this.modalForm, [fieldName]: val };
  }

  async handleTestPing(event) {
    const key = event.target.dataset.key;
    this.isActionInProgress = true;
    try {
      const res = await testConnection({ connectorKey: key });
      this.showToast(
        "Connection Test Passed",
        `${res.provider}: ${res.message} (${res.latencyMs} ms)`,
        "success"
      );
    } catch (error) {
      this.showToast(
        "Connection Test Failed",
        this.extractErrorMessage(error),
        "error"
      );
    } finally {
      this.isActionInProgress = false;
    }
  }

  async handleModalTestPing() {
    try {
      const res = await testConnection({
        connectorKey: this.activeConnectorKey
      });
      this.pingResult = res;
    } catch (error) {
      this.showToast(
        "Connection Test Failed",
        this.extractErrorMessage(error),
        "error"
      );
    }
  }

  async handleSyncNow(event) {
    const key = event.target.dataset.key;
    this.isActionInProgress = true;
    try {
      const msg = await triggerSync({ connectorKey: key });
      this.showToast("Sync Triggered", msg, "success");
      await refreshApex(this.wiredConnectorsResult);
    } catch (error) {
      this.showToast("Sync Failed", this.extractErrorMessage(error), "error");
    } finally {
      this.isActionInProgress = false;
    }
  }

  async handleSaveConfig() {
    this.isSavingConfig = true;
    try {
      await saveConnector({
        connectorKey: this.activeConnectorKey,
        server: this.modalForm.server,
        database: this.modalForm.database,
        username: this.modalForm.username,
        password: this.modalForm.password,
        apiKey: this.modalForm.apiKey,
        frequencyHours:
          this.modalForm.frequencyHours != null
            ? Number(this.modalForm.frequencyHours)
            : 1
      });

      this.showToast(
        "Configuration Saved",
        `${this.activeModalTitle} settings have been saved and enqueued.`,
        "success"
      );
      this.closeModal();
      await refreshApex(this.wiredConnectorsResult);
    } catch (error) {
      this.showToast("Save Error", this.extractErrorMessage(error), "error");
    } finally {
      this.isSavingConfig = false;
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  extractErrorMessage(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    if (error && error.message) {
      return error.message;
    }
    return "An unexpected error occurred.";
  }
}
