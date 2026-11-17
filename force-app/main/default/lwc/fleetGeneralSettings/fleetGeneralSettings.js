import { LightningElement, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getGeneralSettings from "@salesforce/apex/FleetDisplaySettingsController.getGeneralSettings";
import saveGeneralSettings from "@salesforce/apex/FleetDisplaySettingsController.saveGeneralSettings";
import saveDriverAppSettings from "@salesforce/apex/FleetDisplaySettingsController.saveDriverAppSettings";

export default class FleetGeneralSettings extends LightningElement {
  loading = true;
  saving = false;
  activeEditSection = null; // null | 'ai' | 'privacy' | 'maintenance' | 'governance'
  error;

  serverSettings = {
    enableAiInsights: true,
    aiProvider: "Google Gemini",
    enableExtendedPrivacy: false,
    autoCreateDtcTickets: true,
    maintenanceGraceDays: 14,
    odometerDriftThreshold: 5,
    telemetryRetentionDays: 90,
    hasGoogleKey: false,
    hasAnthropicKey: false,
    hasOpenAiKey: false,
    maskedGoogleKey: "",
    maskedAnthropicKey: "",
    maskedOpenAiKey: "",
    allowAdminModeInDriverApp: true,
    canEdit: true,
    aiProviders: []
  };

  draft = {
    enableAiInsights: true,
    aiProvider: "Google Gemini",
    enableExtendedPrivacy: false,
    autoCreateDtcTickets: true,
    maintenanceGraceDays: 14,
    odometerDriftThreshold: 5,
    telemetryRetentionDays: 90,
    googleApiKey: "",
    anthropicApiKey: "",
    openAiApiKey: "",
    allowAdminModeInDriverApp: true
  };

  @wire(getGeneralSettings)
  wiredSettings({ data, error }) {
    this.loading = false;
    if (data) {
      this.serverSettings = data;
      this.resetDraft();
      this.error = undefined;
    } else if (error) {
      this.error =
        (error && error.body && error.body.message) ||
        "Could not load general settings.";
    }
  }

  resetDraft() {
    this.draft = {
      enableAiInsights: this.serverSettings.enableAiInsights !== false,
      aiProvider: this.serverSettings.aiProvider || "Google Gemini",
      enableExtendedPrivacy: !!this.serverSettings.enableExtendedPrivacy,
      autoCreateDtcTickets: this.serverSettings.autoCreateDtcTickets !== false,
      maintenanceGraceDays: this.serverSettings.maintenanceGraceDays || 14,
      odometerDriftThreshold: this.serverSettings.odometerDriftThreshold || 5,
      telemetryRetentionDays: this.serverSettings.telemetryRetentionDays || 90,
      googleApiKey: "",
      anthropicApiKey: "",
      openAiApiKey: "",
      allowAdminModeInDriverApp:
        this.serverSettings.allowAdminModeInDriverApp !== false
    };
  }

  get canEdit() {
    return this.serverSettings && this.serverSettings.canEdit;
  }

  // Section 1: AI
  get isAiOverview() {
    return this.activeEditSection !== "ai";
  }
  get isAiEditing() {
    return this.activeEditSection === "ai";
  }

  // Section 2: Privacy
  get isPrivacyOverview() {
    return this.activeEditSection !== "privacy";
  }
  get isPrivacyEditing() {
    return this.activeEditSection === "privacy";
  }

  // Section 3: Maintenance
  get isMaintenanceOverview() {
    return this.activeEditSection !== "maintenance";
  }
  get isMaintenanceEditing() {
    return this.activeEditSection === "maintenance";
  }

  // Section 4: Governance
  get isGovernanceOverview() {
    return this.activeEditSection !== "governance";
  }
  get isGovernanceEditing() {
    return this.activeEditSection === "governance";
  }

  // Section 5: Driver App
  get isDriverAppOverview() {
    return this.activeEditSection !== "driverApp";
  }
  get isDriverAppEditing() {
    return this.activeEditSection === "driverApp";
  }
  handleEditDriverApp() {
    this.activeEditSection = "driverApp";
  }

  get configuredKeysCount() {
    let count = 0;
    if (this.serverSettings.hasGoogleKey) count++;
    if (this.serverSettings.hasAnthropicKey) count++;
    if (this.serverSettings.hasOpenAiKey) count++;
    return count;
  }

  get aiVaultBadgeText() {
    const count = this.configuredKeysCount;
    if (count === 3) return "All 3 Providers Configured";
    if (count > 0) return `${count} of 3 Providers Configured`;
    return "No Keys Configured";
  }

  get aiVaultBadgeClass() {
    const count = this.configuredKeysCount;
    if (count === 3) return "slds-badge slds-theme_success slds-m-right_small";
    if (count > 0) return "slds-badge slds-theme_info slds-m-right_small";
    return "slds-badge slds-badge_lightest slds-m-right_small";
  }

  get googlePlaceholder() {
    return this.serverSettings.hasGoogleKey
      ? `Configured (${this.serverSettings.maskedGoogleKey})`
      : "Paste Google Gemini API Key...";
  }

  get anthropicPlaceholder() {
    return this.serverSettings.hasAnthropicKey
      ? `Configured (${this.serverSettings.maskedAnthropicKey})`
      : "Paste Anthropic Claude API Key (sk-ant-...)...";
  }

  get openAiPlaceholder() {
    return this.serverSettings.hasOpenAiKey
      ? `Configured (${this.serverSettings.maskedOpenAiKey})`
      : "Paste OpenAI API Key (sk-...)...";
  }

  handleEditAi() {
    this.resetDraft();
    this.activeEditSection = "ai";
    this.error = undefined;
  }

  handleEditPrivacy() {
    this.resetDraft();
    this.activeEditSection = "privacy";
    this.error = undefined;
  }

  handleEditMaintenance() {
    this.resetDraft();
    this.activeEditSection = "maintenance";
    this.error = undefined;
  }

  handleEditGovernance() {
    this.resetDraft();
    this.activeEditSection = "governance";
    this.error = undefined;
  }

  handleCancelEdit() {
    this.resetDraft();
    this.activeEditSection = null;
    this.error = undefined;
  }

  handleToggle(event) {
    const { name, checked } = event.target;
    this.draft = { ...this.draft, [name]: checked };
  }

  handleFieldChange(event) {
    const { name, value } = event.target;
    this.draft = { ...this.draft, [name]: value };
  }

  async handleSaveAi() {
    await this.saveCurrentDraft("AI Foundation Keys Vault updated.");
  }

  async handleSavePrivacy() {
    await this.saveCurrentDraft("Digital Data Sanitization Protocol updated.");
  }

  async handleSaveMaintenance() {
    await this.saveCurrentDraft(
      "Maintenance & Work Order Automation rules saved."
    );
  }

  async handleSaveGovernance() {
    await this.saveCurrentDraft("Telemetry Drift & Governance settings saved.");
  }

  async handleSaveDriverApp() {
    this.saving = true;
    this.error = undefined;
    try {
      const updated = await saveDriverAppSettings({
        allowAdminModeInDriverApp: this.draft.allowAdminModeInDriverApp === true
      });
      this.serverSettings = updated;
      this.resetDraft();
      this.activeEditSection = null;
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Settings Saved",
          message: "Driver App settings updated successfully.",
          variant: "success"
        })
      );
    } catch (e) {
      this.error =
        (e && e.body && e.body.message) ||
        "Unable to save Driver App settings.";
    } finally {
      this.saving = false;
    }
  }

  async saveCurrentDraft(successMsg) {
    this.saving = true;
    this.error = undefined;
    try {
      const updated = await saveGeneralSettings({
        enableAiInsights: this.draft.enableAiInsights,
        aiProvider: this.draft.aiProvider,
        enableExtendedPrivacy: this.draft.enableExtendedPrivacy,
        googleApiKey: this.draft.googleApiKey || null,
        anthropicApiKey: this.draft.anthropicApiKey || null,
        openAiApiKey: this.draft.openAiApiKey || null,
        autoCreateDtcTickets: this.draft.autoCreateDtcTickets,
        maintenanceGraceDays: this.draft.maintenanceGraceDays,
        odometerDriftThreshold: this.draft.odometerDriftThreshold,
        telemetryRetentionDays: this.draft.telemetryRetentionDays
      });
      this.serverSettings = updated;
      this.resetDraft();
      this.activeEditSection = null;
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Settings Saved",
          message: successMsg,
          variant: "success"
        })
      );
    } catch (e) {
      this.error =
        (e && e.body && e.body.message) || "Unable to save settings.";
    } finally {
      this.saving = false;
    }
  }
}
