import { LightningElement, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { NavigationMixin } from "lightning/navigation";
import getGeneralSettings from "@salesforce/apex/FleetDisplaySettingsController.getGeneralSettings";
import saveGeneralSettings from "@salesforce/apex/FleetDisplaySettingsController.saveGeneralSettings";

export default class FleetGeneralSettings extends NavigationMixin(
  LightningElement
) {
  loading = true;
  saving = false;
  error;

  serverSettings = {
    enableAiInsights: true,
    aiProvider: "Gemini 2.5 Flash",
    enableExtendedPrivacy: false,
    canEdit: true,
    aiProviders: []
  };

  draft = {
    enableAiInsights: true,
    aiProvider: "Gemini 2.5 Flash",
    enableExtendedPrivacy: false
  };

  @wire(getGeneralSettings)
  wiredSettings({ data, error }) {
    this.loading = false;
    if (data) {
      this.serverSettings = data;
      this.draft = {
        enableAiInsights: !!data.enableAiInsights,
        aiProvider: data.aiProvider || "Gemini 2.5 Flash",
        enableExtendedPrivacy: !!data.enableExtendedPrivacy
      };
      this.error = undefined;
    } else if (error) {
      this.error =
        (error && error.body && error.body.message) ||
        "Could not load general settings.";
    }
  }

  get aiProviders() {
    return this.serverSettings.aiProviders || [];
  }

  get isReadOnly() {
    return !this.serverSettings.canEdit || this.saving;
  }

  get dirty() {
    return (
      this.draft.enableAiInsights !== this.serverSettings.enableAiInsights ||
      this.draft.aiProvider !== this.serverSettings.aiProvider ||
      this.draft.enableExtendedPrivacy !==
        this.serverSettings.enableExtendedPrivacy
    );
  }

  get saveDisabled() {
    return !this.dirty || this.saving || !this.serverSettings.canEdit;
  }

  handleToggle(event) {
    const { name, checked } = event.target;
    this.draft = { ...this.draft, [name]: checked };
  }

  handleFieldChange(event) {
    const { name, value } = event.target;
    this.draft = { ...this.draft, [name]: value };
  }

  handleCancel() {
    this.draft = {
      enableAiInsights: !!this.serverSettings.enableAiInsights,
      aiProvider: this.serverSettings.aiProvider || "Gemini 2.5 Flash",
      enableExtendedPrivacy: !!this.serverSettings.enableExtendedPrivacy
    };
    this.error = undefined;
  }

  async handleSave() {
    this.saving = true;
    this.error = undefined;
    try {
      const updated = await saveGeneralSettings({
        enableAiInsights: this.draft.enableAiInsights,
        aiProvider: this.draft.aiProvider,
        enableExtendedPrivacy: this.draft.enableExtendedPrivacy
      });
      this.serverSettings = updated;
      this.draft = {
        enableAiInsights: !!updated.enableAiInsights,
        aiProvider: updated.aiProvider,
        enableExtendedPrivacy: !!updated.enableExtendedPrivacy
      };
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Settings Saved",
          message: "FleetForce general settings have been updated.",
          variant: "success"
        })
      );
    } catch (e) {
      this.error =
        (e && e.body && e.body.message) || "Unable to save general settings.";
    } finally {
      this.saving = false;
    }
  }

  navigateToAutoNaming() {
    this[NavigationMixin.Navigate]({
      type: "standard__navItemPage",
      attributes: {
        apiName: "Fleetforce_Auto_Naming"
      }
    });
  }
}
