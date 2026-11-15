import { LightningElement, wire, track } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

import getAiConfig from "@salesforce/apex/FleetAiInsightsController.getAiConfig";
import getPrebuiltInsights from "@salesforce/apex/FleetAiInsightsController.getPrebuiltInsights";
import queryStrategicInsight from "@salesforce/apex/FleetAiInsightsController.queryStrategicInsight";
import executeStrategicAction from "@salesforce/apex/FleetAiInsightsController.executeStrategicAction";
import setActiveAiModel from "@salesforce/apex/FleetAiInsightsController.setActiveAiModel";

export default class FleetAiInsights extends NavigationMixin(LightningElement) {
  @track aiConfig;
  @track prebuiltInsights = [];
  @track customQueryResult;

  searchPrompt = "";
  isQuerying = false;
  isLoading = true;
  isSwitchingModel = false;

  @wire(getAiConfig)
  wiredAiConfig({ data, error }) {
    if (data) {
      this.aiConfig = data;
    } else if (error) {
      this.showToast("Config Error", this.extractErrorMessage(error), "error");
    }
  }

  @wire(getPrebuiltInsights)
  wiredPrebuilt({ data, error }) {
    this.isLoading = false;
    if (data) {
      this.prebuiltInsights = data.map((item) => ({
        ...item,
        badgeClass: `slds-badge slds-theme_${item.severityVariant || "inverse"}`
      }));
    } else if (error) {
      this.showToast(
        "Failed to Load Insights",
        this.extractErrorMessage(error),
        "error"
      );
    }
  }

  get modelDisplayName() {
    if (!this.aiConfig) return "Detecting Model...";
    return this.aiConfig.modelName || "Google Gemini 2.5 Pro";
  }

  get hasKey() {
    return this.aiConfig && this.aiConfig.hasKey;
  }

  get activeModelValue() {
    return this.aiConfig ? this.aiConfig.provider : "Google Gemini";
  }

  get modelOptions() {
    if (!this.aiConfig || !this.aiConfig.availableModels) {
      return [
        {
          label: "Google Gemini 2.5 Pro (Deep Reasoning)",
          value: "Google Gemini"
        },
        { label: "Anthropic Claude 3.5 Sonnet", value: "Anthropic Claude" },
        { label: "OpenAI GPT-4o Enterprise", value: "OpenAI" }
      ];
    }
    return this.aiConfig.availableModels.map((m) => ({
      label: m.isConfigured
        ? `${m.label} (Ready)`
        : `${m.label} (Key Required)`,
      value: m.value
    }));
  }

  async handleModelChange(event) {
    const selectedProvider = event.detail.value;
    this.isSwitchingModel = true;
    try {
      const updatedConfig = await setActiveAiModel({
        provider: selectedProvider
      });
      this.aiConfig = updatedConfig;
      this.showToast(
        "AI Engine Switched",
        `Active foundation model set to ${updatedConfig.modelName}`,
        "success"
      );
    } catch (error) {
      this.showToast(
        "Model Switch Failed",
        this.extractErrorMessage(error),
        "error"
      );
    } finally {
      this.isSwitchingModel = false;
    }
  }

  get prebuiltInsightsCount() {
    return this.prebuiltInsights.length;
  }

  handlePromptChange(event) {
    this.searchPrompt = event.target.value;
  }

  handleKeyDown(event) {
    if (event.key === "Enter") {
      this.handleExecuteQuery();
    }
  }

  handleQuickPrompt(event) {
    this.searchPrompt = event.target.dataset.prompt;
    this.handleExecuteQuery();
  }

  async handleExecuteQuery() {
    if (!this.searchPrompt || !this.searchPrompt.trim()) {
      this.showToast(
        "Empty Prompt",
        "Please enter a strategic query to analyze.",
        "warning"
      );
      return;
    }

    this.isQuerying = true;
    this.customQueryResult = null;

    try {
      const res = await queryStrategicInsight({ prompt: this.searchPrompt });
      this.customQueryResult = res;
    } catch (error) {
      this.showToast("Query Error", this.extractErrorMessage(error), "error");
    } finally {
      this.isQuerying = false;
    }
  }

  async handleExecuteAction(event) {
    const actionKey = event.target.dataset.action;
    const insightId = event.target.dataset.insight;

    try {
      const msg = await executeStrategicAction({ actionKey, insightId });
      this.showToast("Strategic Action Executed", msg, "success");
    } catch (error) {
      this.showToast("Action Failed", this.extractErrorMessage(error), "error");
    }
  }

  handleNavigateGeneral() {
    const isNamespaced = window.location.pathname.includes("fleetforce__");
    const apiName = isNamespaced
      ? "fleetforce__Fleetforce_General_Settings"
      : "Fleetforce_General_Settings";
    this[NavigationMixin.Navigate]({
      type: "standard__navItemPage",
      attributes: {
        apiName
      }
    });
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
