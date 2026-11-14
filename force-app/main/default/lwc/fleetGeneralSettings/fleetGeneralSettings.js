import { LightningElement, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getGeneralSettings from "@salesforce/apex/FleetDisplaySettingsController.getGeneralSettings";
import saveGeneralSettings from "@salesforce/apex/FleetDisplaySettingsController.saveGeneralSettings";

export default class FleetGeneralSettings extends LightningElement {
  loading = true;
  isEditing = false;
  saving = false;
  error;

  serverSettings = {
    enableAiInsights: false,
    aiProvider: null,
    enableExtendedPrivacy: false,
    hasGoogleKey: false,
    hasAnthropicKey: false,
    hasOpenAiKey: false,
    maskedGoogleKey: "",
    maskedAnthropicKey: "",
    maskedOpenAiKey: "",
    canEdit: true,
    aiProviders: []
  };

  draft = {
    enableAiInsights: false,
    aiProvider: "",
    enableExtendedPrivacy: false,
    googleApiKey: "",
    anthropicApiKey: "",
    openAiApiKey: ""
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
      enableAiInsights: !!this.serverSettings.enableAiInsights,
      aiProvider: this.serverSettings.aiProvider || "",
      enableExtendedPrivacy: !!this.serverSettings.enableExtendedPrivacy,
      googleApiKey: "",
      anthropicApiKey: "",
      openAiApiKey: ""
    };
  }

  get isOverview() {
    return !this.isEditing;
  }

  get canEdit() {
    return this.serverSettings && this.serverSettings.canEdit;
  }

  get activeModelLabel() {
    if (
      !this.serverSettings.enableAiInsights ||
      !this.serverSettings.aiProvider
    ) {
      return null;
    }
    const match = (this.serverSettings.aiProviders || []).find(
      (p) => p.value === this.serverSettings.aiProvider
    );
    return match ? match.label : this.serverSettings.aiProvider;
  }

  get googlePlaceholder() {
    return this.serverSettings.hasGoogleKey
      ? `Configured (${this.serverSettings.maskedGoogleKey})`
      : "Paste Google Gemini API Key...";
  }

  get anthropicPlaceholder() {
    return this.serverSettings.hasAnthropicKey
      ? `Configured (${this.serverSettings.maskedAnthropicKey})`
      : "Paste Anthropic API Key (sk-ant-...)...";
  }

  get openAiPlaceholder() {
    return this.serverSettings.hasOpenAiKey
      ? `Configured (${this.serverSettings.maskedOpenAiKey})`
      : "Paste OpenAI API Key (sk-...)...";
  }

  get hasGoogleActive() {
    return (
      (this.draft.googleApiKey && this.draft.googleApiKey.trim().length > 0) ||
      this.serverSettings.hasGoogleKey
    );
  }

  get hasAnthropicActive() {
    return (
      (this.draft.anthropicApiKey &&
        this.draft.anthropicApiKey.trim().length > 0) ||
      this.serverSettings.hasAnthropicKey
    );
  }

  get hasOpenAiActive() {
    return (
      (this.draft.openAiApiKey && this.draft.openAiApiKey.trim().length > 0) ||
      this.serverSettings.hasOpenAiKey
    );
  }

  get availableModelOptions() {
    const list = [];
    if (this.hasGoogleActive) {
      list.push(
        { label: "Google Gemini 2.5 Flash (Fast)", value: "Gemini 2.5 Flash" },
        {
          label: "Google Gemini 2.5 Pro (Deep Analytics)",
          value: "Gemini 2.5 Pro"
        }
      );
    }
    if (this.hasAnthropicActive) {
      list.push(
        { label: "Anthropic Claude 3.5 Sonnet", value: "Claude 3.5 Sonnet" },
        { label: "Anthropic Claude 3.5 Haiku", value: "Claude 3.5 Haiku" }
      );
    }
    if (this.hasOpenAiActive) {
      list.push(
        { label: "OpenAI GPT-4o", value: "GPT-4o" },
        { label: "OpenAI GPT-4o mini", value: "GPT-4o mini" }
      );
    }
    return list;
  }

  get hasNoAvailableModels() {
    return this.availableModelOptions.length === 0;
  }

  get modelSelectorPlaceholder() {
    return this.hasNoAvailableModels
      ? "Enter at least one API key above"
      : "Select an unlocked AI model";
  }

  get modelSelectorGuidance() {
    return this.hasNoAvailableModels
      ? "No models unlocked. Paste an API key for Google, Anthropic, or OpenAI above to activate models."
      : "Select which model executes analytical queries. Models are unlocked based on your configured API keys.";
  }

  get dirty() {
    const aiToggled =
      this.draft.enableAiInsights !== this.serverSettings.enableAiInsights;
    const privacyToggled =
      this.draft.enableExtendedPrivacy !==
      this.serverSettings.enableExtendedPrivacy;
    const modelChanged =
      this.draft.aiProvider !== (this.serverSettings.aiProvider || "");
    const newKeys =
      (this.draft.googleApiKey && this.draft.googleApiKey.trim().length > 0) ||
      (this.draft.anthropicApiKey &&
        this.draft.anthropicApiKey.trim().length > 0) ||
      (this.draft.openAiApiKey && this.draft.openAiApiKey.trim().length > 0);
    return aiToggled || privacyToggled || modelChanged || newKeys;
  }

  get saveDisabled() {
    return !this.dirty || this.saving;
  }

  handleStartEdit() {
    this.resetDraft();
    this.isEditing = true;
    this.error = undefined;
  }

  handleCancelEdit() {
    this.resetDraft();
    this.isEditing = false;
    this.error = undefined;
  }

  handleToggle(event) {
    const { name, checked } = event.target;
    this.draft = { ...this.draft, [name]: checked };
  }

  handleFieldChange(event) {
    const { name, value } = event.target;
    this.draft = { ...this.draft, [name]: value };

    // Auto-select first model if current selection is invalid
    if (
      this.availableModelOptions.length > 0 &&
      !this.availableModelOptions.some((m) => m.value === this.draft.aiProvider)
    ) {
      this.draft.aiProvider = this.availableModelOptions[0].value;
    }
  }

  async handleSave() {
    this.saving = true;
    this.error = undefined;
    try {
      const updated = await saveGeneralSettings({
        enableAiInsights: this.draft.enableAiInsights,
        aiProvider: this.draft.aiProvider,
        enableExtendedPrivacy: this.draft.enableExtendedPrivacy,
        googleApiKey: this.draft.googleApiKey || null,
        anthropicApiKey: this.draft.anthropicApiKey || null,
        openAiApiKey: this.draft.openAiApiKey || null
      });
      this.serverSettings = updated;
      this.resetDraft();
      this.isEditing = false;
      this.dispatchEvent(
        new ShowToastEvent({
          title: "General Settings Saved",
          message: "FleetForce general settings and API keys updated.",
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
}
